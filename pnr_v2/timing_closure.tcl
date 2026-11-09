# ==============================================================================
# Script: timing_closure.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/timing_closure.tcl   ;# 072: new script (flow step 6e, after antenna_clk_root.tcl, before metal_fill.tcl)
# Stage : Final timing pass after the antenna ECOs: route_opt again, ECO cells protected, fillers out of the way
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 072: THIS SCRIPT CAN CHANGE THE NETLIST: route_opt may resize cells and insert hold buffers. The PM must be told (the netlist written by pv.tcl differs from the one of step 6d).
# 072: why. The exported layout is DRC 0 and antenna 0 in Calibre, but setup WNS is -0.10 ns (2 in-to-out paths) and hold has 53 violations (worst -0.04 ns): route.tcl ended with
# 072: setup 0.00 / 15 hold violations, then the fillers, the route_eco steps and the antenna ECOs (fix passes, port buffers, clock root) moved both. This pass gives the optimiser
# 072: the SAME goals and options as route.tcl once more. No constraint, uncertainty, goal, SDC value, limit or app option is changed relative to route.tcl:
# 072: every block marked "route.tcl line N" below is copied from route.tcl (pnr_v2/test_timing_closure.tcl compares them line by line).
# 072: the antenna ECO cells exist only to satisfy the antenna rule, so they are PROTECTED (dont_touch on the cells and on their nets, fixed placement) and their snapshot
# 072: (reference, origin, orientation, pin connections) is compared after the pass: the 15 `antbuf_*` buffers and the root cell of the `clk` net.
# 072: the fillers occupy every free site, so they are removed during the pass (table method of task 070: get_cells -filter, no geometric query) and re-created as route.tcl does.
# 072: what it does, in order (every decision is printed with `>>> 072`):
# 072:   1 route.tcl settings   2 BEFORE metrics   3 protect the ECO cells   4 remove the fillers   5 route_opt passes (at most MAX_PASSES, stop rules printed)
# 072:   6 legalise, fillers, connect_pg_net, route_detail / route_eco, spec uncertainties restored   7 hard checks (nothing is saved on error)   8 AFTER metrics and verdict   9 save
# 072: every command or option not shown in a usage text in ~/server_pull/rpt/help (the real help of this tool version) is marked VERIFY.

set DESIGN_NAME "unpu_top"   ;# 072: design name (as the other scripts)
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"   ;# 072: ICC2 work directory (as the other scripts)
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set SCRIPT_DIR  "/storage/EE5239G1/aagams_workspace2/unpu/pnr_v2"   ;# 072: where antenna_port_buffers.tcl is: its ICC2 helper procs are read from its text, not copied
set STD_LEF     "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"   ;# 072: kit LEF (as pnr_v2/build_ndm_std.tcl): the filler master sizes
set STD_LIB     "scl180_std"
set FILLER_LIB  "scl180_filler"   ;# 072: as route.tcl
set FILLER_REFS {feedth feedth3 feedth9}   ;# 072: the filler masters route.tcl inserts

# 072: parameters of THIS script (nothing here changes what the optimiser is given)
set BUF_PREFIX      "antbuf"   ;# 072: instance name base of the port buffers made by antenna_port_buffers.tcl (BUF_PREFIX there)
set CLK_PORT        "clk"      ;# 072: the clock port; its net's single leaf load is the CTS root (antenna_clk_root.tcl)
set MAX_PASSES      3          ;# 072: route_opt passes at most (task 072)
set IMPROVE_EPS     0.001      ;# 072: a pass must improve the setup or the hold WNS by more than this (ns) or the loop stops
set WORSE_TOL       0.005      ;# 072: verdict WORSE when a WNS drops by more than this (ns)
set FILLER_TOL_PCT  1.0        ;# 072: the filler count after must be within this percent of the count before, or the site balance must explain the difference
set PROTECT_NETS    1          ;# 072: 1 = the nets of the protected cells are dont_touch too (the optimiser may not buffer them); 0 = cells only
set KEEP_PROTECTION 1          ;# 072: 1 = leave dont_touch / fixed on the protected cells in the saved block (later passes keep them); 0 = remove it before saving
set SETUP_SCEN      "func_ss"  ;# 072: scenario names of cts.tcl / route.tcl
set HOLD_SCEN       "func_ff"
set SETUP_GROUP     "in2out"   ;# 072: path group whose worst setup path is printed in full
set HOLD_GROUP      "reg2out"  ;# 072: path group whose worst hold path is printed in full

# ---- BEGIN PURE TCL 072 ----
# 072: everything between BEGIN and END is plain Tcl (no ICC2 command); pnr_v2/test_timing_closure.tcl extracts and tests exactly this text.

# 072: the loop decision after a pass. prev / cur: dicts with setup and hold (worst slack in ns, "" when unreadable). Returns {action reason}, action = continue | stop.
# 072: stop when a value is unreadable, when both are >= 0 (closed), when pass >= max_passes, or when neither WNS improved by more than eps.
proc ant072_pass_decision {pass max_passes prev cur eps} {
    foreach m {setup hold} {
        if {![string is double -strict [dict get $cur $m]]} { return [list stop "the $m WNS could not be read after pass $pass"] }
    }
    set s [dict get $cur setup]
    set h [dict get $cur hold]
    if {$s >= 0 && $h >= 0} { return [list stop "closed after pass $pass: setup WNS [format %.4f $s], hold WNS [format %.4f $h]"] }
    if {$pass >= $max_passes} { return [list stop "maximum of $max_passes passes reached (setup WNS [format %.4f $s], hold WNS [format %.4f $h])"] }
    set improved 0
    foreach m {setup hold} {
        set p [dict get $prev $m]
        if {[string is double -strict $p] && [dict get $cur $m] - $p > $eps} { set improved 1 }
    }
    if {!$improved} {
        return [list stop "pass $pass improved neither WNS by more than $eps ns (setup [format %.4f [dict get $prev setup]] -> [format %.4f $s], hold [format %.4f [dict get $prev hold]] -> [format %.4f $h])"]
    }
    return [list continue "pass $pass improved a WNS by more than $eps ns, next pass"]
}

