# ==============================================================================
# Script: port_buffers_early.tcl
# Path  : <RUN_DIR>/pnr_v2/port_buffers_early.tcl   ;# 085: new script (flow step 4c, after placement.tcl and before cts.tcl)
# Stage : Predict the input-port antenna failures from the placement and buffer exactly those nets BEFORE clock-tree synthesis and routing
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 085: THIS SCRIPT CHANGES THE NETLIST (an ECO on the placed block): it inserts one buffer between an input port and its loads for every input-port net whose predicted
# 085: pin-to-load wire would fail the Calibre antenna rule. The PM must be told, as for antenna_port_buffers.tcl: the macro netlist differs from the synthesis netlist.
# 085: why. An input port net has no driver and no diffusion inside the macro, so Calibre counts the whole pin-to-gate wire against a gate area of about 0.19 um^2 (AN.MTL.1.*:
# 085: 2 x (length + width) x layer weight / gate area <= 400). Run 1 (2026-11-09): 16 nets failed AFTER the route (pin-to-gate wires of 130 to 478 um against a limit of
# 085: about 72 um on M2/M3 and 46 um on TOP_M); antenna_port_buffers.tcl repaired them after the route (five extra ECO steps, a changed netlist after the sign-off checks began, and a
# 085: late timing break). `adiode` is dont_use (no diode), so a buffer next to the pin is the only repair. This script does it up front, with the numbers known before the router runs.
# 085: what it does, in order (every decision is printed with `>>> 085`):
# 085:   1 open the placed block (read-only until step 8), choose the buffer cell from DATA (the rules of antenna_port_buffers.tcl: input gate area, output diffusion, don't-use list)
# 085:   2 for every INPUT port except the clock: pin position, loads (leaf pins), pin-to-load distances (Manhattan, from the placement), predicted antenna ratio (M2/M3 weight and TOP_M weight);
# 085:     decision BUFFER when the predicted ratio exceeds PREDICT_MARGIN x the limit; the whole table is printed and written to a CSV (for the calibration after the route)
# 085:   3 PLAN_ONLY 1 stops here (nothing is changed): the user sees the count before anything is inserted. PLAN_ONLY, PREDICT_MARGIN and PREDICT_WEIGHT can be set from the
# 085:     environment (UNPU_PBE_PLAN_ONLY, UNPU_PBE_PREDICT_MARGIN, UNPU_PBE_PREDICT_WEIGHT) so the clone stays unedited; invalid values are ERROR 085
# 085:   4 the clock port is NOT buffered: its pin-to-first-load distance and the predicted ratio with the CTS root cell's gate area are printed (CTS sets the root; a separate decision)
# 085:   5 the input-to-output cone (the zero-margin paddr -> prdata read path): every BUFFER net that lies on it is listed with its slack before and after; the in2out WNS and
# 085:     the setup WNS must not drop by more than GATE_TOL_IN2OUT, otherwise the script stops BEFORE saving and lists the nets
# 085:   6 free sites are computed from the row boxes and the cell boxes (there are NO fillers yet); each buffer is put on a free site within MAX_PIN_BUF_DIST of the pin with
# 085:     set_cell_location (NOT legalize_placement: it moved cells far away in run 1), the final location is verified, a bad candidate is removed and the next one tried
# 085:   7 the new cells are protected from the later optimisers (dont_touch and a fixed placement status, read back)
# 085:   8 hard checks (nothing is saved when one fails), metrics before/after (reported, not tuned), save as a NEW block ${DESIGN_NAME}_portbuf (the chain _placement -> _portbuf -> _cts)
# 085: every command or option not shown in a usage text in ~/server_pull/rpt/help is marked VERIFY. No timing option, uncertainty, goal, limit or app option is changed. No diode.

set DESIGN_NAME "unpu_top"
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set RPT_DIR     "${PNR_DIR}/reports"
set SCRIPT_DIR  "${RUN_ROOT}/pnr_v2"   ;# 085: where antenna_port_buffers.tcl is: its formula, constants and procs are read from its text, not copied
set STD_LEF     "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"   ;# 085: kit LEF with ANTENNAGATEAREA / ANTENNADIFFAREA (as antenna_port_buffers.tcl)
set STD_LIB     "scl180_std"

# ---- parameters of THIS script ----
set IN_BLOCK        "${DESIGN_NAME}_placement"   ;# 085: the placed block (placement.tcl)
set OUT_BLOCK       "${DESIGN_NAME}_portbuf"     ;# 085: the new block; cts.tcl opens it through its parameter CTS_INPUT_BLOCK
set PLAN_ONLY       0      ;# 085: 1 = print the prediction table and stop; nothing is inserted or saved (use it first to see the buffer count)
set PREDICT_MARGIN  0.8    ;# 085: BUFFER when the predicted ratio exceeds this fraction of ANT_RATIO_LIMIT. Reason: the routed wire is longer than the Manhattan estimate (detours, layer changes); run 1's
                           ;# 085: observed route / estimate ratio could not be recovered from the repo (no placement of run 1 is stored), so the first run prints the estimates to the CSV and the
                           ;# 085: Calibre antenna database after the route calibrates this number. 0.8 is a stated assumption, not a measurement.
set PREDICT_WEIGHT  "m23"  ;# 085: which weight decides: m23 (ANT_WEIGHT_PINWIRE 0.54: the pins sit on M2/M3 and the router uses them for the pin wire) or top (ANT_WEIGHT_TOPM 0.84, the most conservative). Both ratios are always printed.
set GATE_TOL_IN2OUT 0.005  ;# 085: ns; the in2out WNS (ss) after the buffers may be at most this much below the value before (same value and reason as GATE_TOL_SETUP in pt_eco_apply.tcl: a few ps are estimation noise)
set GATE_TOL_SETUP  0.005  ;# 085: ns; the same for the worst setup slack of the whole design in the setup scenario
set EARLY_PREFIX    "earlybuf"   ;# 085: instance name base. It must NOT be antbuf: antenna_port_buffers.tcl counts the cells named antbuf_* against its own targets (hard check) and pt_eco_apply.tcl protects antbuf_* cells
set CLOCK_PORT_NAMES {clk}   ;# 085: used only if the clock source ports cannot be read from the clock objects
set SETUP_SCEN      "func_ss"   ;# 085: scenario names of cts.tcl / route.tcl
set HOLD_SCEN       "func_ff"
set CTS_ROOT_GATE   0.0    ;# 085: gate area (um^2) of the CTS root cell for the clock-port line; 0.0 = read it from the LEF cell named in CTS_ROOT_CELL
set CTS_ROOT_CELL   "inv0d4"   ;# 085: run 1's root cell (task 071). Only used for the printed clock-port estimate
set ROW_TOL_UM      0.001
set PROTECT_PHYS    "fixed"   ;# 085: placement status given to the new cells (VERIFY the attribute physical_status and its values)

