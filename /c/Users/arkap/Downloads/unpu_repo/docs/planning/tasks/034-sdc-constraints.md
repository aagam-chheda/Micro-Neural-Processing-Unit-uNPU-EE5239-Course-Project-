# Task 034 — Write the timing constraint file `constraints/unpu_top.sdc`

## Goal

Write one file: `constraints/unpu_top.sdc`, the SDC (Synopsys Design
Constraints) timing contract for `unpu_top`. Nothing else. No synthesis
script, no library setup, no testbench, no RTL change.

The back-end flow is fixed (`docs/session-handoff.md` §18): Design Compiler,
ICC2, PrimeTime, Calibre. The same SDC will be read by DC, ICC2 and
PrimeTime, so it holds **timing constraints only**: no libraries, no
don't-use cells, no operating corner, no compile options. Those belong to
the synthesis script, which is a later task.

You cannot run any Synopsys tool (they are on the server only). This task is
written and checked statically. The first real read of the file is in the
Design Compiler task that follows; do not try to pre-empt it.

Standing rules apply: nothing hardcoded, nothing silently missing, no value
tuned to make timing pass.

## What is fixed and what is not

**Fixed by the project:**
- One clock, `clk`, 50 MHz, period 20 ns (`CLAUDE.md`).
- Ports of `unpu_top` (`rtl/unpu_top.sv`): `clk`, `rst_n`; APB slave
  `paddr[31:0]`, `pwdata[31:0]`, `pwrite`, `psel`, `penable` (inputs),
  `prdata[31:0]`, `pready` (outputs); native SRAM master `dma_addr[31:0]`,
  `dma_wdata[31:0]`, `dma_wstrb[3:0]`, `dma_valid` (outputs), `dma_rdata[31:0]`,
  `dma_ready` (inputs). Take the list from the RTL, not from this file.
- Single clock domain, no clock-domain crossings.

**Not known yet (open, needs the PM / SoC team):** the interface timing
budget, that is, how much of the 20 ns the outside world uses on each
input and output; the load each output drives; the cell that drives each
input. These are **assumptions** in this task. They are not facts and the
file must say so.

## Required content of `constraints/unpu_top.sdc`

**1. Header comment.** Purpose; that it is timing constraints only; that all
budget numbers are placeholder assumptions pending the SoC team's interface
timing; the list of assumptions (item 6); who reads the file (DC, ICC2,
PrimeTime); the time unit the values are written in (the SCL libraries use
`ns`; say so, and say the numbers are in library time units).

**2. A variable block at the top, and no bare numbers anywhere below it.**
Every number used later comes from a named variable defined in this block,
each with a one-line comment:

```tcl
set CLK_PERIOD        20.0   ;# 50 MHz, from CLAUDE.md
set CLK_UNCERT         0.5   ;# ASSUMPTION, pre-CTS margin
set APB_IN_PCT         0.3   ;# ASSUMPTION, fraction of period used outside, max input delay
set APB_OUT_PCT        0.3   ;# ASSUMPTION, fraction of period the outside needs after prdata/pready
set DMA_IN_PCT         0.3   ;# ASSUMPTION, dma_rdata, dma_ready
set DMA_OUT_PCT        0.3   ;# ASSUMPTION, dma_addr/wdata/wstrb/valid
set RST_IN_PCT         0.3   ;# ASSUMPTION, rst_n
set IN_MIN_DELAY       0.0   ;# ASSUMPTION, min input delay for hold
set OUT_MIN_DELAY      0.0   ;# ASSUMPTION, min output delay for hold
```

These exact names and values are Planning's placeholders. Keep the names
(later tasks will refer to them). The values were chosen **before any timing
result exists**. They are never to be changed to close timing; changing one
requires a written reason and the user's approval.

APB and DMA have separate variables on purpose: the two interfaces will
probably get different budgets.

**3. Clock.** `create_clock -name clk -period $CLK_PERIOD [get_ports clk]`
and `set_clock_uncertainty $CLK_UNCERT [get_clocks clk]`. No latency
(pre-CTS, ideal clock). Add a comment that after CTS the clock becomes
propagated (`set_propagated_clock`) and the uncertainty is revisited; do not
put those commands in this file.

**4. Input and output delays, by explicit port lists.** Do **not** use
`all_inputs` / `all_outputs`. Name each port group explicitly
(`get_ports {paddr[*] pwdata[*] pwrite psel penable}` etc.) so a port added
later shows up as unconstrained in `check_timing` instead of being covered
silently. For every port group give both `-max` and `-min`, with
`-clock clk`, using the variables above (`[expr {$CLK_PERIOD * $APB_IN_PCT}]`
form). `clk` itself gets no input delay.

**5. `rst_n`.** An input delay like the others (`RST_IN_PCT`, and the min
delay). No `set_false_path` on it: assertion is asynchronous but the
recovery/removal checks on release must remain. Say this in a comment.

**6. Things this file does not set, with the reason, as comments:**
- `set_driving_cell` and `set_load`: they need a buffer cell name from the
  SCL library and an output load from the SoC team; neither is available
  here. Leave them as commented-out lines with `<TODO cell>` / `<TODO load>`
  and state plainly in the header that **they are not set**. Do not guess a
  cell name.
- No exceptions (`set_false_path`, `set_multicycle_path`): none needed; one
  clock, no crossings.
- **The combinational APB read path.** `prdata` depends on `paddr` through
  the read mux (in to out), so its budget is
  `CLK_PERIOD * (1 - APB_IN_PCT - APB_OUT_PCT)` minus uncertainty. Put this
  formula in a comment beside the APB variables and note that the two
  percentages must leave a positive budget for that path (with the values
  above: 8 ns before uncertainty). Do **not** add an assertion or a
  `set_max_delay` for it; the note is a warning to whoever tunes the numbers.

## Verification

1. **Port coverage, static.** Print a table: every port of `unpu_top`
   (parsed from `rtl/unpu_top.sv`), its direction, and the SDC line that
   constrains it. Every port except `clk` must appear; `clk` must appear in
   `create_clock`. Report any port not covered. A throwaway script is fine;
   do not commit it.
2. **No bare numbers.** Show, with `grep`, that below the variable block no
   numeric literal is used except inside `expr` expressions that reference
   the variables (and array indices such as `[*]`). Paste the check.
3. **Tcl syntax.** If `tclsh` is available, check that the file parses as
   Tcl up to the SDC commands (the SDC commands will not exist in `tclsh`,
   so a stub `proc` for each command used is acceptable for this check).
   If `tclsh` is not available, say so; do not claim a syntax check that did
   not run.
4. You cannot run `dc_shell`, `icc2_shell` or `pt_shell`; say so in the
   report. The user will hand the file to the Design Compiler task.

## Acceptance

- `constraints/unpu_top.sdc` exists, follows items 1 to 6, and is the only
  file changed. `git diff --stat` shows one new file;
  `git diff 9f5deab..HEAD -- rtl/` is empty.
- The port-coverage table, the no-bare-numbers check and the syntax-check
  result (or "not run, reason") are in your report.
- The list of open items is in your report: driving cell, output load,
  the interface budget. State which values are assumptions.
- Commit and push (`git pull --rebase origin main` first if rejected).
  Commit message ends with `Co-Authored-By: Claude Sonnet 5.5
  <noreply@anthropic.com>`.

## Out of scope

- No synthesis script, no library or corner setup, no `set_dont_use`, no
  ICC2 or PrimeTime setup.
- No RTL, testbench, model or firmware change.
- No new test infrastructure; no change to `scripts/run_xrun.sh`.
- No run of any back-end tool.
