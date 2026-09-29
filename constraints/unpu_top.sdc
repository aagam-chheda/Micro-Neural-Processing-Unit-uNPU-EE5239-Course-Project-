# =============================================================================
# unpu_top.sdc -- timing constraints for the unpu_top hard macro
#
# Purpose
#   The SDC timing contract for unpu_top (rtl/unpu_top.sv): one clock and the
#   input/output delays on every port. TIMING CONSTRAINTS ONLY -- no libraries,
#   no don't-use cells, no operating corner, no compile options. Those belong
#   to the synthesis script (a later task).
#
# Who reads this file
#   The same file is read by Design Compiler (dc_shell), ICC2 (icc2_shell) and
#   PrimeTime (pt_shell); see docs/session-handoff.md section 18. It has not
#   yet been read by any of them: it was written and checked statically only.
#
# Time unit
#   Values are written in library time units. The SCL libraries (tsl18fs120)
#   use ns, so every number below is in ns. A delay expressed as a fraction of
#   the period is period * fraction, also in ns.
#
# ASSUMPTIONS -- read this before trusting any number
#   The clock period is a project fact (CLAUDE.md, 50 MHz). EVERYTHING ELSE in
#   the variable block is a PLACEHOLDER ASSUMPTION, chosen before any timing
#   result existed, pending the interface timing from the PM / SoC team:
#     1. CLK_UNCERT      pre-CTS clock uncertainty margin.
#     2. APB_IN_PCT      share of the period the outside world uses before
#                        paddr/pwdata/pwrite/psel/penable arrive.
#     3. APB_OUT_PCT     share of the period the outside world needs after
#                        prdata/pready leave.
#     4. DMA_IN_PCT      same, for dma_rdata / dma_ready.
#     5. DMA_OUT_PCT     same, for dma_addr/dma_wdata/dma_wstrb/dma_valid.
#     6. RST_IN_PCT      same, for rst_n.
#     7. IN_MIN_DELAY / OUT_MIN_DELAY   hold-side (min) delays.
#   These values must NEVER be changed to close timing. Changing one needs a
#   written reason and the user's approval.
#
# NOT SET by this file (open items, not forgotten)
#   - set_driving_cell : NOT SET. Needs a buffer cell name from the SCL
#                        library; none is known here and none is guessed.
#   - set_load         : NOT SET. Needs the capacitive load each output drives,
#                        which the SoC team has not given.
#   - The interface budget above is assumed, not agreed.
#   - No set_false_path / set_multicycle_path: none is needed. One clock, no
#     clock-domain crossings.
#
# After CTS
#   This file describes an ideal clock (no latency, no network delay). After
#   clock-tree synthesis the clock becomes propagated (set_propagated_clock)
#   and CLK_UNCERT is revisited. Those commands are deliberately not in this
#   file.
# =============================================================================


# -----------------------------------------------------------------------------
# Variable block. Every number used below this block comes from here.
# -----------------------------------------------------------------------------
set CLK_PERIOD        20.0   ;# 50 MHz, from CLAUDE.md
set CLK_UNCERT         0.5   ;# ASSUMPTION, pre-CTS margin
# The APB read path prdata = f(paddr) is combinational (in to out, through the
# CSR read mux), so its budget is
#     CLK_PERIOD * (1 - APB_IN_PCT - APB_OUT_PCT) - CLK_UNCERT
# APB_IN_PCT and APB_OUT_PCT MUST therefore leave a positive budget for that
# path. With the values below it is 8 ns before uncertainty. Whoever tunes
# these two numbers: check this formula first. It is not asserted or forced
# with set_max_delay here; this comment is the warning.
set APB_IN_PCT         0.3   ;# ASSUMPTION, fraction of period used outside, max input delay
set APB_OUT_PCT        0.3   ;# ASSUMPTION, fraction of period the outside needs after prdata/pready
set DMA_IN_PCT         0.3   ;# ASSUMPTION, dma_rdata, dma_ready
set DMA_OUT_PCT        0.3   ;# ASSUMPTION, dma_addr/wdata/wstrb/valid
set RST_IN_PCT         0.3   ;# ASSUMPTION, rst_n
set IN_MIN_DELAY       0.0   ;# ASSUMPTION, min input delay for hold
set OUT_MIN_DELAY      0.0   ;# ASSUMPTION, min output delay for hold


# -----------------------------------------------------------------------------
# Port groups, listed explicitly. all_inputs / all_outputs are NOT used, so a
# port added to unpu_top later shows up as unconstrained in check_timing
# instead of being covered silently. clk is in no group: it gets no input
# delay.
# -----------------------------------------------------------------------------
set APB_IN_PORTS   {paddr[*] pwdata[*] pwrite psel penable}
set APB_OUT_PORTS  {prdata[*] pready}
set DMA_IN_PORTS   {dma_rdata[*] dma_ready}
set DMA_OUT_PORTS  {dma_addr[*] dma_wdata[*] dma_wstrb[*] dma_valid}
set RST_IN_PORTS   {rst_n}


# -----------------------------------------------------------------------------
# Clock: one clock, ideal (pre-CTS), no latency.
# -----------------------------------------------------------------------------
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty $CLK_UNCERT [get_clocks clk]


# -----------------------------------------------------------------------------
# Input delays. -max is the setup side, -min the hold side.
# -----------------------------------------------------------------------------
set_input_delay -clock clk -max [expr {$CLK_PERIOD * $APB_IN_PCT}] [get_ports $APB_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $APB_IN_PORTS]

set_input_delay -clock clk -max [expr {$CLK_PERIOD * $DMA_IN_PCT}] [get_ports $DMA_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $DMA_IN_PORTS]

# rst_n: an ordinary input delay, deliberately with NO set_false_path. Its
# assertion is asynchronous, but the recovery/removal checks on its release
# must stay in the analysis, so it is timed like any other input.
set_input_delay -clock clk -max [expr {$CLK_PERIOD * $RST_IN_PCT}] [get_ports $RST_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $RST_IN_PORTS]


# -----------------------------------------------------------------------------
# Output delays. -max is the setup side, -min the hold side.
# -----------------------------------------------------------------------------
set_output_delay -clock clk -max [expr {$CLK_PERIOD * $APB_OUT_PCT}] [get_ports $APB_OUT_PORTS]
set_output_delay -clock clk -min $OUT_MIN_DELAY                      [get_ports $APB_OUT_PORTS]

set_output_delay -clock clk -max [expr {$CLK_PERIOD * $DMA_OUT_PCT}] [get_ports $DMA_OUT_PORTS]
set_output_delay -clock clk -min $OUT_MIN_DELAY                      [get_ports $DMA_OUT_PORTS]


# -----------------------------------------------------------------------------
# Deliberately not set (see header). Left commented so the gap is visible.
# Do not fill in a guess: the cell name comes from the SCL library, the load
# from the SoC team.
# -----------------------------------------------------------------------------
# set_driving_cell -lib_cell <TODO cell> [get_ports $APB_IN_PORTS]
# set_driving_cell -lib_cell <TODO cell> [get_ports $DMA_IN_PORTS]
# set_driving_cell -lib_cell <TODO cell> [get_ports $RST_IN_PORTS]
# set_load <TODO load> [get_ports $APB_OUT_PORTS]
# set_load <TODO load> [get_ports $DMA_OUT_PORTS]
