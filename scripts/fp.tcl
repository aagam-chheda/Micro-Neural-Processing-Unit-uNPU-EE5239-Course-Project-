# =============================================================================
# fp.tcl -- uNPU floorplan, runbook Steps 6.1 to 6.6, batch mode
#
# Run from the unpu_flow folder (csh), in the BACKGROUND, with no keyboard:
#   icc2_shell -f scripts/fp.tcl < /dev/null >& logs/fp.log &
#   tail -f logs/fp.log          (Ctrl+C only stops watching, not ICC2)
#
# "< /dev/null" means ICC2 never waits for typing: if any command fails, the
# script stops there and ICC2 exits by itself. The log then shows the last
# "######## STEP" line reached and the Error just after it.
# Reports go to pnr/rpt/. Snapshots are saved after every step.
# =============================================================================

set KIT /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180
set PNR $KIT/digital_pnr_kit/snps/non_rh/4M1L
set RPT pnr/rpt
file mkdir $RPT

proc step {name} { puts "\n######## STEP $name ########\n" }

# -----------------------------------------------------------------------------
step "6.1 design library, netlist, link"
# -----------------------------------------------------------------------------
if {[file exists pnr/unpu_lib]} { file delete -force pnr/unpu_lib }
create_lib pnr/unpu_lib -technology $PNR/SCL_4LM.tf -ref_libs pnr/scl_fs120.ndm
read_verilog -top unpu_top syn/out/unpu_top_cn.dc.v
link_block
save_block -as unpu_top/s1_linked

# -----------------------------------------------------------------------------
step "6.2 supply nets, wire model, timing scenario"
# -----------------------------------------------------------------------------
create_net -power  VDD
create_net -ground VSS
connect_pg_net -automatic

read_parasitic_tech -name typ -tlup $PNR/SCL_TLUPLUS_4M1L_TYP.tlup -layermap $PNR/SCL_TLUPLUS_4M1L.map

create_mode   func
create_corner ss
create_scenario -name func_ss -mode func -corner ss
current_scenario func_ss
read_sdc constraints/pm_unpu_top.sdc
set_parasitic_parameters -corners ss -early_spec typ -late_spec typ
set_temperature 125  -corners ss
set_voltage     1.62 -corners ss -object_list VDD
set_voltage     0    -corners ss -object_list VSS
set_scenario_status func_ss -active true -setup true -hold false
report_pvt > $RPT/pvt.rpt
save_block -as unpu_top/s2_timing

# -----------------------------------------------------------------------------
step "6.3 floorplan box and rows"
# -----------------------------------------------------------------------------
initialize_floorplan -boundary {{0 0} {820.4 823.2}} -core_offset {20}
report_utilization > $RPT/util.rpt
save_block -as unpu_top/s3_box

# -----------------------------------------------------------------------------
step "6.4 pins: APB+clk+rst on top (M2), DMA on right (M3)"
# -----------------------------------------------------------------------------
set top_ports [get_ports {clk rst_n paddr* pwdata* pwrite psel penable prdata* pready}]
set dma_ports [get_ports {dma_*}]
puts "top-edge ports: [sizeof_collection $top_ports]  right-edge ports: [sizeof_collection $dma_ports]"
set_block_pin_constraints -self -allowed_layers {M2 M3}
set_individual_pin_constraints -ports $top_ports -sides 2 -allowed_layers M2
set_individual_pin_constraints -ports $dma_ports -sides 3 -allowed_layers M3
place_pins -self
check_pin_placement > $RPT/pins_check.rpt
save_block -as unpu_top/s4_pins

# -----------------------------------------------------------------------------
step "6.5 power: ring (M3/TOP_M), TOP_M stripes, M1 rails"
# -----------------------------------------------------------------------------
create_pg_ring_pattern core_ring -horizontal_layer M3 -horizontal_width 5 \
    -vertical_layer TOP_M -vertical_width 5 -horizontal_spacing 2 -vertical_spacing 2
set_pg_strategy ring_s -core -pattern {{name: core_ring} {nets: {VDD VSS}} {offset: {3 3}}}

create_pg_mesh_pattern mesh -layers {{{vertical_layer: TOP_M} {width: 2} {spacing: interleaving} {pitch: 40} {offset: 20}}}
set_pg_strategy mesh_s -core -pattern {{name: mesh} {nets: {VDD VSS}}}

create_pg_std_cell_conn_pattern rails -layers {M1}
set_pg_strategy rail_s -core -pattern {{name: rails} {nets: {VDD VSS}}}

compile_pg -strategies {ring_s mesh_s rail_s}
save_block -as unpu_top/s5_power

# -----------------------------------------------------------------------------
step "6.6 checks and final save"
# -----------------------------------------------------------------------------
check_pg_connectivity                  > $RPT/pg_connectivity.rpt
check_pg_drc                           > $RPT/pg_drc.rpt
check_pg_missing_vias                  > $RPT/pg_missing_vias.rpt
check_design -checks pre_placement_stage > $RPT/check_design_preplace.rpt
report_utilization                     > $RPT/util_final.rpt
save_block -as unpu_top/floorplan
save_lib

puts "\n######## FP_DONE: all steps 6.1 to 6.6 finished ########\n"
exit

