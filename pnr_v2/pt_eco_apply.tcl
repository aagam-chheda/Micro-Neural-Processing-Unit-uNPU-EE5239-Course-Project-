# ==============================================================================
# Script: pt_eco_apply.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/pt_eco_apply.tcl   ;# 079: new script (flow step 6g, after timing_closure.tcl (6e), before metal_fill.tcl)
# Stage : Apply PrimeTime's own ECO (hold: insert_buffer; optional setup: size_cell) to the routed block
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 079: THIS SCRIPT CHANGES THE NETLIST (an ECO): it inserts the delay/buffer cells that PrimeTime's fix_eco_timing proposed (109 insert_buffer commands for hold in the first run, 112 in the run with the in2out cone protected; the expected count is read from the probe's count file:
# 079: dl01d1 64, dl02d1 31, buffd1 12, dl01d2 2) and, if the optional setup change file exists, resizes the cells it names. The PM must be told: the netlist of pv.tcl differs again.
# 079: why. PrimeTime is the sign-off and reads the I/O references at the clock PIN with zero latency (task 078 findings): hold -0.3468 ns on 263 endpoints (255 flop D pins fed by
# 079: dma_rdata[*] / pwdata[*]) and setup -0.2423 ns on dma_addr[31]. The user decided on 2026-11-09 to fix the design to pass PrimeTime. PrimeTime's own ECO closed hold in its
# 079: memory (263 -> 0, WNS +0.0002 ns); this script reproduces exactly the pin-level topology PrimeTime assumed:
# 079:   - the change file is parsed in Tcl (pure procs, tested in pnr_v2/test_pt_eco_apply.tcl): current_instance {x} sets the hierarchy of the following pins;
# 079:     `insert_buffer [get_pins {P}] REF -new_net_names {N} -new_cell_names {C}`; `size_cell {I} REF`. Anything else stops the script and is listed.
# 079:   - a buffer on a DRIVER pin takes all loads of that net; on a LOAD pin it isolates that one load: after each insertion the leaf pins of both nets are compared with what PrimeTime
# 079:     assumed (eco079_topology_problems) and any difference is a hard error.
# 079:   - every new cell gets a legal site NEXT TO the pin (the filler-table method of antenna_port_buffers.tcl, wide cells: the width is read from the LEF), is verified at that site
# 079:     and retried with the next candidate (tier 1, then tier 2 with a larger distance); a cell that cannot be placed is listed as FAILED and the script stops BEFORE routing.
# 079:   - the 15 antbuf_* buffers and the clock root are snapshotted and compared at the end (reference, origin, orientation, pin connections); insertions on a port net or on the
# 079:     output net of an antbuf_* are printed as ANTENNA WATCH (Calibre decides afterwards).
# 079: what it does, in order (every decision is printed with `>>> 079`):
# 079:   1 open _route, parse the change files   2 pin / reference / name checks (nothing is changed on any error)   3 BEFORE metrics, protected-cell snapshot
# 079:   4 fillers into a table, apply the changes one at a time with placement   5 refill, connect_pg_net, re-route only the touched nets   6 hard checks, AFTER metrics, save
# 079: every command or option not shown in a usage text in ~/server_pull/rpt/help is marked VERIFY. No constraint, uncertainty, goal, limit or app option is changed. No diode.

set DESIGN_NAME "unpu_top"
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set SCRIPT_DIR  "/storage/EE5239G1/aagams_workspace2/unpu/pnr_v2"   ;# 079: where antenna_port_buffers.tcl and timing_closure.tcl are: their helper procs are read from their text, not copied
set STD_LEF     "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"   ;# 079: kit LEF (as build_ndm_std.tcl): cell widths
set STD_LIB     "scl180_std"
set FILLER_LIB  "scl180_filler"
set FILLER_REFS {feedth feedth3 feedth9}
set PT_DIR      "${PNR_DIR}/pt"   ;# 079: where PrimeTime wrote the change files (pt_eco_probe.tcl, pt_eco_setup_probe.tcl)

# ---- parameters of THIS script ----
set ECO_HOLD_FILE   "${PT_DIR}/pt_eco_hold_changes_icc2.tcl"    ;# 079: REQUIRED. The icc2tcl format of write_changes ("formatted for IC Compiler"); pt_eco_hold_changes.tcl has the same content
set ECO_SETUP_FILE  "${PT_DIR}/pt_eco_setup_changes_icc2.tcl"   ;# 079: OPTIONAL (task 079 part 1 produces it); skipped with a printed line when it does not exist
set ECO_COUNT_FILE  "${PT_DIR}/pt_eco_hold_expected_count.txt"   ;# 081: written by pt_eco_probe.tcl: the number of commands PrimeTime proposed (the expectation comes from the PrimeTime side, not from a typed number)
set EXPECT_HOLD_CMDS 112        ;# 081: ONLY the fallback when ECO_COUNT_FILE does not exist (printed as a WARNING: an assumption). 109 was the first try (unprotected ECO), 112 the current one (in2out cone protected, commit 8b185fa); a different count in the change file is an error
set EXPECT_ANTBUF   15          ;# 079: antenna_port_buffers.tcl made 15 port buffers; they must still be 15
set BUF_PREFIX      "antbuf"    ;# 079: as antenna_port_buffers.tcl
set CLK_PORT        "clk"       ;# 079: the clock port; its net's single leaf load is the CTS root (antenna_clk_root.tcl)
set NEW_CELL_MARK   "PTECO"     ;# 079: PrimeTime's names contain this (U_PTECO_HOLD_BUF<n>, net_PTECO_HOLD_NET<n>); used to find extra / missing new cells
set DIST_TIER1      30.0        ;# 079: tier 1: the new cell's box centre may be at most this far (Manhattan, um) from the pin it was inserted on: a hold delay cell far from its pin adds wire delay that PrimeTime did not assume
set DIST_TIER2      120.0       ;# 079: tier 2 (only if tier 1 has no usable filler run): crowded places; the extra wire delay is judged by the PrimeTime run afterwards. Beyond this the change FAILS.
set MAX_SITE_TRIES  5           ;# 079: candidate filler runs tried per tier and change (closest first), as antenna_port_buffers.tcl
set POS_TOL         0.001       ;# 079: um: the final origin must equal the requested site to this tolerance
set UNPROTECT_DURING 1          ;# 079: 1 = dont_touch of the protected cells/nets is switched off while the changes are applied (insert_buffer on a dont_touch net may be refused) and switched on again; the snapshot comparison is the guard. 0 = leave it as it is.
set ALLOW_PARTIAL   0           ;# 079 fix 3: 0 = strict: a change that cannot be placed after all tiers stops the script (nothing saved). 1 = that change is SKIPPED together with every later change that uses a pin of the cell it should have created; the script continues, prints a SKIPPED CHANGES block and ends with STAGE 6g COMPLETE (PARTIAL: ...). PrimeTime must then be re-run (a second ECO round may be needed).
set GATE_GROUP_PATTERN "in2out" ;# 080: the path group of the combinational APB read path (paddr -> prdata) is named **in2out_default** in ICC2; a group whose name contains this text is the in2out group. If no such group exists the worst setup path from an input port to an output port is used (VERIFY the option -groups and get_path_groups)
set GATE_TOL_SETUP  0.005       ;# 080: ns. The ECO may make the setup WNS of the in2out group or of the whole design worse by at most this much (ICC2's numbers are repeatable to the picosecond; re-routing only the touched nets moves a path by a few ps at most; the in2out margin before the ECO is only +0.0143 ns, and the damage of the unprotected ECO was -0.59 ns). Worse by more: NOTHING IS SAVED.
set GATE_TOL_HOLD   0.005       ;# 080: ns. Hold may get worse by at most this much in ICC2 before a WARNING is printed (not an error: PrimeTime is the sign-off for hold; ICC2's hold before the ECO is -0.0004 to -0.00258 ns depending on state)
set DRC_ROUNDS      3           ;# 081: rounds of the DRC clean-up after routing when check_routes still reports DRCs (each: incremental detail route, then the error windows and their nets re-routed); DRCs left after the last round stop the script, nothing saved
set DRC_WINDOW_MARGIN 5.0       ;# 081: um added around a DRC error box for the windowed re-route (the same margin antenna_port_buffers.tcl used for the Calibre markers)
set DRC_ERR_NAME    "zroute.err" ;# 081: name of the error data check_routes writes (the message "The error data zroute.err is closed (ERRDM-043)" of antenna_port_buffers.tcl); VERIFY
set SETUP_SCEN      "func_ss"   ;# 079: scenario names of cts.tcl / route.tcl
set HOLD_SCEN       "func_ff"
# 079 fix: insertions on an input PORT (get_ports): the pin-to-new-cell wire must stay short (antenna). Limits are READ from antenna_port_buffers.tcl into PORT_MAX_PIN_BUF_DIST, PORT_ANT_RATIO_LIMIT,
# 079 fix: PORT_ANT_WEIGHT_PINWIRE, PORT_WIRE_WIDTH_UM (hard distance limit of step 6c, Calibre ratio limit, M2/M3 weight, wire width).
# 079 fix 3: TIER 2 for ports (when no filler run works within tier 1): the distance at which the predicted ratio with the TOP_M weight (PORT_ANT_WEIGHT_TOPM, 0.84 from the Calibre log, the worst case:
# 079 fix 3: no layer restriction is needed) and the cell's own input gate area stays <= PORT_TIER2_RATIO (360 = 10 percent under the 400 limit, from antenna_port_buffers.tcl TIER2_RATIO).
set DONT_USE_PATTERNS {slnht* skbrb* slbhb* slnhn* slnln* mx08d* adiode bh01d1 cload1}   ;# 079: handoff 18.15 (as antenna_port_buffers.tcl); the delay cells dl* are normal library cells

# ---- BEGIN PURE TCL 079 ----
# 079: everything between BEGIN and END is plain Tcl (no ICC2 command); pnr_v2/test_pt_eco_apply.tcl extracts and tests exactly this text.
# 079: it needs ant_manhattan, ant_dont_use, ant_filler_runs, ant_site_candidates of antenna_port_buffers.tcl (loaded before in the real script, sourced by the test).

