# =============================================================================
# power.tcl -- script 4 of the back-end re-run: power nets, M1 rails, TOP_M stripes, the macro's VDD/VSS
#              pins on the bottom edge, checks, checkpoint pwr
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage B3; commands that worked
# in the first run: docs/session-handoff.md 18.14 (nets, connect_pg_net), 18.15 (the grid), 18.21 (the bottom
# power pins and the mistake made there). In the first run the pins were added by hand after routing; here they
# are part of the power step and are counted.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1                 # the run that floorplan.tcl was run in
#   icc2_shell -file $UNPU_REPO/pnr/power.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/power.log
#   (VERIFY -file / -output_log_file in icc2_shell)
#
# Input: the design library $LIB_DIR/$LIB_NAME with the block $BLK_FP saved by floorplan.tcl (no power yet).
# Output: block $BLK_PWR in the same library ($BLK_FP on disk is never touched); $LOG_DIR/manifest_power.txt.
# Never: places cells, creates signal pins, touches the library of the first run, writes into the kit.
#
# Order: nets -> connect_pg_net -> grid (compile_pg) -> read the stripe list ONCE -> one extension rectangle and
# one terminal per stripe (loop over THAT list; the first run looped over a fresh query and gave one stripe
# a second extension, 18.21) -> checks -> checkpoint. Floating standard cells are EXPECTED at this point (nothing
# is placed: 18.15 saw all 12,487); the check after placement belongs to placement.tcl.
#
# If any CHECK fails the script still prints every verdict, then stops BEFORE the checkpoint.
# Rerun: if power.tcl failed before "RESULT power block_saved", nothing was saved and the block $BLK_FP on disk is
# unchanged, so it can simply be run again. Only after a SUCCESSFUL run (block $BLK_PWR saved) does a different
# power grid need a fresh library: a new UNPU_RUN_TAG, or UNPU_LIB_OVERWRITE=1 and a rerun of design_setup.tcl
# and floorplan.tcl first.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

# ---- 1. start ----------------------------------------------------------------
unpu_require_tool_version $ICC2_VERSION            ;# VERIFY how the version is exposed (see common.tcl)
set UNPU_CHECK_CONTINUE 1
set lib_path $LIB_DIR/$LIB_NAME
if {![file exists $lib_path]} {
  unpu_die "design library not found: $lib_path. design_setup.tcl and floorplan.tcl run first (same UNPU_WORK and UNPU_RUN_TAG)"
}
unpu_stage_begin power run [list $lib_path]
# the checkpoint block must not exist yet. VERIFY (server): get_blocks -quiet <name>
if {![catch {get_blocks -quiet $BLK_PWR} existing]} {
  if {[sizeof_collection $existing] > 0} {
    unpu_die "block $BLK_PWR already exists in $lib_path. A different power grid needs a fresh library: new UNPU_RUN_TAG, or UNPU_LIB_OVERWRITE=1 and a rerun of design_setup.tcl and floorplan.tcl"
  }
} else {
  unpu_warn "could not list the blocks of the library ($existing); cannot tell whether block $BLK_PWR exists already"
}
unpu_open_stage $lib_path $LIB_NAME $BLK_FP
# the block must have no power yet: no P/G net, no shapes on it. VERIFY get_nets -quiet, get_shapes -of_objects
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  set ex [get_nets -quiet $n]
  if {[sizeof_collection $ex] > 0} {
    set nsh [sizeof_collection [get_shapes -quiet -of_objects $ex]]
    unpu_die "net $n already exists in block $BLK_FP ($nsh shape(s) on it); power.tcl needs a block without power"
  }
}

# ---- helpers -------------------------------------------------------------------
# collection -> text of one attribute per object, as a Tcl list
proc pw_bbox_entries {coll net} {
  set out {}
  foreach_in_collection s $coll {
    set e [unpu_box_entry $net [get_attribute $s bbox]]
    if {$e eq ""} { unpu_die "cannot read the bbox of [get_object_name $s]: '[get_attribute $s bbox]'" }
    lappend out $e
  }
  return $out
}

