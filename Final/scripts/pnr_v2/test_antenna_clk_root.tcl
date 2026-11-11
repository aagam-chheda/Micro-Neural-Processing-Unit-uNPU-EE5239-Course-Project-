# ==============================================================================
# Test: test_antenna_clk_root.tcl (task 071)
# Run : tclsh pnr_v2/test_antenna_clk_root.tcl   (from the repository root; no ICC2 needed)
# Tests the pure-Tcl block of pnr_v2/antenna_clk_root.tcl (between "BEGIN PURE TCL 071" and "END PURE TCL 071"), which uses the pure block of
# pnr_v2/antenna_port_buffers.tcl (database parser, LEF parser, don't-use check). The polygon is the one quoted in task 071.
# ==============================================================================

set here [file dirname [file normalize [info script]]]
proc load_block {file tag} {
    set fp [open $file r]
    set src [read $fp]
    close $fp
    set b [string first "# ---- BEGIN PURE TCL $tag ----" $src]
    set e [string first "# ---- END PURE TCL $tag ----" $src]
    if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers $tag in $file"; exit 1 }
    uplevel #0 [string range $src $b $e]
}
load_block $here/antenna_port_buffers.tcl 068
load_block $here/antenna_clk_root.tcl 071

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc near {a b {tol 0.0005}} { return [expr {abs($a - $b) <= $tol}] }

# ------------------------------------------------------------------ 1. the polygon of task 071 in the Calibre database format
set dbtext "unpu_top 1000
AN.MTL.1.M3
1 1 1 Nov  9 16:00:00 2026
Rule File Pathname: ant.ctrl
(M3 area / GATE area) > 400 (M3 not connected to diode)
p 1 8
CN unpu_top c 1 0 0 1 0 0 0
407890 880570
880020 880570
880020 878130
885600 878130
885600 878410
880300 878410
880300 880850
407890 880850
"
set db [ant_parse_db $dbtext]
set polys [dict get $db polys]
check "one polygon" {[llength $polys] == 1}
set p [lindex $polys 0]
check "8 vertices parsed (the CN line is skipped)" {[llength [dict get $p xs]] == 8 && [dict get $p nv] == 8}
check "bbox" {[dict get $p bbox] eq "407.89 878.13 885.6 880.85"}
set per [ant071_perimeter [dict get $p xs] [dict get $p ys]]
puts "perimeter of the polygon: $per um"
# exact: 472.13 + 2.44 + 5.58 + 0.28 + 5.30 + 2.44 + 472.41 + 0.28
check "perimeter 960.86 um" {[near $per 960.86 1e-6]}
check "rectangle perimeter" {[near [ant071_perimeter {0 3 3 0} {0 0 2 2}] 10.0 1e-9]}
set need0 [ant071_needed_gate $per 0.54 400.0 1.0]
set need1 [ant071_needed_gate $per 0.54 400.0 1.10]
set needT [ant071_needed_gate $per 0.84 400.0 1.10]
puts "needed gate area: $need0 (no margin), $need1 (margin 1.10), TOP_M with margin $needT"
check "needed gate about 1.30 um^2" {[near $need0 1.297161 1e-5]}
check "needed gate with margin about 1.43 um^2" {[near $need1 1.426877 1e-5]}
check "TOP_M weight needs 2.22 um^2" {[near $needT 2.219 0.001]}
check "ratio with the old gate 0.19 is about 2,670" {[near [expr {$per * 0.54 / 0.194}] 2674.6 1.0]}

# ------------------------------------------------------------------ 2. the rule formula in the Calibre log text
set line "AN.MTL.1.M3 = NET AREA RATIO M3_no_dio M2 M1 GC_STI GATE > 400 \[PERIMETER(M3_no_dio)*0.54/AREA(GATE)\]"
set f [ant071_parse_rule_formula "other line\n$line\nnext line" AN.MTL.1.M3]
check "formula: weight 0.54, limit 400" {$f eq "0.54 400"}
check "formula: other rule not matched" {[ant071_parse_rule_formula $line AN.MTL.1.M2] eq ""}
check "formula: dots in the rule name are literal" {[ant071_parse_rule_formula $line AN+MTL.1.M3] eq ""}
check "formula: a different weight is read" {[ant071_parse_rule_formula "AN.MTL.1.MT = NET AREA RATIO MT_no_dio GATE > 400 \[PERIMETER(MT_no_dio)*0.84/AREA(GATE)\]" AN.MTL.1.MT] eq "0.84 400"}
check "formula: text without the rule" {[ant071_parse_rule_formula "nothing" AN.MTL.1.M3] eq ""}

