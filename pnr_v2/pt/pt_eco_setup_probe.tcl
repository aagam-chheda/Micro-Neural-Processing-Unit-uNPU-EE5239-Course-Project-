# ==============================================================================
# Script: pt_eco_setup_probe.tcl   (task 079, part 1)  -- PROBE of PrimeTime's setup ECO (size_cell) at the slow corner (ss)
# Run   : cd <RUN_DIR>/pnr_icc2/pt ; pt_shell -f ../../pnr_v2/pt/pt_eco_setup_probe.tcl |& tee pt_eco_setup_probe.log
# Does  : the preparation of pt_setup_ss.tcl (pt_prepare_session setup ss), the same help / licence printing as pt_eco_probe.tcl, then
#         fix_eco_timing -type setup -methods {size_cell}  for ALL setup violators (one is expected: dma_addr[31], -0.2423 ns; last stage HFSINV_13_284 (inv0d4) into the 1.0 pF load).
#         Writes pt_eco_setup_changes.tcl / pt_eco_setup_changes_icc2.tcl / pt_eco_setup_changes.txt, prints the AFTER setup status in PrimeTime's memory and ends with the same
#         three-way PROBE RESULT line as the hold probe. In-memory only: no design file, SDC, SPEF or netlist is written. exit 0 whatever the answer.
# Reuses the procs of pt_common.tcl (log parser, outcome classes, write_changes loop, violation collection); nothing is copied.
# Every PrimeTime ECO command and option is from knowledge, not from a usage text: each is marked VERIFY. The `help` text printed first shows the real form of -methods for setup.
# ==============================================================================
set PT_SCRIPT_DIR [file dirname [file normalize [info script]]]
source ${PT_SCRIPT_DIR}/pt_common.tcl

