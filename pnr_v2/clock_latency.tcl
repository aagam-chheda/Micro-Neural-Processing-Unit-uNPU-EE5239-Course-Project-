# ==============================================================================
# File  : pnr_v2/clock_latency.tcl   (task 088: remove the tool-made set_clock_latency, with printed checks)
# Used by: cts.tcl, route.tcl, fix_antenna.tcl, timing_closure.tcl, pt_eco_apply.tcl, antenna_port_buffers.tcl, antenna_clk_root.tcl, metal_fill.tcl, pv.tcl
#          (each sources it right after run_root.tcl and calls unpu_remove_clock_latency right after open_block / link_block; cts.tcl and pv.tcl have extra calls).
# WHY   : ICC2 writes `set_clock_latency <v> [get_clocks {clk}]` into the block (run 1's exported SDCs: 0.806866 in the ss SDC, 0.379753 in the ff SDC); no script of ours sets it. ICC2 then
#         counts it as the I/O REFERENCE latency (launch of the inputs, capture of the outputs); PrimeTime, with a propagated clock, ignores it and reads the I/O reference at the clock pin
#         with 0.00. Task 086 experiment A0 (remove_clock_latency per scenario, then a re-report) gave PrimeTime's numbers on the example paths: hold slack -0.3494 (PrimeTime -0.35),
#         output required 10.5000 (PrimeTime 10.50), source-flop launch 0.9188 (PrimeTime 0.92); reg-to-reg slacks unchanged.
#         This is NOT a tuned constraint: no margin, no uncertainty, no I/O delay, no goal, no limit is changed. It deletes a tool-made artefact that the instructor never gave and that
#         PrimeTime ignores, so that ICC2 optimises in the convention of the sign-off tool (decision of the user, 2026-11-10, task 088).
# WHAT  : unpu_remove_clock_latency <label>: for EVERY scenario of the open block: switch to it, count the set_clock_latency lines (write_sdc into a scratch file under pnr_icc2/diag), and if
#         there are any remove them with remove_clock_latency on the real clocks (the form that worked in 086), count again, print the counts, ERROR 088 if any is left. Zero before is not an
#         error and issues NO command (idempotent). The proc touches nothing else (uncertainty, propagated state); it restores current_scenario at the end.
#         unpu_clock_latency_count <label>: the same count without any change (information).
#         unpu_clock_latency_grep <label> <files>: hard check of exported SDC files: any set_clock_latency line is ERROR 088.
# Pure parts (counting, decision, grep) are between BEGIN/END PURE TCL 088 and tested with tclsh in pnr_v2/test_clock_latency.tcl.
# ==============================================================================

# ---- BEGIN PURE TCL 088 ----
# unpu_cl_lines <sdc text> -> the set_clock_latency lines (trimmed, comments and other commands ignored)
proc unpu_cl_lines {text} {
    set o {}
    foreach l [split $text "\n"] {
        set t [string trim $l]
        if {[regexp {^set_clock_latency(\s|$)} $t]} { lappend o $t }
    }
    return $o
}

# unpu_cl_decide <before> <after> -> {ok message}: before may be anything >= 0; after must be 0; a count that is not a non-negative integer (unreadable) is an error, never a pass
proc unpu_cl_decide {before after} {
    foreach {w v} [list before $before after $after] {
        if {![string is integer -strict $v] || $v < 0} { return [list 0 "the $w count is unreadable ('$v')"] }
    }
    if {$after != 0} { return [list 0 "$after set_clock_latency line(s) are still there after remove_clock_latency (before $before)"] }
    return [list 1 "ok"]
}

# unpu_cl_summary <label> <scenario> <before> <after> -> the printed line
proc unpu_cl_summary {label scen before after} {
    return ">>> 088 $label $scen: set_clock_latency lines before $before, after $after"
}

# unpu_cl_scan <file name> <text> -> list of {file line_number text} for every set_clock_latency line
proc unpu_cl_scan {fname text} {
    set o {}; set n 0
    foreach l [split $text "\n"] { incr n; if {[regexp {^\s*set_clock_latency(\s|$)} $l]} { lappend o [list $fname $n [string trim $l]] } }
    return $o
}
# ---- END PURE TCL 088 ----

