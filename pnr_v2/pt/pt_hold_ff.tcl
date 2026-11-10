# ==============================================================================
# Script: pt_hold_ff.tcl   (task 074)  -- PrimeTime HOLD sign-off, fast corner (ff)
# Run   : cd <RUN_DIR>/pnr_icc2/pt ; pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
# Reads : library tsl18fs120_scl_ff, the netlist, the SPEF of corner_ff (decided from unpu_top_spef.spef_scenario at run time), unpu_top_pnr_ff.sdc.
# Does  : nothing but read and analyse; no constraint is added or changed. Ends with `exit` (0 = finished, 1 = stopped with a PT ERROR line).
# ==============================================================================
set PT_SCRIPT_DIR [file dirname [file normalize [info script]]]
source ${PT_SCRIPT_DIR}/pt_common.tcl

pt_main {
    set corner ff
    file mkdir $PT_RPT_DIR
    set spef [pt_choose_spef $corner]
    pt_banner hold $corner $PT_CORNER($corner,lib) $PT_CORNER($corner,db) $spef $PT_CORNER($corner,sdc) $PT_NETLIST
    pt_si_setup
    pt_link $corner
    pt_read_spef $corner $spef
    set sdcv [pt_read_sdc_and_check hold $corner]
    pt_check_opcond $corner
    foreach l [pt_limit_report [pt_limit_entries [dict get $sdcv maxtran] [dict get $sdcv maxcap]] $PT_EXPECT_MAX_TRANSITION $PT_EXPECT_MAX_CAP] { puts ">>> 074 $l" }
    pt_checks_and_clock hold $corner

    # ---- hold reports (-delay_type min) -----------------------------------------------------------------------------------------------
    set rpt ${PT_RPT_DIR}/pt_hold_${corner}
    redirect -tee -file ${rpt}_global_timing.rpt { catch {report_global_timing} }   ;# VERIFY report_global_timing exists in this release
    redirect -variable pt_viol_txt { report_constraint -all_violators -min_delay }   ;# VERIFY report_constraint -min_delay
    puts $pt_viol_txt
    set fp [open ${rpt}_violators.rpt w]; puts $fp $pt_viol_txt; close $fp
    set pv [pt_parse_violators $pt_viol_txt]
    puts ">>> 074 report_constraint text: [dict get $pv count] lines marked VIOLATED, worst [dict get $pv wns] (cross-check of the numbers below; VERIFY the wording)"
    redirect -tee -file ${rpt}_paths_worst20.rpt {
        if {[catch {report_timing -delay_type min -path_type full_clock_expanded -max_paths 20 -nworst 1} err]} { puts "report_timing (hold) failed: $err" }
    }
    redirect -tee -file ${rpt}_design_rules.rpt {
        if {[catch {report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width} err]} { puts "report_constraint (design rules) failed: $err" }   ;# VERIFY the three options together
    }

    # ---- every violated endpoint: endpoint, slack, startpoint and the clock arrival of both ends -------------------------------------------
    lassign [pt_violators min $PT_MAX_VIOLATED_DETAIL] wns tns num details
    foreach d $details {
        set ep [dict get $d endpoint]
        set sp [dict get $d startpoint]
        puts ">>> 074 HOLD violated endpoint $ep: slack [pt_fmt_ns [dict get $d slack]] ns, startpoint $sp"
        redirect -tee -file ${rpt}_violated_[string map {/ _ * _ " " _ [ _ ] _} $ep].rpt {
            # the full path shows the clock arrival times of the launching and the capturing flop (their difference is the skew)
            if {[catch {
                set o_sp [get_pins -quiet $sp]; if {[sizeof_collection $o_sp] == 0} { set o_sp [get_ports -quiet $sp] }
                set o_ep [get_pins -quiet $ep]; if {[sizeof_collection $o_ep] == 0} { set o_ep [get_ports -quiet $ep] }
                report_timing -delay_type min -from $o_sp -to $o_ep -path_type full_clock_expanded -nworst 1 -max_paths 1
            } err]} { puts "report_timing for the violated endpoint $ep failed: $err" }   ;# VERIFY the object lookup of the endpoint names
        }
    }
    if {[string is integer -strict $num] && $num > [llength $details]} { puts ">>> 074 only the first [llength $details] of $num violated endpoints are listed (PT_MAX_VIOLATED_DETAIL); the full list is in ${rpt}_violators.rpt" }
    if {[string is integer -strict $num] && [dict get $pv count] != $num} { puts ">>> 074 NOTE: the endpoint count of get_timing_paths ($num) differs from the VIOLATED lines of report_constraint ([dict get $pv count]); read both reports" }

    # ---- 078: EVERY violated endpoint (no limit of PT_MAX_VIOLATED_DETAIL) in a ';' separated file: endpoints, startpoints, kinds, slack, group, the cells of the data path and their delays -----
    set viol_err ""
    set PT_SUMMARY_EXTRA {}
    if {[catch {pt_write_violations min ${rpt}_violations.csv} vres]} {
        set viol_err "the violations file could not be written: $vres"
        puts ">>> 078 ERROR: $viol_err"
        lappend PT_SUMMARY_EXTRA "violations file: NOT WRITTEN ($vres)"
    } else {
        lassign $vres nfile vrows
        lassign [pt_viol_consistency $nfile $num] vok vmsg
        puts ">>> 078 $vmsg"
        lappend PT_SUMMARY_EXTRA "violations file: $nfile endpoints written to ${rpt}_violations.csv"
        if {!$vok} { set viol_err $vmsg; lappend PT_SUMMARY_EXTRA "VIOLATIONS FILE INCONSISTENT: $vmsg" }
    }

    set verdict [pt_print_summary hold $corner $wns $tns $num $PT_ICC2_HOLD_WNS]
    if {$viol_err ne ""} { error "PT ERROR: $viol_err" }   ;# 078: raised after the SUMMARY block so that the summary is not lost
    puts "Reports in $PT_RPT_DIR. Log: pt_hold_ff.log (the tee of this run)."
}
exit 0
