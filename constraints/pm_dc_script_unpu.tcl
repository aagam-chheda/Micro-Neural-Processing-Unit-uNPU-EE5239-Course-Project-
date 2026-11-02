# =============================================================================
# DRAFT -- Planning, not yet reviewed by Execution, never run.
#
# PM's example Design Compiler script, adapted for unpu_top on the SCL 180 nm
# FS120 4M1L kit. Source: the user's copy of the PM's example
# (temp/temp_constraits.txt, untracked).
#
# Every PM command is kept as given (the clock, drive, load and I/O delays now
# live in constraints/pm_unpu_top.sdc): the operating-
# condition and wire-load branches, the optimisation constraints,
# set_fix_multiple_port_nets, remove_unconnected_ports, and the compile.
# Only the lines marked "CHANGED" differ from the PM's file:
#
#   1. top_module       counter_4bit  ->  unpu_top
#   2. tech_lib         UMC65 uk65... ->  tsl18fs120_scl_ss (ff commented out)
#   3. target_library   UMC65 .db     ->  SCL FS120 4M1IL ss .db (ff commented out)
#   4. RTL read         counter_4bit.v, -format verilog
#                       ->  the 11 rtl/*.sv files, explicit list, -format sverilog
#   5. report paths     ./reports     ->  syn/out/$UNPU_STAGE (git-ignored), one directory per stage profile
#
# Run dc_shell from the repo root (paths are relative). The stage profile is REQUIRED:
#   csh:   setenv UNPU_STAGE syn16 ; dc_shell -f constraints/pm_dc_script_unpu.tcl | tee syn/out/syn16.log
# (valid profiles: syn20 syn18 syn16 place cts route signoff; no default; the same error as
# constraints/unpu_top.sdc if it is unset or unknown).
#
#   6. constraints (clock, drive, load, I/O delays): moved to a pure SDC,
#      constraints/pm_unpu_top.sdc, which this script reads with read_sdc. That file
#      keeps the PM's constraints, adds those of constraints/unpu_top.sdc, and adds
#      an input driving cell and an output load. Its numbers are assumptions.
#   7. (task 051) stage profile: UNPU_STAGE is required; outputs go to syn/out/$UNPU_STAGE/.
#   8. (task 051) after compile: extra reports (worst 5 setup paths per path group, violators, qor,
#      check_timing, check_design), each with a one-line profile header; change_names, then the
#      clean-name netlist, SDC and .ddc (unpu_top_cn.*) in addition to the originals.
# =============================================================================


# -----------------------------------------------------------------------------
# 1. Setup: design, library, read RTL
# -----------------------------------------------------------------------------

# CHANGED (task 051): the stage profile is required, and names the output directory. No default: a
# silent default would make a result look like another stage's. The list of valid names here must equal
# the profile table of constraints/unpu_top.sdc (constraints/test_stages.tcl checks that).
set stage_names {syn20 syn18 syn16 place cts route signoff}
if {![info exists ::env(UNPU_STAGE)] || $::env(UNPU_STAGE) eq ""} {
    error "unpu DC script: the environment variable UNPU_STAGE is not set. It has no default. Valid profiles: $stage_names. csh: setenv UNPU_STAGE <profile>"
}
set UNPU_STAGE $::env(UNPU_STAGE)
if {[lsearch -exact $stage_names $UNPU_STAGE] < 0} {
    error "unpu DC script: UNPU_STAGE='$UNPU_STAGE' is not a profile. Valid profiles: $stage_names"
}

# CHANGED: top module
set top_module  unpu_top
set clk_name    clk

# CHANGED: SCL 180 nm FS120 library. One corner per run: the ss line is
# active, the ff line is commented out. To run ff, comment the ss lines and
# uncomment the ff lines, in BOTH places (tech_lib here and target_library
# below); they must always be the same corner.
set tech_lib    tsl18fs120_scl_ss
# set tech_lib  tsl18fs120_scl_ff

set synthetic_library dw_foundation.sldb

