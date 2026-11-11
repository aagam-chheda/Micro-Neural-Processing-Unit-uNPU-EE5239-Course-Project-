# Task 080 — Keep the hold ECO out of the input-to-output (in2out) paths, and gate the ICC2 apply on the in2out result

Read first: `docs/planning/progress-log-2026-11-09.md` (3.11, 3.12), `docs/planning/tasks/078-pt-violation-lists-and-eco-probe.md`, `docs/planning/tasks/079-apply-pt-eco-in-icc2.md`, `pnr_v2/pt/pt_eco_probe.tcl`, `pnr_v2/pt/pt_eco_setup_probe.tcl`, `pnr_v2/pt/pt_common.tcl`, `pnr_v2/pt_eco_apply.tcl`.

## What happened (user's server run, 2026-11-09, ICC2 apply at commit `31427af`)

- PrimeTime hold ECO (probe at ff, `fix_eco_timing -type hold -methods {insert_buffer}`, buffer list = collection of `dl*` + `buffd1`) proposed 109 `insert_buffer` commands that bring hold in PrimeTime's memory from 263 violators (WNS -0.3468 ns) to 0 (WNS +0.0002). PrimeTime's setup ECO proposed `size_cell {HFSINV_13_284} {inv0d7}` (setup 1 violator -> 0).
- The ICC2 apply (all 110 changes accepted, tier 2 used for some, `STAGE 6g COMPLETE: 109 cells inserted, 1 cells resized, 19 on the ANTENNA WATCH list`) then reported, in ICC2's own analysis after the ECO: `AFTER SETUP (func_ss): WNS -0.589873 ns, TNS -12.2922 ns, violating endpoints 32`, ALL in the group `**in2out_default**`; `AFTER HOLD (func_ff): WNS -0.011719 ns, TNS -0.0178 ns, violating endpoints 4`.
- Before the ECO the in2out group (the combinational APB read path `paddr` -> ... -> `prdata`, budget 20 - 1.5 - 7 - 7 = 4.5 ns with about zero margin; PrimeTime: "No paths with slack less than 0.00" for it) was met in both tools. This path does not depend on the clock-latency convention, so both tools agree.
- Cause: hold-ECO delay cells (`dl01d1`, `dl02d1`, 0.4 to 0.9 ns each at ss) were inserted at shared points of the APB block (examples from the change list: `u_apb/U46/Z`, `u_apb/U61/Z`, `u_apb/U29/Z` and similar in `u_csr`) whose nets also feed the read mux. PrimeTime's hold ECO runs in a single fast-corner session and cannot see the setup damage at ss.

## Goal

(1) In the PrimeTime hold-ECO session, keep the ECO out of every cell and net that lies on an input-to-output path (`set_dont_touch` or the ECO's own exclusion option; the dont_touch must be in effect during `fix_eco_timing` only; it changes no constraint and no netlist), so that the 255 input-to-register hold violators are fixed elsewhere (at load pins of the flops, deeper in the register fan-in, etc.). (2) In `pt_eco_apply.tcl` add a hard gate on the in2out group (and on the whole setup WNS): if after the ECO the in2out group (or the setup WNS) is worse than before by more than a named tolerance, the script stops BEFORE saving and says so, with both numbers. The parameter defaults and reasons are yours to set from the facts (ICC2's before value is +0.0143 ns for the whole design; tolerance a few ps; name it; give the reason).

## Part 1 — `pt_eco_probe.tcl` (hold ECO at ff): protect the in2out cone

1. After the preparation and before `fix_eco_timing`, compute the in2out cone from the timing graph in the ff session: all cells and nets on any timing path from an input port to an output port (`get_timing_paths -from [all_inputs] -to [all_outputs]` with a large `-max_paths`/`-nworst` and the path points, or the fan-in cone of the output ports restricted to data paths that start at input ports; choose the PrimeTime method that is exact and affordable; clock-network cells excluded). The cone includes the `u_apb`/`u_csr` read mux cells. Print the number of cells and nets, the first 20 names, and the number of hold violators whose worst path touches the cone.
2. Apply `set_dont_touch` on those cells and nets (VERIFY the command form; print how it was applied and read back an attribute for a sample of 3 objects), run the ECO, then REMOVE the dont_touch again (the session is read-only for the design files anyway; the ECO result is a change file).
3. Print, before and after the ECO, the hold status and the list of violators that remain, and WHY any remain (for example: all fix points are in the protected cone). Write the same change files as now.
4. Add an AFTER check that no proposed insertion/resize touches an object of the cone: parse the change file, resolve every insertion pin / resized cell to its cell and compare with the protected cell names; any hit is reported and makes the probe end with a clear PROBE RESULT line (`ECO RAN BUT TOUCHES THE IN2OUT CONE: ...`).
5. Do the same protection in `pt_eco_setup_probe.tcl` (the setup ECO there resizes cells; resizing `HFSINV_13_284` is not in the cone; a resize of a cone cell would be a speed-up and is fine: do NOT protect the cone from `size_cell` in the setup probe; only print which proposed changes touch it).

## Part 2 — `pt_eco_apply.tcl`: gate on the in2out group

1. The script already prints BEFORE and AFTER setup/hold per scenario and per path group (lines `>>> 072 079 BEFORE ...`/`AFTER ...`). Make a hard check from them: the setup WNS of the group `**in2out_default**` (if the group name is not found, use the worst setup path among those that start at an input port and end at an output port; mark VERIFY) and of the whole design must not drop below (before - tolerance); on violation: `ERROR 079: the ECO made the in2out group worse (before X, after Y, tolerance T): nothing saved` BEFORE `save_block`. Also print the number of violating endpoints before and after.
2. Add the same kind of check for hold (whole design): not worse than before by more than a named tolerance (hold before-ECO in ICC2 is -0.0004 to -0.00258 ns depending on state; the user-visible target is PrimeTime's), reported as WARNING not error (PrimeTime is the sign-off for hold).
3. Tests for the decision function (equal, slightly worse inside tolerance, worse outside tolerance, unreadable -> error, the real numbers: before +0.0143, after -0.5899 -> error).

## README

`pnr_v2/pt/README.md` section 8/9: why the cone is protected (the incident above, with the numbers), the new log lines, and the new sequence for a rerun (restore the library from `bak_pre_pteco`, rerun the hold probe, then the apply). `pnr_v2/README.md` step 6g: the gate.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No constraint, SDC value or limit changes. The dont_touch is applied only inside the probe's PrimeTime session and removed. Do not run anything on the server, do not commit.

## Acceptance test (local)

1. `info complete` for all changed Tcl files; all existing tests pass (`pt/test_pt_common`, `test_pt_eco_apply`, `test_antenna_*`, `test_timing_closure`, `test_pv_*`).
2. New tests for: the cone-membership check on a change file (a change on a cone cell -> reported; none -> clean), the gate decision, the new PROBE RESULT line.
3. `grep -c VERIFY` and the full VERIFY list in the READMEs.
4. `git status`: only `pnr_v2/` files and this task file.

## Report back

Files, diffs, test output, the VERIFY list, how you compute the cone (exactness, cost), what you expect to remain unfixed if the cone blocks all fix points, anything ambiguous. Stop after reporting.
