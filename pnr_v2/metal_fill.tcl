# ==============================================================================
# Script: metal_fill.tcl
# Path  : <RUN_DIR>/pnr_v2/metal_fill.tcl   ;# 063 E1: new path
# Stage : Dummy Metal Fill Insertion for DRC Density Compliance
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "unpu_top"   ;# 063 E2: design name
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
source [file join [file dirname [file normalize [info script]]] clock_latency.tcl]   ;# 088: the shared proc that removes the tool-made set_clock_latency (clock_latency.tcl) and checks it
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"   ;# 063 E3b: ICC2 work directory
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/metal_fill.log {
    puts ">>> RUN ROOT: $RUN_ROOT"   ;# 082: the log shows which clone wrote it

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

    unpu_remove_clock_latency metal_fill   ;# 088: remove the tool-made set_clock_latency (a no-op when the block is clean); prints the counts per scenario, ERROR 088 if any is left
    # Explicitly set safe spacing from metal fill to signal routes across all layers
    set_app_options \
        -name signoff.create_metal_fill.space_to_nets \
        -value {{M1 2x} {M2 2x} {M3 2x} {TOP_M 2x}}

    # 1. Run standard track-based metal fill across all layers
    signoff_create_metal_fill \
        -track_fill generic \
        -select_layers {M1 M2 M3 TOP_M}

    # 2. Surgically remove any fill shape inside the exact M2.S.1 violation window (34.26, 375.46)
    # 063 E10: step 2 commented out, the window belongs to the example's own layout and means nothing for unpu_top
    #signoff_create_metal_fill \
    #    -mode remove \
    #    -select_layers {M2} \
    #    -coordinates {{{33.0 374.0} {36.0 377.0}}}

    # Save the updated block with metal fill
    save_block -as ${DESIGN_NAME}_filled
    save_lib
    puts ">>> METAL FILL COMPLETE: ${DESIGN_NAME}_filled saved. Log: ${LOG_DIR}/metal_fill.log"
}