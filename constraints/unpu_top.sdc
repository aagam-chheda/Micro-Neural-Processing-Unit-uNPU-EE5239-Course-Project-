# =============================================================================
# unpu_top.sdc -- timing constraints for the unpu_top hard macro
#
# Purpose
#   The SDC timing contract for unpu_top (rtl/unpu_top.sv): one clock, the
#   input/output delays on every port, and the boundary driver and loads.
#   TIMING CONSTRAINTS ONLY -- no libraries,
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
#     1. CLK_UNCERT_SETUP / CLK_UNCERT_HOLD   pre-CTS clock uncertainty margins.
#     2. APB_IN_PCT      share of the period the outside world uses before
#                        paddr/pwdata/pwrite/psel/penable arrive.
#     3. APB_OUT_PCT     share of the period the outside world needs after
#                        prdata/pready leave.
#     4. DMA_IN_PCT      same, for dma_rdata / dma_ready.
#     5. DMA_OUT_PCT     same, for dma_addr/dma_wdata/dma_wstrb/dma_valid.
#     6. RST_IN_PCT      same, for rst_n.
#     7. IN_MIN_DELAY / OUT_MIN_DELAY   hold-side (min) delays.
#   Plus the clock transition, the input driving cell, the input wire load and
#   the max transition / max capacitance limits (section 'Boundary' below).
#   The 1 pF output load is the course instructor's value, not an assumption.
#   The assumptions are deliberately HARSH (pessimistic): timing that closes
#   here has margin.
#   These values must NEVER be changed to close timing. Changing one needs a
#   written reason and the user's approval.
#
# NOT SET by this file (open items, not forgotten)
#   - The interface budget above is assumed, not agreed.
#   - No set_false_path / set_multicycle_path: none is needed. One clock, no
#     clock-domain crossings.
#
# After CTS
#   This file describes an ideal clock (no latency, no network delay). After
#   clock-tree synthesis the clock becomes propagated (set_propagated_clock)
#   and CLK_UNCERT_SETUP/HOLD are revisited. Those commands are deliberately not in this
#   file.
# =============================================================================


# -----------------------------------------------------------------------------
# Units. The ss library (tsl18fs120_scl_ss) declares time_unit : 1ns and
# capacitive_load_unit (1, pf) (read from its .lib header on the server): every
# time below is in ns and every load in pF. The ff library's header has NOT been
# read; it is assumed to match and must be confirmed before PrimeTime.
# -----------------------------------------------------------------------------
set_units -time ns -capacitance pF


# -----------------------------------------------------------------------------
# Variable block. Every number used below this block comes from here.
# -----------------------------------------------------------------------------
set CLK_PERIOD        20.0   ;# 50 MHz, from CLAUDE.md; keep equal to the create_clock -period above
set CLK_UNCERT_SETUP   1.5   ;# HARSH ASSUMPTION, setup margin: jitter ~0.5 + skew ~1.0 (7.5% of the period)
set CLK_UNCERT_HOLD    0.5   ;# HARSH ASSUMPTION, hold margin: skew only, jitter does not hurt hold
set CLK_TRANSITION     0.6   ;# HARSH ASSUMPTION, slew at the flop clock pins (ideal clock only)
# The APB read path prdata = f(paddr) is combinational (in to out, through the
# CSR read mux), so its budget is
#     CLK_PERIOD * (1 - APB_IN_PCT - APB_OUT_PCT) - CLK_UNCERT_SETUP
# APB_IN_PCT and APB_OUT_PCT MUST therefore leave a positive budget for that
# path. With the values below it is 6 ns before uncertainty, 4.5 ns after.
set APB_IN_PCT         0.35  ;# HARSH ASSUMPTION, fraction of period used outside, max input delay
set APB_OUT_PCT        0.35  ;# HARSH ASSUMPTION, fraction of period the outside needs after prdata/pready
set DMA_IN_PCT         0.4   ;# HARSH ASSUMPTION, dma_rdata, dma_ready
set DMA_OUT_PCT        0.4   ;# HARSH ASSUMPTION, dma_addr/wdata/wstrb/valid
set RST_IN_PCT         0.4   ;# HARSH ASSUMPTION, rst_n
set IN_MIN_DELAY       0.0   ;# HARSH ASSUMPTION, input may change right at the clock edge (the earliest possible)
set OUT_MIN_DELAY     -0.5   ;# HARSH ASSUMPTION, the outside needs outputs held 0.5 ns after the edge (min output delay = minus its hold time)


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
set_clock_uncertainty -setup $CLK_UNCERT_SETUP [get_clocks clk]
set_clock_uncertainty -hold  $CLK_UNCERT_HOLD  [get_clocks clk]