# ---- 2. nets (handoff 18.14) -----------------------------------------------------
unpu_run_logged [list create_net -power $PG_NET_POWER] {}
unpu_run_logged [list create_net -ground $PG_NET_GROUND] {}
set ctext [unpu_run_logged [list connect_pg_net -automatic] {}]
set parsed [unpu_parse_connect_pg $ctext [list $PG_NET_POWER $PG_NET_GROUND]]
if {$parsed eq "not parsed"} {
  unpu_warn "the connect_pg_net summary could not be parsed (layout unknown, VERIFY); counting the pins connected to each net instead"
  set parsed {}
  foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
    # VERIFY: pins of a net, leaf level
    if {[catch {sizeof_collection [get_pins -quiet -of_objects [get_nets $n] -leaf]} cnt]} { set cnt unavailable }
    lappend parsed $n $cnt
  }
}
foreach {n cnt} $parsed {
  unpu_check_pass power connected_$n [expr {$cnt ne "unavailable" && $cnt == $EXPECT_LEAF_CELLS}] \
      "$cnt pins connected to $n, expected $EXPECT_LEAF_CELLS (one per leaf cell, 18.14)"
  unpu_result power connected_pins_$n $cnt
}

# ---- 3. the grid (handoff 18.15), commands built from the parameters ---------------
set cmds [unpu_pg_commands $PG_PATTERN_RAIL $PG_PATTERN_MESH $PG_STRAT_RAIL $PG_STRAT_MESH \
              $PG_RAIL_LAYER $PG_RAIL_WIDTH $PG_STRIPE_LAYER $PG_STRIPE_WIDTH $PG_STRIPE_PITCH $PG_SPACING \
              $PG_NET_POWER $PG_NET_GROUND]
foreach c [lrange $cmds 0 3] { unpu_run_logged $c {} }
set gtext [unpu_run_logged [lindex $cmds 4] {}]        ;# compile_pg; printed by unpu_run_logged
foreach l [unpu_lines_matching $gtext {(?i)stripe|rail|via|standard cells}] { unpu_info "compile_pg: $l" }

# ---- 4. read the stripes ONCE, before creating any shape of our own ------------------
# VERIFY: get_shapes -of_objects <net> -filter "layer_name==TOP_M && shape_use==stripe" (18.21 shows this query)
set stripes {}
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  set coll [get_shapes -quiet -of_objects [get_nets $n] -filter "layer_name==$PG_STRIPE_LAYER && shape_use==$PG_STRIPE_SHAPE_USE"]
  set stripes [concat $stripes [pw_bbox_entries $coll $n]]
}
foreach n [list $PG_NET_POWER $PG_NET_GROUND] { set nstripe_net($n) 0 }
foreach s $stripes { incr nstripe_net([lindex $s 0]) }
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  unpu_check_pass power stripes_$n [expr {$nstripe_net($n) >= 1}] "$nstripe_net($n) $PG_STRIPE_LAYER stripe(s) on $n (the count is not asserted beyond >= 1: the die is bigger than in the first run)"
}
set bad_w {}; set bad_y {}
foreach s $stripes {
  lassign $s n x0 y0 x1 y1
  if {abs(($x1 - $x0) - $PG_STRIPE_WIDTH) > $PG_TOLERANCE} { lappend bad_w "$n x $x0..$x1 (width [expr {$x1 - $x0}])" }
  if {abs($y0 - $CORE_OFFSET) > $PG_TOLERANCE} { lappend bad_y "$n x $x0..$x1 (lower end $y0)" }
}
unpu_check_pass power stripe_width [expr {[llength $bad_w] == 0}] "every stripe is $PG_STRIPE_WIDTH um wide; not: {$bad_w}"
unpu_check_pass power stripe_lower_end [expr {[llength $bad_y] == 0}] "every stripe starts at the core boundary y = $CORE_OFFSET; not: {$bad_y}"
# rails: M1 shapes of the two nets; expected rows + 1 (the first run: 145 rails for 144 rows)
# VERIFY: the filter value shape_use==follow_pin is a guess; on 0 shapes the layer alone is tried, with a Warning
set nrail 0
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  incr nrail [sizeof_collection [get_shapes -quiet -of_objects [get_nets $n] -filter "layer_name==$PG_RAIL_LAYER && shape_use==$PG_RAIL_SHAPE_USE"]]
}
set rail_filter "layer $PG_RAIL_LAYER, shape_use $PG_RAIL_SHAPE_USE"
if {$nrail == 0} {
  unpu_warn "no $PG_RAIL_LAYER shapes with shape_use==$PG_RAIL_SHAPE_USE; counting every $PG_RAIL_LAYER shape of the two nets instead (the shape_use value is a guess, VERIFY)"
  foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
    incr nrail [sizeof_collection [get_shapes -quiet -of_objects [get_nets $n] -filter "layer_name==$PG_RAIL_LAYER"]]
  }
  set rail_filter "layer $PG_RAIL_LAYER only"
}
unpu_check_pass power rails [expr {$nrail == $FP_ROWS + 1}] "$nrail $PG_RAIL_LAYER rail shapes ($rail_filter), expected rows + 1 = [expr {$FP_ROWS + 1}]"
unpu_result power rails $nrail

