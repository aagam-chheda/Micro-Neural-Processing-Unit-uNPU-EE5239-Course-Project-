# Task 051 — stage-parameterised SDC: the instructor's constraints, most pessimistic end of every range

Read first, in this order: `docs/planning/instructor-guidance-2026-10-27.md` (the source, verbatim), `docs/planning/constraints-update-2026-11-02.md`
(Planning's analysis and the user's decisions in section 9; the tables in sections 1, 3 and 4 are THE SPECIFICATION of this task), then the files you change:
`constraints/unpu_top.sdc`, `constraints/pm_unpu_top.sdc` (its twin for the PM's Design Compiler script), `constraints/pm_dc_script_unpu.tcl`,
`docs/session-handoff.md` 18.6 to 18.8 and 18.30. `constraints/` is yours to edit; `docs/planning/` is not.

## Goal

Replace the single hard-wired constraint set by ONE stage-selectable set. A stage profile fixes the clock period, the setup and hold uncertainty and (as percentages of
that stage's period) every input and output delay. The same SDC is read by `dc_shell`, `icc2_shell` and `pt_shell`; the profile is chosen by an environment variable and is
printed in the log. The PM's DC script reads the profile and writes its outputs per profile.

## Part A — what to write

### A1. The profile table and the derived numbers (one place)

In `constraints/unpu_top.sdc` (a clearly marked section at the top, plain Tcl, no tool command in it so that `tclsh` can run it under a stub). Variables with
comments naming the instructor's rule they come from:

- Jitter `JITTER_NS` 0.20 (instructor: 150 ps, or 200 ps conservative; the user wants the most pessimistic end), skew allowance before CTS `SKEW_ALLOW_PRE_CTS_NS` 0.60,
  margin `MARGIN_NS` 0.40. Derived, never typed: `UNCERT_SETUP_PRE_CTS = JITTER + SKEW_ALLOW + MARGIN` (1.20), `UNCERT_SETUP_POST_CTS = JITTER + MARGIN` (0.60).
  Hold uncertainty `UNCERT_HOLD_NS` 0.05 at every stage (instructor; user decision Q1).
- The profile names and their data, exactly: `syn20`: T 20, pre-CTS; `syn18`: T 18, pre-CTS; `syn16`: T 16, pre-CTS; `place`: T 18, pre-CTS; `cts`: T 18, post-CTS;
  `route`: T 20, post-CTS; `signoff`: T 20, post-CTS. The kind (pre-CTS or post-CTS) selects the setup uncertainty. Any other profile name is an error.
- The profile is read from the environment variable `UNPU_STAGE`. If it is unset or not in the table: STOP with a loud message that lists the valid names. There is NO
  default (a silent default would make a result look like another stage's).
- Interface delays as FRACTIONS of the stage's period (`expr {$CLK_PERIOD * $PCT}`): feedthrough group (`paddr[*]` in, `prdata[*] pready` out) 0.35 / 0.35; all other APB
  inputs (`pwdata[*] pwrite psel penable`) 0.70; DMA inputs (`dma_rdata[*] dma_ready`) 0.70; DMA outputs (`dma_addr[*] dma_wdata[*] dma_wstrb[*] dma_valid`) 0.70;
  `rst_n` 0.70 and TIMED (no false path; user decision Q2). Minimum delays: inputs `IN_MIN_PCT` 0.05 of the period, outputs `OUT_MIN_PCT` 0.0. Comments say that
  `paddr` also reaches flops through the write decode, that one input delay applies to both kinds of path, and that the feedthrough row was chosen on purpose (Q3).
  Explicit port lists as before (no `all_inputs`/`all_outputs`), so a new port shows up as unconstrained.
- A self-check inside the table section: for every profile, the feedthrough input percent plus output percent is below 1.0 and the budget
  `T * (1 - in - out) - setup_uncertainty` is positive; if not, STOP (that would be an impossible constraint, as the 70%+70% reading would be).
- Print one line per read: `Info: [unpu] SDC profile <name>: period <T> ns, setup uncertainty <u> ns, hold uncertainty <h> ns, feedthrough budget <b> ns`.

### A2. The SDC commands

Keep what is not part of this change exactly as it is: units, clock transition 0.6, driving cell `buffd1`/`Z`, 0.2 pF input wire load, 1 pF output load, max transition 3.0,
max capacitance 2.0, the explicit port groups' `set_driving_cell`/`set_load` lines. Change: `create_clock -period $CLK_PERIOD`; `set_clock_uncertainty -setup` and `-hold` from the
profile; the input and output delays (max and min) from the groups above. Remove the old variables and the old header text that says 1.5/0.5/35%/40% and "HARSH ASSUMPTION"
for the values that the instructor's guidance has replaced; the header must instead state: source = the instructor's guidance of 27 Oct, rule = most pessimistic end, date, and
that the driver, the wire load and the max limits remain our own assumptions. Add a short "stage change log" at the end of the header: what the numbers were before
(period 20; uncertainty 1.5/0.5; delays 35/35, 40/40, 40; min 0.0/-0.5) so the history is in the file.

After CTS the clock is propagated by the tool (not in this file); say so as before, and that the `cts`, `route` and `signoff` profiles describe the post-CTS uncertainty.

### A3. The twin and the PM's script

- `constraints/pm_unpu_top.sdc` must stay equivalent to `unpu_top.sdc` in its effect (it carries the PM's own lines first: units, `create_clock -period 20`, zero input/output delays,
  which the lines after them override). Look at how the two differ now (`diff`), and make the same change in the twin so that, under every profile, the final constraints are the same
  as `unpu_top.sdc`'s. The PM's original `create_clock -period 20` and zero delays stay as given but must be overridden by the profile lines (redefinition of the clock is
  expected; print nothing misleading). If you see a cleaner way that keeps the PM's lines visible, propose it in the report instead of doing it.
- `constraints/pm_dc_script_unpu.tcl`: keep every PM command as given. Changes only: (1) require `UNPU_STAGE` (same error as the SDC) and take the output directory from it:
  `syn/out/$UNPU_STAGE/` instead of `syn/out/pm_flow`; (2) after `compile`, add the reports that a reader needs, each to its own file in that directory: `report_timing` for
  the worst 5 setup paths of each path group (`-max_paths 5 -nworst 1`), `report_constraint -all_violators`, `report_qor`, `check_timing`, `check_design`, `report_area` and
  `report_power` as before; (3) `change_names -rules verilog -hierarchy`, then write the clean-name netlist, SDC and `.ddc` (`unpu_top_cn.dc.v`, `unpu_top_cn.sdc`,
  `unpu_top_cn.ddc`) in addition to the originals (18.8 did this by hand); (4) print the profile line and the date at the top of every report file (a header written with
  `echo`), so a copied file says which profile made it. Do not add compile options.

### A4. The self-test

`constraints/test_stages.tcl` (plain `tclsh`): sources the profile section under a stub (`unknown` handler that records commands) for each of the 7 profiles and checks, with the
numbers computed independently inside the test: period, setup and hold uncertainty, every delay in ns (for example `syn16`: `paddr` max 5.6 ns, `prdata` max 5.6 ns, `pwdata` max
11.2 ns, `dma_addr` max 11.2 ns, input min 0.8 ns; `route`: 7.0, 7.0, 14.0, 14.0, 1.0), the feedthrough budgets (3.6 ns at `syn16`, 4.2 ns at `syn18` and `place`, 4.8 ns at
`syn20` and `cts`, 5.4 ns at `route`/`signoff`), that an unset or unknown `UNPU_STAGE` stops with the message, and that each of the explicit port lists names every port of
`unpu_top` exactly once (take the port names from `rtl/unpu_top.sv`, parse the declarations; clk is in no group). Print a table of all 7 profiles at the end.

## Part B — checks you can run here

1. `tclsh constraints/test_stages.tcl` passes; show the table it prints.
2. A stub run of `unpu_top.sdc` and of `pm_unpu_top.sdc` under `syn16` and `route`, showing the logged SDC commands with their numbers and that the twin's effective constraints equal
   the main file's (compare the final value of every constraint, not the text).
3. `info complete` for the Tcl files; `grep` shows no old value left as a live setting (`1.5`, `0.5`, `-0.5` as uncertainty/min delay, `0.35`/`0.4` as the old groups) outside the change log.
4. `git diff --stat constraints/` and `git status`: only `constraints/` changed (plus `scripts/` if you touched nothing there, then nothing). Do not commit.
5. Say exactly what you could NOT check without the tools (that DC/ICC2/PT accept every command, the effect of redefining the clock), and mark those `VERIFY`.

## Constraints that apply

RTL frozen. No value of this task may be changed to close timing; every number comes from the instructor's guidance via the table in the analysis document. Nothing fails silently; nothing
hardcoded outside the one table section; no `$FOUNDRY`.

## Out of scope

Running anything on the server; `pnr/` (a later task); synthesis scripts under `syn/` (the next task); `rtl/`; `docs/planning/`; committing.

## Report back

Files changed, the profile table as the test prints it, Part B output, every `VERIFY`, anything in this prompt that is wrong or ambiguous (especially in the twin handling), and the exact
server commands to run the PM's script for one profile (csh, from the repo root, with `UNPU_STAGE` set). Stop after reporting.
