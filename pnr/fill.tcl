# =============================================================================
# fill.tcl -- script 7 of the back-end re-run: filler cells, the LAST step in ICC2 before the outputs
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage E1; commands that worked in the first
# run: docs/session-handoff.md 18.22 (fillers: what went wrong, the order that works, the hold residual and the decision about
# it) and 18.23 (what the outputs need). Only the fill option of 18.22 is used:
#   create_stdcell_fillers -lib_cells [get_lib_cells */feedth*] -prefix FILLER -rules post_route_auto_delete
#
# FILL IS THE LAST STEP. Any later route_opt DELETES ALL FILLERS and does not put them back (18.22). A routing change means going
# back to the routed block ($BLK_ROUTED) and filling again. Never run route_opt on the final block.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1
#   icc2_shell -file $UNPU_REPO/pnr/fill.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/fill.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Input: the library $LIB_DIR/$LIB_NAME with the routed, UNFILLED block $BLK_ROUTED (route.tcl); start from another one with
#   UNPU_BLK_ROUTED. The filler cells come from the library that ndm_file_gen.tcl built (task 038): their presence and type
#   (design_type filler) are CHECKED here, never repaired here -- fix them in ndm_file_gen.tcl / ndm_check.tcl.
# Output: block $BLK_FINAL (filled); reports in $RPT_DIR (fill_*.rpt); $LOG_DIR/manifest_fill.txt.
#
# Order: preconditions (fillers typed filler, no fillers yet, input routes clean, input legal) -> read the standard-cell area ->
#   create_stdcell_fillers -> connect_pg_net -automatic AT ONCE (without it the DRC engine reports ~17,766 false M1 shorts) ->
#   pin count and coverage checks -> filler violations (-check_only) -> routes / legality / PG / timing -> save final.
# Hold: zero violating endpoints is a CHECK pass. A residual of at most FILL_HOLD_MAX_ENDPOINTS endpoints, none worse than
#   -FILL_HOLD_TOLERANCE_NS (0.001 ns), is the
#   decision of 2026-10-29 (18.22 option A): a Warning with the endpoints, hold_residual_accepted = 1 in the manifest, PrimeTime
#   judges it. Anything worse, or a count that could not be read, FAILS. There is no environment switch for hold here.
# UNPU_FILL_ECO=1 (default 0): if fillers with violations remain, route_eco runs ONCE and the check is repeated (never a second round).
#
# If a CHECK fails the script prints every verdict and stops BEFORE saving $BLK_FINAL.
# Rerun: nothing is saved after the last checkpoint of a failed run; fill is re-done from $BLK_ROUTED under a new name:
#   setenv UNPU_BLK_FINAL final2   (or a new UNPU_RUN_TAG, which needs the whole flow again). No reliable remove-block command is known.
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
unpu_stage_begin fill run [list $lib_path]
# the final block must not exist. VERIFY (server): get_blocks -quiet <name>
if {![catch {get_blocks -quiet $BLK_FINAL} existing]} {
  if {[sizeof_collection $existing] > 0} {
    unpu_die "block $BLK_FINAL already exists in $lib_path; see the Rerun note in the header of fill.tcl (a new name in UNPU_BLK_FINAL)"
  }
} else {
  unpu_warn "could not list the blocks of the library ($existing); cannot tell whether block $BLK_FINAL exists already"
}
unpu_open_stage $lib_path $LIB_NAME $BLK_ROUTED

