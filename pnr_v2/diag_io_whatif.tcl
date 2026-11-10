# ==============================================================================
# Script: diag_io_whatif.tcl
# Path  : <RUN_DIR>/pnr_v2/diag_io_whatif.tcl   ;# 086: new IN-MEMORY what-if (run after diag_io_latency.tcl; nothing is saved)
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 086: QUESTIONS (task 086; the 084 run confirmed H1: ICC2 launch at the input 0.6413 ns, capture at the dma_addr[31] output port 0.8069 ns, PrimeTime 0.00 and 0.00).
# 086:   (A) which way of removing ICC2's I/O reference latency makes the four example paths show PrimeTime's convention? Four experiments, each on a FRESH open of the block:
# 086:       A1a the same I/O delays with -network_latency_included      A1b the same with -source_latency_included      A1c both options
# 086:       A2  emulation by offsets: input MIN delay lowered by the measured ICC2 launch latency, output MAX delay raised by the measured capture latency, only on ports that are NOT on
# 086:           an input-to-output cone (the zero-margin paddr -> prdata read path stays untouched)
# 086:   (A0) FIRST, the cheapest candidate (found in run 1's exported SDCs: one line `set_clock_latency 0.806866 [get_clocks {clk}]` in the ss SDC and `0.379753` in the ff SDC; no script of ours
# 086:       writes it, the tool does; the values equal the I/O reference latencies measured by 084). (a) at which block of the chain the line first exists (write_sdc of every block of the copy,
# 086:       count per scenario); (b) in memory: remove it per scenario and re-report the four paths: do launch and capture go to 0.00? (c) do the reg-to-reg slacks stay unchanged?
# 086:       (d) the same line searched in the exported SDCs under <RUN_ROOT>/pnr_icc2/outputs (or the folder named by the environment variable UNPU_WI_EXPORT_DIR, read-only grep).
# 086:   (B) why ICC2's DATA delay on the hold input path (0.2927 ns) is 0.27 ns smaller than PrimeTime's (0.56 ns), and why the dma_addr[31] source-flop launch differs (0.5913 / 0.92).
# 086:       The script prints the ICC2 path stage by stage beside PrimeTime's, runs the same path from PrimeTime's start flop, adds slew/capacitance/derate columns, dumps the port
# 086:       driving/load data and the drive lines of the SDC, and repeats the baseline on every block of the copy that exists (_route, _filled, _pv).
# 086: SAFETY. It works on the COPY of run 1's library inside THIS clone (the same guards as diag_io_latency.tcl: other clone, missing library, missing block are refused with both names).
# 086:   The constraint edits of experiment A are IN MEMORY only: the library is opened for edit (the edits need it), but no save_block, save_lib or write_* into the library is ever called;
# 086:   every experiment is followed by a REOPEN of the block (unsaved changes are discarded) and a RESTORE CHECK: one path re-run must give the baseline numbers (hard line, counted).
# 086:   Output files only under <RUN_ROOT>/pnr_icc2/diag/ . Run 1 is never opened. The SDC text change of A1 is a WHAT-IF; applying it for real needs the user's approval.
# 086: every report/command is run under catch: a failure prints the raw message, is counted, and the script goes on; the end line gives the failure count.
# 086: every command or option not shown in a usage text in ~/server_pull/rpt/help is marked VERIFY. The help texts saved by the 084 run (diag/help_*.txt) are read first and the option lines about latency are printed.
# 086: run  : cd <RUN_DIR>/pnr_icc2 ; icc2_shell -f ../pnr_v2/diag_io_whatif.tcl |& tee diag_io_whatif_console.log ; then `exit`
# ==============================================================================

set DESIGN_NAME "unpu_top"
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"
set DIAG_DIR    "${PNR_DIR}/diag"   ;# 086: the ONLY place this script writes to
set SCRIPT_DIR  "${RUN_ROOT}/pnr_v2"

# ---- parameters of THIS script (the first six are the ones of diag_io_latency.tcl) ----
set DIAG_LIB      "${PNR_DIR}/blocks_diag/${DESIGN_NAME}.dlib"   ;# 086: the COPY of run 1's library (README of task 084); must lie in THIS clone
set DIAG_BLOCK    "${DESIGN_NAME}_route"
set EXTRA_BLOCKS  [list "${DESIGN_NAME}_filled" "${DESIGN_NAME}_pv"]   ;# 086: part B repeats the baseline on these blocks if they exist in the copy (PrimeTime read the filled layout; fill adds coupling capacitance)
set HOLD_FROM_PORT   "dma_rdata\[14\]"
set HOLD_TO_PIN      "u_dma/stage_reg_1__14_/D"
set SETUP_TO_PORT    "dma_addr\[31\]"
set SETUP_FROM_CELL  "u_dma/beat_idx_reg_0_"   ;# 086: PrimeTime's start flop for dma_addr[31] (the 084 ICC2 path started at u_dma/cur_m_reg_0_: a different flop, so its clock arrival may differ for that reason alone)
set IN2OUT_SETUP_FROM "paddr\[3\]"
set IN2OUT_HOLD_FROM  "paddr\[4\]"
set IN2OUT_TO_PORTS   "prdata\[*\]"
set SETUP_SCEN_PATTERN "*ss*"
set HOLD_SCEN_PATTERN  "*ff*"
set CLOCK_PORT_NAMES   {clk}   ;# 086: used only if the clock source ports cannot be read from the clock objects
set H1_MIN_LATENCY_NS  0.05     ;# 086: as in diag_io_latency.tcl: a latency below this is read as zero (PrimeTime 0.00; ICC2 prints 4 digits)
set TOL_RESTORE_NS     0.0001   ;# 086: the restore check accepts this difference (the report prints 4 digits)
set TOL_STAGE_NS       0.02     ;# 086: part B reports a stage whose delay differs from PrimeTime's by more than this
# 086: PrimeTime's hold path (progress log 3.9 / 3.11): rows {label cell-or-pin increment}; the instance NAMES may differ between the tools, the order and the cell types are compared
set PT_HOLD_STAGES [list {{input external delay} {} 0.00} {{dma_rdata[14] (in)} {} 0.26} {{copt_h_inst_3910/Z} buffd1 0.17} {{U588/Z} mx02d0 0.12}]
set PT_HOLD_ARRIVAL 0.56
set PT_SETUP_LAUNCH 0.92
set BLOCK_CHAIN   [list placement cts route filled pv]   ;# 086 A0(a): the blocks of the chain, probed in this order when they exist in the copy (name = ${DESIGN_NAME}_<entry>)
set EXPORT_SDC_DIR "${PNR_DIR}/outputs"   ;# 086 A0(d): the exported SDCs of THIS clone; the environment variable UNPU_WI_EXPORT_DIR names another folder (for example run 1's outputs; it is only READ)
set REMOVE_FORMS  [list {remove_clock_latency [get_clocks -filter "is_virtual == false"]} {remove_clock_latency -all} {remove_clock_latency}]   ;# 086 A0(b): tried in this order per scenario, the first that works is used and printed (VERIFY: help remove_clock_latency)
set HELP_LATENCY_FILES [list help_set_input_delay.txt help_set_output_delay.txt help_set_clock_latency.txt help_remove_clock_latency.txt help_compute_clock_latency.txt help_latency_cmds.txt]   ;# 086: saved by diag_io_latency.tcl

