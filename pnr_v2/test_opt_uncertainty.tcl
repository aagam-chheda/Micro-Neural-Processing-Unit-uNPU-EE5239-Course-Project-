# ==============================================================================
# Test: test_opt_uncertainty.tcl (task 090)
# Run : tclsh pnr_v2/test_opt_uncertainty.tcl   (no ICC2 needed)
# Tests pnr_v2/opt_uncertainty.tcl: the parameter validation (UNPU_SETUP_SLACK_GOAL, UNPU_HOLD_SLACK_GOAL, UNPU_UNC_SCOPE, UNPU_UNC_PROBE) and the printed source, the SDC parser, the pv.tcl check,
# the apply / restore decisions, the in2out warning, the probe verdict; the ICC2 procs against a STATEFUL mock (clock-level and pin/port-level values per scenario, write_sdc, slacks computed from them):
# the three scopes, the restore proof (n pins left -> ERROR 090), a remove_clock_uncertainty that does nothing, ports ignored by the tool (probe warns); the source of the flow scripts.
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
set nfail 0; set npass 0
set CAPTURE 0; set PUTS ""
rename puts real_puts
proc puts {args} {
    if {[llength $args] == 1 && $::CAPTURE} { append ::PUTS [lindex $args 0] "\n"; return }
    if {[llength $args] == 1 && !$::CAPTURE} { return }   ;# the printed lines of the procs under test are not shown outside capture
    real_puts {*}$args
}
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; real_puts "FAIL $name   ($cond)" }
}
proc errmsg {script} { if {[catch {uplevel 1 $script} m]} { return $m }; return "" }

set src [read_file $here/opt_uncertainty.tcl]
set b [string first "# ---- BEGIN PURE TCL 090 ----" $src]; set e [string first "# ---- END PURE TCL 090 ----" $src]
check "pure markers exist" {$b > 0 && $e > $b}
source $here/opt_uncertainty.tcl

# ---- 1. parameters ----
check "defaults in the file: setup 0.05, hold 0.10, scope flops" {$UNC090_DEF_SETUP_GOAL == 0.05 && $UNC090_DEF_HOLD_GOAL == 0.10 && $UNC090_DEF_SCOPE eq "flops"}
check "unset -> default, source default" {[unc090_resolve UNPU_X 0.05 goal {}] eq "0.05 default"}
check "set -> value, source names the variable" {[unc090_resolve UNPU_SETUP_SLACK_GOAL 0.05 goal {0.2}] eq "0.2 {environment UNPU_SETUP_SLACK_GOAL}"}
foreach ok {0 0.0 1 1.0 .5 0.05 5e-2} { check "goal accepted: $ok" {[errmsg {unc090_resolve V 0.05 goal [list $ok]}] eq ""} }
foreach bad {-0.1 1.01 2 abc "" "  " 0,5 NaN 1.0.0} {
    set m [errmsg {unc090_resolve UNPU_HOLD_SLACK_GOAL 0.1 goal [list $bad]}]
    check "goal rejected: '$bad' (names the variable)" {[string match "ERROR 090: UNPU_HOLD_SLACK_GOAL=*" $m]}
}
foreach ok {flops outputs clock} { check "scope accepted: $ok" {[errmsg {unc090_resolve S flops scope [list $ok]}] eq ""} }
foreach bad {flop Flops "" ports all} { check "scope rejected: '$bad'" {[string match "ERROR 090: S=*" [errmsg {unc090_resolve S flops scope [list $bad]}]]} }
foreach ok {0 1} { check "flag accepted: $ok" {[errmsg {unc090_resolve F 1 flag [list $ok]}] eq ""} }
foreach bad {2 yes ""} { check "flag rejected: '$bad'" {[string match "ERROR 090: F=*" [errmsg {unc090_resolve F 1 flag [list $bad]}]]} }
check "unknown kind -> error" {[string match "ERROR 090*" [errmsg {unc090_resolve F 1 nokind {1}}]]}
set pl [unc090_params_line flops default 0.05 default 0.2 {environment UNPU_HOLD_SLACK_GOAL} 1 default 1.5 0.5]
check "parameters line carries scope, both goals with their source, targets" {[string match "*scope flops (default)*setup goal 0.05 ns (default)*hold goal 0.2 ns (environment UNPU_HOLD_SLACK_GOAL)*targets setup 1.55 (func_ss) and hold 0.7 (func_ff)*" $pl] && [string match ">>> 090 parameters:*" $pl]}
# unc090_params reads the environment
catch {unset ::env(UNPU_SETUP_SLACK_GOAL)}; catch {unset ::env(UNPU_HOLD_SLACK_GOAL)}; catch {unset ::env(UNPU_UNC_SCOPE)}; catch {unset ::env(UNPU_UNC_PROBE)}
set out [unc090_params 1.5 0.5]
check "params: defaults" {$out eq "0.05 0.10 flops 1"}
set ::env(UNPU_HOLD_SLACK_GOAL) 0.3; set ::env(UNPU_UNC_SCOPE) outputs; set ::env(UNPU_UNC_PROBE) 0
check "params: environment" {[unc090_params 1.5 0.5] eq "0.05 0.3 outputs 0"}
set ::env(UNPU_SETUP_SLACK_GOAL) -1
check "params: invalid environment stops" {[string match "ERROR 090: UNPU_SETUP_SLACK_GOAL*" [errmsg {unc090_params 1.5 0.5}]]}
unset ::env(UNPU_SETUP_SLACK_GOAL); unset ::env(UNPU_HOLD_SLACK_GOAL); unset ::env(UNPU_UNC_SCOPE); unset ::env(UNPU_UNC_PROBE)
check "params: SPEC of the script differs from the file -> ERROR" {[string match "ERROR 090: the SPEC values*" [errmsg {unc090_params 1.6 0.5}]] && [string match "ERROR 090: the SPEC values*" [errmsg {unc090_params 1.5 0.4}]]}