# ------------------------------------------------------------------ 3. inverter choice among a table of cells
proc inv {name w h gate {extra ""}} {
    return "MACRO $name\n  SIZE $w BY $h ;\n  PIN I\n    DIRECTION INPUT ;\n    ANTENNAGATEAREA $gate LAYER M1 ;\n  END I\n  PIN ZN\n    DIRECTION OUTPUT ;\n    ANTENNADIFFAREA 1.0 LAYER M1 ;\n  END ZN\n  PIN VDD\n    DIRECTION INOUT ;\n    USE POWER ;\n  END VDD\n$extra\nEND $name\n"
}
set lef ""
append lef [inv invold 1.12 5.6 0.194]          ;# the cell now in the design
append lef [inv inva 1.12 5.6 0.108]
append lef [inv invb 2.24 5.6 1.2]              ;# gate below the need 1.4269
append lef [inv invc 4.48 5.6 1.5]              ;# first that reaches it
append lef [inv invd 5.60 5.6 1.6]
append lef [inv inve 8.96 5.6 2.5]
append lef [inv slnht3 3.36 5.6 1.5]            ;# on the don't-use list (pattern slnht*)
append lef [inv invh 3.36 5.0 1.5]              ;# other height
append lef [inv invc2 5.04 5.6 1.5]             ;# same gate as invc, larger footprint
append lef [inv invc3 4.48 5.6 1.5]             ;# same gate and same footprint as invc: the name decides
# two inputs
append lef "MACRO nand2\n  SIZE 3.36 BY 5.6 ;\n  PIN A1\n    DIRECTION INPUT ;\n    ANTENNAGATEAREA 2.0 LAYER M1 ;\n  END A1\n  PIN A2\n    DIRECTION INPUT ;\n    ANTENNAGATEAREA 2.0 LAYER M1 ;\n  END A2\n  PIN ZN\n    DIRECTION OUTPUT ;\n    ANTENNADIFFAREA 1.0 LAYER M1 ;\n  END ZN\nEND nand2\n"
# other pin names (A / Y)
append lef "MACRO invy\n  SIZE 3.36 BY 5.6 ;\n  PIN A\n    DIRECTION INPUT ;\n    ANTENNAGATEAREA 1.8 LAYER M1 ;\n  END A\n  PIN Y\n    DIRECTION OUTPUT ;\n    ANTENNADIFFAREA 1.0 LAYER M1 ;\n  END Y\nEND invy\n"
set cells [ant_parse_lef $lef]
set names {invold inva invb invc invd inve slnht3 invh invc2 invc3 nand2 invy adiode nolef}
set DONT {slnht* skbrb* slbhb* slnhn* slnln* mx08d* adiode bh01d1 cload1}
set rows [ant071_eval_inverters $cells $names $DONT $need1 {I ZN} 5.6]
proc row {rows name} { foreach r $rows { if {[dict get $r name] eq $name} { return $r } }; error "no row $name" }
check "invold fails (b): its gate 0.194 is below the need" {[dict get [row $rows invold] verdict] eq "FAIL" && [string match "*(b)*" [dict get [row $rows invold] why]]}
check "inva fails (b)" {[dict get [row $rows inva] verdict] eq "FAIL"}
check "invb fails (b): 1.2 < 1.4269" {[dict get [row $rows invb] verdict] eq "FAIL" && [string match "*(b)*" [dict get [row $rows invb] why]]}
check "invc passes" {[dict get [row $rows invc] verdict] eq "PASS"}
check "slnht3 rejected by (c) the don't-use list" {[dict get [row $rows slnht3] verdict] eq "FAIL" && [string match "*(c)*slnht*" [dict get [row $rows slnht3] why]]}
check "adiode (not in the LEF table) rejected" {[dict get [row $rows adiode] verdict] eq "FAIL"}
check "two inputs rejected by (a)" {[dict get [row $rows nand2] verdict] eq "FAIL" && [string match "*(a) 2 signal inputs*" [dict get [row $rows nand2] why]]}
check "different pin names rejected by (d)" {[dict get [row $rows invy] verdict] eq "FAIL" && [string match "*(d)*" [dict get [row $rows invy] why]]}
check "different height rejected by (e)" {[dict get [row $rows invh] verdict] eq "FAIL" && [string match "*(e)*" [dict get [row $rows invh] why]]}
check "cell not in the LEF rejected" {[dict get [row $rows nolef] verdict] eq "FAIL" && [string match "*no MACRO*" [dict get [row $rows nolef] why]]}
check "choice: smallest gate above the need, then smaller footprint, then name -> invc" {[ant071_pick_inverter $rows] eq "invc"}
# without invc and invc3: the footprint decides between the gate-1.5 cells, then the gate decides
set rows2 [ant071_eval_inverters $cells {invd inve invc2 invc} $DONT $need1 {I ZN} 5.6]
check "equal gate: smaller footprint wins (invc 25.1 < invc2 28.2)" {[ant071_pick_inverter $rows2] eq "invc"}
set rows3 [ant071_eval_inverters $cells {invc3 invc2 invd} $DONT $need1 {I ZN} 5.6]
check "equal gate and footprint of invc3 alone beats the larger invc2" {[ant071_pick_inverter $rows3] eq "invc3"}
set rows3b [ant071_eval_inverters $cells {invc3 invc} $DONT $need1 {I ZN} 5.6]
check "equal gate and footprint: the name decides (invc before invc3)" {[ant071_pick_inverter $rows3b] eq "invc"}
check "only larger cells left -> the smallest gate among them" {[ant071_pick_inverter [ant071_eval_inverters $cells {invd inve} $DONT $need1 {I ZN} 5.6]] eq "invd"}
# the error case: nothing reaches the need
set rows4 [ant071_eval_inverters $cells $names $DONT 5.0 {I ZN} 5.6]
check "nothing reaches 5.0 um^2 -> no pick" {[ant071_pick_inverter $rows4] eq ""}
set largest [ant071_largest_gates $rows4 5]
check "five names are listed, largest gate first (inve 2.5)" {[llength $largest] == 5 && [lindex $largest 0] eq "inve 2.500"}

