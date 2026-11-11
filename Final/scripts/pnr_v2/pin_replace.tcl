# PARKED (task 068): see README
# ==============================================================================
# Script: pin_replace.tcl
# Path  : <RUN_DIR>/pnr_v2/pin_replace.tcl   ;# 067: new script (flow step 4b, between placement.tcl and cts.tcl)
# Stage : Re-place the pins once the cells are placed, re-optimise, check, save _pinplace
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 067: why. floorplanning.tcl places the 204 pins once, BEFORE any cell exists (place_pins -self). The tool filled each edge from both ends
# in alternating pairs, so a pin can be far from its load; an input port net has no diode inside the macro and a long single-layer run from the
# pin to a tiny gate fails the Calibre antenna rules (handoff 18.27, 18.32). Routing cannot shorten such a net; the pin position can.
# 067: what stays. The pin constraints of floorplanning.tcl (ports, sides, layers, spacing) are NOT touched: this script does not set or remove
# them. The tool only chooses new positions along the same edges. Sides/layers/count/spacing are checked below (hard error).
# 067: every command or option not shown in a usage text in ~/server_pull/rpt/help (the real help of this tool version) is marked VERIFY.

set DESIGN_NAME "unpu_top"   ;# 067: as in the other scripts
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"   ;# 067: as in the other scripts (the one BASE literal)
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set RPT_DIR     "${PNR_DIR}/reports"   ;# 067: pins_before_replace.txt and pins_after_replace.txt go here (task 067)

# 067: parameters (name = value ;# source)
set IN_BLOCK  "${DESIGN_NAME}_placement"   ;# 067: written by placement.tcl
set OUT_BLOCK "${DESIGN_NAME}_pinplace"    ;# 067: read by cts.tcl (task 067)
set PIN_LAYER_TOP    "M2"   ;# 067: floorplanning.tcl E7, side 2 (top) = dma_* on M2
set PIN_LAYER_RIGHT  "M3"   ;# 067: floorplanning.tcl E7, side 3 (right) = APB, clk, rst_n on M3
set PIN_SIDE_NUM     [dict create left 1 top 2 right 3 bottom 4]   ;# 067: top = 2 and right = 3 are floorplanning.tcl; left = 1 and bottom = 4 are the clockwise continuation (VERIFY, not used by any constraint)
set PIN_SPACING_UM   8      ;# 067: floorplanning.tcl E7 -pin_spacing_distance 8 (checked as a centre-to-centre pitch, which is never smaller than an edge-to-edge distance)
set EXPECT_TOP_PINS    102  ;# 067: task 067 and handoff 18.32 (102 top M2 dma_* pins); also checked against the port count of the pattern below
set EXPECT_RIGHT_PINS  102  ;# 067: task 067 and handoff 18.32 (102 right M3 pins); also checked against the port count of the pattern below
set PIN_MOVE_TOL_UM  0.001  ;# 067: one database unit (units 1000 per um): a pin whose centre differs by more is "moved"
set POWER_PORT_NAMES {VDD VSS}   ;# 067: the power ports (terminals TM_* of powerplanning.tcl); they are never touched here
# 067: the port groups, copied from floorplanning.tcl (side2_ports / side3_ports); they must stay the same text
set TOP_PORT_PATTERNS   {dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] dma_valid dma_ready}
set RIGHT_PORT_PATTERNS {paddr[*] pwdata[*] prdata[*] pwrite psel penable pready clk rst_n}
set EVIDENCE_PORTS {clk rst_n psel pwdata[0] pwdata[10] pwdata[26] dma_rdata[9] dma_rdata[11]}   ;# 067: task 067 item 8 (the port nets named by fix_antenna.tcl)

file mkdir $LOG_DIR
file mkdir $RPT_DIR