# ---- 5. bottom power pins (handoff 18.21): one extension rectangle and one terminal per stripe -----
# The loop runs over the list `stripes` made in step 4 and nothing else: never over a fresh query (18.21).
set made {}     ;# list of {net shape terminal}
proc pw_make_pin {s} {
  global PG_STRIPE_LAYER PG_PIN_HEIGHT PG_PIN_BOTTOM_Y PG_STRIPE_SHAPE_USE
  lassign $s n x0 y0 x1 y1
  # VERIFY: create_shape -shape_type rect -layer -boundary -net -shape_use (18.21), create_terminal -of_objects (18.21)
  set shp [create_shape -shape_type rect -layer $PG_STRIPE_LAYER \
              -boundary [list [list $x0 $PG_PIN_BOTTOM_Y] [list $x1 $PG_PIN_HEIGHT]] -net $n -shape_use $PG_STRIPE_SHAPE_USE]
  set trm [create_terminal -of_objects $shp]
  return [list $n $shp $trm]
}
# no stripe at all: the check above failed; stop here (nothing can be extended)
if {[llength $stripes] == 0} { unpu_checks_finish power }
# the first stripe alone, checked, before the rest
set first [lindex $stripes 0]
lassign [pw_make_pin $first] fn fshp ftrm
if {$ftrm eq ""} { unpu_die "create_terminal returned nothing for the first extension shape '$fshp'; nothing else was created" }
set fbox [unpu_box_entry $fn [get_attribute $ftrm bbox]]
set flayer [get_attribute $ftrm layer]                          ;# VERIFY: attribute layer on a terminal (18.15 reads it on pins)
unpu_info "first extension: net $fn stripe x [lindex $first 1]..[lindex $first 3], terminal bbox {$fbox} layer $flayer"
if {$fbox eq "" || abs([lindex $fbox 1] - [lindex $first 1]) > $PG_TOLERANCE || abs([lindex $fbox 3] - [lindex $first 3]) > $PG_TOLERANCE \
    || abs([lindex $fbox 2] - $PG_PIN_BOTTOM_Y) > $PG_TOLERANCE || $flayer ne $PG_STRIPE_LAYER} {
  unpu_die "first power pin is wrong (terminal bbox {$fbox}, layer $flayer; expected x [lindex $first 1]..[lindex $first 3], y from $PG_PIN_BOTTOM_Y, layer $PG_STRIPE_LAYER); nothing else was created"
}
lappend made [list $fn $fshp $ftrm]
foreach s [lrange $stripes 1 end] { lappend made [pw_make_pin $s] }
unpu_info "created [llength $made] extension rectangle(s) with a terminal each, from a stripe list of [llength $stripes]"

