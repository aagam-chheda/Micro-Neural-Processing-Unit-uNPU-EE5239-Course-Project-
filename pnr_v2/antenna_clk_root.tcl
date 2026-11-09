# ==============================================================================
# Script: antenna_clk_root.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/antenna_clk_root.tcl   ;# 071: new script (flow step 6d, after antenna_port_buffers.tcl, before metal_fill.tcl)
# Stage : Antenna fix of the `clk` port net: replace the CTS root inverter by a larger inverter (size-only change)
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 071: THIS SCRIPT CHANGES THE NETLIST (an ECO on ONE clock-tree cell): the CTS root inverter that is the only load of the `clk` port net is replaced by an inverter
# 071: with the SAME function, pins and connections but a larger input gate. The PM must be told (the netlist written by pv.tcl has a different cell type at that instance).
# 071: why. The `clk` port net runs from the pin to the root inverter (about 490 um of M3) and has no diffusion inside the macro, so Calibre counts the whole wire against the
# 071: input gate of the root inverter: ratio = PERIMETER(M3 polygon) x 0.54 / AREA(gate) must not exceed 400 (rule AN.MTL.1.M3). A buffer at the pin was rejected for the first try
# 071: (it adds delay at the top of the clock tree). A bigger gate at the end of the wire makes the same wire legal: needed gate area = perimeter x weight / limit x margin.
# 071: what it does, in order (read-only until step 7; every decision is printed with `>>> 071`):
# 071:   1 parse the Calibre antenna database (same file and same parser as antenna_port_buffers.tcl) and map every polygon to a net with the SAME functions (ant_rank, ant_decide);
# 071:     the script handles only clock-source port nets; any other net is listed and is an error (antenna_port_buffers.tcl is for those)
# 071:   2 find the root cell = the single leaf load of the clock port net (taken from the design); print reference, location, orientation, distance to the pin, polygon perimeter
# 071:   3 gate area needed (perimeter x weight / limit x margin), also printed for the TOP_M weight
# 071:   4 choose the replacement inverter from the kit LEF (ANTENNAGATEAREA of the input pin): smallest gate area that reaches the need; candidate table printed; error if none
# 071:   5 BEFORE: clock QoR, setup / hold WNS, global timing; plan the room for the larger cell from the filler table (error if a real cell is in the way)
# 071:   6 remove exactly the fillers in the way, size the cell, check position, legalise only that cell, refill, reconnect PG
# 071:   7 route_eco on the nets of the cell, route_detail -incremental
# 071:   8 hard checks (nothing is saved when one fails), AFTER metrics, OK / WORSE / UNKNOWN verdict, save over `_route`
# 071: every command or option not shown in a usage text in ~/server_pull/rpt/help (the real help of this tool version) is marked VERIFY.
# 071: no timing option, uncertainty, goal or limit is changed; no diode; no waiver; no change to a Calibre rule or control file.

set DESIGN_NAME "unpu_top"   ;# 071: design name (as the other scripts)
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"   ;# 071: ICC2 work directory (as the other scripts)
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set SCRIPT_DIR  "/storage/EE5239G1/aagams_workspace2/unpu/pnr_v2"   ;# 071: where antenna_port_buffers.tcl is: its procs (LEF parser, polygon ranking, filler table, check_routes parser) are read from its text, not copied
set ANT_DB      "/storage/EE5239G1/aagams_workspace2/unpu/pv/drc/unpu_top_antenna_bkp.db"   ;# 071: the same file as fix_antenna.tcl / antenna_port_buffers.tcl
set ANT_DECK    "/storage/EE5239G1/aagams_workspace/calibre_run/scr/ANTENNA_TS18SL_SCL_CALIBRE"   ;# 071: OPTIONAL: the kit deck; the weight and the limit are read from its rule text when it can be read (handoff 18.24: working copy of the kit decks)
set STD_LEF     "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"   ;# 071: kit LEF (as pnr_v2/build_ndm_std.tcl)
set STD_LIB     "scl180_std"   ;# 071: reference library name (as cts.tcl)
set FILLER_LIB  "scl180_filler"   ;# 071: as route.tcl
set FILLER_REFS {feedth feedth3 feedth9}   ;# 071: the filler masters route.tcl inserts

# ------------------------------------------------------------------------------
# 071: parameters. Source of the Calibre numbers: the Calibre antenna log of the last server run (task 071):
# 071:   "AN.MTL.1.M3 = NET AREA RATIO M3_no_dio M2 M1 GC_STI GATE > 400 [PERIMETER(M3_no_dio)*0.54/AREA(GATE)]"; TOP_M weight 0.84 (handoff 18.27). They are used only when the deck text cannot be read.
# ------------------------------------------------------------------------------
set ANT_RATIO_LIMIT   400.0   ;# 071: AN.MTL.1.* limit
set ANT_WEIGHT_M3     0.54    ;# 071: M3 weight (M2 is 0.54 too, handoff 18.27)
set ANT_WEIGHT_M2     0.54
set ANT_WEIGHT_TOPM   0.84    ;# 071: TOP_M weight
set GATE_MARGIN       1.10    ;# 071: needed gate area is multiplied by this (10 percent), task 071
set DONT_USE_PATTERNS {slnht* skbrb* slbhb* slnhn* slnln* mx08d* adiode bh01d1 cload1}   ;# 071: handoff 18.15 (15 pattern cells + the library's own three), checked by name; same list as antenna_port_buffers.tcl
set POWER_PORT_NAMES  {VDD VSS}
set SETUP_SCEN        "func_ss"   ;# 071: scenario names of cts.tcl / route.tcl
set HOLD_SCEN         "func_ff"
set SKEW_TOL          0.05    ;# 071: WORSE when the global skew grows by more than this (ns), task 071
set WNS_TOL           0.02    ;# 071: WORSE when the setup or the hold WNS gets worse by more than this (ns), task 071
set TOL_UM            0.006   ;# 071: as antenna_port_buffers.tcl
set MARGIN_SCORE      0.05
set MIN_COVER         0.5

# ---- BEGIN PURE TCL 071 ----
# 071: everything between BEGIN and END is plain Tcl (no ICC2 command); pnr_v2/test_antenna_clk_root.tcl extracts and tests exactly this text.