# the pure procs of diag_io_latency.tcl (parser, verdict, guards) are read from its text, not copied
set dl_path ${SCRIPT_DIR}/diag_io_latency.tcl
if {![file exists $dl_path]} { error "ERROR 086: $dl_path not found (its parser and guard procs are read from it)" }
set fp [open $dl_path r]; set dl_src [read $fp]; close $fp
set dl_b [string first "# ---- BEGIN PURE TCL 084 ----" $dl_src]
set dl_e [string first "# ---- END PURE TCL 084 ----" $dl_src]
if {$dl_b < 0 || $dl_e < 0 || $dl_e <= $dl_b} { error "ERROR 086: markers BEGIN/END PURE TCL 084 not found in $dl_path" }
eval [string range $dl_src $dl_b $dl_e]

# ---- BEGIN PURE TCL 086 ----
# (plain Tcl, no tool command: tested in pnr_v2/test_diag_io_whatif.tcl; it uses the procs of block 084)

# wi086_tokens <command line> -> list of tokens; [...] and {...} groups stay in one token (nested), quoted strings too
proc wi086_tokens {line} {
    set toks {}; set cur ""; set depth 0; set inq 0
    foreach ch [split [string trim $line] ""] {
        if {$inq} { append cur $ch; if {$ch eq "\""} { set inq 0 }; continue }
        if {$ch eq "\"" && $depth == 0} { set inq 1; append cur $ch; continue }
        if {$ch eq "\[" || $ch eq "\{"} { incr depth; append cur $ch; continue }
        if {$ch eq "\]" || $ch eq "\}"} { incr depth -1; append cur $ch; continue }
        if {[string is space $ch] && $depth == 0} { if {$cur ne ""} { lappend toks $cur; set cur "" }; continue }
        append cur $ch
    }
    if {$cur ne ""} { lappend toks $cur }
    return $toks
}

# wi086_parse_io <sdc text> -> list of dicts, one per set_input_delay / set_output_delay command:
#   cmd (set_input_delay|set_output_delay) kind (in|out) clock minmax (max|min|both) value objs (the object token) flags (the other options: -add_delay -clock_fall -rise -fall -network_latency_included
#   -source_latency_included ...) raw (the original line). A command that cannot be understood is returned in the second element of the result list (never dropped silently).
proc wi086_parse_io {text} {
    set out {}; set bad {}
    foreach l [split $text "\n"] {
        set t [string trim $l]
        if {![regexp {^(set_input_delay|set_output_delay)\s} $t]} { continue }
        set toks [wi086_tokens $t]
        set cmd [lindex $toks 0]
        set clock ""; set mm both; set value ""; set objs ""; set flags {}
        set i 1
        set n [llength $toks]
        while {$i < $n} {
            set tk [lindex $toks $i]
            switch -- $tk {
                -clock { set clock [lindex $toks [incr i]] }
                -max { set mm max }
                -min { set mm min }
                -reference_pin - -level_sensitive - -rise - -fall - -clock_fall - -add_delay - -network_latency_included - -source_latency_included { lappend flags $tk }
                default {
                    if {$value eq "" && [string is double -strict $tk]} { set value $tk } elseif {[string index $tk 0] eq "-"} { lappend flags $tk } elseif {$objs eq ""} { set objs $tk } else { lappend flags $tk }
                }
            }
            incr i
        }
        if {$clock eq "" || $value eq "" || $objs eq ""} { lappend bad "cannot understand: $t"; continue }
        lappend out [dict create cmd $cmd kind [expr {$cmd eq "set_input_delay" ? "in" : "out"}] clock $clock minmax $mm value $value objs $objs flags $flags raw $t]
    }
    return [list $out $bad]
}

# wi086_line <io dict> <extra flags> ?value? -> the command text with the extra flags added (once) and, if given, a new value
proc wi086_line {d extra {newvalue ""}} {
    set flags [dict get $d flags]
    foreach e $extra { if {[lsearch -exact $flags $e] < 0} { lappend flags $e } }
    set s "[dict get $d cmd] -clock [dict get $d clock]"
    if {[dict get $d minmax] ne "both"} { append s " -[dict get $d minmax]" }
    foreach f $flags { append s " $f" }
    append s " [expr {$newvalue ne {} ? $newvalue : [dict get $d value]}] [dict get $d objs]"
    return $s
}

# wi086_patterns <objs token> -> {patterns all}: the names inside {...} of `[get_ports {a b[*]}]`, or all=1 for [all_inputs] / [all_outputs]
proc wi086_patterns {objs} {
    if {[regexp {all_(inputs|outputs)} $objs]} { return [list {} 1] }
    if {[regexp {\{([^\}]*)\}} $objs -> inner]} { return [list [split [string trim $inner]] 0] }
    if {[regexp {get_ports\s+(\S+)\s*\]?$} $objs -> one]} { return [list [list [string trim $one "\]"]] 0] }
    return [list {} 0]
}

# wi086_match <SDC pattern> <port name> -> 1 when the glob matches; brackets in SDC patterns are LITERAL (bus bits), only * and ? are wildcards
proc wi086_match {pat name} {
    set re [string map {. \\. + \\+ ( \\( ) \\) | \\| ^ \\^ $ \\$ \{ \\\{ \} \\\} \\ \\\\} $pat]
    set re [string map {\[ \\\[ \] \\\] * .* ? .} $re]
    return [regexp -- "^${re}\$" $name]
}

