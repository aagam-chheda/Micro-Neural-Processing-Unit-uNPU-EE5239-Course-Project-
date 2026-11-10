# ==============================================================================
# Script: diag_io_latency.tcl
# Path  : <RUN_DIR>/pnr_v2/diag_io_latency.tcl   ;# 084: new READ-ONLY diagnostic (run before CTS of the new run; nothing is saved)
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 084: QUESTION. PrimeTime launches/captures the I/O paths at the clk PIN (`clock network delay (propagated) 0.00`) and counts the macro's clock-tree insertion delay (0.40 ns ff,
# 084: 0.92 ns ss) against the interface budgets. ICC2 stopped hold fixing at about 0 slack on 263 input-to-register paths that PrimeTime sees at -0.35 ns. HYPOTHESIS H1: ICC2 adds
# 084: the clock-tree latency to the I/O reference clock. We never saw ICC2's own path report. This script prints it, parses the numbers, and ends with a verdict table:
# 084: H1 CONFIRMED / H1 REFUTED / INCONCLUSIVE (task 084; the answer decides between the SDC-text fix, the I/O-only margin of 083 row 8, and doing nothing).
# 084: READ-ONLY, on a COPY of run 1's library placed inside THIS clone (run 1 is the fallback and is never written):
# 084:   - the script REFUSES to start if the library lies in another clone than the script, or does not exist, or the block is not in it (the blocks that exist are printed);
# 084:   - the library and the block are opened with -read (usage text of open_lib / open_block in ~/server_pull/rpt/help); no save_block, save_lib or write_* into the library;
# 084:   - output files only under <RUN_ROOT>/pnr_icc2/diag/ (reports, SDC copies for reading, help texts);
# 084:   - no constraint, app option or design object is changed (current_scenario only switches the view).
# 084: every report is run inside a catch: a failing report is printed (raw message), counted, and the script goes on; the end line gives the number of failed reports.
# 084: every command or option not shown in a usage text in ~/server_pull/rpt/help is marked VERIFY.
# 084: run  : cd <RUN_DIR>/pnr_icc2 ; icc2_shell -f ../pnr_v2/diag_io_latency.tcl |& tee diag_io_latency_console.log ; then `exit`
# ==============================================================================

set DESIGN_NAME "unpu_top"
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"
set DIAG_DIR    "${PNR_DIR}/diag"   ;# 084: the ONLY place this script writes to

# ---- parameters of THIS script ----
set DIAG_LIB      "${PNR_DIR}/blocks_diag/${DESIGN_NAME}.dlib"   ;# 084: the COPY of run 1's library: `cp -r <run 1>/pnr_icc2/blocks/unpu_top.dlib ${PNR_DIR}/blocks_diag/` (README); must lie in THIS clone
set DIAG_BLOCK    "${DESIGN_NAME}_route"   ;# 084: the routed state of run 1 (the state PrimeTime was run on is this one plus fill)
set HOLD_FROM_PORT   "dma_rdata\[14\]"   ;# 084: PrimeTime example: input delay 0, data arrival 0.56, required 0.90 (capture clock 0.40 + uncertainty 0.50), slack -0.35
set HOLD_TO_PIN      "u_dma/stage_reg_1__14_/D"   ;# 084: its endpoint (progress log 3.11; if the pin name differs in this netlist the report falls back to the worst path from the port)
set SETUP_TO_PORT    "dma_addr\[31\]"   ;# 084: PrimeTime: launch clock arrival 0.92 at u_dma/beat_idx_reg_0_/CP, data arrival 10.74, required 10.50, slack -0.24
set IN2OUT_FROM_PORT "paddr\[3\]"   ;# 084: the in2out example path (PrimeTime: about 0 slack)
set IN2OUT_TO_PORTS  "prdata\[*\]"
set SETUP_SCEN_PATTERN "*ss*"   ;# 084: scenario names are READ from the design and matched by pattern; the script stops reporting for a side if the match is not exactly one scenario
set HOLD_SCEN_PATTERN  "*ff*"
set H1_MIN_LATENCY_NS 0.05   ;# 084: a latency below this is read as zero. Reason: PrimeTime shows 0.00 and ICC2 prints 4 digits; the effect to decide on is 0.40 to 0.92 ns, so 0.05 separates the two with a wide margin
# 084: PrimeTime's numbers (progress log 3.11), only printed beside ICC2's, never used as a limit
set PT_REF [dict create hold_launch 0.00 hold_capture 0.40 hold_arrival 0.56 hold_required 0.90 hold_slack -0.35 setup_launch 0.92 setup_arrival 10.74 setup_required 10.50 setup_slack -0.24]
# 084: the commands whose help text is saved to <diag>/help_<name>.txt so that the [M] items of 083 become [L] (the label is the file name part)
set HELP_ITEMS [list {margin {help *margin*}} {set_clock_latency {help set_clock_latency}} {set_input_delay {help set_input_delay}} {set_output_delay {help set_output_delay}} \
    {set_clock_tree_options {help set_clock_tree_options}} {set_latency_adjustment_options {help set_latency_adjustment_options}} {report_clocks {help report_clocks}} {report_port {help report_port}}]   ;# 084: VERIFY each name; a missing command prints its raw error

