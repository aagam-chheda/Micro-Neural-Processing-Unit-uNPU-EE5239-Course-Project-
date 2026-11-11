# Task 043 — back-end re-run, script 5: `pnr/cts.tcl` (clock tree, then hold optimisation at the chosen uncertainty)

Read first: `docs/planning/backend-rerun-plan.md` (stage C, including the 0.5 ns discussion in C2), `pnr/README.md`,
the current `pnr/*.tcl`, `docs/session-handoff.md` 18.17 and 18.18 (the CTS run, the 0.5 ns run that left 6 hold
endpoints and printed `FLW-8004`, the 0.2 ns run), 18.20 (the first checks after routing, for the style of check).

## Goal

One script that takes the placed block, builds the clock tree, saves a checkpoint, applies the hold uncertainty
from `params.tcl` in the hold scenario, runs the post-CTS optimisation, checks the result, and saves a second
checkpoint. Placement (`pin_place.tcl`, `placement.tcl`) is not written yet; this script only needs the block named
`$BLK_PLACED` to exist.

## Part A — what to write

### A1. `pnr/cts.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/power.tcl`. Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin cts run <library>`; the library must
   exist; refuse to run if the block `$BLK_CTS` or `$BLK_CLKOPT` already exists (the same guard as `power.tcl`);
   open `$BLK_PLACED` with `unpu_open_stage`. Before anything: `check_legality` must report 0 violations (the
   placed block must be legal; parse the `TOTAL 0 Violations` line with a pure-Tcl procedure), and the number of
   clock sinks you expect is `EXPECT_SEQ_CELLS` (2465).
2. Scenarios: do not rely on the current scenario. Select `$SCEN_SETUP` or `$SCEN_HOLD` explicitly wherever a
   command depends on it, and say in a comment which scenario each command acts on.
3. Cells kept out of the clock tree (18.17): `set_lib_cell_purpose -exclude cts [get_lib_cells <CTS_EXCLUDE_PATTERN>]`
   (the 12 delay cells `dl*`). Print how many cells matched; zero matches is an Error (they would end up in the tree).
4. Clock tree: `clock_opt -to build_clock` (18.17). Capture the output. `report_clock_qor -type summary` written to
   `$RPT_DIR/cts_clock_qor_build.rpt` (`redirect -file`) and printed. Parse, with a pure-Tcl procedure in
   `common.tcl`, the numbers 18.17 quotes: sinks, levels, clock repeaters, max latency and global skew for each
   corner (first run: 2,465 sinks, 3 levels, 53 repeaters, ss latency 1.21 ns / skew 0.95 ns, ff latency 0.49 ns /
   skew 0.36 ns). CHECK sinks == `EXPECT_SEQ_CELLS`; levels, repeaters, latency and skew are RESULT lines only.
   If the layout does not parse: the sinks check FAILS with the text it saw (as `unpu_corner_has_point` does).
   Checkpoint: `unpu_checkpoint $BLK_CTS` (this is the "hold unfixed" block of the first run, kept so another hold
   uncertainty can be tried from it).
5. Hold uncertainty (18.18): in `$SCEN_HOLD` set `set_clock_uncertainty -hold $HOLD_UNCERT [get_clocks clk]`, then
   read it back (report or attribute, VERIFY) and CHECK it equals `HOLD_UNCERT`. Comment: the SDC already carries 0.5;
   this makes the value explicit and lets an experiment run with another value.
6. Hold optimisation: `clock_opt -from route_clock -to final_opto` (18.18). Capture the output. Count the lines with
   the message id `FLW-8004` ("Incomplete clock_opt / final_opto"; seen in both earlier runs, cause unknown): print
   them, RESULT `flw_8004_count`, and a Warning when the count is not zero (not an error: the QoR below decides).
   Also print any other `FLW-` ids with counts, so that a new flow message is visible.