# wi086_ports_of <io dict> <all ports of that direction> -> the port names the command covers
proc wi086_ports_of {d allports} {
    lassign [wi086_patterns [dict get $d objs]] pats all
    if {$all} { return $allports }
    set o {}
    foreach p $allports { foreach pt $pats { if {[wi086_match $pt $p]} { lappend o $p; break } } }
    return $o
}

# wi086_experiments_a1 <io dicts> <extra flags> -> list of {command-text n_ports}: every I/O delay command re-issued with the flags, original values and clocks kept
proc wi086_experiments_a1 {ios extra inports outports} {
    set o {}
    foreach d $ios {
        set ports [wi086_ports_of $d [expr {[dict get $d kind] eq "in" ? $inports : $outports}]]
        lappend o [list [wi086_line $d $extra] [llength $ports]]
    }
    return $o
}

# wi086_emulate <io dicts> <inports> <outports> <cone in> <cone out> <l_in> <l_out> -> list of {command-text n_ports}
# input -min lines: value - l_in on the ports NOT in the cone; output -max lines: value + l_out on the ports NOT in the cone. Lines that are not -min inputs / -max outputs are not touched.
# A command whose covered ports are all in the cone is skipped (n=0 is not emitted). Ports are listed explicitly: [get_ports {p1 p2 ...}].
proc wi086_emulate {ios inports outports cone_in cone_out l_in l_out} {
    set o {}
    foreach d $ios {
        set kind [dict get $d kind]; set mm [dict get $d minmax]
        if {$kind eq "in" && $mm eq "min"} { set delta [expr {-1.0 * $l_in}]; set cone $cone_in; set all $inports } elseif {$kind eq "out" && $mm eq "max"} { set delta $l_out; set cone $cone_out; set all $outports } else { continue }
        set ports {}
        foreach p [wi086_ports_of $d $all] { if {[lsearch -exact $cone $p] < 0} { lappend ports $p } }
        if {[llength $ports] == 0} { continue }
        set nd [dict replace $d objs "\[get_ports \{$ports\}\]"]
        lappend o [list [wi086_line $nd {} [format %.4f [expr {[dict get $d value] + $delta}]]] [llength $ports]]
    }
    return $o
}

# wi086_stage_rows <report text> -> the rows of the launch half after the clock edge lines up to `data arrival time`: list of {name incr}, rows with an increment only
proc wi086_stage_rows {text} {
    set rows [diag084_rows $text]
    set o {}
    foreach r $rows {
        if {[lindex $r 4] != 0} { continue }
        if {[lindex $r 0] eq "data arrival time"} { break }
        if {[lindex $r 1] eq ""} { continue }
        if {[regexp {^clock |^clk \(in\)} [lindex $r 0]]} { continue }
        lappend o [list [lindex $r 0] [lindex $r 1]]
    }
    return $o
}

# wi086_stage_cmp <icc rows {name incr}> <pt stages {label cell incr}> <tol> -> list of lines: stage by stage, in order, with the difference, and the largest one flagged
proc wi086_stage_cmp {icc pt tol} {
    set out {}
    set n [expr {max([llength $icc], [llength $pt])}]
    set worst -1; set wi -1
    for {set i 0} {$i < $n} {incr i} {
        set a [lindex $icc $i]; set b [lindex $pt $i]
        set ai [expr {$a eq "" ? "n/a" : [lindex $a 1]}]; set an [expr {$a eq "" ? "(no stage)" : [lindex $a 0]}]
        set bi [expr {$b eq "" ? "n/a" : [lindex $b 2]}]; set bn [expr {$b eq "" ? "(no stage)" : "[lindex $b 0][expr {[lindex $b 1] ne {} ? " ([lindex $b 1])" : {}}]"}]
        if {$ai eq "n/a" || $bi eq "n/a"} { set df "n/a" } else { set df [expr {$ai - $bi}]; if {abs($df) > $worst} { set worst [expr {abs($df)}]; set wi $i } }
        lappend out [list $i $an $ai $bn $bi $df]
    }
    set lines {}
    foreach r $out {
        lassign $r i an ai bn bi df
        set flag [expr {$df ne "n/a" && abs($df) > $tol ? "  <-- differs by more than $tol" : ""}]
        lappend lines [format "stage %d  ICC2 %-44s %8s   PrimeTime %-34s %8s   diff %8s%s" $i $an [expr {$ai eq "n/a" ? "n/a" : [format %.4f $ai]}] $bn [expr {$bi eq "n/a" ? "n/a" : [format %.4f $bi]}] [expr {$df eq "n/a" ? "n/a" : [format %+.4f $df]}] $flag]
    }
    if {$wi >= 0} { lappend lines [format "largest stage difference: stage %d, %+.4f ns" $wi [expr {[lindex [lindex $out $wi] 5]}]] }
    return $lines
}

# wi086_restore_check <baseline parsed dict> <now parsed dict> <tol> -> list of problems ("" list = restored)
proc wi086_restore_check {base now tol} {
    set p {}
    foreach k {launch capture arrival required slack} {
        set a [dict get $base $k]; set b [dict get $now $k]
        if {$a eq "n/a" || $b eq "n/a"} { if {$a ne $b} { lappend p "$k: baseline $a, now $b" }; continue }
        if {abs($a - $b) > $tol} { lappend p [format "%s: baseline %.4f, now %.4f" $k $a $b] }
    }
    return $p
}

# wi086_help_latency_lines <help text> -> the lines that mention latency options (so the user sees what the tool says)
proc wi086_help_latency_lines {text} {
    set o {}
    foreach l [split $text "\n"] { if {[regexp -nocase {latency} $l]} { lappend o [string trim $l] } }
    return $o
}

# wi086_clock_latency_lines <sdc text> -> list of dicts {line value flags} for every set_clock_latency command (the line that the tool writes on its own)
proc wi086_clock_latency_lines {text} {
    set o {}
    foreach l [split $text "\n"] {
        set t [string trim $l]
        if {![regexp {^set_clock_latency\s} $t]} { continue }
        set val ""; set flags {}
        foreach tk [wi086_tokens $t] {
            if {$tk eq "set_clock_latency"} continue
            if {$val eq "" && [string is double -strict $tk]} { set val $tk } elseif {[string index $tk 0] eq "-"} { lappend flags $tk }
        }
        lappend o [dict create line $t value $val flags $flags]
    }
    return $o
}