# ---- 2. preconditions (each a CHECK; nothing is inserted if one fails) --------------------------------------
# 2a. the filler cells: exactly FILLER_CELLS, each with design_type filler. VERIFY: get_lib_cells -quiet <pattern>; get_attribute <cell> design_type
set fcoll [get_lib_cells -quiet $FILLER_PATTERN]
set fnames {}
set ftypes {}
foreach_in_collection c $fcoll {
  lappend fnames [lindex [split [get_object_name $c] /] end]
  lappend ftypes "[lindex [split [get_object_name $c] /] end]=[get_attribute $c design_type]"
}
set fnames [lsort $fnames]
set want [lsort $FILLER_CELLS]
set fix "create_stdcell_fillers would fail with CHF-010/CHF-011 (18.22). This is fixed in ndm_file_gen.tcl / ndm_check.tcl (the filler library must give the cells design_type filler), NOT here"
unpu_check_pass fill filler_cells_found [expr {$fnames eq $want}] "$FILLER_PATTERN matches {$fnames}, expected exactly {$want}. $fix"
set untyped {}
foreach ft $ftypes { if {[lindex [split $ft =] 1] ne "filler"} { lappend untyped $ft } }
unpu_check_pass fill filler_cells_typed [expr {[llength $ftypes] > 0 && [llength $untyped] == 0}] "design_type of the filler cells: {$ftypes} (every one must be filler; not filler: {$untyped}). $fix"
# 2b. no filler cell in the block yet. VERIFY: get_cells -quiet -hierarchical -filter "ref_name==<cell>"
set present 0
set present_ok 1
foreach f $FILLER_CELLS {
  if {[catch {sizeof_collection [get_cells -quiet -hierarchical -filter "ref_name==$f"]} n]} { set present_ok 0; unpu_warn "could not count the cells of reference $f ($n)"; continue }
  incr present $n
}
unpu_check_pass fill no_fillers_yet [expr {$present_ok && $present == 0}] "$present cell(s) of reference {$FILLER_CELLS} in $BLK_ROUTED (0 expected; a block that already has fillers is not filled twice)"
# 2c. the routed input is clean: check_routes and check_legality
set crt [unpu_report fill input_check_routes "check_routes"]
array set cri [unpu_parse_check_routes $crt]
unpu_check_pass fill input_open_nets [expr {$cri(open_nets) ne "not parsed" && $cri(open_nets) == 0}] "open nets in $BLK_ROUTED: $cri(open_nets) (0 expected)"
unpu_check_pass fill input_drcs [expr {$cri(drcs) ne "not parsed" && $cri(drcs) == 0}] "DRCs in $BLK_ROUTED: $cri(drcs) (0 expected)"
set lt [unpu_run_logged [list check_legality] {}]
set leg0 [unpu_parse_legality $lt]
unpu_check_pass fill input_legality [expr {$leg0 ne "not parsed" && $leg0 == 0}] "check_legality on $BLK_ROUTED: $leg0 violations (0 expected)"
if {$UNPU_CHECK_FAILED > 0} { unpu_die "a precondition failed; nothing is inserted (see the CHECK lines above)" }

# ---- 3. area and wire length BEFORE the insertion (RESULT lines; the area gives the free sites) -------------------
# VERIFY which report gives the standard-cell area without fillers: report_utilization and report_qor are read, as in cts.tcl
set ru0 [unpu_report fill utilization_before "report_utilization"]
set rq0 [unpu_report fill qor_before "report_qor"]
set spec {area {(?i)(total\s+)?(std\s*)?cell\s*area} instances {(?i)(number\s+of\s+)?(instances|cells)} utilization {(?i)utili[sz]ation} wire_length {(?i)(total\s+)?wire\s*length}}
array set u0 [unpu_find_numbers "$ru0\n$rq0" $spec]
foreach k {area instances utilization wire_length} {
  if {$u0($k) eq ""} { unpu_warn "$k before the fill could not be read from report_utilization / report_qor (informational)"; set u0($k) unavailable }
  unpu_result fill ${k}_before $u0($k)
}

# ---- 4. insert the fillers (18.22: the exact form that worked) ------------------------------------------------
# acts on the current block; the scenario does not matter. VERIFY: create_stdcell_fillers takes the collection of cells
set ftext [unpu_run_logged [list create_stdcell_fillers -lib_cells [get_lib_cells $FILLER_PATTERN] -prefix $FILLER_PREFIX -rules $FILL_RULES] {CHF- FLW- Error}]
set counts [unpu_parse_fillers $ftext]
set ftotal [unpu_filler_total $counts]
foreach {cell n} $counts { unpu_result fill fillers_$cell $n }
unpu_result fill fillers_total $ftotal
unpu_check_pass fill fillers_inserted [expr {$ftotal > 0}] "$ftotal filler(s) inserted (more than 0 expected; parsed from the lines printed per cell: {$counts})"
array set fcnt $counts
foreach f $FILLER_CELLS {
  set n [expr {[info exists fcnt($f)] ? $fcnt($f) : 0}]
  unpu_check_pass fill fillers_cell_$f [expr {$n > 0}] "$n filler(s) of $f inserted (every one of {$FILLER_CELLS} must appear)"
}

