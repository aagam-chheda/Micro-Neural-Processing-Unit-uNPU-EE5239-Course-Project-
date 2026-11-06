source scripts/00_vars.tcl
open_lib $DLIB
open_block $TOP/routed
puts "INFO lib cells named feed*: [get_object_name [get_lib_cells -quiet */feed*]]"
puts "INFO total lib cells in NDM: [sizeof_collection [get_lib_cells */*]]"
route_opt
connect_pg_net -automatic
set fillers [get_lib_cells -quiet */feed*]
if {[sizeof_collection $fillers] > 0} {
    create_stdcell_fillers -lib_cells $fillers
    connect_pg_net -automatic
    remove_stdcell_fillers_with_violation
} else {
    puts "WARN no feedth cells in the reference NDM"
}
check_routes              > $RPT/05b_check_routes.rpt
check_lvs -max_errors 100 > $RPT/05b_check_lvs.rpt
check_pg_connectivity     > $RPT/05b_pg_conn.rpt
report_qor -summary       > $RPT/05b_qor.rpt
report_timing -delay_type max -max_paths 5 > $RPT/05b_setup.rpt
report_timing -delay_type min -max_paths 5 > $RPT/05b_hold.rpt
save_block
puts "STAGE 5b DONE"
exit
EOF


