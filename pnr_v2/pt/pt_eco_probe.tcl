# ==============================================================================
# Script: pt_eco_probe.tcl   (task 078)  -- PROBE of PrimeTime's own ECO commands, hold at the fast corner (ff)
# Run   : cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt ; pt_shell -f ../../pnr_v2/pt/pt_eco_probe.tcl |& tee pt_eco_probe.log
# Does  : the same preparation as pt_hold_ff.tcl (pt_prepare_session), then asks: does fix_eco_timing / fix_eco_hold + write_changes work here (licence, behaviour, output format)?
#         It proposes netlist changes IN MEMORY only. It writes reports and the change files into pnr_icc2/pt/; no design file, SDC, SPEF or netlist is written or changed.
# Ends  : with ONE line  `PROBE RESULT: ECO NOT AVAILABLE: <message>`  or  `PROBE RESULT: ECO RAN: N changes proposed, change file <path>`  and `exit 0` in both cases (a failed probe is an
#         answer). Errors of the PREPARATION (link, parasitics, SDC, clock proof) stop the script with a PT ERROR and exit 1, as in pt_hold_ff.tcl.
# Every PrimeTime ECO command and option below is from knowledge of PrimeTime, not from a usage text: each is marked VERIFY.
# ==============================================================================
set PT_SCRIPT_DIR [file dirname [file normalize [info script]]]
source ${PT_SCRIPT_DIR}/pt_common.tcl

