# =============================================================================
# placement.tcl -- script 10 of the back-end re-run: place_opt, checks, and the report of the input-port wires
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stages B5 and B6; the first place_opt: docs/session-handoff.md
# 18.16 (place_opt -list_only stages, 133 s, the checks, the hold residual that place_opt does not fix).
# Opens the block with fixed pins ($BLK_PINS, pin_place.tcl), runs the full place_opt (no option), checks the result, writes a per-input-port
# report of wire length against what the antenna rule tolerates (REPORT ONLY: no buffer, diode or other cell is added, nothing is changed),
# and saves $BLK_PLACED.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1
#   icc2_shell -file $UNPU_REPO/pnr/placement.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/placement.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Input: the library $LIB_DIR/$LIB_NAME with the block $BLK_PINS. Output: block $BLK_PLACED; reports in $RPT_DIR (placement_*.rpt,
# placed_port_report.csv); $LOG_DIR/manifest_placement.txt.
# The constraints: the stage profile PROFILE_PLACEMENT (`place`: 18 ns, setup uncertainty 1.2 ns, hold uncertainty 0.05 ns, ideal clock) of
# constraints/unpu_top.sdc is applied by unpu_apply_profile before place_opt (read_sdc in both scenarios, operating conditions, read-back CHECKS).
# Limit: setup WNS >= WNS_SETUP_PLACE (-1.0 ns, instructor); the violating-endpoint count is a RESULT.
# Hold is a Warning only: place_opt does not fix hold (the first run had 2,304 violating endpoints); cts.tcl does.
# If a CHECK fails the script prints every verdict and stops BEFORE saving $BLK_PLACED.
# Rerun: nothing is saved after the last checkpoint of a failed run, so a failed run can be run again as it is. A checkpoint name that
# exists is never reused (new UNPU_BLK_PLACED). No reliable remove-block command is known.
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
  unpu_die "design library not found: $lib_path. [unpu_prev_msg pin_place $BLK_PINS]"
}
unpu_stage_begin placement run [list $lib_path]
unpu_derive_die check          ;# the die from the synthesis area of UNPU_SYN_PROFILE (task 054); the floorplan record must name the same profile and die
if {$UNPU_CHECK_FAILED > 0} { unpu_die "the floorplan record does not match this run (UNPU_SYN_PROFILE / die): see the CHECK line above; nothing is done" }
if {![catch {get_blocks -quiet $BLK_PLACED} existing]} {
  if {[sizeof_collection $existing] > 0} {
    unpu_die "block $BLK_PLACED already exists in $lib_path; see the Rerun note in the header of placement.tcl (a new name in UNPU_BLK_PLACED)"
  }
} else {
  unpu_warn "could not list the blocks of the library ($existing); cannot tell whether block $BLK_PLACED exists already"
}
unpu_open_stage $lib_path $LIB_NAME $BLK_PINS pin_place
unpu_info "synthesis profile $SYN_PROFILE: netlist $NETLIST"
unpu_result placement syn_profile $SYN_PROFILE
unpu_netlist_expect          ;# NETLIST_MODULES, NETLIST_LEAF_CELLS computed from the netlist file

# preconditions: the 204 signal terminals of pin_place.tcl besides the power ones; the scenario status of design_setup.tcl
lassign [unpu_power_terminals] power_names power_boxes
set nsig [expr {[sizeof_collection [get_terminals -quiet]] - [llength $power_names]}]
unpu_check_pass placement pre_signal_terminals [expr {$nsig == $EXPECT_PORTS}] "$nsig signal terminals besides [llength $power_names] power terminals, $EXPECT_PORTS expected"
# VERIFY: get_attribute <scenario> setup / hold (as design_setup.tcl). A status that cannot be read is a Warning (report_scenarios is
# printed for a look by eye); a status that is read and wrong is a CHECK FAIL.
unpu_report placement scenarios "report_scenarios"
foreach {s su hd} [list $SCEN_SETUP true false $SCEN_HOLD false true] {
  if {![catch {list [get_attribute [get_scenarios $s] setup] [get_attribute [get_scenarios $s] hold]} got]} {
    unpu_check_pass placement scenario_status_$s [expr {[string is true -strict [lindex $got 0]] == [string is true $su] && [string is true -strict [lindex $got 1]] == [string is true $hd]}] \
        "scenario $s (setup, hold) = {$got}, expected {$su $hd}"
  } else {
    unpu_warn "could not read the setup/hold status of scenario $s ($got); look at placement_scenarios.rpt"
  }
}
if {$UNPU_CHECK_FAILED > 0} { unpu_die "a precondition failed; nothing is placed (see the CHECK lines above)" }

