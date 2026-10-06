# =============================================================================
# pm_unpu_top.sdc -- timing constraints for unpu_top (SCL 180 nm, 50 MHz)
#
# Pure SDC: constraints only, no library setup, no don't-use cells, no
# operating condition or wire-load model, no compile options. Those stay in
# constraints/pm_dc_script_unpu.tcl, which reads this file with read_sdc.
# The same file can be read by ICC2 and PrimeTime.
#
# Contents, in order:
#   1. The PM's example constraints (clock, drive, load, I/O delays), kept as
#      given. The clock name is the literal port name `clk`, and the clock is
#      created on [get_ports clk]; the PM's "is there a clk port, else make a
#      virtual clock" fallback is script logic, not a constraint, and is dropped
#      because unpu_top has a real clk port.
#   2. The constraints from constraints/unpu_top.sdc: clock uncertainty and
#      transition, and the I/O delays with named port groups. They override the
#      PM's 0 delays on the named ports (a later set_input_delay / set_output_delay
#      on the same port and the same -max or -min wins).
#   3. NEW: input driving cell and output load. They override the PM's
#      set_drive 0 and set_load 0 on the named ports.
#
# EVERY number below except the 20 ns period (CLAUDE.md) is an ASSUMPTION,
# pending the SoC team's interface timing and loads. None may be changed to
# close timing without a written reason and the user's approval.
#
# Units: the SCL libraries declare time_unit 1ns and capacitive_load_unit
# (1, pf) (read from the ss .lib header; the ff library's time unit matches, its
# capacitance unit was not read). All times are ns and all loads are pF.
# =============================================================================

set_units -time ns -capacitance pF


# -----------------------------------------------------------------------------
# 1. The PM's constraints, as given
# -----------------------------------------------------------------------------
create_clock -name clk -period 20 [get_ports clk]

set_drive 0 [all_inputs]
set_load  0 [all_outputs]
set_input_delay  0 [all_inputs]  -clock clk
set_output_delay 0 [all_outputs] -clock clk


# -----------------------------------------------------------------------------
# 2. From constraints/unpu_top.sdc (copied by hand: if one file changes, update
#    the other)
# -----------------------------------------------------------------------------
set CLK_PERIOD        20.0   ;# 50 MHz, from CLAUDE.md; keep equal to the create_clock -period above
set CLK_UNCERT         0.5   ;# ASSUMPTION, pre-CTS margin
set CLK_TRANSITION     0.3   ;# ASSUMPTION, slew at the flop clock pins (ideal clock only)
# The APB read path prdata = f(paddr) is combinational (in to out, through the
# CSR read mux), so its budget is
#     CLK_PERIOD * (1 - APB_IN_PCT - APB_OUT_PCT) - CLK_UNCERT
# APB_IN_PCT and APB_OUT_PCT MUST therefore leave a positive budget for that
# path. With the values below it is 8 ns before uncertainty.
set APB_IN_PCT         0.3   ;# ASSUMPTION, fraction of period used outside, max input delay
set APB_OUT_PCT        0.3   ;# ASSUMPTION, fraction of period the outside needs after prdata/pready
set DMA_IN_PCT         0.3   ;# ASSUMPTION, dma_rdata, dma_ready
set DMA_OUT_PCT        0.3   ;# ASSUMPTION, dma_addr/wdata/wstrb/valid
set RST_IN_PCT         0.3   ;# ASSUMPTION, rst_n
set IN_MIN_DELAY       0.0   ;# ASSUMPTION, min input delay for hold
set OUT_MIN_DELAY      0.0   ;# ASSUMPTION, min output delay for hold

# Port groups, listed explicitly. clk is in no group.
set APB_IN_PORTS   {paddr[*] pwdata[*] pwrite psel penable}
set APB_OUT_PORTS  {prdata[*] pready}
set DMA_IN_PORTS   {dma_rdata[*] dma_ready}
set DMA_OUT_PORTS  {dma_addr[*] dma_wdata[*] dma_wstrb[*] dma_valid}
set RST_IN_PORTS   {rst_n}

set_clock_uncertainty $CLK_UNCERT [get_clocks clk]
set_clock_transition  $CLK_TRANSITION [get_clocks clk]

# Input delays. -max is the setup side, -min the hold side.
set_input_delay -clock clk -max [expr {$CLK_PERIOD * $APB_IN_PCT}] [get_ports $APB_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $APB_IN_PORTS]

set_input_delay -clock clk -max [expr {$CLK_PERIOD * $DMA_IN_PCT}] [get_ports $DMA_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $DMA_IN_PORTS]

# rst_n: an ordinary input delay, deliberately with NO set_false_path. Its
# assertion is asynchronous, but the recovery/removal checks on its release
# must stay in the analysis, so it is timed like any other input.
set_input_delay -clock clk -max [expr {$CLK_PERIOD * $RST_IN_PCT}] [get_ports $RST_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $RST_IN_PORTS]

# Output delays. -max is the setup side, -min the hold side.
set_output_delay -clock clk -max [expr {$CLK_PERIOD * $APB_OUT_PCT}] [get_ports $APB_OUT_PORTS]
set_output_delay -clock clk -min $OUT_MIN_DELAY                      [get_ports $APB_OUT_PORTS]

set_output_delay -clock clk -max [expr {$CLK_PERIOD * $DMA_OUT_PCT}] [get_ports $DMA_OUT_PORTS]
set_output_delay -clock clk -min $OUT_MIN_DELAY                      [get_ports $DMA_OUT_PORTS]


# -----------------------------------------------------------------------------
# 3. NEW: input driving cell and output load
#
# Replaces the PM's idealised boundary (set_drive 0 = an infinitely strong
# driver, set_load 0 = nothing connected) with a finite one. All of it is an
# ASSUMPTION; the SoC team has not given real numbers.
#
# Driving cell: every input is driven by a buffd2, the library's plain buffer
# (inspected: input I, output Z, function "I", area 18.82), through its output
# pin Z. A mid-size buffer is a typical stand-in for "something a few gates
# away in the SoC". clk is excluded (ideal clock, set_clock_transition above).
#
# Output load, in pF, per output port:
#   DMA outputs  0.25  dma_addr / dma_wdata / dma_wstrb / dma_valid go to the
#                      shared SRAM arbiter and a 4-bank SRAM: several input pins
#                      (about 0.01 pF each for a 180 nm cell input) plus a
#                      top-level route of roughly a millimetre (about 0.15 to
#                      0.25 pF per mm). Rounded up to 0.25.
#   APB outputs  0.10  prdata / pready go point to point to the APB interconnect:
#                      one or two input pins and a shorter route.
# The values are deliberately on the conservative side so that a driver sized for
# them is not undersized if the real load turns out lighter. Check them against
# the library: if a port's load exceeds the max_capacitance of the cell that
# ends up driving it, DC will insert buffers (visible in report_constraint).
# -----------------------------------------------------------------------------
set DRIVE_CELL       buffd2  ;# ASSUMPTION, plain buffer standing in for the outside driver
set DRIVE_PIN        Z       ;# output pin of buffd2 (verified in the ss .lib)
set DMA_OUT_LOAD     0.25    ;# ASSUMPTION, pF, shared SRAM bus: several pins + about 1 mm of route
set APB_OUT_LOAD     0.10    ;# ASSUMPTION, pF, point-to-point to the APB interconnect

set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $APB_IN_PORTS]
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $DMA_IN_PORTS]
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $RST_IN_PORTS]

set_load $APB_OUT_LOAD [get_ports $APB_OUT_PORTS]
set_load $DMA_OUT_LOAD [get_ports $DMA_OUT_PORTS]
