# ==============================================================================
# File  : pnr_v2/opt_uncertainty.tcl   (task 090: optimisation-only clock-uncertainty margin, scoped, restored with a proof)
# Used by: cts.tcl, route.tcl, timing_closure.tcl (open: unc090_params + unc090_open_opt before the optimiser; close: unc090_close_opt after it), pv.tcl (unc090_export_check)
# WHY   : ICC2's parasitic estimate and PrimeTime's SPEF differ by tens of picoseconds. Optimising to a slightly stricter target (SPEC + goal) leaves the sign-off slack positive.
#         It is NOT a change of the constraint: the SPEC values (setup 1.5, hold 0.5), the exported SDC and the sign-off stay as they are (user decision 2026-11-10, task 090).
# TRAP  : a clock-wide uncertainty also applies to the input-to-output group (paddr -> prdata): its budget is 20 - 1.5 - 7 - 7 with about ZERO margin in both tools. A clock-wide x makes ICC2 see
#         the group x worse in setup AND hold; the hold part adds delay and breaks the setup part (the break of 2026-11-09, -0.59 ns). So the margin must NOT reach endpoints at output ports.
# SCOPE : UNPU_UNC_SCOPE
#   flops   (DEFAULT) clock-level stays SPEC; the OPT value (SPEC + goal) is set on the CLOCK PINS of the edge-triggered registers. A pin-level value REPLACES the clock-level one for the paths
#           ending at that pin, so the ABSOLUTE value SPEC + goal is set. An endpoint at an output port keeps the SPEC value.
#   outputs clock-level = OPT (the form clock_opt / route_opt handle everywhere), and the SPEC value is pinned on the OUTPUT PORTS (replaces the clock-level value for paths ending there).
#   clock   today's form: the OPT value on the clock; reaches the output ports too. For comparison only.
# GOALS : setup goal in func_ss only, hold goal in func_ff only (as the code did before). Goal 0 for a kind: nothing is set at pin level for that kind (clock-level stays SPEC).
# PROOF : after the optimiser, the pin/port-level values are removed and the SDC of every scenario is written (write_sdc -include clock_uncertainty) and read: the pin/port-level lines left must be
#         0 and the clock-level lines must carry the SPEC value (ERROR 090 otherwise). pv.tcl checks the exported SDC files the same way.
# PROBES: with the pin/port-level value set and removed, ONE known path's slack is reported (flops: dma_rdata[14] -> u_dma/stage_reg_1__14_/D setup and hold; outputs: dma_addr[31] setup, prdata[0] hold).
#         The slack must move by the goal; if it does not, ICC2 ignored the value (WARNING). This makes the VERIFY items self-checking on the server. UNPU_UNC_PROBE 0 switches them off.
# Pure parts (parameters, SDC parsing, decisions) are between BEGIN/END PURE TCL 090 and tested with tclsh in pnr_v2/test_opt_uncertainty.tcl.
# Every ICC2 command or option not shown in a usage text in ~/server_pull/rpt/help is marked VERIFY.
# ==============================================================================

# the SPEC values (course constraints, constraints/unpu_top.sdc profile cts/route: setup 1.5 ns, hold 0.5 ns). cts.tcl / route.tcl / timing_closure.tcl type the same numbers; unc090_params
# compares them with these and stops (ERROR 090) if they differ, so the three copies cannot drift apart silently.
set UNC090_SPEC_SETUP 1.5
set UNC090_SPEC_HOLD  0.5
# the defaults of the goals (task 090, starting values for the user's confirmation; reasons): hold needs the larger one because the sign-off failures of run 1 were hold (263 PrimeTime hold
# violators on input-to-register / register-to-register paths); setup register-to-register has about zero margin already, so only a small one. Override: environment, no file edit.
set UNC090_DEF_SETUP_GOAL 0.05
set UNC090_DEF_HOLD_GOAL  0.10
set UNC090_DEF_SCOPE      flops
set UNC090_SETUP_SCEN func_ss   ;# the scenarios of cts.tcl / route.tcl: setup is checked in func_ss, hold in func_ff; unc090_scen_check stops if one is not in the design
set UNC090_HOLD_SCEN  func_ff
set UNC090_TOL        0.005     ;# ns: tolerance of the in2out warning and of the probe verdict (same value and reason as the other gates: a few ps are estimation noise)
set UNC090_PROBE_IN_PORT       "dma_rdata\[14\]"             ;# the in2reg probe (task 090): the 084 example input ...
set UNC090_PROBE_IN_PIN        "u_dma/stage_reg_1__14_/D"    ;# ... and its endpoint
set UNC090_PROBE_OUT_SETUP_PORT "dma_addr\[31\]"             ;# the outputs-form probes
set UNC090_PROBE_OUT_HOLD_PORT  "prdata\[0\]"
set UNC090_LAST_IN2OUT {}       ;# {setup hold} measured by unc090_open_opt, read by unc090_close_opt

