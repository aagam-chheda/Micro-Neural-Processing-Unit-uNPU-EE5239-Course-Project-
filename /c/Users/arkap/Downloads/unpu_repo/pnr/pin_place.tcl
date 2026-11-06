# =============================================================================
# pin_place.tcl -- script 9 of the back-end re-run: coarse placement, then the tool places the signal pins
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage B4; the first run set the pins by hand
# (docs/session-handoff.md 18.15: set_block_pin_constraints -self -hard_constraints location, set_individual_pin_constraints ... -location,
# place_pins -self). Here the tool decides the ORDER and POSITION of every signal pin, clk included, after a coarse placement, so that
# each pin lands near the cells it feeds (the antenna failure of the first run was a pin 180 um from its only load). What stays fixed is
# the SIDE and the LAYER of each group: right edge M3 for the APB group (PIN_PORTS_RIGHT), top edge M2 for the DMA group (PIN_PORTS_TOP);
# no signal pin on the left or the bottom (the bottom carries the power pins). Not used, on purpose: -location (it would fix the positions)
# and -hard_constraints location.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1
#   icc2_shell -file $UNPU_REPO/pnr/pin_place.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/pin_place.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Input: the library $LIB_DIR/$LIB_NAME with the block $BLK_PWR (power.tcl). Output: block $BLK_PINS; reports in $RPT_DIR:
#   pin_place_constraints.rpt   the block and individual pin constraints as the tool holds them
#   pin_place_report.rpt        report_pin_placement
#   pin_order.txt               THE REPORT FOR THE TOP-LEVEL TEAM: one line per pin (port, edge, coordinate along the edge, layer),
#                               sorted by edge and coordinate, a summary per bus, and the position of clk and rst_n
#   and $LOG_DIR/manifest_pin_place.txt.
# The coarse placement exists only to give the pin placer something to work with; placement.tcl (next) redoes the placement with the pins fixed.
#
# SIDE NUMBERS. The usage text of set_individual_pin_constraints -sides does not say which integer is which edge. PIN_SIDE_RIGHT (3) and
# PIN_SIDE_TOP (2) are a GUESS (clockwise from the left edge: 1 left, 2 top, 3 right, 4 bottom). The geometry checks measure where the pins
# really land; if a group is on the wrong edge the CHECK names the edge each group landed on and the numbers to try:
#   setenv UNPU_PIN_SIDE_RIGHT <n> ; setenv UNPU_PIN_SIDE_TOP <m>      and run the script again (nothing was saved).
#
# PIN PITCH. -pin_spacing_distance is "Minimum distance between adjacent block pins in micron"; the text does not say whether it is centre
# to centre or edge to edge. PIN_PITCH (6.72) is passed. If the tool measures edge to edge the real centre pitch is at least
# PIN_PITCH + PIN_WIDTH, if centre to centre at least PIN_PITCH: both satisfy the check below (centre to centre >= PIN_PITCH - tolerance).
#
# Geometry reading: a terminal box touches the die edge when it reaches the boundary (right: urx >= DIE_SIZE; top: ury >= DIE_SIZE; left:
# llx <= 0; bottom: lly <= 0), within PIN_TOLERANCE_UM; the width of a pin is its extent ALONG the edge, the length its extent ACROSS it.
# The terminal bbox format is the one power.tcl reads ("{llx lly} {urx ury}").
#
# If a CHECK fails the script prints every verdict and stops BEFORE saving $BLK_PINS.
# Rerun: nothing is saved after the last checkpoint of a failed run; a checkpoint name that exists is never reused. A run that failed
# before "RESULT pin_place block_saved_pins" can be run again as it is (different side numbers via the environment); after it use a new
# UNPU_BLK_PINS. No reliable remove-block command is known.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