# ------------------------------------------------------------------ 4. room for the larger cell (filler rows {name x0 y0 x1 y1 orient})
proc fl {name x0 y0 x1 {ori MX}} { return [list $name $x0 $y0 $x1 [expr {$y0 + 5.6}] $ori] }
# the root at x 408.55..409.67 (1.12 wide) in row y=862.4; fillers on both sides
set rows5 [list [fl a 409.67 862.4 414.71] [fl b 414.71 862.4 419.75] [fl c 419.75 862.4 421.43] [fl l1 403.51 862.4 408.55] [fl other 420.0 868.0 425.0]]
# new width 4.48: extra 3.36 -> [409.67, 413.03] covered by the filler a
set pl [ant071_grow_plan $rows5 862.4 408.55 409.67 4.48]
check "grow to the right over one filler" {[dict get $pl mode] eq "right" && [dict get $pl names] eq "a" && [near [dict get $pl origin] 408.55]}
set pl [ant071_grow_plan $rows5 862.4 408.55 409.67 11.2]
check "a wider cell takes two fillers on the right" {[dict get $pl mode] eq "right" && [dict get $pl names] eq "a b"}
set pl [ant071_grow_plan $rows5 862.4 408.55 409.67 1.12]
check "same width: nothing to do" {[dict get $pl mode] eq "none" && [dict get $pl names] eq ""}
set pl [ant071_grow_plan $rows5 862.4 408.55 409.67 0.56]
check "narrower: nothing to do" {[dict get $pl mode] eq "none"}
# right side blocked by a real cell (a gap between the fillers) -> left
set rows6 [list [fl a 409.67 862.4 410.23] [fl l1 403.51 862.4 408.55]]
set pl [ant071_grow_plan $rows6 862.4 408.55 409.67 4.48]
check "right blocked, left free -> left, origin shifted by the extra width" {[dict get $pl mode] eq "left" && [near [dict get $pl origin] [expr {408.55 - 3.36}]] && [dict get $pl names] eq "l1"}
# gap on the left too
set rows7 [list [fl a 409.67 862.4 410.23] [fl l1 407.0 862.4 408.55]]
set pl [ant071_grow_plan $rows7 862.4 408.55 409.67 4.48]
check "both sides blocked -> FAIL with the reason" {[dict get $pl mode] eq "FAIL" && [string match "*right side not covered*left side*" [dict get $pl why]]}
# fillers of another row do not count
set rows8 [list [fl a 409.67 868.0 414.71]]
check "fillers of another row do not count" {[dict get [ant071_grow_plan $rows8 862.4 408.55 409.67 4.48] mode] eq "FAIL"}
# cover details
lassign [ant071_cover $rows5 862.4 409.67 413.03] ok names unc
check "cover: ok" {$ok == 1 && $names eq "a" && $unc eq ""}
lassign [ant071_cover $rows6 862.4 409.67 413.03] ok names unc
check "cover: gap reported at x=410.23" {$ok == 0 && [near $unc 410.23]}
lassign [ant071_cover {} 862.4 409.67 413.03] ok names unc
check "cover: no fillers" {$ok == 0 && [near $unc 409.67]}
# a filler that is wider than needed is listed whole
set rows9 [list [fl w 409.67 862.4 418.71]]
check "wide filler removed whole" {[dict get [ant071_grow_plan $rows9 862.4 408.55 409.67 4.48] names] eq "w"}

