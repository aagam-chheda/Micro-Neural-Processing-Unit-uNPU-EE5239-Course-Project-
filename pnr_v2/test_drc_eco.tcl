# ==============================================================================
# Test: test_drc_eco.tcl (task 095)
# Run : tclsh pnr_v2/test_drc_eco.tcl   (no PrimeTime / ICC2 needed)
# Tests (1) the design rules in the PrimeTime summary on the REAL report of run 3 (pnr_v2/testdata/095_run3_ss_design_rules.rpt: 510 max_transition entries = 424 clock-path limit + 86 data limit,
# 0 max_capacitance, 0 min pulse width; the ff report has none), (2) the ICC2 reference read from ICC2's report instead of constants, (3) UNPU_PT_SI, (4) the data-limit max-transition ECO: selection, grouping
# by net (the 9 nets of run 3, traced from the netlist), the class file with the new clock_net class, the apply script's UNPU_ECO_KIND and the protection of the hold-ECO cells.
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
set nfail 0; set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc has {text lit} { return [expr {[string first $lit $text] >= 0}] }
proc errmsg {script} { if {[catch {uplevel 1 $script} m]} { return $m }; return "" }

source $here/pt/pt_common.tcl
set apply [read_file $here/pt_eco_apply.tcl]
foreach n {079 092 093 095} {
    set b [string first "# ---- BEGIN PURE TCL $n ----" $apply]; set e [string first "# ---- END PURE TCL $n ----" $apply]
    if {$b < 0 || $e < $b} { puts "FAIL pure block $n not found"; exit 1 }
    eval [string range $apply $b $e]
}
set common [read_file $here/pt/pt_common.tcl]
set rep_ss [read_file $here/testdata/095_run3_ss_design_rules.rpt]
set rep_ff [read_file $here/testdata/095_run3_ff_design_rules.rpt]

