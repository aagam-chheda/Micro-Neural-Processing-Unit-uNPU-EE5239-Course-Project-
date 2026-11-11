# ==============================================================================
# Script: pt_eco_setup_probe.tcl   (task 079 part 1; rewritten for the SI-ON ECO round, task 098)  -- PROBE of PrimeTime's setup ECO at the slow corner (ss), SIZE_CELL ONLY
# Run   : cd <RUN_DIR>/pnr_icc2/pt_si ; setenv UNPU_PT_SI 1 ; pt_shell -f ../../pnr_v2/pt/pt_eco_setup_probe.tcl |& tee pt_eco_setup_probe.log      (UNPU_PT_TAG as the other scripts; without UNPU_PT_SI: SI off, folder pt)
# Why   : with SI ON PrimeTime reports 4 setup endpoints (paddr[3] -> prdata[20] -0.0364, [10], [22], [17]: the zero-margin read path, the in2out cone), with SI OFF none. The SI-on ECO round closes them with SIZE
#         changes only: a cell of the read path may be resized ONLY to a FASTER reference of the same function (a larger drive); an insertion on the cone is not made (the probe stops and reports, the user decides).
# Does  : pt_prepare_session setup ss (SI as selected), the measurement BEFORE (SI as selected and, with SI on, the SI-off view of the same session), fix_eco_timing -type setup -methods {size_cell} (with
#         -setup_margin PT_ECO_SETUP_MARGIN, then without it if the option is unknown), write_changes, one line per change (cell, old and new reference, the net, on the read path or not, area), the class of each
#         change, the measurement AFTER in both views, and the result line. The clock network, the earlybuf_*/antbuf_* buffers, the 9 PTECO_HOLD cells and the resized drivers of task 095 are dont_touch.
#         The in2out cone is NOT protected (the paths ARE the cone). The change files go to the reports folder of the session (pt_si for SI on); nothing else is written. exit 0 whatever the answer.
# Files : pt_eco_setup_changes{.tcl,_icc2.tcl,.txt}, pt_eco_setup_expected_count.txt, pt_eco_setup_pin_classes.txt (the last two ONLY when the probe closes the violators and no change is a violation: pt_eco_apply.tcl
#         with UNPU_ECO_KIND=setup requires them). Stale copies are deleted at the start.
# Every PrimeTime command and option is from knowledge of PrimeTime, not from a usage text: each is marked VERIFY.
# ==============================================================================
set PT_SCRIPT_DIR [file dirname [file normalize [info script]]]
source ${PT_SCRIPT_DIR}/pt_common.tcl