# ---- 1. start ----------------------------------------------------------------
unpu_require_tool_version $ICC2_VERSION            ;# sh_product_version (confirmed, VERIFY_STATUS.md)
unpu_require_syn_profile
set UNPU_CHECK_CONTINUE 1
set lib_path $LIB_DIR/$LIB_NAME
if {![file exists $lib_path]} {
  unpu_die "design library not found: $lib_path. [unpu_prev_msg power $BLK_PWR]"
}
unpu_stage_begin pin_place run [list $lib_path]
unpu_derive_die check          ;# the die from the synthesis area of UNPU_SYN_PROFILE (task 054); the floorplan record must name the same profile and die
if {$UNPU_CHECK_FAILED > 0} { unpu_die "the floorplan record does not match this run (UNPU_SYN_PROFILE / die): see the CHECK line above; nothing is done" }
if {![catch {get_blocks -quiet $BLK_PINS} existing]} {
  if {[sizeof_collection $existing] > 0} {
    unpu_die "block $BLK_PINS already exists in $lib_path; see the Rerun note in the header of pin_place.tcl (a new name in UNPU_BLK_PINS)"
  }
} else {
  unpu_warn "could not list the blocks of the library ($existing); cannot tell whether block $BLK_PINS exists already"
}
unpu_open_stage $lib_path $LIB_NAME $BLK_PWR power

# ---- 2. the ports and the two groups ---------------------------------------------
set ports {}
foreach_in_collection p [get_ports *] { lappend ports [get_object_name $p] }
unpu_check_pass pin_place ports_count [expr {[llength $ports] == $EXPECT_PORTS}] "[llength $ports] ports in the block, $EXPECT_PORTS expected (EXPECT_PORTS)"
lassign [unpu_split_ports $ports $PIN_PORTS_RIGHT] ports_right rest
lassign [unpu_split_ports $rest $PIN_PORTS_TOP] ports_top ports_other
unpu_result pin_place ports_right_group [llength $ports_right]
unpu_result pin_place ports_top_group [llength $ports_top]
unpu_check_pass pin_place ports_all_in_a_group [expr {[llength $ports_other] == 0 && [llength $ports_right] + [llength $ports_top] == [llength $ports]}] \
    "every port is in exactly one group: right [llength $ports_right], top [llength $ports_top], in neither: [llength $ports_other] {[lrange $ports_other 0 9]}"

# ---- 3. preconditions ----------------------------------------------------------------
# 3a. the terminals are the power ones of power.tcl, and as many as the stripes (same queries as power.tcl)
lassign [unpu_power_terminals] power_names power_boxes
# NOT compared with a count of stripe shapes: power.tcl creates its extension rectangles with the same shape_use (stripe), so after
# power.tcl that query counts the stripes AND the extension rectangles (power.tcl read the stripes once, before creating its own shapes).
# The terminals are power.tcl's result: one per stripe, checked there (terminals_count).
set nterm_all [sizeof_collection [get_terminals -quiet]]
unpu_result pin_place power_terminals [llength $power_names]
unpu_check_pass pin_place pre_power_terminals [expr {[llength $power_names] > 0 && [llength $power_boxes] == [llength $power_names]}] \
    "[llength $power_names] power terminals on $PG_NET_POWER/$PG_NET_GROUND, [llength $power_boxes] with a readable box (all readable, at least one expected; power.tcl checked one terminal per stripe)"
unpu_check_pass pin_place pre_no_signal_terminals [expr {$nterm_all == [llength $power_names]}] \
    "$nterm_all terminals in the block, [llength $power_names] on the power nets: [expr {$nterm_all - [llength $power_names]}] signal terminal(s) exist already (0 expected)"
