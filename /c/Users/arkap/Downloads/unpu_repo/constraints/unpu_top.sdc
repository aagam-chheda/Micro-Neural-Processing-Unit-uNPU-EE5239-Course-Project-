# =============================================================================
# unpu_top.sdc -- timing constraints for the unpu_top hard macro, STAGE-SELECTABLE
#
# Purpose
#   The SDC timing contract for unpu_top (rtl/unpu_top.sv): one clock, the
#   input/output delays on every port, and the boundary driver and loads.
#   TIMING CONSTRAINTS ONLY -- no libraries, no don't-use cells, no operating
#   corner, no compile options. Those belong to the synthesis script.
#
# Who reads this file
#   The same file is read by Design Compiler (dc_shell), ICC2 (icc2_shell) and
#   PrimeTime (pt_shell); see docs/session-handoff.md section 18. It has not
#   yet been read by any of them: it was written and checked with tclsh under a
#   stub (constraints/test_stages.tcl) only.
#
# THE STAGE PROFILE (new, 2026-11-02)
#   The constraint set is chosen by the environment variable UNPU_STAGE, which
#   has NO DEFAULT: if it is unset or not one of the profile names below the file
#   stops with a message that lists the valid names (a silent default would make
#   a result look like another stage's). csh:   setenv UNPU_STAGE syn16
#   A profile fixes the clock period, the setup and hold clock uncertainty and,
#   as PERCENTAGES OF THAT STAGE'S PERIOD, every input and output delay. The
#   profile is printed on read ("Info: [unpu] SDC profile ...").
#     profile  period  kind      used in
#     syn20     20 ns  pre-CTS   synthesis, mandatory (real period)
#     syn18     18 ns  pre-CTS   synthesis, tighter
#     syn16     16 ns  pre-CTS   synthesis, tightest (target)
#     place     18 ns  pre-CTS   place_opt (ideal clock)
#     cts       18 ns  post-CTS  clock_opt
#     route     20 ns  post-CTS  route_auto, route_opt, fill, outputs
#     signoff   20 ns  post-CTS  PrimeTime (ss setup, ff hold), simulation
#   The pre-CTS / post-CTS kind selects the setup uncertainty (see the table
#   section). After CTS the clock is propagated by the tool, not by this file;
#   the cts, route and signoff profiles describe the post-CTS uncertainty.
#
# SOURCE OF THE NUMBERS
#   The instructor's guidance of 27 Oct 2026 (course channel; recorded verbatim in
#   docs/planning/instructor-guidance-2026-10-27.md), rule applied: the MOST
#   PESSIMISTIC end of every range (the user's decision of 2026-11-02, analysis in
#   docs/planning/constraints-update-2026-11-02.md). Date of this change: 2026-11-02.
#   These values must NEVER be changed to close timing. Changing one needs a
#   written reason and the user's approval.
#
# STILL OUR OWN ASSUMPTIONS (not in the guidance)
#   The input driving cell (buffd1), the 0.2 pF input wire load, the clock
#   transition 0.6 ns, the max capacitance 2.0 pF and the explicit choice of port
#   groups. The 1 pF output load is the course instructor's earlier value and the
#   3.0 ns max transition is the library's own pin limit (section 'Boundary').
#
# NOT SET by this file (open items, not forgotten)
#   - The interface budget is the guidance's rule of thumb, not an agreed number.
#   - No set_false_path / set_multicycle_path: none is needed. One clock, no
#     clock-domain crossings. rst_n is deliberately TIMED (user decision Q2).
#
# After CTS
#   This file describes an ideal clock (no latency, no network delay). After
#   clock-tree synthesis the clock becomes propagated (set_propagated_clock),
#   done by the stage script, not here.
#
# Time unit
#   Values are written in library time units. The SCL libraries (tsl18fs120)
#   use ns, so every number below is in ns. A delay expressed as a fraction of
#   the period is period * fraction, also in ns.
#
# STAGE CHANGE LOG
#   Before 2026-11-02 (one hard-wired set, all values our own HARSH assumptions):
#     period 20 ns; setup uncertainty 1.5 ns; hold uncertainty 0.5 ns;
#     input delay max 35% (APB, incl. paddr), 40% (DMA, rst_n); output delay max
#     35% (APB), 40% (DMA); input min delay 0.0; output min delay -0.5.
#   2026-11-02: replaced by the stage profiles below (instructor, most pessimistic
#     end): period 20/18/16 by stage; setup uncertainty 1.2 (pre-CTS) or 0.6
#     (post-CTS); hold uncertainty 0.05; delays 35% for the feedthrough ports (paddr in,
#     prdata and pready out) and 70% for every other port; input min delay 5% of the
#     period; output min delay 0.
# =============================================================================