pt_main {
    pt_probe_si_guard pt_eco_setup_probe.tcl 1
    set corner ss
    set_app_var timing_save_pin_arrival_and_slack true   ;# VERIFY (PTE-077, as the other probes)
    set sdcv [pt_prepare_session setup $corner]
    set rpt ${PT_RPT_DIR}/pt_eco_setup_${corner}
    set probe_line ""
    foreach f {pt_eco_setup_expected_count.txt pt_eco_setup_pin_classes.txt} { file delete -force ${PT_RPT_DIR}/$f }   ;# a stale file of an earlier run must not let the apply run on this one
    puts ">>> 098 setup ECO probe: SI [expr {$PT_SI_ENABLE ? {ON} : {OFF}}], change files and reports in $PT_RPT_DIR, setup margin $PT_ECO_SETUP_MARGIN ns"

    lassign [pt_write_violations max ${rpt}_before_violations.csv] n_before rows_before
    set m0 [pt_measure_views BEFORE]
    foreach r $rows_before { puts ">>> 098   violator [dict get $r endpoint] (startpoint [dict get $r startpoint]) slack [dict get $r slack]" }

    set prot_clk ""; set prot_named ""
    if {[catch {
        if {$n_before == 0} { error "PROBE: there is no setup violator before the ECO in this view: nothing to fix" }
        foreach c {fix_eco_timing set_eco_options write_changes} { if {[llength [info commands $c]] == 0} { error "PROBE: $c does not exist in this pt_shell" } }
        foreach c {fix_eco_timing set_eco_options} { if {[catch {help -verbose $c} herr]} { if {[catch {help $c} herr2]} { puts ">>> 098 help $c failed: $herr2" } } }
        foreach f $PT_ECO_LICENSE_TRIES { if {[catch {get_license $f} lres]} { puts ">>> 098 get_license $f: FAILED: $lres" } else { puts ">>> 098 get_license $f: ok ($lres)" } }
        if {[catch {set_eco_options -log_file ${rpt}_eco.log} oerr]} { puts ">>> 098 set_eco_options failed (not fatal): $oerr" }

        # the cone: the read path. It is computed, NOT protected; the old reference of every cone cell is recorded (a change on a cone cell is judged by it)
        pt_load_eco_parser
        if {[catch {set cone [pt_in2out_cone]} cerr]} { error "CONE: $cerr" }
        pt_cone_print $cone ${rpt}
        set cone_cells [dict get $cone cells]
        set ref_before [dict create]
        foreach cn $cone_cells { set rf ""; catch {set rf [get_attribute [get_cells -exact $cn] ref_name]}; dict set ref_before $cn $rf }
        puts ">>> 098 in2out cone: [llength $cone_cells] cells, their references recorded before the ECO"
        # protection: the clock network, the buffers of earlier steps, the cells of earlier rounds
        if {[catch {set prot_clk [pt_clock_protect]} cperr]} { error "CLOCK: $cperr" }
        set clock_cells [dict get $prot_clk names]
        set keep {}
        foreach pat {earlybuf_* antbuf_* *PTECO_HOLD*} { foreach_in_collection kc [get_cells -quiet -hierarchical $pat] { lappend keep [get_object_name $kc] } }
        set drcf [file join [lindex [pt_tag_paths $PT_BASE $PT_TAG 0 exported] 1] pt_eco_drc_changes_icc2.tcl]
        if {[file exists $drcf]} {
            set fp [open $drcf r]; set dtxt [read $fp]; close $fp
            foreach c [dict get [eco079_parse $dtxt] cmds] { if {[dict get $c type] eq "size_cell"} { lappend keep [dict get $c full_inst] } else { lappend keep [dict get $c cell] } }
            puts ">>> 098 cells of the max-transition ECO of task 095 read from $drcf"
        } else { puts ">>> 098 no max-transition change file $drcf: the resized drivers of task 095 are not protected by name" }
        set prot_named [pt_protect_named "buffers and cells of earlier rounds" [lsort -unique $keep]]

        # the fix: size_cell only
        set proposed 0; set last_pf ""; set tried {}
        set forms [list [list "size_cell, -setup_margin $PT_ECO_SETUP_MARGIN" "fix_eco_timing -type setup -methods {size_cell} -setup_margin $PT_ECO_SETUP_MARGIN"] [list "size_cell, no margin option" "fix_eco_timing -type setup -methods {size_cell}"]]
        set rcx [catch {
            foreach f $forms {
                lassign $f desc text
                puts ">>> 098 trying ($desc): $text"
                set fx_txt ""; set ferr ""
                set rc [catch {redirect -variable fx_txt { eval $text }} ferr]
                puts $fx_txt
                if {$rc} {
                    lappend tried "$desc: $ferr"
                    puts ">>> 098 that form failed: $ferr"
                    if {[pt_eco_is_option_error $ferr]} continue
                    error "PROBE: fix_eco_timing failed: $ferr"
                }
                set last_pf [pt_eco_parse_fix_text $fx_txt]
                set nmsg [pt_eco_first_messages $last_pf 4]
                puts ">>> 098 form '$desc': commands proposed '[dict get $last_pf ncmd]', messages: [expr {[llength $nmsg] ? [join $nmsg { || }] : {none}}]"
                if {[pt_eco_fix_proposed $last_pf]} { set proposed 1; break }
                lappend tried "$desc: [join $nmsg { || }]"
            }
        } lemsg]
        pt_cone_unprotect $prot_clk; pt_cone_unprotect $prot_named
        if {$rcx} { error $lemsg }
        if {!$proposed} {
            set probe_line [pt_eco_result_line notclosed "fix_eco_timing -type setup -methods {size_cell} proposed no change for the $n_before violators ([join $tried { | }]). Options for the user: an insertion on the read path (cost: a buffer delay on the cone), a stronger early buffer on paddr[3] replacing the CONE-SKIPPED decision, or a margin approach"]
        } else {
            lassign [pt_eco_write_changes_all pt_eco_setup_changes] written n_empty
            if {[dict size $written] == 0} { error "PROBE: fix_eco_timing reported [dict get $last_pf ncmd] commands but write_changes wrote no file ($n_empty of 3 formats said 'No changes to write.')" }
            set chk_file ""
            foreach f {icc2tcl icctcl} { if {$chk_file eq "" && [dict exists $written $f]} { set chk_file [dict get $written $f] } }
            if {$chk_file eq ""} { error "CHECK: no Tcl-format change file was written, the proposed changes cannot be checked" }
            set fp [open $chk_file r]; set chk_txt [read $fp]; close $fp
            set chk [eco079_parse $chk_txt]
            if {[llength [dict get $chk errors]] > 0} { error "CHECK: [llength [dict get $chk errors]] line(s) of $chk_file are not understood by the change-file parser: [join [lrange [dict get $chk errors] 0 2] { | }]" }
            set cmds [dict get $chk cmds]
            puts ">>> 098 PrimeTime proposed [llength $cmds] changes (area change [dict get $last_pf area] um^2, change file $chk_file)"
            # one line and one class per change
            set ins_list {}; set rows {}; set hits {}
            set cls_count [dict create cone_faster 0 resize_other 0 cone_slower 0 clock_net 0 unknown 0]
            set lib $PT_CORNER($corner,lib)
            foreach c $cmds {
                set idx [dict get $c idx]
                if {[dict get $c type] eq "insert_buffer"} {
                    lappend ins_list $c
                    puts ">>> 098 change $idx: INSERTION [dict get $c ref] on [dict get $c full_pin] (the setup kind is size_cell only: the probe stops here)"
                    continue
                }
                set inst [dict get $c full_inst]; set new [dict get $c ref]
                set oldref [expr {[dict exists $ref_before $inst] ? [dict get $ref_before $inst] : ""}]
                set in_cone [expr {[dict exists $ref_before $inst] ? 1 : 0}]
                set is_clock [expr {[lsearch -exact $clock_cells $inst] >= 0 ? 1 : 0}]
                if {$oldref eq "" && $in_cone} { set in_cone "" }   ;# the reference could not be read before: unknown
                set cls [pt_setup_size_class $in_cone $is_clock $oldref $new]
                dict incr cls_count $cls
                set net ""; catch { set net [get_object_name [get_nets -of_objects [lindex [get_object_name [get_pins -of_objects [get_cells -exact $inst] -filter "direction == out"]] 0]]] }
                set a0 ""; set a1 ""
                catch { set a1 [get_attribute [get_lib_cells ${lib}/$new] area] }
                if {$oldref ne ""} { catch { set a0 [get_attribute [get_lib_cells ${lib}/$oldref] area] } }
                puts ">>> 098 change $idx: cell $inst, [expr {$oldref eq {} ? {old reference not recorded (cell not on the read path)} : $oldref}] -> $new ([pt_ref_speed_text $oldref $new]); output net [expr {$net eq {} ? {?} : $net}]; on the read path (in2out cone): [expr {$in_cone eq {} ? {unknown} : ($in_cone ? {YES} : {no})}]; area [expr {$a0 eq {} ? {?} : $a0}] -> [expr {$a1 eq {} ? {?} : $a1}] um^2; class: [pt_eco_class_text093 $cls]"
                lappend rows [pt_eco_class_row $idx $inst $new $cls $net {}]
                if {[pt_eco_class_violation $cls]} { lappend hits "change $idx: $inst [pt_eco_class_text093 $cls]" }
            }
            # AFTER, in PrimeTime's memory, in both views
            update_timing -full
            lassign [pt_write_violations max ${rpt}_after_violations.csv] n_after rows_after
            set m1 [pt_measure_views AFTER]
            foreach r $rows_after { puts ">>> 098   remaining violator [dict get $r endpoint] (startpoint [dict get $r startpoint]) slack [dict get $r slack]" }
            if {[llength $ins_list] > 0} {
                set probe_line [pt_eco_result_line needsdecision "PrimeTime proposes [llength $ins_list] insertion(s) ([join [lmap c $ins_list {string cat [dict get $c ref] { on } [dict get $c full_pin]}] {, }]) next to [expr {[llength $cmds] - [llength $ins_list]}] size_cell change(s); size-only was asked. Options for the user: the insertion with its buffer delay on the cone, a stronger early buffer on paddr[3] replacing the CONE-SKIPPED decision, or a margin approach"]
            } elseif {[llength $hits] > 0} {
                set probe_line [pt_eco_result_line touches "[llength $hits] of [llength $cmds] size changes are violations: [join [lrange $hits 0 2] { | }]"]
            } elseif {$n_after > 0} {
                set probe_line [pt_eco_result_line notclosed "after the [llength $cmds] size changes $n_after violating endpoint(s) remain in this view (before: $n_before). Options for the user: an insertion on the read path (cost: a buffer delay on the cone), a stronger early buffer on paddr[3] replacing the CONE-SKIPPED decision, or a margin approach. The change file is $chk_file, no count or class file is written"]
            } else {
                # closed in this view, no violation class: the count file and the class file for the apply
                lassign [pt_eco_change_number $last_pf [llength $cmds]] nchg nsrc nnote
                set fp [open ${PT_RPT_DIR}/pt_eco_setup_pin_classes.txt w]
                puts $fp "# written by pt_eco_setup_probe.tcl (task 098): one line per size_cell change: <idx> <instance> <new reference> <class> net=<output net> drivers=?; pt_eco_apply.tcl (UNPU_ECO_KIND setup) prints these lines and refuses a violation class"
                foreach l $rows { puts $fp $l }
                close $fp
                if {[string is integer -strict $nchg]} {
                    set fp [open ${PT_RPT_DIR}/pt_eco_setup_expected_count.txt w]
                    puts -nonewline $fp [pt_eco_expected_text $nchg $nsrc [expr {[dict exists $written icc2tcl] ? [dict get $written icc2tcl] : $chk_file}] setup]
                    close $fp
                    puts ">>> 098 expected command count $nchg and the class file written to $PT_RPT_DIR"
                } else { puts ">>> 098 WARNING: the number of proposed commands is unreadable ('$nchg'): NO count file is written, the apply will stop" }
                set offtxt [expr {[dict get $m1 off] eq "" ? "SI-off view NOT measured ([dict get $m1 off_why])" : "SI-off view: [pt_measure_text [dict get $m1 off]]"}]
                set probe_line [pt_eco_result_line 1 "$nchg size_cell changes proposed, change file [expr {[dict exists $written icctcl] ? [dict get $written icctcl] : $chk_file}] (cone cells only to faster references, nothing on the clock network); violating endpoints $n_before -> $n_after in this view; $offtxt"]
            }
        }
    } perr]} {
        foreach pr [list $prot_clk $prot_named] { if {$pr ne ""} { catch {pt_cone_unprotect $pr} } }
        if {[regsub {^CONE: } $perr {} perr]} { set probe_line [pt_eco_result_line cone $perr]
        } elseif {[regsub {^CLOCK: } $perr {} perr]} { set probe_line [pt_eco_result_line clock $perr]
        } elseif {[regsub {^CHECK: } $perr {} perr]} { set probe_line [pt_eco_result_line unchecked $perr]
        } else { regsub {^PROBE: } $perr {} perr; set probe_line [pt_eco_result_line 0 $perr] }
    }
    puts "\n=============================================================================="
    puts " SETUP ECO PROBE (size_cell only, corner $corner, SI [expr {$PT_SI_ENABLE ? {ON} : {OFF}}])"
    puts "   $probe_line"
    foreach cav [pt_summary_caveat [expr {[info exists PT_ANNOTATION_UNCHECKED] && $PT_ANNOTATION_UNCHECKED}]] { puts "   CAVEAT: $cav" }
    puts "=============================================================================="
}
exit 0
