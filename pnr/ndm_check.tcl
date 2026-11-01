# =============================================================================
# ndm_check.tcl -- check the NDM(s) written by ndm_file_gen.tcl
#
# Runs in icc2_shell (U-2022.12-SP3), the shell the NDMs are used in:
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   icc2_shell -file $UNPU_REPO/pnr/ndm_check.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/ndm_check.log
#   (setenv UNPU_REPO <your clone of the repo> and UNPU_WORK first; UNPU_RUN_TAG as in pnr/params.tcl; -file / -output_log_file: confirmed
#    on the server, VERIFY_STATUS.md; mkdir -p the log directory first)
#
# Reads $NDM_DIR/ndm_manifest.txt, creates a scratch design library
# $RUN_DIR/ndm_check_lib_<YYYYmmdd_HHMMSS> (technology file + the NDMs as reference libraries; a
# name that already exists is never reused) and
# prints one CHECK line per question. Every check runs even if an earlier one fails
# (UNPU_CHECK_CONTINUE); the script exits non-zero if any failed. The NDMs are only opened as
# reference libraries, never modified. Scratch libraries STAY ON DISK (one per check, named with the
# time); delete them by hand when they are no longer wanted. A re-check needs no new run tag.
#
# Checks (expected values from pnr/params.tcl):
#   every NDM in the manifest opens as a reference library; in mode two (default) the manifest lists exactly the main NDM
#   (534 cells, no filler) and then the filler NDM (the 3 fillers)
#   total library cells = EXPECT_TIMING_CELLS + number of fillers
#   get_lib_cells */feedth* returns exactly the filler cells, typed filler, none dont_use
#   adiode, bh01d1, cload1 exist and are dont_use; exactly 3 dont_use cells before floorplan.tcl sets the attribute
# Also printed: per reference library its name and cell count, and which NDM holds the fillers
# (single_mode_worked = yes only if the fillers are in the same library as the timing cells; on this kit it is no: LM-052,
# the server run of task 047. The default mode is two, where the fillers are in the second NDM by design.)
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

unpu_require_tool_version $ICC2_VERSION            ;# sh_product_version (confirmed, VERIFY_STATUS.md)
set UNPU_CHECK_CONTINUE 1
unpu_need_file $TECH_FILE "technology file"
set manifest $NDM_DIR/ndm_manifest.txt
unpu_need_file $manifest "NDM manifest (run ndm_file_gen.tcl first)"
unpu_stage_begin ndm_check run [list $TECH_FILE $manifest]

# ---- read the manifest (shared procedure: dies on a missing/empty file or a missing NDM) ----
set ndm_list [unpu_read_ndm_manifest $manifest]
unpu_info "NDMs to check, in reference order: $ndm_list"

# ---- scratch design library (never reused) -----------------------------------
set scratch $RUN_DIR/ndm_check_lib_[clock format [clock seconds] -format %Y%m%d_%H%M%S]
if {[file exists $scratch]} {
  unpu_die "scratch library $scratch already exists (two checks in the same second?); wait a second and rerun. A scratch library is never reused"
}
# create_lib -technology <tf> -ref_libs <paths> <path>: confirmed with ONE reference library (server run); a Tcl list for
# several (mode two, the default) is not yet exercised: VERIFY_STATUS.md.
if {[catch {create_lib -technology $TECH_FILE -ref_libs $ndm_list $scratch} msg]} {
  unpu_die "create_lib $scratch failed: $msg"
}
unpu_info "scratch library created: $scratch"
catch {report_ref_libs}     ;# confirmed (ndm_check.log); printed into the log

