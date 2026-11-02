# =============================================================================
# ndm_file_gen.tcl -- build the ICC2 reference library (NDM) of the SCL 180 nm
#                     standard cells, filler cells INCLUDED at generation time
#
# Runs in the ICC2 LIBRARY MANAGER of the SAME release as icc2_shell (U-2022.12-SP3):
#   /home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell
# NOT the bare name icc2_lm_shell: that finds Fusion Compiler V-2023.12-SP4, whose NDM may
# not open in the older icc2_shell (docs/session-handoff.md 18.10). The script checks the
# version and stops if it is wrong.
#
# Run (csh; paths are the defaults of pnr/params.tcl, override with setenv):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>      # the default is printed by params.tcl (UNPU_WORK)
#   setenv UNPU_NDM_MODE two               # the default; single does not work on this kit (see Mode below)
#   mkdir -p $UNPU_WORK/ndm
#   /home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell \
#       -file $UNPU_REPO/pnr/ndm_file_gen.tcl \
#       -output_log_file $UNPU_WORK/ndm/ndm_file_gen.log
#   (-file / -output_log_file in icc2_lm_shell: confirmed on the server, VERIFY_STATUS.md)
#
# Where the outputs go: $NDM_DIR (params.tcl: $UNPU_WORK/ndm), because commit_workspace writes
# the NDM into the directory where the library manager is running; this script cd's there and
# prints the directory. Files written:
#   feedth.lef            the three filler MACROs cut from the kit LEF (header + 3 MACROs)
#   scl18fs120.ndm        timing cells (+ fillers in mode single)
#   scl18fs120_fillf.ndm  fillers only (mode two; built by the first of NDM_FILL_VARIANTS that works, task 056)
#   ndm_manifest.txt      absolute NDM paths, one per line, in reference-library order
#   manifest_ndm_file_gen.txt   tool version, parameters, checksums
# An existing target NDM is never overwritten silently: the script stops unless
# UNPU_NDM_OVERWRITE=1 (then it prints a Warning for every path it removes).
# Nothing is ever written under SCL_KIT_ROOT.
#
# Mode (UNPU_NDM_MODE, default two, never decided silently at run time):
#   two     the main NDM exactly as in 18.10 (534 timing cells), then a second workspace (-flow physical_only) from
#           feedth.lef, cells typed `filler`, giving scl18fs120_fillf.ndm (537 cells in total, 18.22). THE WAY THAT WORKS.
#   single  one NDM with the 534 timing cells and the three fillers. DOES NOT WORK ON THIS KIT: the server run of task 047
#           (ndm_file_gen.log) read the LEF into 'scl18fs120_std' (LEFR-022); at check_workspace "Skipped 6 physical designs
#           (LM-052)" (the six LEF-only cells feedth, feedth3, feedth9, mx08d1, mx08d2, mx08d4 have no logical view and the
#           workspace skips them) and still "Workspace check succeeded!"; get_lib_cells listed 0 of the 3 fillers;
#           ndm_check.tcl: 534 cells, 0 fillers, single_mode_worked = no. The mode is kept only to reproduce that result.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
source [file join $here ndm_fill_common.tcl]
unpu_load_params

# ---- 1. checks before doing anything ----------------------------------------
unpu_require_tool_version $ICC2_VERSION            ;# sh_product_version (confirmed, VERIFY_STATUS.md)
unpu_need_file $TECH_FILE "technology file"
unpu_need_file $LEF_STD   "standard-cell LEF"
unpu_need_file $LIB_DB_SS "ss .db"
unpu_need_file $LIB_DB_FF "ff .db"
set lef_macros [unpu_count_lef_macros $LEF_STD]
unpu_check_pass ndm_file_gen lef_macro_count [expr {$lef_macros == $EXPECT_LEF_MACROS}] \
    "$lef_macros MACROs in $LEF_STD (expected $EXPECT_LEF_MACROS, handoff 18.10)"

unpu_stage_begin ndm_file_gen shared [list $TECH_FILE $LEF_STD $LIB_DB_SS $LIB_DB_FF]

set targets [list $NDM_DIR/${NDM_WS_MAIN}.ndm]
if {$NDM_MODE eq "two"} { lappend targets $NDM_DIR/${NDM_WS_FILL}.ndm }
set overwrite [expr {[info exists ::env(UNPU_NDM_OVERWRITE)] && $::env(UNPU_NDM_OVERWRITE) eq "1"}]
foreach t $targets {
  if {[file exists $t]} {
    if {!$overwrite} {
      unpu_die "target NDM already exists: $t. Not overwriting. To rebuild: setenv UNPU_NDM_OVERWRITE 1"
    }
    unpu_warn "UNPU_NDM_OVERWRITE=1: removing the existing $t"
    unpu_no_kit_write $t
    file delete -force $t
    if {[file exists $t]} { unpu_die "could not remove $t" }
  }
}
# in mode single a leftover filler NDM from an earlier mode-two run must not stay in the manifest
if {$NDM_MODE eq "single" && [file exists $NDM_DIR/${NDM_WS_FILL}.ndm]} {
  unpu_warn "$NDM_DIR/${NDM_WS_FILL}.ndm exists from an earlier run; it is NOT listed in ndm_manifest.txt in mode single"
}

