# ==============================================================================
# Script: metal_fill.tcl
# Path  : /storage/EE5239G2/RFID_v2/pnr_icc2/TCL_pnr/metal_fill.tcl
# Stage : Dummy Metal Fill Insertion for DRC Density Compliance
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "baseband_crypto_macro"
set PNR_DIR     "/storage/EE5239G2/RFID_v2/pnr_icc2"
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/metal_fill.log {

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

    # Open the design library first
    open_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib

    set blk_name "${DESIGN_NAME}_route"
    if {[catch {open_block ${DESIGN_NAME}.dlib:${blk_name}}]} {
        puts "Available blocks in library:"
        list_blocks
        error "ERROR: Block ${blk_name} not found! Check your route.tcl save name."
    }
    
    current_block ${blk_name}
    link_block

    # Explicitly set safe spacing from metal fill to signal routes across all layers
    set_app_options \
        -name signoff.create_metal_fill.space_to_nets \
        -value {{M1 2x} {M2 2x} {M3 2x} {TOP_M 2x}}

    # 1. Run standard track-based metal fill across all layers
    signoff_create_metal_fill \
        -track_fill generic \
        -select_layers {M1 M2 M3 TOP_M}

    # 2. Surgically remove any fill shape inside the exact M2.S.1 violation window (34.26, 375.46)
    signoff_create_metal_fill \
        -mode remove \
        -select_layers {M2} \
        -coordinates {{{33.0 374.0} {36.0 377.0}}}

    # Save the updated block with metal fill
    save_block -as ${DESIGN_NAME}_filled
    save_lib
    puts ">>> METAL FILL COMPLETE: ${DESIGN_NAME}_filled saved. Log: ${LOG_DIR}/metal_fill.log"
}