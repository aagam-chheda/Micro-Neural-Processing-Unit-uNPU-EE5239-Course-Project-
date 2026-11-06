# 06_outputs.tcl -- Stage 6: write every file the next steps and the top team need.
# Run:  icc2_shell -f scripts/06_outputs.tcl > logs/06_outputs.log &
source scripts/00_vars.tcl
open_lib $DLIB
open_block $TOP/routed

# netlist for STA (no power pins, no fillers)
write_verilog -exclude {pg_objects physical_only_cells} $OUT/${TOP}_pnr.v
# netlist for LVS (with VDD/VSS connections and every cell)
write_verilog -include {pg_netlist} $OUT/${TOP}_pnr_pg.v
# wire resistance/capacitance for PrimeTime, one SPEF per corner
write_parasitics -output $OUT/${TOP}
# constraints as ICC2 sees them now
write_sdc -output $OUT/${TOP}_pnr.sdc
# placement + routing in text form
write_def $OUT/${TOP}.def
# abstract for the top-level team (replaces the dummy LEF)
write_lef -design $TOP $OUT/${TOP}.lef
# the layout itself, with the std-cell insides merged in
write_gds -design $TOP -layer_map $GDS_MAP -merge_files [list $STD_GDS] \
          -long_names $OUT/${TOP}.gds

puts "STAGE 6 DONE"
exit