# ---- BEGIN PURE TCL 084 ----
# (plain Tcl, no tool command: tested in pnr_v2/test_diag_io_latency.tcl)

# diag084_num <v> -> "n/a" or the number with 4 digits
proc diag084_num {v} { if {$v eq "" || $v eq "n/a"} { return "n/a" }; return [format %.4f $v] }

# diag084_rows <text> -> list of rows {name incr path edge section}; section 0 = before the first `data arrival time` (launch half), 1 = after it up to `data required time` (capture half), 2 = the rest.
# A row is `<name> <incr> <path> [r|f]` or `<name> <path> [r|f]` (one number: path only, incr ""). Lines without a number at the end are skipped (headers, rules).
proc diag084_rows {text} {
    set rows {}
    set sec 0
    foreach l [split $text "\n"] {
        set t [string trim $l]
        if {$t eq ""} { continue }
        if {[regexp {^data arrival time\s+(-?\d+\.\d+)\s*$} $t -> v]} { lappend rows [list "data arrival time" "" $v "" $sec]; if {$sec == 0} { set sec 1 }; continue }
        if {[regexp {^data required time\s+(-?\d+\.\d+)\s*$} $t -> v]} { lappend rows [list "data required time" "" $v "" $sec]; if {$sec == 1} { set sec 2 }; continue }
        if {[regexp {^slack \(} $t]} { continue }
        if {[regexp {^(\S.*?)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)(?:\s+([rf]))?$} $t -> n i p e]} { lappend rows [list $n $i $p $e $sec]; continue }
        if {[regexp {^(\S.*?)\s+(-?\d+\.\d+)(?:\s+([rf]))?$} $t -> n p e]} { lappend rows [list $n "" $p $e $sec]; continue }
    }
    return $rows
}

# diag084_header <text> <key> -> the text after `Startpoint:` / `Endpoint:` / `Path Group:` / `Path Type:` up to the end of the line (or "")
proc diag084_header {text key} {
    foreach l [split $text "\n"] { if {[regexp "^\\s*$key:\\s*(.*)$" $l -> v]} { return [string trim $v] } }
    return ""
}

# diag084_first_row <rows> <section> <pattern-regexp on name> -> first matching row or ""
proc diag084_first_row {rows sec re} {
    foreach r $rows { if {[lindex $r 4] == $sec && [regexp $re [lindex $r 0]]} { return $r } }
    return ""
}