# ---- 1. the design rules of run 3 ----
set pss [pt_parse_design_rules $rep_ss]
set sum [pt_design_rules_summary $pss 0.40 3.0]
check "ss report is recognised as a report_constraint report" {[dict get $pss ok] == 1}
check "510 max_transition entries in total" {[dict get $sum total] == 510 && [pt_dr_count $sum max_transition] == 510}
check "424 on the clock-path limit 0.40" {[lindex [dict get [dict get $sum tran] clock] 0] == 424}
check "86 on the design limit 3.0" {[lindex [dict get [dict get $sum tran] design] 0] == 86}
check "none on a limit that is both / another" {[lindex [dict get [dict get $sum tran] both] 0] == 0 && [lindex [dict get [dict get $sum tran] other] 0] == 0}
check "0 max_capacitance, 0 min pulse width" {[pt_dr_count $sum max_capacitance] == 0 && [pt_dr_count $sum min_pulse_width] == 0}
check "worst of the clock group: actual 0.48, slack -0.08" {[lrange [dict get [dict get $sum tran] clock] 1 2] eq "-0.08 0.48"}
check "worst of the design group: actual 3.05, slack -0.05" {[lrange [dict get [dict get $sum tran] design] 1 2] eq "-0.05 3.05"}
check "no entry lost its name (wrapped long names are joined)" {[llength [lmap e [dict get $pss entries] {expr {[dict get $e name] eq {} ? [list x] : [continue]}}]] == 0}
check "a wrapped entry keeps the name from the line before" {[llength [lmap e [dict get $pss entries] {expr {[dict get $e name] eq "u_seq/c_dst_reg_2__0__23_/CP" && [dict get $e required] == 0.40 ? [list 1] : [continue]}}]] == 1}
check "verdict: VIOLATED (510)" {[pt_design_rules_verdict $sum] eq "VIOLATED (510)"}
set lines [pt_design_rules_lines $sum 0.40 3.0]
check "block: clock-path line with 424" {[has [join $lines \n] {clock-path limit (0.40 ns): 424 violators, worst actual 0.48 ns (required 0.40), worst slack -0.08}]}
check "block: design line with 86" {[has [join $lines \n] {design limit (3.0 ns): 86 violators, worst actual 3.05 ns (required 3.00), worst slack -0.05}]}
check "block: capacitance and pulse width lines with 0" {[has [join $lines \n] {max_capacitance: 0 violators}] && [has [join $lines \n] {min pulse width: 0 violators}]}
check "block: the overall line" {[lindex $lines end] eq "  DESIGN RULES: VIOLATED (510)"}
set pff [pt_parse_design_rules $rep_ff]
set sumf [pt_design_rules_summary $pff 0.40 3.0]
check "ff report: readable, no entry, MET" {[dict get $pff ok] == 1 && [dict get $sumf total] == 0 && [pt_design_rules_verdict $sumf] eq "MET"}
set sumg [pt_design_rules_summary [pt_parse_design_rules "garbage\nnothing"] 0.40 3.0]
check "an unreadable report is UNKNOWN, never MET" {[string match "UNKNOWN*" [pt_design_rules_verdict $sumg]]}
check "empty text is UNKNOWN" {[string match "UNKNOWN*" [pt_design_rules_verdict [pt_design_rules_summary [pt_parse_design_rules ""] 0.40 3.0]]]}
set synth "Report : constraint\n\n   max_capacitance\n\n   Pin   Required Actual Slack\n   --------\n   u1/Z   2.00   2.10   -0.10  (VIOLATED)\n\n   min_pulse_width\n\n   u_x/CP    clk (high)   0.50   0.40   -0.10  (VIOLATED)\n   u_y/CP    clk (high)   0.50   0.45   -0.05  (VIOLATED)\n   max_transition\n   u_z/A  3.00  3.10  -0.10 (VIOLATED)\n   u_w/A\n               3.00  nonsense (VIOLATED)\n"
set ps [pt_parse_design_rules $synth]
set ss [pt_design_rules_summary $ps 0.40 3.0]
check "synthetic: 1 cap + 2 pulse width + 2 transition entries" {[pt_dr_count $ss max_capacitance] == 1 && [pt_dr_count $ss min_pulse_width] == 2 && [pt_dr_count $ss max_transition] == 2 && [dict get $ss total] == 5}
check "a VIOLATED line with unreadable numbers is kept, not dropped" {[llength [dict get $ps entries]] == 5 && [dict get [lindex [dict get $ps entries] 4] actual] eq ""}
check "synthetic verdict counts every group" {[pt_design_rules_verdict $ss] eq "VIOLATED (5)"}
set sb [pt_design_rules_summary [pt_parse_design_rules "Report : constraint\n   max_transition\n   a/B 3.00 3.10 -0.10 (VIOLATED)\n"] {3.0} {3.0}]
check "limits with the same value are not separable: reported as both" {[lindex [dict get [dict get $sb tran] both] 0] == 1 && [lindex [dict get [dict get $sb tran] design] 0] == 0}
check "sign-off line: both MET" {[pt_signoff_line setup MET MET] eq "TIMING AND DESIGN RULES: both MET"}
check "sign-off line: timing MET, rules VIOLATED -> NOT CLEAN" {[pt_signoff_line setup MET "VIOLATED (510)"] eq "SIGN-OFF IS NOT CLEAN: DESIGN RULES VIOLATED (510)"}
check "sign-off line: both bad" {[pt_signoff_line hold VIOLATED "VIOLATED (3)"] eq "SIGN-OFF IS NOT CLEAN: HOLD VIOLATED; DESIGN RULES VIOLATED (3)"}
check "sign-off line: rules unknown is not clean" {[string match "SIGN-OFF IS NOT CLEAN*" [pt_signoff_line setup MET "UNKNOWN (x)"]]}
# the summary block, captured
proc cap_run {script} {
    global cap_text
    set cap_text ""
    rename puts _puts_orig
    proc puts {args} { global cap_text; append cap_text "[lindex $args end]\n" }
    set rc [catch {uplevel 1 $script} m]
    rename puts {}
    rename _puts_orig puts
    return [list $rc $m $cap_text]
}
set PT_SUMMARY_EXTRA {}
set PT_DR_LINES $lines
set PT_DR_VERDICT [pt_design_rules_verdict $sum]
lassign [cap_run {pt_print_summary setup ss 0.1058 0.0 0 0.04}] rc m out
check "summary: setup verdict word unchanged (SETUP: MET)" {$rc == 0 && [has $out "SETUP: MET"]}
check "summary: carries the DESIGN RULES block and the NOT CLEAN line" {[has $out "DESIGN RULES: VIOLATED (510)"] && [has $out "SIGN-OFF IS NOT CLEAN: DESIGN RULES VIOLATED (510)"]}
check "summary: the SI state is on the summary line" {[has $out "violating endpoints 0, SI OFF"]}
check "summary: the ICC2 figure given is the one printed" {[has $out "ICC2 +0.0400 ns"]}
unset PT_DR_LINES PT_DR_VERDICT
lassign [cap_run {pt_print_summary hold ff 0.0002 0.0 0 ""}] rc m out
check "summary without a design-rule run says NOT CHECKED, not clean" {[has $out "DESIGN RULES: NOT CHECKED in this run"] && [has $out "SIGN-OFF IS NOT CLEAN"] && [has $out "difference UNKNOWN"]}

