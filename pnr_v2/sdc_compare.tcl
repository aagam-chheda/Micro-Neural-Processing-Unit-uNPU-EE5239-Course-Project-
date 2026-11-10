# ==============================================================================
# Script: sdc_compare.tcl   (task 096)  -- compare two SDC files constraint by constraint (pure Tcl, no EDA tool)
# Run   : tclsh pnr_v2/sdc_compare.tcl <legacy.sdc> <exported.sdc>
#           e.g. tclsh pnr_v2/sdc_compare.tcl constraints/legacy/unpu_top_legacy.sdc pnr_icc2/outputs/unpu_top_pnr_ss.sdc
# Does  : evaluates both files in a SAFE Tcl interpreter in which every SDC command only records its arguments (variables, `expr` and lists of the legacy file are resolved by Tcl itself; get_ports/get_clocks/
#         all_inputs/all_outputs/current_design return markers), then compares the constraints that matter: create_clock, clock uncertainty and transition, input and output delays (-min/-max, per port),
#         driving cells, loads, max_transition (design-wide and -clock_path), max_capacitance, propagated clock. Port patterns of the legacy file (paddr[*], dma_wdata[*]) are expanded against the port names
#         that the exported file uses; all_inputs / all_outputs = the ports that carry an input / output delay in the exported file.
# Prints: a table `legacy | exported | status` (grouped: the same value on many ports is one line with the count), status SAME, DIFFERENT, ONLY-IN-LEGACY, ONLY-IN-EXPORTED or EXPECTED (a difference
#         that the exported SDC has BY DESIGN, listed by name below with its reason), and a verdict. Anything that is not on the list of expected differences is a DIFFERENCE.
# Exit  : 0 = equal apart from the expected differences, 1 = a difference, 2 = usage / unreadable file.
# ==============================================================================

# ---- BEGIN PURE TCL 096 ----
# 096: the differences that the exported SDC has BY DESIGN: {family-pattern reason}. A row whose family matches and whose status is ONLY-IN-EXPORTED / DIFFERENT becomes EXPECTED with this reason.
# 096: a family that is not listed here is a real difference. ("max_transition clock_path" is deliberately NOT listed: since task 096 the exported SDC must not carry it.)
set SDC096_EXPECTED {
    {propagated *            {set_propagated_clock: cts.tcl makes the clock propagated after CTS (the tree is real); the legacy SDC has the ideal clock. PrimeTime applies it too (pt_read_sdc_and_check)}}
    {waveform *              {create_clock -waveform: the exported SDC writes the default waveform {0 period/2} explicitly; the legacy file leaves it implicit}}
    {opcond *                {set_operating_conditions: library/analysis setting of the tool (OCV), not a design constraint; the legacy SDC is pure constraints by design}}
    {units *                 {set_units: the exported SDC writes the library units; the legacy file declares time/capacitance only}}
}

# 096: the recorder interpreter. Every command records {name args}; the helper commands return markers.
proc sdc096_eval {path} {
    if {[catch {set fp [open $path r]; set text [read $fp]; close $fp} err]} { error "cannot read $path: $err" }
    set ip [interp create -safe]
    set ::sdc096_rec [list]
    foreach c {create_clock set_clock_uncertainty set_clock_transition set_input_delay set_output_delay set_driving_cell set_load set_max_transition set_max_capacitance set_propagated_clock set_units set_operating_conditions} {
        interp alias $ip $c {} sdc096_record $c
    }
    interp alias $ip get_ports {} sdc096_marker ports
    interp alias $ip get_clocks {} sdc096_marker clocks
    interp alias $ip all_clocks {} sdc096_marker all_clocks
    interp alias $ip all_inputs {} sdc096_marker all_inputs
    interp alias $ip all_outputs {} sdc096_marker all_outputs
    interp alias $ip current_design {} sdc096_marker design
    interp alias $ip unknown {} sdc096_unknown
    set rc [catch {$ip eval $text} err]
    interp delete $ip
    if {$rc} { error "$path: $err" }
    return $::sdc096_rec
}
proc sdc096_record {name args} { lappend ::sdc096_rec [list $name $args]; return "" }
proc sdc096_marker {kind args} { return [list [concat $kind {*}$args]] }
proc sdc096_unknown {args} { lappend ::sdc096_rec [list unknown $args]; return "" }