# diag084_edge_time <rows> <section> -> the path value of the first `clock <name> (rise edge|fall edge)` row of the section (the clock edge time), 0 if none
proc diag084_edge_time {rows sec} {
    set r [diag084_first_row $rows $sec {^clock \S+ \((rise|fall) edge\)}]
    if {$r eq ""} { return 0.0 }
    return [lindex $r 2]
}

# diag084_latency <rows> <section> <object> <kind> -> clock latency seen at the START (section 0) or END (section 1) of the path, or "n/a"
#  1) a row `clock network delay (...)`: its path value minus the clock edge time (PrimeTime and unexpanded ICC2 reports)
#  2) an expanded clock path: the first row that begins with `<object>/` (the clock pin of the flop): its path value minus the clock edge time
#  3) an input port start: the `input external delay` row: path - incr - edge time (that is where the external launch starts)
# <kind> is "port" or "cell" (the startpoint/endpoint kind read from the header)
proc diag084_latency {rows sec obj kind} {
    set edge [diag084_edge_time $rows $sec]
    set r [diag084_first_row $rows $sec {^clock network delay}]
    if {$r ne ""} { return [expr {[lindex $r 2] - $edge}] }
    if {$kind eq "cell"} {
        foreach x $rows { if {[lindex $x 4] == $sec && [string first "$obj/" [lindex $x 0]] == 0} { return [expr {[lindex $x 2] - $edge}] } }
    }
    if {$kind eq "port" && $sec == 0} {
        set r [diag084_first_row $rows 0 {^input external delay}]
        if {$r ne "" && [lindex $r 1] ne ""} { return [expr {[lindex $r 2] - [lindex $r 1] - $edge}] }
    }
    return "n/a"
}

# diag084_kind <header text like "dma_rdata[14] (input port clocked by clk)"> -> port | cell | ""
proc diag084_kind {h} {
    if {[regexp {\((input|output) port} $h]} { return port }
    if {[regexp {flip-flop|latch|register|clocked by} $h]} { return cell }
    return ""
}

# diag084_name <header text> -> the first word (the startpoint / endpoint name)
proc diag084_name {h} { return [lindex [split [string trim $h]] 0] }

# diag084_parse <report_timing text> -> dict: start end group type skind ekind launch capture uncert arrival required slack found notes
# every value that cannot be read is "n/a" and the reason is in notes (nothing is guessed)
proc diag084_parse {text} {
    set d [dict create start "" end "" group "" type "" skind "" ekind "" launch n/a capture n/a uncert n/a arrival n/a required n/a slack n/a found 0 notes {}]
    set notes {}
    set sh [diag084_header $text Startpoint]
    set eh [diag084_header $text Endpoint]
    dict set d start [diag084_name $sh]
    dict set d end   [diag084_name $eh]
    dict set d group [diag084_header $text "Path Group"]
    dict set d type  [diag084_header $text "Path Type"]
    set sk [diag084_kind $sh]
    set ek [diag084_kind $eh]
    dict set d skind $sk
    dict set d ekind $ek
    set rows [diag084_rows $text]
    if {[llength $rows] == 0} { lappend notes "no path rows found in the report text"; dict set d notes $notes; return $d }
    dict set d found 1
    dict set d launch  [diag084_latency $rows 0 [dict get $d start] $sk]
    dict set d capture [diag084_latency $rows 1 [dict get $d end] $ek]
    if {[dict get $d launch] eq "n/a"}  { lappend notes "launch clock latency not readable (no `clock network delay`, no expanded clock pin of the startpoint, no `input external delay` row)" }
    if {[dict get $d capture] eq "n/a"} { lappend notes "capture clock latency not readable (no `clock network delay`, no expanded clock pin of the endpoint)" }
    set r [diag084_first_row $rows 1 {^clock uncertainty}]
    if {$r ne ""} { dict set d uncert [lindex $r 1] }
    foreach x $rows {
        if {[lindex $x 0] eq "data arrival time" && [dict get $d arrival] eq "n/a"} { dict set d arrival [lindex $x 2] }
        if {[lindex $x 0] eq "data required time" && [dict get $d required] eq "n/a"} { dict set d required [lindex $x 2] }
    }
    if {[regexp {slack \((?:VIOLATED|MET)[^)]*\)\s+(-?\d+\.\d+)} $text -> s]} { dict set d slack $s }
    if {[dict get $d arrival] eq "n/a"}  { lappend notes "data arrival time not found" }
    if {[dict get $d required] eq "n/a"} { lappend notes "data required time not found" }
    dict set d notes $notes
    return $d
}