# ---- 2. the ICC2 reference from ICC2's report ----
check "ICC2 slack: the smallest of the paths" {[lindex [pt_icc2_slack_from_report "  slack (MET)       0.08\n  slack (MET)  0.04\n  slack (MET)  0.09\n"] 0] == 0.04}
check "ICC2 slack: the number of paths" {[lindex [pt_icc2_slack_from_report "  slack (MET)       0.08\n  slack (VIOLATED)  -0.03\n"] 2] == 2 && [lindex [pt_icc2_slack_from_report "  slack (MET)       0.08\n  slack (VIOLATED)  -0.03\n"] 0] == -0.03}
check "ICC2 slack: -0.00 is zero and the raw text is kept" {[pt_icc2_slack_from_report "  slack (VIOLATED)    -0.00\n"] eq "0.0 -0.00 1"}
check "ICC2 slack: no slack line gives an empty value" {[lindex [pt_icc2_slack_from_report "nothing here\n"] 0] eq ""}
check "ICC2 source text names the file, the raw figure and the rounding" {[has [pt_icc2_source_text /r/reports/x.rpt 0.04 0.04 50] "worst slack 0.04 of the 50 paths in /r/reports/x.rpt (the ICC2 report rounds to 2 decimals)"]}
check "ICC2 source text when unavailable: UNKNOWN comparison" {[has [pt_icc2_source_text /r/x.rpt "" "" 0] "NOT AVAILABLE"] && [has [pt_icc2_source_text /r/x.rpt "" "" 0] "UNKNOWN"]}
check "the compare line with no ICC2 figure is UNKNOWN" {[pt_compare_line setup 0.1058 ""] eq "SETUP WNS: PrimeTime +0.1058 ns, ICC2 n/a ns, difference UNKNOWN"}
check "no run-1 constant is left in the scripts" {![has [read_file $here/pt/pt_setup_ss.tcl] PT_ICC2_SETUP_WNS] && ![has [read_file $here/pt/pt_hold_ff.tcl] PT_ICC2_HOLD_WNS] && ![has $common {set PT_ICC2_SETUP_WNS}] && ![has $common {set PT_ICC2_HOLD_WNS}]}
check "reports dir of the same export: tag and no tag" {[pt_reports_dir /r ""] eq "/r/pnr_icc2/reports" && [pt_reports_dir /r route3] eq "/r/pnr_icc2/reports_route3"}
check "scripts call the new procs" {[has [read_file $here/pt/pt_setup_ss.tcl] {pt_design_rules_run setup}] && [has [read_file $here/pt/pt_hold_ff.tcl] {pt_design_rules_run hold}] && [has [read_file $here/pt/pt_setup_ss.tcl] {pt_icc2_reference setup}] && [has [read_file $here/pt/pt_hold_ff.tcl] {pt_icc2_reference hold}]}