# Clock slew. Without this an ideal clock has a perfectly square edge at every
# flop clock pin, so the tool reads setup/hold/clk-Q from the most optimistic
# entries in the library tables. This forces a finite transition instead. It
# applies ONLY while the clock is ideal: after set_propagated_clock in ICC2 the
# real computed transitions are used and this is ignored.
# The value has no measured basis yet. Check the library's own limit with
#   grep -m2 -E 'default_max_transition|max_transition' <ss .lib>
# and keep this well under it; a clock tree is normally built far tighter than
# the data-net limit.
set_clock_transition $CLK_TRANSITION [get_clocks clk]


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
# Boundary: input driver, wire loads, output load, max limits
#
# Gives the boundary a finite driver and finite loads (the PM's idealised
# set_drive 0 and set_load 0 were removed). All of it is an assumption; the
# SoC team has not given real numbers. The output load is the instructor's
# value; everything else is mine.
#
# a) Driving cell: every data input is driven by a buffd1, the weakest of the
#    library's plain buffers (family buffd1/2/3/4/7/da; buffd2 was inspected:
#    input I, output Z, function "I"). A weak driver gives slow input edges
#    and a larger driver delay, the pessimistic side. buffd1 is ASSUMED to
#    have the same pin names as buffd2; that has not been read from the .lib
#    (if DC reports it cannot find pin Z on buffd1, fix it here). The input
#    slew is whatever buffd1 produces into the net below; there is deliberately
#    no set_input_transition on top. clk is excluded (ideal clock, see
#    set_clock_transition above).
#
# b) Input wire load: 0.2 pF on every data input net, roughly 1 mm of 180 nm
#    route (about 0.2 fF/um), so the driver sees a long wire and not an empty
#    pin. HARSH ASSUMPTION.
#
# c) Output load: 1 pF on every output port, the value suggested by the course
#    instructor. It is deliberately conservative: roughly a hundred 180 nm cell
#    inputs (about 0.01 pF each) or several millimetres of route, much heavier
#    than a realistic SoC-level load. A design that meets timing at 1 pF has
#    margin if the real load is lighter. Expect DC to upsize or buffer the
#    output cells, which costs some area, and each output path to slow by
#    roughly a nanosecond at the ss corner. Never lower this to close timing
#    without a written reason and the user's approval.
#
# d) Design-wide max transition 1.0 ns and max capacitance 2.0 pF: deliberately
#    tighter than the PM's own commented-out lines (set_max_transition 2,
#    set_max_capacitance 5, from a different technology). They are not checked
#    against the SCL library. The library's own default_max_transition and each
#    pin's max_capacitance still apply, and where they are tighter they win, so
#    these can only tighten the limits, never loosen them. Check the library with
#        grep -m3 -E 'default_max_transition|default_max_capacitance' <ss .lib>
#    The 1 pF output load sits under the 2.0 pF cap; keep MAX_CAPACITANCE above
#    OUT_LOAD or every output is a violation by construction.
# -----------------------------------------------------------------------------
set DRIVE_CELL       buffd1  ;# ASSUMPTION, weakest plain buffer standing in for the outside driver
set DRIVE_PIN        Z       ;# output pin; verified for buffd2 in the ss .lib, assumed for buffd1
set IN_WIRE_LOAD     0.2     ;# pF, HARSH ASSUMPTION, wire on every data input net
set OUT_LOAD         1.0     ;# pF, every output port; the instructor's suggested value
set MAX_TRANSITION   1.0     ;# ns, HARSH ASSUMPTION
set MAX_CAPACITANCE  2.0     ;# pF, HARSH ASSUMPTION

set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $APB_IN_PORTS]
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $DMA_IN_PORTS]
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $RST_IN_PORTS]

set_load $IN_WIRE_LOAD [get_ports $APB_IN_PORTS]
set_load $IN_WIRE_LOAD [get_ports $DMA_IN_PORTS]
set_load $IN_WIRE_LOAD [get_ports $RST_IN_PORTS]

set_load $OUT_LOAD [get_ports $APB_OUT_PORTS]
set_load $OUT_LOAD [get_ports $DMA_OUT_PORTS]

set_max_transition  $MAX_TRANSITION  [current_design]
set_max_capacitance $MAX_CAPACITANCE [current_design]
