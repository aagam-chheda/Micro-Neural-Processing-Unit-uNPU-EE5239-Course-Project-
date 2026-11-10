# ==============================================================================
# Script: antenna_port_buffers.tcl
# Path  : <RUN_DIR>/pnr_v2/antenna_port_buffers.tcl   ;# 068: new script (flow step 6c, after fix_antenna.tcl, before metal_fill.tcl)
# Stage : Targeted antenna fix: one buffer next to the pin of each long INPUT PORT net
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 068: THIS SCRIPT CHANGES THE NETLIST (an ECO). Each buffered port net gets one extra buffer cell between the port and its loads. The PM must be told:
# 068: the macro netlist and the gate-level / post-layout simulation views are no longer the synthesis netlist (pv.tcl writes the new netlist).
# 068: why. An input port net has no driver and no diffusion inside the macro, so Calibre counts the whole pin-to-gate wire against a gate area of about
# 068: 0.19 um^2 (AN.MTL.1.*: perimeter x layer weight / gate area > 400; handoff 18.27, task 068). `adiode` is dont_use, layer hopping (fix_antenna.tcl)
# 068: reaches only about 190 um, and moving the pins (task 067, parked) did not shorten the nets. A buffer within a few um of the pin makes the
# 068: pin-to-buffer wire short and gives the rest of the net a driver WITH diffusion (the deck counts diffusion of at least 0.202 um^2 as a diode).
# 068: what it does, in order (all read-only until step 7; every decision is printed with `>>> 068`):
# 068:   1 parse the Calibre antenna database (the same file fix_antenna.tcl reads; format: header `<cell> <dbu>`, rule lines, `p <id> <n>` polygons)
# 068:   2 for every polygon find its net: only nets connected to a port, best geometric match of the net's shapes on that layer; ambiguous or
# 068:     undecided polygons are listed and counted; any unresolved polygon is a hard error BEFORE the design is touched
# 068:   3 print the set of port nets and compare it with EXPECT_PORT_NETS (an expectation to compare, not an input)
# 068:   4 `clk` (clock net) is NOT buffered: its polygons and the distance pin-to-first-loads are printed for a decision by Planning
# 068:   5 choose the buffer cell from DATA: antenna areas in the kit LEF (ANTENNAGATEAREA / ANTENNADIFFAREA) against the Calibre thresholds
# 068:   6 clear the fillers in a small window at each pin, insert one buffer per net, place it next to the pin, legalise, refill
# 068:   7 re-route only the touched nets (route_eco with the nets, as fix_antenna.tcl), clean up with route_detail -incremental
# 068:   8 hard checks (nothing is saved when one fails), timing before/after (reported, not tuned), save over `_route`
# 068: every command or option not shown in a usage text in ~/server_pull/rpt/help (the real help of this tool version) is marked VERIFY.
# 068: no timing option, uncertainty, goal or limit is changed; no diode; no waiver; no change to a Calibre rule or control file.

set DESIGN_NAME "unpu_top"   ;# 068: design name (as the other scripts)
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
source [file join [file dirname [file normalize [info script]]] clock_latency.tcl]   ;# 088: the shared proc that removes the tool-made set_clock_latency (clock_latency.tcl) and checks it
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"   ;# 068: ICC2 work directory (as the other scripts)
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set RPT_DIR     "${PNR_DIR}/reports"
set ANT_DB      "${RUN_ROOT}/pv/drc/unpu_top_antenna_bkp.db"   ;# 068: the same file as fix_antenna.tcl (README step 6c copies the NEW Calibre run there)
set DRC_DB      "${RUN_ROOT}/pv/drc/unpu_top_drc_bkp.db"   ;# 068: OPTIONAL Calibre DRC database (README copies it); only used to locate leftover DRC markers
set STD_LEF     "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"   ;# 068: kit LEF with ANTENNAGATEAREA / ANTENNADIFFAREA (same path as pnr_v2/build_ndm_std.tcl)
set STD_LIB     "scl180_std"   ;# 068: reference library name (as cts.tcl: scl180_std/*)
set FILLER_LIB  "scl180_filler"   ;# 068: as route.tcl
set FILLER_REFS {feedth feedth3 feedth9}   ;# 068: the filler masters route.tcl inserts

# ------------------------------------------------------------------------------
# 068: parameters. Calibre numbers are from handoff 18.27 / task 068 (deck weights, limit); nothing is tuned to close timing.
# ------------------------------------------------------------------------------
set ANT_RATIO_LIMIT   400.0   ;# 068: AN.MTL.1.*: perimeter x weight / gate area must not exceed this
set ANT_WEIGHT_PINWIRE 0.54   ;# 068: M2 / M3 layer weight of the deck (TOP_M is 0.84); the short pin wire is on M2/M3
set ANT_WEIGHT_TOPM    0.84   ;# 068: printed as a second figure for the predicted ratio
set WIRE_WIDTH_UM      0.28   ;# 068: M3 / M2 minimum width: perimeter = 2 x (length + width)
set DIODE_MIN_AREA     0.202  ;# 068: the deck counts only diffusion of at least this area (um^2) as a diode (Calibre log: M3_good_dio)
set PIN_WIRE_UM        30.0   ;# 068: wire length the buffer input must tolerate; the core offset is 20 um so the pin cannot be closer than about 20 um to a row
set GATE_SAFETY        1.0    ;# 068: factor on the needed gate area (LEF area vs layout area may differ); 1.0 = none, the predicted ratio is re-checked after placement
set MAX_PIN_BUF_DIST   40.0   ;# 068: hard limit (um, Manhattan) from the pin to the buffer input pin after legalisation
set MAX_SITE_TRIES     5          ;# 069: candidate filler runs tried per tier and net (closest first)
set TIER2_RATIO        360.0      ;# 069: tier 2 (only for a net with no usable run within MAX_PIN_BUF_DIST): predicted M2/M3 ratio must stay at or below this (10 percent under ANT_RATIO_LIMIT)
set TIER2_MAX_LAYER    "M3"       ;# 069: tier 2 nets: the pin-to-buffer route may not go above this layer (TOP_M has weight 0.84)
set DONT_USE_PATTERNS {slnht* skbrb* slbhb* slnhn* slnln* mx08d* adiode bh01d1 cload1}   ;# 068: handoff 18.15 (15 pattern cells + the library's own three); ICC2 has no don't-use list set in this flow, so the names are checked here
set BUF_PREFIX         "antbuf"   ;# 068: instance name base of the new buffers
set POWER_PORT_NAMES   {VDD VSS}   ;# 068: as pin_replace.tcl
set SETUP_SCEN         "func_ss"  ;# 068: scenario names of cts.tcl / route.tcl
set HOLD_SCEN          "func_ff"
set EXPECT_POLYGONS    46         ;# 068: expectation from task 068 (printed as a difference, not an input)
set EXPECT_PORT_NETS {pwdata[0] pwdata[2] pwdata[6] pwdata[7] pwdata[8] pwdata[10] pwdata[12] pwdata[14] pwdata[16] pwdata[20] pwdata[22] pwdata[26] pwdata[28] pwdata[30] clk dma_rdata[9]}   ;# 068: the 16 nets of task 068; compared with the result, never used as input
set TOL_UM             0.006      ;# 068: shape bbox equal to polygon bbox (database unit is 1 nm; ICC2 prints 2 to 3 decimals)
set MARGIN_SCORE       0.05       ;# 068: two nets of the same tier closer than this in score are ambiguous
set MIN_COVER          0.5        ;# 068: a polygon covered less than this by the best net is undecided

# ---- BEGIN PURE TCL 068 ----
# 068: everything between BEGIN and END is plain Tcl (no ICC2 command); pnr_v2/test_antenna_port_buffers.tcl extracts and tests exactly this text.

# 068: parse a Calibre ASCII results database (antenna or DRC). Returns a dict: top, dbu, polys.
# 068: each poly is a dict: rule id nv xs ys bbox {x0 y0 x1 y1} (micrometres). Lines such as `CN unpu_top c 1 0 0 1 0 0 0` between the `p` line and
# 068: the vertices are skipped (fix_antenna.tcl reads them as one of the vertices, which loses the last vertex of the first polygon of each rule).
proc ant_parse_db {text} {
    set lines [split $text "\n"]
    set n [llength $lines]
    set i 0
    set dbu ""
    set top ""
    while {$i < $n} {
        set l [string trim [lindex $lines $i]]
        incr i
        if {$l eq ""} continue
        if {![regexp {^(\S+)\s+([0-9]+)$} $l -> top dbu]} {
            error "ant_parse_db: the first line is not '<cell> <database units per um>': '$l'"
        }
        break
    }
    if {$dbu eq "" || $dbu == 0} { error "ant_parse_db: no header line (cell and database unit)" }
    set rule ""
    set polys {}
    while {$i < $n} {
        set l [string trim [lindex $lines $i]]
        if {[regexp {^[A-Za-z][A-Za-z0-9_.]*$} $l] && ($i + 1) < $n && [regexp {^[0-9]+\s+[0-9]+\s+[0-9]+\s+[A-Z][a-z][a-z]\s} [string trim [lindex $lines [expr {$i + 1}]]]]} {
            set rule $l
            incr i
            continue
        }
        if {[regexp {^p\s+([0-9]+)\s+([0-9]+)$} $l -> pid nv]} {
            if {$rule eq ""} { error "ant_parse_db: polygon $pid before any rule line" }
            set xs {}
            set ys {}
            set j [expr {$i + 1}]
            while {[llength $xs] < $nv} {
                if {$j >= $n} { error "ant_parse_db: polygon $pid of rule $rule is cut off by the end of the file" }
                set vl [string trim [lindex $lines $j]]
                if {[regexp {^(-?[0-9]+)\s+(-?[0-9]+)$} $vl -> vx vy]} {
                    lappend xs [expr {$vx / double($dbu)}]
                    lappend ys [expr {$vy / double($dbu)}]
                } elseif {[regexp {^p\s+[0-9]+\s+[0-9]+$} $vl]} {
                    error "ant_parse_db: polygon $pid of rule $rule has fewer than $nv vertices"
                }
                incr j
            }
            set xmin [lindex [lsort -real $xs] 0]
            set xmax [lindex [lsort -real $xs] end]
            set ymin [lindex [lsort -real $ys] 0]
            set ymax [lindex [lsort -real $ys] end]
            lappend polys [dict create rule $rule id $pid nv $nv xs $xs ys $ys bbox [list $xmin $ymin $xmax $ymax]]
            set i $j
            continue
        }
        incr i
    }
    return [dict create top $top dbu $dbu polys $polys]
}