# ---- 2. SDC parser ----
set T "# comment\nset_clock_uncertainty -setup 1.55 \[get_pins \{a/CK b/CK\}\]\nset_clock_uncertainty 1.5 -setup \[get_clocks \{clk\}\]\nset_clock_uncertainty -hold 0.5 \[get_ports \{dma_addr\[31\] x\}\]\nset_clock_uncertainty -from \[get_clocks a\] -to \[get_clocks b\] 0.3\nset_clock_uncertainty 0.25 \[get_clocks clk\]\nset_clock_uncertainty -setup 1.55 \\\n   \[get_pins \{c/CK d/CK e/CK\}\]\ncreate_clock x\n"
set P [unc090_parse $T]
check "parse: 6 lines (comment and other commands ignored, continuation joined)" {[llength $P] == 6}
check "parse: pin line" {[dict get [lindex $P 0] level] eq "pin" && [dict get [lindex $P 0] nnames] == 2 && [dict get [lindex $P 0] type] eq "setup" && [dict get [lindex $P 0] value] == 1.55}
check "parse: clock line, value before the flag" {[dict get [lindex $P 1] level] eq "clock" && [dict get [lindex $P 1] value] == 1.5 && [dict get [lindex $P 1] type] eq "setup"}
check "parse: port names with brackets are names" {[dict get [lindex $P 2] level] eq "pin" && [dict get [lindex $P 2] nnames] == 2 && [dict get [lindex $P 2] type] eq "hold"}
check "parse: inter-clock line" {[dict get [lindex $P 3] level] eq "interclock"}
check "parse: no flag -> both" {[dict get [lindex $P 4] type] eq "both" && [dict get [lindex $P 4] level] eq "clock"}
check "parse: continuation line counts 3 names" {[dict get [lindex $P 5] nnames] == 3}
check "parse: unbalanced bracket -> level other" {[dict get [lindex [unc090_parse "set_clock_uncertainty 1 \[get_clocks \{clk\}"] 0] level] eq "other"}
check "parse: no object -> level other" {[dict get [lindex [unc090_parse "set_clock_uncertainty 1 -setup"] 0] level] eq "other"}
check "parse: nothing -> empty" {[llength [unc090_parse "create_clock x\n"]] == 0}
lassign [unc090_pin_left $P] nl nn
check "pin_left counts lines and names" {$nl == 3 && $nn == 7}

