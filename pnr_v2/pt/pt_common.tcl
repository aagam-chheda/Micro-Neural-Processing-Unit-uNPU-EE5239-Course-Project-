# ==============================================================================
# File : pt_common.tcl   (task 074: PrimeTime sign-off of the final layout)
# Path : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/pt/pt_common.tcl
# Tool : Synopsys PrimeTime (pt_shell T-2022.03-SP2 per handoff 18.2)
# Use  : sourced by pt_setup_ss.tcl and pt_hold_ff.tcl; it holds the paths and parameters in ONE place and the procs. At the top level it only SETs variables and
#        defines procs (no PrimeTime command is run on sourcing), so the pure-Tcl procs can be tested with tclsh (pnr_v2/pt/test_pt_common.tcl).
# Rules: PrimeTime only READS what ICC2 wrote (netlist, SPEF, per-scenario SDC); no constraint, uncertainty, limit or exception is added or changed. No $FOUNDRY.
#        Every command or option not known for sure is marked VERIFY (the README lists what to look at in the log).
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Paths and parameters (ONE place)
# ------------------------------------------------------------------------------
set PT_BASE      "/storage/EE5239G1/aagams_workspace2/unpu"
set PT_OUT_DIR   "${PT_BASE}/pnr_icc2/outputs"      ;# files written by pv.tcl
set PT_RPT_DIR   "${PT_BASE}/pnr_icc2/pt"           ;# all PrimeTime reports; created by the scripts
set PT_KIT       "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180"
set PT_DESIGN    "unpu_top"

# NETLIST: the one WITHOUT PG pins (unpu_top_pnr_sim.v). Reason: PrimeTime without UPF does not know the PG pins of the cells; and pv.tcl renames the nets N<digits> to N_uc_<digits> only in the
# PG netlist (unpu_top_pnr_pg.v, for case-insensitive LVS), so the SPEF (written by ICC2 with the original names) would not match its net names. VERIFY: link_design accepts this file.
set PT_NETLIST   "${PT_OUT_DIR}/${PT_DESIGN}_pnr_sim.v"
set PT_SPEF_BASE "${PT_OUT_DIR}/${PT_DESIGN}_spef"   ;# write_parasitics -output prefix of pv.tcl: <prefix>.TYPICAL_RC_125.spef, <prefix>.TYPICAL_RC_-40.spef, <prefix>.spef_scenario
set PT_SPEF_SCENARIO_FILE "${PT_SPEF_BASE}.spef_scenario"
set PT_SPEF_FILES [list "${PT_SPEF_BASE}.TYPICAL_RC_125.spef" "${PT_SPEF_BASE}.TYPICAL_RC_-40.spef"]   ;# the two files named in task 074
# Per corner: scenario / corner names that ICC2 used (design_setup.tcl: func_ss = corner_ss, func_ff = corner_ff), library, db file, SDC.
set PT_CORNER(ss,names) {func_ss corner_ss}
set PT_CORNER(ff,names) {func_ff corner_ff}
set PT_CORNER(ss,lib)   "tsl18fs120_scl_ss"
set PT_CORNER(ff,lib)   "tsl18fs120_scl_ff"
set PT_CORNER(ss,db)    "${PT_KIT}/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db"
set PT_CORNER(ff,db)    "${PT_KIT}/stdcell/fs120/4M1IL/liberty/lib_flow_ff/tsl18fs120_scl_ff.db"
set PT_CORNER(ss,sdc)   "${PT_OUT_DIR}/${PT_DESIGN}_pnr_ss.sdc"
set PT_CORNER(ff,sdc)   "${PT_OUT_DIR}/${PT_DESIGN}_pnr_ff.sdc"
set PT_CLOCK     "clk"

# Manual SPEF choice. EMPTY = decide from unpu_top_spef.spef_scenario (the only normal case). Set a file name ONLY after reading the printed content of the .spef_scenario file when the
# decision stopped with an error; the script then prints that it used the override.
set PT_SPEF_OVERRIDE(ss) ""
set PT_SPEF_OVERRIDE(ff) ""

# Expected constraint values: the legacy course constraints (constraints/legacy/unpu_top_legacy.sdc: create_clock -period 20, CLK_UNCERT_SETUP 1.5, CLK_UNCERT_HOLD 0.5)
set PT_EXPECT_PERIOD      20.0
set PT_EXPECT_SETUP_UNC   1.5
set PT_EXPECT_HOLD_UNC    0.5
# Expected design-wide limits (same legacy SDC: MAX_TRANSITION 3.0 ns, MAX_CAPACITANCE 2.0 pF); printed and compared, a difference is an error
set PT_EXPECT_MAX_TRANSITION 3.0
set PT_EXPECT_MAX_CAP        2.0

# Unannotated PIN-TO-PIN nets (the nets that carry timing arcs; driverless and loadless nets are information only): percent of the pin-to-pin nets that may be without parasitics. 0.0 = any unannotated net is an error (task 074). After the printed list has been read and explained
# (for example nets that are constants or have no loads) the user may raise it here with the reason written in the line.
set PT_MAX_UNANNOTATED_PCT 0.0
# 0 = a report_annotated_parasitics text that cannot be parsed is an error. 1 = continue, print a warning (use only after reading the text in the log)
set PT_ALLOW_UNREADABLE_ANNOTATION 0
# PrimeTime (T-2022.03-SP2) writes the text of read_parasitics / report_annotated_parasitics to this file in the CURRENT directory (PARA-107): the runbook runs from pnr_icc2/pt
set PT_PARA_LOG "parasitics_command.log"
# The log file is written BUFFERED: in the second server run it stayed at 0 bytes during the session and was complete only afterwards. pt_read_spef therefore sets the PrimeTime variable
# parasitics_log_file to an empty string before read_parasitics (VERIFY: an empty string makes the two commands print to the session) and reads the table from the session text.
# If the table is still not in the session, the script STOPS, unless the user declares the post-run check with the shell variable PT_ANNOTATION_CHECKED_AFTER=1 (csh: setenv PT_ANNOTATION_CHECKED_AFTER 1)
# and then runs `tclsh pnr_v2/pt/check_annotation.tcl parasitics_command.log` after the session; the SUMMARY block then carries the caveat.
set PT_ANNOTATION_ENV "PT_ANNOTATION_CHECKED_AFTER"

# Endpoints that are unconstrained by design and may be reported by check_timing (task 074: "known constants such as pready")
set PT_KNOWN_UNCONSTRAINED {pready}

# Signal integrity (PrimeTime-SI). DEFAULT OFF. The ICC2 numbers were computed with SI/crosstalk analysis ON (route.tcl: time.si_enable_analysis true). With SI OFF PrimeTime sees no
# crosstalk delta delay: its setup slack is usually BETTER (larger) and its hold slack usually BETTER than the ICC2 one, so a difference in that direction is expected.
# 1 = turn it on; the script then checks the licence and stops if it is not available.
set PT_SI_ENABLE 0

# ICC2 figures for the same checks (user's run, handoff 18.35: setup WNS +0.0143 ns func_ss, hold WNS about -0.0004 ns func_ff)
set PT_ICC2_SETUP_WNS  0.0143
set PT_ICC2_HOLD_WNS  -0.0004

# How many violated endpoints get a full path report in the hold script, and how many in the setup script
set PT_MAX_VIOLATED_DETAIL 50

