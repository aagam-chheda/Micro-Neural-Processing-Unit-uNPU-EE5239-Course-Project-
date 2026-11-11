# Task 072 — Timing closure pass after the antenna ECOs: `route_opt` again with the ECO cells protected (step 6e, `pnr_v2/timing_closure.tcl`)

Read first: `pnr_v2/route.tcl` (the whole script: scenarios, the temporary optimisation uncertainty and its restore, app options, `route_opt`, filler insertion, `route_eco` / `route_detail`, checks), `pnr_v2/antenna_port_buffers.tcl` and `pnr_v2/antenna_clk_root.tcl` (naming of the ECO cells, filler handling, checks, style), `pnr_v2/cts.tcl` (the same uncertainty handling), `docs/session-handoff.md` 18.32 and 18.33, `pnr_v2/README.md`.

## State (facts from the server runs of 2026-11-09)

- Exported layout: Calibre DRC 404 rules 0 results, antenna 16 rules 0 results. This must still be true after this task (the user re-runs Calibre; ICC2 cannot judge antenna on port nets).
- Timing of the exported state (`pnr_icc2/reports/unpu_top_final_global_timing.rpt`): setup WNS -0.10 ns, 2 violating paths, both in-to-out (`paddr[3]` -> `prdata[5]` and a second one); hold 53 violations, WNS -0.04 ns, TNS -0.73 ns (reg-to-reg 15, reg-to-out 38). Before the clock-root change (task 071) hold was 21 violations, WNS -0.015.
- In `route.tcl` the optimiser (`route_opt`, spec uncertainties 1.5 setup / 0.5 hold plus goal 0.0) ended with setup WNS 0.0000 and 15 hold violations (-0.0145); the later steps (fillers, `route_detail`, two `route_eco`) moved setup to -0.07; the antenna ECOs (fix passes, port buffers, clock root) moved it to -0.10 and hold to -0.04.
- The 15 port buffers `antbuf_*` (reference `buffd1`, one per offending input port net, placed on free filler sites next to the pins) and the clock root `ZCTSINV_121581_2576` (now `inv0d4`) exist ONLY to satisfy the antenna rule. If the optimiser resizes, moves or removes them, the antenna results return. They must be protected.
- Fillers (`feedth`, `feedth3`, `feedth9`, 21.6k cells created by `create_stdcell_fillers` in `route.tcl`) occupy every free site; an optimiser that needs a bigger cell or a new hold buffer has no room until they are removed. `route.tcl` itself inserts them AFTER `route_opt` for that reason.

## Goal

A script `pnr_v2/timing_closure.tcl` (flow step 6e, after `antenna_clk_root.tcl` and before `metal_fill.tcl`) that runs a final optimisation pass with the same goals and options as `route.tcl`, with the antenna cells protected and the fillers out of the way, then restores the fillers, re-routes, checks, and overwrites `unpu_top_route` in place. No constraint, uncertainty, goal or limit is changed: the optimiser sees exactly what `route.tcl` gave it (setup uncertainty 1.5, hold 0.5, goals 0.0; the restore at the end puts back the spec values).

## Behaviour (decide the ICC2 commands from the help texts in `/home/aagam_chheda/server_pull/rpt/help`; mark each unverified command `VERIFY`)

