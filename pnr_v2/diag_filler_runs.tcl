# ==============================================================================
# Script: diag_filler_runs.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/diag_filler_runs.tcl   ;# 070: new script, READ-ONLY diagnostic for antenna_port_buffers.tcl
# Stage : none (nothing is saved, no ECO)
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================
# 070: why. The second server run of antenna_port_buffers.tcl (task 069) found "0 usable candidate sites" for all 15 nets and a "nearest free filler run" of about 300 um
# 070: (the half size of the wide window) for every pin. The pure procs work on the real filler rows (Planning checked), so the input they get inside ICC2 must differ.
# 070: what it does, for ONE net (DIAG_NET below): repeats the pin lookup, the window, the filler query and the run / candidate procs of antenna_port_buffers.tcl
# 070: (the procs are taken from that file's text, not copied), prints every intermediate value, and compares the old geometric query (get_cells -intersect) with
# 070: the table method now used by the ECO (all fillers read once, window selected in Tcl).
# 070: it opens the block `unpu_top_route` and changes nothing; it does not save. Leave icc2_shell with `exit` (no save) afterwards.

set DESIGN_NAME "unpu_top"   ;# 070: as the other scripts
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"
set SCRIPT_DIR  "/storage/EE5239G1/aagams_workspace2/unpu/pnr_v2"   ;# 070: where antenna_port_buffers.tcl is (its procs are read from it)
set STD_LEF     "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"
set FILLER_REFS {feedth feedth3 feedth9}

set DIAG_NET    {pwdata[30]}   ;# 070: the net to examine: a port net name (change this line)
set BUF_CELL    "buffd1"       ;# 070: the buffer master whose size is used (the cell chosen by the first server run)
set LIMIT_UM    40.0           ;# 070: MAX_PIN_BUF_DIST of antenna_port_buffers.tcl
set EXTRA_UM    0.0            ;# 070: widen the window by this much (um) to see more rows

file mkdir $LOG_DIR

# 070: take the pure-Tcl block and the ICC2 helper procs from antenna_port_buffers.tcl (same code, no copy)
set fp [open ${SCRIPT_DIR}/antenna_port_buffers.tcl r]
set dg_src [read $fp]
close $fp
set dg_b [string first "# ---- BEGIN PURE TCL 068 ----" $dg_src]
set dg_e [string first "# ---- END PURE TCL 068 ----" $dg_src]
set dg_h [string first "# 068: ICC2 side helpers" $dg_src]
set dg_f [string first "file mkdir \$LOG_DIR" $dg_src]
if {$dg_b < 0 || $dg_e < 0 || $dg_h < 0 || $dg_f < 0 || $dg_f <= $dg_h} { error "ERROR 070: markers not found in ${SCRIPT_DIR}/antenna_port_buffers.tcl" }
eval [string range $dg_src $dg_b $dg_e]
eval [string range $dg_src $dg_h [expr {$dg_f - 1}]]