# the stage profile (task 053): period, uncertainty, operating conditions of both scenarios, read back and CHECKED, before place_opt
unpu_apply_profile $PROFILE_PLACEMENT
if {$UNPU_CHECK_FAILED > 0} { unpu_die "the stage profile $PROFILE_PLACEMENT is not in force (see the CHECK lines above); place_opt is not run" }

# ---- 2. the stages of place_opt ----------------------------------------------------------
set lo [unpu_run_logged [list place_opt -list_only] {}]
lassign [unpu_stages_in_text $lo $PLACE_OPT_STAGES] st_found st_missing
unpu_result placement place_opt_stages_found [join $st_found " "]
if {[llength $st_missing] > 0} {
  unpu_warn "place_opt -list_only does not name the stage(s) {$st_missing} of 18.16 ({$PLACE_OPT_STAGES}). Text seen: [string trim $lo]"
}

# ---- 3. place_opt (all stages; 133 s in the first run) ----------------------------------------------
# acts on both scenarios (setup in $SCEN_SETUP, hold in $SCEN_HOLD)
set t0 [clock seconds]
set po [unpu_run_logged [list place_opt] {LGL- PDC- FLW-}]
unpu_result placement place_opt_seconds [expr {[clock seconds] - $t0}]
foreach prefix {FLW OPT PLACE LGL ZRT} {
  foreach {id n} [unpu_count_ids $po $prefix] {
    unpu_info "place_opt: message id $id appears $n time(s)"
    unpu_result placement msg_${id}_count $n
  }
}

# ---- 4. checks -----------------------------------------------------------------------------------
# setup (acts on $SCEN_SETUP). First run: WNS 0.0000, 0 violating endpoints, worst path paddr[3] -> prdata[23], slack 0.00
lassign [unpu_timing_summary placement $SCEN_SETUP max setup] ws sv sg spaths
unpu_result placement worst_setup_slack_ns $ws
if {[llength $spaths] > 0} { unpu_result placement worst_setup_path [lindex [unpu_worst_endpoints $spaths 1] 0] }
unpu_result placement setup_violating_endpoints $sv
unpu_result placement setup_wns_margin_ns [unpu_wns_margin $ws $WNS_SETUP_PLACE]
unpu_check_pass placement setup_wns [unpu_wns_ok $ws $WNS_SETUP_PLACE] "worst setup slack $ws ns in $SCEN_SETUP, limit $WNS_SETUP_PLACE ns (margin [unpu_wns_margin $ws $WNS_SETUP_PLACE] ns; 'unavailable' fails); $sv setup-violating endpoint(s); by group {$sg}"
# hold (acts on $SCEN_HOLD): RESULT and a Warning, NOT a check
lassign [unpu_timing_summary placement $SCEN_HOLD min hold] wh hv hg hpaths
unpu_result placement worst_hold_slack_ns $wh
unpu_result placement hold_violating_endpoints $hv
if {$hv eq "unavailable"} {
  unpu_warn "the number of hold-violating endpoints could not be read; worst hold slack $wh ns"
} elseif {$hv != 0} {
  unpu_warn "$hv hold-violating endpoint(s) in $SCEN_HOLD after place_opt (worst slack $wh ns). place_opt does NOT fix hold (the first run had 2,304 here); cts.tcl does. Not a failure."
}
# max transition / capacitance (first run: 0 and 0)
foreach {kind opt} {max_transition -max_transition max_capacitance -max_capacitance} {
  set cnt [unpu_constraint_count placement $kind $opt]
  unpu_check_pass placement $kind [expr {$cnt ne "unavailable" && $cnt == 0}] "$cnt $kind violation(s) after place_opt (0 expected; 'unavailable' fails)"
}
# legality (the PDC-003 warning about the GC layer's routing direction is benign and printed above)
set lt [unpu_run_logged [list check_legality] {PDC-}]
set leg [unpu_parse_legality $lt]
unpu_check_pass placement legality [expr {$leg ne "not parsed" && $leg == 0}] "check_legality after place_opt: $leg violations (0 expected)"
# power connectivity: the check power.tcl could not make because nothing was placed (first run: 11,986 cells, 0 floating)
set pct [unpu_run_logged [list check_pg_connectivity] {}]
array set fl [unpu_parse_pg_connectivity $pct]
foreach {k what} {cells "floating standard cells" wires "floating wires" vias "floating vias" terminals "floating terminals"} {
  set v [expr {[info exists fl($k)] ? $fl($k) : "not parsed"}]
  unpu_check_pass placement pg_conn_$k [expr {$v ne "not parsed" && $v == 0}] "$what: $v (0 expected)"
}