# wi086_a0_table <entries {block scenario count values}> -> {lines first_block_per_scenario_text}: one line per block and scenario, and the first block of the chain in which each scenario has the attribute
proc wi086_a0_table {entries} {
    set lines {}; array set first {}; set scens {}
    foreach e $entries {
        lassign $e b s c v
        lappend lines [format "block %-22s scenario %-10s set_clock_latency lines: %d  values: %s" $b $s $c [expr {[llength $v] ? [join $v {, }] : {-}}]]
        if {[lsearch -exact $scens $s] < 0} { lappend scens $s }
        if {$c > 0 && ![info exists first($s)]} { set first($s) $b }
    }
    set f {}
    foreach s $scens { lappend f "$s: [expr {[info exists first($s)] ? "first in $first($s)" : {never (0 lines in every block probed)}}]" }
    return [list $lines [join $f "; "]]
}

# wi086_launch_rows <report text> <n> -> the first n rows of the launch half as text lines (name, incr, path), so a launch latency can be checked by eye against the parsed number
proc wi086_launch_rows {text n} {
    set o {}
    foreach r [diag084_rows $text] {
        if {[lindex $r 4] != 0} { continue }
        lappend o [format "%-48s incr %8s  path %8s %s" [lindex $r 0] [lindex $r 1] [lindex $r 2] [lindex $r 3]]
        if {[llength $o] >= $n} { break }
    }
    return $o
}

# wi086_scan_sdc <file name> <sdc text> -> list of {file line_number text} for every set_clock_latency line
proc wi086_scan_sdc {fname text} {
    set o {}; set n 0
    foreach l [split $text "\n"] { incr n; if {[regexp {^\s*set_clock_latency\s} $l]} { lappend o [list $fname $n [string trim $l]] } }
    return $o
}

# wi086_export_dir <default> <env value or NONE> -> {dir source}; a set variable must name an existing directory (checked by the caller with file isdirectory)
proc wi086_export_dir {default envval} {
    if {$envval eq "NONE"} { return [list $default default] }
    if {$envval eq ""} { error "ERROR 086: UNPU_WI_EXPORT_DIR is set but empty" }
    return [list $envval "environment UNPU_WI_EXPORT_DIR"]
}

# wi086_help_has <help text> <option> -> 1 when the option name appears in the help text
proc wi086_help_has {text opt} { return [expr {[string first $opt $text] >= 0}] }

# wi086_row <experiment label> <metrics dict> -> one table line. keys: hold_launch hold_capture hold_arrival hold_slack setup_capture setup_required setup_slack beat_launch io_setup io_hold changed failed
proc wi086_row {label m} {
    set f {}
    foreach k {hold_launch hold_capture hold_arrival hold_slack setup_capture setup_required setup_slack beat_launch io_setup io_hold r2r_setup r2r_hold} { lappend f [diag084_num [dict get $m $k]] }
    return [format "%-6s hold: launch %s capture %s arrival %s slack %s | setup dma_addr\[31\]: capture %s required %s slack %s start-flop launch %s | in2out setup %s hold %s | reg-to-reg setup %s hold %s | constraints changed %s, command failures %s" $label {*}$f [dict get $m changed] [dict get $m failed]]
}

# wi086_verdict_a <rows: list of {label metrics}> <thr> -> list of lines: for each experiment whether it shows PrimeTime's convention (launch and capture both below thr), whether the in2out numbers stayed
proc wi086_verdict_a {rows base thr tol_io {ref {}}} {
    set o {}
    foreach r $rows {
        lassign $r label m
        set hl [dict get $m hold_launch]; set sc [dict get $m setup_capture]
        if {$label eq "A2"} {
            # the emulation changes the DELAYS, not the latency: the launch/capture rows stay; judge it by the slacks against PrimeTime's
            set hs [dict get $m hold_slack]; set ss [dict get $m setup_slack]
            set cmpt ""
            if {[dict exists $ref hold_slack] && [dict exists $ref setup_slack]} { set cmpt [format " (PrimeTime: hold %s, dma_addr\[31\] setup %s)" [diag084_num [dict get $ref hold_slack]] [diag084_num [dict get $ref setup_slack]]] }
            lappend o [format "%s: emulation by offsets; hold slack %s, dma_addr\[31\] setup slack %s%s; the latency rows are not expected to change" $label [diag084_num $hs] [diag084_num $ss] $cmpt]
            continue
        }
        if {$hl eq "n/a" || $sc eq "n/a"} { lappend o "$label: INCONCLUSIVE (launch or capture not readable)"; continue }
        set conv [expr {abs($hl) < $thr && abs($sc) < $thr}]
        set io_ok 1; set why {}
        foreach k {io_setup io_hold} {
            set b [dict get $base $k]; set v [dict get $m $k]
            if {$b eq "n/a" || $v eq "n/a"} { set io_ok 0; lappend why "$k unreadable"; continue }
            if {abs($v - $b) > $tol_io} { set io_ok 0; lappend why [format "%s moved %+.4f" $k [expr {$v - $b}]] }
        }
        set r_ok 1; set rwhy {}
        foreach k {r2r_setup r2r_hold} {
            set b [dict get $base $k]; set v [dict get $m $k]
            if {$b eq "n/a" || $v eq "n/a"} { set r_ok 0; lappend rwhy "$k unreadable"; continue }
            if {abs($v - $b) > $tol_io} { set r_ok 0; lappend rwhy [format "%s moved %+.4f" $k [expr {$v - $b}]] }
        }
        lappend o [format "%s: %s%s%s" $label [expr {$conv ? "SHOWS THE PRIMETIME CONVENTION (launch [diag084_num $hl], capture [diag084_num $sc])" : "does NOT show it (launch [diag084_num $hl], capture [diag084_num $sc])"}] [expr {$io_ok ? "; in2out unchanged" : "; in2out CHANGED ([join $why {, }])"}] [expr {$r_ok ? "; reg-to-reg unchanged" : "; reg-to-reg CHANGED ([join $rwhy {, }])"}]]
    }
    return $o
}
# ---- END PURE TCL 086 ----

