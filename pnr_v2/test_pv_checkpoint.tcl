# ==============================================================================
# Test: test_pv_checkpoint.tcl (task 091)
# Run : tclsh pnr_v2/test_pv_checkpoint.tcl   (no ICC2 / PrimeTime / Calibre needed)
# Tests the checkpoint mode: pv.tcl's pure block 091 (UNPU_PV_BLOCK / UNPU_PV_TAG validation, the output places, the netlist module check), the source of pv.tcl (every export goes through
# OUT_DIR / RPT_DIR / LOG_DIR, the copy is made first, nothing writes to outputs/ in a tagged run), pt_common.tcl's UNPU_PT_TAG (pure procs and a real source in a tree copy), the sed commands of
# the README on the REAL control files, and that the README and the simulation script carry the switches.
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
set nfail 0; set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc errmsg {script} { if {[catch {uplevel 1 $script} m]} { return $m }; return "" }

set pv [read_file $here/pv.tcl]
set b [string first "# ---- BEGIN PURE TCL 091 ----" $pv]; set e [string first "# ---- END PURE TCL 091 ----" $pv]
check "pure markers exist" {$b > 0 && $e > $b}
eval [string range $pv $b $e]

# ---- 1. tag and block validation ----
foreach ok {route r1 Route_2 a 12345 route_after_eco} { check "tag accepted: $ok" {[pv091_tag_problem $ok] eq ""} }
set badtags [list "" "a b" "a-b" "a/b" "../x" "a.b" "x;y" "route\n" [string repeat a 33]]
foreach bad $badtags { check "tag rejected: '[string map {"\n" {\n}} $bad]'" {[pv091_tag_problem $bad] ne ""} }
check "default: no variable -> the final block, no tag" {[pv091_resolve unpu_top {} {}] eq "unpu_top_filled {}"}
check "tag only -> final block with a tag" {[pv091_resolve unpu_top {} {route}] eq "unpu_top_filled route"}
check "block and tag" {[pv091_resolve unpu_top {unpu_top_route} {route}] eq "unpu_top_route route"}
check "block == default and no tag is fine" {[pv091_resolve unpu_top {unpu_top_filled} {}] eq "unpu_top_filled {}"}
check "other block WITHOUT a tag -> ERROR 091 (would overwrite the final export)" {[string match "ERROR 091: UNPU_PV_BLOCK=unpu_top_route differs*overwrite the final export folder*" [errmsg {pv091_resolve unpu_top {unpu_top_route} {}}]]}
foreach bad {"" "lib:blk" "a b" "a/b" "x;y"} { check "block rejected: '$bad'" {[string match "ERROR 091: UNPU_PV_BLOCK=*" [errmsg {pv091_resolve unpu_top [list $bad] {route}}]]} }
foreach bad {"" "a b" "../x"} { check "tag rejected via resolve: '$bad'" {[string match "ERROR 091: UNPU_PV_TAG:*" [errmsg {pv091_resolve unpu_top {} [list $bad]}]]} }
check "the block the run would save is refused as input" {[string match "ERROR 091:*would save*" [errmsg {pv091_resolve unpu_top {unpu_top_pv_route} {route}}]]}

# ---- 2. the output places ----
set d [pv091_paths /r/pnr_icc2 unpu_top ""]
check "no tag: the places of the final export, unchanged" {[dict get $d out_dir] eq "/r/pnr_icc2/outputs" && [dict get $d rpt_dir] eq "/r/pnr_icc2/reports" && [dict get $d log_name] eq "7_pv.log" && [dict get $d save_name] eq "unpu_top_pv"}
set d [pv091_paths /r/pnr_icc2 unpu_top route]
check "tag route: outputs_route, reports_route, 7_pv_route.log, unpu_top_pv_route" {[dict get $d out_dir] eq "/r/pnr_icc2/outputs_route" && [dict get $d rpt_dir] eq "/r/pnr_icc2/reports_route" && [dict get $d log_name] eq "7_pv_route.log" && [dict get $d save_name] eq "unpu_top_pv_route"}
set clash 0
foreach tag {a route r1 Route_2 outputs reports pv x_y 1} {
    set d [pv091_paths /r/pnr_icc2 unpu_top $tag]
    set f [pv091_paths /r/pnr_icc2 unpu_top ""]
    foreach k {out_dir rpt_dir log_name save_name} { if {[dict get $d $k] eq [dict get $f $k]} { incr clash } }
}
check "no valid tag gives any place of the final export (outputs, reports, log, saved block)" {$clash == 0}
check "a tagged place never lies inside the final export folder" {![string match "/r/pnr_icc2/outputs/*" [dict get [pv091_paths /r/pnr_icc2 unpu_top outputs] out_dir]]}

