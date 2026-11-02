# ==============================================================================
# Script: pv.tcl
# Path  : /storage/EE5239G2/RFID_v2/pnr_icc2/TCL_pnr/pv.tcl
# Stage : Physical Verification, Filler Insertion & Signoff Export
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "baseband_crypto_macro"
set PNR_DIR     "/storage/EE5239G2/RFID_v2/pnr_icc2"
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
    redirect -tee -file ${RPT_DIR}/${DESIGN_NAME}_final_violators.rpt { report_constraints -all_violators }
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
    write_lef \
        -design ${current_block_name} \
        ${OUT_DIR}/${DESIGN_NAME}.lef

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

    # 5. Save Final Checkpoint
    save_block -as ${DESIGN_NAME}_pv
    save_lib
    puts ">>> STAGE 7 COMPLETE: All deliverables exported to ${OUT_DIR}. Reports in ${RPT_DIR}. Log: ${LOG_DIR}/7_pv.log"

}