# the full name of a thing inside the hierarchy given by current_instance ("" = top)
proc eco079_full {hier name} {
    if {$hier eq ""} { return $name }
    return "$hier/$name"
}
# the cell part of a pin name: everything before the last "/"; "" for a name without "/"
proc eco079_pin_cell {full} {
    set i [string last / $full]
    if {$i < 0} { return "" }
    return [string range $full 0 [expr {$i - 1}]]
}
# 079 fix: split the arguments of a command into words. A word is a braced group {..} (braces removed), a bracketed group [..] (kept with the brackets) or a bare run.
# Returns {ok words}; ok 0 when a brace or bracket is not closed (words then holds the text from there).
proc eco079_words {s} {
    set out {}
    set i 0
    set n [string length $s]
    while {$i < $n} {
        set ch [string index $s $i]
        if {[string is space $ch]} { incr i; continue }
        if {$ch eq "\x7b"} {
            set j [string first "\x7d" $s $i]
            if {$j < 0} { return [list 0 [list [string range $s $i end]]] }
            lappend out [string range $s [expr {$i + 1}] [expr {$j - 1}]]
            set i [expr {$j + 1}]
        } elseif {$ch eq "\["} {
            set j [string first "\]" $s $i]
            if {$j < 0} { return [list 0 [list [string range $s $i end]]] }
            lappend out [string range $s $i $j]
            set i [expr {$j + 1}]
        } else {
            set j $i
            while {$j < $n && ![string is space [string index $s $j]]} { incr j }
            lappend out [string range $s $i [expr {$j - 1}]]
            set i $j
        }
    }
    return [list 1 $out]
}
# 079: parse a PrimeTime change file (write_changes -format icc2tcl). Returns a dict: cmds (list of dicts), errors (list of texts).
# cmd: idx (1-based among the changes), line (number in the file), type (insert_buffer | size_cell), hier, pin (as written), objkind (pin | port), full_pin (for a port: the port name), ref, cell, net (new names, full) | inst, full_inst (size_cell)
# `insert_buffer [get_pins {P}] REF ...` (P relative to current_instance) and `insert_buffer [get_ports {PORT}] REF ...` (a top-level port: only valid with an empty current_instance);
# `size_cell {INST} {REF}` (braces optional, `[get_cells {INST}]` accepted). Everything else is an error listed with its line number.
proc eco079_parse {text} {
    set cmds {}
    set errors {}
    set hier ""
    set n 0
    set ln 0
    foreach raw [split $text "\n"] {
        incr ln
        set l [string trim $raw]
        if {$l eq "" || [string match "#*" $l]} continue
        if {[regexp {^current_instance(?:\s+(.*))?$} $l -> arg]} {
            set hier [string trim [string trim $arg] "{}"]
            set hier [string trim $hier]
            continue
        }
        if {[regexp {^insert_buffer\s+\[(get_pins|get_ports)\s+(?:\{([^\}]+)\}|([^\]\s]+))\]\s+(\S+)(.*)$} $l -> kw braced bare ref rest]} {
            set pin [expr {$braced ne "" ? $braced : $bare}]
            set objkind [expr {$kw eq "get_ports" ? "port" : "pin"}]
            set ref [string trim $ref "\x7b\x7d"]
            if {$objkind eq "port" && $hier ne ""} { lappend errors "line $ln: get_ports under current_instance {$hier}: a port of a hierarchical cell is not supported: $l"; continue }
            set net ""
            set cell ""
            foreach {opt var} {new_net_names net new_cell_names cell} {
                set pat "-$opt\\s+\\x7b?(\[^\\s\\x7d\]+)\\x7d?"   ;# (\x7b / \x7d = the braces: a literal brace after a double backslash would unbalance the proc body)
                if {[regexp -- $pat $rest -> v]} {
                    set $var $v
                    regsub -- $pat $rest {} rest
                }
            }
            set rest [string trim $rest]
            if {$rest ne ""} { lappend errors "line $ln: insert_buffer has options this script does not understand: '$rest'"; continue }
            if {$net eq "" || $cell eq ""} { lappend errors "line $ln: insert_buffer without both -new_net_names and -new_cell_names: $l"; continue }
            incr n
            lappend cmds [dict create idx $n line $ln type insert_buffer hier $hier objkind $objkind pin $pin full_pin [expr {$objkind eq "port" ? $pin : [eco079_full $hier $pin]}] ref $ref cell [eco079_full $hier $cell] net [eco079_full $hier $net]]
            continue
        }
        if {[regexp {^size_cell(\s.*)$} $l -> args]} {
            lassign [eco079_words $args] wok words
            set inst ""
            set ref ""
            if {$wok && [llength $words] == 2} {
                lassign $words w0 ref
                if {[string index $w0 0] eq "\["} {
                    lassign [eco079_words [string range $w0 1 end-1]] iok iw
                    if {$iok && [llength $iw] == 2 && [lindex $iw 0] eq "get_cells"} { set inst [lindex $iw 1] }
                } else {
                    set inst $w0
                }
            }
            if {$inst eq "" || $ref eq ""} { lappend errors "line $ln: size_cell form not understood (expected: size_cell {INSTANCE} {REFERENCE}): $l"; continue }
            incr n
            lappend cmds [dict create idx $n line $ln type size_cell hier $hier objkind cell inst $inst full_inst [eco079_full $hier $inst] ref $ref]
            continue
        }
        lappend errors "line $ln: command not understood: $l"
    }
    return [dict create cmds $cmds errors $errors]
}
# 079: the count check: found vs expected; {ok message}
proc eco079_count_check {what found expected} {
    if {$found == $expected} { return [list 1 "$what: $found (expected $expected)"] }
    return [list 0 "$what: $found but $expected expected"]
}
# 079: references used and how often (dict ref -> count), over the commands of one type
proc eco079_ref_table {cmds {type ""}} {
    set t [dict create]
    foreach c $cmds { if {$type eq "" || [dict get $c type] eq $type} { dict incr t [dict get $c ref] } }
    return $t
}
# 079: references that are not in the library (names given) or match a don't-use pattern. Returns a list of problems.
proc eco079_ref_problems {refs lib_names patterns} {
    set out {}
    foreach r $refs {
        if {[lsearch -exact $lib_names $r] < 0} { lappend out "reference $r is not in the library" }
        set hit [ant_dont_use $r $patterns]
        if {$hit ne ""} { lappend out "reference $r matches the don't-use pattern $hit" }
    }
    return $out
}
# 079: duplicate new cell or net names inside the file(s), and clashes with names that already exist in the design. Returns a list of problems.
proc eco079_name_problems {cmds existing_cells existing_nets} {
    set out {}
    array set sc {}; array set sn {}
    foreach c $cmds {
        if {[dict get $c type] ne "insert_buffer"} continue
        set cn [dict get $c cell]; set nn [dict get $c net]
        if {[info exists sc($cn)]} { lappend out "new cell name $cn used twice (changes $sc($cn) and [dict get $c idx])" } else { set sc($cn) [dict get $c idx] }
        if {[info exists sn($nn)]} { lappend out "new net name $nn used twice (changes $sn($nn) and [dict get $c idx])" } else { set sn($nn) [dict get $c idx] }
        if {[lsearch -exact $existing_cells $cn] >= 0} { lappend out "cell $cn already exists in the design" }
        if {[lsearch -exact $existing_nets $nn] >= 0} { lappend out "net $nn already exists in the design" }
    }
    return $out
}
# 079: a pin or instance whose cell is created by an EARLIER insert_buffer of the file cannot be looked up before that command is applied (it is deferred, not missing)
proc eco079_is_deferred {cmds idx full_pin_or_inst isinst} {
    set cellname [expr {$isinst ? $full_pin_or_inst : [eco079_pin_cell $full_pin_or_inst]}]
    foreach c $cmds {
        if {[dict get $c idx] >= $idx} break
        if {[dict get $c type] eq "insert_buffer" && [dict get $c cell] eq $cellname} { return 1 }
    }
    return 0
}
# 079: the topology after one insert_buffer must be what PrimeTime assumed.
#   dir out (a DRIVER pin): the buffer input is on the driver's net together with the driver: after_in = {pin buf_i}; the buffer output net has the buffer output and every other
#     load the net had: after_out = {buf_z} + (before - pin).
#   dir in (a LOAD pin): the load is isolated behind the buffer: after_out = {buf_z pin}; the net keeps every other pin and gets the buffer input: after_in = (before - pin) + {buf_i}.
#   dir port (an input PORT, `pin` is the port name and is not a leaf pin): after_in = {buf_i}; after_out = {buf_z} + every load the net had (before).
# before = leaf pins of the pin's net before the insertion (including the pin, except for a port); all arguments are lists of leaf pin names. Returns a list of problems (empty = as assumed).
proc eco079_topology_problems {dir pin before after_in after_out buf_i buf_z} {
    set rest {}
    foreach p $before { if {$p ne $pin} { lappend rest $p } }
    if {$dir eq "out"} {
        set want_in [list $pin $buf_i]
        set want_out [concat [list $buf_z] $rest]
    } elseif {$dir eq "port"} {
        # an INPUT PORT (not a leaf pin: it is not in `before`): the port stays on the net with the buffer input; every load moves behind the buffer (like the antenna buffers of step 6c)
        set want_in [list $buf_i]
        set want_out [concat [list $buf_z] $before]
    } elseif {$dir eq "in"} {
        set want_in [concat $rest [list $buf_i]]
        set want_out [list $buf_z $pin]
    } else {
        return [list "pin direction '$dir' is neither out, in nor port"]
    }
    set out {}
    if {[lsort $after_in] ne [lsort $want_in]} { lappend out "buffer input net has pins {[lsort $after_in]}, expected {[lsort $want_in]}" }
    if {[lsort $after_out] ne [lsort $want_out]} { lappend out "buffer output net has pins {[lsort $after_out]}, expected {[lsort $want_out]}" }
    return $out
}
# 079: who drives the net of an insertion pin: port | antbuf | other. driver_cells = names of the cells of the output leaf pins of the net, has_input_port = an input port is on the net.
proc eco079_driver_kind {driver_cells has_input_port prefix} {
    if {$has_input_port} { return port }
    foreach c $driver_cells { if {[string match "${prefix}_*" [lindex [split $c /] end]]} { return antbuf } }
    return other
}
# 079: the ANTENNA WATCH reason text, "" for no watch
proc eco079_watch_reason {kind} {
    switch -- $kind {
        port { return "the net is driven directly by an input port: the new cell adds gate area and wire on a port net" }
        antbuf { return "the net is driven by the output of an antenna buffer" }
        default { return "" }
    }
}
# 079: growing a cell to a wider master: the filler run that starts at the cell's right edge must be at least `extra` wide. runs: ant_filler_runs result; row y0 of the cell, right edge x1.
# Returns {ok names reason}: the names of the fillers to remove (those overlapping [x1, x1 + extra rounded up to whole sites]).
proc eco079_grow_plan {runs y0 x1 extra site_w {tol 0.001}} {
    set span [expr {ceil($extra / $site_w - 1e-6) * $site_w}]
    foreach r $runs {
        if {abs([dict get $r y0] - $y0) > $tol} continue
        if {abs([dict get $r x0] - $x1) > $tol} continue
        if {[dict get $r x1] - [dict get $r x0] < $span - $tol} { return [list 0 {} "the free run at the right edge is [format %.2f [expr {[dict get $r x1] - [dict get $r x0]}]] um wide, [format %.2f $span] um needed"] }
        set names {}
        foreach f [dict get $r fillers] {
            lassign $f fname fx0 fx1
            if {min($fx1, $x1 + $span) - max($fx0, $x1) > $tol} { lappend names $fname }
        }
        return [list 1 $names ""]
    }
    return [list 0 {} "no free filler run starts at the right edge of the cell"]
}
# 079 fix: the value of `set NAME value ;# ...` in another script's text (so a limit used in step 6c is read, not retyped); error when absent or not a number
proc eco079_param_from_text {text name} {
    if {![regexp -line "^set\\s+$name\\s+(\\S+)" $text -> v]} { error "parameter $name not found in the text" }
    set v [string trim $v "\""]
    if {![string is double -strict $v]} { error "parameter $name is '$v', not a number" }
    return $v
}
# 079 fix: the input gate area (um^2, ANTENNAGATEAREA) of a LEF cell with exactly one signal input; 0.0 when the cell has no or several signal inputs or the gate area is not given. lefcell = a value of ant_parse_lef.
proc eco079_in_gate {lefcell} {
    set ins {}
    dict for {pn pd} [dict get $lefcell pins] {
        if {[dict get $pd use] eq "POWER" || [dict get $pd use] eq "GROUND" || [dict get $pd dir] eq "INOUT"} continue
        if {[dict get $pd dir] eq "INPUT"} { lappend ins $pn }
    }
    if {[llength $ins] != 1} { return 0.0 }
    return [ant_min_or_zero [dict get $lefcell pins [lindex $ins 0] gate]]
}
# 079 fix: the largest distance (um) from a PORT pin to the input pin of a new cell: the tier-1 limit of step 6c, and no larger than the distance at which the predicted antenna ratio
# (ant_ratio, M2/M3 weight) of the port wire reaches the Calibre limit for this cell's input gate area. Returns {limit text}; limit <= 0 means the cell cannot be placed on a port.
proc eco079_port_limit {gate tier1 ratio_limit weight width} {
    if {$gate <= 0} { return [list 0.0 "the input gate area of the cell is unknown"] }
    set dmax [ant_max_dist_for_ratio $gate $width $weight $ratio_limit]
    if {$dmax < $tier1} { return [list $dmax "limited by the predicted antenna ratio $ratio_limit with the input gate [format %.3f $gate] um^2"] }
    return [list $tier1 "the tier-1 limit of step 6c"]
}
# 079 fix: the leaf pins of a port net that belong to an antenna buffer (cell name ${prefix}_*): the antbuf loads that an insertion on the port moves behind the new cell
proc eco079_antbuf_pins {leaf_pins prefix} {
    set out {}
    foreach p $leaf_pins {
        set c [eco079_pin_cell $p]
        if {$c ne "" && [string match "${prefix}_*" [lindex [split $c /] end]]} { lappend out $p }
    }
    return $out
}
# 079 fix: the pins of protected cells (names in `protected`) among `leaf_pins` as expectation records {cell leafpin oldnet}: an insertion on their net may legitimately move them to a PrimeTime net.
proc eco079_protected_moves {leaf_pins protected oldnet} {
    set out {}
    foreach p $leaf_pins {
        set c [eco079_pin_cell $p]
        if {$c ne "" && [lsearch -exact $protected $c] >= 0} { lappend out [list $c [lindex [split $p /] end] $oldnet] }
    }
    return $out
}
# 079 fix: split the differences of the protected-cell snapshot into the expected net moves (pin P of a protected cell went from the net it had to a PrimeTime net, whose name contains `mark`;
# the topology of that insertion was verified at the time) and the rest. Returns {unexpected expected}.
proc eco079_diff_split {diff moves mark} {
    set un {}
    set ex {}
    foreach d $diff {
        set hit 0
        foreach m $moves {
            lassign $m c pn old
            set prefix "$c: pin $pn net $old -> "   ;# (exact text compare: net names such as pwdata[0] contain glob characters)
            if {[string first $prefix $d] == 0 && [string first $mark $d [string length $prefix]] >= 0} { set hit 1; break }
        }
        if {$hit} { lappend ex $d } else { lappend un $d }
    }
    return [list $un $ex]
}
# 079 fix 2: the signal pins of a LEF cell: {input_name output_name}. Exactly one signal input and one signal output (a buffer / delay cell); otherwise an error with the counts.
# Power and ground pins (USE POWER / GROUND) and INOUT pins are not signal pins.
proc eco079_signal_pins {name lefcell} {
    set ins {}
    set outs {}
    dict for {pn pd} [dict get $lefcell pins] {
        if {[dict get $pd use] eq "POWER" || [dict get $pd use] eq "GROUND" || [dict get $pd dir] eq "INOUT"} continue
        if {[dict get $pd dir] eq "INPUT"} { lappend ins $pn }
        if {[dict get $pd dir] eq "OUTPUT"} { lappend outs $pn }
    }
    if {[llength $ins] != 1 || [llength $outs] != 1} { error "cell $name has [llength $ins] signal inputs ($ins) and [llength $outs] signal outputs ($outs), 1 and 1 expected" }
    return [list [lindex $ins 0] [lindex $outs 0]]
}
# 079 fix 2: the names of all power / ground pins in the LEF (dict of ant_parse_lef): they are never on a signal net, but some ICC2 queries return them
proc eco079_pg_names {lef} {
    set out {}
    dict for {m cd} $lef {
        dict for {pn pd} [dict get $cd pins] {
            if {[dict get $pd use] eq "POWER" || [dict get $pd use] eq "GROUND"} { if {[lsearch -exact $out $pn] < 0} { lappend out $pn } }
        }
    }
    return [lsort $out]
}
# 079 fix 2: remove from a list of full pin names those whose last part (the library pin name) is a power / ground pin name
proc eco079_drop_pg {pins pgnames} {
    set out {}
    foreach p $pins { if {[lsearch -exact $pgnames [lindex [split $p /] end]] < 0} { lappend out $p } }
    return $out
}
# 079 fix 2: the topology check of one insertion. The expected sets are built from the SIGNAL pins of the new cell only (input pin sigin = "I", output pin sigout = "Z", full names
# "<bcell>/<pin>"), and power / ground pins are removed from `before` and from both actual sets before comparing. Returns a list of problems (empty = as PrimeTime assumed).
proc eco079_topology_check {dir pin before after_in after_out bcell sigin sigout pgnames} {
    return [eco079_topology_problems $dir $pin [eco079_drop_pg $before $pgnames] [eco079_drop_pg $after_in $pgnames] [eco079_drop_pg $after_out $pgnames] "$bcell/$sigin" "$bcell/$sigout"]
}
# 079 fix 2: the progress line printed every `every` changes (after `done` changes were processed); "" when no line is due
proc eco079_progress {done total ok failed every} {
    if {$done <= 0 || $done % $every != 0} { return "" }
    return "$done of $total changes processed, $ok OK so far, $failed failed"
}
# 079 fix 3: TIER 2 for a PORT insertion: the largest pin-to-cell distance (um) at which the predicted antenna ratio, computed with the TOP_M weight (the worst case: the wire may go up to the top metal)
# and the cell's own input gate area, stays at or below ratio2 (10 percent under the Calibre limit). Returns {limit text}; limit 0.0 = no tier 2 (not larger than tier 1, or unknown gate).
proc eco079_port_tier2 {gate w_topm ratio2 width tier1} {
    if {$gate <= 0} { return [list 0.0 "the input gate area of the cell is unknown"] }
    set d [ant_max_dist_for_ratio $gate $width $w_topm $ratio2]
    if {$d <= $tier1} { return [list 0.0 "the ratio distance [format %.1f $d] um is not larger than the tier-1 limit [format %.1f $tier1] um"] }
    return [list $d "predicted ratio <= $ratio2 with the TOP_M weight $w_topm and the input gate [format %.3f $gate] um^2"]
}
# 079 fix 3: why no usable filler run was found. runs = ant_filler_runs of the WHOLE filler table, bw the cell width, tiers = list of {tier limit}. One text line: the nearest free run wide
# enough with its centre distance and, for every tier, whether the limit was exceeded (and by how much) or was met (then another check rejected the sites).
proc eco079_fail_diag {runs bw site_w px py tiers} {
    set best ""
    set bd 1e18
    set nwide 0
    foreach r $runs {
        set ev [ant_run_eval $r $bw $site_w $px $py 1e18]
        if {![dict get $ev ok]} continue
        incr nwide
        if {[dict get $ev dist] < $bd} { set bd [dict get $ev dist]; set best $r }
    }
    set need [expr {ceil($bw / $site_w - 1e-6) * $site_w}]
    if {$best eq ""} { return "no free filler run in the design is wide enough for the cell ([format %.2f $need] um = [expr {int(ceil($bw / $site_w - 1e-6))}] sites; [llength $runs] runs examined)" }
    set t [format "nearest free run wide enough: row y=%.2f x=%.2f..%.2f (width %.2f um), centre distance from the pin %.1f um ($nwide such runs in the design)" [dict get $best y0] [dict get $best x0] [dict get $best x1] [expr {[dict get $best x1] - [dict get $best x0]}] $bd]
    foreach ti $tiers {
        lassign $ti tn tl
        if {$bd > $tl} { append t [format "; exceeds the tier-%s limit %.1f um by %.1f um" $tn $tl [expr {$bd - $tl}]] } else { append t [format "; within the tier-%s limit %.1f um, so the sites were rejected by another check (see the CHANGE lines)" $tn $tl] }
    }
    return $t
}
# 079 fix 3: the cell that a command depends on when it was created by a skipped / failed change: "" when none. gone = new cell names of skipped or failed insertions.
proc eco079_depends_on_gone {cmd gone} {
    if {[dict get $cmd type] eq "insert_buffer"} {
        if {[dict get $cmd objkind] eq "port"} { return "" }
        set c [eco079_pin_cell [dict get $cmd full_pin]]
    } else {
        set c [dict get $cmd full_inst]
    }
    if {$c ne "" && [lsearch -exact $gone $c] >= 0} { return $c }
    return ""
}
# 079 fix 3: the SKIPPED CHANGES block. skipped = list of dicts idx line pin reason on ("" = the change itself failed, else the cell of the skipped change it depends on); cmds = all commands (to know which
# cell each change creates). One text line per skipped change with its dependants (transitively, by name).
proc eco079_skip_report {skipped cmds} {
    array set made {}
    foreach c $cmds { if {[dict get $c type] eq "insert_buffer"} { set made([dict get $c idx]) [dict get $c cell] } }
    set out {}
    foreach r $skipped {
        set idx [dict get $r idx]
        set deps {}
        if {[info exists made($idx)]} {
            set frontier [list $made($idx)]
            while {[llength $frontier]} {
                set cell [lindex $frontier 0]
                set frontier [lrange $frontier 1 end]
                foreach d $skipped {
                    if {[dict get $d on] eq $cell} {
                        lappend deps [dict get $d idx]
                        if {[info exists made([dict get $d idx])]} { lappend frontier $made([dict get $d idx]) }
                    }
                }
            }
        }
        lappend out [format "change %d (file line %d): pin %s: %s; dependants: %s" $idx [dict get $r line] [dict get $r pin] [dict get $r reason] [expr {[llength $deps] ? [join [lsort -integer -unique $deps] {, }] : {none}}]]
    }
    return $out
}
# 079 fix 3: the STAGE line. No skipped change: the plain line; some: PARTIAL with the count and the numbers.
proc eco079_final_line {nskipped total skipped_nums ninserted nresized nwatch block logfile} {
    set head "STAGE 6g COMPLETE"
    if {$nskipped > 0} { set head "STAGE 6g COMPLETE (PARTIAL: $nskipped of $total changes skipped: [join [lsort -integer $skipped_nums] {, }])" }
    return "$head: $ninserted cells inserted, $nresized cells resized, $nwatch on the ANTENNA WATCH list, $block overwritten in place. Log: $logfile"
}
# 080: the gate decision on one WNS (ns): before / after / tolerance. Returns {status message}: status ok | worse | unreadable. worse = after < before - tolerance.
proc eco079_gate_check {label before after tol} {
    if {![string is double -strict $before] || ![string is double -strict $after]} {
        return [list unreadable "the ECO gate on $label cannot be decided: before '$before', after '$after' (a value is unreadable)"]
    }
    if {$after < $before - $tol} {
        return [list worse "the ECO made $label worse (before [format %+.4f $before], after [format %+.4f $after], tolerance [format %.4f $tol])"]
    }
    return [list ok "$label: before [format %+.4f $before] ns, after [format %+.4f $after] ns, change [format %+.4f [expr {$after - $before}]] ns (tolerance [format %.4f $tol])"]
}
# 080: the path groups whose name contains `pattern`
proc eco079_group_match {names pattern} {
    set out {}
    foreach n $names { if {[string first $pattern $n] >= 0} { lappend out $n } }
    return $out
}
# 080: the violators of the groups that match `pattern`: groups = list of {name wns tns num} (ant072_wns). Returns {wns num}: the worst wns among them and the sum of the numbers; {"" 0} when none matches.
proc eco079_group_violators {groups pattern} {
    set w ""
    set n 0
    foreach g $groups {
        if {[string first $pattern [lindex $g 0]] < 0} continue
        if {$w eq "" || [lindex $g 1] < $w} { set w [lindex $g 1] }
        incr n [lindex $g 3]
    }
    return [list $w $n]
}
# 081: the expected number of hold commands. text = the content of the count file written by pt_eco_probe.tcl, or "" when the file does not exist (exists 0).
# Returns {n source warning}: from the file when it exists (an unreadable file is an ERROR), else the parameter with a WARNING that it is an assumption.
proc eco079_expect_decide {exists text param param_name} {
    if {!$exists} {
        return [list $param "the parameter $param_name (an ASSUMPTION)" "the count file written by pt_eco_probe.tcl does not exist: the expectation $param comes from the parameter $param_name, which is an assumption (the number of commands PrimeTime proposed in the run that made the change file)"]
    }
    if {![regexp -line {^commands\s+([0-9]+)\s*$} $text -> n]} { error "the count file has no line 'commands <N>' (content: '[string trim $text]')" }
    return [list $n "the count file of the probe" ""]
}
# 081: the DRC clean-up. Decision after a check: drc = the count of check_routes ("" = unreadable), round = rounds done, max_rounds. Returns done | retry | exhausted | unreadable.
proc eco081_next_action {drc round max_rounds} {
    if {![string is integer -strict $drc]} { return unreadable }
    if {$drc == 0} { return done }
    if {$round >= $max_rounds} { return exhausted }
    return retry
}
# 081: history = list of {label count} -> "after routing: 1; round 1 (incremental route): 1; round 1 (windows + nets): 0"
proc eco081_history_text {hist} {
    return [join [lmap h $hist {string cat [lindex $h 0] ": " [lindex $h 1]}] "; "]
}
# 081: a DRC error box ("{x0 y0} {x1 y1}" or "x0 y0 x1 y1") widened by margin -> {{x0 y0} {x1 y1}}
proc eco081_window {bbox margin} {
    lassign [ant_bbox_nums $bbox] a b c d
    return [list [list [expr {$a - $margin}] [expr {$b - $margin}]] [list [expr {$c + $margin}] [expr {$d + $margin}]]]
}
# 081: the windows of several error boxes without duplicates and without a window that lies inside another one
proc eco081_windows {bboxes margin} {
    set wins {}
    foreach b $bboxes { set w [eco081_window $b $margin]; if {[lsearch -exact $wins $w] < 0} { lappend wins $w } }
    set out {}
    foreach w $wins {
        set inside 0
        foreach v $wins {
            if {$v eq $w} continue
            if {[lindex $v 0 0] <= [lindex $w 0 0] && [lindex $v 0 1] <= [lindex $w 0 1] && [lindex $v 1 0] >= [lindex $w 1 0] && [lindex $v 1 1] >= [lindex $w 1 1]} { set inside 1; break }
        }
        if {!$inside} { lappend out $w }
    }
    return $out
}
# 081: nets to re-route: those not protected; returns {use skipped}
proc eco081_split_nets {nets protected} {
    set use {}
    set skipped {}
    foreach n [lsort -unique $nets] { if {[lsearch -exact $protected $n] >= 0} { lappend skipped $n } else { lappend use $n } }
    return [list $use $skipped]
}
# 081: one DRC error as a line: rec = dict with any of type_name layer bounding_box nets
proc eco081_error_line {rec} {
    set t "n/a"; set l "n/a"; set b "n/a"; set n "n/a"
    if {[dict exists $rec type_name] && [dict get $rec type_name] ne ""} { set t [dict get $rec type_name] }
    foreach k {layer layers} { if {[dict exists $rec $k] && [dict get $rec $k] ne ""} { set l [dict get $rec $k]; break } }
    if {[dict exists $rec bounding_box] && [dict get $rec bounding_box] ne ""} { set b [dict get $rec bounding_box] }
    if {[dict exists $rec nets] && [llength [dict get $rec nets]] > 0} { set n [join [dict get $rec nets] ,] }
    return "rule $t, layer $l, box $b, nets $n"
}
# ---- END PURE TCL 079 ----

