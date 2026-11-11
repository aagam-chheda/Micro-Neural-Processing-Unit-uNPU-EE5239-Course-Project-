# =============================================================================
# dc_script_legacy.tcl -- Design Compiler synthesis of unpu_top with the OLD constraints (task 064).
#
# PURPOSE   Clean-slate run of 2026-11-02 (user decision): synthesise unpu_top once with the old constraints (period 20 ns, setup
#           uncertainty 1.5, hold uncertainty 0.5, APB 35/35, DMA 40/40, rst_n 40, min delays 0 / -0.5, ...) and no stage profiles.
#           The result feeds the gate-level simulation and the pnr_v2/ ICC2 flow (pnr_v2/design_setup.tcl reads
#           syn/out/legacy/unpu_top_cn.dc.v and unpu_top_cn.sdc).
# READS     rtl/*.sv (the 11 files listed below, RTL is frozen) and constraints/legacy/unpu_top_legacy.sdc, which is
#           byte-identical to `git show 925bfa9:constraints/pm_unpu_top.sdc` (the only authoritative form of the old numbers;
#           nothing is retyped here).
# WRITES    syn/out/legacy/ : exactly 14 files (unpu_top.{profile,area,power,timing,timing_top5,constraint,qor,check_timing,check_design},
#           unpu_top.dc.v, unpu_top.sdc, unpu_top_cn.dc.v, unpu_top_cn.sdc, unpu_top_cn.ddc); no SDF (write_sdf is task 059, not accepted).
#           DC scratch files go to syn/out/work/legacy/ (both under the git-ignored syn/out/).
# RUN       csh, from the repo root (the script checks that it is):
#             mkdir -p syn/out ; dc_shell -f constraints/legacy/dc_script_legacy.tcl |& tee syn/out/legacy_dc.log
#           See syn/RUNBOOK_legacy.md. The script ends with exit.
# DO NOT    edit this script or the SDC to close timing. The old numbers are the user's decision; a change needs a written
#           reason and the user's approval.
#
# BASIS     The COMMITTED constraints/pm_dc_script_unpu.tcl (HEAD, with the task-055 fixes: fatal guards, exit, scratch directory,
#           exact output check, change_names to _cn), not the working-tree version. Library setup, operating-condition and
#           wire-load branches, optimisation constraints and compile options are unchanged. Differences, and only these:
#   L1. no UNPU_STAGE, no constraints/stage_numbers.tcl, no profile table. read_sdc reads constraints/legacy/unpu_top_legacy.sdc.
#   L2. The numbers the base takes from the profile (period, setup and hold uncertainty) are read from the SDC's own
#       `set CLK_PERIOD` / `set CLK_UNCERT_SETUP` / `set CLK_UNCERT_HOLD` lines by unpu_sdc_number (pure Tcl, strict: not exactly one
#       such line, or a non-numeric value, stops the script). Why this and not a typed 20.0: one table, no second copy of a number;
#       the tool's clock period (from create_clock in the same file) is then compared with the SDC's CLK_PERIOD, which also
#       catches an SDC whose create_clock and CLK_PERIOD disagree. They are used in the report headers and the read-back check.
#       (dc_shell evaluates the SDC in its own scope, so the variables themselves are not visible after read_sdc: task 055.)
#   L3. outputs go to syn/out/legacy/ and scratch to syn/out/work/legacy/; no write_sdf; the end-of-script check expects the 14 files
#       above. unpu_check_outputs is the base's procedure from constraints/stage_numbers.tcl, copied here (no file is sourced).
#   L4. the report header says "legacy constraints" instead of "stage profile <name>".
# =============================================================================


# -----------------------------------------------------------------------------
# 1. Setup: design, library, read RTL
# -----------------------------------------------------------------------------