# 072: worst slack to WNS: 0 when nothing violates
proc ant072_clamp {slack} {
    if {![string is double -strict $slack]} { return $slack }
    return [expr {min($slack, 0.0)}]
}

# 072: verdict from before / after dicts (setup, hold = worst slack in ns). UNKNOWN when a number is unreadable (never CLOSED then);
# 072: CLOSED when both are >= 0 after; WORSE when a WNS (0 when not violating) dropped by more than worse_tol; IMPROVED when none got worse and one improved by more than eps;
# 072: UNCHANGED otherwise (not in the task's list: it says nothing changed more than the tolerances).
proc ant072_verdict {before after worse_tol eps} {
    foreach m {setup hold} {
        if {![string is double -strict [dict get $before $m]] || ![string is double -strict [dict get $after $m]]} {
            return [list UNKNOWN "the $m WNS could not be read (before '[dict get $before $m]', after '[dict get $after $m]')"]
        }
    }
    if {[dict get $after setup] >= 0 && [dict get $after hold] >= 0} { return [list CLOSED "setup WNS [format %.4f [dict get $after setup]] and hold WNS [format %.4f [dict get $after hold]] are >= 0"] }
    set worse {}
    set better {}
    foreach m {setup hold} {
        set b [ant072_clamp [dict get $before $m]]
        set a [ant072_clamp [dict get $after $m]]
        if {$a < $b - $worse_tol - 1e-12} { lappend worse "$m WNS [format %.4f $b] -> [format %.4f $a]" }
        if {$a > $b + $eps} { lappend better "$m WNS [format %.4f $b] -> [format %.4f $a]" }
    }
    if {[llength $worse]} { return [list WORSE [join $worse {; }]] }
    if {[llength $better]} { return [list IMPROVED [join $better {; }]] }
    return [list UNCHANGED "neither WNS changed by more than $eps ns"]
}

# 072: snapshots of protected cells: a list of dicts: name ref x y ori pins ({{pin net} ...}). Differences between two snapshots (list of text lines, empty = identical).
proc ant072_snapshot_diff {before after {tol 0.001}} {
    array set a {}
    foreach s $after { set a([dict get $s name]) $s }
    set diff {}
    foreach b $before {
        set n [dict get $b name]
        if {![info exists a($n)]} { lappend diff "$n: cell is gone"; continue }
        set s $a($n)
        if {[dict get $s ref] ne [dict get $b ref]} { lappend diff "$n: reference [dict get $b ref] -> [dict get $s ref]" }
        if {abs([dict get $s x] - [dict get $b x]) > $tol || abs([dict get $s y] - [dict get $b y]) > $tol} {
            lappend diff "$n: origin ([dict get $b x], [dict get $b y]) -> ([dict get $s x], [dict get $s y])"
        }
        if {[dict get $s ori] ne [dict get $b ori]} { lappend diff "$n: orientation [dict get $b ori] -> [dict get $s ori]" }
        array unset pb
        array unset pa
        foreach e [dict get $b pins] { set pb([lindex $e 0]) [lindex $e 1] }
        foreach e [dict get $s pins] { set pa([lindex $e 0]) [lindex $e 1] }
        foreach p [lsort [array names pb]] {
            if {![info exists pa($p)]} { lappend diff "$n: pin $p is gone"; continue }
            if {$pa($p) ne $pb($p)} { lappend diff "$n: pin $p net $pb($p) -> $pa($p)" }
        }
        foreach p [lsort [array names pa]] { if {![info exists pb($p)]} { lappend diff "$n: new pin $p (net $pa($p))" } }
    }
    return $diff
}

# 072: filler check. count_*: number of filler instances; sites_*: total filler width in sites; cell_sites_added: sites taken by the standard cells added (negative when removed).
# 072: ok when the count is within tol_pct percent of the count before, or when the site balance explains the change: |(sites_after - sites_before) + cell_sites_added| <= tol_pct percent of sites_before.
# 072: returns {ok message}.
proc ant072_filler_check {count_before count_after sites_before sites_after cell_sites_added tol_pct} {
    if {$count_before <= 0} { return [list 0 "no filler before the pass"] }
    set dc [expr {$count_after - $count_before}]
    set pc [expr {100.0 * abs($dc) / $count_before}]
    if {$pc <= $tol_pct} { return [list 1 "filler count $count_before -> $count_after ([format %+d $dc], [format %.2f $pc] percent, within $tol_pct percent)"] }
    set resid [expr {($sites_after - $sites_before) + $cell_sites_added}]
    set pr [expr {100.0 * abs($resid) / $sites_before}]
    if {$pr <= $tol_pct} {
        return [list 1 "filler count $count_before -> $count_after ([format %+d $dc], [format %.2f $pc] percent) is explained by the site balance: filler sites [format %.0f $sites_before] -> [format %.0f $sites_after], cells added take [format %.0f $cell_sites_added] sites, residual [format %.0f $resid] sites ([format %.2f $pr] percent)"]
    }
    return [list 0 "filler count $count_before -> $count_after ([format %+d $dc], [format %.2f $pc] percent); the site balance does not explain it: filler sites [format %.0f $sites_before] -> [format %.0f $sites_after], cells added take [format %.0f $cell_sites_added] sites, residual [format %.0f $resid] sites ([format %.2f $pr] percent)"]
}
# ---- END PURE TCL 072 ----

