# ==============================================================================
# Test: test_diag_io_whatif.tcl (task 086)
# Run : tclsh pnr_v2/test_diag_io_whatif.tcl   (no ICC2 needed)
# Tests the pure procs of pnr_v2/diag_io_whatif.tcl (between BEGIN/END PURE TCL 086; they use the parser/guard procs of block 084 of diag_io_latency.tcl):
#   the SDC I/O delay parser (ICC2-style lines of the legacy SDC), the rewriting for experiments A1a/A1b/A1c, the offset emulation A2 (cone ports excluded, only input -min and output -max),
#   the A0 helpers (set_clock_latency lines, per-block table, export grep), the stage-by-stage comparison of part B (PrimeTime's numbers from the progress log), the restore check,
#   the table row and the verdict (convention shown / in2out and reg-to-reg unchanged), and source checks (nothing is saved, no write into the library).
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
source $here/run_root.tcl
set dl [read_file $here/diag_io_latency.tcl]
set b [string first "# ---- BEGIN PURE TCL 084 ----" $dl]; set e [string first "# ---- END PURE TCL 084 ----" $dl]
eval [string range $dl $b $e]
set src [read_file $here/diag_io_whatif.tcl]
set b [string first "# ---- BEGIN PURE TCL 086 ----" $src]; set e [string first "# ---- END PURE TCL 086 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]
set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc near {a b {tol 1e-6}} { return [expr {abs($a - $b) <= $tol}] }

# ---- 1. tokens and the I/O delay parser ----------------------------------------------------------------------------------------------------------
check "tokens keep bracket and brace groups whole" {[wi086_tokens {set_input_delay -clock [get_clocks clk] -max 7.0 [get_ports {paddr[*] pwdata[*]}]}] eq {set_input_delay -clock {[get_clocks clk]} -max 7.0 {[get_ports {paddr[*] pwdata[*]}]}}}
check "tokens: nested brackets" {[llength [wi086_tokens {a [b [c d] e] f}]] == 3}
set sdc {
# comment
create_clock -name clk -period 20 [get_ports clk]
set_input_delay -clock [get_clocks clk] -max 7 [get_ports {paddr[*]}]
set_input_delay -clock [get_clocks clk] -min 1 [get_ports {paddr[*]}]
set_input_delay -clock [get_clocks clk] -max 8 [get_ports {dma_rdata[*] dma_ready}]
set_input_delay -clock [get_clocks clk] -min 0 [get_ports {dma_rdata[*] dma_ready pwdata[*]}]
set_output_delay -clock [get_clocks clk] -max 7 [get_ports {prdata[*] pready}]
set_output_delay -clock [get_clocks clk] -min 0 [get_ports {prdata[*] pready}]
set_output_delay -clock [get_clocks clk] -max 8 [get_ports {dma_addr[*] dma_valid}]
set_output_delay -clock [get_clocks clk] -min -0.5 [get_ports {dma_addr[*] dma_valid}]
set_input_delay 3.0 -clock clk -max -add_delay [all_inputs]
set_driving_cell -lib_cell buffd1 -pin Z [get_ports {dma_rdata[*]}]
}
lassign [wi086_parse_io $sdc] ios bad
check "parser: 9 commands, none unparsed" {[llength $ios] == 9 && [llength $bad] == 0}
set d0 [lindex $ios 0]
check "parser: kind clock minmax value objs" {[dict get $d0 kind] eq "in" && [dict get $d0 clock] eq "\[get_clocks clk\]" && [dict get $d0 minmax] eq "max" && [dict get $d0 value] == 7 && [dict get $d0 objs] eq "\[get_ports \{paddr\[*\]\}\]"}
check "parser: output kind" {[dict get [lindex $ios 4] kind] eq "out" && [dict get [lindex $ios 4] minmax] eq "max"}
check "parser: negative value and -min" {[dict get [lindex $ios 7] value] == -0.5 && [dict get [lindex $ios 7] minmax] eq "min"}
check "parser: -add_delay kept as a flag and the value placed before the options" {[dict get [lindex $ios 8] flags] eq "-add_delay" && [dict get [lindex $ios 8] value] == 3.0 && [dict get [lindex $ios 8] objs] eq "\[all_inputs\]"}
lassign [wi086_parse_io "set_input_delay -clock clk -max \[get_ports x\]\nset_output_delay 5 \[get_ports y\]"] i2 b2
check "parser: lines it cannot understand are returned, never dropped" {[llength $i2] == 0 && [llength $b2] == 2}
check "parser: set_driving_cell and create_clock are not I/O delay lines" {[llength [wi086_parse_io "create_clock -name clk\nset_driving_cell -lib_cell buffd1 x"]] == 2 && [llength [lindex [wi086_parse_io "create_clock -name clk\nset_driving_cell -lib_cell buffd1 x"] 0]] == 0}

# ---- 2. rewriting for A1 --------------------------------------------------------------------------------------------------------------------------
set l1 [wi086_line $d0 {-network_latency_included}]
check "A1a: the option is added, value, clock, min/max and object kept" {$l1 eq "set_input_delay -clock \[get_clocks clk\] -max -network_latency_included 7 \[get_ports \{paddr\[*\]\}\]"}
check "A1c: both options" {[string match "*-network_latency_included -source_latency_included 7*" [wi086_line $d0 {-network_latency_included -source_latency_included}]]}
check "an option already there is not added twice" {[llength [regexp -all -inline -- {-network_latency_included} [wi086_line [dict replace $d0 flags -network_latency_included] {-network_latency_included}]]] == 1}
check "-add_delay of the original is kept" {[string match "*-add_delay*" [wi086_line [lindex $ios 8] {-network_latency_included}]]}
set inports [list {paddr[0]} {paddr[1]} {paddr[2]} {dma_rdata[0]} {dma_rdata[1]} dma_ready {pwdata[0]} clk]
set outports [list {prdata[0]} {prdata[1]} pready {dma_addr[0]} {dma_addr[1]} dma_valid]
check "pattern match: brackets are literal, * is a wildcard" {[wi086_match {paddr[*]} {paddr[1]}] && ![wi086_match {paddr[*]} paddr1] && ![wi086_match {paddr[*]} paddr]  && [wi086_match dma_ready dma_ready] && ![wi086_match dma_ready dma_ready2]}
check "ports of a command" {[wi086_ports_of [lindex $ios 2] $inports] eq [list {dma_rdata[0]} {dma_rdata[1]} dma_ready]}
check "ports of an all_inputs command" {[wi086_ports_of [lindex $ios 8] $inports] eq $inports}
set a1 [wi086_experiments_a1 $ios -network_latency_included $inports $outports]
check "A1: one command per original command" {[llength $a1] == 9}
check "A1: port counts per command" {[lindex [lindex $a1 0] 1] == 3 && [lindex [lindex $a1 4] 1] == 3 && [lindex [lindex $a1 2] 1] == 3}
check "A1: total ports changed = sum" {[tcl::mathop::+ {*}[lmap x $a1 {lindex $x 1}]] == 3+3+3+4+3+3+3+3+8}

# ---- 3. emulation A2 ------------------------------------------------------------------------------------------------------------------------------
set em [wi086_emulate $ios $inports $outports {paddr[0] paddr[1] paddr[2]} {prdata[0] prdata[1] pready} 0.6413 0.8069]
check "A2: only input -min (3 lines incl. paddr group) and output -max lines are emitted" {[llength $em] >= 2}
set txts [lmap x $em {lindex $x 0}]
check "A2: the input min delay of the dma ports is lowered by 0.6413 (0 -> -0.6413)" {[llength [lsearch -all -inline -glob $txts "set_input_delay * -min -0.6413 *"]] >= 1}
check "A2: the output max delay of the dma ports is raised by 0.8069 (8 -> 8.8069)" {[llength [lsearch -all -inline -glob $txts "set_output_delay * -max 8.8069 *"]] == 1}
check "A2: cone input ports are not in any emitted command" {[string first "paddr" [join $txts " "]] < 0}
check "A2: the cone output ports (prdata, pready) are not in any emitted command" {[string first "prdata" [join $txts " "]] < 0 && [string first "pready" [join $txts " "]] < 0}
check "A2: max input lines and min output lines are untouched" {[llength [lsearch -all -inline -glob $txts "set_input_delay * -max *"]] == 0 && [llength [lsearch -all -inline -glob $txts "set_output_delay * -min *"]] == 0}
set np [tcl::mathop::+ {*}[lmap x $em {lindex $x 1}]]
check "A2: ports changed counted (dma_rdata 2, dma_ready, pwdata bit 0 = 4 inputs; dma_addr 2, dma_valid = 3 outputs)" {$np == 4 + 3}
check "A2: a command whose ports are all in the cone is skipped" {[llength [wi086_emulate [lrange $ios 0 1] $inports $outports {paddr[0] paddr[1] paddr[2]} {} 0.6 0.8]] == 0}

# ---- 4. A0 helpers ------------------------------------------------------------------------------------------------------------------------------------
set sdcA "create_clock x\nset_clock_latency 0.806866 \[get_clocks \{clk\}\]\nset_clock_latency -source 0.2 \[get_clocks clk\]\nset_clock_uncertainty 1.5 clk\n"
set cl [wi086_clock_latency_lines $sdcA]
check "A0: both set_clock_latency lines found, nothing else" {[llength $cl] == 2}
check "A0: values read" {[dict get [lindex $cl 0] value] == 0.806866 && [dict get [lindex $cl 1] value] == 0.2 && [dict get [lindex $cl 1] flags] eq "-source"}
check "A0: none in a clean SDC" {[llength [wi086_clock_latency_lines "create_clock x\nset_clock_uncertainty 1.5 clk\n"]] == 0}
lassign [wi086_a0_table [list {unpu_top_placement func_ss 0 {}} {unpu_top_placement func_ff 0 {}} {unpu_top_cts func_ss 1 0.8} {unpu_top_cts func_ff 1 0.38} {unpu_top_route func_ss 1 0.8} {unpu_top_route func_ff 1 0.38}]] tl first
check "A0 table: one line per block and scenario" {[llength $tl] == 6}
check "A0 table: the first block per scenario is the CTS block" {[string match "*func_ss: first in unpu_top_cts*func_ff: first in unpu_top_cts*" $first]}
lassign [wi086_a0_table [list {b1 s 0 {}} {b2 s 0 {}}]] tl first
check "A0 table: never when every block has 0 lines" {[string match "*never*" $first]}
lassign [wi086_a0_table [list {b1 s -1 {}}]] tl first
check "A0 table: an unwritten SDC (-1) is not counted as present" {[string match "*never*" $first]}
set hits [wi086_scan_sdc /x/unpu_top_pnr_ss.sdc "a\nb\nset_clock_latency 0.806866 \[get_clocks \{clk\}\]\n"]
check "export grep: file, line number and text" {[llength $hits] == 1 && [lindex [lindex $hits 0] 1] == 3 && [string match "set_clock_latency 0.806866*" [lindex [lindex $hits 0] 2]]}
check "export grep: a clean file gives nothing" {[llength [wi086_scan_sdc /x/y.sdc "create_clock\n"]] == 0}
check "export dir: not set -> default" {[wi086_export_dir /d NONE] eq {/d default}}
check "export dir: set -> environment" {[wi086_export_dir /d /other] eq {/other {environment UNPU_WI_EXPORT_DIR}}}
check "export dir: empty -> ERROR 086" {[catch {wi086_export_dir /d ""} m] && [string match "ERROR 086*empty*" $m]}

# ---- 5. launch rows and stage comparison (part B) ----------------------------------------------------------------------------------------------------
set icc {
  Startpoint: dma_rdata[14] (input port clocked by clk)
  Endpoint: u_dma/stage_reg_1__14_ (rising edge-triggered flip-flop clocked by clk)
  Path Group: clk
  Path Type: min

  Point                                    Incr       Path
  -----------------------------------------------------------
  clock clk (rise edge)                  0.0000     0.0000
  clock network delay (propagated)       0.3798     0.3798
  input external delay                   0.0000     0.3798 f
  dma_rdata[14] (in)                     0.2615     0.6413 f
  copt_h_inst_3910/Z (buffd1)            0.1700     0.8113 f
  U588/Z (mx02d0)                        0.1200     0.9313 f
  u_dma/stage_reg_1__14_/D (dfcrq1)      0.0027     0.9340 f
  data arrival time                                 0.9340
}
set lr [wi086_launch_rows $icc 5]
check "launch rows: the first n rows of the launch half" {[llength $lr] == 5 && [string match "clock clk (rise edge)*" [lindex $lr 0]]}
set sr [wi086_stage_rows $icc]
check "stage rows: only rows with an increment, no clock lines" {[llength $sr] == 5 && [lindex [lindex $sr 0] 0] eq "input external delay"}
set pt {{{input external delay} {} 0.00} {{dma_rdata[14] (in)} {} 0.26} {{copt_h_inst_3910/Z} buffd1 0.17} {{U588/Z} mx02d0 0.12}}
set cmp [wi086_stage_cmp $sr $pt 0.02]
check "stage cmp: every stage listed, an extra ICC2 stage shows as (no stage)" {[llength [lsearch -all -inline -glob $cmp "stage *"]] == 5 && [string match "*(no stage)*" [lindex $cmp 4]]}
check "stage cmp: equal stages are not flagged" {[string first "differs" [lindex $cmp 1]] < 0}
set icc_short [wi086_stage_rows [string map {0.2615 0.0100} $icc]]
set cmp2 [wi086_stage_cmp $icc_short $pt 0.02]
check "stage cmp: a stage 0.25 ns smaller than PrimeTime's is flagged and named as the largest" {[string match "*differs by more than 0.02*" [lindex $cmp2 1]] && [string match "largest stage difference: stage 1, -0.2500*" [lindex $cmp2 end]]}

# ---- 6. restore check, rows, verdict ---------------------------------------------------------------------------------------------------------------------
set pa [diag084_parse $icc]
check "parse of the ICC2-style text: launch = the clock network delay row (0.3798), not 0.6413" {[near [dict get $pa launch] 0.3798 1e-9]}
check "parse: data delay = arrival - launch = 0.5542 (PrimeTime 0.56)" {[near [expr {[dict get $pa arrival] - [dict get $pa launch]}] 0.5542 1e-9]}
check "restore: identical -> no problem" {[llength [wi086_restore_check $pa $pa 0.0001]] == 0}
set pb [dict replace $pa slack 0.1]
check "restore: a changed slack is named" {[string match "slack: baseline*" [lindex [wi086_restore_check $pa $pb 0.0001] 0]]}
check "restore: n/a on one side is a problem" {[llength [wi086_restore_check $pa [dict replace $pa launch n/a] 0.0001]] == 1}
check "restore: both n/a is not a problem" {[llength [wi086_restore_check [dict replace $pa launch n/a] [dict replace $pa launch n/a] 0.0001]] == 0}
set base [dict create hold_launch 0.6413 hold_capture 0.3997 hold_arrival 0.934 hold_slack 0.0308 setup_capture 0.8069 setup_required 11.3069 setup_slack 0.3318 beat_launch 0.92 io_setup 0.0212 io_hold 0.0068 r2r_setup 2.5 r2r_hold 0.12 changed 0 failed 0]
set good [dict replace $base hold_launch 0.0 setup_capture 0.0 changed 12 failed 0]
set badm [dict replace $base hold_launch 0.0 setup_capture 0.0 io_setup -0.5 r2r_hold 0.30 changed 12]
set none [dict replace $base hold_launch 0.40 setup_capture 0.80]
set rowtxt [wi086_row A0 $good]
check "row: shows launch, capture, reg-to-reg and the counts" {[string match "A0 *launch 0.0000*capture 0.0000*reg-to-reg setup 2.5000 hold 0.1200*constraints changed 12*" $rowtxt]}
set vd [wi086_verdict_a [list [list A0 $good] [list A1a $badm] [list A1b $none]] $base 0.05 0.005]
check "verdict: convention shown, in2out and reg-to-reg unchanged" {[string match "A0: SHOWS THE PRIMETIME CONVENTION*in2out unchanged*reg-to-reg unchanged*" [lindex $vd 0]]}
check "verdict: convention shown but in2out and reg-to-reg changed -> both named" {[string match "A1a: SHOWS*in2out CHANGED (io_setup moved -0.5212)*reg-to-reg CHANGED (r2r_hold moved +0.1800)*" [lindex $vd 1]]}
check "verdict: not shown" {[string match "A1b: does NOT show it*" [lindex $vd 2]]}
set vd2 [wi086_verdict_a [list [list A2 $none]] $base 0.05 0.005 [dict create hold_slack -0.35 setup_slack -0.24]]
check "verdict A2: judged by the slacks with PrimeTime's numbers beside, not by launch/capture" {[string match "A2: emulation by offsets; hold slack 0.0308*PrimeTime: hold -0.3500, dma_addr\\\[31\\\] setup -0.2400*" [lindex $vd2 0]]}
check "verdict: unreadable launch -> INCONCLUSIVE" {[string match "*INCONCLUSIVE*" [lindex [wi086_verdict_a [list [list X [dict replace $good hold_launch n/a]]] $base 0.05 0.005] 0]]}
check "help lines: only the latency lines" {[llength [wi086_help_latency_lines "a\n -network_latency_included  (x latency)\nb\n-rise\n"]] == 1}
check "help has option" {[wi086_help_has "foo -source_latency_included bar" -source_latency_included] && ![wi086_help_has "foo" -source_latency_included]}

# ---- 7. source checks ---------------------------------------------------------------------------------------------------------------------------------------
set code {}
foreach l [split [string range $src [expr {$e + 1}] end] "\n"] { set t [string trim $l]; if {$t ne "" && [string index $t 0] ne "#"} { lappend code $t } }
foreach bad {save_block save_lib write_verilog write_gds write_lef write_parasitics} {
    set n 0
    foreach l $code { if {[string match "puts *" $l]} continue; foreach w [split $l " \t\{\}\[\]\""] { if {[string match $bad $w]} { incr n; puts "  found: $l" } } }
    check "script code does not call $bad" {$n == 0}
}
set wsdc 0
foreach l $code { if {[regexp {write_sdc} $l] && ![regexp {DIAG_DIR|\$f|\$sdc_file|\$\{f\}} $l] && ![string match "puts *" $l]} { incr wsdc; puts "  write_sdc elsewhere: $l" } }
check "every write_sdc goes into the diag folder (a variable that holds a diag path)" {$wsdc == 0}
check "the library is opened with open_lib and the guard runs before" {[string first "diag084_lib_check" $src] > 0 && [string first "diag084_lib_check" $src] < [string first "open_lib \$DIAG_LIB" $src]}
check "the restore check exists for every experiment (wi_open + wi_measure restore)" {[string first "RESTORE CHECK" $src] > 0 && [string first "wi_measure \${label}_restore" $src] > 0}
check "the experiments list starts with A0" {[string first "lappend experiments \[list A0 REMOVE\]" $src] > 0}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