# 079: take the helper procs from the text of antenna_port_buffers.tcl (pure block 068 and the ICC2 helpers) and of timing_closure.tcl (pure block 072 and its ICC2 helpers): same code, no copy
proc eco079_read {f} { set fp [open $f r]; set s [read $fp]; close $fp; return $s }
set ec_src [eco079_read ${SCRIPT_DIR}/antenna_port_buffers.tcl]
set ec_b [string first "# ---- BEGIN PURE TCL 068 ----" $ec_src]
set ec_e [string first "# ---- END PURE TCL 068 ----" $ec_src]
set ec_h [string first "# 068: ICC2 side helpers" $ec_src]
set ec_f [string first "file mkdir \$LOG_DIR" $ec_src]
if {$ec_b < 0 || $ec_e < 0 || $ec_h < 0 || $ec_f < 0 || $ec_f <= $ec_h} { error "ERROR 079: markers not found in ${SCRIPT_DIR}/antenna_port_buffers.tcl" }
eval [string range $ec_src $ec_b $ec_e]
eval [string range $ec_src $ec_h [expr {$ec_f - 1}]]
# 079 fix: the antenna numbers used for insertions on a PORT are read from antenna_port_buffers.tcl (one source), printed below
foreach ec_n {MAX_PIN_BUF_DIST ANT_RATIO_LIMIT ANT_WEIGHT_PINWIRE WIRE_WIDTH_UM ANT_WEIGHT_TOPM TIER2_RATIO} {
    if {[catch {set PORT_$ec_n [eco079_param_from_text $ec_src $ec_n]} ec_err]} { error "ERROR 079: ${SCRIPT_DIR}/antenna_port_buffers.tcl: $ec_err" }
}
set ec_src2 [eco079_read ${SCRIPT_DIR}/timing_closure.tcl]
set ec_b [string first "# ---- BEGIN PURE TCL 072 ----" $ec_src2]
set ec_e [string first "# ---- END PURE TCL 072 ----" $ec_src2]
set ec_h [string first "# 072: ICC2 side helpers of this script" $ec_src2]
set ec_f [string first "file mkdir \$LOG_DIR" $ec_src2]
if {$ec_b < 0 || $ec_e < 0 || $ec_h < 0 || $ec_f < 0 || $ec_f <= $ec_h} { error "ERROR 079: markers not found in ${SCRIPT_DIR}/timing_closure.tcl" }
eval [string range $ec_src2 $ec_b $ec_e]
eval [string range $ec_src2 $ec_h [expr {$ec_f - 1}]]
unset ec_src ec_src2 ec_b ec_e ec_h ec_f ec_n

