# =============================================================================
# cts.tcl -- script 5 of the back-end re-run: clock tree, then hold optimisation at the chosen uncertainty
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage C; commands that worked in the
# first run: docs/session-handoff.md 18.17 (clock tree), 18.18 (hold run, FLW-8004), 18.20 (style of checks).
# No CTS option beyond those in the handoff is used (no skew targets, no useful skew: experiments for later).
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1
#   icc2_shell -file $UNPU_REPO/pnr/cts.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/cts.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Input: the library $LIB_DIR/$LIB_NAME with the placed block $BLK_PLACED (placement.tcl, not written yet; the
#   block only has to exist and be legal).
# Output: block $BLK_CTS (clock tree built, hold NOT fixed: kept so that another hold uncertainty can be tried from
#   it) and block $BLK_CLKOPT (hold optimised at HOLD_UNCERT); reports in $RPT_DIR (cts_*.rpt);
#   $LOG_DIR/manifest_cts.txt.
# Never: places or routes signal nets, changes the SDC, changes the setup uncertainty, touches the first-run library.
#
# Scenarios: no command here relies on the scenario that happens to be current. Each step selects the one it needs
# ($SCEN_SETUP = ss, setup; $SCEN_HOLD = ff, hold) and the comments say which one a command acts on.
#
# Remaining hold endpoints after the optimisation are a Warning with the worst list, NOT a check: plan C2 says the
# user decides what to do if hold does not close at 0.5 ns. FLW-8004 is counted and reported, not an error.
#
# Stage (UNPU_CTS_STAGE, default all; a Warning in the log says which mode ran and cts_stage is in the manifest):
#   all   the tree, then the hold optimisation (opens $BLK_PLACED; $BLK_CTS and $BLK_CLKOPT must not exist)
#   tree  build the tree, save $BLK_CTS, stop (opens $BLK_PLACED; $BLK_CTS must not exist)
#   hold  does NOT touch the tree: opens $BLK_CTS, applies HOLD_UNCERT, optimises, saves $BLK_CLKOPT ($BLK_CTS must
#         exist and $BLK_CLKOPT must not). Several hold-uncertainty experiments in one library:
#           setenv UNPU_CTS_STAGE hold ; setenv UNPU_HOLD_UNCERT 0.2 ; setenv UNPU_BLK_CLKOPT clkopt_h02
#         and the later stages start from any of them with the same UNPU_BLK_CLKOPT.
#
# If a CHECK fails the script prints every verdict, then stops BEFORE saving $BLK_CLKOPT. $BLK_CTS is saved earlier
# (right after the tree, if its own checks pass).
# Rerun: nothing is saved after the last checkpoint of a failed run, and a checkpoint name that exists is never reused.
#   - failed before "RESULT cts block_saved_cts": run the same command again.
#   - failed after it (or any other hold experiment): run it again with UNPU_CTS_STAGE hold (it reuses the saved tree)
#     and, if $BLK_CLKOPT exists, a new name in UNPU_BLK_CLKOPT.
# No reliable remove-block command is known, so names are never freed.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

# ---- 1. start ----------------------------------------------------------------
unpu_require_tool_version $ICC2_VERSION            ;# sh_product_version (confirmed, VERIFY_STATUS.md)
set UNPU_CHECK_CONTINUE 1
set lib_path $LIB_DIR/$LIB_NAME
if {![file exists $lib_path]} {
  unpu_die "design library not found: $lib_path. The earlier scripts run first (same UNPU_WORK and UNPU_RUN_TAG)"
}
unpu_stage_begin cts run [list $lib_path]
# which blocks must (not) exist and which one is opened depends on UNPU_CTS_STAGE (params.tcl CTS_STAGE)
lassign [unpu_cts_stage_plan $CTS_STAGE $BLK_PLACED $BLK_CTS $BLK_CLKOPT] must_not must_have open_blk
unpu_warn "UNPU_CTS_STAGE = $CTS_STAGE: [expr {$CTS_STAGE eq {all} ? {tree and hold optimisation} : ($CTS_STAGE eq {tree} ? {tree only, stops after saving the cts block} : {hold optimisation only, starting from the saved cts block})}]"
unpu_result cts cts_stage $CTS_STAGE
# VERIFY (server): get_blocks -quiet <name>
foreach b $must_not {
  if {![catch {get_blocks -quiet $b} existing]} {
    if {[sizeof_collection $existing] > 0} {
      unpu_die "block $b already exists in $lib_path; see the Rerun note in the header of cts.tcl (a new name in UNPU_BLK_*, or UNPU_CTS_STAGE hold)"
    }
  } else {
    unpu_warn "could not list the blocks of the library ($existing); cannot tell whether block $b exists already"
  }
}
foreach b $must_have {
  if {[catch {get_blocks -quiet $b} existing] || [sizeof_collection $existing] == 0} {
    unpu_die "UNPU_CTS_STAGE=$CTS_STAGE needs the block $b in $lib_path, and it was not found (run UNPU_CTS_STAGE tree or all first)"
  }
}
unpu_open_stage $lib_path $LIB_NAME $open_blk

