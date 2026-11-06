# 05_route.tcl -- Stage 5: route all signal nets, optimise, add fillers.
# Run:  icc2_shell -f scripts/05_route.tcl > logs/05_route.log &
source scripts/00_vars.tcl
open_lib $DLIB
open_block $TOP/cts

check_routability > $RPT/05_routability.rpt

# ---- 5.1 route ---------------------------------------------------------------
set_app_options -name route.global.timing_driven    -value true
set_app_options -name route.track.timing_driven     -value true
set_app_options -name route.detail.timing_driven    -value true
route_auto -max_detail_route_iterations 40     ;# global -> track -> detail
route_opt                                      ;# fix timing with real wires
connect_pg_net -automatic

# ---- 5.2 fillers: close the gaps in every row --------------------------------
set fillers [get_lib_cells -quiet */feedth*]
puts "INFO filler cells: [get_object_name $fillers]"
if {[sizeof_collection $fillers] > 0} {
    create_stdcell_fillers -lib_cells $fillers
    connect_pg_net -automatic
    remove_stdcell_fillers_with_violation
}

# ---- 5.3 checks --------------------------------------------------------------
check_routes          > $RPT/05_check_routes.rpt   ;# DRC, opens, antenna
check_lvs -max_errors 100 > $RPT/05_check_lvs.rpt   ;# shorts/opens vs netlist
check_pg_connectivity > $RPT/05_pg_conn.rpt
report_qor -summary   > $RPT/05_qor.rpt
report_timing -delay_type max -max_paths 10 > $RPT/05_setup.rpt
report_timing -delay_type min -max_paths 10 > $RPT/05_hold.rpt
report_utilization    > $RPT/05_util.rpt

save_block -as $TOP/routed
puts "STAGE 5 DONE"
exit
