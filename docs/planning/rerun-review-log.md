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