# -----------------------------------------------------------------------------
# Units. The ss library (tsl18fs120_scl_ss) declares time_unit : 1ns and
# capacitive_load_unit (1, pf) (read from its .lib header on the server): every
# time below is in ns and every load in pF. The ff library's header has NOT been
# read; it is assumed to match and must be confirmed before PrimeTime.
# -----------------------------------------------------------------------------
set_units -time ns -capacitance pF


# ==== BEGIN STAGE PROFILE TABLE =============================================
# Plain Tcl (set, expr, if, foreach), NO tool command, so that tclsh can run
# this section under a stub (constraints/test_stages.tcl). constraints/pm_unpu_top.sdc carries
# a byte-identical copy of this section (the self-test compares them): change both or neither.
# Everything numeric about the stage constraints is typed HERE and nowhere else.

# Clock uncertainty building blocks (ns). Instructor, 27 Oct: setup uncertainty pre-CTS =
# jitter + skew + margin, post-CTS = jitter + margin; hold 50 ps. Most pessimistic end.
set JITTER_NS            0.20   ;# instructor: 150 ps, or 200 ps if conservative -> 200 ps
set SKEW_ALLOW_PRE_CTS_NS 0.60  ;# instructor: skew allowance before CTS 600 ps
set MARGIN_NS            0.40   ;# instructor: margin 400 ps
set UNCERT_HOLD_NS       0.05   ;# instructor: 50 ps at every stage (user decision Q1, 2026-11-02)
# Derived, never typed (rounded to 1e-6 ns so that no floating-point noise reaches the written SDC):
set UNCERT_SETUP_PRE_CTS  [expr {round(($JITTER_NS + $SKEW_ALLOW_PRE_CTS_NS + $MARGIN_NS) * 1000000.0) / 1000000.0}]   ;# 1.2
set UNCERT_SETUP_POST_CTS [expr {round(($JITTER_NS + $MARGIN_NS) * 1000000.0) / 1000000.0}]                           ;# 0.6

# Interface delays as FRACTIONS of the stage's period (instructor, "thumb rule for input and output delays").
# - Feedthrough row (input to output with no flop, ~30-35% each): paddr in, prdata and pready out. The read path
#   prdata = f(paddr) is combinational through the CSR read mux (rtl/unpu_csr.sv). paddr ALSO reaches flops through the
#   write decode; one input delay applies to both kinds of path, and the feedthrough row was chosen on purpose
#   (user decision Q3: 35% for paddr, no virtual clock).
# - Every other port: the neighbour is unknown, so the "logic at the port" row, 60-70% -> 70% (most pessimistic).
# - rst_n: asynchronous in nature, but TIMED like any input (no false path) so that recovery/removal checks exist (Q2).
set FT_IN_PCT   0.35   ;# paddr[*]
set FT_OUT_PCT  0.35   ;# prdata[*] pready
set APB_IN_PCT  0.70   ;# pwdata[*] pwrite psel penable
set DMA_IN_PCT  0.70   ;# dma_rdata[*] dma_ready
set DMA_OUT_PCT 0.70   ;# dma_addr[*] dma_wdata[*] dma_wstrb[*] dma_valid
set RST_IN_PCT  0.70   ;# rst_n
set IN_MIN_PCT  0.05   ;# input min delay: 5-10% of T -> 5% (the earliest)
set OUT_MIN_PCT 0.0    ;# output min delay: 0-5% of T -> 0