# ---- 6. checks after ---------------------------------------------------------------------
set terms {}
set term_layers {}
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  # VERIFY: get_terminals -of_objects <net>
  foreach_in_collection t [get_terminals -quiet -of_objects [get_nets $n]] {
    set e [unpu_box_entry $n [get_attribute $t bbox]]
    if {$e eq ""} { unpu_die "cannot read the bbox of terminal [get_object_name $t]" }
    lappend terms $e
    lappend term_layers [get_attribute $t layer]
  }
}
set bad_layer {}
foreach l $term_layers { if {$l ne $PG_STRIPE_LAYER} { lappend bad_layer $l } }
unpu_check_pass power terminals_layer [expr {[llength $bad_layer] == 0}] "every terminal is on $PG_STRIPE_LAYER; not: {$bad_layer}"
lassign [unpu_terminals_vs_stripes $terms $stripes $DIE_SIZE $PG_PIN_BOTTOM_Y $PG_TOLERANCE] pc px pd pl po
unpu_check_pass power terminals_count [expr {[llength $pc] == 0 && [llength $terms] == [llength $stripes]}] \
    "[llength $terms] terminals for [llength $stripes] stripes; problems: {$pc}"
unpu_check_pass power terminals_xrange [expr {[llength $px] == 0}] "every terminal has the x range of its stripe; problems: {$px}"
unpu_check_pass power terminals_no_duplicate [expr {[llength $pd] == 0}] "no two terminals share a net and x range; problems: {$pd}"
unpu_check_pass power terminals_lowest_y [expr {[llength $pl] == 0}] "every terminal starts at y = $PG_PIN_BOTTOM_Y; problems: {$pl}"
unpu_check_pass power terminals_inside_die [expr {[llength $po] == 0}] "every terminal lies inside the die 0..$DIE_SIZE; problems: {$po}"
# DRC and connectivity of the grid. VERIFY: the texts of check_pg_drc and check_pg_connectivity
set dtext [unpu_run_logged [list check_pg_drc] {}]
set derr [unpu_parse_pg_drc $dtext]
unpu_check_pass power pg_drc [expr {$derr ne "not parsed" && $derr == 0}] "check_pg_drc errors: $derr (0 expected; 'not parsed' = read the log)"
set ctext2 [unpu_run_logged [list check_pg_connectivity] {}]
array set fl [unpu_parse_pg_connectivity $ctext2]
foreach {k what} {wires "floating wires" vias "floating vias" terminals "floating terminals"} {
  set v [expr {[info exists fl($k)] ? $fl($k) : "not parsed"}]
  unpu_check_pass power pg_conn_$k [expr {$v ne "not parsed" && $v == 0}] "$what: $v (0 expected)"
}
# floating standard cells are EXPECTED now (nothing is placed): RESULT and a Warning if it is not the leaf count
if {[info exists fl(cells)]} {
  unpu_result power floating_std_cells $fl(cells)
  if {$fl(cells) != $EXPECT_LEAF_CELLS} {
    unpu_warn "floating standard cells = $fl(cells), the first run saw all $EXPECT_LEAF_CELLS before placement (18.15); not a check here"
  }
} else {
  unpu_warn "floating standard cells could not be read from the check_pg_connectivity text (read the log); not a check here"
}

# ---- 7. verdict, then the checkpoint ----------------------------------------------
unpu_checks_finish power             ;# stops here if any check failed: nothing is saved
unpu_checkpoint $BLK_PWR

# ---- 8. summary: the full stripe list is the pin list the top-level team needs -------------
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  set xs {}
  foreach s $stripes { if {[lindex $s 0] eq $n} { lappend xs [lindex $s 1] } }
  unpu_result power stripes_$n [llength $xs]
  unpu_result power stripe_x_left_edges_$n [join $xs " "]
  set nt 0
  foreach t $terms { if {[lindex $t 0] eq $n} { incr nt } }
  unpu_result power terminals_$n $nt
}
unpu_result power stripe_width_um $PG_STRIPE_WIDTH
unpu_result power stripe_y_range_um "[lindex [lindex $stripes 0] 2]..[lindex [lindex $stripes 0] 4]"
unpu_result power pin_extension_y_um "$PG_PIN_BOTTOM_Y..$PG_PIN_HEIGHT"
unpu_result power block_saved $BLK_PWR
unpu_info "done: block $BLK_PWR saved in $lib_path"
exit 0
