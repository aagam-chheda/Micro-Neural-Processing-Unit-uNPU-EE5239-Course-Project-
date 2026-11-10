# ==============================================================================
# Test: test_clock_latency.tcl (task 088)
# Run : tclsh pnr_v2/test_clock_latency.tcl   (no ICC2 needed)
# Tests pnr_v2/clock_latency.tcl: the pure counting/decision/grep procs; the ICC2 procs against a command-recording mock (counts, before 1 after 0, before 0 after 0 and NO command
# issued, after 1 -> ERROR 088, unreadable counts, scenario restore, no other command than the allowed ones); the source of the flow scripts (the shared file is sourced by the identical
# 4th bootstrap line, the proc is called after link_block in every listed script, pv.tcl removes before write_sdc and greps both exported SDCs, cts.tcl splits clock_opt and no longer
# sets clock_opt.hold.effort); the Part 0 script's parsers (UNPU_WI_LIB / UNPU_WI_BLOCKS).
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
set src [read_file $here/clock_latency.tcl]
set b [string first "# ---- BEGIN PURE TCL 088 ----" $src]; set e [string first "# ---- END PURE TCL 088 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
source $here/clock_latency.tcl   ;# the file holds only procs (pure and ICC2 side); the ICC2 commands are mocked below
set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}

# ---- 1. pure procs ----
set sdc1 "create_clock x\nset_clock_latency 0.806866 \[get_clocks \{clk\}\]\n# set_clock_latency 9\nset_clock_uncertainty 1.5 clk\n"
check "lines: one tool-made line found, comments and other commands ignored" {[llength [unpu_cl_lines $sdc1]] == 1}
check "lines: none in a clean SDC" {[llength [unpu_cl_lines "create_clock x\n"]] == 0}
check "lines: source latency lines count too" {[llength [unpu_cl_lines "set_clock_latency -source 0.2 \[get_clocks clk\]\nset_clock_latency 0.3 clk\n"]] == 2}
check "lines: a bare command word counts" {[llength [unpu_cl_lines "set_clock_latency"]] == 1}
check "lines: a command that only starts with the same letters does not count" {[llength [unpu_cl_lines "set_clock_latency_foo 1"]] == 0}
check "decide: 0 -> 0 is ok" {[lindex [unpu_cl_decide 0 0] 0] == 1}
check "decide: 1 -> 0 is ok" {[lindex [unpu_cl_decide 1 0] 0] == 1}
check "decide: 1 -> 1 is an error with both numbers" {[lindex [unpu_cl_decide 1 1] 0] == 0 && [string match "*1 set_clock_latency line(s) are still there*before 1*" [lindex [unpu_cl_decide 1 1] 1]]}
check "decide: 0 -> 1 (created by the removal?) is an error" {[lindex [unpu_cl_decide 0 1] 0] == 0}
foreach bad {"" n/a -1 abc 1.5} {
    check "decide: unreadable after '$bad' -> error, never a pass" {[lindex [unpu_cl_decide 1 $bad] 0] == 0 && [string match "*unreadable*" [lindex [unpu_cl_decide 1 $bad] 1]]}
}
check "decide: unreadable before -> error" {[lindex [unpu_cl_decide "" 0] 0] == 0}
check "summary line" {[unpu_cl_summary cts-x func_ss 1 0] eq ">>> 088 cts-x func_ss: set_clock_latency lines before 1, after 0"}
set hits [unpu_cl_scan /o/unpu_top_pnr_ss.sdc "a\nb\nset_clock_latency 0.806866 \[get_clocks \{clk\}\]\n"]
check "scan: file, line number, text" {[llength $hits] == 1 && [lindex [lindex $hits 0] 1] == 3}
check "scan: clean file -> nothing" {[llength [unpu_cl_scan /o/x.sdc "create_clock\n"]] == 0}