redirect -tee -file ${LOG_DIR}/diag_filler_runs.log {

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} { close_blocks -force $open_blk }
    set open_lib [get_libs -quiet *]
    if {[sizeof_collection $open_lib] > 0} { foreach_in_collection lib_obj $open_lib { close_lib -force $lib_obj } }
    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    open_block ${DESIGN_NAME}.dlib:${DESIGN_NAME}_route
    current_block ${DESIGN_NAME}_route
    link_block
    puts ">>> 070 DIAG block ${DESIGN_NAME}_route opened; READ-ONLY: nothing is saved"

    # --- the sizes, from the LEF as in antenna_port_buffers.tcl
    set fp [open $STD_LEF r]
    set dg_lef [ant_parse_lef [read $fp]]
    close $fp
    if {![dict exists $dg_lef $BUF_CELL]} { error "ERROR 070: $BUF_CELL is not in the LEF" }
    set dg_bw [dict get $dg_lef $BUF_CELL w]
    set dg_bh [dict get $dg_lef $BUF_CELL h]
    set dg_site 1e9
    foreach f $FILLER_REFS {
        if {[dict exists $dg_lef $f]} {
            puts ">>> 070 DIAG LEF filler $f: width [dict get $dg_lef $f w] height [dict get $dg_lef $f h]"
            if {[dict get $dg_lef $f w] < $dg_site} { set dg_site [dict get $dg_lef $f w] }
        } else {
            puts ">>> 070 DIAG LEF filler $f: NOT in the LEF"
        }
    }
    if {$dg_site > 1e8} { error "ERROR 070: no filler master in the LEF" }
    puts ">>> 070 DIAG buffer $BUF_CELL: width $dg_bw height $dg_bh; site width $dg_site; needs [expr {ceil($dg_bw / $dg_site - 1e-6) * $dg_site}] um of contiguous filler"

    # --- the pin
    set dg_port [get_ports -quiet -exact $DIAG_NET]
    puts ">>> 070 DIAG port '$DIAG_NET': [sizeof_collection $dg_port] found"
    if {[sizeof_collection $dg_port] != 1} { error "ERROR 070: port $DIAG_NET not found" }
    set dg_term [get_terminals -quiet -of_objects $dg_port]
    puts ">>> 070 DIAG terminals of the port: [sizeof_collection $dg_term]"
    set dg_raw [get_attribute -quiet [index_collection $dg_term 0] bbox]
    puts ">>> 070 DIAG terminal bbox attribute (raw string): '$dg_raw'"
    set dg_xy [ant068_centre [index_collection $dg_term 0]]
    lassign $dg_xy px py
    puts ">>> 070 DIAG pin centre px=$px py=$py (list '$dg_xy', [llength $dg_xy] elements)"

    # --- the window
    set dg_L [expr {$LIMIT_UM + $dg_bw + $dg_bh + $EXTRA_UM}]
    set win [list [list [expr {$px - $dg_L}] [expr {$py - $dg_L}]] [list [expr {$px + $dg_L}] [expr {$py + $dg_L}]]]
    lassign [lindex $win 0] wx0 wy0
    lassign [lindex $win 1] wx1 wy1
    puts ">>> 070 DIAG limit $LIMIT_UM um, L = limit + width + height = $dg_L; window = $win"

    set dg_filter {}
    foreach f $FILLER_REFS { lappend dg_filter "ref_name == $f" }
    set dg_filter [join $dg_filter " || "]
    puts ">>> 070 DIAG filter: $dg_filter"

    # --- A: the geometric queries (the old way: -intersect)
    foreach mode {-intersect -within -touching} {
        if {[catch {set dg_c [get_cells -quiet $mode $win -filter $dg_filter]} err]} {
            puts ">>> 070 DIAG get_cells $mode: error $err"
            continue
        }
        set dg_rows {}
        foreach_in_collection f $dg_c { lappend dg_rows [concat [list [get_object_name $f]] [ant068_bbox_of $f] [list {}]] }
        set dg_ext [ant_rows_extent $dg_rows]
        puts ">>> 070 DIAG get_cells $mode: [llength $dg_rows] fillers, extent $dg_ext"
        # how many of the returned fillers lie within 2 um of the window border? (a query that returns only the border cells shows a high number)
        set nb 0
        foreach r $dg_rows {
            lassign $r nm x0 y0 x1 y1 o
            if {$x0 < $wx0 + 2.0 || $x1 > $wx1 - 2.0 || $y0 < $wy0 + 2.0 || $y1 > $wy1 - 2.0} { incr nb }
        }
        puts ">>> 070 DIAG get_cells $mode: $nb of them within 2 um of the window border"
        set dg_res($mode) $dg_rows
    }

    # --- B: the table method (all fillers, window in Tcl)
    set dg_t0 [clock seconds]
    set dg_all [ant070_all_fillers $dg_filter]
    puts ">>> 070 DIAG table: [llength $dg_all] fillers read in [expr {[clock seconds] - $dg_t0}] s, extent [ant_rows_extent $dg_all]"
    set dg_tw [ant_rows_in_window $dg_all $wx0 $wy0 $wx1 $wy1]
    puts ">>> 070 DIAG table window: [llength $dg_tw] fillers, extent [ant_rows_extent $dg_tw]"
    puts ">>> 070 DIAG first 3 rows of the table window {name x0 y0 x1 y1 orient}: [lrange $dg_tw 0 2]"
    if {[info exists dg_res(-intersect)]} {
        array set dg_in {}
        foreach r $dg_res(-intersect) { set dg_in([lindex $r 0]) 1 }
        set dg_missing {}
        foreach r $dg_tw { if {![info exists dg_in([lindex $r 0])]} { lappend dg_missing [lindex $r 0] } }
        puts ">>> 070 DIAG fillers in the table window that get_cells -intersect did NOT return: [llength $dg_missing] of [llength $dg_tw]; first 5: [lrange $dg_missing 0 4]"
    }

    # --- C: runs and candidates, for both inputs
    foreach {label rows} [list "table window" $dg_tw "get_cells -intersect" [expr {[info exists dg_res(-intersect)] ? $dg_res(-intersect) : {}}]] {
        set runs [ant_filler_runs $rows]
        set cands [ant_site_candidates $runs $dg_bw $dg_site $px $py $LIMIT_UM]
        puts ">>> 070 DIAG ($label): [llength $rows] fillers -> [llength $runs] runs -> [llength $cands] usable candidate sites"
        foreach c [lrange $cands 0 4] { puts ">>> 070 DIAG ($label): candidate $c" }
        foreach ln [ant_run_report $runs $dg_bw $dg_site $px $py $LIMIT_UM 5] { puts ">>> 070 DIAG ($label): nearest run: $ln" }
    }

    puts ">>> 070 DIAG done: READ-ONLY, nothing was saved or changed. Leave icc2_shell with: exit"
}
