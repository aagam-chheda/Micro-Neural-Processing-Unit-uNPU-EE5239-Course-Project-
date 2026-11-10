# ==============================================================================
# Script: cts.tcl
# Path  : <RUN_DIR>/pnr_v2/cts.tcl   ;# 063 E1: new path
# Stage : Clock Tree Synthesis & Hold Time Optimization (target +0.50 ns hold slack)   ;# 065: stale text of the example, the goals are 0.0 now (see HOLD_SLACK_GOAL below)
# Tool  : Synopsys ICC2 (U-2022.12-SP3)
# ==============================================================================

set DESIGN_NAME "unpu_top"   ;# 063 E2: design name
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"   ;# 063 E3b: ICC2 work directory
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

# ------------------------------------------------------------------------------
# Hold margin control
#   SPEC_HOLD_UNC   : real hold uncertainty from the SDC (used for signoff/reports)
#   HOLD_SLACK_GOAL : slack you want after hold fixing
#   OPT_HOLD_UNC    : temporary uncertainty used only while the optimizer runs.
#                     ICC2 fixes hold only when slack < 0, so we raise the
#                     uncertainty by the extra margin you want.
# ------------------------------------------------------------------------------
set SPEC_HOLD_UNC    0.5   ;# 063 E9: old constraints, hold uncertainty 0.5 (the example had 0.05)
set HOLD_SLACK_GOAL  0.0   ;# 065: user decision 2026-11-02, no extra margin on top of the course uncertainties (the example had 0.70)
set OPT_HOLD_UNC     [expr {$SPEC_HOLD_UNC + $HOLD_SLACK_GOAL}]

set SPEC_SETUP_UNC   1.5   ;# 063 E9: old constraints, setup uncertainty 1.5 (the example had 0.15)
set SETUP_SLACK_GOAL 0.0   ;# 065: user decision 2026-11-02, no extra margin on top of the course uncertainties (the example had 0.3)
set OPT_SETUP_UNC    [expr {$SPEC_SETUP_UNC + $SETUP_SLACK_GOAL}]

file mkdir $LOG_DIR

