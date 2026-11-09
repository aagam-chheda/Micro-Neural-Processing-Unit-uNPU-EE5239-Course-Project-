# ==============================================================================
# Script: pv.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/pv.tcl   ;# 063 E1: new path
# Stage : Physical Verification, Filler Insertion & Signoff Export
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "unpu_top"   ;# 063 E2: design name
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"   ;# 063 E3b: ICC2 work directory
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set OUT_DIR     "${PNR_DIR}/outputs"
set LOG_DIR     "${PNR_DIR}/logs"
set RPT_DIR     "${PNR_DIR}/reports"
set PDK_DIR     "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/digital_pnr_kit/snps/non_rh/4M1L"

# Name of the physical-only filler library (as reported by get_libs)
set FILLER_LIB  "scl180_filler"

# GDS Merge Paths
set STDCELL_GDS "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/gds/scl18fs120.gds"
set IOPAD_GDS   "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/iopad/cio250/4M1L/gds/tsl18cio250_4lm.gds"
set GDS_MERGE_LIST [list $STDCELL_GDS $IOPAD_GDS]

set PV_POWER_PORTS {VDD VSS}   ;# 073: names of the power ports of the macro (expected LEF pins = signal ports + these)
set PV_LEF_TOL      0.001      ;# 073: um, tolerance of the LEF SIZE against the die box

# ---- BEGIN PURE TCL 073 ----
# 073: plain Tcl (no ICC2 command) for the LEF export check; pnr_v2/test_pv_lef_check.tcl extracts and tests exactly this text.

# 073: the MACRO entries of a LEF text as a list of {line_index name}. A MACRO entry is a line that STARTS at column 0 with "MACRO <name>" and has nothing else but optional trailing
# 073: spaces. Lines between PROPERTYDEFINITIONS and END PROPERTYDEFINITIONS are ignored: the header of the real file holds the indented property definition "  MACRO expanded_util REAL ;"
# 073: (first server run of this check, task 073 fix). This one proc decides what a MACRO line is for the check, the block extraction and the rename.
proc pv_lef_macro_lines {text} {
    set out {}
    set inprop 0
    set i 0
    foreach l [split $text "\n"] {
        if {[regexp {^\s*PROPERTYDEFINITIONS\s*$} $l]} {
            set inprop 1
        } elseif {$inprop && [regexp {^\s*END\s+PROPERTYDEFINITIONS\s*$} $l]} {
            set inprop 0
        } elseif {!$inprop && [regexp {^MACRO\s+(\S+)\s*$} $l -> m]} {
            lappend out [list $i $m]
        }
        incr i
    }
    return $out
}

# 073: names of all MACRO entries of a LEF text, in order
proc pv_lef_macros {text} {
    return [lmap e [pv_lef_macro_lines $text] {lindex $e 1}]
}

# 073: number of lines "END <name>" for a macro name
proc pv_lef_end_count {text name} {
    set n 0
    foreach l [split $text "\n"] { if {[regexp {^\s*END\s+(\S+)\s*$} $l -> m] && $m eq $name} { incr n } }
    return $n
}

# 073: text of one macro (from its MACRO line to its END line), "" when absent
proc pv_lef_block {text name} {
    set lines [split $text "\n"]
    set start -1
    foreach e [pv_lef_macro_lines $text] { if {[lindex $e 1] eq $name} { set start [lindex $e 0]; break } }
    if {$start < 0} { return "" }
    set out {}
    for {set i $start} {$i < [llength $lines]} {incr i} {
        set l [lindex $lines $i]
        lappend out $l
        if {$i > $start && [regexp {^\s*END\s+(\S+)\s*$} $l -> m] && $m eq $name} { break }
    }
    return [join $out "\n"]
}

