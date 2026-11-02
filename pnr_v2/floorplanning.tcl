# ==============================================================================
# Script: floorplanning.tcl
# Path  : /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/floorplanning.tcl   ;# 063 E1: new path
# Stage : Floorplan Initialization, Tap Cells & Circular Sequenced Pin Placement
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "unpu_top"   ;# 063 E2: design name
set PNR_DIR     "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"   ;# 063 E3b: ICC2 work directory
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

    # 3. Initialize Rectangular Floorplan (die derived by the tool from the netlist area, 20 um core offset, 60% core utilization)   ;# 063 E6
    # 063 E6: control_type core instead of a fixed die; 0.60 = instructor guidance start utilisation 60 to 70 percent (pessimistic end); offset 20 stays because the PDN ring of powerplanning.tcl sits in it
    initialize_floorplan \
        -control_type core \
        -core_utilization 0.60 \
        -core_offset {20 20 20 20}

    # 4. Configure Circular Sequenced Pin Placement Constraints
    remove_block_pin_constraints
    remove_individual_pin_constraints

    set_block_pin_constraints -self \
        -allowed_layers {M2 M3 TOP_M} \
        -pin_spacing 2

    # 063 E7: pins per the top-level team (handoff 18.9 Q4): side 2 (top, M2) = DMA port (102 pins), side 3 (right, M3) = APB port plus clk and rst_n (102 pins), nothing on sides 1 and 4; the example's side1 and side4 groups are deleted
    set side2_ports [get_ports -quiet {dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] dma_valid dma_ready}]   ;# 063 E7
    set side3_ports [get_ports -quiet {paddr[*] pwdata[*] prdata[*] pwrite psel penable pready clk rst_n}]   ;# 063 E7

    if {[sizeof_collection $side2_ports] > 0} {
        set_individual_pin_constraints -ports $side2_ports -sides 2 -allowed_layers {M2} -pin_spacing_distance 8   ;# 063 E7: spacing 8 um (old flow minimum pitch 6.72 um)
    }
    if {[sizeof_collection $side3_ports] > 0} {
        set_individual_pin_constraints -ports $side3_ports -sides 3 -allowed_layers {M3} -pin_spacing_distance 8   ;# 063 E7: spacing 8 um (old flow minimum pitch 6.72 um)
    }

    # Explicitly assign VDD and VSS pins to ensure physical ports and labels are generated for LVS
    set power_ports [get_ports -quiet {VDD VSS}]
    if {[sizeof_collection $power_ports] > 0} {
        # 063 E8: the two VDD/VSS set_individual_pin_constraints lines are deleted (these ports do not exist before powerplanning.tcl, and the sides used there belonged to the deleted groups)
    }

    # Catch-all for any remaining miscellaneous control pins not explicitly ordered above   ;# 063 E8: example-specific word dropped from this comment
    # 063 E8: assigned_ports = the ports of the two groups above (VDD VSS dropped); the catch-all must stay empty, see the printed count
    set assigned_ports [get_ports -quiet {paddr[*] pwdata[*] prdata[*] dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] pwrite psel penable pready clk rst_n dma_valid dma_ready}]   ;# 063 E8
    set misc_ports [remove_from_collection [get_ports *] $assigned_ports]
    puts ">>> unassigned ports: [sizeof_collection $misc_ports]"   ;# 063 E8: expected 0
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