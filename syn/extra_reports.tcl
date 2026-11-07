# =============================================================================
# syn/extra_reports.tcl -- reports scripts/synth.tcl does not write
#
# scripts/synth.tcl's report_timing lists the 10 worst setup paths, and with
# the harsh APB budget all 10 are paddr -> prdata. The register-to-register
# paths (the PE multiply-accumulate, +1.80 ns in the 14 Oct run) never appear.
# This script reopens the finished design and writes them, plus input->reg,
# reg->output and the high-fanout nets.
#
# Run from the repo root AFTER scripts/synth.tcl (csh):
#     dc_shell -f syn/extra_reports.tcl |& tee logs/dc_extra.log
#
# Reads syn/out/unpu_top_cn.ddc (it carries the constraints, operating
# condition and wire-load model). Writes syn/out/timing_*.rpt and
# syn/out/high_fanout.rpt. Nothing in the design is changed or rewritten.
# =============================================================================

set target_library "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db"
set link_library   "* $target_library dw_foundation.sldb"

read_ddc syn/out/unpu_top_cn.ddc
current_design unpu_top
link

set rpt_dir syn/out
report_timing -from [all_registers -clock_pins] -to [all_registers -data_pins] \
              -delay_type max -max_paths 10 -nosplit      > $rpt_dir/timing_reg2reg.rpt
report_timing -from [all_inputs] -to [all_registers -data_pins] \
              -delay_type max -max_paths 5 -nosplit       > $rpt_dir/timing_in2reg.rpt
report_timing -from [all_registers -clock_pins] -to [all_outputs] \
              -delay_type max -max_paths 5 -nosplit       > $rpt_dir/timing_reg2out.rpt
report_net_fanout -high_fanout                            > $rpt_dir/high_fanout.rpt
exit