# ---- BEGIN PURE TCL 090 ----
proc unc090_isnum {v} { return [regexp {^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$} $v] }

# unc090_resolve <variable> <default> <kind> <envlist> -> {value source}; envlist is {} when the variable is not set, {value} when it is (an empty value is an error, never "unset")
#   kind goal  : a number 0 <= v <= 1.0     kind scope : flops | outputs | clock     kind flag : 0 | 1
proc unc090_resolve {name default kind envl} {
    if {[llength $envl] == 0} { return [list $default default] }
    set v [string trim [lindex $envl 0]]
    switch -- $kind {
        goal {
            if {![unc090_isnum $v]} { error "ERROR 090: $name='$v' is not a number (0 <= value <= 1.0 ns)" }
            if {$v < 0 || $v > 1.0} { error "ERROR 090: $name='$v' is outside 0 .. 1.0 ns" }
        }
        scope {
            if {[lsearch -exact {flops outputs clock} $v] < 0} { error "ERROR 090: $name='$v' is not valid: flops, outputs or clock" }
        }
        flag {
            if {$v ne "0" && $v ne "1"} { error "ERROR 090: $name='$v' is not valid: 0 or 1" }
        }
        default { error "ERROR 090: unc090_resolve: unknown kind '$kind'" }
    }
    return [list $v "environment $name"]
}

# unc090_params_line -> the printed parameters line
proc unc090_params_line {scope scope_src gs gs_src gh gh_src probe probe_src spec_s spec_h} {
    return ">>> 090 parameters: scope $scope ($scope_src), setup goal $gs ns ($gs_src), hold goal $gh ns ($gh_src), probes $probe ($probe_src); SPEC setup $spec_s / hold $spec_h; optimiser targets setup [expr {$spec_s + $gs}] (func_ss) and hold [expr {$spec_h + $gh}] (func_ff)"
}

# unc090_split_objects <sdc line> -> {objects rest}: every [ ... ] group (bracket-aware: brackets inside braces, e.g. port names a[3], are names) and the line without them; {ERROR text} when unbalanced
proc unc090_split_objects {t} {
    set objs {}; set rest ""
    set n [string length $t]; set i 0
    while {$i < $n} {
        set c [string index $t $i]
        if {$c ne "\["} { append rest $c; incr i; continue }
        set depth 0; set bd 0; set j [expr {$i + 1}]; set closed 0
        while {$j < $n} {
            set d [string index $t $j]
            if {$d eq "\x7b"} { incr bd } elseif {$d eq "\x7d"} { incr bd -1 } elseif {$bd == 0} {
                if {$d eq "\["} { incr depth } elseif {$d eq "\]"} { if {$depth == 0} { set closed 1; break }; incr depth -1 }
            }
            incr j
        }
        if {!$closed} { return [list ERROR "unbalanced bracket in: $t"] }
        lappend objs [string trim [string range $t [expr {$i + 1}] [expr {$j - 1}]]]
        append rest " "
        set i [expr {$j + 1}]
    }
    return [list $objs $rest]
}