1. Open `unpu_top_route`. Copy from `route.tcl`, not from memory: the scenario and corner setup, `set_clock_uncertainty` with `SPEC_*` and `*_SLACK_GOAL`, the app options, the hold and optimisation cell purposes, the routing settings. Print the values used (they must equal route.tcl's: 1.5 / 0.5 / 0.0 / 0.0).
2. BEFORE metrics, printed: `report_global_timing`, setup and hold WNS/TNS/NUM per group, the worst setup path of the `in2out` group in full (so the user can see which cells are on it), the worst hold path of `reg2out` in full, `report_clock_qor` summary text, `check_routes` counts. Also print the number of cells, the total cell area and the number of buffer/inverter cells.
3. Protect the ECO cells: all instances whose name starts with `antbuf_` (prefix as a parameter, matching what `antenna_port_buffers.tcl` creates) and the root cell of the `clk` net (the single leaf load of the `clk` port net: take it from the design). Use `set_dont_touch` (VERIFY the command and that it blocks resizing, moving and removal in `route_opt`) and, if available, `set_size_only` is NOT enough (it allows moving); print the list of protected cells with reference and location. Snapshot for each protected cell: reference name, origin, orientation, the nets on every pin.
4. Remove the fillers exactly as the antenna scripts do (the table-based method of task 070, not a geometric `-intersect` query; `get_cells -filter` by `ref_name`), keeping the count. The protected buffers sit on sites that were fillers; do not touch them.
5. Run `route_opt` (same call and options as `route.tcl`; hold fixing stays on). Loop at most `MAX_PASSES` times (parameter, default 3): after each pass print setup and hold WNS/TNS/NUM; stop when setup WNS >= 0 and hold WNS >= 0, or when a pass does not improve either WNS by more than 0.001 ns (print why it stopped). Never raise a goal or an uncertainty between passes.
6. Legalise, re-create the fillers as `route.tcl` does, `connect_pg_net`, then `route_detail -incremental` and `route_eco` as in `route.tcl` (the clock routing rule line as in `antenna_clk_root.tcl`), then `check_routes`. Restore the spec uncertainties (setup 1.5, hold 0.5) as `route.tcl` does.
7. Checks, each a number and a hard `error` if wrong; NOTHING is saved on error: `check_routes` DRC = 0, open nets = 0; `check_legality` 0 violations; every protected cell has the same reference, the same origin and orientation, the same pin connections as in the snapshot; the count of `antbuf_*` is unchanged; the root's reference is unchanged; the filler count is within 1 percent of the count before step 4 or the difference is explained in one printed line.
8. AFTER metrics, same as BEFORE, plus the number of cells/area/buffers added (hold buffers). Print `>>> 072 VERDICT` with one of: `CLOSED` (setup WNS >= 0 and hold WNS >= 0), `IMPROVED` (both WNS did not get worse and at least one improved), `WORSE` (any WNS dropped by more than 0.005 ns), `UNKNOWN` (a number could not be read: never printed as `CLOSED`). `IMPROVED`/`WORSE`/`UNKNOWN` do not stop the script; the README tells the user to read the numbers and, if `WORSE`, restore the backup.
9. `save_block` over `${DESIGN_NAME}_route`, `save_lib`, print `>>> STAGE 6e COMPLETE: ...` including the verdict.

## README (`pnr_v2/README.md`)

Add step 6e to the run order (after 6d, before metal fill), and to the section "Loop after the Calibre antenna run" the 6e lines, ONE csh command per line: the library backup `cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_closure`, `icc2_shell -f ../pnr_v2/timing_closure.tcl |& tee timing_closure_console.log`, then `metal_fill.tcl`, `pv.tcl`, the two Calibre commands, and what to read: the BEFORE/AFTER tables, the verdict, the protected-cell checks, Calibre DRC 0 and antenna 0 (if antenna is not 0 again, say which cells changed).

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No uncertainty, goal, SDC value, limit or app option is changed relative to `route.tcl` (list any option you ADD, with the reason, in the report: the user must approve it). The protected cells are not edited. No diode, no waiver. Do not touch the other flow scripts. Do not run anything on the server, do not commit.

## Acceptance test (local, no server)

1. `info complete` = 1 for `pnr_v2/timing_closure.tcl`; the earlier tests (`test_antenna_port_buffers.tcl`, `test_antenna_clk_root.tcl`) still pass.
2. `pnr_v2/test_timing_closure.tcl` (passes with `tclsh`) for the pure-Tcl parts: the pass-loop decision (stop on closed, on no improvement, on the maximum), the verdict (`CLOSED` / `IMPROVED` / `WORSE` / `UNKNOWN`) for several before/after tables including the real numbers above, the protected-cell snapshot comparison (changed reference, moved origin, changed connection each detected), and the filler-count check.
3. A table in the report: every value copied from `route.tcl` (name, value, line in `route.tcl`) and the one-to-one comparison with what `timing_closure.tcl` sets (they must be identical).
4. `grep -c "072" pnr_v2/timing_closure.tcl` and the list of every `VERIFY` item, each with what the user should look at in the log.
5. `git status`: only `pnr_v2/timing_closure.tcl`, `pnr_v2/test_timing_closure.tcl`, `pnr_v2/README.md`, plus this task file.

## Report back

Files changed, test output, the option table of point 3, the `VERIFY` list, how the protection is implemented and what you expect `route_opt` to do on the two failing in-to-out paths (which cells it can resize), anything ambiguous. Stop after reporting.