# utilisation (instructor POST 2: post-placement <= 75 percent) and congestion (overflow <= 1 percent): CHECKS (task 054); the growth row of this stage
unpu_check_utilization placement $UTIL_MAX_PLACE place_opt
unpu_check_congestion placement place_opt 1
unpu_growth_row placement place

# ---- 5. RESULT lines (first run: area 426,097.72 um2, 11,986 instances, 161 buffers, 1,353 inverters) ----------------
# VERIFY: report_utilization / report_qor texts; not readable = Warning, not a check
set ru [unpu_report placement utilization "report_utilization"]
set rq [unpu_report placement qor "report_qor"]
array set u [unpu_find_numbers "$ru\n$rq" {area {(?i)(total\s+)?(std\s*)?cell\s*area} instances {(?i)(number\s+of\s+)?(instances|cells)} buffers {(?i)buffers?} inverters {(?i)inverters?} utilization {(?i)utili[sz]ation} wire_length {(?i)(total\s+)?wire\s*length}}]
foreach k {area instances buffers inverters utilization wire_length} {
  if {$u($k) eq ""} { unpu_warn "$k could not be read from report_utilization / report_qor (informational)"; set u($k) unavailable }
  unpu_result placement $k $u($k)
}
# place_opt merges and removes cells: the netlist's leaf count and the placed count differ (501 in the first run)
set nleaf [sizeof_collection [get_cells -hierarchical -filter "is_hierarchical==false"]]
unpu_result placement leaf_cells_netlist $NETLIST_LEAF_CELLS
unpu_result placement leaf_cells_placed $nleaf
unpu_result placement leaf_cells_difference [expr {$NETLIST_LEAF_CELLS - $nleaf}]