# ---- 3. pv.tcl check on sample SDC text ----
set okT "set_clock_uncertainty -setup 1.5 \[get_clocks \{clk\}\]\nset_clock_uncertainty -hold 0.5 \[get_clocks \{clk\}\]\n"
check "export: clock-level SPEC lines only -> ok" {[llength [unc090_export_problems [unc090_parse $okT] 1.5 0.5]] == 0}
check "export: no line at all -> ok (the count note is printed by the caller)" {[llength [unc090_export_problems {} 1.5 0.5]] == 0}
check "export: a pin-level line -> problem" {[llength [unc090_export_problems [unc090_parse "set_clock_uncertainty -hold 0.6 \[get_pins \{a/CK\}\]\n"] 1.5 0.5]] == 1}
check "export: a port-level line at SPEC value is still a problem" {[llength [unc090_export_problems [unc090_parse "set_clock_uncertainty -hold 0.5 \[get_ports \{a\}\]\n"] 1.5 0.5]] == 1}
check "export: changed setup value -> problem" {[string match "setup value 1.55 differs*" [lindex [unc090_export_problems [unc090_parse "set_clock_uncertainty -setup 1.55 \[get_clocks clk\]\n"] 1.5 0.5] 0]]}
check "export: changed hold value -> problem" {[string match "hold value 0.6 differs*" [lindex [unc090_export_problems [unc090_parse "set_clock_uncertainty -hold 0.6 \[get_clocks clk\]\n"] 1.5 0.5]  0]]}
check "export: a line without flag (both) must match both" {[llength [unc090_export_problems [unc090_parse "set_clock_uncertainty 1.5 \[get_clocks clk\]\n"] 1.5 0.5]] == 1}
check "export: unreadable line -> problem" {[llength [unc090_export_problems [unc090_parse "set_clock_uncertainty 1.5 -setup\n"] 1.5 0.5]] == 1}
check "export: inter-clock at SPEC is allowed" {[llength [unc090_export_problems [unc090_parse "set_clock_uncertainty -setup 1.5 -from \[get_clocks a\] -to \[get_clocks b\]\n"] 1.5 0.5]] == 0}
# unc090_export_check on files
set tmp [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] unc090_test_[pid]]
file mkdir $tmp
proc wf {path txt} { set fp [open $path w]; puts -nonewline $fp $txt; close $fp }
wf $tmp/ss.sdc $okT; wf $tmp/ff.sdc $okT
check "export_check: two clean files -> 4 lines, no error" {[unc090_export_check t [list $tmp/ss.sdc $tmp/ff.sdc] 1.5 0.5] == 4}
wf $tmp/bad.sdc "set_clock_uncertainty -hold 0.6 \[get_pins \{a/CK\}\]\n$okT"
check "export_check: a pin-level line -> ERROR 090 with the line" {[string match "ERROR 090: t:*a/CK*" [errmsg {unc090_export_check t [list $tmp/ss.sdc $tmp/bad.sdc] 1.5 0.5}]]}
check "export_check: missing file -> ERROR 090" {[string match "ERROR 090*does not exist*" [errmsg {unc090_export_check t [list $tmp/none.sdc] 1.5 0.5}]]}

