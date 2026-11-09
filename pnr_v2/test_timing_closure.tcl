# ==============================================================================
# Test: test_timing_closure.tcl (task 072)
# Run : tclsh pnr_v2/test_timing_closure.tcl   (from the repository root; no ICC2 needed)
# Tests the pure-Tcl block of pnr_v2/timing_closure.tcl (pass-loop decision, verdict, protected-cell snapshot comparison, filler check)
# and compares the settings copied from pnr_v2/route.tcl with route.tcl itself, line by line (it also prints the option table).
# ==============================================================================

set here [file dirname [file normalize [info script]]]
proc read_file {f} { set fp [open $f r]; set s [read $fp]; close $fp; return $s }
set src [read_file $here/timing_closure.tcl]
set b [string first "# ---- BEGIN PURE TCL 072 ----" $src]
set e [string first "# ---- END PURE TCL 072 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc D {setup hold} { return [dict create setup $setup hold $hold] }

# ------------------------------------------------------------------ 1. pass-loop decision (eps 0.001, at most 3 passes)
lassign [ant072_pass_decision 1 3 [D -0.10 -0.04] [D 0.0 0.0] 0.001] a w
check "closed after pass 1 -> stop" {$a eq "stop" && [string match "closed after pass 1*" $w]}
lassign [ant072_pass_decision 1 3 [D -0.10 -0.04] [D 0.02 0.01] 0.001] a w
check "both positive -> stop (closed)" {$a eq "stop" && [string match "closed*" $w]}
lassign [ant072_pass_decision 1 3 [D -0.10 -0.04] [D -0.05 -0.04] 0.001] a w
check "setup improved by 0.05 -> continue" {$a eq "continue"}
lassign [ant072_pass_decision 1 3 [D -0.10 -0.04] [D -0.10 -0.03] 0.001] a w
check "only hold improved by 0.01 -> continue" {$a eq "continue"}
lassign [ant072_pass_decision 2 3 [D -0.05 -0.04] [D -0.05 -0.04] 0.001] a w
check "no change -> stop, reason says so" {$a eq "stop" && [string match "*improved neither WNS by more than 0.001*" $w]}
lassign [ant072_pass_decision 2 3 [D -0.05 -0.04] [D -0.0495 -0.0395] 0.001] a w
check "improvement of 0.0005 is below eps -> stop" {$a eq "stop"}
lassign [ant072_pass_decision 2 3 [D -0.05 -0.04] [D -0.0485 -0.04] 0.001] a w
check "improvement of 0.0015 is above eps -> continue" {$a eq "continue"}
lassign [ant072_pass_decision 3 3 [D -0.05 -0.04] [D -0.02 -0.01] 0.001] a w
check "improving at the maximum pass -> stop (maximum)" {$a eq "stop" && [string match "maximum of 3 passes*" $w]}
lassign [ant072_pass_decision 1 3 [D -0.10 -0.04] [D -0.12 -0.05] 0.001] a w
check "got worse -> stop (no improvement)" {$a eq "stop"}
lassign [ant072_pass_decision 1 3 [D -0.10 -0.04] [D "" -0.04] 0.001] a w
check "unreadable setup -> stop" {$a eq "stop" && [string match "*setup WNS could not be read*" $w]}
lassign [ant072_pass_decision 1 3 [D -0.10 -0.04] [D 0.0 n/a] 0.001] a w
check "unreadable hold -> stop" {$a eq "stop" && [string match "*hold WNS could not be read*" $w]}
lassign [ant072_pass_decision 1 1 [D -0.10 -0.04] [D 0.0 0.0] 0.001] a w
check "closed wins over the maximum" {[string match "closed*" $w]}
lassign [ant072_pass_decision 1 3 [D 0.2 -0.04] [D 0.2 -0.03] 0.001] a w
check "positive setup slack, hold improving -> continue" {$a eq "continue"}

# ------------------------------------------------------------------ 2. verdict (the real numbers: setup -0.10, hold -0.04 before)
set before [D -0.10 -0.04]
lassign [ant072_verdict $before [D 0.0 0.0] 0.005 0.001] v w
check "both closed -> CLOSED" {$v eq "CLOSED"}
lassign [ant072_verdict $before [D 0.003 0.010] 0.005 0.001] v w
check "both positive -> CLOSED" {$v eq "CLOSED"}
lassign [ant072_verdict $before [D 0.0 -0.01] 0.005 0.001] v w
check "setup closed, hold -0.01 -> IMPROVED" {$v eq "IMPROVED" && [string match "*setup WNS*hold WNS*" $w]}
lassign [ant072_verdict $before [D -0.10 -0.03] 0.005 0.001] v w
check "only hold improved -> IMPROVED" {$v eq "IMPROVED"}
lassign [ant072_verdict $before [D -0.12 -0.04] 0.005 0.001] v w
check "setup dropped by 0.02 -> WORSE" {$v eq "WORSE" && [string match "setup WNS*" $w]}
lassign [ant072_verdict $before [D 0.0 -0.05] 0.005 0.001] v w
check "setup closed but hold dropped by 0.01 -> WORSE (a drop is not hidden by an improvement)" {$v eq "WORSE" && [string match "hold WNS*" $w]}
lassign [ant072_verdict $before [D -0.105 -0.04] 0.005 0.001] v w
check "a drop of exactly 0.005 is inside the tolerance -> UNCHANGED" {$v eq "UNCHANGED"}
lassign [ant072_verdict $before [D -0.1051 -0.04] 0.005 0.001] v w
check "a drop of 0.0051 -> WORSE" {$v eq "WORSE"}
lassign [ant072_verdict $before $before 0.005 0.001] v w
check "identical -> UNCHANGED" {$v eq "UNCHANGED"}
lassign [ant072_verdict $before [D "" 0.0] 0.005 0.001] v w
check "unreadable after -> UNKNOWN" {$v eq "UNKNOWN" && [string match "*setup WNS could not be read*" $w]}
lassign [ant072_verdict [D -0.1 n/a] [D 0.0 0.0] 0.005 0.001] v w
check "unreadable before -> UNKNOWN, never CLOSED" {$v eq "UNKNOWN"}
lassign [ant072_verdict [D 0.3 -0.04] [D 0.1 -0.04] 0.005 0.001] v w
check "positive slack that shrinks is not a drop (WNS counts 0)" {$v eq "UNCHANGED"}
lassign [ant072_verdict [D 0.3 -0.04] [D 0.1 -0.03] 0.005 0.001] v w
check "positive setup slack shrinking, hold improving -> IMPROVED" {$v eq "IMPROVED"}
lassign [ant072_verdict [D -0.04 -0.04] [D 0.5 0.2] 0.005 0.001] v w
check "closed with margin" {$v eq "CLOSED"}

# ------------------------------------------------------------------ 3. protected cells: snapshot comparison
proc snap {name ref x y ori pins} { return [dict create name $name ref $ref x $x y $y ori $ori pins $pins] }
set pb {{I pwdata[7]} {Z antbuf_pwdata_7__13_n} {VDD VDD} {VSS VSS}}
set s0 [list [snap antbuf_pwdata_7__13 buffd1 863.36 630.4 MX $pb] [snap ZCTSINV_1 inv0d4 408.55 862.4 MX {{I clk} {ZN n1} {VDD VDD} {VSS VSS}}]]
check "identical snapshots -> no difference" {[ant072_snapshot_diff $s0 $s0] eq ""}
set s1 [list [snap antbuf_pwdata_7__13 buffd1 863.3605 630.4005 MX $pb] [lindex $s0 1]]
check "an origin that moved by 0.0005 is inside the tolerance" {[ant072_snapshot_diff $s0 $s1] eq ""}
set s1 [list [snap antbuf_pwdata_7__13 buffd2 863.36 630.4 MX $pb] [lindex $s0 1]]
set d [ant072_snapshot_diff $s0 $s1]
check "changed reference detected" {[llength $d] == 1 && [string match "*reference buffd1 -> buffd2" [lindex $d 0]]}
set s1 [list [snap antbuf_pwdata_7__13 buffd1 864.48 630.4 MX $pb] [lindex $s0 1]]
set d [ant072_snapshot_diff $s0 $s1]
check "moved origin detected" {[llength $d] == 1 && [string match "*origin*" [lindex $d 0]]}
set s1 [list [snap antbuf_pwdata_7__13 buffd1 863.36 640.0 MX $pb] [lindex $s0 1]]
check "moved in y detected" {[llength [ant072_snapshot_diff $s0 $s1]] == 1}
set s1 [list [snap antbuf_pwdata_7__13 buffd1 863.36 630.4 N $pb] [lindex $s0 1]]
set d [ant072_snapshot_diff $s0 $s1]
check "changed orientation detected" {[llength $d] == 1 && [string match "*orientation MX -> N" [lindex $d 0]]}
set s1 [list [snap antbuf_pwdata_7__13 buffd1 863.36 630.4 MX {{I pwdata[7]} {Z other_net} {VDD VDD} {VSS VSS}}] [lindex $s0 1]]
set d [ant072_snapshot_diff $s0 $s1]
check "changed connection detected" {[llength $d] == 1 && [string match "*pin Z net antbuf_pwdata_7__13_n -> other_net" [lindex $d 0]]}
set s1 [list [snap antbuf_pwdata_7__13 buffd1 863.36 630.4 MX {{I pwdata[7]} {VDD VDD} {VSS VSS}}] [lindex $s0 1]]
check "a pin that is gone is detected" {[string match "*pin Z is gone*" [lindex [ant072_snapshot_diff $s0 $s1] 0]]}
set s1 [list [snap antbuf_pwdata_7__13 buffd1 863.36 630.4 MX [concat $pb {{EN x}}]] [lindex $s0 1]]
check "a new pin is detected" {[string match "*new pin EN*" [lindex [ant072_snapshot_diff $s0 $s1] 0]]}
check "a cell that is gone is detected" {[string match "*cell is gone" [lindex [ant072_snapshot_diff $s0 [list [lindex $s0 1]]] 0]]}
set s1 [list [snap antbuf_pwdata_7__13 buffd2 864.48 630.4 N {{I x} {Z y}}] [snap ZCTSINV_1 inv0d2 408.55 862.4 MX {{I clk} {ZN n1} {VDD VDD} {VSS VSS}}]]
check "several changes in two cells are all listed" {[llength [ant072_snapshot_diff $s0 $s1]] >= 6}
check "the root's reference change is detected" {[string match "ZCTSINV_1: reference inv0d4 -> inv0d2" [lindex [ant072_snapshot_diff $s0 [list [lindex $s0 0] [snap ZCTSINV_1 inv0d2 408.55 862.4 MX {{I clk} {ZN n1} {VDD VDD} {VSS VSS}}]]] 0]]}
check "a snapshot of a missing cell (ref '') differs" {[llength [ant072_snapshot_diff $s0 [list [snap antbuf_pwdata_7__13 "" 1e9 1e9 "" {}] [lindex $s0 1]]]] >= 3}

# ------------------------------------------------------------------ 4. filler check
lassign [ant072_filler_check 21600 21600 90000 90000 0 1.0] ok m
check "same count -> ok" {$ok == 1 && [string match "*within 1.0 percent*" $m]}
lassign [ant072_filler_check 21600 21500 90000 89900 0 1.0] ok m
check "-100 fillers (0.46 percent) -> ok" {$ok == 1}
lassign [ant072_filler_check 21600 21300 90000 89000 0 1.0] ok m
check "-300 fillers (1.4 percent) and the sites are gone without cells added -> not ok" {$ok == 0 && [string match "*does not explain*" $m]}
lassign [ant072_filler_check 21600 21300 90000 89000 1000 1.0] ok m
check "-300 fillers, 1000 sites taken by added cells -> explained by the site balance" {$ok == 1 && [string match "*explained by the site balance*" $m]}
lassign [ant072_filler_check 21600 22000 90000 90000 0 1.0] ok m
check "more fillers, sites equal (other filler sizes) -> explained" {$ok == 1 && [string match "*explained*" $m]}
lassign [ant072_filler_check 0 100 0 500 0 1.0] ok m
check "no filler before -> not ok" {$ok == 0}

# ------------------------------------------------------------------ 5. the settings copied from route.tcl are identical to route.tcl (line by line, in order)
set rt [split [read_file $here/route.tcl] "\n"]
set tc [split $src "\n"]
proc trimmed {lines} { set o {}; foreach l $lines { set t [string trim [regsub {\s+;# 072.*$} $l ""]]; if {$t ne "" && ![string match "#*" $t]} { lappend o $t } }; return $o }
set tcl_t [trimmed $tc]
set ranges {{36 36} {42 57} {59 83} {85 132} {142 143} {147 152} {158 192}}
set ptr 0
foreach r $ranges {
    lassign $r a z
    set want [trimmed [lrange $rt [expr {$a - 1}] [expr {$z - 1}]]]
    set ok 1
    set missing ""
    foreach w $want {
        set found -1
        for {set i $ptr} {$i < [llength $tcl_t]} {incr i} { if {[lindex $tcl_t $i] eq $w} { set found $i; break } }
        if {$found < 0} { set ok 0; set missing $w; break }
        set ptr [expr {$found + 1}]
    }
    check "route.tcl lines $a-$z appear in timing_closure.tcl, in order ($missing)" {$ok}
}
# values
foreach {name want} {SPEC_SETUP_UNC 1.5 SETUP_SLACK_GOAL 0.0 SPEC_HOLD_UNC 0.5 HOLD_SLACK_GOAL 0.0} {
    set found 0
    foreach l $tc { if {[regexp "^\\s*set $name\\s+(\[0-9.\]+)" $l -> v] && $v == $want} { set found 1 } }
    check "$name = $want as in route.tcl" {$found}
}
# the option table: every setting line of route.tcl that is copied, with its line number
puts "OPTION TABLE (route.tcl line, setting; all present verbatim in timing_closure.tcl):"
set i 0
foreach l $rt {
    incr i
    set t [string trim $l]
    if {[regexp {^(set_app_options|set_clock_uncertainty|set_scenario_status|set_ignored_layers|set_clock_routing_rules|set_lib_cell_purpose|set SPEC_|set OPT_|set SETUP_SLACK|set HOLD_SLACK|remove_antenna_rules|define_antenna|route_opt|legalize_placement|create_stdcell_fillers|route_detail|route_eco|connect_pg_net)} $t]} {
        if {$i >= 36 && $i <= 192} { puts [format "  route.tcl:%-4d %s" $i [string range $t 0 110]] }
    }
}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
