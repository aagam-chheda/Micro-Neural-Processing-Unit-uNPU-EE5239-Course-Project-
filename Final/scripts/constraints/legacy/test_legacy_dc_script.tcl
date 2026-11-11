# =============================================================================
# test_legacy_dc_script.tcl -- self-test of constraints/legacy/dc_script_legacy.tcl (task 064). Plain tclsh, no EDA tool:
#
#   cd <repo root> ; tclsh constraints/legacy/test_legacy_dc_script.tcl
#
# Same technique as constraints/test_dc_script.tcl: the DC script is run in a slave interpreter in which every dc_shell command is a
# STUB that records its call and writes what the real command would write. The script runs in a COPY of the repo (rtl/ and
# constraints/legacy/ only) in a temporary directory, from that directory as the repo root. It proves the order of the commands,
# the paths, the guards and the file list. It proves NOTHING about what dc_shell does (the VERIFY items stay in the script).
# Exit code 0 only if everything passed.
# =============================================================================

set here [file dirname [file normalize [info script]]]
set repo [file dirname [file dirname $here]]
set npass 0
set nfail 0
proc check {name ok {detail ""}} {
  global npass nfail
  if {$ok} { incr npass } else { incr nfail; puts "FAIL: $name  $detail" }
}
proc slurp {f} { set fh [open $f r]; set d [read $fh]; close $fh; return $d }
proc spit {f d} { set fh [open $f w]; puts -nonewline $fh $d; close $fh }
proc cmds {log} { set r {}; foreach l $log { lappend r [lindex $l 0] }; return $r }

# ---- the expected numbers: typed here independently of the SDC (they are the user's decision of 2026-11-02) -------------
set expT 20.0 ; set expSetup 1.5 ; set expHold 0.5

set tmp [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] unpu_test_legacy_[pid]]
file delete -force $tmp
file mkdir $tmp
set root $tmp/repo
file mkdir $root/rtl $root/constraints/legacy
foreach f [glob -directory [file join $repo rtl] *.sv] { file copy $f $root/rtl/ }
foreach f {dc_script_legacy.tcl unpu_top_legacy.sdc} { file copy [file join $here $f] $root/constraints/legacy/ }
set sdc_good [slurp $here/unpu_top_legacy.sdc]