# ==============================================================================
# ICC2 part
# ==============================================================================
set WI_FAILED 0
set WI_TOTAL 0
proc wi_fail {label msg} { global WI_FAILED; incr WI_FAILED; puts ">>> 086 FAILED: $label: $msg" }
proc wi_run {label script} {   ;# run a command string under catch, capture and print its text, write it to <diag>/<label>.rpt
    global DIAG_DIR WI_TOTAL
    incr WI_TOTAL
    puts "\n>>> 086 ===== $label ====="
    puts ">>> 086 command: $script"
    set txt ""
    if {[catch {redirect -variable txt { eval $script }} err]} { puts $txt; wi_fail $label $err; return "" }
    puts $txt
    set ext [expr {[string match help_* $label] ? "txt" : "rpt"}]
    if {[catch {set fp [open ${DIAG_DIR}/${label}.${ext} w]; puts $fp "# $script"; puts $fp $txt; close $fp} werr]} { wi_fail "$label (writing the file)" $werr }
    return $txt
}
proc wi_names {coll} { set o {}; foreach_in_collection x $coll { lappend o [get_object_name $x] }; return $o }
proc wi_open {} {   ;# (re)open the block from the copy: unsaved changes of the previous state are discarded
    global DIAG_LIB WI_BLOCK
    catch {close_blocks -force [get_blocks -quiet *]}
    open_block ${DIAG_LIB}:${WI_BLOCK}
    if {[catch {link_block} lerr]} { puts ">>> 086 link_block: $lerr (not fatal)" }
}
proc wi_wns {scen type from_ports to_ports} {
    set p [get_timing_paths -scenarios $scen -delay_type $type -from $from_ports -to $to_ports -max_paths 1]   ;# usage text [L]
    if {[sizeof_collection $p] == 0} { return "n/a" }
    return [get_attribute $p slack]
}
proc wi_measure {label} {
    global HOLD_SCEN SETUP_SCEN HOLD_FROM_PORT HOLD_TO_PIN SETUP_TO_PORT SETUP_FROM_CELL IN2OUT_SETUP_FROM IN2OUT_HOLD_FROM IN2OUT_TO_PORTS
    set rt "-path_type full_clock_expanded -input_pins -nets -significant_digits 4 -nosplit"
    set to_opt ""
    if {[sizeof_collection [get_pins -quiet $HOLD_TO_PIN]] > 0} { set to_opt "-to \[get_pins \{$HOLD_TO_PIN\}\]" }
    set th [wi_run wi_${label}_hold_input "report_timing -scenarios $HOLD_SCEN -delay_type min -from \[get_ports \{$HOLD_FROM_PORT\}\] $to_opt $rt"]
    set ts [wi_run wi_${label}_setup_dma_addr31 "report_timing -scenarios $SETUP_SCEN -delay_type max -to \[get_ports \{$SETUP_TO_PORT\}\] $rt"]
    set tb ""
    if {[sizeof_collection [get_cells -quiet $SETUP_FROM_CELL]] > 0} { set tb [wi_run wi_${label}_setup_from_beat "report_timing -scenarios $SETUP_SCEN -delay_type max -from \[get_cells \{$SETUP_FROM_CELL\}\] -to \[get_ports \{$SETUP_TO_PORT\}\] $rt"] }
    set io_s "n/a"; set io_h "n/a"
    if {[catch {set io_s [wi_wns $SETUP_SCEN max [get_ports -exact $IN2OUT_SETUP_FROM] [get_ports $IN2OUT_TO_PORTS]]} e1]} { wi_fail "wi_${label} in2out setup" $e1 }
    if {[catch {set io_h [wi_wns $HOLD_SCEN min [get_ports -exact $IN2OUT_HOLD_FROM] [get_ports $IN2OUT_TO_PORTS]]} e2]} { wi_fail "wi_${label} in2out hold" $e2 }
    set r2r_s "n/a"; set r2r_h "n/a"
    if {[catch {set r2r_s [wi_wns $SETUP_SCEN max [all_registers -edge_triggered] [all_registers -edge_triggered]]} e3]} { wi_fail "wi_${label} reg-to-reg setup" $e3 }   ;# VERIFY all_registers -edge_triggered as -from / -to
    if {[catch {set r2r_h [wi_wns $HOLD_SCEN min [all_registers -edge_triggered] [all_registers -edge_triggered]]} e4]} { wi_fail "wi_${label} reg-to-reg hold" $e4 }
    puts ">>> 086 wi_${label} reg-to-reg worst slack: setup $r2r_s, hold $r2r_h"
    puts ">>> 086 wi_${label} the first rows of the launch half of the hold path (to read the launch latency by eye):"
    foreach l [wi086_launch_rows $th 8] { puts ">>> 086       $l" }
    puts ">>> 086 wi_${label} in2out setup $IN2OUT_SETUP_FROM -> $IN2OUT_TO_PORTS: $io_s; in2out hold $IN2OUT_HOLD_FROM -> $IN2OUT_TO_PORTS: $io_h"
    return [dict create hold [diag084_parse $th] setup [diag084_parse $ts] beat [diag084_parse $tb] io_setup $io_s io_hold $io_h r2r_setup $r2r_s r2r_hold $r2r_h hold_txt $th setup_txt $ts]
}
proc wi_metrics {meas changed failed} {
    set h [dict get $meas hold]; set s [dict get $meas setup]; set b [dict get $meas beat]
    set arr [dict get $h arrival]; set la [dict get $h launch]
    return [dict create hold_launch [dict get $h launch] hold_capture [dict get $h capture] hold_arrival $arr hold_slack [dict get $h slack] setup_capture [dict get $s capture] setup_required [dict get $s required] setup_slack [dict get $s slack] beat_launch [dict get $b launch] io_setup [dict get $meas io_setup] io_hold [dict get $meas io_hold] r2r_setup [dict get $meas r2r_setup] r2r_hold [dict get $meas r2r_hold] changed $changed failed $failed]
}

file mkdir $DIAG_DIR
puts "\n>>> 086 IN-MEMORY WHAT-IF: nothing is saved. Library copy: $DIAG_LIB, block: $DIAG_BLOCK. Output folder: $DIAG_DIR"

# ---- 1. guards (as diag_io_latency.tcl) ----
set lib_msg [diag084_lib_check $DIAG_LIB $RUN_ROOT]
if {$lib_msg ne ""} { error $lib_msg }
set WI_BLOCK $DIAG_BLOCK
set open_lib_all [get_libs -quiet *]
if {[sizeof_collection $open_lib_all] > 0} { foreach_in_collection lib_obj $open_lib_all { close_lib -force $lib_obj } }
open_lib $DIAG_LIB   ;# [L] open_lib usage; opened for EDIT on purpose: the what-if edits constraints in memory. The copy is disposable and nothing is saved; run 1 is protected by the guard above.
set existing {}
catch {set existing [wi_names [get_blocks -all -quiet]]}
set bl_msg [diag084_block_check $DIAG_BLOCK $existing]
if {$bl_msg ne ""} { error $bl_msg }
puts ">>> 086 blocks in the copy: $existing"
wi_open
puts ">>> 086 opened: [get_object_name [current_block]]"