# ---- every NDM opens ---------------------------------------------------------
# The library name is the NDM file name without the extension (the workspace name).
set total_cells 0
array set cells_in {}
array set fillers_in {}
foreach ndm $ndm_list {
  set libname [file rootname [file tail $ndm]]
  # confirmed on the server (ndm_check.log): get_libs -quiet <name> finds a reference library by name
  set lib [get_libs -quiet $libname]
  set opened [expr {[sizeof_collection $lib] == 1}]
  unpu_check_pass ndm_check opens_$libname $opened "reference library $libname from $ndm"
  if {!$opened} { set cells_in($libname) 0; set fillers_in($libname) 0; continue }
  # confirmed on the server (534 cells): get_lib_cells <lib>/* returns the cells of one reference library
  set cells_in($libname) [sizeof_collection [get_lib_cells -quiet ${libname}/*]]
  set fillers_in($libname) 0
  foreach f $FILLER_CELLS { incr fillers_in($libname) [sizeof_collection [get_lib_cells -quiet ${libname}/$f]] }
  incr total_cells $cells_in($libname)
  unpu_result ndm_check cells_in_$libname $cells_in($libname)
  unpu_result ndm_check fillers_in_$libname $fillers_in($libname)
}

# ---- totals ------------------------------------------------------------------
set nf [llength $FILLER_CELLS]
set expect_total [expr {$EXPECT_TIMING_CELLS + $nf}]
unpu_check_pass ndm_check cells_total [expr {$total_cells == $expect_total}] \
    "$total_cells library cells in total, expected $EXPECT_TIMING_CELLS timing + $nf filler = $expect_total"
unpu_result ndm_check cells_total $total_cells

# ---- mode two: one NDM per role, in reference order (main first) -----------------------------
# The default mode (task 047: mode single does not work on this kit). The main NDM holds the 534 timing cells and NO filler,
# the second holds exactly the filler cells; the manifest lists them main first, then the fillers.
if {$NDM_MODE eq "two"} {
  set want_names [list $NDM_WS_MAIN $NDM_WS_FILL]
  set got_names {}
  foreach ndm $ndm_list { lappend got_names [file rootname [file tail $ndm]] }
  unpu_check_pass ndm_check manifest_two_libs [expr {$got_names eq $want_names}] "ndm_manifest.txt lists {$got_names}, expected {$want_names} (main first, then the fillers)"
  foreach {ln want_cells want_fill} [list $NDM_WS_MAIN $EXPECT_TIMING_CELLS 0 $NDM_WS_FILL $nf $nf] {
    set c [expr {[info exists cells_in($ln)] ? $cells_in($ln) : "not opened"}]
    set f [expr {[info exists fillers_in($ln)] ? $fillers_in($ln) : "not opened"}]
    unpu_check_pass ndm_check cells_in_${ln}_expected [expr {$c eq $want_cells}] "$ln holds $c cell(s), expected $want_cells"
    unpu_check_pass ndm_check fillers_in_${ln}_expected [expr {$f eq $want_fill}] "$ln holds $f filler cell(s), expected $want_fill"
  }
}

# ---- fillers -----------------------------------------------------------------
set fcells [get_lib_cells -quiet */feedth*]
set fnames {}
foreach_in_collection c $fcells { lappend fnames [lindex [split [get_object_name $c] /] end] }
set fnames [lsort $fnames]
unpu_check_pass ndm_check fillers_exact [expr {$fnames eq [lsort $FILLER_CELLS]}] \
    "*/feedth* returns {$fnames}, expected {[lsort $FILLER_CELLS]}"
set bad_type {}
set bad_dnu {}
# confirmed on the server: attribute names design_type and dont_use on library cells; dont_use values true/false
foreach_in_collection c $fcells {
  if {[get_attribute $c design_type] ne "filler"} { lappend bad_type "[get_object_name $c]=[get_attribute $c design_type]" }
  if {[string is true -strict [get_attribute $c dont_use]]} { lappend bad_dnu [get_object_name $c] }
}
unpu_check_pass ndm_check fillers_typed_filler [expr {[llength $bad_type] == 0}] \
    "design_type is filler for all of {$fnames}; not filler: {$bad_type}"
unpu_check_pass ndm_check fillers_not_dont_use [expr {[llength $bad_dnu] == 0}] \
    "none of {$fnames} is dont_use; dont_use: {$bad_dnu}"

# ---- library-flagged dont_use cells ------------------------------------------
foreach nm $LIB_DONT_USE_CELLS {
  set c [get_lib_cells -quiet */$nm]
  set found [expr {[sizeof_collection $c] >= 1}]
  set flagged 0
  if {$found} {
    foreach_in_collection one $c { set flagged [string is true -strict [get_attribute $one dont_use]] }
  }
  unpu_check_pass ndm_check lib_dont_use_$nm [expr {$found && $flagged}] \
      "$nm exists: $found, dont_use set by the library: $flagged"
}
# the -filter form works (server run, 3 cells); counted BEFORE the dont_use attribute is set by floorplan.tcl
set dnu [get_lib_cells -quiet -filter "dont_use==true" */*]
set ndnu [sizeof_collection $dnu]
set dnu_names {}
foreach_in_collection c $dnu { lappend dnu_names [get_object_name $c] }
unpu_check_pass ndm_check dont_use_count_before [expr {$ndnu == [llength $LIB_DONT_USE_CELLS]}] \
    "$ndnu cell(s) dont_use before floorplan.tcl sets the attribute: {$dnu_names} (expected [llength $LIB_DONT_USE_CELLS]: $LIB_DONT_USE_CELLS)"

# ---- which NDM holds the fillers ---------------------------------------------
set holders {}
foreach ndm $ndm_list {
  set libname [file rootname [file tail $ndm]]
  if {$fillers_in($libname) > 0} { lappend holders $libname }
}
unpu_result ndm_check filler_holder_libraries [join $holders " "]
set timing_lib ""
foreach ndm $ndm_list {
  set libname [file rootname [file tail $ndm]]
  if {$cells_in($libname) >= $EXPECT_TIMING_CELLS} { set timing_lib $libname }
}
set single_ok [expr {$timing_lib ne "" && $fillers_in($timing_lib) == $nf}]
unpu_result ndm_check single_mode_worked [expr {$single_ok ? "yes" : "no"}]
if {$single_ok} {
  unpu_info "the fillers are in the same NDM ($timing_lib) as the timing cells: mode single worked"
} else {
  unpu_info "the fillers are NOT in the library with the timing cells (holders: {$holders}); this is the expected layout of mode two (mode single does not work on this kit: LM-052, 0 of 3 fillers)"
}

# scratch library: close without saving anything else; the NDMs were not touched
catch {close_lib}          ;# close_lib [library] exists (usage); the server run ended normally
unpu_checks_finish ndm_check
exit 0