# 071: perimeter (um) of a polygon given its vertex lists
proc ant071_perimeter {xs ys} {
    set n [llength $xs]
    set p 0.0
    for {set i 0} {$i < $n} {incr i} {
        set j [expr {($i + 1) % $n}]
        set p [expr {$p + hypot([lindex $xs $j] - [lindex $xs $i], [lindex $ys $j] - [lindex $ys $i])}]
    }
    return $p
}

# 071: gate area (um^2) needed so that perimeter x weight / gate <= limit, with a margin factor
proc ant071_needed_gate {perimeter weight limit margin} {
    return [expr {$perimeter * $weight / $limit * $margin}]
}

# 071: read the weight and the limit of one antenna rule out of a deck or log text. Accepts
# 071: "AN.MTL.1.M3 = NET AREA RATIO M3_no_dio M2 M1 GC_STI GATE > 400 [PERIMETER(M3_no_dio)*0.54/AREA(GATE)]" (the line of the Calibre log). Returns {weight limit} or "".
proc ant071_parse_rule_formula {text rule} {
    set re "[string map {. {\.}} $rule]\\s*=\[^\\n\]*?>\\s*(\[0-9.\]+)\[^\\n\]*?PERIMETER\\(\[^)\]*\\)\\s*\\*\\s*(\[0-9.\]+)\\s*/\\s*AREA\\(GATE\\)"
    if {[regexp -- $re $text -> limit weight]} { return [list $weight $limit] }
    return ""
}

# 071: evaluate inverters (names already known to be inverters of the library) against the LEF.
# 071: criteria: (a) exactly one signal input and one signal output; (b) input gate area >= needed; (c) not on the don't-use list;
# 071: (d) the signal pin names are the same as those of the cell being replaced (so every connection can stay); (e) the same height as the cell being replaced.
# 071: rows: dict name area w h gate verdict why. Smallest listed gate value is used (conservative).
proc ant071_eval_inverters {lef names dont_patterns needed old_pins old_h} {
    set rows {}
    foreach name [lsort $names] {
        if {![dict exists $lef $name]} {
            lappend rows [dict create name $name area 0 w 0 h 0 gate 0 verdict FAIL why "no MACRO in the LEF"]
            continue
        }
        set c [dict get $lef $name]
        set w [dict get $c w]
        set h [dict get $c h]
        set area [expr {($w eq "" || $h eq "") ? 0.0 : $w * $h}]
        set ins {}
        set outs {}
        dict for {pn pd} [dict get $c pins] {
            set use [dict get $pd use]
            set dir [dict get $pd dir]
            if {$use eq "POWER" || $use eq "GROUND" || $dir eq "INOUT"} continue
            if {$dir eq "INPUT"} { lappend ins $pn }
            if {$dir eq "OUTPUT"} { lappend outs $pn }
        }
        set gate 0.0
        set why {}
        if {[llength $ins] != 1 || [llength $outs] != 1} {
            lappend why "(a) [llength $ins] signal inputs and [llength $outs] outputs"
        } else {
            set gate [ant_min_or_zero [dict get $c pins [lindex $ins 0] gate]]
            if {$gate < $needed} { lappend why "(b) input gate [format %.3f $gate] < needed [format %.3f $needed]" }
            if {[lsort [concat $ins $outs]] ne [lsort $old_pins]} { lappend why "(d) pins {[concat $ins $outs]} differ from {$old_pins}" }
        }
        set du [ant_dont_use $name $dont_patterns]
        if {$du ne ""} { lappend why "(c) on the don't-use list ($du)" }
        if {$h ne "" && $old_h ne "" && abs($h - $old_h) > 1e-6} { lappend why "(e) height $h != $old_h" }
        lappend rows [dict create name $name area $area w $w h $h gate $gate verdict [expr {[llength $why] ? "FAIL" : "PASS"}] why [join $why "; "]]
    }
    return $rows
}

# 071: the passing inverter with the smallest gate area; ties: smaller footprint, then name. "" when none passes.
proc ant071_pick_inverter {rows} {
    set best ""
    set bg 0
    set ba 0
    foreach nm [lsort [lmap r $rows {dict get $r name}]] {
        foreach r $rows {
            if {[dict get $r name] ne $nm || [dict get $r verdict] ne "PASS"} continue
            set g [dict get $r gate]
            set a [dict get $r area]
            if {$best eq "" || $g < $bg - 1e-9 || (abs($g - $bg) <= 1e-9 && $a < $ba - 1e-9)} { set best $nm; set bg $g; set ba $a }
        }
    }
    return $best
}

# 071: the `n` largest input gate areas among the one-in-one-out rows (for the error message when nothing reaches the need): list of "name gate"
proc ant071_largest_gates {rows n} {
    set l {}
    foreach r $rows { if {[dict get $r gate] > 0} { lappend l [list [dict get $r name] [dict get $r gate]] } }
    set l [lsort -decreasing -real -index 1 $l]
    return [lmap e [lrange $l 0 [expr {$n - 1}]] {format "%s %.3f" [lindex $e 0] [lindex $e 1]}]
}

# 071: do filler rows {name x0 y0 x1 y1 orient} cover the x interval [xa, xb] of the row starting at y0 without gap? Returns {ok names uncovered_from}:
# 071: names = every filler of that row overlapping the interval; uncovered_from = x where the coverage first breaks ("" when ok).
proc ant071_cover {rows y0 xa xb {tol 0.001}} {
    set inrow {}
    foreach r $rows {
        lassign $r name x0 ry0 x1 ry1
        if {abs($ry0 - $y0) <= $tol && $x1 > $xa + $tol && $x0 < $xb - $tol} { lappend inrow $r }
    }
    set inrow [lsort -real -index 1 $inrow]
    set pos $xa
    set names {}
    foreach r $inrow {
        lassign $r name x0 ry0 x1 ry1
        if {$x0 > $pos + $tol} { return [list 0 $names $pos] }
        lappend names $name
        if {$x1 > $pos} { set pos $x1 }
    }
    if {$pos < $xb - $tol} { return [list 0 $names $pos] }
    return [list 1 $names ""]
}

