# =============================================================================
# stage_numbers.tcl -- the stage profile's numbers for the DC script (task 055). PLAIN Tcl, no tool command.
#
# Why this file exists
#   constraints/pm_dc_script_unpu.tcl prints the profile (period, setup and hold uncertainty) in the first
#   line of every report file. It used to expect the variables CLK_PERIOD, CLK_UNCERT_SETUP and CLK_UNCERT_HOLD
#   to be visible after read_sdc. They are not: dc_shell evaluates the SDC in its own scope (first real run,
#   all three profiles), so the guard fired and nothing was written with a header.
#
# What it does
#   unpu_stage_numbers <sdc file> <profile> reads the text of the SDC, cuts out the section between the lines
#       # ==== BEGIN STAGE PROFILE TABLE
#       # ==== END STAGE PROFILE TABLE
#   and evaluates it INSIDE A PROC (local variables, so nothing leaks into the DC script's globals). That
#   section is the ONE table of the profile numbers: it is typed in constraints/unpu_top.sdc, and
#   constraints/pm_unpu_top.sdc carries a byte-identical copy (constraints/test_stages.tcl compares them).
#   Nothing is typed here. The section is plain Tcl by design (set, expr, foreach, if, error, puts).
#   Result: a flat list  period <ns> setup <ns> hold <ns> kind <pre|post> budget <ns>
#   Any problem (file unreadable, markers missing or duplicated, profile unknown, UNPU_STAGE unset) raises a Tcl
#   error with the reason. The caller decides what to do (the DC script stops: it is fatal there).
#
# The SDC section reads the profile from the environment (UNPU_STAGE); the caller sets it before the call.
# The section prints its Info line ("Info: [unpu] SDC profile ...") when it is evaluated, so the line appears in
# the log once from here and once from read_sdc itself. Both come from the same text.
# =============================================================================

proc unpu_stage_section {sdc_file} {
    if {[catch {set fh [open $sdc_file r]} msg]} { return -code error "cannot open $sdc_file: $msg" }
    set text [read $fh]
    close $fh
    set begin_pat {^# ==== BEGIN STAGE PROFILE TABLE}
    set end_pat   {^# ==== END STAGE PROFILE TABLE}
    set lines [split $text "\n"]
    set b {}
    set e {}
    set n 0
    foreach l $lines {
        if {[regexp -- $begin_pat $l]} { lappend b $n }
        if {[regexp -- $end_pat $l]}   { lappend e $n }
        incr n
    }
    if {[llength $b] != 1 || [llength $e] != 1} {
        return -code error "$sdc_file must contain exactly one BEGIN and one END STAGE PROFILE TABLE marker line (found [llength $b] and [llength $e])"
    }
    if {[lindex $b 0] >= [lindex $e 0]} { return -code error "$sdc_file: the END marker comes before the BEGIN marker" }
    return [join [lrange $lines [expr {[lindex $b 0] + 1}] [expr {[lindex $e 0] - 1}]] "\n"]
}

# The section is evaluated in this proc's own scope. Variable names: the section sets CLK_PERIOD, CLK_UNCERT_SETUP,
# CLK_UNCERT_HOLD, UNPU_STAGE_KIND and FT_BUDGET_NS (the names the SDC itself uses below the table).
proc unpu_stage_numbers {sdc_file profile} {
    set section [unpu_stage_section $sdc_file]
    set had_env [info exists ::env(UNPU_STAGE)]
    if {$had_env} { set old_env $::env(UNPU_STAGE) }
    set ::env(UNPU_STAGE) $profile
    set rc [catch {unpu_stage_eval $section} res]
    if {$had_env} { set ::env(UNPU_STAGE) $old_env } else { unset ::env(UNPU_STAGE) }
    if {$rc} { return -code error "stage profile '$profile' from $sdc_file: $res" }
    return $res
}
proc unpu_stage_eval {section} {
    eval $section
    foreach v {CLK_PERIOD CLK_UNCERT_SETUP CLK_UNCERT_HOLD UNPU_STAGE_KIND FT_BUDGET_NS} {
        if {![info exists $v]} { return -code error "the table section did not set $v" }
    }
    return [list period $CLK_PERIOD setup $CLK_UNCERT_SETUP hold $CLK_UNCERT_HOLD kind $UNPU_STAGE_KIND budget $FT_BUDGET_NS]
}

# unpu_check_outputs <dir> <report files> <other files> <header prefix> <header-only files>
#   The check of syn/out/<profile>/ at the end of the DC script (task 055). Returns a list of problems (empty = OK):
#   - the directory must exist,
#   - its entries must be exactly the report files plus the other files (nothing extra, nothing missing),
#   - every entry must be a non-empty regular file,
#   - the FIRST line of every report file must start with the header prefix (so no report is anonymous),
#   - every report file except the header-only ones (the .profile file) must have at least one line after the header
#     (a header with nothing under it means the report command wrote nothing).
proc unpu_check_outputs {dir report_files other_files header_prefix header_only} {
    set problems {}
    if {![file isdirectory $dir]} { return [list "directory $dir does not exist"] }
    set have {}
    foreach f [glob -nocomplain -directory $dir -tails * .*] {
        if {$f eq "." || $f eq ".."} { continue }
        lappend have $f
    }
    set want [concat $report_files $other_files]
    foreach f $want { if {[lsearch -exact $have $f] < 0} { lappend problems "missing: $f" } }
    foreach f $have { if {[lsearch -exact $want $f] < 0} { lappend problems "unexpected file: $f" } }
    foreach f $want {
        if {[lsearch -exact $have $f] < 0} { continue }
        set path [file join $dir $f]
        if {![file isfile $path]} { lappend problems "not a regular file: $f"; continue }
        if {[file size $path] == 0} { lappend problems "empty: $f"; continue }
    }
    foreach f $report_files {
        set path [file join $dir $f]
        if {![file isfile $path] || [file size $path] == 0} { continue }
        set fh [open $path r]
        set first [gets $fh]
        set rest [string trim [read $fh]]
        close $fh
        if {$rest eq "" && [lsearch -exact $header_only $f] < 0} { lappend problems "$f: nothing after the profile header (the report command wrote no text)" }
        if {[string first $header_prefix $first] != 0} { lappend problems "$f: first line is not the profile header (got '[string range $first 0 60]')" }
    }
    return $problems
}
