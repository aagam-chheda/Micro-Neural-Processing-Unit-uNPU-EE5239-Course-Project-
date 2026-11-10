# ==============================================================================
# Script: pt_eco_probe.tcl   (task 078)  -- PROBE of PrimeTime's own ECO commands, hold at the fast corner (ff)
# Run   : cd <RUN_DIR>/pnr_icc2/pt ; pt_shell -f ../../pnr_v2/pt/pt_eco_probe.tcl |& tee pt_eco_probe.log
# 092   : optional environment variables: UNPU_ECO_SCOPE (in2reg = default, reg2out = the register-to-output hold violators), UNPU_PT_TAG (task 091: the checkpoint folders outputs_<tag> / pt_<tag>).
# Does  : the same preparation as pt_hold_ff.tcl (pt_prepare_session), then asks: does fix_eco_timing / fix_eco_hold + write_changes work here (licence, behaviour, output format)?
#         It proposes netlist changes IN MEMORY only. It writes reports and the change files into pnr_icc2/pt/; no design file, SDC, SPEF or netlist is written or changed.
# Ends  : with ONE line  `PROBE RESULT: ECO NOT AVAILABLE: <message>`, `PROBE RESULT: ECO RAN BUT PROPOSED NO CHANGES: <PrimeTime's first messages>` or
#         `PROBE RESULT: ECO RAN: N changes proposed, change file <path>`  and `exit 0` in all cases (a failed probe is an
#         answer). Errors of the PREPARATION (link, parasitics, SDC, clock proof) stop the script with a PT ERROR and exit 1, as in pt_hold_ff.tcl.
# 080: the cells and nets on any input-to-output path (the "in2out cone", e.g. the combinational APB read path paddr -> prdata) are dont_touch DURING fix_eco_timing only, and the change file is checked afterwards:
#      the first ICC2 apply of the unprotected ECO put delay cells on shared points of u_apb / u_csr and broke the read path (setup WNS -0.5899 ns in group **in2out_default**). Two more PROBE RESULT forms:
#      `ECO RAN BUT TOUCHES THE IN2OUT CONE: ...` and `ECO NOT RUN, IN2OUT CONE NOT COMPUTED: ...`.
# Every PrimeTime ECO command and option below is from knowledge of PrimeTime, not from a usage text: each is marked VERIFY.
# ==============================================================================
set PT_SCRIPT_DIR [file dirname [file normalize [info script]]]
source ${PT_SCRIPT_DIR}/pt_common.tcl