# ------------------------------------------------------------------------------
# 067: helper procedures (pure Tcl except where a tool command is named)
# ------------------------------------------------------------------------------
# four numbers of "{llx lly} {urx ury}" -> {llx lly urx ury}; error if there are not exactly four
proc pr_bbox {text} {
    set nums {}
    foreach tok [regexp -all -inline -- {[^\s,;(){}\[\]]+} $text] { if {[string is double -strict $tok]} { lappend nums $tok } }
    if {[llength $nums] != 4} { error "cannot read a box from '$text'" }
    return $nums
}
proc pr_center {text} {
    lassign [pr_bbox $text] x0 y0 x1 y1
    return [list [expr {($x0 + $x1) / 2.0}] [expr {($y0 + $y1) / 2.0}]]
}
# attribute that may be an object handle (_sel22, handoff K61: the layer attribute of a terminal): the name of the object, else the text
proc pr_attr_name {obj attr} {
    set v [get_attribute $obj $attr]
    if {[regexp {^_sel[0-9]+$} $v]} { return [get_object_name $v] }
    return $v
}
# nearest die edge of a point: {edge distance along}; along = coordinate along that edge from the lower-left end (y on left/right, x on top/bottom)
proc pr_edge {cx cy die} {
    lassign $die x0 y0 x1 y1
    set d [dict create left [expr {$cx - $x0}] right [expr {$x1 - $cx}] bottom [expr {$cy - $y0}] top [expr {$y1 - $cy}]]
    set best ""; set bd 1e30
    foreach e {left right bottom top} { if {[dict get $d $e] < $bd} { set bd [dict get $d $e]; set best $e } }
    if {$best eq "left" || $best eq "right"} { set along [expr {$cy - $y0}] } else { set along [expr {$cx - $x0}] }
    return [list $best $bd $along]
}
# one record per signal port: dict port -> {cx cy layer status}; plus the list of ports that do not have exactly one readable terminal
# (the terminal of a port: get_terminals -of_objects <port>, usage "Get terminals of these ports")
proc pr_snapshot {names} {
    set rec [dict create]
    set bad {}
    foreach p $names {
        set t [get_terminals -quiet -of_objects [get_ports -quiet -exact $p]]
        if {[sizeof_collection $t] != 1} { lappend bad "${p}(terminals=[sizeof_collection $t])"; continue }
        if {[catch {pr_center [get_attribute $t bbox]} c]} { lappend bad "${p}(bbox:$c)"; continue }
        if {[catch {pr_attr_name $t layer} lay]} { set lay unavailable }
        if {[catch {get_attribute $t physical_status} st]} { set st n/a }   ;# 067 VERIFY: attribute physical_status on a terminal
        dict set rec $p [list [lindex $c 0] [lindex $c 1] $lay $st]
    }
    return [list $rec $bad]
}
# pins whose centre moved by more than tol between two records
proc pr_moved {a b tol} {
    set n 0
    dict for {p r} $a {
        if {![dict exists $b $p]} continue
        set s [dict get $b $p]
        if {abs([lindex $r 0] - [lindex $s 0]) + abs([lindex $r 1] - [lindex $s 1]) > $tol} { incr n }
    }
    return $n
}
proc pr_stuck {rec} {
    set o {}
    dict for {p r} $rec { if {[lindex $r 3] eq "fixed" || [lindex $r 3] eq "locked"} { lappend o $p } }
    return $o
}
# "block unpu_top pin <name> layer <L> side <S> offset <um>" lines, sorted by side then offset
proc pr_pin_lines {rec die design sidenum} {
    set rows {}
    dict for {p r} $rec {
        lassign [pr_edge [lindex $r 0] [lindex $r 1] $die] e dist along
        lappend rows [list [dict get $sidenum $e] $along $p [lindex $r 2]]
    }
    set out {}
    foreach r [lsort -index 1 -real [lsort -index 0 -integer $rows]] {
        lassign $r s along p lay
        lappend out [format "block %s pin %s layer %s side %s offset %.2f" $design $p $lay $s $along]
    }
    return $out
}
# loads of a port net: {nloads nearest farthest unreadable via_cell}; distance = Manhattan, pin centre to load pin centre
proc pr_loads {p pcx pcy} {
    set net [get_nets -quiet -of_objects [get_ports -quiet -exact $p]]   ;# 067 VERIFY: get_nets -of_objects <port> (usage: pins, ports, cells, ...)
    if {[sizeof_collection $net] != 1} { return [list unavailable "net of $p not found"] }
    set pins [get_pins -quiet -leaf -of_objects $net]   ;# 067 VERIFY: get_pins -leaf -of_objects <net> (used by pnr/power.tcl)
    set n [sizeof_collection $pins]
    set dmin ""; set dmax ""; set unread 0; set viacell 0
    foreach_in_collection lp $pins {
        set c ""
        if {![catch {pr_center [get_attribute $lp bbox]} c0]} { set c $c0 } else {   ;# 067 VERIFY: attribute bbox on a leaf pin
            if {![catch {pr_center [get_attribute [get_cells -of_objects $lp] bbox]} c1]} { set c $c1; incr viacell }   ;# 067 VERIFY: fallback = the cell's box
        }
        if {$c eq ""} { incr unread; continue }
        set d [expr {abs([lindex $c 0] - $pcx) + abs([lindex $c 1] - $pcy)}]
        if {$dmin eq "" || $d < $dmin} { set dmin $d }
        if {$dmax eq "" || $d > $dmax} { set dmax $d }
    }
    return [list $n $dmin $dmax $unread $viacell]
}
proc pr_loads_text {l} {
    if {[lindex $l 0] eq "unavailable"} { return "unavailable ([lindex $l 1])" }
    lassign $l n dmin dmax unread viacell
    if {$dmin eq ""} { return "$n loads, distances unreadable" }
    return [format "%d loads, nearest %.1f um, farthest %.1f um (unreadable %d, via cell box %d)" $n $dmin $dmax $unread $viacell]
}

