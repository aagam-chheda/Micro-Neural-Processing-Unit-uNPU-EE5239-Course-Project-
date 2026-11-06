# =============================================================================
# test_dc_script.tcl -- self-test of constraints/pm_dc_script_unpu.tcl and constraints/stage_numbers.tcl (task 055).
# Plain tclsh, no EDA tool:
#
#   cd <repo root> ; tclsh constraints/test_dc_script.tcl
#
# The DC script is run in a slave interpreter in which every dc_shell command is a STUB that records its call and
# writes what the real command would write (a line into the report file, a scratch file into the current
# directory). The script runs in a COPY of the repo (rtl/ and constraints/ only) in a temporary directory, from
# that directory as the repo root. This proves the order of the commands, the paths, the guards and the file lists.
# It proves NOTHING about what dc_shell does: that is listed as VERIFY in the script and in syn/RUNBOOK.md.
#
# The stub of read_sdc does NOT define the variables of the SDC's table section in the script's scope. That is
# the behaviour of the real dc_shell seen in the first real run (task 055); the old script fails on it.
# Exit code 0 only if everything passed.
# =============================================================================

set here [file dirname [file normalize [info script]]]
set repo [file dirname $here]
set npass 0
set nfail 0
proc check {name ok {detail ""}} {
  global npass nfail
  if {$ok} { incr npass } else { incr nfail; puts "FAIL: $name  $detail" }
}
proc slurp {f} { set fh [open $f r]; set d [read $fh]; close $fh; return $d }
proc spit {f d} { set fh [open $f w]; puts -nonewline $fh $d; close $fh }

source [file join $here stage_numbers.tcl]
# the table section prints its Info line when evaluated: keep this test's own output quiet
rename puts ::real_puts
proc puts {args} { if {[string match "Info: \\\[unpu\\\]*" [lindex $args end]]} return; ::real_puts {*}$args }

# ---- the expected numbers, typed here independently of the SDC --------------------------------------------------
array set expT      {syn20 20.0 syn18 18.0 syn16 16.0 place 18.0 cts 18.0 route 20.0 signoff 20.0}
array set expKind   {syn20 pre  syn18 pre  syn16 pre  place pre  cts post route post signoff post}
array set expSetup  {pre 1.2 post 0.6}
set expHold 0.05
set profiles {syn20 syn18 syn16 place cts route signoff}
proc approx {a b} { return [expr {abs($a - $b) < 1e-9}] }

# =============================================================================
# A. unpu_stage_numbers
# =============================================================================
foreach f {unpu_top.sdc pm_unpu_top.sdc} {
  foreach p $profiles {
    set r [unpu_stage_numbers [file join $here $f] $p]
    array unset g
    array set g $r
    check "numbers $f $p: period" [approx $g(period) $expT($p)] $r
    check "numbers $f $p: setup uncertainty" [approx $g(setup) $expSetup($expKind($p))] $r
    check "numbers $f $p: hold uncertainty" [approx $g(hold) $expHold] $r
    check "numbers $f $p: kind" [expr {$g(kind) eq $expKind($p)}] $r
    check "numbers $f $p: feedthrough budget = 0.30 T - setup" [approx $g(budget) [expr {0.30 * $expT($p) - $expSetup($expKind($p))}]] $r
  }
}
check "numbers: nothing leaks into the caller's globals" [expr {![info exists ::CLK_PERIOD] && ![info exists ::UNPU_STAGE_TABLE] && ![info exists ::JITTER_NS]}]
# the environment is restored
catch {unset ::env(UNPU_STAGE)}
unpu_stage_numbers [file join $here unpu_top.sdc] syn16
check "numbers: UNPU_STAGE was unset before, is unset after" [expr {![info exists ::env(UNPU_STAGE)]}]
set ::env(UNPU_STAGE) keepme
unpu_stage_numbers [file join $here unpu_top.sdc] syn16
check "numbers: UNPU_STAGE had a value before, has it after" [expr {$::env(UNPU_STAGE) eq "keepme"}]
unset ::env(UNPU_STAGE)
# errors
foreach {name prof} {unknown syn17 empty ""} {
  set rc [catch {unpu_stage_numbers [file join $here unpu_top.sdc] $prof} msg]
  check "numbers: $name profile '$prof' is an error that lists the valid names" [expr {$rc && [string match "*syn20 syn18 syn16 place cts route signoff*" $msg]}] $msg
}
set rc [catch {unpu_stage_numbers /nonexistent/x.sdc syn20} msg]
check "numbers: missing file is an error" [expr {$rc && [string match "*cannot open*" $msg]}] $msg

