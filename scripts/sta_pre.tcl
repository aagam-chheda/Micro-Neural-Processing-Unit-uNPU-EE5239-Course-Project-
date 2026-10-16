# Pre-layout STA, ss corner (setup)
set KIT /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180
set search_path ". $KIT/stdcell/fs120/4M1IL/liberty/lib_flow_ss"
set link_path   "* tsl18fs120_scl_ss.db"

read_verilog syn/out/unpu_top_cn.dc.v
current_design unpu_top
link_design

read_sdc constraints/pm_unpu_top.sdc
set_wire_load_model -name 140000 -library tsl18fs120_scl_ss

set R sta
check_timing -verbose                  > $R/check_timing.rpt
report_clock                           > $R/clocks.rpt
report_analysis_coverage               > $R/coverage.rpt
report_global_timing                   > $R/global.rpt
report_constraint -all_violators       > $R/violators.rpt
report_timing -delay_type max -max_paths 10 -input_pins -nets > $R/setup.rpt
report_timing -delay_type min -max_paths 10                   > $R/hold.rpt
report_qor                             > $R/qor.rpt
exit
