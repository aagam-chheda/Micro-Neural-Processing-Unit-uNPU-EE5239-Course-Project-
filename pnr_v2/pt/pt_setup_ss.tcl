# ==============================================================================
# Script: pt_setup_ss.tcl   (task 074)  -- PrimeTime SETUP sign-off, slow corner (ss)
# Run   : cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt ; pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
# Reads : library tsl18fs120_scl_ss, the netlist, the SPEF of corner_ss (decided from unpu_top_spef.spef_scenario at run time), unpu_top_pnr_ss.sdc.
# Does  : nothing but read and analyse; no constraint is added or changed. Ends with `exit` (0 = finished, 1 = stopped with a PT ERROR line).
# ==============================================================================
set PT_SCRIPT_DIR [file dirname [file normalize [info script]]]
source ${PT_SCRIPT_DIR}/pt_common.tcl

pt_main {
    set corner ss
    file mkdir $PT_RPT_DIR
    set spef [pt_choose_spef $corner]
    pt_banner setup $corner $PT_CORNER($corner,lib) $PT_CORNER($corner,db) $spef $PT_CORNER($corner,sdc) $PT_NETLIST
    pt_si_setup
    pt_link $corner
    pt_read_spef $corner $spef
    set sdcv [pt_read_sdc_and_check setup $corner]
    pt_check_opcond $corner
    foreach l [pt_limit_report [pt_limit_entries [dict get $sdcv maxtran] [dict get $sdcv maxcap]] $PT_EXPECT_MAX_TRANSITION $PT_EXPECT_MAX_CAP] { puts ">>> 074 $l" }
    pt_checks_and_clock setup $corner

    # ---- setup reports (-delay_type max) -----------------------------------------------------------------------------------------------
    set rpt ${PT_RPT_DIR}/pt_setup_${corner}
    redirect -tee -file ${rpt}_global_timing.rpt { catch {report_global_timing} }   ;# VERIFY report_global_timing exists in this release
    redirect -variable pt_viol_txt { report_constraint -all_violators -max_delay }   ;# VERIFY report_constraint -max_delay
    puts $pt_viol_txt
    set fp [open ${rpt}_violators.rpt w]; puts $fp $pt_viol_txt; close $fp
    set pv [pt_parse_violators $pt_viol_txt]
    puts ">>> 074 report_constraint text: [dict get $pv count] lines marked VIOLATED, worst [dict get $pv wns] (cross-check of the numbers below; VERIFY the wording if it prints 0 while the summary shows violations)"
    # worst 10 paths per path group, full clock expansion
    set groups {}
    catch {foreach_in_collection g [get_path_groups *] { lappend groups [get_object_name $g] }}   ;# VERIFY get_path_groups
    puts ">>> 074 path groups: $groups"
    foreach g $groups {
        redirect -tee -file ${rpt}_paths_group_[string map {/ _ * _ " " _} $g].rpt {
            if {[catch {report_timing -delay_type max -path_type full_clock_expanded -max_paths 10 -nworst 1 -group [list $g]} err]} { puts "report_timing -group $g failed: $err" }   ;# VERIFY -group
        }
    }
    # the in2out paths in particular: paddr -> prdata (the combinational APB read mux)
    redirect -tee -file ${rpt}_paths_in2out_paddr_prdata.rpt {
        if {[catch {report_timing -from [get_ports paddr*] -to [get_ports prdata*] -delay_type max -path_type full_clock_expanded -max_paths 10 -nworst 1} err]} { puts "report_timing paddr -> prdata failed: $err" }
    }
    # design rules
    redirect -tee -file ${rpt}_design_rules.rpt {
        if {[catch {report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width} err]} { puts "report_constraint (design rules) failed: $err" }   ;# VERIFY the three options together
    }

    # ---- summary -----------------------------------------------------------------------------------------------------------------------
    lassign [pt_violators max $PT_MAX_VIOLATED_DETAIL] wns tns num details
    foreach d $details { puts ">>> 074 SETUP violated endpoint [dict get $d endpoint]: slack [pt_fmt_ns [dict get $d slack]] ns, startpoint [dict get $d startpoint]" }
    if {[string is integer -strict $num] && [dict get $pv count] != $num} { puts ">>> 074 NOTE: the endpoint count of get_timing_paths ($num) differs from the VIOLATED lines of report_constraint ([dict get $pv count]); read both reports" }
    # ---- 078: EVERY violated endpoint (no limit of PT_MAX_VIOLATED_DETAIL) in a ';' separated file: endpoints, startpoints, kinds, slack, group, the cells of the data path and their delays -----
    set viol_err ""
    set PT_SUMMARY_EXTRA {}
    if {[catch {pt_write_violations max ${rpt}_violations.csv} vres]} {
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

    set verdict [pt_print_summary setup $corner $wns $tns $num $PT_ICC2_SETUP_WNS]
    if {$viol_err ne ""} { error "PT ERROR: $viol_err" }   ;# 078: raised after the SUMMARY block so that the summary is not lost
    puts "Reports in $PT_RPT_DIR. Log: pt_setup_ss.log (the tee of this run)."
}
exit 0
