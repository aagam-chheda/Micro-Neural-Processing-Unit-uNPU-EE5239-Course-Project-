# =============================================================================
# test_stages.tcl -- self-test of the stage-selectable SDC (task 051). Plain tclsh, no EDA tool:
#
#   cd <repo root> ; tclsh constraints/test_stages.tcl
#
# For each of the 7 stage profiles it sources constraints/unpu_top.sdc AND constraints/pm_unpu_top.sdc in a
# slave interpreter in which every SDC command is a stub that records its arguments, and checks, against numbers
# computed independently in THIS file (never read back from the SDC):
#   - the period, the setup and hold uncertainty, every input and output delay (max and min) in ns,
#   - the feedthrough budget, the printed "Info: [unpu] SDC profile ..." line,
#   - that an unset, empty or unknown UNPU_STAGE stops with a message that lists the valid names (both files),
#   - that the explicit port groups name every port of unpu_top (parsed from 
#     rtl/unpu_top.sv) exactly once; clk is in no group,
#   - that the twin pm_unpu_top.sdc has the same EFFECT as unpu_top.sdc: the final value of every constraint on every
#     port is compared (not the text), and the profile table section is byte-identical in both files,
#   - that the profile names of constraints/pm_dc_script_unpu.tcl are the profile names of the table.
# It ends with a printed table of all 7 profiles. Exit code 0 only if everything passed.
# =============================================================================

set here [file dirname [file normalize [info script]]]
set repo [file dirname $here]
set npass 0
set nfail 0
proc check {name ok {detail ""}} {
  global npass nfail
  if {$ok} { incr npass } else { incr nfail; puts "FAIL: $name  $detail" }
}
proc approx {a b} { return [expr {abs($a - $b) < 1e-9}] }
proc slurp {f} { set fh [open $f r]; set d [read $fh]; close $fh; return $d }

# ---- the ports of unpu_top, parsed from the RTL module header -------------------------------------------
set rtl [slurp [file join $repo rtl unpu_top.sv]]
regexp {module\s+unpu_top\s*\((.*?)\);} $rtl -> hdr
array set width {}
array set dir {}
set all_ports {}
set ports_in {}; set ports_out {}
foreach line [split $hdr "\n"] {
  if {[regexp {^\s*(input|output)\s+logic\s*(?:\[(\d+):0\])?\s*(\w+)} $line -> d hi n]} {
    set width($n) [expr {$hi eq "" ? 1 : $hi + 1}]
    set dir($n) $d
    lappend all_ports $n
  }
}
# expand a name list with [*] into scalar port names
proc expand_ports {patterns} {
  global width dir all_ports
  set out {}
  foreach p $patterns {
    if {[regexp {^(\w+)\[\*\]$} $p -> base]} {
      if {![info exists width($base)] || $width($base) < 2} { return -code error "pattern $p names no bus" }
      for {set i 0} {$i < $width($base)} {incr i} { lappend out "$base\[$i\]" }
    } else {
      if {![info exists width($p)]} { return -code error "port $p is not a port of unpu_top" }
      lappend out $p
    }
  }
  return $out
}
set in_names {}; set out_names {}
foreach n $all_ports {
  if {$width($n) == 1} { set names [list $n] } else { set names [expand_ports [list "$n\[*\]"]] }
  if {$dir($n) eq "input"} { set in_names [concat $in_names $names] } else { set out_names [concat $out_names $names] }
}
check "RTL parse: 102 input and 102 output bits (204 ports with clk)" [expr {[llength $in_names] == 102 && [llength $out_names] == 102}] "[llength $in_names] [llength $out_names]"