# ---- helpers: the shared procedures live in common.tcl (unpu_scenario, unpu_report, unpu_paths, unpu_timing_summary) ----
proc ct_scen {name} { unpu_scenario $name }
proc ct_report {name cmd} { return [unpu_report cts $name $cmd] }

set corners [list $CORNER_SETUP $CORNER_HOLD]
# stages all and tree: legality of the placed block, the tree, its checks and the first checkpoint. Stage hold skips this
# (it opens the saved $BLK_CTS and does not touch the tree).
if {$CTS_STAGE ne "hold"} {
  # ---- 1b. the placed block must be legal; the sink count we expect --------------------------------
  set lt [unpu_run_logged [list check_legality] {}]
  set leg0 [unpu_parse_legality $lt]
  unpu_check_pass cts legality_before [expr {$leg0 ne "not parsed" && $leg0 == 0}] "check_legality on the placed block: $leg0 violations (0 expected; 'not parsed' = read the log)"
  unpu_info "expected clock sinks: $EXPECT_SEQ_CELLS (= sequential cells)"
  if {$UNPU_CHECK_FAILED > 0} { unpu_die "the placed block is not legal; no clock tree is built from it" }

  # ---- 3. cells kept out of the clock tree (18.17) -------------------------------------------------
  # acts on the library cells (not on a scenario)
  set excl [get_lib_cells -quiet $CTS_EXCLUDE_PATTERN]
  set nexcl [sizeof_collection $excl]
  if {$nexcl == 0} { unpu_die "CTS_EXCLUDE_PATTERN '$CTS_EXCLUDE_PATTERN' matched 0 library cells: the delay cells would end up in the clock tree" }
  unpu_info "$nexcl library cell(s) excluded from the clock tree by '$CTS_EXCLUDE_PATTERN'"
  if {$nexcl != $EXPECT_CTS_EXCLUDED} { unpu_warn "$nexcl cells matched '$CTS_EXCLUDE_PATTERN', the first run had $EXPECT_CTS_EXCLUDED" }
  unpu_run_logged [list set_lib_cell_purpose -exclude cts $excl] {}      ;# VERIFY: takes the collection as typed in 18.17
  unpu_result cts excluded_cells $nexcl

  # ---- 4. the clock tree (18.17) --------------------------------------------------------------------
  # clock_opt acts on all scenarios of the block (no scenario selected)
  set bt [unpu_run_logged [list clock_opt -to $CTS_BUILD_TO] {FLW-}]
  foreach {id n} [unpu_count_ids $bt FLW] { unpu_result cts build_${id}_count $n }
  set cq1 [ct_report clock_qor_build "report_clock_qor -type summary"]
  set pq1 [unpu_parse_clock_qor $cq1 $corners]
  if {[lindex $pq1 0] eq "ok"} {
    array set q1 [lrange $pq1 1 end]
    unpu_check_pass cts clock_sinks [expr {$q1(sinks) == $EXPECT_SEQ_CELLS}] "$q1(sinks) clock sinks, expected $EXPECT_SEQ_CELLS (= sequential cells)"
    unpu_result cts build_levels "$q1(levels) (first run: $EXPECT_CTS_LEVELS)"
    unpu_result cts build_repeaters "$q1(repeaters) (first run: $EXPECT_CTS_REPEATERS)"
    foreach c $corners { unpu_result cts build_latency_ns_$c $q1(latency_$c); unpu_result cts build_skew_ns_$c $q1(skew_$c) }
  } else {
    unpu_check_pass cts clock_sinks 0 "[lindex $pq1 1]"
  }
  if {$UNPU_CHECK_FAILED > 0} { unpu_die "the clock tree failed its checks; no checkpoint saved (see the CHECK lines above)" }
  unpu_checkpoint $BLK_CTS
  unpu_result cts block_saved_cts $BLK_CTS
}
if {$CTS_STAGE eq "tree"} {
  unpu_checks_finish cts
  unpu_info "done (UNPU_CTS_STAGE tree): block $BLK_CTS saved in $lib_path; the hold optimisation is a separate run: setenv UNPU_CTS_STAGE hold"
  exit 0
}

