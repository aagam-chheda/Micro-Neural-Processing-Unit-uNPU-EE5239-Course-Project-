# sim/waves.tcl -- batch waveform dump for any uNPU testbench under Xcelium.
#
# Usage (from the repo root), add to any xrun command line:
#     -input sim/waves.tcl
# Then open the result with:
#     simvision waves.shm &
#
# Probing the whole hierarchy of a long testbench (unpu_top_tb runs
# 138 ms of simulated time) makes a very large database. For those, change
# "-depth all" to e.g. "-depth 3", or comment out the probe line and probe
# by hand in the GUI instead.

database -open waves -shm -default
probe -create -all -depth all -database waves
run
database -close waves
exit