# ---- the expected numbers, typed independently of the SDC ------------------------------------------------------
# profile  T   kind
set profiles {
  {syn20   20.0 pre}
  {syn18   18.0 pre}
  {syn16   16.0 pre}
  {place   18.0 pre}
  {cts     18.0 post}
  {route   20.0 post}
  {signoff 20.0 post}
}
set exp_setup(pre) 1.2      ;# 0.20 jitter + 0.60 skew + 0.40 margin
set exp_setup(post) 0.6     ;# 0.20 jitter + 0.40 margin
set exp_hold 0.05
proc expected {T kind} {
  global exp_setup exp_hold
  return [list period $T setup $exp_setup($kind) hold $exp_hold \
      ft_in [expr {0.35 * $T}] ft_out [expr {0.35 * $T}] apb_in [expr {0.70 * $T}] dma_in [expr {0.70 * $T}] \
      dma_out [expr {0.70 * $T}] rst_in [expr {0.70 * $T}] in_min [expr {0.05 * $T}] out_min 0.0 \
      budget [expr {0.30 * $T - $exp_setup($kind)}]]
}
# spot values from the task text
array set e16 [expected 16.0 pre]
check "independent numbers: syn16 paddr 5.6, pwdata 11.2, input min 0.8, budget 3.6" [expr {[approx $e16(ft_in) 5.6] && [approx $e16(apb_in) 11.2] && [approx $e16(in_min) 0.8] && [approx $e16(budget) 3.6]}]
array set eroute [expected 20.0 post]
check "independent numbers: route 7.0 / 14.0 / min 1.0 / budget 5.4" [expr {[approx $eroute(ft_in) 7.0] && [approx $eroute(apb_in) 14.0] && [approx $eroute(in_min) 1.0] && [approx $eroute(budget) 5.4]}]

# ---- running an SDC under a stub ---------------------------------------------------------------------------------
# returns {status log infolines message}: status ok | error
proc run_sdc {file stage} {
  set i [interp create]
  $i eval {
    set ::LOG {}
    set ::PUTS {}
    proc get_ports {args} { return [list PORTS [lindex $args 0]] }
    proc get_clocks {args} { return [list CLOCK [lindex $args 0]] }
    proc all_inputs {} { return ALL_INPUTS }
    proc all_outputs {} { return ALL_OUTPUTS }
    proc current_design {args} { return DESIGN }
    proc puts {args} { lappend ::PUTS [lindex $args end] }
    proc unknown {args} { lappend ::LOG $args; return "" }
  }
  if {$stage eq "<unset>"} { $i eval {catch {unset ::env(UNPU_STAGE)}} } else { $i eval [list set ::env(UNPU_STAGE) $stage] }
  set rc [catch {$i eval [list source $file]} msg]
  set log [$i eval {set ::LOG}]
  set pts [$i eval {set ::PUTS}]
  interp delete $i
  return [list [expr {$rc ? "error" : "ok"}] $log $pts $msg]
}
# the final (last-wins) effect of a command log on every port, as an array: key -> value
proc effect {log} {
  global in_names out_names all_ports
  array set eff {}
  foreach c $log {
    set cmd [lindex $c 0]
    set a [lrange $c 1 end]
    switch -- $cmd {
      create_clock { set eff(clock_period) [lindex $a [expr {[lsearch -exact $a -period] + 1}]] }
      set_clock_uncertainty {
        if {[lsearch -exact $a -setup] >= 0} { set eff(unc_setup) [lindex $a [expr {[lsearch -exact $a -setup] + 1}]] }
        if {[lsearch -exact $a -hold] >= 0} { set eff(unc_hold) [lindex $a [expr {[lsearch -exact $a -hold] + 1}]] }
      }
      set_clock_transition { set eff(clock_transition) [lindex $a 0] }
      set_input_delay - set_output_delay {
        set kind [expr {$cmd eq "set_input_delay" ? "in" : "out"}]
        set val ""; set tgt ""; set mx 0; set mn 0
        for {set k 0} {$k < [llength $a]} {incr k} {
          set x [lindex $a $k]
          if {$x eq "-clock"} { incr k; continue }
          if {$x eq "-max"} { set mx 1; continue }
          if {$x eq "-min"} { set mn 1; continue }
          if {$val eq "" && [string is double -strict $x]} { set val $x; continue }
          set tgt $x
        }
        set tgt_ports [target_ports $tgt]
        foreach p $tgt_ports {
          if {$mx || !$mn} { set eff(delay_${kind}_max_$p) $val }
          if {$mn || !$mx} { set eff(delay_${kind}_min_$p) $val }
        }
      }
      set_driving_cell {
        set cell [lindex $a [expr {[lsearch -exact $a -lib_cell] + 1}]]; set pin [lindex $a [expr {[lsearch -exact $a -pin] + 1}]]
        foreach p [target_ports [lindex $a end]] { set eff(drive_$p) "$cell/$pin" }
      }
      set_load { foreach p [target_ports [lindex $a end]] { set eff(load_$p) [lindex $a 0] } }
      set_max_transition { set eff(max_transition) [lindex $a 0] }
      set_max_capacitance { set eff(max_capacitance) [lindex $a 0] }
    }
  }
  return [array get eff]
}
proc target_ports {tgt} {
  global in_names out_names
  if {$tgt eq "ALL_INPUTS"} { return $in_names }
  if {$tgt eq "ALL_OUTPUTS"} { return $out_names }
  if {[lindex $tgt 0] eq "PORTS"} { return [expand_ports [lindex $tgt 1]] }
  return {}
}