# diag084_diff_list <hold dict> <setup dict> <pt ref dict> <tol> -> list of text lines: every quantity that differs from PrimeTime's by more than tol (only for values that were read)
proc diag084_diff_list {hd sd ref tol} {
    set out {}
    foreach {lbl d keyp} {{hold arrival} hold arrival {hold required} hold required {hold slack} hold slack {setup arrival} setup arrival {setup required} setup required {setup slack} setup slack} {
        set which [lindex $lbl 0]
        set dd [expr {$which eq "hold" ? $hd : $sd}]
        set v [dict get $dd $keyp]
        set rk "${which}_$keyp"
        if {$v eq "n/a" || ![dict exists $ref $rk]} { continue }
        set pv [dict get $ref $rk]
        if {abs($v - $pv) > $tol} { lappend out [format "%s %s: ICC2 %.4f, PrimeTime %.4f (difference %+.4f)" $which $keyp $v $pv [expr {$v - $pv}]] }
    }
    return $out
}

# diag084_verdict <hold dict> <setup dict> <pt ref dict> <thr> -> dict: lines (the 4 table lines), verdict (one of the 3 labels with its reason), sentence
# Evidence: E1 = ICC2 launch latency of the INPUT-port hold path (PrimeTime 0.00); E2 = ICC2 capture latency at the OUTPUT port of the dma_addr setup path (PrimeTime 0.00);
# the table also prints the capture latency at the hold endpoint flop and the launch latency at the dma_addr source flop (both are in the clock tree in both tools).
proc diag084_verdict {hd sd ref thr} {
    set lines {}
    lappend lines [format "ICC2 launch clock latency at the input port path:        %s ns (PrimeTime: %s)" [diag084_num [dict get $hd launch]] [diag084_num [dict get $ref hold_launch]]]
    lappend lines [format "ICC2 capture clock latency at the endpoint flop:         %s ns (PrimeTime: %s ff)" [diag084_num [dict get $hd capture]] [diag084_num [dict get $ref hold_capture]]]
    lappend lines [format "ICC2 launch latency at the dma_addr\[31\] source flop:      %s ns (PrimeTime: %s ss)" [diag084_num [dict get $sd launch]] [diag084_num [dict get $ref setup_launch]]]
    lappend lines [format "ICC2 required time at the output port for dma_addr\[31\]:   %s ns (PrimeTime: %s); capture clock latency at that port %s ns (PrimeTime: 0.00)" [diag084_num [dict get $sd required]] [diag084_num [dict get $ref setup_required]] [diag084_num [dict get $sd capture]]]
    set e1 [dict get $hd launch]
    set e2 [dict get $sd capture]
    set pos {}
    set zero {}
    set miss {}
    foreach {nm v} [list "input-port launch (hold)" $e1 "output-port capture (setup dma_addr\[31\])" $e2] {
        if {$v eq "n/a"} { lappend miss $nm } elseif {abs($v) >= $thr} { lappend pos "$nm [diag084_num $v] ns" } else { lappend zero "$nm [diag084_num $v] ns" }
    }
    set verdict ""
    set sentence ""
    if {[llength $pos] > 0} {
        set verdict "H1 CONFIRMED (ICC2 adds latency to the I/O reference: [join $pos {; }])"
        set sentence "ICC2 counts a clock latency on the I/O reference where PrimeTime counts 0.00. The mismatch of the two tools is explained; the choice is now between the SDC-text fix (-network_latency_included, needs the user's approval) and the I/O-only margin of 083 row 8."
        if {[llength $zero] > 0} { append sentence " Only one side shows it ([join $zero {; }]); the fix must be checked for that side separately." }
        if {[llength $miss] > 0} { append sentence " The other side could not be read ([join $miss {, }]): read its report in the diag folder by hand before choosing the fix." }
    } elseif {[llength $zero] == 2} {
        set diffs [diag084_diff_list $hd $sd $ref 0.02]
        set verdict "H1 REFUTED (ICC2 shows 0.00 like PrimeTime: the cause is elsewhere; differences found: [expr {[llength $diffs] ? [join $diffs { | }] : {none above 0.02 ns in the quantities that were read}}])"
        set sentence "ICC2 launches and captures the I/O at the clock pin like PrimeTime, so neither fix is justified until the real difference is found (look at the differences listed, the clock uncertainty lines, the path groups and the parasitics)."
    } else {
        set verdict "INCONCLUSIVE: [expr {[llength $miss] ? "not readable: [join $miss {, }]" : {}}][expr {[llength $miss] && [llength $zero] ? {; } : {}}][expr {[llength $zero] ? "read as zero: [join $zero {, }]" : {}}]"
        set sentence "The numbers read do not decide H1. Open the full reports in the diag folder and read the launch and capture clock lines by hand; send them to Planning."
    }
    return [dict create lines $lines verdict $verdict sentence $sentence]
}