redirect -tee -file ${LOG_DIR}/4b_pin_replace.log {
    puts ">>> RUN ROOT: $RUN_ROOT"   ;# 082: the log shows which clone wrote it

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }

    # 067: clean previous _pinplace block (same idiom as cts.tcl does for _cts)
    if {[file exists ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${OUT_BLOCK}]} {
        remove_blocks ${DESIGN_NAME}.dlib:${OUT_BLOCK}
    }

    open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${IN_BLOCK}
    link_block

    suppress_message {DCHK-027 DCHK-010 ATTR-12}

    puts ">>> 067 no random seed is set by this script (placement and pin placement use the tool defaults)"
    set pr_failures {}   ;# 067: every failed check is added here and the script stops with an error before saving

    # --------------------------------------------------------------------------
    # 1. Ports, groups, die; the state BEFORE
    # --------------------------------------------------------------------------
    set die [pr_bbox [get_attribute [current_block] boundary_bbox]]   ;# 067: as pnr/floorplan.tcl (boundary_bbox)
    puts ">>> 067 die box: $die"
    set all_names {}
    foreach_in_collection pr_p [get_ports -quiet *] {
        set nm [get_object_name $pr_p]
        if {[lsearch -exact $POWER_PORT_NAMES $nm] < 0} { lappend all_names $nm }
    }
    set top_names {}
    foreach_in_collection pr_p [get_ports -quiet $TOP_PORT_PATTERNS] { lappend top_names [get_object_name $pr_p] }
    set right_names {}
    foreach_in_collection pr_p [get_ports -quiet $RIGHT_PORT_PATTERNS] { lappend right_names [get_object_name $pr_p] }
    puts ">>> 067 signal ports [llength $all_names], top group [llength $top_names], right group [llength $right_names]"
    if {[llength $top_names] != $EXPECT_TOP_PINS || [llength $right_names] != $EXPECT_RIGHT_PINS || [llength $all_names] != ($EXPECT_TOP_PINS + $EXPECT_RIGHT_PINS)} {
        error "ERROR 067: port counts differ from the expectation: signal [llength $all_names] (expected [expr {$EXPECT_TOP_PINS + $EXPECT_RIGHT_PINS}]), top [llength $top_names] ($EXPECT_TOP_PINS), right [llength $right_names] ($EXPECT_RIGHT_PINS)"
    }
    set n_term_before [sizeof_collection [get_terminals -quiet *]]
    puts ">>> 067 terminals in the block before: $n_term_before (signal [llength $all_names] + power)"

    lassign [pr_snapshot $all_names] rec0 bad0
    if {[llength $bad0] > 0} { error "ERROR 067: ports without exactly one readable terminal before the re-placement: [llength $bad0] {[lrange $bad0 0 9]}" }
    puts ">>> 067 BEFORE: pin positions read for [dict size $rec0] ports"
    foreach p {clk rst_n} {
        lassign [pr_edge [lindex [dict get $rec0 $p] 0] [lindex [dict get $rec0 $p] 1] $die] e dist along
        puts [format ">>> 067 BEFORE %s: edge %s, offset %.2f um from the lower-left end of the edge (compare with pins_floorplan.txt: the offset convention), layer %s, status %s" $p $e $along [lindex [dict get $rec0 $p] 2] [lindex [dict get $rec0 $p] 3]]
    }
    set n_stuck0 [llength [pr_stuck $rec0]]
    puts ">>> 067 BEFORE: terminals with physical_status fixed or locked: $n_stuck0 (statuses seen: [lsort -unique [lmap r [dict values $rec0] {lindex $r 3}]])"

    # evidence before: pin to load distance per port net
    foreach p $EVIDENCE_PORTS {
        if {![dict exists $rec0 $p]} { error "ERROR 067: evidence port $p is not a signal port of this block" }
        set ev0($p) [pr_loads $p [lindex [dict get $rec0 $p] 0] [lindex [dict get $rec0 $p] 1]]
    }

    redirect -file ${RPT_DIR}/pins_before_replace.txt { report_pin_placement -self }   ;# 067: the tool's own report (floorplanning.tcl uses the same command)
    puts ">>> 067 BEFORE: report_pin_placement -self written to ${RPT_DIR}/pins_before_replace.txt"
    puts ">>> 067 the pin constraints as the block holds them (not changed by this script):"
    report_block_pin_constraints
    report_individual_pin_constraints

    # --------------------------------------------------------------------------
    # 2. Re-place the pins with the cells known
    # --------------------------------------------------------------------------
    # 067: how the already-placed pins are released. Plan A: place_pins -self again (constraints untouched). A pin that is placed but not
    # fixed/locked is expected to be moved by a second call (VERIFY: not shown in the usage text). If NO pin moved, or any pin is still
    # fixed/locked afterwards, plan B: remove_terminals -force on the 204 SIGNAL terminals only (usage: -force = "ignore locked status of
    # the objects"; the power terminals TM_* are not in the list), then place_pins -self creates them again from the unchanged constraints.
    # Nothing is assumed: the number of moved pins and the statuses are printed after each plan, and the script stops if no pin moved.
    set plan "A"
    place_pins -self
    lassign [pr_snapshot $all_names] rec1 bad1
    set moved1 [pr_moved $rec0 $rec1 $PIN_MOVE_TOL_UM]
    set stuck1 [pr_stuck $rec1]
    puts ">>> 067 plan A (place_pins -self): moved pins $moved1 of [dict size $rec0]; unreadable [llength $bad1]; fixed/locked afterwards [llength $stuck1]"
    if {$moved1 == 0 || [llength $stuck1] > 0 || [llength $bad1] > 0} {
        puts ">>> 067 plan A did not release all pins: plan B (remove_terminals -force on the signal terminals, then place_pins -self)"
        set plan "B"
        set sig_terms [get_terminals -quiet -of_objects [get_ports -quiet -exact $all_names]]
        puts ">>> 067 plan B removes [sizeof_collection $sig_terms] signal terminals"
        if {[sizeof_collection $sig_terms] != [llength $all_names]} {
            error "ERROR 067: plan B would remove [sizeof_collection $sig_terms] terminals, expected [llength $all_names] (one per signal port); nothing removed"
        }
        remove_terminals -force $sig_terms   ;# 067 VERIFY: usage in help/remove_terminals.txt (-force, terminal_list)
        puts ">>> 067 plan B: terminals in the block after the removal: [sizeof_collection [get_terminals -quiet *]]"
        report_block_pin_constraints
        report_individual_pin_constraints
        place_pins -self
        lassign [pr_snapshot $all_names] rec1 bad1
        set moved1 [pr_moved $rec0 $rec1 $PIN_MOVE_TOL_UM]
        set stuck1 [pr_stuck $rec1]
        puts ">>> 067 plan B: moved pins $moved1 of [dict size $rec0]; unreadable [llength $bad1]; fixed/locked afterwards [llength $stuck1]"
    }
    if {[llength $bad1] > 0} { error "ERROR 067: ports without exactly one readable terminal after place_pins: [llength $bad1] {[lrange $bad1 0 9]}" }
    if {$moved1 == 0} { error "ERROR 067: no pin moved after place_pins (plan $plan): the pins were not released; nothing is saved. Read the printed statuses and the pin constraints above" }
    if {[llength $stuck1] > 0} { error "ERROR 067: [llength $stuck1] pins are still fixed or locked after plan $plan: {[lrange $stuck1 0 9]}" }
    puts ">>> 067 pins released with plan $plan, $moved1 of [dict size $rec0] moved"

    # --------------------------------------------------------------------------
    # 3. Re-optimise the placement (default plan of task 067: place_opt again with the SAME options as placement.tcl)
    # --------------------------------------------------------------------------
    # 067: options copied from placement.tcl (blocks 2 and 3), not invented
    set_ignored_layers \
        -min_routing_layer M1 \
        -max_routing_layer TOP_M

    set_app_options -name place_opt.flow.do_path_opt -value true
    set_app_options -name place_opt.flow.clock_aware_placement -value true
    set_app_options -name place_opt.flow.trial_clock_tree -value true
    set_app_options -name place_opt.initial_drc.global_route_based -value true
    set_app_options -name place_opt.place.congestion_effort -value high
    set_app_options -name place.coarse.continue_on_missing_scandef -value true

    place_opt

    # Ensure strict cell legality on standard cell rows
    legalize_placement

    # PG nets of any newly added buffers (as placement.tcl)
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # --------------------------------------------------------------------------
    # 4. Checks (the same as placement.tcl) and the numbers that decide
    # --------------------------------------------------------------------------
    redirect -variable pr_legal_txt { check_legality }
    puts $pr_legal_txt
    check_pg_drc
    check_pg_connectivity
    report_placement
    report_congestion
    report_utilization
    report_qor
    report_global_timing

    # legality: the number of violating cells. VERIFY: check_legality -cell_violation returns the violating cells (usage text); fallback = a "N violation" count in the text
    set pr_nleg unavailable
    if {![catch {sizeof_collection [check_legality -cell_violation]} v]} { set pr_nleg $v } elseif {[regexp -nocase {([0-9]+)\s+(legality\s+)?violation} $pr_legal_txt -> v]} { set pr_nleg $v }
    puts ">>> 067 CHECK legality violations: $pr_nleg (0 expected)"
    if {$pr_nleg eq "unavailable"} { lappend pr_failures "legality count could not be read (VERIFY check_legality output above)" } elseif {$pr_nleg != 0} { lappend pr_failures "legality violations $pr_nleg" }

    # pins: re-read after place_opt
    lassign [pr_snapshot $all_names] rec2 bad2
    if {[llength $bad2] > 0} { lappend pr_failures "ports without exactly one readable terminal after place_opt: [llength $bad2] {[lrange $bad2 0 9]}" }
    set moved_opt [pr_moved $rec1 $rec2 $PIN_MOVE_TOL_UM]
    puts ">>> 067 CHECK pins moved by place_opt/legalize_placement: $moved_opt (0 expected)"
    if {$moved_opt != 0} { lappend pr_failures "place_opt moved $moved_opt pins" }
    set n_term_after [sizeof_collection [get_terminals -quiet *]]
    puts ">>> 067 CHECK terminals in the block after: $n_term_after (before $n_term_before)"
    if {$n_term_after != $n_term_before} { lappend pr_failures "terminal count changed from $n_term_before to $n_term_after (the power terminals must be untouched)" }

    # sides, layers, count, spacing
    set pr_cnt_top 0; set pr_cnt_right 0; set pr_wrong {}
    set pr_by_edge [dict create top {} right {} left {} bottom {}]
    foreach p $all_names {
        lassign [dict get $rec2 $p] cx cy lay st
        lassign [pr_edge $cx $cy $die] e dist along
        dict lappend pr_by_edge $e $along
        if {[lsearch -exact $top_names $p] >= 0} {
            if {$e eq "top" && $lay eq $PIN_LAYER_TOP} { incr pr_cnt_top } else { lappend pr_wrong "$p:edge=$e,layer=$lay,want=top/$PIN_LAYER_TOP" }
        } else {
            if {$e eq "right" && $lay eq $PIN_LAYER_RIGHT} { incr pr_cnt_right } else { lappend pr_wrong "$p:edge=$e,layer=$lay,want=right/$PIN_LAYER_RIGHT" }
        }
    }
    puts ">>> 067 CHECK pins on side 2 (top) / $PIN_LAYER_TOP: $pr_cnt_top (expected $EXPECT_TOP_PINS); on side 3 (right) / $PIN_LAYER_RIGHT: $pr_cnt_right (expected $EXPECT_RIGHT_PINS); wrong: [llength $pr_wrong] {[lrange $pr_wrong 0 5]}"
    if {$pr_cnt_top != $EXPECT_TOP_PINS || $pr_cnt_right != $EXPECT_RIGHT_PINS || [llength $pr_wrong] > 0} { lappend pr_failures "pins on the wrong side or layer: top $pr_cnt_top, right $pr_cnt_right, wrong [llength $pr_wrong] {[lrange $pr_wrong 0 5]}" }
    foreach e {top right left bottom} {
        set al [lsort -real [dict get $pr_by_edge $e]]
        set mn ""
        for {set i 1} {$i < [llength $al]} {incr i} {
            set g [expr {[lindex $al $i] - [lindex $al [expr {$i - 1}]]}]
            if {$mn eq "" || $g < $mn} { set mn $g }
        }
        puts ">>> 067 CHECK edge $e: [llength $al] pins, smallest centre pitch [expr {$mn eq {} ? {n/a} : [format %.3f $mn]}] um (>= $PIN_SPACING_UM um expected)"
        if {$mn ne "" && $mn < $PIN_SPACING_UM - $PIN_MOVE_TOL_UM} { lappend pr_failures "edge $e: centre pitch $mn um is below the spacing $PIN_SPACING_UM um" }
    }

    # the tool's own pin check. VERIFY: the wording of the output; every line that mentions a violation without "no"/"0" is counted
    redirect -variable pr_pc_txt { check_pin_placement -self }
    puts $pr_pc_txt
    set pr_pc_bad 0
    foreach l [split $pr_pc_txt "\n"] {
        if {[regexp -nocase {violat|error} $l] && ![regexp -nocase {no violat|\m0 violat|violations?: *0|0 error} $l]} { incr pr_pc_bad }
    }
    puts ">>> 067 CHECK check_pin_placement -self: lines that report a problem: $pr_pc_bad (0 expected)"
    if {$pr_pc_bad > 0} { lappend pr_failures "check_pin_placement -self reports a problem ($pr_pc_bad lines, see the text above)" }

    # --------------------------------------------------------------------------
    # 5. The positions for the top-level team
    # --------------------------------------------------------------------------
    foreach p {clk rst_n} {
        lassign [pr_edge [lindex [dict get $rec2 $p] 0] [lindex [dict get $rec2 $p] 1] $die] e dist along
        puts [format ">>> 067 AFTER %s: edge %s, offset %.2f um (before %.2f um), layer %s" $p $e $along [lindex [pr_edge [lindex [dict get $rec0 $p] 0] [lindex [dict get $rec0 $p] 1] $die] 2] [lindex [dict get $rec2 $p] 2]]
    }
    set fh [open ${RPT_DIR}/pins_after_replace.txt w]
    foreach l [pr_pin_lines $rec2 $die $DESIGN_NAME $PIN_SIDE_NUM] { puts $fh $l }
    close $fh
    puts ">>> 067 pin list for the top-level team: ${RPT_DIR}/pins_after_replace.txt ([dict size $rec2] lines; offset = centre along the edge from its lower-left end, same format as pins_floorplan.txt)"
    redirect -file ${RPT_DIR}/pins_after_replace_report.txt { report_pin_placement -self }   ;# 067: the tool's own text next to the list
    report_pin_placement -self

    # --------------------------------------------------------------------------
    # 6. The evidence the experiment is about: pin to load distance, before and after
    # --------------------------------------------------------------------------
    puts ">>> 067 EVIDENCE port nets, Manhattan distance from the pin centre to the load pins (before = placement block, after = now):"
    foreach p $EVIDENCE_PORTS {
        set l2 [pr_loads $p [lindex [dict get $rec2 $p] 0] [lindex [dict get $rec2 $p] 1]]
        puts ">>> 067 EVIDENCE $p  BEFORE: [pr_loads_text $ev0($p)]"
        puts ">>> 067 EVIDENCE $p  AFTER : [pr_loads_text $l2]"
    }

    if {[llength $pr_failures] > 0} {
        error "ERROR 067: [llength $pr_failures] check(s) failed, nothing is saved: [join $pr_failures { | }]"
    }

    save_block -as ${OUT_BLOCK}
    save_lib
    puts ">>> STAGE 4b COMPLETE: ${OUT_BLOCK} saved (pins released with plan $plan, $moved1 moved). Log: ${LOG_DIR}/4b_pin_replace.log"

}