# 071: room for a cell that grows from the old box [x0,x1] (row y0) to width neww. Returns a dict: mode none|right|left|FAIL, origin (new lower-left x), names (fillers to remove), why.
# 071: right: the extra width is taken from the fillers to the right of the old box; left: from the fillers to the left (the cell then moves left by the extra width).
proc ant071_grow_plan {rows y0 x0 x1 neww {tol 0.001}} {
    set extra [expr {$neww - ($x1 - $x0)}]
    if {$extra <= $tol} { return [dict create mode none origin $x0 names {} why "no extra width needed"] }
    lassign [ant071_cover $rows $y0 $x1 [expr {$x0 + $neww}] $tol] okr nr ur
    if {$okr} { return [dict create mode right origin $x0 names $nr why "extra [format %.3f $extra] um taken from the fillers on the right"] }
    lassign [ant071_cover $rows $y0 [expr {$x0 - $extra}] $x0 $tol] okl nl ul
    if {$okl} { return [dict create mode left origin [expr {$x0 - $extra}] names $nl why "extra [format %.3f $extra] um taken from the fillers on the left"] }
    return [dict create mode FAIL origin $x0 names {} why "a cell other than a filler is in the way: right side not covered by fillers from x=$ur, left side from x=$ul"]
}

# 071: guess-parser for `report_clock_qor -type summary` (VERIFY the wording on the server): returns a dict with skew (largest "global skew" number in the text),
# 071: trans / cap (transition / capacitance DRC violation counts) and sinks; a value is "" when the text has no such line.
proc ant071_parse_cqor {text} {
    set skew ""
    set trans ""
    set cap ""
    set sinks ""
    foreach l [split $text "\n"] {
        if {[regexp -nocase -- {global\s+skew\D*(-?[0-9]*\.?[0-9]+)} $l -> v]} { if {$skew eq "" || $v > $skew} { set skew $v } }
        if {[regexp -nocase -- {transition[^0-9\n]*(violation|drc)[^0-9\n]*([0-9]+)} $l -> k v]} { set trans $v }
        if {[regexp -nocase -- {capacitance[^0-9\n]*(violation|drc)[^0-9\n]*([0-9]+)} $l -> k v]} { set cap $v }
        if {[regexp -nocase -- {(clock\s+)?sinks?\D*([0-9][0-9,]*)} $l -> k v]} { if {$sinks eq ""} { set sinks [string map {, {}} $v] } }
    }
    return [dict create skew $skew trans $trans cap $cap sinks $sinks]
}

# 071: before / after dicts with skew setup hold trans cap (numbers or ""). Returns {verdict reasons}: WORSE when a readable metric trips its tolerance,
# 071: else UNKNOWN when some metric is unreadable, else OK. Tolerances: skew growth > skew_tol, setup or hold WNS lower by more than wns_tol,
# 071: transition or capacitance violations after > before.
proc ant071_verdict {before after skew_tol wns_tol} {
    set worse {}
    set unread {}
    foreach m {skew setup hold trans cap} {
        set b [dict get $before $m]
        set a [dict get $after $m]
        if {![string is double -strict $b] || ![string is double -strict $a]} { lappend unread $m; continue }
        switch $m {
            skew  { if {$a - $b > $skew_tol + 1e-9} { lappend worse "global skew [format %.3f $b] -> [format %.3f $a] (limit +$skew_tol)" } }
            setup - hold { if {$a < $b - $wns_tol - 1e-9} { lappend worse "$m WNS [format %.4f $b] -> [format %.4f $a] (limit -$wns_tol)" } }
            trans { if {$a > $b} { lappend worse "max-transition violations $b -> $a" } }
            cap   { if {$a > $b} { lappend worse "max-capacitance violations $b -> $a" } }
        }
    }
    if {[llength $worse]} { return [list WORSE $worse] }
    if {[llength $unread]} { return [list UNKNOWN "unreadable: [join $unread {, }]"] }
    return [list OK {}]
}

# 071: compare two lists of {pin net} (before / after the size change): returns the list of differences ("" = identical)
proc ant071_diff_pins {before after} {
    array set b {}
    array set a {}
    foreach e $before { set b([lindex $e 0]) [lindex $e 1] }
    foreach e $after  { set a([lindex $e 0]) [lindex $e 1] }
    set diff {}
    foreach p [lsort -unique [concat [array names b] [array names a]]] {
        if {![info exists b($p)]} { lappend diff "pin $p new (net $a($p))"; continue }
        if {![info exists a($p)]} { lappend diff "pin $p gone (was net $b($p))"; continue }
        if {$a($p) ne $b($p)} { lappend diff "pin $p: net $b($p) -> $a($p)" }
    }
    return $diff
}
# ---- END PURE TCL 071 ----

# 071: take the pure-Tcl block and the ICC2 helper procs of antenna_port_buffers.tcl from its text (same code, no copy)
set fp [open ${SCRIPT_DIR}/antenna_port_buffers.tcl r]
set cr_src [read $fp]
close $fp
set cr_b [string first "# ---- BEGIN PURE TCL 068 ----" $cr_src]
set cr_e [string first "# ---- END PURE TCL 068 ----" $cr_src]
set cr_h [string first "# 068: ICC2 side helpers" $cr_src]
set cr_f [string first "file mkdir \$LOG_DIR" $cr_src]
if {$cr_b < 0 || $cr_e < 0 || $cr_h < 0 || $cr_f < 0 || $cr_f <= $cr_h} { error "ERROR 071: markers not found in ${SCRIPT_DIR}/antenna_port_buffers.tcl" }
eval [string range $cr_src $cr_b $cr_e]
eval [string range $cr_src $cr_h [expr {$cr_f - 1}]]