# ---- 2. work in NDM_DIR ------------------------------------------------------
cd $NDM_DIR
unpu_info "working directory (the NDM lands here): [pwd]"
unpu_result ndm_file_gen mode $NDM_MODE

# ---- 3. the filler LEF -------------------------------------------------------
set feedth_lef $NDM_DIR/feedth.lef
if {[file exists $feedth_lef]} { unpu_warn "regenerating the derived file $feedth_lef" }
set nfill_lef [unpu_extract_lef_macros $LEF_STD $FILLER_CELLS $feedth_lef]
unpu_check_pass ndm_file_gen feedth_lef [expr {$nfill_lef == [llength $FILLER_CELLS]}] \
    "$nfill_lef MACROs written to $feedth_lef ($FILLER_CELLS)"

# ---- helper: type the filler cells `filler` ----------------------------------
# get_lib_cells, foreach_in_collection, get_object_name, set_attribute exist in icc2_lm_shell (help_lm usage files); the server run of
# mode single ran this loop without error (0 cells found: LM-052)
# design_type (18.22 shows foreach_in_collection c [get_lib_cells] {set_attribute $c design_type
# filler} in a workspace that holds only the three fillers). Here the loop is restricted to the
# filler names because in mode single the workspace holds the timing cells too.
proc ndm_type_fillers {} {
  global FILLER_CELLS
  set n 0
  set seen {}
  foreach_in_collection c [get_lib_cells] {
    set full [get_object_name $c]
    set nm [lindex [split $full /] end]
    if {[lsearch -exact $FILLER_CELLS $nm] >= 0} {
      set_attribute $c design_type filler
      incr n
      lappend seen $full
    }
  }
  unpu_info "design_type filler set on $n cell(s): $seen"
  return $n
}

# ---- helper: check_workspace must report success (the first run printed "Workspace check succeeded!") ----
# `redirect -variable` captures the messages of check_workspace (confirmed: the success text is captured, VERIFY_STATUS.md). If nothing at all was
# captured the script cannot tell and says so loudly (Warning); if something was captured but the
# success text is absent, it stops and prints what was captured.
proc ndm_check_workspace {ws} {
  set text [unpu_run_logged [list check_workspace] {}]
  if {$::UNPU_CAP_OK == 0} {
    unpu_warn "check_workspace $ws: output capture unavailable; CANNOT VERIFY that it printed 'Workspace check succeeded!' (read the log)"
  } elseif {[string trim $text] eq ""} {
    unpu_warn "check_workspace $ws: nothing was captured; CANNOT VERIFY that it printed 'Workspace check succeeded!' (read the log)"
  } elseif {![unpu_workspace_check_ok $text]} {
    unpu_die "check_workspace $ws did not report 'Workspace check succeeded!'. Captured output:\n$text"
  } else {
    unpu_info "check_workspace $ws: reported success"
  }
  # LM-052 "Skipped N physical designs": the LEF-only cells that have no logical view (6 in the main workspace on this kit, task 047)
  set skipped [unpu_workspace_skipped $text]
  unpu_result ndm_file_gen lm052_skipped_physical_designs_$ws [expr {$skipped eq "" ? "none reported" : $skipped}]
}

# ---- 4. main workspace (handoff 18.10) ---------------------------------------
unpu_info "create_workspace -flow normal $NDM_WS_MAIN"
unpu_run_logged [list create_workspace -flow normal -technology $TECH_FILE $NDM_WS_MAIN] $FILLER_CELLS
unpu_run_logged [list read_lef $LEF_STD] $FILLER_CELLS
unpu_run_logged [list read_db $LIB_DB_SS] $FILLER_CELLS
unpu_run_logged [list read_db $LIB_DB_FF] $FILLER_CELLS
set timing_libs_read 2

set lef_read 1          ;# LEF files read so far: the kit LEF
set fillers_in_ws 0
if {$NDM_MODE eq "single"} {
  # Fillers in the same library, from the kit LEF read above only: it already contains the three
  # MACROs, and a second read of known MACROs may be an error. feedth.lef is NOT read in this mode
  # (it is written for mode two). Every message that mentions a filler was echoed above as
  # MSG-MENTIONING-<name>.
  # Server run of task 047: get_lib_cells lists 0 of the 3 fillers here (LM-052 skipped the physical-only cells).
  unpu_warn "UNPU_NDM_MODE=single DOES NOT WORK on this kit: the server run showed 'Skipped 6 physical designs (LM-052)', 0 of 3 fillers in the workspace and single_mode_worked = no in ndm_check. Use the default, UNPU_NDM_MODE two."
  set fillers_in_ws [ndm_type_fillers]
  if {$fillers_in_ws != [llength $FILLER_CELLS]} {
    unpu_warn "mode single: get_lib_cells lists only $fillers_in_ws of [llength $FILLER_CELLS] filler cells in the workspace (as in the server run: LM-052). Committing anyway so the result can be reproduced; ndm_check.tcl will say single_mode_worked = no. Fix: setenv UNPU_NDM_MODE two, setenv UNPU_NDM_OVERWRITE 1 and rerun."
  }
}
unpu_result ndm_file_gen fillers_in_main_workspace $fillers_in_ws

