# ==============================================================================
# File  : pnr_v2/run_root.tcl   (task 082: one clone = one self-contained run)
# Used by: every ICC2 and PrimeTime script of pnr_v2/ (they source it from the folder they live in, see the 3 bootstrap lines at their top).
# Does  : derives the PROJECT ROOT ("run root") from the location of the script that is running, never from a typed path:
#         root = the folder that contains pnr_v2/. A second clone (for example .../unpu_run2) therefore writes ONLY into itself; the
#         old clone is never touched. The name of the clone does not matter.
# Why   : before 082 about 20 scripts carried the server path of run 1 as a typed literal; a second clone would have silently
#         written into run 1 and overwritten the fallback.
# Pure Tcl (no tool command): tested with tclsh in pnr_v2/test_run_root.tcl.
# ==============================================================================

# unpu_run_root <script path>: the run root of the script, or an error that says what was found
proc unpu_run_root {script_path} {
    if {$script_path eq ""} {
        error "ERROR 082: \[info script\] is empty: the script was pasted or typed into the shell. Start it with `source <file>` or `-f <file>` so that the run root can be derived from where the file is"
    }
    set dir [file dirname [file normalize $script_path]]
    set d $dir
    while {1} {
        if {[file tail $d] eq "pnr_v2"} { break }
        set up [file dirname $d]
        if {$up eq $d} {
            error "ERROR 082: no folder named pnr_v2 above the script $script_path (searched up from $dir): the script is not inside a clone of the repository, so no run root can be derived"
        }
        set d $up
    }
    set root [file dirname $d]
    if {![file isdirectory $d] || ![file exists [file join $d run_root.tcl]]} {
        error "ERROR 082: $d (found above $script_path) does not contain run_root.tcl: it is not the pnr_v2 folder of this repository"
    }
    return [unpu_run_norm $root]
}

# unpu_run_norm <dir>: the path with symbolic links resolved (so that two spellings of one folder compare equal)
proc unpu_run_norm {dir} {
    return [file normalize [file join $dir .]]
}

# unpu_run_clone_of <dir>: the root of the clone that contains <dir> (searched upwards for pnr_v2/run_root.tcl), or "" if <dir> is in no clone
proc unpu_run_clone_of {dir} {
    set d [unpu_run_norm $dir]
    while {1} {
        if {[file exists [file join $d pnr_v2 run_root.tcl]]} { return $d }
        set up [file dirname $d]
        if {$up eq $d} { return "" }
        set d $up
    }
}

# unpu_run_cwd_warning <root> <script path> <cwd>: the WARNING text if <cwd> lies in ANOTHER clone than <root>, else "" (not blocking: the user may do it on purpose)
proc unpu_run_cwd_warning {root script_path cwd} {
    set other [unpu_run_clone_of $cwd]
    if {$other ne "" && $other ne $root} {
        return ">>> WARNING 082: the current directory ($cwd) belongs to the clone $other, but this script ($script_path) belongs to the clone $root: every file of this run is written under $root, NOT under $other"
    }
    return ""
}

# unpu_run_init <script path>: derive the run root, print the RUN ROOT line (and the cwd warning), return the root
proc unpu_run_init {script_path} {
    set root [unpu_run_root $script_path]
    puts ">>> RUN ROOT: $root"
    set w [unpu_run_cwd_warning $root $script_path [pwd]]
    if {$w ne ""} { puts $w }
    return $root
}
