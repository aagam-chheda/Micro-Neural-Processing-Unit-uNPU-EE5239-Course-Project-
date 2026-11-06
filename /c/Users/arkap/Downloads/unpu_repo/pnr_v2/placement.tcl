# ==============================================================================
# Script: placement.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/placement.tcl   ;# 063 E1: new path
# Stage : Standard Cell Placement, HFNS & Timing Optimization
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "unpu_top"   ;# 063 E2: design name
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"   ;# 063 E3b: ICC2 work directory
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/4_placement.log {

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }

    open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${DESIGN_NAME}_powerplan
    link_block

    suppress_message {DCHK-027 DCHK-010 ATTR-12}

    # 1. Pre-Placement Checks
    check_design -checks pre_placement_stage
    check_pg_connectivity

    # 2. Restrict Routing Layers for RC Estimation (M1 to TOP_M)
    set_ignored_layers \
        -min_routing_layer M1 \
        -max_routing_layer TOP_M

    # 3. Placement Application Options
    set_app_options -name place_opt.flow.do_path_opt -value true
    set_app_options -name place_opt.flow.clock_aware_placement -value true
    set_app_options -name place_opt.flow.trial_clock_tree -value true
    set_app_options -name place_opt.initial_drc.global_route_based -value true
    set_app_options -name place_opt.place.congestion_effort -value high
    set_app_options -name place.coarse.continue_on_missing_scandef -value true

    # 4. Execute Placement and Optimization
    place_opt

    # Ensure strict cell legality on standard cell rows
    legalize_placement

    # 5. Connect PG Nets to Newly Added Buffers
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # 6. Post-Placement Verification & QoR Reporting
    check_legality
    check_pg_drc
    check_pg_connectivity
    report_placement
    report_congestion
    report_utilization
    report_qor
    report_global_timing

    save_block -as ${DESIGN_NAME}_placement
    save_lib
    puts ">>> STAGE 4 COMPLETE: ${DESIGN_NAME}_placement saved. Log: ${LOG_DIR}/4_placement.log"

}