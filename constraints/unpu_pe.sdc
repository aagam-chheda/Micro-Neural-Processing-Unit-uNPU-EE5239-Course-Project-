# =============================================================================
# unpu_pe.sdc -- bring-up timing constraints for the unpu_pe module ALONE
#
# WHAT THIS FILE IS, AND IS NOT
#   This file exists only so the single module unpu_pe can be synthesised on
#   its own as a first check of the Design Compiler flow (task 035). It is NOT
#   the constraint set for the hard macro: that is constraints/unpu_top.sdc.
#   Do not carry anything from here into the macro's constraints.
#
# Purpose
#   One clock and the input/output delays on every port of unpu_pe
#   (rtl/unpu_pe.sv). TIMING CONSTRAINTS ONLY -- no libraries, no don't-use
#   cells, no operating corner, no compile options. Same style and same rules
#   as constraints/unpu_top.sdc.
#
# Who reads this file
#   Design Compiler (dc_shell) for the bring-up run. It has not yet been read
#   by any tool: it was written and checked statically only.
#
# Time unit
#   Values are in library time units. The SCL libraries (tsl18fs120) use ns,
#   so every number below is in ns. See the set_units line below.
#
# ASSUMPTIONS -- read this before trusting any number
#   The clock period is a project fact (CLAUDE.md, 50 MHz). EVERYTHING ELSE in
#   the variable block is a PLACEHOLDER ASSUMPTION, chosen before any timing
#   result existed. The fractions equal the placeholders in unpu_top.sdc. They
#   must NEVER be changed to close timing; changing one needs a written reason
#   and the user's approval.
#     1. CLK_UNCERT      pre-CTS clock uncertainty margin.
#     2. PE_IN_PCT       share of the period used outside before the data and
#                        control inputs arrive.
#     3. PE_OUT_PCT      share of the period the outside needs after act_out /
#                        psum_out leave.
#     4. RST_IN_PCT      same, for rst_n.
#     5. IN_MIN_DELAY / OUT_MIN_DELAY   hold-side (min) delays.
#   In the real array the PE inputs come from neighbouring PEs' registers and
#   the skew/deskew logic, not from an outside world; these fractions are a
#   stand-in for a first synthesis run, nothing more.
#
# NOT SET by this file (open items, not forgotten)
#   - set_driving_cell : NOT SET. Needs an SCL buffer cell name; none guessed.
#   - set_load         : NOT SET. Needs an output load; none available.
#   - No set_false_path / set_multicycle_path: none needed, one clock.
#   - No combinational input-to-output path exists in unpu_pe: act_out and
#     psum_out are registered, so no in-to-out budget note is needed here.
#
# After CTS
#   Ideal clock (no latency). Not relevant for this bring-up file.
# =============================================================================


# -----------------------------------------------------------------------------
# Units. Time only: the ss library (tsl18fs120_scl_ss) declares time_unit : 1ns
# (read from its .lib header on the server), and every number in this file is
# a time. The ff library's header has NOT been read; it is assumed to match
# and must be confirmed before PrimeTime. No capacitance unit is set here: the
# library's capacitive unit has not been read and no capacitance is used until
# set_load is added; the capacitance unit is added together with set_load.
# -----------------------------------------------------------------------------
set_units -time ns


# -----------------------------------------------------------------------------
# Variable block. Every number used below this block comes from here.
# -----------------------------------------------------------------------------
set CLK_PERIOD        20.0   ;# 50 MHz, from CLAUDE.md
set CLK_UNCERT         0.5   ;# ASSUMPTION, pre-CTS margin
set PE_IN_PCT          0.3   ;# ASSUMPTION, fraction of period used outside, max input delay
set PE_OUT_PCT         0.3   ;# ASSUMPTION, fraction of period the outside needs after act_out/psum_out
set RST_IN_PCT         0.3   ;# ASSUMPTION, rst_n
set IN_MIN_DELAY       0.0   ;# ASSUMPTION, min input delay for hold
set OUT_MIN_DELAY      0.0   ;# ASSUMPTION, min output delay for hold


# -----------------------------------------------------------------------------
# Port groups, listed explicitly. all_inputs / all_outputs are NOT used, so a
# port added to unpu_pe later shows up as unconstrained in check_timing instead
# of being covered silently. clk is in no group: it gets no input delay.
# -----------------------------------------------------------------------------
set PE_IN_PORTS    {array_en weight_load mode_unsigned weight_in[*] act_in[*] psum_in[*]}
set PE_OUT_PORTS   {act_out[*] psum_out[*]}
set RST_IN_PORTS   {rst_n}


# -----------------------------------------------------------------------------
# Clock: one clock, ideal (pre-CTS), no latency.
# -----------------------------------------------------------------------------
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty $CLK_UNCERT [get_clocks clk]


# -----------------------------------------------------------------------------
# Input delays. -max is the setup side, -min the hold side.
# -----------------------------------------------------------------------------
set_input_delay -clock clk -max [expr {$CLK_PERIOD * $PE_IN_PCT}]  [get_ports $PE_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $PE_IN_PORTS]

# rst_n: an ordinary input delay, deliberately with NO set_false_path. Its
# assertion is asynchronous, but the recovery/removal checks on its release
# must stay in the analysis, so it is timed like any other input.
set_input_delay -clock clk -max [expr {$CLK_PERIOD * $RST_IN_PCT}] [get_ports $RST_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY                      [get_ports $RST_IN_PORTS]


# -----------------------------------------------------------------------------
# Output delays. -max is the setup side, -min the hold side.
# -----------------------------------------------------------------------------
set_output_delay -clock clk -max [expr {$CLK_PERIOD * $PE_OUT_PCT}] [get_ports $PE_OUT_PORTS]
set_output_delay -clock clk -min $OUT_MIN_DELAY                     [get_ports $PE_OUT_PORTS]


# -----------------------------------------------------------------------------
# Deliberately not set (see header). Left commented so the gap is visible.
# Do not fill in a guess: the cell name comes from the SCL library, the load
# from whoever owns the interface.
# -----------------------------------------------------------------------------
# set_driving_cell -lib_cell <TODO cell> [get_ports $PE_IN_PORTS]
# set_driving_cell -lib_cell <TODO cell> [get_ports $RST_IN_PORTS]
# set_load <TODO load> [get_ports $PE_OUT_PORTS]