# tampered copies of the SDC
set tmp [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] unpu_test_dc_[pid]]
file delete -force $tmp
file mkdir $tmp
set sdc [slurp [file join $here unpu_top.sdc]]
spit $tmp/nobegin.sdc [string map [list "# ==== BEGIN STAGE PROFILE TABLE" "# begin removed"] $sdc]
spit $tmp/noend.sdc   [string map [list "# ==== END STAGE PROFILE TABLE" "# end removed"] $sdc]
spit $tmp/dup.sdc     [string map [list "# ==== END STAGE PROFILE TABLE" "# ==== END STAGE PROFILE TABLE\n# ==== END STAGE PROFILE TABLE"] $sdc]
set b "# ==== BEGIN STAGE PROFILE TABLE"; set e "# ==== END STAGE PROFILE TABLE"
set ib [string first $b $sdc]; set ie [string first $e $sdc]
spit $tmp/reversed.sdc "[string range $sdc 0 [expr {$ib - 1}]]$e\n$b[string range $sdc [expr {$ie + [string length $e]}] end]"
spit $tmp/novar.sdc   [string map [list "set CLK_UNCERT_HOLD \$UNCERT_HOLD_NS" "# removed"] $sdc]
foreach {f what} {nobegin "no BEGIN marker" noend "no END marker" dup "two END markers" reversed "END before BEGIN" novar "a variable not set"} {
  set rc [catch {unpu_stage_numbers $tmp/$f.sdc syn20} msg]
  check "numbers: tampered SDC ($what) is an error" $rc $msg
}

# =============================================================================
# B. the DC script under stubs
# =============================================================================
# The scratch repo: rtl/, constraints/ (copies).
set root $tmp/repo
file mkdir $root/rtl $root/constraints
foreach f [glob -directory [file join $repo rtl] *.sv] { file copy $f $root/rtl/ }
foreach f {pm_dc_script_unpu.tcl pm_unpu_top.sdc stage_numbers.tcl} { file copy [file join $here $f] $root/constraints/ }

