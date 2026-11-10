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
source [file join [file dirname [file normalize [info script]]] clock_latency.tcl]   ;# 088: the shared proc that removes the tool-made set_clock_latency (clock_latency.tcl) and checks it
set PNR_DIR     "${RUN_ROOT}/pnr_icc2"   ;# 063 E3b: ICC2 work directory
set BLOCKS_DIR  "${PNR_DIR}/blocks"
set LOG_DIR     "${PNR_DIR}/logs"

set CTS_INPUT_BLOCK  "${DESIGN_NAME}_portbuf"   ;# 085: the block CTS reads. Default = the output of step 4c (port_buffers_early.tcl: _placement -> _portbuf -> _cts). Set it to ${DESIGN_NAME}_placement to run without step 4c
set CTS_SPLIT        1   ;# 088: 1 = clock_opt in three calls (build_clock, route_clock, final_opto) with the removal of the tool-made set_clock_latency after each; 0 = one call, removal after it. Environment UNPU_CTS_SPLIT (0 or 1) overrides without editing the file
set CTS_SPLIT_SRC    "default"
if {[info exists ::env(UNPU_CTS_SPLIT)]} {
    if {$::env(UNPU_CTS_SPLIT) ne "0" && $::env(UNPU_CTS_SPLIT) ne "1"} { error "ERROR 088: UNPU_CTS_SPLIT='$::env(UNPU_CTS_SPLIT)' is not valid: it must be 0 or 1" }
    set CTS_SPLIT $::env(UNPU_CTS_SPLIT)
    set CTS_SPLIT_SRC "environment UNPU_CTS_SPLIT"
}
set CTS_CHECK_IN_PORT  "dma_rdata\[14\]"   ;# 088: the input port of the I/O reference check printed at the end (the example path of the 084 diagnostic); a name that does not exist prints a WARNING, not a silent skip
set CTS_CHECK_OUT_PORT "dma_addr\[31\]"    ;# 088: the output port of the same check

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

    if {[catch {open_block ${BLOCKS_DIR}/${DESIGN_NAME}.dlib:${CTS_INPUT_BLOCK}} cts_open_err]} {   ;# 085: the block comes from the parameter CTS_INPUT_BLOCK; a missing block stops with the way out
        error "ERROR 085: cannot open the block ${CTS_INPUT_BLOCK} ($cts_open_err). Step 4c (port_buffers_early.tcl) writes it; to run without step 4c set CTS_INPUT_BLOCK to ${DESIGN_NAME}_placement at the top of cts.tcl. Blocks that exist: [get_object_name [get_blocks -all -quiet]]"
    }
    link_block
    unpu_remove_clock_latency cts-input   ;# 088: a no-op when the input block is clean; cleans a block that an earlier step or an older script left with the tool-made set_clock_latency (the counts are printed)

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

    # 088: the line `set_app_options -name clock_opt.hold.effort -value high` is deleted: this ICC2 has no such option (error NDMUI-439 in run 1, caught and printed as a WARNING every time). Nothing replaces it.

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
    # 088: ICC2 writes `set_clock_latency <v> [get_clocks {clk}]` into the block and then counts it as the I/O reference latency; PrimeTime ignores it (task 086 A0, clock_latency.tcl). It is removed
    # 088: at the earliest point it exists. clock_opt is split at its sub-steps (usage text: clock_opt [-list_only] [-from <step>] [-to <step>], steps build_clock route_clock final_opto) so that
    # 088: final_opto (the optimisation and hold fixing) runs WITHOUT the line; the counts before each removal show which step creates it. No other CTS option is changed.
    # 088: CTS_SPLIT 0 (environment UNPU_CTS_SPLIT 0) runs one clock_opt call and removes the line after it; then final_opto ran WITH the line (printed).
    if {$CTS_SPLIT} {
        set cts_steps_txt ""
        redirect -variable cts_steps_txt { clock_opt -list_only }
        puts ">>> 088 clock_opt -list_only: [string trim $cts_steps_txt]"
        foreach cts_step {build_clock route_clock final_opto} {
            if {[string first $cts_step $cts_steps_txt] < 0} { error "ERROR 088: the clock_opt step '$cts_step' is not listed by clock_opt -list_only; run with UNPU_CTS_SPLIT 0 (one clock_opt call, the line is removed after it)" }
        }
        puts ">>> 088 CTS_SPLIT 1 ($CTS_SPLIT_SRC): clock_opt in three calls, the tool-made set_clock_latency is removed after each"
        clock_opt -to build_clock
        unpu_remove_clock_latency cts-after-build_clock
        clock_opt -from route_clock -to route_clock
        unpu_remove_clock_latency cts-after-route_clock
        clock_opt -from final_opto
        unpu_remove_clock_latency cts-after-final_opto
        puts ">>> 088 final_opto ran WITHOUT the tool-made line unless the count before its removal above says it was re-created inside final_opto"
    } else {
        puts ">>> 088 CTS_SPLIT 0 ($CTS_SPLIT_SRC): one clock_opt call; the tool-made set_clock_latency is removed AFTER it, so final_opto ran WITH the line"
        clock_opt
        unpu_remove_clock_latency cts-after-clock_opt
    }

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

    # 088: the I/O reference check (a reduced form of the 084 diagnostic): after the removal the input launch must carry no clock latency and the output capture must be 0.00
    unpu_clock_latency_count cts-final-check
    if {[catch {
        set cts_dl_path ${RUN_ROOT}/pnr_v2/diag_io_latency.tcl
        set fp [open $cts_dl_path r]; set cts_dl_src [read $fp]; close $fp
        set cts_b [string first "# ---- BEGIN PURE TCL 084 ----" $cts_dl_src]; set cts_e [string first "# ---- END PURE TCL 084 ----" $cts_dl_src]
        if {$cts_b < 0 || $cts_e < 0} { error "markers BEGIN/END PURE TCL 084 not found in $cts_dl_path" }
        eval [string range $cts_dl_src $cts_b $cts_e]
        set cts_io_h ""; set cts_io_s ""
        redirect -variable cts_io_h { report_timing -scenarios func_ff -delay_type min -from [get_ports $CTS_CHECK_IN_PORT] -path_type full_clock_expanded -input_pins -nets -significant_digits 4 -nosplit }
        redirect -variable cts_io_s { report_timing -scenarios func_ss -delay_type max -to [get_ports $CTS_CHECK_OUT_PORT] -path_type full_clock_expanded -input_pins -nets -significant_digits 4 -nosplit }
        set cts_ph [diag084_parse $cts_io_h]; set cts_ps [diag084_parse $cts_io_s]
        puts ">>> 088 I/O reference latency after the removal: input launch [diag084_num [dict get $cts_ph launch]] at $CTS_CHECK_IN_PORT (hold, func_ff; PrimeTime convention: 0.00 plus the port stage only), output capture [diag084_num [dict get $cts_ps capture]] at $CTS_CHECK_OUT_PORT (setup, func_ss; expected 0.00)"
        puts ">>> 088 raw first rows of the hold path (read the launch latency by eye; the port stage of the driving cell is not a clock latency):"
        set cts_n 0
        foreach cts_r [diag084_rows $cts_io_h] { if {[lindex $cts_r 4] != 0} continue; puts [format ">>> 088     %-46s incr %8s path %8s" [lindex $cts_r 0] [lindex $cts_r 1] [lindex $cts_r 2]]; if {[incr cts_n] >= 8} break }
    } cts_io_err]} {
        puts ">>> 088 WARNING: the I/O reference check could not run: $cts_io_err"
    }

    save_block -as ${DESIGN_NAME}_cts
    save_lib
    puts ">>> STAGE 5 COMPLETE: ${DESIGN_NAME}_cts saved successfully. Log: ${LOG_DIR}/5_cts.log"

}