ndm_check_workspace $NDM_WS_MAIN
unpu_run_logged [list commit_workspace] $FILLER_CELLS
set committed 1

# ---- 5. mode two: second workspace for the fillers (handoff 18.22) -----------
if {$NDM_MODE eq "two"} {
  # Task 056. pnr_run2 (real server run): create_workspace -flow physical_only -technology <tf> + read_lef feedth.lef worked
  # ("Read LEF into a new library 'feedth'", LEFR-022) but get_lib_cells matched 0 of the 3 fillers, so nothing was typed and the
  # script stopped. The cause is not known (ndm_fill_probe.tcl answers it in one server run). Until then the script tries the VARIANTS of
  # NDM_FILL_VARIANTS (common.tcl unpu_fill_variant_cmds) in order, and for each tries the FORMS of NDM_FILL_FIND_FORMS to list the lib
  # cells. A variant is accepted only if one form lists EXACTLY the 3 fillers, they are typed `filler` (read back), and check_workspace
  # prints "Workspace check succeeded!". A failed variant is printed and its workspace removed (remove_workspace). If no variant works the
  # CHECK fillers_typed fails and the script stops with every reason printed. Nothing is accepted on a guess.
  # design_type must be set in the library manager BEFORE check_workspace and commit_workspace; it cannot be set in icc2_shell (ATTR-25);
  # cells left typed lib_cell gave CHF-011/CHF-010 (18.22).
  set fill_ok 0
  set fill_variant none
  set fill_msgs {}
  foreach variant $NDM_FILL_VARIANTS {
    unpu_info "second workspace $NDM_WS_FILL: trying variant $variant"
    lassign [ndm_try_fill_variant $variant $NDM_WS_FILL $TECH_FILE $feedth_lef] ok msg
    if {$ok} { incr lef_read; set fill_ok 1; set fill_variant $variant; lappend fill_msgs "$variant: OK ($msg)"; break }
    lappend fill_msgs "$variant: FAILED ($msg)"
    unpu_warn "variant $variant failed: $msg"
    if {![ndm_discard_ws]} { lappend fill_msgs "(remove_workspace failed after $variant: later variants may be contaminated)" }
  }
  foreach m $fill_msgs { unpu_info "filler workspace summary: $m" }
  unpu_result ndm_file_gen fill_workspace_variant $fill_variant
  unpu_check_pass ndm_file_gen fillers_typed $fill_ok \
      "[llength $FILLER_CELLS] filler cells typed filler in $NDM_WS_FILL (variant $fill_variant); tried: [join $fill_msgs {; }]"
  unpu_run_logged [list commit_workspace] $FILLER_CELLS
  incr committed
}

# ---- 6. after the commits ----------------------------------------------------
set ndm_paths {}
foreach t $targets {
  if {![file exists $t]} { unpu_die "expected NDM was not created: $t" }
  set size [unpu_path_size $t]
  unpu_info "NDM $t: type [file type $t], $size bytes"
  if {$size <= 0} { unpu_die "NDM $t is empty" }
  lappend ndm_paths [file normalize $t]
}
set fh [open $NDM_DIR/ndm_manifest.txt w]
foreach p $ndm_paths { puts $fh $p }
close $fh
unpu_info "wrote $NDM_DIR/ndm_manifest.txt ([llength $ndm_paths] path(s), reference-library order)"
unpu_manifest ndm_file_gen [list $TECH_FILE $LEF_STD $LIB_DB_SS $LIB_DB_FF $feedth_lef] $NDM_DIR

# ---- 7. counts ---------------------------------------------------------------
unpu_result ndm_file_gen lef_macros_read [expr {$lef_macros + ($lef_read > 1 ? $nfill_lef : 0)}]   ;# MACROs actually read: kit LEF, plus feedth.lef only in mode two
unpu_result ndm_file_gen lef_files_read $lef_read
unpu_result ndm_file_gen timing_libraries_read $timing_libs_read
unpu_result ndm_file_gen workspaces_committed $committed
unpu_result ndm_file_gen ndm_paths [join $ndm_paths " "]
unpu_info "done. Next: icc2_shell -file .../pnr/ndm_check.tcl"
exit 0
