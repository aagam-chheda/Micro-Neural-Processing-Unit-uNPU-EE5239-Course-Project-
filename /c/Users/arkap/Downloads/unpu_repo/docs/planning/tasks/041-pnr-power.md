# Task 041 — back-end re-run, script 4: `pnr/power.tcl` (power nets, standard-cell rails, TOP_M stripes, bottom power pins)

Read first: `docs/planning/backend-rerun-plan.md` (stage B3), `pnr/README.md`, the current `pnr/*.tcl` (reuse
their procedures and message format), `docs/session-handoff.md` 18.14 (power connections), 18.15 (the power grid
and the numbers it gave), 18.21 (the bottom-edge power pins, the commands, and the mistake made there).

## Goal

One script that opens the floorplanned block, creates the power and ground nets and connects the cells, builds the
M1 rails and the TOP_M stripes, extends every stripe to the bottom edge of the die and gives each extension exactly
one terminal (the macro's `VDD`/`VSS` pins), checks all of it, and saves the next checkpoint block. In the first run
the pins were added by hand after routing and one stripe got a duplicate terminal; here they are part of the power
step and are counted.

## Part A — what to write

### A1. `pnr/power.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/floorplan.tcl`. Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin power run <library>`; the library must
   exist; open the block `$BLK_FP` with `unpu_open_stage`. Refuse to run if a block named `$BLK_PWR` already exists
   (as `floorplan.tcl` does for `fp`) or if the block already has power shapes (count the shapes of the net `VDD`
   before; must be 0; VERIFY how).
2. Nets (18.14): `create_net -power VDD`, `create_net -ground VSS` (names in new parameters `PG_NET_POWER`,
   `PG_NET_GROUND`), `connect_pg_net -automatic`. Capture the output. The first run connected 12,487 VDD and 12,487
   VSS pins, which equals the leaf-cell count: CHECK both equal `EXPECT_LEAF_CELLS` (parse the "P/G pin count" table
   of `connect_pg_net` with a pure-Tcl procedure in `common.tcl`; if the table cannot be parsed, a Warning and a
   second way of counting: the pins connected to each net).
3. Grid (18.15, exact commands that worked, names as parameters): `create_pg_std_cell_conn_pattern std_rail -layers
   {M1} -rail_width 0.74`; `create_pg_mesh_pattern top_mesh -layers {{{vertical_layer: TOP_M} {width: 2.24} {pitch:
   112} {spacing: interleaving}}}`; `set_pg_strategy s_rail -core -pattern {{name: std_rail} {nets: {VDD VSS}}}`;
   `set_pg_strategy s_mesh -core -pattern {{name: top_mesh} {nets: {VDD VSS}}}`; `compile_pg -strategies {s_rail
   s_mesh}`. Build the argument strings from the parameters (`PG_RAIL_LAYER`, `PG_RAIL_WIDTH`, `PG_STRIPE_LAYER`,
   `PG_STRIPE_WIDTH`, `PG_STRIPE_PITCH`); add the pattern and strategy names and the spacing mode as parameters.
   Capture the output of `compile_pg` and print it (the first run reported 14 stripes, 145 rails, 1,015 stacked-via
   locations).
4. Read the stripes from the database ONCE, before creating any shape of your own: for each of `VDD`, `VSS`, the
   shapes on `TOP_M` with `shape_use==stripe` (18.21), as a list of `{net llx lly urx ury}` with the numbers rounded
   to 4 decimals. Checks: at least one stripe per net; every stripe is `PG_STRIPE_WIDTH` wide (tolerance) and its
   lower end is at the core boundary (`CORE_OFFSET`); the stripe count per net is printed (do not assert 7 and 7:
   the die is bigger than in the first run, which had x = 60.48 ... 788.48 at pitch 112). Rails: count the `M1`
   rail shapes and compare with rows + 1 (`FP_ROWS + 1`; the first run had 145 rails for 144 rows). VERIFY the
   filter (`shape_use==follow_pin` is a guess).
5. Bottom power pins (18.21): for each stripe of the list from step 4, create one rectangle on `TOP_M` from the
   stripe's `llx` to its `urx`, from y = 0 to y = `PG_PIN_HEIGHT` (6.0), same net, `-shape_use stripe`, with
   `create_shape -shape_type rect -layer TOP_M -boundary {{llx 0} {urx 6.0}} -net <net> -shape_use stripe`; then one
   terminal on that shape: `create_terminal -of_objects <shape>` (`-port` cannot be combined with `-of_objects`; the
   port comes from the shape's net). Do the loop over the list made in step 4, never over a fresh query (that is
   how the first run created a second extension on one stripe: its skip test selected the original stripes, one of
   them already extended). Try the first stripe alone, check it (terminal exists, bbox, layer), then do the rest.
6. Checks after, one `unpu_check_pass` each: number of terminals equals the number of stripes, per net; every
   terminal is on `TOP_M`; no two terminals have the same x range; every terminal's x range equals that of its
   stripe; the lowest y of every terminal is 0; no terminal is outside the die; `check_pg_drc` reports no errors
   (parse its summary with a pure-Tcl procedure; VERIFY the text); `check_pg_connectivity` reports 0 floating wires,
   0 floating vias, 0 floating terminals (parse; VERIFY). Floating standard cells are EXPECTED here (nothing is
   placed yet; 18.15 saw all 12,487): print the number as a RESULT and compare it with `EXPECT_LEAF_CELLS` as a
   Warning if different, not as a check. The check after placement belongs to `placement.tcl`.
7. `unpu_checks_finish power` BEFORE the checkpoint, then `unpu_checkpoint $BLK_PWR`.
8. Summary `unpu_result power` lines: stripes per net with their x positions (the full list, so the top-level team
   gets the pin positions from the log), rails, stacked vias if the output gives them, terminals per net, the
   check results, block saved.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `PG_NET_POWER VDD`, `PG_NET_GROUND VSS`, `PG_PATTERN_RAIL std_rail`, `PG_PATTERN_MESH top_mesh`,
  `PG_STRAT_RAIL s_rail`, `PG_STRAT_MESH s_mesh`, `PG_SPACING interleaving`, each with its source (18.15, 18.21).
- `pnr/common.tcl`: pure-Tcl procedures to parse the `connect_pg_net` summary table, the `check_pg_drc` summary and
  the `check_pg_connectivity` summary (strict about what they accept, a clear "not parsed" otherwise), and one that
  checks a list of terminal boxes against a list of stripe boxes (counts, same x range, no duplicates, lowest y).
- `pnr/test_common.tcl`: tests for each, with made-up text in at least two layouts, and the failure cases (a
  duplicate terminal like the one in 18.21, a missing terminal, a wrong x range).
- `pnr/floorplan.tcl` (small follow-up): the header's rerun note must say what is true: if `floorplan.tcl` failed
  before `block_saved`, nothing was saved and it can simply be run again; only after a successful run does a new
  floorplan need a new `UNPU_RUN_TAG` (or `UNPU_LIB_OVERWRITE=1` and a rerun of `design_setup.tcl`).
- `pnr/README.md`: row 5 written.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 125 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `power.tcl` (scratch only) with the logged command sequence in the order of A1, and
   these failure paths firing: library or block missing; block `pwr` already present; connect counts differ from
   12,487; a stripe not `PG_STRIPE_WIDTH` wide; a duplicate terminal on one stripe (the 18.21 mistake); one stripe
   without a terminal; `check_pg_drc` with errors; floating wires. State what the stub proves and what it does not.
   Also show that the stripe list is read once and the loop runs over that list (the logged `get_shapes` calls).
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; nothing written under `SCL_KIT_ROOT`.
5. `git status`: only `pnr/` changed.

## Part C — server block for the user (in your report)

csh commands with the `$UNPU_REPO` placeholder, the `icc2_shell -file ... power.tcl -output_log_file ...` line, a
good result (CHECK and RESULT lines with the numbers to expect for the default die; the stripe count and x
positions are NOT known in advance, say so), the grep and the files to paste back, and the correct rerun note (as
in A2).

## Constraints that apply

Standing rules of tasks 038 to 040. Mark every tool command or option not shown in the handoff `VERIFY`.

## Out of scope

Signal pins, placement and everything after; `rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on
the server; committing (wait for Planning).

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt
that is wrong or ambiguous, and the Part C block. Stop after reporting.
