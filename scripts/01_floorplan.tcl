# 01_floorplan.tcl -- Stage 1: design setup, timing scenarios, die box, pins.
# Run:  icc2_shell -f scripts/01_floorplan.tcl > logs/01_floorplan.log &
source scripts/00_vars.tcl

# ---- 1.1 design library + netlist -------------------------------------------
if {[file exists $DLIB]} { file delete -force $DLIB }      ;# start clean every run
create_lib $DLIB -technology $TF -ref_libs $REF_NDM
read_verilog -top $TOP $NETLIST
current_block $TOP
link_block                                                 ;# every gate -> a library cell
lassign [get_metals] M1 M2 M3 M4

# ---- 1.2 power nets ----------------------------------------------------------
create_net -power  VDD
create_net -ground VSS
connect_pg_net -automatic                                  ;# every cell's VDD/VSS pin -> net

# ---- 1.3 wire model + two timing scenarios -----------------------------------
read_parasitic_tech -name typ -tlup $TLU_TYP -layermap $TLU_MAP
create_mode   func
create_corner ss
create_corner ff
create_scenario -name func_ss -mode func -corner ss
create_scenario -name func_ff -mode func -corner ff

current_scenario func_ss
read_sdc $SDC
current_scenario func_ff
read_sdc $SDC

set_parasitic_parameters -corners {ss ff} -early_spec typ -late_spec typ
set_temperature 125   -corners ss
set_voltage     1.62  -corners ss -object_list VDD
set_voltage     0     -corners ss -object_list VSS
set_temperature -40   -corners ff
set_voltage     1.98  -corners ff -object_list VDD
set_voltage     0     -corners ff -object_list VSS

# setup checked at slow corner, hold at fast corner
set_scenario_status func_ss -active true -setup true  -hold false -leakage_power true -dynamic_power true
set_scenario_status func_ff -active true -setup false -hold true
current_scenario func_ss
report_pvt > $RPT/01_pvt.rpt                                ;# must show no PVT mismatch

# ---- 1.4 the box -------------------------------------------------------------
initialize_floorplan -control_type die \
    -boundary [list {0 0} [list $DIE_W $DIE_H]] -core_offset $CORE_OFFSET
report_utilization > $RPT/01_util.rpt
catch {puts "DIE  bbox: [get_attribute [current_block] boundary_bounding_box]"}
catch {puts "CORE bbox: [get_attribute [get_core_area] bounding_box]"}

# ---- 1.5 routing layers allowed for signals ----------------------------------
set_ignored_layers -min_routing_layer $M1 -max_routing_layer $M4

# ---- 1.6 pins: side 1 = left, 2 = top, 3 = right, 4 = bottom -----------------
set_individual_pin_constraints \
    -ports [get_ports {clk rst_n psel penable pwrite paddr* pwdata* prdata* pready}] \
    -sides 2 -allowed_layers $M2
set_individual_pin_constraints -ports [get_ports dma_*] -sides 3 -allowed_layers $M3
place_pins -self
check_pin_placement -self > $RPT/01_pins.rpt
catch {puts "terminals placed: [sizeof_collection [get_terminals]]  (expect 204)"}

# ---- 1.7 tap cells (only if the library has them) ----------------------------
set taps [get_lib_cells -quiet */*tap*]
if {[sizeof_collection $taps] > 0} {
    create_tap_cells -lib_cell [index_collection $taps 0] -distance 30 -pattern stagger
    puts "INFO tap cells added: [get_object_name [index_collection $taps 0]]"
} else {
    puts "INFO no tap cells in library -> skipped (normal for this 180 nm kit)"
}

save_block -as $TOP/floorplan
puts "STAGE 1 DONE"
exit