# options (a dict of knobs for the stubs): sdc_rc <v> (read_sdc return), clk_error 1, period_add <x> (read-back differs),
# attr_error 1, skip_write <name> (not written), empty_write <name> (written empty), no_header 1, extra_file <name>
proc run_dc {opts} {
  global root expT
  set pwd0 [pwd]
  cd $root
  file delete -force $root/syn
  array set o {sdc_rc 1 clk_error 0 period_add 0 attr_error 0 skip_write {} empty_write {} no_header 0 extra_file {}}
  array set o $opts
  if {$o(extra_file) ne ""} { file mkdir $root/syn/out/legacy; close [open $root/syn/out/legacy/$o(extra_file) w] }
  set i [interp create]
  $i eval {
    set ::LOG {}
    set ::PUTS {}
    set ::PWDS {}
    rename puts ::tcl::puts_real
    proc puts {args} { if {[llength $args] >= 2 && [string match {file*} [lindex $args end-1]]} { ::tcl::puts_real {*}$args } else { lappend ::PUTS [lindex $args end] } }
    proc rec {name args} { lappend ::LOG [concat [list $name] $args] }
    proc exit {{code 0}} { error "UNPU_EXIT $code" }
    proc analyze {args} { rec analyze {*}$args; lappend ::PWDS [pwd]; set fh [open UNPU_[file rootname [file tail [lindex $args end]]].mr w]; close $fh }
    proc elaborate {args} { rec elaborate {*}$args; set fh [open default.svf w]; close $fh }
    proc link {args} { rec link {*}$args }
    proc current_design {args} { rec current_design {*}$args; return DESIGN }
    proc read_sdc {args} { rec read_sdc {*}$args; return $::SDC_RC }
    proc get_clocks {args} { rec get_clocks {*}$args; if {$::CLK_ERROR} { error "no such clock" }; return CLKOBJ }
    proc sizeof_collection {c} { return 1 }
    proc get_attribute {obj attr} { rec get_attribute $obj $attr
        if {$::ATTR_ERROR} { error "attribute $attr unknown" }
        return [expr {$::PERIOD_REAL + $::PERIOD_ADD}] }
    foreach c {set_operating_conditions set_wire_load_model set_max_area set_max_dynamic_power set_max_leakage_power set_max_total_power set_fix_multiple_port_nets remove_unconnected_ports change_names} {
      proc $c {args} "rec $c {*}\$args"
    }
    proc find {args} { rec find {*}$args; return {} }
    proc compile {args} { rec compile {*}$args }
    foreach c {report_area report_power report_timing report_constraint report_qor check_timing check_design} {
      proc $c {args} {
        set name [lindex [info level 0] 0]
        rec $name {*}$args
        set k [lsearch -exact $args ">>"]
        if {$k < 0} { error "$name stub: expected '>> file'" }
        set f [lindex $args [expr {$k + 1}]]
        if {[lsearch -exact $::SKIP [file tail $f]] >= 0} { return }
        set fh [open $f a]; ::tcl::puts_real $fh "report of $name"; close $fh
      }
    }
    proc echo {args} {
      rec echo {*}$args
      set k [lsearch -exact $args ">"]
      if {$k < 0} { error "echo stub: expected '> file'" }
      set f [lindex $args [expr {$k + 1}]]
      if {$::NO_HEADER} { return }
      set fh [open $f w]; ::tcl::puts_real $fh [join [lrange $args 0 [expr {$k - 1}]] " "]; close $fh
    }
    proc stubwrite {name f text} {
      if {[lsearch -exact $::SKIP [file tail $f]] >= 0} { return }
      set fh [open $f w]
      if {[lsearch -exact $::EMPTY [file tail $f]] < 0} { ::tcl::puts_real $fh $text }
      close $fh
    }
    proc write {args} { rec write {*}$args; set k [lsearch -exact $args "-output"]; stubwrite write [lindex $args [expr {$k + 1}]] "written by write" }
    proc write_sdc {args} { rec write_sdc {*}$args; stubwrite write_sdc [lindex $args end] "written by write_sdc" }
    proc write_sdf {args} { rec write_sdf {*}$args; stubwrite write_sdf [lindex $args end] "written by write_sdf" }
  }
  $i eval [list set ::SDC_RC $o(sdc_rc)]
  $i eval [list set ::CLK_ERROR $o(clk_error)]
  $i eval [list set ::ATTR_ERROR $o(attr_error)]
  $i eval [list set ::PERIOD_ADD $o(period_add)]
  $i eval [list set ::SKIP $o(skip_write)]
  $i eval [list set ::EMPTY $o(empty_write)]
  $i eval [list set ::NO_HEADER $o(no_header)]
  $i eval [list set ::PERIOD_REAL $expT]
  set rc [catch {$i eval [list source $root/constraints/legacy/dc_script_legacy.tcl]} msg]
  set log [$i eval {set ::LOG}]
  set pts [$i eval {set ::PUTS}]
  set pwds [$i eval {set ::PWDS}]
  interp delete $i
  set endpwd [pwd]
  cd $pwd0
  set code none
  if {$rc && [regexp {UNPU_EXIT (\d+)} $msg -> c]} { set code $c } elseif {$rc} { set code "tclerror: $msg" }
  return [list code $code log $log puts $pts pwds $pwds endpwd $endpwd]
}