# 096: arity of the options per command: options that take a value; every other option starting with `-` is a flag.
set SDC096_ARGV(create_clock)            {-name -period -waveform -comment}
set SDC096_ARGV(set_clock_uncertainty)   {-from -to -rise_from -fall_from -rise_to -fall_to -comment}
set SDC096_ARGV(set_clock_transition)    {-comment}
set SDC096_ARGV(set_input_delay)         {-clock -reference_pin -comment}
set SDC096_ARGV(set_output_delay)        {-clock -reference_pin -comment}
set SDC096_ARGV(set_driving_cell)        {-lib_cell -pin -library -from_pin -input_transition_rise -input_transition_fall -multiply_by -dont_scale -comment}
set SDC096_ARGV(set_load)                {-comment}
set SDC096_ARGV(set_max_transition)      {-comment}
set SDC096_ARGV(set_max_capacitance)     {-comment}
set SDC096_ARGV(set_propagated_clock)    {}
# 096: -> dict: opts (name -> value, flags -> 1), pos (the positional words, in order). An object (a marker list from get_ports ...) is a positional word.
proc sdc096_parse {cmd args} {
    global SDC096_ARGV
    set withval [expr {[info exists SDC096_ARGV($cmd)] ? $SDC096_ARGV($cmd) : {}}]
    set opts [dict create]; set pos {}
    set n [llength $args]
    for {set i 0} {$i < $n} {incr i} {
        set a [lindex $args $i]
        if {[string match -* $a] && ![string is double -strict $a] && [llength $a] == 1} {
            if {$a in $withval} { dict set opts $a [lindex $args [incr i]] } else { dict set opts $a 1 }
        } else { lappend pos $a }
    }
    return [dict create opts $opts pos $pos]
}
# 096: a number to its canonical text (20 and 20.0 are the same), anything else as it is
proc sdc096_num {v} { if {[string is double -strict $v]} { return [format %.6g $v] }; return $v }
# 096: the names in an object marker
proc sdc096_names {obj} {
    # obj: {ports a b c} / {clocks clk} / {all_inputs} / {design} (the marker list is wrapped once: a list holding one list)
    set o [lindex $obj 0]
    return [lrange $o 1 end]
}
proc sdc096_kind {obj} { return [lindex [lindex $obj 0] 0] }
# 096: glob match of a legacy port pattern against a name (brackets are literal in port names)
proc sdc096_match {pattern name} { return [string match [string map {[ \\[ ] \\]} $pattern] $name] }

