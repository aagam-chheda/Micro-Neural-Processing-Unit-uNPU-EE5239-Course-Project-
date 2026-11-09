# ==============================================================================
# Test: test_pt_eco_apply.tcl (task 079)
# Run : tclsh pnr_v2/test_pt_eco_apply.tcl   (from the repository root; no ICC2 needed)
# Tests the pure-Tcl block of pnr_v2/pt_eco_apply.tcl: the change-file parser, the count check, the reference table and don't-use check, the name checks, deferred pins,
# the topology rule for driver-pin and load-pin insertions, the ANTENNA WATCH classification, the placement of wide cells and the growth plan of size_cell.
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {f} { set fp [open $f r]; set s [read $fp]; close $fp; return $s }
# the 068 pure block (ant_manhattan, ant_dont_use, ant_filler_runs, ant_site_candidates, ...) from antenna_port_buffers.tcl
set a [read_file $here/antenna_port_buffers.tcl]
set b [string first "# ---- BEGIN PURE TCL 068 ----" $a]; set e [string first "# ---- END PURE TCL 068 ----" $a]
eval [string range $a $b $e]
set src [read_file $here/pt_eco_apply.tcl]
set b [string first "# ---- BEGIN PURE TCL 079 ----" $src]; set e [string first "# ---- END PURE TCL 079 ----" $src]
if {$b < 0 || $e < $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}

