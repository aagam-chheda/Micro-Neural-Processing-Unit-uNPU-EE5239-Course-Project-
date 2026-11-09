# ==============================================================================
# Test: test_antenna_port_buffers.tcl (task 068)
# Run : tclsh pnr_v2/test_antenna_port_buffers.tcl   (from the repository root; no ICC2 needed)
# Tests the pure-Tcl part of pnr_v2/antenna_port_buffers.tcl (text between "BEGIN PURE TCL 068" and "END PURE TCL 068"):
#   database parser, polygon bbox / area / point-in-polygon, net identification (ranking and decision), LEF parser, buffer choice, helpers.
# The real Calibre database is read from ANT_DB_TEST; the expected bbox values below were computed by a SEPARATE implementation (Python) from the
# same file, not by the code under test.
# ==============================================================================

set here [file dirname [file normalize [info script]]]
set ANT_DB_TEST "/home/aagam_chheda/server_pull/calibre/run1/ant/unpu_top.ant.db"
set DRC_DB_TEST "/home/aagam_chheda/server_pull/calibre/run1/drc/unpu_top.drc.db"

set fp [open $here/antenna_port_buffers.tcl r]
set src [read $fp]
close $fp
set b [string first "# ---- BEGIN PURE TCL 068 ----" $src]
set e [string first "# ---- END PURE TCL 068 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc near {a b {tol 0.0005}} { return [expr {abs($a - $b) <= $tol}] }
proc bbox_near {a b} {
    foreach x $a y $b { if {![near $x $y]} { return 0 } }
    return 1
}
proc must_error {script} { return [catch {uplevel 1 $script}] }

# ------------------------------------------------------------------ 1. the real antenna database
if {![file exists $ANT_DB_TEST]} { puts "FAIL $ANT_DB_TEST not found"; exit 1 }
set fp [open $ANT_DB_TEST r]
set db [ant_parse_db [read $fp]]
close $fp
set polys [dict get $db polys]
check "top cell" {[dict get $db top] eq "unpu_top"}
check "database unit" {[dict get $db dbu] == 1000}
check "46 polygons" {[llength $polys] == 46}
array set cnt {}
foreach p $polys { set r [dict get $p rule]; if {![info exists cnt($r)]} { set cnt($r) 0 }; incr cnt($r) }
check "rule AN.MTL.1.M2 = 9"  {$cnt(AN.MTL.1.M2) == 9}
check "rule AN.MTL.1.M3 = 13" {$cnt(AN.MTL.1.M3) == 13}
check "rule AN.MTL.1.MT = 24" {$cnt(AN.MTL.1.MT) == 24}
check "three rules only" {[llength [array names cnt]] == 3}
# every polygon has as many vertices as declared (the CN line must not eat one)
set allv 1
foreach p $polys { if {[llength [dict get $p xs]] != [dict get $p nv]} { set allv 0 } }
check "all vertex counts match" {$allv}

proc find_poly {polys rule id} {
    foreach p $polys { if {[dict get $p rule] eq $rule && [dict get $p id] == $id} { return $p } }
    error "polygon $rule #$id not found"
}
# expected bboxes: independent Python computation from the same file (um)
set expect {
    {AN.MTL.1.M2  1 830.74  413.49 831.02  413.87}
    {AN.MTL.1.M2  3 853.7   310.76 853.98  413.87}
    {AN.MTL.1.M2  4 852.805 426.12 856.22  431.74}
    {AN.MTL.1.M2  6 853.7   220.5  857.9   310.76}
    {AN.MTL.1.M2  9 884.5   326.26 884.78  352.83}
    {AN.MTL.1.M3  4 826.21  626.2  841.15  627.7}
    {AN.MTL.1.M3 11 407.89  878.13 885.6   880.85}
    {AN.MTL.1.M3 13 840.77  631.08 883.76  634.46}
    {AN.MTL.1.MT  1 401.65  790.16 402.19  884.03}
    {AN.MTL.1.MT  5 823.94  327.78 825.55  404.57}
    {AN.MTL.1.MT 23 881.01  280.2  881.55  326.26}
}
foreach row $expect {
    lassign $row rule id x0 y0 x1 y1
    set p [find_poly $polys $rule $id]
    check "bbox $rule #$id" {[bbox_near [dict get $p bbox] [list $x0 $y0 $x1 $y1]]}
}
# the first polygon of a rule has a `CN` line between the p line and its vertices: the 12-vertex MT #1 must keep all 12
check "MT #1 has 12 vertices" {[llength [dict get [find_poly $polys AN.MTL.1.MT 1] xs]] == 12}
# areas: the 4-vertex rectangle M2 #3 is 0.28 x 103.11; the 12-vertex polygon M2 #4 is smaller than its bbox
set p3 [find_poly $polys AN.MTL.1.M2 3]
check "area of rectangle M2 #3" {[near [ant_poly_area [dict get $p3 xs] [dict get $p3 ys]] [expr {0.28 * 103.11}] 0.001]}
set p4 [find_poly $polys AN.MTL.1.M2 4]
lassign [dict get $p4 bbox] a b c d
check "area of staircase M2 #4 < bbox area" {[ant_poly_area [dict get $p4 xs] [dict get $p4 ys]] < ($c - $a) * ($d - $b)}
# point in polygon on the staircase: inside the first leg, outside the notch of the bbox, boundary counts as inside
check "point inside staircase"   {[ant_pt_in_poly 853.0 431.6 [dict get $p4 xs] [dict get $p4 ys]]}
check "point in bbox corner but outside polygon" {![ant_pt_in_poly 856.0 431.5 [dict get $p4 xs] [dict get $p4 ys]]}
check "vertex counts as inside"  {[ant_pt_in_poly 852.805 431.46 [dict get $p4 xs] [dict get $p4 ys]]}

# the layers
check "rule M2 -> M2"      {[ant_rule_layer AN.MTL.1.M2] eq "M2"}
check "rule M3 -> M3"      {[ant_rule_layer AN.MTL.1.M3] eq "M3"}
check "rule MT -> TOP_M"   {[ant_rule_layer AN.MTL.1.MT] eq "TOP_M"}
check "rule AN.MTL.2.MT -> TOP_M" {[ant_rule_layer AN.MTL.2.MT] eq "TOP_M"}
check "via rule has no layer"     {[ant_rule_layer AN.VIA.1.V2] eq ""}

# the DRC database has the same format; its one marker is the M3.S.1 of task 068
if {[file exists $DRC_DB_TEST]} {
    set fp [open $DRC_DB_TEST r]
    set ddb [ant_parse_db [read $fp]]
    close $fp
    set dp [dict get $ddb polys]
    check "DRC db: one marker" {[llength $dp] == 1}
    check "DRC db: rule M3.S.1" {[dict get [lindex $dp 0] rule] eq "M3.S.1"}
    check "DRC db: marker near (127.8, 287.0)" {[bbox_near [dict get [lindex $dp 0] bbox] {127.76 286.99 127.89 287.37}]}
} else {
    puts "NOTE $DRC_DB_TEST not found, DRC database test skipped"
}

# ------------------------------------------------------------------ 2. parser errors
check "no header -> error" {[must_error {ant_parse_db "AN.MTL.1.M2\n9 9 2 Nov  9 14:22:57 2026\np 1 4\n0 0\n"}]}
check "empty file -> error" {[must_error {ant_parse_db ""}]}
check "truncated polygon -> error" {[must_error {ant_parse_db "unpu_top 1000\nAN.MTL.1.M2\n9 9 2 Nov  9 14:22:57 2026\np 1 4\n0 0\n1000 0\n"}]}
check "polygon with too few vertices before the next p -> error" {[must_error {ant_parse_db "unpu_top 1000\nAN.MTL.1.M2\n9 9 2 Nov  9 14:22:57 2026\np 1 4\n0 0\n1000 0\np 2 4\n0 0\n"}]}
check "polygon before a rule -> error" {[must_error {ant_parse_db "unpu_top 1000\np 1 4\n0 0\n1000 0\n1000 1000\n0 1000\n"}]}
set small [ant_parse_db "unpu_top 2000\nAN.MTL.1.M2\n1 1 1 Nov  9 14:22:57 2026\ntext line\np 7 4\nCN unpu_top c 1 0 0 1 0 0 0\n0 0\n2000 0\n2000 4000\n0 4000\n"]
check "other database unit is read" {[dict get $small dbu] == 2000}
check "CN line skipped, bbox in um" {[bbox_near [dict get [lindex [dict get $small polys] 0] bbox] {0 0 1 2}]}

# ------------------------------------------------------------------ 3. net identification
proc rect {net x0 y0 x1 y1} { return [list $net $x0 $y0 $x1 $y1] }
set pM2_3 [find_poly $polys AN.MTL.1.M2 3]          ;# 853.7,310.76 -> 853.98,413.87
# a: exact shape of the right net; a wrong net beside it
set r [ant_rank $pM2_3 [list [rect pwdata\[14\] 853.7 310.76 853.98 413.87] [rect other 853.98 310.76 854.3 413.87]]]
check "exact shape wins"    {[lindex [lindex $r 0] 0] eq "pwdata\[14\]" && [lindex [lindex $r 0] 1] == 3}
check "touching neighbour is not a candidate" {[llength $r] == 1}
lassign [ant_decide $r] st ch note
check "decision OK" {$st eq "OK" && $ch eq "pwdata\[14\]"}
# b: a longer shape contains the polygon bbox (tier 2); a net that only overlaps loses
set r [ant_rank $pM2_3 [list [rect netA 853.7 300.0 853.98 420.0] [rect netB 853.0 330.0 853.8 340.0]]]
check "contains beats overlap" {[lindex [lindex $r 0] 0] eq "netA" && [lindex [lindex $r 0] 1] == 2}
lassign [ant_decide $r] st ch note
check "decision OK (contains)" {$st eq "OK" && $ch eq "netA"}
# c: two nets both with an exact shape -> ambiguous, never guessed
set r [ant_rank $pM2_3 [list [rect netA 853.7 310.76 853.98 413.87] [rect netB 853.7 310.76 853.98 413.87]]]
lassign [ant_decide $r] st ch note
check "two exact nets -> AMBIGUOUS" {$st eq "AMBIGUOUS" && $ch eq ""}
# d: pieces of one net tile the polygon (no single shape has its bbox): the net with the larger cover wins
set r [ant_rank $pM2_3 [list [rect netA 853.7 310.76 853.98 360.0] [rect netA 853.7 360.0 853.98 413.87] [rect netB 853.7 410.0 853.98 413.0]]]
lassign [ant_decide $r] st ch note
check "tiled by pieces -> OK netA" {$st eq "OK" && $ch eq "netA"}
# e: only a sliver overlaps -> low cover, undecided
set r [ant_rank $pM2_3 [list [rect netB 853.7 310.76 853.98 320.0]]]
lassign [ant_decide $r] st ch note
check "sliver -> LOWCOVER" {$st eq "LOWCOVER" && $ch eq ""}
# f: nothing overlaps
set r [ant_rank $pM2_3 [list [rect netB 100 100 101 101]]]
lassign [ant_decide $r] st ch note
check "no overlap -> NONE" {$st eq "NONE" && $ch eq ""}
# g: staircase polygon: a shape in the bbox corner that is outside the polygon must not count
set r [ant_rank $p4 [list [rect netA 852.805 431.46 853.14 431.74] [rect netB 855.9 431.0 856.2 431.7]]]
check "shape outside the staircase is ignored" {[llength $r] == 1 && [lindex [lindex $r 0] 0] eq "netA"}
# h: a real case: the clk polygon M3 #11 is an L (478 um along y 880.57-880.85, a drop at x 880.02-880.3, a foot to x 885.6); clk shapes in 3 pieces;
# a decoy net crosses the bbox but not the polygon
set pclk [find_poly $polys AN.MTL.1.M3 11]
set r [ant_rank $pclk [list [rect clk 407.89 880.57 880.3 880.85] [rect clk 880.02 878.13 880.3 880.85] [rect clk 880.02 878.13 885.6 878.41] [rect pwdata\[7\] 700.0 800.0 700.3 879.0]]]
lassign [ant_decide $r] st ch note
check "clk polygon -> clk" {$st eq "OK" && $ch eq "clk"}
# i: tier beats score (a contains-shape of one net against a larger covered overlap of another)
set r [ant_rank $pM2_3 [list [rect netA 853.7 310.76 853.98 413.87] [rect netB 853.7 311.0 853.98 413.0]]]
check "exact tier first" {[lindex [lindex $r 0] 0] eq "netA"}

# ------------------------------------------------------------------ 4. antenna arithmetic
# gate 0.1944 um^2, M3 weight 0.54, limit 400: the largest tolerated perimeter is 144 um, i.e. wire length 72 - 0.28 um
check "ratio at 71.72 um is 400" {[near [ant_ratio 0.1944 71.72 0.28 0.54] 400.0 0.01]}
check "need_gate inverts ratio" {[near [ant_need_gate 71.72 0.28 0.54 400.0 1.0] 0.1944 0.0001]}
check "need_gate 30 um" {[near [ant_need_gate 30.0 0.28 0.54 400.0 1.0] 0.081756 0.0001]}
check "safety factor multiplies" {[near [ant_need_gate 30.0 0.28 0.54 400.0 2.0] 0.163512 0.0002]}
check "Manhattan" {[near [ant_manhattan 0 0 3 -4] 7.0]}

# ------------------------------------------------------------------ 5. LEF parser (the inv0d0 text is the real excerpt from the kit LEF, plus synthetic cells)
set lef {
MACRO inv0d0
    CLASS CORE ;
    FOREIGN inv0d0 0 0 ;
    SIZE 1.120 BY 5.600 ;
    SITE CoreSite ;
    PIN I
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.108  LAYER M1  ;
        PORT
        LAYER M1 ;
        RECT  0.130 2.790 0.460 3.200 ;
        END
    END I
    PIN ZN
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.505  LAYER M1  ;
        PORT
        LAYER M1 ;
        RECT  0.550 3.430 0.990 3.750 ;
        END
    END ZN
    PIN VDD
        DIRECTION INOUT ;
        USE POWER ;
        SHAPE ABUTMENT ;
        PORT
        LAYER M1 ;
        RECT  0.000 4.860 1.120 5.600 ;
        END
    END VDD
    PIN VSS
        DIRECTION INOUT ;
        USE GROUND ;
        PORT
        LAYER M1 ;
        RECT  0.000 0.000 1.120 0.740 ;
        END
    END VSS
    OBS
        LAYER M1 ;
        RECT 0 0 1 1 ;
    END
END inv0d0
MACRO bufa
    SIZE 2.240 BY 5.600 ;
    PIN I
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.200  LAYER M1  ;
    END I
    PIN Z
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.400  LAYER M1  ;
    END Z
    PIN VDD
        DIRECTION INOUT ;
        USE POWER ;
    END VDD
END bufa
MACRO bufb
    SIZE 3.360 BY 5.600 ;
    PIN I
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.300  LAYER M1  ;
    END I
    PIN Z
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.800  LAYER M1  ;
        ANTENNADIFFAREA 0.900  LAYER M2  ;
    END Z
END bufb
MACRO bufc
    SIZE 1.680 BY 5.600 ;
    PIN I
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.050  LAYER M1  ;
    END I
    PIN Z
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.300  LAYER M1  ;
    END Z
END bufc
MACRO bufd
    SIZE 1.680 BY 5.600 ;
    PIN I
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.250  LAYER M1  ;
    END I
    PIN Z
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.100  LAYER M1  ;
    END Z
END bufd
MACRO adiode
    SIZE 1.120 BY 5.600 ;
    PIN I
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.900  LAYER M1  ;
    END I
    PIN Z
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.925  LAYER M1  ;
    END Z
END adiode
MACRO slnht1
    SIZE 1.120 BY 5.600 ;
    PIN I
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.900  LAYER M1  ;
    END I
    PIN Z
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.925  LAYER M1  ;
    END Z
END slnht1
MACRO bufe
    SIZE 1.120 BY 5.600 ;
    PIN I1
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.900  LAYER M1  ;
    END I1
    PIN I2
        DIRECTION INPUT ;
        ANTENNAGATEAREA 0.900  LAYER M1  ;
    END I2
    PIN Z
        DIRECTION OUTPUT ;
        ANTENNADIFFAREA 0.925  LAYER M1  ;
    END Z
END bufe
}
set cells [ant_parse_lef $lef]
check "7+1 macros" {[dict size $cells] == 8}
check "inv0d0 size" {[dict get $cells inv0d0 w] == 1.120 && [dict get $cells inv0d0 h] == 5.600}
check "inv0d0 gate" {[dict get $cells inv0d0 pins I gate] eq "0.108"}
check "inv0d0 diff" {[dict get $cells inv0d0 pins ZN diff] eq "0.505"}
check "inv0d0 power pin use" {[dict get $cells inv0d0 pins VDD use] eq "POWER"}
check "OBS block does not end the macro" {[dict exists $cells bufa]}
check "two diff entries kept" {[dict get $cells bufb pins Z diff] eq "0.800 0.900"}

set names {bufa bufb bufc bufd adiode slnht1 bufe nolef}
set need [ant_need_gate 30.0 0.28 0.54 400.0 1.0]      ;# 0.0819
set DONT {slnht* skbrb* slbhb* slnhn* slnln* mx08d* adiode bh01d1 cload1}
set rows [ant_eval_buffers $cells $names $DONT $need 0.202]
proc row {rows name} { foreach r $rows { if {[dict get $r name] eq $name} { return $r } }; error "no row $name" }
check "bufa passes"   {[dict get [row $rows bufa] verdict] eq "PASS"}
check "bufb passes (smallest listed diffusion 0.8)" {[dict get [row $rows bufb] verdict] eq "PASS" && [near [dict get [row $rows bufb] diff] 0.8]}
check "bufc fails (b) gate" {[dict get [row $rows bufc] verdict] eq "FAIL" && [string match "*(b)*" [dict get [row $rows bufc] why]]}
check "bufd fails (a) diffusion" {[dict get [row $rows bufd] verdict] eq "FAIL" && [string match "*(a)*" [dict get [row $rows bufd] why]]}
check "adiode fails (c)" {[dict get [row $rows adiode] verdict] eq "FAIL" && [string match "*(c)*" [dict get [row $rows adiode] why]]}
check "pattern cell slnht1 fails (c)" {[dict get [row $rows slnht1] verdict] eq "FAIL" && [string match "*(c)*" [dict get [row $rows slnht1] why]]}
check "two inputs fail (d)" {[dict get [row $rows bufe] verdict] eq "FAIL" && [string match "*(d)*" [dict get [row $rows bufe] why]]}
check "no macro in the LEF fails" {[dict get [row $rows nolef] verdict] eq "FAIL" && [string match "*no MACRO*" [dict get [row $rows nolef] why]]}
check "pick = smallest footprint among PASS (bufa 2.24 < bufb 3.36)" {[ant_pick_buffer $rows] eq "bufa"}
# with a stricter gate need only bufb passes
set rows2 [ant_eval_buffers $cells $names $DONT 0.25 0.202]
check "stricter need -> bufb" {[ant_pick_buffer $rows2] eq "bufb"}
# with a need nobody meets nothing is picked (the script then stops with an error)
set rows3 [ant_eval_buffers $cells $names $DONT 5.0 0.202]
check "impossible need -> no pick" {[ant_pick_buffer $rows3] eq ""}
# tie on area -> alphabetical (names are sorted before evaluation)
set tie [ant_parse_lef "MACRO t2\nSIZE 1 BY 1 ;\nPIN I\nDIRECTION INPUT ;\nANTENNAGATEAREA 1 LAYER M1 ;\nEND I\nPIN Z\nDIRECTION OUTPUT ;\nANTENNADIFFAREA 1 LAYER M1 ;\nEND Z\nEND t2\nMACRO t1\nSIZE 1 BY 1 ;\nPIN I\nDIRECTION INPUT ;\nANTENNAGATEAREA 1 LAYER M1 ;\nEND I\nPIN Z\nDIRECTION OUTPUT ;\nANTENNADIFFAREA 1 LAYER M1 ;\nEND Z\nEND t1\n"]
check "tie -> t1" {[ant_pick_buffer [ant_eval_buffers $tie {t2 t1} $DONT 0.1 0.202]] eq "t1"}
check "dont_use match is case-insensitive" {[ant_dont_use ADIODE $DONT] eq "adiode"}
check "dont_use no match" {[ant_dont_use buf1 $DONT] eq ""}

# ------------------------------------------------------------------ 6. placement helper and text parsers
set core {20.0 20.0 865.6 865.6}
lassign [ant_target_xy 885.6 440.3 2.24 5.6 $core] tx ty
check "pin on the right edge -> buffer at the core edge" {[near $tx [expr {865.6 - 2.24}] 0.0001]}
check "buffer row is a multiple of the row height from the core bottom" {[near [expr {fmod($ty - 20.0, 5.6)}] 0.0 0.0001] || [near [expr {fmod($ty - 20.0, 5.6)}] 5.6 0.0001]}
check "buffer y within 3 um of the pin y" {abs($ty + 2.8 - 440.3) <= 3.0}
lassign [ant_target_xy 300.0 885.6 2.24 5.6 $core] tx ty
check "pin on the top edge -> top row" {[near $ty [expr {865.6 - 5.6}] 0.0001]}
lassign [ant_target_xy 5.0 5.0 2.24 5.6 $core] tx ty
check "corner clamp" {[near $tx 20.0 0.0001] && [near $ty 20.0 0.0001]}
check "bbox string" {[ant_bbox_nums "{837.46 408.465} {837.74 409.365}"] eq "837.46 408.465 837.74 409.365"}
check "bbox string, negative / exponent" {[llength [ant_bbox_nums "{-1.5e-1 2} {3 4}"]] == 4}
check "bbox with 3 numbers -> error" {[must_error {ant_bbox_nums "{1 2} {3}"}]}
set crtxt "Verify Summary:\n\nTotal number of nets = 16329, of which 0 are not extracted\nTotal number of open nets = 0, of which 0 are frozen\nTotal number of DRCs = 1\nTotal number of antenna violations = 72\n"
check "check_routes DRCs"    {[ant_parse_count $crtxt "DRCs"] == 1}
check "check_routes opens"   {[ant_parse_count $crtxt "open nets"] == 0}
check "check_routes antenna" {[ant_parse_count $crtxt "antenna violations"] == 72}
check "missing line -> empty" {[ant_parse_count "nothing" "DRCs"] eq ""}
check "legality: TOTAL 0 Violations" {[ant_parse_legality "foo\nTOTAL 0 Violations\n"] eq "0"}
check "legality: total 1,234 violations" {[ant_parse_legality "Total 1,234 violations"] eq "1234"}
check "legality: 3 violations" {[ant_parse_legality "found 3 legality violations"] eq "3"}
check "legality: 'succeeded' alone is unreadable" {[ant_parse_legality "Legality check succeeded"] eq ""}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