# 073: rename a macro: the one "MACRO old" line (counted as pv_lef_macro_lines does) and the one "END old" line. Returns {newtext changed_lines}; refuses (error) unless exactly one of each exists.
proc pv_lef_rename {text old new} {
    set lines [split $text "\n"]
    set mlines {}
    foreach e [pv_lef_macro_lines $text] { if {[lindex $e 1] eq $old} { lappend mlines [lindex $e 0] } }
    set nm [llength $mlines]
    set ne 0
    set out {}
    set i 0
    foreach l $lines {
        if {[lsearch -exact $mlines $i] >= 0} {
            regexp {^MACRO(\s+)(\S+)(\s*)$} $l -> b m c
            set l "MACRO${b}${new}${c}"
        } elseif {[regexp {^(\s*)END(\s+)(\S+)(\s*)$} $l -> a b m c] && $m eq $old} {
            set l "${a}END${b}${new}${c}"
            incr ne
        }
        lappend out $l
        incr i
    }
    if {$nm != 1 || $ne != 1} { error "pv_lef_rename: expected one 'MACRO $old' and one 'END $old' line, found $nm and $ne" }
    return [list [join $out "\n"] [expr {$nm + $ne}]]
}

# 073: check a LEF text against the design. Returns the list of problems (empty = the LEF is accepted); every problem is a full sentence.
# 073: name = the macro name expected; pins = expected number of PIN entries (signal + power ports); w, h = die box (um); tol in um.
proc pv_lef_check {text name pins w h {tol 0.001}} {
    set problems {}
    set macros [pv_lef_macros $text]
    set nm [llength [lsearch -all -exact $macros $name]]
    if {[llength $macros] == 0} {
        lappend problems "the LEF holds no MACRO at all"
    } else {
        if {$nm != 1} { lappend problems "the LEF holds $nm 'MACRO $name' entries, 1 expected ([llength $macros] MACRO entries in total, first '[lindex $macros 0]', last '[lindex $macros end]')" }
        if {$nm == 1 && [llength $macros] != 1} { lappend problems "the LEF holds [llength $macros] MACRO entries, 1 expected (extra: [lrange [lsearch -all -inline -not -exact $macros $name] 0 4])" }
    }
    set ne [pv_lef_end_count $text $name]
    if {$ne != 1} { lappend problems "the LEF holds $ne 'END $name' lines, 1 expected" }
    if {$nm >= 1} {
        set blk [pv_lef_block $text $name]
        set np 0
        foreach l [split $blk "\n"] { if {[regexp {^\s*PIN\s+\S+} $l]} { incr np } }
        if {$np != $pins} { lappend problems "macro $name has $np PIN entries, $pins expected (signal ports plus power ports)" }
        if {[regexp {SIZE\s+([0-9.eE+-]+)\s+BY\s+([0-9.eE+-]+)} $blk -> sw sh]} {
            if {abs($sw - $w) > $tol || abs($sh - $h) > $tol} { lappend problems "macro $name SIZE is $sw x $sh um, the die box is [format %.3f $w] x [format %.3f $h] um (tolerance $tol)" }
        } else {
            lappend problems "macro $name has no SIZE line"
        }
    }
    return $problems
}
# ---- END PURE TCL 073 ----