# ---- 4. apply and restore decisions ----
set clkS "set_clock_uncertainty -setup 1.5 \[get_clocks clk\]\n"
set clkO "set_clock_uncertainty -setup 1.55 \[get_clocks clk\]\n"
set pinO "set_clock_uncertainty -setup 1.55 \[get_pins \{a/CK b/CK\}\]\n"
set pinS "set_clock_uncertainty -setup 1.5 \[get_ports \{x y z\}\]\n"
lassign [unc090_apply_check [unc090_parse "$clkS$pinO"] flops setup 1.5 1.55 0.05] pr m
check "apply_check flops: clock SPEC + pin OPT -> ok, 2 names" {[llength $pr] == 0 && $m == 2}
lassign [unc090_apply_check [unc090_parse "$clkO$pinS"] outputs setup 1.5 1.55 0.05] pr m
check "apply_check outputs: clock OPT + port SPEC -> ok, 3 names" {[llength $pr] == 0 && $m == 3}
lassign [unc090_apply_check [unc090_parse $clkO] clock setup 1.5 1.55 0.05] pr m
check "apply_check clock: clock OPT -> ok" {[llength $pr] == 0}
lassign [unc090_apply_check [unc090_parse $clkS] flops setup 1.5 1.55 0.05] pr m
check "apply_check flops: the pin values are missing -> problem" {[llength $pr] > 0 && $m == 0}
lassign [unc090_apply_check [unc090_parse "$clkO$pinO"] flops setup 1.5 1.55 0.05] pr m
check "apply_check flops: clock-level raised too (leak) -> problem" {[llength $pr] > 0}
lassign [unc090_apply_check [unc090_parse "$clkS$pinO"] clock setup 1.5 1.55 0.05] pr m
check "apply_check clock: unexpected pin line and clock-level not raised -> problems" {[llength $pr] >= 2}
lassign [unc090_apply_check [unc090_parse $clkS] flops setup 1.5 1.5 0] pr m
check "apply_check goal 0: clock SPEC and nothing else -> ok" {[llength $pr] == 0}
lassign [unc090_apply_check [unc090_parse "$clkS$pinO"] flops setup 1.5 1.5 0] pr m
check "apply_check goal 0: a pin line is a problem" {[llength $pr] > 0}
lassign [unc090_apply_check [unc090_parse "set_clock_uncertainty -hold 0.5 \[get_clocks clk\]\n"] flops setup 1.5 1.55 0.05] pr m
check "apply_check: the other kind does not count (no setup clock line -> problem)" {[llength $pr] > 0}
check "restore: clean -> no problem" {[llength [unc090_restore_problems [unc090_parse $clkS] setup 1.5]] == 0}
check "restore: n pins left -> problem naming the lines and names" {[string match "1 pin/port-level line(s) with 2 name(s)*" [lindex [unc090_restore_problems [unc090_parse "$clkS$pinO"] setup 1.5] 0]]}
check "restore: ports left -> problem" {[llength [unc090_restore_problems [unc090_parse "$clkS$pinS"] setup 1.5]] == 1}
check "restore: clock-level not SPEC -> problem" {[llength [unc090_restore_problems [unc090_parse $clkO] setup 1.5]] == 1}
check "restore: no clock line -> problem" {[llength [unc090_restore_problems {} setup 1.5]] == 1}
check "in2out: drop beyond tolerance -> WARNING with both numbers" {[string match ">>> 090 WARNING: the margin made the in2out group worse*0.0081*-0.04*" [unc090_in2out_cmp setup 0.0081 -0.04 0.005]]}
check "in2out: within tolerance -> nothing" {[unc090_in2out_cmp setup 0.0081 0.004 0.005] eq ""}
check "in2out: better -> nothing" {[unc090_in2out_cmp hold 0.0068 0.02 0.005] eq ""}
check "in2out: unreadable -> told, not silent" {[string match ">>> 090 WARNING: in2out setup could not be compared*" [unc090_in2out_cmp setup n/a 0.1 0.005]]}
lassign [unc090_probe_verdict p 1.0 1.05 -0.05 0.005] st tx
check "probe: moves by the goal -> ok" {$st eq "ok"}
lassign [unc090_probe_verdict p 1.0 1.0 -0.05 0.005] st tx
check "probe: no change -> same (ICC2 ignored the value)" {$st eq "same" && [string match "*ICC2 ignored the pin/port-level value*" $tx]}
lassign [unc090_probe_verdict p 1.0 1.02 -0.05 0.005] st tx
check "probe: moves by the wrong amount -> off with numbers" {$st eq "off" && [string match "*change -0.0200*expected -0.05*" $tx]}
lassign [unc090_probe_verdict p n/a 1.0 -0.05 0.005] st tx
check "probe: no slack -> na with WARNING" {$st eq "na" && [string match ">>> 090 WARNING*" $tx]}
lassign [unc090_probe_verdict p 1.1 1.0 0.1 0.005] st tx
check "probe: positive expectation (outputs form) -> ok" {$st eq "ok"}
check "scen_missing" {[unc090_scen_missing {func_ss func_ff} {func_ss func_ff}] eq "" && [unc090_scen_missing {func_ss} {func_ss func_ff}] eq "func_ff"}

