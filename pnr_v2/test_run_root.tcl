# ==============================================================================
# Test: test_run_root.tcl (task 082)
# Run : tclsh pnr_v2/test_run_root.tcl   (any directory; no ICC2 / PrimeTime needed)
# Tests pnr_v2/run_root.tcl and the way the scripts use it:
#   - a copy of the tree under ANOTHER directory name resolves to ITS OWN root (the point of the task), also through a symbolic link;
#   - an empty [info script] and a script outside any pnr_v2 folder stop with an error that says what was found;
#   - the cwd warning appears only when the current directory lies in ANOTHER clone;
#   - the bootstrap lines are identical in all scripts of one folder level; no script has the typed server path in a line of code;
#   - the real pt_common.tcl, sourced from a copy, puts all PrimeTime paths under the copy.
# ==============================================================================
set here [file dirname [file normalize [info script]]]
set repo [file dirname $here]
source $here/run_root.tcl

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
proc caught {script} { if {[catch {uplevel 1 $script} m]} { return [list 1 $m] }; return [list 0 $m] }

# ---- a temporary tree: <tmp>/<name>/pnr_v2 (a copy of the real folder) -------------------------------------------------------------
set tmp [file normalize [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] "rr082_[pid]"]]
file delete -force $tmp
file mkdir $tmp
proc make_clone {tmp name} {
    global repo
    set root [file join $tmp $name]
    file mkdir $root
    file copy $repo/pnr_v2 $root/pnr_v2
    file mkdir $root/pnr_icc2
    return [file normalize $root]
}
set c1 [make_clone $tmp unpu]
set c2 [make_clone $tmp totally_other_name_7]

# ---- 1. the root of a script is the clone it lives in, whatever the clone is called --------------------------------------------------
check "script in pnr_v2 -> its clone (name unpu)" {[unpu_run_root $c1/pnr_v2/cts.tcl] eq $c1}
check "script in pnr_v2 -> its clone (other name)" {[unpu_run_root $c2/pnr_v2/cts.tcl] eq $c2}
check "script in pnr_v2/pt -> the same clone (one level deeper)" {[unpu_run_root $c2/pnr_v2/pt/pt_common.tcl] eq $c2}
check "two clones give two different roots" {[unpu_run_root $c1/pnr_v2/cts.tcl] ne [unpu_run_root $c2/pnr_v2/cts.tcl]}
check "the real repository resolves to itself" {[unpu_run_root $here/cts.tcl] eq [file normalize $repo]}
check "a relative script path is made absolute first" {[set old [pwd]; cd $c2/pnr_v2; set r [unpu_run_root ./cts.tcl]; cd $old; set r] eq $c2}
file link -symbolic $tmp/link_to_c2 $c2
check "a symbolic link to a clone resolves to the clone" {[unpu_run_root $tmp/link_to_c2/pnr_v2/cts.tcl] eq $c2}

# ---- 2. errors say what was found ----------------------------------------------------------------------------------------------------
lassign [caught {unpu_run_root ""}] bad m
check "empty \[info script\] -> error" {$bad == 1}
check "empty \[info script\] -> the message names the cause" {[string match "*ERROR 082*empty*source*" $m]}
file mkdir $tmp/stray
file copy $repo/pnr_v2/cts.tcl $tmp/stray/cts.tcl
lassign [caught {unpu_run_root $tmp/stray/cts.tcl}] bad m
check "script outside any pnr_v2 folder -> error" {$bad == 1}
check "that message names the script and the folder searched" {[string match "*ERROR 082*no folder named pnr_v2*$tmp/stray/cts.tcl*$tmp/stray*" $m]}
file mkdir $tmp/fake/pnr_v2
file copy $repo/pnr_v2/cts.tcl $tmp/fake/pnr_v2/cts.tcl
lassign [caught {unpu_run_root $tmp/fake/pnr_v2/cts.tcl}] bad m
check "a pnr_v2 folder without run_root.tcl -> error" {$bad == 1 && [string match "*ERROR 082*does not contain run_root.tcl*" $m]}

# ---- 3. the RUN ROOT line and the cwd warning ------------------------------------------------------------------------------------------
check "cwd inside the same clone -> no warning" {[unpu_run_cwd_warning $c2 $c2/pnr_v2/cts.tcl $c2/pnr_icc2] eq ""}
check "cwd at the clone root -> no warning" {[unpu_run_cwd_warning $c2 $c2/pnr_v2/cts.tcl $c2] eq ""}
set w [unpu_run_cwd_warning $c2 $c2/pnr_v2/cts.tcl $c1/pnr_icc2]
check "cwd in ANOTHER clone -> WARNING" {$w ne "" && [string match ">>> WARNING 082:*" $w]}
check "the warning names both clones" {[string first $c1 $w] >= 0 && [string first $c2 $w] >= 0}
check "cwd in no clone at all -> no warning (nothing to confuse)" {[unpu_run_cwd_warning $c2 $c2/pnr_v2/cts.tcl $tmp/stray] eq ""}
check "cwd through a symbolic link to the SAME clone -> no warning" {[unpu_run_cwd_warning $c2 $c2/pnr_v2/cts.tcl $tmp/link_to_c2/pnr_icc2] eq ""}
set old [pwd]
cd $c1/pnr_icc2
set out [exec tclsh << "source $c2/pnr_v2/run_root.tcl\nputs \[unpu_run_init $c2/pnr_v2/cts.tcl\]"]
cd $old
check "unpu_run_init prints the RUN ROOT line first" {[string match ">>> RUN ROOT: $c2*" $out]}
check "unpu_run_init prints the WARNING when started in the other clone" {[string match "*>>> WARNING 082*" $out]}
check "unpu_run_init returns the root" {[lindex [split $out "\n"] end] eq $c2}