# The profiles: name, period (ns), kind (pre = before CTS, post = after CTS). Instructor: synthesis 10-20% tighter
# (16-18 ns), placement/CTS 5-10% tighter (18-19 ns), route and signoff the real 20 ns; the tighter end is used.
set UNPU_STAGE_TABLE {
  {syn20   20.0 pre}
  {syn18   18.0 pre}
  {syn16   16.0 pre}
  {place   18.0 pre}
  {cts     18.0 post}
  {route   20.0 post}
  {signoff 20.0 post}
}
set UNPU_STAGE_NAMES {}
foreach UNPU_ROW $UNPU_STAGE_TABLE { lappend UNPU_STAGE_NAMES [lindex $UNPU_ROW 0] }

# Self-check of EVERY profile: the feedthrough input and output fractions must sum to less than 1 and the budget
#     T * (1 - FT_IN_PCT - FT_OUT_PCT) - setup uncertainty
# must be positive, or the constraint is impossible (the 70% + 70% reading of the guidance would be).
foreach UNPU_ROW $UNPU_STAGE_TABLE {
  set UNPU_T    [lindex $UNPU_ROW 1]
  set UNPU_KIND [lindex $UNPU_ROW 2]
  if {$UNPU_KIND eq "pre"} { set UNPU_U $UNCERT_SETUP_PRE_CTS } elseif {$UNPU_KIND eq "post"} { set UNPU_U $UNCERT_SETUP_POST_CTS } else {
    error "unpu SDC: profile [lindex $UNPU_ROW 0] has kind '$UNPU_KIND', expected pre or post"
  }
  if {$FT_IN_PCT + $FT_OUT_PCT >= 1.0} { error "unpu SDC: feedthrough input + output fractions ($FT_IN_PCT + $FT_OUT_PCT) are not below 1.0" }
  if {$UNPU_T * (1.0 - $FT_IN_PCT - $FT_OUT_PCT) - $UNPU_U <= 0.0} {
    error "unpu SDC: profile [lindex $UNPU_ROW 0] has no feedthrough budget left (T $UNPU_T, in $FT_IN_PCT, out $FT_OUT_PCT, setup uncertainty $UNPU_U)"
  }
}

# The profile is read from the environment. NO DEFAULT.
if {![info exists ::env(UNPU_STAGE)] || $::env(UNPU_STAGE) eq ""} {
  error "unpu SDC: the environment variable UNPU_STAGE is not set. It has no default. Valid profiles: $UNPU_STAGE_NAMES. csh: setenv UNPU_STAGE <profile>"
}
set UNPU_STAGE_SEL $::env(UNPU_STAGE)
set UNPU_FOUND 0
foreach UNPU_ROW $UNPU_STAGE_TABLE {
  if {[lindex $UNPU_ROW 0] eq $UNPU_STAGE_SEL} {
    set CLK_PERIOD [lindex $UNPU_ROW 1]
    set UNPU_STAGE_KIND [lindex $UNPU_ROW 2]
    set UNPU_FOUND 1
  }
}
if {!$UNPU_FOUND} {
  error "unpu SDC: UNPU_STAGE='$UNPU_STAGE_SEL' is not a profile. Valid profiles: $UNPU_STAGE_NAMES"
}
if {$UNPU_STAGE_KIND eq "pre"} { set CLK_UNCERT_SETUP $UNCERT_SETUP_PRE_CTS } else { set CLK_UNCERT_SETUP $UNCERT_SETUP_POST_CTS }
set CLK_UNCERT_HOLD $UNCERT_HOLD_NS