# unc090_parse <sdc text> -> list of dicts {line type value level nnames} for every set_clock_uncertainty line
#   type setup|hold|both; level clock (objects are clocks only) | interclock (-from/-to) | pin (pins, ports or cells: nnames = how many names) | other (anything else, never a pass)
proc unc090_parse {text} {
    set o {}
    set text [string map [list "\\\n" " "] $text]
    foreach l [split $text "\n"] {
        set t [string trim $l]
        if {![regexp {^set_clock_uncertainty(\s|$)} $t]} continue
        set sp [unc090_split_objects $t]
        if {[lindex $sp 0] eq "ERROR"} { lappend o [dict create line $t type both value "" level other nnames 0]; continue }
        lassign $sp objs rest
        set cmds {}; set nn 0
        foreach ob $objs {
            regexp {^(\S+)\s*(.*)$} $ob -> cmd args
            lappend cmds $cmd
            foreach nm [split [string map [list "\x7b" " " "\x7d" " " "\"" " "] $args] " \t"] {
                if {$nm ne "" && [string index $nm 0] ne "-"} { incr nn }
            }
        }
        set isset 0; set ishold 0; set inter 0; set value ""
        foreach tk [split $rest " \t"] {
            if {$tk eq ""} continue
            if {$value eq "" && [unc090_isnum $tk]} { set value $tk; continue }
            switch -- $tk {
                -setup { set isset 1 }
                -hold  { set ishold 1 }
                -from - -to - -rise_from - -fall_from - -rise_to - -fall_to { set inter 1 }
            }
        }
        set type both
        if {$isset && !$ishold} { set type setup } elseif {$ishold && !$isset} { set type hold }
        set level other
        if {[llength $cmds] > 0} {
            set allclk 1; set anypin 0
            foreach c $cmds {
                if {$c ne "get_clocks"} { set allclk 0 }
                if {$c eq "get_pins" || $c eq "get_ports" || $c eq "get_cells"} { set anypin 1 }
            }
            if {$anypin} { set level pin } elseif {$allclk} { set level [expr {$inter ? "interclock" : "clock"}] }
        }
        lappend o [dict create line $t type $type value $value level $level nnames $nn]
    }
    return $o
}

# unc090_pin_left <parsed> -> {lines names}: the pin/port-level lines and the number of names in them (and the lines of level other count as lines with 0 names)
proc unc090_pin_left {parsed} {
    set nl 0; set nn 0
    foreach e $parsed { if {[dict get $e level] eq "pin" || [dict get $e level] eq "other"} { incr nl; incr nn [dict get $e nnames] } }
    return [list $nl $nn]
}

# unc090_same <a> <b> -> 1 when both are numbers and equal within 1e-9
proc unc090_same {a b} { return [expr {[unc090_isnum $a] && [unc090_isnum $b] && abs($a - $b) < 1e-9}] }

# unc090_export_problems <parsed> <spec setup> <spec hold> -> list of problem texts (empty = ok): pv.tcl check of an exported SDC
proc unc090_export_problems {parsed spec_s spec_h} {
    set p {}
    foreach e $parsed {
        set ln [dict get $e line]; set lv [dict get $e level]; set v [dict get $e value]; set ty [dict get $e type]
        if {$lv eq "pin"} { lappend p "names pins/ports/cells instead of the clock: $ln"; continue }
        if {$lv eq "other"} { lappend p "cannot be read as a clock-level line: $ln"; continue }
        if {![unc090_isnum $v]} { lappend p "no numeric value: $ln"; continue }
        if {($ty eq "setup" || $ty eq "both") && ![unc090_same $v $spec_s]} { lappend p "setup value $v differs from SPEC $spec_s: $ln" }
        if {($ty eq "hold"  || $ty eq "both") && ![unc090_same $v $spec_h]} { lappend p "hold value $v differs from SPEC $spec_h: $ln" }
    }
    return $p
}

# unc090_apply_check <parsed> <scope> <kind setup|hold> <spec> <opt> <goal> -> {problems matched_names}: what the SDC of the scenario must show right after the OPT values were set
#   clock: clock-level lines of the kind carry OPT, no pin-level line of the kind;  flops: clock-level SPEC and pin-level lines of the kind with OPT (names counted);
#   outputs: clock-level OPT and pin-level lines of the kind with SPEC (names counted). Goal 0: clock-level SPEC and nothing at pin level.
proc unc090_apply_check {parsed scope kind spec opt goal} {
    set p {}; set matched 0; set nclk 0; set npin 0
    set want_clk $spec
    if {$goal != 0 && ($scope eq "clock" || $scope eq "outputs")} { set want_clk $opt }
    set want_pin ""
    if {$goal != 0 && $scope eq "flops"}   { set want_pin $opt }
    if {$goal != 0 && $scope eq "outputs"} { set want_pin $spec }
    foreach e $parsed {
        set ty [dict get $e type]
        if {$ty ne $kind && $ty ne "both"} continue
        set lv [dict get $e level]; set v [dict get $e value]
        if {$lv eq "clock"} {
            incr nclk
            if {![unc090_same $v $want_clk]} { lappend p "clock-level $kind value $v, expected $want_clk: [dict get $e line]" }
        } elseif {$lv eq "pin"} {
            incr npin
            if {$want_pin eq ""} { lappend p "unexpected pin/port-level $kind line: [dict get $e line]" } elseif {[unc090_same $v $want_pin]} { incr matched [dict get $e nnames] } else { lappend p "pin/port-level $kind value $v, expected $want_pin: [dict get $e line]" }
        } elseif {$lv eq "other"} { lappend p "unreadable line: [dict get $e line]" }
    }
    if {$nclk == 0} { lappend p "no clock-level $kind line in the SDC of the scenario" }
    if {$want_pin ne "" && $matched == 0} { lappend p "no pin/port-level $kind line with $want_pin: the value was not set (or write_sdc does not show it)" }
    return [list $p $matched]
}