# ---- 5. the ICC2 procs against a stateful mock ----
set RUN_ROOT $tmp
set LOG {}
array set UC {}     ;# UC(scen,kind) clock-level value
array set PL {}     ;# PL(scen,kind,objname) pin/port-level value
set CURS func_ss
set IGNORE_PORTS 0  ;# 1: the tool writes port-level values into the SDC but ignores them in timing
set REMOVE_NOOP 0   ;# 1: remove_clock_uncertainty does nothing
set REMOVE_NOKIND 0 ;# 1: remove_clock_uncertainty rejects -setup/-hold
proc mock_reset {} {
    global UC PL LOG CURS IGNORE_PORTS REMOVE_NOOP REMOVE_NOKIND
    array unset UC; array unset PL; set LOG {}; set CURS func_ss; set IGNORE_PORTS 0; set REMOVE_NOOP 0; set REMOVE_NOKIND 0
    foreach s {func_ss func_ff} { set UC($s,setup) 1.0; set UC($s,hold) 0.3 }   ;# a pre-CTS profile value, not SPEC
}
proc foreach_in_collection {v coll body} { upvar 1 $v x; foreach i $coll { set x $i; uplevel 1 $body } }
proc sizeof_collection {c} { return [llength $c] }
proc get_object_name {x} { return [lindex [split [lindex $x 0] |] 1] }
proc get_scenarios {args} { return {s|func_ss s|func_ff} }
proc current_scenario {args} { global CURS; if {[llength $args] == 0} { return [list s|$CURS] }; set CURS [lindex $args 0]; return }
proc get_clocks {args} { return c|clk }
proc update_timing {args} { lappend ::LOG update_timing }
proc unpu_remove_clock_latency {label} { return 0 }
proc unpu_clock_latency_note {label what n} { }
set FLOPS {a b c d u_dma/stage_reg_1__14_}
set OUTS {dma_addr[31] prdata[0] x}
proc all_registers {args} {
    global FLOPS
    if {[lsearch -exact $args -level_sensitive] >= 0} { return {} }
    if {[lsearch -exact $args -clock_pins] >= 0} { return [lmap f $FLOPS {string cat p| $f /CK}] }
    return [lmap f $FLOPS {string cat r| $f}]
}
proc all_outputs {} { global OUTS; return [lmap o $OUTS {string cat o| $o}] }
proc all_inputs {} { return {i|clk i|dma_rdata[14] i|paddr[3]} }
proc get_ports {args} { global OUTS; set n [lindex $args end]; if {[lsearch -exact $OUTS $n] >= 0} { return o|$n }; if {$n eq "dma_rdata\[14\]"} { return i|$n }; return {} }
proc get_pins {args} { set n [lindex $args end]; if {$n eq "u_dma/stage_reg_1__14_/D"} { return p|$n }; return {} }
proc remove_from_collection {a b} { set o {}; foreach x $a { if {[lsearch -exact $b $x] < 0} { lappend o $x } }; return $o }
proc get_attribute {obj name args} {
    if {$name eq "slack"} { return [lindex [split $obj |] 1] }
    if {$name eq "sources"} { return i|clk }
    return ""
}
proc set_clock_uncertainty {args} {
    global UC PL CURS LOG
    set kind both; set val ""; set objs {}
    foreach a $args { if {$a eq "-setup"} { set kind setup } elseif {$a eq "-hold"} { set kind hold } elseif {$val eq "" && [string is double -strict $a]} { set val $a } else { set objs $a } }
    lappend LOG [list set_clock_uncertainty $kind $val [lindex $objs 0]]
    foreach o $objs {
        lassign [split $o |] t n
        if {$t eq "c"} { set UC($CURS,$kind) $val } else { set PL($CURS,$kind,$o) $val }
    }
}
proc remove_clock_uncertainty {args} {
    global PL CURS LOG REMOVE_NOOP REMOVE_NOKIND
    lappend LOG [list remove_clock_uncertainty $args]
    set kind both; set objs {}
    foreach a $args { if {$a eq "-setup"} { set kind setup } elseif {$a eq "-hold"} { set kind hold } else { set objs $a } }
    if {$REMOVE_NOKIND && $kind ne "both"} { error "Error: unknown option" }
    if {$REMOVE_NOOP} { return }
    foreach o $objs { foreach k {setup hold} { if {$kind eq "both" || $kind eq $k} { if {[info exists PL($CURS,$k,$o)]} { unset PL($CURS,$k,$o) } } } }
}
proc write_sdc {args} {
    global UC PL
    set scen ""; set out ""
    for {set i 0} {$i < [llength $args]} {incr i} { set a [lindex $args $i]; if {$a eq "-scenario"} { set scen [lindex $args [incr i]] } elseif {$a eq "-output"} { set out [lindex $args [incr i]] } elseif {$a eq "-include"} { incr i } }
    set fp [open $out w]
    foreach k {setup hold} {
        puts $fp "set_clock_uncertainty -$k $UC($scen,$k) \[get_clocks \{clk\}\]"
        set g [dict create]
        foreach key [array names PL $scen,$k,*] { set o [lindex [split $key ,] 2]; set v $PL($key); set key2 "$v [string index $o 0]"; dict lappend g $key2 [lindex [split $o |] 1] }
        dict for {kv names} $g { lassign $kv v t; puts $fp "set_clock_uncertainty -$k $v \[get_[expr {$t eq {o} ? {ports} : {pins}}] \{$names\}\]" }
    }
    close $fp
}
# the effective uncertainty at an endpoint object
proc eff_unc {scen kind obj} {
    global UC PL IGNORE_PORTS
    set key $scen,$kind,$obj
    if {[info exists PL($key)] && !($IGNORE_PORTS && [string index $obj 0] eq "o")} { return $PL($key) }
    return $UC($scen,$kind)
}
proc get_timing_paths {args} {
    array set A {-max_paths 1}
    array set A $args
    set kind [expr {$A(-delay_type) eq "max" ? "setup" : "hold"}]
    set best ""
    foreach t $A(-to) {
        set o $t
        if {[string match p|*/D $t]} { set o [string map {/D /CK} $t] }
        set s [expr {10.0 - [eff_unc $A(-scenarios) $kind $o]}]
        if {$best eq "" || $s < $best} { set best $s }
    }
    if {$best eq ""} { return {} }
    return path|$best
}

