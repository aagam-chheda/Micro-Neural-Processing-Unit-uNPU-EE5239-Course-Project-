# ==============================================================================
# Test: test_sdc_limits.tcl (task 096)
# Run : tclsh pnr_v2/test_sdc_limits.tcl   (no PrimeTime / ICC2 needed)
# Tests (1) the removal of the clock-path max_transition before write_sdc and the hard check of the exported SDCs (pure parts of pv.tcl) on the REAL exported SDC of run 3
# (pnr_v2/testdata/096_run3_exported_{ss,ff}.sdc: comment lines stripped), (2) UNPU_PT_SDC (exported / legacy) and the variable resolution of the legacy SDC, (3) pnr_v2/sdc_compare.tcl on the
# legacy SDC and the run-3 exports.
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
source $here/sdc_compare.tcl
set pv [read_file $here/pv.tcl]
set b [string first "# ---- BEGIN PURE TCL 096 ----" $pv]; set e [string first "# ---- END PURE TCL 096 ----" $pv]
if {$b < 0 || $e < $b} { puts "FAIL pure block 096 not found in pv.tcl"; exit 1 }
eval [string range $pv $b $e]
set ss [read_file $here/testdata/096_run3_exported_ss.sdc]
set ff [read_file $here/testdata/096_run3_exported_ff.sdc]
set legacy_path $here/../constraints/legacy/unpu_top_legacy.sdc
set legacy [read_file $legacy_path]

