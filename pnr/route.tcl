# =============================================================================
# route.tcl -- script 6 of the back-end re-run: antenna rule first, then routing and route optimisation
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage D; commands that worked in the first
# run: docs/session-handoff.md 18.20 (route_auto, route_opt, the checks and what they did not do), 18.22 (route_opt deletes
# fillers), 18.25 and 18.26 (the antenna rule that worked), 18.27 (why the input-port nets matter).
# No route option beyond the handoff's and no antenna option beyond define_antenna_rule (and reading the options) is used:
# NO diode option, no route.detail.antenna_fixing_preference (its valid values are not known until the help probe is read).
# After define_antenna_rule the value of route.detail.antenna is read; anything but true is a loud Warning (the router only fixes
# antennas if it is on). It is a Warning, not a CHECK, and the script never sets the option.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1
#   icc2_shell -file $UNPU_REPO/pnr/route.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/route.log
#   (VERIFY -file / -output_log_file in icc2_shell)
#
# Input: the library $LIB_DIR/$LIB_NAME with the block $BLK_CLKOPT (cts.tcl). Start from another hold experiment with
#   UNPU_BLK_CLKOPT (for example clkopt_h02).
# Output: block $BLK_ROUTE_AUTO (right after route_auto, if its critical checks pass: the fallback if route_opt goes wrong)
#   and block $BLK_ROUTED (after route_opt and all checks); reports in $RPT_DIR (route_*.rpt); $LOG_DIR/manifest_route.txt.
#
# THE ROUTED BLOCK IS UNFILLED ON PURPOSE. It is the fallback for every later step. Fill, outputs and the Calibre antenna
# check come next, and Calibre decides the antenna question: ICC2 does not analyse input-port nets (ZRT-311), so "antenna 0"
# from check_routes here is NOT the final word.
#
# Order: antenna rule -> route_auto -> checks -> save routeauto -> route_opt -> checks -> save routed.
# Hold is a Warning after route_auto and a CHECK after route_opt (plan D2). If the hold check fails the script stops without
# saving, UNLESS the environment variable UNPU_ROUTE_ACCEPT_HOLD is 1 (default 0, never set it without a written reason):
# then it saves, records hold_accepted = 1 and the endpoint list in the manifest and prints the worst endpoints. Only the hold
# check can be overridden, and only when the number of violating endpoints is KNOWN and above zero.
#
# Rerun: nothing is saved after the last checkpoint of a failed run, and a checkpoint name that exists is never reused. A
# run that failed before "RESULT route block_saved_route_auto" can be run again as it is. After it, run again with new names:
# setenv UNPU_BLK_ROUTE_AUTO routeauto2 ; setenv UNPU_BLK_ROUTED routed2 (it starts from $BLK_CLKOPT again). No reliable
# remove-block command is known.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

# ---- 1. start ----------------------------------------------------------------
unpu_require_tool_version $ICC2_VERSION            ;# VERIFY how the version is exposed (see common.tcl)
set UNPU_CHECK_CONTINUE 1
set lib_path $LIB_DIR/$LIB_NAME
if {![file exists $lib_path]} {
  unpu_die "design library not found: $lib_path. The earlier scripts run first (same UNPU_WORK and UNPU_RUN_TAG)"
}
unpu_stage_begin route run [list $lib_path]
# neither checkpoint block may exist. VERIFY (server): get_blocks -quiet <name>
foreach b [list $BLK_ROUTE_AUTO $BLK_ROUTED] {
  if {![catch {get_blocks -quiet $b} existing]} {
    if {[sizeof_collection $existing] > 0} {
      unpu_die "block $b already exists in $lib_path; see the Rerun note in the header of route.tcl (new names in UNPU_BLK_ROUTE_AUTO / UNPU_BLK_ROUTED)"
    }
  } else {
    unpu_warn "could not list the blocks of the library ($existing); cannot tell whether block $b exists already"
  }
}
unpu_open_stage $lib_path $LIB_NAME $BLK_CLKOPT
# VERIFY: no command known to tell whether the block already has routed signal nets. The input is the clock-optimised block,
# in which only the clock nets are detail-routed (route_clock, 18.17), so this is not tested.
unpu_warn "cannot tell by a command whether the block already has routed nets; the input is $BLK_CLKOPT (only the clock nets are routed in it)"
set lt [unpu_run_logged [list check_legality] {}]
set leg0 [unpu_parse_legality $lt]
unpu_check_pass route legality_before [expr {$leg0 ne "not parsed" && $leg0 == 0}] "check_legality on $BLK_CLKOPT: $leg0 violations (0 expected)"
if {$UNPU_CHECK_FAILED > 0} { unpu_die "the input block is not legal; nothing is routed" }