# ---- the formula, constants and procs of antenna_port_buffers.tcl (read from its text; nothing is retyped) ----
set ab_path ${SCRIPT_DIR}/antenna_port_buffers.tcl
if {![file exists $ab_path]} { error "ERROR 085: $ab_path not found (the formula and constants are read from it)" }
set fp [open $ab_path r]; set ab_src [read $fp]; close $fp
set ab_b [string first "# ---- BEGIN PURE TCL 068 ----" $ab_src]
set ab_e [string first "# ---- END PURE TCL 068 ----" $ab_src]
if {$ab_b < 0 || $ab_e < 0 || $ab_e <= $ab_b} { error "ERROR 085: markers BEGIN/END PURE TCL 068 not found in $ab_path" }
eval [string range $ab_src $ab_b $ab_e]

# ---- BEGIN PURE TCL 085 ----
# (plain Tcl, no tool command: tested in pnr_v2/test_port_buffers_early.tcl; it uses ant_* procs of block 068 and ant_ratio / ant_max_dist_for_ratio)

# pbe085_param <script text> <NAME> -> the value of the line `set NAME <value>` (quoted, braced or bare), error when it is not there
proc pbe085_param {text name} {
    foreach l [split $text "\n"] {
        if {[regexp "^set\\s+$name\\s+(\"\[^\"\]*\"|\\x7b\[^\\x7d\]*\\x7d|\[^\\s;\]+)" $l -> v]} {   ;# braces written as \x7b / \x7d: an escaped brace in a braced proc body would unbalance it
            if {[string index $v 0] eq "\"" || [string index $v 0] eq "\{"} { set v [string range $v 1 end-1] }
            return $v
        }
    }
    error "pbe085_param: no line 'set $name <value>' in the text"
}

# pbe085_env_resolve <name> <default> <kind> <env value or NONE> <env var name> -> {value source}
# kind: flag (0 or 1) | margin (a number, 0 < x <= 10) | word:<a|b|...> (one of the listed words). The environment value replaces the default only when the variable is set;
# a set but invalid value (empty, wrong type, out of range) is an error, never a silent fallback to the default.
proc pbe085_env_resolve {name default kind envval envname} {
    if {$envval eq "NONE"} { return [list $default "default"] }
    set src "environment $envname"
    switch -glob -- $kind {
        flag {
            if {$envval ne "0" && $envval ne "1"} { error "ERROR 085: $envname='$envval' is not valid for $name: it must be 0 or 1" }
        }
        margin {
            if {$envval eq "" || [catch {expr {double($envval)}}] || ![string is double -strict $envval] || $envval <= 0 || $envval > 10} {
                error "ERROR 085: $envname='$envval' is not valid for $name: it must be a number above 0 and at most 10"
            }
        }
        word:* {
            set allowed [split [string range $kind 5 end] "|"]
            if {[lsearch -exact $allowed $envval] < 0} { error "ERROR 085: $envname='$envval' is not valid for $name: it must be one of [join $allowed {, }]" }
        }
        default { error "pbe085_env_resolve: unknown kind '$kind'" }
    }
    return [list $envval $src]
}

# pbe085_mst <points {{x y} ...}> -> total Manhattan length of the minimum spanning tree (Prim). A rectilinear Steiner tree is at least 2/3 of it; it is printed as information only.
proc pbe085_mst {pts} {
    set n [llength $pts]
    if {$n < 2} { return 0.0 }
    set inT [lrepeat $n 0]
    set d [lrepeat $n 1e30]
    lset d 0 0.0
    set total 0.0
    for {set it 0} {$it < $n} {incr it} {
        set u -1; set best 1e30
        for {set i 0} {$i < $n} {incr i} { if {![lindex $inT $i] && [lindex $d $i] < $best} { set best [lindex $d $i]; set u $i } }
        lset inT $u 1
        set total [expr {$total + $best}]
        lassign [lindex $pts $u] ux uy
        for {set i 0} {$i < $n} {incr i} {
            if {![lindex $inT $i]} {
                lassign [lindex $pts $i] vx vy
                set w [expr {abs($ux - $vx) + abs($uy - $vy)}]
                if {$w < [lindex $d $i]} { lset d $i $w }
            }
        }
    }
    return $total
}

# pbe085_predict <pin {x y}> <loads {{x y gate_um2} ...}> -> dict nloads maxd (longest pin-to-load Manhattan, um) gmin (smallest known load gate area or "") gsum mst
# gate area "" or <= 0 means unknown (counted in nunknown). The ratio uses the SMALLEST known gate area (conservative) and the longest pin-to-load distance, as run 1 was analysed.
proc pbe085_predict {pin loads} {
    lassign $pin px py
    set maxd 0.0; set gmin ""; set gsum 0.0; set nunk 0
    set pts [list $pin]
    foreach l $loads {
        lassign $l x y g
        set dd [expr {abs($px - $x) + abs($py - $y)}]
        if {$dd > $maxd} { set maxd $dd }
        lappend pts [list $x $y]
        if {$g eq "" || $g <= 0} { incr nunk; continue }
        if {$gmin eq "" || $g < $gmin} { set gmin $g }
        set gsum [expr {$gsum + $g}]
    }
    return [dict create nloads [llength $loads] maxd $maxd gmin $gmin gsum $gsum nunknown $nunk mst [pbe085_mst $pts]]
}

# pbe085_decide <nloads> <ratio> <limit> <margin> <gate_known 0|1> -> {decision reason}
# NO-LOADS: nothing to protect. UNKNOWN-GATE: no load gate area is known: treated as BUFFER (the conservative side) with that reason. BUFFER when ratio > margin x limit (strictly above), else OK.
proc pbe085_decide {nloads ratio limit margin gate_known} {
    if {$nloads == 0} { return [list NO-LOADS "the net has no load pin"] }
    if {!$gate_known} { return [list BUFFER "no load gate area is known in the LEF: predicted ratio unavailable, buffered on the safe side"] }
    set thr [expr {$margin * $limit}]
    if {$ratio > $thr} { return [list BUFFER [format "predicted ratio %.1f > %.2f x limit %.0f = %.1f" $ratio $margin $limit $thr]] }
    return [list OK [format "predicted ratio %.1f <= %.2f x limit %.0f = %.1f" $ratio $margin $limit $thr]]
}

