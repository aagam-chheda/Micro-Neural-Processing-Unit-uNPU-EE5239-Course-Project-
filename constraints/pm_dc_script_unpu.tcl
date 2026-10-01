# =============================================================================
# DRAFT -- Planning, not yet reviewed by Execution, never run.
#
# PM's example Design Compiler script, adapted for unpu_top on the SCL 180 nm
# FS120 4M1L kit. Source: the user's copy of the PM's example
# (temp/temp_constraits.txt, untracked).
#
# Every PM constraint and command is kept exactly as given: the clock,
# set_drive / set_load / set_input_delay / set_output_delay, the operating-
# condition and wire-load branches, the optimisation constraints,
# set_fix_multiple_port_nets, remove_unconnected_ports, and the compile.
# Only the lines marked "CHANGED" differ from the PM's file:
#
#   1. top_module       counter_4bit  ->  unpu_top
#   2. corner switch    new: ss (default) or ff, from env CORNER or `set corner`
#   2b. tech_lib        UMC65 uk65... ->  tsl18fs120_scl_<corner>
#   3. target_library   UMC65 .db     ->  SCL FS120 4M1IL .db for the corner
#   4. RTL read         counter_4bit.v, -format verilog
#                       ->  the 11 rtl/*.sv files, explicit list, -format sverilog
#   5. report paths     ./reports     ->  syn/out/pm_flow_<corner> (git-ignored)
#
# Run dc_shell from the repo root (paths are relative).
#
# Note: the PM's values differ from constraints/unpu_top.sdc. Here all I/O
# delays, drive and load are 0; unpu_top.sdc uses 30% budgets. Both are
# assumptions pending the SoC team, and they are not reconciled here.
# =============================================================================


# -----------------------------------------------------------------------------
# 1. Setup: design, library, read RTL
# -----------------------------------------------------------------------------

# CHANGED: top module
set top_module  unpu_top
set clk_name    clk

# CHANGED: corner switch. One script, one corner per run: ss (default) or ff.
# Pick it before sourcing the script, either way:
#     csh, before starting dc_shell:     setenv CORNER ff
#     at the dc_shell> prompt:           set corner ff
# The two corners are separate runs on purpose. The ss and ff libraries define
# the same cell names, so they are not listed together in target_library.
if {![info exists corner]} {
    if {[info exists ::env(CORNER)] && $::env(CORNER) ne ""} {
        set corner $::env(CORNER)
    } else {
        set corner ss
    }
}
if {$corner ne "ss" && $corner ne "ff"} {
    error "corner must be ss or ff, got '$corner'"
}
puts "Info: corner = $corner"

# CHANGED: SCL 180 nm FS120 library for the chosen corner.
set tech_lib    tsl18fs120_scl_$corner

set synthetic_library dw_foundation.sldb

# CHANGED: SCL kit .db for the chosen corner (4M1L; the directory really is
# spelled 4M1IL).
set target_library "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_$corner/tsl18fs120_scl_$corner.db"

set link_library "* $target_library $synthetic_library"

# CHANGED: the design is SystemVerilog (.sv), so -format sverilog. The file list
# is explicit, leaves first, and relative to the repo root.
set rtl_dir rtl
set rtl_files [list \
    $rtl_dir/unpu_pe.sv    $rtl_dir/unpu_grid.sv   $rtl_dir/unpu_skew.sv \
    $rtl_dir/unpu_deskew.sv $rtl_dir/unpu_wbuf.sv  $rtl_dir/unpu_actbuf.sv \
    $rtl_dir/unpu_dma.sv   $rtl_dir/unpu_seq.sv    $rtl_dir/unpu_csr.sv \
    $rtl_dir/unpu_apb.sv   $rtl_dir/unpu_top.sv ]

foreach ff $rtl_files {
    analyze -library WORK -format sverilog $ff
}

set synlib_enable_dpgen true
elaborate $top_module
current_design $top_module
link


# -----------------------------------------------------------------------------
# 2. Create clock
# -----------------------------------------------------------------------------

set find_clock [find port [list $clk_name]]
if {$find_clock != [list]} {
    create_clock $clk_name -period 20
    puts "clock present"
} else {
    set clk_name vclk
    create_clock -period 20 -name $clk_name
    puts "clock not present"
}


# -----------------------------------------------------------------------------
# 3. Operating environment: input/output delay, drive strength
# -----------------------------------------------------------------------------

if {[string match gscl45nm $tech_lib] == 1} {
    set_driving_cell -lib_cell INVX1 [all_inputs]
}
set_drive 0 [all_inputs]
set_load  0 [all_outputs]
set_input_delay  0 [all_inputs]  -clock $clk_name
set_output_delay 0 [all_outputs] -clock $clk_name


# -----------------------------------------------------------------------------
# 4. Operating environment: operating condition, wire load
# -----------------------------------------------------------------------------

# set auto_wire_load_selection true
# set wire_lode_mode "top"
# Allow DC to restructure the adder tree