# ---- per profile ---------------------------------------------------------------------------------------------------
set files [list [file join $here unpu_top.sdc] [file join $here pm_unpu_top.sdc]]
set rows {}
foreach pr $profiles {
  lassign $pr name T kind
  array unset e; array set e [expected $T $kind]
  array unset eff_f
  foreach f $files {
    set tag [file tail $f]
    lassign [run_sdc $f $name] st log pts msg
    check "$tag $name: reads without error" [expr {$st eq "ok"}] $msg
    if {$st ne "ok"} continue
    array unset eff; array set eff [effect $log]
    set eff_f($tag) [array get eff]
    check "$tag $name: clock period $T" [approx $eff(clock_period) $T] $eff(clock_period)
    check "$tag $name: setup uncertainty $e(setup)" [approx $eff(unc_setup) $e(setup)] $eff(unc_setup)
    check "$tag $name: hold uncertainty $e(hold)" [approx $eff(unc_hold) $e(hold)] $eff(unc_hold)
    check "$tag $name: clock transition 0.6 (unchanged)" [approx $eff(clock_transition) 0.6]
    # every delay, port by port
    set bad {}
    foreach {grp ports mxv mnv} [list \
        ft_in {paddr} $e(ft_in) $e(in_min)  apb_in {pwdata pwrite psel penable} $e(apb_in) $e(in_min) \
        dma_in {dma_rdata dma_ready} $e(dma_in) $e(in_min)  rst_in {rst_n} $e(rst_in) $e(in_min)] {
      foreach b $ports {
        foreach p [expr {$width($b) > 1 ? [expand_ports [list "$b\[*\]"]] : [list $b]}] {
          if {![info exists eff(delay_in_max_$p)] || ![approx $eff(delay_in_max_$p) $mxv]} { lappend bad "in max $p" }
          if {![info exists eff(delay_in_min_$p)] || ![approx $eff(delay_in_min_$p) $mnv]} { lappend bad "in min $p" }
        }
      }
    }
    foreach {grp ports mxv mnv} [list \
        ft_out {prdata pready} $e(ft_out) $e(out_min)  dma_out {dma_addr dma_wdata dma_wstrb dma_valid} $e(dma_out) $e(out_min)] {
      foreach b $ports {
        foreach p [expr {$width($b) > 1 ? [expand_ports [list "$b\[*\]"]] : [list $b]}] {
          if {![info exists eff(delay_out_max_$p)] || ![approx $eff(delay_out_max_$p) $mxv]} { lappend bad "out max $p" }
          if {![info exists eff(delay_out_min_$p)] || ![approx $eff(delay_out_min_$p) $mnv]} { lappend bad "out min $p" }
        }
      }
    }
    check "$tag $name: every input and output delay (max and min) of every data port" [expr {[llength $bad] == 0}] "wrong: [lrange $bad 0 5]"
    # boundary values unchanged
    set okb [expr {$eff(max_transition) == 3.0 && $eff(max_capacitance) == 2.0 && $eff(drive_pwdata\[0\]) eq "buffd1/Z" && $eff(drive_paddr\[0\]) eq "buffd1/Z" && [approx $eff(load_paddr\[0\]) 0.2] && [approx $eff(load_prdata\[0\]) 1.0] && [approx $eff(load_dma_addr\[0\]) 1.0] && [approx $eff(load_rst_n) 0.2]}]
    check "$tag $name: driving cell buffd1/Z, 0.2 pF input load (paddr included), 1 pF output load, max transition 3.0, max capacitance 2.0" $okb
    # the Info line
    set info {}
    foreach l $pts { if {[string first "Info: \[unpu\] SDC profile" $l] == 0} { lappend info $l } }
    set want [format "Info: \[unpu\] SDC profile %s: period %s ns, setup uncertainty %s ns, hold uncertainty %s ns, feedthrough budget %s ns" $name $T $e(setup) $e(hold) [expr {double(round($e(budget) * 1e6)) / 1e6}]]
    check "$tag $name: prints exactly one profile line" [expr {[llength $info] == 1}] [llength $info]
    if {[llength $info] == 1} {
      regexp {budget ([0-9.]+) ns} [lindex $info 0] -> b
      check "$tag $name: the printed profile line has the expected period, uncertainties and budget" [expr {[string first "SDC profile $name: period $T ns, setup uncertainty $e(setup) ns, hold uncertainty $e(hold) ns" [lindex $info 0]] >= 0 && [approx $b $e(budget)]}] [lindex $info 0]
    }
  }
  # the twin has the same effect as the main file on every port except the clk port (the PM's zero input delay on all_inputs)
  if {[info exists eff_f(unpu_top.sdc)] && [info exists eff_f(pm_unpu_top.sdc)]} {
    array unset m; array set m $eff_f(unpu_top.sdc)
    array unset t; array set t $eff_f(pm_unpu_top.sdc)
    set diffs {}
    foreach k [lsort -unique [concat [array names m] [array names t]]] {
      if {![info exists m($k)] || ![info exists t($k)] || $m($k) ne $t($k)} { lappend diffs $k }
    }
    set only_clk [expr {[llength $diffs] == 0}]
    set diffs_nonclk {}
    foreach k $diffs { if {![string match "delay_in_*_clk" $k]} { lappend diffs_nonclk $k } }
    check "twin $name: same final effect on every constraint (only the PM's zero input delay on the clk port itself may remain)" [expr {[llength $diffs_nonclk] == 0}] "differ: [lrange $diffs_nonclk 0 5]"
    check "twin $name: the clk-port difference is exactly the PM's zero input delay" [expr {[llength [lsearch -all -inline -glob $diffs delay_in_*_clk]] == [llength $diffs]}] $diffs
  }
  lappend rows [list $name $T $kind $e(setup) $e(hold) $e(ft_in) $e(ft_out) $e(apb_in) $e(dma_out) $e(rst_in) $e(in_min) $e(budget)]
}

