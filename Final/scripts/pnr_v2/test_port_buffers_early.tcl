# ==============================================================================
# Test: test_port_buffers_early.tcl (task 085)
# Run : tclsh pnr_v2/test_port_buffers_early.tcl   (no ICC2 needed)
# Tests the pure procs of pnr_v2/port_buffers_early.tcl (between BEGIN/END PURE TCL 085) together with the procs of block 068 of antenna_port_buffers.tcl:
#  - the parameters read from antenna_port_buffers.tcl (single source) and the real numbers of run 1 (limits 72 / 46 um at gate area 0.194, wires 130 to 478 um)
#  - the prediction (longest pin-to-load, MST, smallest gate), the decision rule at its boundaries, the NO-LOADS / unknown-gate cases
#  - the free-site computation from rows and cell boxes (no fillers), site selection with ant_site_candidates, the occupancy update
#  - the in2out / setup gate (equal, inside the tolerance, outside, unreadable, the run-1 style numbers), the location check, the name-prefix isolation, totals, CSV
#  - cts.tcl opens the new block through a parameter whose default is the new block
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
set ab_src [read_file $here/antenna_port_buffers.tcl]
set b [string first "# ---- BEGIN PURE TCL 068 ----" $ab_src]; set e [string first "# ---- END PURE TCL 068 ----" $ab_src]
eval [string range $ab_src $b $e]
set src [read_file $here/port_buffers_early.tcl]
set b [string first "# ---- BEGIN PURE TCL 085 ----" $src]; set e [string first "# ---- END PURE TCL 085 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]
set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc near {a b {tol 1e-6}} { return [expr {abs($a - $b) <= $tol}] }

# ---- 1. parameters from antenna_port_buffers.tcl --------------------------------------------------------------------------------------------
check "param ANT_RATIO_LIMIT" {[pbe085_param $ab_src ANT_RATIO_LIMIT] == 400.0}
check "param weights" {[pbe085_param $ab_src ANT_WEIGHT_PINWIRE] == 0.54 && [pbe085_param $ab_src ANT_WEIGHT_TOPM] == 0.84}
check "param WIRE_WIDTH_UM, MAX_PIN_BUF_DIST, MAX_SITE_TRIES" {[pbe085_param $ab_src WIRE_WIDTH_UM] == 0.28 && [pbe085_param $ab_src MAX_PIN_BUF_DIST] == 40.0 && [pbe085_param $ab_src MAX_SITE_TRIES] == 5}
check "param quoted value (BUF_PREFIX)" {[pbe085_param $ab_src BUF_PREFIX] eq "antbuf"}
check "param braced list (DONT_USE_PATTERNS) keeps adiode" {[lsearch -exact [pbe085_param $ab_src DONT_USE_PATTERNS] adiode] >= 0}
check "param braced list (POWER_PORT_NAMES)" {[pbe085_param $ab_src POWER_PORT_NAMES] eq "VDD VSS"}
check "param missing -> error" {[catch {pbe085_param $ab_src NO_SUCH_PARAM}]}

# ---- 2. the numbers of run 1 ----------------------------------------------------------------------------------------------------------------
set lim 400.0; set W 0.28; set G 0.194
set d_m23 [ant_max_dist_for_ratio $G $W 0.54 $lim]
set d_top [ant_max_dist_for_ratio $G $W 0.84 $lim]
check "run 1 limit M2/M3 about 72 um at gate 0.194" {abs($d_m23 - 71.8) < 0.5}
check "run 1 limit TOP_M about 46 um" {abs($d_top - 45.9) < 0.5}
foreach L {130.0 234.0 252.0 478.0} {
    set r [ant_ratio $G $L $W 0.54]
    lassign [pbe085_decide 4 $r $lim 0.8 1] dec why
    check "run-1 wire $L um -> BUFFER" {$dec eq "BUFFER"}
}

# ---- 3. the decision rule at its boundaries --------------------------------------------------------------------------------------------------
set thr [expr {0.8 * $lim}]
check "ratio exactly at 0.8 x limit -> OK (strictly above buffers)" {[lindex [pbe085_decide 2 $thr $lim 0.8 1] 0] eq "OK"}
check "ratio just above -> BUFFER" {[lindex [pbe085_decide 2 [expr {$thr + 0.001}] $lim 0.8 1] 0] eq "BUFFER"}
check "ratio just below -> OK" {[lindex [pbe085_decide 2 [expr {$thr - 0.001}] $lim 0.8 1] 0] eq "OK"}
check "margin 1.0: ratio at the limit -> OK, above -> BUFFER" {[lindex [pbe085_decide 2 400.0 $lim 1.0 1] 0] eq "OK" && [lindex [pbe085_decide 2 400.1 $lim 1.0 1] 0] eq "BUFFER"}
check "no loads -> NO-LOADS whatever the ratio" {[lindex [pbe085_decide 0 9999.0 $lim 0.8 1] 0] eq "NO-LOADS"}
lassign [pbe085_decide 3 0.0 $lim 0.8 0] dec why
check "unknown gate area -> BUFFER on the safe side, with the reason" {$dec eq "BUFFER" && [string match "*no load gate area is known*" $why]}
check "the reason of OK / BUFFER carries both numbers" {[string match "*> 0.80 x limit 400 = 320.0*" [lindex [pbe085_decide 1 321.0 $lim 0.8 1] 1]] && [string match "*<= 0.80 x limit 400 = 320.0*" [lindex [pbe085_decide 1 10.0 $lim 0.8 1] 1]]}
# the boundary in distance: the longest distance that is still OK at gate 0.194, margin 0.8, M2/M3
set dmax [ant_max_dist_for_ratio $G $W 0.54 [expr {0.8 * $lim}]]
check "distance boundary: just below dmax OK, just above BUFFER" {[lindex [pbe085_decide 1 [ant_ratio $G [expr {$dmax - 0.01}] $W 0.54] $lim 0.8 1] 0] eq "OK" && [lindex [pbe085_decide 1 [ant_ratio $G [expr {$dmax + 0.01}] $W 0.54] $lim 0.8 1] 0] eq "BUFFER"}

# ---- 4. the prediction ----------------------------------------------------------------------------------------------------------------------
check "MST of one point is 0" {[pbe085_mst {{0 0}}] == 0.0}
check "MST of two points is their Manhattan distance" {[near [pbe085_mst {{0 0} {3 4}}] 7.0]}
check "MST of an L of three points" {[near [pbe085_mst {{0 0} {10 0} {10 10}}] 20.0]}
check "MST takes the cheaper edges (square of 4 points = 3 sides)" {[near [pbe085_mst {{0 0} {10 0} {10 10} {0 10}}] 30.0]}
set pr [pbe085_predict {100.0 0.0} {{100.0 200.0 0.194} {150.0 100.0 0.4} {90.0 50.0 ""}}]
check "predict: loads counted" {[dict get $pr nloads] == 3}
check "predict: the longest pin-to-load distance is the Manhattan one (200)" {[near [dict get $pr maxd] 200.0]}
check "predict: smallest KNOWN gate area is used" {[near [dict get $pr gmin] 0.194]}
check "predict: unknown gate areas are counted" {[dict get $pr nunknown] == 1}
check "predict: gate sum over the known ones" {[near [dict get $pr gsum] 0.594]}
set pr0 [pbe085_predict {0 0} {}]
check "predict: no loads -> maxd 0, gmin empty" {[dict get $pr0 nloads] == 0 && [dict get $pr0 maxd] == 0.0 && [dict get $pr0 gmin] eq ""}
set pr1 [pbe085_predict {0 0} {{5 5 0}}]
check "predict: a zero gate area is unknown" {[dict get $pr1 nunknown] == 1 && [dict get $pr1 gmin] eq ""}

# ---- 5. free sites from rows and cell boxes (no fillers) ------------------------------------------------------------------------------------------
set row {0.0 5.6 0.0 100.0 N}
set runs [pbe085_row_runs $row {{10.0 20.0} {50.0 60.0}} 0.001]
check "row with two cells -> three free runs" {[llength $runs] == 3}
check "run edges" {[near [dict get [lindex $runs 0] x0] 0.0] && [near [dict get [lindex $runs 0] x1] 10.0] && [near [dict get [lindex $runs 1] x0] 20.0] && [near [dict get [lindex $runs 1] x1] 50.0] && [near [dict get [lindex $runs 2] x0] 60.0] && [near [dict get [lindex $runs 2] x1] 100.0]}
check "run carries the row orientation and an empty filler list" {[dict get [lindex $runs 0] orient] eq "N" && [dict get [lindex $runs 0] fillers] eq ""}
check "touching cells leave no zero-width run" {[llength [pbe085_row_runs $row {{0.0 40.0} {40.0 100.0}} 0.001]] == 0}
check "empty row is one run" {[llength [pbe085_row_runs $row {} 0.001]] == 1}
check "overlapping boxes are merged" {[llength [pbe085_row_runs $row {{10.0 30.0} {20.0 40.0}} 0.001]] == 2}
check "unsorted occupancy is sorted" {[llength [pbe085_row_runs $row {{50.0 60.0} {10.0 20.0}} 0.001]] == 3}
check "a cell outside the row span does not produce a run" {[llength [pbe085_row_runs $row {{120.0 130.0}} 0.001]] == 1}
set rows2 {{0.0 5.6 0.0 100.0 N} {5.6 11.2 0.0 100.0 FS}}
set cells2 {{10.0 0.0 20.0 5.6} {0.0 5.6 100.0 11.2}}
set ar [pbe085_all_runs $rows2 $cells2 0.001]
check "two rows: row 2 is full, row 1 has two runs" {[llength [dict get $ar runs]] == 2 && [dict get $ar stray] == 0}
set ar [pbe085_all_runs $rows2 {{10.0 2.0 20.0 7.6}} 0.001]
check "a cell whose y0 matches no row is counted as stray (never ignored)" {[dict get $ar stray] == 1}
# site selection with the block-068 procs on the free runs: pin at (50, 3), buffer 4.48 wide, site 0.56
set cands [ant_site_candidates [pbe085_row_runs {0.0 5.6 0.0 100.0 N} {{44.8 56.0}} 0.001] 4.48 0.56 50.0 3.0 40.0]
check "site candidates: nearest start sites on both sides of the occupied span" {[llength $cands] == 2}
check "site candidates: the site is on the site grid" {[near [expr {[dict get [lindex $cands 0] x] / 0.56}] [expr {round([dict get [lindex $cands 0] x] / 0.56)}] 1e-6]}
check "site candidates: within the limit" {[dict get [lindex $cands 0] dist] <= 40.0}
check "site candidates: orientation of the row is carried" {[dict get [lindex $cands 0] orient] eq "N"}
check "no candidate when the run is narrower than the buffer" {[llength [ant_site_candidates [pbe085_row_runs {0.0 5.6 0.0 100.0 N} {{0.0 98.0}} 0.001] 4.48 0.56 50.0 3.0 40.0]] == 0}
check "no candidate beyond the distance limit" {[llength [ant_site_candidates [pbe085_row_runs {0.0 5.6 0.0 100.0 N} {} 0.001] 4.48 0.56 500.0 3.0 40.0]] == 0}
# occupancy update: after the first buffer takes the site, the second pin gets a different site
set occ [list [list 44.8 56.0]]
set c1 [lindex [ant_site_candidates [pbe085_row_runs {0.0 5.6 0.0 100.0 N} $occ 0.001] 4.48 0.56 50.0 3.0 40.0] 0]
lappend occ [list [dict get $c1 x] [expr {[dict get $c1 x] + [dict get $c1 w]}]]
set c2 [lindex [ant_site_candidates [pbe085_row_runs {0.0 5.6 0.0 100.0 N} $occ 0.001] 4.48 0.56 50.0 3.0 40.0] 0]
check "after the occupancy update the same site is not offered twice" {[dict get $c1 x] != [dict get $c2 x]}
check "and the two boxes do not overlap" {abs([dict get $c1 x] - [dict get $c2 x]) >= 4.48 - 1e-6}

# ---- 6. location check, gate, prefix, totals, CSV -------------------------------------------------------------------------------------------
check "location equal -> ok" {[pbe085_loc_ok {10.0 5.6} {10.0 5.6} 0.001]}
check "location within tolerance -> ok" {[pbe085_loc_ok {10.0 5.6} {10.0005 5.6} 0.001]}
check "location moved by the legaliser (far) -> not ok" {![pbe085_loc_ok {10.0 5.6} {370.0 5.6} 0.001]}
lassign [pbe085_gate "in2out WNS" 0.0143 0.0143 0.005] ok m
check "gate: equal -> ok" {$ok == 1}
lassign [pbe085_gate "in2out WNS" 0.0143 0.0100 0.005] ok m
check "gate: slightly worse inside the tolerance -> ok" {$ok == 1}
lassign [pbe085_gate "in2out WNS" 1.0 0.75 0.25] ok m
check "gate: exactly at the tolerance edge (binary-exact numbers) -> ok" {$ok == 1}
lassign [pbe085_gate "in2out WNS" 1.0 0.7499 0.25] ok m
check "gate: just outside the tolerance -> stop" {$ok == 0 && [string match "*got worse*before 1.0000*after 0.7499*" $m]}
lassign [pbe085_gate "in2out WNS" 0.0143 -0.5899 0.005] ok m
check "gate: the run-1 style break (+0.0143 -> -0.5899) -> stop with both numbers" {$ok == 0 && [string match "*0.0143*-0.5899*" $m]}
lassign [pbe085_gate "in2out WNS" 0.0143 0.2 0.005] ok m
check "gate: better -> ok" {$ok == 1}
lassign [pbe085_gate "in2out WNS" "n/a" 0.0 0.005] ok m
check "gate: unreadable before -> stop (never a pass)" {$ok == 0 && [string match "*unreadable*" $m]}
lassign [pbe085_gate "setup WNS" 0.01 "" 0.005] ok m
check "gate: empty after -> stop" {$ok == 0}
check "prefix isolation: earlybuf vs antbuf is fine" {[pbe085_prefix_ok earlybuf antbuf]}
check "prefix isolation: equal prefixes collide" {![pbe085_prefix_ok antbuf antbuf]}
check "prefix isolation: antbuf2 vs antbuf are different globs but antbuf_* must not match" {[pbe085_prefix_ok antbuf2 antbuf]}
check "the early prefix used by the script is isolated from the real BUF_PREFIX" {[pbe085_prefix_ok [pbe085_param $src EARLY_PREFIX] [pbe085_param $ab_src BUF_PREFIX]]}
set tbl {}
foreach {p dec} {a BUFFER b BUFFER c OK d NO-LOADS e CLOCK-SKIPPED f OK} {
    lappend tbl [dict create port $p loads 1 maxd 10.0 mst 10.0 gmin 0.194 ratio_m23 50.0 ratio_top 77.0 decision $dec reason r]
}
set tot [pbe085_totals $tbl]
check "totals count every row exactly once" {[dict get $tot BUFFER] == 2 && [dict get $tot OK] == 2 && [dict get $tot NO-LOADS] == 1 && [dict get $tot CLOCK-SKIPPED] == 1 && [dict get $tot total] == 6}
check "line format has the port, the decision and the ratios" {[string match "a *loads   1*BUFFER*" [pbe085_line [lindex $tbl 0]]]}
set csv [split [string trim [pbe085_csv $tbl]] "\n"]
check "csv: header plus one line per row" {[llength $csv] == 7 && [string match "port,loads,*" [lindex $csv 0]]}
check "csv: the decision is the last field" {[string match "*,BUFFER" [lindex $csv 1]]}

# ---- 7. the real script is consistent with its rules -------------------------------------------------------------------------------------------
set code {}
foreach l [split [string range $src [expr {$e + 1}] end] "\n"] { set t [string trim $l]; if {$t ne "" && [string index $t 0] ne "#"} { lappend code $t } }
set joined [join $code "\n"]
check "the script saves ONLY as the new block (save_block -as OUT_BLOCK)" {[regexp -all {save_block} $joined] == 1 && [string first {save_block -as ${OUT_BLOCK}} $joined] >= 0}
check "the script does not call legalize_placement (it moved cells far in run 1)" {[string first "legalize_placement" $joined] < 0}
check "the script does not use a diode" {[string first "adiode" $joined] < 0 && [string first "add_port_protection_diodes" $joined] < 0}
check "the script does not change a constraint, uncertainty or app option" {[string first "set_app_options" $joined] < 0 && [string first "set_clock_uncertainty" $joined] < 0 && [string first "set_input_delay" $joined] < 0}
check "default PLAN_ONLY is 0 and the margin is 0.8 (parameters as Planning wrote them)" {[pbe085_param $src PLAN_ONLY] eq "0" && [pbe085_param $src PREDICT_MARGIN] eq "0.8"}
check "tolerance of the gates is 0.005 ns" {[pbe085_param $src GATE_TOL_IN2OUT] eq "0.005" && [pbe085_param $src GATE_TOL_SETUP] eq "0.005"}
set cts [read_file $here/cts.tcl]
check "cts.tcl has the parameter CTS_INPUT_BLOCK" {[regexp {^set CTS_INPUT_BLOCK\s+"\$\{DESIGN_NAME\}_portbuf"} $cts] || [regexp -line {^set CTS_INPUT_BLOCK\s+"\$\{DESIGN_NAME\}_portbuf"} $cts]}
set cts_open {open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${CTS_INPUT_BLOCK}}
set cts_old "dlib:\$\{DESIGN_NAME\}_placement"
check "cts.tcl opens the block through the parameter, not a typed name" {[string first $cts_open $cts] >= 0 && [string first $cts_old $cts] < 0}


# ---- 8. optional environment overrides (task 085 follow-up) ------------------------------------------------------------------------------------
check "env: not set -> default, source 'default'" {[pbe085_env_resolve PLAN_ONLY 0 flag NONE UNPU_PBE_PLAN_ONLY] eq {0 default}}
check "env: flag 1 accepted, source names the variable" {[pbe085_env_resolve PLAN_ONLY 0 flag 1 UNPU_PBE_PLAN_ONLY] eq {1 {environment UNPU_PBE_PLAN_ONLY}}}
check "env: flag 0 accepted" {[lindex [pbe085_env_resolve PLAN_ONLY 1 flag 0 X] 0] eq "0"}
foreach bad {2 -1 yes true "" "1 " 0.5} {
    check "env: flag '$bad' -> ERROR 085" {[catch {pbe085_env_resolve PLAN_ONLY 0 flag $bad UNPU_PBE_PLAN_ONLY} m] && [string match "ERROR 085*UNPU_PBE_PLAN_ONLY*must be 0 or 1*" $m]}
}
check "env: margin 0.5 accepted" {[lindex [pbe085_env_resolve PREDICT_MARGIN 0.8 margin 0.5 X] 0] eq "0.5"}
check "env: margin 10 (upper edge) accepted, 1 accepted" {[lindex [pbe085_env_resolve PREDICT_MARGIN 0.8 margin 10 X] 0] eq "10" && [lindex [pbe085_env_resolve PREDICT_MARGIN 0.8 margin 1 X] 0] eq "1"}
foreach bad {0 -0.5 10.01 abc "" nan inf "0.8x"} {
    check "env: margin '$bad' -> ERROR 085" {[catch {pbe085_env_resolve PREDICT_MARGIN 0.8 margin $bad UNPU_PBE_PREDICT_MARGIN} m] && [string match "ERROR 085*UNPU_PBE_PREDICT_MARGIN*number above 0 and at most 10*" $m]}
}
check "env: weight m23 and top accepted" {[lindex [pbe085_env_resolve PREDICT_WEIGHT m23 word:m23|top top X] 0] eq "top" && [lindex [pbe085_env_resolve PREDICT_WEIGHT top word:m23|top m23 X] 0] eq "m23"}
foreach bad {M23 TOP both "" "m23 "} {
    check "env: weight '$bad' -> ERROR 085 listing the allowed words" {[catch {pbe085_env_resolve PREDICT_WEIGHT m23 word:m23|top $bad UNPU_PBE_PREDICT_WEIGHT} m] && [string match "ERROR 085*one of m23, top*" $m]}
}
check "env: a default is never validated as input (the file's defaults are checked by the script)" {[lindex [pbe085_env_resolve PLAN_ONLY 0 flag NONE X] 0] eq "0"}
check "the script reads exactly the three variables named by Planning" {[string first "UNPU_PBE_PLAN_ONLY" $src] > 0 && [string first "UNPU_PBE_PREDICT_MARGIN" $src] > 0 && [string first "UNPU_PBE_PREDICT_WEIGHT" $src] > 0}
check "the parameters line prints where each value came from" {[string first "\[join \$pb_param_src" $src] > 0}

# ---- 9. CONE_POLICY (task 087) ----------------------------------------------------------------------------------------------------------------
check "cone policy: default parameter is skip" {[pbe085_param $src CONE_POLICY] eq "skip"}
check "cone policy env: skip and buffer accepted, source named" {[pbe085_env_resolve CONE_POLICY skip word:skip|buffer buffer UNPU_PBE_CONE_POLICY] eq {buffer {environment UNPU_PBE_CONE_POLICY}}}
check "cone policy env: not set -> default" {[pbe085_env_resolve CONE_POLICY skip word:skip|buffer NONE UNPU_PBE_CONE_POLICY] eq {skip default}}
foreach bad {SKIP both none "" "skip "} {
    check "cone policy env: '$bad' -> ERROR 085 listing skip, buffer" {[catch {pbe085_env_resolve CONE_POLICY skip word:skip|buffer $bad UNPU_PBE_CONE_POLICY} m] && [string match "ERROR 085*UNPU_PBE_CONE_POLICY*one of skip, buffer*" $m]}
}
check "the script reads UNPU_PBE_CONE_POLICY in the loop with the other three" {[string first "CONE_POLICY UNPU_PBE_CONE_POLICY word:skip|buffer" $src] > 0}
lassign [pbe085_cone_decide skip BUFFER 1 "predicted ratio 940.7 > 0.80 x limit 400 = 320.0"] d w
check "policy skip: BUFFER on the cone -> CONE-SKIPPED" {$d eq "CONE-SKIPPED"}
check "the reason keeps the predicted ratio and names the repair" {[string match "*940.7*input-to-output cone*antenna_port_buffers.tcl*Calibre antenna run*" $w]}
check "policy skip: BUFFER off the cone stays BUFFER" {[lindex [pbe085_cone_decide skip BUFFER 0 r] 0] eq "BUFFER"}
check "policy buffer: BUFFER on the cone stays BUFFER (the 085 behaviour)" {[lindex [pbe085_cone_decide buffer BUFFER 1 r] 0] eq "BUFFER"}
foreach dec {OK NO-LOADS CLOCK-SKIPPED} {
    check "policy skip: $dec on the cone is never changed" {[lindex [pbe085_cone_decide skip $dec 1 r] 0] eq $dec}
}
set tbl2 {}
foreach {p dec} {a BUFFER b CONE-SKIPPED c OK d NO-LOADS e CLOCK-SKIPPED f CONE-SKIPPED} {
    lappend tbl2 [dict create port $p loads 2 maxd 120.5 mst 150.0 gmin 0.194 ratio_m23 650.2 ratio_top 1011.5 decision $dec reason r]
}
set tot2 [pbe085_totals $tbl2]
check "totals count CONE-SKIPPED and the sum is the number of ports" {[dict get $tot2 CONE-SKIPPED] == 2 && [dict get $tot2 BUFFER] == 1 && [dict get $tot2 total] == 6 && ([dict get $tot2 BUFFER] + [dict get $tot2 OK] + [dict get $tot2 NO-LOADS] + [dict get $tot2 CLOCK-SKIPPED] + [dict get $tot2 CONE-SKIPPED]) == [dict get $tot2 total]}
check "the TOTALS line of the script names CONE-SKIPPED" {[string first "+ CONE-SKIPPED \[dict get \$pb_tot CONE-SKIPPED\]" $src] > 0}
set cb [pbe085_cone_block $tbl2 m23]
check "cone block: one line per CONE-SKIPPED net with ratio and distance" {[llength $cb] == 2 && [string match "b *650.2*M2/M3*120.5*" [lindex $cb 0]]}
check "cone block with the TOP_M weight prints the TOP_M ratio" {[string match "*1011.5*TOP_M*" [lindex [pbe085_cone_block $tbl2 top] 0]]}
check "cone block: none when no net is skipped" {[llength [pbe085_cone_block [lrange $tbl2 0 0] m23]] == 0}
set rows_f [ant_eval_buffers [dict create buffd1 [dict create w 2.24 h 5.6 pins [dict create I [dict create dir INPUT use SIGNAL gate 0.19 diff {}] Z [dict create dir OUTPUT use SIGNAL gate {} diff 0.25]]] buffd4 [dict create w 4.48 h 5.6 pins [dict create I [dict create dir INPUT use SIGNAL gate 0.5 diff {}] Z [dict create dir OUTPUT use SIGNAL gate {} diff 0.6]]] buffd2 [dict create w 3.36 h 5.6 pins [dict create I [dict create dir INPUT use SIGNAL gate 0.3 diff {}] Z [dict create dir OUTPUT use SIGNAL gate {} diff 0.4]]]] {buffd1 buffd2 buffd4} {adiode} 0.1 0.2]
check "fastest: the highest drive among the passing buffers" {[pbe085_fastest $rows_f] eq "buffd4"}
check "fastest: a failing cell is not chosen (dont-use pattern)" {[pbe085_fastest [ant_eval_buffers [dict get [dict create x [dict create buffd4 [dict create w 4.48 h 5.6 pins [dict create I [dict create dir INPUT use SIGNAL gate 0.5 diff {}] Z [dict create dir OUTPUT use SIGNAL gate {} diff 0.6]]]]] x] {buffd4} {buffd4} 0.1 0.2]] eq ""}
check "fastest: none -> empty" {[pbe085_fastest {}] eq ""}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