# ---- 5. connect the fillers' power pins AT ONCE (18.22) ------------------------------------------------------
# without this the DRC engine reported ~17,766 false M1 shorts
set ctext [unpu_run_logged [list connect_pg_net -automatic] {}]
array set pgc [unpu_parse_connect_pg_change $ctext [list $PG_NET_POWER $PG_NET_GROUND]]
unpu_result fill pg_pins_changed $pgc(pins)
set want_pins [expr {2 * $ftotal}]
unpu_check_pass fill pg_pins_connected [expr {$pgc(pins) ne "not parsed" && $pgc(pins) == $want_pins}] "connect_pg_net created or changed $pgc(pins) power/ground pin(s); 2 x $ftotal fillers = $want_pins expected"
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  set prev $pgc(${n}_previous); set cur $pgc(${n}_current)
  unpu_result fill pg_${n}_previous $prev
  unpu_result fill pg_${n}_current $cur
  unpu_check_pass fill pg_${n}_count [expr {$prev ne "not parsed" && $cur ne "not parsed" && $cur == $prev + $ftotal}] "net $n: $prev pin(s) before (= the leaf-cell count) and $cur after; $prev + $ftotal fillers = [expr {$prev eq {not parsed} ? {unknown} : $prev + $ftotal}] expected"
}

# ---- 6. coverage: the filler sites must equal the free sites (a consistency check on the fill itself) ----------
# total sites = rows x sites per row (FP_ROWS, core side / SITE_WIDTH); used sites = standard-cell area / (SITE_WIDTH x ROW_HEIGHT)
set sites_per_row [expr {int(round($CORE_SIDE / $SITE_WIDTH))}]
set fs [unpu_free_sites $FP_ROWS $sites_per_row $u0(area) $SITE_WIDTH $ROW_HEIGHT]
set cov_covered [lindex [unpu_filler_coverage $counts $FILLER_SITES 0 $FILL_COVERAGE_TOL_SITES] 1]
unpu_result fill sites_covered_by_fillers $cov_covered
unpu_result fill sites_total "$FP_ROWS rows x $sites_per_row sites = [expr {$FP_ROWS * $sites_per_row}]"
if {$fs eq "not parsed"} {
  unpu_warn "the standard-cell area could not be read before the insertion ($u0(area)), so the free sites cannot be computed and the coverage is NOT checked. Arithmetic: $FP_ROWS rows x $sites_per_row sites = [expr {$FP_ROWS * $sites_per_row}] total sites; the fillers cover $cov_covered sites; free = total - area / ($SITE_WIDTH x $ROW_HEIGHT). Compare by hand."
} else {
  lassign $fs s_total s_used s_free
  unpu_result fill sites_used_by_cells $s_used
  unpu_result fill sites_free $s_free
  lassign [unpu_filler_coverage $counts $FILLER_SITES $s_free $FILL_COVERAGE_TOL_SITES] cov_ok cov_covered cov_free cov_diff cov_unknown
  unpu_result fill coverage_difference_sites $cov_diff
  unpu_check_pass fill coverage [expr {$cov_ok}] "fillers cover $cov_covered sites, free sites $cov_free ($s_total total - $s_used used by $u0(area) um2 / ($SITE_WIDTH x $ROW_HEIGHT)); difference $cov_diff (within $FILL_COVERAGE_TOL_SITES expected; cells without a site width: {$cov_unknown})"
}