# options: a dict of knobs for the stubs
#   sdc_rc <v> (read_sdc return), clk_error 1 (get_clocks fails), period_add <x> (readback differs), attr_error 1,
#   skip_write <name> (the stub does not write this file), no_header 1 (echo writes nothing), extra_file <name>
#   (pre-existing file in the profile dir)
proc run_dc {stage opts} {
  global root
  set pwd0 [pwd]
  cd $root
  file delete -force $root/syn
  array set o {sdc_rc 1 clk_error 0 period_add 0 attr_error 0 skip_write {} no_header 0 extra_file {}}
  array set o $opts
  if {$o(extra_file) ne ""} { file mkdir $root/syn/out/$stage; close [open $root/syn/out/$stage/$o(extra_file) w] }
  set i [interp create]
  $i eval {
    set ::LOG {}
    set ::PUTS {}
    set ::PWDS {}
    rename puts ::tcl::puts_real
    proc puts {args} { if {[llength $args] >= 2 && [string match {file*} [lindex $args end-1]]} { ::tcl::puts_real {*}$args } else { lappend ::PUTS [lindex $args end] } }
    proc rec {name args} { lappend ::LOG [concat [list $name] $args] }
    proc exit {{code 0}} { error "UNPU_EXIT $code" }
    proc analyze {args} { rec analyze {*}$args; lappend ::PWDS [pwd]; set fh [open UNPU_[file rootname [file tail [lindex $args end]]].mr w]; close $fh
                          set fh [open unpu_[file rootname [file tail [lindex $args end]]]-verilog.pvl w]; close $fh }
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
    # redirecting report commands: "cmd ... >> file" appends a line to the file
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
  } 
  $i eval [list set ::SDC_RC $o(sdc_rc)]
  $i eval [list set ::CLK_ERROR $o(clk_error)]
  $i eval [list set ::ATTR_ERROR $o(attr_error)]
  $i eval [list set ::PERIOD_ADD $o(period_add)]
  $i eval [list set ::SKIP $o(skip_write)]
  $i eval [list set ::NO_HEADER $o(no_header)]
  global expT
  $i eval [list set ::PERIOD_REAL [expr {[info exists expT($stage)] ? $expT($stage) : 20.0}]]
  # write / write_sdc stubs: written file name given by -output / the last argument
  $i eval {
    proc write {args} {
      rec write {*}$args
      set k [lsearch -exact $args "-output"]
      set f [lindex $args [expr {$k + 1}]]
      if {[lsearch -exact $::SKIP [file tail $f]] >= 0} { return }
      set fh [open $f w]; ::tcl::puts_real $fh "written by write"; close $fh
    }
    proc write_sdc {args} {
      rec write_sdc {*}$args
      set f [lindex $args end]
      if {[lsearch -exact $::SKIP [file tail $f]] >= 0} { return }
      set fh [open $f w]; ::tcl::puts_real $fh "written by write_sdc"; close $fh
    }
  }
  if {$stage eq "<unset>"} { $i eval {catch {unset ::env(UNPU_STAGE)}} } else { $i eval [list set ::env(UNPU_STAGE) $stage] }
  set rc [catch {$i eval [list source $root/constraints/pm_dc_script_unpu.tcl]} msg]
  set log [$i eval {set ::LOG}]
  set pts [$i eval {set ::PUTS}]
  set pwds [$i eval {set ::PWDS}]
  interp delete $i
  set endpwd [pwd]
  cd $pwd0
  # exit code: the stub raises "UNPU_EXIT n"; a normal end of the script without exit is code "none"
  set code none
  if {$rc && [regexp {UNPU_EXIT (\d+)} $msg -> c]} { set code $c } elseif {$rc} { set code "tclerror: $msg" }
  return [list code $code log $log puts $pts pwds $pwds endpwd $endpwd]
}
proc cmds {log} { set r {}; foreach l $log { lappend r [lindex $l 0] }; return $r }