# diag084_lib_check <library path> <run root> -> "" when the library may be used, else the refusal text (both clones are named)
# uses unpu_run_clone_of / unpu_run_norm of run_root.tcl
proc diag084_lib_check {lib run_root} {
    if {$lib eq ""} { return "ERROR 084: the library path is empty" }
    if {![file isdirectory $lib]} { return "ERROR 084: the library $lib does not exist (copy run 1's library first: see the README of pnr_v2, section 'diag_io_latency')" }
    set other [unpu_run_clone_of $lib]
    if {$other ne "" && $other ne [unpu_run_norm $run_root]} {
        return "ERROR 084: the library $lib lies in the clone $other, but this script belongs to the clone $run_root. Run 1 is the fallback and must not be opened here: copy the library into THIS clone and give that copy"
    }
    return ""
}

# diag084_block_check <block name> <list of block names that exist> -> "" or the refusal text (the blocks that exist are printed)
proc diag084_block_check {block existing} {
    foreach b $existing {
        set n [lindex [split $b ":"] end]
        set n [lindex [split $n "/"] 0]
        regsub {\.(design|layout|frame|abstract|views)$} $n {} n   ;# VERIFY the form get_object_name gives for a block: lib:block, lib:block/label.view or just block; all are accepted
        if {$n eq $block || $b eq $block} { return "" }
    }
    return "ERROR 084: the block $block is not in the library. Blocks that exist: [expr {[llength $existing] ? [join $existing {, }] : {none}}]"
}

# diag084_pick_scenario <names> <glob pattern> -> {ok name message}; exactly one match is ok
proc diag084_pick_scenario {names pat} {
    set m {}
    foreach n $names { if {[string match $pat $n]} { lappend m $n } }
    if {[llength $m] == 1} { return [list 1 [lindex $m 0] "scenario [lindex $m 0] (pattern $pat)"] }
    return [list 0 "" "pattern $pat matches [llength $m] of the scenarios [expr {[llength $names] ? [join $names {, }] : {none}}]: [expr {[llength $m] ? [join $m {, }] : {no match}}]; the reports of this side are skipped"]
}

