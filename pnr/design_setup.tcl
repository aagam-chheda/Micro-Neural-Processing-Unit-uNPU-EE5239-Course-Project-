# =============================================================================
# design_setup.tcl -- script 2 of the back-end re-run: design library, TLUPlus, netlist, SDC,
#                     corners and scenarios, count checks, first checkpoint block
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage B1;
# commands that worked in the first run: docs/session-handoff.md 18.11 to 18.13.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1                 # default run1
#   mkdir -p $UNPU_WORK/$UNPU_RUN_TAG/logs
#   icc2_shell -file $UNPU_REPO/pnr/design_setup.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/design_setup.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Inputs (all must exist): the NDM list $NDM_DIR/ndm_manifest.txt (from ndm_file_gen.tcl), the
#   technology file, the TLUPlus file and its map, the netlist of the chosen synthesis profile
#   (syn/out/$UNPU_SYN_PROFILE/unpu_top_cn.dc.v; UNPU_SYN_PROFILE is REQUIRED, no default; overridable by UNPU_NETLIST) and the
#   stage-selectable SDC constraints/unpu_top.sdc (read with the profile PROFILE_DESIGN_SETUP = place; params.tcl).
# Outputs: design library $LIB_DIR/$LIB_NAME holding the block $BLK_IMPORT (= $TOP_NAME) with the
#   netlist linked, the `place` profile of the SDC read into two scenarios (period, uncertainty, operating
#   condition of each read back and CHECKED), the corners and the parasitic setup;
#   reports $RPT_DIR/design_setup_*.rpt; $LOG_DIR/manifest_design_setup.txt.
# Never: touches the libraries of the first run, writes into the kit, reuses an existing library
#   (UNPU_LIB_OVERWRITE=1 removes it, with a Warning), places or floorplans anything. The SDC that DC wrote
#   (unpu_top_cn.sdc) is NOT an input any more: the layout flow reads the profile SDC (task 053).
#
# If any CHECK fails the script still runs every remaining check and prints every verdict, then stops
# BEFORE saving the block (no checkpoint is written from a setup that failed its checks).
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

# ---- 1. checks and stage start ----------------------------------------------
unpu_require_tool_version $ICC2_VERSION            ;# sh_product_version (confirmed, VERIFY_STATUS.md)
unpu_require_syn_profile
set UNPU_CHECK_CONTINUE 1
set ndm_manifest $NDM_DIR/ndm_manifest.txt
foreach {f what} [list $TECH_FILE "technology file" $TLUPLUS_FILE "TLUPlus file" $TLUPLUS_MAP "TLUPlus layer map" \
                       $NETLIST "netlist of the synthesis profile $SYN_PROFILE" $PROFILE_SDC "profile SDC (constraints/unpu_top.sdc)" $ndm_manifest "NDM manifest (run ndm_file_gen.tcl first)"] {
  unpu_need_file $f $what
}
unpu_stage_begin design_setup run [list $TECH_FILE $TLUPLUS_FILE $TLUPLUS_MAP $NETLIST $PROFILE_SDC $ndm_manifest]
unpu_info "synthesis profile $SYN_PROFILE: netlist $NETLIST"
unpu_result design_setup syn_profile $SYN_PROFILE
unpu_netlist_expect          ;# NETLIST_MODULES, NETLIST_LEAF_CELLS computed from the netlist file
set ndm_list [unpu_read_ndm_manifest $ndm_manifest]
unpu_info "reference NDMs, in order: $ndm_list"
if {$TOP_NAME ne $BLK_IMPORT} {
  unpu_die "TOP_NAME ($TOP_NAME) and BLK_IMPORT ($BLK_IMPORT) differ; the first block is named after the top module"
}