7. Checks after (the way 18.18 and 18.20 did them), each one `unpu_check_pass` or a RESULT as stated:
   - setup: the worst setup slack in `$SCEN_SETUP` and the number of violating endpoints; CHECK violating == 0
     (use `report_qor`/`report_constraint` or `get_timing_paths`; VERIFY; if a count cannot be obtained, the check
     FAILS as "unavailable", never passes);
   - hold: the worst hold slack in `$SCEN_HOLD` and the number of violating endpoints per path group. This is a
     RESULT and a Warning if not zero, NOT a check: plan C2 says `route_opt` may clear the last endpoints and that
     the user decides what to do if hold does not close at 0.5 ns. The Warning text must say so and quote the
     endpoint list (the worst 10 with their slack);
   - max transition and max capacitance violations: CHECK both 0 (VERIFY how to read);
   - `check_legality`: CHECK 0 violations;
   - `check_pg_connectivity`: CHECK 0 floating standard cells, wires, vias (reuse `unpu_parse_pg_connectivity`);
   - clock QoR after the optimisation: the same parse as in step 4, RESULT lines (compare with the build stage:
     latency and skew should not change much);
   - area, instance count, buffer count and core utilisation: RESULT lines (first run, 0.5 ns: area 427,619 ->
     484,572 um2, instances 12,039 -> 14,309, buffers 214 -> 2,511, utilisation 66% -> 74.5%; 0.2 ns: area 428,230,
     instances 12,039, utilisation 65.9%). VERIFY how to read them; if not readable: a Warning, not a check.
8. `unpu_checks_finish cts`, then `unpu_checkpoint $BLK_CLKOPT`, then the summary `unpu_result cts` lines.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `CTS_BUILD_TO build_clock`, `CTS_OPT_FROM route_clock`, `CTS_OPT_TO final_opto` (18.17, 18.18),
  `FLW_INCOMPLETE_ID FLW-8004` (18.18), `EXPECT_CTS_LEVELS 3` and `EXPECT_CTS_REPEATERS 53` as INFORMATIVE reference
  values (18.17; used only in a comment/RESULT, never in a check), each with its source.
- `pnr/common.tcl`: pure-Tcl procedures: parse `report_clock_qor -type summary` text (sinks, levels, repeaters,
  latency, skew per corner), parse the `check_legality` summary, count message ids with a prefix (reuse
  `unpu_message_ids` if it fits), and a procedure that turns the worst hold endpoints into a short list.
- `pnr/test_common.tcl`: tests for each, with made-up texts in two layouts for the clock QoR (include the 18.17
  numbers), the legality text with 0 and with a nonzero count, and the `FLW-8004` counting.
- `pnr/README.md`: row 8 written.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 181 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `cts.tcl` (scratch only) with the logged command sequence in the order of A1, and these
   failure paths firing: library or block `placed` missing; block `cts` already present; a nonlegal placed block;
   `dl*` matching 0 cells; sinks 2464; hold uncertainty not applied; setup violations > 0; legality > 0; floating
   cells > 0; output with `FLW-8004` twice (Warning, still saves); remaining hold violations (Warning, still saves).
   Show that the two checkpoints are saved in the right places (after the clock tree, after the optimisation).
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; nothing written under `SCL_KIT_ROOT`.
5. `git status`: only `pnr/` changed.

## Part C — server block for the user (in your report)

csh commands with the `$UNPU_REPO` placeholder, the `icc2_shell -file ... cts.tcl -output_log_file ...` line (run
time: the first run's `clock_opt` stages took minutes, say what you know), what a good result looks like for the
0.5 ns baseline (2,465 sinks; expect more area than at 0.2 ns; possible `FLW-8004`; remaining hold endpoints are
possible and are not a failure of the script), the grep and the files to paste back (the two clock QoR reports, the
`FLW-` lines, the hold endpoint list), and the rerun note (a failed run saved nothing after its last checkpoint;
`cts` saved means a new hold uncertainty restarts from `cts` only after the `clkopt` block is dealt with, say how:
new run tag or a documented removal; you do not know a reliable remove command).

## Constraints that apply

Standing rules of tasks 038 to 042. Mark every tool command or option not shown in the handoff `VERIFY`. Do not
add any CTS option that the handoff does not show (no skew targets, no useful-skew): those are experiments for later.

## Out of scope

Pin placement, placement (not written yet), routing and everything after; changing the hold uncertainty value;
`rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on the server; committing.

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt
that is wrong or ambiguous, and the Part C block. Stop after reporting.
