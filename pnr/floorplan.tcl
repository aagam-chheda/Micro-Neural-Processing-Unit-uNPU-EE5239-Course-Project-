# =============================================================================
# floorplan.tcl -- script 3 of the back-end re-run: die (derived from the synthesis area), core, rows, don't-use cells, checkpoint fp
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage B2 and the don't-use
# part of B3; commands that worked in the first run: docs/session-handoff.md 18.14 (floorplan) and 18.15
# (don't-use cells). Power (nets, grid, pins) is NOT here: it is power.tcl, the next script.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1                 # the run that design_setup.tcl was run in
#   icc2_shell -file $UNPU_REPO/pnr/floorplan.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/floorplan.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Input: the design library $LIB_DIR/$LIB_NAME with the block $BLK_IMPORT saved by design_setup.tcl
#   (it must have no floorplan yet) and the DC area report of the chosen synthesis profile, syn/out/$UNPU_SYN_PROFILE/unpu_top.area
#   (UNPU_SYN_PROFILE is required). The die is DERIVED: core area = cell area / FP_START_UTIL (0.60), square core, side rounded up to a
#   whole number of rows, die = core + 2 x 5.6 um (unpu_derive_die, common.tcl). UNPU_DIE_SIZE is an experiment knob that replaces it (Warning).
#   The profile and the die are written to $RUN_DIR/floorplan_profile.txt; every later script CHECKS that its own derivation equals that record.
# Output: block $BLK_FP in the same library (the block $BLK_IMPORT on disk is never touched);
#   $RPT_DIR/floorplan_design.rpt; $LOG_DIR/manifest_floorplan.txt.
# Never: changes power, pins, placement; touches the library of the first run; writes into the kit.
#
# If any CHECK fails the script still prints every verdict, then stops BEFORE the checkpoint (nothing is
# saved from a floorplan that failed its checks).
#
# Rerun: if floorplan.tcl failed before "RESULT floorplan block_saved", nothing was saved and the block
# $BLK_IMPORT on disk is unchanged, so the script can simply be run again. Only after a SUCCESSFUL run (block
# $BLK_FP saved) does a different floorplan need a fresh library: a new UNPU_RUN_TAG, or UNPU_LIB_OVERWRITE=1
# and a rerun of design_setup.tcl first.
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
  unpu_die "design library not found: $lib_path. [unpu_prev_msg design_setup $BLK_IMPORT]"
}
unpu_stage_begin floorplan run [list $lib_path]
unpu_derive_die record          ;# the die from the synthesis area of UNPU_SYN_PROFILE (task 054) and the record of this floorplan
unpu_open_stage $lib_path $LIB_NAME $BLK_IMPORT design_setup
# the derived die, core, rows and the numbers they come from (task 054)
unpu_result floorplan syn_profile $SYN_PROFILE
unpu_result floorplan syn_cell_area_um2 $SYN_CELL_AREA
unpu_result floorplan start_utilisation $FP_START_UTIL
unpu_result floorplan core_side_um $CORE_SIDE
unpu_result floorplan rows_derived $FP_ROWS
unpu_result floorplan die_side_um $DIE_SIZE
unpu_result floorplan die_area_um2 [format %.2f [expr {$DIE_SIZE * $DIE_SIZE}]]
unpu_result floorplan ports_in_block [sizeof_collection [get_ports *]]     ;# sanity line, not asserted
# the block from design_setup must have no floorplan yet
# VERIFY (server): get_site_rows lists the site rows of the current block (empty before initialize_floorplan)
set rows_before [sizeof_collection [get_site_rows -quiet]]
if {$rows_before != 0} {
  unpu_die "block $BLK_IMPORT already has $rows_before site row(s); floorplan.tcl needs a block without a floorplan (rerun from design_setup.tcl with UNPU_LIB_OVERWRITE=1, or use a new UNPU_RUN_TAG)"
}

# the checkpoint block must not exist yet (a rerun never overwrites it silently).
# VERIFY (server): get_blocks -quiet <name> lists the blocks of the current library by name
if {![catch {get_blocks -quiet $BLK_FP} existing]} {
  if {[sizeof_collection $existing] > 0} {
    unpu_die "block $BLK_FP already exists in $lib_path. Floorplan again from a fresh library: rerun design_setup.tcl with UNPU_LIB_OVERWRITE=1 (or a new UNPU_RUN_TAG), then floorplan.tcl"
  }
} else {
  unpu_warn "could not list the blocks of the library ($existing); cannot tell whether block $BLK_FP exists already"
}