# pbe085_row_runs <row {y0 y1 x0 x1 orient}> <occupied {{x0 x1} ...}> <tol> -> list of run dicts (the format ant_site_candidates reads: y0 y1 x0 x1 orient fillers {}) = the free spans of the row
proc pbe085_row_runs {row occupied tol} {
    lassign $row y0 y1 rx0 rx1 ori
    set runs {}
    set cur $rx0
    foreach o [lsort -real -index 0 $occupied] {
        lassign $o ox0 ox1
        if {$ox1 <= $cur + $tol} { continue }
        if {$ox0 > $cur + $tol} { lappend runs [dict create y0 $y0 y1 $y1 x0 $cur x1 [expr {min($ox0, $rx1)}] orient $ori fillers {}] }
        if {$ox1 > $cur} { set cur $ox1 }
        if {$cur >= $rx1 - $tol} { break }
    }
    if {$cur < $rx1 - $tol} { lappend runs [dict create y0 $y0 y1 $y1 x0 $cur x1 $rx1 orient $ori fillers {}] }
    return $runs
}

# pbe085_rowkey <y0> -> the key a row / a cell is grouped by
proc pbe085_rowkey {y0} { return [format %.3f $y0] }

# pbe085_group_cells <cells {{x0 y0 x1 y1} ...}> <row keys> -> dict key -> {{x0 x1} ...}, plus the number of cells whose y0 matches no row (they are not on a row: reported, never ignored)
proc pbe085_group_cells {cells rowkeys} {
    set g [dict create]
    foreach k $rowkeys { dict set g $k {} }
    set stray 0
    foreach c $cells {
        lassign $c x0 y0 x1 y1
        set k [pbe085_rowkey $y0]
        if {[dict exists $g $k]} { dict lappend g $k [list $x0 $x1] } else { incr stray }
    }
    return [list $g $stray]
}

# pbe085_all_runs <rows {{y0 y1 x0 x1 orient} ...}> <cells> <tol> -> dict runs (all free runs) stray (cells not on a row) occ (key -> occupied list)
proc pbe085_all_runs {rows cells tol} {
    set keys [lmap r $rows {pbe085_rowkey [lindex $r 0]}]
    lassign [pbe085_group_cells $cells $keys] occ stray
    set runs {}
    foreach r $rows {
        set k [pbe085_rowkey [lindex $r 0]]
        foreach x [pbe085_row_runs $r [dict get $occ $k] $tol] { lappend runs $x }
    }
    return [dict create runs $runs stray $stray occ $occ]
}

# pbe085_loc_ok <requested {x y}> <actual {x y}> <tol> -> 1 when the cell sits where it was put
proc pbe085_loc_ok {req act tol} {
    return [expr {abs([lindex $req 0] - [lindex $act 0]) <= $tol && abs([lindex $req 1] - [lindex $act 1]) <= $tol}]
}

# pbe085_gate <before> <after> <tol> -> {ok message}: after must not be below before - tol; an unreadable number is an error (never a pass)
proc pbe085_gate {name before after tol} {
    foreach {w v} [list before $before after $after] {
        if {$v eq "" || $v eq "n/a" || [catch {expr {double($v)}}]} { return [list 0 "$name: the $w value is unreadable ('$v'): the gate cannot decide, nothing saved"] }
    }
    if {$after < $before - $tol} { return [list 0 [format "%s got worse (before %.4f ns, after %.4f ns, tolerance %.4f ns)" $name $before $after $tol]] }
    return [list 1 [format "%s ok (before %.4f ns, after %.4f ns, tolerance %.4f ns)" $name $before $after $tol]]
}

# pbe085_prefix_ok <early prefix> <repair prefix> -> 1 when no cell name of one can match the glob of the other (prefix_*)
proc pbe085_prefix_ok {a b} {
    return [expr {$a ne $b && ![string match "${b}_*" "${a}_x"] && ![string match "${a}_*" "${b}_x"]}]
}

# pbe085_line <row dict> -> one table line. keys: port loads maxd ratio_m23 ratio_top decision reason
proc pbe085_line {r} {
    return [format "%-14s loads %3d  longest %7.1f um  ratio M2/M3 %8.1f  TOP_M %8.1f  %-11s %s" [dict get $r port] [dict get $r loads] [dict get $r maxd] [dict get $r ratio_m23] [dict get $r ratio_top] [dict get $r decision] [dict get $r reason]]
}

# pbe085_totals <rows> -> dict BUFFER OK NO-LOADS CLOCK-SKIPPED total (every row counted exactly once)
proc pbe085_totals {rows} {
    set t [dict create BUFFER 0 OK 0 NO-LOADS 0 CLOCK-SKIPPED 0 total 0]
    foreach r $rows { dict incr t [dict get $r decision]; dict incr t total }
    return $t
}

# pbe085_csv <rows> -> CSV text: the estimates, kept for the calibration against the Calibre antenna database after the route
proc pbe085_csv {rows} {
    set o "port,loads,longest_um,mst_um,gate_min_um2,ratio_m23,ratio_top,decision\n"
    foreach r $rows { append o [format "%s,%d,%.3f,%.3f,%s,%.2f,%.2f,%s\n" [string map {, ;} [dict get $r port]] [dict get $r loads] [dict get $r maxd] [dict get $r mst] [dict get $r gmin] [dict get $r ratio_m23] [dict get $r ratio_top] [dict get $r decision]] }
    return $o
}
# ---- END PURE TCL 085 ----

# optional overrides from the environment (csh: setenv UNPU_PBE_PLAN_ONLY 1 ... unsetenv UNPU_PBE_PLAN_ONLY): the clone stays clean, no edit of this file is needed on the server
set pb_param_src {}
foreach {nm envname kind} {PLAN_ONLY UNPU_PBE_PLAN_ONLY flag PREDICT_MARGIN UNPU_PBE_PREDICT_MARGIN margin PREDICT_WEIGHT UNPU_PBE_PREDICT_WEIGHT word:m23|top} {
    set ev [expr {[info exists ::env($envname)] ? $::env($envname) : "NONE"}]
    lassign [pbe085_env_resolve $nm [set $nm] $kind $ev $envname] val srcx
    set $nm $val
    lappend pb_param_src "$nm $val ($srcx)"
}