# ---- A. a normal run --------------------------------------------------------------------------------------------------
set report_exts {profile area power timing timing_top5 constraint qor check_timing check_design}
set want {}
foreach e $report_exts { lappend want unpu_top.$e }
set want [lsort [concat $want {unpu_top.dc.v unpu_top.sdc unpu_top_cn.dc.v unpu_top_cn.sdc unpu_top_cn.ddc}]]
array set R [run_dc {}]
puts "--- stub run, command sequence:"
puts "    [cmds $R(log)]"
puts "--- stub run, output set in syn/out/legacy:"
set have [lsort [glob -nocomplain -directory $root/syn/out/legacy -tails *]]
puts "    $have"
check "run: ends with exit 0 (the script calls exit itself)" [expr {$R(code) eq "0"}] $R(code)
check "run: syn/out/legacy holds exactly the 14 expected files (no SDF)" [expr {$have eq $want && [llength $have] == 14}] "$have"
set hdr_ok 1
foreach e $report_exts {
  set l [lindex [split [slurp $root/syn/out/legacy/unpu_top.$e] "\n"] 0]
  set exp "# legacy constraints: period $expT ns, setup uncertainty $expSetup ns, hold uncertainty $expHold ns;"
  if {[string first $exp $l] != 0} { set hdr_ok 0; puts "  header of $e: '$l' expected prefix '$exp'" }
}
check "run: every report starts with the legacy header carrying 20.0 / 1.5 / 0.5 (read from the SDC)" $hdr_ok
set rootfiles [lsort [glob -nocomplain -directory $root -tails *]]
check "run: nothing in the repo root but rtl constraints syn" [expr {$rootfiles eq {constraints rtl syn}}] $rootfiles
set wk [lsort [glob -nocomplain -directory $root/syn/out/work/legacy -tails *]]
check "run: the scratch files are in syn/out/work/legacy" [expr {[lsearch -glob $wk UNPU_*.mr] >= 0 && [lsearch -exact $wk default.svf] >= 0}] $wk
check "run: syn/out holds only legacy and work" [expr {[lsort [glob -nocomplain -directory $root/syn/out -tails *]] eq {legacy work}}]
set apwd [lsort -unique $R(pwds)]
check "run: analyze ran with the scratch directory as cwd" [expr {[llength $apwd] == 1 && [file normalize [lindex $apwd 0]] eq [file normalize $root/syn/out/work/legacy]}] $apwd
set abs_ok 1; set n_an 0
foreach l $R(log) { if {[lindex $l 0] eq "analyze"} { incr n_an; set f [lindex $l end]; if {[file pathtype $f] ne "absolute" || ![file exists $f]} { set abs_ok 0 } } }
check "run: 11 analyze calls with absolute, existing RTL paths" [expr {$n_an == 11 && $abs_ok}] "$n_an"
set c [cmds $R(log)]
set ia [lsearch $c analyze]; set il [lsearch $c link]; set is [lsearch $c read_sdc]; set ig [lsearch $c get_attribute]; set ic [lsearch $c compile]; set iw [lsearch $c write]; set icn [lsearch $c change_names]
check "run: order analyze < elaborate < link < read_sdc < get_attribute < compile < write < change_names" [expr {$ia >= 0 && $ia < [lsearch $c elaborate] && [lsearch $c elaborate] < $il && $il < $is && $is < $ig && $ig < $ic && $ic < $iw && $iw < $icn}] $c
check "run: exactly one read_sdc, with the absolute path of constraints/legacy/unpu_top_legacy.sdc" [expr {[llength [lsearch -all $c read_sdc]] == 1 && [lindex [lindex $R(log) $is] end] eq "$root/constraints/legacy/unpu_top_legacy.sdc"}]
check "run: library setup and compile options as in the base (set_operating_conditions, set_wire_load_model, set_fix_multiple_port_nets, compile -map_effort high)" \
  [expr {[lsearch $c set_operating_conditions] >= 0 && [lsearch $c set_wire_load_model] >= 0 && [lsearch $c set_fix_multiple_port_nets] >= 0 && [lindex [lindex $R(log) $ic] 1] eq "-map_effort" && [lindex [lindex $R(log) $ic] 2] eq "high"}] [lindex $R(log) $ic]
check "run: no write_sdf in the sequence" [expr {[lsearch $c write_sdf] < 0}]
check "run: the 3 writes of netlist and the 2 write_sdc, the ddc" [expr {[llength [lsearch -all $c write]] == 3 && [llength [lsearch -all $c write_sdc]] == 2}] $c
check "run: no Error: line is printed" [expr {[lsearch -glob $R(puts) "Error:*"] < 0}] [lsearch -all -inline -glob $R(puts) "Error:*"]
check "run: the printed Info says DONE legacy" [expr {[llength [lsearch -all -glob $R(puts) "Info: \\\[unpu\\\] DONE legacy:*"]] == 1}]
check "run: the readback says OK" [expr {[llength [lsearch -all -glob $R(puts) "*period read back from the tool: *OK"]] == 1}]
check "run: the shell is left in the scratch directory (cd was used)" [expr {[file normalize $R(endpwd)] eq [file normalize $root/syn/out/work/legacy]}]
puts "--- stub run, printed lines:"
foreach l $R(puts) { puts "    $l" }

