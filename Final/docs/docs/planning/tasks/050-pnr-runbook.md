# Task 050 — `pnr/RUNBOOK.md`: the run order, command by command, for the user at the server

Read first: `pnr/README.md`, the Part C blocks you wrote in the reports of tasks 038 to 049 (they are the source), `pnr/VERIFY_STATUS.md`,
`docs/session-handoff.md` 18.4 (server setup; the user's shell is csh), 18.28.

## Goal

One document the user can follow at the server without hunting through reports: every script of the flow in order, with the exact csh
commands, what to look for, what to copy back, and what to do when it fails. Plus one small cleanup.

## Part A — what to write

### A1. `pnr/RUNBOOK.md`

- A short front part: the layout of the work directory (`UNPU_WORK`, `ndm/`, `run1/{logs,rpt,lib,out,calibre}`), the environment
  variables to set once (`UNPU_REPO` is only a convention for the commands; the scripts find the repo from their own location), the two shells
  (`icc2_lm_shell` by its full path, `icc2_shell`), `source ~/cad_cshrc` then `source ~/synopsys_cshrc`, and the rule that every command is
  one line in csh.
- Then one section per step, in this order: (0) the optional probes, (1) `ndm_file_gen.tcl` in mode `two` (default) with
  `UNPU_NDM_OVERWRITE 1` when the NDM exists, (2) `ndm_check.tcl`, (3) `design_setup.tcl`, (4) `floorplan.tcl`, (5) `power.tcl`,
  (6) `pin_place.tcl`, (7) `placement.tcl`, (8) `cts.tcl`, (9) `route.tcl`, (10) `fill.tcl`, (11) `outputs.tcl`. Each section: the shell and the
  command (with `-file` and `-output_log_file`), the block it needs and the block it saves, the run time you know, the lines of a good result
  (CHECK/RESULT names, the numbers you know from the first run and the plan), the usual failures you predicted (for example the pin side numbers,
  the `report_corners` parser, the follow-ups listed in `VERIFY_STATUS.md`), and how to re-run it (nothing saved on a failed run; new
  `UNPU_BLK_*` name or `UNPU_RUN_TAG` after a successful one).
- Then: the hold-uncertainty experiment (`UNPU_CTS_STAGE hold`, `UNPU_HOLD_UNCERT`, `UNPU_BLK_CLKOPT`, and how `route.tcl` starts from it);
  the `UNPU_ROUTE_ACCEPT_HOLD` switch (never default; written reason first); the fill hold residual rule.
- Then the copy-back section: the `scp` commands with the user's server `EE5239G1@172.16.82.70` and `~/server_pull/` as the destination, run in a
  laptop terminal (WSL), one for `rpt`, one for `logs`, one for the `out` folder EXCLUDING the large files (list which files are big: SPEF, GDS), and
  how to name the destination per run tag so earlier pulls are not overwritten. No password appears anywhere.
- A last section "after the ICC2 flow": a numbered list of what is not scripted yet (Calibre DRC/antenna/LVS, PrimeTime, post-layout simulation)
  so nobody thinks the flow ends at `outputs.tcl`.
- Keep it factual and short per step; every number must come from a script, a report of yours or the handoff; mark the ones that are guesses.

### A2. Cleanup

`HPWL_DETOUR` is defined twice in `pnr/params.tcl` (lines near 260 and 291; same value). Remove the second definition and the redundant comment, keep one
with the plan reference. Check that no other parameter is defined twice (a small grep/Tcl check; if it is cheap, add it as a test that fails on a duplicate
`set NAME` at the top level of params.tcl). Update the tests if they count parameters.

## Part B — checks

1. `tclsh pnr/test_common.tcl` passes (show the output); all `pnr/*.tcl` complete Tcl.
2. `grep`: no password text, no `/home` path, no `~/server_pull` reference as a script input in the RUNBOOK commands except as the scp destination.
3. Every command in the RUNBOOK that is a script invocation names a file that exists in `pnr/`; show the check (a loop over the RUNBOOK lines).
4. `git status`: only `pnr/` changed. Do not commit.

## Report back

The RUNBOOK section titles, Part B output, anything in this prompt that is wrong or ambiguous. Stop after reporting.

## Out of scope

New stage scripts, Calibre, PrimeTime, simulation; `rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on the server; committing.