# parameters read from antenna_port_buffers.tcl (single source)
foreach nm {ANT_RATIO_LIMIT ANT_WEIGHT_PINWIRE ANT_WEIGHT_TOPM WIRE_WIDTH_UM DIODE_MIN_AREA PIN_WIRE_UM GATE_SAFETY MAX_PIN_BUF_DIST MAX_SITE_TRIES DONT_USE_PATTERNS POWER_PORT_NAMES} {
    if {[catch {set $nm [pbe085_param $ab_src $nm]} perr]} { error "ERROR 085: $ab_path: $perr" }
}
if {![pbe085_prefix_ok $EARLY_PREFIX [pbe085_param $ab_src BUF_PREFIX]]} { error "ERROR 085: EARLY_PREFIX '$EARLY_PREFIX' collides with BUF_PREFIX '[pbe085_param $ab_src BUF_PREFIX]' of antenna_port_buffers.tcl" }
if {$PREDICT_WEIGHT ne "m23" && $PREDICT_WEIGHT ne "top"} { error "ERROR 085: PREDICT_WEIGHT must be m23 or top, got '$PREDICT_WEIGHT'" }

# ---- ICC2 side helpers (use ICC2 commands, not tested locally) ----
proc pbe085_bbox_of {obj} { return [ant_bbox_nums [get_attribute -quiet $obj bbox]] }   ;# VERIFY: the bbox attribute of cells, pins and terminals is a string with 4 numbers (as antenna_port_buffers.tcl ant068_bbox_of)
proc pbe085_centre {obj} { lassign [pbe085_bbox_of $obj] x0 y0 x1 y1; return [list [expr {($x0 + $x1) / 2.0}] [expr {($y0 + $y1) / 2.0}]] }
proc pbe085_names {coll} { set o {}; foreach_in_collection x $coll { lappend o [get_object_name $x] }; return $o }
proc pbe085_wns {scen type} {   ;# worst slack of the whole design in a scenario; VERIFY get_timing_paths -scenarios -delay_type -max_paths and the slack attribute (usage text [L])
    set p [get_timing_paths -scenarios $scen -delay_type $type -max_paths 1]
    if {[sizeof_collection $p] == 0} { return "n/a" }
    return [get_attribute $p slack]
}
proc pbe085_in2out {scen from_ports} {   ;# {wns violating_endpoints} of the paths from the non-clock input ports to the output ports; VERIFY -from/-to with port collections (pt_eco_apply.tcl uses the same form)
    set p [get_timing_paths -scenarios $scen -delay_type max -from $from_ports -to [all_outputs] -max_paths 1]
    if {[sizeof_collection $p] == 0} { return [list n/a 0] }
    set w [get_attribute $p slack]
    set nv [sizeof_collection [get_timing_paths -scenarios $scen -delay_type max -from $from_ports -to [all_outputs] -slack_lesser_than 0 -max_paths 100000]]
    return [list $w $nv]
}
proc pbe085_port_slack {scen port} {   ;# worst slack from ONE port to the outputs ("n/a" = no path = the port is not on the cone)
    set p [get_timing_paths -scenarios $scen -delay_type max -from [get_ports -exact $port] -to [all_outputs] -max_paths 1]
    if {[sizeof_collection $p] == 0} { return "n/a" }
    return [get_attribute $p slack]
}
proc pbe085_cone_struct {port outset} {   ;# 1 when an output port is among the endpoints reachable from the port through combinational cells; VERIFY all_fanout -flat -endpoints_only -from
    set ep [pbe085_names [all_fanout -flat -endpoints_only -from [get_ports -exact $port]]]
    foreach e $ep { if {[lsearch -exact $outset $e] >= 0} { return 1 } }
    return 0
}
proc pbe085_pin_xy {pin} { return [pbe085_centre $pin] }
proc pbe085_net_loads {net lef} {   ;# {{x y gate} ...} for the leaf pins of a net; the gate area is the smallest ANTENNAGATEAREA of the pin in the LEF, "" when unknown
    set o {}
    foreach_in_collection p [get_pins -quiet -leaf -of_objects [get_nets -quiet -exact $net]] {
        set full [get_object_name $p]
        set pn [lindex [split $full /] end]
        set c [get_cells -quiet -of_objects $p]
        set ref ""
        if {[sizeof_collection $c] == 1} { set ref [get_attribute -quiet $c ref_name] }
        set g ""
        if {$ref ne "" && [dict exists $lef $ref pins $pn]} {
            set gl [dict get $lef $ref pins $pn gate]
            if {[llength $gl] > 0} { set g [lindex [lsort -real $gl] 0] }
        }
        lassign [pbe085_pin_xy $p] x y
        lappend o [list $x $y $g $full $ref]
    }
    return $o
}
proc pbe085_read_cells {} {   ;# all leaf cell boxes {x0 y0 x1 y1} (the occupancy) and the orientation of the first cell of each row key; VERIFY get_cells -hierarchical -filter, the bbox and orientation attributes
    set boxes {}
    array set ori {}
    foreach_in_collection c [get_cells -quiet -hierarchical -filter "is_hierarchical == false"] {
        lassign [pbe085_bbox_of $c] x0 y0 x1 y1
        lappend boxes [list $x0 $y0 $x1 $y1]
        set k [pbe085_rowkey $y0]
        if {![info exists ori($k)]} { set o [get_attribute -quiet $c orientation]; if {$o ne ""} { set ori($k) $o } }
    }
    return [list $boxes [array get ori]]
}

file mkdir $LOG_DIR
file mkdir $RPT_DIR