# ---- an unset, empty or unknown profile stops, and says which names are valid --------------------------------
foreach f $files {
  set tag [file tail $f]
  foreach bad [list <unset> "" syn17 SYN16 route2] {
    lassign [run_sdc $f $bad] st log pts msg
    set listed 1
    foreach n {syn20 syn18 syn16 place cts route signoff} { if {[string first $n $msg] < 0} { set listed 0 } }
    check "$tag: UNPU_STAGE '$bad' stops with the valid names" [expr {$st eq "error" && $listed && [string first UNPU_STAGE $msg] >= 0}] "$st: $msg"
    check "$tag: UNPU_STAGE '$bad' records no constraint after the error" [expr {[llength [lsearch -all -inline -glob $log create_clock*]] == ([string match *pm_unpu* $f] ? 1 : 0)}] "[llength $log] commands"
  }
}

# ---- the explicit port groups name every port exactly once; clk is in no group ---------------------------------------
foreach f $files {
  set tag [file tail $f]
  lassign [run_sdc $f route] st log pts msg
  set seen {}
  foreach c $log {
    if {[lindex $c 0] in {set_input_delay set_output_delay} && [lsearch -exact $c -max] >= 0} { lappend seen [lindex $c end] }
  }
  set cover {}
  foreach tg $seen { if {[lindex $tg 0] eq "PORTS"} { set cover [concat $cover [expand_ports [lindex $tg 1]]] } }
  set cover_sorted [lsort $cover]
  set want [lsort [concat [lsearch -all -inline -exact -not $in_names clk] $out_names]]
  # (clk is not a bit of any name in in_names above except the port 'clk' itself)
  check "$tag: the max-delay port groups name every port once (101 inputs without clk + 102 outputs)" [expr {$cover_sorted eq $want && [llength $cover] == [llength [lsort -unique $cover]]}] "[llength $cover] named, [llength $want] expected"
  check "$tag: clk is in no group" [expr {[lsearch -exact $cover clk] < 0}]
}