# ---- BEGIN PURE TCL 074 ----
# 074: everything between BEGIN and END is plain Tcl (no PrimeTime command); pnr_v2/pt/test_pt_common.tcl tests these procs.

# 074: "" when the file exists and is not empty; otherwise a sentence
proc pt_file_problem {path} {
    if {![file exists $path]} { return "the file $path does not exist" }
    if {![file isfile $path]} { return "$path is not a regular file" }
    if {[file size $path] == 0} { return "the file $path is empty" }
    return ""
}

# 074: stop (error) with a clear message when the file is missing or empty; "what" says what the file is for
proc pt_need_file {path what} {
    set p [pt_file_problem $path]
    if {$p ne ""} { error "PT ERROR: $what: $p" }
    return $path
}

# 074: the tag of a SPEF file name: the text between "<prefix>." and ".spef" of "unpu_top_spef.TYPICAL_RC_125.spef" -> "TYPICAL_RC_125"
proc pt_spef_tag {file} {
    set b [file tail $file]
    if {[regexp {^[^.]*\.(.+)\.spef$} $b -> tag]} { return $tag }
    return $b
}

# 074: does a text line mention this SPEF file (full file name, base name, or its tag followed by a character that does not continue a number or word)?
proc pt_line_mentions_spef {line file} {
    set tag [pt_spef_tag $file]
    if {[string first $file $line] >= 0 || [string first [file tail $file] $line] >= 0} { return 1 }
    set i [string first $tag $line]
    while {$i >= 0} {
        set after [string index $line [expr {$i + [string length $tag]}]]
        if {$after eq "" || ![regexp {[A-Za-z0-9_]} $after]} { return 1 }
        set i [string first $tag $line [expr {$i + 1}]]
    }
    return 0
}

# 074: which corner does a text name? "ss" or "ff" or "both" or "" (neither). The names are the scenario and corner names of ICC2 (func_ss, corner_ss, func_ff, corner_ff).
proc pt_line_corner {line ss_names ff_names} {
    set s 0
    set f 0
    foreach n $ss_names { if {[regexp -- "(^|\[^A-Za-z0-9_\])[string map {. {\\.}} $n](\[^A-Za-z0-9_\]|$)" $line]} { set s 1 } }
    foreach n $ff_names { if {[regexp -- "(^|\[^A-Za-z0-9_\])[string map {. {\\.}} $n](\[^A-Za-z0-9_\]|$)" $line]} { set f 1 } }
    if {$s && $f} { return both }
    if {$s} { return ss }
    if {$f} { return ff }
    return ""
}

# 074: the association list {file corner} found in a spef_scenario text. A line that mentions exactly one SPEF file and names exactly one corner makes an association;
# 074: a blank-line separated block does the same when the lines alone do not (for example a header line with the scenario and a second line with the file).
# 074: A line or block that mixes both corners or two files is ambiguous and makes no association (the decision then stops if nothing else decides).
proc pt_spef_associations {text files ss_names ff_names} {
    set out {}
    foreach unit [list line block] {
        if {$unit eq "line"} {
            set chunks [split $text "\n"]
        } else {
            set chunks {}
            set cur {}
            foreach l [split $text "\n"] {
                if {[string trim $l] eq ""} { if {[llength $cur]} { lappend chunks [join $cur "\n"]; set cur {} } } else { lappend cur $l }
            }
            if {[llength $cur]} { lappend chunks [join $cur "\n"] }
        }
        foreach ch $chunks {
            set hit {}
            foreach f $files { if {[pt_line_mentions_spef $ch $f]} { lappend hit $f } }
            set c [pt_line_corner $ch $ss_names $ff_names]
            if {[llength $hit] == 1 && ($c eq "ss" || $c eq "ff")} {
                set a [list [lindex $hit 0] $c]
                if {[lsearch -exact $out $a] < 0} { lappend out $a }
            }
        }
    }
    return $out
}

# 074: THE DECISION. Which SPEF file belongs to the corner ("ss" or "ff")? Reads only the text. Errors (with the full text printed in the message) when:
# 074:   the text names no corner for any file; the corner has no file or two different files; one file is claimed by both corners.
# 074: The temperature in a file name is never used. Returns the file name.
proc pt_spef_decide {text files corner ss_names ff_names} {
    set assoc [pt_spef_associations $text $files $ss_names $ff_names]
    set mine {}
    set other {}
    foreach a $assoc {
        lassign $a f c
        if {$c eq $corner} { lappend mine $f } else { lappend other $f }
    }
    set mine [lsort -unique $mine]
    set other [lsort -unique $other]
    set shown "----- content of the spef_scenario file -----\n$text\n----- end -----"
    if {[llength $assoc] == 0} {
        error "PT ERROR: the spef_scenario text does not name the corner ([join $ss_names /] for ss, [join $ff_names /] for ff) next to any of the SPEF files ([join [lmap f $files {file tail $f}] {, }]). Decide by reading it:\n$shown"
    }
    if {[llength $mine] == 0} { error "PT ERROR: the spef_scenario text names no SPEF file for corner $corner. Associations found: $assoc\n$shown" }
    if {[llength $mine] > 1} { error "PT ERROR: the spef_scenario text names more than one SPEF file for corner $corner ([join $mine {, }])\n$shown" }
    set f [lindex $mine 0]
    if {[lsearch -exact $other $f] >= 0} { error "PT ERROR: the SPEF file $f is named for BOTH corners in the spef_scenario text\n$shown" }
    return $f
}

# 074: numbers out of an SDC text: a dict with period (create_clock -period), setup_unc, hold_unc (set_clock_uncertainty -setup/-hold; a value given without -setup/-hold counts for both),
# 074: propagated (1 when set_propagated_clock appears), opcond (list of set_operating_conditions lines), maxtran (list of set_max_transition lines), maxcap (list of set_max_capacitance lines).
# 074: Values are "" when absent. Comment lines are ignored.
proc pt_sdc_values {text} {
    set period ""
    set su ""
    set hu ""
    set prop 0
    set opc {}
    set mt {}
    set mc {}
    foreach raw [split $text "\n"] {
        set l [string trim $raw]
        if {$l eq "" || [string index $l 0] eq "#"} continue
        if {[regexp {^create_clock\M.*-period\s+([0-9.eE+-]+)} $l -> v]} { set period $v }
        if {[regexp {^set_clock_uncertainty\M} $l]} {
            if {[regexp {^set_clock_uncertainty\s+(-\S+\s+)*-setup\s+([0-9.eE+-]+)} $l -> x v2]} { set su $v2 }
            if {[regexp {^set_clock_uncertainty\s+(-\S+\s+)*-hold\s+([0-9.eE+-]+)} $l -> x v2]} { set hu $v2 }
            if {![regexp -- {-setup\M} $l] && ![regexp -- {-hold\M} $l] && [regexp {^set_clock_uncertainty\s+([0-9.eE+-]+)} $l -> v]} { set su $v; set hu $v }
        }
        if {[regexp {^set_propagated_clock\M} $l]} { set prop 1 }
        if {[regexp {^set_operating_conditions\M} $l]} { lappend opc $l }
        if {[regexp {^set_max_transition\M} $l]} { lappend mt $l }
        if {[regexp {^set_max_capacitance\M} $l]} { lappend mc $l }
    }
    return [dict create period $period setup_unc $su hold_unc $hu propagated $prop opcond $opc maxtran $mt maxcap $mc]
}

