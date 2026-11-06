# 02_power.tcl -- Stage 2: power ring, straps, cell rails.
# Run:  icc2_shell -f scripts/02_power.tcl > logs/02_power.log &
source scripts/00_vars.tcl
open_lib $DLIB
open_block $TOP/floorplan
lassign [get_metals] M1 M2 M3 M4

# ---- 2.1 ring around the core, inside the 20 um band -------------------------
create_pg_ring_pattern ring_pat \
    -horizontal_layer $M3 -horizontal_width 6 -horizontal_spacing 2 \
    -vertical_layer   $M4 -vertical_width   6 -vertical_spacing   2
set_pg_strategy ring_strat -core \
    -pattern {{name: ring_pat} {nets: {VDD VSS}} {offset: {2 2}}}
compile_pg -strategies ring_strat

# ---- 2.2 mesh: vertical M4 straps, sparse horizontal M3 straps ---------------
create_pg_mesh_pattern mesh_pat -layers [list \
    "{vertical_layer: $M4} {width: 4} {spacing: interleaving} {pitch: 80} {offset: 20}" \
    ]
set_pg_strategy mesh_strat -core \
    -pattern {{name: mesh_pat} {nets: {VDD VSS}}} \
    -extension {{stop: outermost_ring}}
compile_pg -strategies mesh_strat

# ---- 2.3 rails: the M1 lines along every cell row ----------------------------
create_pg_std_cell_conn_pattern rail_pat -layers [list $M1]
set_pg_strategy rail_strat -core -pattern {{name: rail_pat} {nets: {VDD VSS}}}
compile_pg -strategies rail_strat

# ---- 2.4 checks --------------------------------------------------------------
check_pg_connectivity > $RPT/02_pg_conn.rpt
check_pg_drc          > $RPT/02_pg_drc.rpt
check_pg_missing_vias > $RPT/02_pg_vias.rpt

save_block -as $TOP/power
puts "STAGE 2 DONE"
exit