# ---- B. fatal guards: exit 1 --------------------------------------------------------------------------------------------
proc expect_fatal {tag opts pattern {before_cmd analyze}} {
  global root
  array unset R
  array set R [run_dc $opts]
  set c [cmds $R(log)]
  check "$tag: exit 1" [expr {$R(code) eq "1"}] $R(code)
  check "$tag: Error line mentions '$pattern'" [expr {[lsearch -glob $R(puts) "Error: unpu DC script: *$pattern*"] >= 0}] $R(puts)
  check "$tag: STOPPED line printed" [expr {[lsearch -glob $R(puts) "Error: unpu DC script: STOPPED with exit 1*"] >= 0}]
  check "$tag: '$before_cmd' and everything after it did not run" [expr {[lsearch $c $before_cmd] < 0}] $c
  check "$tag: compile did not run" [expr {[lsearch $c compile] < 0}] $c
  check "$tag: no output file written" [expr {![file exists $root/syn/out/legacy] || [llength [glob -nocomplain -directory $root/syn/out/legacy *]] == 0}]
  puts "--- failure path '$tag': exit $R(code); [lsearch -inline -regexp $R(puts) {^Error: unpu DC script: (?!STOPPED)}]"
}
set sdcpath $root/constraints/legacy/unpu_top_legacy.sdc
file rename $sdcpath $sdcpath.off
expect_fatal "SDC file missing" {} "constraints/legacy/unpu_top_legacy.sdc not found"
file rename $sdcpath.off $sdcpath
expect_fatal "read_sdc returns 0" {sdc_rc 0} "read_sdc" compile
expect_fatal "clock missing after read_sdc" {clk_error 1} "does not exist" compile
expect_fatal "clock period read back is 21 (not 20)" {period_add 1.0} "tool holds clock period '21.0' ns" compile
expect_fatal "clock period read back is 19.9" {period_add -0.1} "tool holds clock period" compile
file rename $root/rtl/unpu_top.sv $root/rtl/unpu_top.sv.off
expect_fatal "not at the repo root (rtl/unpu_top.sv missing)" {} "rtl/unpu_top.sv not found"
file rename $root/rtl/unpu_top.sv.off $root/rtl/unpu_top.sv

# the SDC's own numbers (the strict reader)
proc tamper {map} { global root sdc_good sdcpath; spit $sdcpath [string map $map $sdc_good] }
set l_per "set CLK_PERIOD        20.0"
check "test setup: the SDC has the CLK_PERIOD line as expected" [expr {[string first $l_per $sdc_good] >= 0}]
tamper [list $l_per "# set CLK_PERIOD removed"]
expect_fatal "SDC without a CLK_PERIOD line" {} "cannot get CLK_PERIOD"
tamper [list $l_per "set CLK_PERIOD        twenty"]
expect_fatal "SDC with a non-numeric CLK_PERIOD" {} "'twenty' is not a number"
tamper [list $l_per "$l_per\nset CLK_PERIOD 20.0"]
expect_fatal "SDC with two CLK_PERIOD lines" {} "found 2"
tamper [list "set CLK_UNCERT_HOLD    0.5" "# hold removed"]
expect_fatal "SDC without a CLK_UNCERT_HOLD line" {} "cannot get CLK_UNCERT_HOLD"
tamper [list "set CLK_UNCERT_SETUP   1.5" "set CLK_UNCERT_SETUP   x1.5"]
expect_fatal "SDC with a non-numeric CLK_UNCERT_SETUP" {} "cannot get CLK_UNCERT_SETUP"
# a different (valid) period in the SDC table is used for the check: the tool (stub) says 20.0, so a table of 18.0 stops
tamper [list $l_per "set CLK_PERIOD        18.0"]
expect_fatal "SDC table says 18.0 but the tool holds 20.0" {} "tool holds clock period '20.0' ns, the SDC's CLK_PERIOD is 18.0" compile
spit $sdcpath $sdc_good

