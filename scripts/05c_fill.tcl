source scripts/00_vars.tcl
open_lib $DLIB
set_ref_libs -add pnr/scl_fill.ndm
open_block $TOP/routed
set fillers [get_lib_cells scl_fill/feedth*]
puts "INFO fillers available: [get_object_name $fillers]"
create_stdcell_fillers -lib_cells $fillers
connect_pg_net -automatic
remove_stdcell_fillers_with_violation
check_routes              > $RPT/05c_check_routes.rpt
check_lvs -max_errors 100 > $RPT/05c_check_lvs.rpt
check_pg_connectivity     > $RPT/05c_pg_conn.rpt
report_utilization        > $RPT/05c_util.rpt
save_block
save_lib
puts "STAGE 5c DONE"
exit
