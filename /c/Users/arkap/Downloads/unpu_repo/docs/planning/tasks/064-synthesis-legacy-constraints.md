# Task 064 — Synthesis with the OLD constraints into `syn/out/legacy/` (clean-slate run)

Read first: `docs/session-handoff.md` 18.31 (the restart), 18.5 and 18.9 (the old constraints), `constraints/pm_dc_script_unpu.tcl` as committed (`git show HEAD:constraints/pm_dc_script_unpu.tcl`), `constraints/stage_numbers.tcl`,
`syn/RUNBOOK.md`, `pnr_v2/design_setup.tcl` (what it reads), `docs/planning/tasks/063-backend-flow-v2-minimal-edits.md`.

## Goal

A DC script and an SDC that reproduce the OLD constraints exactly (no stage profiles), and write the same set of outputs as a profile run into `syn/out/legacy/`, so that `pnr_v2/design_setup.tcl` can read `unpu_top_cn.dc.v` and `unpu_top_cn.sdc` from there.

## The old constraints (user decision 2026-11-02, "clean slate")

Period 20 ns; setup uncertainty 1.5, hold uncertainty 0.5; clock transition 0.6; APB in/out 35 percent of the period, DMA in/out 40 percent, `rst_n` 40 percent; input min delay 0, output min delay -0.5; driving cell `buffd1` pin `Z`; input wire load 0.2 pF;
output load 1.0 pF; max transition 3.0 ns; max capacitance 2.0 pF. Their only authoritative form is the file `git show 925bfa9:constraints/pm_unpu_top.sdc` (a pure SDC with the table of numbers at the top). Do not retype the numbers.

## Files

- Create `constraints/legacy/unpu_top_legacy.sdc` = `git show 925bfa9:constraints/pm_unpu_top.sdc`, byte for byte (acceptance 1). Do not edit it.
- Create `constraints/legacy/dc_script_legacy.tcl`: the DC flow script. Base: the COMMITTED `constraints/pm_dc_script_unpu.tcl` at HEAD (it has the task-055 fixes: fatal guards, `exit`, scratch directory, exact output-file check, `change_names` to `_cn`). Do NOT base it on the working-tree
  version (it holds the half-done, unaccepted task 059 changes). Differences from the base, and only these:
  - no `UNPU_STAGE`, no `stage_numbers.tcl`, no profile table; it `read_sdc`s `constraints/legacy/unpu_top_legacy.sdc`;
  - the numbers that the base takes from the profile (clock period, uncertainties) for its read-back check and its report headers are read back from the SDC's own `set CLK_PERIOD` / `CLK_UNCERT_*` lines by a small pure-Tcl reader
    (strict: a missing or non-numeric line stops the script), or the check compares the tool's clock period with 20.0 and the headers print "legacy constraints"; your choice, say which and why;
  - outputs go to `syn/out/legacy/` (scratch dir `syn/out/work/legacy/`); the output set equals a profile run's EXCEPT the SDF (no `write_sdf`: that is task 059, not accepted); the end-of-script directory check expects exactly that set;
  - the header comment says: purpose (clean-slate run 2026-11-02), what it reads, where it writes, that it must not be edited to close timing.
- Create `syn/RUNBOOK_legacy.md`: one page, csh, one command per line: the run command (`dc_shell -f constraints/legacy/dc_script_legacy.tcl | tee syn/out/legacy_dc.log` or the form `syn/RUNBOOK.md` uses), what to look for in the log and in the reports
  (all constraints MET or `max_area` only, no latch, no don't-use cell, flop count 2,465, area), where the files land, the follow-up (`pnr_v2/`).
- Do NOT modify any existing file under `constraints/`, `syn/` (except the new RUNBOOK_legacy.md), `pnr/`, `pnr_v2/`.

## Acceptance test

1. `git show 925bfa9:constraints/pm_unpu_top.sdc | cmp - constraints/legacy/unpu_top_legacy.sdc` prints nothing.
2. The script is complete Tcl (`info complete`) and a stub run (the same stub technique as `constraints/test_dc_script.tcl`: fake `dc_shell` commands that log themselves) runs to the end and shows: the command sequence (library setup, analyze/elaborate, `read_sdc` of the legacy SDC,
   compile, reports, writes), the output set in `syn/out/legacy/`, and the failure paths: SDC file missing (STOP), clock period read back != 20 (STOP), an expected output file missing or empty (STOP). Put the stub test in `constraints/legacy/test_legacy_dc_script.tcl`; it passes with `tclsh`.
3. `grep -n "UNPU_STAGE\|stage_numbers\|write_sdf" constraints/legacy/dc_script_legacy.tcl` shows nothing outside comments.
4. The existing tests still pass: `tclsh constraints/test_stages.tcl`, `tclsh constraints/test_dc_script.tcl`.
5. `git status`: new files only in `constraints/legacy/` and `syn/RUNBOOK_legacy.md` (plus what the earlier uncommitted tasks and 063 already changed). Do not commit. Do not run anything on the server.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." The old numbers are the user's decision; the script never changes them.
Don't-use list, library setup and compile options stay exactly as in the base script. RTL frozen.

## Out of scope

Gate-level simulation (the next task, after the netlist exists), `pnr_v2/`, SDF, power-aware anything, running on the server, committing.

## Report back

Files created, the stub-run output (sequence and the three failure paths), acceptance 1 to 5, the choice for the read-back (point 2 of the script differences), anything in this prompt that is wrong or ambiguous. Stop after reporting.