# ---- 3. UNPU_PT_SI ----
check "SI: unset -> 0, default" {[pt_si_resolve {}] eq "0 default"}
check "SI: 1 and 0 from the environment" {[pt_si_resolve 1] eq "1 {environment UNPU_PT_SI}" && [pt_si_resolve 0] eq "0 {environment UNPU_PT_SI}"}
foreach bad {"" yes true 2 on " 1x" -1} { check "SI rejected: '$bad'" {[string match "PT ERROR: UNPU_PT_SI=*" [errmsg {pt_si_resolve [list $bad]}]]} }
check "paths: SI off keeps the old folders" {[pt_tag_paths /r route3] eq "/r/pnr_icc2/outputs_route3 /r/pnr_icc2/pt_route3" && [pt_tag_paths /r ""] eq "/r/pnr_icc2/outputs /r/pnr_icc2/pt"}
check "paths: SI on, with a tag: inputs unchanged, reports in pt_<tag>_si" {[pt_tag_paths /r route3 1] eq "/r/pnr_icc2/outputs_route3 /r/pnr_icc2/pt_route3_si"}
check "paths: SI on without a tag: pt_si" {[pt_tag_paths /r "" 1] eq "/r/pnr_icc2/outputs /r/pnr_icc2/pt_si"}
check "paths: the SI folder never equals the SI-off folder" {[lindex [pt_tag_paths /r x 1] 1] ne [lindex [pt_tag_paths /r x 0] 1]}
# the real file sourced in a child tclsh with the variable set
set tmp [file join [expr {[info exists env(TMPDIR)] ? $env(TMPDIR) : "/tmp"}] "test095_si_[pid].tcl"]
set fp [open $tmp w]
puts $fp "set auto_path \[list\]; proc unpu_run_init {args} { return /r }"
puts $fp "proc info_script_override {} { return $here/pt/pt_common.tcl }"
puts $fp "set src \[read \[open $here/pt/pt_common.tcl\]\]"
puts $fp "set b \[string first {proc pt_tag_problem} \$src\]; set e \[string first {set PT_KIT} \$src\]"
puts $fp "set UNPU_ERR {}; set RUN_ROOT /r; set PT_BASE \$env(TEST095_BASE)"
puts $fp "eval \[string range \$src \$b \[expr {\$e - 1}\]\]"
puts $fp "puts \"SI=\$PT_SI_ENABLE SRC=\$PT_SI_SOURCE RPT=\$PT_RPT_DIR REPORTS=\$PT_REPORTS_DIR\""
close $fp
proc child {tmp envset} {
    set cmd [list tclsh $tmp]
    if {$envset ne ""} { set cmd [concat env $envset $cmd] }
    if {[catch {exec {*}$cmd 2>@1} out]} { return "ERR: $out" }
    return $out
}
set tbase [file join [file dirname $tmp] "test095_base_[pid]"]
file mkdir $tbase/pnr_icc2/outputs_route4
set env(TEST095_BASE) $tbase
set o0 [child $tmp {}]
check "child tclsh, UNPU_PT_SI unset: SI=0, reports in pnr_icc2/pt" {[has $o0 "SI=0 SRC=default RPT=$tbase/pnr_icc2/pt REPORTS=$tbase/pnr_icc2/reports"]}
set o1 [child $tmp {UNPU_PT_SI=1 UNPU_PT_TAG=route4}]
check "child tclsh, UNPU_PT_SI=1 and a tag: SI=1, reports in pt_route4_si" {[has $o1 "SI=1"] && [has $o1 "RPT=$tbase/pnr_icc2/pt_route4_si"] && [has $o1 "REPORTS=$tbase/pnr_icc2/reports_route4"]}
set o2 [child $tmp {UNPU_PT_SI=maybe}]
check "child tclsh, UNPU_PT_SI=maybe: the script stops with PT ERROR" {[has $o2 "PT ERROR: UNPU_PT_SI='maybe' is not valid"]}
file delete $tmp; file delete -force $tbase
check "SI: the licence check and the guard are in place" {[has $common {proc pt_si_setup}] && [has $common {get_license PrimeTime-SI}] && [has $common {UNPU_PT_SI=1 but the PrimeTime-SI licence}]}
check "SI: the three ECO probes refuse UNPU_PT_SI=1" {[has [read_file $here/pt/pt_eco_probe.tcl] {pt_probe_si_guard pt_eco_probe.tcl}] && [has [read_file $here/pt/pt_eco_setup_probe.tcl] {pt_probe_si_guard pt_eco_setup_probe.tcl}] && [has [read_file $here/pt/pt_eco_drc_probe.tcl] {pt_probe_si_guard pt_eco_drc_probe.tcl}]}
set PT_SI_ENABLE 1; set PT_SI_SOURCE {environment UNPU_PT_SI}
check "SI guard: an ECO probe with SI on is an error" {[string match "PT ERROR: pt_eco_probe.tcl is an ECO probe*" [errmsg {pt_probe_si_guard pt_eco_probe.tcl}]]}
set PT_DR_LINES {}; set PT_DR_VERDICT MET
lassign [cap_run {pt_print_summary setup ss 0.1 0.0 0 0.04}] rc m out
check "summary: SI ON on the summary line" {[has $out "violating endpoints 0, SI ON"]}
set PT_SI_ENABLE 0

