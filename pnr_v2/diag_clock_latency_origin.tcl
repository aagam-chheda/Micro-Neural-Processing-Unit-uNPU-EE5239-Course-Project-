# ==============================================================================
# Script: diag_clock_latency_origin.tcl
# Path  : <RUN_DIR>/pnr_v2/diag_clock_latency_origin.tcl   ;# 088 Part 0: READ-ONLY, on a library of THIS clone
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 088: QUESTION. ICC2 writes `set_clock_latency <v> [get_clocks {clk}]` into the block and counts it as the I/O reference latency (task 086, A0). In which block of the chain does the line
# 088: FIRST exist? The 086 run could not say: its copy held only unpu_top_route. Run 2's own library has unpu_top_placement, unpu_top_portbuf, unpu_top_cts. This script opens each named block
# 088: READ-ONLY (open_block -read), writes the SDC of every scenario into pnr_icc2/diag/ and counts the set_clock_latency lines, then prints the table (block, scenario, count, value) and the
# 088: first block per scenario. If the line is already in _cts, the next question (which clock_opt step creates it) is answered by the split of clock_opt in cts.tcl, which prints the count
# 088: before each removal.
# 088: nothing is saved or changed; no save_block, save_lib or write_* into the library (write_sdc only into the diag folder).
# 088: optional environment variables (the clone stays clean): UNPU_WI_LIB (a library path; default <RUN_ROOT>/pnr_icc2/blocks/unpu_top.dlib; it must lie in this clone or in no clone, like
# 088: diag_io_latency.tcl), UNPU_WI_BLOCKS (a list of block names; default unpu_top_placement unpu_top_portbuf unpu_top_cts unpu_top_route). Invalid values are ERROR 088; the printed
# 088: parameters line says where each value came from. A block that is not in the library is skipped and printed; at least one must exist.
# 088: every ICC2 command or option not shown in a usage text in ~/server_pull/rpt/help is marked VERIFY.
# 088: run  : cd <RUN_DIR>/pnr_icc2 ; icc2_shell -f ../pnr_v2/diag_clock_latency_origin.tcl |& tee diag_clock_latency_origin_console.log ; then `exit`
# ==============================================================================

set DESIGN_NAME "unpu_top"
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"
set DIAG_DIR    "${PNR_DIR}/diag"
set SCRIPT_DIR  "${RUN_ROOT}/pnr_v2"

set ORIGIN_LIB     "${PNR_DIR}/blocks/${DESIGN_NAME}.dlib"   ;# 088: run 2's own library (default)
set ORIGIN_BLOCKS  [list ${DESIGN_NAME}_placement ${DESIGN_NAME}_portbuf ${DESIGN_NAME}_cts ${DESIGN_NAME}_route]

# the pure procs of 084 (guards) and 086 (SDC latency lines, the A0 table) are read from their texts, not copied
foreach {src_name b_marker e_marker} {diag_io_latency.tcl "# ---- BEGIN PURE TCL 084 ----" "# ---- END PURE TCL 084 ----"  diag_io_whatif.tcl "# ---- BEGIN PURE TCL 086 ----" "# ---- END PURE TCL 086 ----"} {
    set fp [open ${SCRIPT_DIR}/$src_name r]; set txt [read $fp]; close $fp
    set b [string first $b_marker $txt]; set e [string first $e_marker $txt]
    if {$b < 0 || $e < 0 || $e <= $b} { error "ERROR 088: markers $b_marker not found in ${SCRIPT_DIR}/$src_name" }
    eval [string range $txt $b $e]
}

# ---- BEGIN PURE TCL 088O ----
# orig088_lib <default> <env value or NONE> -> {path source}; a set variable must not be empty (the guard diag084_lib_check checks the rest)
proc orig088_lib {default envval} {
    if {$envval eq "NONE"} { return [list $default default] }
    if {[string trim $envval] eq ""} { error "ERROR 088: UNPU_WI_LIB is set but empty" }
    return [list [string trim $envval] "environment UNPU_WI_LIB"]
}
# orig088_blocks <default list> <env value or NONE> -> {list source}; every name must be a plain block name (letters, digits, _ . : / -), the list must not be empty
proc orig088_blocks {default envval} {
    if {$envval eq "NONE"} { return [list $default default] }
    set l [lsearch -all -inline -not -exact [split [string map {, " "} $envval] " "] ""]
    if {[llength $l] == 0} { error "ERROR 088: UNPU_WI_BLOCKS is set but contains no block name" }
    foreach b $l { if {![regexp {^[A-Za-z0-9_.:/-]+$} $b]} { error "ERROR 088: UNPU_WI_BLOCKS: '$b' is not a block name" } }
    return [list $l "environment UNPU_WI_BLOCKS"]
}
# orig088_present <block> <names that exist> -> 1 when the block is in the library (as lib:block, lib:block/label.view, block or block.view)
proc orig088_present {block existing} { return [expr {[diag084_block_check $block $existing] eq ""}] }
# ---- END PURE TCL 088O ----