# ---- the twin's profile section is a byte-identical copy; the DC script knows the same profile names --------------
proc section {text} {
  set a [string first "# ==== BEGIN STAGE PROFILE TABLE" $text]
  set b [string first "# ==== END STAGE PROFILE TABLE" $text]
  if {$a < 0 || $b < 0} { return "" }
  return [string range $text $a [expr {$b + 200}]]
}
set s1 [section [slurp [lindex $files 0]]]
set s2 [section [slurp [lindex $files 1]]]
check "the profile table section is byte-identical in unpu_top.sdc and pm_unpu_top.sdc" [expr {$s1 ne "" && $s1 eq $s2}]
set dc [slurp [file join $here pm_dc_script_unpu.tcl]]
regexp {set stage_names \{([^\}]*)\}} $dc -> dcnames
set tnames {}
foreach pr $profiles { lappend tnames [lindex $pr 0] }
check "pm_dc_script_unpu.tcl lists the same profile names as the table" [expr {$dcnames eq $tnames}] "$dcnames"
set sdc_names {}
regexp {set UNPU_STAGE_TABLE \{(.*?)\n\}} [slurp [lindex $files 0]] -> tbl
foreach l [split $tbl "\n"] { if {[regexp {^\s*\{(\w+)\s} $l -> n]} { lappend sdc_names $n } }
check "the SDC table names are the 7 expected names, in order" [expr {$sdc_names eq $tnames}] $sdc_names
check "the DC script requires UNPU_STAGE and writes to syn/out/\$UNPU_STAGE" [expr {[string first {set rpt_dir syn/out/$UNPU_STAGE} $dc] >= 0 && [string first {pm_flow} $dc] < 0}]

# ---- the printed table ------------------------------------------------------------------------------------------------
puts ""
puts "Stage profiles (delays in ns = percentage of the stage's period; max, except 'in min')"
puts [format "%-8s %5s %-5s %6s %6s | %7s %8s %8s %8s %8s %7s | %7s" profile T kind setup hold "paddr" "prdata" "pwdata" "dma_out" "rst_n" "in min" budget]
puts [string repeat - 100]
foreach r $rows {
  lassign $r name T kind su hu fti fto api dmo rsti inm bud
  puts [format "%-8s %5.1f %-5s %6.2f %6.2f | %7.2f %8.2f %8.2f %8.2f %8.2f %7.2f | %7.2f" $name $T $kind $su $hu $fti $fto $api $dmo $rsti $inm $bud]
}
puts "(paddr max = prdata/pready max = 35% T, the feedthrough row; pwdata pwrite psel penable dma_* rst_n max = 70% T;"
puts " input min = 5% T, output min = 0; budget = T*(1-0.35-0.35) - setup uncertainty, the feedthrough path paddr -> prdata)"
puts ""
puts "test_stages: $npass passed, $nfail failed"
if {$nfail > 0} { puts "TESTS FAILED"; exit 1 }
puts "ALL TESTS PASSED"
exit 0