# ------------------------------------------------------------------ 5. OK / WORSE decisions
proc tbl {skew setup hold trans cap} { return [dict create skew $skew setup $setup hold $hold trans $trans cap $cap] }
set b [tbl 0.31 -0.10 -0.01 0 0]
lassign [ant071_verdict $b [tbl 0.31 -0.10 -0.01 0 0] 0.05 0.02] v r
check "identical -> OK" {$v eq "OK" && $r eq ""}
lassign [ant071_verdict $b [tbl 0.34 -0.11 -0.02 0 0] 0.05 0.02] v r
check "small changes inside the tolerances -> OK" {$v eq "OK"}
lassign [ant071_verdict $b [tbl 0.20 -0.05 0.00 0 0] 0.05 0.02] v r
check "better everywhere -> OK" {$v eq "OK"}
lassign [ant071_verdict $b [tbl 0.37 -0.10 -0.01 0 0] 0.05 0.02] v r
check "skew +0.06 -> WORSE" {$v eq "WORSE" && [string match "*global skew*" [lindex $r 0]]}
lassign [ant071_verdict $b [tbl 0.31 -0.13 -0.01 0 0] 0.05 0.02] v r
check "setup WNS -0.03 worse -> WORSE" {$v eq "WORSE" && [string match "setup WNS*" [lindex $r 0]]}
lassign [ant071_verdict $b [tbl 0.31 -0.10 -0.04 0 0] 0.05 0.02] v r
check "hold WNS -0.03 worse -> WORSE" {$v eq "WORSE" && [string match "hold WNS*" [lindex $r 0]]}
lassign [ant071_verdict $b [tbl 0.31 -0.10 -0.01 2 0] 0.05 0.02] v r
check "a max-transition violation appears -> WORSE" {$v eq "WORSE" && [string match "max-transition*" [lindex $r 0]]}
lassign [ant071_verdict $b [tbl 0.31 -0.10 -0.01 0 1] 0.05 0.02] v r
check "a max-capacitance violation appears -> WORSE" {$v eq "WORSE" && [string match "max-capacitance*" [lindex $r 0]]}
lassign [ant071_verdict $b [tbl 0.40 -0.20 -0.01 0 3] 0.05 0.02] v r
check "several trips are all listed" {$v eq "WORSE" && [llength $r] == 3}
lassign [ant071_verdict [tbl 0.31 -0.10 -0.01 3 0] [tbl 0.31 -0.10 -0.01 3 0] 0.05 0.02] v r
check "existing violations that do not grow -> OK" {$v eq "OK"}
lassign [ant071_verdict [tbl "" -0.10 -0.01 0 0] [tbl "" -0.10 -0.01 0 0] 0.05 0.02] v r
check "unreadable skew -> UNKNOWN, not OK" {$v eq "UNKNOWN" && [string match "*skew*" $r]}
lassign [ant071_verdict [tbl "" -0.10 -0.01 0 0] [tbl "" -0.20 -0.01 0 0] 0.05 0.02] v r
check "a readable trip still gives WORSE when another metric is unreadable" {$v eq "WORSE"}
lassign [ant071_verdict $b [tbl 0.31 -0.10 n/a 0 0] 0.05 0.02] v r
check "a text value is unreadable" {$v eq "UNKNOWN" && [string match "*hold*" $r]}
lassign [ant071_verdict $b [tbl 0.36 -0.10 -0.01 0 0] 0.05 0.02] v r
check "skew +0.05 exactly is inside the tolerance" {$v eq "OK"}

# ------------------------------------------------------------------ 6. report parser guesses and pin maps
set cq "Clock Tree Summary
  Clock Tree Sinks            2465
  Corner default Global Skew  0.31
  Corner ff      Global Skew  0.12
  Max transition DRC violations: 0
  Max capacitance DRC violations: 2
"
set q [ant071_parse_cqor $cq]
check "cqor: the largest global skew" {[dict get $q skew] eq "0.31"}
check "cqor: transition and capacitance counts" {[dict get $q trans] == 0 && [dict get $q cap] == 2}
check "cqor: sinks" {[dict get $q sinks] == 2465}
check "cqor: unreadable text gives empty values" {[dict get [ant071_parse_cqor "nothing here"] skew] eq ""}
set pb {{I clk} {ZN ZCTSNET_1} {VDD VDD} {VSS VSS}}
check "pins: identical" {[ant071_diff_pins $pb $pb] eq ""}
check "pins: a net changed" {[llength [ant071_diff_pins $pb {{I clk} {ZN other} {VDD VDD} {VSS VSS}}]] == 1}
check "pins: a pin gone and a pin new" {[llength [ant071_diff_pins $pb {{I clk} {ZN ZCTSNET_1} {VDD VDD} {VSS VSS} {EN x}}]] == 1 && [llength [ant071_diff_pins $pb {{I clk} {VDD VDD} {VSS VSS}}]] == 1}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