# diag084_sdc_io_lines <sdc text> -> dict: lines (the I/O delay / clock latency / propagated / uncertainty lines), network_incl (count of -network_latency_included), source_incl (count of -source_latency_included), latency (count of set_clock_latency)
proc diag084_sdc_io_lines {text} {
    set out {}
    set ni 0; set si 0; set cl 0
    foreach l [split $text "\n"] {
        set t [string trim $l]
        if {$t eq "" || [string index $t 0] eq "#"} { continue }
        if {[regexp {^(set_input_delay|set_output_delay|set_clock_latency|set_propagated_clock|set_clock_uncertainty|set_clock_transition)} $t]} {
            lappend out $t
            if {[string first "-network_latency_included" $t] >= 0} { incr ni }
            if {[string first "-source_latency_included" $t] >= 0} { incr si }
            if {[string match "set_clock_latency*" $t]} { incr cl }
        }
    }
    return [dict create lines $out network_incl $ni source_incl $si latency $cl]
}

# diag084_help_list <text of `help *x*`> -> the non-empty lines (one per command)
proc diag084_help_list {text} {
    set o {}
    foreach l [split $text "\n"] { set t [string trim $l]; if {$t ne ""} { lappend o $t } }
    return $o
}
# ---- END PURE TCL 084 ----

# ==============================================================================
# ICC2 part
# ==============================================================================
set DIAG_FAILED 0
set DIAG_TOTAL 0
proc diag_fail_note {label msg} {
    global DIAG_FAILED
    incr DIAG_FAILED
    puts ">>> 084 REPORT FAILED: $label: $msg"
}
# diag_run <label> <script>: run a tool command string under catch, capture its text, print it, write it to <diag>/<label>.rpt; returns the text ("" on failure)
proc diag_run {label script} {
    global DIAG_DIR DIAG_TOTAL
    incr DIAG_TOTAL
    puts "\n>>> 084 ===== $label ====="
    puts ">>> 084 command: $script"
    set txt ""
    if {[catch {redirect -variable txt { eval $script }} err]} {   ;# VERIFY redirect -variable captures the report text of the command
        puts $txt
        diag_fail_note $label $err
        return ""
    }
    puts $txt
    set ext [expr {[string match help_* $label] ? "txt" : "rpt"}]   ;# 084: the help texts are help_<name>.txt (task 084), the others <label>.rpt
    if {[catch {set fp [open ${DIAG_DIR}/${label}.${ext} w]; puts $fp "# $script"; puts $fp $txt; close $fp} werr]} { diag_fail_note "$label (writing the report file)" $werr }
    return $txt
}

file mkdir $DIAG_DIR
puts "\n>>> 084 READ-ONLY DIAGNOSTIC: nothing is saved. Library: $DIAG_LIB, block: $DIAG_BLOCK. Output folder: $DIAG_DIR"
puts ">>> 084 parameters: HOLD $HOLD_FROM_PORT -> $HOLD_TO_PIN; SETUP -> $SETUP_TO_PORT; IN2OUT $IN2OUT_FROM_PORT -> $IN2OUT_TO_PORTS; scenario patterns setup '$SETUP_SCEN_PATTERN' hold '$HOLD_SCEN_PATTERN'; H1 threshold $H1_MIN_LATENCY_NS ns"

# ---- 1. guards (nothing is opened before they pass) ----
set lib_msg [diag084_lib_check $DIAG_LIB $RUN_ROOT]
if {$lib_msg ne ""} { error $lib_msg }
set lib_clone [unpu_run_clone_of $DIAG_LIB]
puts ">>> 084 library clone: [expr {$lib_clone ne {} ? $lib_clone : {(not inside any clone)}}]; script clone: $RUN_ROOT"
if {$lib_clone eq ""} { puts ">>> 084 NOTE: the library is not inside any clone; it is opened read-only and nothing is written to it" }