# 096: the records -> the constraint table: a dict key -> value.  Keys:  clock <name> | waveform <name> | uncertainty <setup|hold> <clock> | clock_transition <clock> | input_delay <min|max> <port> |
# 096: output_delay <min|max> <port> | driving_cell <port> | load <port> | max_transition design | max_transition clock_path <clock> | max_capacitance design | propagated <clock> | opcond | units | sdcversion.
# 096: ports (the universe) and the in/out sets come from ctx: dict ports inputs outputs (the exported file's names). A later record wins for the same key (as in the tools). Unknown commands are returned in `unknown`.
proc sdc096_table {records ctx} {
    set t [dict create]
    set unknown {}
    set ports [dict get $ctx ports]; set ins [dict get $ctx inputs]; set outs [dict get $ctx outputs]
    foreach r $records {
        lassign $r cmd args
        if {$cmd eq "unknown"} { lappend unknown [lindex $args 0]; continue }
        set pa [sdc096_parse $cmd {*}$args]
        set o [dict get $pa opts]; set pos [dict get $pa pos]
        switch -- $cmd {
            create_clock {
                set nm [expr {[dict exists $o -name] ? [dict get $o -name] : "?"}]
                dict set t "clock $nm" [sdc096_num [dict get $o -period]]
                dict set t "waveform $nm" [expr {[dict exists $o -waveform] ? [join [lmap x [dict get $o -waveform] {sdc096_num $x}] ,] : "(default)"}]
            }
            set_clock_uncertainty {
                set v [sdc096_num [lindex $pos 0]]
                foreach c [sdc096_names [lindex $pos 1]] {
                    foreach k {setup hold} { if {[dict exists $o -$k] || (![dict exists $o -setup] && ![dict exists $o -hold])} { dict set t "uncertainty $k $c" $v } }
                }
            }
            set_clock_transition { foreach c [sdc096_names [lindex $pos 1]] { dict set t "clock_transition $c" [sdc096_num [lindex $pos 0]] } }
            set_input_delay - set_output_delay {
                set kind [expr {$cmd eq "set_input_delay" ? "input_delay" : "output_delay"}]
                set v [sdc096_num [lindex $pos 0]]
                set clk "?"
                if {[dict exists $o -clock]} {
                    set cv [dict get $o -clock]
                    if {[llength $cv] == 1 && [llength [lindex $cv 0]] >= 2 && [sdc096_kind $cv] eq "clocks"} { set clk [lindex [sdc096_names $cv] 0] } else { set clk $cv }
                }
                set obj [lindex $pos 1]
                set names {}
                switch -- [sdc096_kind $obj] {
                    all_inputs { set names $ins }
                    all_outputs { set names $outs }
                    ports { foreach p [sdc096_names $obj] { foreach u $ports { if {[sdc096_match $p $u]} { lappend names $u } } } }
                }
                foreach p [lsort -unique $names] {
                    foreach m {min max} { if {[dict exists $o -$m] || (![dict exists $o -min] && ![dict exists $o -max])} { dict set t "$kind $m $p" "$v clock $clk" } }
                }
            }
            set_driving_cell {
                foreach p [sdc096_names [lindex $pos 0]] { foreach u $ports { if {[sdc096_match $p $u]} { dict set t "driving_cell $u" "[dict get $o -lib_cell] pin [expr {[dict exists $o -pin] ? [dict get $o -pin] : {?}}]" } } }
            }
            set_load {
                set mode [expr {[dict exists $o -wire_load] ? "wire" : "pin"}]
                foreach p [sdc096_names [lindex $pos 1]] { foreach u $ports { if {[sdc096_match $p $u]} { dict set t "load $u" "[sdc096_num [lindex $pos 0]] $mode" } } }
            }
            set_max_transition {
                set v [sdc096_num [lindex $pos 0]]
                if {[dict exists $o -clock_path]} { foreach c [sdc096_names [lindex $pos 1]] { dict set t "max_transition clock_path $c" $v } } else { dict set t "max_transition design" $v }
            }
            set_max_capacitance { dict set t "max_capacitance design" [sdc096_num [lindex $pos 0]] }
            set_propagated_clock { foreach c [sdc096_names [lindex $pos 0]] { dict set t "propagated $c" yes } }
            set_units { dict set t units [join $args " "] }
            set_operating_conditions { dict set t opcond [join $args " "] }
        }
    }
    return [dict create table $t unknown $unknown]
}
# 096: the context (port universe, inputs, outputs) from the EXPORTED records
proc sdc096_context {records} {
    set ports {}; set ins {}; set outs {}
    foreach r $records {
        lassign $r cmd args
        foreach a $args {
            if {[llength $a] == 1 && [llength [lindex $a 0]] >= 2 && [lindex [lindex $a 0] 0] eq "ports"} {
                foreach p [lrange [lindex $a 0] 1 end] { lappend ports $p; if {$cmd eq "set_input_delay"} { lappend ins $p } elseif {$cmd eq "set_output_delay"} { lappend outs $p } }
            }
        }
    }
    return [dict create ports [lsort -unique $ports] inputs [lsort -unique $ins] outputs [lsort -unique $outs]]
}
# 096: the family of a key (the first word, or the first two for max_transition), for the expected-difference list and the grouping
proc sdc096_family {key} {
    set w [split $key " "]
    if {[lindex $w 0] in {max_transition input_delay output_delay uncertainty}} { return "[lindex $w 0] [lindex $w 1]" }
    return [lindex $w 0]
}
proc sdc096_family_name {key} {   ;# the name used in the expected list: the first word
    return [lindex [split $key " "] 0]
}
# 096: -> a list of rows {key legacy exported status reason}
proc sdc096_compare {tl te expected} {
    set rows {}
    set keys [lsort -unique [concat [dict keys $tl] [dict keys $te]]]
    foreach k $keys {
        set l [expr {[dict exists $tl $k] ? [dict get $tl $k] : ""}]
        set e [expr {[dict exists $te $k] ? [dict get $te $k] : ""}]
        if {[dict exists $tl $k] && [dict exists $te $k]} { set st [expr {$l eq $e ? "SAME" : "DIFFERENT"}] } elseif {[dict exists $tl $k]} { set st ONLY-IN-LEGACY } else { set st ONLY-IN-EXPORTED }
        set reason ""
        if {$st ne "SAME"} {
            foreach x $expected {
                lassign $x fam pat why
                if {[sdc096_family_name $k] eq $fam} { set st EXPECTED; set reason $why; break }
            }
        }
        lappend rows [list $k $l $e $st $reason]
    }
    return $rows
}
# 096: group the rows: same family, same legacy value, same exported value, same status -> one line with the count and the names
proc sdc096_group {rows} {
    set g [dict create]
    foreach r $rows {
        lassign $r k l e st why
        set w [split $k " "]
        set fam [sdc096_family $k]
        set obj [lindex $w end]
        dict lappend g [list $fam $l $e $st $why] $obj
    }
    set out {}
    dict for {gk objs} $g { lappend out [list {*}$gk $objs] }
    return [lsort -index 0 $out]
}
# 096: the printable table and the verdict. Returns {lines verdict n_different n_expected}
proc sdc096_report {rows unknown_l unknown_e} {
    set lines [list [format "%-28s | %-26s | %-26s | %s" constraint legacy exported status]]
    lappend lines [string repeat - 100]
    set nd 0; set ne 0
    foreach g [sdc096_group $rows] {
        lassign $g fam l e st why objs
        set n [llength $objs]
        set names [expr {$n > 6 ? "[join [lrange $objs 0 3] { }] ... ($n)" : [join $objs { }]}]
        lappend lines [format "%-28s | %-26s | %-26s | %s  %s" $fam [expr {$l eq {} ? {-} : $l}] [expr {$e eq {} ? {-} : $e}] $st "$names"]
        if {$st eq "EXPECTED"} { incr ne $n; lappend lines "      expected: $why" }
        if {$st in {DIFFERENT ONLY-IN-LEGACY ONLY-IN-EXPORTED}} { incr nd $n }
    }
    foreach {side u} [list legacy $unknown_l exported $unknown_e] {
        if {[llength $u] > 0} { lappend lines "commands not compared in the $side file: [lsort -unique $u]" }
    }
    set same 0
    foreach r $rows { if {[lindex $r 3] eq "SAME"} { incr same } }
    lappend lines "constraints compared: [llength $rows]; SAME $same; EXPECTED differences $ne; DIFFERENCES $nd"
    set verdict [expr {$nd == 0 ? "SDC COMPARE: EQUAL apart from the $ne expected difference(s)" : "SDC COMPARE: $nd DIFFERENCE(S) not on the list of expected differences"}]
    return [list $lines $verdict $nd $ne]
}
# 096: the whole comparison of two files. Returns {lines verdict n_different n_expected}
proc sdc096_run {legacy exported} {
    global SDC096_EXPECTED
    set rl [sdc096_eval $legacy]
    set re [sdc096_eval $exported]
    set ctx [sdc096_context $re]
    set tl [sdc096_table $rl $ctx]
    set te [sdc096_table $re $ctx]
    # the exported file's set sdc_version line is a plain `set`, not recorded: it is a header, nothing to compare
    set rows [sdc096_compare [dict get $tl table] [dict get $te table] $SDC096_EXPECTED]
    return [sdc096_report $rows [dict get $tl unknown] [dict get $te unknown]]
}
# ---- END PURE TCL 096 ----

if {[info exists argv0] && [file normalize $argv0] eq [file normalize [info script]]} {
    if {[llength $argv] != 2} { puts stderr "usage: tclsh sdc_compare.tcl <legacy.sdc> <exported.sdc>"; exit 2 }
    if {[catch {lassign [sdc096_run {*}$argv] lines verdict nd ne} err]} { puts stderr "sdc_compare.tcl: $err"; exit 2 }
    foreach l $lines { puts $l }
    puts $verdict
    exit [expr {$nd > 0}]
}