# ---- 3. the netlist module check ----
set v "// netlist\nmodule unpu_top (\n  clk,\n  rst\n);\nendmodule\nmodule sub_a(x);\nendmodule\n"
check "modules read in order" {[pv091_modules $v] eq "unpu_top sub_a"}
check "design module present -> no problem" {[pv091_module_problem [pv091_modules $v] unpu_top] eq ""}
check "design module absent -> sentence naming link_design" {[string match "*no module 'unpu_top'*link_design unpu_top*" [pv091_module_problem [pv091_modules "module unpu_top_route (a);\nendmodule\n"] unpu_top]]}
check "no module at all -> problem" {[pv091_module_problem {} unpu_top] ne ""}

# ---- 4. the source of pv.tcl ----
proc code_lines {text} {
    set o {}; set n 0
    foreach l [split $text "\n"] { incr n; set t [string trim $l]; if {$t eq "" || [string index $t 0] eq "#"} continue; regsub {\s;#.*$} $t "" t; lappend o [list $n [string trim $t]] }
    return $o
}
set cl [code_lines $pv]
set l_over 0; set l_pure_end 0
foreach x $cl { lassign $x n t; if {[regexp {^set OUT_DIR\s+\[dict get \$pv_paths out_dir\]} $t]} { set l_over $n } }
check "pv.tcl overrides OUT_DIR from pv091_paths" {$l_over > 0}
set late_bad {}
foreach x $cl {
    lassign $x n t
    if {$n > $l_over && [regexp {/outputs([^_[:alnum:]]|$)|/reports([^_[:alnum:]]|$)|_pv\y} $t] && ![regexp {pv091_|PV_SAVE|PV_LOG|PV_TAG|PV_BLOCK|puts } $t]} { lappend late_bad "$n: $t" }
}
check "after the override no code line names outputs/, reports/ or the final block _pv literally ($late_bad)" {[llength $late_bad] == 0}
set bad_w {}
foreach x $cl {
    lassign $x n t
    if {[regexp {^(write_gds|write_def|write_parasitics|write_verilog|write_sdc|write_sdf|write_lef)\y} $t] || [regexp {^-output |^-output\s} $t]} continue
}
# every output file path of the export commands is built from OUT_DIR
set export_paths [regexp -all -inline {\$\{OUT_DIR\}/[^ \n\\]+} $pv]
check "the export file names are all built from \${OUT_DIR} ([llength $export_paths] occurrences)" {[llength $export_paths] >= 12}
check "the reports are all written under \${RPT_DIR} and none under a literal reports/" {[regexp -all {redirect -tee -file \$\{RPT_DIR\}/} $pv] >= 12 && ![regexp {redirect -tee -file [^$]*reports/} $pv]}
check "the log is \${LOG_DIR}/\${PV_LOG}" {[string match "*redirect -tee -file \${LOG_DIR}/\${PV_LOG} \{*" $pv] && ![string match "*\${LOG_DIR}/7_pv.log*" [join [lmap x $cl {lindex $x 1}] "\n"]]}
check "the final save uses PV_SAVE" {[string match "*save_block -as \$PV_SAVE*" $pv] && ![regexp {save_block -as \$\{DESIGN_NAME\}_pv\y} $pv]}
set codetxt [join [lmap x $cl {lindex $x 1}] "\n"]
set lp_copy [string first "save_block -force -as \$PV_SAVE" $codetxt]
set lp_latency [string first "unpu_remove_clock_latency pv" $codetxt]
set lp_connect [string first "connect_pg_net -automatic" $codetxt]
set lp_frame [string first "create_frame" $codetxt]
check "the copy is made BEFORE the clock-latency removal, connect_pg_net and create_frame (the source block is not modified)" {$lp_copy > 0 && $lp_copy < $lp_latency && $lp_copy < $lp_connect && $lp_copy < $lp_frame}
check "the copy is made only in a tagged run (the save is inside the if on PV_TAG)" {[regexp {if \{\$PV_TAG ne ""\} \{\nif \{\[catch \{save_block -force -as \$PV_SAVE\}} $codetxt]}
check "the block to open comes from PV_BLOCK" {[string match "*set blk_name \$PV_BLOCK*" $pv]}
check "the summary line prints block, tag and folders" {[string match "*>>> 091 PV block \$PV_BLOCK, tag*output folder \$OUT_DIR*" $pv]}
check "the module check is an error only for a tagged run" {[regexp {if \{\$pv_modp ne "" && \$PV_TAG ne ""\}} $pv]}
check "the existing hard checks are still in pv.tcl (LEF check, SDF 3.0, 088 grep, 090 export check)" {[string match "*LEF CHECK PASSED*" $pv] && [string match "*SDF CHECK PASSED*" $pv] && [string match "*unpu_clock_latency_grep pv-exported-sdc*" $pv] && [string match "*unc090_export_check pv-exported-sdc*" $pv]}
check "the default OUT_DIR assignment is overridden before the first mkdir" {[string first "file mkdir \$OUT_DIR" $pv] > [string first "set OUT_DIR   \[dict get \$pv_paths out_dir\]" $pv]}

# a mock of the checkpoint decision: with a tag, the set of directories the script would create / write
foreach tag {route r2} {
    lassign [pv091_resolve unpu_top unpu_top_route [list $tag]] blk tg
    set pp [pv091_paths /r/pnr_icc2 unpu_top $tg]
    set writes [list [dict get $pp out_dir] [dict get $pp rpt_dir] /r/pnr_icc2/logs/[dict get $pp log_name]]
    set hit 0
    foreach w $writes { if {[string match "/r/pnr_icc2/outputs/*" $w] || [string match "/r/pnr_icc2/outputs" $w] || [string match "/r/pnr_icc2/reports" $w] || $w eq "/r/pnr_icc2/logs/7_pv.log"} { incr hit } }
    check "mock: tag $tag writes nothing into outputs/, reports/ or logs/7_pv.log" {$hit == 0}
}

# ---- 5. PrimeTime: UNPU_PT_TAG ----
set pc [read_file $here/pt/pt_common.tcl]
set b2 [string first "proc pt_tag_problem" $pc]; set e2 [string first "set PT_TAG \"\"" $pc]
check "pt_common.tcl has the tag procs before their use" {$b2 > 0 && $e2 > $b2}
eval [string range $pc $b2 [expr {$e2 - 1}]]
foreach ok {route r1 A_b} { check "pt tag accepted: $ok" {[pt_tag_problem $ok] eq ""} }
foreach bad {"" "a b" "a/b" "../x" "x-y"} { check "pt tag rejected: '$bad'" {[pt_tag_problem $bad] ne ""} }
check "pt paths: no tag" {[pt_tag_paths /r ""] eq "/r/pnr_icc2/outputs /r/pnr_icc2/pt"}
check "pt paths: tag route" {[pt_tag_paths /r route] eq "/r/pnr_icc2/outputs_route /r/pnr_icc2/pt_route"}
check "the PT tag folder is the one pv.tcl writes (same tag, same rule)" {[lindex [pt_tag_paths /r/x route] 0] eq [dict get [pv091_paths /r/x/pnr_icc2 unpu_top route] out_dir]}
# a real source in a tree copy: pt_common.tcl derives its run root from where it lives
set tmp [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] pv091_test_[pid]]
file delete -force $tmp
file mkdir $tmp/pnr_v2/pt $tmp/pnr_icc2
file copy $here/run_root.tcl $tmp/pnr_v2/run_root.tcl
file copy $here/pt/pt_common.tcl $tmp/pnr_v2/pt/pt_common.tcl
set drv $tmp/drv.tcl
set fp [open $drv w]
puts $fp "source $tmp/pnr_v2/pt/pt_common.tcl\nputs \"OUT=\$PT_OUT_DIR\"\nputs \"RPT=\$PT_RPT_DIR\"\nputs \"NET=\$PT_NETLIST\"\nputs \"SDC=\$PT_CORNER(ss,sdc)\"\nputs \"SPEF=\$PT_SPEF_BASE\"\nputs \"TAG=\$PT_TAG\""
close $fp
proc run_pt {env} {
    global drv tmp
    foreach k {UNPU_PT_TAG} { catch {unset ::env($k)} }
    foreach {k v} $env { set ::env($k) $v }
    set rc [catch {exec tclsh $drv 2>@1} out]
    catch {unset ::env(UNPU_PT_TAG)}
    return [list $rc $out]
}
set r [run_pt {}]
check "pt source, no tag: the final places" {[lindex $r 0] == 0 && [string match "*OUT=[file normalize $tmp]/pnr_icc2/outputs*RPT=[file normalize $tmp]/pnr_icc2/pt*" [string map {"\n" " "} [lindex $r 1]]] || [string match "*pnr_icc2/outputs *" [string map {"\n" " "} [lindex $r 1]]]}
check "pt source, no tag: TAG empty and the line says no UNPU_PT_TAG" {[string match "*no UNPU_PT_TAG: the final export*" [lindex $r 1]] && [string match "*TAG=*" [lindex $r 1]]}
set r [run_pt {UNPU_PT_TAG route}]
check "pt source, tag route without the folder -> PT ERROR naming pv.tcl" {[lindex $r 0] == 1 && [string match "*PT ERROR: UNPU_PT_TAG=route but the folder*outputs_route does not exist*UNPU_PV_TAG route*" [lindex $r 1]]}
file mkdir $tmp/pnr_icc2/outputs_route
set r [run_pt {UNPU_PT_TAG route}]
set flat [string map {"\n" " "} [lindex $r 1]]
check "pt source, tag route with the folder: every input path is under outputs_route, reports under pt_route" {[lindex $r 0] == 0 && [string match "*pnr_icc2/outputs_route*" $flat] && [regexp {NET=\S*/pnr_icc2/outputs_route/unpu_top_pnr_sim.v} $flat] && [regexp {SDC=\S*/pnr_icc2/outputs_route/unpu_top_pnr_ss.sdc} $flat] && [regexp {SPEF=\S*/pnr_icc2/outputs_route/unpu_top_spef} $flat] && [regexp {RPT=\S*/pnr_icc2/pt_route} $flat] && [string match "*PT CHECKPOINT tag route*" $flat]}
foreach bad {"a b" "../x" ""} {
    set r [run_pt [list UNPU_PT_TAG $bad]]
    check "pt source, invalid tag '$bad' -> PT ERROR" {[lindex $r 0] == 1 && [string match "*PT ERROR: UNPU_PT_TAG:*" [lindex $r 1]]}
}
set ptl [string map {"\n" " "} $pc]
set lit {}
foreach x [code_lines $pc] { if {[string match "*pnr_icc2/outputs*" [lindex $x 1]] && ![regexp {PT_OUT_DIR|pt_tag_paths|return \[list} [lindex $x 1]]} { lappend lit $x } }
check "pt_common.tcl: no other literal 'pnr_icc2/outputs' path is left (the inputs all derive from PT_OUT_DIR) ($lit)" {[llength $lit] == 0}
foreach f {pt_setup_ss.tcl pt_hold_ff.tcl pt_eco_probe.tcl pt_eco_setup_probe.tcl} {
    check "pt/$f: no literal outputs/ or pt/ path (it uses PT_OUT_DIR / PT_RPT_DIR)" {![regexp {pnr_icc2/(outputs|pt)\y} [join [lmap x [code_lines [read_file $here/pt/$f]] {lindex $x 1}] "\n"]]}
}

# ---- 6. the README sed commands on the REAL control files ----
set rd [read_file $here/README.md]
set rb [string first "## Checkpoint after route (task 091)" $rd]
check "README has the section 'Checkpoint after route (task 091)'" {$rb > 0}
set sec [string range $rd $rb end]
set nx [string first "\n## " $sec 10]
if {$nx > 0} { set sec [string range $sec 0 $nx] }
set seds [lsearch -all -inline -glob [split $sec "\n"] "sed -i *"]
check "README has one sed per control file (drc, ant), none for lvs" {[llength $seds] == 2 && [llength [lsearch -all -inline -glob $seds "*drc.ctrl"]] == 1 && [llength [lsearch -all -inline -glob $seds "*ant.ctrl"]] == 1}
set run $tmp/RUN
file mkdir $run/pnr_icc2/calibre/route1/drc $run/pnr_icc2/calibre/route1/ant $run/pnr_icc2/outputs_route
foreach {k} {drc ant} { file copy -force $here/calibre/$k.ctrl $run/pnr_icc2/calibre/route1/$k/$k.ctrl }
foreach sedcmd $seds { exec sh -c "cd $run && $sedcmd" }
foreach k {drc ant} {
    set new [read_file $run/pnr_icc2/calibre/route1/$k/$k.ctrl]
    set old [read_file $here/calibre/$k.ctrl]
    set nl [split $new "\n"]; set ol [split $old "\n"]
    set diff 0; set lp ""
    for {set i 0} {$i < [llength $ol]} {incr i} { if {[lindex $ol $i] ne [lindex $nl $i]} { incr diff; set lp [lindex $nl $i] } }
    check "$k.ctrl: exactly one line changed and it is the LAYOUT PATH line" {$diff == 1 && [llength $nl] == [llength $ol] && [string match "LAYOUT PATH *" $lp]}
    check "$k.ctrl: the line is LAYOUT PATH \"../../../outputs_route/unpu_top_routed.gds\"" {$lp eq "LAYOUT PATH \"../../../outputs_route/unpu_top_routed.gds\""}
    file mkdir $run/pnr_icc2/outputs_route
    set fp [open $run/pnr_icc2/outputs_route/unpu_top_routed.gds w]; puts $fp x; close $fp
    set resolved [file normalize [file join $run/pnr_icc2/calibre/route1/$k ../../../outputs_route/unpu_top_routed.gds]]
    check "$k: from the run folder the path resolves to this clone's outputs_route GDS" {$resolved eq [file normalize $run/pnr_icc2/outputs_route/unpu_top_routed.gds] && [file exists $resolved]}
    check "$k: the repository copy is untouched (still outputs/)" {[string match "*LAYOUT PATH \"../../../outputs/unpu_top_routed.gds\"*" $old]}
}
check "README: the sequence has the env lines, the pv command, both pt_shell runs with the tag, both Calibre runs" {
    [string match "*setenv UNPU_PV_BLOCK unpu_top_route*" $sec] && [string match "*setenv UNPU_PV_TAG route*" $sec] && [string match "*icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_route_console.log*" $sec] &&
    [string match "*unsetenv UNPU_PV_BLOCK*" $sec] && [string match "*unsetenv UNPU_PV_TAG*" $sec] && [string match "*setenv UNPU_PT_TAG route*" $sec] && [string match "*pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl*" $sec] && [string match "*pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl*" $sec] &&
    [string match "*calibre -drc -hier drc.ctrl*" $sec] && [string match "*calibre -drc -hier ant.ctrl*" $sec] && [string match "*unsetenv UNPU_PT_TAG*" $sec]}
check "README: ls -lL and grep of the LAYOUT PATH line before the Calibre runs" {[string match "*grep '^LAYOUT PATH' drc.ctrl*" $sec] && [string match "*ls -lL ../../../outputs_route/unpu_top_routed.gds*" $sec]}
# ---- 7. the simulation script ----
set sim [read_file $here/sim/run_postlayout_sim.sh]
check "run_postlayout_sim.sh: PL_OUT_DIR selects the export folder (task 075) and the README names it for the checkpoint" {[string match "*PL_OUT_DIR:-\$OUT_DIR_DEFAULT*" $sim] && [string match "*PL_OUT_DIR*" $sec]}

file delete -force $tmp
puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