# unc090_restore_problems <parsed> <kind> <spec> -> problems: after the restore no pin/port-level line may be left (any kind) and the clock-level lines of the kind carry SPEC
proc unc090_restore_problems {parsed kind spec} {
    set p {}
    lassign [unc090_pin_left $parsed] nl nn
    if {$nl > 0} { lappend p "$nl pin/port-level line(s) with $nn name(s) are still there" }
    set nclk 0
    foreach e $parsed {
        set ty [dict get $e type]
        if {[dict get $e level] eq "clock" && ($ty eq $kind || $ty eq "both")} {
            incr nclk
            if {![unc090_same [dict get $e value] $spec]} { lappend p "clock-level $kind value [dict get $e value], expected SPEC $spec: [dict get $e line]" }
        }
    }
    if {$nclk == 0} { lappend p "no clock-level $kind line in the SDC of the scenario" }
    return $p
}

# unc090_in2out_cmp <what> <before> <after> <tol> -> "" or the WARNING text (the margin made the group worse by more than tol); n/a is told, never passed silently
proc unc090_in2out_cmp {what before after tol} {
    if {![unc090_isnum $before] || ![unc090_isnum $after]} { return ">>> 090 WARNING: in2out $what could not be compared (before '$before', after '$after')" }
    if {$after < $before - $tol} { return ">>> 090 WARNING: the margin made the in2out group worse: $what WNS before $before ns, after $after ns (tolerance $tol ns)" }
    return ""
}

# unc090_probe_verdict <name> <slack with the value set> <slack with it removed> <expected set-minus-removed> <tol> -> {status text}; status ok | same | off | na
proc unc090_probe_verdict {name s1 s2 expected tol} {
    if {![unc090_isnum $s1] || ![unc090_isnum $s2]} { return [list na ">>> 090 WARNING: probe $name: no slack could be read (set '$s1', removed '$s2'); the VERIFY items of this form are not checked"] }
    set d [expr {$s1 - $s2}]
    set dtxt [format %.4f $d]
    if {abs($d) < $tol/10.0 && abs($expected) > $tol} { return [list same ">>> 090 WARNING: probe $name: slack with the value set $s1, removed $s2: the SAME. ICC2 ignored the pin/port-level value (expected a change of $expected ns)"] }
    if {abs($d - $expected) <= $tol} { return [list ok ">>> 090 probe $name: slack set $s1, removed $s2, change $dtxt ns (expected $expected): the value acts"] }
    return [list off ">>> 090 WARNING: probe $name: slack set $s1, removed $s2, change $dtxt ns, expected $expected ns (tolerance $tol)"]
}

# unc090_scen_missing <scenarios the design has> <scenarios wanted> -> the wanted ones that are missing
proc unc090_scen_missing {have wanted} {
    set m {}
    foreach w $wanted { if {[lsearch -exact $have $w] < 0} { lappend m $w } }
    return $m
}
# ---- END PURE TCL 090 ----