# 071: ICC2 side helpers of this script (not tested locally)
proc ant071_metrics {label root_cell setup_scen hold_scen} {   ;# 071: numbers for the verdict; the raw reports are printed so the user can read them
    update_timing -full
    set out [dict create skew "" setup "" hold "" trans "" cap "" sinks ""]
    if {[catch {redirect -variable cr_cq { report_clock_qor -type summary }} err]} {   ;# 071: VERIFY report_clock_qor -type summary (usage text)
        puts ">>> 071 $label report_clock_qor failed: $err"
    } else {
        puts ">>> 071 $label ===== report_clock_qor -type summary ====="
        puts $cr_cq
        set out [ant071_parse_cqor $cr_cq]   ;# 071: VERIFY the wording of "global skew" and the DRC violation lines
    }
    puts ">>> 071 $label ===== report_global_timing ====="
    report_global_timing
    foreach {key scen dt} [list setup $setup_scen max hold $hold_scen min] {
        if {[catch {
            set p [get_timing_paths -scenarios $scen -delay_type $dt -max_paths 1]
            if {[sizeof_collection $p] > 0} { dict set out $key [get_attribute $p slack] }
        } err]} { puts ">>> 071 $label $key WNS unavailable: $err" }
    }
    if {[catch {
        puts ">>> 071 $label ===== report_clock_timing -type transition through the root cell ====="
        report_clock_timing -type transition -scenarios $setup_scen -through $root_cell -nworst 3 -significant_digits 4   ;# 071: VERIFY: transition at the root cell pins (the root's own delay is in the clock latency reports above)
    } err]} { puts ">>> 071 $label root transition report failed: $err" }
    puts ">>> 071 $label METRICS: global skew [dict get $out skew] ns, sinks [dict get $out sinks], setup WNS [dict get $out setup] ns ($setup_scen), hold WNS [dict get $out hold] ns ($hold_scen), max-transition violations [dict get $out trans], max-capacitance violations [dict get $out cap]"
    return $out
}
proc ant071_pin_nets {cell} {   ;# 071: {pin net} for every pin of a cell, power pins included
    set out {}
    foreach_in_collection p [get_pins -quiet -of_objects $cell] {
        set nc [get_nets -quiet -of_objects $p]
        lappend out [list [lindex [split [get_object_name $p] /] end] [expr {[sizeof_collection $nc] ? [get_object_name $nc] : {-}}]]   ;# 071: pin name = the part of the pin's full name after the last /
    }
    return $out
}
proc ant071_net_layer_length {netname} {   ;# 071: {layer total_length_um shapes} per routing layer of a net (information; the sum of the longer side of each shape)
    set out {}
    foreach l {M1 M2 M3 TOP_M} {
        set tot 0.0
        set cnt 0
        foreach s [ant068_net_shapes $netname $l] {
            lassign [lrange $s 1 4] a b c d
            set tot [expr {$tot + max($c - $a, $d - $b)}]
            incr cnt
        }
        lappend out [list $l [format %.1f $tot] $cnt]
    }
    return $out
}

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/6d_antenna_clk_root.log {

    set cr_failures {}

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }
    set open_lib [get_libs -quiet *]
    if {[sizeof_collection $open_lib] > 0} {
        foreach_in_collection lib_obj $open_lib {
            close_lib -force $lib_obj
        }
    }

    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    open_block ${DESIGN_NAME}.dlib:${DESIGN_NAME}_route
    current_block ${DESIGN_NAME}_route
    link_block
    puts ">>> 071 block ${DESIGN_NAME}_route opened (it is overwritten in place at the end; the README tells the user to back up the library first)"

    # Allow clock nets to be routed up to TOP_M, as route.tcl and fix_antenna.tcl do (a routing rule, not a timing option)
    set_clock_routing_rules \
        -default_rule \
        -min_routing_layer M2 \
        -max_routing_layer TOP_M

    # --------------------------------------------------------------------------
    # 1. Antenna database and polygon -> net (same functions as antenna_port_buffers.tcl)
    # --------------------------------------------------------------------------
    if {![file exists $ANT_DB]} { error "ERROR 071: Cannot find the Calibre antenna DB at $ANT_DB (README step 6d copies the NEW run's unpu_top.ant.db there)" }
    set fp [open $ANT_DB r]
    set cr_db [ant_parse_db [read $fp]]
    close $fp
    set cr_polys [dict get $cr_db polys]
    puts ">>> 071 database $ANT_DB: top '[dict get $cr_db top]', [dict get $cr_db dbu] units per um, [llength $cr_polys] polygons"
    if {[llength $cr_polys] == 0} { error "ERROR 071: the database holds no polygon, nothing to do" }

    array set cr_port_of_net {}
    array set cr_port_dir {}
    foreach_in_collection p [get_ports -quiet *] {
        set pn [get_object_name $p]
        if {[lsearch -exact $POWER_PORT_NAMES $pn] >= 0} continue
        set nc [get_nets -quiet -of_objects $p]   ;# 068: VERIFY get_nets -of_objects <port> returns exactly one net
        if {[sizeof_collection $nc] != 1} continue
        set cr_port_of_net([get_object_name $nc]) $pn
        set cr_port_dir($pn) [get_attribute -quiet $p direction]
    }
    puts ">>> 071 port nets: [array size cr_port_of_net]"

    set cr_layers {}
    foreach p $cr_polys {
        set l [ant_rule_layer [dict get $p rule]]
        if {$l ne "" && [lsearch -exact $cr_layers $l] < 0} { lappend cr_layers $l }
    }
    array set cr_shapes {}
    foreach l $cr_layers {
        set cr_shapes($l) {}
        foreach nn [lsort [array names cr_port_of_net]] { set cr_shapes($l) [concat $cr_shapes($l) [ant068_net_shapes $nn $l]] }
        puts ">>> 071   layer $l: [llength $cr_shapes($l)] port-net shapes"
    }

    set cr_clk_ports {}
    foreach_in_collection c [get_clocks -quiet -filter "is_virtual == false"] {
        foreach_in_collection s [get_attribute -quiet $c sources] { lappend cr_clk_ports [get_object_name $s] }   ;# 068: VERIFY the `sources` attribute of a clock
    }
    puts ">>> 071 clock source ports: $cr_clk_ports"

    array set cr_net_polys {}      ;# net -> list of {tag perimeter weight_layer layer}
    set cr_unresolved {}
    foreach p $cr_polys {
        set rule [dict get $p rule]
        set pid  [dict get $p id]
        lassign [dict get $p bbox] x0 y0 x1 y1
        set lyr [ant_rule_layer $rule]
        set tag "$rule #$pid"
        if {$lyr eq ""} { puts ">>> 071 POLY $tag UNRESOLVED: not a metal-area rule"; lappend cr_unresolved "$tag: rule without a layer"; continue }
        set cands {}
        foreach s $cr_shapes($lyr) {
            lassign [lrange $s 1 4] sx0 sy0 sx1 sy1
            if {$sx1 >= $x0 && $sx0 <= $x1 && $sy1 >= $y0 && $sy0 <= $y1} { lappend cands $s }
        }
        set win [list [list [expr {$x0 - 0.05}] [expr {$y0 - 0.05}]] [list [expr {$x1 + 0.05}] [expr {$y1 + 0.05}]]]
        foreach_in_collection s [get_shapes -quiet -intersect $win -filter "layer.name == $lyr"] {   ;# 068: unreliable alone (handoff 18.26); only extra competitors
            set nc [get_nets -quiet -of_objects $s -filter "net_type == signal || net_type == clock"]
            if {[sizeof_collection $nc] == 0} continue
            set nn [get_object_name [index_collection $nc 0]]
            if {[array names cr_port_of_net -exact $nn] ne ""} continue
            lappend cands [concat [list $nn] [ant068_bbox_of $s]]
        }
        set ranks [ant_rank $p $cands $TOL_UM]
        lassign [ant_decide $ranks $MARGIN_SCORE $MIN_COVER] st chosen note
        if {$st eq "OK" && [array names cr_port_of_net -exact $chosen] eq ""} { set st NONPORT; set note "best net $chosen is not connected to a port ($note)"; set chosen "" }
        set top3 {}
        foreach r [lrange $ranks 0 2] { lappend top3 "[lindex $r 0]:t[lindex $r 1]:[format %.2f [lindex $r 2]]" }
        set per [ant071_perimeter [dict get $p xs] [dict get $p ys]]
        puts ">>> 071 POLY $tag layer $lyr bbox=($x0,$y0)->($x1,$y1) vertices [dict get $p nv] perimeter [format %.3f $per] um ranks=[join $top3 { }] chosen=[expr {$chosen eq {} ? {none} : $chosen}] status=$st ($note)"
        if {$st ne "OK"} { lappend cr_unresolved "$tag: $st, $note"; continue }
        lappend cr_net_polys($chosen) [list $tag $per $lyr]
    }
    foreach u $cr_unresolved { puts ">>> 071 UNRESOLVED $u" }
    if {[llength $cr_unresolved] > 0} { error "ERROR 071: [llength $cr_unresolved] polygon(s) could not be assigned to a port net (listed above). Nothing was changed." }

    set cr_clk_nets {}
    foreach n [lsort [array names cr_net_polys]] {
        set pn $cr_port_of_net($n)
        set nt [get_attribute -quiet [get_nets -quiet -exact $n] net_type]
        if {[lsearch -exact $cr_clk_ports $pn] >= 0 || $nt eq "clock"} { lappend cr_clk_nets $n } else { lappend cr_unresolved "net $n (port $pn) is not a clock-source net" }
    }
    puts ">>> 071 nets in the database: [lsort [array names cr_net_polys]]; clock-source nets: $cr_clk_nets"
    if {[llength $cr_unresolved] > 0} { error "ERROR 071: the database holds non-clock port nets: [join $cr_unresolved {; }]. This script handles only clock-source port nets; run antenna_port_buffers.tcl for the others. Nothing was changed." }
    if {[llength $cr_clk_nets] != 1} { error "ERROR 071: expected exactly one clock-source port net in the database, found [llength $cr_clk_nets]: $cr_clk_nets. Nothing was changed." }
    set cr_net [lindex $cr_clk_nets 0]
    set cr_port $cr_port_of_net($cr_net)

    # --------------------------------------------------------------------------
    # 2. The root cell: the single leaf load of the clock port net
    # --------------------------------------------------------------------------
    set cr_loads [ant068_net_leaf_pins $cr_net]
    puts ">>> 071 leaf pins on net $cr_net: [llength $cr_loads] $cr_loads"
    if {[llength $cr_loads] != 1} { error "ERROR 071: the clock port net $cr_net has [llength $cr_loads] leaf loads, 1 expected (the CTS root). Nothing was changed." }
    set cr_rootpin [lindex $cr_loads 0]
    set cr_cellc [get_cells -quiet -of_objects [get_pins -quiet -exact $cr_rootpin]]   ;# 071: VERIFY get_cells -of_objects <pin>
    if {[sizeof_collection $cr_cellc] != 1} { error "ERROR 071: cannot find the cell of pin $cr_rootpin" }
    set cr_root [get_object_name $cr_cellc]
    set cr_oldref [get_attribute -quiet $cr_cellc ref_name]
    lassign [ant068_bbox_of $cr_cellc] rx0 ry0 rx1 ry1
    set cr_ori [get_attribute -quiet $cr_cellc orientation]   ;# 071: VERIFY orientation of a standard cell (N / FS / MX ...)
    set t [get_terminals -quiet -of_objects [get_ports -quiet -exact $cr_port]]
    lassign [ant068_centre [index_collection $t 0]] cpx cpy
    lassign [ant068_centre [get_pins -quiet -exact $cr_rootpin]] lpx lpy
    set cr_dist [ant_manhattan $cpx $cpy $lpx $lpy]
    puts ">>> 071 ROOT cell $cr_root: reference $cr_oldref, box ([format %.3f $rx0], [format %.3f $ry0])->([format %.3f $rx1], [format %.3f $ry1]), orientation $cr_ori; input pin at ([format %.2f $lpx], [format %.2f $lpy]); clock pin at ([format %.2f $cpx], [format %.2f $cpy]); Manhattan distance [format %.1f $cr_dist] um"
    puts ">>> 071 net $cr_net routing before the change (layer, total length um, shapes): [ant071_net_layer_length $cr_net]"
    set cr_pins_before [ant071_pin_nets $cr_cellc]
    puts ">>> 071 ROOT pin connections before: $cr_pins_before"
    set cr_outpins [get_pins -quiet -of_objects $cr_cellc -filter "direction == out"]   ;# 068: VERIFY pin attribute direction == out
    if {[sizeof_collection $cr_outpins] != 1} { error "ERROR 071: the root cell has [sizeof_collection $cr_outpins] output pins, 1 expected" }
    set cr_outnet [get_object_name [get_nets -quiet -of_objects $cr_outpins]]
    puts ">>> 071 ROOT output net: $cr_outnet ([llength [ant068_net_leaf_pins $cr_outnet]] leaf pins)"

    # --------------------------------------------------------------------------
    # 3. Gate area needed
    # --------------------------------------------------------------------------
    set cr_weight(M2) $ANT_WEIGHT_M2
    set cr_weight(M3) $ANT_WEIGHT_M3
    set cr_weight(TOP_M) $ANT_WEIGHT_TOPM
    set cr_limit $ANT_RATIO_LIMIT
    set cr_src "parameters at the top of the script (Calibre log text of task 071)"
    if {[file exists $ANT_DECK]} {
        set fp [open $ANT_DECK r]
        set cr_deck [read $fp]
        close $fp
        foreach {rule lay} {AN.MTL.1.M3 M3 AN.MTL.1.M2 M2 AN.MTL.1.MT TOP_M} {
            set f [ant071_parse_rule_formula $cr_deck $rule]
            if {$f eq ""} { puts ">>> 071 deck $ANT_DECK: no formula found for $rule, parameter used for $lay"; continue }
            if {abs([lindex $f 0] - $cr_weight($lay)) > 1e-9 || abs([lindex $f 1] - $cr_limit) > 1e-9} {
                puts ">>> 071 deck says $rule: weight [lindex $f 0], limit [lindex $f 1]; the parameters say weight $cr_weight($lay), limit $cr_limit; THE DECK VALUE IS USED"
            } else {
                puts ">>> 071 deck $rule: weight [lindex $f 0], limit [lindex $f 1] (equal to the parameters)"
            }
            set cr_weight($lay) [lindex $f 0]
            set cr_limit [lindex $f 1]
            set cr_src "the deck $ANT_DECK"
        }
    } else {
        puts ">>> 071 deck $ANT_DECK not readable here: weights and limit come from the $cr_src"
    }
    puts ">>> 071 weights: M2 $cr_weight(M2), M3 $cr_weight(M3), TOP_M $cr_weight(TOP_M); limit $cr_limit; margin $GATE_MARGIN; source: $cr_src"
    set cr_needed 0.0
    foreach pl $cr_net_polys($cr_net) {
        lassign $pl tag per lyr
        if {![info exists cr_weight($lyr)]} { error "ERROR 071: no antenna weight for layer $lyr (polygon $tag)" }
        set nd [ant071_needed_gate $per $cr_weight($lyr) $cr_limit $GATE_MARGIN]
        set nd0 [ant071_needed_gate $per $cr_weight($lyr) $cr_limit 1.0]
        set ndt [ant071_needed_gate $per $cr_weight(TOP_M) $cr_limit $GATE_MARGIN]
        puts ">>> 071 NEED $tag: perimeter [format %.3f $per] um x weight $cr_weight($lyr) / $cr_limit = [format %.4f $nd0] um^2, with margin $GATE_MARGIN = [format %.4f $nd] um^2; the same polygon at the TOP_M weight $cr_weight(TOP_M) would need [format %.4f $ndt] um^2"
        if {$nd > $cr_needed} { set cr_needed $nd }
    }
    puts ">>> 071 gate area needed (largest over the polygons of net $cr_net): [format %.4f $cr_needed] um^2"

    # --------------------------------------------------------------------------
    # 4. The replacement inverter, chosen from the LEF
    # --------------------------------------------------------------------------
    if {![file exists $STD_LEF]} { error "ERROR 071: kit LEF not found at $STD_LEF" }
    set fp [open $STD_LEF r]
    set cr_lef [ant_parse_lef [read $fp]]
    close $fp
    if {![dict exists $cr_lef $cr_oldref]} { error "ERROR 071: the root's reference $cr_oldref is not in the LEF" }
    set cr_old_pins {}
    dict for {pn pd} [dict get $cr_lef $cr_oldref pins] {
        if {[dict get $pd use] eq "POWER" || [dict get $pd use] eq "GROUND" || [dict get $pd dir] eq "INOUT"} continue
        lappend cr_old_pins $pn
    }
    set cr_old_h [dict get $cr_lef $cr_oldref h]
    set cr_old_w [dict get $cr_lef $cr_oldref w]
    set cr_old_gate 0.0
    dict for {pn pd} [dict get $cr_lef $cr_oldref pins] { if {[dict get $pd dir] eq "INPUT" && [dict get $pd use] ne "POWER"} { set cr_old_gate [ant_min_or_zero [dict get $pd gate]] } }
    puts ">>> 071 current root $cr_oldref: ${cr_old_w} x ${cr_old_h} um, signal pins $cr_old_pins, input gate [format %.3f $cr_old_gate] um^2 (ratio at the polygon perimeter: [format %.0f [expr {[lindex [lindex $cr_net_polys($cr_net) 0] 1] * $cr_weight(M3) / ($cr_old_gate > 0 ? $cr_old_gate : 1e-9)}]])"

    set cr_method "attribute is_inverter == true"
    set cr_invnames {}
    set cr_libof {}
    if {[catch {set cr_lc [get_lib_cells -quiet ${STD_LIB}/* -filter "is_inverter == true"]} err] || [sizeof_collection $cr_lc] == 0} {   ;# 071: VERIFY lib_cell attribute is_inverter
        puts ">>> 071 is_inverter filter unavailable or empty ([expr {[info exists err] ? $err : {no cell}}]); FALLBACK: is_buffer == false and the kit's inverter name pattern inv*/clkinv*, then the LEF test (one input, one output) decides"
        set cr_method "FALLBACK is_buffer == false and name inv*/clkinv*"
        set cr_lc [get_lib_cells -quiet [list ${STD_LIB}/inv* ${STD_LIB}/clkinv*] -filter "is_buffer == false"]
    }
    foreach_in_collection lc $cr_lc {
        set full [get_object_name $lc]
        set short [lindex [split $full /] end]
        if {[get_attribute -quiet $lc dont_use] eq "true"} { puts ">>> 071   $short: dont_use attribute is true in the library, skipped"; continue }
        lappend cr_invnames $short
        lappend cr_libof $short $full
    }
    puts ">>> 071 inverter selection method: $cr_method; [llength $cr_invnames] library inverters (not dont_use)"
    if {[llength $cr_invnames] == 0} { error "ERROR 071: no inverter cell found in ${STD_LIB}" }
    set cr_rows [ant071_eval_inverters $cr_lef $cr_invnames $DONT_USE_PATTERNS $cr_needed $cr_old_pins $cr_old_h]
    puts ">>> 071 candidate table (name, footprint um^2, input gate um^2, verdict, reason); needed gate [format %.4f $cr_needed] um^2:"
    foreach r [lsort -real -index 2 [lmap r $cr_rows {list [dict get $r name] [dict get $r verdict] [dict get $r gate] [dict get $r area] [dict get $r why]}]] {
        puts [format ">>> 071   %-12s area %8.2f  gate %7.3f  %s  %s" [lindex $r 0] [lindex $r 3] [lindex $r 2] [lindex $r 1] [lindex $r 4]]
    }
    set cr_new [ant071_pick_inverter $cr_rows]
    if {$cr_new eq ""} {
        error "ERROR 071: no inverter reaches the needed gate area [format %.4f $cr_needed] um^2. The five largest input gate areas found: [join [ant071_largest_gates $cr_rows 5] {, }]. Decide between a buffer at the pin and a waiver. Nothing was changed."
    }
    if {$cr_new eq $cr_oldref} { error "ERROR 071: the chosen inverter is the current root reference $cr_oldref; nothing to change (is the database current?)" }
    foreach r $cr_rows { if {[dict get $r name] eq $cr_new} { set cr_new_row $r } }
    set cr_new_lc [dict get $cr_libof $cr_new]
    set cr_new_w [dict get $cr_new_row w]
    puts ">>> 071 CHOSEN $cr_new_lc: smallest input gate area that reaches the need ([format %.3f [dict get $cr_new_row gate]] um^2 >= [format %.4f $cr_needed]; ties: smaller footprint, then name); footprint [format %.2f [dict get $cr_new_row area]] um^2, width ${cr_new_w} um (old ${cr_old_w}); predicted ratio on the current polygon [format %.0f [expr {[lindex [lindex $cr_net_polys($cr_net) 0] 1] * $cr_weight(M3) / [dict get $cr_new_row gate]}]]"
    set cr_old_inv [get_attribute -quiet $cr_cellc is_inverter]
    puts ">>> 071 polarity: the current root cell attribute is_inverter = '$cr_old_inv'; the replacement was selected among inverters ($cr_method)"

    # --------------------------------------------------------------------------
    # 5. BEFORE
    # --------------------------------------------------------------------------
    set cr_before [ant071_metrics BEFORE $cr_root $SETUP_SCEN $HOLD_SCEN]
    set cr_cr0 [ant068_check_routes_counts]
    puts ">>> 071 check_routes BEFORE: DRCs [lindex $cr_cr0 0], open nets [lindex $cr_cr0 1], ICC2 antenna violations [lindex $cr_cr0 2]"

    # --------------------------------------------------------------------------
    # 6. Room for the larger cell, size-only change, placement
    # --------------------------------------------------------------------------
    set cr_filter {}
    foreach f $FILLER_REFS { lappend cr_filter "ref_name == $f" }
    set cr_filter [join $cr_filter " || "]
    set cr_t0 [clock seconds]
    set cr_ftable [ant070_all_fillers $cr_filter]   ;# 070: all fillers once, no geometric query (get_cells -intersect returns only the window border cells, task 070)
    puts ">>> 071 filler table: [llength $cr_ftable] filler instances in [expr {[clock seconds] - $cr_t0}] s"
    set cr_plan [ant071_grow_plan $cr_ftable $ry0 $rx0 $rx1 $cr_new_w]
    puts ">>> 071 PLAN mode [dict get $cr_plan mode], new origin x [format %.3f [dict get $cr_plan origin]], fillers to remove [llength [dict get $cr_plan names]] [dict get $cr_plan names]: [dict get $cr_plan why]"
    if {[dict get $cr_plan mode] eq "FAIL"} { error "ERROR 071: cannot make room for $cr_new_lc at $cr_root: [dict get $cr_plan why]. Nothing was changed." }

    set cr_rm [dict get $cr_plan names]
    if {[llength $cr_rm] > 0} {
        set flc [get_cells -quiet -exact $cr_rm]
        if {[sizeof_collection $flc] != [llength $cr_rm]} { error "ERROR 071: only [sizeof_collection $flc] of [llength $cr_rm] filler names found; nothing saved" }
        remove_cells $flc   ;# 069: VERIFY remove_cells on the filler instances (worked in the task 069/070 runs)
    }
    set cr_sized 0
    foreach cmd [list [list size_cell $cr_cellc $cr_new_lc] [list change_link $cr_cellc $cr_new_lc]] {   ;# 071: VERIFY size_cell, then change_link (neither is in the probed help); the first that works is used
        if {![catch {eval $cmd} err]} { puts ">>> 071 size-only change done with: [lindex $cmd 0]"; set cr_sized 1; break }
        puts ">>> 071 [lindex $cmd 0] failed: $err"
    }
    if {!$cr_sized} { error "ERROR 071: no command could change the reference of $cr_root (nothing saved)" }
    set cr_cellc [get_cells -exact $cr_root]
    if {[dict get $cr_plan mode] eq "left"} {
        if {[catch {set_cell_location -coordinates [list [dict get $cr_plan origin] $ry0] $cr_cellc} err]} { error "ERROR 071: cannot move $cr_root: $err (nothing saved)" }   ;# 068: set_cell_location worked on the server
    }
    legalize_placement -cells $cr_cellc   ;# 071: only this cell; at the planned site it must not move
    lassign [ant068_bbox_of $cr_cellc] nx0 ny0 nx1 ny1
    puts ">>> 071 root after: reference [get_attribute -quiet $cr_cellc ref_name], box ([format %.3f $nx0], [format %.3f $ny0])->([format %.3f $nx1], [format %.3f $ny1]), orientation [get_attribute -quiet $cr_cellc orientation]"
    if {[get_attribute -quiet $cr_cellc ref_name] ne $cr_new} { lappend cr_failures "reference is [get_attribute -quiet $cr_cellc ref_name], expected $cr_new" }
    if {abs($nx0 - [dict get $cr_plan origin]) > 0.001 || abs($ny0 - $ry0) > 0.001 || abs(($nx1 - $nx0) - $cr_new_w) > 0.001} {
        lappend cr_failures "the cell box is not the planned one: x0 [format %.3f $nx0] (planned [format %.3f [dict get $cr_plan origin]]), width [format %.3f [expr {$nx1 - $nx0}]] (expected $cr_new_w)"
    }
    if {[get_attribute -quiet $cr_cellc orientation] ne $cr_ori} { lappend cr_failures "orientation changed from $cr_ori to [get_attribute -quiet $cr_cellc orientation]" }

    set fill_cells [get_lib_cells -quiet [lmap f $FILLER_REFS {string cat ${FILLER_LIB}/ $f}]]   ;# same selection as route.tcl
    if {[sizeof_collection $fill_cells] == 0} { set fill_cells [get_lib_cells -quiet {*/feedth9 */feedth3 */feedth}] }
    if {[sizeof_collection $fill_cells] > 0} {
        create_stdcell_fillers -lib_cells $fill_cells   ;# as route.tcl: only empty sites are filled
    } else {
        lappend cr_failures "filler cells not found, the removed fillers are not restored"
    }
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]
    if {[llength $cr_failures] > 0} { error "ERROR 071: [llength $cr_failures] check(s) failed after the size change, NOTHING SAVED: [join $cr_failures {; }]" }

    # --------------------------------------------------------------------------
    # 7. Re-route the nets of the cell (the routes are NOT removed: route_eco keeps what is valid and connects the moved or enlarged pins)
    # --------------------------------------------------------------------------
    set cr_nets [get_nets -quiet -exact [list $cr_net $cr_outnet]]
    puts ">>> 071 nets to re-route: [get_object_name $cr_nets]"
    route_eco \
        -nets $cr_nets \
        -reuse_existing_global_route false \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 60
    route_detail -incremental true -max_number_iterations 40

    # --------------------------------------------------------------------------
    # 8. Checks, AFTER, verdict
    # --------------------------------------------------------------------------
    set cr_cr [ant068_check_routes_counts]
    set cr_drc [lindex $cr_cr 0]
    set cr_open [lindex $cr_cr 1]
    puts ">>> 071 check_routes AFTER: DRCs $cr_drc, open nets $cr_open, ICC2 antenna violations [lindex $cr_cr 2]"
    if {$cr_drc ne "" && $cr_drc > 0} {   ;# one more incremental pass before giving up
        route_detail -incremental true -max_number_iterations 40
        set cr_cr [ant068_check_routes_counts]
        set cr_drc [lindex $cr_cr 0]
        set cr_open [lindex $cr_cr 1]
        puts ">>> 071 check_routes after one more route_detail: DRCs $cr_drc, open nets $cr_open"
    }
    if {$cr_drc eq ""} { lappend cr_failures "check_routes DRC count not readable" } elseif {$cr_drc != 0} { lappend cr_failures "check_routes DRCs $cr_drc (0 required)" }
    if {$cr_open eq ""} { lappend cr_failures "check_routes open-net count not readable" } elseif {$cr_open != 0} { lappend cr_failures "check_routes open nets $cr_open (0 required)" }

    redirect -variable cr_leg_txt { check_legality -verbose }
    puts $cr_leg_txt
    set cr_leg [ant_parse_legality $cr_leg_txt]
    if {$cr_leg eq ""} { if {![catch {sizeof_collection [check_legality -cell_violation]} v]} { set cr_leg $v } }   ;# 068: VERIFY -cell_violation as the fallback when the text has no number
    puts ">>> 071 CHECK legality violations: [expr {$cr_leg eq {} ? {unreadable} : $cr_leg}] (0 required)"
    if {$cr_leg eq ""} { lappend cr_failures "check_legality result unreadable" } elseif {$cr_leg != 0} { lappend cr_failures "legality violations $cr_leg" }

    set cr_cellc [get_cells -quiet -exact $cr_root]
    if {[sizeof_collection $cr_cellc] != 1} {
        lappend cr_failures "cell $cr_root not found after the change"
    } else {
        set cr_pins_after [ant071_pin_nets $cr_cellc]
        puts ">>> 071 ROOT pin connections after: $cr_pins_after"
        set cr_diff [ant071_diff_pins $cr_pins_before $cr_pins_after]
        puts ">>> 071 CHECK pin connections: [expr {[llength $cr_diff] ? $cr_diff : {identical to before (every pin on the same net)}}]"
        if {[llength $cr_diff]} { lappend cr_failures "pin connections changed: [join $cr_diff {; }]" }
        puts ">>> 071 CHECK reference [get_attribute -quiet $cr_cellc ref_name] (expected $cr_new); is_inverter before '$cr_old_inv', after '[get_attribute -quiet $cr_cellc is_inverter]'"
        if {[get_attribute -quiet $cr_cellc ref_name] ne $cr_new} { lappend cr_failures "reference is not $cr_new" }
        if {[get_attribute -quiet $cr_cellc is_inverter] ne $cr_old_inv} { lappend cr_failures "polarity attribute is_inverter changed from '$cr_old_inv'" }   ;# 071: VERIFY the attribute (polarity unchanged)
    }
    set cr_loads2 [ant068_net_leaf_pins $cr_net]
    puts ">>> 071 CHECK leaf loads of $cr_net: [llength $cr_loads2] $cr_loads2 (only $cr_rootpin expected)"
    if {[llength $cr_loads2] != 1 || [lindex $cr_loads2 0] ne $cr_rootpin} { lappend cr_failures "clock port net leaf loads are $cr_loads2, expected only $cr_rootpin" }
    puts ">>> 071 net $cr_net routing after the change (layer, total length um, shapes): [ant071_net_layer_length $cr_net]"
    puts ">>> 071 (a re-route onto TOP_M would need [format %.4f [ant071_needed_gate [lindex [lindex $cr_net_polys($cr_net) 0] 1] $cr_weight(TOP_M) $cr_limit 1.0]] um^2 for the current perimeter; the new gate is [format %.3f [dict get $cr_new_row gate]] um^2)"

    set cr_after [ant071_metrics AFTER $cr_root $SETUP_SCEN $HOLD_SCEN]
    lassign [ant071_verdict $cr_before $cr_after $SKEW_TOL $WNS_TOL] cr_verdict cr_reasons
    puts ">>> 071 VERDICT $cr_verdict: [expr {[llength $cr_reasons] ? [join $cr_reasons {; }] : {no tolerance exceeded}}]"
    if {$cr_verdict eq "WORSE"} { puts ">>> 071 WORSE: the clock tree or the timing got worse because of the root change. The script still saves (it is a report, not a stop). To undo: restore the library backup (README step 6d) and tell Planning." }
    if {$cr_verdict eq "UNKNOWN"} { puts ">>> 071 UNKNOWN: some metrics could not be read from the reports ($cr_reasons); read the BEFORE / AFTER report texts above by hand before deciding." }

    if {[llength $cr_failures] > 0} {
        error "ERROR 071: [llength $cr_failures] check(s) failed, NOTHING SAVED: [join $cr_failures {; }]"
    }

    # --------------------------------------------------------------------------
    # 9. Save over _route (as fix_antenna.tcl) and finish
    # --------------------------------------------------------------------------
    save_block
    save_block -force -as ${DESIGN_NAME}_route
    save_lib
    puts ">>> STAGE 6d COMPLETE: clk root $cr_oldref -> $cr_new, instance $cr_root, verdict $cr_verdict, ${DESIGN_NAME}_route overwritten in place. Log: ${LOG_DIR}/6d_antenna_clk_root.log"
    puts ">>> 071 NEXT: metal_fill.tcl, pv.tcl, then a NEW Calibre antenna run (expect 0 results)."
}