# ---- 6. the report of the input-port wires (plan B6): REPORT ONLY -------------------------------------------
# For every input port except clk: its net, the load pins, the HPWL of the net, the gate area of the loads, and the estimated antenna ratio
# of a single-layer run, flagged above ANT_RATIO. Nothing is added or changed. Every command here is a read; each is in a catch, and a port
# whose data cannot be read gets a line that says so (the run goes on).
# VERIFY: get_attribute <port> direction (values in/out) ; get_nets -of_objects <port> ; get_pins -leaf -of_objects <net> ; get_attribute <net> bbox ;
# get_attribute <pin> bbox ; get_attribute <port> bbox ; the gate-area attribute names in GATE_AREA_ATTRS (guesses).
proc pr_input_ports {} {
  set ports {}
  foreach_in_collection p [get_ports *] {
    set nm [get_object_name $p]
    if {[catch {get_attribute $p direction} d]} { return [list unavailable "get_attribute direction failed: $d"] }
    if {$d eq "in" || $d eq "input"} { lappend ports $nm }
  }
  return [list ok $ports]
}
# the gate area of one load pin, "" if no attribute could be read. Tries each of GATE_AREA_ATTRS on the pin, then on its library pin.
proc pr_pin_gate_area {pin} {
  global GATE_AREA_ATTRS
  foreach a $GATE_AREA_ATTRS {
    if {![catch {get_attribute $pin $a} v] && [string is double -strict $v]} { return $v }
  }
  if {![catch {get_lib_pins -quiet -of_objects $pin} lp] && [sizeof_collection $lp] == 1} {
    foreach a $GATE_AREA_ATTRS {
      if {![catch {get_attribute $lp $a} v] && [string is double -strict $v]} { return $v }
    }
  }
  return ""
}
# one report row for a port: {port net loads hpwl gate_area gate_source ratio flag method}
proc pr_port_row {port} {
  global MIN_GATE_AREA HPWL_DETOUR ANT_WEIGHT_TOP ANT_RATIO
  set net "n/a"; set hpwl unavailable; set method "none"
  if {[catch {get_nets -quiet -of_objects [get_ports -exact $port]} nets] || [sizeof_collection $nets] != 1} {
    return [list $port "no net found" "n/a" unavailable $MIN_GATE_AREA "assumed (no net)" unavailable unknown none]
  }
  set net [get_object_name $nets]
  # everything about the load pins is read INSIDE the loop (a collection element is used while it is in scope, never kept in a Tcl list)
  set loads 0; set boxes {}; set gate 0.0; set gate_ok 1
  if {![catch {get_pins -quiet -leaf -of_objects $nets -filter "direction==in"} lp]} {
    foreach_in_collection p $lp {
      incr loads
      if {![catch {get_attribute $p bbox} b]} { set bx [unpu_parse_bbox $b]; if {[llength $bx] == 4} { lappend boxes $bx } }
      set a [pr_pin_gate_area $p]
      if {$a eq ""} { set gate_ok 0 } else { set gate [expr {$gate + $a}] }
    }
  }
  # HPWL: the net bbox attribute if it can be read; else the centres of the load pins and of the port (min/max of the points)
  if {![catch {get_attribute $nets bbox} bb]} { set hpwl [unpu_hpwl_of_bbox $bb]; if {$hpwl ne "unavailable"} { set method net_bbox } }
  if {$hpwl eq "unavailable"} {
    if {![catch {get_attribute [get_ports -exact $port] bbox} b]} { set bx [unpu_parse_bbox $b]; if {[llength $bx] == 4} { lappend boxes $bx } }
    set hpwl [unpu_hpwl_of_boxes $boxes]
    if {$hpwl ne "unavailable"} { set method pin_boxes }
  }
  # gate area: the sum over the loads when every load's area could be read, else the assumed MIN_GATE_AREA
  if {$gate_ok && $loads > 0} { set src "library ($loads load pin(s))" } else { set gate $MIN_GATE_AREA; set src "assumed MIN_GATE_AREA" }
  set ratio [unpu_antenna_estimate $hpwl $HPWL_DETOUR $ANT_WEIGHT_TOP $gate]
  return [list $port $net $loads $hpwl $gate $src $ratio [unpu_antenna_flag $ratio $ANT_RATIO] $method]
}
lassign [pr_input_ports] pstat pdata
set rows {}
if {$pstat ne "ok"} {
  unpu_warn "the input ports could not be determined ($pdata); the port report is empty. Planning: the port direction attribute is not confirmed (VERIFY)"
} else {
  foreach port $pdata {
    if {$port eq "clk"} continue
    lappend rows [pr_port_row $port]
  }
}
unpu_result placement report_input_ports [llength $rows]
set csv [file join $RPT_DIR placed_port_report.csv]
unpu_no_kit_write $csv
set fh [open $csv w]; foreach l [unpu_port_report_csv $rows] { puts $fh $l }; close $fh
unpu_info "port report: $csv ([llength $rows] input ports except clk)"
set sorted [unpu_port_report_sort $rows]
unpu_info "worst 10 by estimated antenna ratio (assumed: single layer, detour $HPWL_DETOUR, weight $ANT_WEIGHT_TOP; Calibre decides):"
foreach r [lrange $sorted 0 9] {
  lassign $r port net loads hpwl gate src ratio flag method
  unpu_info [format "  %-14s hpwl %s um  gate %s um2 (%s)  ratio %s  %s" $port [expr {[string is double -strict $hpwl] ? [format %.1f $hpwl] : "unavailable"}] [expr {[string is double -strict $gate] ? [format %.3f $gate] : $gate}] $src [expr {[string is double -strict $ratio] ? [format %.1f $ratio] : "unavailable"}] [expr {$flag eq "1" ? "FLAG" : $flag eq "0" ? "ok" : "unknown"}]]
}
lassign [unpu_port_report_summary $rows $PORT_REPORT_LONG_UM] nflag lh lp nlong nunk
unpu_result placement port_report_flagged $nflag
unpu_result placement port_report_longest_hpwl_um [expr {[string is double -strict $lh] ? [format %.1f $lh] : $lh}]
unpu_result placement port_report_longest_port $lp
unpu_result placement port_report_hpwl_above_${PORT_REPORT_LONG_UM}um $nlong
unpu_result placement port_report_hpwl_unavailable $nunk
if {$nflag > 0} {
  set names {}
  foreach r $sorted { if {[lindex $r 7] eq "1"} { lappend names [lindex $r 0] }; if {[llength $names] >= 20} break }
  unpu_warn "$nflag input-port net(s) have an estimated antenna ratio above $ANT_RATIO ([join $names { }][expr {$nflag > 20 ? {, ...} : {}}]). This is an ESTIMATE (HPWL x $HPWL_DETOUR, single layer, weight $ANT_WEIGHT_TOP); Calibre decides. The later fix loop starts from this list (first run: paddr\[4\], 180 um)."
}
if {$nunk > 0} { unpu_warn "$nunk input port(s) have no readable HPWL (their lines in $csv say so)" }

# ---- 7. verdict, then the placed block ------------------------------------------------------------------
unpu_checks_finish placement             ;# stops here if any check failed: $BLK_PLACED is not saved
unpu_checkpoint $BLK_PLACED
unpu_result placement block_saved_placed $BLK_PLACED
unpu_info "done: block $BLK_PLACED saved in $lib_path. This block still has no clock tree and no hold fixing; cts.tcl is next."
exit 0