# ---- 2. scenarios, help texts ----
set scen_names {}
catch {set scen_names [wi_names [get_scenarios]]}
lassign [diag084_pick_scenario $scen_names $SETUP_SCEN_PATTERN] s_ok SETUP_SCEN s_msg
lassign [diag084_pick_scenario $scen_names $HOLD_SCEN_PATTERN]  h_ok HOLD_SCEN  h_msg
puts ">>> 086 scenarios $scen_names: setup -> $s_msg; hold -> $h_msg"
if {!$s_ok || !$h_ok} { error "ERROR 086: the scenarios are not unique ($s_msg / $h_msg): nothing to compare" }
# 086 A0: the help texts that explain where the line comes from and how to remove it (saved as diag/help_*.txt; the command lists are [L] for the names, the option texts are new)
wi_run help_remove_clock_latency "help remove_clock_latency"
wi_run help_compute_clock_latency "help compute_clock_latency"
wi_run help_latency_cmds "help *latency*"
foreach opt {time.all_clocks_propagated time.enable_io_path_groups time.deprioritize_io_path_groups time.allow_port_latency_for_feedthrough time.edge_specific_source_latency clock_opt.flow.enable_ccd ccd.hold_control_effort ccd.ignore_ports_for_boundary_identification cts.balance_groups.honor_source_latency opt.clock_latency_estimation.report_skipped_pins} {
    wi_run app_option_[string map {. _} $opt] "report_app_options $opt"   ;# one option per call (a call with several names failed in the 084 run); [L] report_app_options patterns
}
wi_run clock_attributes {list_attributes -class clock}   ;# VERIFY list_attributes -class clock: the 084 run found no is_propagated attribute; this lists the attributes that exist
wi_run clocks_report {report_clocks -nosplit}   ;# VERIFY report_clocks -nosplit
set help_all ""
foreach hf $HELP_LATENCY_FILES {
    set path ${DIAG_DIR}/$hf
    if {![file exists $path]} { puts ">>> 086 $hf not found in the diag folder (run diag_io_latency.tcl first): the options are tried without the help text"; continue }
    set fp [open $path r]; set ht [read $fp]; close $fp
    append help_all $ht
    puts ">>> 086 $hf: lines about latency:"
    foreach l [wi086_help_latency_lines $ht] { puts "      $l" }
}
foreach opt {-network_latency_included -source_latency_included} {
    puts ">>> 086 help texts mention $opt: [expr {$help_all eq {} ? {unknown (no help text)} : [wi086_help_has $help_all $opt]}]"
}

# ---- 3. baseline, the I/O constraints (from the active SDC), the clock ports, the cone ----
puts "\n>>> 086 ################ BASELINE ($DIAG_BLOCK) ################"
set base [wi_measure base]
set base_m [wi_metrics $base 0 0]
puts ">>> 086 [wi086_row base $base_m]"
set sdc_file ${DIAG_DIR}/whatif_${SETUP_SCEN}.sdc
wi_run wi_write_sdc "write_sdc -scenario $SETUP_SCEN -output $sdc_file"   ;# [L] write_sdc -scenario / -output
if {![file exists $sdc_file]} { error "ERROR 086: the SDC copy $sdc_file was not written: the I/O delay lines cannot be read, experiment A cannot be built" }
set fp [open $sdc_file r]; set sdc_txt [read $fp]; close $fp
lassign [wi086_parse_io $sdc_txt] ios bad
foreach b $bad { wi_fail "SDC parse" $b }
puts ">>> 086 I/O delay commands read from the active constraints ($SETUP_SCEN): [llength $ios] (set_input_delay [llength [lsearch -all -inline -regexp $ios {kind in}]] / set_output_delay)"
foreach d $ios { puts "      [dict get $d raw]" }
if {[llength $ios] == 0} { error "ERROR 086: no set_input_delay / set_output_delay line found in $sdc_file" }
set inports [wi_names [all_inputs]]
set outports [wi_names [all_outputs]]
set clock_ports {}
foreach_in_collection ck [get_clocks -quiet -filter "is_virtual == false"] {
    set srcs [get_attribute -quiet $ck sources]   ;# VERIFY the clock attribute `sources`
    if {$srcs ne "" && [sizeof_collection $srcs] > 0} { foreach s [wi_names $srcs] { lappend clock_ports $s } }
}
if {[llength $clock_ports] == 0} { set clock_ports $CLOCK_PORT_NAMES; puts ">>> 086 clock ports taken from CLOCK_PORT_NAMES: $clock_ports" }
set cone_in {}; set cone_out_set {}
foreach p $inports {
    if {[lsearch -exact $clock_ports $p] >= 0} { continue }
    set ep {}
    if {[catch {set ep [wi_names [all_fanout -flat -endpoints_only -from [get_ports -exact $p]]]} ferr]} { wi_fail "cone of $p" $ferr; continue }   ;# VERIFY all_fanout -flat -endpoints_only -from (as port_buffers_early.tcl)
    set hit 0
    foreach e $ep { if {[lsearch -exact $outports $e] >= 0} { set hit 1; lappend cone_out_set $e } }
    if {$hit} { lappend cone_in $p }
}
set cone_out [lsort -unique $cone_out_set]
puts ">>> 086 input-to-output cone: [llength $cone_in] input ports {$cone_in} reach [llength $cone_out] output ports {$cone_out}"
set noncone_in [llength [lsearch -all -inline -not -exact $inports clk]]

# ---- 3b. A0 (a): where does `set_clock_latency` first exist? write_sdc of every block of the chain, count per scenario ----
puts "\n>>> 086 ################ A0 (a): the set_clock_latency line per block and scenario ################"
set a0_entries {}
foreach b $BLOCK_CHAIN {
    set bn "${DESIGN_NAME}_$b"
    if {[lsearch -glob $existing "*:$bn"] < 0 && [lsearch -exact $existing $bn] < 0 && [lsearch -glob $existing "*:$bn/*"] < 0} { puts ">>> 086 A0(a) block $bn is not in the copy: skipped"; continue }
    set WI_BLOCK $bn
    if {[catch {wi_open} oerr]} { wi_fail "A0(a) open $bn" $oerr; continue }
    set bsc {}
    catch {set bsc [wi_names [get_scenarios]]}
    if {[llength $bsc] == 0} { wi_fail "A0(a) $bn" "no scenario found in the block"; continue }
    foreach s $bsc {
        set f ${DIAG_DIR}/whatif_a0_${b}_${s}.sdc
        wi_run wi_a0_write_${b}_${s} "write_sdc -scenario $s -output $f"
        if {![file exists $f]} { lappend a0_entries [list $bn $s -1 {}]; continue }
        set fp [open $f r]; set tx [read $fp]; close $fp
        set cl [wi086_clock_latency_lines $tx]
        lappend a0_entries [list $bn $s [llength $cl] [lmap x $cl {dict get $x value}]]
    }
}
set WI_BLOCK $DIAG_BLOCK
wi_open
lassign [wi086_a0_table $a0_entries] a0_lines a0_first
foreach l $a0_lines { puts ">>> 086 A0(a) $l" }
puts ">>> 086 A0(a) first block with the attribute: $a0_first"
puts ">>> 086 A0(a) (-1 lines would mean the SDC file was not written; the failed report is listed above)"