# ---- 4. the bootstrap lines of the scripts --------------------------------------------------------------------------------------------
proc bootstrap_of {text} {
    set l [split $text "\n"]
    set b -1
    for {set i 0} {$i < [llength $l]} {incr i} { if {[string match {set UNPU_ERR ""*} [lindex $l $i]]} { set b $i; break } }
    if {$b < 0} { return "" }
    return [join [lrange $l $b [expr {$b + 2}]] "\n"]
}
proc strip_comment {s} { return [regsub -all {\s+;# 082:[^\n]*} $s ""] }
set level0 {build_ndm_std build_ndm_filler floorplanning powerplanning placement pin_replace cts route fix_antenna antenna_port_buffers antenna_clk_root timing_closure pt_eco_apply metal_fill pv diag_filler_runs design_setup diag_io_latency}
set ref0 [bootstrap_of [read_file $here/cts.tcl]]
check "the reference bootstrap (cts.tcl) has 3 lines" {[llength [split $ref0 "\n"]] == 3}
check "it sources run_root.tcl from the folder of the script itself" {[string first {[file dirname [file normalize [info script]]] run_root.tcl} $ref0] >= 0}
foreach f $level0 {
    set bs [bootstrap_of [read_file $here/$f.tcl]]
    check "$f.tcl: the bootstrap is the same 3 lines as in cts.tcl" {[strip_comment $bs] eq [strip_comment $ref0]}
    set txt [read_file $here/$f.tcl]
    set p_set [string first "set RUN_ROOT " $txt]
    set p_use [expr {[string first "\$\{RUN_ROOT\}" $txt] >= 0 ? [string first "\$\{RUN_ROOT\}" $txt] : [string first "\$RUN_ROOT" $txt]}]
    check "$f.tcl: RUN_ROOT is set before it is used" {$p_set >= 0 && $p_use > $p_set}
}
set ref1 [bootstrap_of [read_file $here/pt/pt_common.tcl]]
check "pt_common.tcl: bootstrap one level deeper (dirname of dirname)" {[string first {[file dirname [file dirname [file normalize [info script]]]] run_root.tcl} $ref1] >= 0}
check "pt_common.tcl: the rest of the bootstrap equals the pnr_v2 one" {[string map [list {[file dirname [file dirname [file normalize [info script]]]]} {[file dirname [file normalize [info script]]]}] [strip_comment $ref1]] eq [strip_comment $ref0]}

# ---- 5. no typed server path in a line of code ----------------------------------------------------------------------------------------
set lit "/storage/EE5239G1/aagams_work[string cat space2]"
set nlit 0
foreach f [concat [glob $here/*.tcl] [glob $here/pt/*.tcl] [glob $here/calibre/*.ctrl]] {
    set ln 0
    foreach l [split [read_file $f] "\n"] {
        incr ln
        if {[string first $lit $l] >= 0} { incr nlit; puts "  typed path: [file tail $f]:$ln: [string range $l 0 100]" }
    }
}
check "no script, test or control file carries the typed server path" {$nlit == 0}


# ---- 5b. the Calibre control files: LAYOUT PATH is relative and resolves, from the run folder the README starts Calibre in, to THIS clone's GDS ----------
foreach k {drc ant lvs} {
    set ctrl [read_file $here/calibre/$k.ctrl]
    set lp ""
    foreach l [split $ctrl "\n"] { if {[regexp {^LAYOUT PATH "([^"]+)"} $l -> v]} { set lp $v } }
    check "$k.ctrl: has a LAYOUT PATH line" {$lp ne ""}
    check "$k.ctrl: LAYOUT PATH is relative" {[file pathtype $lp] eq "relative"}
    set got [file normalize [file join $c2/pnr_icc2/calibre/run1/$k $lp]]
    check "$k.ctrl: from <clone>/pnr_icc2/calibre/run1/$k it points at that clone's pnr_icc2/outputs GDS" {$got eq "$c2/pnr_icc2/outputs/unpu_top_routed.gds"}
}

# ---- 6. the real pt_common.tcl, sourced from a copy -------------------------------------------------------------------------------------
set pt [exec tclsh << "source $c2/pnr_v2/pt/pt_common.tcl\nputs \"BASE=\$PT_BASE\"\nputs \"OUT=\$PT_OUT_DIR\"\nputs \"RPT=\$PT_RPT_DIR\""]
check "pt_common.tcl in a copy prints its RUN ROOT" {[string match "*>>> RUN ROOT: $c2*" $pt]}
check "pt_common.tcl in a copy: PT_BASE is the copy" {[string match "*BASE=$c2\n*" "$pt\n"]}
check "pt_common.tcl in a copy: outputs are read from the copy" {[string match "*OUT=$c2/pnr_icc2/outputs*" $pt]}
check "pt_common.tcl in a copy: reports are written into the copy" {[string match "*RPT=$c2/pnr_icc2/pt*" $pt]}
check "the old clone is not mentioned" {[string first $c1 $pt] < 0}

# ---- 7. a script pasted into the shell (empty info script) stops with the message of its bootstrap ---------------------------------------
set boot [bootstrap_of [read_file $here/cts.tcl]]
set fp [open $tmp/paste_test.tcl w]
puts $fp "info script {}"
puts $fp "set boot {$boot}"
puts $fp {if {[catch {uplevel #0 $boot} m]} { puts "CAUGHT: $m" } else { puts "reached" }}
close $fp
set pasted [exec tclsh $tmp/paste_test.tcl]
check "bootstrap with an empty \[info script\] stops with ERROR 082 and never continues" {[string match "CAUGHT: ERROR 082*pasted into the shell*" $pasted] && [string first reached $pasted] < 0}

file delete -force $tmp
puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