# 072: take the ICC2 helper procs of antenna_port_buffers.tcl from its text (same code, no copy): ant068_bbox_of, ant068_centre, ant070_all_fillers, ant068_net_leaf_pins, ant068_check_routes_counts, ...
set fp [open ${SCRIPT_DIR}/antenna_port_buffers.tcl r]
set tc_src [read $fp]
close $fp
set tc_b [string first "# ---- BEGIN PURE TCL 068 ----" $tc_src]
set tc_e [string first "# ---- END PURE TCL 068 ----" $tc_src]
set tc_h [string first "# 068: ICC2 side helpers" $tc_src]
set tc_f [string first "file mkdir \$LOG_DIR" $tc_src]
if {$tc_b < 0 || $tc_e < 0 || $tc_h < 0 || $tc_f < 0 || $tc_f <= $tc_h} { error "ERROR 072: markers not found in ${SCRIPT_DIR}/antenna_port_buffers.tcl" }
eval [string range $tc_src $tc_b $tc_e]
eval [string range $tc_src $tc_h [expr {$tc_f - 1}]]

# 072: ICC2 side helpers of this script (not tested locally)
proc ant072_pin_nets {cell} {   ;# 072: {pin net} for every pin of a cell, power pins included; pin = the part of the full name after the last /
    set out {}
    foreach_in_collection p [get_pins -quiet -of_objects $cell] {
        set nc [get_nets -quiet -of_objects $p]
        lappend out [list [lindex [split [get_object_name $p] /] end] [expr {[sizeof_collection $nc] ? [get_object_name $nc] : {-}}]]
    }
    return $out
}
proc ant072_snapshot {cellname} {   ;# 072: dict name ref x y ori pins of one cell
    set c [get_cells -quiet -exact $cellname]
    if {[sizeof_collection $c] != 1} { return [dict create name $cellname ref "" x 1e9 y 1e9 ori "" pins {}] }
    lassign [ant068_bbox_of $c] x0 y0 x1 y1
    return [dict create name $cellname ref [get_attribute -quiet $c ref_name] x $x0 y $y0 ori [get_attribute -quiet $c orientation] pins [ant072_pin_nets $c]]
}
proc ant072_wns {scen dtype} {   ;# 072: {wns tns num groups} from get_timing_paths: wns = worst slack of all paths (positive when nothing violates), tns/num over the violating endpoints, groups = {{group wns tns num} ...}
    set wns ""
    set tns 0.0
    set num 0
    array set g {}
    if {[catch {
        set p [get_timing_paths -scenarios $scen -delay_type $dtype -max_paths 1]
        if {[sizeof_collection $p] > 0} { set wns [get_attribute $p slack] }
        set v [get_timing_paths -scenarios $scen -delay_type $dtype -max_paths 100000 -slack_lesser_than 0.0]   ;# 072: -slack_lesser_than is in the usage text
        foreach_in_collection q $v {
            set s [get_attribute $q slack]
            set tns [expr {$tns + $s}]
            incr num
            if {![catch {set gn [get_object_name [get_attribute $q path_group]]}]} {   ;# 072: VERIFY the path attribute path_group
                if {![info exists g($gn)]} { set g($gn) [list $s 0.0 0] }
                lassign $g($gn) gw gt gn2
                set g($gn) [list [expr {min($gw, $s)}] [expr {$gt + $s}] [expr {$gn2 + 1}]]
            }
        }
    } err]} {
        puts ">>> 072 WNS query failed for $scen $dtype: $err"
        return [list "" "" "" {}]
    }
    set groups {}
    foreach k [lsort [array names g]] { lappend groups [concat [list $k] $g($k)] }
    return [list $wns $tns $num $groups]
}
proc ant072_metrics {label} {   ;# 072: print and return the numbers of the verdict (dict setup hold, ...)
    global SETUP_SCEN HOLD_SCEN SETUP_GROUP HOLD_GROUP
    update_timing -full
    puts ">>> 072 $label ===== report_global_timing ====="
    report_global_timing
    lassign [ant072_wns $SETUP_SCEN max] sw st sn sg
    lassign [ant072_wns $HOLD_SCEN min] hw ht hn hg
    puts ">>> 072 $label SETUP ($SETUP_SCEN): WNS $sw ns, TNS [expr {$st eq {} ? {n/a} : [format %.4f $st]}] ns, violating endpoints $sn"
    foreach e $sg { puts ">>> 072 $label SETUP group [lindex $e 0]: WNS [format %.4f [lindex $e 1]] ns, TNS [format %.4f [lindex $e 2]] ns, violating endpoints [lindex $e 3]" }
    puts ">>> 072 $label HOLD ($HOLD_SCEN): WNS $hw ns, TNS [expr {$ht eq {} ? {n/a} : [format %.4f $ht]}] ns, violating endpoints $hn"
    foreach e $hg { puts ">>> 072 $label HOLD group [lindex $e 0]: WNS [format %.4f [lindex $e 1]] ns, TNS [format %.4f [lindex $e 2]] ns, violating endpoints [lindex $e 3]" }
    return [dict create setup $sw hold $hw setup_tns $st hold_tns $ht setup_num $sn hold_num $hn]
}
proc ant072_paths {label} {   ;# 072: the worst setup path of the in2out group and the worst hold path of reg2out in full
    global SETUP_SCEN HOLD_SCEN SETUP_GROUP HOLD_GROUP
    if {[catch {
        puts ">>> 072 $label ===== worst setup path, group $SETUP_GROUP ====="
        report_timing -scenarios $SETUP_SCEN -delay_type max -groups $SETUP_GROUP -max_paths 1 -path_type full_clock_expanded -significant_digits 4   ;# 072: VERIFY the group name
    } err]} { puts ">>> 072 $label setup path report failed: $err" }
    if {[catch {
        puts ">>> 072 $label ===== worst hold path, group $HOLD_GROUP ====="
        report_timing -scenarios $HOLD_SCEN -delay_type min -groups $HOLD_GROUP -max_paths 1 -path_type full_clock_expanded -significant_digits 4
    } err]} { puts ">>> 072 $label hold path report failed: $err" }
}
proc ant072_stats {label filler_filter nonfiller_filter site_w} {   ;# 072: cells (not fillers), area, buffers, inverters, fillers (count and sites); returns a dict
    set ncell 0
    set area 0.0
    foreach_in_collection c [get_cells -quiet -filter $nonfiller_filter] {   ;# 072: VERIFY the filter ref_name != ...
        incr ncell
        set a [get_attribute -quiet $c area]   ;# 072: VERIFY the cell attribute area
        if {[string is double -strict $a]} { set area [expr {$area + $a}] }
    }
    set nbuf [sizeof_collection [get_cells -quiet -filter "is_buffer == true"]]   ;# 072: VERIFY the cell attributes is_buffer / is_inverter
    set ninv [sizeof_collection [get_cells -quiet -filter "is_inverter == true"]]
    set fl [ant070_all_fillers $filler_filter]
    set fsites 0.0
    foreach r $fl { lassign $r nm x0 y0 x1 y1; set fsites [expr {$fsites + ($x1 - $x0) / $site_w}] }
    puts ">>> 072 $label CELLS: $ncell cells (fillers excluded), area [format %.2f $area] um^2, buffers $nbuf, inverters $ninv, fillers [llength $fl] ([format %.0f $fsites] sites)"
    return [dict create ncell $ncell area $area nbuf $nbuf ninv $ninv nfill [llength $fl] fsites $fsites]
}

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/6e_timing_closure.log {

    set tc_failures {}

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
    puts ">>> 072 block ${DESIGN_NAME}_route opened (it is overwritten in place at the end; the README tells the user to back up the library first)"

    # --------------------------------------------------------------------------
    # 1. The settings of route.tcl (copied, not retyped; the test compares them line by line)
    # --------------------------------------------------------------------------
    # 072: route.tcl lines 36-36, verbatim
    suppress_message {DCHK-027 DCHK-010 ATTR-12 PDC-003 ZRT-740 ZRT-027 POW-046 UIC-058 UIC-057}

    # 072: route.tcl lines 42-57, verbatim
   # 2. Restrict Routing to SCL 180nm 4-Metal Stack (M1 to TOP_M)
    set_ignored_layers \
        -min_routing_layer M1 \
        -max_routing_layer TOP_M

    # Allow clock nets (from CTS) to hop up to TOP_M to fix M3 antenna violations
    set_clock_routing_rules \
        -default_rule \
        -min_routing_layer M2 \
        -max_routing_layer TOP_M

    # Ensure Hold cells remain enabled for Post-Route Hold Optimization
    set hold_cells [get_lib_cells -quiet {scl180_std/*BUF* scl180_std/*INV* scl180_std/*DEL* scl180_std/*DLY* scl180_std/*buf* scl180_std/*inv* scl180_std/*del* scl180_std/*dly*}]
    if {[sizeof_collection $hold_cells] > 0} {
        set_lib_cell_purpose -include hold $hold_cells
    }

    # 072: the clock routing rule line as in antenna_clk_root.tcl: it is the same line as route.tcl line 48-51 above (kept there)

    # 072: route.tcl lines 59-83, verbatim
    set SPEC_SETUP_UNC   1.5   ;# 063 E9: old constraints, setup uncertainty 1.5 (the example had 0.15)
    set SETUP_SLACK_GOAL 0.0   ;# 065: user decision 2026-11-02, no extra margin on top of the course uncertainties (the example had 0.30)
    set OPT_SETUP_UNC    [expr {$SPEC_SETUP_UNC + $SETUP_SLACK_GOAL}]

    set_scenario_status func_ss -active true -setup true -hold false
    current_scenario func_ss
    set_clock_uncertainty -setup $OPT_SETUP_UNC [get_clocks -filter "is_virtual == false"]
    puts ">>> Setup uncertainty during optimization: $OPT_SETUP_UNC ns (spec $SPEC_SETUP_UNC ns)"

    # Same hold margin as CTS: spec 0.5 + 0.70 goal   ;# 063 E9: comment follows the new spec value   ;# 065: the goal is 0.0 now
    set SPEC_HOLD_UNC    0.5   ;# 063 E9: old constraints, hold uncertainty 0.5 (the example had 0.05)
    set HOLD_SLACK_GOAL  0.0   ;# 065: user decision 2026-11-02, no extra margin on top of the course uncertainties (the example had 0.70)
    set OPT_HOLD_UNC     [expr {$SPEC_HOLD_UNC + $HOLD_SLACK_GOAL}]

    set_scenario_status func_ff -active true -hold true -setup true
    current_scenario func_ff
    set_clock_uncertainty -hold $OPT_HOLD_UNC [get_clocks -filter "is_virtual == false"]

    # 3. Configure Routing, SI Crosstalk & Antenna App Options
    set_app_options -name route.global.timing_driven -value true
    set_app_options -name route.track.timing_driven -value true
    set_app_options -name route.detail.timing_driven -value true
    set_app_options -name route.global.crosstalk_driven -value true
    set_app_options -name route.track.crosstalk_driven -value true
    set_app_options -name time.si_enable_analysis -value true

    # 072: route.tcl lines 85-132, verbatim
   # ==========================================================================
    # SCL 180nm (4M1L) Fast Layer-Hopping Antenna Rules
    # - Keeps M1 & M2 -diode_ratio at 180/75 (already 0 errors, fast runtime)
    # - Tightens -ratio (input port nets only) to 25/12 to clear the 6 MT errors
    # - Tightens M3 -diode_ratio to 100/45 to clear the 14 M3 errors
    # ==========================================================================
    remove_antenna_rules

    # 1. Mode 4: Sidewall Area Rules for Metal Layers
    define_antenna_rule -mode 4 -diode_mode 4 \
        -metal_ratio 25 -cut_ratio 0
    define_antenna_layer_rule -layer M1    -mode 4 \
        -ratio 25  -diode_ratio {0 0 0 180}
    define_antenna_layer_rule -layer M2    -mode 4 \
        -ratio 25  -diode_ratio {0 0 0 180}
    define_antenna_layer_rule -layer M3    -mode 4 \
        -ratio 25  -diode_ratio {0 0 0 100}
    define_antenna_layer_rule -layer TOP_M -mode 4 \
        -ratio 25  -diode_ratio {0 0 8000 30000}

    # 2. Mode 1: Polygon Area Rules for Via Cut & Metal Layers
    define_antenna_rule -mode 1 -diode_mode 4 \
        -metal_ratio 12 -cut_ratio 20
    define_antenna_layer_rule -layer M1    -mode 1 \
        -ratio 12  -diode_ratio {0 0 0 75}
    define_antenna_layer_rule -layer M2    -mode 1 \
        -ratio 12  -diode_ratio {0 0 0 75}
    define_antenna_layer_rule -layer M3    -mode 1 \
        -ratio 12  -diode_ratio {0 0 0 45}
    define_antenna_layer_rule -layer TOP_M -mode 1 \
        -ratio 12  -diode_ratio {0 0 2000 7500}

    foreach via_lyr [get_object_name [get_layers -quiet -filter "layer_type == interconnect_via"]] {
        define_antenna_layer_rule -layer $via_lyr -mode 1 \
            -ratio 20 -diode_ratio {0 0 83.33 75}
    }

    report_antenna_rules
    
    # Pure layer-hopping antenna options (fast runtime, no diodes)
    set_app_options -name route.detail.antenna -value true
    set_app_options -name route.detail.hop_layers_to_fix_antenna -value true
    set_app_options -name route.detail.antenna_fixing_preference -value hop_layers
    set_app_options -name route.detail.insert_diodes_during_routing -value false
    #set_app_options -name route.detail.diode_libcell_names -value {scl180_std/adiode}

    set_app_options -name route_opt.flow.enable_power -value false
    set_app_options -name route_opt.flow.enable_ccd -value false
    puts ">>> 072 SETTINGS used: setup uncertainty during optimisation $OPT_SETUP_UNC ns (spec $SPEC_SETUP_UNC + goal $SETUP_SLACK_GOAL), hold uncertainty during optimisation $OPT_HOLD_UNC ns (spec $SPEC_HOLD_UNC + goal $HOLD_SLACK_GOAL); route.tcl uses 1.5 / 0.5 / 0.0 / 0.0"
    foreach {nm val exp} [list SPEC_SETUP_UNC $SPEC_SETUP_UNC 1.5 SPEC_HOLD_UNC $SPEC_HOLD_UNC 0.5 SETUP_SLACK_GOAL $SETUP_SLACK_GOAL 0.0 HOLD_SLACK_GOAL $HOLD_SLACK_GOAL 0.0] {
        if {abs($val - $exp) > 1e-12} { error "ERROR 072: $nm is $val, route.tcl's value is $exp" }
    }

    # --------------------------------------------------------------------------
    # 2. BEFORE
    # --------------------------------------------------------------------------
    set tc_filter {}
    foreach f $FILLER_REFS { lappend tc_filter "ref_name == $f" }
    set tc_filter [join $tc_filter " || "]
    set tc_nfilter {}
    foreach f $FILLER_REFS { lappend tc_nfilter "ref_name != $f" }
    set tc_nfilter [join $tc_nfilter " && "]
    set fp [open $STD_LEF r]
    set tc_lef [ant_parse_lef [read $fp]]
    close $fp
    set tc_site 1e9
    foreach f $FILLER_REFS { if {[dict exists $tc_lef $f] && [dict get $tc_lef $f w] < $tc_site} { set tc_site [dict get $tc_lef $f w] } }
    if {$tc_site > 1e8} { error "ERROR 072: none of the filler masters $FILLER_REFS is in the LEF" }
    set tc_row_h [dict get $tc_lef [lindex $FILLER_REFS 0] h]
    puts ">>> 072 site width $tc_site um, row height $tc_row_h um (narrowest filler master in the LEF)"
    set tc_stats0 [ant072_stats BEFORE $tc_filter $tc_nfilter $tc_site]
    set tc_before [ant072_metrics BEFORE]
    ant072_paths BEFORE
    redirect -variable tc_cq0 { report_clock_qor -type summary }   ;# 072: VERIFY (usage text); printed only
    puts ">>> 072 BEFORE ===== report_clock_qor -type summary =====\n$tc_cq0"
    set tc_cr0 [ant068_check_routes_counts]
    puts ">>> 072 check_routes BEFORE: DRCs [lindex $tc_cr0 0], open nets [lindex $tc_cr0 1], ICC2 antenna violations [lindex $tc_cr0 2]"

    # --------------------------------------------------------------------------
    # 3. Protect the antenna ECO cells and snapshot them
    # --------------------------------------------------------------------------
    set tc_names {}
    foreach_in_collection c [get_cells -quiet ${BUF_PREFIX}_*] { lappend tc_names [get_object_name $c] }
    set tc_nbuf [llength $tc_names]
    set tc_loads [ant068_net_leaf_pins $CLK_PORT]
    if {[llength $tc_loads] != 1} { error "ERROR 072: the clock port net $CLK_PORT has [llength $tc_loads] leaf loads, 1 expected (the CTS root)" }
    set tc_rootcell [get_cells -quiet -of_objects [get_pins -quiet -exact [lindex $tc_loads 0]]]   ;# 071: VERIFY get_cells -of_objects <pin>
    if {[sizeof_collection $tc_rootcell] != 1} { error "ERROR 072: cannot find the cell of pin [lindex $tc_loads 0]" }
    set tc_root [get_object_name $tc_rootcell]
    lappend tc_names $tc_root
    if {$tc_nbuf == 0} { error "ERROR 072: no instance named ${BUF_PREFIX}_* found: antenna_port_buffers.tcl has not run on this block (nothing to protect), nothing was changed" }
    set tc_snap0 {}
    set tc_pnets {}
    foreach nm $tc_names {
        set s [ant072_snapshot $nm]
        lappend tc_snap0 $s
        puts ">>> 072 PROTECTED $nm: reference [dict get $s ref], origin ([format %.3f [dict get $s x]], [format %.3f [dict get $s y]]), orientation [dict get $s ori], pins [dict get $s pins]"
        foreach e [dict get $s pins] {
            set pn [lindex $e 1]
            if {$pn ne "-" && $pn ne "VDD" && $pn ne "VSS" && [lsearch -exact $tc_pnets $pn] < 0} { lappend tc_pnets $pn }
        }
    }
    puts ">>> 072 protected cells: [llength $tc_names] ($tc_nbuf port buffers ${BUF_PREFIX}_* + the clock root $tc_root, reference [dict get [lindex $tc_snap0 end] ref]); their signal nets: [llength $tc_pnets]"
    set tc_cells [get_cells -quiet -exact $tc_names]
    set tc_status0 {}
    foreach_in_collection c $tc_cells { lappend tc_status0 [list [get_object_name $c] [get_attribute -quiet $c physical_status]] }   ;# 072: VERIFY the cell attribute physical_status
    set tc_dt_ok 0
    if {![catch {set_dont_touch $tc_cells true} err]} { set tc_dt_ok 1 } else { puts ">>> 072 set_dont_touch on the cells failed: $err" }   ;# 072: VERIFY set_dont_touch <cells> true (not in the probed help)
    if {$PROTECT_NETS} {
        if {[catch {set_dont_touch [get_nets -quiet -exact $tc_pnets] true} err]} { puts ">>> 072 set_dont_touch on the nets failed: $err"; set tc_dt_ok 0 }
    }
    if {!$tc_dt_ok} { error "ERROR 072: the protection could not be set (set_dont_touch), nothing was changed. Without it route_opt may resize or remove the antenna cells." }
    if {[catch {set_attribute -objects $tc_cells -name physical_status -value fixed} err]} { puts ">>> 072 physical_status fixed failed: $err (the cell origin is still checked at the end)" }   ;# 072: VERIFY physical_status fixed blocks moving
    foreach_in_collection c $tc_cells {
        puts ">>> 072 PROTECTION [get_object_name $c]: dont_touch=[get_attribute -quiet $c dont_touch] physical_status=[get_attribute -quiet $c physical_status]"   ;# 072: VERIFY the cell attribute dont_touch
    }

    # --------------------------------------------------------------------------
    # 4. Remove the fillers (table method of task 070; counts kept)
    # --------------------------------------------------------------------------
    set tc_fcoll [get_cells -quiet -filter $tc_filter]
    set tc_nfill0 [sizeof_collection $tc_fcoll]
    puts ">>> 072 removing $tc_nfill0 filler instances (count and site balance are checked at the end)"
    if {$tc_nfill0 == 0} { error "ERROR 072: no filler instance found with the filter '$tc_filter'" }
    remove_cells $tc_fcoll   ;# 069: VERIFY remove_cells on 20k filler instances at once (it worked per net in the task 069/070 runs)
    puts ">>> 072 fillers left after the removal: [sizeof_collection [get_cells -quiet -filter $tc_filter]]"

    # --------------------------------------------------------------------------
    # 5. route_opt passes (the call of route.tcl line 142)
    # --------------------------------------------------------------------------
    set tc_prev $tc_before
    set tc_pass 0
    set tc_stop_reason "no pass run"
    while {1} {
        incr tc_pass
        puts ">>> 072 ===== route_opt pass $tc_pass of at most $MAX_PASSES (goals unchanged: setup uncertainty $OPT_SETUP_UNC, hold $OPT_HOLD_UNC) ====="
        route_opt   ;# 072: route.tcl line 142 (same call, no argument)
        set tc_cur [ant072_metrics "PASS $tc_pass"]
        set tc_diff [ant072_snapshot_diff $tc_snap0 [lmap nm $tc_names {ant072_snapshot $nm}]]
        if {[llength $tc_diff]} {
            puts ">>> 072 PROTECTED CELL CHANGED in pass $tc_pass: [join $tc_diff {; }]"
            lappend tc_failures "protected cells changed in pass $tc_pass: [join $tc_diff {; }]"
            set tc_stop_reason "a protected cell changed"
            break
        }
        lassign [ant072_pass_decision $tc_pass $MAX_PASSES $tc_prev $tc_cur $IMPROVE_EPS] tc_act tc_why
        puts ">>> 072 PASS DECISION after pass $tc_pass: $tc_act: $tc_why"
        set tc_prev $tc_cur
        if {$tc_act eq "stop"} { set tc_stop_reason $tc_why; break }
    }
    puts ">>> 072 route_opt loop ended after $tc_pass pass(es): $tc_stop_reason"
    set tc_afteropt $tc_prev

    # --------------------------------------------------------------------------
    # 6. Legalise, restore the spec uncertainties, fillers, PG, route_detail / route_eco (route.tcl)
    # --------------------------------------------------------------------------
    legalize_placement   ;# 072: route.tcl line 143
    # 072: route.tcl lines 147-152, verbatim
    current_scenario func_ss
    set_clock_uncertainty -setup $SPEC_SETUP_UNC [get_clocks -filter "is_virtual == false"]

  # Restore the real hold uncertainty so reports and exported SDC are correct
    current_scenario func_ff
    set_clock_uncertainty -hold $SPEC_HOLD_UNC [get_clocks -filter "is_virtual == false"]
    puts ">>> 072 uncertainties restored to the spec values: setup $SPEC_SETUP_UNC ns, hold $SPEC_HOLD_UNC ns"

    # 072: route.tcl lines 158-192, verbatim
    # Insert Standard Cell Fillers (Pulling from scl180_filler.ndm via reference libraries)
    set fill_cells [get_lib_cells -quiet [list ${FILLER_LIB}/feedth9 ${FILLER_LIB}/feedth3 ${FILLER_LIB}/feedth]]
    if {[sizeof_collection $fill_cells] == 0} {
        set fill_cells [get_lib_cells -quiet {*/feedth9 */feedth3 */feedth}]
    }
    if {[sizeof_collection $fill_cells] > 0} { 
        create_stdcell_fillers -lib_cells $fill_cells
        connect_pg_net -automatic
        connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
        connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]
    } else {
        puts "ERROR: feedth filler cells not found in reference libraries!"
    }

    # 7. Connect PG Nets for Any Post-Route ECO & Filler Cells
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # Fix filler-induced DRCs and close any open nets without ripping up clean global routes
    route_detail -incremental true -max_number_iterations 100
    route_eco \
        -reuse_existing_global_route true \
        -utilize_dangling_wires true \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 200
    # Final pass specifically ensuring 0 open nets remain
    route_eco \
        -open_net_driven true \
        -reuse_existing_global_route true \
        -utilize_dangling_wires true \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 200
    route_detail -incremental true -max_number_iterations 100
    check_routes

    # --------------------------------------------------------------------------
    # 7. Checks (nothing is saved when one fails)
    # --------------------------------------------------------------------------
    set tc_cr [ant068_check_routes_counts]
    set tc_drc [lindex $tc_cr 0]
    set tc_open [lindex $tc_cr 1]
    puts ">>> 072 check_routes AFTER: DRCs $tc_drc, open nets $tc_open, ICC2 antenna violations [lindex $tc_cr 2]"
    if {$tc_drc eq ""} { lappend tc_failures "check_routes DRC count not readable" } elseif {$tc_drc != 0} { lappend tc_failures "check_routes DRCs $tc_drc (0 required)" }
    if {$tc_open eq ""} { lappend tc_failures "check_routes open-net count not readable" } elseif {$tc_open != 0} { lappend tc_failures "check_routes open nets $tc_open (0 required)" }

    redirect -variable tc_leg_txt { check_legality -verbose }
    puts $tc_leg_txt
    set tc_leg [ant_parse_legality $tc_leg_txt]
    if {$tc_leg eq ""} { if {![catch {sizeof_collection [check_legality -cell_violation]} v]} { set tc_leg $v } }   ;# 068: VERIFY -cell_violation as the fallback when the text has no number
    puts ">>> 072 CHECK legality violations: [expr {$tc_leg eq {} ? {unreadable} : $tc_leg}] (0 required)"
    if {$tc_leg eq ""} { lappend tc_failures "check_legality result unreadable" } elseif {$tc_leg != 0} { lappend tc_failures "legality violations $tc_leg" }

    set tc_snap1 [lmap nm $tc_names {ant072_snapshot $nm}]
    set tc_diff [ant072_snapshot_diff $tc_snap0 $tc_snap1]
    puts ">>> 072 CHECK protected cells ([llength $tc_names]): [expr {[llength $tc_diff] ? $tc_diff : {reference, origin, orientation and every pin connection are identical to the snapshot}}]"
    foreach d $tc_diff { lappend tc_failures "protected cell: $d" }
    set tc_nbuf1 [sizeof_collection [get_cells -quiet ${BUF_PREFIX}_*]]
    puts ">>> 072 CHECK ${BUF_PREFIX}_* count: $tc_nbuf before, $tc_nbuf1 after"
    if {$tc_nbuf1 != $tc_nbuf} { lappend tc_failures "${BUF_PREFIX}_* count $tc_nbuf -> $tc_nbuf1" }
    set tc_loads1 [ant068_net_leaf_pins $CLK_PORT]
    puts ">>> 072 CHECK $CLK_PORT leaf loads: $tc_loads1, root $tc_root reference [dict get [lindex $tc_snap1 end] ref] (before [dict get [lindex $tc_snap0 end] ref])"
    if {$tc_loads1 ne $tc_loads} { lappend tc_failures "the leaf loads of $CLK_PORT changed: $tc_loads -> $tc_loads1" }

    set tc_stats1 [ant072_stats AFTER $tc_filter $tc_nfilter $tc_site]
    set tc_cell_sites [expr {([dict get $tc_stats1 area] - [dict get $tc_stats0 area]) / ($tc_site * $tc_row_h)}]
    lassign [ant072_filler_check $tc_nfill0 [dict get $tc_stats1 nfill] [dict get $tc_stats0 fsites] [dict get $tc_stats1 fsites] $tc_cell_sites $FILLER_TOL_PCT] tc_fok tc_fmsg
    puts ">>> 072 CHECK fillers: $tc_fmsg"
    if {!$tc_fok} { lappend tc_failures $tc_fmsg }
    puts ">>> 072 ADDED by the pass: cells [expr {[dict get $tc_stats1 ncell] - [dict get $tc_stats0 ncell]}], area [format %.2f [expr {[dict get $tc_stats1 area] - [dict get $tc_stats0 area]}]] um^2, buffers [expr {[dict get $tc_stats1 nbuf] - [dict get $tc_stats0 nbuf]}], inverters [expr {[dict get $tc_stats1 ninv] - [dict get $tc_stats0 ninv]}] (hold buffers and resizing by route_opt)"

    # --------------------------------------------------------------------------
    # 8. AFTER and verdict
    # --------------------------------------------------------------------------
    puts ">>> 072 timing after route_opt and legalisation, before the fillers / route_eco steps: setup WNS [dict get $tc_afteropt setup], hold WNS [dict get $tc_afteropt hold] (compare with AFTER below: the difference is what the filler and route_eco steps of route.tcl cost)"
    set tc_after [ant072_metrics AFTER]
    ant072_paths AFTER
    redirect -variable tc_cq1 { report_clock_qor -type summary }
    puts ">>> 072 AFTER ===== report_clock_qor -type summary =====\n$tc_cq1"
    lassign [ant072_verdict $tc_before $tc_after $WORSE_TOL $IMPROVE_EPS] tc_verdict tc_vwhy
    puts ">>> 072 VERDICT $tc_verdict: $tc_vwhy"
    puts ">>> 072 BEFORE setup WNS [dict get $tc_before setup] hold WNS [dict get $tc_before hold]; AFTER setup WNS [dict get $tc_after setup] hold WNS [dict get $tc_after hold]"

    if {[llength $tc_failures] > 0} {
        error "ERROR 072: [llength $tc_failures] check(s) failed, NOTHING SAVED: [join $tc_failures {; }]"
    }

    # --------------------------------------------------------------------------
    # 9. Save over _route (as fix_antenna.tcl) and finish
    # --------------------------------------------------------------------------
    if {!$KEEP_PROTECTION} {
        catch {set_dont_touch $tc_cells false}
        if {$PROTECT_NETS} { catch {set_dont_touch [get_nets -quiet -exact $tc_pnets] false} }
        foreach e $tc_status0 { catch {set_attribute -objects [get_cells -exact [lindex $e 0]] -name physical_status -value [lindex $e 1]} }
        puts ">>> 072 protection removed before saving"
    } else {
        puts ">>> 072 protection (dont_touch on the cells[expr {$PROTECT_NETS ? { and their nets} : {}}], fixed placement) is KEPT in the saved block"
    }
    save_block
    save_block -force -as ${DESIGN_NAME}_route
    save_lib
    puts ">>> STAGE 6e COMPLETE: route_opt passes $tc_pass, verdict $tc_verdict ($tc_vwhy), setup WNS [dict get $tc_before setup] -> [dict get $tc_after setup], hold WNS [dict get $tc_before hold] -> [dict get $tc_after hold], ${DESIGN_NAME}_route overwritten in place. Log: ${LOG_DIR}/6e_timing_closure.log"
    puts ">>> 072 NEXT: metal_fill.tcl, pv.tcl, then NEW Calibre DRC and antenna runs (both must stay 0)."
}
