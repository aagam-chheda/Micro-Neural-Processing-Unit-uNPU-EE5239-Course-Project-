# 07_sta.tcl -- Stage 7: post-layout STA in PrimeTime, one corner per run.
# Run twice:
#   pt_shell -f scripts/07_sta.tcl -x "set CORNER ss" > logs/07_sta_ss.log
#   pt_shell -f scripts/07_sta.tcl -x "set CORNER ff" > logs/07_sta_ff.log
source scripts/00_vars.tcl
if {![info exists CORNER]} { set CORNER ss }
if {$CORNER eq "ss"} { set DB $DB_SS } else { set DB $DB_FF }

set_app_var search_path ". [file dirname $DB]"
set_app_var link_path   "* $DB"
read_verilog $OUT/${TOP}_pnr.v
current_design $TOP
link_design

read_sdc $OUT/${TOP}_pnr.sdc
set spef [glob -nocomplain $OUT/${TOP}*${CORNER}*.spef* $OUT/${TOP}*.spef*]
puts "INFO SPEF used: [lindex $spef 0]"
read_parasitics -format SPEF [lindex $spef 0]
set_propagated_clock [all_clocks]               ;# real clock tree delays

update_timing -full
report_parasitic_annotation                         > $RPT/07_${CORNER}_annot.rpt
check_timing -verbose                               > $RPT/07_${CORNER}_check.rpt
report_global_timing                                > $RPT/07_${CORNER}_global.rpt
report_constraint -all_violators                    > $RPT/07_${CORNER}_violators.rpt
report_timing -delay_type max -max_paths 10         > $RPT/07_${CORNER}_setup.rpt
report_timing -delay_type min -max_paths 10         > $RPT/07_${CORNER}_hold.rpt
exit