# attribute unreadable: Warning, not fatal, and the run completes
array unset R
array set R [run_dc {attr_error 1}]
check "get_attribute fails: a Warning, the run completes with exit 0" [expr {$R(code) eq "0" && [lsearch -glob $R(puts) "Warning: unpu DC script: cannot read the period*NOT done*"] >= 0}] "$R(code)"
check "get_attribute fails: no Error: line" [expr {[lsearch -glob $R(puts) "Error:*"] < 0}]

# ---- C. the output check at the end: problems are Errors and exit 1 --------------------------------------------------------
foreach {tag opts pattern} {
  "an expected output file not written (netlist)" {skip_write unpu_top_cn.dc.v} "missing: unpu_top_cn.dc.v"
  "an expected output file not written (SDC)" {skip_write unpu_top.sdc} "missing: unpu_top.sdc"
  "an expected output file empty (ddc)" {empty_write unpu_top_cn.ddc} "empty: unpu_top_cn.ddc"
  "an expected output file empty (clean SDC)" {empty_write unpu_top_cn.sdc} "empty: unpu_top_cn.sdc"
  "a report with only the header" {skip_write unpu_top.qor} "unpu_top.qor: nothing after the profile header"
  "a stale SDF in the directory" {extra_file unpu_top_cn.sdf} "unexpected file: unpu_top_cn.sdf"
  "a stale extra file in the directory" {extra_file old_run.rpt} "unexpected file: old_run.rpt"
  "no header" {no_header 1} "first line is not the profile header"
} {
  array unset R
  array set R [run_dc $opts]
  check "output check ($tag): exit 1" [expr {$R(code) eq "1"}] $R(code)
  check "output check ($tag): Error line '$pattern'" [expr {[lsearch -glob $R(puts) "Error: unpu DC script: output check: *$pattern*"] >= 0}] [lsearch -all -inline -glob $R(puts) "Error*"]
  check "output check ($tag): it is the end-of-run check (compile ran first)" [expr {[lsearch [cmds $R(log)] compile] >= 0}]
  puts "--- failure path '$tag': exit $R(code); [lsearch -inline -glob $R(puts) {Error: unpu DC script: output check*}]"
}

# ---- D. text checks on the files -------------------------------------------------------------------------------------------
set dc [slurp $here/dc_script_legacy.tcl]
# acceptance 3: no UNPU_STAGE / stage_numbers / write_sdf outside comments
set bad {}
set n 0
foreach l [split $dc "\n"] {
  incr n
  if {[regexp {^\s*#} $l]} continue
  if {[regexp {UNPU_STAGE|stage_numbers|write_sdf} $l]} { lappend bad "$n: $l" }
}
check "script: no UNPU_STAGE / stage_numbers / write_sdf outside comments" [expr {[llength $bad] == 0}] $bad
check "script: has a plain exit line before the disabled reports" [regexp {\nexit\n\n# More reports} $dc]
check "script: the old numbers are not typed in the script (no 20.0 / 1.5 / 0.5 period or uncertainty literals)" [expr {![regexp {(period|uncert)[^\n#]*(20\.0|1\.5|0\.5)} [join [lsearch -all -inline -not -regexp [split $dc "\n"] {^\s*#}] "\n"]]}]
# the SDC against git (acceptance 1), if git and the commit are available
if {![catch {exec git -C $repo cat-file -e 925bfa9^{commit}}]} {
  set ref [exec git -C $repo show 925bfa9:constraints/pm_unpu_top.sdc]
  check "SDC: byte-identical to git show 925bfa9:constraints/pm_unpu_top.sdc" [expr {[string trimright $ref "\n"] eq [string trimright $sdc_good "\n"] && [file size $here/unpu_top_legacy.sdc] > 0}]
} else {
  puts "SKIP: commit 925bfa9 not available here; compare with: git show 925bfa9:constraints/pm_unpu_top.sdc | cmp - constraints/legacy/unpu_top_legacy.sdc"
}

file delete -force $tmp
puts ""
puts "test_legacy_dc_script: $npass passed, $nfail failed"
if {$nfail > 0} { puts "TESTS FAILED"; exit 1 }
puts "ALL TESTS PASSED"
exit 0