# ---- 4. the data-limit max-transition ECO ----
set sel [pt_drc_select $pss 0.40 3.0]
check "selection: the 86 entries of the data limit, none of the clock-path limit" {[llength $sel] == 86 && [llength [pt_drc_select $pss 3.0 0.40]] == 424}
check "selection: names include the ports, the load pins and the wrapped driver pin" {[lsearch -exact [lmap e $sel {dict get $e name}] {dma_wdata[25]}] >= 0 && [lsearch -exact [lmap e $sel {dict get $e name}] u_actbuf/U419/A2] >= 0 && [lsearch -exact [lmap e $sel {dict get $e name}] u_actbuf/HFSBUF_21543_531/Z] >= 0}
# the facts of the real nets (traced from the post-layout netlist of run 3)
proc fct {net refs pins fo kind} { return [dict create name x net $net driver_refs $refs driver_pins $pins fanout $fo kind $kind err ""] }
set facts [dict create]
foreach e $sel {
    set nm [dict get $e name]
    if {[string match u_seq/* $nm]} { dict set facts $nm [fct u_seq/HFSNET_137 buffd1 u_seq/HFSBUF_1163_489/Z 40 pin] } \
    elseif {[string match u_actbuf/* $nm]} { dict set facts $nm [fct u_actbuf/HFSNET_29 buffd1 u_actbuf/HFSBUF_21543_531/Z 37 pin] } \
    else { regexp {\[(\d+)\]} $nm -> bit; dict set facts $nm [fct $nm an02d4 u_dma/U_wd$bit/Z 1 port] }
}
set groups [pt_drc_group_by_net $sel $facts]
check "86 entries on 9 nets" {[llength $groups] == 9}
check "the two high-fanout nets carry 41 + 38 entries" {[lsort -integer [lmap g $groups {llength [dict get $g entries]}]] eq "1 1 1 1 1 1 1 38 41" || [lsort -integer [lmap g $groups {llength [dict get $g entries]}]] eq "1 1 1 1 1 1 1 38 40"}
check "ordered by the worst slack: the first net is a dma_wdata port (slack -0.05)" {[dict get [lindex $groups 0] worst_slack] == -0.05}
check "7 nets are output ports driven by an02d4" {[llength [lmap g $groups {expr {[dict get $g kind] eq "port" ? [list 1] : [continue]}}]] == 7}
set why [pt_drc_why [lindex $groups 0]]
check "why line: driver reference and the port remark" {[has $why "driven by an02d4"] && [has $why "OUTPUT PORT"]}
set hf [lindex [lsearch -inline -all -glob [lmap g $groups {list [dict get $g net] $g}] {u_seq/HFSNET_137 *}] 0]
check "why line of a high-fanout net: buffd1 and 40 load pins" {[has [pt_drc_why [lindex $hf 1]] "driven by buffd1"] && [has [pt_drc_why [lindex $hf 1]] "40 load pin(s)"]}
check "csv header and row" {[pt_drc_nets_header] eq "net;kind;driver_pins;driver_refs;fanout_load_pins;n_entries;worst_actual_ns;worst_slack_ns;entries" && [string match "u_seq/HFSNET_137;pin;u_seq/HFSBUF_1163_489/Z;buffd1;40;*" [pt_drc_nets_row [lindex $hf 1]]]}
set none [pt_drc_group_by_net [list [dict create group max_transition name zz required 3.00 actual 3.04 slack -0.04]] [dict create]]
check "an entry without facts goes to the net ? (never dropped)" {[llength $none] == 1 && [dict get [lindex $none 0] net] eq "?" && [has [pt_drc_nets_row [lindex $none 0]] ";?;"]}
# the class file with the clock_net class
check "clock_net is a violation class on both sides" {[pt_eco_class_violation clock_net] == 1 && [eco093_violation clock_net] == 1}
check "the violation lists of the two sides are equal" {[lsort [lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize clock_net unknown} {expr {[pt_eco_class_violation $c] ? $c : [continue]}}]] eq [lsort [lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize clock_net unknown} {expr {[eco093_violation $c] ? $c : [continue]}}]]}
check "class text of clock_net" {[has [pt_eco_class_text093 clock_net] "VIOLATION"] && [has [pt_eco_class_text093 clock_net] "clock"]}
set chg "current_instance {u_seq}\ninsert_buffer \[get_pins {HFSBUF_1163_489/Z}\] buffd3 -new_net_names {net_PTECO_DRC_NET1} -new_cell_names {U_PTECO_DRC_BUF1}\nsize_cell {HFSBUF_21543_531} buffd7\nsize_cell {ZCTSINV_1} invbd7\ncurrent_instance {}\n"
set pc [eco079_parse $chg]
check "the change file with insert_buffer + size_cell parses" {[llength [dict get $pc errors]] == 0 && [llength [dict get $pc cmds]] == 3}
set hits [pt_cone_hits_pin [dict get $pc cmds] [dict create 1 load_flop] {u_apb/U46} {u_seq/ZCTSINV_1}]
check "a size_cell of a clock-network cell is a hit; load_flop and a data resize are not" {[llength $hits] == 1 && [dict get [lindex $hits 0] name] eq "u_seq/ZCTSINV_1" && [has [dict get [lindex $hits 0] what] "clock-network"]}
set hits2 [pt_cone_hits_pin [dict get $pc cmds] [dict create 1 clock_net] {} {}]
check "an insertion of class clock_net is a hit" {[llength $hits2] == 1 && [has [dict get [lindex $hits2 0] what] "clock-network"]}
set hits3 [pt_cone_hits_pin [dict get $pc cmds] [dict create] {} {}]
check "an insertion without a class is unknown = a hit" {[llength $hits3] == 1}
check "the old 3-argument call still works" {[llength [pt_cone_hits_pin [dict get $pc cmds] [dict create 1 load_flop] {}]] == 0}
check "the class summary names clock_net" {[has [pt_eco_class_summary [dict create clock_net 2 load_flop 7]] "7 load pin on a flop-driven net"] && [has [pt_eco_class_summary [dict create clock_net 2]] "2 change on a clock-network"]}
check "result line: clock network not protected" {[pt_eco_result_line clock "x"] eq "PROBE RESULT: ECO NOT RUN, CLOCK NETWORK NOT PROTECTED: x"}
# the apply script: kind, files, hold cells
check "kind hold (default): the files of tasks 079-093" {[eco095_kind_files hold /p] eq "main /p/pt_eco_hold_changes_icc2.tcl setup /p/pt_eco_setup_changes_icc2.tcl count /p/pt_eco_hold_expected_count.txt classes /p/pt_eco_hold_pin_classes.txt"}
check "kind drc: its own change, count and class files, no setup file" {[eco095_kind_files drc /p] eq "main /p/pt_eco_drc_changes_icc2.tcl setup {} count /p/pt_eco_drc_expected_count.txt classes /p/pt_eco_drc_pin_classes.txt"}
foreach bad {"" Hold setup both} { check "kind rejected: '$bad'" {[string match "ERROR 095: UNPU_ECO_KIND=*" [errmsg {eco095_kind_files $bad /p}]]} }
set names {u_csr/U_PTECO_HOLD_BUF1 u_csr/U_PTECO_HOLD_BUF2 u_seq/U_PTECO_DRC_BUF1 u_x/U1}
check "hold cells are told from the new drc cells" {[eco095_hold_cells $names PTECO_HOLD] eq "u_csr/U_PTECO_HOLD_BUF1 u_csr/U_PTECO_HOLD_BUF2" && [eco095_not_hold $names PTECO PTECO_HOLD] eq "u_seq/U_PTECO_DRC_BUF1"}
check "not_hold with the marker PTECO leaves only the new cells" {[eco095_not_hold {u_csr/U_PTECO_HOLD_BUF1 u_seq/U_PTECO_DRC_BUF1} PTECO PTECO_HOLD] eq "u_seq/U_PTECO_DRC_BUF1"}
check "apply source: UNPU_ECO_KIND is read, validated through eco095_kind_files and printed" {[has $apply {UNPU_ECO_KIND}] && [has $apply {>>> 095 ECO kind $ECO_KIND}] && [has $apply {set ECO_FILES [eco095_kind_files $ECO_KIND $PT_DIR]}]}
check "apply source: the class file is REQUIRED for the kind drc" {[has $apply {for the kind drc it is REQUIRED}]}
check "apply source: the hold-ECO cells are protected, compared and not counted as new" {[has $apply {set ea_names [concat $ea_names $ea_early $ea_holdprev]}] && [has $apply {CHECK hold-ECO cells}] && [has $apply {eco095_not_hold $ea_pre}] && [has $apply {eco095_not_hold $ea_found_names}]}
check "apply source: the gates are unchanged (in2out and whole-design setup WNS tolerance, DRC, legality, open nets)" {[has $apply {GATE_TOL_SETUP}] && [has $apply {check_routes DRCs}] && [has $apply {legality violations}] && [has $apply {open nets}] && [has $apply {set GATE_TOL_SETUP  0.005}]}
check "apply source: hold WNS before and after is reported" {[has $apply {GATE hold $ghst}] && [has $apply {the whole-design hold WNS}]}
# the probe script
set probe [read_file $here/pt/pt_eco_drc_probe.tcl]
check "probe: fix_eco_drc -type max_transition with size_cell and insert_buffer" {[has $probe {fix_eco_drc -type max_transition -methods {size_cell insert_buffer}}]}
check "probe: buffer candidates are plain buffers, not the dl* delay cells" {[has $probe {PT_ECO_DRC_LIB_PATTERNS}] && $PT_ECO_DRC_LIB_PATTERNS eq {buff* bufbd*} && ![has $PT_ECO_DRC_LIB_PATTERNS dl]}
check "probe: the cone AND the clock network are protected, and removed again" {[has $probe {pt_cone_protect $cone}] && [has $probe {pt_clock_protect}] && [has $probe {pt_cone_unprotect $prot_clk}] && [has $probe {pt_cone_unprotect $prot_cone}]}
check "probe: the data-limit entries only (the clock-path limit is not part of it)" {[has $probe {pt_drc_select}] && [has $probe {not part of this ECO}]}
check "probe: before/after of the data-limit violators, setup WNS, in2out slack, the clock-path count" {[has $probe {AFTER the ECO (PrimeTime's memory): data-limit max_transition violators}] && [has $probe {in2out worst slack}] && [has $probe {clock-path max_transition entries: before}]}
check "probe: writes the nets file, the count file and the class file" {[has $probe {_nets.csv}] && [has $probe {pt_eco_drc_expected_count.txt}] && [has $probe {pt_eco_drc_pin_classes.txt}]}
check "probe: a hit is the result TOUCHES, never a success line" {[has $probe {pt_eco_result_line touches}] && [has $probe {pt_eco_result_line clock}]}
check "probe: no limit, uncertainty or constraint command" {![regexp {set_max_transition|set_clock_uncertainty|set_input_delay|set_output_delay|set_load|set_driving_cell} [regexp -all -inline -line {^[^#]*$} $probe]]}
check "probe: the rule about cone resizes is stated" {[has $probe {stricter than "allowed if it is a speed-up"}]}

puts "RESULT: $npass passed, $nfail failed"
exit [expr {$nfail > 0}]
