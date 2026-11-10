# ==============================================================================
# Script: pt_eco_drc_probe.tcl   (task 095)  -- PROBE of PrimeTime's max-transition ECO for the DATA limit (3.0 ns), slow corner (ss)
# Run   : cd <RUN_DIR>/pnr_icc2/pt ; pt_shell -f ../../pnr_v2/pt/pt_eco_drc_probe.tcl |& tee pt_eco_drc_probe.log        (UNPU_PT_TAG as the other scripts)
# Why   : the final ss design-rule report of run 3 had 86 max_transition violators of the DATA limit (set_max_transition 3 [current_design], legacy SDC): actual 3.00 to 3.05 ns, ports dma_wdata[*] and load pins of
#         u_actbuf / u_seq cells (high-fanout nets). The 424 clock-path entries (limit 0.40 ns) are NOT part of this ECO.
# Does  : pt_prepare_session setup ss; the design-rule report BEFORE (the data-limit entries are selected: required value = the design-wide limit read from the SDC); the facts of each entry (net, driver cell, load pins)
#         grouped by NET (pt_eco_drc_nets.csv); then fix_eco_drc -type max_transition (size_cell, insert_buffer) with the in2out cone AND the clock network dont_touch; write_changes; the AFTER design-rule report in
#         PrimeTime's memory (remaining data-limit violators printed); the proposals are classified at pin level (the rule of task 093) and a change on the clock network is a violation too.
#         Nothing is written except reports and change files in the reports folder. exit 0 whatever the answer; a failed probe is an answer.
# Files : pt_eco_drc_changes{.tcl,_icc2.tcl,.txt}, pt_eco_drc_expected_count.txt, pt_eco_drc_pin_classes.txt, pt_eco_drc_nets.csv, pt_eco_drc_ss_after_violations... (the apply script reads the _icc2.tcl, the count file and the class file).
# Rule  : a resize of an in2out-cone cell is NOT allowed in this probe (cone cells and the nets that carry an input-to-output path are dont_touch, as in tasks 092/093): this is stricter than "allowed if it is a speed-up".
#         Any remaining violator that sits on such a net is printed as remaining. The ICC2 apply gate (in2out WNS and whole-design setup WNS not worse than 0.005 ns) is the proof for everything that is applied.
# Every PrimeTime command and option below is from knowledge of PrimeTime, not from a usage text: each is marked VERIFY (the `help fix_eco_drc` text is printed first).
# ==============================================================================
set PT_SCRIPT_DIR [file dirname [file normalize [info script]]]
source ${PT_SCRIPT_DIR}/pt_common.tcl