pt_main {
    pt_probe_si_guard pt_eco_setup_probe.tcl   ;# 095
    set corner ss
    set_app_var timing_save_pin_arrival_and_slack true   ;# VERIFY (PTE-077, as the hold probe)
    set sdcv [pt_prepare_session setup $corner]
    set rpt ${PT_RPT_DIR}/pt_eco_setup_${corner}
    set probe_line ""

    lassign [pt_write_violations max ${rpt}_before_violations.csv] n_before rows_before
    set wns_before ""
    catch {set wns_before [get_attribute [get_timing_paths -delay_type max -max_paths 1] slack]}
    puts ">>> 079 BEFORE the setup ECO: $n_before setup-violating endpoints, WNS [pt_fmt_ns $wns_before] ns"
    foreach r $rows_before { puts ">>> 079   violator [dict get $r endpoint] (startpoint [dict get $r startpoint]) slack [dict get $r slack]" }

    if {[catch {
        foreach c {fix_eco_timing set_eco_options} {
            if {[catch {help -verbose $c} herr]} { if {[catch {help $c} herr2]} { puts ">>> 079 help $c failed: $herr2" } }   ;# VERIFY help -verbose <command>
        }
        if {[llength [info commands fix_eco_timing]] == 0} { error "PROBE: fix_eco_timing does not exist in this pt_shell" }
        if {[llength [info commands write_changes]] == 0} { error "PROBE: write_changes does not exist in this pt_shell" }
        if {[catch {redirect -variable pt_lic_txt { list_licenses }} lerr]} { puts ">>> 079 list_licenses failed: $lerr"; set pt_lic_txt "" }   ;# VERIFY list_licenses
        puts ">>> 079 list_licenses lines that mention ECO: [expr {[llength [pt_eco_license_lines $pt_lic_txt]] ? [pt_eco_license_lines $pt_lic_txt] : {none (or list_licenses unavailable)}}]"
        foreach f $PT_ECO_LICENSE_TRIES {
            if {[catch {get_license $f} lres]} { puts ">>> 079 get_license $f: FAILED: $lres" } else { puts ">>> 079 get_license $f: ok ($lres)" }   ;# VERIFY get_license <feature>
        }
        if {$n_before == 0} { error "PROBE: there is no setup violator before the ECO: nothing to fix" }
        # 080: the in2out cone is COMPUTED (information) but NOT protected: a resize of a cone cell is a speed-up and is fine. The proposed changes that touch it are only printed.
        pt_load_eco_parser
        set cone ""
        if {[catch {set cone [pt_in2out_cone]} cerr]} { puts ">>> 080 the in2out cone could not be computed ($cerr): the information below is skipped" } else {
            pt_cone_print $cone ${rpt}
            set touching [pt_cone_touching $rows_before [dict get $cone cells]]
            puts ">>> 080 setup violators whose worst path touches the cone: [llength $touching] of $n_before"
        }
        puts ">>> 079 the ECO is LOGICAL only (no physical data)"
        if {[catch {set_eco_options -log_file ${rpt}_eco.log} oerr]} { puts ">>> 079 set_eco_options failed (not fatal): $oerr" }   ;# VERIFY set_eco_options -log_file

        # the form: -type setup -methods {size_cell}, all setup violators (VERIFY: the help text above shows whether size_cell needs -cell_type or a list)
        set text "fix_eco_timing -type setup -methods {size_cell}"
        puts ">>> 079 trying: $text"
        set fx_txt ""
        if {[catch {redirect -variable fx_txt { eval $text }} ferr]} { puts $fx_txt; error "PROBE: fix_eco_timing failed: $ferr" }
        puts $fx_txt
        set pf [pt_eco_parse_fix_text $fx_txt]
        set nmsg [pt_eco_first_messages $pf 4]
        puts ">>> 079 commands proposed '[dict get $pf ncmd]' (per verb in the log: [dict get $pf commands]), area change [dict get $pf area] um^2, messages: [expr {[llength $nmsg] ? [join $nmsg { || }] : {none}}]"
        if {![pt_eco_fix_proposed $pf]} {
            set probe_line [pt_eco_result_line nochanges "fix_eco_timing -type setup -methods {size_cell} ran but proposed no change. [join $nmsg { || }]"]
        } else {
            lassign [pt_eco_write_changes_all pt_eco_setup_changes] written n_empty
            if {[dict size $written] == 0} {
                set probe_line [pt_eco_result_line nochanges "fix_eco_timing reported [dict get $pf ncmd] commands but write_changes wrote no file ($n_empty of 3 formats said 'No changes to write.')"]
            } else {
                set countfile [expr {[dict exists $written text] ? [dict get $written text] : [lindex [dict values $written] 0]}]
                set fp [open $countfile r]; set ctext [read $fp]; close $fp
                set cc [pt_eco_count_changes $ctext {}]
                puts ">>> 079 first 30 lines of $countfile:"
                foreach l [lrange [split $ctext "\n"] 0 29] { puts "      $l" }
                update_timing -full
                lassign [pt_write_violations max ${rpt}_after_violations.csv] n_after rows_after
                set wns_after ""
                catch {set wns_after [get_attribute [get_timing_paths -delay_type max -max_paths 1] slack]}
                puts ">>> 079 AFTER the setup ECO (in PrimeTime's memory): $n_after setup-violating endpoints, WNS [pt_fmt_ns $wns_after] ns (before: $n_before, WNS [pt_fmt_ns $wns_before] ns)"
                lassign [pt_eco_change_number $pf [dict get $cc n]] nchg nsrc nnote
                puts ">>> 079 changes proposed: $nchg (from: $nsrc)[expr {$nnote ne {} ? "; NOTE: $nnote" : {}}]"
                # 080: which proposed changes touch the cone (information; a resize of a cone cell is fine, an insertion there would slow the read path)
                if {$cone ne ""} {
                    set chk_file ""
                    foreach f {icc2tcl icctcl} { if {$chk_file eq "" && [dict exists $written $f]} { set chk_file [dict get $written $f] } }
                    if {$chk_file eq ""} { puts ">>> 080 no Tcl-format change file: the cone check is skipped" } else {
                        set fp [open $chk_file r]; set chk_txt [read $fp]; close $fp
                        set chk [eco079_parse $chk_txt]
                        foreach e [dict get $chk errors] { puts ">>> 080 change file line not understood (cone check incomplete): $e" }
                        set hits [pt_cone_hits [dict get $chk cmds] [dict get $cone cells] [dict get $cone ports]]
                        puts ">>> 080 setup change file $chk_file: [llength [dict get $chk cmds]] changes parsed, [llength $hits] touch the in2out cone (information only for the setup ECO)"
                        foreach h $hits { puts ">>> 080   change [dict get $h idx] (line [dict get $h line]): [dict get $h what] [dict get $h name]" }
                    }
                }
                set probe_line [pt_eco_result_line 1 "$nchg changes proposed, change file [expr {[dict exists $written icctcl] ? [dict get $written icctcl] : $countfile}]"]
            }
        }
    } perr]} {
        regsub {^PROBE: } $perr {} perr
        set probe_line [pt_eco_result_line 0 $perr]
    }
    puts "\n=============================================================================="
    puts " SETUP ECO PROBE (corner $corner)"
    puts "   $probe_line"
    foreach cav [pt_summary_caveat [expr {[info exists PT_ANNOTATION_UNCHECKED] && $PT_ANNOTATION_UNCHECKED}]] { puts "   CAVEAT: $cav" }
    puts "=============================================================================="
}
exit 0