# ---- BEGIN PURE TCL 076 ----
# 076: SDF version check (plain Tcl). The first server run of the post-layout simulation showed that write_sdf of this ICC2 writes the header (SDFVERSION "OVI 2.1") but REMOVAL / RECOVERY entries,
# 076: which exist only in SDF 3.0: Xcelium stops with SDFIRE ("REMOVAL keyword is only allowed in SDFVERSION of 3.0 or later") and SDFCNC (SDF skipped, a zero-delay run).
# 076: the version strings of all (SDFVERSION "...") lines of a text, in order
proc pv_sdf_versions {text} {
    set out {}
    foreach l [split $text "\n"] { if {[regexp {\(\s*SDFVERSION\s+"([^"]*)"\s*\)} $l -> v]} { lappend out $v } }
    return $out
}

# 076: "" when the header has exactly one SDFVERSION line and it is "3.0"; otherwise a sentence
proc pv_sdf_version_problem {text} {
    set v [pv_sdf_versions $text]
    if {[llength $v] == 0} { return "no (SDFVERSION \"...\") line in the header" }
    if {[llength $v] > 1} { return "[llength $v] SDFVERSION lines in the header ($v), 1 expected" }
    if {[lindex $v 0] ne "3.0"} { return "SDFVERSION is \"[lindex $v 0]\", 3.0 required" }
    return ""
}
# ---- END PURE TCL 076 ----

file mkdir $OUT_DIR
file mkdir $LOG_DIR
file mkdir $RPT_DIR

redirect -tee -file ${LOG_DIR}/7_pv.log {

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} { 
        close_blocks -force $open_blk 
    }

    # Safely close any open libraries without collection mismatch
    set open_lib [get_libs -quiet *]
    if {[sizeof_collection $open_lib] > 0} { 
        foreach_in_collection lib_obj $open_lib {
            close_lib -force $lib_obj
        }
    }

    # Open the design library
    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    
    # Open the final filled block containing the metal fill
    set blk_name "${DESIGN_NAME}_filled"
    if {[catch {open_block ${DESIGN_NAME}.dlib:${blk_name}} open_err]} {
        puts "WARNING: could not open ${blk_name}: $open_err"
        puts "Blocks available in library ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:"
        list_blocks
        error "ERROR: No block named ${blk_name} found in ${BLOCKS_DIR}/${DESIGN_NAME}.dlib! Check the block name saved by metal_fill.tcl."
    }
    current_block ${blk_name}
    link_block

    # 1. Standard Cell Fillers & route_eco DRC clearance already completed in route.tcl
    # Re-connect PG net sanity check before final signoff verification
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # 2. Final Signoff Checks & Congestion in ICC2
    route_global -congestion_map_only true
    redirect -tee -file ${RPT_DIR}/congestion.rpt {
        report_congestion -rerun_global_router
    }

    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_update_timing.rpt {
        update_timing -full
    }

    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_check_legality.rpt {
        check_legality
    }

    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_check_routes.rpt {
        check_routes
    }

    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_check_pg_drc.rpt {
        check_pg_drc
    }

    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_check_pg_connectivity.rpt {
        check_pg_connectivity
    }

    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_check_pg_missing_vias.rpt {
        check_pg_missing_vias
    }

    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_check_lvs.rpt {
        check_lvs -max_error 0
    }

    # Generate Final Signoff Reports
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_qor.rpt { report_qor }
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_global_timing.rpt { report_global_timing }
    # 073: report_constraints -all_violators also does hold analysis; with func_ss current ("setup only") it printed UIC-057 (handoff 18.32). The two scenarios are named, so
    # 073: setup is reported for func_ss and hold for func_ff (active for hold). VERIFY: -scenarios on report_constraints, and that this is the command that printed UIC-057 (the pv log was not
    # 073: available to identify it; the fallback keeps the old report but run in func_ff, where both analyses are active).
    if {[catch {redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_violators.rpt { report_constraints -all_violators -scenarios {func_ss func_ff} }} pv_rc_err]} {   ;# 073
        puts ">>> 073 report_constraints -scenarios failed ($pv_rc_err): the report is run in func_ff instead"
        current_scenario func_ff   ;# 073
        redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_violators.rpt { report_constraints -all_violators }   ;# 073
        current_scenario func_ss   ;# 073
    }
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_power.rpt { report_power }
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_clock_qor.rpt { report_clock_qor }
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_utilization.rpt { report_utilization }

    current_scenario func_ff
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_hold_ff.rpt {
        report_timing -path_type full_clock_expanded -delay_type min -max_paths 50
    }

    current_scenario func_ss
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_setup_ss.rpt {
        report_timing -path_type full_clock_expanded -delay_type max -max_paths 50
    }

    # 3. Export Physical Deliverables (LEF, GDS, DEF, Parasitics, LVS Netlist)
    set current_block_name [get_object_name [current_block]]
    # 073: LEF of the MACRO (the block abstract), not of the library cells. The old command (write_lef -design <block> without -include cell and without a frame view) wrote 122 library MACROs
    # 073: and no unpu_top (handoff 18.32). What worked in the old flow (handoff 18.25): create_frame -block_all true (everything blocked except the pins), then write_lef -design <block> -include cell.
    # 073: the name of the macro: the block name (unpu_top_filled) is not the cell name; in the old flow the macro was called unpu_top (the design name). If the file still holds one macro with another
    # 073: name, that one MACRO line and its END line are renamed to ${DESIGN_NAME} in Tcl (error unless exactly one of each), and everything is checked again below.
    set pv_lef ${OUT_DIR}/${DESIGN_NAME}.lef   ;# 073
    file delete -force $pv_lef   ;# 073: a stale file must not pass the check
    create_frame -block_all true   ;# 073: VERIFY create_frame -block_all true (usage text; used in the old flow); it adds a frame view to the open block, saved with save_lib below
    write_lef -design ${current_block_name} -include cell $pv_lef   ;# 073: VERIFY -include cell (usage text: values cell, tech); the technology LEF is the kit's scl18fs120_tech.lef, not repeated here

    # 073: the LEF checks. A failure is recorded here, the other exports below still run, and the script ends with an error before it saves or says COMPLETE.
    set pv_lef_problems {}   ;# 073
    if {![file exists $pv_lef] || [file size $pv_lef] == 0} {   ;# 073
        lappend pv_lef_problems "the LEF file $pv_lef does not exist or is empty"   ;# 073
        set pv_lef_txt ""   ;# 073
    } else {   ;# 073
        set fp [open $pv_lef r]   ;# 073
        set pv_lef_txt [read $fp]   ;# 073
        close $fp   ;# 073
    }   ;# 073
    set pv_macros [pv_lef_macros $pv_lef_txt]   ;# 073
    puts ">>> 073 LEF $pv_lef: [file size $pv_lef] bytes, [llength $pv_macros] MACRO entries: [lrange $pv_macros 0 4]"   ;# 073
    if {[llength $pv_macros] == 1 && [lindex $pv_macros 0] ne $DESIGN_NAME} {   ;# 073
        set pv_old [lindex $pv_macros 0]   ;# 073
        if {[catch {lassign [pv_lef_rename $pv_lef_txt $pv_old $DESIGN_NAME] pv_lef_txt pv_nchg} pv_ren_err]} {   ;# 073
            lappend pv_lef_problems "cannot rename macro $pv_old to $DESIGN_NAME: $pv_ren_err"   ;# 073
        } else {   ;# 073
            set fp [open $pv_lef w]   ;# 073
            puts -nonewline $fp $pv_lef_txt   ;# 073
            close $fp   ;# 073
            puts ">>> 073 LEF macro renamed $pv_old -> $DESIGN_NAME ($pv_nchg lines changed: the MACRO line and the END line)"   ;# 073
        }   ;# 073
    } elseif {[llength $pv_macros] == 1} {   ;# 073
        puts ">>> 073 LEF macro is already called $DESIGN_NAME, no rename"   ;# 073
    }   ;# 073
    set pv_nsig 0   ;# 073
    set pv_npwr 0   ;# 073
    foreach_in_collection pv_p [get_ports -quiet *] {   ;# 073
        if {[lsearch -exact $PV_POWER_PORTS [get_object_name $pv_p]] >= 0} { incr pv_npwr } else { incr pv_nsig }   ;# 073
    }   ;# 073
    puts ">>> 073 ports of the design: $pv_nsig signal + $pv_npwr power = [expr {$pv_nsig + $pv_npwr}] (204 + 2 expected)"   ;# 073
    set pv_bb [get_attribute -quiet [current_block] boundary_bbox]   ;# 073: VERIFY the block attribute boundary_bbox (used in pin_replace.tcl)
    set pv_nums [regexp -all -inline -- {-?[0-9]+(?:\.[0-9]+)?} $pv_bb]   ;# 073
    if {[llength $pv_nums] == 4} {   ;# 073
        lassign $pv_nums pv_x0 pv_y0 pv_x1 pv_y1   ;# 073
        set pv_dw [expr {$pv_x1 - $pv_x0}]   ;# 073
        set pv_dh [expr {$pv_y1 - $pv_y0}]   ;# 073
        puts ">>> 073 die box $pv_bb: [format %.3f $pv_dw] x [format %.3f $pv_dh] um (885.6 x 885.6 expected)"   ;# 073
        set pv_lef_problems [concat $pv_lef_problems [pv_lef_check $pv_lef_txt $DESIGN_NAME [expr {$pv_nsig + $pv_npwr}] $pv_dw $pv_dh $PV_LEF_TOL]]   ;# 073
    } else {   ;# 073
        lappend pv_lef_problems "the die box could not be read (boundary_bbox '$pv_bb')"   ;# 073
    }   ;# 073
    if {[llength $pv_lef_problems] == 0} {   ;# 073
        puts ">>> 073 LEF CHECK PASSED: one MACRO $DESIGN_NAME with [expr {$pv_nsig + $pv_npwr}] PIN entries, SIZE equal to the die box"   ;# 073
    } else {   ;# 073
        foreach pv_pr $pv_lef_problems { puts ">>> 073 LEF CHECK FAILED: $pv_pr" }   ;# 073
    }   ;# 073

     write_gds \
        -layer_map ${PDK_DIR}/icc_gds_out_4LM.map \
        -merge_files $GDS_MERGE_LIST \
        -units 1000 \
        -fill include \
        -output_pin all \
        -hierarchy all \
        -long_names \
        -keep_data_type \
        -instance_property 1 \
        -net_property 2 \
        -pin_property 3 \
        ${OUT_DIR}/${DESIGN_NAME}_routed.gds

    write_def \
        -version 5.8 \
        -include_tech_via_definitions \
        ${OUT_DIR}/${DESIGN_NAME}.def

    write_parasitics \
        -format spef \
        -output ${OUT_DIR}/${DESIGN_NAME}_spef

    write_verilog \
        -exclude {scalar_wire_declarations leaf_module_declarations empty_modules filler_cells well_tap_cells end_cap_cells corner_cells pad_spacer_cells physical_only_cells unconnected_ports supply_statements} \
        ${OUT_DIR}/${DESIGN_NAME}_pnr_pg.v

    # 4. Export Gate-Level Simulation (GLS) Deliverables
    write_verilog \
        -exclude {pg_netlist physical_only_cells leaf_module_declarations} \
        ${OUT_DIR}/${DESIGN_NAME}_pnr_sim.v

     # Rename uppercase internal nets N<digits> to N_uc_<digits> so case-insensitive LVS never shorts N33 with n33
    exec sed -i -E {s/\bN([0-9]+)\b/N_uc_\1/g} ${OUT_DIR}/${DESIGN_NAME}_pnr_pg.v
    

    current_scenario func_ss
    write_sdc \
        -scenario func_ss \
        -output ${OUT_DIR}/${DESIGN_NAME}_pnr_ss.sdc

    write_sdf \
        -corner corner_ss \
        -mode mode_func \
        ${OUT_DIR}/${DESIGN_NAME}_ss.sdf

    current_scenario func_ff
    write_sdc \
        -scenario func_ff \
        -output ${OUT_DIR}/${DESIGN_NAME}_pnr_ff.sdc
    write_sdf \
        -corner corner_ff \
        -mode mode_func \
        ${OUT_DIR}/${DESIGN_NAME}_ff.sdf

    # 076: the SDF version. write_sdf of this ICC2 has NO -version option (usage text in ~/server_pull/rpt/help/write_sdf.txt: -include, -significant_digits, -compress, -corner, -mode), and it wrote the header
    # 076: (SDFVERSION "OVI 2.1") over REMOVAL / RECOVERY entries, which belong to SDF 3.0 (Xcelium: SDFIRE, SDFCNC). The header line is therefore rewritten to 3.0 in the first lines of each file
    # 076: (3.0 is a superset of 2.1, the entries are not touched), and the result is CHECKED: exactly one SDFVERSION line and it is 3.0, else the run ends with ERROR 076 below. The layout, the GDS and the
    # 076: delays are unchanged, so the Calibre results stay valid.
    set pv_sdf_problems {}   ;# 076
    foreach pv_c {ss ff} {   ;# 076
        set pv_sdf ${OUT_DIR}/${DESIGN_NAME}_${pv_c}.sdf   ;# 076
        if {![file exists $pv_sdf] || [file size $pv_sdf] == 0} { lappend pv_sdf_problems "the SDF $pv_sdf does not exist or is empty"; continue }   ;# 076
        if {[catch {exec head -n 60 $pv_sdf} pv_head]} { lappend pv_sdf_problems "cannot read the header of $pv_sdf: $pv_head"; continue }   ;# 076
        set pv_ver0 [pv_sdf_versions $pv_head]   ;# 076
        if {[catch {exec grep -c -E {\((REMOVAL|RECOVERY|RECREM|SETUPHOLD)[ )]} $pv_sdf} pv_n3]} { set pv_n3 0 }   ;# 076: grep -c exits 1 when the count is 0
        puts ">>> 076 SDF $pv_sdf: SDFVERSION lines $pv_ver0; entries that exist only in SDF 3.0 (REMOVAL, RECOVERY, RECREM, SETUPHOLD): $pv_n3"   ;# 076
        if {[pv_sdf_version_problem $pv_head] ne ""} {   ;# 076
            if {[llength $pv_ver0] == 0} { lappend pv_sdf_problems "$pv_sdf: [pv_sdf_version_problem $pv_head] (nothing to rewrite)"; continue }   ;# 076
            if {[catch {exec sed -i {1,60s/(SDFVERSION "[^"]*")/(SDFVERSION "3.0")/} $pv_sdf} pv_sed_err]} {   ;# 076: only the header lines are edited
                lappend pv_sdf_problems "cannot rewrite the SDFVERSION of $pv_sdf: $pv_sed_err"; continue   ;# 076
            }   ;# 076
            puts ">>> 076 SDF $pv_sdf: SDFVERSION rewritten $pv_ver0 -> 3.0 (write_sdf has no -version option)"   ;# 076
        }   ;# 076
        catch {exec head -n 60 $pv_sdf} pv_head2   ;# 076
        set pv_prob [pv_sdf_version_problem $pv_head2]   ;# 076
        if {$pv_prob ne ""} { lappend pv_sdf_problems "$pv_sdf: $pv_prob" } else { puts ">>> 076 SDF CHECK PASSED: $pv_sdf has exactly one SDFVERSION line and it is 3.0" }   ;# 076
    }   ;# 076
    foreach pv_pr $pv_sdf_problems { puts ">>> 076 SDF CHECK FAILED: $pv_pr" }   ;# 076

    # 073: a failed LEF check makes the whole run fail (the other exports above are written, but nothing is saved and no COMPLETE line is printed)
    if {[llength $pv_lef_problems] > 0} {   ;# 073
        error "ERROR 073: the LEF export failed its checks, NOTHING SAVED, the run is NOT complete: [join $pv_lef_problems {; }]"   ;# 073
    }   ;# 073

    if {[llength $pv_sdf_problems] > 0} {   ;# 076
        error "ERROR 076: the SDF export failed its checks, NOTHING SAVED, the run is NOT complete: [join $pv_sdf_problems {; }]"   ;# 076
    }   ;# 076

    # 5. Save Final Checkpoint
    save_block -as ${DESIGN_NAME}_pv
    save_lib
    puts ">>> STAGE 7 COMPLETE: All deliverables exported to ${OUT_DIR}. Reports in ${RPT_DIR}. Log: ${LOG_DIR}/7_pv.log"

}