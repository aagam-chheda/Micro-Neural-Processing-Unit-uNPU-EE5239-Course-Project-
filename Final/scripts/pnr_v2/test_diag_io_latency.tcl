# ==============================================================================
# Test: test_diag_io_latency.tcl (task 084)
# Run : tclsh pnr_v2/test_diag_io_latency.tcl   (no ICC2 needed)
# Tests the pure parsers / decisions of pnr_v2/diag_io_latency.tcl (between BEGIN PURE TCL 084 and END PURE TCL 084) on:
#  - PrimeTime-style path text built from the numbers of progress log 3.11 (hold dma_rdata[14]: arrival 0.56, required 0.90, slack -0.35; setup dma_addr[31]: launch 0.92, arrival 10.74,
#    required 10.50, slack -0.24). The line layout is the usual PrimeTime/ICC2 report layout; the numbers are the real ones.
#  - an INVENTED ICC2-style text where the I/O reference carries the clock latency (H1 case), an unexpanded and an expanded clock path,
#    and broken texts (nothing guessed: n/a).
# ==============================================================================
set here [file dirname [file normalize [info script]]]
source $here/run_root.tcl
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
set src [read_file $here/diag_io_latency.tcl]
set b [string first "# ---- BEGIN PURE TCL 084 ----" $src]
set e [string first "# ---- END PURE TCL 084 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]
set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}

# ---- samples ----------------------------------------------------------------------------------------------------------------------
# PrimeTime-like hold path from an input port: network delay row 0.00 (progress log 3.11)
set pt_hold {
  Startpoint: dma_rdata[14] (input port clocked by clk)
  Endpoint: u_dma/stage_reg_1__14_ (rising edge-triggered flip-flop clocked by clk)
  Path Group: clk
  Path Type: min

  Point                                    Incr       Path
  -----------------------------------------------------------
  clock clk (rise edge)                  0.0000     0.0000
  clock network delay (propagated)       0.0000     0.0000
  input external delay                   0.0000     0.0000 f
  dma_rdata[14] (in)                     0.2600     0.2600 f
  copt_h_inst_3077/Z (buffd1)            0.1700     0.4300 f
  U55/Z (mx02d1)                         0.1200     0.5500 f
  u_dma/stage_reg_1__14_/D (dfcrq1)      0.0100     0.5600 f
  data arrival time                                 0.5600

  clock clk (rise edge)                  0.0000     0.0000
  clock network delay (propagated)       0.4000     0.4000
  clock uncertainty                      0.5000     0.9000
  u_dma/stage_reg_1__14_/CP (dfcrq1)                0.9000 r
  library hold time                      0.0000     0.9000
  data required time                                0.9000
  -----------------------------------------------------------
  data required time                                0.9000
  data arrival time                                -0.5600
  -----------------------------------------------------------
  slack (VIOLATED)                                 -0.3400
}
# PrimeTime-like setup path to the output port dma_addr[31] (launch 0.92, arrival 10.74, required 10.50)
set pt_setup {
  Startpoint: u_dma/beat_idx_reg_0_ (rising edge-triggered flip-flop clocked by clk)
  Endpoint: dma_addr[31] (output port clocked by clk)
  Path Group: clk
  Path Type: max

  Point                                    Incr       Path
  -----------------------------------------------------------
  clock clk (rise edge)                  0.0000     0.0000
  clock network delay (propagated)       0.9200     0.9200
  u_dma/beat_idx_reg_0_/CP (dfcrq1)                 0.9200 r
  u_dma/beat_idx_reg_0_/Q (dfcrq1)       0.5900     1.5100 f
  HFSINV_13_284/ZN (inv0d4)              1.6100    10.7400 r
  dma_addr[31] (out)                     0.0000    10.7400 r
  data arrival time                                10.7400

  clock clk (rise edge)                 20.0000    20.0000
  clock network delay (propagated)       0.0000    20.0000
  clock uncertainty                     -1.5000    18.5000
  output external delay                 -8.0000    10.5000
  data required time                               10.5000
  -----------------------------------------------------------
  data required time                               10.5000
  data arrival time                               -10.7400
  -----------------------------------------------------------
  slack (VIOLATED)                                 -0.2400
}
# INVENTED ICC2-style, H1 case: the input reference carries the clock latency (expanded clock path before the input external delay), the output required time 11.42 (0.92 added)
set icc_hold_h1 {
  Startpoint: dma_rdata[14] (input port clocked by clk)
  Endpoint: u_dma/stage_reg_1__14_ (rising edge-triggered flip-flop clocked by clk)
  Path Group: clk
  Path Type: min

  Point                                    Incr       Path
  -----------------------------------------------------------
  clock clk (rise edge)                  0.0000     0.0000
  clk (in)                               0.0000     0.0000 r
  CTS_ccl_BUF_clk_1/Z (clkbuf4)          0.2000     0.2000 r
  CTS_ccl_BUF_clk_2/Z (clkbuf4)          0.2000     0.4000 r
  input external delay                   0.0000     0.4000 f
  dma_rdata[14] (in)                     0.2600     0.6600 f
  u_dma/stage_reg_1__14_/D (dfcrq1)      0.0100     0.6700 f
  data arrival time                                 0.6700

  clock clk (rise edge)                  0.0000     0.0000
  clk (in)                               0.0000     0.0000 r
  CTS_ccl_BUF_clk_1/Z (clkbuf4)          0.2000     0.2000 r
  CTS_ccl_BUF_clk_2/Z (clkbuf4)          0.2000     0.4000 r
  u_dma/stage_reg_1__14_/CP (dfcrq1)                0.4000 r
  clock uncertainty                      0.5000     0.9000
  library hold time                      0.0000     0.9000
  data required time                                0.9000
  slack (VIOLATED)                                 -0.2300
}
set icc_setup_h1 [string map {{clock network delay (propagated)       0.0000    20.0000} {clock network delay (propagated)       0.9200    20.9200} {-1.5000    18.5000} {-1.5000    19.4200} {-8.0000    10.5000} {-8.0000    11.4200} {data required time                               10.5000
  -----} {data required time                               11.4200
  -----} {slack (VIOLATED)                                 -0.2400} {slack (MET)                                      0.6800} {data arrival time                               -10.7400} {data arrival time                               -10.7400}} $pt_setup]