# ---- 2. the antenna rule, BEFORE any route command (18.25) ------------------------------------------
# define_antenna_rule -mode 4 -diode_mode 1 -metal_ratio <r> -cut_ratio 0 applied to M1, M2, M3 and TOP_M in the first run.
# ANT_RATIO (300) is stricter than Calibre's 400 for the reason in plan 2.3 D3. NO diode option, no antenna_fixing_preference.
unpu_run_logged [list define_antenna_rule -mode $ANT_MODE -diode_mode $ANT_DIODE_MODE -metal_ratio $ANT_RATIO -cut_ratio $ANT_CUT_RATIO] {}
unpu_result route antenna_rule "mode $ANT_MODE diode_mode $ANT_DIODE_MODE metal_ratio $ANT_RATIO cut_ratio $ANT_CUT_RATIO (Calibre limit $ANT_CALIBRE_LIMIT)"
# print the antenna-related application options with their values. VERIFY: get_app_options / report_app_options <pattern>
set antopt_text ""
if {[catch {set antopt_text [unpu_report route antenna_options "report_app_options $ROUTE_ANTENNA_OPTION_PATTERN"]} m]} {
  unpu_warn "report_app_options $ROUTE_ANTENNA_OPTION_PATTERN failed ($m); trying get_app_options"
  if {[catch {set antopt_text [get_app_options $ROUTE_ANTENNA_OPTION_PATTERN]; puts $antopt_text} m2]} { unpu_warn "get_app_options $ROUTE_ANTENNA_OPTION_PATTERN failed too ($m2)" }
}
# the router fixes antennas only if route.detail.antenna is on: read its value (get_app_option_value -name; VERIFY, else the
# printed report) and make a loud Warning of anything but true. Not a CHECK: the routing goes on (task 044 follow-up).
set ant_value ""
if {![catch {get_app_option_value -name $ROUTE_ANTENNA_ENABLE_OPTION} v]} { set ant_value $v } else {
  unpu_info "get_app_option_value -name $ROUTE_ANTENNA_ENABLE_OPTION failed ($v); reading the value from the printed options"
  set ant_value [unpu_app_option_from_report $antopt_text $ROUTE_ANTENNA_ENABLE_OPTION]
}
lassign [unpu_antenna_switch_message $ROUTE_ANTENNA_ENABLE_OPTION $ant_value] ant_state ant_msg
unpu_result route antenna_switch_state "$ant_state ($ROUTE_ANTENNA_ENABLE_OPTION = '$ant_value')"
if {$ant_state eq "on"} { unpu_info $ant_msg } else { unpu_warn $ant_msg }