pt_main {
    set corner ff
    set sdcv [pt_prepare_session hold $corner]
    set rpt ${PT_RPT_DIR}/pt_eco_hold_${corner}
    set probe_line ""

    # ---- baseline: every hold violator before the ECO ------------------------------------------------------------------------------------------------
    lassign [pt_write_violations min ${rpt}_before_violations.csv] n_before rows_before
    set wns_before ""
    catch {set wns_before [get_attribute [get_timing_paths -delay_type min -max_paths 1] slack]}
    puts ">>> 078 BEFORE the ECO: $n_before hold-violating endpoints, WNS [pt_fmt_ns $wns_before] ns"
    set eps [pt_eco_port_fed_endpoints $rows_before]
    puts ">>> 078 hold violators whose startpoint is an input port and whose endpoint is a pin: [llength $eps] (the ECO is asked to fix these; the task expects 255 flop D pins)"

    # ---- everything below is the probe: any error is the ANSWER, not a script error -----------------------------------------------------------------
    if {[catch {
        # 1. what exists
        puts ">>> 078 ECO commands known to this pt_shell (help output):"
        foreach pat {*eco* write_changes} { if {[catch {help $pat} herr]} { puts ">>> 078 help $pat failed: $herr" } }   ;# VERIFY help <pattern>
        set existing {}
        foreach c {fix_eco_timing fix_eco_hold fix_eco_drc fix_eco_power set_eco_options write_changes} {
            if {[llength [info commands $c]] > 0} { lappend existing $c } else { puts ">>> 078 command not found by 'info commands': $c" }
        }
        puts ">>> 078 existing: $existing"
        set cmd [pt_eco_pick_cmd $existing]
        if {$cmd eq ""} { error "PROBE: neither fix_eco_timing nor fix_eco_hold exists in this pt_shell (see the help output above)" }
        if {[lsearch -exact $existing write_changes] < 0} { error "PROBE: write_changes does not exist in this pt_shell, the proposed changes could not be exported" }
        puts ">>> 078 fix command used: $cmd"

        # 2. licences: print what PrimeTime says; the ECO command itself is the final test
        if {[catch {redirect -variable pt_lic_txt { list_licenses }} lerr]} { puts ">>> 078 list_licenses failed: $lerr"; set pt_lic_txt "" }   ;# VERIFY list_licenses
        puts ">>> 078 list_licenses lines that mention ECO: [expr {[llength [pt_eco_license_lines $pt_lic_txt]] ? [pt_eco_license_lines $pt_lic_txt] : {none (or list_licenses unavailable)}}]"
        foreach f $PT_ECO_LICENSE_TRIES {
            if {[catch {get_license $f} lres]} { puts ">>> 078 get_license $f: FAILED: $lres" } else { puts ">>> 078 get_license $f: ok ($lres)" }   ;# VERIFY get_license <feature>
        }

        # 3. buffer candidates from the library, with their data; the choice is made by data (is_buffer, delay, area), not by name
        set lib $PT_CORNER($corner,lib)
        set cands {}
        set seen {}
        foreach pat $PT_ECO_LIB_PATTERNS {
            foreach_in_collection lc [get_lib_cells -quiet "${lib}/${pat}"] {
                set nm [lindex [split [get_object_name $lc] /] end]
                set isb ""; set area ""; set delay ""
                catch {set isb [get_attribute $lc is_buffer]}    ;# VERIFY the lib cell attribute is_buffer
                catch {set area [get_attribute $lc area]}
                # the largest delay value found among the timing arcs of the cell (VERIFY: lib timing arc attributes; unreadable -> empty)
                set dmax ""
                catch {
                    foreach_in_collection arc [get_lib_timing_arcs -of_objects $lc] {
                        foreach a {delay_max_rise delay_max_fall delay_min_rise delay_min_fall} {
                            set v ""
                            catch {set v [get_attribute $arc $a]}
                            if {[string is double -strict $v] && ($dmax eq "" || $v > $dmax)} { set dmax $v }
                        }
                    }
                }
                if {[lsearch -exact $seen $nm] >= 0} continue   ;# a cell matched by two patterns is listed once
                lappend seen $nm
                lappend cands [dict create name $nm is_buffer $isb area $area delay $dmax]
            }
        }
        puts ">>> 078 buffer candidates (name, is_buffer, area, delay at this corner if readable; patterns: $PT_ECO_LIB_PATTERNS):"
        foreach c $cands { puts ">>> 078   [format {%-12s is_buffer %-6s area %-10s delay %s} [dict get $c name] [dict get $c is_buffer] [dict get $c area] [expr {[dict get $c delay] eq {} ? {n/a} : [dict get $c delay]}]]" }
        lassign [pt_eco_choose_buffers $cands $PT_ECO_MAX_BUFFERS] blist bnote
        puts ">>> 078 buffer list for the ECO: $blist -- $bnote"
        if {[llength $blist] == 0} { error "PROBE: no buffer cell among the candidates ($bnote)" }
        set libblist {}
        foreach b $blist { lappend libblist ${lib}/$b }

        # 4. ECO options (logical ECO: no physical data)
        if {[catch {set_eco_options -log_file ${rpt}_eco.log} oerr]} { puts ">>> 078 set_eco_options -log_file failed (not fatal): $oerr" }   ;# VERIFY set_eco_options and -log_file

        # 5. the fix, restricted to the port-fed endpoints; the forms are tried in order, only an unknown-option error moves on to the next form
        if {[llength $eps] == 0} { error "PROBE: no hold violator is fed by an input port (and ends at a pin): nothing to fix; the probe has nothing to test" }
        set inports [remove_from_collection [all_inputs] [get_ports $PT_CLOCK]]
        set epobjs [get_pins $eps]
        set forms [list \
            "-to \$epobjs" \
            "-from \$inports" \
            "" ]
        set done 0
        set errs {}
        foreach restr $forms {
            set text "$cmd -type hold -methods {insert_buffer} -buffer_list {$libblist} -hold_margin $PT_ECO_HOLD_MARGIN $restr"   ;# VERIFY -type -methods -buffer_list -hold_margin and the restriction option
            puts ">>> 078 trying: [string map [list \$epobjs "<[llength $eps] endpoint pins>" \$inports "<input ports>"] $text]"
            if {[catch {eval $text} ferr]} {
                lappend errs "($restr) $ferr"
                puts ">>> 078 that form failed: $ferr"
                if {[pt_eco_is_option_error $ferr]} { continue }
                error "PROBE: $cmd failed: $ferr"
            }
            set done 1
            if {$restr eq ""} { puts ">>> 078 NOTE: neither -to nor -from was accepted: the ECO was run WITHOUT a restriction, it may also touch the endpoints that are not port-fed" }
            break
        }
        if {!$done} { error "PROBE: $cmd rejected every form of the command: [join $errs { | }]" }

        # 6. the changes: three formats are tried; icc2tcl is the one the ICC2 side of the next task would read (VERIFY the format names)
        set outs [list icctcl $PT_ECO_FILE_ICCTCL icc2tcl $PT_ECO_FILE_ICC2TCL text $PT_ECO_FILE_TEXT]
        set written {}
        foreach {fmt fn} $outs {
            set path ${PT_RPT_DIR}/$fn
            if {[catch {write_changes -format $fmt -output $path} werr]} { puts ">>> 078 write_changes -format $fmt FAILED: $werr" } else { puts ">>> 078 write_changes -format $fmt -> $path"; lappend written $fmt $path }   ;# VERIFY write_changes -format -output
        }
        if {[llength $written] == 0} { error "PROBE: $cmd ran but write_changes failed in every format" }
        # the count from the text file (else from the first file that was written)
        array set wr $written
        set countfile [expr {[info exists wr(text)] ? $wr(text) : [lindex $written 1]}]
        set fp [open $countfile r]; set ctext [read $fp]; close $fp
        set known {}
        foreach c $cands { lappend known [dict get $c name] }
        set cc [pt_eco_count_changes $ctext $known]
        puts ">>> 078 first 30 lines of $countfile:"
        foreach l [lrange [split $ctext "\n"] 0 29] { puts "      $l" }
        puts ">>> 078 changes proposed (lines starting with a netlist-changing command; VERIFY the verbs against the file): [dict get $cc n]; per command: [dict get $cc verbs]; per library cell: [dict get $cc refs]"
        if {[dict get $cc n] == 0} { puts ">>> 078 WARNING: no change line was recognised in $countfile although $cmd returned without error: read the file (the format may differ from the verbs expected)" }

        # 7. does PrimeTime think the ECO closes hold?
        update_timing -full
        redirect -variable pt_after_txt { report_constraint -all_violators -min_delay }   ;# VERIFY report_constraint -min_delay
        set fp [open ${rpt}_after_violators.rpt w]; puts $fp $pt_after_txt; close $fp
        set pva [pt_parse_violators $pt_after_txt]
        lassign [pt_write_violations min ${rpt}_after_violations.csv] n_after rows_after
        set wns_after ""
        catch {set wns_after [get_attribute [get_timing_paths -delay_type min -max_paths 1] slack]}
        puts ">>> 078 AFTER the ECO (in PrimeTime's memory): $n_after hold-violating endpoints (report_constraint: [dict get $pva count] lines marked VIOLATED), WNS [pt_fmt_ns $wns_after] ns (before: $n_before, WNS [pt_fmt_ns $wns_before] ns)"
        puts ">>> 078 per-endpoint slack after the ECO: ${rpt}_after_violators.rpt and ${rpt}_after_violations.csv (the first 40 lines of the report follow)"
        foreach l [lrange [split $pt_after_txt "\n"] 0 39] { puts "      $l" }
        set probe_line [pt_eco_result_line 1 "[dict get $cc n] changes proposed, change file [expr {[info exists wr(icctcl)] ? $wr(icctcl) : $countfile}]"]
    } perr]} {
        regsub {^PROBE: } $perr {} perr
        set probe_line [pt_eco_result_line 0 $perr]
    }
    puts "\n=============================================================================="
    puts " ECO PROBE (hold, corner $corner; hold margin $PT_ECO_HOLD_MARGIN ns)"
    puts "   $probe_line"
    foreach cav [pt_summary_caveat [expr {[info exists PT_ANNOTATION_UNCHECKED] && $PT_ANNOTATION_UNCHECKED}]] { puts "   CAVEAT: $cav" }
    puts "=============================================================================="
}
exit 0
