# Task 040 — back-end re-run, script 3: `pnr/floorplan.tcl` (die, rows, don't-use cells)

Read first: `docs/planning/backend-rerun-plan.md` (stage B2 and B3's don't-use part), `pnr/README.md`, the
current `pnr/*.tcl` (reuse their procedures and message format), `docs/session-handoff.md` 18.14 (floorplan,
including the mistake made on the first attempt) and 18.15 (don't-use cells).

## Goal

One script that opens the block saved by `design_setup.tcl`, creates the floorplan for the die size in
`params.tcl`, checks that the die, the core and the rows are what the parameters say, marks the don't-use cells, and
saves the next checkpoint block. Power is NOT part of this script (it is `power.tcl`, the next task).

## Part A — what to write

### A1. `pnr/floorplan.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/design_setup.tcl` (purpose, csh run command with `$UNPU_REPO`, inputs, outputs, never).
Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin floorplan run <files>`. Input: the library
   `$LIB_DIR/$LIB_NAME` must exist (die naming the path, and saying that `design_setup.tcl` runs first). Open the
   block `$BLK_IMPORT` with `unpu_open_stage`. Before doing anything check that the opened block has no floorplan
   yet (the number of site rows is 0; VERIFY how to count rows) and print the port count as a sanity line.
2. `initialize_floorplan -boundary $FP_BOUNDARY -core_offset $CORE_OFFSET` (18.14). **Read the 18.14 mistake and
   put it in a comment**: `-boundary` is the CORE rectangle and `-core_offset` is added OUTSIDE it, so the die is
   boundary + offset. `FP_BOUNDARY` in `params.tcl` is already built that way (core corners 5.6 and DIE−5.6).
3. Checks, one `unpu_check_pass` each, with the numbers in the detail:
   - die: `boundary_bbox` of the block equals `{0 0} {DIE_SIZE DIE_SIZE}` (tolerance `FP_TOLERANCE` scaled sensibly;
     VERIFY the attribute, 18.14 shows `boundary_bbox`);
   - rows: the number of site rows equals `FP_ROWS` (VERIFY the command; 18.14 saw 144 rows at 817.6);
   - site: the rows use the site `unit`, 0.56 by 5.6 um (VERIFY how to read it; if it cannot be read, a Warning);
   - areas: `report_design -floorplan` written to `$RPT_DIR/floorplan_design.rpt` (`redirect -file`), printed, and
     the chip area and core area parsed from it with a pure-Tcl procedure in `common.tcl` and compared with
     DIE_SIZE² and `CORE_AREA` (668,469.76 and 650,280.96 at 817.6 in the first run; 753,424 and 734,106.24 at
     868.0). If the layout of the report does not parse, the check FAILS with the text it saw (as
     `unpu_corner_has_point` does); the report file is the evidence.
   - utilisation: print the core utilisation from the same report as a RESULT (informational; the cell area of the
     DC netlist is 429,161 um2, so about 58.5% at the plan's die). Not asserted.
4. Don't-use cells (18.15): for each pattern of `DONT_USE_PATTERNS` collect `get_lib_cells -quiet */<pattern>`,
   print the count per pattern, `set_dont_use` on the collection. A pattern with zero matches is an `Info` for
   `mx08d*` (its three cells have no timing view and are not in the NDM; 18.15) and a `Warning` for any other
   pattern. Afterwards count the library cells with `dont_use==true`: it must equal the new parameter
   `EXPECT_DONT_USE_COUNT` (18 = 15 matched by the patterns + `adiode`, `bh01d1`, `cload1` flagged by the library;
   18.15). Also check that the three library-flagged cells are among them. VERIFY the `-filter` form (the same
   one `ndm_check.tcl` uses).
5. `unpu_checks_finish floorplan` BEFORE the checkpoint (a failed check stops the script and nothing is saved), then
   `unpu_checkpoint $BLK_FP`.
6. Summary `unpu_result floorplan` lines: die, core, rows, site, chip area, core area, utilisation, don't-use
   count per pattern and total, block saved.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `EXPECT_DONT_USE_COUNT 18` (18.15, with the 15 + 3 explanation in the comment) and
  `EXPECT_DONT_USE_MATCHED 15` (cells matched by our patterns); `EXPECT_CHIP_AREA` is NOT a parameter (derived from
  `DIE_SIZE`), do not add one.
- `pnr/common.tcl`: the pure-Tcl procedure that extracts chip and core area from `report_design -floorplan` text
  (tolerant of the layouts you can imagine, strict about what it accepts; returns a clear "not found").
- `pnr/test_common.tcl`: tests for it with made-up text in two layouts, including the first run's numbers (chip
  668,469.76, core 650,280.96) and the new ones, and the failure cases (number absent, wrong number).
- `pnr/design_setup.tcl` (two small follow-ups from the review of task 039): (a) the first `read_sdc` also prints a
  Warning for an EXPECTED id that does not appear (the first run saw both `SDC-3` and `SDC-4`); the second read stays
  as it is; (b) before `save_block`, make `$SCEN_SETUP` the current scenario again, and say in a comment that stage
  scripts must not rely on which scenario is current: each one selects the scenario it needs.
- `pnr/README.md`: row 4 written.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 111 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `floorplan.tcl` (scratch only), with the logged command sequence in the order of A1
   (`open_lib`, `open_block`, row count, `initialize_floorplan -boundary {{5.6 5.6} {862.4 862.4}} -core_offset 5.6`,
   the checks' queries, `report_design -floorplan`, `set_dont_use` per pattern, the dont_use count,
   `save_block -as`, `close_blocks -force`, `open_block`, `save_lib`). Show these failure paths firing: library
   missing; a block that already has rows; die bbox 817.6 when 868.0 is expected; 152 rows; dont_use count 17; a
   report text in which the areas are absent. Also run it once with `UNPU_DIE_SIZE=817.6` and show that the same
   script then expects 144 rows and the 817.6 boundary (that is the regression setting of plan A2). State what this
   proves and does not.
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; nothing written under `SCL_KIT_ROOT`.
5. `git status`: only `pnr/` changed.

## Part C — server block for the user (in your report)

csh commands, `$UNPU_REPO` placeholder, the `icc2_shell -file ... floorplan.tcl -output_log_file ...` line, what
a good result looks like (the CHECK and RESULT lines with the expected numbers for the default die: 868 / 856.8 /
153 rows / 18 don't-use), the grep to paste back, and the rerun recipe (the earlier block is never touched; delete
`$LIB_DIR/$LIB_NAME`'s block `fp` or use a new run tag, state which and how).

## Constraints that apply

Standing rules of task 038 and 039. Mark every tool command or option not shown in the handoff `VERIFY`.

## Out of scope

Power nets, grid and pins (next task), placement and everything after; `rtl/`, `constraints/`, `syn/`,
`docs/planning/`; running anything on the server; committing (wait for Planning).

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt
that is wrong or ambiguous, and the Part C block. Stop after reporting.