# ---- 1. pv.tcl: the clock-path limit ----
set exp_cp [list "set_max_transition 0.4 \[get_clocks \{clk\}\] -clock_path"]
check "real ss export: exactly one clock-path line" {[pv096_clockpath_lines $ss] eq $exp_cp}
check "real ff export: exactly one clock-path line" {[llength [pv096_clockpath_lines $ff]] == 1}
set exp_dl [list "set_max_transition 3 \[current_design\]" "set_max_capacitance 2 \[current_design\]"]
check "design-wide lines of the real export: max_transition 3 and max_capacitance 2" {[pv096_design_lines $ss] eq $exp_dl}
set ss_b [join [lsearch -all -inline -not -glob [split $ss "\n"] "*-clock_path*"] "\n"]
check "after the removal (line deleted): no clock-path line, design lines kept" {[llength [pv096_clockpath_lines $ss_b]] == 0 && [pv096_design_lines $ss_b] eq [pv096_design_lines $ss]}
check "export check on the removed text: no problem" {[pv096_export_problems ss $ss_b [pv096_design_lines $ss]] eq ""}
check "export check on the real run-3 text: ERROR (the clock-path line)" {[has [pv096_export_problems ss $ss [pv096_design_lines $ss]] "1 clock-path max_transition line(s) in the exported SDC"]}
set ss_c [string map {"set_max_transition 3 \[current_design\]" ""} $ss_b]
check "export check: the design-wide max_transition missing is an ERROR" {[has [pv096_export_problems ss $ss_c [pv096_design_lines $ss]] "no design-wide set_max_transition line"]}
set ss_d [string map {"set_max_capacitance 2 \[current_design\]" ""} $ss_b]
check "export check: the max_capacitance missing is an ERROR" {[has [pv096_export_problems ss $ss_d [pv096_design_lines $ss]] "no set_max_capacitance line"]}
set ss_e [string map {"set_max_transition 3 \[current_design\]" "set_max_transition 2 \[current_design\]"} $ss_b]
check "export check: a design-wide value that differs from the block's is an ERROR" {[has [pv096_export_problems ss $ss_e [pv096_design_lines $ss]] "differ from the ones the block had"]}
check "a clock-path line with the option before the object is found too" {[llength [pv096_clockpath_lines "set_max_transition -clock_path 0.4 \[get_clocks clk\]"]] == 1}
check "a commented line is not a limit" {[llength [pv096_clockpath_lines "# set_max_transition 0.4 -clock_path"]] == 0}
check "forms: only for commands that exist" {[pv096_forms {}] eq "" && [pv096_forms {remove_max_transition}] eq "{remove_max_transition -clock_path %C} {remove_max_transition %C -clock_path} {remove_max_transition %C}" && [pv096_forms {reset_max_transition}] eq "{reset_max_transition -clock_path %C}"}
check "pv.tcl: the removal runs for both scenarios BEFORE the first write_sdc" {[string first {pv096_remove_clock_path func_ss} $pv] > 0 && [string first {pv096_remove_clock_path func_ff} $pv] > 0 && [string first {pv096_remove_clock_path func_ff} $pv] < [string first "write_sdc \\\n        -scenario func_ss" $pv]}
check "pv.tcl: the hard check of both exported files is an ERROR 096" {[has $pv {pv096_export_problems ${pv096_c}}] && [has $pv {error "ERROR 096: [join $pv096_probs {; }]"}]}
check "pv.tcl: state before and after is printed (>>> 096 <scenario>: clock-path ... before N, after M)" {[has $pv {clock-path max_transition lines before [llength $cp0], after [llength $cp1]}]}
check "pv.tcl: no removal form worked is an ERROR 096 with the help text" {[has $pv {catch {help *max_transition*}}] && [has $pv {could not be removed with any known form}]}
check "pv.tcl: the design-wide lines are restored when a form also removed them" {[has $pv {they are restored from the state before}]}
check "pv.tcl: no new constraint is added (only set_max_transition lines that the block had are re-applied)" {![regexp {set_max_transition [0-9]} [regexp -all -inline -line {^[^#]*$} [string range $pv [string first "proc pv096_remove_clock_path" $pv] [string first "# 091: checkpoint mode: the output places" $pv]]]]}
set cts [read_file $here/cts.tcl]
check "cts.tcl keeps the 0.40 clock-path limit as the CTS target (unchanged)" {[has $cts {set_max_transition 0.40 -clock_path $real_clks}]}

# ---- 2. UNPU_PT_SDC ----
check "SDC mode: unset -> exported, default" {[pt_sdc_mode_resolve {}] eq "exported default"}
check "SDC mode: legacy and exported from the environment" {[pt_sdc_mode_resolve legacy] eq "legacy {environment UNPU_PT_SDC}" && [pt_sdc_mode_resolve exported] eq "exported {environment UNPU_PT_SDC}"}
foreach bad {"" Legacy both yes 1} { check "SDC mode rejected: '$bad'" {[string match "PT ERROR: UNPU_PT_SDC=*" [errmsg {pt_sdc_mode_resolve [list $bad]}]]} }
check "paths: exported keeps the old folders" {[pt_tag_paths /r route3 0 exported] eq "/r/pnr_icc2/outputs_route3 /r/pnr_icc2/pt_route3"}
check "paths: legacy -> pt_<tag>_legacy, inputs unchanged" {[pt_tag_paths /r route3 0 legacy] eq "/r/pnr_icc2/outputs_route3 /r/pnr_icc2/pt_route3_legacy" && [pt_tag_paths /r "" 0 legacy] eq "/r/pnr_icc2/outputs /r/pnr_icc2/pt_legacy"}
check "paths: legacy + SI -> pt_<tag>_legacy_si" {[pt_tag_paths /r route3 1 legacy] eq "/r/pnr_icc2/outputs_route3 /r/pnr_icc2/pt_route3_legacy_si"}
check "paths: the four reports folders of one tag are all different" {[llength [lsort -unique [list [lindex [pt_tag_paths /r x 0 exported] 1] [lindex [pt_tag_paths /r x 1 exported] 1] [lindex [pt_tag_paths /r x 0 legacy] 1] [lindex [pt_tag_paths /r x 1 legacy] 1]]]] == 4}
# the variables of the legacy SDC
set resolved [pt_sdc_resolve_vars $legacy]
set v [pt_sdc_values $resolved]
check "legacy SDC: the period is read (20)" {[dict get $v period] == 20}
check "legacy SDC: the uncertainties are read through the variables (1.5 / 0.5)" {[dict get $v setup_unc] == 1.5 && [dict get $v hold_unc] == 0.5}
check "legacy SDC without the resolution: the numbers are NOT readable (why the step exists)" {[dict get [pt_sdc_values $legacy] setup_unc] eq "" || ![string is double -strict [dict get [pt_sdc_values $legacy] setup_unc]]}
set ents [pt_limit_entries [dict get $v maxtran] [dict get $v maxcap]]
check "legacy SDC: the limits are numbers (3.0 ns and 2.0 pF, design-wide)" {[llength $ents] == 2 && [dict get [lindex $ents 0] value] == 3.0 && [dict get [lindex $ents 1] value] == 2.0 && ![dict get [lindex $ents 0] clock_path]}
check "legacy SDC: the limit report has no WARNING" {![has [join [pt_limit_report $ents $PT_EXPECT_MAX_TRANSITION $PT_EXPECT_MAX_CAP] \n] WARNING]}
check "legacy constraint check passes with the expected legacy values" {[pt_check_constraints setup [dict get $v period] [dict get $v setup_unc] [dict get $v hold_unc] $PT_EXPECT_PERIOD $PT_EXPECT_SETUP_UNC $PT_EXPECT_HOLD_UNC] eq ""}
check "variables: braces form and a trailing comment" {[pt_sdc_resolve_vars "set A 2.5 ;# x\nset_max_capacitance \${A} \[current_design\]\nset_load \$A \[get_ports x\]"] eq "set A 2.5 ;# x\nset_max_capacitance 2.5 \[current_design\]\nset_load 2.5 \[get_ports x\]"}
check "variables: a list or an expression is left alone" {[has [pt_sdc_resolve_vars "set L {a b}\nset X \[expr {1+2}\]\nfoo \$L \$X"] {foo $L $X}]}
set ex [pt_sdc_values [pt_sdc_resolve_vars $ss]]
check "the exported SDC is read the same way as before (1.5 / 0.5 / 20, and the clock-path limit is a clock-path entry)" {[dict get $ex period] == 20 && [dict get $ex setup_unc] == 1.5 && [llength [dict get $ex maxtran]] == 2 && [dict get [lindex [pt_limit_entries [dict get $ex maxtran] {}] 1] clock_path]}
# the real pt_common.tcl in a child tclsh with the variable
set tmp [file join [expr {[info exists env(TMPDIR)] ? $env(TMPDIR) : "/tmp"}] "test096_sdc_[pid].tcl"]
set tbase [file join [file dirname $tmp] "test096_base_[pid]"]
file mkdir $tbase/pnr_icc2/outputs_route4
set fp [open $tmp w]
puts $fp "proc unpu_run_init {args} { return /r }"
puts $fp "set src \[read \[open $here/pt/pt_common.tcl\]\]"
puts $fp "set b \[string first {proc pt_tag_problem} \$src\]; set e \[string first {set PT_CLOCK } \$src\]"
puts $fp "set UNPU_ERR {}; set RUN_ROOT $tbase; set PT_BASE $tbase; set PT_KIT /k; set PT_DESIGN unpu_top"
puts $fp "eval \[string range \$src \$b \[expr {\$e - 1}\]\]"
puts $fp "puts \"MODE=\$PT_SDC_MODE SRC=\$PT_SDC_SOURCE RPT=\$PT_RPT_DIR SSSDC=\$PT_CORNER(ss,sdc) FFSDC=\$PT_CORNER(ff,sdc)\""
close $fp
proc child {tmp envset} {
    set cmd [list tclsh $tmp]
    if {$envset ne ""} { set cmd [concat env $envset $cmd] }
    if {[catch {exec {*}$cmd 2>@1} out]} { return "ERR: $out" }
    return $out
}
set o0 [child $tmp {}]
check "child tclsh, UNPU_PT_SDC unset: exported, the SDCs of outputs/" {[has $o0 "MODE=exported SRC=default"] && [has $o0 "SSSDC=$tbase/pnr_icc2/outputs/unpu_top_pnr_ss.sdc"]}
set o1 [child $tmp {UNPU_PT_SDC=legacy UNPU_PT_TAG=route4}]
check "child tclsh, UNPU_PT_SDC=legacy: the legacy file for both corners, reports in pt_route4_legacy" {[has $o1 "MODE=legacy"] && [has $o1 "SSSDC=$tbase/constraints/legacy/unpu_top_legacy.sdc"] && [has $o1 "FFSDC=$tbase/constraints/legacy/unpu_top_legacy.sdc"] && [has $o1 "RPT=$tbase/pnr_icc2/pt_route4_legacy"]}
set o2 [child $tmp {UNPU_PT_SDC=nope}]
check "child tclsh, UNPU_PT_SDC=nope: PT ERROR" {[has $o2 "PT ERROR: UNPU_PT_SDC='nope' is not valid"]}
file delete $tmp; file delete -force $tbase
set common [read_file $here/pt/pt_common.tcl]
check "the legacy path is derived from the run root, not typed" {[has $common {set PT_LEGACY_SDC "${PT_BASE}/constraints/legacy/unpu_top_legacy.sdc"}]}
check "the single PrimeTime change stays: set_propagated_clock all_clocks" {[has $common "set_propagated_clock \[all_clocks\]"] && [has $common {This is the only change PrimeTime makes}]}
set lit3 "errors while reading \$sdc (text above)"
check "read_sdc errors stop the run with the message (a command PrimeTime rejects)" {[has $common $lit3] && [has $common "PT ERROR: "]}
set lit1 "puts \"   SDC: \$PT_SDC_MODE ("
set lit2 "\$::PT_SDC_MODE"
check "the summary and the banner print the SDC source" {[has $common $lit1] && [has $common $lit2]}
set PT_SDC_MODE legacy; set PT_SDC_SOURCE {environment UNPU_PT_SDC}
check "guard: an ECO probe with UNPU_PT_SDC=legacy is an error" {[string match "PT ERROR: pt_eco_drc_probe.tcl is an ECO probe and runs on the exported SDC*" [errmsg {pt_probe_si_guard pt_eco_drc_probe.tcl}]]}
set PT_SDC_MODE exported
set PT_SI_ENABLE 0

# ---- 3. sdc_compare.tcl ----
lassign [sdc096_run $legacy_path $here/testdata/096_run3_exported_ss.sdc] lines verdict nd ne
set rep [join $lines \n]
check "ss: 723 constraints compared, 718 SAME, 4 EXPECTED, 1 DIFFERENCE" {[has $rep "constraints compared: 723; SAME 718; EXPECTED differences 4; DIFFERENCES 1"]}
check "ss: the one difference is the clock-path max_transition" {$nd == 1 && [has $rep "max_transition clock_path"] && [has $rep "ONLY-IN-EXPORTED"] && [has $verdict "1 DIFFERENCE(S)"]}
check "ss: the clock, uncertainties, transition, design limits are SAME" {[regexp {uncertainty setup\s+\| 1.5\s+\| 1.5\s+\| SAME} $rep] && [regexp {uncertainty hold\s+\| 0.5\s+\| 0.5\s+\| SAME} $rep] && [regexp {clock_transition\s+\| 0.6\s+\| 0.6\s+\| SAME} $rep] && [regexp {max_transition design\s+\| 3\s+\| 3\s+\| SAME} $rep] && [regexp {max_capacitance\s+\| 2\s+\| 2\s+\| SAME} $rep]}
check "ss: input delays 7 / 8 / 0 and output delays 7 / 8 / -0.5 SAME on all ports" {[regexp {input_delay max\s+\| 7 clock clk\s+\| 7 clock clk\s+\| SAME\s+paddr\[0\].*\(67\)} $rep] && [regexp {input_delay max\s+\| 8 clock clk\s+\| 8 clock clk\s+\| SAME\s+dma_rdata\[0\].*\(34\)} $rep] && [regexp {output_delay min\s+\| -0.5 clock clk\s+\| -0.5 clock clk\s+\| SAME.*\(102\)} $rep]}
check "ss: driving cells buffd1/Z on 101 ports and loads 1 pF on 102, 0.2 pF on 101 ports are SAME" {[regexp {driving_cell\s+\| buffd1 pin Z\s+\| buffd1 pin Z\s+\| SAME.*\(101\)} $rep] && [regexp {load\s+\| 1 pin\s+\| 1 pin\s+\| SAME.*\(102\)} $rep] && [regexp {load\s+\| 0.2 pin\s+\| 0.2 pin\s+\| SAME.*\(101\)} $rep]}
check "ss: the expected differences are listed by name with a reason" {[has $rep "EXPECTED  opcond"] && [has $rep "EXPECTED  clk"] && [has $rep "expected: set_propagated_clock"] && [has $rep "expected: create_clock -waveform"] && [has $rep "expected: set_units"] && [has $rep "expected: set_operating_conditions"]}
lassign [sdc096_run $legacy_path $here/testdata/096_run3_exported_ff.sdc] lines_f verdict_f nd_f ne_f
check "ff: the same result as ss (1 difference, 4 expected)" {$nd_f == 1 && $ne_f == 4 && [has [join $lines_f \n] "constraints compared: 723; SAME 718"]}
# the exported SDC after option B: the line removed
set tmpd [file join [expr {[info exists env(TMPDIR)] ? $env(TMPDIR) : "/tmp"}] "test096_cmp_[pid]"]
file mkdir $tmpd
proc writef {path text} { set fp [open $path w]; puts -nonewline $fp $text; close $fp }
writef $tmpd/b.sdc $ss_b
lassign [sdc096_run $legacy_path $tmpd/b.sdc] lb vb ndb neb
check "after option B (the line removed): EQUAL apart from the expected differences" {$ndb == 0 && $neb == 4 && [has $vb "SDC COMPARE: EQUAL apart from the 4 expected difference(s)"]}
# a changed value is a difference
writef $tmpd/c.sdc [string map {"-max 7 \[get_ports {paddr\[3\]}\]" "-max 6 \[get_ports {paddr\[3\]}\]"} $ss_b]
lassign [sdc096_run $legacy_path $tmpd/c.sdc] lc vc ndc nec
check "a changed input delay on one port is a DIFFERENT row and a verdict with 1 difference" {$ndc == 1 && [has [join $lc \n] "DIFFERENT"] && [has [join $lc \n] "paddr\[3\]"]}
# a constraint only in the legacy file
writef $tmpd/d.sdc [string map {"set_max_capacitance 2 \[current_design\]" ""} $ss_b]
lassign [sdc096_run $legacy_path $tmpd/d.sdc] ld vd ndd ned
check "the max_capacitance missing in the exported file is ONLY-IN-LEGACY" {$ndd == 1 && [has [join $ld \n] "ONLY-IN-LEGACY"]}
# a changed uncertainty and a changed clock period
writef $tmpd/e.sdc [string map {"-setup 1.5" "-setup 1.4" "-period 20" "-period 21"} $ss_b]
lassign [sdc096_run $legacy_path $tmpd/e.sdc] le ve nde nee
check "a changed uncertainty and a changed period are two DIFFERENT rows" {$nde == 2}
# an unknown command is reported, not ignored
writef $tmpd/f.sdc "$ss_b\nset_false_path -from \[get_ports rst_n\]\n"
lassign [sdc096_run $legacy_path $tmpd/f.sdc] lf vf ndf nef
check "a command that is not compared is named in the output" {[has [join $lf \n] "commands not compared in the exported file: set_false_path"]}
# the command line: exit codes
set rc [catch {exec tclsh $here/sdc_compare.tcl $legacy_path $here/testdata/096_run3_exported_ss.sdc} out]
check "command line on the run-3 SDC: exit 1 (a difference) and the verdict line" {$rc == 1 && [has $out "SDC COMPARE: 1 DIFFERENCE(S)"]}
set rc [catch {exec tclsh $here/sdc_compare.tcl $legacy_path $tmpd/b.sdc} out]
check "command line after option B: exit 0" {$rc == 0 && [has $out "SDC COMPARE: EQUAL"]}
set rc [catch {exec tclsh $here/sdc_compare.tcl $legacy_path 2>@1} out]
set ec $::errorCode
check "command line without the second file: usage and exit status 2" {$rc == 1 && [has $out "usage"] && [lindex $ec 0] eq "CHILDSTATUS" && [lindex $ec 2] == 2}
set rc [catch {exec tclsh $here/sdc_compare.tcl $legacy_path $tmpd/nope.sdc 2>@1} out]
set ec $::errorCode
check "command line with an unreadable file: an error text and exit status 2, not a table" {$rc != 0 && [has $out "cannot read"] && [lindex $ec 2] == 2}
file delete -force $tmpd
check "pure helpers: port pattern with brackets" {[sdc096_match {paddr[*]} {paddr[3]}] == 1 && [sdc096_match {paddr[*]} {pwdata[3]}] == 0 && [sdc096_match {rst_n} {rst_n}] == 1}
check "pure helpers: 20 and 20.0 are the same number" {[sdc096_num 20.0] eq [sdc096_num 20]}

puts "RESULT: $npass passed, $nfail failed"
exit [expr {$nfail > 0}]
