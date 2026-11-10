# ==============================================================================
# Script: powerplanning.tcl
# Path  : <RUN_DIR>/pnr_v2/powerplanning.tcl   ;# 063 E1: new path
# Stage : Power Distribution Network (M3/TOP_M Ring, M3+TOP_M Mesh, M1 Rails)
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "unpu_top"   ;# 063 E2: design name
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"   ;# 063 E3b: ICC2 work directory
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/3_powerplanning.log {
    puts ">>> RUN ROOT: $RUN_ROOT"   ;# 082: the log shows which clone wrote it

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }

    open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${DESIGN_NAME}_floorplan
    link_block

    # Automatically detect exact layer names in SCL_4LM.tf
    if {[sizeof_collection [get_layers -quiet TOP_M]] > 0} {
        set M1_LAYER "M1"
        set M3_LAYER "M3"
        set M4_LAYER "TOP_M"
    } elseif {[sizeof_collection [get_layers -quiet M4]] > 0} {
        set M1_LAYER "M1"
        set M3_LAYER "M3"
        set M4_LAYER "M4"
    } else {
        set M1_LAYER "Metal1"
        set M3_LAYER "Metal3"
        set M4_LAYER "Metal4"
    }
    puts ">>> Using PDN Layers: Rail=${M1_LAYER} (H), Ring=${M3_LAYER} (H) & ${M4_LAYER} (V), Mesh=${M3_LAYER} (H) & ${M4_LAYER} (V)"

    # 1. Clean Existing PG Objects & Create Logical Power/Ground Nets
    remove_pg_strategies -all
    remove_pg_patterns -all
    remove_pg_regions -all
    remove_pg_via_master_rules -all
    remove_pg_strategy_via_rules -all

    set_app_options -name plan.pgroute.connect_user_route_shapes -value true

    if {[sizeof_collection [get_nets -quiet VDD]] == 0} {
        create_net -power VDD
    }
    if {[sizeof_collection [get_nets -quiet VSS]] == 0} {
        create_net -ground VSS
    }

    # Connect logical PG pins across hierarchy
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # 2. Peripheral Core Power Ring (M3 Horizontal, TOP_M Vertical)
    create_pg_ring_pattern ring_pattern \
        -horizontal_layer ${M3_LAYER} -horizontal_width 4.0 -horizontal_spacing 2.0 \
        -vertical_layer   ${M4_LAYER} -vertical_width   4.0 -vertical_spacing   2.0

    set_pg_strategy core_ring \
        -core \
        -pattern {{name: ring_pattern} {nets: {VDD VSS}} {offset: {4.0 4.0}}}

    compile_pg -strategies core_ring

    # 3. Core Power Mesh Straps (TOP_M Vertical + M3 Horizontal)
    # Row height = 5.6 um.
    # Pitch = 56.0 um (10 rows) -> Interleaving half-pitch = 28.0 um (5 rows = ODD multiple of 5.6 um)
    # Offset = 11.2 um (2 rows = EVEN multiple of 5.6 um)
    # This guarantees VDD M3 straps land on EVEN rows (VDD rails) and VSS M3 straps land on ODD rows (VSS rails)!
   create_pg_mesh_pattern core_mesh_m3_topm \
    -layers [list \
        [list [list vertical_layer: ${M4_LAYER}]   {width: 2.5} {spacing: interleaving} {pitch: 60.0} {offset: 30.0}] \
        [list [list horizontal_layer: ${M3_LAYER}] {width: 1.5} {spacing: interleaving} {pitch: 56.0} {offset: 11.2}] \
    ]

    set_pg_strategy m3_topm_straps \
        -core \
        -pattern {{name: core_mesh_m3_topm} {nets: {VDD VSS}}} \
        -extension {{stop: outermost_ring}}

    compile_pg -strategies m3_topm_straps

    # 4. Standard Cell Follow-Pin Rails (M1 Horizontal)
    create_pg_std_cell_conn_pattern rail_pattern \
        -layers [list ${M1_LAYER}] \
        -rail_width 0.44

    set_pg_strategy std_rails \
        -core \
        -pattern {{name: rail_pattern} {nets: {VDD VSS}}} \
        -extension {{stop: outermost_ring}}

    compile_pg -strategies std_rails

    # 5. Power Network Verification
    check_pg_drc
    check_pg_connectivity
    check_pg_missing_vias

    # 6. Create VDD/VSS block ports and physical terminals on the top-metal ring
    #    (the synthesized netlist has no PG ports, so write_gds had nothing to label,
    #     and Calibre LVS reported "Power/Ground net missing in layout")
    foreach {pg_net pg_type} {VDD power VSS ground} {
        if {[sizeof_collection [get_ports -quiet $pg_net]] == 0} {
            if {[catch {create_port -direction inout -port_type $pg_type -net $pg_net $pg_net} port_err]} {
                puts "WARNING: create_port failed for $pg_net: $port_err  (check: man create_port)"
            }
        }
        set pg_shapes [get_shapes -quiet -of_objects [get_nets $pg_net] -filter "layer_name==${M4_LAYER}"]
        if {[sizeof_collection $pg_shapes] > 0 && [sizeof_collection [get_ports -quiet $pg_net]] > 0} {
            set pg_bbox [get_attribute [index_collection $pg_shapes 0] bbox]
            if {[catch {create_terminal -port $pg_net -layer ${M4_LAYER} -boundary $pg_bbox} term_err]} {
                puts "WARNING: create_terminal failed for $pg_net: $term_err  (check: man create_terminal)"
            }
        } else {
            puts "WARNING: no ${M4_LAYER} shape or no port found for $pg_net, no terminal created"
        }
    }
    puts ">>> PG ports: [get_object_name [get_ports -quiet {VDD VSS}]]"
    puts ">>> PG terminals: [sizeof_collection [get_terminals -quiet -of_objects [get_ports -quiet {VDD VSS}]]]"

    save_block -as ${DESIGN_NAME}_powerplan
    save_lib
    puts ">>> STAGE 3 COMPLETE: ${DESIGN_NAME}_powerplan saved. Log: ${LOG_DIR}/3_powerplanning.log"

}