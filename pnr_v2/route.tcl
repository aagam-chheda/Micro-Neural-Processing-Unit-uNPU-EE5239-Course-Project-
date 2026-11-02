# ==============================================================================
# Script: route.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/route.tcl   ;# 063 E1: new path
# Stage : Global/Detail Routing, Redundant Vias & Post-Route Optimization
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "unpu_top"   ;# 063 E2: design name
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"   ;# 063 E3b: ICC2 work directory
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

# Name of the physical-only filler library (as reported by get_libs)
set FILLER_LIB  "scl180_filler"

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/6_route.log {

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }

    # Clean previous route block to run completely from square one
    if {[file exists ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${DESIGN_NAME}_route]} {
        remove_blocks ${DESIGN_NAME}.dlib:${DESIGN_NAME}_route
    }

    open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${DESIGN_NAME}_cts
    link_block

    # Save as _route immediately from clean CTS checkpoint
    save_block -as ${DESIGN_NAME}_route

    suppress_message {DCHK-027 DCHK-010 ATTR-12 PDC-003 ZRT-740 ZRT-027 POW-046 UIC-058 UIC-057}

    # 1. Pre-Route Checks
    check_design -checks pre_route_stage
    check_routability

   # 2. Restrict Routing to SCL 180nm 4-Metal Stack (M1 to TOP_M)
    set_ignored_layers \
        -min_routing_layer M1 \
        -max_routing_layer TOP_M

    # Allow clock nets (from CTS) to hop up to TOP_M to fix M3 antenna violations
    set_clock_routing_rules \
        -default_rule \
        -min_routing_layer M2 \
        -max_routing_layer TOP_M

    # Ensure Hold cells remain enabled for Post-Route Hold Optimization
    set hold_cells [get_lib_cells -quiet {scl180_std/*BUF* scl180_std/*INV* scl180_std/*DEL* scl180_std/*DLY* scl180_std/*buf* scl180_std/*inv* scl180_std/*del* scl180_std/*dly*}]
    if {[sizeof_collection $hold_cells] > 0} {
        set_lib_cell_purpose -include hold $hold_cells
    }

    set SPEC_SETUP_UNC   1.5   ;# 063 E9: old constraints, setup uncertainty 1.5 (the example had 0.15)
    set SETUP_SLACK_GOAL 0.0   ;# 065: user decision 2026-11-02, no extra margin on top of the course uncertainties (the example had 0.30)
    set OPT_SETUP_UNC    [expr {$SPEC_SETUP_UNC + $SETUP_SLACK_GOAL}]

    set_scenario_status func_ss -active true -setup true -hold false
    current_scenario func_ss
    set_clock_uncertainty -setup $OPT_SETUP_UNC [get_clocks -filter "is_virtual == false"]
    puts ">>> Setup uncertainty during optimization: $OPT_SETUP_UNC ns (spec $SPEC_SETUP_UNC ns)"

    # Same hold margin as CTS: spec 0.5 + 0.70 goal   ;# 063 E9: comment follows the new spec value   ;# 065: the goal is 0.0 now
    set SPEC_HOLD_UNC    0.5   ;# 063 E9: old constraints, hold uncertainty 0.5 (the example had 0.05)
    set HOLD_SLACK_GOAL  0.0   ;# 065: user decision 2026-11-02, no extra margin on top of the course uncertainties (the example had 0.70)
    set OPT_HOLD_UNC     [expr {$SPEC_HOLD_UNC + $HOLD_SLACK_GOAL}]

    set_scenario_status func_ff -active true -hold true -setup true
    current_scenario func_ff
    set_clock_uncertainty -hold $OPT_HOLD_UNC [get_clocks -filter "is_virtual == false"]

    # 3. Configure Routing, SI Crosstalk & Antenna App Options
    set_app_options -name route.global.timing_driven -value true
    set_app_options -name route.track.timing_driven -value true
    set_app_options -name route.detail.timing_driven -value true
    set_app_options -name route.global.crosstalk_driven -value true
    set_app_options -name route.track.crosstalk_driven -value true
    set_app_options -name time.si_enable_analysis -value true

   # ==========================================================================
    # SCL 180nm (4M1L) Fast Layer-Hopping Antenna Rules
    # - Keeps M1 & M2 -diode_ratio at 180/75 (already 0 errors, fast runtime)
    # - Tightens -ratio (input port nets only) to 25/12 to clear the 6 MT errors
    # - Tightens M3 -diode_ratio to 100/45 to clear the 14 M3 errors
    # ==========================================================================
    remove_antenna_rules

    # 1. Mode 4: Sidewall Area Rules for Metal Layers
    define_antenna_rule -mode 4 -diode_mode 4 \
        -metal_ratio 25 -cut_ratio 0
    define_antenna_layer_rule -layer M1    -mode 4 \
        -ratio 25  -diode_ratio {0 0 0 180}
    define_antenna_layer_rule -layer M2    -mode 4 \
        -ratio 25  -diode_ratio {0 0 0 180}
    define_antenna_layer_rule -layer M3    -mode 4 \
        -ratio 25  -diode_ratio {0 0 0 100}
    define_antenna_layer_rule -layer TOP_M -mode 4 \
        -ratio 25  -diode_ratio {0 0 8000 30000}

    # 2. Mode 1: Polygon Area Rules for Via Cut & Metal Layers
    define_antenna_rule -mode 1 -diode_mode 4 \
        -metal_ratio 12 -cut_ratio 20
    define_antenna_layer_rule -layer M1    -mode 1 \
        -ratio 12  -diode_ratio {0 0 0 75}
    define_antenna_layer_rule -layer M2    -mode 1 \
        -ratio 12  -diode_ratio {0 0 0 75}
    define_antenna_layer_rule -layer M3    -mode 1 \
        -ratio 12  -diode_ratio {0 0 0 45}
    define_antenna_layer_rule -layer TOP_M -mode 1 \
        -ratio 12  -diode_ratio {0 0 2000 7500}

    foreach via_lyr [get_object_name [get_layers -quiet -filter "layer_type == interconnect_via"]] {
        define_antenna_layer_rule -layer $via_lyr -mode 1 \
            -ratio 20 -diode_ratio {0 0 83.33 75}
    }

    report_antenna_rules
    
    # Pure layer-hopping antenna options (fast runtime, no diodes)
    set_app_options -name route.detail.antenna -value true
    set_app_options -name route.detail.hop_layers_to_fix_antenna -value true
    set_app_options -name route.detail.antenna_fixing_preference -value hop_layers
    set_app_options -name route.detail.insert_diodes_during_routing -value false
    #set_app_options -name route.detail.diode_libcell_names -value {scl180_std/adiode}

    set_app_options -name route_opt.flow.enable_power -value false
    set_app_options -name route_opt.flow.enable_ccd -value false
    

     # 4. Execute Global, Track, and Detail Routing
    route_global -effort_level ultra
    route_auto
    # 5. Insert Redundant Vias for DFM Yield Enhancement
    add_redundant_vias

    # 6. Post-Route Timing, Crosstalk & DRC Closure
    route_opt
    legalize_placement

    puts "diodes inserted: [sizeof_collection [get_cells -quiet -filter {ref_name == adiode}]]"

    current_scenario func_ss
    set_clock_uncertainty -setup $SPEC_SETUP_UNC [get_clocks -filter "is_virtual == false"]

  # Restore the real hold uncertainty so reports and exported SDC are correct
    current_scenario func_ff
    set_clock_uncertainty -hold $SPEC_HOLD_UNC [get_clocks -filter "is_virtual == false"]

    # Sanity check: confirm reference libraries and filler cells are visible
    puts "Reference libraries: [get_object_name [get_libs -quiet *]]"
    puts "feedth cells visible: [get_object_name [get_lib_cells -quiet */feedth*]]"

    # Insert Standard Cell Fillers (Pulling from scl180_filler.ndm via reference libraries)
    set fill_cells [get_lib_cells -quiet [list ${FILLER_LIB}/feedth9 ${FILLER_LIB}/feedth3 ${FILLER_LIB}/feedth]]
    if {[sizeof_collection $fill_cells] == 0} {
        set fill_cells [get_lib_cells -quiet {*/feedth9 */feedth3 */feedth}]
    }
    if {[sizeof_collection $fill_cells] > 0} { 
        create_stdcell_fillers -lib_cells $fill_cells
        connect_pg_net -automatic
        connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
        connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]
    } else {
        puts "ERROR: feedth filler cells not found in reference libraries!"
    }

    # 7. Connect PG Nets for Any Post-Route ECO & Filler Cells
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # Fix filler-induced DRCs and close any open nets without ripping up clean global routes
    route_detail -incremental true -max_number_iterations 100
    route_eco \
        -reuse_existing_global_route true \
        -utilize_dangling_wires true \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 200
    # Final pass specifically ensuring 0 open nets remain
    route_eco \
        -open_net_driven true \
        -reuse_existing_global_route true \
        -utilize_dangling_wires true \
        -reroute modified_nets_first_then_others \
        -max_detail_route_iterations 200
    route_detail -incremental true -max_number_iterations 100
    check_routes

    # 8. Post-Route Verification & Timing Reports
    update_timing -full
    check_legality
    check_routes
    check_pg_drc
    check_pg_connectivity
    check_lvs

    report_qor
    report_global_timing
    report_power

    current_scenario func_ff
    report_timing -scenarios func_ff -path_type full_clock_expanded -delay_type min -max_paths 20 -significant_digits 4

    current_scenario func_ss
    report_timing -scenarios func_ss -path_type full_clock_expanded -delay_type max -max_paths 20 -significant_digits 4

    save_block -as ${DESIGN_NAME}_route
    save_lib
    puts ">>> STAGE 6 COMPLETE: ${DESIGN_NAME}_route saved successfully. Log: ${LOG_DIR}/6_route.log"

}