# ---- 2. open the COPY read-only ----
set open_lib_all [get_libs -quiet *]
if {[sizeof_collection $open_lib_all] > 0} { foreach_in_collection lib_obj $open_lib_all { close_lib -force $lib_obj } }
open_lib -read $DIAG_LIB   ;# [L] open_lib usage: -read
set existing {}
if {[catch {set existing [get_object_name [get_blocks -all -quiet]]} gerr]} { puts ">>> 084 could not list the blocks ($gerr)" }   ;# VERIFY get_blocks -all
set bl_msg [diag084_block_check $DIAG_BLOCK $existing]
if {$bl_msg ne ""} { error $bl_msg }
open_block -read ${DIAG_LIB}:${DIAG_BLOCK}   ;# [L] open_block usage: -read
if {[catch {link_block} lerr]} { puts ">>> 084 link_block: $lerr (not fatal for a read-only view)" }
puts ">>> 084 opened read-only: [get_object_name [current_block]]"

# ---- 3. scenarios, read from the design ----
set scen_names {}
catch {set scen_names [get_object_name [get_scenarios]]}
puts ">>> 084 scenarios in the design: $scen_names"
diag_run report_scenarios {report_scenarios}
lassign [diag084_pick_scenario $scen_names $SETUP_SCEN_PATTERN] s_ok SETUP_SCEN s_msg
lassign [diag084_pick_scenario $scen_names $HOLD_SCEN_PATTERN]  h_ok HOLD_SCEN  h_msg
puts ">>> 084 setup side: $s_msg"
puts ">>> 084 hold side:  $h_msg"
if {!$s_ok} { diag_fail_note "scenario choice (setup)" $s_msg }
if {!$h_ok} { diag_fail_note "scenario choice (hold)" $h_msg }

# ---- 4. the four path reports ----
set hold_txt ""; set hold_worst_txt ""; set setup_txt ""; set in2out_txt ""
set rt_opts "-path_type full_clock_expanded -input_pins -nets -significant_digits 4 -nosplit"   ;# [L] report_timing usage lists these options
if {$h_ok} {
    set to_opt ""
    if {[sizeof_collection [get_pins -quiet $HOLD_TO_PIN]] > 0} { set to_opt "-to \[get_pins \{$HOLD_TO_PIN\}\]" } else { puts ">>> 084 the pin $HOLD_TO_PIN does not exist in this block: the hold report below is the worst path from the port instead" }
    set hold_txt [diag_run hold_input_port "report_timing -scenarios $HOLD_SCEN -delay_type min -from \[get_ports \{$HOLD_FROM_PORT\}\] $to_opt $rt_opts"]
    set hold_worst_txt [diag_run hold_worst_from_inputs "report_timing -scenarios $HOLD_SCEN -delay_type min -from \[all_inputs\] $rt_opts"]
}
if {$s_ok} {
    set setup_txt [diag_run setup_dma_addr31 "report_timing -scenarios $SETUP_SCEN -delay_type max -to \[get_ports \{$SETUP_TO_PORT\}\] $rt_opts"]
    set in2out_txt [diag_run setup_in2out "report_timing -scenarios $SETUP_SCEN -delay_type max -from \[get_ports \{$IN2OUT_FROM_PORT\}\] -to \[get_ports \{$IN2OUT_TO_PORTS\}\] $rt_opts"]
}

