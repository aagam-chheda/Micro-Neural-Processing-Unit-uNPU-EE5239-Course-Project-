# 03_place.tcl -- Stage 3: place every standard cell and fix timing (ideal clock).
# Run:  icc2_shell -f scripts/03_place.tcl > logs/03_place.log &
source scripts/00_vars.tcl
open_lib $DLIB
open_block $TOP/power

# no scan chain in our netlist -> tell the placer not to look for one
set_app_options -name place.coarse.continue_on_missing_scandef -value true
# same don't-use cells as synthesis
foreach pat {slnht* skbrb* slbhb* slnhn* slnln* mx08d*} {
    set c [get_lib_cells -quiet */$pat]
    if {[sizeof_collection $c] > 0} { set_dont_use $c }
}

check_design -checks pre_placement_stage > $RPT/03_pre_place_check.rpt
place_opt                                       ;# place -> optimise -> legalise
check_legality > $RPT/03_legality.rpt
connect_pg_net -automatic                       ;# new buffers get power too

report_utilization                     > $RPT/03_util.rpt
report_congestion                      > $RPT/03_congestion.rpt
report_qor -summary                    > $RPT/03_qor.rpt
report_timing -delay_type max -max_paths 10 > $RPT/03_setup.rpt

check_pg_connectivity > $RPT/03_pg_conn.rpt
save_block -as $TOP/placed
puts "STAGE 3 DONE"
exit