# ---- rows ------------------------------------------------------------------------------------------------------------------------
set rows [diag084_rows $pt_hold]
check "rows: sections split at data arrival / data required" {[lindex [diag084_first_row $rows 0 {^input external}] 4] == 0 && [lindex [diag084_first_row $rows 1 {^clock uncertainty}] 4] == 1}
check "rows: edge time of the launch half is 0" {[diag084_edge_time $rows 0] == 0.0}
check "rows: edge time of the setup capture half is 20" {[diag084_edge_time [diag084_rows $pt_setup] 1] == 20.0}
check "rows: a one-number pin row has path only" {[lindex [diag084_first_row $rows 1 {^u_dma/stage_reg_1__14_/CP}] 1] eq "" && [lindex [diag084_first_row $rows 1 {^u_dma/stage_reg_1__14_/CP}] 2] == 0.9}
check "rows: headers and rules are skipped" {[llength [diag084_first_row $rows 0 {^Point}]] == 0}

# ---- parse PrimeTime hold -----------------------------------------------------------------------------------------------------------
set h [diag084_parse $pt_hold]
check "PT hold: start/end names" {[dict get $h start] eq "dma_rdata\[14\]" && [dict get $h end] eq "u_dma/stage_reg_1__14_"}
check "PT hold: kinds" {[dict get $h skind] eq "port" && [dict get $h ekind] eq "cell"}
check "PT hold: group and type" {[dict get $h group] eq "clk" && [dict get $h type] eq "min"}
check "PT hold: launch latency 0.00 (input port)" {abs([dict get $h launch]) < 1e-9}
check "PT hold: capture latency 0.40" {abs([dict get $h capture] - 0.40) < 1e-9}
check "PT hold: uncertainty 0.50" {abs([dict get $h uncert] - 0.50) < 1e-9}
check "PT hold: arrival 0.56, required 0.90" {abs([dict get $h arrival] - 0.56) < 1e-9 && abs([dict get $h required] - 0.90) < 1e-9}
check "PT hold: slack -0.34" {abs([dict get $h slack] + 0.34) < 1e-9}
check "PT hold: found, no notes" {[dict get $h found] == 1 && [llength [dict get $h notes]] == 0}