# ---- 5. hold uncertainty (18.18) ----------------------------------------------------------------------
# acts on $SCEN_HOLD (ff, hold). The SDC already carries 0.5; setting it here makes the value explicit and lets an
# experiment run with another value (UNPU_HOLD_UNCERT). set_clock_uncertainty -hold -scenarios <s> <v> [get_clocks clk] (usage text, task 047)
ct_scen $SCEN_HOLD
# without -modes/-corners/-scenarios the command acts on the current scenario (usage text); the scenario is named explicitly
unpu_run_logged [list set_clock_uncertainty -hold -scenarios $SCEN_HOLD $HOLD_UNCERT [get_clocks clk]] {}
# read it back from a hold path report (18.19 used this: report_timing -delay_type min shows "clock uncertainty")
set rb [ct_report hold_uncertainty_readback "report_timing -delay_type min -max_paths 1 -nosplit"]
set got [unpu_parse_clock_uncertainty $rb]
unpu_check_pass cts hold_uncertainty [expr {$got ne "" && abs($got - $HOLD_UNCERT) < 1e-6}] \
    "hold clock uncertainty read back from report_timing in $SCEN_HOLD: '$got', expected $HOLD_UNCERT"
# optimising at the wrong uncertainty would waste the long clock_opt run and prove nothing: stop here ($BLK_CTS is saved)
if {$UNPU_CHECK_FAILED > 0} { unpu_die "the hold uncertainty is not in force; clock_opt -from $CTS_OPT_FROM is not run. Block $BLK_CTS is saved." }

# ---- 6. hold optimisation (18.18) -------------------------------------------------------------------------
# clock_opt acts on all scenarios (setup in $SCEN_SETUP, hold in $SCEN_HOLD)
set ot [unpu_run_logged [list clock_opt -from $CTS_OPT_FROM -to $CTS_OPT_TO] {FLW-}]
set flw [unpu_count_ids $ot FLW]
set n8004 0
foreach {id n} $flw { if {$id eq $FLW_INCOMPLETE_ID} { set n8004 $n }; unpu_info "message id $id: $n occurrence(s) in the clock_opt output" }
unpu_result cts flw_8004_count $n8004
unpu_result cts flw_ids_seen [join $flw " "]
if {$n8004 != 0} {
  unpu_warn "$FLW_INCOMPLETE_ID ('Incomplete clock_opt / final_opto') appeared $n8004 time(s); the first run saw it with every check clean, cause unknown. The QoR checks below decide."
}

# ---- 7. checks after ------------------------------------------------------------------------------------
# setup (acts on $SCEN_SETUP)
lassign [unpu_timing_summary cts $SCEN_SETUP max setup] ws sv sg spaths
unpu_result cts worst_setup_slack_ns $ws
unpu_check_pass cts setup_violations [expr {$sv ne "unavailable" && $sv == 0}] \
    "$sv setup-violating endpoint(s) in $SCEN_SETUP (0 expected; 'unavailable' = the count could not be obtained); worst slack $ws ns; by group {$sg}"