# 3b. no cell is placed yet. VERIFY: get_cells -filter "is_hierarchical==false && physical_status==unplaced". The filter is validated here:
# before any placement it must count ALL leaf cells; if it does not, it cannot be trusted after the placement either.
proc pp_unplaced {} {
  if {[catch {sizeof_collection [get_cells -quiet -hierarchical -filter "is_hierarchical==false && physical_status==unplaced"]} n]} { return unavailable }
  return $n
}
set nleaf [sizeof_collection [get_cells -hierarchical -filter "is_hierarchical==false"]]
set unpl0 [pp_unplaced]
set filter_ok 0
if {$unpl0 eq "unavailable" || $unpl0 == 0} {
  unpu_warn "cannot tell whether the cells are placed: the unplaced count is $unpl0 for $nleaf leaf cells (VERIFY the attribute physical_status and its value unplaced). The check after the placement is then a Warning too."
} elseif {$unpl0 != $nleaf} {
  unpu_check_pass pin_place pre_nothing_placed 0 "$unpl0 of $nleaf leaf cells are unplaced: some cells are already placed (none expected)"
} else {
  set filter_ok 1
  unpu_check_pass pin_place pre_nothing_placed 1 "all $nleaf leaf cells are unplaced"
}
if {$UNPU_CHECK_FAILED > 0} { unpu_die "a precondition failed; nothing is placed (see the CHECK lines above)" }

# ---- 4. coarse placement ---------------------------------------------------------------
# acts on the whole block; the scenario does not matter (no timing option is given)
set cp [unpu_run_logged [list create_placement -floorplan] {Error Warning}]
set unpl1 [pp_unplaced]
unpu_result pin_place unplaced_after_placement $unpl1
if {$filter_ok} {
  unpu_check_pass pin_place cells_placed [expr {$unpl1 ne "unavailable" && $unpl1 == 0}] "$unpl1 of $nleaf leaf cells unplaced after create_placement -floorplan (0 expected)"
} else {
  unpu_warn "placement not verified: the unplaced count after create_placement is $unpl1 but the attribute filter could not be validated before it"
}

# ---- 5. pin constraints (options from the usage text only) ----------------------------------------
# block level: width, length, minimum distance (see PIN PITCH above), and the two sides that may carry signal pins (so nothing lands on the
# left or the bottom). Individual level: per group the side number and the layer.
unpu_run_logged [list set_block_pin_constraints -self -width $PIN_WIDTH -length $PIN_LENGTH -pin_spacing_distance $PIN_PITCH \
    -sides [list $PIN_SIDE_RIGHT $PIN_SIDE_TOP]] {}
# get_ports -exact: the names contain [ ], which must not be read as a pattern. VERIFY: -ports takes the collection
unpu_run_logged [list set_individual_pin_constraints -ports [get_ports -exact $ports_right] -sides $PIN_SIDE_RIGHT \
    -allowed_layers $PIN_LAYER_RIGHT -width $PIN_WIDTH -length $PIN_LENGTH] {}
unpu_run_logged [list set_individual_pin_constraints -ports [get_ports -exact $ports_top] -sides $PIN_SIDE_TOP \
    -allowed_layers $PIN_LAYER_TOP -width $PIN_WIDTH -length $PIN_LENGTH] {}
# the constraints as the tool holds them (VERIFY: options of the two report commands are not in the probe; none are used)
set rb [unpu_report pin_place constraints_block "report_block_pin_constraints"]
set ri [unpu_report pin_place constraints_individual "report_individual_pin_constraints"]
set fh [open [file join $RPT_DIR pin_place_constraints.rpt] w]
puts $fh "# report_block_pin_constraints\n$rb\n# report_individual_pin_constraints\n$ri"
close $fh

# ---- 6. place the pins -----------------------------------------------------------------------------
set pt [unpu_run_logged [list place_pins -self] {Error Warning}]