# ---- parse PrimeTime setup -----------------------------------------------------------------------------------------------------------
set s [diag084_parse $pt_setup]
check "PT setup: start flop, end port" {[dict get $s start] eq "u_dma/beat_idx_reg_0_" && [dict get $s end] eq "dma_addr\[31\]" && [dict get $s skind] eq "cell" && [dict get $s ekind] eq "port"}
check "PT setup: launch latency 0.92" {abs([dict get $s launch] - 0.92) < 1e-9}
check "PT setup: capture latency at the output port 0.00 (edge time 20 removed)" {abs([dict get $s capture]) < 1e-9}
check "PT setup: arrival 10.74, required 10.50, slack -0.24" {abs([dict get $s arrival] - 10.74) < 1e-9 && abs([dict get $s required] - 10.50) < 1e-9 && abs([dict get $s slack] + 0.24) < 1e-9}
check "PT setup: uncertainty -1.5 as printed (a setup uncertainty reduces the required time)" {abs([dict get $s uncert] + 1.5) < 1e-9}

# ---- ICC2 H1 case (expanded clock path before the input external delay) ------------------------------------------------------------------------
set hh [diag084_parse $icc_hold_h1]
check "ICC2 H1 hold: launch latency 0.40 read from the input external delay row (expanded clock path)" {abs([dict get $hh launch] - 0.40) < 1e-9}
check "ICC2 H1 hold: capture latency 0.40 read from the expanded clock pin row" {abs([dict get $hh capture] - 0.40) < 1e-9}
set ss [diag084_parse $icc_setup_h1]
check "ICC2 H1 setup: capture latency at the output 0.92" {abs([dict get $ss capture] - 0.92) < 1e-9}
check "ICC2 H1 setup: required 11.42" {abs([dict get $ss required] - 11.42) < 1e-9}
check "ICC2 H1 setup: slack MET read" {abs([dict get $ss slack] - 0.68) < 1e-9}