pt_main {
    pt_probe_si_guard pt_eco_probe.tcl   ;# 095
    set corner ff
    # PTE-077: fix_eco_timing recommends that this variable is set BEFORE the initial timing update of the session (otherwise it updates timing again itself). Only the probe sets it.
    set_app_var timing_save_pin_arrival_and_slack true   ;# VERIFY the variable name (taken from the message PTE-076/PTE-077 of the second server run)
    puts ">>> 078 timing_save_pin_arrival_and_slack set to true before the first update_timing (PTE-077 recommendation)"
    # 092: the scope of the ECO: in2reg (DEFAULT, tasks 078-081) or reg2out (the register-to-output hold violators of the route checkpoint). Environment UNPU_ECO_SCOPE, validated, source printed.
    set eco_envl {}
    if {[info exists ::env(UNPU_ECO_SCOPE)]} { set eco_envl [list $::env(UNPU_ECO_SCOPE)] }
    lassign [pt_eco_scope_resolve $eco_envl] eco_scope eco_scope_src
    puts ">>> 092 ECO scope $eco_scope ($eco_scope_src); input folder $PT_OUT_DIR, change files and reports in $PT_RPT_DIR"
    set sdcv [pt_prepare_session hold $corner]
    set rpt ${PT_RPT_DIR}/pt_eco_hold_${corner}
    set probe_line ""

    # ---- baseline: every hold violator before the ECO ------------------------------------------------------------------------------------------------
    lassign [pt_write_violations min ${rpt}_before_violations.csv] n_before rows_before
    set wns_before ""
    catch {set wns_before [get_attribute [get_timing_paths -delay_type min -max_paths 1] slack]}
    puts ">>> 078 BEFORE the ECO: $n_before hold-violating endpoints, WNS [pt_fmt_ns $wns_before] ns"
    set split [pt_eco_split_kinds $rows_before]
    puts ">>> 078 hold violators by kind (information; the ECO is run for ALL of them, without a -to / -from restriction): port-fed pin (startpoint is an input port, endpoint a pin) [dict get $split port_fed_pin]; other pin (endpoint a pin, startpoint a pin, e.g. register to register) [dict get $split other_pin]; endpoint is a port [dict get $split port]; kind unreadable [dict get $split unknown]; total [dict get $split total]"
    if {[dict get $split total] == 0} { puts ">>> 078 NOTE: there is no hold violator before the ECO; the probe has nothing to fix" }
    # 092: the targets of the scope. fix_eco_timing is still run WITHOUT a -from / -to restriction (the form that worked in tasks 078-081; no restriction option is known from a usage text), so it may also
    # 092: fix violators outside the scope: they are counted here and the number that remains is checked after the ECO.
    set eco_targets [pt_eco_targets $eco_scope $rows_before]
    puts ">>> 092 scope $eco_scope: [llength $eco_targets] of $n_before hold violators are targets of this scope ([expr {$n_before - [llength $eco_targets]}] other)"
    foreach l [pt_eco_target_lines $eco_targets] { puts ">>> 092   target: $l" }
    if {$eco_scope eq "reg2out" && [llength $eco_targets] == 0} { puts ">>> 092 NOTE: no register-to-output hold violator in this session: nothing for the scope reg2out to fix (check UNPU_PT_TAG and the corner)" }

    # ---- everything below is the probe: any error is the ANSWER, not a script error -----------------------------------------------------------------
    if {[catch {
        # 1. what exists
        puts ">>> 078 ECO commands known to this pt_shell (help output):"
        foreach pat {*eco* write_changes} { if {[catch {help $pat} herr]} { puts ">>> 078 help $pat failed: $herr" } }   ;# VERIFY help <pattern>
        foreach c {fix_eco_timing set_eco_options} {
            if {[catch {help -verbose $c} herr]} { if {[catch {help $c} herr2]} { puts ">>> 078 help $c failed: $herr2" } }   ;# VERIFY help -verbose <command>
        }
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

        # 3. buffer candidates from the library, with their data (raw is_buffer value, pin function, delay, area); when no delay is readable the hold-fixing set is chosen by name (dl* + buffd1), and the log says so
        set lib $PT_CORNER($corner,lib)
        set cands {}
        set seen {}
        foreach pat $PT_ECO_LIB_PATTERNS {
            foreach_in_collection lc [get_lib_cells -quiet "${lib}/${pat}"] {
                set nm [lindex [split [get_object_name $lc] /] end]
                set isb ""; set area ""; set delay ""
                catch {set isb [get_attribute $lc is_buffer]}    ;# VERIFY the lib cell attribute is_buffer (the raw value is kept and printed; an unrecognised value is not read as "no")
                catch {set area [get_attribute $lc area]}
                # the function of the pins (VERIFY get_lib_pins -of_objects and the lib pin attributes direction / function)
                set lpins {}
                catch {
                    foreach_in_collection lp [get_lib_pins -of_objects $lc] {
                        set pd ""; set pf ""
                        catch {set pd [get_attribute $lp direction]}
                        catch {set pf [get_attribute $lp function]}
                        lappend lpins [dict create name [lindex [split [get_object_name $lp] /] end] dir $pd func $pf]
                    }
                }
                set fnb [pt_eco_func_is_buffer $lpins]
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
                lappend cands [dict create name $nm raw $isb func $fnb area $area delay $dmax]
            }
        }
        puts ">>> 078 buffer candidates (patterns: $PT_ECO_LIB_PATTERNS; is_buffer is the RAW attribute value; function = buffer by the pins' function: yes / no / n/a):"
        foreach c $cands {
            lassign [pt_eco_buffer_class $c] cls basis
            puts ">>> 078   [format {%-12s is_buffer=%-8s function-buffer=%-4s area %-10s delay %-6s -> buffer: %-3s (%s)} [dict get $c name] '[dict get $c raw]' [expr {[dict get $c func] eq {} ? {n/a} : [dict get $c func]}] [dict get $c area] [expr {[dict get $c delay] eq {} ? {n/a} : [dict get $c delay]}] $cls $basis]"
        }
        lassign [pt_eco_choose_buffers $cands $PT_ECO_MAX_BUFFERS $PT_ECO_DELAY_PATTERN $PT_ECO_EXTRA_CELLS] blist bnote
        puts ">>> 078 buffer list for the ECO ([llength $blist] cells): $blist"
        puts ">>> 078   $bnote"
        if {[llength $blist] == 0} { error "PROBE: no buffer cell among the candidates ($bnote)" }
        set libblist {}
        foreach b $blist { lappend libblist ${lib}/$b }

        # 4. ECO options. LOGICAL ECO (no physical data) unless PT_ECO_PHYSICAL is 1
        set eopts [list -log_file ${rpt}_eco.log]
        if {$PT_ECO_PHYSICAL} {
            lappend eopts -physical_lib_path $PT_ECO_STD_LEF -physical_design_path $PT_ECO_DEF
            if {$PT_ECO_TECH_LEF ne ""} { lappend eopts -physical_tech_lib_path $PT_ECO_TECH_LEF }
            puts ">>> 078 PHYSICAL ECO requested (PT_ECO_PHYSICAL 1): std LEF $PT_ECO_STD_LEF, tech LEF '$PT_ECO_TECH_LEF', DEF $PT_ECO_DEF"   ;# VERIFY the option names
        } else {
            puts ">>> 078 the ECO is LOGICAL only (PT_ECO_PHYSICAL 0): no physical data is given to set_eco_options"
        }
        puts ">>> 078 set_eco_options $eopts"
        if {[catch {set_eco_options {*}$eopts} oerr]} { puts ">>> 078 set_eco_options failed (not fatal): $oerr" }   ;# VERIFY set_eco_options -log_file / -physical_lib_path / -physical_design_path / -physical_tech_lib_path

        # 5. the fix for ALL hold violators (no -to / -from restriction). The first form hands -buffer_list a COLLECTION of library cells (the second server run: a list of name strings gave
        #    PTECO-099 "corresponding library cell definition does not exist" for every cell and PTECO-017 "buffer list is empty or doesn't have any valid buffer"); the second form a list of bare names.
        # 5a. 080: the in2out cone, protected during the ECO only
        pt_load_eco_parser
        if {[catch {set cone [pt_in2out_cone]} cerr]} { error "CONE: $cerr" }
        pt_cone_print $cone ${rpt}
        if {$eco_scope eq "reg2out"} {
            # 092: the nets that a flop drives into a cone cell are released (see pt_cone_nets_reg2out); the cone cells stay dont_touch, and the AFTER check still rejects any change on a cone cell or port
            if {[catch {set cone [pt_cone_nets_reg2out $cone]} nerr]} { error "CONE: $nerr" }
        }
        set cone_cells [dict get $cone cells]
        set cone_ports [dict get $cone ports]
        set touching [pt_cone_touching $rows_before $cone_cells]
        puts ">>> 080 hold violators whose worst path touches the cone: [llength $touching] of $n_before (the others do not cross it)"
        foreach t [lrange $touching 0 [expr {$PT_CONE_TOUCH_PRINT - 1}]] { puts ">>> 080   [lindex $t 0]: cone cells on its path [lindex $t 1]" }
        set prot ""
        if {$PT_CONE_PROTECT} {
            if {[catch {set prot [pt_cone_protect $cone]} perr2]} { error "CONE: $perr2" }
        } else {
            puts ">>> 080 PT_CONE_PROTECT is 0: the cone is computed and checked but NOT protected (comparison run)"
        }
        set proposed 0
        set last_pf ""
        set tried {}
        set rcx [catch {
        foreach att {collection bare_names} {
            if {$att eq "collection"} { set bl [get_lib_cells $libblist]; set desc "-buffer_list is a collection of [sizeof_collection $bl] library cells (get_lib_cells)" } else { set bl $blist; set desc "-buffer_list is a Tcl list of bare cell names" }
            set text "$cmd -type hold -methods {insert_buffer} -buffer_list \$bl -hold_margin $PT_ECO_HOLD_MARGIN[expr {$PT_ECO_PHYSICAL ? { -physical_mode occupied_site} : {}}]"   ;# VERIFY -type -methods -buffer_list -hold_margin -physical_mode
            puts ">>> 078 trying ($desc): $text"
            set fx_txt ""
            set ferr ""
            set rc [catch {redirect -variable fx_txt { eval $text }} ferr]
            puts $fx_txt
            if {$rc} {
                lappend tried "$att: $ferr"
                puts ">>> 078 that form failed: $ferr"
                if {[pt_eco_is_option_error $ferr]} { continue }
                error "PROBE: $cmd failed: $ferr"
            }
            set last_pf [pt_eco_parse_fix_text $fx_txt]
            set nmsg [pt_eco_first_messages $last_pf 4]
            puts ">>> 078 $att form: commands proposed '[dict get $last_pf ncmd]', PTECO-099 warnings [dict get $last_pf n099], messages: [expr {[llength $nmsg] ? [join $nmsg { || }] : {none}}]"
            if {[pt_eco_fix_proposed $last_pf]} { set proposed 1; break }
            lappend tried "$att: [join $nmsg { || }]"
        }
        } lemsg]
        if {$prot ne ""} { pt_cone_unprotect $prot }   ;# 080: the dont_touch is in effect during fix_eco_timing only
        if {$rcx} { error $lemsg }

        if {!$proposed} {
            # what is "missing" about the library cell? one cell, all the ways that may work (VERIFY each)
            set one [lindex $libblist 0]
            puts ">>> 078 DIAGNOSTIC for ONE library cell ($one): object name, attributes, report"
            catch {puts ">>> 078   get_lib_cells -> [get_object_name [get_lib_cells $one]]"}
            catch {foreach a {base_name full_name is_buffer is_inverter area is_sequential dont_use dont_touch} { set v "<unreadable>"; catch {set v [get_attribute [get_lib_cells $one] $a]}; puts ">>> 078   attribute $a = $v" }}
            catch {redirect -variable lc_txt { report_lib -cell [list [lindex $blist 0]] $lib }; foreach l [lrange [split $lc_txt "\n"] 0 40] { puts "      $l" }}   ;# VERIFY report_lib -cell
            catch {redirect -variable la_txt { list_attributes -class lib_cell -application }; puts ">>> 078   lib_cell attributes: [join [lrange [split $la_txt "\n"] 0 60] { }]"}   ;# VERIFY list_attributes
            set why "[expr {$last_pf eq {} ? {the command was not accepted in any form} : "$cmd ran"}] but proposed no change. [join $tried { | }]"
            set probe_line [pt_eco_result_line nochanges $why]
        } else {
            # 6. the changes: three formats are tried; icc2tcl is the one the ICC2 side of the next task would read (VERIFY the format names). A format counts only if the file exists.
            set outs [list icctcl $PT_ECO_FILE_ICCTCL icc2tcl $PT_ECO_FILE_ICC2TCL text $PT_ECO_FILE_TEXT]
            set written {}
            set n_empty 0
            foreach {fmt fn} $outs {
                set path ${PT_RPT_DIR}/$fn
                file delete -force $path
                set wtxt ""
                if {[catch {redirect -variable wtxt { write_changes -format $fmt -output $path }} werr]} { puts ">>> 078 write_changes -format $fmt FAILED: $werr"; continue }   ;# VERIFY write_changes -format -output
                puts $wtxt
                if {[pt_eco_write_empty $wtxt]} { incr n_empty; puts ">>> 078 write_changes -format $fmt: 'No changes to write.'"; continue }
                if {![file exists $path]} { puts ">>> 078 write_changes -format $fmt printed no error but $path does not exist"; continue }
                puts ">>> 078 write_changes -format $fmt -> $path"
                lappend written $fmt $path
            }
            if {[llength $written] == 0} {
                set probe_line [pt_eco_result_line nochanges "$cmd reported [dict get $last_pf ncmd] commands but write_changes wrote no file ($n_empty of 3 formats said 'No changes to write.'): [join [pt_eco_first_messages $last_pf 4] { || }]"]
            } else {
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
                lassign [pt_eco_change_number $last_pf [dict get $cc n]] nchg nsrc nnote
                # 081: the count file for pt_eco_apply.tcl (the expectation comes from the PrimeTime side)
                if {[string is integer -strict $nchg]} {
                    set cfpath ${PT_RPT_DIR}/pt_eco_hold_expected_count.txt
                    set fp [open $cfpath w]; puts -nonewline $fp [pt_eco_expected_text $nchg $nsrc [expr {[info exists wr(icc2tcl)] ? $wr(icc2tcl) : $countfile}] $eco_scope]; close $fp
                    puts ">>> 081 expected command count $nchg (scope $eco_scope) written to $cfpath (pt_eco_apply.tcl compares the change file against it)"
                } else {
                    puts ">>> 081 WARNING: the number of proposed commands is unreadable ('$nchg'): NO count file is written; pt_eco_apply.tcl will fall back to its parameter EXPECT_HOLD_CMDS with a warning"
                }
                puts ">>> 079 changes proposed: $nchg (from: $nsrc)[expr {$nnote ne {} ? "; NOTE: $nnote" : {}}]; per command in the log: [dict get $last_pf commands]; area change [dict get $last_pf area] um^2; cells [dict get $last_pf cells]"
                # 8. 080: remaining violators and WHY; the after-check of the change file against the cone
                set rem [pt_cone_why_remaining $rows_after $cone_cells]
                set fp [open ${rpt}_after_remaining.txt w]; foreach l $rem { puts $fp $l }; close $fp
                set rem_touch [llength [pt_cone_touching $rows_after $cone_cells]]
                puts ">>> 080 AFTER the ECO: $n_after hold violators remain, [llength [pt_cone_touching $rows_after $cone_cells]] of them cross the protected cone on their data path (reasons for all in ${rpt}_after_remaining.txt; the first $PT_CONE_TOUCH_PRINT follow)"
                foreach l [lrange $rem 0 [expr {$PT_CONE_TOUCH_PRINT - 1}]] { puts ">>> 080   remaining: $l" }
                if {$n_after > 0 && $rem_touch == $n_after} { puts ">>> 080 every remaining violator crosses the cone: the fix points PrimeTime needed are in the protected cone. This is the expected cost of the protection (the read path has no margin); see README section 8 for the options" }
                set chk_file ""
                foreach f {icc2tcl icctcl} { if {$chk_file eq "" && [info exists wr($f)]} { set chk_file $wr($f) } }
                if {$chk_file eq ""} { error "CHECK: no Tcl-format change file was written, the proposed changes cannot be checked against the cone" }
                set fp [open $chk_file r]; set chk_txt [read $fp]; close $fp
                set chk [eco079_parse $chk_txt]
                if {[llength [dict get $chk errors]] > 0} { error "CHECK: [llength [dict get $chk errors]] line(s) of $chk_file are not understood by the change-file parser, the cone check is incomplete: [join [lrange [dict get $chk errors] 0 2] { | }]" }
                # 093: every proposed insertion is judged at PIN level: a load pin by the NET that feeds it (a flop-driven released net starts at a flop: safe), a driver pin of a cone cell, a kept cone net,
                # 093: a cone port, a resize of a cone cell and anything unreadable are violations. The cell-level dont_touch above and the ICC2 apply gate stay the other two lines of defence.
                file delete -force ${PT_RPT_DIR}/pt_eco_hold_pin_classes.txt
                set eco_clsd [dict create]
                set eco_cls [dict create load_flop 0 load_comb 0 flop_output 0 flop_input 0 other 0 port 0 cone_net 0 cone_driver 0 cone_port 0 unknown 0]
                set eco_rows {}
                foreach c [dict get $chk cmds] {
                    if {[dict get $c type] ne "insert_buffer"} continue
                    set fx [pt_eco_insert_facts_pin [dict get $c objkind] [dict get $c full_pin] $cone [dict get $c cell]]
                    set cls [pt_eco_pin_class [dict get $c objkind] [dict get $fx in_cone] [dict get $fx dir] [dict get $fx state] [dict get $fx drv_seq] [dict get $fx is_seq] [dict get $fx is_out]]
                    dict set eco_clsd [dict get $c idx] $cls
                    dict incr eco_cls $cls
                    lappend eco_rows [pt_eco_class_row [dict get $c idx] [dict get $c full_pin] [dict get $c ref] $cls [dict get $fx net] [dict get $fx drivers]]
                    puts ">>> 093 insertion [dict get $c idx]: pin [dict get $c full_pin] (cell [expr {[dict get $fx cell] eq {} ? {?} : [dict get $fx cell]}], [dict get $c ref]); original net [expr {[dict get $fx net] eq {} ? {?} : [dict get $fx net]}], original driver [expr {[llength [dict get $fx drivers]] == 0 ? {?} : [join [dict get $fx drivers] {, }]}] (sequential: [expr {[llength [dict get $fx drv_seq]] == 0 ? {?} : [join [dict get $fx drv_seq] {, }]}]); net state [expr {[dict get $fx state] eq {} ? {?} : [dict get $fx state]}]; after the ECO the pin sees [expr {[dict get $fx new_net] eq {} ? {the same net} : "net [dict get $fx new_net] driven by [dict get $fx new_driver]"}]: [pt_eco_class_text093 $cls]"
                }
                set fp [open ${PT_RPT_DIR}/pt_eco_hold_pin_classes.txt w]
                puts $fp "# written by pt_eco_probe.tcl (task 093): one line per insertion of the hold change file: <idx> <pin> <ref> <class> net=<net> drivers=<driver pins>; pt_eco_apply.tcl prints these lines and refuses a violation class"
                foreach l $eco_rows { puts $fp $l }
                close $fp
                puts ">>> 093 pin classes written to ${PT_RPT_DIR}/pt_eco_hold_pin_classes.txt"
                set hits [pt_cone_hits_pin [dict get $chk cmds] $eco_clsd $cone_cells]
                puts ">>> 080 AFTER-CHECK of $chk_file (pin level, task 093): [llength [dict get $chk cmds]] changes parsed, [llength $hits] violate the cone"
                foreach h $hits { puts ">>> 080   HIT change [dict get $h idx] (line [dict get $h line]): [dict get $h what] [dict get $h name]" }
                puts ">>> 093 insertions by class: [pt_eco_class_summary $eco_cls]"
                if {$eco_scope eq "reg2out" && ([dict get $eco_cls other] + [dict get $eco_cls flop_input] + [dict get $eco_cls load_comb]) > 0} { puts ">>> 093 NOTE: some insertions are outside the cone but not on a flop-driven load pin (listed above); the apply gate and PrimeTime decide, read them before applying" }
                set eco_rem [pt_eco_targets $eco_scope $rows_after]
                puts ">>> 092 scope $eco_scope: targets before [llength $eco_targets], remaining after the ECO (in PrimeTime's memory) [llength $eco_rem]"
                foreach l [pt_eco_target_lines $eco_rem] { puts ">>> 092   remaining target: $l" }
                if {[llength $hits] > 0} {
                    set probe_line [pt_eco_result_line touches "[llength $hits] of [llength [dict get $chk cmds]] proposed changes touch the cone; first: [dict get [lindex $hits 0] what] [dict get [lindex $hits 0] name] (change [dict get [lindex $hits 0] idx], line [dict get [lindex $hits 0] line]); change file [expr {[info exists wr(icctcl)] ? $wr(icctcl) : $countfile}] must NOT be applied"]
                } else {
                    set probe_line [pt_eco_result_line 1 "$nchg changes proposed, change file [expr {[info exists wr(icctcl)] ? $wr(icctcl) : $countfile}] (none touches the in2out cone). Pin classes: [pt_eco_class_summary $eco_cls]"]
                }
            }
        }
    } perr]} {
        if {[regsub {^CONE: } $perr {} perr]} {
            set probe_line [pt_eco_result_line cone $perr]
        } elseif {[regsub {^CHECK: } $perr {} perr]} {
            set probe_line [pt_eco_result_line unchecked $perr]
        } else {
            regsub {^PROBE: } $perr {} perr
            set probe_line [pt_eco_result_line 0 $perr]
        }
    }
    puts "\n=============================================================================="
    puts " ECO PROBE (hold, corner $corner; hold margin $PT_ECO_HOLD_MARGIN ns; scope $eco_scope)"
    puts "   $probe_line"
    foreach cav [pt_summary_caveat [expr {[info exists PT_ANNOTATION_UNCHECKED] && $PT_ANNOTATION_UNCHECKED}]] { puts "   CAVEAT: $cav" }
    puts "=============================================================================="
}
exit 0
