# =============================================================================
# floorplan.tcl -- script 3 of the back-end re-run: die, core, rows, don't-use cells, checkpoint fp
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
#   (VERIFY -file / -output_log_file in icc2_shell)
#
# Input: the design library $LIB_DIR/$LIB_NAME with the block $BLK_IMPORT saved by design_setup.tcl
#   (it must have no floorplan yet).
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
unpu_require_tool_version $ICC2_VERSION            ;# VERIFY how the version is exposed (see common.tcl)
set UNPU_CHECK_CONTINUE 1
set lib_path $LIB_DIR/$LIB_NAME
if {![file exists $lib_path]} {
  unpu_die "design library not found: $lib_path. design_setup.tcl runs first (same UNPU_WORK and UNPU_RUN_TAG)"
}
unpu_stage_begin floorplan run [list $lib_path]
unpu_open_stage $lib_path $LIB_NAME $BLK_IMPORT
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
unpu_run_logged [list initialize_floorplan -boundary $FP_BOUNDARY -core_offset $CORE_OFFSET] {}

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
      set sname [get_attribute $row0 site_name]                      ;# VERIFY
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
  if {$util eq ""} {
    unpu_warn "no core utilization found in the report text (informational only)"
    set util unavailable
  }
} else {
  set chip unavailable; set core unavailable; set util unavailable
  unpu_check_pass floorplan chip_area 0 "[lindex $pa 1]"
  unpu_check_pass floorplan core_area 0 "report text did not parse (see floorplan_design.rpt)"
}
# utilisation: informational (DC cell area 429,161 um2 -> about 58.5% at the plan's die), not asserted
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
    set_dont_use $coll
  }
}
unpu_check_pass floorplan dont_use_matched [expr {$matched_total == $EXPECT_DONT_USE_MATCHED}] \
    "$matched_total cells matched by the patterns, expected $EXPECT_DONT_USE_MATCHED (18.15)"
# VERIFY: the -filter form is the one ndm_check.tcl uses
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