# CHANGED (task 055): FATAL guards. A Tcl "error" in a dc_shell -f script only prints "Error:" and the script goes on
# (seen in the first real run: compile and the reports ran after the guard fired). unpu_fatal prints the reason
# and runs exit 1, so nothing after a failed guard runs. VERIFY: "exit 1" ends dc_shell with status 1 from inside a proc.
proc unpu_fatal {msg} {
    puts "Error: unpu DC script: $msg"
    puts "Error: unpu DC script: STOPPED with exit 1; nothing after this point was run."
    exit 1
    # not reached; if exit ever returned, do not go on:
    return -code error "unpu DC script: exit 1 did not end the shell"
}

# The script must run from the repo root: every path below is the repo root plus a relative path.
set repo_root [pwd]
set sdc_rel constraints/legacy/unpu_top_legacy.sdc
foreach rel [list rtl/unpu_top.sv $sdc_rel] {
    if {![file exists $repo_root/$rel]} {
        unpu_fatal "$rel not found under the current directory $repo_root. Run dc_shell from the repo root."
    }
}

# L2: the numbers come from the SDC's own table lines. strict: exactly one line `set <name> <number>` per name.
proc unpu_sdc_number {sdc_text var} {
    set hits {}
    foreach l [split $sdc_text "\n"] {
        if {[regexp "^set\[ \t\]+$var\[ \t\]+(\[^ \t;\]+)" $l -> v]} { lappend hits $v }
    }
    if {[llength $hits] != 1} { return -code error "expected exactly one line 'set $var <number>' in the SDC, found [llength $hits]" }
    set v [lindex $hits 0]
    if {![string is double -strict $v]} { return -code error "'set $var $v' in the SDC: '$v' is not a number" }
    return $v
}
if {[catch {set fh [open $repo_root/$sdc_rel r]} msg]} { unpu_fatal "cannot open $sdc_rel: $msg" }
set sdc_text [read $fh]
close $fh
foreach var {CLK_PERIOD CLK_UNCERT_SETUP CLK_UNCERT_HOLD} {
    if {[catch {unpu_sdc_number $sdc_text $var} val]} { unpu_fatal "cannot get $var from $sdc_rel: $val" }
    set $var $val
}

# L3: DC's scratch files go to a scratch directory, not to the repo root and not to the output directory.
set run_tag  legacy
set work_dir $repo_root/syn/out/work/$run_tag
file mkdir $work_dir
cd $work_dir
puts "Info: \[unpu\] $run_tag constraints: period $CLK_PERIOD ns, setup uncertainty $CLK_UNCERT_SETUP ns, hold uncertainty $CLK_UNCERT_HOLD ns (from $sdc_rel); scratch directory $work_dir"

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
set rtl_dir $repo_root/rtl
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

# L1: the constraints are the old ones, a pure SDC byte-identical to `git show 925bfa9:constraints/pm_unpu_top.sdc`.
set sdc_rc [read_sdc $repo_root/$sdc_rel]
# VERIFY: read_sdc returns 1 on success and 0 on failure in dc_shell (not read from a usage text); only an explicit 0 is
# treated as failure here. The clock check below is the real test.
if {$sdc_rc eq "0"} { unpu_fatal "read_sdc $sdc_rel failed (returned 0); see the Error lines above" }