# CHANGED: SCL kit .db files (4M1L; the directory really is spelled 4M1IL)
set target_library "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db"
# set target_library "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ff/tsl18fs120_scl_ff.db"

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
# 2. Constraints: clock, I/O delays, drive, load
# -----------------------------------------------------------------------------

# CHANGED: the constraints moved out of this script into a pure SDC file,
# constraints/pm_unpu_top.sdc, so ICC2 and PrimeTime can read the same file.
# It holds the PM's original constraints (clock, I/O delays; the PM's set_drive 0
# and set_load 0 are removed), the constraints from constraints/unpu_top.sdc, and the new driving cell and
# output load. The PM's "is there a clk port, else make vclk" fallback is gone:
# unpu_top has a real clk port. The path is relative to the repo root.
read_sdc constraints/pm_unpu_top.sdc

# CHANGED (task 051): the profile's numbers are set by the SDC as Tcl variables (they are used in the report headers
# below). VERIFY: variables set inside read_sdc are visible here; if not, this stops with the message.
foreach v {CLK_PERIOD CLK_UNCERT_SETUP CLK_UNCERT_HOLD} {
    if {![info exists $v]} { error "unpu DC script: $v was not set by constraints/pm_unpu_top.sdc (the stage profile section) or is not visible after read_sdc" }
}


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

# CHANGED: reports go under syn/out/<stage profile>/ (git-ignored) instead of ./reports.
set rpt_dir syn/out/$UNPU_STAGE
file mkdir $rpt_dir

# CHANGED (task 051): the first line of every report file says which profile made it, so a copied file is never
# anonymous. The header is written with echo, the report is appended.
set profile_line "# stage profile $UNPU_STAGE: period $CLK_PERIOD ns, setup uncertainty $CLK_UNCERT_SETUP ns, hold uncertainty $CLK_UNCERT_HOLD ns; written [clock format [clock seconds]]"
proc unpu_hdr {file} {
    global profile_line
    echo $profile_line > $file
}
unpu_hdr $rpt_dir/$top_module.profile

unpu_hdr $rpt_dir/$top_module.area
report_area >> $rpt_dir/$top_module.area
unpu_hdr $rpt_dir/$top_module.power
report_power -verbose >> $rpt_dir/$top_module.power
unpu_hdr $rpt_dir/$top_module.timing
report_timing >> $rpt_dir/$top_module.timing

# CHANGED (task 051): the reports a reader needs, each in its own file. VERIFY: report_timing -max_paths 5 -nworst 1 gives
# the 5 worst setup paths of each path group in dc_shell (max_paths counts per path group there).
unpu_hdr $rpt_dir/$top_module.timing_top5
report_timing -max_paths 5 -nworst 1 >> $rpt_dir/$top_module.timing_top5
unpu_hdr $rpt_dir/$top_module.constraint
report_constraint -all_violators >> $rpt_dir/$top_module.constraint
unpu_hdr $rpt_dir/$top_module.qor
report_qor >> $rpt_dir/$top_module.qor
unpu_hdr $rpt_dir/$top_module.check_timing
check_timing >> $rpt_dir/$top_module.check_timing
unpu_hdr $rpt_dir/$top_module.check_design
check_design >> $rpt_dir/$top_module.check_design

write -hierarchy -format verilog -output $rpt_dir/$top_module.dc.v
# write -hierarchy -format verilog -output $dir_out_synopsys/$top_module.db
# write -hierarchy -format ddc -output $dir_out_synopsys/$top_module.ddc
write_sdc -version 2.1 $rpt_dir/$top_module.sdc

# CHANGED (task 051): clean names for ICC2 (18.8 did this by hand): change_names, then the clean-name netlist, SDC and .ddc
# in addition to the originals above. The reports above keep the names DC chose.
change_names -rules verilog -hierarchy
write -hierarchy -format verilog -output $rpt_dir/${top_module}_cn.dc.v
write_sdc -version 2.1 $rpt_dir/${top_module}_cn.sdc
write -hierarchy -format ddc -output $rpt_dir/${top_module}_cn.ddc

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