# ---- verdicts ------------------------------------------------------------------------------------------------------------------------------
set ref [dict create hold_launch 0.00 hold_capture 0.40 hold_arrival 0.56 hold_required 0.90 hold_slack -0.35 setup_launch 0.92 setup_arrival 10.74 setup_required 10.50 setup_slack -0.24]
set v [diag084_verdict $hh $ss $ref 0.05]
check "verdict H1 case -> CONFIRMED" {[string match "H1 CONFIRMED*" [dict get $v verdict]]}
check "verdict H1 case names both sides" {[string match "*input-port launch (hold) 0.4000 ns*" [dict get $v verdict]] && [string match "*output-port capture*0.9200 ns*" [dict get $v verdict]]}
check "verdict table has the 4 labelled lines" {[llength [dict get $v lines]] == 4 && [string match "ICC2 launch clock latency at the input port path:*" [lindex [dict get $v lines] 0]]}
check "verdict table prints PrimeTime's numbers beside" {[string match "*(PrimeTime: 0.4000 ff)*" [lindex [dict get $v lines] 1]] && [string match "*(PrimeTime: 10.5000)*" [lindex [dict get $v lines] 3]]}
set v [diag084_verdict $h $s $ref 0.05]
check "verdict with PrimeTime's own texts (0.00 / 0.00) -> REFUTED" {[string match "H1 REFUTED*" [dict get $v verdict]]}
check "REFUTED lists no difference when the numbers are PrimeTime's" {[string match "*none above 0.02 ns*" [dict get $v verdict]]}
# refuted but different arrival: the difference is listed
set h2 [dict replace $h arrival 0.40 slack -0.50]
set v [diag084_verdict $h2 $s $ref 0.05]
check "REFUTED lists the differing quantity" {[string match "H1 REFUTED*hold arrival: ICC2 0.4000, PrimeTime 0.5600*" [dict get $v verdict]]}
# mixed: only the input side
set s0 [dict replace $ss capture 0.0]
set v [diag084_verdict $hh $s0 $ref 0.05]
check "only the input side shows latency -> CONFIRMED with a warning in the sentence" {[string match "H1 CONFIRMED*" [dict get $v verdict]] && [string match "*Only one side shows it*" [dict get $v sentence]]}
# missing data
set none [diag084_parse ""]
set v [diag084_verdict $hh $none $ref 0.05]
check "input side positive, output side unreadable -> CONFIRMED and the sentence says the other side is unread" {[string match "H1 CONFIRMED*" [dict get $v verdict]] && [string match "*other side could not be read*" [dict get $v sentence]]}
check "empty text -> found 0, note" {[dict get $none found] == 0 && [llength [dict get $none notes]] == 1}
set v [diag084_verdict $none $none $ref 0.05]
check "nothing readable -> INCONCLUSIVE" {[string match "INCONCLUSIVE*not readable*input-port launch*output-port capture*" [dict get $v verdict]]}
check "n/a is printed as n/a" {[diag084_num n/a] eq "n/a" && [diag084_num ""] eq "n/a" && [diag084_num 0.4] eq "0.4000"}
set v [diag084_verdict $h $none $ref 0.05]
check "one zero and one missing -> INCONCLUSIVE (never REFUTED on half the evidence)" {[string match "INCONCLUSIVE*" [dict get $v verdict]]}
# a text with only an unexpanded input path and no network delay row and no input external delay -> n/a
set bad "  Startpoint: a (input port clocked by clk)\n  Endpoint: b (output port clocked by clk)\n  a (in)  0.1000  0.1000 r\n  data arrival time  0.1000\n  data required time  0.5000\n"
set hb [diag084_parse $bad]
check "no latency row at all -> n/a with a note, not 0" {[dict get $hb launch] eq "n/a" && [string match "*launch clock latency not readable*" [lindex [dict get $hb notes] 0]]}

# ---- guards ----------------------------------------------------------------------------------------------------------------------------------
set tmp [file normalize [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] "dg084_[pid]"]]
file delete -force $tmp
foreach c {run1 run2} { file mkdir $tmp/$c/pnr_v2; close [open $tmp/$c/pnr_v2/run_root.tcl w]; file mkdir $tmp/$c/pnr_icc2/blocks_diag/unpu_top.dlib }
set r1 [unpu_run_norm $tmp/run1]; set r2 [unpu_run_norm $tmp/run2]
check "library inside this clone -> accepted" {[diag084_lib_check $r2/pnr_icc2/blocks_diag/unpu_top.dlib $r2] eq ""}
set m [diag084_lib_check $r1/pnr_icc2/blocks_diag/unpu_top.dlib $r2]
check "library inside ANOTHER clone -> refused, both named" {[string match "ERROR 084*" $m] && [string first $r1 $m] >= 0 && [string first $r2 $m] >= 0}
check "missing library -> refused with the copy hint" {[string match "*does not exist*copy run 1's library*" [diag084_lib_check $tmp/nope $r2]]}
check "empty library path -> refused" {[string match "ERROR 084*empty*" [diag084_lib_check "" $r2]]}
file mkdir $tmp/outside/unpu_top.dlib
check "library in no clone -> accepted (opened read-only, a note is printed by the script)" {[diag084_lib_check $tmp/outside/unpu_top.dlib $r2] eq ""}
check "block present (as lib:block) -> ok" {[diag084_block_check unpu_top_route {unpu_top.dlib:unpu_top_placement unpu_top.dlib:unpu_top_route}] eq ""}
set m [diag084_block_check unpu_top_route {unpu_top.dlib:unpu_top_placement unpu_top.dlib:unpu_top_cts}]
check "block listed with a label and a view suffix -> ok" {[diag084_block_check unpu_top_route {unpu_top.dlib:unpu_top_route/final.design}] eq "" && [diag084_block_check unpu_top_route {unpu_top_route.design}] eq ""}
check "a block whose name only starts the same is NOT accepted" {[diag084_block_check unpu_top_route {unpu_top.dlib:unpu_top_route2}] ne ""}
check "block missing -> refused, existing blocks listed" {[string match "ERROR 084*unpu_top.dlib:unpu_top_placement, unpu_top.dlib:unpu_top_cts*" $m]}
check "no block at all -> refused with 'none'" {[string match "*Blocks that exist: none*" [diag084_block_check x {}]]}
file delete -force $tmp