# ---- 2. the ICC2 procs against a recording mock ----
set ::LOG {}
set ::SCEN_CUR func_ss
array set ::LAT {func_ss 1 func_ff 1}
set ::RUN_ROOT [file normalize [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] "cl088_[pid]"]]
file delete -force $::RUN_ROOT
file mkdir $::RUN_ROOT
proc get_scenarios {args} { lappend ::LOG get_scenarios; return {s|func_ss s|func_ff} }
proc foreach_in_collection {var coll body} { upvar 1 $var v; foreach x $coll { set v $x; uplevel 1 $body } }
proc get_object_name {x} { return [lindex [split [lindex $x 0] |] 1] }
proc current_scenario {args} { lappend ::LOG [concat current_scenario $args]; if {[llength $args] == 0} { return [list s|$::SCEN_CUR] }; set ::SCEN_CUR [lindex $args 0]; return }
proc get_clocks {args} { lappend ::LOG [concat get_clocks $args]; return c|clk }
proc write_sdc {args} {
    lappend ::LOG [concat write_sdc $args]
    set f [lindex $args end]
    if {$::NOWRITE} { return }
    set fp [open $f w]
    puts $fp "create_clock x"
    if {$::LAT($::SCEN_CUR) > 0} { for {set i 0} {$i < $::LAT($::SCEN_CUR)} {incr i} { puts $fp "set_clock_latency 0.8 \[get_clocks \{clk\}\]" } }
    close $fp
}
proc remove_clock_latency {args} { lappend ::LOG [concat remove_clock_latency $args]; if {!$::STICKY} { set ::LAT($::SCEN_CUR) 0 } }
set ::NOWRITE 0; set ::STICKY 0
proc run_proc {script} { set ::LOG {}; set out ""; set rc [catch {set out [eval $script]} m]; return [list $rc $m] }
# before 1, after 0 in both scenarios
array set ::LAT {func_ss 1 func_ff 1}
set o [run_proc {unpu_remove_clock_latency testA}]
check "proc: before 1 / after 0 in both scenarios -> ok, returns the removed count 2" {[lindex $o 0] == 0 && [lindex $o 1] == 2}
set cmds [lmap l $::LOG {lindex $l 0}]
check "proc: remove_clock_latency issued once per scenario (2)" {[llength [lsearch -all -exact $cmds remove_clock_latency]] == 2}
set gc [lsearch -all -inline -exact [lmap l $::LOG {join $l " "}] "get_clocks -filter is_virtual == false"]
check "proc: the removal form is the one that worked in 086 (real clocks only)" {[llength $gc] >= 2}
check "proc: only allowed commands were issued" {[lsort -unique [lsearch -all -inline -not -regexp $cmds {^(get_scenarios|current_scenario|write_sdc|remove_clock_latency|get_clocks)$}]] eq ""}
check "proc: the current scenario is restored" {$::SCEN_CUR eq "func_ss"}
check "proc: the scratch SDC is written under pnr_icc2/diag" {[file exists $::RUN_ROOT/pnr_icc2/diag/clock_latency_func_ss.sdc]}
# before 0 / after 0: no command issued
array set ::LAT {func_ss 0 func_ff 0}
set o [run_proc {unpu_remove_clock_latency testB}]
set cmds [lmap l $::LOG {lindex $l 0}]
check "proc: clean block -> ok, 0 removed" {[lindex $o 0] == 0 && [lindex $o 1] == 0}
check "proc: clean block -> NO remove_clock_latency issued (idempotent, touches nothing)" {[lsearch -exact $cmds remove_clock_latency] < 0}
# still there after the removal -> error
array set ::LAT {func_ss 1 func_ff 1}
set ::STICKY 1
set o [run_proc {unpu_remove_clock_latency testC}]
check "proc: line still there after the removal -> ERROR 088 naming label and scenario" {[lindex $o 0] == 1 && [string match "ERROR 088: testC func_ss*still there*" [lindex $o 1]]}
set ::STICKY 0
# unreadable (no SDC written)
array set ::LAT {func_ss 1 func_ff 1}
set ::NOWRITE 1
set o [run_proc {unpu_remove_clock_latency testD}]
check "proc: write_sdc wrote no file -> ERROR 088 (never a pass)" {[lindex $o 0] == 1 && [string match "ERROR 088*wrote no file*" [lindex $o 1]]}
set ::NOWRITE 0
# count only: no remove
array set ::LAT {func_ss 1 func_ff 2}
set o [run_proc {unpu_clock_latency_count testE}]
set cmds [lmap l $::LOG {lindex $l 0}]
check "count: total over scenarios, no remove issued" {[lindex $o 1] == 3 && [lsearch -exact $cmds remove_clock_latency] < 0}
# grep of exported files
set d $::RUN_ROOT/outputs; file mkdir $d
set fp [open $d/a.sdc w]; puts $fp "create_clock x"; close $fp
set fp [open $d/b.sdc w]; puts $fp "create_clock x"; puts $fp "set_clock_latency 0.4 \[get_clocks \{clk\}\]"; close $fp
set o [run_proc [list unpu_clock_latency_grep t [list $d/a.sdc]]]
check "grep: clean file -> ok" {[lindex $o 0] == 0}
set o [run_proc [list unpu_clock_latency_grep t [list $d/a.sdc $d/b.sdc]]]
check "grep: a line left in an exported file -> ERROR 088 with count" {[lindex $o 0] == 1 && [string match "ERROR 088: t: 1 set_clock_latency line(s) in the exported SDC*" [lindex $o 1]]}
set o [run_proc [list unpu_clock_latency_grep t [list $d/none.sdc]]]
check "grep: a missing exported file -> ERROR 088 (not a silent pass)" {[lindex $o 0] == 1 && [string match "ERROR 088*does not exist*" [lindex $o 1]]}
file delete -force $::RUN_ROOT