# ---- 7. read the terminals: every terminal that is not on a power net is a signal pin ------------------
array set is_power {}
foreach n $power_names { set is_power($n) 1 }
set records {}
set unreadable {}
foreach_in_collection t [get_terminals -quiet] {
  set tn [get_object_name $t]
  if {[info exists is_power($tn)]} continue
  set box [unpu_parse_bbox [get_attribute $t bbox]]
  set layer [unpu_attr_name_safe $t layer]   ;# the layer attribute may be an object handle (`_sel22` in power.tcl, task 061): its name
  # the port of the terminal. VERIFY: attribute port; otherwise the terminal name is taken as the port name
  if {[catch {get_attribute $t port} pobj] || $pobj eq ""} { set port $tn } elseif {[catch {get_object_name $pobj} port]} { set port $pobj }
  if {[llength $box] != 4} { lappend unreadable $tn; continue }
  lappend records [unpu_pin_record $port $box $layer $DIE_SIZE $PIN_TOLERANCE_UM]
}
unpu_result pin_place signal_terminals [llength $records]
unpu_check_pass pin_place terminals_readable [expr {[llength $unreadable] == 0}] "terminals whose bbox could not be read: [llength $unreadable] {[lrange $unreadable 0 9]}"

# ---- 8. checks ----------------------------------------------------------------------------------------
proc pp_names {records} { set o {}; foreach r $records { lappend o [lindex $r 0] }; return $o }
set dups [unpu_pin_duplicates $records]
unpu_check_pass pin_place terminals_count [expr {[llength $records] == $EXPECT_PORTS && [llength $dups] == 0}] \
    "[llength $records] signal terminals, $EXPECT_PORTS expected (one per port); ports with more than one terminal: {$dups}"
set recorded {}
foreach r $records { lappend recorded [lindex $r 0] }
set missing {}
foreach p $ports { if {[lsearch -exact $recorded $p] < 0} { lappend missing $p } }
unpu_check_pass pin_place terminals_every_port [expr {[llength $missing] == 0}] "ports without a terminal: [llength $missing] {[lrange $missing 0 9]}"
set rr [unpu_pins_of $records $ports_right]
set tt [unpu_pins_of $records $ports_top]
set redge [unpu_pin_dominant_edge $rr]
set tedge [unpu_pin_dominant_edge $tt]
unpu_result pin_place right_group_edges [unpu_pin_edge_counts $rr]
unpu_result pin_place top_group_edges [unpu_pin_edge_counts $tt]
set off_r [unpu_pins_off_edge $rr right]
set off_t [unpu_pins_off_edge $tt top]
set diag [unpu_pin_side_diagnosis $PIN_SIDE_RIGHT $PIN_SIDE_TOP $redge $tedge]
set diag_txt [expr {$diag eq "" ? "" : " DIAGNOSIS: $diag"}]
unpu_check_pass pin_place right_group_on_right_edge [expr {[llength $rr] > 0 && [llength $off_r] == 0}] \
    "right (APB) group: [llength $rr] pins, edges {[unpu_pin_edge_counts $rr]}, [llength $off_r] off the right edge {[lrange [pp_names $off_r] 0 5]}.$diag_txt"
unpu_check_pass pin_place top_group_on_top_edge [expr {[llength $tt] > 0 && [llength $off_t] == 0}] \
    "top (DMA) group: [llength $tt] pins, edges {[unpu_pin_edge_counts $tt]}, [llength $off_t] off the top edge {[lrange [pp_names $off_t] 0 5]}.$diag_txt"