redirect -tee -file ${LOG_DIR}/5_cts.log {
    puts ">>> RUN ROOT: $RUN_ROOT"   ;# 082: the log shows which clone wrote it

    set open_blk [get_blocks -quiet *]
    if {[sizeof_collection $open_blk] > 0} {
        close_blocks -force $open_blk
    }

    # Clean previous CTS block to run completely from square one
    if {[file exists ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${DESIGN_NAME}_cts]} {
        remove_blocks ${DESIGN_NAME}.dlib:${DESIGN_NAME}_cts
    }

    open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${DESIGN_NAME}_placement   ;# 068: back to _placement, step 4b is parked
    link_block

    # Save as _cts immediately from clean placement checkpoint
    save_block -as ${DESIGN_NAME}_cts

    suppress_message {DCHK-027 DCHK-010 ATTR-12 PDC-003 ZRT-740 ZRT-027 POW-046 UIC-058 UIC-057}

    # 1. Pre-CTS Checks
    check_design -checks pre_clock_tree_stage
    check_clock_trees

    # 2. Specify CTS Buffer and Inverter Cells
    set cts_cells  [get_lib_cells -quiet {scl180_std/*CLKBUF* scl180_std/*CLKINV* scl180_std/*clkbuf* scl180_std/*clkinv*}]
    if {[sizeof_collection $cts_cells] > 0} {
        set_lib_cell_purpose -include cts $cts_cells
    }

    # NOTE: this pattern matches every BUF/INV including large drive strengths.
    # If hold fixing inserts big buffers, narrow it to small buffers / delay cells.
    set hold_cells [get_lib_cells -quiet {scl180_std/*BUF* scl180_std/*INV* scl180_std/*DEL* scl180_std/*DLY* scl180_std/*buf* scl180_std/*inv* scl180_std/*del* scl180_std/*dly*}]
    if {[sizeof_collection $hold_cells] > 0} {
        set_lib_cell_purpose -include hold $hold_cells
    }

    # 3. Configure Clock Tree Targets & Routing Layers (M2 & M3)
    set_clock_tree_options \
        -target_skew 0.2

    # Set 0.40 ns max transition on real clock network across active scenarios
    foreach_in_collection scen [all_scenarios] {
        current_scenario $scen
        set real_clks [get_clocks -quiet -filter "is_virtual == false"]
        if {[sizeof_collection $real_clks] > 0} {
            set_max_transition 0.40 -clock_path $real_clks
        }
        remove_ideal_network -all
    }

    set_clock_routing_rules \
        -default_rule \
        -min_routing_layer M2 \
        -max_routing_layer M3

    # 4. Configure CTS & Optimization Application Options
    set_app_options -name cts.compile.enable_global_route -value true
    set_app_options -name clock_opt.flow.enable_ccd -value true

    # Stronger hold fixing (skip silently if the option is not in this release)
    if {[catch {set_app_options -name clock_opt.hold.effort -value high} err]} {
        puts "WARNING: clock_opt.hold.effort not set: $err"
    }

    set_scenario_status func_ss -active true -setup true -hold false
    current_scenario func_ss
    set_clock_uncertainty -setup $OPT_SETUP_UNC [get_clocks -filter "is_virtual == false"]
    puts ">>> Setup uncertainty during optimization: $OPT_SETUP_UNC ns (spec $SPEC_SETUP_UNC ns)"

    # 4b. Raise hold uncertainty on func_ff so the optimizer targets +HOLD_SLACK_GOAL
    set_scenario_status func_ff -active true -hold true -setup true
    current_scenario func_ff
    set_clock_uncertainty -hold $OPT_HOLD_UNC [get_clocks -filter "is_virtual == false"]
    puts ">>> Hold uncertainty during optimization: $OPT_HOLD_UNC ns (spec $SPEC_HOLD_UNC ns)"

    # 5. Run Clock Tree Synthesis and Optimization
    puts ">>> Running Clock Tree Synthesis and Optimization..."
    clock_opt

    # Ensure propagated clock is active on real clocks across all scenarios
    foreach_in_collection scen [all_scenarios] {
        current_scenario $scen
        set real_clks [get_clocks -quiet -filter "is_virtual == false"]
        if {[sizeof_collection $real_clks] > 0} {
            set_propagated_clock $real_clks
        }
    }

    # 5b. Restore the real (spec) hold uncertainty so reports show true slack
    #     (reports should now be >= +HOLD_SLACK_GOAL if the optimizer succeeded)

    current_scenario func_ss
    set_clock_uncertainty -setup $SPEC_SETUP_UNC [get_clocks -filter "is_virtual == false"]

    current_scenario func_ff
    set_clock_uncertainty -hold $SPEC_HOLD_UNC [get_clocks -filter "is_virtual == false"]

    # 6. Connect PG Nets to CTS & Hold Buffers
    connect_pg_net -automatic
    connect_pg_net -net VDD [get_pins -hierarchical -quiet */VDD]
    connect_pg_net -net VSS [get_pins -hierarchical -quiet */VSS]

    # 7. Post-CTS Verification & Timing Reports
    update_timing -full
    check_legality
    check_clock_trees
    check_pg_connectivity
    report_clock_qor
    report_clock_timing -type skew
    report_qor
    report_global_timing
    report_power

    current_scenario func_ff
    report_timing -scenarios func_ff -path_type full_clock_expanded -delay_type min -max_paths 20 -significant_digits 4

    current_scenario func_ss
    report_timing -scenarios func_ss -path_type full_clock_expanded -delay_type max -max_paths 20 -significant_digits 4

    save_block -as ${DESIGN_NAME}_cts
    save_lib
    puts ">>> STAGE 5 COMPLETE: ${DESIGN_NAME}_cts saved successfully. Log: ${LOG_DIR}/5_cts.log"

}