# ---- helpers ---------------------------------------------------------------------------------------
# message ids of a route command's output: counts for ZRT-, OPT-, FLW-; ZRT-309 is returned for the check
proc rt_ids {label text} {
  set z309 0
  foreach prefix {ZRT OPT FLW} {
    foreach {id n} [unpu_count_ids $text $prefix] {
      unpu_info "$label: message id $id appears $n time(s)"
      unpu_result route ${label}_${id}_count $n
      if {$id eq "ZRT-309"} { set z309 $n }
    }
  }
  return $z309
}
# the checks after a routing command. final = 0: only the critical ones are CHECKs (open nets, DRCs, shorts/opens, legality);
# everything else is a RESULT or a Warning (hold is a Warning after route_auto). final = 1: every check is a CHECK.
# Returns the hold decision text for the final stage. tag is route_auto or route_opt.
proc rt_checks {tag final cmd_text} {
  global SCEN_SETUP SCEN_HOLD HOLD_UNCERT ROUTE_ACCEPT_HOLD HOLD_ENDPOINTS_LISTED RPT_DIR
  # check_routes (VERIFY: the first run printed a "Verify Summary" block)
  set crt [unpu_report route ${tag}_check_routes "check_routes"]
  array set cr [unpu_parse_check_routes $crt]
  unpu_check_pass route ${tag}_open_nets [expr {$cr(open_nets) ne "not parsed" && $cr(open_nets) == 0}] "open nets after $tag: $cr(open_nets) (0 expected; 'not parsed' = read the log); frozen $cr(frozen)"
  unpu_check_pass route ${tag}_drcs [expr {$cr(drcs) ne "not parsed" && $cr(drcs) == 0}] "DRCs after $tag: $cr(drcs) (0 expected)"
  unpu_result route ${tag}_nets $cr(nets)
  unpu_result route ${tag}_nets_not_extracted $cr(not_extracted)
  if {[llength $cr(tie_lines)] > 0} { foreach l $cr(tie_lines) { unpu_info "check_routes: $l" }; unpu_result route ${tag}_tie_to_rail "not checked (known gap, 18.20)" } else { unpu_result route ${tag}_tie_to_rail "not reported" }
  set skipped [unpu_zrt311_nets "$cmd_text\n$crt"]      ;# ZRT-311 may be printed by the route command or by check_routes
  unpu_result route ${tag}_antenna_port_nets_skipped [llength $skipped]
  if {[llength $skipped] > 0} {
    set f [file join $RPT_DIR route_${tag}_antenna_port_nets_skipped.txt]
    set fh [open $f w]; foreach n $skipped { puts $fh $n }; close $fh
    unpu_info "ICC2 skipped the antenna analysis of [llength $skipped] input-port net(s) (ZRT-311, no gate-area data at macro ports; list in $f): 'antenna 0' below is NOT the final word, Calibre decides: [join [lrange $skipped 0 9] { }]..."
    unpu_result route ${tag}_antenna_port_nets_skipped_names [join $skipped " "]
  }
  # check_lvs (VERIFY the text; 18.20 gives the numbers: 0 shorts, 0 opens, 0 floating routes)
  set lvs [unpu_report route ${tag}_check_lvs "check_lvs"]
  array set lv [unpu_parse_check_lvs $lvs]
  unpu_check_pass route ${tag}_lvs_shorts [expr {$lv(shorts) ne "not parsed" && $lv(shorts) == 0}] "check_lvs shorts: $lv(shorts) (0 expected)"
  unpu_check_pass route ${tag}_lvs_opens [expr {$lv(opens) ne "not parsed" && $lv(opens) == 0}] "check_lvs opens: $lv(opens) (0 expected)"
  if {$final} {
    unpu_check_pass route ${tag}_lvs_floating [expr {$lv(floating) ne "not parsed" && $lv(floating) == 0}] "check_lvs floating routes: $lv(floating) (0 expected)"
    set av $cr(antenna)
    unpu_check_pass route ${tag}_antenna_violations [expr {$av ne "not parsed" && $av == 0}] "ICC2 antenna violations: $av (0 expected; input-port nets are skipped by ICC2, Calibre decides)"
  } else {
    unpu_result route ${tag}_antenna_violations $cr(antenna)
    unpu_result route ${tag}_lvs_floating $lv(floating)
  }
  # legality and power connectivity
  set lt [unpu_run_logged [list check_legality] {}]
  set leg [unpu_parse_legality $lt]
  unpu_check_pass route ${tag}_legality [expr {$leg ne "not parsed" && $leg == 0}] "check_legality after $tag: $leg violations (0 expected)"
  if {$final} {
    set pct [unpu_run_logged [list check_pg_connectivity] {}]
    array set fl [unpu_parse_pg_connectivity $pct]
    foreach {k what} {cells "floating standard cells" wires "floating wires" vias "floating vias" terminals "floating terminals"} {
      set v [expr {[info exists fl($k)] ? $fl($k) : "not parsed"}]
      unpu_check_pass route ${tag}_pg_conn_$k [expr {$v ne "not parsed" && $v == 0}] "$what: $v (0 expected)"
    }
  }
  # setup (in $SCEN_SETUP)
  lassign [unpu_timing_summary route $SCEN_SETUP max ${tag}_setup] ws sv sg spaths
  unpu_result route ${tag}_worst_setup_slack_ns $ws
  if {$final} {
    unpu_check_pass route ${tag}_setup_violations [expr {$sv ne "unavailable" && $sv == 0}] "$sv setup-violating endpoint(s) in $SCEN_SETUP after $tag (0 expected; 'unavailable' fails); worst slack $ws ns; by group {$sg}"
  } elseif {$sv ne "unavailable" && $sv != 0} {
    unpu_warn "$sv setup-violating endpoint(s) in $SCEN_SETUP after $tag (worst $ws ns); route_opt follows"
  }
  # hold (in $SCEN_HOLD): a Warning after route_auto, a CHECK after route_opt with the explicit never-default switch
  lassign [unpu_timing_summary route $SCEN_HOLD min ${tag}_hold] wh hv hg hpaths
  unpu_result route ${tag}_worst_hold_slack_ns $wh
  unpu_result route ${tag}_hold_violating_endpoints $hv
  set worst [unpu_worst_endpoints $hpaths $HOLD_ENDPOINTS_LISTED]
  set decision ""
  if {!$final} {
    if {$hv eq "unavailable" || $hv != 0} {
      unpu_warn "hold after $tag: $hv violating endpoint(s), worst $wh ns (the first run had -0.01 ns here and route_opt cleared it). Worst: [join $worst { ; }]"
    }
  } else {
    set decision [unpu_hold_decision $hv $ROUTE_ACCEPT_HOLD]
    if {$decision eq "pass"} {
      unpu_check_pass route ${tag}_hold_violations 1 "0 hold-violating endpoints in $SCEN_HOLD after $tag at hold uncertainty $HOLD_UNCERT; worst slack $wh ns"
    } elseif {$decision eq "accepted"} {
      puts "Warning: \[unpu\] CHECK route ${tag}_hold_violations ACCEPTED BY UNPU_ROUTE_ACCEPT_HOLD=1: $hv hold-violating endpoint(s) remain in $SCEN_HOLD (worst $wh ns). The routed block is saved with a hold residual; this needs a written reason. Worst [llength $worst]: [join $worst { ; }]"
      unpu_manifest_append route [concat [list "hold_accepted = 1" "hold_violating_endpoints = $hv" "hold_worst_slack_ns = $wh" "hold_uncertainty_ns = $HOLD_UNCERT"] [unpu_hold_endpoint_lines $worst]]
      unpu_result route hold_accepted 1
    } else {
      unpu_check_pass route ${tag}_hold_violations 0 "$hv hold-violating endpoint(s) in $SCEN_HOLD after $tag at hold uncertainty $HOLD_UNCERT ('unavailable' = could not be counted); worst slack $wh ns; by group {$hg}. Worst: [join $worst { ; }]. [expr {$hv eq {unavailable} ? {UNPU_ROUTE_ACCEPT_HOLD cannot override a count that could not be obtained.} : {To go on knowingly: setenv UNPU_ROUTE_ACCEPT_HOLD 1 (with a written reason).}}]"
    }
  }
  # max transition / capacitance
  foreach {kind opt} {max_transition -max_transition max_capacitance -max_capacitance} {
    set cnt [unpu_constraint_count route ${tag}_$kind $opt]
    if {$final} {
      unpu_check_pass route ${tag}_$kind [expr {$cnt ne "unavailable" && $cnt == 0}] "$cnt $kind violation(s) after $tag (0 expected; 'unavailable' fails)"
    } else {
      unpu_result route ${tag}_$kind $cnt
    }
  }
  return $decision
}
# the routing summary of a command's output as RESULT lines (wire length and vias per layer, open nets, DR iterations)
proc rt_summary {tag text} {
  global ROUTE_WIRE_LAYERS ROUTE_VIA_LAYERS
  foreach {k v} [unpu_parse_route_summary $text $ROUTE_WIRE_LAYERS $ROUTE_VIA_LAYERS] {
    set shown [expr {$v eq "" ? "not found in the output" : $v}]
    unpu_result route ${tag}_$k $shown
  }
  foreach it [unpu_parse_dr_iterations $text] { unpu_result route ${tag}_dr_iteration_[lindex $it 0]_violations [lindex $it 1] }
}