# ---- 5. clocks, latency, skew, clock tree options, flags, constraints ----
foreach {lbl scen ok} [list setup $SETUP_SCEN $s_ok hold $HOLD_SCEN $h_ok] {
    if {!$ok} { continue }
    if {[catch {current_scenario $scen} cerr]} { diag_fail_note "current_scenario $scen" $cerr; continue }
    diag_run clocks_${lbl} {report_clocks}   ;# VERIFY report_clocks
    diag_run clock_latency_${lbl} "report_clock_timing -scenarios $scen -type latency -significant_digits 4"   ;# [L] report_clock_timing usage
    diag_run clock_skew_${lbl} "report_clock_timing -scenarios $scen -type skew -significant_digits 4"
    diag_run clock_propagated_${lbl} {puts "is_propagated of clk: [get_attribute [get_clocks clk] is_propagated]"}   ;# VERIFY the attribute name is_propagated
    set sdc_file ${DIAG_DIR}/sdc_${scen}.sdc
    diag_run write_sdc_${lbl} "write_sdc -scenario $scen -output $sdc_file"   ;# [L] write_sdc -scenario / -output; the file is a READ-ONLY copy for this diagnostic
    if {[file exists $sdc_file]} {
        set fp [open $sdc_file r]; set sdc_txt [read $fp]; close $fp
        set io [diag084_sdc_io_lines $sdc_txt]
        puts ">>> 084 ($scen) constraint lines that decide the I/O reference ([llength [dict get $io lines]] lines):"
        foreach l [dict get $io lines] { puts "      $l" }
        puts ">>> 084 ($scen) set_clock_latency lines: [dict get $io latency]; -network_latency_included: [dict get $io network_incl]; -source_latency_included: [dict get $io source_incl]"
    }
}
diag_run clock_tree_options {report_clock_tree_options}   ;# VERIFY the command exists
diag_run app_options_time {report_app_options time.all_clocks_propagated time.enable_io_path_groups time.deprioritize_io_path_groups time.allow_port_latency_for_feedthrough time.edge_specific_source_latency}   ;# [L] report_app_options patterns

# ---- 6. the help texts of 083's [M] items ----
foreach item $HELP_ITEMS {
    lassign $item nm cmd
    set t [diag_run help_$nm $cmd]
    if {$nm eq "margin"} {
        puts ">>> 084 commands that match *margin*:"
        foreach l [diag084_help_list $t] { puts "      $l" }
    }
}

# ---- 7. the verdict table (from the numbers read; n/a where a line was not found) ----
puts "\n=============================================================================="
puts " 084 I/O LATENCY DIAGNOSTIC: what ICC2 uses on the I/O paths (library $DIAG_LIB, block $DIAG_BLOCK)"
set pa_hold  [diag084_parse $hold_txt]
set pa_worst [diag084_parse $hold_worst_txt]
set pa_setup [diag084_parse $setup_txt]
set pa_in2o  [diag084_parse $in2out_txt]
foreach {nm pa} [list hold_input_port $pa_hold hold_worst_from_inputs $pa_worst setup_dma_addr31 $pa_setup setup_in2out $pa_in2o] {
    if {![dict get $pa found]} { puts "   path $nm: not available (report missing or not parsable)"; continue }
    puts [format "   path %-24s %s -> %s  launch %s  capture %s  uncertainty %s  arrival %s  required %s  slack %s%s" $nm [dict get $pa start] [dict get $pa end] [diag084_num [dict get $pa launch]] [diag084_num [dict get $pa capture]] [diag084_num [dict get $pa uncert]] [diag084_num [dict get $pa arrival]] [diag084_num [dict get $pa required]] [diag084_num [dict get $pa slack]] [expr {[llength [dict get $pa notes]] ? "   NOTES: [join [dict get $pa notes] { / }]" : {}}]]
}
set vd [diag084_verdict $pa_hold $pa_setup $PT_REF $H1_MIN_LATENCY_NS]
foreach l [dict get $vd lines] { puts "   $l" }
puts "   [dict get $vd verdict]"
puts "   [dict get $vd sentence]"
puts "   reports run: $DIAG_TOTAL, reports failed: $DIAG_FAILED (the raw messages are above, lines '>>> 084 REPORT FAILED')"
puts "   nothing was saved. Check that run 1 was not written: ls -ld on its library before and after (README)."
puts "=============================================================================="
catch {close_blocks -force [get_blocks -quiet *]}   ;# the library is open read-only: -force only discards in-memory state, nothing is written
puts ">>> 084 done. Type exit."