# 068: Calibre antenna rule name -> ICC2 layer name, "" when the rule is not a metal-area rule (AN.VIA.*, AN.GC.1, ...)
proc ant_rule_layer {rule} {
    if {[regexp {^AN\.MTL\.[12]\.(M[1-3]|MT)$} $rule -> l]} {
        if {$l eq "MT"} { return "TOP_M" }
        return $l
    }
    return ""
}

# 068: four numbers out of an ICC2 bbox string such as "{837.46 408.465} {837.74 409.365}"
proc ant_bbox_nums {s} {
    set nums [regexp -all -inline -- {-?[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?} $s]
    if {[llength $nums] != 4} { error "ant_bbox_nums: expected 4 numbers in '$s'" }
    return $nums
}

proc ant_poly_area {xs ys} {
    set n [llength $xs]
    set a 0.0
    for {set i 0} {$i < $n} {incr i} {
        set j [expr {($i + 1) % $n}]
        set a [expr {$a + [lindex $xs $i] * [lindex $ys $j] - [lindex $xs $j] * [lindex $ys $i]}]
    }
    return [expr {abs($a) / 2.0}]
}

# 068: point in polygon, boundary counts as inside (eps in um)
proc ant_pt_in_poly {x y xs ys {eps 1e-4}} {
    set n [llength $xs]
    for {set i 0} {$i < $n} {incr i} {
        set j [expr {($i + 1) % $n}]
        set x1 [lindex $xs $i]; set y1 [lindex $ys $i]
        set x2 [lindex $xs $j]; set y2 [lindex $ys $j]
        set dx [expr {$x2 - $x1}]; set dy [expr {$y2 - $y1}]
        set len2 [expr {$dx * $dx + $dy * $dy}]
        if {$len2 == 0.0} continue
        set t [expr {(($x - $x1) * $dx + ($y - $y1) * $dy) / $len2}]
        if {$t < 0.0} { set t 0.0 }
        if {$t > 1.0} { set t 1.0 }
        set cx [expr {$x1 + $t * $dx}]; set cy [expr {$y1 + $t * $dy}]
        if {hypot($x - $cx, $y - $cy) <= $eps} { return 1 }
    }
    set inside 0
    for {set i 0} {$i < $n} {incr i} {
        set j [expr {($i + $n - 1) % $n}]
        set xi [lindex $xs $i]; set yi [lindex $ys $i]
        set xj [lindex $xs $j]; set yj [lindex $ys $j]
        if {(($yi > $y) != ($yj > $y)) && ($x < ($xj - $xi) * ($y - $yi) / ($yj - $yi) + $xi)} {
            set inside [expr {!$inside}]
        }
    }
    return $inside
}

# 068: rank the nets of a list of shapes {net x0 y0 x1 y1} against one polygon (dict from ant_parse_db).
# 068: tier 3 = a shape of the net has the polygon's bbox (within tol); tier 2 = a shape contains the polygon's bbox; tier 1 = shapes overlap the polygon
# 068: (overlap area whose centre lies inside the polygon, divided by the polygon area = score). Result: list of {net tier score}, best first.
proc ant_rank {poly shapes {tol 0.006}} {
    lassign [dict get $poly bbox] px0 py0 px1 py1
    set xs [dict get $poly xs]
    set ys [dict get $poly ys]
    set parea [ant_poly_area $xs $ys]
    array set tier {}
    array set num {}
    foreach s $shapes {
        lassign $s net sx0 sy0 sx1 sy1
        set ix0 [expr {max($sx0, $px0)}]
        set iy0 [expr {max($sy0, $py0)}]
        set ix1 [expr {min($sx1, $px1)}]
        set iy1 [expr {min($sy1, $py1)}]
        if {$ix1 - $ix0 <= 1e-6 || $iy1 - $iy0 <= 1e-6} continue
        if {![info exists tier($net)]} { set tier($net) 0; set num($net) 0.0 }
        set t 0
        if {abs($sx0 - $px0) <= $tol && abs($sy0 - $py0) <= $tol && abs($sx1 - $px1) <= $tol && abs($sy1 - $py1) <= $tol} {
            set t 3
        } elseif {$sx0 <= $px0 + $tol && $sy0 <= $py0 + $tol && $sx1 >= $px1 - $tol && $sy1 >= $py1 - $tol} {
            set t 2
        }
        if {[ant_pt_in_poly [expr {($ix0 + $ix1) / 2.0}] [expr {($iy0 + $iy1) / 2.0}] $xs $ys]} {
            set num($net) [expr {$num($net) + ($ix1 - $ix0) * ($iy1 - $iy0)}]
            if {$t == 0} { set t 1 }
        } elseif {$t < 2} {
            set t 0
        }
        if {$t > $tier($net)} { set tier($net) $t }
    }
    set out {}
    foreach net [array names tier] {
        if {$tier($net) == 0} continue
        set sc [expr {$parea > 0 ? min(1.0, $num($net) / $parea) : 0.0}]
        lappend out [list $net $tier($net) $sc]
    }
    return [lsort -decreasing -integer -index 1 [lsort -decreasing -real -index 2 $out]]   ;# sort by score, then (stable) by tier: tier first, score second
}

# 068: decision on a ranked list: {status chosen note}. status: OK | NONE | AMBIGUOUS | LOWCOVER. Nothing is guessed: only OK has a net.
proc ant_decide {ranks {margin 0.05} {mincover 0.5}} {
    if {[llength $ranks] == 0} { return [list NONE "" "no shape overlaps the polygon"] }
    set top [lindex $ranks 0]
    lassign $top n1 t1 s1
    if {[llength $ranks] > 1} {
        lassign [lindex $ranks 1] n2 t2 s2
        if {$t2 == $t1 && ($t1 >= 2 || abs($s1 - $s2) < $margin)} {
            return [list AMBIGUOUS "" "$n1 and $n2 both at tier $t1 (scores [format %.2f $s1] / [format %.2f $s2])"]
        }
    }
    if {$t1 == 1 && $s1 < $mincover} {
        return [list LOWCOVER "" "best net $n1 covers only [format %.2f $s1] of the polygon"]
    }
    return [list OK $n1 "tier $t1 score [format %.2f $s1]"]
}

# 068: gate area (um^2) a pin wire of wire_um on a layer of the given weight needs: 2 x (L + W) x weight / limit x safety
proc ant_need_gate {wire_um width_um weight limit safety} {
    return [expr {2.0 * ($wire_um + $width_um) * $weight / $limit * $safety}]
}
proc ant_ratio {gate_area wire_um width_um weight} {
    return [expr {2.0 * ($wire_um + $width_um) * $weight / $gate_area}]
}

# 068: kit LEF -> dict cell -> {w h pins}, pins: dict pin -> {dir use gate {list} diff {list}}
proc ant_parse_lef {text} {
    set cells [dict create]
    set macro ""
    set pin ""
    foreach raw [split $text "\n"] {
        set l [string trim $raw]
        if {$l eq ""} continue
        if {[regexp {^MACRO\s+(\S+)} $l -> m]} {
            set macro $m
            set pin ""
            dict set cells $macro [dict create w "" h "" pins [dict create]]
            continue
        }
        if {$macro eq ""} continue
        if {[regexp {^SIZE\s+([0-9.eE+-]+)\s+BY\s+([0-9.eE+-]+)} $l -> w h]} {
            dict set cells $macro w $w
            dict set cells $macro h $h
            continue
        }
        if {[regexp {^PIN\s+(\S+)} $l -> p]} {
            set pin $p
            dict set cells $macro pins $pin [dict create dir "" use "" gate {} diff {}]
            continue
        }
        if {[regexp {^END\s+(\S+)} $l -> e]} {
            if {$e eq $macro} { set macro ""; set pin "" } elseif {$e eq $pin} { set pin "" }
            continue
        }
        if {$pin eq ""} continue
        set pd [dict get $cells $macro pins $pin]
        if {[regexp {^DIRECTION\s+(\S+)} $l -> d]} {
            dict set pd dir $d
        } elseif {[regexp {^USE\s+(\S+)} $l -> u]} {
            dict set pd use $u
        } elseif {[regexp {^ANTENNAGATEAREA\s+([0-9.eE+-]+)} $l -> v]} {
            dict lappend pd gate $v
        } elseif {[regexp {^ANTENNADIFFAREA\s+([0-9.eE+-]+)} $l -> v]} {
            dict lappend pd diff $v
        } else {
            continue
        }
        dict set cells $macro pins $pin $pd
    }
    return $cells
}

proc ant_dont_use {name patterns} {
    foreach p $patterns { if {[string match -nocase $p $name]} { return $p } }
    return ""
}

proc ant_min_or_zero {l} {
    if {[llength $l] == 0} { return 0.0 }
    return [lindex [lsort -real $l] 0]
}

# 068: evaluate the candidate buffers `names` (already known to be non-inverting buffers of the library) against the LEF data.
# 068: criteria: (a) output diffusion >= diode_min; (b) input gate area >= need_gate; (c) not on the don't-use list; (d) exactly one signal input and one signal output.
# 068: rows: dict name area w h gate diff verdict(PASS|FAIL) why. The smallest gate and diffusion value listed in the LEF is used (conservative).
proc ant_eval_buffers {lef names dont_patterns need_gate diode_min} {
    set rows {}
    foreach name [lsort $names] {
        if {![dict exists $lef $name]} {
            lappend rows [dict create name $name area 0 w 0 h 0 gate 0 diff 0 verdict FAIL why "no MACRO in the LEF"]
            continue
        }
        set c [dict get $lef $name]
        set w [dict get $c w]
        set h [dict get $c h]
        set area [expr {($w eq "" || $h eq "") ? 0.0 : $w * $h}]
        set ins {}
        set outs {}
        dict for {pn pd} [dict get $c pins] {
            set use [dict get $pd use]
            set dir [dict get $pd dir]
            if {$use eq "POWER" || $use eq "GROUND" || $dir eq "INOUT"} continue
            if {$dir eq "INPUT"} { lappend ins $pn }
            if {$dir eq "OUTPUT"} { lappend outs $pn }
        }
        set gate 0.0
        set diff 0.0
        set why {}
        if {[llength $ins] != 1 || [llength $outs] != 1} {
            lappend why "(d) [llength $ins] signal inputs and [llength $outs] outputs"
        } else {
            set gate [ant_min_or_zero [dict get $c pins [lindex $ins 0] gate]]
            set diff [ant_min_or_zero [dict get $c pins [lindex $outs 0] diff]]
            if {$diff < $diode_min} { lappend why "(a) output diffusion [format %.3f $diff] < [format %.3f $diode_min]" }
            if {$gate < $need_gate} { lappend why "(b) input gate [format %.3f $gate] < [format %.3f $need_gate]" }
        }
        set du [ant_dont_use $name $dont_patterns]
        if {$du ne ""} { lappend why "(c) on the don't-use list ($du)" }
        lappend rows [dict create name $name area $area w $w h $h gate $gate diff $diff verdict [expr {[llength $why] ? "FAIL" : "PASS"}] why [join $why "; "]]
    }
    return $rows
}

# 068: the passing cell with the smallest footprint (ties: name); "" when none passes
proc ant_pick_buffer {rows} {
    set best ""
    set barea 0
    foreach r $rows {
        if {[dict get $r verdict] ne "PASS"} continue
        set a [dict get $r area]
        if {$best eq "" || $a < $barea} { set best [dict get $r name]; set barea $a }
    }
    return $best
}

# 068: where to put a buffer of size bw x bh for a pin at (px,py): the pin position clamped into the core box {x0 y0 x1 y1} and snapped to a row
# 068: (rows start at y0 with height bh). Returns {x y}.
proc ant_target_xy {px py bw bh core} {
    lassign $core cx0 cy0 cx1 cy1
    set tx [expr {$px - $bw / 2.0}]
    set ty [expr {$py - $bh / 2.0}]
    set tx [expr {min(max($tx, $cx0), $cx1 - $bw)}]
    set ty [expr {min(max($ty, $cy0), $cy1 - $bh)}]
    set ty [expr {$cy0 + floor(($ty - $cy0) / $bh + 0.5) * $bh}]
    if {$ty > $cy1 - $bh} { set ty [expr {$ty - $bh}] }
    return [list $tx $ty]
}

proc ant_manhattan {x1 y1 x2 y2} {
    return [expr {abs($x1 - $x2) + abs($y1 - $y2)}]
}

# 068: "Total number of DRCs = 1" style lines of check_routes -> number, or "" when the line is missing
proc ant_parse_count {text label} {
    set pat "(?i)total number of ${label}\\s*=\\s*(\[0-9\]+)"
    if {[regexp -- $pat $text -> n]} { return $n }
    return ""
}

# 068: check_legality text -> number of violations or "" (accepts "TOTAL 0 Violations", "Total N violations", and "N violation(s)"; "succeeded" alone is NOT a number)
proc ant_parse_legality {text} {
    foreach l [split $text "\n"] {
        if {[regexp -nocase -- {total\s+([0-9][0-9,]*)\s+violations?} $l -> n]} { return [string map {, {}} $n] }
    }
    foreach l [split $text "\n"] {
        if {[regexp -nocase -- {([0-9][0-9,]*)\s+(legality\s+)?violations?} $l -> n]} { return [string map {, {}} $n] }
    }
    return ""
}
# 069: group filler instances into contiguous runs per row. fillers: list of {name x0 y0 x1 y1 orient}. Returns a list of dicts:
# 069: y0 y1 x0 x1 orient fillers {{name x0 x1} ...} (fillers sorted by x). Two fillers are in one run when they touch (gap <= tol) in the same row.
proc ant_filler_runs {fillers {tol 0.001}} {
    set rows [dict create]
    foreach f $fillers { dict lappend rows [format %.3f [lindex $f 2]] $f }
    set runs {}
    foreach key [lsort -real [dict keys $rows]] {
        set cur {}
        foreach f [lsort -real -index 1 [dict get $rows $key]] {
            lassign $f name x0 y0 x1 y1 ori
            if {[llength $cur] > 0 && $x0 <= [dict get $cur x1] + $tol && abs($y1 - [dict get $cur y1]) <= $tol} {
                dict set cur x1 [expr {max([dict get $cur x1], $x1)}]
                dict lappend cur fillers [list $name $x0 $x1]
            } else {
                if {[llength $cur] > 0} { lappend runs $cur }
                set cur [dict create y0 $y0 y1 $y1 x0 $x0 x1 $x1 orient $ori fillers [list [list $name $x0 $x1]]]
            }
        }
        if {[llength $cur] > 0} { lappend runs $cur }
    }
    return $runs
}

# 070: evaluate ONE run for a buffer of width bw: returns a dict ok (0/1), reason ("" when ok), x (start site on the run's site grid, nearest to the pin),
# 070: dist (Manhattan from the pin to the buffer box centre), need (width needed in whole sites), width (of the run), near (Manhattan from the pin to the run's nearest point)
proc ant_run_eval {r bw site_w px py limit {tol 0.001}} {
    set span [expr {ceil($bw / $site_w - 1e-6) * $site_w}]
    set x0 [dict get $r x0]; set x1 [dict get $r x1]
    set y0 [dict get $r y0]; set y1 [dict get $r y1]
    set dx [expr {max($x0 - $px, 0.0, $px - $x1)}]
    set dy [expr {max($y0 - $py, 0.0, $py - $y1)}]
    set res [dict create ok 0 reason "" x $x0 dist 0.0 need $span width [expr {$x1 - $x0}] near [expr {$dx + $dy}]]
    if {$x1 - $x0 < $span - $tol} {
        dict set res reason "too narrow: width [format %.2f [expr {$x1 - $x0}]] < needed [format %.2f $span]"
        return $res
    }
    set nsteps [expr {int(floor(($x1 - $x0 - $span) / $site_w + 1e-6))}]
    set k [expr {int(floor(($px - $span / 2.0 - $x0) / $site_w + 0.5))}]
    if {$k < 0} { set k 0 }
    if {$k > $nsteps} { set k $nsteps }
    set xs [expr {$x0 + $k * $site_w}]
    set dist [ant_manhattan $px $py [expr {$xs + $bw / 2.0}] [expr {($y0 + $y1) / 2.0}]]
    dict set res x $xs
    dict set res dist $dist
    if {$dist > $limit} {
        dict set res reason "too far: dist [format %.2f $dist] > limit [format %.2f $limit]"
        return $res
    }
    dict set res ok 1
    return $res
}

# 069: candidate sites for a buffer of width bw: in every run at least as wide as the buffer (rounded up to whole sites) take the start site
# 069: nearest to the pin (px,py), on the site grid of the run. Keep the candidates whose box centre is within `limit` (Manhattan) of the pin, closest first
# 069: (ties: lower y, lower x). A candidate is a dict: x y w h dist orient names (the fillers to remove: those overlapping the buffer box) run_x0 run_x1.
proc ant_site_candidates {runs bw site_w px py limit {tol 0.001}} {
    set span [expr {ceil($bw / $site_w - 1e-6) * $site_w}]
    set list_ {}
    foreach r $runs {
        set ev [ant_run_eval $r $bw $site_w $px $py $limit $tol]
        if {![dict get $ev ok]} continue
        set xs [dict get $ev x]
        set x0 [dict get $r x0]; set x1 [dict get $r x1]
        set y0 [dict get $r y0]; set y1 [dict get $r y1]
        set names {}
        foreach f [dict get $r fillers] {
            lassign $f fname fx0 fx1
            if {min($fx1, $xs + $span) - max($fx0, $xs) > $tol} { lappend names $fname }
        }
        lappend list_ [list [dict get $ev dist] $y0 $xs [dict create x $xs y $y0 w $span h [expr {$y1 - $y0}] dist [dict get $ev dist] orient [dict get $r orient] names $names run_x0 $x0 run_x1 $x1]]
    }
    set list_ [lsort -real -index 2 $list_]
    set list_ [lsort -real -index 1 $list_]
    set list_ [lsort -real -index 0 $list_]
    return [lmap e $list_ {lindex $e 3}]
}

# 070: the nearest `n` runs (by Manhattan distance from the pin to the run's nearest point) with the reason each one is rejected ("" = usable). Lines of text.
proc ant_run_report {runs bw site_w px py limit {n 3} {tol 0.001}} {
    set evs {}
    foreach r $runs {
        set ev [ant_run_eval $r $bw $site_w $px $py $limit $tol]
        lappend evs [list [dict get $ev near] $r $ev]
    }
    set out {}
    foreach e [lrange [lsort -real -index 0 $evs] 0 [expr {$n - 1}]] {
        lassign $e near r ev
        lappend out [format "row y=%.2f x=%.2f..%.2f width=%.2f needed=%.2f nearest-point distance=%.1f: %s" [dict get $r y0] [dict get $r x0] [dict get $r x1] [dict get $ev width] [dict get $ev need] $near [expr {[dict get $ev ok] ? "usable (site x=[format %.2f [dict get $ev x]], centre distance [format %.1f [dict get $ev dist]])" : [dict get $ev reason]}]]
    }
    return $out
}

# 070: rows {name x0 y0 x1 y1 orient} that overlap the window (positive overlap in x and y); the window is given as four numbers
proc ant_rows_in_window {rows wx0 wy0 wx1 wy1} {
    set out {}
    foreach r $rows {
        lassign $r name x0 y0 x1 y1
        if {$x1 > $wx0 && $x0 < $wx1 && $y1 > $wy0 && $y0 < $wy1} { lappend out $r }
    }
    return $out
}

# 070: the table without the rows whose name is in `names`
proc ant_rows_remove {rows names} {
    array set gone {}
    foreach nm $names { set gone($nm) 1 }
    set out {}
    foreach r $rows { if {![info exists gone([lindex $r 0])]} { lappend out $r } }
    return $out
}

# 070: {xmin ymin xmax ymax} over the rows, "" for no row
proc ant_rows_extent {rows} {
    if {[llength $rows] == 0} { return "" }
    set xa 1e18; set ya 1e18; set xb -1e18; set yb -1e18
    foreach r $rows {
        lassign $r name x0 y0 x1 y1
        set xa [expr {min($xa, $x0)}]; set ya [expr {min($ya, $y0)}]
        set xb [expr {max($xb, $x1)}]; set yb [expr {max($yb, $y1)}]
    }
    return [list $xa $ya $xb $yb]
}

# 069: longest pin-to-buffer Manhattan distance (um) whose predicted antenna ratio stays at or below `ratio` for this gate area
proc ant_max_dist_for_ratio {gate_area width_um weight ratio} {
    return [expr {$ratio * $gate_area / (2.0 * $weight) - $width_um}]
}
# ---- END PURE TCL 068 ----

# 068: ICC2 side helpers (use ICC2 commands, not tested locally)
proc ant068_bbox_of {obj} {   ;# 068: VERIFY: the `bbox` attribute of shapes, terminals, pins and cells is a plain string with 4 numbers (it was in task 067)
    return [ant_bbox_nums [get_attribute -quiet $obj bbox]]
}
proc ant068_centre {obj} {
    lassign [ant068_bbox_of $obj] x0 y0 x1 y1
    return [list [expr {($x0 + $x1) / 2.0}] [expr {($y0 + $y1) / 2.0}]]
}
proc ant068_net_shapes {netname layer} {   ;# 068: shapes of one net on one layer: {net x0 y0 x1 y1}; the filter text is the one fix_antenna.tcl uses
    set out {}
    set sc [get_shapes -quiet -of_objects [get_nets -quiet -exact $netname] -filter "layer.name == $layer"]
    foreach_in_collection s $sc { lappend out [concat [list $netname] [ant068_bbox_of $s]] }
    return $out
}
proc ant068_slack {port scen type} {   ;# 068: worst slack of the paths starting at a port; VERIFY get_timing_paths ... and the `slack` attribute
    # 069: get_timing_paths rejects -quiet in this ICC2 (CMD-010); the real option list is in ~/server_pull/rpt/help/get_timing_paths.txt. A failure is printed ONCE, not per net.
    global ab_timing_err
    if {[catch {
        set p [get_timing_paths -scenarios $scen -from [get_ports -quiet -exact $port] -delay_type $type -max_paths 1]
        if {[sizeof_collection $p] == 0} { set r "n/a" } else { set r [get_attribute $p slack] }
    } err]} {
        if {![info exists ab_timing_err]} {
            set ab_timing_err $err
            puts ">>> 069 per-net timing unavailable: $err"
        }
        return "unavailable"
    }
    return $r
}
proc ant069_filler_rows {win filter} {   ;# 069: fillers intersecting a window -> list of {name x0 y0 x1 y1 orientation}; VERIFY get_cells -intersect finds fillers, and the `orientation` attribute
    # 070: NOT used by the ECO any more (see ant070_all_fillers); kept for pnr_v2/diag_filler_runs.tcl, which compares it with the table
    set rows {}
    foreach_in_collection f [get_cells -quiet -intersect $win -filter $filter] {
        lappend rows [concat [list [get_object_name $f]] [ant068_bbox_of $f] [list [get_attribute -quiet $f orientation]]]
    }
    return $rows
}
proc ant070_all_fillers {filter} {   ;# 070: ALL filler instances once, with no geometric query: {name x0 y0 x1 y1 {}} (orientation is read only for the fillers that are removed)
    set rows {}
    foreach_in_collection f [get_cells -quiet -filter $filter] {
        lappend rows [concat [list [get_object_name $f]] [ant068_bbox_of $f] [list {}]]
    }
    return $rows
}
proc ant068_net_leaf_pins {netname} {   ;# 068: names of the leaf pins on a net; VERIFY get_pins -leaf -of_objects <net>
    set out {}
    foreach_in_collection p [get_pins -quiet -leaf -of_objects [get_nets -quiet -exact $netname]] { lappend out [get_object_name $p] }
    return $out
}
proc ant068_check_routes_counts {} {   ;# 068: run check_routes, return {drc opens antenna} from its "Verify Summary" (text as in fix_antenna2_console.log)
    redirect -variable ab_cr_txt { check_routes }
    puts $ab_cr_txt
    return [list [ant_parse_count $ab_cr_txt "DRCs"] [ant_parse_count $ab_cr_txt "open nets"] [ant_parse_count $ab_cr_txt "antenna violations"]]
}

file mkdir $LOG_DIR
file mkdir $RPT_DIR

redirect -tee -file ${LOG_DIR}/6c_antenna_port_buffers.log {
    puts ">>> RUN ROOT: $RUN_ROOT"   ;# 082: the log shows which clone wrote it

    set ab_failures {}

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }
    set open_lib [get_libs -quiet *]
    if {[sizeof_collection $open_lib] > 0} {
        foreach_in_collection lib_obj $open_lib {
            close_lib -force $lib_obj
        }
    }

    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    open_block ${DESIGN_NAME}.dlib:${DESIGN_NAME}_route
    current_block ${DESIGN_NAME}_route
    link_block
    unpu_remove_clock_latency antenna_port_buffers   ;# 088: remove the tool-made set_clock_latency (a no-op when the block is clean); prints the counts per scenario, ERROR 088 if any is left
    puts ">>> 068 block ${DESIGN_NAME}_route opened (it is overwritten in place at the end; the README tells the user to back up the library first)"

    # --------------------------------------------------------------------------
    # 1. Parse the Calibre antenna database
    # --------------------------------------------------------------------------
    if {![file exists $ANT_DB]} { error "ERROR 068: Cannot find the Calibre antenna DB at $ANT_DB (README step 6c copies the NEW run's unpu_top.ant.db there)" }
    set fp [open $ANT_DB r]
    set ab_db [ant_parse_db [read $fp]]
    close $fp
    set ab_polys [dict get $ab_db polys]
    puts ">>> 068 database $ANT_DB: top '[dict get $ab_db top]', [dict get $ab_db dbu] units per um, [llength $ab_polys] polygons"
    array set ab_rule_count {}
    foreach p $ab_polys {
        set r [dict get $p rule]
        if {![info exists ab_rule_count($r)]} { set ab_rule_count($r) 0 }
        incr ab_rule_count($r)
    }
    foreach r [lsort [array names ab_rule_count]] { puts ">>> 068   rule $r: $ab_rule_count($r) polygons" }
    puts ">>> 068 polygons: [llength $ab_polys], expectation of task 068: $EXPECT_POLYGONS (a different number is not an error: the database may be a newer Calibre run)"
    if {[llength $ab_polys] == 0} { error "ERROR 068: the database holds no polygon, nothing to do" }

    # --------------------------------------------------------------------------
    # 2. Port nets and the shapes of those nets, then polygon -> net
    # --------------------------------------------------------------------------
    array set ab_port_of_net {}
    array set ab_net_of_port {}
    array set ab_port_dir {}
    set ab_bad_ports {}
    foreach_in_collection p [get_ports -quiet *] {
        set pn [get_object_name $p]
        if {[lsearch -exact $POWER_PORT_NAMES $pn] >= 0} continue
        set nc [get_nets -quiet -of_objects $p]   ;# 068: VERIFY get_nets -of_objects <port> returns exactly one net
        if {[sizeof_collection $nc] != 1} { lappend ab_bad_ports $pn; continue }
        set nn [get_object_name $nc]
        set ab_port_of_net($nn) $pn
        set ab_net_of_port($pn) $nn
        set ab_port_dir($pn) [get_attribute -quiet $p direction]   ;# 068: VERIFY: `direction` of a port is in / out
    }
    puts ">>> 068 signal ports with one net: [array size ab_net_of_port]; ports without exactly one net: [llength $ab_bad_ports] $ab_bad_ports"
    if {[array size ab_net_of_port] == 0} { error "ERROR 068: no port net found (VERIFY get_ports / get_nets -of_objects)" }

    set ab_layers {}
    foreach p $ab_polys {
        set l [ant_rule_layer [dict get $p rule]]
        if {$l ne "" && [lsearch -exact $ab_layers $l] < 0} { lappend ab_layers $l }
    }
    puts ">>> 068 layers to read: $ab_layers; reading the shapes of [array size ab_net_of_port] port nets (a few minutes at most)"
    array set ab_shapes {}
    foreach l $ab_layers {
        set ab_shapes($l) {}
        foreach pn [lsort [array names ab_net_of_port]] {
            set ab_shapes($l) [concat $ab_shapes($l) [ant068_net_shapes $ab_net_of_port($pn) $l]]
        }
        puts ">>> 068   layer $l: [llength $ab_shapes($l)] port-net shapes"
    }

    array set ab_net_polys {}
    set ab_unresolved {}
    foreach p $ab_polys {
        set rule [dict get $p rule]
        set pid  [dict get $p id]
        lassign [dict get $p bbox] x0 y0 x1 y1
        set lyr [ant_rule_layer $rule]
        set tag "$rule #$pid"
        if {$lyr eq ""} {
            puts ">>> 068 POLY $tag bbox=($x0,$y0)->($x1,$y1) UNRESOLVED: the rule is not a metal-area rule of M1/M2/M3/MT"
            lappend ab_unresolved "$tag: rule without a layer"
            continue
        }
        # candidates: shapes of port nets that overlap the bbox, plus ALL nets seen by get_shapes -intersect (information, and a port net must beat them)
        set cands {}
        foreach s $ab_shapes($lyr) {
            lassign [lrange $s 1 4] sx0 sy0 sx1 sy1
            if {$sx1 >= $x0 && $sx0 <= $x1 && $sy1 >= $y0 && $sy0 <= $y1} { lappend cands $s }
        }
        set others {}
        set win [list [list [expr {$x0 - 0.05}] [expr {$y0 - 0.05}]] [list [expr {$x1 + 0.05}] [expr {$y1 + 0.05}]]]
        foreach_in_collection s [get_shapes -quiet -intersect $win -filter "layer.name == $lyr"] {   ;# 068: unreliable alone (handoff 18.26); used as extra competitors only
            set nc [get_nets -quiet -of_objects $s -filter "net_type == signal || net_type == clock"]   ;# 068: power and ground stripes are not competitors (same filter as fix_antenna.tcl)
            if {[sizeof_collection $nc] == 0} continue
            set nn [get_object_name [index_collection $nc 0]]
            if {[array names ab_port_of_net -exact $nn] ne ""} continue
            lappend cands [concat [list $nn] [ant068_bbox_of $s]]
            if {[lsearch -exact $others $nn] < 0} { lappend others $nn }
        }
        set ranks [ant_rank $p $cands $TOL_UM]
        lassign [ant_decide $ranks $MARGIN_SCORE $MIN_COVER] st chosen note
        set top3 {}
        foreach r [lrange $ranks 0 2] { lappend top3 "[lindex $r 0]:t[lindex $r 1]:[format %.2f [lindex $r 2]]" }
        if {$st eq "OK" && [array names ab_port_of_net -exact $chosen] eq ""} {
            set st NONPORT
            set note "best net $chosen is not connected to a port ($note)"
            set chosen ""
        }
        if {$st eq "OK"} {
            set pn $ab_port_of_net($chosen)
            if {$ab_port_dir($pn) ne "" && [string match -nocase "out*" $ab_port_dir($pn)]} {
                set st OUTPORT
                set note "net $chosen belongs to OUTPUT port $pn (it has a driver; a buffer at the pin does not help)"
                set chosen ""
            }
        }
        puts ">>> 068 POLY $tag layer $lyr bbox=($x0,$y0)->($x1,$y1) candidates=[llength $cands] ranks=[join $top3 { }] others_seen=[llength $others] chosen=[expr {$chosen eq {} ? {none} : $chosen}] status=$st ($note)"
        if {$st eq "OK"} {
            lappend ab_net_polys($chosen) $tag
        } else {
            lappend ab_unresolved "$tag bbox=($x0,$y0)->($x1,$y1): $st, $note"
        }
    }
    puts ">>> 068 polygons resolved: [expr {[llength $ab_polys] - [llength $ab_unresolved]}] of [llength $ab_polys]; unresolved: [llength $ab_unresolved]"
    foreach u $ab_unresolved { puts ">>> 068 UNRESOLVED $u" }
    if {[llength $ab_unresolved] > 0} {
        error "ERROR 068: [llength $ab_unresolved] polygon(s) could not be assigned to a port net (listed above). Nothing was changed. Decide those by hand (get_shapes at the bbox, see handoff 18.26/18.27)."
    }

    # --------------------------------------------------------------------------
    # 3. The set of port nets and the comparison with the expectation
    # --------------------------------------------------------------------------
    set ab_set [lsort [array names ab_net_polys]]
    puts ">>> 068 port nets with antenna polygons: [llength $ab_set]"
    foreach n $ab_set { puts ">>> 068   $n (port $ab_port_of_net($n)): [llength $ab_net_polys($n)] polygons: [join $ab_net_polys($n) {, }]" }
    set ab_missing {}
    foreach e $EXPECT_PORT_NETS { if {[lsearch -exact $ab_set $e] < 0} { lappend ab_missing $e } }
    set ab_extra {}
    foreach n $ab_set { if {[lsearch -exact $EXPECT_PORT_NETS $n] < 0} { lappend ab_extra $n } }
    puts ">>> 068 compared with the [llength $EXPECT_PORT_NETS] nets expected by task 068: expected but not found: [llength $ab_missing] $ab_missing; found but not expected: [llength $ab_extra] $ab_extra"

    # --------------------------------------------------------------------------
    # 4. Clock nets are not buffered: print what Planning needs
    # --------------------------------------------------------------------------
    set ab_clk_ports {}
    foreach_in_collection c [get_clocks -quiet -filter "is_virtual == false"] {
        foreach_in_collection s [get_attribute -quiet $c sources] { lappend ab_clk_ports [get_object_name $s] }   ;# 068: VERIFY the `sources` attribute of a clock
    }
    puts ">>> 068 clock source ports: $ab_clk_ports"
    set ab_targets {}
    set ab_clk_nets {}
    foreach n $ab_set {
        set pn $ab_port_of_net($n)
        set nt [get_attribute -quiet [get_nets -quiet -exact $n] net_type]
        if {[lsearch -exact $ab_clk_ports $pn] >= 0 || $nt eq "clock"} { lappend ab_clk_nets $n } else { lappend ab_targets $n }
    }
    puts ">>> 068 nets to buffer: [llength $ab_targets]; clock nets left alone: [llength $ab_clk_nets] $ab_clk_nets"
    foreach n $ab_clk_nets {
        set pn $ab_port_of_net($n)
        set t [get_terminals -quiet -of_objects [get_ports -quiet -exact $pn]]
        if {[sizeof_collection $t] == 0} { puts ">>> 068 CLOCK $n: no terminal found"; continue }
        lassign [ant068_centre [index_collection $t 0]] cpx cpy
        puts ">>> 068 CLOCK $n (port $pn): pin at ([format %.2f $cpx], [format %.2f $cpy]); polygons: [join $ab_net_polys($n) {, }]"
        set cl {}
        foreach lp [ant068_net_leaf_pins $n] {
            lassign [ant068_centre [get_pins -quiet -exact $lp]] lx ly
            lappend cl [list $lp $lx $ly [ant_manhattan $cpx $cpy $lx $ly]]
        }
        foreach r [lrange [lsort -real -index 3 $cl] 0 4] { puts ">>> 068 CLOCK $n load [lindex $r 0] at ([format %.2f [lindex $r 1]], [format %.2f [lindex $r 2]]) Manhattan distance from the pin [format %.1f [lindex $r 3]] um" }
        puts ">>> 068 CLOCK $n: [llength $cl] leaf loads on the port net (the CTS root); NOT buffered by this script (a buffer before the CTS root shifts the clock latency and the I/O timing: decision for Planning)"
    }
    if {[llength $ab_targets] == 0} { error "ERROR 068: no non-clock port net to buffer" }

    # --------------------------------------------------------------------------
    # 5. Buffer cell chosen by data
    # --------------------------------------------------------------------------
    if {![file exists $STD_LEF]} { error "ERROR 068: kit LEF not found at $STD_LEF" }
    set fp [open $STD_LEF r]
    set ab_lef [ant_parse_lef [read $fp]]
    close $fp
    puts ">>> 068 LEF $STD_LEF: [dict size $ab_lef] macros"
    set ab_bufnames {}
    set ab_libcell_of {}
    if {[catch {set ab_lc [get_lib_cells -quiet ${STD_LIB}/* -filter "is_buffer == true"]} err]} {   ;# 068: VERIFY lib_cell attribute is_buffer (non-inverting buffer)
        error "ERROR 068: cannot select buffers with the lib_cell attribute is_buffer: $err"
    }
    foreach_in_collection lc $ab_lc {
        set full [get_object_name $lc]
        set short [lindex [split $full /] end]
        set du [get_attribute -quiet $lc dont_use]
        if {$du eq "true"} { puts ">>> 068   $short: dont_use attribute is true in the library, skipped"; continue }
        lappend ab_bufnames $short
        lappend ab_libcell_of $short $full
    }
    puts ">>> 068 library buffers (is_buffer, not dont_use): [llength $ab_bufnames]"
    if {[llength $ab_bufnames] == 0} { error "ERROR 068: no buffer cell found in ${STD_LIB}" }
    set ab_need [ant_need_gate $PIN_WIRE_UM $WIRE_WIDTH_UM $ANT_WEIGHT_PINWIRE $ANT_RATIO_LIMIT $GATE_SAFETY]
    puts ">>> 068 requirements: (a) output diffusion >= $DIODE_MIN_AREA um^2; (b) input gate >= [format %.4f $ab_need] um^2 for a ${PIN_WIRE_UM} um wire (2 x (L+W) x $ANT_WEIGHT_PINWIRE / $ANT_RATIO_LIMIT x $GATE_SAFETY); (c) not in {$DONT_USE_PATTERNS}; (d) one input, one output, non-inverting"
    set ab_rows [ant_eval_buffers $ab_lef $ab_bufnames $DONT_USE_PATTERNS $ab_need $DIODE_MIN_AREA]
    puts ">>> 068 candidate table (name, footprint um^2, input gate um^2, output diffusion um^2, verdict, reason):"
    foreach r [lsort -real -index 3 [lmap r $ab_rows {list [dict get $r name] [dict get $r verdict] [dict get $r why] [dict get $r area] [dict get $r gate] [dict get $r diff]}]] {
        puts [format ">>> 068   %-12s area %8.2f  gate %7.3f  diff %7.3f  %s  %s" [lindex $r 0] [lindex $r 3] [lindex $r 4] [lindex $r 5] [lindex $r 1] [lindex $r 2]]
    }
    set ab_buf [ant_pick_buffer $ab_rows]
    if {$ab_buf eq ""} {
        error "ERROR 068: no library buffer meets (a) to (d); see the candidate table above"
    }
    foreach r $ab_rows { if {[dict get $r name] eq $ab_buf} { set ab_buf_row $r } }
    set ab_buf_lc [dict get $ab_libcell_of $ab_buf]
    set ab_bw [dict get $ab_buf_row w]
    set ab_bh [dict get $ab_buf_row h]
    puts ">>> 068 CHOSEN buffer $ab_buf_lc: smallest footprint ([format %.2f [dict get $ab_buf_row area]] um^2, ${ab_bw} x ${ab_bh}) among the cells that pass (a) to (d); input gate [format %.3f [dict get $ab_buf_row gate]] um^2, output diffusion [format %.3f [dict get $ab_buf_row diff]] um^2"

    # --------------------------------------------------------------------------
    # 6. Measurements before the ECO
    # --------------------------------------------------------------------------
    set ab_rows_sites [get_site_rows -quiet]   ;# 068: VERIFY: the core box = union of the site row boxes
    if {[sizeof_collection $ab_rows_sites] == 0} { error "ERROR 068: no site rows found" }
    set cx0 1e9; set cy0 1e9; set cx1 -1e9; set cy1 -1e9
    foreach_in_collection sr $ab_rows_sites {
        lassign [ant068_bbox_of $sr] a b c d
        set cx0 [expr {min($cx0, $a)}]; set cy0 [expr {min($cy0, $b)}]; set cx1 [expr {max($cx1, $c)}]; set cy1 [expr {max($cy1, $d)}]
    }
    set ab_core [list $cx0 $cy0 $cx1 $cy1]
    puts ">>> 068 core box from the site rows: ($cx0,$cy0)->($cx1,$cy1) (rows [sizeof_collection $ab_rows_sites])"

    update_timing -full
    puts ">>> 068 ===== report_global_timing BEFORE ====="
    report_global_timing
    array set ab_pin_xy {}
    array set ab_loads_before {}
    array set ab_slack0 {}
    foreach n $ab_targets {
        set pn $ab_port_of_net($n)
        set t [get_terminals -quiet -of_objects [get_ports -quiet -exact $pn]]
        if {[sizeof_collection $t] == 0} { lappend ab_failures "net $n: port $pn has no terminal"; continue }
        set ab_pin_xy($n) [ant068_centre [index_collection $t 0]]
        set ab_loads_before($n) [llength [ant068_net_leaf_pins $n]]
        set ab_slack0($n) [list [ant068_slack $pn $SETUP_SCEN max] [ant068_slack $pn $HOLD_SCEN min]]
        if {[info exists ab_timing_err]} {   ;# 069: no error text as a result
            puts ">>> 068 BEFORE $n: pin ([format %.2f [lindex $ab_pin_xy($n) 0]], [format %.2f [lindex $ab_pin_xy($n) 1]]), leaf loads $ab_loads_before($n)"
        } else {
            puts ">>> 068 BEFORE $n: pin ([format %.2f [lindex $ab_pin_xy($n) 0]], [format %.2f [lindex $ab_pin_xy($n) 1]]), leaf loads $ab_loads_before($n), worst slack from the port: setup [lindex $ab_slack0($n) 0] ($SETUP_SCEN), hold [lindex $ab_slack0($n) 1] ($HOLD_SCEN)"
        }
    }
    if {[llength $ab_failures] > 0} { error "ERROR 068: [join $ab_failures {; }]" }
    set ab_anti_before [ant068_check_routes_counts]
    puts ">>> 068 check_routes BEFORE: DRCs [lindex $ab_anti_before 0], open nets [lindex $ab_anti_before 1], ICC2 antenna violations [lindex $ab_anti_before 2] (ICC2 skips port nets, Calibre decides)"
    set ab_drc_before [lindex $ab_anti_before 0]

    # --------------------------------------------------------------------------
    # 7. ECO (069): pick a free run of FILLER sites per net, remove exactly those fillers, insert, place on the site, verify, undo and retry on failure
    # --------------------------------------------------------------------------
    # 069: the first server run asked the legaliser to find a site in a cleared window; two buffers were moved 360 and 1080 um away (it never fails, it moves).
    # 069: now the site is chosen here from the fillers that route.tcl created, and the result is verified (position and distance) before the next net.
    set ab_filter {}
    foreach f $FILLER_REFS { lappend ab_filter "ref_name == $f" }
    set ab_filter [join $ab_filter " || "]
    set ab_site_w 1e9
    foreach f $FILLER_REFS {   ;# 069: the site width is the width of the narrowest filler master in the LEF (data, not typed)
        if {[dict exists $ab_lef $f] && [dict get $ab_lef $f w] ne "" && [dict get $ab_lef $f w] < $ab_site_w} { set ab_site_w [dict get $ab_lef $f w] }
    }
    if {$ab_site_w > 1e8} { error "ERROR 069: none of the filler masters $FILLER_REFS is in the LEF, the site width is unknown" }
    # 070: the first server run of 069 found 0 usable sites for all nets and "the nearest free run" about 300 um away (the half size of the wide window) for every pin:
    # 070: the candidates were all at the border of the search window, so get_cells -intersect with a rectangle returned the cells at the window border, not the interior (cause
    # 070: inferred from the numbers, to be confirmed by pnr_v2/diag_filler_runs.tcl). The ECO therefore reads every filler ONCE without a geometric query and selects the
    # 070: window in Tcl (ant_rows_in_window). Removed fillers are deleted from the table (they are refilled at the end).
    set ab_t0 [clock seconds]
    set ab_ftable [ant070_all_fillers $ab_filter]
    puts ">>> 070 filler table: [llength $ab_ftable] filler instances read in [expr {[clock seconds] - $ab_t0}] s, extent [ant_rows_extent $ab_ftable]"
    if {[llength $ab_ftable] == 0} { error "ERROR 070: no filler instance found with the filter '$ab_filter' (the design has fillers: route.tcl creates them)" }
    set ab_gate [dict get $ab_buf_row gate]
    set ab_tier2_dist [ant_max_dist_for_ratio $ab_gate $WIRE_WIDTH_UM $ANT_WEIGHT_PINWIRE $TIER2_RATIO]
    puts ">>> 069 site width $ab_site_w um (narrowest of $FILLER_REFS in the LEF), buffer $ab_buf is ${ab_bw} um wide = [expr {int(ceil($ab_bw / $ab_site_w - 1e-6))}] sites; tier 1 limit $MAX_PIN_BUF_DIST um; tier 2 limit [format %.1f $ab_tier2_dist] um (predicted M2/M3 ratio <= $TIER2_RATIO with gate [format %.3f $ab_gate])"
    array set ab_cell_of {}
    array set ab_newnet_of {}
    array set ab_tier {}
    array set ab_lim {}
    set ab_removed 0
    set ab_failed {}
    set k 0
    foreach n $ab_targets {
        set pn $ab_port_of_net($n)
        lassign $ab_pin_xy($n) px py
        set ab_cell_of($n) ""
        set placed 0
        set tried {}
        foreach tier {1 2} {
            if {$placed} break
            set lim [expr {$tier == 1 ? $MAX_PIN_BUF_DIST : $ab_tier2_dist}]
            if {$tier == 2 && $lim <= $MAX_PIN_BUF_DIST} continue
            set L [expr {$lim + $ab_bw + $ab_bh}]
            set win [list [list [expr {$px - $L}] [expr {$py - $L}]] [list [expr {$px + $L}] [expr {$py + $L}]]]
            set frows [ant_rows_in_window $ab_ftable [expr {$px - $L}] [expr {$py - $L}] [expr {$px + $L}] [expr {$py + $L}]]   ;# 070: window selection in Tcl
            set runs [ant_filler_runs $frows]
            set cands {}
            foreach c [ant_site_candidates $runs $ab_bw $ab_site_w $px $py $lim] {
                if {[lsearch -exact $tried [list [dict get $c x] [dict get $c y]]] < 0} { lappend cands $c }
            }
            puts ">>> 069 $n tier $tier: limit [format %.1f $lim] um, [llength $frows] fillers in the search window, [llength $runs] runs, [llength $cands] usable candidate sites"
            if {[llength $cands] == 0} {   ;# 070: nothing fails silently: say why, run by run
                puts ">>> 070 $n tier $tier: 0 usable candidates. pin=([format %.3f $px], [format %.3f $py]) window=({[format %.3f [expr {$px - $L}]] [format %.3f [expr {$py - $L}]]} {[format %.3f [expr {$px + $L}]] [format %.3f [expr {$py + $L}]]}) buffer width $ab_bw needs [format %.2f [expr {ceil($ab_bw / $ab_site_w - 1e-6) * $ab_site_w}]] um of contiguous filler, site width $ab_site_w"
                if {[llength $runs] == 0} { puts ">>> 070 $n tier $tier:   no filler run in the window" }
                foreach ln [ant_run_report $runs $ab_bw $ab_site_w $px $py $lim 3] { puts ">>> 070 $n tier $tier:   nearest run: $ln" }
            }
            if {![info exists ab_070_first]} {   ;# 070: for the FIRST net only: the raw rows and the extent, so a wrong query is visible
                set ab_070_first 1
                puts ">>> 070 first net $n: first 3 filler rows of the window {name x0 y0 x1 y1 orient}: [lrange $frows 0 2]"
                puts ">>> 070 first net $n: extent of the [llength $frows] window fillers [ant_rows_extent $frows] (window $win)"
            }
            set ntry 0
            foreach c $cands {
                if {$ntry >= $MAX_SITE_TRIES} break
                incr ntry
                set cx [dict get $c x]; set cy [dict get $c y]
                lappend tried [list $cx $cy]
                set rm [dict get $c names]
                set flc [get_cells -quiet -exact $rm]
                if {[sizeof_collection $flc] != [llength $rm]} {
                    puts ">>> 069 BUFFER $n tier $tier candidate ($cx, $cy): only [sizeof_collection $flc] of [llength $rm] filler names found, candidate skipped"
                    continue
                }
                set ori0 [get_attribute -quiet [index_collection $flc 0] orientation]   ;# 070: VERIFY `orientation` of a filler (MX / N / FS ...), read here only for the removed fillers
                remove_cells $flc   ;# 069: VERIFY remove_cells on the filler instances (as in task 068)
                set ab_ftable [ant_rows_remove $ab_ftable $rm]   ;# 070: the table follows the design
                incr ab_removed [llength $rm]
                set base "${BUF_PREFIX}_[regsub -all {[^A-Za-z0-9]} $pn _]_${k}_t${tier}a${ntry}"
                insert_buffer -lib_cell [get_lib_cells -exact $ab_buf_lc] -new_cell_names $base -new_net_names ${base}_n [get_ports -exact $pn]   ;# 068: VERIFY insert_buffer on a PORT puts the buffer between the port and all its loads (usage text: add_buffer ... object_list = nets, ports or pins)
                set bname ""
                foreach_in_collection c2 [get_cells -quiet -of_objects [get_nets -quiet -exact $n]] {
                    if {[get_attribute -quiet $c2 ref_name] eq $ab_buf} { set bname [get_object_name $c2] }
                }
                if {$bname eq ""} { error "ERROR 069: net $n: no cell of type $ab_buf found on the port net after insert_buffer (nothing saved)" }
                set bc [get_cells -exact $bname]
                set op [get_pins -quiet -of_objects $bc -filter "direction == out"]   ;# 068: VERIFY pin attribute direction == out
                if {[sizeof_collection $op] != 1} { error "ERROR 069: net $n: buffer $bname has [sizeof_collection $op] output pins (nothing saved)" }
                set newnet [get_object_name [get_nets -quiet -of_objects $op]]
                set sargs [list -coordinates [list $cx $cy]]
                if {$ori0 ne ""} { lappend sargs -orientation $ori0 }   ;# 069: the row's orientation, read from the removed fillers (070: read just before the removal)
                if {[catch {set_cell_location {*}$sargs $bc} err]} {   ;# 068: VERIFY set_cell_location (the first server run accepted -coordinates); 069: VERIFY -orientation
                    puts ">>> 069 set_cell_location failed ($err), trying the origin attribute"
                    if {[catch {set_attribute -objects $bc -name origin -value [list $cx $cy]} err2]} { error "ERROR 069: net $n: cannot move $bname: $err / $err2 (nothing saved)" }
                }
                legalize_placement -cells $bc   ;# 069: only this cell; at a free site it must not move
                lassign [ant068_bbox_of $bc] bx0 by0 bx1 by1
                set dpos [ant_manhattan $bx0 $by0 $cx $cy]
                set inp [get_pins -quiet -of_objects $bc -filter "direction == in"]   ;# 068: VERIFY pin attribute direction == in
                lassign [expr {[sizeof_collection $inp] == 1 ? [ant068_centre $inp] : [ant068_centre $bc]}] ix iy
                set dist [ant_manhattan $px $py $ix $iy]
                set ratio [ant_ratio $ab_gate $dist $WIRE_WIDTH_UM $ANT_WEIGHT_PINWIRE]
                set why {}
                if {$dpos > 0.001} { lappend why "buffer at ([format %.3f $bx0], [format %.3f $by0]) instead of the site ([format %.3f $cx], [format %.3f $cy])" }
                if {$dist > $lim} { lappend why "distance [format %.1f $dist] > [format %.1f $lim]" }
                puts [format ">>> 069 BUFFER %s tier %d pin=(%.2f, %.2f) run: row y=%.2f x=%.2f..%.2f fillers_removed=%d %s buffer=%s site=(%.3f, %.3f) final=(%.3f, %.3f) distance=%.1f um predicted_ratio=%.0f %s" \
                    $n $tier $px $py $cy [dict get $c run_x0] [dict get $c run_x1] [llength $rm] $rm $bname $cx $cy $bx0 $by0 $dist $ratio [expr {[llength $why] ? "REJECTED: [join $why {; }]" : "OK"}]]
                if {[llength $why] == 0} {
                    set ab_cell_of($n) $bname
                    set ab_newnet_of($n) $newnet
                    set ab_tier($n) $tier
                    set ab_lim($n) $lim
                    set placed 1
                    if {$tier == 2} {
                        puts ">>> 069 $n: TIER 2: no usable filler run within $MAX_PIN_BUF_DIST um; buffer [format %.1f $dist] um from the pin, predicted M2/M3 ratio [format %.0f $ratio] (<= $TIER2_RATIO); the route of this port net is limited to layers up to $TIER2_MAX_LAYER"
                        set_routing_rule -max_routing_layer $TIER2_MAX_LAYER -max_layer_mode hard [get_nets -quiet -exact $n]   ;# 069: VERIFY set_routing_rule on a signal net (usage text); 'hard' = the route may not use a layer above M3 (TOP_M weight 0.84 allows only about 45 um)
                    }
                    break
                }
                # undo this net and retry with the next candidate
                if {[catch {remove_buffers $bc} err]} { error "ERROR 069: net $n: cannot remove the rejected buffer $bname: $err (nothing saved)" }   ;# 069: VERIFY remove_buffers restores the original net
                set back [llength [ant068_net_leaf_pins $n]]
                if {$back != $ab_loads_before($n)} { error "ERROR 069: net $n: $back leaf pins after removing the rejected buffer, $ab_loads_before($n) before (nothing saved)" }
                puts ">>> 069 $n: rejected buffer $bname removed, net restored ($back leaf pins)"
            }
        }
        if {!$placed} {
            set wide [ant_site_candidates [ant_filler_runs [ant_rows_in_window $ab_ftable [expr {$px - 300.0}] [expr {$py - 300.0}] [expr {$px + 300.0}] [expr {$py + 300.0}]]] $ab_bw $ab_site_w $px $py 1e9]   ;# 069: only for the message: the nearest free run in a wider window (070: from the table)
            if {[llength $wide] > 0} { set nearest "nearest free filler run at [format %.1f [dict get [lindex $wide 0] dist]] um" } else { set nearest "no free filler run within 300 um" }
            puts ">>> 069 BUFFER $n FAILED: no site within the tier 1 limit ($MAX_PIN_BUF_DIST um) or the tier 2 limit ([format %.1f $ab_tier2_dist] um); $nearest"
            lappend ab_failed "$n ($nearest)"
        }
        incr k
    }
    puts ">>> 068 fillers removed: $ab_removed"
    if {[llength $ab_failed] > 0} { error "ERROR 069: [llength $ab_failed] net(s) FAILED to get a buffer site, nothing saved (the design in memory is not saved): [join $ab_failed {; }]" }

    set fill_cells [get_lib_cells -quiet [lmap f $FILLER_REFS {string cat ${FILLER_LIB}/ $f}]]   ;# 068: the same selection as route.tcl
    if {[sizeof_collection $fill_cells] == 0} { set fill_cells [get_lib_cells -quiet {*/feedth9 */feedth3 */feedth}] }
    if {[sizeof_collection $fill_cells] > 0} {
        create_stdcell_fillers -lib_cells $fill_cells   ;# 068: as route.tcl: only empty sites are filled, the other fillers stay
    } else {
        lappend ab_failures "filler cells not found, the removed fillers are not restored"
    }
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # --------------------------------------------------------------------------
    # 8. Re-route only the touched nets
    # --------------------------------------------------------------------------
    set ab_touched {}
    foreach n $ab_targets {
        lappend ab_touched $n $ab_newnet_of($n)
    }
    set ab_touched_coll [get_nets -quiet -exact $ab_touched]
    puts ">>> 068 nets to re-route: [sizeof_collection $ab_touched_coll] ($ab_touched)"
    remove_routes -nets $ab_touched_coll -detail_route
    route_eco \
        -nets $ab_touched_coll \
        -reuse_existing_global_route false \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 60
    route_eco \
        -open_net_driven true \
        -reuse_existing_global_route true \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 40
    route_detail -incremental true -max_number_iterations 40

    # --------------------------------------------------------------------------
    # 9. Leftover DRC markers (the task expects M3.S.1 near (127.8, 287.0))
    # --------------------------------------------------------------------------
    set ab_cr [ant068_check_routes_counts]
    set ab_drc [lindex $ab_cr 0]
    puts ">>> 068 check_routes after the ECO: DRCs $ab_drc (before $ab_drc_before), open nets [lindex $ab_cr 1], ICC2 antenna violations [lindex $ab_cr 2]"
    if {$ab_drc ne "" && $ab_drc > 0} {
        puts ">>> 068 DRC error list (VERIFY the command: get_drc_errors with the error data of check_routes):"
        if {[catch {
            foreach_in_collection e [get_drc_errors -quiet -error_data zroute.err *] {   ;# 068: VERIFY get_drc_errors and the error data name
                puts ">>> 068   DRC [get_attribute -quiet $e type_name] bbox [get_attribute -quiet $e bounding_box]"
            }
        } err]} { puts ">>> 068   could not list the DRC errors: $err" }
        set ab_wins {}
        if {[file exists $DRC_DB]} {   ;# 068: the Calibre DRC markers give the locations (same ASCII format as the antenna database)
            set fp [open $DRC_DB r]
            set ab_drcdb [ant_parse_db [read $fp]]
            close $fp
            foreach p [dict get $ab_drcdb polys] {
                lassign [dict get $p bbox] a b c d
                puts ">>> 068   Calibre marker [dict get $p rule] #[dict get $p id] at ($a,$b)->($c,$d)"
                lappend ab_wins [list [list [expr {$a - 5.0}] [expr {$b - 5.0}]] [list [expr {$c + 5.0}] [expr {$d + 5.0}]]]
            }
        } else {
            puts ">>> 068   $DRC_DB not found: no Calibre marker location (README copies unpu_top.drc.db there)"
        }
        foreach w $ab_wins {
            route_detail -incremental true -max_number_iterations 40 -coordinates [list $w]   ;# 068: the same incremental routing, limited to the marker window
        }
        set ab_cr [ant068_check_routes_counts]
        set ab_drc [lindex $ab_cr 0]
        puts ">>> 068 check_routes after the window clean-up: DRCs $ab_drc"
    }

    # --------------------------------------------------------------------------
    # 10. Final checks (nothing is saved when one fails)
    # --------------------------------------------------------------------------
    if {$ab_drc eq ""} { lappend ab_failures "check_routes DRC count not readable" } elseif {$ab_drc != 0} { lappend ab_failures "check_routes DRCs $ab_drc (0 required)" }
    set ab_open [lindex $ab_cr 1]
    if {$ab_open eq ""} { lappend ab_failures "check_routes open-net count not readable" } elseif {$ab_open != 0} { lappend ab_failures "check_routes open nets $ab_open (0 required)" }

    redirect -variable ab_leg_txt { check_legality -verbose }
    puts $ab_leg_txt
    set ab_leg [ant_parse_legality $ab_leg_txt]
    if {$ab_leg eq ""} { if {![catch {sizeof_collection [check_legality -cell_violation]} v]} { set ab_leg $v } }   ;# 068: VERIFY -cell_violation (usage text) as fallback when the text has no number
    puts ">>> 068 CHECK legality violations: [expr {$ab_leg eq {} ? {unreadable} : $ab_leg}] (0 required)"
    if {$ab_leg eq ""} { lappend ab_failures "check_legality result unreadable (see the text above)" } elseif {$ab_leg != 0} { lappend ab_failures "legality violations $ab_leg" }

    set ab_nbuf [sizeof_collection [get_cells -quiet ${BUF_PREFIX}_*]]
    puts ">>> 068 CHECK buffers in the design: $ab_nbuf, nets buffered: [llength $ab_targets]"
    if {$ab_nbuf != [llength $ab_targets]} { lappend ab_failures "buffer count $ab_nbuf != nets buffered [llength $ab_targets]" }

    foreach n $ab_targets {
        set pn $ab_port_of_net($n)
        set bc [get_cells -quiet -exact $ab_cell_of($n)]
        if {[sizeof_collection $bc] == 0} { lappend ab_failures "net $n: buffer $ab_cell_of($n) vanished"; continue }
        set pin_loads [llength [ant068_net_leaf_pins $n]]
        set out_loads [expr {[llength [ant068_net_leaf_pins $ab_newnet_of($n)]] - 1}]
        puts ">>> 068 CHECK $n: loads before $ab_loads_before($n); after: port net $pin_loads leaf pin (the buffer input), buffer output net $out_loads loads"
        if {$pin_loads != 1} { lappend ab_failures "net $n: port net has $pin_loads leaf pins after the ECO (1 required)" }
        if {$out_loads != $ab_loads_before($n)} { lappend ab_failures "net $n: loads $ab_loads_before($n) before, $out_loads after the buffer" }
        set inp [get_pins -quiet -of_objects $bc -filter "direction == in"]   ;# 068: VERIFY pin attribute direction == in
        lassign [expr {[sizeof_collection $inp] == 1 ? [ant068_centre $inp] : [ant068_centre $bc]}] bx by
        lassign $ab_pin_xy($n) px py
        set dist [ant_manhattan $px $py $bx $by]
        set gate [dict get $ab_buf_row gate]
        set r1 [ant_ratio $gate $dist $WIRE_WIDTH_UM $ANT_WEIGHT_PINWIRE]
        set r2 [ant_ratio $gate $dist $WIRE_WIDTH_UM $ANT_WEIGHT_TOPM]
        puts ">>> 068 CHECK $n: buffer $ab_cell_of($n) at ([format %.2f $bx], [format %.2f $by]), pin at ([format %.2f $px], [format %.2f $py]): Manhattan distance [format %.1f $dist] um (limit $ab_lim($n), tier $ab_tier($n)); predicted ratio on M2/M3 [format %.0f $r1], on TOP_M [format %.0f $r2] (limit $ANT_RATIO_LIMIT)"
        if {$dist > $ab_lim($n)} { lappend ab_failures "net $n: buffer is $dist um from the pin (limit $ab_lim($n), tier $ab_tier($n))" }   ;# 069: the limit of the tier the net was placed in
        if {$r1 > $ANT_RATIO_LIMIT} { lappend ab_failures "net $n: predicted antenna ratio [format %.0f $r1] on M2/M3 exceeds $ANT_RATIO_LIMIT" }
    }

    # --------------------------------------------------------------------------
    # 11. Timing after the ECO: reported, not tuned
    # --------------------------------------------------------------------------
    update_timing -full
    puts ">>> 068 ===== report_global_timing AFTER ====="
    report_global_timing
    foreach n $ab_targets {
        set pn $ab_port_of_net($n)
        set s1 [list [ant068_slack $pn $SETUP_SCEN max] [ant068_slack $pn $HOLD_SCEN min]]
        if {[info exists ab_timing_err]} continue   ;# 069: the one message "per-net timing unavailable: <reason>" was printed once; no per-net line with error text
        set worse {}
        foreach i {0 1} {
            set a [lindex $ab_slack0($n) $i]
            set b [lindex $s1 $i]
            if {[string is double -strict $a] && [string is double -strict $b] && $b < $a - 1e-6} { lappend worse [lindex {setup hold} $i] }
        }
        puts ">>> 068 TIMING $n: setup [lindex $ab_slack0($n) 0] -> [lindex $s1 0], hold [lindex $ab_slack0($n) 1] -> [lindex $s1 1]  [expr {[llength $worse] ? "WORSE: $worse" : {not worse}}]"
    }
    if {[info exists ab_timing_err]} { puts ">>> 069 per-net TIMING lines skipped (reason above); the report_global_timing tables before and after are printed" }
    if {[llength $ab_failures] > 0} {
        error "ERROR 068: [llength $ab_failures] check(s) failed, NOTHING SAVED: [join $ab_failures {; }]"
    }

    # --------------------------------------------------------------------------
    # 12. Save over _route (as fix_antenna.tcl) and finish
    # --------------------------------------------------------------------------
    save_block
    save_block -force -as ${DESIGN_NAME}_route
    save_lib
    puts ">>> STAGE 6c COMPLETE: [llength $ab_targets] port nets buffered with $ab_buf_lc, ${DESIGN_NAME}_route overwritten in place. Log: ${LOG_DIR}/6c_antenna_port_buffers.log"
    puts ">>> 068 NEXT: metal_fill.tcl, pv.tcl, then a NEW Calibre antenna run; only a database from that new run may be used for another pass of this script."
    puts ">>> 068 clock nets left for a decision: $ab_clk_nets"
}