# the scratch SDC is small: only the clock latency part is requested (write_sdc -include clock_latency; VERIFY that -include limits the output; the counter reads only set_clock_latency lines anyway)
proc unpu_clock_latency_count_scen {scen} {
    global RUN_ROOT
    set dir ${RUN_ROOT}/pnr_icc2/diag
    file mkdir $dir
    set f ${dir}/clock_latency_[string map {/ _ : _} $scen].sdc
    file delete -force $f
    if {[catch {write_sdc -scenario $scen -include clock_latency -output $f} err]} { error "ERROR 088: write_sdc of scenario $scen failed: $err" }   ;# [L] write_sdc -scenario / -include / -output
    if {![file exists $f]} { error "ERROR 088: write_sdc of scenario $scen wrote no file ($f)" }
    set fp [open $f r]; set tx [read $fp]; close $fp
    return [unpu_cl_lines $tx]
}

proc unpu_scenario_names {} {
    set o {}
    foreach_in_collection s [get_scenarios] { lappend o [get_object_name $s] }
    return $o
}

proc unpu_clock_latency_count {label} {
    set cur ""
    catch {set cur [get_object_name [current_scenario]]}   ;# VERIFY current_scenario without argument returns the current scenario
    set total 0
    foreach s [unpu_scenario_names] {
        if {[catch {current_scenario $s} e]} { error "ERROR 088: cannot switch to scenario $s: $e" }
        set n [llength [unpu_clock_latency_count_scen $s]]
        puts [unpu_cl_summary $label $s $n $n]
        incr total $n
    }
    if {$cur ne ""} { catch {current_scenario $cur} }
    return $total
}

proc unpu_remove_clock_latency {label} {
    set cur ""
    catch {set cur [get_object_name [current_scenario]]}   ;# VERIFY current_scenario without argument returns the current scenario
    set names [unpu_scenario_names]
    if {[llength $names] == 0} { error "ERROR 088: $label: no scenario found in the block" }
    set removed 0
    foreach s $names {
        if {[catch {current_scenario $s} e]} { error "ERROR 088: $label: cannot switch to scenario $s: $e" }
        set lines [unpu_clock_latency_count_scen $s]
        set before [llength $lines]
        set after $before
        if {$before > 0} {
            foreach l $lines { puts ">>> 088 $label $s: removing the tool-made line: $l" }
            if {[catch {remove_clock_latency [get_clocks -filter "is_virtual == false"]} e]} { error "ERROR 088: $label: remove_clock_latency failed in scenario $s: $e" }   ;# the form that worked in task 086 (VERIFY: help remove_clock_latency)
            set after [llength [unpu_clock_latency_count_scen $s]]
            incr removed $before
        }
        puts [unpu_cl_summary $label $s $before $after]
        lassign [unpu_cl_decide $before $after] ok msg
        if {!$ok} { error "ERROR 088: $label $s: $msg" }
    }
    if {$cur ne ""} { catch {current_scenario $cur} }
    puts ">>> 088 $label: [llength $names] scenarios checked, $removed set_clock_latency line(s) removed, none left"
    return $removed
}

proc unpu_clock_latency_grep {label files} {
    set hits {}
    foreach f $files {
        if {![file exists $f]} { error "ERROR 088: $label: the exported SDC $f does not exist" }
        set fp [open $f r]; set tx [read $fp]; close $fp
        foreach h [unpu_cl_scan $f $tx] { lappend hits $h }
        puts ">>> 088 $label: [file tail $f]: set_clock_latency lines [llength [unpu_cl_scan $f $tx]]"
    }
    if {[llength $hits] > 0} {
        foreach h $hits { puts ">>> 088 $label: [file tail [lindex $h 0]] line [lindex $h 1]: [lindex $h 2]" }
        error "ERROR 088: $label: [llength $hits] set_clock_latency line(s) in the exported SDC file(s); the export must not carry the tool-made latency"
    }
    puts ">>> 088 $label: exported SDC files checked ([llength $files]): 0 set_clock_latency lines"
    return 0
}