redirect -tee -file ${LOG_DIR}/4c_port_buffers_early.log {
    puts ">>> RUN ROOT: $RUN_ROOT"   ;# 082: the log shows which clone wrote it
    puts ">>> 085 parameters: IN_BLOCK $IN_BLOCK, OUT_BLOCK $OUT_BLOCK, [join $pb_param_src {, }], GATE_TOL_IN2OUT $GATE_TOL_IN2OUT, GATE_TOL_SETUP $GATE_TOL_SETUP, EARLY_PREFIX $EARLY_PREFIX"
    puts ">>> 085 from antenna_port_buffers.tcl: ANT_RATIO_LIMIT $ANT_RATIO_LIMIT, weights M2/M3 $ANT_WEIGHT_PINWIRE and TOP_M $ANT_WEIGHT_TOPM, wire width $WIRE_WIDTH_UM um, diode area $DIODE_MIN_AREA um^2, MAX_PIN_BUF_DIST $MAX_PIN_BUF_DIST um, PIN_WIRE_UM $PIN_WIRE_UM"

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} { close_blocks -force $open_blk }
    set open_lib [get_libs -quiet *]
    if {[sizeof_collection $open_lib] > 0} { foreach_in_collection lib_obj $open_lib { close_lib -force $lib_obj } }
    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    if {[catch {open_block ${DESIGN_NAME}.dlib:${IN_BLOCK}} oerr]} { error "ERROR 085: cannot open the block ${IN_BLOCK} ($oerr): run placement.tcl first. Blocks that exist: [pbe085_names [get_blocks -all -quiet]]" }
    link_block
    puts ">>> 085 block ${IN_BLOCK} opened; the result is saved as the NEW block ${OUT_BLOCK} (${IN_BLOCK} is not overwritten)"
    suppress_message {DCHK-027 DCHK-010 ATTR-12 PDC-003 UIC-058 UIC-057}

    # --------------------------------------------------------------------------
    # 1. Buffer cell chosen by data (the rules of antenna_port_buffers.tcl)
    # --------------------------------------------------------------------------
    if {![file exists $STD_LEF]} { error "ERROR 085: kit LEF not found at $STD_LEF" }
    set fp [open $STD_LEF r]; set pb_lef [ant_parse_lef [read $fp]]; close $fp
    puts ">>> 085 LEF $STD_LEF: [dict size $pb_lef] macros"
    set pb_bufnames {}; set pb_libcell_of {}
    if {[catch {set pb_lc [get_lib_cells -quiet ${STD_LIB}/* -filter "is_buffer == true"]} err]} { error "ERROR 085: cannot select buffers with the lib_cell attribute is_buffer: $err" }   ;# VERIFY is_buffer (as antenna_port_buffers.tcl)
    foreach_in_collection lc $pb_lc {
        set full [get_object_name $lc]; set short [lindex [split $full /] end]
        if {[get_attribute -quiet $lc dont_use] eq "true"} { continue }
        lappend pb_bufnames $short; lappend pb_libcell_of $short $full
    }
    if {[llength $pb_bufnames] == 0} { error "ERROR 085: no buffer cell found in $STD_LIB" }
    set pb_need [ant_need_gate $PIN_WIRE_UM $WIRE_WIDTH_UM $ANT_WEIGHT_PINWIRE $ANT_RATIO_LIMIT $GATE_SAFETY]
    set pb_rows [ant_eval_buffers $pb_lef $pb_bufnames $DONT_USE_PATTERNS $pb_need $DIODE_MIN_AREA]
    foreach r [lsort -real -index 3 [lmap r $pb_rows {list [dict get $r name] [dict get $r verdict] [dict get $r why] [dict get $r area] [dict get $r gate] [dict get $r diff]}]] {
        puts [format ">>> 085   %-12s area %8.2f  gate %7.3f  diff %7.3f  %s  %s" [lindex $r 0] [lindex $r 3] [lindex $r 4] [lindex $r 5] [lindex $r 1] [lindex $r 2]]
    }
    set pb_buf [ant_pick_buffer $pb_rows]
    if {$pb_buf eq ""} { error "ERROR 085: no library buffer meets the rules (a) to (d); see the table above" }
    foreach r $pb_rows { if {[dict get $r name] eq $pb_buf} { set pb_row $r } }
    set pb_lc_name [dict get $pb_libcell_of $pb_buf]
    set pb_bw [dict get $pb_row w]; set pb_bh [dict get $pb_row h]; set pb_gate [dict get $pb_row gate]
    puts ">>> 085 CHOSEN buffer $pb_lc_name: ${pb_bw} x ${pb_bh} um, input gate [format %.3f $pb_gate] um^2, output diffusion [format %.3f [dict get $pb_row diff]] um^2"

    # --------------------------------------------------------------------------
    # 2. The input ports and the prediction table
    # --------------------------------------------------------------------------
    set pb_clock_ports {}
    foreach_in_collection ck [get_clocks -quiet -filter "is_virtual == false"] {
        set srcs [get_attribute -quiet $ck sources]   ;# VERIFY the clock attribute `sources`
        if {$srcs ne "" && [sizeof_collection $srcs] > 0} { foreach s [pbe085_names $srcs] { lappend pb_clock_ports $s } }
    }
    if {[llength $pb_clock_ports] == 0} { set pb_clock_ports $CLOCK_PORT_NAMES; puts ">>> 085 the clock source ports could not be read from the clocks: using CLOCK_PORT_NAMES $CLOCK_PORT_NAMES" }
    puts ">>> 085 clock ports (not buffered): $pb_clock_ports"
    set pb_inputs {}
    foreach p [pbe085_names [all_inputs]] { if {[lsearch -exact $POWER_PORT_NAMES $p] < 0} { lappend pb_inputs $p } }
    puts ">>> 085 input ports: [llength $pb_inputs] (clock ports and $POWER_PORT_NAMES included in this count are handled below)"
    set pb_data_inputs {}
    foreach p $pb_inputs { if {[lsearch -exact $pb_clock_ports $p] < 0} { lappend pb_data_inputs $p } }
    set pb_outset [pbe085_names [all_outputs]]

    set pb_ab_gate_unknown 0
    set pb_table {}
    array set pb_xy {}
    array set pb_loads_n {}
    foreach p $pb_inputs {
        set t [get_terminals -quiet -of_objects [get_ports -quiet -exact $p]]
        if {[sizeof_collection $t] == 0} { error "ERROR 085: port $p has no terminal (the pins are not placed?)" }
        set pxy [pbe085_centre [index_collection $t 0]]
        set pb_xy($p) $pxy
        if {[lsearch -exact $pb_clock_ports $p] >= 0} {
            lappend pb_table [dict create port $p loads 0 maxd 0.0 mst 0.0 gmin "" ratio_m23 0.0 ratio_top 0.0 decision CLOCK-SKIPPED reason "clock port: not buffered (CTS)"]
            continue
        }
        set net [pbe085_names [get_nets -quiet -of_objects [get_ports -exact $p]]]
        if {[llength $net] != 1} { error "ERROR 085: port $p is on [llength $net] nets {$net}, expected exactly one" }
        set loads [pbe085_net_loads [lindex $net 0] $pb_lef]
        set pb_loads_n($p) [llength $loads]
        set pr [pbe085_predict $pxy [lmap l $loads {lrange $l 0 2}]]
        set gm [dict get $pr gmin]
        set gk [expr {$gm ne ""}]
        set rm 0.0; set rt 0.0
        if {$gk} {
            set rm [ant_ratio $gm [dict get $pr maxd] $WIRE_WIDTH_UM $ANT_WEIGHT_PINWIRE]
            set rt [ant_ratio $gm [dict get $pr maxd] $WIRE_WIDTH_UM $ANT_WEIGHT_TOPM]
        }
        lassign [pbe085_decide [dict get $pr nloads] [expr {$PREDICT_WEIGHT eq "top" ? $rt : $rm}] $ANT_RATIO_LIMIT $PREDICT_MARGIN $gk] dec why
        if {[dict get $pr nunknown] > 0} { append why [format " (%d of %d load gate areas unknown)" [dict get $pr nunknown] [dict get $pr nloads]] }
        lappend pb_table [dict create port $p loads [dict get $pr nloads] maxd [dict get $pr maxd] mst [dict get $pr mst] gmin $gm ratio_m23 $rm ratio_top $rt decision $dec reason $why]
    }
    puts ">>> 085 ===== PREDICTION TABLE (port, loads, longest pin-to-load distance from the placement, predicted ratio, decision) ====="
    foreach r $pb_table { puts ">>> 085 [pbe085_line $r]" }
    set pb_tot [pbe085_totals $pb_table]
    puts ">>> 085 TOTALS: ports [dict get $pb_tot total] = BUFFER [dict get $pb_tot BUFFER] + OK [dict get $pb_tot OK] + NO-LOADS [dict get $pb_tot NO-LOADS] + CLOCK-SKIPPED [dict get $pb_tot CLOCK-SKIPPED]"
    if {[dict get $pb_tot total] != [llength $pb_inputs]} { error "ERROR 085: table totals ([dict get $pb_tot total]) differ from the number of input ports ([llength $pb_inputs])" }
    set csv ${RPT_DIR}/port_buffers_early_table.csv
    set fp [open $csv w]; puts -nonewline $fp [pbe085_csv $pb_table]; close $fp
    puts ">>> 085 estimates written to $csv (compare with the Calibre antenna database after the route to calibrate PREDICT_MARGIN)"

    # 4. the clock port: print only
    foreach ckp $pb_clock_ports {
        set net [pbe085_names [get_nets -quiet -of_objects [get_ports -exact $ckp]]]
        set loads [pbe085_net_loads [lindex $net 0] $pb_lef]
        set rg $CTS_ROOT_GATE
        if {$rg == 0.0 && [dict exists $pb_lef $CTS_ROOT_CELL]} {
            set gl {}
            dict for {pn pd} [dict get $pb_lef $CTS_ROOT_CELL pins] { if {[dict get $pd dir] eq "INPUT" && [dict get $pd use] ne "POWER" && [dict get $pd use] ne "GROUND"} { lappend gl {*}[dict get $pd gate] } }
            if {[llength $gl] > 0} { set rg [lindex [lsort -real $gl] 0] }
        }
        if {[llength $loads] == 0} { puts ">>> 085 CLOCK port $ckp: no load pin before CTS (the CTS root is inserted later); nothing to estimate"; continue }
        lassign $pb_xy($ckp) cx cy
        set md 0.0; foreach l $loads { set md [expr {max($md, abs($cx - [lindex $l 0]) + abs($cy - [lindex $l 1]))}] }
        if {$rg > 0} {
            set r_ [ant_ratio $rg $md $WIRE_WIDTH_UM $ANT_WEIGHT_PINWIRE]
            puts [format ">>> 085 CLOCK port %s (not buffered): pin-to-first-load %.1f um; with the CTS root cell %s (gate %.3f um^2) the predicted ratio is %.0f (limit %.0f) -> %s" $ckp $md $CTS_ROOT_CELL $rg $r_ $ANT_RATIO_LIMIT [expr {$r_ > $ANT_RATIO_LIMIT ? "a larger root cell is likely needed (task 071); CTS decides" : "no larger root cell needed by this estimate"}]]
        } else {
            puts ">>> 085 CLOCK port $ckp: pin-to-first-load [format %.1f $md] um; the gate area of the root cell $CTS_ROOT_CELL is unknown in the LEF: no ratio printed"
        }
    }

    if {$PLAN_ONLY} {
        puts ">>> 085 PLAN_ONLY 1: nothing was inserted or saved. BUFFER count [dict get $pb_tot BUFFER]. Set PLAN_ONLY 0 (and decide PREDICT_MARGIN with a written reason) to apply."
        puts ">>> STAGE 4c PLAN ONLY: ${IN_BLOCK} unchanged, ${OUT_BLOCK} NOT created. Log: ${LOG_DIR}/4c_port_buffers_early.log"
    }
    if {!$PLAN_ONLY} {   ;# everything below changes the block (no `return` inside the redirect body)
    set pb_targets {}
    foreach r $pb_table { if {[dict get $r decision] eq "BUFFER"} { lappend pb_targets [dict get $r port] } }
    if {[llength $pb_targets] == 0} { error "ERROR 085: no net needs a buffer by this prediction: nothing to do. Check PREDICT_MARGIN; the block ${OUT_BLOCK} is not created" }

    # --------------------------------------------------------------------------
    # 5. Measurements before, and the input-to-output cone
    # --------------------------------------------------------------------------
    set pb_from [remove_from_collection [all_inputs] [get_ports -quiet $pb_clock_ports]]
    update_timing -full
    set pb_s0 [pbe085_wns $SETUP_SCEN max]; set pb_h0 [pbe085_wns $HOLD_SCEN min]
    lassign [pbe085_in2out $SETUP_SCEN $pb_from] pb_io0 pb_ion0
    puts ">>> 085 BEFORE: setup WNS ($SETUP_SCEN) $pb_s0, hold WNS ($HOLD_SCEN) $pb_h0, in2out WNS ($SETUP_SCEN) $pb_io0 with $pb_ion0 violating endpoints"
    array set pb_cone {}
    array set pb_slack0 {}
    set pb_cone_nets {}
    foreach p $pb_targets {
        set s_struct [pbe085_cone_struct $p $pb_outset]
        set s0 [pbe085_port_slack $SETUP_SCEN $p]
        set s_time [expr {$s0 ne "n/a"}]
        if {$s_struct != $s_time} { puts ">>> 085 cone DISAGREEMENT for $p: structural fanout says $s_struct, timing paths say $s_time: treated as ON the cone (the safe side)" }
        set pb_cone($p) [expr {$s_struct || $s_time}]
        set pb_slack0($p) $s0
        if {$pb_cone($p)} { lappend pb_cone_nets $p }
    }
    puts ">>> 085 BUFFER nets on an input-to-output cone ([llength $pb_cone_nets]): $pb_cone_nets"

    # --------------------------------------------------------------------------
    # 6. Free sites (no fillers yet) and the insertions
    # --------------------------------------------------------------------------
    set rows_all {}
    foreach_in_collection sr [get_site_rows -quiet] {
        lassign [pbe085_bbox_of $sr] a b c d
        lappend rows_all [list $b $d $a $c ""]   ;# y0 y1 x0 x1 orient (orientation is taken from the cells of the row below)
    }
    if {[llength $rows_all] == 0} { error "ERROR 085: no site rows found" }
    lassign [pbe085_read_cells] pb_boxes pb_ori_list
    array set pb_ori $pb_ori_list
    puts ">>> 085 rows [llength $rows_all], cell boxes read [llength $pb_boxes]"
    if {[llength $pb_boxes] < 1000} { error "ERROR 085: only [llength $pb_boxes] cell boxes were read: the occupancy would be wrong (VERIFY get_cells -hierarchical -filter); nothing changed" }
    set rows_o {}
    foreach r $rows_all {
        set k [pbe085_rowkey [lindex $r 0]]
        lappend rows_o [list [lindex $r 0] [lindex $r 1] [lindex $r 2] [lindex $r 3] [expr {[info exists pb_ori($k)] ? $pb_ori($k) : ""}]]
    }
    set pb_ar [pbe085_all_runs $rows_o $pb_boxes $ROW_TOL_UM]
    if {[dict get $pb_ar stray] > 0} { error "ERROR 085: [dict get $pb_ar stray] cells do not sit on a site row (y0 matches no row): the free-site table would be wrong; nothing changed" }
    set pb_runs [dict get $pb_ar runs]
    puts ">>> 085 free runs: [llength $pb_runs] (rows without an orientation read from a cell are skipped as candidates)"
    set pb_site_w 1e9
    foreach f {feedth feedth3 feedth9} { if {[dict exists $pb_lef $f] && [dict get $pb_lef $f w] ne "" && [dict get $pb_lef $f w] < $pb_site_w} { set pb_site_w [dict get $pb_lef $f w] } }
    if {$pb_site_w > 1e8} { error "ERROR 085: no filler master in the LEF: the site width is unknown" }   ;# the site width is the width of the narrowest filler master (as antenna_port_buffers.tcl)
    puts ">>> 085 site width $pb_site_w um, buffer ${pb_bw} um = [expr {int(ceil($pb_bw / $pb_site_w - 1e-6))}] sites, limit MAX_PIN_BUF_DIST $MAX_PIN_BUF_DIST um"

    array set pb_cell_of {}
    array set pb_dist_of {}
    array set pb_req_of {}
    array set pb_nl_of {}
    set pb_failed {}
    set k 0
    foreach p $pb_targets {
        incr k
        lassign $pb_xy($p) px py
        set net [lindex [pbe085_names [get_nets -quiet -of_objects [get_ports -exact $p]]] 0]
        set nbefore [llength [pbe085_names [get_pins -quiet -leaf -of_objects [get_nets -exact $net]]]]
        set placed 0
        set ntry 0
        foreach c [lrange [ant_site_candidates $pb_runs $pb_bw $pb_site_w $px $py $MAX_PIN_BUF_DIST] 0 [expr {$MAX_SITE_TRIES - 1}]] {
            incr ntry
            set cx [dict get $c x]; set cy [dict get $c y]
            set ori [dict get $c orient]
            if {$ori eq ""} { puts ">>> 085 $p candidate ($cx, $cy): the row has no orientation read from a cell: skipped"; continue }
            set base "${EARLY_PREFIX}_[regsub -all {[^A-Za-z0-9]} $p _]_${k}_a${ntry}"
            insert_buffer -lib_cell [get_lib_cells -exact $pb_lc_name] -new_cell_names $base -new_net_names ${base}_n [get_ports -exact $p]   ;# VERIFY insert_buffer on a PORT (as antenna_port_buffers.tcl)
            set bc [get_cells -quiet -exact $base]
            if {[sizeof_collection $bc] != 1} { error "ERROR 085: port $p: the new cell $base was not found after insert_buffer (nothing saved)" }
            if {[catch {set_cell_location -coordinates [list $cx $cy] -orientation $ori $bc} err]} {   ;# VERIFY set_cell_location -orientation (as antenna_port_buffers.tcl)
                if {[catch {set_attribute -objects $bc -name origin -value [list $cx $cy]} err2]} { error "ERROR 085: port $p: cannot move $base: $err / $err2 (nothing saved)" }
            }
            lassign [pbe085_bbox_of $bc] bx0 by0 bx1 by1
            set inp [get_pins -quiet -of_objects $bc -filter "direction == in"]
            lassign [expr {[sizeof_collection $inp] == 1 ? [pbe085_centre $inp] : [pbe085_centre $bc]}] ix iy
            set dist [ant_manhattan $px $py $ix $iy]
            set why {}
            if {![pbe085_loc_ok [list $cx $cy] [list $bx0 $by0] 0.001]} { lappend why "buffer at ([format %.3f $bx0], [format %.3f $by0]) instead of the site ([format %.3f $cx], [format %.3f $cy])" }
            if {$dist > $MAX_PIN_BUF_DIST} { lappend why "distance [format %.1f $dist] > $MAX_PIN_BUF_DIST" }
            puts [format ">>> 085 BUFFER %s pin=(%.2f, %.2f) site=(%.3f, %.3f) final=(%.3f, %.3f) distance=%.1f um try %d %s" $p $px $py $cx $cy $bx0 $by0 $dist $ntry [expr {[llength $why] ? "REJECTED: [join $why {; }]" : "OK"}]]
            if {[llength $why] == 0} {
                set pb_cell_of($p) $base; set pb_dist_of($p) $dist; set pb_req_of($p) [list $cx $cy]; set pb_nl_of($p) $nbefore
                set placed 1
                # the occupancy follows the design: the new box is removed from the free runs of its row
                set rk [pbe085_rowkey $cy]
                set occ [dict get $pb_ar occ]
                dict lappend occ $rk [list $bx0 $bx1]
                dict set pb_ar occ $occ
                set pb_runs {}
                foreach r $rows_o { foreach x [pbe085_row_runs $r [dict get $occ [pbe085_rowkey [lindex $r 0]]] $ROW_TOL_UM] { lappend pb_runs $x } }
                break
            }
            if {[catch {remove_buffers $bc} err]} { error "ERROR 085: port $p: cannot remove the rejected buffer $base: $err (nothing saved)" }   ;# VERIFY remove_buffers restores the net
            set back [llength [pbe085_names [get_pins -quiet -leaf -of_objects [get_nets -exact $net]]]]
            if {$back != $nbefore} { error "ERROR 085: port $p: $back leaf pins after removing the rejected buffer, $nbefore before (nothing saved)" }
        }
        if {!$placed} { lappend pb_failed $p; puts ">>> 085 BUFFER $p FAILED: no free site within $MAX_PIN_BUF_DIST um after $ntry tries" }
    }
    if {[llength $pb_failed] > 0} { error "ERROR 085: [llength $pb_failed] buffers could not be placed: {$pb_failed} (nothing saved; the nets are not silently skipped)" }

    # --------------------------------------------------------------------------
    # 7. Protection from the later optimisers (CTS, route_opt): dont_touch (no removal, no resizing) and a fixed placement status
    # --------------------------------------------------------------------------
    set pb_cells [get_cells -quiet ${EARLY_PREFIX}_*]
    if {[sizeof_collection $pb_cells] != [llength $pb_targets]} { error "ERROR 085: [sizeof_collection $pb_cells] cells named ${EARLY_PREFIX}_* for [llength $pb_targets] BUFFER nets (nothing saved)" }
    if {[catch {set_dont_touch $pb_cells true} err]} { error "ERROR 085: set_dont_touch failed: $err (nothing saved)" }   ;# VERIFY set_dont_touch <cells> true
    if {[catch {set_attribute -objects $pb_cells -name physical_status -value $PROTECT_PHYS} err]} { error "ERROR 085: setting physical_status $PROTECT_PHYS failed: $err (nothing saved)" }   ;# VERIFY the cell attribute physical_status and its value fixed
    set pb_bad {}
    foreach_in_collection c $pb_cells {
        set dt [get_attribute -quiet $c dont_touch]; set ps [get_attribute -quiet $c physical_status]   ;# VERIFY attribute names dont_touch / physical_status
        if {$dt ne "true" || $ps ne $PROTECT_PHYS} { lappend pb_bad "[get_object_name $c] dont_touch=$dt physical_status=$ps" }
    }
    if {[llength $pb_bad] > 0} { error "ERROR 085: protection read back wrong for [llength $pb_bad] cells: [lrange $pb_bad 0 4] (nothing saved)" }
    puts ">>> 085 PROTECTION: [sizeof_collection $pb_cells] cells have dont_touch true and physical_status $PROTECT_PHYS (read back). dont_touch also forbids resizing: a smaller gate would weaken the antenna protection, so no sizing is allowed on purpose"

    # --------------------------------------------------------------------------
    # 8. Checks, metrics after, gate, save
    # --------------------------------------------------------------------------
    set pb_fail {}
    redirect -variable pb_leg_txt { check_legality -verbose }
    puts $pb_leg_txt
    set pb_leg [ant_parse_legality $pb_leg_txt]
    if {$pb_leg eq ""} { lappend pb_fail "check_legality result unreadable (see the text above)" } elseif {$pb_leg != 0} { lappend pb_fail "legality violations $pb_leg" }
    foreach p $pb_targets {
        if {$pb_dist_of($p) > $MAX_PIN_BUF_DIST} { lappend pb_fail "$p: buffer [format %.1f $pb_dist_of($p)] um from the pin" }
        set net [lindex [pbe085_names [get_nets -quiet -of_objects [get_ports -exact $p]]] 0]
        set n_port [llength [pbe085_names [get_pins -quiet -leaf -of_objects [get_nets -exact $net]]]]
        if {$n_port != 1} { lappend pb_fail "$p: the port net has $n_port leaf pins after the insertion, expected exactly 1 (the buffer input)" }
        set outn [pbe085_names [get_nets -quiet -of_objects [get_pins -quiet -of_objects [get_cells -exact $pb_cell_of($p)] -filter "direction == out"]]]
        set n_new [llength [pbe085_names [get_pins -quiet -leaf -of_objects [get_nets -exact [lindex $outn 0]]]]]
        if {$n_new != $pb_nl_of($p) + 1} { lappend pb_fail "$p: the buffer output net has $n_new leaf pins, expected [expr {$pb_nl_of($p) + 1}] (the loads and the buffer output)" }
    }
    update_timing -full
    set pb_s1 [pbe085_wns $SETUP_SCEN max]; set pb_h1 [pbe085_wns $HOLD_SCEN min]
    lassign [pbe085_in2out $SETUP_SCEN $pb_from] pb_io1 pb_ion1
    puts ">>> 085 AFTER:  setup WNS ($SETUP_SCEN) $pb_s1 (before $pb_s0), hold WNS ($HOLD_SCEN) $pb_h1 (before $pb_h0), in2out WNS ($SETUP_SCEN) $pb_io1 with $pb_ion1 violating endpoints (before $pb_io0 with $pb_ion0)"
    foreach p $pb_cone_nets {
        set s1 [pbe085_port_slack $SETUP_SCEN $p]
        set added [expr {($pb_slack0($p) eq "n/a" || $s1 eq "n/a") ? "n/a" : [format %.4f [expr {$pb_slack0($p) - $s1}]]}]
        puts ">>> 085 CONE net $p: worst slack to the outputs before $pb_slack0($p), after $s1: delay added by the buffer on that path $added ns"
    }
    lassign [pbe085_gate "in2out WNS" $pb_io0 $pb_io1 $GATE_TOL_IN2OUT] g1 gm1
    lassign [pbe085_gate "setup WNS" $pb_s0 $pb_s1 $GATE_TOL_SETUP] g2 gm2
    puts ">>> 085 GATE: $gm1"
    puts ">>> 085 GATE: $gm2"
    if {!$g1} { lappend pb_fail "ERROR 085: the buffers made the in2out group worse: $gm1; nets on the cone: $pb_cone_nets" }
    if {!$g2} { lappend pb_fail "ERROR 085: the buffers made the setup WNS worse: $gm2" }
    if {[llength $pb_fail] > 0} { error "ERROR 085: hard checks failed, nothing saved: [join $pb_fail {; }]" }

    save_block -as ${OUT_BLOCK}
    save_lib
    puts ">>> STAGE 4c COMPLETE: [llength $pb_targets] input-port nets buffered with $pb_lc_name, ${OUT_BLOCK} saved (${IN_BLOCK} unchanged). Next: cts.tcl (it opens ${OUT_BLOCK}). Log: ${LOG_DIR}/4c_port_buffers_early.log"
    }
}
