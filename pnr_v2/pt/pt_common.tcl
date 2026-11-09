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

# Unannotated nets: percent of all nets that may be without parasitics. 0.0 = any unannotated net is an error (task 074). After the printed list has been read and explained
# (for example nets that are constants or have no loads) the user may raise it here with the reason written in the line.
set PT_MAX_UNANNOTATED_PCT 0.0
# 0 = a report_annotated_parasitics text that cannot be parsed is an error. 1 = continue, print a warning (use only after reading the text in the log)
set PT_ALLOW_UNREADABLE_ANNOTATION 0

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

# 074: report_annotated_parasitics text -> dict total annotated unannotated, from the lines of the net summary (VERIFY the wording on the server; the patterns accept
# 074: "Total number of nets = N", "Number of nets: N", "Nets with (complete) parasitics annotated: N", "Fully annotated nets N", "Unannotated nets: N", "N nets (are) not annotated").
# 074: A number that is absent is "". The policy is applied by pt_annotation_verdict.
proc pt_parse_annotation {text} {
    set total ""
    set ann ""
    set unann ""
    foreach l [split $text "\n"] {
        if {[regexp -nocase {total\s+(number\s+of\s+)?nets\s*[:=]?\s*([0-9][0-9,]*)} $l -> x n]} { set total [string map {, {}} $n] }
        if {[regexp -nocase {^\s*number\s+of\s+nets\s*[:=]\s*([0-9][0-9,]*)} $l -> n] && $total eq ""} { set total [string map {, {}} $n] }
        if {[regexp -nocase {(fully\s+annotated|annotated)\s+nets?\s*[:=]?\s*([0-9][0-9,]*)} $l -> x n] && ![regexp -nocase {un-?annotated} $l]} { set ann [string map {, {}} $n] }
        if {[regexp -nocase {nets\s+with\s+(complete\s+)?parasitics\s+annotated\s*[:=]?\s*([0-9][0-9,]*)} $l -> x n]} { set ann [string map {, {}} $n] }
        if {[regexp -nocase {un-?annotated\s+nets?\s*[:=]?\s*([0-9][0-9,]*)} $l -> n]} { set unann [string map {, {}} $n] }
        if {[regexp -nocase {([0-9][0-9,]*)\s+nets?\s+(are\s+)?(not|un)\s*-?\s*annotated} $l -> n]} { set unann [string map {, {}} $n] }
    }
    if {$unann eq "" && $total ne "" && $ann ne ""} { set unann [expr {$total - $ann}] }
    if {$total eq "" && $ann ne "" && $unann ne ""} { set total [expr {$ann + $unann}] }
    return [dict create total $total annotated $ann unannotated $unann]
}

# 074: policy for the annotation: returns {ok message}. Unreadable numbers are an error unless allow_unreadable (then a warning). Percent unannotated must not exceed max_pct.
proc pt_annotation_verdict {info max_pct allow_unreadable} {
    set total [dict get $info total]
    set un [dict get $info unannotated]
    if {![string is integer -strict $total] || ![string is integer -strict $un] || $total <= 0} {
        if {$allow_unreadable} { return [list 1 "WARNING: the annotation summary could not be read (total '$total', unannotated '$un'); continuing because PT_ALLOW_UNREADABLE_ANNOTATION is 1"] }
        return [list 0 "the annotation summary could not be read (total '$total', unannotated '$un'); read the text above, then either fix the parser or set PT_ALLOW_UNREADABLE_ANNOTATION"]
    }
    set pct [expr {100.0 * $un / $total}]
    if {$pct > $max_pct + 1e-12} { return [list 0 "$un of $total nets ([format %.3f $pct] percent) are not annotated; the limit is $max_pct percent (PT_MAX_UNANNOTATED_PCT)"] }
    return [list 1 "$un of $total nets ([format %.3f $pct] percent) are not annotated (limit $max_pct percent)"]
}