# The delays of the selected profile in ns (period * fraction, rounded to 1e-6 ns like the uncertainties above).
set FT_IN_MAX    [expr {round($CLK_PERIOD * $FT_IN_PCT   * 1000000.0) / 1000000.0}]
set FT_OUT_MAX   [expr {round($CLK_PERIOD * $FT_OUT_PCT  * 1000000.0) / 1000000.0}]
set APB_IN_MAX   [expr {round($CLK_PERIOD * $APB_IN_PCT  * 1000000.0) / 1000000.0}]
set DMA_IN_MAX   [expr {round($CLK_PERIOD * $DMA_IN_PCT  * 1000000.0) / 1000000.0}]
set DMA_OUT_MAX  [expr {round($CLK_PERIOD * $DMA_OUT_PCT * 1000000.0) / 1000000.0}]
set RST_IN_MAX   [expr {round($CLK_PERIOD * $RST_IN_PCT  * 1000000.0) / 1000000.0}]
set IN_MIN_DELAY  [expr {round($CLK_PERIOD * $IN_MIN_PCT  * 1000000.0) / 1000000.0}]
set OUT_MIN_DELAY [expr {round($CLK_PERIOD * $OUT_MIN_PCT * 1000000.0) / 1000000.0}]
set FT_BUDGET_NS [expr {round(($CLK_PERIOD * (1.0 - $FT_IN_PCT - $FT_OUT_PCT) - $CLK_UNCERT_SETUP) * 1000000.0) / 1000000.0}]

# VERIFY: puts, "info exists ::env(...)", error, foreach and expr are accepted inside read_sdc by dc_shell, icc2_shell and pt_shell.
puts "Info: \[unpu\] SDC profile $UNPU_STAGE_SEL: period $CLK_PERIOD ns, setup uncertainty $CLK_UNCERT_SETUP ns, hold uncertainty $CLK_UNCERT_HOLD ns, feedthrough budget $FT_BUDGET_NS ns"
# ==== END STAGE PROFILE TABLE ===================================================

# -----------------------------------------------------------------------------
# Port groups, listed explicitly. all_inputs / all_outputs are NOT used, so a
# port added to unpu_top later shows up as unconstrained in check_timing
# instead of being covered silently. clk is in no group: it gets no input
# delay.
# -----------------------------------------------------------------------------
set CLK_TRANSITION     0.6   ;# HARSH ASSUMPTION (ours, not the guidance's), slew at the flop clock pins (ideal clock only)
set APB_FT_IN_PORTS {paddr[*]}
set APB_IN_PORTS   {pwdata[*] pwrite psel penable}
set APB_OUT_PORTS  {prdata[*] pready}
set DMA_IN_PORTS   {dma_rdata[*] dma_ready}
set DMA_OUT_PORTS  {dma_addr[*] dma_wdata[*] dma_wstrb[*] dma_valid}
set RST_IN_PORTS   {rst_n}