# ---- scenarios, sdc lines, help list -----------------------------------------------------------------------------------------------------------
lassign [diag084_pick_scenario {func_ss func_ff} *ss*] ok n m
check "scenario pick: one match" {$ok == 1 && $n eq "func_ss"}
lassign [diag084_pick_scenario {func_ss func_ff} *tt*] ok n m
check "scenario pick: no match -> not ok, names listed" {$ok == 0 && [string match "*func_ss, func_ff*no match*skipped*" $m]}
lassign [diag084_pick_scenario {func_ss func_ss_2 func_ff} *ss*] ok n m
check "scenario pick: two matches -> not ok (never a silent choice)" {$ok == 0 && [string match "*matches 2*" $m]}
set sdc "# comment\ncreate_clock -name clk -period 20 \[get_ports clk\]\nset_input_delay -clock clk -max 7.0 \[get_ports {paddr\[*\]}\]\nset_input_delay -clock clk -network_latency_included -max 8.0 \[get_ports {dma_rdata\[*\]}\]\nset_clock_latency -source 0.2 \[get_clocks clk\]\nset_output_delay -clock clk -source_latency_included -max 8.0 \[get_ports {dma_addr\[*\]}\]\nset_propagated_clock \[get_clocks clk\]\nset_clock_uncertainty -setup 1.5 \[get_clocks clk\]\n"
set io [diag084_sdc_io_lines $sdc]
check "sdc lines: 6 relevant lines kept" {[llength [dict get $io lines]] == 6}
check "sdc lines: option counts" {[dict get $io network_incl] == 1 && [dict get $io source_incl] == 1 && [dict get $io latency] == 1}
set io [diag084_sdc_io_lines "set_input_delay 0 \[all_inputs\] -clock clk\n"]
check "sdc lines: none of the latency options present -> counts 0" {[dict get $io network_incl] == 0 && [dict get $io source_incl] == 0 && [dict get $io latency] == 0}
check "help list: one line per command, blank lines dropped" {[llength [diag084_help_list " set_path_margin # x\n\n report_x # y\n"]] == 2}

# ---- the script itself never writes into a library ---------------------------------------------------------------------------------------------
set body [string range $src [expr {$e + 1}] end]
set code {}
foreach l [split $body "\n"] { set t [string trim $l]; if {$t ne "" && [string index $t 0] ne "#"} { lappend code $t } }
foreach bad {save_block save_lib write_verilog write_gds write_lef set_app_options set_clock_uncertainty set_clock_latency set_input_delay set_output_delay set_scenario_status remove_* set_dont_touch insert_buffer} {
    set n 0
    foreach l $code {
        if {[string match "puts *" $l]} { continue }
        foreach w [split $l " \t\{\}\[\]\""] { if {[string match $bad $w]} { incr n; puts "  found: $l" } }
    }
    check "script code does not call $bad" {$n == 0}
}
check "the library is opened with -read" {[string first "open_lib -read" $src] > 0 && [string first "open_block -read" $src] > 0}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
