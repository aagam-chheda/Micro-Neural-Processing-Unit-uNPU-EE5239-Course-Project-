# Re-run script tasks: review log (Planning)

One entry per task and per review round. Used for the final summary. Nothing here is a task prompt.

## Task 038: params.tcl, common.tcl, ndm_file_gen.tcl, ndm_check.tcl, test_common.tcl, README.md

### Round 1 (2026-11-01), Execution report received, files read in full, tests re-run by Planning

Independently verified by Planning: `tclsh pnr/test_common.tcl` gives 46 passed, 0 failed; `info complete` is 1 for all five
`.tcl` files; no change under `rtl/`, `constraints/`, `syn/`; no `FOUNDRY`; the only absolute `/storage` paths in `pnr/*.tcl` are
the two defaults in `params.tcl`.

Planning's own error found by Execution: core area is 856.8 x 856.8 = 734,106.24 um2, not 734,090 as written in plan 2.2 (the
core side, 153 rows and the 66.0% figure were right). Plan corrected.

Changes requested (sent to Execution):
1. MUST: remove the second `read_lef feedth.lef` in mode single. The kit LEF read in step 4 already holds the three MACROs; a
   second read of known MACROs may be an error, and `unpu_run_logged` would then die before any diagnostics. `lef_macros_read`
   must count what was actually read.
2. MUST: check the result of `check_workspace` (the first run printed "Workspace check succeeded!"); do not ignore its output.
3. SHOULD: wording of the mode-single warning: `get_lib_cells` may not list physical-only cells that are in the workspace, so
   "0 of 3" is a hint, not proof; `ndm_check.tcl` is the verdict.
4. SHOULD: `ndm_check.tcl` scratch library name with a timestamp so a re-check needs no new run tag.
5. SHOULD: validate `HOLD_UNCERT` (numeric, not negative) and that `CORE_OFFSET` is a whole number of sites and rows; round the
   boundary numbers to 4 decimals so floating-point tails never reach `initialize_floorplan`; print a Warning when
   `UNPU_DIE_SIZE` or `UNPU_HOLD_UNCERT` differs from the plan default.
6. SHOULD: `unpu_checkpoint` also calls `save_lib` after reopening (VERIFY); `unpu_open_stage` and `unpu_checkpoint` accept only
   an exact block name, not any name containing it.
7. SHOULD: `UNPU_SKIP_VERSION_CHECK` use is recorded in the manifest.
8. MINOR: `unpu_run_logged` prints what it captured before dying on a failed command.
9. The server block in Part C used a guessed clone path (`~/aagams_workspace/unpu`); the user's server clone is
   `/storage/EE5239G1/aagams_workspace/unpu_without_claude`. Part C is rewritten by Planning for the user; no change in code.

Accepted as proposed: derive REPO_ROOT from params.tcl's own location; `UNPU_CHECK_CONTINUE` and `unpu_checks_finish`;
manifest of the NDM stage in `$NDM_DIR`; vacuous passes covered by `fillers_exact`; `mx08d*` absent from the NDMs; tolerance 1e-6;
the extra environment knobs (`UNPU_DIE_SIZE`, `UNPU_HOLD_UNCERT`, `UNPU_ICC2_ROOT`) and the kit-write guard; answer to
Execution's question (d): do NOT stop before committing in mode single, the NDM check decides.

Open until the server run: every VERIFY item (shell options, version variable, `redirect -variable`, `physical_only` with
`-technology`, `get_lib_cells` in a workspace, `-ref_libs` with a list). Whether mode single can work at all is unknown; if it
fails, a follow-up task will investigate (a timing view for the fillers, or accepting two NDMs built in one run).

### Round 2 (2026-11-01), revised files read, tests re-run by Planning

Independently verified: `tclsh pnr/test_common.tcl` gives 70 passed, 0 failed; all five `.tcl` files complete; nothing outside
`pnr/` changed. Read the changed parts: `ndm_file_gen.tcl` (single `read_lef` in mode single, `ndm_check_workspace` requires
"Workspace check succeeded", warning reworded, `lef_macros_read` counted), `params.tcl` (validation, `unpu_round4`, `PLAN_*`
defaults with Warning on experiment knobs, offset checks), `common.tcl` (`unpu_block_name_matches` exact match,
`unpu_checkpoint` with `save_lib`, `unpu_run_logged` prints captured text on failure, manifest records the version check).