if {[string match *_brs_generic_core_* $tech_lib] == 1} {
    set condition [lindex [split $tech_lib "_"] end]
    set_operating_conditions -library $tech_lib $condition
    set_wire_load_model -name "enG50K" -library "$tech_lib"

} elseif {[string match *generic_core_ff* $tech_lib] == 1} {
    # append tech "_ff"
    set_operating_conditions -library $tech_lib
    set_wire_load_model -name "enG50K" -library "$tech_lib"

} elseif {[string match *generic_core_ss* $tech_lib] == 1} {
    # append tech "_ss"
    set_operating_conditions -library $tech_lib WCCOM
    set_wire_load_model -name "enG50K" -library "$tech_lib"

} elseif {[string match *generic_core_tt* $tech_lib] == 1} {
    # append tech "_tt"
    set_operating_conditions -library $tech_lib TCCOM
    set_wire_load_model -name "enG50K" -library "$tech_lib"

} elseif {[string match gscl45nm $tech_lib] == 1} {
    set_operating_conditions -library $tech_lib typical

} elseif {[string match *tsl18fs120_scl* $tech_lib] == 1} {
    # This is the branch that applies to the SCL library.
    if {[string match *ff* $tech_lib] == 1} {
        append tech "_ff"
    } elseif {[string match *ss* $tech_lib] == 1} {
        append tech "_ss"
    }
    set_operating_conditions -library $tech_lib $tech_lib
    set_wire_load_model -name "140000" -library "$tech_lib"

} elseif {[string match *uk65lscspmvl9b* $tech_lib] == 1} {
    # set_operating_conditions -library $tech_lib
    set_wire_load_model -name "wl30" -library "$tech_lib"
}


# -----------------------------------------------------------------------------
# 5. Optimisation constraints
# -----------------------------------------------------------------------------

# set_max_delay 5.4 -from $clk_name

# set_max_transition 2 $top_module
# set_max_capacitance 5 $top_module

set_max_area 0
set_max_dynamic_power 0
set_max_leakage_power 0
set_max_total_power 0

set_fix_multiple_port_nets -buffer_constant -all
remove_unconnected_ports [find -hierarchy cell {"*"}]


# -----------------------------------------------------------------------------
# 6. Compile
# -----------------------------------------------------------------------------

# Alternatives kept from the PM's file, all disabled:
#
# if {$clock_gatting_en == "true"} {
#     compile -gate_clock -map_effort  high -incremental_mapping
#     compile -gate_clock -area_effort high -incremental_mapping
#     compile -gate_clock -power_effort high -incremental_mapping
# } else {
#     compile -map_effort  high -incremental_mapping
#     compile -area_effort high -incremental_mapping
#     compile -power_effort high -incremental_mapping
# }

compile -map_effort high
# compile -area_effort medium
# compile -power_effort high
# compile -incremental_mapping
# compile -map_effort low -area_effort high -power_effort low
# compile -area_effort high -incremental_mapping
# compile -map_effort high -area_effort high -power_effort high -incremental_mapping


# -----------------------------------------------------------------------------
# 7. Reports and outputs
# -----------------------------------------------------------------------------

# CHANGED: reports go under syn/out/ (git-ignored) instead of ./reports, one
# directory per corner so the ss and ff runs do not overwrite each other.
set rpt_dir syn/out/pm_flow_$corner
file mkdir $rpt_dir

report_area > $rpt_dir/$top_module.area
report_power -verbose > $rpt_dir/$top_module.power
report_timing > $rpt_dir/$top_module.timing
write -hierarchy -format verilog -output $rpt_dir/$top_module.dc.v
# write -hierarchy -format verilog -output $dir_out_synopsys/$top_module.db
# write -hierarchy -format ddc -output $dir_out_synopsys/$top_module.ddc
write_sdc -version 2.1 $rpt_dir/$top_module.sdc

# More reports from the PM's file, all disabled:
#
# source ./scripts/report.tcl
# check_design -multiple_designs > $dir_rep_synopsys/$top_module.check.report
# report_area > $dir_rep_synopsys/$top_module.area.report
# report_design > $dir_rep_synopsys/$top_module.design.report
# report_cell > $dir_rep_synopsys/$top_module.cell.report
# report_reference > $dir_rep_synopsys/$top_module.reference.report
# report_port -verbose > $dir_rep_synopsys/$top_module.port.report
# report_net -verbose > $dir_rep_synopsys/$top_module.net.report
# report_compile_options > $dir_rep_synopsys/$top_module.compile.report
# report_constraint -all_violators > $dir_rep_synopsys/$top_module.constraint.report
#
# report_net -noflat -transition_times -cell_degradation -connection >> $dir_rep_synopsys/$top_module.net.report
# report_timing > $dir_rep_synopsys/$top_module.timing.report
# report_timing -path end >> $dir_rep_synopsys/$top_module.timing.report
# report_timing_requirements >> $dir_rep_synopsys/$top_module.timing.report
# report_timing -max_path 10 >> $dir_rep_synopsys/$top_module.timing.report
# report_qor > $dir_rep_synopsys/$top_module.qor.report
# report_power -verbose > $dir_rep_synopsys/$top_module.power.report