# 074: compare a value with the expected one: "" when equal (to 1e-9) or when the value is unreadable is NOT accepted: returns a sentence for a mismatch or an unreadable value
proc pt_compare_value {name value expected} {
    if {![string is double -strict $value]} { return "$name could not be read (got '$value'), expected $expected" }
    if {abs($value - $expected) > 1e-9} { return "$name is $value, expected $expected" }
    return ""
}

# 074: operating condition and library names from a report_design / report_analysis text. VERIFY the wording on the server; PrimeTime prints a line like
# 074: "Operating Conditions: tsl18fs120_scl_ss   Library: tsl18fs120_scl_ss". Returns a list of {condition library}; empty when not found.
proc pt_parse_opcond {text} {
    set out {}
    foreach l [split $text "\n"] {
        if {[regexp {Operating Conditions?:\s*(\S+)\s+Library:\s*(\S+)} $l -> c lib]} { lappend out [list $c $lib] }
    }
    return $out
}

# 074 (fix after the first server run): in this PrimeTime (T-2022.03-SP2) read_parasitics and report_annotated_parasitics do NOT print into the session. They print
# 074: "Information: Log for '<command>' will be generated in 'parasitics_command.log'. (PARA-107)": the text is in a FILE of the current directory, APPENDED by both commands.
# 074: size of a file in bytes, 0 when it does not exist
proc pt_file_size0 {path} {
    if {![file exists $path]} { return 0 }
    return [file size $path]
}

# 074: the part of a file written after byte `offset` (the text of the command that ran after the size was taken); "" when the file is missing or nothing was added
proc pt_file_tail {path offset} {
    if {![file exists $path] || [file size $path] <= $offset} { return "" }
    set fp [open $path r]
    fconfigure $fp -translation binary
    seek $fp $offset start
    set t [read $fp]
    close $fp
    return $t
}

# 074: from the LAST "Report : annotated_parasitics" line to the end of the text ("" when there is none)
proc pt_last_annotation_block {text} {
    set last -1
    set i [string first "Report : annotated_parasitics" $text]
    while {$i >= 0} { set last $i; set i [string first "Report : annotated_parasitics" $text [expr {$i + 1}]] }
    if {$last < 0} { return "" }
    return [string range $text $last end]
}

# 074: the error count of a read_parasitics block: the largest N of the lines "N error(s)"; "" when no such line exists
proc pt_parse_para_errors {text} {
    set n ""
    foreach l [split $text "\n"] {
        if {[regexp -nocase {([0-9]+)\s+error\(s\)} $l -> v]} { if {$n eq "" || $v > $n} { set n $v } }
    }
    return $n
}

# 074: the table of "Report : annotated_parasitics -check -internal_nets -boundary_nets" as printed by PrimeTime:
#   Net Type | Total | Lumped | RC pi | RC network | Not Annotated     then the rows "  - Pin to pin nets | 16113 | 0 | 0 | 16113 | 0", "  - Driverless nets ...", "  - Loadless nets ..."
#   for the internal nets and again under "Boundary/port nets", a total row "| 16688 | 0 | 0 | 16295 | 393 |", the line "Annotated nets : N", and numbered lines of the unannotated nets
#   ("1.  csr_sel[2] (driver: <none>)").
# 074: Returns a dict: found (1 when at least one row and the total row were read), rows (list of {section type total lumped rcpi rcnet notann}), total (list of the five numbers of the
# 074: total row), annotated (the "Annotated nets" number or ""), names (list of {index name driver}).
proc pt_parse_annotation_table {text} {
    set rows {}
    set total {}
    set annotated ""
    set names {}
    set section internal
    foreach l [split $text "\n"] {
        if {[regexp -nocase {^\s*boundary} $l]} { set section boundary; continue }
        if {[regexp -nocase {^\s*internal} $l]} { set section internal; continue }
        if {[regexp -nocase {^\s*-\s*(pin\s+to\s+pin|driverless|loadless)\s+nets\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)} $l -> ty t lu pi rc na]} {
            set ty [expr {[string match -nocase "pin*" $ty] ? "p2p" : ([string match -nocase "driver*" $ty] ? "driverless" : "loadless")}]
            lappend rows [list $section $ty $t $lu $pi $rc $na]
            continue
        }
        if {[regexp {^\s*\|?\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|\s*([0-9]+)\s*\|?\s*$} $l -> a b c d e]} { set total [list $a $b $c $d $e]; continue }
        if {[regexp -nocase {^\s*annotated\s+nets\s*:\s*([0-9]+)} $l -> n]} { set annotated $n; continue }
        if {[regexp {^\s*([0-9]+)\.\s+(\S+)\s+\(driver:\s*(.*?)\)\s*$} $l -> idx nm drv]} { lappend names [list $idx $nm $drv] }
    }
    return [dict create found [expr {[llength $rows] > 0 && [llength $total] == 5}] rows $rows total $total annotated $annotated names $names]
}

# 074: policy for the table. errors = the read_parasitics error count ("" when none was printed). Returns {ok lines}; every line is for the log.
# 074: ERROR (ok = 0) when: read_parasitics reported errors; the table was not found (unless allow_unreadable, then a WARNING line); the table is inconsistent (sum of the rows differs from the total
# 074: row); a "Pin to pin nets" row (internal or boundary) has Not Annotated nets above max_pct percent of the pin-to-pin nets (max_pct 0 = any). The unannotated DRIVERLESS and LOADLESS nets
# 074: are INFORMATION: counted per row, they carry no timing arc (no driver or no load); the first 10 names are listed.
proc pt_annotation_policy {parsed errors max_pct allow_unreadable} {
    set out {}
    set ok 1
    if {[string is integer -strict $errors] && $errors > 0} {
        lappend out "read_parasitics reported $errors error(s): the parasitics are not trustworthy"
        set ok 0
    }
    if {![dict get $parsed found]} {
        if {$allow_unreadable} {
            lappend out "WARNING: the annotation table could not be found or read; continuing because PT_ALLOW_UNREADABLE_ANNOTATION is 1"
            return [list $ok $out]
        }
        lappend out "the annotation table of report_annotated_parasitics could not be found or read (no rows or no total row); read parasitics_command.log, then either fix the parser or set PT_ALLOW_UNREADABLE_ANNOTATION"
        return [list 0 $out]
    }
    set rows [dict get $parsed rows]
    set tot [dict get $parsed total]
    # consistency of the table with its own total row
    set st 0
    set sna 0
    foreach r $rows { incr st [lindex $r 2]; incr sna [lindex $r 6] }
    if {$st != [lindex $tot 0] || $sna != [lindex $tot 4]} {
        lappend out "the table is inconsistent: the rows add up to total $st / not annotated $sna, the total row says [lindex $tot 0] / [lindex $tot 4]"
        set ok 0
    }
    # pin-to-pin rows: the nets that carry timing arcs
    set p2p_total 0
    set p2p_ann 0
    set p2p_un 0
    set detail {}
    foreach r $rows {
        lassign $r sec ty t lu pi rc na
        if {$ty eq "p2p"} {
            incr p2p_total $t
            incr p2p_ann [expr {$lu + $pi + $rc}]
            incr p2p_un $na
            lappend detail "$sec $t (annotated [expr {$lu + $pi + $rc}], not annotated $na)"
        }
    }
    if {$p2p_total == 0} {
        lappend out "the table has no pin-to-pin net row with nets"
        set ok 0
    } else {
        set pct [expr {100.0 * $p2p_un / $p2p_total}]
        lappend out "pin-to-pin nets: $p2p_total in total ([join $detail {; }]); $p2p_un not annotated ([format %.3f $pct] percent, limit $max_pct percent)"
        if {$pct > $max_pct + 1e-12} {
            lappend out "ERROR: $p2p_un pin-to-pin nets ([format %.3f $pct] percent) are not annotated; the limit is $max_pct percent (PT_MAX_UNANNOTATED_PCT)"
            set ok 0
        }
    }
    # driverless / loadless: information
    set info {}
    foreach r $rows {
        lassign $r sec ty t lu pi rc na
        if {$ty ne "p2p"} { lappend info "$sec $ty nets: $t in total, $na not annotated" }
    }
    lappend out "information (not an error): [join $info {; }]. A driverless or loadless net has no driver or no load, so it carries no timing arc and its missing parasitics cannot change a path."
    set names [dict get $parsed names]
    lappend out "unannotated nets listed in the report: [llength $names]; the first 10: [join [lmap n [lrange $names 0 9] {format "%s (driver: %s)" [lindex $n 1] [lindex $n 2]}] {, }]"
    set an [dict get $parsed annotated]
    if {[string is integer -strict $an] && $an != ($p2p_ann + 0) && $an != ([lindex $tot 1] + [lindex $tot 2] + [lindex $tot 3])} {
        lappend out "WARNING: 'Annotated nets : $an' differs from the annotated counts of the table ($p2p_ann pin-to-pin, [expr {[lindex $tot 1] + [lindex $tot 2] + [lindex $tot 3]}] in the total row)"
    }
    return [list $ok $out]
}

