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
#   3. NEW: boundary non-idealities: a weak input driving cell, a wire load on
#      the input nets, the output load, and design-wide max transition and max
#      capacitance. They override the PM's set_drive 0 and set_load 0 on the
#      named ports.
#
# EVERY number below except the 20 ns period (CLAUDE.md) and the 1 pF output
# load (the course instructor's value) is an ASSUMPTION, pending the SoC team's
# interface timing and loads. The assumptions are deliberately HARSH (pessimistic):
# large clock uncertainty and slew, big external delay shares, a long input wire,
# tight transition and capacitance limits. Timing that closes here has margin. None may be changed to close timing without a
# written reason and the user's approval.
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

# Port groups, listed explicitly. clk is in no group.
set APB_IN_PORTS   {paddr[*] pwdata[*] pwrite psel penable}
set APB_OUT_PORTS  {prdata[*] pready}
set DMA_IN_PORTS   {dma_rdata[*] dma_ready}
set DMA_OUT_PORTS  {dma_addr[*] dma_wdata[*] dma_wstrb[*] dma_valid}
set RST_IN_PORTS   {rst_n}

set_clock_uncertainty -setup $CLK_UNCERT_SETUP [get_clocks clk]
set_clock_uncertainty -hold  $CLK_UNCERT_HOLD  [get_clocks clk]
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
# 3. NEW: boundary non-idealities
#
# Replaces the PM's idealised boundary (set_drive 0 = an infinitely strong
# driver, set_load 0 = nothing connected) with a finite one. All of it is an
# assumption; the SoC team has not given real numbers. The output load is the
# instructor's value; everything else is mine.
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