# ---- 3. route_auto (18.20) ---------------------------------------------------------------------------
# acts on all scenarios (the router uses the timing of both for timing-driven routing)
set ra [unpu_run_logged [list route_auto] {ZRT- FLW-}]
rt_summary route_auto $ra
set z309a [rt_ids route_auto $ra]
unpu_check_pass route route_auto_zrt309 [expr {$z309a == 0}] "$z309a occurrence(s) of ZRT-309 ('No antenna rules defined') in the route_auto output (0 expected: the rule is defined before routing)"

# ---- 4. checks after route_auto; save routeauto only if the critical ones pass ------------------------
rt_checks route_auto 0 $ra
if {$UNPU_CHECK_FAILED > 0} { unpu_die "route_auto failed its critical checks (ZRT-309, open nets, DRCs, shorts/opens, legality); no checkpoint saved (see the CHECK lines above)" }
unpu_checkpoint $BLK_ROUTE_AUTO
unpu_result route block_saved_route_auto $BLK_ROUTE_AUTO

# ---- 5. route_opt (18.20) --------------------------------------------------------------------------------
set ro [unpu_run_logged [list route_opt] {ZRT- OPT- FLW- fillers}]
rt_summary route_opt $ro
set z309o [rt_ids route_opt $ro]
unpu_check_pass route route_opt_zrt309 [expr {$z309o == 0}] "$z309o occurrence(s) of ZRT-309 in the route_opt output (0 expected)"
array set optids [unpu_count_ids $ro OPT]
if {[info exists optids(OPT-209)]} {
  unpu_warn "OPT-209 ('unreasonable large hold violation(s)') appeared $optids(OPT-209) time(s) in the route_opt output. The first run printed it twice with a clean QoR: the QoR checks below decide."
}
if {[regexp -nocase -- {deleted\s+[0-9,]*\s*filler} $ro]} {
  unpu_warn "route_opt reports that fillers were deleted; there are none at this stage, so this is unexpected"
}