set ev1 [expr {[info exists ::env(UNPU_WI_LIB)] ? $::env(UNPU_WI_LIB) : "NONE"}]
set ev2 [expr {[info exists ::env(UNPU_WI_BLOCKS)] ? $::env(UNPU_WI_BLOCKS) : "NONE"}]
lassign [orig088_lib $ORIGIN_LIB $ev1] ORIGIN_LIB lib_src
lassign [orig088_blocks $ORIGIN_BLOCKS $ev2] ORIGIN_BLOCKS blk_src
file mkdir $DIAG_DIR
puts ">>> 088 READ-ONLY ORIGIN CHECK: nothing is saved. Library $ORIGIN_LIB ($lib_src); blocks $ORIGIN_BLOCKS ($blk_src); output folder $DIAG_DIR"

set lib_msg [diag084_lib_check $ORIGIN_LIB $RUN_ROOT]
if {$lib_msg ne ""} { error $lib_msg }
set open_lib_all [get_libs -quiet *]
if {[sizeof_collection $open_lib_all] > 0} { foreach_in_collection lib_obj $open_lib_all { close_lib -force $lib_obj } }
open_lib -read $ORIGIN_LIB   ;# [L] open_lib usage: -read
set existing {}
if {[catch {foreach_in_collection bo [get_blocks -all -quiet] { lappend existing [get_object_name $bo] }} gerr]} { puts ">>> 088 could not list the blocks ($gerr)" }   ;# VERIFY get_blocks -all
puts ">>> 088 blocks in the library: $existing"

set entries {}
set failed 0
set probed 0
foreach b $ORIGIN_BLOCKS {
    if {![orig088_present $b $existing]} { puts ">>> 088 block $b is not in the library: skipped"; continue }
    incr probed
    catch {close_blocks -force [get_blocks -quiet *]}
    if {[catch {open_block -read ${ORIGIN_LIB}:$b; link_block} oerr]} { incr failed; puts ">>> 088 FAILED: open $b: $oerr"; continue }   ;# [L] open_block -read
    set scens {}
    foreach_in_collection s [get_scenarios] { lappend scens [get_object_name $s] }
    if {[llength $scens] == 0} { incr failed; puts ">>> 088 FAILED: $b has no scenario"; continue }
    foreach s $scens {
        set f ${DIAG_DIR}/origin_[string map {/ _ : _} $b]_${s}.sdc
        file delete -force $f
        if {[catch {write_sdc -scenario $s -output $f} werr]} { incr failed; puts ">>> 088 FAILED: write_sdc $b $s: $werr"; lappend entries [list $b $s -1 {}]; continue }   ;# [L] write_sdc -scenario / -output
        if {![file exists $f]} { incr failed; puts ">>> 088 FAILED: write_sdc $b $s wrote no file"; lappend entries [list $b $s -1 {}]; continue }
        set fp [open $f r]; set tx [read $fp]; close $fp
        set cl [wi086_clock_latency_lines $tx]
        lappend entries [list $b $s [llength $cl] [lmap x $cl {dict get $x value}]]
        foreach x $cl { puts ">>> 088 $b $s: [dict get $x line]" }
    }
}
catch {close_blocks -force [get_blocks -quiet *]}
if {$probed == 0} { error "ERROR 088: none of the blocks $ORIGIN_BLOCKS is in the library $ORIGIN_LIB (blocks that exist: $existing)" }
lassign [wi086_a0_table $entries] lines first
puts "\n=============================================================================="
puts " 088 WHERE DOES set_clock_latency FIRST EXIST? (library $ORIGIN_LIB)"
foreach l $lines { puts "   $l" }
puts "   first block per scenario: $first"
puts "   blocks probed: $probed of [llength $ORIGIN_BLOCKS]; failed writes/opens: $failed (a -1 count means no SDC was written)"
puts "   reading: if the line is first in unpu_top_cts, it is created inside clock_opt (cts.tcl, split into build_clock / route_clock / final_opto, prints the count before each removal);"
puts "            if it is already in unpu_top_placement / unpu_top_portbuf, it comes from an earlier step and cts.tcl's removal at the start of CTS is too late for that step."
puts "   nothing was saved."
puts "=============================================================================="
puts ">>> 088 done. Type exit."