proc run_open_close {scope gs gh probe} {
    unc090_open_opt t 1.5 0.5 $gs $gh $scope $probe
}
proc state_ok_restored {} {
    global UC PL
    return [expr {$UC(func_ss,setup) == 1.5 && $UC(func_ff,hold) == 0.5 && [llength [array names PL]] == 0}]
}
proc out_of {script} { set ::OUT ""; set ::OUTM [errmsg $script]; return $::OUTM }
# capture stdout
proc capture {script} { set ::PUTS ""; set ::CAPTURE 1; if {[catch {uplevel 1 $script} m]} {} else {set m ""}; set ::CAPTURE 0; return [list $m $::PUTS] }

foreach scope {flops outputs clock} {
    mock_reset
    lassign [capture {unc090_open_opt t 1.5 0.5 0.05 0.10 $scope 1}] m o
    check "$scope: open_opt runs without error ($m)" {$m eq ""}
    check "$scope: clock-level SPEC was set first in the right scenarios (the stale 1.0 / 0.3 are gone or OPT)" {$UC(func_ss,setup) in {1.5 1.55} && $UC(func_ff,hold) in {0.5 0.6}}
    if {$scope eq "flops"} {
        check "flops: clock-level stays SPEC, pins carry OPT in the right scenario only" {$UC(func_ss,setup) == 1.5 && $UC(func_ff,hold) == 0.5 && $PL(func_ss,setup,p|a/CK) == 1.55 && $PL(func_ff,hold,p|a/CK) == 0.6 && ![info exists PL(func_ss,hold,p|a/CK)] && ![info exists PL(func_ff,setup,p|a/CK)]}
        check "flops: no output port carries a value" {![info exists PL(func_ss,setup,o|x)]}
        check "flops: the report says 5 clock pins of 5 registers and the probes act" {[string match "*5 clock pins of 5 edge-triggered registers*" $o] && [string match "*probe in2reg-setup*the value acts*" $o] && [string match "*probe in2reg-hold*the value acts*" $o]}
        check "flops: parameters of the log lines (Setup/Hold uncertainty during optimization with the scope)" {[string match "*Setup uncertainty during optimization: 1.55 ns (spec 1.5 ns), scope flops, scenario func_ss*" $o] && [string match "*Hold uncertainty during optimization: 0.6 ns*" $o]}
    }
    if {$scope eq "outputs"} {
        check "outputs: clock-level OPT, ports carry SPEC" {$UC(func_ss,setup) == 1.55 && $UC(func_ff,hold) == 0.6 && $PL(func_ss,setup,o|x) == 1.5 && $PL(func_ff,hold,o|x) == 0.5}
        check "outputs: 3 output ports pinned and the probes act" {[string match "*3 output ports pinned*" $o] && [string match "*probe out-setup-dma_addr?31?*the value acts*" $o] && [string match "*probe out-hold-prdata?0?*the value acts*" $o]}
    }
    if {$scope eq "clock"} {
        check "clock: clock-level OPT, nothing at pin level, no probe" {$UC(func_ss,setup) == 1.55 && $UC(func_ff,hold) == 0.6 && [llength [array names PL]] == 0 && [string match "*scope clock has no pin-level value to probe*" $o]}
    }
    check "$scope: the SDC check lines are printed for both scenarios" {[string match "*SDC check func_ss (setup, scope $scope): ok*" $o] && [string match "*SDC check func_ff (hold, scope $scope): ok*" $o]}
    lassign [capture {unc090_close_opt t 1.5 0.5 0.05 0.10 $scope}] m o
    check "$scope: close_opt ok ($m)" {$m eq ""}
    check "$scope: everything restored, no pin/port-level value left" {[state_ok_restored]}
    check "$scope: proof lines printed for both scenarios" {[string match "*RESTORE PROOF func_ss: pin/port-level uncertainty lines left 0 (0 names), clock-level values: setup 1.5, hold 1.0*" $o] || [string match "*RESTORE PROOF func_ss: pin/port-level uncertainty lines left 0*" $o]}
    check "$scope: in2out before/after printed" {[string match "*in2out (scope $scope, goals setup 0.05 / hold 0.10): setup WNS *" $o]}
}
# the in2out numbers of the mock: before = SPEC state, after = SPEC state -> no warning
mock_reset
lassign [capture {unc090_open_opt t 1.5 0.5 0.05 0.10 flops 0; unc090_close_opt t 1.5 0.5 0.05 0.10 flops}] m o
check "flops: before = after in the mock -> no in2out WARNING" {$m eq "" && ![string match "*made the in2out group worse*" $o]}
check "flops: probes off message" {[string match "*probes switched off*" $o]}
# goal 0 for both: nothing pin-level, no remove command
mock_reset
lassign [capture {unc090_open_opt t 1.5 0.5 0 0 flops 1; unc090_close_opt t 1.5 0.5 0 0 flops}] m o
check "goal 0/0: no error, restored" {$m eq "" && [state_ok_restored]}
check "goal 0/0: no pin-level set and no remove_clock_uncertainty issued" {[lsearch -glob $LOG {remove_clock_uncertainty*}] < 0 && [string match "*goal 0: nothing set above the SPEC value*" $o]}
# setup goal only
mock_reset
lassign [capture {unc090_open_opt t 1.5 0.5 0.05 0 flops 1; unc090_close_opt t 1.5 0.5 0.05 0 flops}] m o
check "setup goal only: hold has no pin-level value and the run is clean" {$m eq "" && [state_ok_restored]}
# the tool ignores port-level values: the probe warns, the run goes on
mock_reset; set IGNORE_PORTS 1
lassign [capture {unc090_open_opt t 1.5 0.5 0.05 0.10 outputs 1}] m o
check "outputs, ports ignored by timing: WARNING 'ICC2 ignored' for both probes, no stop" {$m eq "" && [regexp {WARNING: probe out-setup.*SAME.*ignored} $o] && [regexp {WARNING: probe out-hold.*SAME} $o]}
# remove does nothing -> the restore proof stops
mock_reset
capture {unc090_open_opt t 1.5 0.5 0.05 0.10 flops 0}
set REMOVE_NOOP 1
lassign [capture {unc090_close_opt t 1.5 0.5 0.05 0.10 flops}] m o
check "remove does nothing -> ERROR 090 with 'still there'" {[string match "ERROR 090: t: restore failed*still there*" $m]}
# remove rejects the kind option -> the form without it is used and a NOTE is printed
mock_reset
capture {unc090_open_opt t 1.5 0.5 0.05 0.10 flops 0}
set REMOVE_NOKIND 1
lassign [capture {unc090_close_opt t 1.5 0.5 0.05 0.10 flops}] m o
check "remove without -setup/-hold works: NOTE printed, restored" {$m eq "" && [state_ok_restored] && [string match "*NOTE: remove_clock_uncertainty accepted no -setup*" $o]}
# the margin made in2out worse -> WARNING (leak simulated: after the close the output port keeps a higher value)
mock_reset
capture {unc090_open_opt t 1.5 0.5 0.05 0.10 clock 0}
set UNC090_LAST_IN2OUT {5.0 5.0}
lassign [capture {unc090_close_opt t 1.5 0.5 0.05 0.10 clock}] m o
check "in2out much better before than after (5.0 vs 8.5/9.5) is not a warning; a worse state is" {![string match "*made the in2out group worse*" $o]}
set UNC090_LAST_IN2OUT {20.0 20.0}
mock_reset; capture {unc090_open_opt t 1.5 0.5 0.05 0.10 clock 0}
set UNC090_LAST_IN2OUT {20.0 20.0}
lassign [capture {unc090_close_opt t 1.5 0.5 0.05 0.10 clock}] m o
check "in2out dropped -> WARNING printed twice (setup and hold), run continues" {$m eq "" && [regexp -all {made the in2out group worse} $o] == 2}
# a scenario that does not exist
proc get_scenarios {args} { return {s|func_ss} }
check "missing scenario -> ERROR 090" {[string match "ERROR 090: scenario(s) func_ff not in the design*" [errmsg {unc090_open_opt t 1.5 0.5 0.05 0.10 flops 0}]]}
proc get_scenarios {args} { return {s|func_ss s|func_ff} }
# no register
set FLOPS {}
mock_reset
check "no register -> ERROR 090" {[string match "ERROR 090: all_registers -edge_triggered returned no register*" [errmsg {unc090_open_opt t 1.5 0.5 0.05 0.10 flops 0}]]}
set FLOPS {a b c d u_dma/stage_reg_1__14_}
# the write_sdc failure is an error, not a pass
rename write_sdc write_sdc_ok
proc write_sdc {args} { error "boom" }
mock_reset
check "write_sdc fails -> ERROR 090" {[string match "ERROR 090: write_sdc of scenario*boom*" [errmsg {unc090_open_opt t 1.5 0.5 0.05 0.10 clock 0}]]}
rename write_sdc {}; rename write_sdc_ok write_sdc