# ------------------------------------------------------------------------------
# ICC2 side
# ------------------------------------------------------------------------------
# unc090_params <spec setup> <spec hold> -> {setup goal, hold goal, scope, probe flag}: environment overrides UNPU_SETUP_SLACK_GOAL, UNPU_HOLD_SLACK_GOAL, UNPU_UNC_SCOPE, UNPU_UNC_PROBE
proc unc090_params {spec_s spec_h} {
    global UNC090_SPEC_SETUP UNC090_SPEC_HOLD UNC090_DEF_SETUP_GOAL UNC090_DEF_HOLD_GOAL UNC090_DEF_SCOPE
    if {![unc090_same $spec_s $UNC090_SPEC_SETUP] || ![unc090_same $spec_h $UNC090_SPEC_HOLD]} {
        error "ERROR 090: the SPEC values of the script (setup $spec_s, hold $spec_h) differ from opt_uncertainty.tcl (setup $UNC090_SPEC_SETUP, hold $UNC090_SPEC_HOLD)"
    }
    set r {}
    foreach {var def kind} [list UNPU_SETUP_SLACK_GOAL $UNC090_DEF_SETUP_GOAL goal UNPU_HOLD_SLACK_GOAL $UNC090_DEF_HOLD_GOAL goal UNPU_UNC_SCOPE $UNC090_DEF_SCOPE scope UNPU_UNC_PROBE 1 flag] {
        set envl {}
        if {[info exists ::env($var)]} { set envl [list $::env($var)] }
        lappend r [unc090_resolve $var $def $kind $envl]
    }
    lassign $r gs gh sc pr
    puts [unc090_params_line [lindex $sc 0] [lindex $sc 1] [lindex $gs 0] [lindex $gs 1] [lindex $gh 0] [lindex $gh 1] [lindex $pr 0] [lindex $pr 1] $spec_s $spec_h]
    return [list [lindex $gs 0] [lindex $gh 0] [lindex $sc 0] [lindex $pr 0]]
}

proc unc090_scen_check {} {
    global UNC090_SETUP_SCEN UNC090_HOLD_SCEN
    set have {}
    foreach_in_collection s [get_scenarios] { lappend have [get_object_name $s] }
    set m [unc090_scen_missing $have [list $UNC090_SETUP_SCEN $UNC090_HOLD_SCEN]]
    if {[llength $m] > 0} { error "ERROR 090: scenario(s) $m not in the design (scenarios: $have)" }
}

# the scratch SDC of one scenario, parsed
proc unc090_scan {scen label} {
    global RUN_ROOT
    set dir ${RUN_ROOT}/pnr_icc2/diag
    file mkdir $dir
    set f ${dir}/uncertainty_[string map {/ _ : _ { } _} $label]_${scen}.sdc
    file delete -force $f
    if {[catch {write_sdc -scenario $scen -include clock_uncertainty -nosplit -output $f} err]} { error "ERROR 090: write_sdc of scenario $scen failed: $err" }   ;# [L] write_sdc -scenario / -include clock_uncertainty / -nosplit / -output
    if {![file exists $f]} { error "ERROR 090: write_sdc of scenario $scen wrote no file ($f)" }
    set fp [open $f r]; set tx [read $fp]; close $fp
    return [unc090_parse $tx]
}

# the clock pins of the edge-triggered registers -> {pins nregs how}; ERROR 090 when none are found
proc unc090_flop_pins {} {
    set regs [all_registers -edge_triggered]   ;# VERIFY all_registers -edge_triggered
    set nregs [sizeof_collection $regs]
    if {$nregs == 0} { error "ERROR 090: all_registers -edge_triggered returned no register" }
    set pins ""; set how ""
    if {![catch {all_registers -edge_triggered -clock_pins} p1] && [sizeof_collection $p1] > 0} { set pins $p1; set how "all_registers -edge_triggered -clock_pins" }   ;# VERIFY -clock_pins together with -edge_triggered
    if {$how eq ""} {
        set p2 [get_pins -quiet -of_objects $regs -filter "is_clock_pin == true"]   ;# VERIFY get_pins -of_objects <cells> and the pin attribute is_clock_pin
        if {[sizeof_collection $p2] > 0} { set pins $p2; set how "get_pins -of_objects <registers> -filter is_clock_pin" }
    }
    if {$how eq ""} { error "ERROR 090: found $nregs edge-triggered registers but no clock pin (tried all_registers -clock_pins and get_pins -filter is_clock_pin == true); scope flops cannot be used, UNPU_UNC_SCOPE outputs or clock is the way out" }
    return [list $pins $nregs $how]
}

# the objects that carry the pin/port-level value for a scope
proc unc090_pin_objects {scope} {
    if {$scope eq "flops"} { return [lindex [unc090_flop_pins] 0] }
    return [all_outputs]
}

proc unc090_set_pin {kind scen val objs} {
    current_scenario $scen
    set_clock_uncertainty -$kind $val $objs   ;# [L] set_clock_uncertainty: the object list may be clocks, ports or pins
}