# ---- helpers -------------------------------------------------------------------
# write a report with redirect -file, read it back, print it, return the text (VERIFY redirect -file)
proc fp_report {name cmd} {
  global RPT_DIR
  set f [file join $RPT_DIR floorplan_${name}.rpt]
  unpu_no_kit_write $f
  if {[catch {redirect -file $f [list uplevel #0 $cmd]} msg]} { unpu_die "report '$cmd' failed: $msg" }
  if {![file exists $f]} { unpu_die "report '$cmd' did not write $f" }
  set fh [open $f r]; set text [read $fh]; close $fh
  unpu_info "--- $cmd -> $f ---"
  puts -nonewline $text
  if {![string match *\n $text]} { puts "" }
  return $text
}

# ---- 2. the floorplan (handoff 18.14) -------------------------------------------
# MISTAKE OF THE FIRST ATTEMPT (18.14): initialize_floorplan -boundary {{0 0} {817.6 817.6}} -core_offset 5.6
# made that boundary the CORE and added the offset OUTSIDE it: die 828.8 x 828.8 instead of 817.6, chip area
# 686,909.44, 146 rows. So -boundary is the CORE rectangle and the die is boundary + core_offset on every side.
# FP_BOUNDARY in params.tcl is built that way: core corners at CORE_OFFSET and at DIE_SIZE - CORE_OFFSET.
unpu_info "initialize_floorplan -boundary $FP_BOUNDARY -core_offset $CORE_OFFSET (core is the boundary; die = boundary + offset)"
set fptext [unpu_run_logged [list initialize_floorplan -boundary $FP_BOUNDARY -core_offset $CORE_OFFSET] {}]

# ---- 3. checks -----------------------------------------------------------------
# die: boundary_bbox attribute of the block (18.14), VERIFY the value format "{llx lly} {urx ury}"
set tol [expr {$FP_TOLERANCE * $DIE_SIZE}]
set bb [unpu_parse_bbox [get_attribute [current_block] boundary_bbox]]
if {[llength $bb] == 4} {
  lassign $bb x0 y0 x1 y1
  set ok [expr {abs($x0) <= $tol && abs($y0) <= $tol && abs($x1 - $DIE_SIZE) <= $tol && abs($y1 - $DIE_SIZE) <= $tol}]
  unpu_check_pass floorplan die_bbox $ok "boundary_bbox {{$x0 $y0} {$x1 $y1}}, expected {{0 0} {$DIE_SIZE $DIE_SIZE}} (tolerance $tol um)"
  set die_w [expr {$x1 - $x0}]
} else {
  unpu_check_pass floorplan die_bbox 0 "boundary_bbox attribute could not be read as four numbers: '[get_attribute [current_block] boundary_bbox]'"
  set die_w "unknown"
}
# rows: VERIFY get_site_rows
set nrows [sizeof_collection [get_site_rows -quiet]]
unpu_check_pass floorplan rows [expr {$nrows == $FP_ROWS}] "$nrows site rows, expected $FP_ROWS (core side $CORE_SIDE um / row height $ROW_HEIGHT um)"
# site: the site of the first row, 0.56 x 5.6 um. VERIFY the attribute names (site_name on a site row;
# width/height on the site definition); a failure to read is a Warning, not a check
set site_info "unreadable"
if {[catch {
      set row0 [index_collection [get_site_rows] 0]                  ;# VERIFY
      set sname [unpu_attr_name $row0 site_name]                     ;# VERIFY (name, even if the tool returns an object, task 061)
      set sdef [get_site_defs $sname]                                ;# VERIFY
      set sw [get_attribute $sdef width]                             ;# VERIFY
      set sh [get_attribute $sdef height]                            ;# VERIFY
    } smsg]} {
  unpu_warn "could not read the site of the rows ($smsg); the site check was skipped. Expected site $SITE_NAME, $SITE_WIDTH x $ROW_HEIGHT um"
} else {
  set site_info "$sname ${sw}x${sh}"
  unpu_check_pass floorplan site [expr {$sname eq $SITE_NAME && abs($sw - $SITE_WIDTH) < 1e-6 && abs($sh - $ROW_HEIGHT) < 1e-6}] \
      "rows use site $sname, $sw x $sh um, expected $SITE_NAME, $SITE_WIDTH x $ROW_HEIGHT"
}
# areas: report_design -floorplan, parsed by a pure-Tcl procedure; the report file is the evidence
set rd [fp_report design {report_design -floorplan}]
set pa [unpu_parse_floorplan_areas $rd]
set expect_chip [expr {$DIE_SIZE * $DIE_SIZE}]
if {[lindex $pa 0] eq "ok"} {
  lassign $pa st chip core util detail
  unpu_check_pass floorplan chip_area [expr {abs($chip - $expect_chip) <= 0.01}] "chip area $chip um2, expected DIE_SIZE^2 = $expect_chip"
  unpu_check_pass floorplan core_area [expr {abs($core - $CORE_AREA) <= 0.01}] "core area $core um2, expected $CORE_AREA"
  # the utilisation (task 061): report_design -floorplan prints none; the message of initialize_floorplan does ("Core utilization ratio = 59.56%").
  # Sources: the report text, the initialize_floorplan message, and the computation cell area / core area from the DC area (SYN_CELL_AREA).
  if {$util eq ""} { set util [unpu_parse_core_util_message $fptext] }
  set util_calc [expr {100.0 * $SYN_CELL_AREA / $CORE_AREA}]
  if {$util eq ""} {
    unpu_warn "no core utilization in the report_design text or in the initialize_floorplan message; using cell area / core area"
    set util [format %.2f $util_calc]
  }
  unpu_result floorplan core_utilization_computed_percent [format %.2f $util_calc]
  if {abs($util - $util_calc) > $UTIL_CROSSCHECK_PP} {
    unpu_warn "core utilization: the tool says $util percent, cell area / core area gives [format %.2f $util_calc] percent (more than $UTIL_CROSSCHECK_PP percentage points apart)"
  }
} else {
  set chip unavailable; set core unavailable; set util unavailable
  unpu_check_pass floorplan chip_area 0 "[lindex $pa 1]"
  unpu_check_pass floorplan core_area 0 "report text did not parse (see floorplan_design.rpt)"
}
# utilisation: a RESULT (the tool's own number, cross-checked with cell area / core area), not asserted
unpu_result floorplan core_utilization_percent $util

# ---- 4. don't-use cells (handoff 18.15) ----------------------------------------
set matched_total 0
array set per_pattern {}
foreach pat $DONT_USE_PATTERNS {
  set coll [get_lib_cells -quiet */$pat]
  set n [sizeof_collection $coll]
  set per_pattern($pat) $n
  incr matched_total $n
  if {$n == 0} {
    if {[lsearch -exact $DONT_USE_EXPECT_EMPTY $pat] >= 0} {
      unpu_info "don't-use pattern $pat matched 0 library cells (expected: those cells have no timing view and are not in the NDM, 18.15)"
    } else {
      unpu_warn "don't-use pattern $pat matched 0 library cells (not expected)"
    }
  } else {
    unpu_info "don't-use pattern $pat matched $n library cell(s)"
    # set_dont_use is NOT a command in icc2_shell U-2022.12-SP3 (help probe: "No commands matched", CMD-040). The attribute is set
    # on the library cells (set_attribute usage: -objects -name -value); this prints ATTR-12 "block-level overrides" (18.15).
    unpu_run_logged [list set_attribute -objects $coll -name dont_use -value true] {ATTR-}
  }
}
unpu_check_pass floorplan dont_use_matched [expr {$matched_total == $EXPECT_DONT_USE_MATCHED}] \
    "$matched_total cells matched by the patterns, expected $EXPECT_DONT_USE_MATCHED (18.15)"
# the -filter form is the one ndm_check.tcl uses (confirmed by the server run of ndm_check, VERIFY_STATUS.md)
set dnu [get_lib_cells -quiet -filter "dont_use==true" */*]
set dnu_names {}
foreach_in_collection c $dnu { lappend dnu_names [lindex [split [get_object_name $c] /] end] }
set ndnu [llength $dnu_names]
unpu_check_pass floorplan dont_use_count [expr {$ndnu == $EXPECT_DONT_USE_COUNT}] \
    "$ndnu cells with dont_use==true, expected $EXPECT_DONT_USE_COUNT ($EXPECT_DONT_USE_MATCHED matched by the patterns + [llength $LIB_DONT_USE_CELLS] flagged by the library)"
set lib_missing {}
foreach c $LIB_DONT_USE_CELLS { if {[lsearch -exact $dnu_names $c] < 0} { lappend lib_missing $c } }
unpu_check_pass floorplan dont_use_library_cells [expr {[llength $lib_missing] == 0}] \
    "library-flagged cells {$LIB_DONT_USE_CELLS} are among the dont_use cells; missing: {$lib_missing}"

# ---- 5. verdict, then the checkpoint -------------------------------------------
unpu_checks_finish floorplan         ;# stops here if any check failed: nothing is saved
unpu_checkpoint $BLK_FP

# ---- 6. summary ----------------------------------------------------------------
unpu_result floorplan die_um $die_w
unpu_result floorplan core_um $CORE_SIDE
unpu_result floorplan rows $nrows
unpu_result floorplan site $site_info
unpu_result floorplan chip_area_um2 $chip
unpu_result floorplan core_area_um2 $core
unpu_result floorplan dont_use_total $ndnu
foreach pat $DONT_USE_PATTERNS { unpu_result floorplan dont_use_count_$pat $per_pattern($pat) }
unpu_result floorplan block_saved $BLK_FP
unpu_info "done: block $BLK_FP saved in $lib_path"
exit 0