# -----------------------------------------------------------------------------
# Clock: one clock, ideal (pre-CTS), no latency. The period and the
# uncertainties come from the stage profile above.
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
set_input_delay -clock clk -max $FT_IN_MAX  [get_ports $APB_FT_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY [get_ports $APB_FT_IN_PORTS]

set_input_delay -clock clk -max $APB_IN_MAX [get_ports $APB_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY [get_ports $APB_IN_PORTS]

set_input_delay -clock clk -max $DMA_IN_MAX [get_ports $DMA_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY [get_ports $DMA_IN_PORTS]

# rst_n: an ordinary input delay, deliberately with NO set_false_path. Its
# assertion is asynchronous, but the recovery/removal checks on its release
# must stay in the analysis, so it is timed like any other input (user decision Q2).
set_input_delay -clock clk -max $RST_IN_MAX [get_ports $RST_IN_PORTS]
set_input_delay -clock clk -min $IN_MIN_DELAY [get_ports $RST_IN_PORTS]


# -----------------------------------------------------------------------------
# Output delays. -max is the setup side, -min the hold side.
# -----------------------------------------------------------------------------
set_output_delay -clock clk -max $FT_OUT_MAX [get_ports $APB_OUT_PORTS]
set_output_delay -clock clk -min $OUT_MIN_DELAY [get_ports $APB_OUT_PORTS]

set_output_delay -clock clk -max $DMA_OUT_MAX [get_ports $DMA_OUT_PORTS]
set_output_delay -clock clk -min $OUT_MIN_DELAY [get_ports $DMA_OUT_PORTS]


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
# d) Design-wide max transition 3.0 ns and max capacitance 2.0 pF.
#    Max transition 3.0 ns is the library's own pin limit (max_transition : 3 in
#    the ss .lib, read on the server), so it is the characterised limit and not a
#    tightened one. It replaces my earlier harsh 1.0 ns (see e). Max capacitance
#    2.0 pF is a harsh assumption, tighter than the PM's own
#    commented-out set_max_capacitance 5 (a different technology) and not checked
#    against the SCL library. The library's pin limits still apply and where they
#    are tighter they win. The 1 pF output load sits under the 2.0 pF cap; keep
#    MAX_CAPACITANCE above OUT_LOAD or every output is a violation by construction.
#
# e) Why max transition is 3.0 ns and not 1.0 ns (decided by the user, 2026-10-14,
#    option A, after the first two DC runs). Assumptions a) and b) already fix the
#    slew at every data input: a buffd1 driving 0.2 pF gives 2.43 ns (DC, ss
#    corner), which can never meet 1.0 ns; DC cannot change the driver or the wire,
#    so 79 input ports were violated by construction (-1.43 ns each), which says
#    nothing about the design. A port-specific looser limit does not help: DC
#    applies the tighter of the design-wide and the port limit, so a 3.0 ns
#    set_max_transition on the ports did not override a design-wide 1.0 ns (tried
#    in the second DC run). The 1.0 ns, my own harsh guess with no library basis,
#    is therefore dropped and the library's 3 ns applies everywhere. The input
#    driver and wire assumptions stay harsh. The one internal net that was over 1.0
#    ns (n45 in pe_10, 1.46 ns) is legal under 3 ns and no longer reported.
# -----------------------------------------------------------------------------
set DRIVE_CELL       buffd1  ;# ASSUMPTION, weakest plain buffer standing in for the outside driver
set DRIVE_PIN        Z       ;# output pin; verified for buffd2 in the ss .lib, assumed for buffd1
set IN_WIRE_LOAD     0.2     ;# pF, HARSH ASSUMPTION, wire on every data input net
set OUT_LOAD         1.0     ;# pF, every output port; the instructor's suggested value
set MAX_TRANSITION   3.0     ;# ns, the library's own pin limit (see e)
set MAX_CAPACITANCE  2.0     ;# pF, HARSH ASSUMPTION

set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $APB_FT_IN_PORTS]
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $APB_IN_PORTS]
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $DMA_IN_PORTS]
set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN [get_ports $RST_IN_PORTS]

set_load $IN_WIRE_LOAD [get_ports $APB_FT_IN_PORTS]
set_load $IN_WIRE_LOAD [get_ports $APB_IN_PORTS]
set_load $IN_WIRE_LOAD [get_ports $DMA_IN_PORTS]
set_load $IN_WIRE_LOAD [get_ports $RST_IN_PORTS]

set_load $OUT_LOAD [get_ports $APB_OUT_PORTS]
set_load $OUT_LOAD [get_ports $DMA_OUT_PORTS]

set_max_transition  $MAX_TRANSITION  [current_design]
set_max_capacitance $MAX_CAPACITANCE [current_design]