# ---- 3. the proc source: no other command than the allowed ones ----
set pb [string range $src $e end]
set body {}
foreach l [split $pb "\n"] { set t [string trim $l]; if {$t ne "" && [string index $t 0] ne "#"} { lappend body $t } }
set j [join $body "\n"]
foreach bad {set_clock_uncertainty set_propagated_clock set_app_options set_input_delay set_output_delay save_block save_lib set_scenario_status set_clock_latency} {
    set n 0
    foreach l $body { if {[regexp "^${bad}(\\s|\$)" $l] || [regexp "(catch \\x7b|\\\[)${bad}(\\s|\$)" $l]} { incr n } }
    check "clock_latency.tcl does not issue $bad" {$n == 0}
}

# ---- 4. the flow scripts ----
set boot4 {source [file join [file dirname [file normalize [info script]]] clock_latency.tcl]}
set users {route fix_antenna timing_closure pt_eco_apply antenna_port_buffers antenna_clk_root metal_fill pv cts placement port_buffers_early powerplanning}
foreach f $users {
    set t [read_file $here/$f.tcl]
    set lines [split $t "\n"]
    set k -1
    for {set i 0} {$i < [llength $lines]} {incr i} { if {[string match "set RUN_ROOT *" [lindex $lines $i]]} { set k $i; break } }
    check "$f.tcl: the 4th bootstrap line (right after set RUN_ROOT) sources clock_latency.tcl" {$k >= 0 && [string first $boot4 [lindex $lines [expr {$k + 1}]]] == 0}
    check "$f.tcl: the 4th line is identical to the one of the other scripts" {[string trim [regsub {;#.*$} [lindex $lines [expr {$k + 1}]] ""]] eq $boot4}
    set po [string first "unpu_remove_clock_latency" $t [string first "clock_latency.tcl" $t]]
    check "$f.tcl: calls unpu_remove_clock_latency" {$po > 0}
    set pl [string first "link_block" $t [expr {$k > 0 ? 0 : 0}]]
    if {$f ne "cts" && $f ne "powerplanning" && $f ne "port_buffers_early"} {
        set after_boot [string first $boot4 $t]
        set pl [string first "\n    link_block\n" $t $after_boot]
        check "$f.tcl: the first call comes right after link_block (the block is open and linked)" {$pl > 0 && $po > $pl && ($po - $pl) < [expr {$f eq "pv" ? 1500 : 400}]}   ;# 091: pv.tcl has the checkpoint copy (save_block -as, reopen) between link_block and the removal, on purpose: the removal must land in the copy
    }
}
set pv [read_file $here/pv.tcl]
set pw1 [string first "write_sdc \\\n        -scenario func_ss" $pv]   ;# 096: the export write_sdc (pv.tcl has a temporary write_sdc in its 096 helper too)
set prem [string first "unpu_remove_clock_latency pv-before-write_sdc" $pv]
check "pv.tcl: removes the line again before the first write_sdc" {$prem > 0 && $prem < $pw1}
set pg [string first "unpu_clock_latency_grep pv-exported-sdc" $pv]
check "pv.tcl: greps the exported SDCs after the last write_sdc" {$pg > [string last "write_sdc" $pv]}
check "pv.tcl: the grep names both exported SDC files (ss and ff)" {[string match "*_pnr_ss.sdc*_pnr_ff.sdc*" [string range $pv $pg [expr {$pg + 260}]]]}
set cts_raw [read_file $here/cts.tcl]
set cts $cts_raw
check "cts.tcl: clock_opt is split into the three sub-steps" {[string first "clock_opt -to build_clock" $cts] > 0 && [string first "clock_opt -from route_clock -to route_clock" $cts] > 0 && [string first "clock_opt -from final_opto" $cts] > 0}
check "cts.tcl: the list of steps is checked with clock_opt -list_only" {[string first "clock_opt -list_only" $cts] > 0}
check "cts.tcl: the removal follows each part" {[string first "cts-after-build_clock" $cts] > [string first "clock_opt -to build_clock" $cts] && [string first "cts-after-final_opto" $cts] > [string first "clock_opt -from final_opto" $cts]}
check "cts.tcl: the unsplit fallback exists and says final_opto ran WITH the line" {[string first "UNPU_CTS_SPLIT" $cts] > 0 && [string first "final_opto ran WITH the line" $cts] > 0}
set cts_code [join [lsearch -all -inline -not -regexp [split $cts_raw "\n"] {^\s*#}] "\n"]
check "cts.tcl: no set_app_options for clock_opt.hold.effort remains (comments excluded)" {![regexp {set_app_options[^\n]*clock_opt\.hold\.effort} $cts_code]}
check "cts.tcl: the I/O reference line is printed" {[string first ">>> 088 I/O reference latency after the removal" $cts] > 0}
check "cts.tcl: no other CTS app option was added (the option lines are the same set as before)" {[llength [regexp -all -inline {set_app_options -name [A-Za-z_.]+} $cts_code]] == 2}

# ---- 5. Part 0 parsers ----
set o0 [read_file $here/diag_clock_latency_origin.tcl]
set b0 [string first "# ---- BEGIN PURE TCL 088O ----" $o0]; set e0 [string first "# ---- END PURE TCL 088O ----" $o0]
set dl [read_file $here/diag_io_latency.tcl]
eval [string range $dl [string first "# ---- BEGIN PURE TCL 084 ----" $dl] [string first "# ---- END PURE TCL 084 ----" $dl]]
eval [string range $o0 $b0 $e0]
check "origin: default library when the variable is not set" {[orig088_lib /d NONE] eq {/d default}}
check "origin: environment library" {[orig088_lib /d " /x "] eq {/x {environment UNPU_WI_LIB}}}
check "origin: empty library -> ERROR 088" {[catch {orig088_lib /d "  "} m] && [string match "ERROR 088*UNPU_WI_LIB*empty*" $m]}
check "origin: default blocks" {[orig088_blocks {a b} NONE] eq {{a b} default}}
check "origin: environment blocks (spaces and commas)" {[lindex [orig088_blocks {a} "x_1, y_2 z"] 0] eq {x_1 y_2 z}}
check "origin: empty list -> ERROR 088" {[catch {orig088_blocks {a} "  "} m] && [string match "ERROR 088*no block name*" $m]}
check "origin: an invalid name -> ERROR 088" {[catch {orig088_blocks {a} "ok bad;name"} m] && [string match "ERROR 088*bad;name*" $m]}
check "origin: block present as lib:block" {[orig088_present unpu_top_cts {unpu_top.dlib:unpu_top_cts unpu_top.dlib:unpu_top_route}]}
check "origin: block absent" {![orig088_present unpu_top_portbuf {unpu_top.dlib:unpu_top_cts}]}
check "origin: the script uses open_block -read and never saves" {[string first "open_block -read" $o0] > 0 && [string first "save_block" [regsub -all {#[^\n]*} $o0 ""]] < 0 && [string first "save_lib" [regsub -all {#[^\n]*} $o0 ""]] < 0}
check "origin: the guard runs before the library is opened" {[string first "diag084_lib_check \$ORIGIN_LIB" $o0] > 0 && [string first "diag084_lib_check \$ORIGIN_LIB" $o0] < [string first "open_lib -read" $o0]}


# ---- 6. task 089: placement, powerplanning, port_buffers_early ----
proc code_of {path} { global here; set o {}; foreach l [split [read_file $path] "\n"] { set t [string trim $l]; if {$t ne "" && [string index $t 0] ne "#"} { lappend o [regsub {;#.*$} $l ""] } }; return [join $o "\n"] }
set pl [read_file $here/placement.tcl]
set pl_open [string first "open_block" $pl]; set pl_in [string first "unpu_remove_clock_latency placement-input" $pl]
set pl_po [string first "    place_opt\n" $pl]; set pl_fin [string first "unpu_remove_clock_latency placement-final" $pl]; set pl_save [string first "save_block" $pl]; set pl_rep [string first "report_qor" $pl]
check "placement.tcl: input removal right after open_block / link_block" {$pl_in > $pl_open && ($pl_in - $pl_open) < 300}
check "placement.tcl: the final removal comes after place_opt and before the reports and the save" {$pl_fin > $pl_po && $pl_fin < $pl_rep && $pl_fin < $pl_save}
check "placement.tcl: the NOTE for a line re-created inside place_opt" {[string first "unpu_clock_latency_note placement-final place_opt" $pl] > $pl_fin}
set pp [read_file $here/powerplanning.tcl]
set pp_in [string first "powerplan-probe-open" $pp]; set pp_c [string first "powerplan-probe-after-compile_pg" $pp]; set pp_k [string first "powerplan-probe-after-check_pg" $pp]; set pp_f [string first "unpu_remove_clock_latency powerplan-final" $pp]; set pp_s [string first "save_block" $pp]
check "powerplanning.tcl: three probes in order (open, after compile_pg, after the check_pg commands)" {$pp_in > 0 && $pp_c > $pp_in && $pp_k > $pp_c}
check "powerplanning.tcl: the probes only count (unpu_clock_latency_count), they never remove" {[string first "unpu_clock_latency_count powerplan-probe-open" $pp] > 0 && [string first "unpu_remove_clock_latency powerplan-probe" $pp] < 0}
check "powerplanning.tcl: the final removal is after the probes and before save_block" {$pp_f > $pp_k && $pp_f < $pp_s}
set pb [read_file $here/port_buffers_early.tcl]
set pb_in [string first "unpu_remove_clock_latency port-buffers-input" $pb]; set pb_ut [string first "pbe089_update_timing table-prediction" $pb]; set pb_fin [string first "unpu_remove_clock_latency port-buffers-final" $pb]; set pb_sv [string first "save_block -as" $pb]
check "port_buffers_early.tcl: the input removal comes before the first timing update and measure" {$pb_in > 0 && $pb_in < $pb_ut}
check "port_buffers_early.tcl: the final removal comes right before save_block -as" {$pb_fin > 0 && $pb_fin < $pb_sv && ($pb_sv - $pb_fin) < 500}
set pbcode [code_of $here/port_buffers_early.tcl]
set n_raw [llength [regexp -all -inline {update_timing -full} $pbcode]]
check "port_buffers_early.tcl: update_timing -full appears only inside the helper (2 times: before and after the removal)" {$n_raw == 2}
check "port_buffers_early.tcl: PLAN_ONLY says the removal is in memory only" {[string first "changed the block IN MEMORY only" $pb] > 0}
check "port_buffers_early.tcl: the gate tolerances are unchanged" {[regexp {set GATE_TOL_IN2OUT 0.005} $pb] && [regexp {set GATE_TOL_SETUP  0.005} $pb]}
set src_now [read_file $here/clock_latency.tcl]
check "the NOTE text exists in clock_latency.tcl" {[string first {>>> 089 NOTE: $label: the tool re-created the line inside} $src_now] > 0}
# the note proc against the mock
set ::UNPU_CL_LAST {{func_ss {set_clock_latency 0.8 [get_clocks {clk}]}}}
set out [run_proc {unpu_clock_latency_note lab place_opt 1}]
check "note proc returns normally" {[lindex $out 0] == 0}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