# ---- 4. experiment A ----
set L_in [dict get $base hold launch]
set L_out [dict get $base setup capture]
puts ">>> 086 measured ICC2 reference latencies: input launch (hold, $HOLD_SCEN) $L_in, output capture (setup, $SETUP_SCEN) $L_out"
# the SDC attribute against the measured numbers (the A0 hypothesis: they are the same thing)
foreach {sc lbl measured} [list $SETUP_SCEN setup $L_out $HOLD_SCEN hold $L_in] {
    set f ${DIAG_DIR}/whatif_chk_${sc}.sdc
    wi_run wi_chk_write_${sc} "write_sdc -scenario $sc -output $f"
    if {![file exists $f]} { continue }
    set fp [open $f r]; set tx [read $fp]; close $fp
    set cl [wi086_clock_latency_lines $tx]
    puts ">>> 086 A0 scenario $sc ($lbl): set_clock_latency lines in the SDC: [llength $cl] [expr {[llength $cl] ? "values [lmap x $cl {dict get $x value}] lines {[lmap x $cl {dict get $x line}]}" : {}}]; measured ICC2 $lbl reference latency $measured"
    foreach x $cl { if {[dict get $x value] ne "" && $measured ne "n/a"} { puts [format ">>> 086 A0   SDC value %s minus measured %s = %+.4f ns" [dict get $x value] $measured [expr {[dict get $x value] - $measured}]] } }
}
set experiments [list]
lappend experiments [list A0 REMOVE] [list A1a "-network_latency_included"] [list A1b "-source_latency_included"] [list A1c "-network_latency_included -source_latency_included"] [list A2 EMULATE]
set a_rows [list [list base $base_m]]
foreach ex $experiments {
    lassign $ex label what
    puts "\n>>> 086 ################ EXPERIMENT $label ($what) ################"
    wi_open   ;# a fresh state: whatever the previous experiment did is gone
    set changed 0; set failed 0
    set cf [open ${DIAG_DIR}/whatif_${label}_commands.txt w]
    if {$what eq "REMOVE"} {
        # A0 (b): remove the tool-written set_clock_latency per scenario with the first form that works, then verify by writing the SDC again
        foreach s [list $SETUP_SCEN $HOLD_SCEN] {
            set done ""
            foreach form $REMOVE_FORMS {
                set txt "current_scenario $s ; $form"
                if {[catch {eval $txt} err]} { puts ">>> 086 A0 form failed in $s: $form : $err" } else { set done $txt; break }
            }
            if {$done eq ""} { incr failed; wi_fail "A0 remove in $s" "none of the forms worked: $REMOVE_FORMS"; continue }
            puts $cf $done
            puts ">>> 086 A0 command used in $s: $done"
            set f ${DIAG_DIR}/whatif_A0_after_${s}.sdc
            wi_run wi_a0_after_write_$s "write_sdc -scenario $s -output $f"
            set left -1
            if {[file exists $f]} { set fp [open $f r]; set tx [read $fp]; close $fp; set left [llength [wi086_clock_latency_lines $tx]] }
            puts ">>> 086 A0 after the removal in $s: set_clock_latency lines left in the SDC: $left"
            if {$left == 0} { incr changed } else { incr failed; wi_fail "A0 remove in $s" "$left set_clock_latency lines are still in the SDC after the removal" }
        }
        set cmds {}
    } elseif {$what eq "EMULATE"} {
        if {$L_in eq "n/a" || $L_out eq "n/a"} { wi_fail $label "the baseline latencies are not readable: the emulation cannot be built"; close $cf; continue }
        set cmds [wi086_emulate $ios $inports $outports $cone_in $cone_out $L_in $L_out]
    } else {
        set cmds [wi086_experiments_a1 $ios $what $inports $outports]
    }
    foreach c $cmds {
        lassign $c text np
        puts $cf $text
        puts ">>> 086 $label command ($np ports): [expr {[string length $text] > 300 ? "[string range $text 0 300] ... (full text in whatif_${label}_commands.txt)" : $text}]"
        if {[catch {eval $text} err]} { incr failed; wi_fail "$label command" "$err   <- $text" } else { incr changed $np }
    }
    close $cf
    puts ">>> 086 $label: [llength $cmds] commands, $changed changed (ports, or scenarios for A0), $failed failures"
    set meas [wi_measure $label]
    set m [wi_metrics $meas $changed $failed]
    puts ">>> 086 [wi086_row $label $m]"
    lappend a_rows [list $label $m]
    # restore: reopen the block (unsaved edits are dropped) and re-run the paths
    wi_open
    set chk [wi_measure ${label}_restore]
    set probs [concat [wi086_restore_check [dict get $base hold] [dict get $chk hold] $TOL_RESTORE_NS] [wi086_restore_check [dict get $base setup] [dict get $chk setup] $TOL_RESTORE_NS]]
    if {[llength $probs] == 0} { puts ">>> 086 RESTORE CHECK $label: OK (hold and setup paths give the baseline numbers again)" } else { wi_fail "RESTORE CHECK $label" [join $probs {; }] }
}