# 074: endpoints named in a check_timing text under an "unconstrained endpoints" heading (VERIFY the wording): the names are the tokens of the lines after a line that
# 074: mentions "unconstrained"/"not constrained" and "endpoint", up to the next blank line. Returns {found_heading names}.
proc pt_parse_unconstrained {text} {
    set head 0
    set names {}
    set in 0
    foreach l [split $text "\n"] {
        if {[regexp -nocase {(unconstrained|not\s+constrained).*endpoint|endpoint.*(unconstrained|not\s+constrained)} $l]} { set head 1; set in 1; continue }
        if {$in} {
            if {[string trim $l] eq ""} { set in 0; continue }
            foreach tok [regexp -all -inline {\S+} $l] {
                if {[regexp {^(Warning|Information|Error|-+|=+)} $tok]} { set in 0; break }
                if {[regexp {^[A-Za-z_][A-Za-z0-9_./\[\]$-]*$} $tok]} { lappend names $tok }
            }
        }
    }
    return [list $head [lsort -unique $names]]
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

# 074: read the SPEF and apply the annotation policy
proc pt_read_spef {corner spef} {
    global PT_MAX_UNANNOTATED_PCT PT_ALLOW_UNREADABLE_ANNOTATION PT_SI_ENABLE
    pt_need_file $spef "SPEF file"
    puts ">>> 074 reading parasitics $spef"
    if {$PT_SI_ENABLE} {
        read_parasitics -keep_capacitive_coupling -format spef $spef   ;# VERIFY -keep_capacitive_coupling / -format spef (needed only for crosstalk)
    } else {
        read_parasitics -format spef $spef   ;# VERIFY -format spef
    }
    redirect -variable pt_an_txt { report_annotated_parasitics -check }   ;# VERIFY report_annotated_parasitics -check
    puts $pt_an_txt
    set info [pt_parse_annotation $pt_an_txt]
    lassign [pt_annotation_verdict $info $PT_MAX_UNANNOTATED_PCT $PT_ALLOW_UNREADABLE_ANNOTATION] ok msg
    puts ">>> 074 ANNOTATION: total [dict get $info total], annotated [dict get $info annotated], unannotated [dict get $info unannotated]: $msg"
    if {!$ok} {
        catch {report_annotated_parasitics -list_not_annotated -max_nets 30}   ;# VERIFY the options
        error "PT ERROR: parasitics annotation: $msg"
    }
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
    puts ">>> 074 SDC text values: period [dict get $v period], setup uncertainty [dict get $v setup_unc], hold uncertainty [dict get $v hold_unc], set_propagated_clock in the SDC: [dict get $v propagated]"
    puts ">>> 074 SDC set_operating_conditions lines: [expr {[llength [dict get $v opcond]] ? [dict get $v opcond] : {none}}]"
    # read back from the design (VERIFY the attribute names period / setup_uncertainty / hold_uncertainty / is_propagated of a clock)
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
    # propagated clock
    set isprop ""
    catch {set isprop [get_attribute $clk is_propagated]}   ;# VERIFY the clock attribute is_propagated
    if {[dict get $v propagated] || $isprop eq "true" || $isprop == 1} {
        puts ">>> 074 clocks are propagated: the SDC already carries set_propagated_clock (design attribute is_propagated '$isprop')"
    } else {
        set_propagated_clock [all_clocks]
        puts ">>> 074 clocks were NOT propagated in the SDC: set_propagated_clock [all_clocks] applied for the analysis (the CTS tree is real). This is the only change PrimeTime makes to what ICC2 wrote."
    }
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
    lassign [pt_parse_unconstrained $pt_ct_txt] head names
    set bad [pt_unexpected_endpoints $names $PT_KNOWN_UNCONSTRAINED]
    puts ">>> 074 check_timing: unconstrained-endpoint heading found: $head; endpoints named: $names; not in the known list ($PT_KNOWN_UNCONSTRAINED): $bad"
    if {$head && [llength $bad] > 0} { error "PT ERROR: unconstrained endpoints other than the known constants: $bad" }
    if {$head && [llength $names] == 0} { error "PT ERROR: check_timing reports unconstrained endpoints but their names could not be read (VERIFY the wording); read the text above" }
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
    puts "=============================================================================="
    return $v
}