# hold (acts on $SCEN_HOLD): RESULT and a Warning, NOT a check
lassign [unpu_timing_summary cts $SCEN_HOLD min hold] wh hv hg hpaths
unpu_result cts worst_hold_slack_ns $wh
unpu_result cts hold_violating_endpoints $hv
unpu_result cts hold_violating_by_group $hg
if {$hv eq "unavailable"} {
  unpu_warn "the number of hold-violating endpoints could not be obtained (see the report_timing warnings above); worst hold slack $wh ns"
} elseif {$hv != 0} {
  set worst [unpu_worst_endpoints $hpaths $HOLD_ENDPOINTS_LISTED]
  unpu_warn "$hv hold-violating endpoint(s) remain in $SCEN_HOLD at hold uncertainty $HOLD_UNCERT (worst slack $wh ns). This is NOT a failure of the script: plan C2 says route_opt may clear the last ones and the user decides what to do if hold does not close. Worst [llength $worst]: [join $worst { ; }]"
  foreach l $worst { unpu_info "hold endpoint: $l" }
}
# max transition and max capacitance (VERIFY: report_constraint -all_violators -max_transition / -max_capacitance)
foreach {kind opt} {max_transition -max_transition max_capacitance -max_capacitance} {
  set f [file join $RPT_DIR cts_${kind}.rpt]
  if {[catch {redirect -file $f [list uplevel #0 [list report_constraint -all_violators $opt]]} msg]} {
    set cnt unavailable
    unpu_warn "report_constraint -all_violators $opt failed: $msg"
  } else {
    set fh [open $f r]; set rtxt [read $fh]; close $fh
    set cnt [unpu_parse_violations $rtxt]
  }
  unpu_check_pass cts $kind [expr {$cnt ne "unavailable" && $cnt == 0}] "$cnt $kind violation(s) (0 expected; 'unavailable' = could not be read, see $f)"
}
# legality and power connectivity of the placed-and-optimised block
set lt2 [unpu_run_logged [list check_legality] {}]
set leg1 [unpu_parse_legality $lt2]
unpu_check_pass cts legality_after [expr {$leg1 ne "not parsed" && $leg1 == 0}] "check_legality after the optimisation: $leg1 violations (0 expected)"
set pct [unpu_run_logged [list check_pg_connectivity] {}]
array set fl [unpu_parse_pg_connectivity $pct]
foreach {k what} {cells "floating standard cells" wires "floating wires" vias "floating vias"} {
  set v [expr {[info exists fl($k)] ? $fl($k) : "not parsed"}]
  unpu_check_pass cts pg_conn_$k [expr {$v ne "not parsed" && $v == 0}] "$what: $v (0 expected once the cells are placed)"
}
# clock QoR after the optimisation: RESULT lines (latency and skew should not change much)
set cq2 [ct_report clock_qor_final "report_clock_qor -type summary"]
set pq2 [unpu_parse_clock_qor $cq2 $corners]
if {[lindex $pq2 0] eq "ok"} {
  array set q2 [lrange $pq2 1 end]
  unpu_result cts final_sinks $q2(sinks)
  unpu_result cts final_levels $q2(levels)
  unpu_result cts final_repeaters $q2(repeaters)
  foreach c $corners { unpu_result cts final_latency_ns_$c $q2(latency_$c); unpu_result cts final_skew_ns_$c $q2(skew_$c) }
} else {
  unpu_warn "the clock QoR after the optimisation could not be parsed: [lindex $pq2 1]"
}
# area, instances, buffers, utilisation: RESULT lines (first run 0.5 ns: area 427,619 -> 484,572 um2, instances 12,039 ->
# 14,309, buffers 214 -> 2,511, utilisation 66% -> 74.5%; 0.2 ns: 428,230 / 12,039 / 65.9%).
# VERIFY: report_utilization / report_qor texts; not readable = Warning, not a check
set ru [ct_report utilization "report_utilization"]
set rq [ct_report qor "report_qor"]
array set u [unpu_find_numbers "$ru\n$rq" {area {(?i)(total\s+)?(std\s*)?cell\s*area} instances {(?i)(number\s+of\s+)?(instances|cells)} buffers {(?i)buffers?} utilization {(?i)utili[sz]ation}}]
foreach k {area instances buffers utilization} {
  if {$u($k) eq ""} { unpu_warn "$k could not be read from report_utilization / report_qor (informational)"; set u($k) unavailable }
  unpu_result cts $k $u($k)
}

# ---- 8. verdict, then the second checkpoint --------------------------------------------------------
unpu_checks_finish cts               ;# stops here if any check failed: $BLK_CLKOPT is not saved
unpu_checkpoint $BLK_CLKOPT
unpu_result cts hold_uncertainty_ns $HOLD_UNCERT
unpu_result cts block_saved_clkopt $BLK_CLKOPT
unpu_info "done: blocks $BLK_CTS and $BLK_CLKOPT saved in $lib_path"
exit 0