# 079: ICC2 side helpers of this script (not tested locally)
proc eco079_lookup_pin {full} {   ;# 079: the pin object name, or "" ; VERIFY get_pins -exact with a hierarchical leaf pin name
    set p [get_pins -quiet -exact $full]
    if {[sizeof_collection $p] == 1} { return [get_object_name $p] }
    set p [get_pins -quiet -hierarchical -filter "full_name == $full"]
    if {[sizeof_collection $p] == 1} { return [get_object_name $p] }
    return ""
}
proc eco079_lookup_cell {full} {
    set c [get_cells -quiet -exact $full]
    if {[sizeof_collection $c] == 1} { return [get_object_name $c] }
    set c [get_cells -quiet -hierarchical -filter "full_name == $full"]
    if {[sizeof_collection $c] == 1} { return [get_object_name $c] }
    return ""
}
proc eco079_lookup_net {full} {
    set n [get_nets -quiet -exact $full]
    if {[sizeof_collection $n] == 1} { return [get_object_name $n] }
    set n [get_nets -quiet -hierarchical -filter "full_name == $full"]
    if {[sizeof_collection $n] == 1} { return [get_object_name $n] }
    return ""
}
proc eco079_lookup_port {name} {   ;# 079 fix: the port object name or "" ; -exact as antenna_port_buffers.tcl (names with brackets such as dma_rdata[14])
    set p [get_ports -quiet -exact $name]
    if {[sizeof_collection $p] == 1} { return [get_object_name $p] }
    return ""
}
proc eco079_port_xy {name} {   ;# 079 fix: the centre of the first terminal of the port (the pin location, as antenna_port_buffers.tcl); "" if none
    set t [get_terminals -quiet -of_objects [get_ports -quiet -exact $name]]
    if {[sizeof_collection $t] == 0} { return "" }
    return [ant068_centre [index_collection $t 0]]
}
proc eco079_net_of_port {name} {   ;# 079 fix: the net object name of a port, "" if none
    set n [get_nets -quiet -of_objects [get_ports -quiet -exact $name]]
    if {[sizeof_collection $n] >= 1} { return [get_object_name [index_collection $n 0]] }
    return ""
}
proc eco079_net_of_pin {pinname} {   ;# the net object name of a pin, "" if none
    set n [get_nets -quiet -of_objects [get_pins -quiet -exact $pinname]]
    if {[sizeof_collection $n] >= 1} { return [get_object_name [index_collection $n 0]] }
    return ""
}
proc eco079_net_leaf_pins {netname} {
    set out {}
    foreach_in_collection p [get_pins -quiet -leaf -of_objects [get_nets -quiet -exact $netname]] { lappend out [get_object_name $p] }
    upvar #0 ea_pgnames pgn   ;# 079 fix 2: power / ground pins never belong to the signal topology (set from the LEF in step 3)
    if {[info exists pgn]} { return [eco079_drop_pg $out $pgn] }
    return $out
}
proc eco079_driver_info {netname} {   ;# {driver_cells has_input_port driver_xy}: the cells of the output leaf pins of the net, an input port on it, a point to measure from
    set cells {}
    set xy ""
    foreach_in_collection p [get_pins -quiet -leaf -of_objects [get_nets -quiet -exact $netname] -filter "direction == out"] {
        lappend cells [get_object_name [get_cells -quiet -of_objects $p]]
        if {$xy eq ""} { set xy [ant068_centre $p] }
    }
    set hp 0
    foreach_in_collection po [get_ports -quiet -of_objects [get_nets -quiet -exact $netname]] {   ;# VERIFY get_ports -of_objects <net>
        if {[get_attribute -quiet $po direction] eq "in"} { set hp 1; if {$xy eq ""} { set xy [ant068_centre $po] } }
    }
    return [list $cells $hp $xy]
}