# ---- 4b. A0 (d): the line in the exported SDCs (read-only grep) ----
puts "\n>>> 086 ################ A0 (d): set_clock_latency in the exported SDCs ################"
set evn [expr {[info exists ::env(UNPU_WI_EXPORT_DIR)] ? $::env(UNPU_WI_EXPORT_DIR) : "NONE"}]
lassign [wi086_export_dir $EXPORT_SDC_DIR $evn] exp_dir exp_src
puts ">>> 086 export folder: $exp_dir ($exp_src)"
if {![file isdirectory $exp_dir]} {
    if {$exp_src ne "default"} { error "ERROR 086: UNPU_WI_EXPORT_DIR='$exp_dir' is not a directory" }
    puts ">>> 086 A0(d) the folder does not exist yet (the flow has not exported an SDC in this clone): nothing to search"
} else {
    set exp_files [lsort [glob -nocomplain -directory $exp_dir unpu_top*.sdc]]
    puts ">>> 086 A0(d) SDC files found: [llength $exp_files] {$exp_files}"
    set exp_hits 0
    foreach f $exp_files {
        set fp [open $f r]; set tx [read $fp]; close $fp
        set hits [wi086_scan_sdc $f $tx]
        incr exp_hits [llength $hits]
        foreach h $hits { puts ">>> 086 A0(d) [file tail [lindex $h 0]] line [lindex $h 1]: [lindex $h 2]" }
        if {[llength $hits] == 0} { puts ">>> 086 A0(d) [file tail $f]: no set_clock_latency line" }
    }
    puts ">>> 086 A0(d) total set_clock_latency lines in the exported SDCs: $exp_hits"
}

# ---- 5. part B: the data-delay difference ----
puts "\n>>> 086 ################ PART B: stage by stage, hold path $HOLD_FROM_PORT ################"
wi_open
set ic_rows [wi086_stage_rows [dict get $base hold_txt]]
foreach l [wi086_stage_cmp $ic_rows $PT_HOLD_STAGES $TOL_STAGE_NS] { puts ">>> 086 $l" }
set ic_total 0.0; foreach r $ic_rows { set ic_total [expr {$ic_total + [lindex $r 1]}] }
puts [format ">>> 086 ICC2 data delay (sum of the stage increments) %.4f ns, arrival %s; PrimeTime arrival %.2f ns" $ic_total [diag084_num [dict get $base hold arrival]] $PT_HOLD_ARRIVAL]
puts ">>> 086 same ICC2 hold path with slew, capacitance and derate columns (compare with PrimeTime's `report_timing -transition_time -capacitance -derate -input_pins -nets` for the same path):"
wi_run wi_partB_hold_columns "report_timing -scenarios $HOLD_SCEN -delay_type min -from \[get_ports \{$HOLD_FROM_PORT\}\] -path_type full_clock_expanded -input_pins -nets -transition_time -capacitance -derate -significant_digits 4 -nosplit"
wi_run wi_partB_port_verbose "report_port -verbose \[get_ports \{$HOLD_FROM_PORT\}\]"   ;# VERIFY report_port -verbose (driving cell, load, transition of the port)
set drive_lines {}
foreach l [split $sdc_txt "\n"] { if {[regexp {^\s*(set_driving_cell|set_input_transition|set_load|set_wire_load)} $l]} { lappend drive_lines [string trim $l] } }
puts ">>> 086 SDC lines about the port drive and load ([llength $drive_lines]):"
foreach l [lrange $drive_lines 0 29] { puts "      $l" }
if {[llength $drive_lines] > 30} { puts "      ... ([expr {[llength $drive_lines] - 30}] more in $sdc_file)" }
puts ">>> 086 the same hold path from PrimeTime's side: run in pt_shell on the same netlist, the command lines are in the README (section 'diag_io_whatif.tcl')"
# the setup launch difference: the same path from PrimeTime's start flop
set sb [dict get $base beat]
puts [format ">>> 086 setup dma_addr\[31\]: ICC2 worst path starts at [dict get $base setup start] with launch %s; the same path from PrimeTime's start flop $SETUP_FROM_CELL gives launch %s (PrimeTime %.2f)" [diag084_num [dict get $base setup launch]] [diag084_num [dict get $sb launch]] $PT_SETUP_LAUNCH]
# the same baseline on the other blocks of the copy
foreach xb $EXTRA_BLOCKS {
    if {[lsearch -glob $existing "*:$xb"] < 0 && [lsearch -exact $existing $xb] < 0} { puts ">>> 086 block $xb is not in the copy: skipped"; continue }
    puts "\n>>> 086 ################ BASELINE on $xb ################"
    set WI_BLOCK $xb
    if {[catch {wi_open} oerr]} { wi_fail "open $xb" $oerr; continue }
    set xm [wi_measure base_$xb]
    puts ">>> 086 [wi086_row $xb [wi_metrics $xm 0 0]]"
    puts [format ">>> 086 data delay of the hold path on %s: %s ns (arrival - launch)" $xb [expr {[dict get $xm hold arrival] eq "n/a" || [dict get $xm hold launch] eq "n/a" ? "n/a" : [format %.4f [expr {[dict get $xm hold arrival] - [dict get $xm hold launch]}]]}]]
}
set WI_BLOCK $DIAG_BLOCK

# ---- 6. summary ----
puts "\n=============================================================================="
puts " 086 WHAT-IF SUMMARY (library $DIAG_LIB, block $DIAG_BLOCK)"
foreach r $a_rows { puts "   [wi086_row [lindex $r 0] [lindex $r 1]]" }
foreach l [wi086_verdict_a [lrange $a_rows 1 end] $base_m $H1_MIN_LATENCY_NS 0.005 [dict create hold_slack -0.35 setup_slack -0.24]] { puts "   $l" }
puts "   A0 first block: $a0_first"
puts "   PROPOSAL (not implemented): the tool writes a line the PM never gave. (1) remove it right after clock_opt in cts.tcl and again before every later optimisation (route.tcl, timing_closure.tcl) if A0 shows that ICC2 then uses 0.00 as PrimeTime does and the reg-to-reg slacks do not move; (2) pv.tcl: remove_clock_latency (the form A0 found) before write_sdc, and after write_sdc grep the exported file for set_clock_latency (hard error if any is left). VERIFY with this run."
puts "   baseline data delay on the hold path: [expr {[dict get $base hold arrival] eq {n/a} || [dict get $base hold launch] eq {n/a} ? {n/a} : [format %.4f [expr {[dict get $base hold arrival] - [dict get $base hold launch]}]]}] ns (PrimeTime 0.56)"
puts "   reports run: $WI_TOTAL, failed or restored wrongly: $WI_FAILED (raw messages above, lines '>>> 086 FAILED')"
puts "   nothing was saved. Check that run 1 was not written (README: ls -ld before/after)."
puts "=============================================================================="
catch {close_blocks -force [get_blocks -quiet *]}
puts ">>> 086 done. Type exit."