proc unc090_remove_pin {kind scen objs} {
    current_scenario $scen
    if {[catch {remove_clock_uncertainty -$kind $objs} e1]} {   ;# VERIFY remove_clock_uncertainty -setup/-hold <objects> (only the name is in the probed help)
        if {[catch {remove_clock_uncertainty $objs} e2]} { error "ERROR 090: remove_clock_uncertainty failed on the pin/port-level values in $scen: with -$kind: $e1; without: $e2" }
        puts ">>> 090 NOTE: remove_clock_uncertainty accepted no -$kind option ($e1); the form without it removed both kinds on those objects in $scen"
    }
}

# update_timing, then the removal of the tool-made set_clock_latency if the update re-created it (task 089), then a second update
proc unc090_update {label} {
    update_timing -full
    set n [unpu_remove_clock_latency unc090-$label]
    unpu_clock_latency_note unc090-$label update_timing $n
    if {$n > 0} { update_timing -full }
}

proc unc090_slack {scen type from to} {   ;# worst slack of the paths from/to the given objects ("" = not given), n/a when none
    set a [list -scenarios $scen -delay_type $type -max_paths 1]
    if {$from ne ""} { lappend a -from $from }
    if {$to ne ""} { lappend a -to $to }
    if {[catch {get_timing_paths {*}$a} p]} { return "n/a" }   ;# VERIFY get_timing_paths -scenarios -delay_type -from -to -max_paths (usage text [L])
    if {[sizeof_collection $p] == 0} { return "n/a" }
    return [get_attribute $p slack]
}

# {setup hold} WNS of the input-to-output group (clock ports excluded), setup in func_ss, hold in func_ff
proc unc090_in2out {label} {
    global UNC090_SETUP_SCEN UNC090_HOLD_SCEN
    unc090_update in2out-$label
    set ck {}
    foreach_in_collection c [get_clocks -quiet -filter "is_virtual == false"] {
        set srcs [get_attribute -quiet $c sources]   ;# VERIFY the clock attribute `sources` (as in port_buffers_early.tcl)
        if {$srcs ne "" && [sizeof_collection $srcs] > 0} { foreach_in_collection s $srcs { lappend ck [get_object_name $s] } }
    }
    set from [all_inputs]
    if {[llength $ck] > 0} { set from [remove_from_collection $from [get_ports -quiet $ck]] }
    set s [unc090_slack $UNC090_SETUP_SCEN max $from [all_outputs]]
    set h [unc090_slack $UNC090_HOLD_SCEN min $from [all_outputs]]
    puts ">>> 090 $label in2out: setup WNS ($UNC090_SETUP_SCEN) $s ns, hold WNS ($UNC090_HOLD_SCEN) $h ns"
    return [list $s $h]
}

# one probe: the slack with the value set (already in place), with it removed, set again
proc unc090_probe_one {name kind scen type from to objs val expected} {
    global UNC090_TOL
    unc090_update probe-$name-set
    set s1 [unc090_slack $scen $type $from $to]
    unc090_remove_pin $kind $scen $objs
    unc090_update probe-$name-removed
    set s2 [unc090_slack $scen $type $from $to]
    unc090_set_pin $kind $scen $val $objs
    unc090_update probe-$name-reset
    lassign [unc090_probe_verdict $name $s1 $s2 $expected $UNC090_TOL] st txt
    puts $txt
    return $st
}

