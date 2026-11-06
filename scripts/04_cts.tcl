# 04_cts.tcl -- Stage 4: build the clock tree, then fix setup AND hold.
# Run:  icc2_shell -f scripts/04_cts.tcl > logs/04_cts.log &
source scripts/00_vars.tcl
open_lib $DLIB
open_block $TOP/placed
lassign [get_metals] M1 M2 M3 M4

# ---- 4.1 which cells may build the tree --------------------------------------
set cts_cells [get_lib_cells -quiet {*/buf* */inv* */clkbuf* */clkinv*}]
puts "INFO CTS cell count: [sizeof_collection $cts_cells]  (must be > 0)"
set_lib_cell_purpose -include cts $cts_cells

# ---- 4.2 targets -------------------------------------------------------------
set_clock_tree_options -target_skew 0.2 -target_latency 1.0
# clock wires on the upper layers (less resistance), double spacing
create_routing_rule clk_ndr -multiplier_spacing 2
set_clock_routing_rules -rules clk_ndr -min_routing_layer $M3 -max_routing_layer $M4

check_clock_trees > $RPT/04_pre_cts_check.rpt

# ---- 4.3 build + route clock + optimise --------------------------------------
clock_opt                                      ;# build tree, route clock nets, final opt
connect_pg_net -automatic

report_clock_qor                         > $RPT/04_clock_qor.rpt
report_clock_timing -type skew           > $RPT/04_skew.rpt
report_qor -summary                      > $RPT/04_qor.rpt
report_timing -delay_type max -max_paths 10 > $RPT/04_setup.rpt
report_timing -delay_type min -max_paths 10 > $RPT/04_hold.rpt

save_block -as $TOP/cts
puts "STAGE 4 DONE"
exit