set badl {}
foreach r $rr { if {[lindex $r 5] ne $PIN_LAYER_RIGHT} { lappend badl "[lindex $r 0]=[lindex $r 5]" } }
foreach r $tt { if {[lindex $r 5] ne $PIN_LAYER_TOP} { lappend badl "[lindex $r 0]=[lindex $r 5]" } }
unpu_check_pass pin_place layers [expr {[llength $badl] == 0}] "right group on $PIN_LAYER_RIGHT, top group on $PIN_LAYER_TOP; not: [llength $badl] {[lrange $badl 0 5]}"
set wrong_edge {}
foreach r $records { if {[lindex $r 1] eq "left" || [lindex $r 1] eq "bottom"} { lappend wrong_edge "[lindex $r 0]@[lindex $r 1]" } }
unpu_check_pass pin_place no_left_bottom_pins [expr {[llength $wrong_edge] == 0}] "signal pins on the left or bottom edge: [llength $wrong_edge] {[lrange $wrong_edge 0 5]}"
set bads [unpu_pin_bad_size $records $PIN_WIDTH $PIN_LENGTH $PIN_TOLERANCE_UM]
unpu_check_pass pin_place pin_size [expr {[llength $bads] == 0}] "pins whose width/length is not $PIN_WIDTH x $PIN_LENGTH um: [llength $bads] {[lrange $bads 0 3]}"
foreach e {right top left bottom} {
  lassign [unpu_pin_gaps $records $e] n mn mx
  unpu_result pin_place gap_${e}_pins_min_max "$n pins, smallest gap [expr {$mn eq {} ? {n/a} : [format %.3f $mn]}] um, largest [expr {$mx eq {} ? {n/a} : [format %.3f $mx]}] um"
}
set close [unpu_pin_close_pairs $records $PIN_PITCH $PIN_TOLERANCE_UM]
unpu_check_pass pin_place pitch [expr {[llength $close] == 0}] "neighbouring pins closer than $PIN_PITCH um centre to centre (tolerance $PIN_TOLERANCE_UM): [llength $close] {[lrange $close 0 3]}"
set ovl [unpu_pin_overlaps $records $PIN_TOLERANCE_UM]
unpu_check_pass pin_place no_overlap [expr {[llength $ovl] == 0}] "pins that overlap another pin: [llength $ovl] {[lrange $ovl 0 3]}"
set corner [unpu_pin_corner_pins $records $DIE_SIZE $PIN_CORNER_KEEPOUT_UM]
unpu_check_pass pin_place corner_keepout [expr {[llength $corner] == 0}] "pins within $PIN_CORNER_KEEPOUT_UM um of a corner (a safety margin of 2 x pitch, not a kit rule): [llength $corner] {[lrange $corner 0 5]}"
set pov [unpu_pin_power_overlaps $records $power_boxes $PIN_TOLERANCE_UM]
unpu_check_pass pin_place no_power_overlap [expr {[llength $pov] == 0}] "signal pins that overlap a power terminal: [llength $pov] {[lrange $pov 0 3]}"

# ---- 9. reports for the top-level team ---------------------------------------------------------------------
set lines [unpu_pin_order_lines $records]
set fh [open [file join $RPT_DIR pin_order.txt] w]
puts $fh "# pin order of $TOP_NAME after place_pins -self (block $BLK_PINS, die $DIE_SIZE um); coordinate = centre along the edge from the lower-left corner"
puts $fh "# pin width $PIN_WIDTH um, length $PIN_LENGTH um, minimum centre pitch $PIN_PITCH um; right edge $PIN_LAYER_RIGHT, top edge $PIN_LAYER_TOP"
puts $fh "# port                   edge     coordinate  layer"
foreach l $lines { puts $fh $l }
puts $fh "\n# per bus: bit numbers in position order (increasing coordinate)"
foreach l [unpu_pin_bus_summary $records] { puts $fh $l }
close $fh
foreach clkp [list clk rst_n] {
  set found {}
  foreach r $records { if {[lindex $r 0] eq $clkp} { set found $r } }
  if {$found ne ""} { unpu_result pin_place pin_$clkp "[lindex $found 1] edge, [format %.3f [lindex $found 2]] um along it, layer [lindex $found 5]" } else { unpu_result pin_place pin_$clkp "no terminal" }
}
unpu_info "the clk pin position above goes to the top level and to the PM (clock latency and skew at clk, question Q14)"
# report_pin_placement. VERIFY: no options are used (the usage text of this command was not probed)
unpu_report pin_place report report_pin_placement

# ---- 10. verdict, then the next block -------------------------------------------------------------------------
unpu_checks_finish pin_place             ;# stops here if any check failed: $BLK_PINS is not saved
unpu_checkpoint $BLK_PINS
unpu_result pin_place block_saved_pins $BLK_PINS
unpu_info "done: block $BLK_PINS saved in $lib_path; pin order for the top level: $RPT_DIR/pin_order.txt. Next: placement.tcl."
exit 0