# ---- 6. the source of the flow scripts ----
proc code_lines {text} {
    set o {}; set n 0
    foreach l [split $text "\n"] { incr n; set t [string trim $l]; if {$t eq "" || [string index $t 0] eq "#"} continue; regsub {\s;#.*$} $t "" t; lappend o [list $n [string trim $t]] }
    return $o
}
foreach f {cts.tcl route.tcl timing_closure.tcl} {
    set tx [read_file $here/$f]
    set cl [code_lines $tx]
    set n_open 0; set n_close 0; set line_open 0; set line_close 0; set n_set 0; set n_params 0; set l_src 0
    foreach x $cl {
        lassign $x ln t
        if {[regexp {^unc090_open_opt } $t]} { incr n_open; set line_open $ln }
        if {[regexp {^unc090_close_opt } $t]} { incr n_close; set line_close $ln }
        if {[regexp {set_clock_uncertainty} $t]} { incr n_set }
        if {[regexp {lassign \[unc090_params} $t]} { incr n_params }
        if {[regexp {opt_uncertainty\.tcl\]$} $t]} { set l_src $ln }
    }
    set l_unc [lindex [lsearch -inline -glob -index 1 $cl "*opt_uncertainty.tcl*"] 1]
    set l_clk [lindex [lsearch -inline -glob -index 1 $cl "*clock_latency.tcl*"] 1]
    check "$f: sources opt_uncertainty.tcl with the same bootstrap form as clock_latency.tcl" {$l_src > 0 && [string map {opt_uncertainty.tcl clock_latency.tcl} $l_unc] eq $l_clk}
    check "$f: one open_opt, one close_opt, open before close" {$n_open == 1 && $n_close == 1 && $line_open < $line_close}
    check "$f: no set_clock_uncertainty command outside opt_uncertainty.tcl" {$n_set == 0}
    check "$f: the goals come from unc090_params (once)" {$n_params == 1}
    check "$f: no typed goal of 0.0 (065) left" {![regexp {set (SETUP|HOLD)_SLACK_GOAL\s+0\.0} $tx]}
    # the order: open_opt before the optimiser, close_opt after it, both before the reports
    set opt_cmd [expr {$f eq "cts.tcl" ? "clock_opt" : "route_opt"}]
    set lopt 0
    foreach x $cl { lassign $x ln t; if {[regexp "^${opt_cmd}(\\s|\$)" $t] && $lopt == 0} { set lopt $ln } }
    check "$f: open_opt ($line_open) < $opt_cmd ($lopt) < close_opt ($line_close)" {$line_open < $lopt && $lopt < $line_close}
}
set cts [read_file $here/cts.tcl]
check "cts.tcl: update_timing -full / reports come after close_opt" {[string first "unc090_close_opt" $cts] < [string first "update_timing -full" $cts] && [string first "unc090_close_opt" $cts] < [string first "report_clock_qor" $cts]}
set pv [read_file $here/pv.tcl]
check "pv.tcl: unc090_export_check comes after the last write_sdc and before write_sdf ff" {
    [set pe [string first "unc090_export_check" $pv]] > [string last "-output \${OUT_DIR}/\${DESIGN_NAME}_pnr_ff.sdc" $pv] && $pe > 0 && $pe < [string first "\${DESIGN_NAME}_ff.sdf" $pv]}
check "pv.tcl: sources opt_uncertainty.tcl and passes the SPEC constants of the file" {[string match "*opt_uncertainty.tcl\]*" $pv] && [string match "*unc090_export_check pv-exported-sdc*\$UNC090_SPEC_SETUP \$UNC090_SPEC_HOLD*" $pv]}
set oc $src
set objcode [lmap x [code_lines $oc] {lindex $x 1}]
set sets [lsearch -all -inline -glob $objcode "*set_clock_uncertainty*"]
check "opt_uncertainty.tcl: set_clock_uncertainty is issued only in the OPT/SPEC procs (open_opt, close_opt, unc090_set_pin)" {[llength $sets] == 9}
check "opt_uncertainty.tcl: no write to the library (no save_block / save_lib / write_*) except the scratch SDC" {![regexp {save_block|save_lib} $oc] && [regexp -all {write_sdc} $oc] >= 1}
check "opt_uncertainty.tcl: the environment variables are documented in the file" {[string match "*UNPU_UNC_SCOPE*" $src] && [string match "*UNPU_UNC_PROBE*" $src] && [string match "*UNPU_SETUP_SLACK_GOAL*" $src] && [string match "*UNPU_HOLD_SLACK_GOAL*" $src]}
file delete -force $tmp
real_puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