proc eco081_list_errors {label} {   ;# 081: the DRC errors of check_routes as a list of dicts {type_name layer(s) bounding_box nets}; every failure is printed raw, nothing is swallowed. VERIFY every command here.
    global DRC_ERR_NAME eco081_info_done eco081_noattr
    if {![info exists eco081_info_done]} {
        set eco081_info_done 1
        foreach pat {*drc_error*} { if {[catch {help $pat} herr]} { puts ">>> 081 help $pat failed: $herr" } }
        foreach c {open_drc_error_data get_drc_error_data get_drc_errors write_drc_error_data close_drc_error_data} { puts ">>> 081 command $c: [expr {[llength [info commands $c]] ? {exists} : {NOT found}}]" }
        if {[catch {redirect -variable la_txt { list_attributes -class drc_error }; puts ">>> 081 drc_error attributes: [join [lrange [split $la_txt "\n"] 0 40] { }]"} lerr]} { puts ">>> 081 list_attributes -class drc_error failed: $lerr" }
    }
    set coll ""
    set got 0
    foreach open_cmd [list "" "open_drc_error_data $DRC_ERR_NAME" "open_drc_error_data -name $DRC_ERR_NAME"] {
        if {$open_cmd ne ""} { if {[catch {eval $open_cmd} oerr]} { puts ">>> 081 $label: $open_cmd failed: $oerr"; continue } else { puts ">>> 081 $label: $open_cmd ok" } }
        if {[catch {set coll [get_drc_errors -error_data $DRC_ERR_NAME *]} gerr]} { puts ">>> 081 $label: get_drc_errors -error_data $DRC_ERR_NAME * failed: $gerr"; continue }
        set got 1
        break
    }
    set recs {}
    if {!$got} {
        puts ">>> 081 $label: the DRC errors could not be listed with get_drc_errors; trying write_drc_error_data"
        set ef $::LOG_DIR/6g_drc_errors.txt
        if {[catch {write_drc_error_data $ef} werr] && [catch {write_drc_error_data -file $ef} werr2]} { puts ">>> 081 $label: write_drc_error_data failed: $werr / $werr2" } elseif {[file exists $ef]} { puts ">>> 081 $label: error data written to $ef; first lines: [join [lrange [split [eco079_read $ef] "\n"] 0 15] { | }]" }
        return $recs
    }
    puts ">>> 081 $label: [sizeof_collection $coll] DRC error object(s)"
    foreach_in_collection e $coll {
        set rec [dict create]
        foreach a {type_name layer layers bounding_box} {
            set v ""
            catch {set v [get_attribute -quiet $e $a]}
            if {$v ne ""} { dict set rec $a $v } else { set eco081_noattr($a) 1 }
        }
        set nets {}
        catch { foreach_in_collection o [get_attribute -quiet $e objects] { if {[get_attribute -quiet $o object_class] eq "net"} { lappend nets [get_object_name $o] } } }   ;# VERIFY the attribute objects
        dict set rec nets $nets
        lappend recs $rec
    }
    if {[array exists eco081_noattr]} { puts ">>> 081 NOTE: attributes empty or not readable on the error objects: [lsort [array names eco081_noattr]]" }
    return $recs
}
proc eco081_nets_in_window {w} {   ;# 081: signal net names whose shapes intersect the window; VERIFY get_nets -intersect and the attribute net_type
    set out {}
    if {[catch {
        foreach_in_collection n [get_nets -quiet -intersect $w] {
            set nt [get_attribute -quiet $n net_type]
            if {$nt eq "power" || $nt eq "ground"} continue
            lappend out [get_object_name $n]
        }
    } err]} { puts ">>> 081 get_nets -intersect $w failed: $err" }
    return $out
}
proc eco081_cleanup {protected_nets} {   ;# 081: returns {drc open antenna history}; the DRC clean-up loop (rounds, windows, nets), prints everything
    global DRC_ROUNDS DRC_WINDOW_MARGIN
    set hist {}
    lassign [ant068_check_routes_counts] d o a
    lappend hist [list "after routing" $d]
    puts ">>> 081 DRC clean-up: check_routes after routing: DRCs $d, open nets $o, ICC2 antenna violations $a"
    set round 0
    while {1} {
        set act [eco081_next_action $d $round $DRC_ROUNDS]
        if {$act ne "retry"} break
        incr round
        puts ">>> 081 DRC clean-up round $round of $DRC_ROUNDS: $d DRC(s) before"
        set recs [eco081_list_errors "round $round"]
        foreach r $recs { puts ">>> 081   DRC: [eco081_error_line $r]" }
        if {[catch {route_detail -incremental true -max_number_iterations 40} err]} { puts ">>> 081 route_detail -incremental failed: $err" }
        lassign [ant068_check_routes_counts] d o a
        lappend hist [list "round $round (incremental route)" $d]
        puts ">>> 081 round $round after route_detail -incremental: DRCs $d, open nets $o"
        if {[eco081_next_action $d $round $DRC_ROUNDS] eq "done"} continue
        set recs [eco081_list_errors "round $round remaining"]
        set boxes {}
        foreach r $recs { if {[dict exists $r bounding_box]} { lappend boxes [dict get $r bounding_box] } }
        set wins [eco081_windows $boxes $DRC_WINDOW_MARGIN]
        set nets {}
        foreach w $wins {
            set nw [eco081_nets_in_window $w]
            puts ">>> 081 round $round window $w: [llength $nw] net(s)[expr {[llength $nw] ? " : [lrange $nw 0 7]" : {}}]"
            lappend nets {*}$nw
            if {[catch {route_detail -incremental true -max_number_iterations 40 -coordinates [list $w]} err]} { puts ">>> 081 route_detail -coordinates $w failed: $err" }
        }
        foreach r $recs { lappend nets {*}[dict get $r nets] }
        lassign [eco081_split_nets $nets $protected_nets] use skipped
        if {[llength $skipped]} { puts ">>> 081 round $round: [llength $skipped] protected net(s) (antenna buffers / clock root) are NOT re-routed: $skipped" }
        if {[llength $use] > 0} {
            set coll [get_nets -quiet -exact $use]
            puts ">>> 081 round $round: route_eco -nets <[sizeof_collection $coll] nets> -reuse_existing_global_route false"
            if {[catch {route_eco -nets $coll -reuse_existing_global_route false -reroute modified_nets_first_then_others -max_detail_route_iterations 60} err]} { puts ">>> 081 route_eco -nets failed: $err" }
            if {[catch {route_detail -incremental true -max_number_iterations 40} err]} { puts ">>> 081 route_detail -incremental failed: $err" }
        } else { puts ">>> 081 round $round: no net found for the error windows (the windowed route_detail above is all that was done)" }
        lassign [ant068_check_routes_counts] d o a
        lappend hist [list "round $round (windows + nets)" $d]
        puts ">>> 081 round $round after the windows and nets: DRCs $d, open nets $o"
    }
    puts ">>> 081 DRC clean-up result: [eco081_next_action $d $round $DRC_ROUNDS]; DRC counts: [eco081_history_text $hist]"
    if {[string is integer -strict $d] && $d > 0} {
        foreach r [eco081_list_errors "REMAINING after $round round(s)"] { puts ">>> 081 REMAINING DRC: [eco081_error_line $r]" }
    }
    return [list $d $o $a $hist]
}
proc eco079_in2out_state {label} {   ;# 080: {wns num source}: setup WNS of the in2out group (even when it has no violator), its violating endpoints, and where the WNS came from
    global SETUP_SCEN GATE_GROUP_PATTERN CLK_PORT
    lassign [ant072_wns $SETUP_SCEN max] w t n groups
    lassign [eco079_group_violators $groups $GATE_GROUP_PATTERN] gv_w gv_n
    set gnames {}
    catch { foreach_in_collection g [get_path_groups -quiet *] { lappend gnames [get_object_name $g] } }   ;# VERIFY get_path_groups
    set match [eco079_group_match $gnames $GATE_GROUP_PATTERN]
    set gw ""
    foreach g $match {
        if {[catch {
            set p [get_timing_paths -scenarios $SETUP_SCEN -delay_type max -groups $g -max_paths 1]   ;# VERIFY get_timing_paths -groups
            if {[sizeof_collection $p] > 0} { set sl [get_attribute $p slack]; if {$gw eq "" || $sl < $gw} { set gw $sl } }
        } err]} { puts ">>> 080 $label in2out: the WNS of path group $g could not be read: $err" }
    }
    set fw ""
    if {[catch {
        set ins [remove_from_collection [all_inputs] [get_ports -quiet -exact $CLK_PORT]]
        # 081: only input ports whose net has loads: an unused port (the unused paddr bits) is "not a timing startpoint" (TIM-010) and made a warning per port
        set used ""
        set nunused 0
        foreach_in_collection ip $ins {
            set nt [get_nets -quiet -of_objects $ip]
            if {[sizeof_collection $nt] > 0 && [sizeof_collection [get_pins -quiet -leaf -of_objects $nt -filter "direction == in"]] > 0} { append_to_collection used $ip } else { incr nunused }
        }
        puts ">>> 080 $label in2out: $nunused input port(s) without a loaded net are left out of the -from list (TIM-010 'not a timing startpoint' silenced)"
        if {$used ne ""} { set ins $used }
        set p [get_timing_paths -scenarios $SETUP_SCEN -delay_type max -from $ins -to [all_outputs] -max_paths 1]   ;# VERIFY get_timing_paths -from <ports> -to <ports>
        if {[sizeof_collection $p] > 0} { set fw [get_attribute $p slack] }
    } err]} { puts ">>> 080 $label in2out: the worst input-to-output path could not be read: $err" }
    if {$gw ne ""} { set src "path group(s) $match" } elseif {$fw ne ""} { set src "worst setup path from an input port to an output port (no path group named *$GATE_GROUP_PATTERN* was readable; groups seen: $gnames)"; set gw $fw } else { set src "UNREADABLE (groups seen: $gnames)" }
    puts ">>> 080 $label in2out: WNS [expr {$gw eq {} ? {UNKNOWN} : $gw}] ns from $src; worst input-to-output path [expr {$fw eq {} ? {UNKNOWN} : $fw}] ns; violating endpoints in the group: $gv_n"
    return [list $gw $gv_n $src]
}

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/6g_pt_eco_apply.log {

    set ea_failures {}

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} { close_blocks -force $open_blk }
    set open_lib [get_libs -quiet *]
    if {[sizeof_collection $open_lib] > 0} { foreach_in_collection lib_obj $open_lib { close_lib -force $lib_obj } }
    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    open_block ${DESIGN_NAME}.dlib:${DESIGN_NAME}_route
    current_block ${DESIGN_NAME}_route
    link_block
    puts ">>> 079 block ${DESIGN_NAME}_route opened (it is overwritten in place at the end; the README tells the user to back up the library first)"

    # --------------------------------------------------------------------------
    # 1. Parse the change files
    # --------------------------------------------------------------------------
    if {![file exists $ECO_HOLD_FILE] || [file size $ECO_HOLD_FILE] == 0} { error "ERROR 079: the hold change file $ECO_HOLD_FILE is missing or empty (pt_eco_probe.tcl writes it; copy it from the PrimeTime run to $PT_DIR)" }
    set ea_files [list hold $ECO_HOLD_FILE]
    if {[file exists $ECO_SETUP_FILE] && [file size $ECO_SETUP_FILE] > 0} { lappend ea_files setup $ECO_SETUP_FILE } else { puts ">>> 079 the optional setup change file $ECO_SETUP_FILE does not exist (or is empty): the setup ECO is SKIPPED" }
    set ea_cmds {}
    set ea_perr {}
    foreach {kind f} $ea_files {
        set pr [eco079_parse [eco079_read $f]]
        set k 0
        foreach c [dict get $pr cmds] {
            dict set c file $kind
            dict set c idx [expr {[llength $ea_cmds] + 1}]
            lappend ea_cmds $c
            incr k
        }
        foreach e [dict get $pr errors] { lappend ea_perr "$f: $e" }
        puts ">>> 079 $kind change file $f: $k change command(s)"
    }
    if {[llength $ea_perr] > 0} { error "ERROR 079: [llength $ea_perr] line(s) of the change files are not understood, NOTHING was changed:\n    [join $ea_perr "\n    "]" }
    set ea_nins 0; set ea_nsize 0
    foreach c $ea_cmds { if {[dict get $c type] eq "insert_buffer"} { incr ea_nins } else { incr ea_nsize } }
    puts ">>> 079 changes in total: $ea_nins insert_buffer, $ea_nsize size_cell"
    set ea_hold_n 0
    foreach c $ea_cmds { if {[dict get $c file] eq "hold"} { incr ea_hold_n } }
    set ea_cf_exists [expr {[file exists $ECO_COUNT_FILE] && [file size $ECO_COUNT_FILE] > 0}]
    set ea_cf_text ""
    if {$ea_cf_exists} { set ea_cf_text [eco079_read $ECO_COUNT_FILE] }
    if {[catch {lassign [eco079_expect_decide $ea_cf_exists $ea_cf_text $EXPECT_HOLD_CMDS EXPECT_HOLD_CMDS] ea_expect ea_expect_src ea_expect_warn} err]} { error "ERROR 079: $ECO_COUNT_FILE: $err (nothing changed)" }
    if {$ea_expect_warn ne ""} { puts ">>> 079 WARNING: $ea_expect_warn" }
    puts ">>> 079 expected number of hold commands: $ea_expect (from $ea_expect_src[expr {$ea_cf_exists ? ", $ECO_COUNT_FILE" : {}}])"
    lassign [eco079_count_check "hold change file commands" $ea_hold_n $ea_expect] ok msg
    puts ">>> 079 CHECK $msg"
    if {!$ok} { error "ERROR 079: $msg (nothing changed)" }

    # --------------------------------------------------------------------------
    # 2. Pins, references, names (nothing is changed on any error here)
    # --------------------------------------------------------------------------
    set ea_prob {}
    set ea_deferred 0
    set ea_nport 0
    foreach c $ea_cmds {
        set idx [dict get $c idx]
        if {[dict get $c type] eq "insert_buffer" && [dict get $c objkind] eq "port"} {
            set pn [dict get $c full_pin]
            if {[eco079_lookup_port $pn] eq ""} {
                lappend ea_prob "change $idx (line [dict get $c line]): port $pn not found in the design"
            } else {
                incr ea_nport
                set pdir [get_attribute -quiet [get_ports -exact $pn] direction]   ;# VERIFY port attribute direction (in / out / inout)
                if {$pdir ne "in"} { lappend ea_prob "change $idx (line [dict get $c line]): port $pn has direction '$pdir', only input ports are supported (the loads move behind the new cell)" }
                if {[eco079_port_xy $pn] eq ""} { lappend ea_prob "change $idx (line [dict get $c line]): port $pn has no terminal (no pin location)" }
                if {[eco079_net_of_port $pn] eq ""} { lappend ea_prob "change $idx (line [dict get $c line]): port $pn has no net" }
            }
        } elseif {[dict get $c type] eq "insert_buffer"} {
            if {[eco079_is_deferred $ea_cmds $idx [dict get $c full_pin] 0]} { incr ea_deferred; continue }
            if {[eco079_lookup_pin [dict get $c full_pin]] eq ""} { lappend ea_prob "change $idx (line [dict get $c line]): pin [dict get $c full_pin] not found" }
        } else {
            if {[eco079_is_deferred $ea_cmds $idx [dict get $c full_inst] 1]} { incr ea_deferred; continue }
            if {[eco079_lookup_cell [dict get $c full_inst]] eq ""} { lappend ea_prob "change $idx (line [dict get $c line]): cell [dict get $c full_inst] not found" }
        }
    }
    puts ">>> 079 pins/ports/cells checked: [llength $ea_cmds] changes ($ea_nport on a top-level port), $ea_deferred refer to a cell that an earlier insertion creates (looked up when applied), [llength $ea_prob] not found"
    foreach p $ea_prob { puts ">>> 079 ERROR $p" }

    set ea_libnames {}
    foreach_in_collection lc [get_lib_cells -quiet ${STD_LIB}/*] { lappend ea_libnames [lindex [split [get_object_name $lc] /] end] }   ;# the library prefix is the design's reference library (STD_LIB as in cts.tcl)
    set ea_rtab [eco079_ref_table $ea_cmds]
    puts ">>> 079 reference table (reference, count, in library, don't-use):"
    foreach r [lsort [dict keys $ea_rtab]] { puts ">>> 079   [format {%-10s %4d  in library: %-3s  don't-use: %s} $r [dict get $ea_rtab $r] [expr {[lsearch -exact $ea_libnames $r] >= 0 ? {yes} : {NO}}] [expr {[ant_dont_use $r $DONT_USE_PATTERNS] eq {} ? {no} : {YES}}]]" }
    foreach p [eco079_ref_problems [dict keys $ea_rtab] $ea_libnames $DONT_USE_PATTERNS] { lappend ea_prob $p; puts ">>> 079 ERROR $p" }
    set ea_ex_cells {}
    set ea_ex_nets {}
    foreach c $ea_cmds {
        if {[dict get $c type] ne "insert_buffer"} continue
        if {[eco079_lookup_cell [dict get $c cell]] ne ""} { lappend ea_ex_cells [dict get $c cell] }
        if {[eco079_lookup_net [dict get $c net]] ne ""} { lappend ea_ex_nets [dict get $c net] }
    }
    foreach p [eco079_name_problems $ea_cmds $ea_ex_cells $ea_ex_nets] { lappend ea_prob $p; puts ">>> 079 ERROR $p" }
    set ea_pre [get_cells -quiet -hierarchical -filter "name =~ *${NEW_CELL_MARK}*"]
    if {[sizeof_collection $ea_pre] > 0} { lappend ea_prob "[sizeof_collection $ea_pre] cell(s) with $NEW_CELL_MARK in the name already exist: this change list was applied before"; puts ">>> 079 ERROR [lindex $ea_prob end]" }
    if {[llength $ea_prob] > 0} { error "ERROR 079: [llength $ea_prob] problem(s) found before any change, NOTHING was changed (listed above)" }

    # --------------------------------------------------------------------------
    # 3. LEF sizes, BEFORE metrics, protected cells
    # --------------------------------------------------------------------------
    set fp [open $STD_LEF r]
    set ea_lef [ant_parse_lef [read $fp]]
    close $fp
    foreach r [dict keys $ea_rtab] {
        if {![dict exists $ea_lef $r] || [dict get $ea_lef $r w] eq ""} { error "ERROR 079: reference $r has no SIZE in the LEF $STD_LEF" }
    }
    set ea_site_w 1e9
    foreach f $FILLER_REFS { if {[dict exists $ea_lef $f] && [dict get $ea_lef $f w] ne "" && [dict get $ea_lef $f w] < $ea_site_w} { set ea_site_w [dict get $ea_lef $f w] } }
    if {$ea_site_w > 1e8} { error "ERROR 079: none of the filler masters $FILLER_REFS is in the LEF, the site width is unknown" }
    puts ">>> 079 site width $ea_site_w um; cell widths (um): [lmap r [lsort [dict keys $ea_rtab]] {list $r [dict get $ea_lef $r w]}]"

    set ea_pgnames [eco079_pg_names $ea_lef]
    puts ">>> 079 power / ground pin names (from the LEF, removed from every pin set of the topology check): $ea_pgnames"
    if {[llength $ea_pgnames] == 0} { error "ERROR 079: no power/ground pin found in the LEF (USE POWER / GROUND): the topology check cannot filter them (nothing changed)" }
    set ea_sig [dict create]
    foreach c $ea_cmds {
        if {[dict get $c type] ne "insert_buffer"} continue
        set r [dict get $c ref]
        if {[dict exists $ea_sig $r]} continue
        if {[catch {dict set ea_sig $r [eco079_signal_pins $r [dict get $ea_lef $r]]} err]} { error "ERROR 079: reference $r cannot be inserted as a buffer: $err (nothing changed)" }
        puts ">>> 079 reference $r: signal input [lindex [dict get $ea_sig $r] 0], signal output [lindex [dict get $ea_sig $r] 1]"
    }
    set ea_gate [dict create]
    foreach c $ea_cmds {
        if {[dict get $c type] eq "insert_buffer" && [dict get $c objkind] eq "port"} {
            set r [dict get $c ref]
            if {![dict exists $ea_gate $r]} {
                dict set ea_gate $r [eco079_in_gate [dict get $ea_lef $r]]
                lassign [eco079_port_limit [dict get $ea_gate $r] $PORT_MAX_PIN_BUF_DIST $PORT_ANT_RATIO_LIMIT $PORT_ANT_WEIGHT_PINWIRE $PORT_WIRE_WIDTH_UM] pl ptxt
                puts ">>> 079 port insertions with $r: input gate [format %.3f [dict get $ea_gate $r]] um^2, distance limit pin-to-cell [format %.1f $pl] um ($ptxt; ratio limit $PORT_ANT_RATIO_LIMIT, weight $PORT_ANT_WEIGHT_PINWIRE, wire width $PORT_WIRE_WIDTH_UM, all read from antenna_port_buffers.tcl)"
                if {$pl <= 0} { error "ERROR 079: reference $r cannot be placed on a port: $ptxt (nothing changed)" }
                lassign [eco079_port_tier2 [dict get $ea_gate $r] $PORT_ANT_WEIGHT_TOPM $PORT_TIER2_RATIO $PORT_WIRE_WIDTH_UM $pl] pl2 ptxt2
                if {$pl2 > 0} { puts ">>> 079 port insertions with $r: TIER 2 limit pin-to-cell [format %.1f $pl2] um ($ptxt2; TOP_M weight $PORT_ANT_WEIGHT_TOPM, ratio limit $PORT_TIER2_RATIO, both read from antenna_port_buffers.tcl)" } else { puts ">>> 079 port insertions with $r: NO tier 2 ($ptxt2)" }
            }
        }
    }
    set ea_m0 [ant072_metrics "079 BEFORE"]
    set ea_g0 [eco079_in2out_state "079 BEFORE"]
    lassign [ant068_check_routes_counts] ea_drc0 ea_open0 ea_ant0
    puts ">>> 079 check_routes BEFORE: DRCs $ea_drc0, open nets $ea_open0, ICC2 antenna violations $ea_ant0"

    set ea_names {}
    foreach_in_collection c [get_cells -quiet ${BUF_PREFIX}_*] { lappend ea_names [get_object_name $c] }
    set ea_nant [llength $ea_names]
    if {$ea_nant != $EXPECT_ANTBUF} { error "ERROR 079: $ea_nant ${BUF_PREFIX}_* cells found, $EXPECT_ANTBUF expected: this is not the block after antenna_port_buffers.tcl (nothing changed)" }
    set ea_loads [ant068_net_leaf_pins $CLK_PORT]
    if {[llength $ea_loads] != 1} { error "ERROR 079: the clock port net $CLK_PORT has [llength $ea_loads] leaf loads, 1 expected (the CTS root)" }
    set ea_root [get_object_name [get_cells -quiet -of_objects [get_pins -quiet -exact [lindex $ea_loads 0]]]]
    lappend ea_names $ea_root
    set ea_snap0 [lmap nm $ea_names {ant072_snapshot $nm}]
    set ea_pnets {}
    foreach s $ea_snap0 { foreach e [dict get $s pins] { set pn [lindex $e 1]; if {$pn ne "-" && $pn ne "VDD" && $pn ne "VSS" && [lsearch -exact $ea_pnets $pn] < 0} { lappend ea_pnets $pn } } }
    puts ">>> 079 protected cells: $ea_nant ${BUF_PREFIX}_* + the clock root $ea_root ([dict get [lindex $ea_snap0 end] ref]); signal nets [llength $ea_pnets]"
    set ea_pcells [get_cells -quiet -exact $ea_names]
    if {$UNPROTECT_DURING} {
        catch {set_dont_touch $ea_pcells false}
        catch {set_dont_touch [get_nets -quiet -exact $ea_pnets] false}
        puts ">>> 079 dont_touch of the protected cells and nets switched OFF while the changes are applied (UNPROTECT_DURING 1); the snapshot comparison at the end is the guard"
    }

    # --------------------------------------------------------------------------
    # 4. Fillers into a table; apply the changes one at a time
    # --------------------------------------------------------------------------
    set ea_filter [join [lmap f $FILLER_REFS {string cat "ref_name == " $f}] " || "]
    set ea_ftable [ant070_all_fillers $ea_filter]
    puts ">>> 079 filler table: [llength $ea_ftable] filler instances"
    if {[llength $ea_ftable] == 0} { error "ERROR 079: no filler instance found with '$ea_filter'" }
    set ea_nfill0 [llength $ea_ftable]
    set ea_done {}
    set ea_failed {}
    set ea_watch {}
    set ea_touched {}
    set ea_moves {}
    set ea_removed 0
    set ea_ins_err_shown 0
    set ea_skipped {}
    set ea_gone {}
    foreach c $ea_cmds {
        set idx [dict get $c idx]
        set pl [eco079_progress [expr {$idx - 1}] [llength $ea_cmds] [llength $ea_done] [llength $ea_failed] 10]
        if {$pl ne ""} { puts ">>> 079 PROGRESS $pl" }
        set dep [eco079_depends_on_gone $c $ea_gone]
        if {$dep ne ""} {   ;# 079 fix 3: uses a pin of a cell that a skipped / failed change should have created
            set dreason "uses a pin of $dep, the cell of a skipped or failed change"
            puts ">>> 079 CHANGE $idx [expr {$ALLOW_PARTIAL ? {SKIPPED} : {FAILED}}]: $dreason"
            if {$ALLOW_PARTIAL} { lappend ea_skipped [dict create idx $idx line [dict get $c line] pin [expr {[dict get $c type] eq {insert_buffer} ? [dict get $c full_pin] : [dict get $c full_inst]}] reason $dreason on $dep] } else { lappend ea_failed "change $idx: $dreason" }
            if {[dict get $c type] eq "insert_buffer"} { lappend ea_gone [dict get $c cell] }
            continue
        }
        set ref [dict get $c ref]
        set lcname ${STD_LIB}/$ref
        set lc [get_lib_cells -quiet -exact $lcname]
        if {[sizeof_collection $lc] != 1} { lappend ea_failed "change $idx: library cell $lcname not found"; continue }
        set bw [dict get $ea_lef $ref w]
        set bh [dict get $ea_lef $ref h]
        if {[dict get $c type] eq "size_cell"} {
            # ---- size_cell: same cell, other master; the cell may grow to the right into free filler sites ----
            set inst [eco079_lookup_cell [dict get $c full_inst]]
            if {$inst eq ""} { lappend ea_failed "change $idx: cell [dict get $c full_inst] not found"; continue }
            set cc [get_cells -exact $inst]
            set oldref [get_attribute -quiet $cc ref_name]
            lassign [ant068_bbox_of $cc] cx0 cy0 cx1 cy1
            set extra [expr {$bw - ($cx1 - $cx0)}]
            set rm {}
            if {$extra > 0.001} {
                lassign [eco079_grow_plan [ant_filler_runs $ea_ftable] $cy0 $cx1 $extra $ea_site_w] gok rm greason
                if {!$gok} {
                    set fmsg "$inst $oldref -> $ref needs [format %.2f $extra] um more width: $greason"
                    puts ">>> 079 SIZE change $idx [expr {$ALLOW_PARTIAL ? {SKIPPED} : {FAILED}}]: $fmsg"
                    if {$ALLOW_PARTIAL} { lappend ea_skipped [dict create idx $idx line [dict get $c line] pin $inst reason $fmsg on {}] } else { lappend ea_failed "change $idx: $fmsg" }
                    continue
                }
                remove_cells [get_cells -exact $rm]
                set ea_ftable [ant_rows_remove $ea_ftable $rm]
                incr ea_removed [llength $rm]
            }
            if {[catch {size_cell $cc $lcname} err]} {   ;# VERIFY size_cell <cells> <lib_cell> (usage text of this release)
                if {[catch {size_cell -lib_cell $lc $cc} err2]} { puts ">>> 079 SIZE change $idx FAILED: $err / $err2"; lappend ea_failed "change $idx: size_cell $inst $ref failed: $err / $err2"; continue }
            }
            legalize_placement -cells [get_cells -exact $inst]
            lassign [ant068_bbox_of [get_cells -exact $inst]] nx0 ny0 nx1 ny1
            set newref [get_attribute -quiet [get_cells -exact $inst] ref_name]
            set mv [ant_manhattan $nx0 $ny0 $cx0 $cy0]
            set okc [expr {$newref eq $ref && $mv <= $POS_TOL}]
            puts [format ">>> 079 SIZE change %d: %s %s -> %s, fillers removed %d, origin (%.3f, %.3f) -> (%.3f, %.3f) %s" $idx $inst $oldref $newref [llength $rm] $cx0 $cy0 $nx0 $ny0 [expr {$okc ? "OK" : "FAILED"}]]
            if {!$okc} { lappend ea_failed "change $idx: $inst now $newref, moved by [format %.3f $mv] um" } else { lappend ea_done [dict create idx $idx type size_cell cell $inst ref $ref] ; lappend ea_touched {*}[lmap e [ant072_pin_nets $inst] {lindex $e 1}] }
            continue
        }
        # ---- insert_buffer ----
        set isport [expr {[dict get $c objkind] eq "port"}]
        set abpins {}
        set gate 0.0
        set portlim 0.0
        if {$isport} {
            # 079 fix: an input PORT: the loads move behind the new cell; the pin location is the port terminal (as antenna_port_buffers.tcl)
            set pinname [eco079_lookup_port [dict get $c full_pin]]
            if {$pinname eq ""} { lappend ea_failed "change $idx: port [dict get $c full_pin] not found"; continue }
            set pobj [get_ports -exact $pinname]
            set dir port
            set netb [eco079_net_of_port $pinname]
            if {$netb eq ""} { lappend ea_failed "change $idx: port $pinname has no net"; continue }
            set before [eco079_net_leaf_pins $netb]
            lassign [eco079_port_xy $pinname] px py
            set drv_cells {}; set has_port 1; set drv_xy [list $px $py]
            set dkind port
            set gate [dict get $ea_gate $ref]
            lassign [eco079_port_limit $gate $PORT_MAX_PIN_BUF_DIST $PORT_ANT_RATIO_LIMIT $PORT_ANT_WEIGHT_PINWIRE $PORT_WIRE_WIDTH_UM] portlim portwhy
            set abpins [eco079_antbuf_pins $before $BUF_PREFIX]
            if {[llength $abpins] > 0} {
                set abinfo {}
                foreach ap $abpins { lassign [ant068_centre [get_pins -exact $ap]] ax ay; lappend abinfo [format "%s (input pin %.1f um from the port pin)" $ap [ant_manhattan $px $py $ax $ay]] }
                puts ">>> 079 CASE change $idx: port $pinname already has an antenna buffer: [join $abinfo {, }]. The new cell goes BETWEEN the port and the antenna buffer (which is not touched); it must be within [format %.1f $portlim] um of the port pin ($portwhy)"
            }
        } else {
            set pinname [eco079_lookup_pin [dict get $c full_pin]]
            if {$pinname eq ""} { lappend ea_failed "change $idx: pin [dict get $c full_pin] not found (it should exist now)"; continue }
            set pobj [get_pins -exact $pinname]
            set dir [get_attribute -quiet $pobj direction]   ;# VERIFY pin attribute direction
            set netb [eco079_net_of_pin $pinname]
            if {$netb eq ""} { lappend ea_failed "change $idx: pin $pinname has no net"; continue }
            set before [eco079_net_leaf_pins $netb]
            lassign [eco079_driver_info $netb] drv_cells has_port drv_xy
            set dkind [eco079_driver_kind $drv_cells $has_port $BUF_PREFIX]
            lassign [ant068_centre $pobj] px py
        }
        set placed 0
        set tried {}
        set last_why "no usable filler run"
        set tiers {1 2}
        set tier_notes {}
        set tier_lims {}
        set portlim2 0.0
        if {$isport} {
            lassign [eco079_port_tier2 $gate $PORT_ANT_WEIGHT_TOPM $PORT_TIER2_RATIO $PORT_WIRE_WIDTH_UM $portlim] portlim2 portwhy2
            if {$portlim2 <= 0} { set tiers {1} }
        }
        foreach tier $tiers {
            if {$placed} break
            if {$isport} { set lim [expr {$tier == 1 ? $portlim : $portlim2}] } else { set lim [expr {$tier == 1 ? $DIST_TIER1 : $DIST_TIER2}] }
            lappend tier_lims [list $tier $lim]
            set rw $PORT_ANT_WEIGHT_PINWIRE; set rl $PORT_ANT_RATIO_LIMIT   ;# the predicted ratio of a port wire: tier 1 with the M2/M3 weight against the limit, tier 2 with the TOP_M weight against TIER2_RATIO
            if {$tier == 2} { set rw $PORT_ANT_WEIGHT_TOPM; set rl $PORT_TIER2_RATIO }
            set L [expr {$lim + $bw + $bh}]
            set frows [ant_rows_in_window $ea_ftable [expr {$px - $L}] [expr {$py - $L}] [expr {$px + $L}] [expr {$py + $L}]]
            set cands {}
            foreach cd [ant_site_candidates [ant_filler_runs $frows] $bw $ea_site_w $px $py $lim] {
                if {[lsearch -exact $tried [list [dict get $cd x] [dict get $cd y]]] < 0} { lappend cands $cd }
            }
            if {[llength $cands] == 0} { lappend tier_notes [format "tier %d (limit %.1f um): no usable filler run within the limit" $tier $lim] }
            set tier_rej {}
            set ntry 0
            foreach cd $cands {
                if {$ntry >= $MAX_SITE_TRIES} break
                incr ntry
                set cx [dict get $cd x]; set cy [dict get $cd y]
                lappend tried [list $cx $cy]
                set rmn [dict get $cd names]
                set flc [get_cells -quiet -exact $rmn]
                if {[sizeof_collection $flc] != [llength $rmn]} { set last_why "only [sizeof_collection $flc] of [llength $rmn] filler names found"; continue }
                set ori0 [get_attribute -quiet [index_collection $flc 0] orientation]
                remove_cells $flc
                set ea_ftable [ant_rows_remove $ea_ftable $rmn]
                incr ea_removed [llength $rmn]
                # PrimeTime's new names are kept; the full hierarchical name is tried first, then the leaf name
                set cell_full [dict get $c cell]; set net_full [dict get $c net]
                if {[catch {insert_buffer -lib_cell $lc -new_cell_names $cell_full -new_net_names $net_full $pobj} err ierr]} {   ;# VERIFY insert_buffer on a pin (driver or load) with hierarchical new names
                    if {!$ea_ins_err_shown} {
                        set ea_ins_err_shown 1
                        puts ">>> 079 insert_buffer with the full hierarchical names returned an error (shown once; every later change uses the same fallback silently if it recurs): message '$err', code [dict get $ierr -code]; the leaf names are tried. First lines of the error info: [join [lrange [split [dict get $ierr -errorinfo] "\n"] 0 4] { | }]"
                    }
                    if {[catch {insert_buffer -lib_cell $lc -new_cell_names [lindex [split $cell_full /] end] -new_net_names [lindex [split $net_full /] end] $pobj} err2]} { set last_why "insert_buffer failed: $err / $err2"; continue }
                }
                set bname [eco079_lookup_cell $cell_full]
                if {$bname eq ""} { set last_why "the new cell $cell_full was not found after insert_buffer"; continue }
                set bc [get_cells -exact $bname]
                set sargs [list -coordinates [list $cx $cy]]
                if {$ori0 ne ""} { lappend sargs -orientation $ori0 }
                if {[catch {set_cell_location {*}$sargs $bc} err]} {
                    if {[catch {set_attribute -objects $bc -name origin -value [list $cx $cy]} err2]} { set last_why "cannot move $bname: $err / $err2"; continue }
                }
                legalize_placement -cells $bc
                lassign [ant068_bbox_of $bc] bx0 by0 bx1 by1
                set dpos [ant_manhattan $bx0 $by0 $cx $cy]
                lassign [dict get $ea_sig $ref] sigin sigout   ;# 079 fix 2: the SIGNAL pins from the LEF (a direction filter also returned VDD / VSS)
                set inp [get_pins -quiet -exact "$bname/$sigin"]
                set outp [get_pins -quiet -exact "$bname/$sigout"]
                if {[sizeof_collection $inp] != 1 || [sizeof_collection $outp] != 1} { error "ERROR 079: change $idx: the new cell $bname has no pins $sigin / $sigout (found [sizeof_collection $inp] / [sizeof_collection $outp]) (nothing saved)" }
                lassign [ant068_centre $inp] ix iy
                set dist [ant_manhattan $px $py $ix $iy]
                set why {}
                if {$dpos > $POS_TOL} { lappend why "cell at ([format %.3f $bx0], [format %.3f $by0]) instead of the site ([format %.3f $cx], [format %.3f $cy])" }
                if {$dist > $lim} { lappend why "distance [format %.1f $dist] > [format %.1f $lim]" }
                set ratio 0.0
                set rtxt ""
                if {$isport} {
                    set ratio [ant_ratio $gate $dist $PORT_WIRE_WIDTH_UM $rw]
                    set rtxt [format " predicted antenna ratio %.0f (weight %s, limit %s)" $ratio $rw $rl]
                    if {$ratio > $rl} { lappend why "predicted antenna ratio [format %.0f $ratio] > $rl (weight $rw)" }
                }
                set bi [get_object_name $inp]; set bz [get_object_name $outp]
                set netin [eco079_net_of_pin $bi]; set netout [eco079_net_of_pin $bz]
                set tprob [eco079_topology_check $dir $pinname $before [eco079_net_leaf_pins $netin] [eco079_net_leaf_pins $netout] $bname $sigin $sigout $ea_pgnames]
                foreach tp $tprob { lappend why "topology: $tp" }
                puts [format ">>> 079 CHANGE %d (%s line %d) %s %s ref %s tier %d%s site (%.3f, %.3f) distance %.1f um%s cell %s %s" $idx [dict get $c file] [dict get $c line] [switch -- $dir { out {string cat {driver pin}} port {string cat {input port}} default {string cat {load pin}} }] $pinname $ref $tier [expr {$isport && $tier == 2 ? { (TIER 2: beyond the tier-1 limit)} : {}}] $cx $cy $dist $rtxt $bname [expr {[llength $why] ? "REJECTED: [join $why {; }]" : "OK"}]]
                if {[llength $why] == 0} {
                    set placed 1
                    lappend ea_done [dict create idx $idx type insert_buffer cell $bname ref $ref pin $pinname dir $dir net_in $netin net_out $netout site [list $cx $cy] dist $dist]
                    lappend ea_touched $netin $netout
                    foreach mv [eco079_protected_moves $before $ea_names $netb] { lappend ea_moves $mv }
                    set wr [eco079_watch_reason $dkind]
                    if {$wr ne ""} {
                        set ddist "n/a"
                        if {$drv_xy ne ""} { set ddist [format %.1f [ant_manhattan [lindex $drv_xy 0] [lindex $drv_xy 1] $ix $iy]] }
                        set extra ""
                        if {$isport} {
                            set extra [format "; %s input gate %.3f um^2, predicted antenna ratio %.0f (TOP_M-weight worst case %.0f; this tier: weight %s, limit %s), tier-%d distance limit %.1f um" [expr {$tier == 2 ? {TIER 2:} : {tier 1:}}] $gate $ratio [ant_ratio $gate $dist $PORT_WIRE_WIDTH_UM $PORT_ANT_WEIGHT_TOPM] $rw $rl $tier $lim]
                            if {[llength $abpins] > 0} {
                                set closer {}
                                foreach ap $abpins { lassign [ant068_centre [get_pins -exact $ap]] ax ay; lappend closer [format "%s is %.1f um from the port pin: the new cell is %s" $ap [ant_manhattan $px $py $ax $ay] [expr {$dist <= [ant_manhattan $px $py $ax $ay] ? {CLOSER} : {not closer, but within the limit}}]] }
                                append extra "; ANTBUF CASE (new cell between the port and the antenna buffer): [join $closer {; }]"
                            }
                        }
                        lappend ea_watch [format "change %d: kind=%s cell %s ref %s on %s, net %s (%s); pin-to-buffer %.1f um, driver-to-buffer %s um%s" $idx [dict get $c objkind] $bname $ref $pinname $netb $wr $dist $ddist $extra]
                    }
                    break
                }
                if {[llength $tprob] > 0} {   ;# 079 fix 2: a topology problem does not depend on the site: no other candidate is tried
                    error "ERROR 079: change $idx ([dict get $c file] line [dict get $c line]): the topology after insert_buffer on $pinname ($dir) differs from what PrimeTime assumed (independent of the site, so no other candidate is tried): [join $tprob {; }]. Nothing saved. Net before (signal pins): {$before}; buffer input net $netin: {[eco079_net_leaf_pins $netin]}; buffer output net $netout: {[eco079_net_leaf_pins $netout]}"
                }
                set last_why [join $why {; }]
                lappend tier_rej "($cx, $cy): $last_why"
                if {[catch {remove_buffers $bc} err]} { error "ERROR 079: change $idx: cannot remove the rejected cell $bname: $err (nothing saved)" }   ;# VERIFY remove_buffers restores the net
                set after_back [eco079_net_leaf_pins [expr {$isport ? [eco079_net_of_port $pinname] : [eco079_net_of_pin $pinname]}]]   ;# 079 fix: a port has no pin object
                if {[lsort $after_back] ne [lsort $before]} { error "ERROR 079: change $idx: after removing the rejected cell the net of $pinname has {[lsort $after_back]}, expected {[lsort $before]} (nothing saved)" }
            }
            if {!$placed && [llength $tier_rej] > 0} { lappend tier_notes [format "tier %d (limit %.1f um): %d candidate(s) rejected: %s" $tier $lim [llength $tier_rej] [join $tier_rej { | }]] }
        }
        if {!$placed} {
            set fwhy "[join $tier_notes {; }]; [eco079_fail_diag [ant_filler_runs $ea_ftable] $bw $ea_site_w $px $py $tier_lims]"
            if {$ALLOW_PARTIAL} {
                puts ">>> 079 CHANGE $idx SKIPPED (ALLOW_PARTIAL 1): pin $pinname ref $ref: $fwhy"
                lappend ea_skipped [dict create idx $idx line [dict get $c line] pin $pinname reason $fwhy on {}]
            } else {
                puts ">>> 079 CHANGE $idx FAILED: pin $pinname ref $ref: $fwhy"
                lappend ea_failed "change $idx: pin $pinname ($ref): $fwhy"
            }
            lappend ea_gone [dict get $c cell]
        }
    }
    puts ">>> 079 fillers removed: $ea_removed; changes applied: [llength $ea_done] of [llength $ea_cmds], skipped: [llength $ea_skipped]"
    set ea_skip_idx [lmap r $ea_skipped {dict get $r idx}]
    set ea_nskip_ins 0
    foreach c $ea_cmds { if {[lsearch -exact $ea_skip_idx [dict get $c idx]] >= 0 && [dict get $c type] eq "insert_buffer"} { incr ea_nskip_ins } }
    if {[llength $ea_skipped] > 0} {
        puts ">>> 079 ===== SKIPPED CHANGES (ALLOW_PARTIAL 1): [llength $ea_skipped] of [llength $ea_cmds]: [join [lsort -integer $ea_skip_idx] {, }] ====="
        foreach ln [eco079_skip_report $ea_skipped $ea_cmds] { puts ">>> 079 SKIPPED $ln" }
        puts ">>> 079 SKIPPED: PrimeTime assumed these changes; its timing (zero violations) is NOT valid for this netlist. PrimeTime MUST be re-run (pt_hold_ff.tcl, pt_setup_ss.tcl) and a second ECO round may be needed."
    }
    if {[llength $ea_failed] > 0} { error "ERROR 079: [llength $ea_failed] change(s) FAILED, nothing saved and nothing routed (the design in memory is not saved):\n    [join $ea_failed "\n    "]" }

    # --------------------------------------------------------------------------
    # 5. Fillers back, power, re-route only the touched nets
    # --------------------------------------------------------------------------
    set fill_cells [get_lib_cells -quiet [lmap f $FILLER_REFS {string cat ${FILLER_LIB}/ $f}]]
    if {[sizeof_collection $fill_cells] == 0} { set fill_cells [get_lib_cells -quiet {*/feedth9 */feedth3 */feedth}] }
    if {[sizeof_collection $fill_cells] > 0} { create_stdcell_fillers -lib_cells $fill_cells } else { lappend ea_failures "filler cells not found, the removed fillers are not restored" }
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]
    set ea_tn [lsort -unique [lsearch -all -inline -not -exact $ea_touched {}]]
    set ea_tcoll [get_nets -quiet -exact $ea_tn]
    puts ">>> 079 nets to re-route: [sizeof_collection $ea_tcoll] of [llength $ea_tn] touched net names"
    remove_routes -nets $ea_tcoll -detail_route
    route_eco -nets $ea_tcoll -reuse_existing_global_route false -reroute modified_nets_first_then_others -max_detail_route_iterations 60
    route_eco -open_net_driven true -reuse_existing_global_route true -reroute modified_nets_first_then_others -max_detail_route_iterations 40
    route_detail -incremental true -max_number_iterations 40
    if {$UNPROTECT_DURING} {
        catch {set_dont_touch $ea_pcells true}
        catch {set_dont_touch [get_nets -quiet -exact $ea_pnets] true}
        puts ">>> 079 dont_touch of the protected cells and nets switched ON again"
    }

    # --------------------------------------------------------------------------
    # 6. ANTENNA WATCH, hard checks, AFTER metrics, save
    # --------------------------------------------------------------------------
    puts ">>> 079 ===== ANTENNA WATCH: [llength $ea_watch] inserted cell(s) on a port net or on the output net of an antenna buffer (Calibre decides afterwards; none is skipped) ====="
    foreach w $ea_watch { puts ">>> 079 ANTENNA WATCH $w" }
    lassign [eco081_cleanup $ea_pnets] ea_drc ea_open ea_ant ea_drc_hist   ;# 081: check_routes plus the DRC clean-up loop (rounds); the counts are those of the last check
    puts ">>> 079 check_routes AFTER: DRCs $ea_drc (before the ECO: $ea_drc0), open nets $ea_open, ICC2 antenna violations $ea_ant; DRC counts per step: [eco081_history_text $ea_drc_hist]"
    if {$ea_drc eq "" || $ea_drc != 0} { lappend ea_failures "check_routes DRCs '$ea_drc' (0 required) after $DRC_ROUNDS clean-up round(s) (DRC counts per step: [eco081_history_text $ea_drc_hist]; the remaining errors are listed above as REMAINING DRC)" }
    if {$ea_open eq "" || $ea_open != 0} { lappend ea_failures "check_routes open nets '$ea_open' (0 required)" }
    redirect -variable ea_leg_txt { check_legality -verbose }
    puts $ea_leg_txt
    set ea_leg [ant_parse_legality $ea_leg_txt]
    puts ">>> 079 CHECK legality violations: [expr {$ea_leg eq {} ? {unreadable} : $ea_leg}] (0 required)"
    if {$ea_leg eq "" || $ea_leg != 0} { lappend ea_failures "legality violations '$ea_leg' (0 required)" }
    # counts and references of the new cells
    set ea_n_ins_done 0; set ea_n_size_done 0
    foreach d $ea_done { if {[dict get $d type] eq "insert_buffer"} { incr ea_n_ins_done } else { incr ea_n_size_done } }
    set ea_found [sizeof_collection [get_cells -quiet -hierarchical -filter "name =~ *${NEW_CELL_MARK}*"]]
    set ea_want_ins [expr {$ea_nins - $ea_nskip_ins}]
    puts ">>> 079 CHECK inserted cells: applied $ea_n_ins_done, insertions in the change files $ea_nins, skipped $ea_nskip_ins, expected applied = total - skipped = $ea_want_ins, found in the design by name ($NEW_CELL_MARK): $ea_found"
    if {$ea_n_ins_done != $ea_want_ins} { lappend ea_failures "inserted cells applied $ea_n_ins_done != $ea_want_ins (= $ea_nins insertions in the change files - $ea_nskip_ins skipped)" }
    if {$ea_found != $ea_want_ins} { lappend ea_failures "cells with $NEW_CELL_MARK in the name: $ea_found != $ea_want_ins (= $ea_nins - $ea_nskip_ins skipped)" }
    foreach d $ea_done {
        set cobj [get_cells -quiet -exact [dict get $d cell]]
        if {[sizeof_collection $cobj] != 1} { lappend ea_failures "change [dict get $d idx]: cell [dict get $d cell] vanished"; continue }
        if {[get_attribute -quiet $cobj ref_name] ne [dict get $d ref]} { lappend ea_failures "change [dict get $d idx]: [dict get $d cell] has reference [get_attribute -quiet $cobj ref_name], PrimeTime wrote [dict get $d ref]" }
    }
    # new nets exist
    foreach c $ea_cmds { if {[dict get $c type] eq "insert_buffer" && [lsearch -exact $ea_skip_idx [dict get $c idx]] < 0 && [eco079_lookup_net [dict get $c net]] eq ""} { lappend ea_failures "change [dict get $c idx]: the net name [dict get $c net] does not exist after the insertion (PrimeTime's name is not kept)" } }
    # protected cells
    set ea_snap1 [lmap nm $ea_names {ant072_snapshot $nm}]
    set ea_diff [ant072_snapshot_diff $ea_snap0 $ea_snap1]
    lassign [eco079_diff_split $ea_diff $ea_moves $NEW_CELL_MARK] ea_diff ea_exp
    foreach d $ea_exp { puts ">>> 079 EXPECTED protected pin move (an insertion put a PrimeTime cell in front of the antenna buffer / on its net; the topology was verified): $d" }
    puts ">>> 079 CHECK protected cells ([llength $ea_names]): [expr {[llength $ea_diff] ? $ea_diff : {reference, origin and orientation identical; every pin on the same net except the [llength $ea_exp] expected move(s) listed above}}]"
    foreach d $ea_diff { lappend ea_failures "protected cell: $d" }
    set ea_nant1 [sizeof_collection [get_cells -quiet ${BUF_PREFIX}_*]]
    puts ">>> 079 CHECK ${BUF_PREFIX}_* count: $ea_nant1 (expected $EXPECT_ANTBUF)"
    if {$ea_nant1 != $EXPECT_ANTBUF} { lappend ea_failures "${BUF_PREFIX}_* count $ea_nant1 != $EXPECT_ANTBUF" }
    set ea_m1 [ant072_metrics "079 AFTER"]
    set ea_g1 [eco079_in2out_state "079 AFTER"]
    # 080: the GATE. The in2out group and the whole setup WNS must not be worse than before by more than the tolerance; hold only gives a warning (PrimeTime is the sign-off for hold).
    puts ">>> 079 GATE setup violating endpoints: whole design before [dict get $ea_m0 setup_num], after [dict get $ea_m1 setup_num]; in2out group before [lindex $ea_g0 1], after [lindex $ea_g1 1]; hold before [dict get $ea_m0 hold_num], after [dict get $ea_m1 hold_num]"
    foreach {glabel gb ga gtol} [list "the in2out group" [lindex $ea_g0 0] [lindex $ea_g1 0] $GATE_TOL_SETUP "the whole-design setup WNS" [dict get $ea_m0 setup] [dict get $ea_m1 setup] $GATE_TOL_SETUP] {
        lassign [eco079_gate_check $glabel $gb $ga $gtol] gst gmsg
        puts ">>> 079 GATE $gst: $gmsg"
        if {$gst ne "ok"} {
            puts ">>> 079 ERROR 079: $gmsg: nothing saved"
            lappend ea_failures "$gmsg: nothing saved"
        }
    }
    lassign [eco079_gate_check "the whole-design hold WNS" [dict get $ea_m0 hold] [dict get $ea_m1 hold] $GATE_TOL_HOLD] ghst ghmsg
    puts ">>> 079 GATE hold $ghst: $ghmsg"
    if {$ghst ne "ok"} { puts ">>> 079 WARNING: $ghmsg. ICC2's hold view is not the sign-off: PrimeTime (pt_hold_ff.tcl) decides." }
    puts ">>> 079 NOTE: ICC2's view of the I/O paths is more lenient than PrimeTime's (ICC2 gives the external clock the macro's insertion delay; PrimeTime launches/captures at the clock pin with zero latency). The numbers above are REPORTED, not tuned; PrimeTime (pt_setup_ss.tcl / pt_hold_ff.tcl) is the sign-off."
    if {[llength $ea_failures] > 0} { error "ERROR 079: [llength $ea_failures] check(s) failed, NOTHING SAVED: [join $ea_failures {; }]" }

    save_block
    save_block -force -as ${DESIGN_NAME}_route
    save_lib
    puts ">>> [eco079_final_line [llength $ea_skipped] [llength $ea_cmds] $ea_skip_idx $ea_n_ins_done $ea_n_size_done [llength $ea_watch] ${DESIGN_NAME}_route ${LOG_DIR}/6g_pt_eco_apply.log]"
    if {[llength $ea_skipped] > 0} { puts ">>> 079 PARTIAL RESULT: re-run PrimeTime on the result; the skipped changes are listed above (SKIPPED CHANGES)" }
    puts ">>> 079 NEXT: metal_fill.tcl, pv.tcl, the Calibre DRC / antenna / LVS runs (the ANTENNA WATCH cells first), then PrimeTime pt_setup_ss.tcl and pt_hold_ff.tcl (zero violations expected), then the post-layout simulation."
}