# 074 (fix 2): parse a check_timing -verbose text. "Information: Checking 'x'." lines are only the NAME of the check being run (they are NOT findings, third server run).
# A finding is a block that starts with a "Warning:" or "Error:" line; the lines after it, up to the next Warning:/Error:/Information: line, hold its list (header words such
# as Endpoints/Ports and dashed lines are skipped, the first token of every other line is a name). Returns a dict: checks (names of the checks that were run),
# findings (list of dicts: level, msg, count (N of "There is/are N ..." or ""), names).
proc pt_parse_check_timing {text} {
    set checks {}
    set findings {}
    set cur ""
    set lines {}
    set flush {
        if {$cur ne ""} { lappend findings $cur }
        set cur ""
    }
    foreach l [split $text "\n"] {
        if {[regexp {^\s*(Warning|Error|Information):\s*(.*)$} $l -> level msg]} {
            eval $flush
            if {$level eq "Information"} {
                if {[regexp {^Checking '([^']*)'} $msg -> cn]} { lappend checks $cn }
                continue
            }
            set cnt ""
            regexp {There (?:is|are) ([0-9]+)} $msg -> cnt
            set cur [dict create level $level msg [string trim $msg] count $cnt names {}]
            continue
        }
        if {$cur eq ""} continue
        set t [string trim $l]
        if {$t eq "" || [regexp {^[-=_ ]+$} $t]} continue
        set tok [lindex [regexp -all -inline {\S+} $t] 0]
        if {[regexp -nocase {^(endpoints?|ports?|pins?|name|names)$} $tok]} continue
        dict lappend cur names $tok
    }
    eval $flush
    return [dict create checks $checks findings $findings]
}

# 074 (fix 2): decide what the findings of check_timing mean. clock_ports: the source port(s) of the clock; known: glob patterns of the endpoints that may be unconstrained.
# Returns a dict: errors (stop), warnings (printed with WARNING), infos (printed as information).
proc pt_check_timing_decide {parsed known clock_ports} {
    set errors {}
    set warnings {}
    set infos {}
    foreach f [dict get $parsed findings] {
        set msg [dict get $f msg]
        set names [dict get $f names]
        set cnt [dict get $f count]
        if {[regexp -nocase {unconstrained\s+endpoint|endpoints?\s+(?:which\s+)?(?:is|are)\s+not\s+constrained|not\s+constrained\s+for} $msg]} {
            if {[llength $names] == 0 || ($cnt ne "" && [llength $names] != $cnt)} {
                lappend errors "check_timing reports unconstrained endpoints ('$msg') but read [llength $names] names for a count of '$cnt' (VERIFY the wording); read the text above"
                continue
            }
            set bad [pt_unexpected_endpoints $names $known]
            if {[llength $bad] > 0} { lappend errors "unconstrained endpoints other than the known constants ($known): $bad" } else { lappend infos "unconstrained endpoints, all in the known list ($known): $names" }
        } elseif {[regexp -nocase {no\s+driving\s+cell} $msg]} {
            set other {}
            foreach n $names { if {[lsearch -exact $clock_ports $n] < 0} { lappend other $n } }
            if {[llength $names] > 0 && [llength $other] == 0} {
                lappend infos "port(s) with no driving cell: $names; these are the clock source port(s) ($clock_ports), expected (the clock input has no driving cell in the SDC)"
            } else {
                lappend warnings "port(s) with no driving cell that are not the clock source ($clock_ports): [expr {[llength $other] ? $other : {names could not be read}}]  ('$msg')"
            }
        } else {
            lappend warnings "check_timing [dict get $f level]: '$msg'[expr {[llength $names] ? " names: $names" : {}}]"
        }
    }
    return [dict create errors $errors warnings $warnings infos $infos]
}

# 074 (fix 2): is the clock of a timing report propagated? Reads the "(propagated)" / "(ideal)" tags of the clock path (the "clock network delay (propagated)" lines).
# status: propagated (at least one propagated tag and NO ideal tag), ideal (any ideal tag), none (no tag at all: cannot be proved). lines: the tagged lines.
proc pt_clock_propagation {text} {
    set np 0
    set ni 0
    set lines {}
    set delays {}
    foreach l [split $text "\n"] {
        if {[regexp {\((propagated|ideal)\)} $l -> tag]} {
            if {$tag eq "propagated"} { incr np } else { incr ni }
            lappend lines [string trim $l]
            if {[regexp {clock network delay \((?:propagated|ideal)\)\s+(-?[0-9.]+)} $l -> v]} { lappend delays [list $tag $v] }
        }
    }
    set status [expr {$ni > 0 ? "ideal" : ($np > 0 ? "propagated" : "none")}]
    return [dict create status $status propagated $np ideal $ni lines $lines delays $delays]
}

# 074 (fix 2): the known messages of read_sdc: UITE-305 (a propagated clock converted to ideal by a later create_clock) and UITE-489 (input delay on the clock port itself ignored).
# Returns a list of information lines (counts of each); other warnings are not touched here.
proc pt_sdc_known_messages {text} {
    set out {}
    set n305 [llength [regexp -all -inline {UITE-305} $text]]
    set n489 [llength [regexp -all -inline {UITE-489} $text]]
    if {$n305} { lappend out "read_sdc printed UITE-305 $n305 time(s): the SDC order resets the clock to IDEAL after its set_propagated_clock, so this script applies set_propagated_clock itself and proves it" }
    if {$n489} { lappend out "read_sdc printed UITE-489 $n489 time(s): an input delay on the clock port itself is ignored by PrimeTime; harmless" }
    return $out
}

# 074: the names that are not covered by the known list (glob patterns, also matched against the last path component)
proc pt_unexpected_endpoints {names known} {
    set out {}
    foreach n $names {
        set ok 0
        foreach k $known { if {[string match $k $n] || [string match $k [lindex [split $n /] end]]} { set ok 1 } }
        if {!$ok} { lappend out $n }
    }
    return $out
}

# 074: violation lines of a report_constraint -all_violators text: lines that end with "(VIOLATED)" (VERIFY the wording). Returns a dict count, wns (the most negative slack or ""), tns.
proc pt_parse_violators {text} {
    set n 0
    set wns ""
    set tns 0.0
    foreach l [split $text "\n"] {
        if {[regexp {(-?[0-9]+\.[0-9]+)\s*\(VIOLATED\)} $l -> s]} {
            incr n
            set tns [expr {$tns + $s}]
            if {$wns eq "" || $s < $wns} { set wns $s }
        }
    }
    return [dict create count $n wns $wns tns $tns]
}

# 074: slack text; "n/a" when not a number
proc pt_fmt_ns {v {fmt %+.4f}} {
    if {![string is double -strict $v]} { return "n/a" }
    return [format $fmt $v]
}

# 074: MET when WNS >= 0, VIOLATED when < 0, UNKNOWN when it cannot be read (never MET on an unreadable number)
proc pt_verdict {wns} {
    if {![string is double -strict $wns]} { return UNKNOWN }
    if {$wns >= 0} { return MET }
    return VIOLATED
}

# 074: "SETUP corner ss: WNS <x> ns, TNS <y> ns, violating endpoints <n>"
proc pt_summary_line {kind corner wns tns n} {
    return "[string toupper $kind] corner $corner: WNS [pt_fmt_ns $wns] ns, TNS [pt_fmt_ns $tns] ns, violating endpoints [expr {[string is integer -strict $n] ? $n : {n/a}}]"
}

# 074: the comparison with the ICC2 figure: "<KIND> WNS: PrimeTime x ns, ICC2 y ns, difference d ns (PrimeTime minus ICC2)" or UNKNOWN when one of them is not a number
proc pt_compare_line {kind pt icc2} {
    if {![string is double -strict $pt] || ![string is double -strict $icc2]} {
        return "[string toupper $kind] WNS: PrimeTime [pt_fmt_ns $pt] ns, ICC2 [pt_fmt_ns $icc2] ns, difference UNKNOWN"
    }
    return "[string toupper $kind] WNS: PrimeTime [pt_fmt_ns $pt] ns, ICC2 [pt_fmt_ns $icc2] ns, difference [pt_fmt_ns [expr {$pt - $icc2}]] ns (PrimeTime minus ICC2)"
}

# 074: clock period / uncertainty checks against the expected values for one script. Returns the list of problems (empty = ok).
# 074: kind = setup (checks the setup uncertainty) or hold (checks the hold uncertainty); the period is always checked.
proc pt_check_constraints {kind period setup_unc hold_unc exp_period exp_setup exp_hold} {
    set p {}
    set m [pt_compare_value "clock period" $period $exp_period]
    if {$m ne ""} { lappend p $m }
    if {$kind eq "setup"} {
        set m [pt_compare_value "setup uncertainty" $setup_unc $exp_setup]
    } else {
        set m [pt_compare_value "hold uncertainty" $hold_unc $exp_hold]
    }
    if {$m ne ""} { lappend p $m }
    return $p
}
# 074: the limits of set_max_transition / set_max_capacitance lines (from pt_sdc_values): a list of dicts {kind value clock_path line}; clock_path is 1 when the line has -clock_path.
proc pt_limit_entries {maxtran maxcap} {
    set out {}
    foreach {kind lines} [list max_transition $maxtran max_capacitance $maxcap] {
        foreach l $lines {
            set v ""
            regexp {^set_max_(?:transition|capacitance)\s+(?:-\S+\s+)*([0-9.eE+-]+)} $l -> v
            lappend out [dict create kind $kind value $v clock_path [regexp -- {-clock_path\M} $l] line $l]
        }
    }
    return $out
}

# 074: text lines for the log: every limit PrimeTime reads, which one applies to the clock path, and whether the design-wide values equal the expected ones.
proc pt_limit_report {entries exp_tran exp_cap} {
    set out {}
    set dw_tran {}
    set dw_cap {}
    set clk_tran {}
    foreach e $entries {
        lappend out "limit read: [dict get $e line]"
        if {[dict get $e clock_path]} {
            lappend clk_tran [dict get $e value]
            lappend out "  -> a CLOCK-PATH limit of [dict get $e value] ([dict get $e kind]) is part of the constraints that are signed off"
        } elseif {[dict get $e kind] eq "max_transition"} { lappend dw_tran [dict get $e value] } else { lappend dw_cap [dict get $e value] }
    }
    if {[llength $clk_tran] == 0} { lappend out "no -clock_path limit in the SDC: the design-wide max transition applies to the clock path too" }
    if {[llength $dw_tran] == 0 || [lsearch -real -exact $dw_tran $exp_tran] < 0} { lappend out "WARNING: the design-wide max_transition is [expr {[llength $dw_tran] ? $dw_tran : {absent}}], the legacy value is $exp_tran" }
    if {[llength $dw_cap] == 0 || [lsearch -real -exact $dw_cap $exp_cap] < 0} { lappend out "WARNING: the design-wide max_capacitance is [expr {[llength $dw_cap] ? $dw_cap : {absent}}], the legacy value is $exp_cap" }
    return $out
}
# 074: the whole-log check used after the session (check_annotation.tcl): errors from the whole text, the table from the LAST report block (else from the whole text); the policy is
# 074: the in-session one (pt_annotation_policy), with allow_unreadable ALWAYS 0: a post-run check cannot be waived. Returns {ok lines}.
proc pt_check_log_text {text max_pct} {
    set errors [pt_parse_para_errors $text]
    set blk [pt_last_annotation_block $text]
    set parsed [pt_parse_annotation_table $blk]
    if {![dict get $parsed found]} { set parsed [pt_parse_annotation_table $text] }
    set res [pt_annotation_policy $parsed $errors $max_pct 0]
    return [list [lindex $res 0] [linsert [lindex $res 1] 0 "read_parasitics errors: [expr {$errors eq {} ? {none printed} : $errors}]"]]
}

# 074: 1 when the user declared the post-run annotation check (the value of the shell variable is exactly 1)
proc pt_declared_after {value} {
    return [expr {$value eq "1"}]
}

# 074: the caveat lines of the SUMMARY block: empty when the annotation was checked in-session
proc pt_summary_caveat {unchecked} {
    if {!$unchecked} { return {} }
    return [list "ANNOTATION NOT CHECKED IN-SESSION: run check_annotation after the session (tclsh pnr_v2/pt/check_annotation.tcl parasitics_command.log); this result is valid only if that check prints ANNOTATION CHECK PASSED"]
}
# ---- END PURE TCL 074 ----

# ------------------------------------------------------------------------------
# 2. Procs that use PrimeTime commands (not tested locally; every uncertain command is marked VERIFY)
# ------------------------------------------------------------------------------

# 074: run the body; on any error print it and EXIT with status 1, so that nothing waits at a pt_shell prompt
proc pt_main {body} {
    if {[catch {uplevel 1 $body} err]} {
        puts "\nPT ERROR (script stopped, no result): $err"
        exit 1
    }
}

# 074: banner with what is actually used
proc pt_banner {kind corner lib db spef sdc netlist} {
    puts "\n=============================================================================="
    puts " PrimeTime [string toupper $kind] sign-off, corner $corner"
    puts "   library : $lib   ($db)"
    puts "   netlist : $netlist"
    puts "   SPEF    : $spef"
    puts "   SDC     : $sdc"
    puts "   date    : [clock format [clock seconds]]"
    puts "   SI      : [expr {$::PT_SI_ENABLE ? {ON} : {OFF (default)}}]"
    puts "==============================================================================\n"
}

# 074: decide the SPEF of a corner from the spef_scenario text (or the override); prints what it did
proc pt_choose_spef {corner} {
    global PT_SPEF_SCENARIO_FILE PT_SPEF_FILES PT_CORNER PT_SPEF_OVERRIDE
    foreach f $PT_SPEF_FILES { pt_need_file $f "SPEF file" }
    if {$PT_SPEF_OVERRIDE($corner) ne ""} {
        puts ">>> 074 SPEF for corner $corner: OVERRIDE by PT_SPEF_OVERRIDE($corner) = $PT_SPEF_OVERRIDE($corner) (the spef_scenario file is not used)"
        return [pt_need_file $PT_SPEF_OVERRIDE($corner) "SPEF override"]
    }
    pt_need_file $PT_SPEF_SCENARIO_FILE "spef_scenario file"
    set fp [open $PT_SPEF_SCENARIO_FILE r]
    set text [read $fp]
    close $fp
    puts ">>> 074 content of $PT_SPEF_SCENARIO_FILE:\n$text\n>>> 074 end of content"
    set f [pt_spef_decide $text $PT_SPEF_FILES $corner $PT_CORNER(ss,names) $PT_CORNER(ff,names)]
    puts ">>> 074 SPEF for corner $corner decided from the text: $f"
    return $f
}

# 074: set the libraries, read the netlist, link, stop on errors; prints the numbers
proc pt_link {corner} {
    global PT_CORNER PT_NETLIST PT_DESIGN
    pt_need_file $PT_CORNER($corner,db) "library db of corner $corner"
    pt_need_file $PT_NETLIST "netlist"
    set_app_var search_path [list [file dirname $PT_CORNER($corner,db)] $::PT_OUT_DIR]
    set_app_var link_path [list * [file tail $PT_CORNER($corner,db)]]   ;# VERIFY: link_path with the db file name found through search_path (target_library is not used by PrimeTime)
    puts ">>> 074 search_path: $::search_path"
    puts ">>> 074 link_path: $::link_path"
    redirect -variable pt_rd_txt { read_verilog $PT_NETLIST }
    puts $pt_rd_txt
    redirect -variable pt_lk_txt { set pt_lk_rc [link_design $PT_DESIGN] }   ;# VERIFY: link_design <design> returns 1 on success
    puts $pt_lk_txt
    if {[regexp -nocase {unable to resolve reference|unresolved} $pt_lk_txt] || [regexp {(^|\n)Error:} $pt_lk_txt] || [regexp {(^|\n)Error:} $pt_rd_txt]} {
        error "PT ERROR: errors or unresolved references while reading/linking the netlist (text above)"
    }
    if {![info exists pt_lk_rc] || $pt_lk_rc == 0} { error "PT ERROR: link_design $PT_DESIGN did not succeed (return value '[expr {[info exists pt_lk_rc] ? $pt_lk_rc : {none}}]')" }
    set leaf [sizeof_collection [get_cells -hierarchical -quiet -filter "is_hierarchical == false"]]   ;# VERIFY the attribute is_hierarchical
    set hier [sizeof_collection [get_cells -hierarchical -quiet -filter "is_hierarchical == true"]]
    set missing [sizeof_collection [get_lib_cells -quiet -filter "is_black_box == true"]]   ;# VERIFY: library cells missing show as black boxes; harmless if the attribute does not exist (printed as 0)
    puts ">>> 074 linked $PT_DESIGN: $leaf leaf cells, $hier hierarchical cells, library cells missing (black boxes) $missing"
    if {$leaf <= 0} { error "PT ERROR: no leaf cell after link_design" }
    if {$missing > 0} { error "PT ERROR: $missing library cells are missing after link_design" }
}

# 074: read the SPEF and apply the annotation policy. PrimeTime T-2022.03-SP2 sends the text of read_parasitics and report_annotated_parasitics to the file parasitics_command.log
# (PARA-107), WRITTEN BUFFERED (0 bytes during the session in the second server run). So the variable parasitics_log_file is set to an empty string first (VERIFY: then the text
# comes to the session); the table is taken from the session text, else from the part of the log file added by the command, else from the last report block of the file.
# If no table is found in-session: STOP, unless PT_ANNOTATION_CHECKED_AFTER=1 is declared (then the sign-off continues with the caveat in the SUMMARY block).
proc pt_read_spef {corner spef} {
    global PT_MAX_UNANNOTATED_PCT PT_ALLOW_UNREADABLE_ANNOTATION PT_SI_ENABLE PT_PARA_LOG PT_ANNOTATION_ENV PT_ANNOTATION_UNCHECKED env
    pt_need_file $spef "SPEF file"
    set logf [file join [pwd] $PT_PARA_LOG]
    # the variable that controls the log file
    if {[catch {redirect -variable pt_pv_txt { printvar parasitics_log_file }} err]} { set pt_pv_txt "printvar failed: $err" }   ;# VERIFY printvar parasitics_log_file
    puts ">>> 074 parasitics_log_file before: [string trim $pt_pv_txt]"
    if {[catch {set_app_var parasitics_log_file ""} err]} {   ;# VERIFY: an empty string sends the text of the two commands to the session
        puts ">>> 074 set_app_var parasitics_log_file \"\" failed: $err (the text will be looked for in the log file)"
    } else {
        if {[catch {redirect -variable pt_pv_txt { printvar parasitics_log_file }} err]} { set pt_pv_txt "printvar failed: $err" }
        puts ">>> 074 parasitics_log_file after: [string trim $pt_pv_txt]"
    }
    puts ">>> 074 reading parasitics $spef"
    set off0 [pt_file_size0 $logf]
    redirect -variable pt_rp_txt {
        if {$PT_SI_ENABLE} {
            read_parasitics -keep_capacitive_coupling -format spef $spef   ;# VERIFY -keep_capacitive_coupling / -format spef (needed only for crosstalk)
        } else {
            read_parasitics -format spef $spef   ;# VERIFY -format spef
        }
    }
    puts $pt_rp_txt
    set rp_chunk [pt_file_tail $logf $off0]
    if {$rp_chunk ne ""} { puts ">>> 074 read_parasitics text from $PT_PARA_LOG ([string length $rp_chunk] bytes):\n$rp_chunk" }
    set errors [pt_parse_para_errors "$pt_rp_txt\n$rp_chunk"]
    set off1 [pt_file_size0 $logf]
    redirect -variable pt_an_txt { report_annotated_parasitics -check -internal_nets -boundary_nets }   ;# VERIFY: the options are the ones the report header of this PrimeTime printed
    puts $pt_an_txt
    set an_chunk [pt_file_tail $logf $off1]
    if {$an_chunk ne ""} { puts ">>> 074 report_annotated_parasitics text from $PT_PARA_LOG ([string length $an_chunk] bytes):\n$an_chunk" }
    puts ">>> 074 session text: read_parasitics [string length $pt_rp_txt] bytes, report_annotated_parasitics [string length $pt_an_txt] bytes; file $logf: [pt_file_size0 $logf] bytes"
    set parsed ""
    foreach {src txt} [list "the session text of report_annotated_parasitics" $pt_an_txt "the part of $PT_PARA_LOG written by report_annotated_parasitics" $an_chunk "the last report block of $PT_PARA_LOG" [pt_last_annotation_block [pt_file_tail $logf 0]]] {
        set p [pt_parse_annotation_table [pt_last_annotation_block $txt]]
        if {![dict get $p found]} { set p [pt_parse_annotation_table $txt] }
        if {[dict get $p found]} { set parsed $p; puts ">>> 074 annotation table read from $src"; break }
    }
    puts ">>> 074 ANNOTATION: read_parasitics errors '[expr {$errors eq {} ? {none printed} : $errors}]'"
    if {$parsed eq ""} {
        # no table in the session
        set declared [pt_declared_after [expr {[info exists env($PT_ANNOTATION_ENV)] ? $env($PT_ANNOTATION_ENV) : {}}]]
        set why "the annotation table is NOT in the session text: the log file $PT_PARA_LOG is written only at the end of the session (it was [pt_file_size0 $logf] bytes now), so the check cannot be done in-session."
        if {[string is integer -strict $errors] && $errors > 0} { error "PT ERROR: parasitics annotation: read_parasitics reported $errors error(s). $why" }
        if {$declared} {
            set PT_ANNOTATION_UNCHECKED 1
            puts ">>> 074 ANNOTATION NOT CHECKED IN-SESSION: run check_annotation after the session. $why The user declared the post-run check with $PT_ANNOTATION_ENV=1; the sign-off continues and its SUMMARY block carries the caveat."
            puts ">>> 074 AFTER the session: tclsh <repo>/pnr_v2/pt/check_annotation.tcl parasitics_command.log   (must print ANNOTATION CHECK PASSED)"
            return
        }
        if {$PT_ALLOW_UNREADABLE_ANNOTATION} {
            set PT_ANNOTATION_UNCHECKED 1
            puts ">>> 074 WARNING: $why Continuing because PT_ALLOW_UNREADABLE_ANNOTATION is 1; the SUMMARY block carries the caveat."
            return
        }
        error "PT ERROR: parasitics annotation: $why The check stays MANDATORY. Options: (a) verify with printvar that parasitics_log_file is empty and read the session text above; (b) the two-step path: setenv $PT_ANNOTATION_ENV 1, run this script again, and AFTER the session run: tclsh pnr_v2/pt/check_annotation.tcl parasitics_command.log (it prints ANNOTATION CHECK PASSED or FAILED; the sign-off counts only if it passed)."
    }
    lassign [pt_annotation_policy $parsed $errors $PT_MAX_UNANNOTATED_PCT $PT_ALLOW_UNREADABLE_ANNOTATION] ok lines
    foreach l $lines { puts ">>> 074 ANNOTATION: $l" }
    if {!$ok} { error "PT ERROR: parasitics annotation: [join $lines { | }]" }
}

# 074: read the per-scenario SDC, then check what the design says against the expected legacy values; returns the sdc values dict
proc pt_read_sdc_and_check {kind corner} {
    global PT_CORNER PT_CLOCK PT_EXPECT_PERIOD PT_EXPECT_SETUP_UNC PT_EXPECT_HOLD_UNC PT_EXPECT_MAX_TRANSITION PT_EXPECT_MAX_CAP
    set sdc $PT_CORNER($corner,sdc)
    pt_need_file $sdc "SDC file"
    set fp [open $sdc r]
    set sdctext [read $fp]
    close $fp
    set v [pt_sdc_values $sdctext]
    redirect -variable pt_sdc_txt { read_sdc $sdc }
    puts $pt_sdc_txt
    if {[regexp {(^|\n)Error:} $pt_sdc_txt]} { error "PT ERROR: errors while reading $sdc (text above)" }
    puts ">>> 074 SDC text values: period [dict get $v period], setup uncertainty [dict get $v setup_unc], hold uncertainty [dict get $v hold_unc]"
    puts ">>> 074 SDC set_operating_conditions lines: [expr {[llength [dict get $v opcond]] ? [dict get $v opcond] : {none}}]"
    # read back from the design (VERIFY the attribute names period / setup_uncertainty / hold_uncertainty of a clock)
    set clk [get_clocks -quiet $PT_CLOCK]
    if {[sizeof_collection $clk] != 1} { error "PT ERROR: clock $PT_CLOCK not found in the design after read_sdc" }
    set dp ""
    set ds ""
    set dh ""
    catch {set dp [get_attribute $clk period]}
    catch {set ds [get_attribute $clk setup_uncertainty]}
    catch {set dh [get_attribute $clk hold_uncertainty]}
    puts ">>> 074 DESIGN values (get_attribute of clock $PT_CLOCK): period '$dp', setup_uncertainty '$ds', hold_uncertainty '$dh'"
    # the design value wins when it is a number; otherwise the SDC text value is used and the line says so
    set period [expr {[string is double -strict $dp] ? $dp : [dict get $v period]}]
    set su [expr {[string is double -strict $ds] ? $ds : [dict get $v setup_unc]}]
    set hu [expr {[string is double -strict $dh] ? $dh : [dict get $v hold_unc]}]
    if {![string is double -strict $dp] || ![string is double -strict $ds] || ![string is double -strict $dh]} {
        puts ">>> 074 NOTE: a design attribute could not be read; the value of the SDC text is used for it (VERIFY the attribute names)"
    }
    puts ">>> 074 clock $PT_CLOCK: period $period ns, setup uncertainty $su ns, hold uncertainty $hu ns (expected $PT_EXPECT_PERIOD / $PT_EXPECT_SETUP_UNC / $PT_EXPECT_HOLD_UNC from constraints/legacy/unpu_top_legacy.sdc)"
    set problems [pt_check_constraints $kind $period $su $hu $PT_EXPECT_PERIOD $PT_EXPECT_SETUP_UNC $PT_EXPECT_HOLD_UNC]
    # the other uncertainty is printed and checked too, but only warns when it differs (it belongs to the other script)
    set other [expr {$kind eq "setup" ? [pt_compare_value "hold uncertainty" $hu $PT_EXPECT_HOLD_UNC] : [pt_compare_value "setup uncertainty" $su $PT_EXPECT_SETUP_UNC]}]
    if {$other ne ""} { puts ">>> 074 NOTE (not an error for this script): $other" }
    if {[llength $problems]} { error "PT ERROR: the constraints read from $sdc differ from the legacy constraints: [join $problems {; }]" }
    # propagated clock (third server run: UITE-305 converts the propagated clock to ideal, so the text of the SDC is NOT trusted and no attribute is read):
    # the clocks are ALWAYS made propagated here, and pt_checks_and_clock proves it from a timing report.
    foreach l [pt_sdc_known_messages $pt_sdc_txt] { puts ">>> 074 $l" }
    puts ">>> 074 (the SDC text contains set_propagated_clock: [dict get $v propagated]; this is not used as evidence)"
    set_propagated_clock [all_clocks]
    puts ">>> 074 APPLIED: set_propagated_clock \[all_clocks\] -- the CTS tree is real. This is the only change PrimeTime makes to what ICC2 wrote."
    return $v
}

# 074: operating condition read back from the design must be the library of the corner
proc pt_check_opcond {corner} {
    global PT_CORNER
    redirect -variable pt_rd_txt { report_design }   ;# VERIFY report_design prints the operating conditions
    puts $pt_rd_txt
    set oc [pt_parse_opcond $pt_rd_txt]
    puts ">>> 074 operating conditions read from report_design: $oc (expected library $PT_CORNER($corner,lib))"
    if {[llength $oc] == 0} {
        puts ">>> 074 NOTE: report_design printed no 'Operating Conditions: ... Library: ...' line (VERIFY the wording). Only the library $PT_CORNER($corner,lib) is linked, so its own operating condition is the one in use."
        return
    }
    foreach e $oc { if {[lindex $e 1] ne $PT_CORNER($corner,lib)} { error "PT ERROR: operating condition [lindex $e 0] of library [lindex $e 1] is in use, expected library $PT_CORNER($corner,lib)" } }
}

# 074: signal integrity switch with licence check
proc pt_si_setup {} {
    global PT_SI_ENABLE
    if {!$PT_SI_ENABLE} { puts ">>> 074 SI/crosstalk analysis OFF (PT_SI_ENABLE 0): ICC2 had it ON, so PrimeTime is expected to be the same or LESS pessimistic than ICC2 (README)"; return }
    if {[catch {get_license PrimeTime-SI} err]} { error "PT ERROR: PT_SI_ENABLE is 1 but the PrimeTime-SI licence could not be acquired: $err" }   ;# VERIFY get_license PrimeTime-SI
    set_app_var si_enable_analysis true
    puts ">>> 074 SI/crosstalk analysis ON (licence acquired)"
}

# 074: update_timing, check_timing, design and clock reports (shared by both scripts)
proc pt_checks_and_clock {kind corner} {
    global PT_RPT_DIR PT_KNOWN_UNCONSTRAINED PT_CLOCK
    update_timing -full
    redirect -variable pt_ct_txt { check_timing -verbose }   ;# VERIFY check_timing -verbose
    puts $pt_ct_txt
    # the clock source port(s): from the clock, else the clock name (VERIFY the attribute sources)
    set cports {}
    catch {foreach_in_collection s [get_attribute [get_clocks $PT_CLOCK] sources] { lappend cports [get_object_name $s] }}
    if {[llength $cports] == 0} { set cports [list $PT_CLOCK]; puts ">>> 074 NOTE: the clock source port could not be read from the clock; the clock name $PT_CLOCK is used as the port name" }
    set parsed [pt_parse_check_timing $pt_ct_txt]
    puts ">>> 074 check_timing: checks run: [dict get $parsed checks]; findings (Warning/Error blocks): [llength [dict get $parsed findings]]"
    set dec [pt_check_timing_decide $parsed $PT_KNOWN_UNCONSTRAINED $cports]
    foreach m [dict get $dec infos] { puts ">>> 074 check_timing information: $m" }
    foreach m [dict get $dec warnings] { puts ">>> 074 WARNING check_timing: $m" }
    foreach m [dict get $dec errors] { puts ">>> 074 ERROR check_timing: $m" }
    if {[llength [dict get $dec errors]]} { error "PT ERROR: check_timing: [join [dict get $dec errors] { | }]" }
    # PROOF that the clock is propagated (the setup script reads max paths, the hold script min paths)
    set dt [expr {$kind eq "hold" ? "min" : "max"}]
    set prop_txt ""
    foreach pt {full_clock_expanded full} {
        if {[catch {redirect -variable pt_prop_one { report_timing -delay_type $dt -path_type $pt -max_paths 1 }} err]} { error "PT ERROR: clock propagation could not be proved: report_timing -delay_type $dt -path_type $pt failed: $err" }
        append prop_txt "\n$pt_prop_one"
        if {$pt eq "full_clock_expanded"} { puts ">>> 074 clock path of the worst $dt path (full_clock_expanded), first lines:"; foreach l [lrange [split $pt_prop_one "\n"] 0 29] { puts "      $l" } }
    }
    set pr [pt_clock_propagation $prop_txt]
    foreach l [dict get $pr lines] { puts ">>> 074 clock tag: $l" }
    puts ">>> 074 clock network delay values ((tag value) per path end): [dict get $pr delays]"
    if {[dict get $pr status] ne "propagated"} { error "PT ERROR: the clock is not proved propagated: status [dict get $pr status] ([dict get $pr ideal] ideal tag(s), [dict get $pr propagated] propagated tag(s)) in the worst $dt timing path; read the lines above" }
    puts ">>> 074 PROVED: the clock is propagated ([dict get $pr propagated] '(propagated)' tag(s), 0 '(ideal)' tag(s) in the worst $dt path)"
    redirect -tee -file ${PT_RPT_DIR}/pt_${kind}_${corner}_design.rpt { report_design }
    redirect -tee -file ${PT_RPT_DIR}/pt_${kind}_${corner}_clock.rpt {
        report_clock
        catch {report_clock -skew}   ;# VERIFY report_clock -skew
        catch {report_clock_timing -type latency -clock [get_clocks $PT_CLOCK]}   ;# VERIFY report_clock_timing -type latency
        catch {report_clock_timing -type skew -clock [get_clocks $PT_CLOCK]}   ;# VERIFY report_clock_timing -type skew
    }
    puts ">>> 074 CTS values to compare with (ICC2 after CTS): clock latency about 0.59 ns, global skew about 0.31 ns (handoff 18.32)"
}

# 074: violated endpoints of one delay type: a list of dicts {endpoint startpoint slack}, worst first, at most `limit`; the total count and TNS over ALL violators are returned too.
# 074: Returns {wns tns num details}. get_timing_paths without -nworst gives the worst path per endpoint. VERIFY the options -slack_lesser_than / -max_paths and the attributes slack, endpoint, startpoint.
proc pt_violators {delay_type limit} {
    set wns ""
    set tns ""
    set num ""
    set details {}
    if {[catch {
        set p [get_timing_paths -delay_type $delay_type -max_paths 1]
        if {[sizeof_collection $p] > 0} { set wns [get_attribute $p slack] }
    } err]} { puts ">>> 074 WNS ($delay_type) is UNKNOWN: $err" }
    if {[catch {
        set tns 0.0
        set num 0
        set all [get_timing_paths -delay_type $delay_type -slack_lesser_than 0.0 -max_paths 100000]
        foreach_in_collection q $all {
            set s [get_attribute $q slack]
            set tns [expr {$tns + $s}]
            incr num
            if {$num <= $limit} {
                set ep ""
                set sp ""
                catch {set ep [get_object_name [get_attribute $q endpoint]]}
                catch {set sp [get_object_name [get_attribute $q startpoint]]}
                lappend details [dict create endpoint $ep startpoint $sp slack $s]
            }
        }
    } err]} {
        puts ">>> 074 TNS and violating-endpoint count ($delay_type) are UNKNOWN: $err"
        set tns ""
        set num ""
    }
    return [list $wns $tns $num $details]
}

# 074: the summary block and the comparison with ICC2, printed at the end of each script
proc pt_print_summary {kind corner wns tns num icc2_wns} {
    set v [pt_verdict $wns]
    puts "\n=============================================================================="
    puts " SUMMARY"
    puts "   [pt_summary_line $kind $corner $wns $tns $num]"
    puts "   [string toupper $kind]: $v[expr {$v eq {UNKNOWN} ? { (a number could not be read, see the log above)} : {}}]"
    puts "   [pt_compare_line $kind $wns $icc2_wns]"
    global PT_ANNOTATION_UNCHECKED
    foreach cav [pt_summary_caveat [expr {[info exists PT_ANNOTATION_UNCHECKED] && $PT_ANNOTATION_UNCHECKED}]] { puts "   CAVEAT: $cav" }
    puts "=============================================================================="
    return $v
}