Accepted. All nine items done, no disagreements. Remaining risk, all server-side: every VERIFY item of round 1, and one new
one: the empty-capture case of `ndm_check_workspace` is a Warning, so if `redirect -variable` does not capture shell messages
the success text of `check_workspace` is not verified and must be read in the log. Execution's note: `UNPU_REPO` appears only in
header comments (no script reads it); fine.

Nothing committed yet (Planning waits for the user's word; the files must be committed and pulled on the server before a run).

## Task 039: design_setup.tcl

Sent after round 2 of 038. Scope: library creation, TLUPlus, netlist and SDC read, corners and scenarios, count checks, the
first checkpoint block; plus additive edits to the 038 files (new parameters, `unpu_read_ndm_manifest`).

### Task 039, round 1 (2026-11-01): accepted

Independently verified: `tclsh pnr/test_common.tcl` 111 passed, 0 failed; all six `.tcl` files complete; only `pnr/` changed;
no absolute `/storage` path besides the two defaults. Read `design_setup.tcl` in full and the new `common.tcl` procedures'
use. Command order matches the prompt and 18.11 to 18.13; failure paths and parsers are covered by tests.

Execution's questions answered: (a) the unknown `report_corners` layout is handled by a check that fails with the numbers it
saw, so the first real run may need one parser fix (paste `design_setup_corners.rpt` back); (b) the `check_timing` warning count
is a Warning, not a die; (c) checks in continue mode and stop before `save_block`: accepted (the rerun needs
`UNPU_LIB_OVERWRITE=1`); (d) an expected SDC id that is absent is silent in the second read: for the FIRST read it becomes a
Warning (folded into task 040); (e) text slack values: accepted; (g) printing the whole short reports: accepted.

Observation (small): `design_setup.tcl` leaves `ff_hold` as the current scenario after the first-timing step. Fixed by making
`default` current again before `save_block` and by a comment that no stage may rely on the current scenario (folded into 040).

Residual risk, all server-side: `current_scenario <name>`, the `report_corners`/`report_ref_libs` layouts, `get_timing_paths`
and `slack`, `create_lib -ref_libs` with a list, `redirect -file/-variable` capturing messages, the exact wording of the link
messages.

## Task 040: floorplan.tcl

Scope: `initialize_floorplan` with the boundary-is-core rule, die/rows/site/area checks, don't-use cells (18 = 15 + 3), next
checkpoint `fp`; plus two follow-ups to `design_setup.tcl` and a pure-Tcl parser for `report_design -floorplan`.

### Task 040, round 1 (2026-11-01): accepted with one follow-up

Independently verified: `tclsh pnr/test_common.tcl` 125 passed, 0 failed; all seven `.tcl` files complete; only `pnr/` changed.
Read `floorplan.tcl` in full: the 18.14 mistake is in a comment and `FP_BOUNDARY` is built as core + offset; checks cover die
bbox, rows, site (Warning if unreadable), chip and core area from `report_design -floorplan`, don't-use matched 15 and total 18
and the three library-flagged cells; the checkpoint is after `unpu_checks_finish`; the guards (rows before = 0, block `fp` must
not exist) are sensible.

Added by Execution beyond the prompt, accepted: `DONT_USE_EXPECT_EMPTY`, `SITE_NAME`, the guard against an existing `fp` block.

Correction of Execution's rerun recipe (ambiguity c): if `floorplan.tcl` fails before `block_saved`, nothing was saved and the
script can simply be run again (the block on disk is unchanged); only after a SUCCESSFUL run does a different floorplan need a new
run tag or `UNPU_LIB_OVERWRITE=1` with `design_setup.tcl` rerun. The script's header and Part C say the opposite for the first
case; fixed in task 041 (A2). Whether a `remove_blocks` command exists and works here is unknown and not relied on.

Residual risk (server only): `get_site_rows`, the site attributes, the `report_design -floorplan` layout, `boundary_bbox` format,
`get_blocks -quiet`, the `-filter "dont_use==true"` form.

## Task 041: power.tcl

Scope: PG nets, `connect_pg_net`, M1 rails + TOP_M stripes (18.15 commands), stripes read once from the database, bottom
extension shapes and exactly one terminal per stripe (the 18.21 duplicate-terminal mistake designed out), counts and DRC /
connectivity checks, checkpoint `pwr`.

### Task 041, round 1 (2026-11-01): accepted

Independently verified: `tclsh pnr/test_common.tcl` 156 passed, 0 failed; all eight `.tcl` files complete; only `pnr/` changed.
Read `power.tcl` in full: stripe list read once, loop over that list, first stripe made and checked alone, 17 checks including
count/duplicate/x-range/lowest-y/inside-die for terminals (the 18.21 duplicate is a test case), `connect_pg_net` counts against
`EXPECT_LEAF_CELLS`, rails against rows + 1, DRC and connectivity parsers (unparsed text FAILS, never passes), checkpoint after
`unpu_checks_finish`. The five grid commands are built from parameters and compared in tests with the 18.15 text. Header rerun note
now correct in `floorplan.tcl` and `power.tcl`.

Additions by Execution accepted: `PG_PIN_BOTTOM_Y`, `PG_STRIPE_SHAPE_USE`, `PG_RAIL_SHAPE_USE follow_pin` (a guess, flagged),
`PG_TOLERANCE`. Their ambiguity (d) is real: if `compile_pg` leaves other M1 shapes on the two nets the fallback rail count can exceed
rows + 1; the log names the filter used, so the first server run will show it.

Planning observation: five stage scripts are now written and none has run on a real tool. The unknowns are concentrated in
output layouts and command forms. Decision taken: before writing the placement, CTS and routing scripts, collect the real usage
text of every command (task 042, a probe the user runs once) so that those scripts are written against facts. Recommendation to the
user: commit and pull `pnr/`, and run the five finished scripts on the server before the later ones are reviewed.

## Task 042: help_probe.tcl and help_probe_lm.tcl

Scope: print `-help` of every command of the flow, the commands matching name patterns, and the application options matching
patterns, into `$RPT_DIR/help/`; one summary and one concatenated file for pasting; find out how the tool release string is
exposed. No design, no library, no state change.

### Task 042, round 1 (2026-11-01): accepted

Independently verified: `tclsh pnr/test_common.tcl` 181 passed, 0 failed; all ten `.tcl` files complete; only `pnr/` changed.
Read `help_probe.tcl` and the probe procedures in `common.tcl`: each probe in its own `catch`, text judged before the error code,
`-help` then `help <cmd>`, `report_app_options` then `get_app_options`, all help text to files through `redirect -file`
(no pager), nothing opened or created, exit 0 with a Warning per missing command. The probe lists cover every tool command with a
`VERIFY` comment; the 27 identifiers not in a list are attributes, options, variables or our own procedures (checked in the report).
Extras accepted: `all_wildcards.txt`, `all_appopts.txt`, extra commands in the lists.

Their ambiguity (b): `report_app_options` may print thousands of lines. Decision: keep as is; if the pasted files are too big
the user pastes per-probe files, and I name which ones.

Needs the user: the probe cannot run until `pnr/` is committed, pushed and pulled on the server. The results decide the syntax of
`pin_place.tcl` and `placement.tcl` (`place_pins`, `set_block_pin_constraints`, `create_placement`, `place_opt` options), so those two
tasks wait for the probe output. The tasks that only use commands shown in the handoff (CTS, routing, fill, outputs) continue.

## Task 043: cts.tcl

Scope: `set_lib_cell_purpose -exclude cts`, `clock_opt -to build_clock` (checkpoint `cts`), explicit `set_clock_uncertainty -hold
$HOLD_UNCERT`, `clock_opt -from route_clock -to final_opto` (checkpoint `clkopt`), `FLW-8004` counted and reported, setup /
legality / PG / transition / capacitance as checks, remaining hold endpoints as a Warning with the worst list (plan C2).

### Task 043, round 1 (2026-11-01): accepted with one design change

Independently verified: `tclsh pnr/test_common.tcl` 203 passed, 0 failed; all eleven `.tcl` files complete; only `pnr/` changed.
Read `cts.tcl` in full: legality of the placed block checked and a failure stops before any tree is built; the sink count is a check
and an unparsable QoR text fails it; the tree is checkpointed before the hold uncertainty is touched; the uncertainty is read back
and a mismatch stops before the long optimisation; `FLW-8004` counted and reported; setup, transition, capacitance, legality and PG
connectivity are checks and "unavailable" fails; remaining hold endpoints are a Warning with the worst ten, as the plan says.
Additions accepted: `EXPECT_CTS_EXCLUDED`, `TIMING_MAX_PATHS`, `HOLD_ENDPOINTS_LISTED`, the two mid-run stops.

Design change decided (their ambiguity a): the guard "cts or clkopt must not exist" makes a hold-uncertainty experiment impossible
without a new library, and the experiment is exactly what the 0.5 ns decision needs (the first run did it from `unpu_top_cts`).
Folded into task 044: `UNPU_CTS_STAGE` = all | tree | hold, and a general `UNPU_BLK_<NAME>` override for every checkpoint block name so
several experiments can live in one library and later stages can start from any of them.

Their ambiguities (b, c): the violating-endpoint count uses `report_timing -slack_lesser_than 0 -max_paths 100000`, which may print
several paths per endpoint and may be rejected by the shell; after the help probe is read it may be replaced by a better count command.
Marked as a revisit item, not changed now.

## Task 044: route.tcl

Scope: `define_antenna_rule` BEFORE routing (the first run routed with no rule: `ZRT-309`); `route_auto` (checkpoint `routeauto`), `route_opt`,
`check_routes` summary / `check_lvs` / legality / PG / timing as checks; hold is a check at this stage with an explicit, never-default
`UNPU_ROUTE_ACCEPT_HOLD` switch; ICC2's blind spot (the 80 skipped port nets) printed; fillers and diodes out of scope; plus the
`cts.tcl` stage switch and the `BLK_*` override.

### Task 044, round 1 (2026-11-01): accepted with one follow-up

Independently verified: `tclsh pnr/test_common.tcl` 240 passed, 0 failed; all twelve `.tcl` files complete; only `pnr/` changed.
Read `route.tcl` in full: `define_antenna_rule` precedes `route_auto`; `ZRT-309` is a check on both route commands; no diode option and
no fixing preference; `routeauto` is saved only if the critical checks pass; after `route_opt` every check is a CHECK (open nets, DRCs,
ICC2 antenna, shorts/opens/floating, legality, PG connectivity, setup, hold, transition, capacitance); the ZRT-311 port nets are counted
and listed with the statement that Calibre decides; hold has the explicit never-default `UNPU_ROUTE_ACCEPT_HOLD` that can only accept a
KNOWN positive count and records the endpoints in the manifest; the last line says the block is unfilled on purpose.
`cts.tcl` stage modes and the `UNPU_BLK_*` override are as designed (stub shows `clkopt_h02`, `clkopt_h03` coexisting; route starts from
`clkopt_h02`). Rename `ct_*` to `unpu_*`: accepted.

Follow-up (small, folded into the next task that touches `route.tcl`): after the antenna rule is defined, read the value of
`route.detail.antenna` and make a Warning of anything but true (the router only fixes antennas if it is on; the first run's log
showed it on after a rule existed, but that was set by hand in that session). The help probe will say what the default is.

## Task 045: fill.tcl

Scope: filler cells (`feedth*` typed filler, checked), `create_stdcell_fillers ... post_route_auto_delete`, `connect_pg_net -automatic` at once,
pin count = 2 x fillers, a filler COVERAGE check (the first run's numbers are exact: 70,686 free sites = 9 x 4,159 + 3 x 7,451 + 10,902),
violations of fillers, legality / PG / routes / timing, hold residual rule from the decision of 2026-10-29 (sub-picosecond accepted,
anything larger fails), checkpoint `final`; fill is the last step.

### Task 045 (and the 044 follow-up), round 1 (2026-11-01): accepted with one follow-up

Independently verified: `tclsh pnr/test_common.tcl` 298 passed, 0 failed; all thirteen `.tcl` files complete; only `pnr/` changed.
044 follow-up: the state of `route.detail.antenna` is read after the rule is defined and anything but on is a loud Warning (never set by the script).
Read `fill.tcl`: filler presence/type and an empty-of-fillers block are preconditions; the exact 18.22 insertion form; `connect_pg_net`
immediately afterwards; pin count = 2 x fillers and VDD/VSS current = previous + fillers; the coverage check of filled sites against free
sites (the first run's numbers are exact); filler violations with an optional single `route_eco` round; the hold rule of the 2026-10-29
decision; no `route_opt` command anywhere; checkpoint `final` last.

Execution's observation worth recording: `unpu_report` dies on failure inside a `catch` in `route.tcl`, so the `get_app_options` fallback line
there can never run. Harmless (the new code reads the option separately); left as is.

Follow-up (folded into task 046): the accepted hold residual must also be bounded in COUNT (`FILL_HOLD_MAX_ENDPOINTS` 10): the decision of
2026-10-29 accepted one path at 0.6 ps; a wide degradation must not hide behind a small worst slack. Their ambiguity on this is the reason.

## Task 046: outputs.tcl

Scope: netlists (sim without power pins, LVS with), LEF with `create_frame` and `write_lef -design` (the two-MACRO and 163-byte traps), SPEF /
SDF / SDC for both corners, GDS with `-units 1000`, and independent checks of every file: module counts, one MACRO and the right SIZE, pins and
rectangles, headers, GDS HEADER/UNITS/top structure, every port name present as GDS text, library cell structures present for every cell type
of the netlist; no checkpoint block (nothing is modified).

### Task 046, round 1 (2026-11-01): accepted

Independently verified after the usage-limit interruption (Execution resumed by itself): `tclsh pnr/test_common.tcl` 338 passed, 0 failed; all 14 `.tcl`
files complete; only `pnr/` changed. Read `outputs.tcl`'s write commands (each exactly as in 18.23, one `write_lef` and it has `-design`, no
`save_block`) and the GDS reader in `common.tcl` (record types HEADER 0, UNITS 3, ENDLIB 4, STRNAME 6, SNAME 18, STRING 25 are the right GDSII codes;
binary channel; length checks; zero padding after ENDLIB accepted; the UNITS arithmetic bug that Execution found and fixed is covered by a test).
`FILL_HOLD_MAX_ENDPOINTS` bound is in `fill.tcl` and tested (10 accepted, 11 fail, 400 at -0.1 ps fail). Floors in `OUT_MIN_BYTES` for netlists/SDC are
not measurements (the handoff has no sizes for them): acceptable, to be tightened from the first server run.

Open (server only): the GDS scan time in Tcl on a 15+ MB file (Execution prints `gds_scan_seconds`), whether the LEF VDD/VSS rectangle count equals
the stripe count, the real layout of the written files.

## State after task 046 (interim)

Written and statically checked: params, common, ndm_file_gen, ndm_check, design_setup, floorplan, power, help_probe (x2), cts, route, fill, outputs
(14 `.tcl` files, 338 local tests). None has run on a real tool. Not written: pin_place, placement (need the help probe), Calibre scripts (need the
server's control files), PrimeTime, post-layout simulation wrapper.

## First server results (2026-11-01 evening), read by Planning from ~/server_pull

- Both help probes ran (icc2: 141 probes, 140 found; lm: 24, 23 found). Release string, `-file`, `-output_log_file` all work.
- `set_dont_use` is not a command in this version. The handoff's 18.15 text names it; the first run most likely used `set_attribute` on the
  library cells (the `ATTR-12` "block-level override" messages). `floorplan.tcl` would have failed. Planning's handoff text was wrong.
- `ndm_file_gen.tcl` (mode single) ran clean and `ndm_check.tcl` reports `single_mode_worked = no`: `Skipped 6 physical designs (LM-052)`,
  0 of 3 fillers in the library, 534 cells. The library manager skips cells without a logical view. Mode `two` is the way (decision pending the
  user's OK: default mode becomes `two`; one NDM literally containing the fillers would need a hand-written Liberty for the three cells read
  with `read_lib`, an experiment not worth blocking on).
- `report_timing -slack_lesser_than`, `-scenarios`, `get_site_rows -quiet`, `get_blocks -quiet`, `current_scenario <name>`,
  `create_stdcell_fillers -lib_cells -prefix -rules post_route_auto_delete`, `define_antenna_rule`, `place_pins` and the pin-constraint
  commands all exist with the options the scripts use. `set_clock_uncertainty` acts on the current scenario unless `-scenarios` is given.
- The user now copies server files to `~/server_pull/` with scp, so Planning and Execution read them directly.

## Task 047: VERIFY close-out

Scope: table of every VERIFY item against the usage files and logs; fix the contradicted ones (`set_dont_use` -> `set_attribute`,
`set_clock_uncertainty -scenarios`), default NDM mode `two`, real-text tests for the parsers that have real text.

### Task 047, round 1 (2026-11-01): accepted

Independently verified: `tclsh pnr/test_common.tcl` 355 passed, 0 failed; all 14 `.tcl` files complete; only `pnr/` (and the planning docs) changed; no
`set_dont_use` command left in code (only comments, the probe list and a fixture of the real help text); no `server_pull` or `/home` path in a script or
test. Read `pnr/VERIFY_STATUS.md` header and the contradicted table. Value: running the parsers on real text found two parsers that would have made
`design_setup.tcl` fail its first real run (`report_ref_libs` rows carry `*`, not the word "open") and mis-read the antenna switch. Planning corrected
18.15 of the handoff (`set_dont_use`) and recorded the server results as 18.28.

Execution's notes: `get_app_option_value` and `report_constraint` were not probed (still unknown); `connect_pg_net` has `-report_connection_summary` (try it if the
summary is not parsed). Planning: add both commands to the probe list in the next probe run.

### Task 048, round 1 (2026-11-02): accepted

Independently verified: `tclsh pnr/test_common.tcl` 397 passed, 0 failed; all 15 `.tcl` files complete; only `pnr/` changed. Read the command lines of `pin_place.tcl`
(`create_placement -floorplan`, `set_block_pin_constraints -self ... -sides {R T}`, one `set_individual_pin_constraints` per group with `-sides` and `-allowed_layers`, `place_pins -self`;
no `-location`, no `-hard_constraints`). Checks: 204 terminals, right group on the right edge M3, top group on the top edge M2, none left or bottom, size, centre pitch,
overlap, corner keep-out, no overlap with power terminals, with a diagnosis that names the edge each group landed on when the guessed side numbers are wrong. The pin-order report is
written for the top-level team; `clk` and `rst_n` positions are RESULT lines (the clock position goes to the PM, Q14).

Execution found and fixed a bug of its own in `outputs.tcl` (task 046): the LEF check compared VDD/VSS PIN rectangles with a count of TOP_M stripe SHAPES, but `power.tcl`'s extension
rectangles are also `shape_use stripe`, so the count would have doubled and the check failed on the server. Now it counts the power TERMINALS. Same reason `pin_place.tcl` does not compare
terminals with a stripe count. Accepted. Added by Execution: block-level `-sides {R T}` in `set_block_pin_constraints` (keeps the tool off the left and bottom): accepted, the check covers it.

Open (server only): meaning of the side integers (guess 3 right, 2 top), terminal attributes (`bbox`, `layer`, `port`), `physical_status==unplaced`, whether `place_pins` honours the spacing option.

## Task 049: placement.tcl

Scope: `place_opt -list_only` (five stages), `place_opt`, setup / transition / capacitance / legality / PG connectivity as checks, hold a Warning (place_opt does not fix hold), RESULT lines
with the first run's numbers, and the input-port wire report (HPWL, load gate area or assumed 0.108 um2, estimated antenna ratio with the top-metal weight 0.84, flag above 300), report only.

### Task 049, round 1 (2026-11-02): accepted

Independently verified: `tclsh pnr/test_common.tcl` 415 passed, 0 failed; all 16 `.tcl` files complete; only `pnr/` changed; `placement.tcl` has no `insert_buffer`, `create_cell`,
`add_port_protection_diodes` or `reset_placement`. Read the flow as reported: `place_opt -list_only` checked against the five stages, `place_opt` with no option, setup violations 0 /
transition / capacitance / legality / PG connectivity as checks, hold a Warning only, the input-port report (net, loads, HPWL with the method named per port, gate area or the assumed
0.108, estimate with weight 0.84, flag above 300) as a CSV; every read in a catch; unreadable HPWL does not stop the run.

Minor: `HPWL_DETOUR` is now defined twice in `params.tcl` (Execution did not see the first one from task 038); same value, harmless; removed in task 050. The scenario-status precondition is a
Warning when unreadable (deviation from "CHECK each") and a CHECK when read and wrong: accepted.

Open (server only): attributes `direction`, `bbox` on nets/pins/ports, the gate-area attribute names (guesses), `physical_status`, the texts of `report_utilization` / `report_qor`.

## State after task 049

All ICC2 stages are written: `ndm_file_gen`, `ndm_check`, `design_setup`, `floorplan`, `power`, `pin_place`, `placement`, `cts`, `route`, `fill`, `outputs` (+ the two probes), 415 local tests,
`pnr/VERIFY_STATUS.md`. Not written: Calibre scripts (need the server's control files), PrimeTime, post-layout simulation wrapper. Not run on the server: everything except the probes,
`ndm_file_gen` (single mode) and `ndm_check`.

## Task 050: RUNBOOK.md

Scope: one document with every script's csh command, block in/out, good result, predicted failures, rerun rule, copy-back commands, plus removal of the duplicate `HPWL_DETOUR`.

### Task 050, round 1 (2026-11-02): accepted

Independently verified: `tclsh pnr/test_common.tcl` 417 passed, 0 failed; the duplicate `HPWL_DETOUR` is gone (one definition left) and a test now fails on any duplicate top-level `set` in
`params.tcl`; `pnr/RUNBOOK.md` has a section for every script (0 to 11), the hold-uncertainty experiment, the `scp` copy-back (laptop terminal, a new local folder per pull so earlier pulls are not
overwritten, big files listed), and the list of what is not scripted yet. No password text. Every script named in the RUNBOOK exists.

## Status at the end of the first loop (2026-11-02)

Tasks 038 to 050 done and reviewed: 13 tasks, 16 `.tcl` files, `RUNBOOK.md`, `VERIFY_STATUS.md`, `README.md`, 417 local tests, about 6,000 lines. Nothing past `ndm_check.tcl` has run on a real tool.
Next steps need the user: commit, pull, run per the RUNBOOK, copy logs back. Then: Calibre scripts (need `drc.ctrl`, `ant.ctrl`, the deck headers), PrimeTime, post-layout simulation, antenna fix loop.

## Constraints change (2026-11-02): tasks 051 onward

Decisions of the user (Q1 hold 0.05 ns, Q2 `rst_n` timed at 70%, Q3 `paddr` 35%): `docs/planning/constraints-update-2026-11-02.md` section 9; source `docs/planning/instructor-guidance-2026-10-27.md`.

### Task 051, round 1: accepted

Independently verified: `tclsh constraints/test_stages.tcl` 171 passed, 0 failed; the printed profile table equals the specification (syn20/18/16, place, cts, route, signoff: periods, setup 1.2 or 0.6, hold 0.05,
`paddr`/`prdata` 35%, other groups 70%, input min 5%, output min 0, feedthrough budgets 4.8/4.2/3.6/4.2/4.8/5.4/5.4); only `constraints/` changed. Read the profile table section of `unpu_top.sdc`: derived
uncertainties (not typed), no default for `UNPU_STAGE`, self-check that the feedthrough fractions leave a positive budget, rounding to 1e-6 ns, one printed profile line. Execution mutated copies to prove the test
fails on a wrong percent, a wrong twin value, a missing min delay and a wrong uncertainty kind. Good: `paddr` gets its own group and still receives the driving cell and the load (Execution noticed that the old group
carried them).

Notes: (1) the twin keeps the PM's `set_input_delay 0 [all_inputs]` which also touches the `clk` port: harmless, asserted as the only difference. (2) Risk: `error`, `foreach`, `puts`, `info exists ::env` inside
`read_sdc` in `dc_shell`/`icc2_shell`/`pt_shell` are untested (earlier SDC used only `set`/`expr`); if DC rejects them the fallback is to `source` the file (Execution marked VERIFY). (3) The `pnr/` defaults
(`UNPU_NETLIST`, `UNPU_SDC`, `HOLD_UNCERT`) now point at things this change replaces: to be done in task 053.

## Task 052: syn/RUNBOOK.md, scripts/syn_compare.sh, the netlist rule

Scope: the user runs DC at syn20/syn18/syn16; a runbook with commands, copy-back and the gate-level simulation; a comparison script with verdicts (syn20 must PASS, 18 and 16 reported); rule: the netlist
from the tightest profile that meets its own period goes on.

### Task 052: accepted with one change

Independently verified: `bash scripts/test_syn_compare.sh` 33 passed, `bash -n` clean on both scripts, no CRs; `syn/RUNBOOK.md` has the 8 sections asked for. Verdict logic as specified (syn20 PASS needs worst slack >= 0, only
`max_area` violated, no latch, no don't-use hit; syn18/syn16 MET or "NOT MET (ideal target)"; exit 0 only if syn20 PASSES and nothing is MISSING/UNPARSED/WRONG PROFILE/FLAGGED).
Change requested (sent 2026-11-02): a tighter profile that is MET but has a violator other than `max_area`, a latch line or a don't-use hit is ineligible for the recommendation. Open: the real layouts of the new report
files (`timing_top5`, `constraint`, `qor`, `check_timing`, `check_design`, `profile`) are assumptions until the first real DC run; the GLS file order is reconstructed from 18.7 (VERIFY).

## Task 053: pnr/ follows the stage profiles

Written and sent 2026-11-02. Scope: `UNPU_SYN_PROFILE` selects the netlist (`syn/out/<profile>/unpu_top_cn.dc.v`); the profile SDC `constraints/unpu_top.sdc` replaces `unpu_top_cn.sdc`; `unpu_apply_profile` applies
place/cts/route per stage with read-back checks (period, uncertainty, propagated clock, operating condition); per-stage WNS limits (placement -1.0, CTS -0.4, route 0 setup and hold) replace "zero violators";
`HOLD_UNCERT` removed; netlist-derived expectations; probe list extended. Task 054 (die size from the new cell area, utilisation, congestion, hold-buffer reporting) follows.

### Task 053: accepted (2026-11-02)

Independently verified: `tclsh pnr/test_common.tcl` 453 passed (417 + 36), `constraints/test_stages.tcl` 171, `scripts/test_syn_compare.sh` 36 (the 052 eligibility follow-up is in); greps for `HOLD_UNCERT`, `unpu_top_cn.sdc`, `SDC_FILE`,
`pm_flow`, `EXPECT_LEAF_CELLS`, `EXPECT_NETLIST_MODULES`, `server_pull` find only tests and the refusal messages. Choices accepted: `UNPU_SDC` and `UNPU_HOLD_UNCERT` are refused (not ignored); expected profile numbers are computed from the SDC's own
table through a slave interpreter (K39: `interp create` inside `icc2_shell` unverified); "unavailable" read-backs FAIL; post-CTS profile applied before the tree is read back after `clock_opt` build; unsafe-re-read fallback not written (K37).
Not stub-run in 053 (done in 054): `power`, `fill`, `outputs`, `floorplan`, `pin_place`. `syn/RUNBOOK.md` section 8 sentence to update (in 054).

## Task 054: die from the synthesis area, utilisation, congestion, growth report

Sent 2026-11-02. Die = smallest multiple of 5.6 um >= sqrt(cell area / 0.60), plus 11.2 (old area: 862.4 um); limits 75% placement, 80% CTS and route, congestion overflow 1%; growth table against the instructor's typical budget (Warning, not check).

### Task 054: accepted (2026-11-02)

Independently verified: `tclsh pnr/test_common.tcl` 487 passed (453 + 34), `constraints/test_stages.tcl` 171, `scripts/test_syn_compare.sh` 36, all `pnr/*.tcl` complete Tcl; no `PLAN_DIE_SIZE`/`868`/`817.6`/`server_pull` live in code; the die table recomputed
independently (area -> rows -> core -> die: 386,245 -> 144 -> 806.4 -> 817.6; 400,000 -> 146 -> 817.6 -> 828.8; 429,161 -> 152 -> 851.2 -> 862.4; 472,077 -> 159 -> 890.4 -> 901.6; 500,000 -> 164 -> 918.4 -> 929.6).
Changed files: `pnr/` and one sentence of `syn/RUNBOOK.md` section 8. Stub runs now exist for every script from `design_setup` to `outputs`.
Choices accepted: the die is derived in every script from floorplan on (`UNPU_SYN_PROFILE` required there); `floorplan_profile.txt` in the run directory is the record that later scripts check (same profile AND same die, else FAIL before any heavy command);
classes for the growth table by name pattern (`buf*`, `inv*`, `dl0*`; tie/spare "not counted"); growth over the instructor's typical figures is a Warning; unreadable utilisation or congestion is a FAIL.
My arithmetic slip in the task text (core area 715,268.3, correct 715,268.7) did not matter.
Open (VERIFY K43-K48): `report_utilization` wording, `report_congestion` layout and options, `ref_name` filter and cell `area` attribute, CTS-added cells not identifiable by name.

### Status after task 054

The scripted flow is complete from `ndm_file_gen` to `outputs` with the instructor's stage profiles: 487 local tests, 48 VERIFY items (K1-K48) for the first real run. Next work needs the user: commit; pull on the server; DC at syn20/18/16
(`syn/RUNBOOK.md`); `scripts/syn_compare.sh`; choose the netlist; run the probe again (`pnr/RUNBOOK.md` step 0); then `ndm_file_gen` onward. After real output: Calibre (needs `drc.ctrl`, `ant.ctrl`, `scr/headers` by scp), PrimeTime, post-layout simulation.