# helper: run a report command to $RPT_DIR/design_setup_<name>.rpt with redirect -file, read it back,
# print it to the log, return the text.  VERIFY: redirect -file <file> <script>
proc ds_report {name cmd} {
  global RPT_DIR
  set f [file join $RPT_DIR design_setup_${name}.rpt]
  unpu_no_kit_write $f
  if {[catch {redirect -file $f [list uplevel #0 $cmd]} msg]} { unpu_die "report '$cmd' failed: $msg" }
  if {![file exists $f]} { unpu_die "report '$cmd' did not write $f" }
  set fh [open $f r]; set text [read $fh]; close $fh
  unpu_info "--- $cmd -> $f ---"
  puts -nonewline $text
  if {![string match *\n $text]} { puts "" }
  if {[string trim $text] eq ""} { unpu_warn "report '$cmd' is empty" }
  return $text
}
# helper: first slack of a path group query, VERIFY get_timing_paths / the slack attribute
proc ds_worst_slack {scenario delay} {
  current_scenario $scenario                                         ;# VERIFY
  if {![catch {
        set p [get_timing_paths -delay_type $delay -max_paths 1]     ;# VERIFY
        set s [get_attribute $p slack]                               ;# VERIFY
      } msg] && $s ne "" && [string is double -strict $s]} {
    return $s
  }
  unpu_warn "get_timing_paths/slack did not work for scenario $scenario ($delay): falling back to report_timing text. Reason: [expr {[info exists msg] ? $msg : {empty or non-numeric slack}}]"
  set f [file join $::RPT_DIR design_setup_firsttiming_${scenario}.rpt]
  if {[catch {redirect -file $f [list uplevel #0 [list report_timing -delay_type $delay -max_paths 1]]} m2]} {
    unpu_warn "report_timing fallback failed too: $m2"
    return unavailable
  }
  set fh [open $f r]; set text [read $fh]; close $fh
  set s [unpu_parse_slack $text]
  if {$s eq ""} { unpu_warn "no slack found in $f"; return unavailable }
  return $s
}

# ---- 2. the design library must not exist -----------------------------------
set lib_path $LIB_DIR/$LIB_NAME
unpu_ensure_dir $LIB_DIR
if {[file exists $lib_path]} {
  if {![info exists ::env(UNPU_LIB_OVERWRITE)] || $::env(UNPU_LIB_OVERWRITE) ne "1"} {
    unpu_die "design library already exists: $lib_path. It is never reused silently. To rebuild: setenv UNPU_LIB_OVERWRITE 1"
  }
  unpu_warn "UNPU_LIB_OVERWRITE=1: removing the existing design library $lib_path"
  unpu_no_kit_write $lib_path
  file delete -force $lib_path
  if {[file exists $lib_path]} { unpu_die "could not remove $lib_path" }
}

# ---- 3. create the library (18.11) -------------------------------------------
# VERIFY (server): -ref_libs takes a Tcl list for several libraries (18.11 shows one).
if {[catch {create_lib -technology $TECH_FILE -ref_libs $ndm_list $lib_path} msg]} {
  unpu_die "create_lib $lib_path failed: $msg"
}
unpu_info "design library created: $lib_path"
# VERIFY: current_lib returns the library just created
if {![catch {current_lib} cl]} { unpu_info "current library: [get_object_name $cl]" } else { unpu_warn "current_lib failed: $cl" }
set rrl [ds_report ref_libs report_ref_libs]
set nref 0
foreach ndm $ndm_list {
  set lname [file rootname [file tail $ndm]]
  unpu_check_pass design_setup reflib_open_$lname [unpu_reflib_open $rrl $lname] \
      "reference library $lname listed and open in report_ref_libs"
  incr nref
}

# ---- 4. TLUPlus (18.11): the nine TLUP-011 warnings are benign and are NOT hidden ----
unpu_run_logged [list read_parasitic_tech -name $PARA_TECH_NAME -tlup $TLUPLUS_FILE -layermap $TLUPLUS_MAP] {TLUP-}

# ---- 5. netlist and link (18.12) ---------------------------------------------
unpu_run_logged [list read_verilog -top $TOP_NAME $NETLIST] {}
set ltext [unpu_run_logged [list link_block] {}]
set unres [unpu_unresolved_lines $ltext]
if {$::UNPU_CAP_OK && [string trim $ltext] ne ""} {
  unpu_check_pass design_setup link_success [unpu_text_has $ltext "successfully linked"] \
      "link_block output contains 'successfully linked'"
  unpu_check_pass design_setup link_no_unresolved [expr {[llength $unres] == 0}] \
      "no unresolved references in the link_block output; found: {$unres}"
} else {
  unpu_warn "link_block output was not captured: CANNOT VERIFY 'successfully linked' (read the log); the count checks below still run"
}
set nports [sizeof_collection [get_ports *]]
set nseq   [sizeof_collection [get_cells -hierarchical -filter "is_sequential==true"]]
set nleaf  [sizeof_collection [get_cells -hierarchical -filter "is_hierarchical==false"]]
unpu_check_pass design_setup ports [expr {$nports == $EXPECT_PORTS}] "$nports top-level ports, expected $EXPECT_PORTS (18.12)"
unpu_check_pass design_setup seq_cells [expr {$nseq == $EXPECT_SEQ_CELLS}] "$nseq sequential cells, expected $EXPECT_SEQ_CELLS (18.12)"
if {$nleaf != $NETLIST_LEAF_CELLS} { unpu_leaf_mismatch_report }   ;# task 060: say WHERE the two counts differ before the check stops the script
unpu_check_pass design_setup leaf_cells [expr {$nleaf == $NETLIST_LEAF_CELLS}] "$nleaf leaf cells in the linked design, $NETLIST_LEAF_CELLS counted in the netlist file (the first run's netlist had $PREV_LEAF_CELLS)"

# ---- 6. the profile SDC into the first scenario (18.12, 18.13; task 053) ----------------------------------------
# read_sdc creates the mode, corner and scenario named default (the shell has no rename command). The SDC read is the stage profile
# PROFILE_DESIGN_SETUP of constraints/unpu_top.sdc; the second scenario is handled by unpu_apply_profile in step 7.
proc ds_read_sdc {label {check_missing 0}} {
  global PROFILE_SDC EXPECT_SDC_IGNORED PROFILE_DESIGN_SETUP
  set ::env(UNPU_STAGE) $PROFILE_DESIGN_SETUP
  set text [unpu_run_logged [list read_sdc $PROFILE_SDC] {SDC- UIC-}]
  set sdclines [unpu_lines_matching $text {SDC-[0-9]+}]
  set ids [unpu_message_ids $text SDC]
  foreach l $sdclines { unpu_info "$label SDC message: $l" }
  set bad [unpu_ids_unexpected $ids $EXPECT_SDC_IGNORED]
  if {[llength $bad] > 0} {
    unpu_warn "$label: unexpected SDC message id(s) {$bad}; the profile SDC is expected to print none ({$EXPECT_SDC_IGNORED} allowed). Read the lines above."
  }
  if {!$::UNPU_CAP_OK || [string trim $text] eq ""} {
    unpu_warn "$label: read_sdc output was not captured; the SDC message ids and the profile line could NOT be compared (read the log)"
  }
  unpu_result design_setup sdc_ignored_ids_$label [join $ids " "]
  return $text
}
set sdc_text [ds_read_sdc $SCEN_SETUP 1]
lassign [unpu_profile_numbers $PROFILE_DESIGN_SETUP] _pn _pT _pU _pH _pB _pk
set _got [unpu_parse_profile_line $sdc_text]
unpu_check_pass design_setup profile_${PROFILE_DESIGN_SETUP}_${SCEN_SETUP}_sdc_line [expr {[llength $_got] == 5 && [lindex $_got 0] eq $PROFILE_DESIGN_SETUP && abs([lindex $_got 1] - $_pT) < 1e-6 && abs([lindex $_got 2] - $_pU) < 1e-6 && abs([lindex $_got 3] - $_pH) < 1e-6}] \
    "the SDC read in scenario $SCEN_SETUP printed the profile line {$_got}, expected $PROFILE_DESIGN_SETUP / $_pT / $_pU / $_pH"

# ---- 7. corners and scenarios (18.13) ----------------------------------------
unpu_run_logged [list create_corner $CORNER_HOLD] {}
unpu_run_logged [list create_scenario -name $SCEN_HOLD -mode $MODE_NAME -corner $CORNER_HOLD] {}
unpu_run_logged [list set_scenario_status $SCEN_SETUP -setup true -hold false] {}
unpu_run_logged [list set_scenario_status $SCEN_HOLD -setup false -hold true] {}
# The profile SDC carries NO operating condition (the DC-written SDC carried the ss one), so BOTH scenarios get theirs explicitly here.
# unpu_apply_profile: hold scenario = read the SDC (UIC-034 "Redefining clock" is benign: both scenarios share the mode default); both
# scenarios = operating condition (ss / ff), read-back and CHECK of period, uncertainty, propagation; the setup scenario's SDC was read in step 6.
unpu_apply_profile $PROFILE_DESIGN_SETUP {} [list $SCEN_SETUP]
# VERIFY: the name of the first corner is $CORNER_SETUP (report_corners shows it)
foreach c [list $CORNER_SETUP $CORNER_HOLD] {
  unpu_run_logged [list set_parasitic_parameters -corners $c -early_spec $PARA_TECH_NAME -late_spec $PARA_TECH_NAME] {}
}

# ---- 8. reports and checks ---------------------------------------------------
# the corners (voltage, temperature) were checked by unpu_apply_profile in step 7 (unpu_check_corners)
ds_report scenarios report_scenarios
ds_report parasitic_parameters report_parasitic_parameters
# scenario status: ask the scenarios themselves; VERIFY attribute names (setup / hold)
foreach {s su hd} [list $SCEN_SETUP true false $SCEN_HOLD false true] {
  if {![catch {list [get_attribute [get_scenarios $s] setup] [get_attribute [get_scenarios $s] hold]} got]} {
    unpu_check_pass design_setup scenario_status_$s [expr {[string is true -strict [lindex $got 0]] == [string is true $su] && [string is true -strict [lindex $got 1]] == [string is true $hd]}] \
        "scenario $s (setup, hold) = {$got}, expected {$su $hd}"
  } else {
    unpu_warn "could not read the setup/hold status of scenario $s ($got); compare design_setup_scenarios.rpt by eye"
  }
}
# check_timing in each scenario
foreach s [list $SCEN_SETUP $SCEN_HOLD] {
  unpu_run_logged [list current_scenario $s] {}                     ;# VERIFY
  set ct [ds_report check_timing_$s check_timing]
  set w [unpu_warning_lines $ct]
  foreach l $w { unpu_info "check_timing ($s) warning: $l" }
  if {[llength $w] != $EXPECT_CHECK_TIMING_WARNINGS} {
    unpu_warn "check_timing ($s): [llength $w] warning line(s), expected $EXPECT_CHECK_TIMING_WARNINGS (only pready, unconstrained constant, rtl/unpu_apb.sv:87): {$w}"
  }
  unpu_result design_setup check_timing_warnings_$s [llength $w]
}

# ---- 9. first timing, informational only -------------------------------------
# No placement (zero interconnect, TIM-101/102), ideal clock. First run saw +0.82 ns setup in
# $SCEN_SETUP (paddr[2] to prdata[1]) and -0.50 ns hold in $SCEN_HOLD (u_csr/src_b_reg_reg_4_ to
# prdata[4]; OUT_MIN_DELAY -0.5 plus 0.5 uncertainty). Both change after placement and CTS: NOT asserted.
set ws [ds_worst_slack $SCEN_SETUP max]
set wh [ds_worst_slack $SCEN_HOLD min]
unpu_result design_setup worst_setup_slack_$SCEN_SETUP $ws
unpu_result design_setup worst_hold_slack_$SCEN_HOLD $wh
unpu_info "informational, not asserted: first run had +0.82 ns setup and -0.50 ns hold at this point"

# ---- 10. verdict, then the checkpoint ---------------------------------------
unpu_checks_finish design_setup      ;# stops here if any check failed: no checkpoint from a failed setup
set cur [unpu_current_block_name]
if {![unpu_block_name_matches $cur $BLK_IMPORT]} {
  unpu_die "current block is '$cur', expected $BLK_IMPORT before save_block"
}
# This script leaves ff_hold current after the corner setup; make the setup scenario current again before
# saving. NO stage script may rely on which scenario is current: each one selects the scenario it needs.
unpu_run_logged [list current_scenario $SCEN_SETUP] {}            ;# VERIFY (see above)
if {[catch {save_block} msg]} { unpu_die "save_block failed: $msg" }
if {[catch {save_lib} msg]}   { unpu_die "save_lib failed: $msg" }

# ---- 11. summary -------------------------------------------------------------
unpu_result design_setup library_path $lib_path
unpu_result design_setup block $cur
unpu_result design_setup reference_libraries $nref
unpu_result design_setup ports $nports
unpu_result design_setup sequential_cells $nseq
unpu_result design_setup leaf_cells $nleaf
unpu_result design_setup sdc_ignored_ids [join [unpu_message_ids $sdc_text SDC] " "]
unpu_result design_setup scenarios "$SCEN_SETUP (setup) $SCEN_HOLD (hold)"
unpu_result design_setup worst_setup_slack_ns $ws
unpu_result design_setup worst_hold_slack_ns $wh
unpu_info "done: block $cur saved in $lib_path"
exit 0