proc unc090_probes {scope spec_s spec_h gs gh} {
    global UNC090_SETUP_SCEN UNC090_HOLD_SCEN UNC090_PROBE_IN_PORT UNC090_PROBE_IN_PIN UNC090_PROBE_OUT_SETUP_PORT UNC090_PROBE_OUT_HOLD_PORT
    if {$scope eq "clock"} { puts ">>> 090 probes: scope clock has no pin-level value to probe"; return }
    set objs [unc090_pin_objects $scope]
    foreach {kind scen type spec goal} [list setup $UNC090_SETUP_SCEN max $spec_s $gs hold $UNC090_HOLD_SCEN min $spec_h $gh] {
        if {$goal == 0} { puts ">>> 090 probe $scope $kind: goal 0, nothing to probe"; continue }
        set val [expr {$spec + $goal}]
        if {$scope eq "flops"} {
            set from [get_ports -quiet -exact $UNC090_PROBE_IN_PORT]; set to [get_pins -quiet -exact $UNC090_PROBE_IN_PIN]
            set expected [expr {-$goal}]    ;# the OPT value on the capture pin makes the slack smaller by the goal
            set name "in2reg-$kind"
            if {[sizeof_collection $from] == 0 || [sizeof_collection $to] == 0} { puts ">>> 090 WARNING: probe $name: $UNC090_PROBE_IN_PORT or $UNC090_PROBE_IN_PIN not found in the design; not probed"; continue }
        } else {
            set from ""
            set pn [expr {$kind eq "setup" ? $UNC090_PROBE_OUT_SETUP_PORT : $UNC090_PROBE_OUT_HOLD_PORT}]
            set to [get_ports -quiet -exact $pn]
            set expected $goal              ;# the SPEC value pinned on the port makes the slack larger by the goal than the clock-level OPT value
            set name "out-$kind-$pn"
            if {[sizeof_collection $to] == 0} { puts ">>> 090 WARNING: probe $name: port $pn not found in the design; not probed"; continue }
        }
        if {$scope eq "outputs"} { set val $spec }   ;# the port-level value is the SPEC value; the flop-pin value is SPEC + goal (set above)
        unc090_probe_one $name $kind $scen $type $from $to $objs $val $expected
    }
}

# unc090_open_opt <label> <spec s> <spec h> <goal s> <goal h> <scope> <probe>: clock-level SPEC first, the in2out numbers, then the OPT values of the scope (with the probes), verified in the SDC
proc unc090_open_opt {label spec_s spec_h gs gh scope probe} {
    global UNC090_SETUP_SCEN UNC090_HOLD_SCEN UNC090_LAST_IN2OUT
    unc090_scen_check
    set opt_s [expr {$spec_s + $gs}]; set opt_h [expr {$spec_h + $gh}]
    set clk [get_clocks -filter "is_virtual == false"]
    # 1. the clock-level value is SPEC in both scenarios (the block may carry a pre-CTS profile value); the same as the lines of the scripts before task 090
    current_scenario $UNC090_SETUP_SCEN
    set_clock_uncertainty -setup $spec_s $clk
    current_scenario $UNC090_HOLD_SCEN
    set_clock_uncertainty -hold $spec_h $clk
    # 2. the in2out numbers in the SPEC state (the state they are compared in after the restore)
    set UNC090_LAST_IN2OUT [unc090_in2out $label-before]
    # 3. the OPT values
    set nobj "-"
    foreach {kind scen spec goal opt} [list setup $UNC090_SETUP_SCEN $spec_s $gs $opt_s hold $UNC090_HOLD_SCEN $spec_h $gh $opt_h] {
        current_scenario $scen
        if {$goal == 0} { puts ">>> 090 $label $kind goal 0: nothing set above the SPEC value $spec in $scen"; continue }
        switch -- $scope {
            clock   { set_clock_uncertainty -$kind $opt $clk }
            flops   {
                lassign [unc090_flop_pins] pins nregs how
                puts ">>> 090 $label scope flops: [sizeof_collection $pins] clock pins of $nregs edge-triggered registers ($how); level-sensitive registers: [expr {[catch {sizeof_collection [all_registers -level_sensitive]} nl] ? "unknown" : $nl}] (they keep the SPEC value)"
                set nobj [sizeof_collection $pins]
                unc090_set_pin $kind $scen $opt $pins
            }
            outputs {
                set_clock_uncertainty -$kind $opt $clk
                set ports [all_outputs]
                set nobj [sizeof_collection $ports]
                puts ">>> 090 $label scope outputs: $nobj output ports pinned at the SPEC value $spec ($kind, $scen)"
                unc090_set_pin $kind $scen $spec $ports
            }
        }
        puts ">>> [expr {$kind eq "setup" ? "Setup" : "Hold"}] uncertainty during optimization: $opt ns (spec $spec ns), scope $scope, scenario $scen"
    }
    # 4. the probes
    if {$probe} { unc090_probes $scope $spec_s $spec_h $gs $gh } else { puts ">>> 090 probes switched off (UNPU_UNC_PROBE 0)" }
    # 5. what the SDC shows
    foreach {kind scen spec goal opt} [list setup $UNC090_SETUP_SCEN $spec_s $gs $opt_s hold $UNC090_HOLD_SCEN $spec_h $gh $opt_h] {
        lassign [unc090_apply_check [unc090_scan $scen $label-opt] $scope $kind $spec $opt $goal] probs matched
        puts ">>> 090 $label SDC check $scen ($kind, scope $scope): [expr {[llength $probs] == 0 ? "ok" : "PROBLEM"}]; pin/port names carrying the value: $matched (objects set: $nobj)"
        if {[llength $probs] > 0} { error "ERROR 090: $label: [join $probs {; }]" }
        if {$goal != 0 && $scope ne "clock" && $nobj ne "-" && $matched != $nobj} { puts ">>> 090 WARNING: $label: $matched names in the SDC, $nobj objects were set ($scen)" }
    }
}