# What the tool itself holds is checked: the clock must exist, and its period must be the SDC's CLK_PERIOD (L2).
if {[catch {get_clocks $clk_name} clk_obj] || [sizeof_collection $clk_obj] != 1} {
    unpu_fatal "clock $clk_name does not exist (exactly one expected) after read_sdc; the SDC did not create it"
}
# VERIFY: get_attribute <clock> period (the usage of get_attribute was not read; if it cannot be read this is a Warning, not an Error).
if {[catch {get_attribute $clk_obj period} got_period]} {
    puts "Warning: unpu DC script: cannot read the period of clock $clk_name back from the tool ($got_period); the check against $CLK_PERIOD ns was NOT done (VERIFY the attribute name)"
} elseif {![string is double -strict $got_period] || abs($got_period - $CLK_PERIOD) > 1e-9} {
    unpu_fatal "the tool holds clock period '$got_period' ns, the SDC's CLK_PERIOD is $CLK_PERIOD ns"
} else {
    puts "Info: \[unpu\] clock $clk_name period read back from the tool: $got_period ns (SDC CLK_PERIOD: $CLK_PERIOD ns) OK"
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

# CHANGED (task 064): reports go under syn/out/legacy/ (git-ignored); absolute, the script has cd'd to the scratch directory.
set rpt_dir $repo_root/syn/out/$run_tag
file mkdir $rpt_dir

# L4: the first line of every report file says which constraints made it, so a copied file is never anonymous. The header is
# written with echo, the report is appended.
set profile_line "# legacy constraints: period $CLK_PERIOD ns, setup uncertainty $CLK_UNCERT_SETUP ns, hold uncertainty $CLK_UNCERT_HOLD ns; written [clock format [clock seconds]]"
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

# unpu_check_outputs <dir> <report files> <other files> <header prefix> <header-only files>
#   Copied from constraints/stage_numbers.tcl (task 055), unchanged. Returns a list of problems (empty = OK): the directory exists;
#   its entries are exactly the report files plus the other files; every entry is a non-empty regular file; the FIRST line of every
#   report file starts with the header prefix; every report file except the header-only ones has a line after the header.
proc unpu_check_outputs {dir report_files other_files header_prefix header_only} {
    set problems {}
    if {![file isdirectory $dir]} { return [list "directory $dir does not exist"] }
    set have {}
    foreach f [glob -nocomplain -directory $dir -tails * .*] {
        if {$f eq "." || $f eq ".."} { continue }
        lappend have $f
    }
    set want [concat $report_files $other_files]
    foreach f $want { if {[lsearch -exact $have $f] < 0} { lappend problems "missing: $f" } }
    foreach f $have { if {[lsearch -exact $want $f] < 0} { lappend problems "unexpected file: $f" } }
    foreach f $want {
        if {[lsearch -exact $have $f] < 0} { continue }
        set path [file join $dir $f]
        if {![file isfile $path]} { lappend problems "not a regular file: $f"; continue }
        if {[file size $path] == 0} { lappend problems "empty: $f"; continue }
    }
    foreach f $report_files {
        set path [file join $dir $f]
        if {![file isfile $path] || [file size $path] == 0} { continue }
        set fh [open $path r]
        set first [gets $fh]
        set rest [string trim [read $fh]]
        close $fh
        if {$rest eq "" && [lsearch -exact $header_only $f] < 0} { lappend problems "$f: nothing after the profile header (the report command wrote no text)" }
        if {[string first $header_prefix $first] != 0} { lappend problems "$f: first line is not the profile header (got '[string range $first 0 60]')" }
    }
    return $problems
}

# CHANGED (task 064): check the output directory, then end the shell. syn/out/legacy/ must hold exactly the files below
# (no SDF): nothing else, none empty, every report with the header as its first line and (except .profile) some text under it.
set report_exts {profile area power timing timing_top5 constraint qor check_timing check_design}
set report_files {}
foreach e $report_exts { lappend report_files $top_module.$e }
set netlist_files [list $top_module.dc.v $top_module.sdc ${top_module}_cn.dc.v ${top_module}_cn.sdc ${top_module}_cn.ddc]
set header_expect "# legacy constraints: period $CLK_PERIOD ns, setup uncertainty $CLK_UNCERT_SETUP ns, hold uncertainty $CLK_UNCERT_HOLD ns;"
set problems [unpu_check_outputs $rpt_dir $report_files $netlist_files $header_expect [list $top_module.profile]]
if {[llength $problems] > 0} {
    foreach pr $problems { puts "Error: unpu DC script: output check: $pr" }
    unpu_fatal "the output directory $rpt_dir is not as expected ([llength $problems] problem(s) above)"
}
puts "Info: \[unpu\] DONE $run_tag: [llength $report_files] reports and [llength $netlist_files] netlist/SDC/ddc files in $rpt_dir, scratch files in $work_dir"
# VERIFY: a plain exit ends dc_shell -f with status 0 (the pipe to tee hides the status in csh anyway).
exit

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