# ---- 6. checks after route_opt (every one a CHECK; hold with the explicit switch) --------------------------
set decision [rt_checks route_opt 1 $ro]
# area, instances, utilisation (RESULT lines, as cts.tcl). VERIFY: report_utilization / report_qor texts
set ru [unpu_report route utilization "report_utilization"]
set rq [unpu_report route qor "report_qor"]
array set u [unpu_find_numbers "$ru\n$rq" {area {(?i)(total\s+)?(std\s*)?cell\s*area} instances {(?i)(number\s+of\s+)?(instances|cells)} utilization {(?i)utili[sz]ation}}]
foreach k {area instances utilization} {
  if {$u($k) eq ""} { unpu_warn "$k could not be read from report_utilization / report_qor (informational)"; set u($k) unavailable }
  unpu_result route $k $u($k)
}

# ---- 7. verdict, then the routed block ---------------------------------------------------------------------
unpu_checks_finish route             ;# stops here if any check failed: $BLK_ROUTED is not saved
unpu_checkpoint $BLK_ROUTED
unpu_result route block_saved_routed $BLK_ROUTED
unpu_result route hold_decision [expr {$decision eq "" ? "n/a" : $decision}]
unpu_info "done: blocks $BLK_ROUTE_AUTO and $BLK_ROUTED saved in $lib_path. The routed block is UNFILLED on purpose (the fallback for every later step); fill, outputs and the Calibre antenna check come next, and Calibre decides the antenna question."
exit 0