# ---- 7. checks on the filled block ---------------------------------------------------------------------------
# 7a. check_routes (ICC2's view; the input-port nets are skipped by ICC2: Calibre decides)
set crt [unpu_report fill check_routes "check_routes"]
array set cr [unpu_parse_check_routes $crt]
unpu_check_pass fill open_nets [expr {$cr(open_nets) ne "not parsed" && $cr(open_nets) == 0}] "open nets after the fill: $cr(open_nets) (0 expected; 'not parsed' = read the log)"
unpu_check_pass fill drcs [expr {$cr(drcs) ne "not parsed" && $cr(drcs) == 0}] "DRCs after the fill: $cr(drcs) (0 expected)"
unpu_check_pass fill antenna_violations [expr {$cr(antenna) ne "not parsed" && $cr(antenna) == 0}] "ICC2 antenna violations: $cr(antenna) (0 expected; input-port nets are skipped by ICC2, Calibre decides)"
set skipped [unpu_zrt311_nets $crt]
unpu_result fill antenna_port_nets_skipped [llength $skipped]
if {[llength $skipped] > 0} {
  set f [file join $RPT_DIR fill_antenna_port_nets_skipped.txt]
  set fh [open $f w]; foreach n $skipped { puts $fh $n }; close $fh
  unpu_info "ICC2 skipped the antenna analysis of [llength $skipped] input-port net(s) (ZRT-311; list in $f): 'antenna 0' above is NOT the final word, Calibre decides"
}
# 7b. fillers with violations (18.22: -check_only true lists them in <block>_fillers_with_violation.rpt). VERIFY the output text.
proc fl_violations {} {
  set t [unpu_run_logged [list remove_stdcell_fillers_with_violation -check_only true] {}]
  return [unpu_parse_filler_violations $t]
}
set fv [fl_violations]
set eco_done 0
if {$fv ne "not parsed" && $fv > 0 && $FILL_ECO eq "1"} {
  # ONE round of route_eco (18.22 fixed its one real violation this way: 1 net moved), then the same check again. VERIFY: route_eco
  unpu_warn "$fv filler(s) with violations; UNPU_FILL_ECO=1: running route_eco once (18.22 moved one net this way)"
  set et [unpu_run_logged [list route_eco] {}]
  set eco_done 1
  foreach l [unpu_lines_matching $et {(?i)\mnets?\M}] { unpu_info "route_eco: [string trim $l]" }
  set fv_before $fv
  set fv [fl_violations]
  unpu_result fill fillers_with_violation_before_eco $fv_before
}
unpu_result fill fillers_with_violation $fv
unpu_check_pass fill fillers_with_violation [expr {$fv ne "not parsed" && $fv == 0}] "fillers with violations: $fv (0 expected; 'not parsed' = read the log; the list is in <block>_fillers_with_violation.rpt in the shell's working directory). 18.22: with the power pins connected one real violation remained (a feedth3 rail against a signal wire) and route_eco fixed it by moving one net; UNPU_FILL_ECO=1 does that once (route_eco ran: $eco_done)"
# 7c. legality and power connectivity
set lt [unpu_run_logged [list check_legality] {}]
set leg [unpu_parse_legality $lt]
unpu_check_pass fill legality [expr {$leg ne "not parsed" && $leg == 0}] "check_legality after the fill: $leg violations (0 expected)"
set pct [unpu_run_logged [list check_pg_connectivity] {}]
array set fl [unpu_parse_pg_connectivity $pct]
foreach {k what} {cells "floating standard cells" wires "floating wires" vias "floating vias" terminals "floating terminals"} {
  set v [expr {[info exists fl($k)] ? $fl($k) : "not parsed"}]
  unpu_check_pass fill pg_conn_$k [expr {$v ne "not parsed" && $v == 0}] "$what: $v (0 expected)"
}
# 7d. setup (in $SCEN_SETUP)
lassign [unpu_timing_summary fill $SCEN_SETUP max setup] ws sv sg spaths
unpu_result fill worst_setup_slack_ns $ws
unpu_check_pass fill setup_violations [expr {$sv ne "unavailable" && $sv == 0}] "$sv setup-violating endpoint(s) in $SCEN_SETUP after the fill (0 expected; 'unavailable' fails); worst slack $ws ns; by group {$sg}"
# 7e. hold (in $SCEN_HOLD): the decision of 2026-10-29 (18.22 option A)
lassign [unpu_timing_summary fill $SCEN_HOLD min hold] wh hv hg hpaths
unpu_result fill worst_hold_slack_ns $wh
unpu_result fill hold_violating_endpoints $hv
set worst [unpu_worst_endpoints $hpaths $HOLD_ENDPOINTS_LISTED]
set decision [unpu_fill_hold_decision $hv $wh $FILL_HOLD_TOLERANCE_NS $FILL_HOLD_MAX_ENDPOINTS]
if {$decision eq "pass"} {
  unpu_check_pass fill hold_violations 1 "0 hold-violating endpoints in $SCEN_HOLD after the fill at hold uncertainty $HOLD_UNCERT; worst slack $wh ns"
} elseif {$decision eq "accepted"} {
  unpu_warn "HOLD RESIDUAL ACCEPTED (decision of 2026-10-29, handoff 18.22 option A): $hv hold-violating endpoint(s) in $SCEN_HOLD after the fill, worst slack $wh ns, not worse than -$FILL_HOLD_TOLERANCE_NS ns, at most $FILL_HOLD_MAX_ENDPOINTS endpoints. The filler capacitance causes it; PrimeTime judges it with its own extraction of the filled layout, and that path is fixed there only if PrimeTime also reports it. Endpoints ([llength $worst]): [join $worst { ; }]"
  unpu_manifest_append fill [concat [list "hold_residual_accepted = 1" "hold_violating_endpoints = $hv" "hold_worst_slack_ns = $wh" "hold_tolerance_ns = $FILL_HOLD_TOLERANCE_NS" "hold_uncertainty_ns = $HOLD_UNCERT"] [unpu_hold_endpoint_lines $worst]]
  unpu_result fill hold_residual_accepted 1
} else {
  set why [expr {$hv eq "unavailable" ? "the number of violating endpoints could not be read" : "worst slack $wh ns is worse than -$FILL_HOLD_TOLERANCE_NS ns, or more than $FILL_HOLD_MAX_ENDPOINTS endpoints are violated, or the slack could not be read"}]
  unpu_check_pass fill hold_violations 0 "$hv hold-violating endpoint(s) in $SCEN_HOLD after the fill at hold uncertainty $HOLD_UNCERT: $why; by group {$hg}. Worst: [join $worst { ; }]"
}
# 7f. max transition / max capacitance
foreach {kind opt} {max_transition -max_transition max_capacitance -max_capacitance} {
  set cnt [unpu_constraint_count fill $kind $opt]
  unpu_check_pass fill $kind [expr {$cnt ne "unavailable" && $cnt == 0}] "$cnt $kind violation(s) after the fill (0 expected; 'unavailable' fails)"
}
# 7g. RESULT lines: area, utilisation, wire length after (the fillers add cell area; the wiring must not change)
set ru1 [unpu_report fill utilization_after "report_utilization"]
set rq1 [unpu_report fill qor_after "report_qor"]
array set u1 [unpu_find_numbers "$ru1\n$rq1" $spec]
foreach k {area instances utilization wire_length} {
  if {$u1($k) eq ""} { unpu_warn "$k after the fill could not be read from report_utilization / report_qor (informational)"; set u1($k) unavailable }
  unpu_result fill ${k}_after $u1($k)
}
if {$u0(wire_length) eq "unavailable" || $u1(wire_length) eq "unavailable"} {
  unpu_warn "the wire length could not be read before and after the fill from report_utilization / report_qor (VERIFY the report); 'wiring unchanged' rests on check_routes only"
} elseif {$u0(wire_length) != $u1(wire_length)} {
  unpu_warn "the wire length changed with the fill: $u0(wire_length) before, $u1(wire_length) after (the fill must not change the wiring; unless route_eco ran: $eco_done)"
}
if {$u0(area) ne "unavailable" && $u1(area) ne "unavailable"} {
  unpu_result fill area_added_by_fill [format %.2f [expr {[string map {, {}} $u1(area)] - [string map {, {}} $u0(area)]}]]
}

# ---- 8. verdict, then the final block ----------------------------------------------------------------------
unpu_checks_finish fill             ;# stops here if any check failed: $BLK_FINAL is not saved
unpu_checkpoint $BLK_FINAL
unpu_result fill block_saved_final $BLK_FINAL
unpu_result fill hold_decision $decision
unpu_info "done: block $BLK_FINAL saved in $lib_path. The final block is FILLED; do not run route_opt on it (it deletes every filler and does not put them back); the outputs come from this block."
exit 0