# ---- B1. a normal run, every profile ---------------------------------------------------------------------------------
set report_files {profile area power timing timing_top5 constraint qor check_timing check_design}
set other_files {unpu_top.dc.v unpu_top.sdc unpu_top_cn.dc.v unpu_top_cn.sdc unpu_top_cn.ddc}
foreach p $profiles {
  array unset R
  array set R [run_dc $p {}]
  check "run $p: ends with exit 0 (the script calls exit itself)" [expr {$R(code) eq "0"}] $R(code)
  set have [lsort [glob -nocomplain -directory $root/syn/out/$p -tails *]]
  set want {}
  foreach e $report_files { lappend want unpu_top.$e }
  set want [lsort [concat $want $other_files]]
  check "run $p: syn/out/$p holds exactly the 14 expected files" [expr {$have eq $want}] "$have"
  # headers
  set hdr_ok 1
  foreach e $report_files {
    set l [lindex [split [slurp $root/syn/out/$p/unpu_top.$e] "\n"] 0]
    set exp "# stage profile $p: period [format %s $expT($p)] ns, setup uncertainty $expSetup($expKind($p)) ns, hold uncertainty $expHold ns;"
    if {[string first $exp $l] != 0} { set hdr_ok 0; puts "  header of $e: '$l' expected prefix '$exp'" }
  }
  check "run $p: every report starts with the profile header carrying the profile's numbers" $hdr_ok
  # scratch files
  set rootfiles [lsort [glob -nocomplain -directory $root -tails *]]
  check "run $p: nothing in the repo root but rtl constraints syn" [expr {$rootfiles eq {constraints rtl syn}}] $rootfiles
  set wk [lsort [glob -nocomplain -directory $root/syn/out/work/$p -tails *]]
  check "run $p: the scratch files are in syn/out/work/$p" [expr {[lsearch -glob $wk UNPU_*.mr] >= 0 && [lsearch -glob $wk unpu_*-verilog.pvl] >= 0 && [lsearch -exact $wk default.svf] >= 0}] $wk
  check "run $p: syn/out holds only the profile directory and work" [expr {[lsort [glob -nocomplain -directory $root/syn/out -tails *]] eq [lsort [list $p work]]}] [glob -nocomplain -directory $root/syn/out -tails *]
  # analyze ran inside the scratch dir, with absolute paths that exist
  set apwd [lsort -unique $R(pwds)]
  check "run $p: analyze ran with the scratch directory as cwd" [expr {[llength $apwd] == 1 && [file normalize [lindex $apwd 0]] eq [file normalize $root/syn/out/work/$p]}] $apwd
  set abs_ok 1; set n_an 0
  foreach l $R(log) {
    if {[lindex $l 0] eq "analyze"} { incr n_an; set f [lindex $l end]; if {[file pathtype $f] ne "absolute" || ![file exists $f]} { set abs_ok 0 } }
  }
  check "run $p: 11 analyze calls with absolute, existing RTL paths" [expr {$n_an == 11 && $abs_ok}] "$n_an"
  # the order
  set c [cmds $R(log)]
  set ia [lsearch $c analyze]; set il [lsearch $c link]; set is [lsearch $c read_sdc]; set ic [lsearch $c compile]; set iw [lsearch $c write]
  check "run $p: order analyze < link < read_sdc < get_attribute < compile < write" [expr {$ia >= 0 && $ia < $il && $il < $is && $is < [lsearch $c get_attribute] && [lsearch $c get_attribute] < $ic && $ic < $iw}] $c
  check "run $p: read_sdc takes the absolute path of constraints/pm_unpu_top.sdc" [expr {[lindex [lindex $R(log) $is] end] eq "$root/constraints/pm_unpu_top.sdc"}]
  check "run $p: no Error: line is printed" [expr {[lsearch -glob $R(puts) "Error:*"] < 0}] [lsearch -all -inline -glob $R(puts) "Error:*"]
  check "run $p: the printed Info says DONE" [expr {[llength [lsearch -all -glob $R(puts) "Info: \\\[unpu\\\] DONE profile $p:*"]] == 1}]
  check "run $p: the readback says OK" [expr {[llength [lsearch -all -glob $R(puts) "*period read back from the tool: *OK"]] == 1}]
  check "run $p: the shell is left in the scratch directory (cd was used)" [expr {[file normalize $R(endpwd)] eq [file normalize $root/syn/out/work/$p]}]
}

# ---- B2. fatal guards: exit 1, before anything is analysed --------------------------------------------------------
proc expect_fatal {tag stage opts pattern {before_cmd analyze}} {
  global root
  array unset R
  array set R [run_dc $stage $opts]
  set c [cmds $R(log)]
  check "$tag: exit 1" [expr {$R(code) eq "1"}] $R(code)
  check "$tag: Error line mentions '$pattern'" [expr {[lsearch -glob $R(puts) "Error: unpu DC script: *$pattern*"] >= 0}] $R(puts)
  check "$tag: STOPPED line printed" [expr {[lsearch -glob $R(puts) "Error: unpu DC script: STOPPED with exit 1*"] >= 0}]
  check "$tag: '$before_cmd' and everything after it did not run" [expr {[lsearch $c $before_cmd] < 0}] $c
  check "$tag: compile did not run" [expr {[lsearch $c compile] < 0}] $c
  check "$tag: no output directory written" [expr {![file exists $root/syn/out/$stage] || [llength [glob -nocomplain -directory $root/syn/out/$stage *]] == 0 || $stage eq "x"}]
}
expect_fatal "UNPU_STAGE unset" <unset> {} "UNPU_STAGE is not set"
expect_fatal "UNPU_STAGE empty" "" {} "UNPU_STAGE is not set"
expect_fatal "UNPU_STAGE=syn17" syn17 {} "not a profile"
check "unset: the message lists the valid names" [expr {[lsearch -glob [dict get [run_dc <unset> {}] puts] "*syn20 syn18 syn16 place cts route signoff*"] >= 0}]
expect_fatal "read_sdc returns 0" syn20 {sdc_rc 0} "read_sdc" compile
expect_fatal "clock missing after read_sdc" syn20 {clk_error 1} "does not exist" compile
expect_fatal "period read back differs by 1 ns" syn16 {period_add 1.0} "tool holds clock period" compile