# unc090_close_opt <label> <spec s> <spec h> <goal s> <goal h> <scope>: remove the pin/port-level values, clock-level SPEC, the proof, the in2out comparison
proc unc090_close_opt {label spec_s spec_h gs gh scope} {
    global UNC090_SETUP_SCEN UNC090_HOLD_SCEN UNC090_LAST_IN2OUT UNC090_TOL
    set clk [get_clocks -filter "is_virtual == false"]
    foreach {kind scen spec goal} [list setup $UNC090_SETUP_SCEN $spec_s $gs hold $UNC090_HOLD_SCEN $spec_h $gh] {
        if {$scope ne "clock" && $goal != 0} { unc090_remove_pin $kind $scen [unc090_pin_objects $scope] }
        current_scenario $scen
        set_clock_uncertainty -$kind $spec $clk
    }
    set bad {}
    foreach {kind scen spec} [list setup $UNC090_SETUP_SCEN $spec_s hold $UNC090_HOLD_SCEN $spec_h] {
        set parsed [unc090_scan $scen $label-restored]
        lassign [unc090_pin_left $parsed] nl nn
        set cl {}
        foreach e $parsed { if {[dict get $e level] eq "clock"} { lappend cl "[dict get $e type] [dict get $e value]" } }
        puts ">>> 090 $label RESTORE PROOF $scen: pin/port-level uncertainty lines left $nl ($nn names), clock-level values: [join $cl {, }]"
        foreach pr [unc090_restore_problems $parsed $kind $spec] { lappend bad "$scen: $pr" }
    }
    if {[llength $bad] > 0} { error "ERROR 090: $label: restore failed: [join $bad {; }]" }
    puts ">>> 090 $label uncertainties restored to the SPEC values: setup $spec_s ns, hold $spec_h ns; no pin/port-level value is left"
    # the in2out comparison (SPEC state before and after)
    lassign [unc090_in2out $label-after] s1 h1
    lassign $UNC090_LAST_IN2OUT s0 h0
    puts ">>> 090 $label in2out (scope $scope, goals setup $gs / hold $gh): setup WNS $s0 -> $s1, hold WNS $h0 -> $h1"
    foreach {what b a} [list setup $s0 $s1 hold $h0 $h1] {
        set w [unc090_in2out_cmp $what $b $a $UNC090_TOL]
        if {$w ne ""} { puts $w }
    }
}

# pv.tcl: unc090_export_check <label> <files> <spec s> <spec h>: any set_clock_uncertainty line that names pins/ports or whose value differs from SPEC is ERROR 090; the lines are printed
proc unc090_export_check {label files spec_s spec_h} {
    set total 0
    set probs {}
    foreach f $files {
        if {![file exists $f]} { error "ERROR 090: $label: the exported SDC $f does not exist" }
        set fp [open $f r]; set tx [read $fp]; close $fp
        set parsed [unc090_parse $tx]
        puts ">>> 090 $label: [file tail $f]: [llength $parsed] set_clock_uncertainty line(s)"
        foreach e $parsed { puts ">>> 090 $label:     [dict get $e line]" }
        incr total [llength $parsed]
        foreach p [unc090_export_problems $parsed $spec_s $spec_h] { lappend probs "[file tail $f]: $p" }
    }
    if {[llength $probs] > 0} { error "ERROR 090: $label: the exported SDC must carry only the clock-level SPEC values: [join $probs {; }]" }
    if {$total != 2 * [llength $files]} { puts ">>> 090 NOTE: $label: $total set_clock_uncertainty lines in [llength $files] files (2 per file expected: setup and hold); every one of them is a clock-level SPEC line" }
    puts ">>> 090 $label: exported SDC files checked ([llength $files]): $total line(s), all clock-level at SPEC (setup $spec_s, hold $spec_h)"
    return $total
}