pt_main {
    pt_probe_si_guard pt_eco_drc_probe.tcl
    set corner ss
    set_app_var timing_save_pin_arrival_and_slack true   ;# VERIFY (PTE-077, as the other probes)
    set sdcv [pt_prepare_session setup $corner]
    set rpt ${PT_RPT_DIR}/pt_eco_drc_${corner}
    set probe_line ""

    # ---- BEFORE: the design rules and the data-limit entries --------------------------------------------------------------------------------------------
    set dr0 [pt_design_rules_run eco_drc_before $corner $sdcv]
    set clk [dict get $dr0 clk]; set dw [dict get $dr0 dw]
    if {![dict get [dict get $dr0 sum] ok]} { error "PT ERROR: the design-rule report could not be read; the data-limit violators are unknown (see [dict get $dr0 report])" }
    set sel [pt_drc_select [dict get $dr0 parsed] $clk $dw]
    puts ">>> 095 BEFORE: [llength $sel] max_transition entries of the DATA limit ([join $dw {, }] ns) of [pt_dr_count [dict get $dr0 sum] max_transition] max_transition entries in total (the others belong to the clock-path limit [join $clk {, }] ns and are not part of this ECO)"
    set wns0 ""
    catch {set wns0 [get_attribute [get_timing_paths -delay_type max -max_paths 1] slack]}
    set in2out0 ""
    catch {set in2out0 [get_attribute [get_timing_paths -delay_type max -from [get_ports paddr*] -to [get_ports prdata*] -max_paths 1] slack]}
    puts ">>> 095 BEFORE: setup WNS [pt_fmt_ns $wns0] ns (ss), in2out (paddr -> prdata) worst slack [pt_fmt_ns $in2out0] ns"

    # the facts per entry and the nets
    set facts [dict create]
    foreach e $sel {
        set nm [dict get $e name]
        if {[dict exists $facts $nm]} continue
        dict set facts $nm [pt_drc_net_facts $nm]
    }
    set nerr 0
    dict for {nm f} $facts { if {[dict get $f err] ne ""} { incr nerr; puts ">>> 095 WARNING: facts of $nm: [dict get $f err]" } }
    set groups [pt_drc_group_by_net $sel $facts]
    puts ">>> 095 the [llength $sel] entries sit on [llength $groups] NETS ($nerr entries with unreadable facts):"
    set fp [open ${rpt}_nets.csv w]
    puts $fp [pt_drc_nets_header]
    foreach g $groups { puts $fp [pt_drc_nets_row $g]; puts ">>> 095   [pt_drc_why $g]" }
    close $fp
    puts ">>> 095 net table written to ${rpt}_nets.csv"

    # ---- everything below is the probe: any error is the ANSWER ------------------------------------------------------------------------------------------
    set prot_cone ""; set prot_clk ""
    if {[catch {
        if {[llength $sel] == 0} { error "PROBE: there is no max_transition violator of the data limit before the ECO: nothing to fix" }
        puts ">>> 095 ECO commands known to this pt_shell (help output):"
        foreach c {fix_eco_drc set_eco_options} { if {[catch {help -verbose $c} herr]} { if {[catch {help $c} herr2]} { puts ">>> 095 help $c failed: $herr2" } } }   ;# VERIFY help -verbose <command>
        foreach c {fix_eco_drc write_changes set_eco_options} { if {[llength [info commands $c]] == 0} { error "PROBE: $c does not exist in this pt_shell" } }
        if {[catch {redirect -variable pt_lic_txt { list_licenses }} lerr]} { set pt_lic_txt "" }
        puts ">>> 095 list_licenses lines that mention ECO: [expr {[llength [pt_eco_license_lines $pt_lic_txt]] ? [pt_eco_license_lines $pt_lic_txt] : {none (or list_licenses unavailable)}}]"
        foreach f $PT_ECO_LICENSE_TRIES { if {[catch {get_license $f} lres]} { puts ">>> 095 get_license $f: FAILED: $lres" } else { puts ">>> 095 get_license $f: ok ($lres)" } }

        # buffer candidates: plain buffers of the library (no delay cells)
        set lib $PT_CORNER($corner,lib)
        set cands [pt_eco_lib_buffers $lib $PT_ECO_DRC_LIB_PATTERNS]
        foreach c $cands { lassign [pt_eco_buffer_class $c] cls basis; puts ">>> 095   candidate [dict get $c name]: buffer $cls ($basis), area [dict get $c area]" }
        lassign [pt_eco_choose_buffers $cands $PT_ECO_MAX_BUFFERS * {}] blist bnote
        puts ">>> 095 buffer list ([llength $blist] cells): $blist"
        puts ">>> 095   $bnote"
        if {[llength $blist] == 0} { error "PROBE: no buffer cell among the candidates ($bnote)" }
        set libblist {}
        foreach b $blist { lappend libblist ${lib}/$b }
        if {[catch {set_eco_options -log_file ${rpt}_eco.log} oerr]} { puts ">>> 095 set_eco_options failed (not fatal): $oerr" }

        # protection: the in2out cone (cells and the nets that carry an input-to-output path; the nets a flop drives into the cone are released, task 092/093) and the clock network
        pt_load_eco_parser
        if {[catch {set cone [pt_in2out_cone]} cerr]} { error "CONE: $cerr" }
        pt_cone_print $cone ${rpt}
        if {[catch {set cone [pt_cone_nets_reg2out $cone]} nerr2]} { error "CONE: $nerr2" }
        if {[catch {set prot_cone [pt_cone_protect $cone]} perr2]} { error "CONE: $perr2" }
        if {[catch {set prot_clk [pt_clock_protect]} cperr]} { error "CLOCK: $cperr" }
        set clock_cells [dict get $prot_clk names]

        # the fix. Forms in order of preference; an option error tries the next, anything else stops. VERIFY every option against the help text above.
        set forms [list \
            [list "size_cell + insert_buffer, -buffer_list a collection of library cells" {fix_eco_drc -type max_transition -methods {size_cell insert_buffer} -buffer_list $bl} collection] \
            [list "size_cell + insert_buffer, -buffer_list bare names" {fix_eco_drc -type max_transition -methods {size_cell insert_buffer} -buffer_list $bl} bare] \
            [list "size_cell + insert_buffer, no buffer list" {fix_eco_drc -type max_transition -methods {size_cell insert_buffer}} none] \
            [list "-type max_transition only" {fix_eco_drc -type max_transition} none]]
        set proposed 0; set last_pf ""; set tried {}
        set rcx [catch {
            foreach f $forms {
                lassign $f desc text bl_kind
                if {$bl_kind eq "collection"} { set bl [get_lib_cells $libblist] } elseif {$bl_kind eq "bare"} { set bl $blist }
                puts ">>> 095 trying ($desc): $text"
                set fx_txt ""; set ferr ""
                set rc [catch {redirect -variable fx_txt { eval $text }} ferr]
                puts $fx_txt
                if {$rc} {
                    lappend tried "$desc: $ferr"
                    puts ">>> 095 that form failed: $ferr"
                    if {[pt_eco_is_option_error $ferr]} continue
                    error "PROBE: fix_eco_drc failed: $ferr"
                }
                set last_pf [pt_eco_parse_fix_text $fx_txt]
                set nmsg [pt_eco_first_messages $last_pf 4]
                puts ">>> 095 form '$desc': commands proposed '[dict get $last_pf ncmd]', messages: [expr {[llength $nmsg] ? [join $nmsg { || }] : {none}}]"
                if {[pt_eco_fix_proposed $last_pf]} { set proposed 1; break }
                lappend tried "$desc: [join $nmsg { || }]"
            }
        } lemsg]
        pt_cone_unprotect $prot_clk
        pt_cone_unprotect $prot_cone
        if {$rcx} { error $lemsg }
        if {!$proposed} {
            set probe_line [pt_eco_result_line nochanges "[expr {$last_pf eq {} ? {fix_eco_drc was not accepted in any form} : {fix_eco_drc ran}}] but proposed no change. [join $tried { | }]"]
        } else {
            lassign [pt_eco_write_changes_all pt_eco_drc_changes] written n_empty
            if {[dict size $written] == 0} {
                set probe_line [pt_eco_result_line nochanges "fix_eco_drc reported [dict get $last_pf ncmd] commands but write_changes wrote no file ($n_empty of 3 formats said 'No changes to write.')"]
            } else {
                set countfile [expr {[dict exists $written text] ? [dict get $written text] : [lindex [dict values $written] 0]}]
                set fp [open $countfile r]; set ctext [read $fp]; close $fp
                set known {}
                foreach c $cands { lappend known [dict get $c name] }
                set cc [pt_eco_count_changes $ctext $known]
                puts ">>> 095 first 30 lines of $countfile:"
                foreach l [lrange [split $ctext "\n"] 0 29] { puts "      $l" }
                puts ">>> 095 changes proposed: [dict get $cc n]; per command: [dict get $cc verbs]; per library cell: [dict get $cc refs]; area change [dict get $last_pf area] um^2"
                if {[dict get $cc n] == 0} { puts ">>> 095 WARNING: no change line was recognised in $countfile although fix_eco_drc returned without error: read the file" }
                lassign [pt_eco_change_number $last_pf [dict get $cc n]] nchg nsrc nnote
                if {[string is integer -strict $nchg]} {
                    set cfpath ${PT_RPT_DIR}/pt_eco_drc_expected_count.txt
                    set fp [open $cfpath w]
                    puts -nonewline $fp [pt_eco_expected_text $nchg $nsrc [expr {[dict exists $written icc2tcl] ? [dict get $written icc2tcl] : $countfile}] drc]
                    close $fp
                    puts ">>> 095 expected command count $nchg written to $cfpath (pt_eco_apply.tcl with UNPU_ECO_KIND drc compares the change file against it)"
                } else {
                    puts ">>> 095 WARNING: the number of proposed commands is unreadable ('$nchg'): NO count file is written"
                }
                # AFTER, in PrimeTime's memory
                update_timing -full
                set dr1 [pt_design_rules_run eco_drc_after $corner $sdcv]
                set sel1 [pt_drc_select [dict get $dr1 parsed] $clk $dw]
                set wns1 ""
                catch {set wns1 [get_attribute [get_timing_paths -delay_type max -max_paths 1] slack]}
                set in2out1 ""
                catch {set in2out1 [get_attribute [get_timing_paths -delay_type max -from [get_ports paddr*] -to [get_ports prdata*] -max_paths 1] slack]}
                puts ">>> 095 AFTER the ECO (PrimeTime's memory): data-limit max_transition violators [llength $sel1] (before [llength $sel]); setup WNS [pt_fmt_ns $wns1] ns (before [pt_fmt_ns $wns0]); in2out worst slack [pt_fmt_ns $in2out1] ns (before [pt_fmt_ns $in2out0])"
                set nclk0 [lindex [dict get [dict get [dict get $dr0 sum] tran] clock] 0]
                set nclk1 [lindex [dict get [dict get [dict get $dr1 sum] tran] clock] 0]
                puts ">>> 095 clock-path max_transition entries: before $nclk0, after $nclk1[expr {$nclk0 != $nclk1 ? {  <-- CHANGED: the ECO must not touch the clock network, read the change file} : {}}]"
                set fp [open ${rpt}_remaining.txt w]
                foreach e $sel1 { set l "[dict get $e name] required [dict get $e required] actual [dict get $e actual] slack [dict get $e slack]"; puts $fp $l; puts ">>> 095   remaining: $l" }
                close $fp
                # the check of the change file: pin classes (task 093) + the clock network
                set chk_file ""
                foreach f {icc2tcl icctcl} { if {$chk_file eq "" && [dict exists $written $f]} { set chk_file [dict get $written $f] } }
                if {$chk_file eq ""} { error "CHECK: no Tcl-format change file was written, the proposed changes cannot be checked" }
                set fp [open $chk_file r]; set chk_txt [read $fp]; close $fp
                set chk [eco079_parse $chk_txt]
                if {[llength [dict get $chk errors]] > 0} { error "CHECK: [llength [dict get $chk errors]] line(s) of $chk_file are not understood by the change-file parser, the check is incomplete: [join [lrange [dict get $chk errors] 0 2] { | }]" }
                file delete -force ${PT_RPT_DIR}/pt_eco_drc_pin_classes.txt
                set eco_clsd [dict create]
                set eco_cls [dict create load_flop 0 load_comb 0 flop_output 0 flop_input 0 other 0 port 0 cone_net 0 cone_driver 0 cone_port 0 clock_net 0 unknown 0]
                set eco_rows {}
                foreach c [dict get $chk cmds] {
                    if {[dict get $c type] ne "insert_buffer"} continue
                    set fx [pt_eco_insert_facts_pin [dict get $c objkind] [dict get $c full_pin] $cone [dict get $c cell]]
                    set cls [pt_eco_pin_class [dict get $c objkind] [dict get $fx in_cone] [dict get $fx dir] [dict get $fx state] [dict get $fx drv_seq] [dict get $fx is_seq] [dict get $fx is_out]]
                    # the clock network: a pin on it (yes) is a violation; unreadable is a violation (unknown)
                    set ck [pt_on_clock_network [dict get $c objkind] [dict get $c full_pin]]
                    if {$ck eq "yes"} { set cls clock_net } elseif {$ck eq "" && ![pt_eco_class_violation $cls]} { set cls unknown }
                    dict set eco_clsd [dict get $c idx] $cls
                    dict incr eco_cls $cls
                    lappend eco_rows [pt_eco_class_row [dict get $c idx] [dict get $c full_pin] [dict get $c ref] $cls [dict get $fx net] [dict get $fx drivers]]
                    puts ">>> 095 insertion [dict get $c idx]: pin [dict get $c full_pin] ([dict get $c ref]); net [expr {[dict get $fx net] eq {} ? {?} : [dict get $fx net]}]: [pt_eco_class_text093 $cls]"
                }
                set fp [open ${PT_RPT_DIR}/pt_eco_drc_pin_classes.txt w]
                puts $fp "# written by pt_eco_drc_probe.tcl (task 095): one line per insertion of the max-transition change file: <idx> <pin> <ref> <class> net=<net> drivers=<driver pins>; pt_eco_apply.tcl (UNPU_ECO_KIND drc) prints these lines and refuses a violation class"
                foreach l $eco_rows { puts $fp $l }
                close $fp
                set nres 0
                foreach c [dict get $chk cmds] { if {[dict get $c type] eq "size_cell"} { incr nres } }
                puts ">>> 095 change file $chk_file: [llength [dict get $chk cmds]] changes ([expr {[llength [dict get $chk cmds]] - $nres}] insert_buffer, $nres size_cell); insertions by class: [pt_eco_class_summary $eco_cls]"
                set hits [pt_cone_hits_pin [dict get $chk cmds] $eco_clsd [dict get $cone cells] $clock_cells]
                foreach h $hits { puts ">>> 095   HIT change [dict get $h idx] (line [dict get $h line]): [dict get $h what] [dict get $h name]" }
                if {[llength $hits] > 0} {
                    set probe_line [pt_eco_result_line touches "[llength $hits] of [llength [dict get $chk cmds]] proposed changes touch the in2out cone or the clock network; first: [dict get [lindex $hits 0] what] [dict get [lindex $hits 0] name] (change [dict get [lindex $hits 0] idx], line [dict get [lindex $hits 0] line])"]
                } else {
                    set probe_line [pt_eco_result_line 1 "$nchg changes proposed, change file [expr {[dict exists $written icctcl] ? [dict get $written icctcl] : $countfile}] (none touches the in2out cone or the clock network); data-limit violators [llength $sel] -> [llength $sel1] in PrimeTime's memory. Pin classes: [pt_eco_class_summary $eco_cls]"]
                }
            }
        }
    } perr]} {
        foreach pr [list $prot_clk $prot_cone] { if {$pr ne ""} { catch {pt_cone_unprotect $pr} } }   ;# a second removal after the normal path is harmless
        if {[regsub {^CONE: } $perr {} perr]} {
            set probe_line [pt_eco_result_line cone $perr]
        } elseif {[regsub {^CLOCK: } $perr {} perr]} {
            set probe_line [pt_eco_result_line clock $perr]
        } elseif {[regsub {^CHECK: } $perr {} perr]} {
            set probe_line [pt_eco_result_line unchecked $perr]
        } else {
            regsub {^PROBE: } $perr {} perr
            set probe_line [pt_eco_result_line 0 $perr]
        }
    }
    puts "\n=============================================================================="
    puts " ECO PROBE (max_transition of the data limit, corner $corner)"
    puts "   $probe_line"
    foreach cav [pt_summary_caveat [expr {[info exists PT_ANNOTATION_UNCHECKED] && $PT_ANNOTATION_UNCHECKED}]] { puts "   CAVEAT: $cav" }
    puts "=============================================================================="
}
exit 0