# attribute unreadable: Warning, not fatal, and the run completes
array unset R
array set R [run_dc syn18 {attr_error 1}]
check "get_attribute fails: a Warning, the run completes with exit 0" [expr {$R(code) eq "0" && [lsearch -glob $R(puts) "Warning: unpu DC script: cannot read the period*NOT done*"] >= 0}] "$R(code)"
check "get_attribute fails: the Warning is not an Error: line" [expr {[lsearch -glob $R(puts) "Error:*"] < 0}]

# the table section tampered: stops before analyze
file copy -force $tmp/nobegin.sdc $root/constraints/pm_unpu_top.sdc
expect_fatal "SDC without BEGIN marker" syn20 {} "cannot get the numbers of profile syn20"
file copy -force [file join $here pm_unpu_top.sdc] $root/constraints/pm_unpu_top.sdc

# a missing file of the repo / not run from the repo root
file rename $root/rtl/unpu_top.sv $root/rtl/unpu_top.sv.off
expect_fatal "not at the repo root (rtl/unpu_top.sv missing)" syn20 {} "rtl/unpu_top.sv not found"
file rename $root/rtl/unpu_top.sv.off $root/rtl/unpu_top.sv
file rename $root/constraints/stage_numbers.tcl $root/constraints/stage_numbers.off
expect_fatal "constraints/stage_numbers.tcl missing" syn20 {} "stage_numbers.tcl not found"
file rename $root/constraints/stage_numbers.off $root/constraints/stage_numbers.tcl

# ---- B3. the output check at the end: problems are Errors and exit 1 -------------------------------------------------
foreach {tag opts pattern} {
  "a stale extra file in the profile dir" {extra_file old_run.rpt} "unexpected file: old_run.rpt"
  "a netlist not written" {skip_write unpu_top_cn.dc.v} "missing: unpu_top_cn.dc.v"
  "the SDC not written" {skip_write unpu_top.sdc} "missing: unpu_top.sdc"
  "a report not written" {skip_write unpu_top.qor} "unpu_top.qor: nothing after the profile header"
  "no profile header" {no_header 1} "first line is not the profile header"
} {
  array unset R
  array set R [run_dc syn20 $opts]
  check "output check ($tag): exit 1" [expr {$R(code) eq "1"}] $R(code)
  check "output check ($tag): Error line '$pattern'" [expr {[lsearch -glob $R(puts) "Error: unpu DC script: output check: *$pattern*"] >= 0}] [lsearch -all -inline -glob $R(puts) "Error*"]
  check "output check ($tag): the run did compile first (this is the end-of-run check)" [expr {[lsearch [cmds $R(log)] compile] >= 0}]
}

# ---- B4. text checks on the script itself --------------------------------------------------------------------------
set dc [slurp [file join $here pm_dc_script_unpu.tcl]]
check "script: no 'error \"unpu DC script' left (every guard is unpu_fatal)" [expr {[string first {error "unpu DC script} $dc] < 0 || [regexp {return -code error "unpu DC script} $dc]}]
check "script: has a plain exit line before the disabled reports" [expr {[regexp {\nexit\n\n# More reports} $dc]}]
check "script: no RTL path relative to the cwd (rtl_dir is under repo_root)" [expr {[string first {set rtl_dir $repo_root/rtl} $dc] >= 0}]
check "script: the profile numbers are not read from variables that read_sdc leaves (no 'info exists \$v' loop)" [expr {[string first {foreach v {CLK_PERIOD CLK_UNCERT_SETUP CLK_UNCERT_HOLD}} $dc] < 0}]

file delete -force $tmp
puts ""
puts "test_dc_script: $npass passed, $nfail failed"
if {$nfail > 0} { puts "TESTS FAILED"; exit 1 }
puts "ALL TESTS PASSED"
exit 0
