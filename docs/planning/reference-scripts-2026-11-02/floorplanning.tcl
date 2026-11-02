# ==============================================================================
# Script: floorplanning.tcl
# Path  : /storage/EE5239G2/RFID_v2/pnr_icc2/TCL_pnr/floorplanning.tcl
# Stage : Floorplan Initialization, Tap Cells & Circular Sequenced Pin Placement
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "baseband_crypto_macro"
set PNR_DIR     "/storage/EE5239G2/RFID_v2/pnr_icc2"
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/2_floorplanning.log {

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }

    open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${DESIGN_NAME}_setup
    link_block

    # 1. Pre-Floorplan Check (Suppress benign synthesis feedthrough port warnings)
    suppress_message {DCHK-027 DCHK-010 ATTR-12}
    check_netlist

    # 2. Restrict Routing Layers to SCL 180nm 4M1L Stack (M1 to TOP_M)
    set_ignored_layers \
        -min_routing_layer M1 \
        -max_routing_layer TOP_M

    # Explicitly ensure preferred routing directions match LEF
    set_attribute [get_layers M1]    routing_direction horizontal
    set_attribute [get_layers M2]    routing_direction vertical
    set_attribute [get_layers M3]    routing_direction horizontal
    set_attribute [get_layers TOP_M] routing_direction vertical

    # 3. Initialize Rectangular Floorplan (500x500 um die, 20 um core offset, 55% core utilization)
    initialize_floorplan \
        -control_type die \
        -boundary {{0 0} {530 530}} \
        -core_offset {20 20 20 20} \
        -core_utilization 0.85

    # 4. Configure Circular Sequenced Pin Placement Constraints
    remove_block_pin_constraints
    remove_individual_pin_constraints

    set_block_pin_constraints -self \
        -allowed_layers {M2 M3 TOP_M} \
        -pin_spacing 2

    # Custom ordered list following a continuous circular progression across sides:
    # Side 1 (West: Top-to-Bottom), Side 2 (North: Left-to-Right), Side 3 (East: Top-to-Bottom), Side 4 (South: Left-to-Right)
    set side1_ports [get_ports -quiet {PADDR[31:26] PRDATA[0:19]}]
    set side2_ports [get_ports -quiet {PADDR[25:0]}]
    set side3_ports [get_ports -quiet {PWDATA[31:20]}]
    set side4_ports [get_ports -quiet {PRDATA[31:20] PWDATA[19:0]}]

    if {[sizeof_collection $side1_ports] > 0} {
        set_individual_pin_constraints -ports $side1_ports -sides 1 -allowed_layers {M3} -pin_spacing_distance 17
    }
    if {[sizeof_collection $side2_ports] > 0} {
        set_individual_pin_constraints -ports $side2_ports -sides 2 -allowed_layers {M2} -pin_spacing_distance 16
    }
    if {[sizeof_collection $side3_ports] > 0} {
        set_individual_pin_constraints -ports $side3_ports -sides 3 -allowed_layers {M3} -pin_spacing_distance 17
    }
    if {[sizeof_collection $side4_ports] > 0} {
        set_individual_pin_constraints -ports $side4_ports -sides 4 -allowed_layers {M2} -pin_spacing_distance 14
    }

    # Explicitly assign VDD and VSS pins to ensure physical ports and labels are generated for LVS
    set power_ports [get_ports -quiet {VDD VSS}]
    if {[sizeof_collection $power_ports] > 0} {
        set_individual_pin_constraints -ports [get_ports VDD] -sides {2} -allowed_layers {TOP_M} -pin_spacing_distance 20
        set_individual_pin_constraints -ports [get_ports VSS] -sides {4} -allowed_layers {TOP_M} -pin_spacing_distance 20
    }

    # Catch-all for any remaining miscellaneous control/RFID pins not explicitly ordered above
    set assigned_ports [get_ports -quiet {PADDR[*] PRDATA[*] PWDATA[*] VDD VSS}]
    set misc_ports [remove_from_collection [get_ports *] $assigned_ports]
    if {[sizeof_collection $misc_ports] > 0} {
        set_individual_pin_constraints -ports $misc_ports -sides {3} -allowed_layers {M3} -pin_spacing_distance 16
    }

    # 5. Place Boundary Pins & Check Self Pins
    place_pins -self
    check_pin_placement -self

    # Explicitly create and bind physical ports for VDD and VSS on TOP_M
    foreach net_name {VDD VSS} {
        set port_obj [get_ports -quiet $net_name]
        if {[sizeof_collection $port_obj] > 0} {
            catch { create_port -direction inout -net_name $net_name $port_obj }
            set_pin_physical_constraints -ports $port_obj -layers {TOP_M}
        }
    }


    # 7. Post-Floorplan Checks & Reports
    report_pin_placement -self
    report_utilization

    save_block -as ${DESIGN_NAME}_floorplan
    save_lib
    puts ">>> STAGE 2 COMPLETE: ${DESIGN_NAME}_floorplan saved. Log: ${LOG_DIR}/2_floorplanning.log"

}