# ==============================================================================
# Script: design_setup.tcl
# Path  : <RUN_DIR>/pnr_v2/design_setup.tcl   ;# 063 E1: new path
# Stage : Design Setup, Library Creation & MCMM Initialization
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME     "unpu_top"   ;# 063 E2: design name
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PROJ_DIR        $RUN_ROOT   ;# 063 E3b: project directory
set SYN_OUT_DIR     "${PROJ_DIR}/syn/out/legacy"   ;# 063 E4: syn/out/legacy/ is produced by the next task (synthesis with the old constraints: 20 ns, setup uncertainty 1.5, hold uncertainty 0.5)
set PNR_DIR         "${PROJ_DIR}/pnr_icc2"
set BLOCKS_DIR      "${PNR_DIR}/blocks"
set LOG_DIR         "${PNR_DIR}/logs"

file mkdir $BLOCKS_DIR
file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/1_design_setup.log {
    puts ">>> RUN ROOT: $RUN_ROOT"   ;# 082: the log shows which clone wrote it

    set NETLIST_FILE    "${SYN_OUT_DIR}/unpu_top_cn.dc.v"   ;# 063 E4: netlist name
    set SDC_FILE        "${SYN_OUT_DIR}/unpu_top_cn.sdc"   ;# 063 E4: SDC name
    
    # Reference Libraries (Standard Cells + Physical-Only Fillers)
    set NDM_LIBS [list \
        "${PNR_DIR}/scl180_std.ndm" \
        "${PNR_DIR}/scl180_filler.ndm" \
    ]

    set PDK_DIR         "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/digital_pnr_kit/snps/non_rh/4M1L"
    set TECH_FILE       "${PDK_DIR}/SCL_4LM.tf"
    set TLUP_FILE       "${PDK_DIR}/SCL_TLUPLUS_4M1L_TYP.tlup"
    set TLUP_MAP        "${PDK_DIR}/SCL_TLUPLUS_4M1L.map"

    # 1. Safe Memory & Disk Cleanup
    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }

    set open_lib [get_libs -quiet *${DESIGN_NAME}*]
    if {[sizeof_collection $open_lib] > 0} {
        close_lib -force $open_lib
    }

    if {[file exists ${BLOCKS_DIR}/${DESIGN_NAME}.dlib]} {
        file delete -force ${BLOCKS_DIR}/${DESIGN_NAME}.dlib
    }

    # 2. Create Design Library (.dlib) linking both NDM reference libraries
    create_lib ${BLOCKS_DIR}/${DESIGN_NAME}.dlib \
        -technology ${TECH_FILE} \
        -ref_libs ${NDM_LIBS}

    # 3. Read Synthesized Netlist & Link Design
    read_verilog -top ${DESIGN_NAME} ${NETLIST_FILE}
    current_block ${DESIGN_NAME}
    link_block

    # 4. Read Parasitic Technology (TLUPlus)
    read_parasitic_tech \
        -tlup ${TLUP_FILE} \
        -layermap ${TLUP_MAP} \
        -name TYPICAL_RC

    # 5. Configure Multi-Corner Multi-Mode (MCMM) Scenarios
    remove_scenarios -all
    remove_modes -all
    remove_corners -all

    create_mode mode_func

    # --- Setup Scenario (Slow-Slow) ---
    create_corner corner_ss
    create_scenario -name func_ss -mode mode_func -corner corner_ss
    current_scenario func_ss
    read_sdc ${SDC_FILE}
    set_parasitic_parameters -early_spec TYPICAL_RC -late_spec TYPICAL_RC
    set_scenario_status func_ss \
        -active true \
        -setup true \
        -hold false \
        -max_transition true \
        -max_capacitance true \
        -dynamic_power true \
        -leakage_power true

    # --- Hold Scenario (Fast-Fast with 1.0 ns Hold Guardband) ---
    create_corner corner_ff
    create_scenario -name func_ff -mode mode_func -corner corner_ff
    current_scenario func_ff
    read_sdc ${SDC_FILE}
    # 063 E5b: the DC-written SDC carries the ss operating condition (set_operating_conditions tsl18fs120_scl_ss), so without the next line the hold scenario would be analysed at ss
    set_operating_conditions tsl18fs120_scl_ff -library tsl18fs120_scl_ff   ;# 063 E5b
    set_parasitic_parameters -early_spec TYPICAL_RC -late_spec TYPICAL_RC
    set_scenario_status func_ff \
        -active true \
        -setup false \
        -hold true \
        -max_transition false \
        -max_capacitance false \
        -dynamic_power false \
        -leakage_power false
    # 063 E5b: print the corners so that the ff operating condition of corner_ff can be checked in the log
    report_corners   ;# 063 E5b

    # Enforce 0.5 ns (2.5% of 20 ns clock) Hold Uncertainty
    #set_clock_uncertainty -hold 0.5 [all_clocks]

    # 6. Enable Buffers, Inverters, and Delay Cells for Optimization & Hold Fixing
    set hold_cells [get_lib_cells -quiet {*/*BUF* */*INV* */*DEL* */*DLY* */*buf* */*inv* */*del* */*dly*}]
    if {[sizeof_collection $hold_cells] > 0} {
        set_lib_cell_purpose -include hold $hold_cells
        set_lib_cell_purpose -include optimization $hold_cells
    }

    # 7. Initial Sanity Checks & Save
    check_netlist
    check_timing -all

    save_block -as ${DESIGN_NAME}_setup
    save_lib
    puts ">>> STAGE 1 COMPLETE: ${DESIGN_NAME}_setup saved. Log: ${LOG_DIR}/1_design_setup.log"

}