# ---- 1. the parser on the three real lines of the task excerpt
set ex "current_instance\ncurrent_instance {u_apb}\ninsert_buffer \[get_pins {U46/Z}\] dl02d1 -new_net_names {net_PTECO_HOLD_NET1} -new_cell_names {U_PTECO_HOLD_BUF1}\ncurrent_instance\ninsert_buffer \[get_pins {U61/Z}\] dl01d2 -new_net_names {net_PTECO_HOLD_NET2} -new_cell_names {U_PTECO_HOLD_BUF2}\ncurrent_instance\n"
set pr [eco079_parse $ex]
set cmds [dict get $pr cmds]
check "excerpt: no parse errors, 2 commands" {[llength [dict get $pr errors]] == 0 && [llength $cmds] == 2}
set c1 [lindex $cmds 0]; set c2 [lindex $cmds 1]
check "excerpt: first command in u_apb: full pin, ref, new names with the hierarchy" {[dict get $c1 full_pin] eq "u_apb/U46/Z" && [dict get $c1 ref] eq "dl02d1" && [dict get $c1 cell] eq "u_apb/U_PTECO_HOLD_BUF1" && [dict get $c1 net] eq "u_apb/net_PTECO_HOLD_NET1" && [dict get $c1 hier] eq "u_apb"}
check "excerpt: the empty current_instance resets to the top" {[dict get $c2 hier] eq "" && [dict get $c2 full_pin] eq "U61/Z" && [dict get $c2 cell] eq "U_PTECO_HOLD_BUF2" && [dict get $c2 ref] eq "dl01d2"}
check "excerpt: indexes and file line numbers" {[dict get $c1 idx] == 1 && [dict get $c2 idx] == 2 && [dict get $c1 line] == 3 && [dict get $c2 line] == 5}
# the test data file: the first 20 lines of the REAL pt_eco_hold_changes_icc2.tcl (server run, commit 4975454), verbatim
set pf [eco079_parse [read_file $here/testdata/pt_eco_hold_changes_head.tcl]]
set pc [dict get $pf cmds]
check "real head: 6 commands (4 get_pins/2 get_ports... see below), no errors" {[llength $pc] == 6 && [llength [dict get $pf errors]] == 0}
check "real head: kinds are pin, pin, pin, port, port, pin" {[lmap c $pc {dict get $c objkind}] eq {pin pin pin port port pin}}
check "real head: the third command (u_apb/U29/Z, dl01d1) belongs to the second u_apb block" {[dict get [lindex $pc 2] full_pin] eq "u_apb/U29/Z" && [dict get [lindex $pc 2] ref] eq "dl01d1" && [dict get [lindex $pc 2] cell] eq "u_apb/U_PTECO_HOLD_BUF3"}
set p4 [lindex $pc 3]; set p5 [lindex $pc 4]
check "get_ports: port name with brackets, no hierarchy prefix, top-level new names" {[dict get $p4 full_pin] eq "dma_rdata\[14\]" && [dict get $p4 cell] eq "U_PTECO_HOLD_BUF4" && [dict get $p4 net] eq "net_PTECO_HOLD_NET4" && [dict get $p4 hier] eq "" && [dict get $p4 ref] eq "dl01d1" && [dict get $p4 objkind] eq "port"}
check "get_ports: the second port insertion follows without a current_instance in between" {[dict get $p5 full_pin] eq "dma_rdata\[22\]" && [dict get $p5 idx] == 5 && [dict get $p5 line] == 17}
check "real head: the last command is in u_dma (copt_h_inst_3077/Z, dl02d1)" {[dict get [lindex $pc 5] full_pin] eq "u_dma/copt_h_inst_3077/Z" && [dict get [lindex $pc 5] ref] eq "dl02d1" && [dict get [lindex $pc 5] objkind] eq "pin"}
set gp [eco079_parse "current_instance {u_dma}\ninsert_buffer \[get_ports {dma_rdata\[3\]}\] dl01d1 -new_net_names {n} -new_cell_names {c}\n"]
check "get_ports under a non-empty current_instance -> error (not supported), nothing returned" {[llength [dict get $gp cmds]] == 0 && [string match "line 2: get_ports under current_instance {u_dma}*" [lindex [dict get $gp errors] 0]]}
set gp2 [eco079_parse "insert_buffer \[get_pins {u_csr/reg_a_reg\[3\]/D}\] buffd1 -new_net_names {n} -new_cell_names {c}\n"]
check "get_pins with brackets in the instance name" {[llength [dict get $gp2 errors]] == 0 && [dict get [lindex [dict get $gp2 cmds] 0] full_pin] eq "u_csr/reg_a_reg\[3\]/D"}
# the load-pin and gate-output forms of the earlier .txt example (pins relative to the hierarchy)
set gp3 [eco079_parse "current_instance {u_csr}\ninsert_buffer \[get_pins {dest_c_reg_reg_2_/D}\] buffd1 -new_net_names {a} -new_cell_names {b}\ninsert_buffer \[get_pins {U81/ZN}\] dl01d1 -new_net_names {c} -new_cell_names {d}\n"]
check "load pin and gate output pin forms" {[dict get [lindex [dict get $gp3 cmds] 0] full_pin] eq "u_csr/dest_c_reg_reg_2_/D" && [dict get [lindex [dict get $gp3 cmds] 1] full_pin] eq "u_csr/U81/ZN"}
# the real setup change file: size_cell with braces around the instance and the reference
set sf [eco079_parse [read_file $here/testdata/pt_eco_setup_changes_head.tcl]]
set sc [dict get $sf cmds]
check "real setup file: one command, no errors" {[llength $sc] == 1 && [llength [dict get $sf errors]] == 0}
check "real setup file: size_cell {HFSINV_13_284} {inv0d7} -> instance HFSINV_13_284, reference inv0d7 (braces removed), top level" {[dict get [lindex $sc 0] full_inst] eq "HFSINV_13_284" && [dict get [lindex $sc 0] ref] eq "inv0d7" && [dict get [lindex $sc 0] hier] eq "" && [dict get [lindex $sc 0] type] eq "size_cell"}
set sh [eco079_parse "current_instance {u_dma}\nsize_cell {U5} {inv0d7}\n"]
check "size_cell: the hierarchy of the preceding current_instance is applied" {[dict get [lindex [dict get $sh cmds] 0] full_inst] eq "u_dma/U5"}
foreach badsz [list "size_cell \x7bA\x7d" "size_cell \x7bA\x7d \x7binv0d7\x7d \x7bx\x7d" "size_cell \x7bA \x7binv0d7\x7d" "size_cell -foo \x7bA\x7d \x7binv0d7\x7d"] {
    set r [eco079_parse $badsz]
    check "size_cell form not understood -> listed: $badsz" {[llength [dict get $r cmds]] == 0 && [llength [dict get $r errors]] == 1 && [string match "line 1: size_cell form not understood*" [lindex [dict get $r errors] 0]]}
}
# unknown commands and options
set bad [eco079_parse "current_instance {u_dma}\nset_dont_touch \[get_cells x\]\ninsert_buffer \[get_pins {U1/Z}\] dl01d1 -new_net_names {n} -new_cell_names {c} -foo bar\ninsert_buffer \[get_pins {U1/Z}\] dl01d1 -new_net_names {n}\nremove_buffer \[get_cells U9\]\n"]
check "unknown command -> error listed with its line" {[llength [dict get $bad errors]] == 4 && [string match "line 2: command not understood: set_dont_touch*" [lindex [dict get $bad errors] 0]]}
check "unknown option on insert_buffer -> error" {[string match "line 3: insert_buffer has options this script does not understand: '-foo bar'" [lindex [dict get $bad errors] 1]]}
check "insert_buffer without both names -> error" {[string match "line 4: insert_buffer without both*" [lindex [dict get $bad errors]  2]]}
check "no command is returned from the bad lines" {[llength [dict get $bad cmds]] == 0}
# size_cell, both spellings
set sz [eco079_parse "current_instance\nsize_cell {HFSINV_13_284} inv0d8\nsize_cell \[get_cells {u_dma/U5}\] inv0d4\n"]
check "size_cell: instance and reference, both syntaxes" {[llength [dict get $sz errors]] == 0 && [dict get [lindex [dict get $sz cmds] 0] full_inst] eq "HFSINV_13_284" && [dict get [lindex [dict get $sz cmds] 0] ref] eq "inv0d8" && [dict get [lindex [dict get $sz cmds] 1] full_inst] eq "u_dma/U5"}
check "comments and blank lines are ignored" {[llength [dict get [eco079_parse "# a\n\n   \n# b\n"] cmds]] == 0}
# ---- 2. count check: 109 expected
check "count: 109 found, 109 expected -> ok" {[lindex [eco079_count_check "hold change file commands" 109 109] 0] == 1}
lassign [eco079_count_check "hold change file commands" 108 109] ok msg
check "count: 108 found, 109 expected -> error with both numbers" {$ok == 0 && [string match "*108 but 109 expected*" $msg]}
# ---- 3. reference table (hold run: dl01d1 64, dl02d1 31, buffd1 12, dl01d2 2)
set many {}
foreach {r n} {dl01d1 64 dl02d1 31 buffd1 12 dl01d2 2} { for {set i 0} {$i < $n} {incr i} { lappend many [dict create type insert_buffer ref $r idx [expr {[llength $many] + 1}]] } }
set rt [eco079_ref_table $many]
check "reference table: the counts of the user's run, total 109" {[dict get $rt dl01d1] == 64 && [dict get $rt dl02d1] == 31 && [dict get $rt buffd1] == 12 && [dict get $rt dl01d2] == 2 && [llength $many] == 109}
set libn {dl01d1 dl02d1 buffd1 dl01d2 inv0d4 adiode}
check "references: all in the library, none don't-use -> no problem" {[eco079_ref_problems {dl01d1 dl02d1 buffd1 dl01d2} $libn {slnht* skbrb* slbhb* slnhn* slnln* mx08d* adiode bh01d1 cload1}] eq ""}
check "references: a missing reference is reported" {[eco079_ref_problems {dl09d9} $libn {adiode}] eq "{reference dl09d9 is not in the library}"}
check "references: adiode is don't-use" {[string match "*adiode matches the don't-use pattern adiode*" [eco079_ref_problems {adiode} $libn {adiode bh01d1}]]}
check "references: mx08d1 matches mx08d*" {[string match "*matches the don't-use pattern mx08d**" [eco079_ref_problems {mx08d1} {mx08d1} {mx08d*}]]}
# ---- 4. names
set two [list [dict create type insert_buffer idx 1 cell u_apb/U_PTECO_HOLD_BUF1 net u_apb/net_PTECO_HOLD_NET1] [dict create type insert_buffer idx 2 cell u_apb/U_PTECO_HOLD_BUF1 net u_apb/net_PTECO_HOLD_NET2]]
check "names: a cell name used twice is reported" {[llength [eco079_name_problems $two {} {}]] == 1 && [string match "new cell name u_apb/U_PTECO_HOLD_BUF1 used twice*" [lindex [eco079_name_problems $two {} {}] 0]]}
check "names: an existing cell or net stops" {[llength [eco079_name_problems [lrange $two 0 0] {u_apb/U_PTECO_HOLD_BUF1} {u_apb/net_PTECO_HOLD_NET1}]] == 2}
check "names: the 6 real commands have unique new names -> no problem" {[eco079_name_problems $pc {} {}] eq ""}
# ---- 5. deferred pins: a pin of a cell that an earlier insertion creates
set dc [list [dict create idx 1 type insert_buffer cell u_dma/U_PTECO_HOLD_BUF3] [dict create idx 2 type insert_buffer cell u_dma/U_PTECO_HOLD_BUF4]]
check "deferred: the pin U_PTECO_HOLD_BUF3/Z of change 2 belongs to the cell created by change 1" {[eco079_is_deferred $dc 2 u_dma/U_PTECO_HOLD_BUF3/Z 0] == 1}
check "deferred: the pin of an existing cell is not deferred" {[eco079_is_deferred $dc 2 u_dma/copt_h_inst_3080/Z 0] == 0}
check "deferred: a cell created LATER is not deferred for an earlier change" {[eco079_is_deferred $dc 1 u_dma/U_PTECO_HOLD_BUF4/Z 0] == 0}
check "pin cell: the part before the last slash" {[eco079_pin_cell u_dma/copt_h_inst_3080/Z] eq "u_dma/copt_h_inst_3080" && [eco079_pin_cell Z] eq ""}
# ---- 6. topology: driver-pin vs load-pin insertion
# driver pin U1/Z with loads a/D b/D c/D: the buffer takes ALL loads
check "driver pin: buffer input with the driver, output with all loads -> as assumed" {[eco079_topology_problems out U1/Z {U1/Z a/D b/D c/D} {U1/Z B/I} {B/Z a/D b/D c/D} B/I B/Z] eq ""}
check "driver pin: only one load moved behind the buffer -> problem" {[llength [eco079_topology_problems out U1/Z {U1/Z a/D b/D c/D} {U1/Z B/I b/D c/D} {B/Z a/D} B/I B/Z]] == 2}
# load pin a/D: isolates that one load
check "load pin: the load alone behind the buffer, the others stay -> as assumed" {[eco079_topology_problems in a/D {U1/Z a/D b/D c/D} {U1/Z b/D c/D B/I} {B/Z a/D} B/I B/Z] eq ""}
check "load pin: all loads moved behind the buffer (driver-pin behaviour) -> problem" {[llength [eco079_topology_problems in a/D {U1/Z a/D b/D c/D} {U1/Z B/I} {B/Z a/D b/D c/D} B/I B/Z]] == 2}
check "topology: an unknown direction is reported" {[string match "*neither out, in nor port*" [lindex [eco079_topology_problems inout p {p} {p} {p} i z] 0]]}
# input PORT: the port stays on the net with the buffer input, every load moves behind the buffer
check "port: loads a/D b/D behind the buffer, buffer input alone on the port net -> as assumed" {[eco079_topology_problems port dma_rdata\[14\] {a/D b/D} {B/I} {B/Z a/D b/D} B/I B/Z] eq ""}
check "port: one load left on the port net -> problem" {[llength [eco079_topology_problems port p {a/D b/D} {B/I a/D} {B/Z b/D} B/I B/Z]] == 2}
check "port with an antenna buffer: the new cell goes between the port and antbuf_x/I" {[eco079_topology_problems port pwdata\[0\] {antbuf_pwdata_0_/I} {B/I} {B/Z antbuf_pwdata_0_/I} B/I B/Z] eq ""}
check "port with an antenna buffer: antbuf_x/I still on the port net -> problem" {[llength [eco079_topology_problems port pwdata\[0\] {antbuf_pwdata_0_/I} {B/I antbuf_pwdata_0_/I} {B/Z} B/I B/Z]] == 2}
# ---- 7. ANTENNA WATCH
check "driver kind: an input port on the net -> port" {[eco079_driver_kind {} 1 antbuf] eq "port"}
check "driver kind: the output of antbuf_x_3 -> antbuf (also inside a hierarchy)" {[eco079_driver_kind {antbuf_pwdata_0__3_t1a1} 0 antbuf] eq "antbuf" && [eco079_driver_kind {u_x/antbuf_a} 0 antbuf] eq "antbuf"}
check "driver kind: an ordinary cell -> other" {[eco079_driver_kind {U46} 0 antbuf] eq "other"}
check "watch reason: port and antbuf have a text, other has none" {[eco079_watch_reason port] ne "" && [eco079_watch_reason antbuf] ne "" && [eco079_watch_reason other] eq ""}
# ---- 8. placement of wide cells (delay cells are wider than buffd1): rows of fillers y=0..5.04
set site 0.56
proc frow {name x0 x1 y} { return [list $name $x0 $y $x1 [expr {$y + 5.04}] N] }
set rows {}
for {set i 0} {$i < 12} {incr i} { lappend rows [frow f$i [expr {10 + $i * 0.56}] [expr {10 + ($i + 1) * 0.56}] 0.0] }    ;# a run of 12 sites = 6.72 um at x 10..16.72
for {set i 0} {$i < 4} {incr i} { lappend rows [frow g$i [expr {40 + $i * 0.56}] [expr {40 + ($i + 1) * 0.56}] 5.04] }    ;# a narrow run of 4 sites = 2.24 um
set runs [ant_filler_runs $rows]
check "wide cell: a 5.6 um cell fits the 6.72 um run" {[llength [ant_site_candidates $runs 5.6 $site 12.0 2.5 40.0]] == 1}
check "wide cell: it needs 10 sites (5.6/0.56), the candidate removes only those fillers" {[llength [dict get [lindex [ant_site_candidates $runs 5.6 $site 12.0 2.5 40.0] 0] names]] == 10}
check "wide cell: a 7.0 um cell does NOT fit the 6.72 um run" {[llength [ant_site_candidates $runs 7.0 $site 12.0 2.5 40.0]] == 0}
check "wide cell: the narrow 2.24 um run is no candidate for a 5.6 um cell" {[llength [ant_site_candidates $runs 5.6 $site 41.0 7.5 40.0]] == 1 && [dict get [lindex [ant_site_candidates $runs 5.6 $site 41.0 7.5 40.0] 0] y] == 0.0}
check "narrow cell (2.2 um) uses the narrow run first when it is closer" {[dict get [lindex [ant_site_candidates $runs 2.2 $site 41.0 7.5 40.0] 0] y] == 5.04}
# ---- 9. growth plan for size_cell
set grow {}
for {set i 0} {$i < 6} {incr i} { lappend grow [frow h$i [expr {20 + $i * 0.56}] [expr {20 + ($i + 1) * 0.56}] 0.0] }
set gr [ant_filler_runs $grow]
lassign [eco079_grow_plan $gr 0.0 20.0 1.5 0.56] ok names why
check "grow: 1.5 um more width needs 3 sites; the free run at the right edge has 6 -> 3 fillers" {$ok == 1 && [llength $names] == 3 && $names eq {h0 h1 h2}}
lassign [eco079_grow_plan $gr 0.0 20.0 4.0 0.56] ok names why
check "grow: 4.0 um needs 8 sites, only 6 free -> reason with both widths" {$ok == 0 && [string match "*3.36 um wide, 4.48 um needed*" $why]}
lassign [eco079_grow_plan $gr 0.0 25.0 1.0 0.56] ok names why
check "grow: no free run at the right edge -> reason" {$ok == 0 && [string match "no free filler run starts*" $why]}
lassign [eco079_grow_plan $gr 5.04 20.0 1.0 0.56] ok names why
check "grow: another row -> no run" {$ok == 0}
# ---- 10. fix: antenna numbers read from antenna_port_buffers.tcl, input gate from the LEF, port limit, antbuf pins, expected protected moves
check "param from text: MAX_PIN_BUF_DIST of antenna_port_buffers.tcl is read, not typed" {[eco079_param_from_text $a MAX_PIN_BUF_DIST] == 40.0 && [eco079_param_from_text $a ANT_RATIO_LIMIT] == 400.0 && [eco079_param_from_text $a ANT_WEIGHT_PINWIRE] == 0.54 && [eco079_param_from_text $a WIRE_WIDTH_UM] == 0.28}
check "param from text: a missing name is an error" {[catch {eco079_param_from_text $a NO_SUCH_PARAMETER_X} err] == 1 && [string match "parameter NO_SUCH_PARAMETER_X not found*" $err]}
check "param from text: a non-number is an error" {[catch {eco079_param_from_text "set FOO abc\n" FOO} err] == 1 && [string match "*not a number*" $err]}
set lefx "MACRO dl01d1\n SIZE 5.04 BY 5.04 ;\n PIN I\n  DIRECTION INPUT ;\n  USE SIGNAL ;\n  ANTENNAGATEAREA 0.3969 ;\n END I\n PIN Z\n  DIRECTION OUTPUT ;\n  USE SIGNAL ;\n  ANTENNADIFFAREA 0.5 ;\n END Z\nEND dl01d1\nMACRO nand2\n SIZE 2.8 BY 5.04 ;\n PIN A\n  DIRECTION INPUT ;\n  USE SIGNAL ;\n  ANTENNAGATEAREA 0.1 ;\n END A\n PIN B\n  DIRECTION INPUT ;\n  USE SIGNAL ;\n  ANTENNAGATEAREA 0.1 ;\n END B\nEND nand2\n"
set lefd [ant_parse_lef $lefx]
check "in_gate: one signal input -> its ANTENNAGATEAREA (synthetic LEF text; the real widths and gate areas are read from the kit LEF at run time)" {[eco079_in_gate [dict get $lefd dl01d1]] == 0.3969}
check "in_gate: two inputs -> 0.0 (the port insertion would stop with the reason)" {[eco079_in_gate [dict get $lefd nand2]] == 0.0}
lassign [eco079_port_limit 0.3969 40.0 400.0 0.54 0.28] pl pt
check "port limit: the gate is large enough for 40 um -> 40, tier-1 text" {$pl == 40.0 && [string match "the tier-1 limit*" $pt]}
lassign [eco079_port_limit 0.1 40.0 400.0 0.54 0.28] pl pt
check "port limit: a small gate area limits the distance by the ratio (400*0.1/(2*0.54) - 0.28 = 36.8)" {abs($pl - 36.7593) < 0.01 && [string match "limited by the predicted antenna ratio*" $pt]}
lassign [eco079_port_limit 0.0 40.0 400.0 0.54 0.28] pl pt
check "port limit: unknown gate area -> 0 and a reason" {$pl == 0.0 && [string match "*unknown*" $pt]}
check "antbuf pins: only the leaf pins of cells named antbuf_*" {[eco079_antbuf_pins {antbuf_pwdata_0_/I u_dma/U5/A U9/B} antbuf] eq {antbuf_pwdata_0_/I}}
set mv [eco079_protected_moves {antbuf_x/I U9/B} {antbuf_x antbuf_y} pwdata\[0\]]
check "protected moves: the antbuf pin with its old net, the ordinary pin not" {[llength $mv] == 1 && [lindex $mv 0 0] eq "antbuf_x" && [lindex $mv 0 1] eq "I" && [lindex $mv 0 2] eq "pwdata\[0\]"}
set dsplit [eco079_diff_split {{antbuf_x: pin I net pwdata[0] -> net_PTECO_HOLD_NET9} {antbuf_x: pin Z net n1 -> n2} {antbuf_y: pin I net q -> net_PTECO_HOLD_NET1}} $mv PTECO]
check "diff split: the expected move is separated, a pin Z change and a pin of another cell stay as errors" {[llength [lindex $dsplit 1]] == 1 && [llength [lindex $dsplit 0]] == 2 && [string match "antbuf_x: pin I*" [lindex [lindex $dsplit 1] 0]]}
set dsplit2 [eco079_diff_split {{antbuf_x: pin I net pwdata[0] -> some_other_net}} $mv PTECO]
check "diff split: a move to a net that is NOT a PrimeTime net is not excused" {[llength [lindex $dsplit2 0]] == 1}
set wk [eco079_words " \x7bHFSINV_13_284\x7d  inv0d7 \[get_cells \x7bx\x7d\] "]
check "words: braced, bare and bracketed" {$wk eq {1 {HFSINV_13_284 inv0d7 {[get_cells {x}]}}}}
puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
