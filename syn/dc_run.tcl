# =============================================================================
# dc_run.tcl -- Design Compiler bring-up run for one design (task 035)
#
# Usage (csh, from syn/out/<design>; see the server block in the task report):
#   setenv DESIGN unpu_pe            ;# or unpu_top
#   dc_shell -f <repo>/syn/dc_run.tcl |& tee dc.log
#
# DESIGN must be unpu_pe or unpu_top. Everything is written under
# syn/out/$DESIGN/ (netlist, .ddc, SDC, rpt/), and that directory is the
# working directory, so default.svf, WORK/ and command.log land there too.
#
# Timing scope: DC runs the ss library only, so this run has NO hold report.
# Hold is checked in PrimeTime with the ff library. DC also knows no wire delay
# from layout, and the I/O budgets in the SDC are assumptions.
# =============================================================================

# ---- Paths: derived from this script's own location, before any cd -----------
if {[info script] eq ""} {
  puts "Error: \[unpu\] cannot determine this script's location (info script is empty)"
  exit 1
}
set SYN_DIR   [file dirname [file normalize [info script]]]
set REPO_ROOT [file dirname $SYN_DIR]

# Library, don't-use cells, unpu_die.
source [file join $SYN_DIR dc_setup.tcl]

# dc_shell keeps going after some errors by default; make it stop.
set_app_var sh_continue_on_error false

# ---- Design selection --------------------------------------------------------
if {![info exists ::env(DESIGN)] || $::env(DESIGN) eq ""} {
  unpu_die "DESIGN is not set; it must be unpu_pe or unpu_top (csh: setenv DESIGN unpu_pe)"
}
set DESIGN $::env(DESIGN)
if {$DESIGN ne "unpu_pe" && $DESIGN ne "unpu_top"} {
  unpu_die "DESIGN='$DESIGN' is not allowed; it must be unpu_pe or unpu_top"
}

# ---- RTL file lists: explicit, never globbed ---------------------------------
set RTL_FILES(unpu_pe) {unpu_pe.sv}
set RTL_FILES(unpu_top) {
  unpu_actbuf.sv unpu_apb.sv unpu_csr.sv unpu_deskew.sv unpu_dma.sv
  unpu_grid.sv unpu_pe.sv unpu_seq.sv unpu_skew.sv unpu_top.sv unpu_wbuf.sv
}

set rtl_paths {}
foreach f $RTL_FILES($DESIGN) {
  set p [file join $REPO_ROOT rtl $f]
  if {![file exists $p]} { unpu_die "RTL file missing: $p" }
  lappend rtl_paths $p
}
# A stray file in rtl/ must not be silently ignored either: say so.
foreach g [lsort [glob -nocomplain -directory [file join $REPO_ROOT rtl] *.sv]] {
  if {[lsearch -exact $rtl_paths $g] < 0 && $DESIGN eq "unpu_top"} {
    puts "Warning: \[unpu\] $g exists in rtl/ but is NOT in the unpu_top file list"
  }
}

set SDC_FILE [file join $REPO_ROOT constraints ${DESIGN}.sdc]
if {![file exists $SDC_FILE]} { unpu_die "constraint file missing: $SDC_FILE" }

# ---- Output directory; it becomes the working directory ----------------------
set OUT_DIR [file join $REPO_ROOT syn out $DESIGN]
set RPT_DIR [file join $OUT_DIR rpt]
file mkdir $OUT_DIR
file mkdir $RPT_DIR
cd $OUT_DIR
puts "Info: \[unpu\] design=$DESIGN  repo=$REPO_ROOT  out=$OUT_DIR"

# Write one report file; complain (not silently) if it comes out missing/empty.
proc unpu_rpt {name script} {
  global RPT_DIR
  set f [file join $RPT_DIR ${name}.rpt]
  redirect -file $f $script
  if {![file exists $f] || [file size $f] == 0} {
    puts "Warning: \[unpu\] report $f is missing or empty"
  }
}

# ---- Read, elaborate, link ---------------------------------------------------
if {[catch {analyze -format sverilog $rtl_paths} msg]} { unpu_die "analyze failed: $msg" }
if {[catch {elaborate $DESIGN} msg]}                   { unpu_die "elaborate failed: $msg" }
if {[catch {current_design $DESIGN} msg]}              { unpu_die "current_design failed: $msg" }
if {[catch {link} link_ok]}                            { unpu_die "link failed: $link_ok" }
if {$link_ok == 0}                                     { unpu_die "link returned 0 (unresolved reference or error); see the log" }

unpu_rpt check_design_pre {check_design}

# ---- Constraints -------------------------------------------------------------
# report_units first, so any mismatch between the SDC's set_units and the
# library's units is visible in the log. If set_units is rejected by DC, that
# error stays in the log and is counted by scripts/dc_summary.sh; it is not
# removed here.
if {[catch {report_units} msg]} {
  puts "Warning: \[unpu\] report_units failed: $msg"
}
if {[catch {read_sdc $SDC_FILE} msg]} { unpu_die "read_sdc $SDC_FILE failed: $msg" }
if {[catch {report_units} msg]} {
  puts "Warning: \[unpu\] report_units (after read_sdc) failed: $msg"
}

# ---- Compile -----------------------------------------------------------------
# Plain compile, on purpose: DC-Expert is confirmed on the licence server,
# compile_ultra needs licence features nobody has checked. No other compile
# options are added.
if {[catch {compile} msg]} { unpu_die "compile failed: $msg" }

# ---- Checks and reports (setup only; no hold, see header) --------------------
unpu_rpt check_design_post {check_design}
unpu_rpt check_timing      {check_timing}
unpu_rpt port              {report_port -verbose}
unpu_rpt clock             {report_clock}
unpu_rpt constraint        {report_constraint -all_violators}
unpu_rpt timing            {report_timing -delay_type max -max_paths 10 -nosplit}
unpu_rpt area              {report_area}
unpu_rpt power             {report_power}
unpu_rpt qor               {report_qor}
unpu_rpt hierarchy         {report_hierarchy}
unpu_rpt reference         {report_reference}

# ---- Outputs -----------------------------------------------------------------
write -format verilog -hierarchy -output [file join $OUT_DIR ${DESIGN}.v]
write -format ddc     -hierarchy -output [file join $OUT_DIR ${DESIGN}.ddc]
write_sdc [file join $OUT_DIR ${DESIGN}.sdc]

puts "Info: \[unpu\] dc_run.tcl finished for $DESIGN; next: bash scripts/dc_summary.sh $DESIGN"
exit 0
