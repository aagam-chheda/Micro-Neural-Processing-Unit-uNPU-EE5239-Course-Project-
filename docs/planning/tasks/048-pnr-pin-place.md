# Task 048 — back-end re-run, script 9: `pnr/pin_place.tcl` (coarse placement, then the tool places the signal pins)

Read first: `docs/planning/backend-rerun-plan.md` (stage B4 and the pin decisions), `pnr/README.md`, `pnr/VERIFY_STATUS.md`, the
current `pnr/*.tcl`, `docs/session-handoff.md` 18.9 (pin sides and layers decided with the top level), 18.15 (how the first run
set the pins by hand: `set_block_pin_constraints -self -hard_constraints location`, `set_individual_pin_constraints ... -location`,
`place_pins -self`), and the REAL usage files (read them, do not rely on memory): `~/server_pull/rpt/help/place_pins.txt`,
`set_block_pin_constraints.txt`, `set_individual_pin_constraints.txt`, `create_placement.txt`, `get_terminals.txt`,
`all_wildcards.txt` (the `*pin*` and `*place*` lists: `report_pin_placement`, `check_pin_placement`, `report_pin_constraints`,
`report_individual_pin_constraints`, `report_block_pin_constraints`, `remove_individual_pin_constraints` exist).

## Decisions behind this task (user, 2026-11-01)

The tool decides the ORDER and POSITION of every signal pin, `clk` included, after a coarse placement, so that each pin lands
near the cells it feeds (the cause of the antenna failure was a pin 180 um from its only load). What stays fixed: the SIDE and
the LAYER of each group: right edge M3 for the APB group (`paddr[*] pwdata[*] prdata[*] pwrite psel penable pready clk rst_n`),
top edge M2 for the DMA group (`dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] dma_valid dma_ready`); no signal pin on the
left or on the bottom (the bottom carries the power pins). Pin width 0.28 um, length 1.0 um, centre-to-centre pitch at least
6.72 um (all in `params.tcl`). Do not keep the old "bits ascending" convention.

## Goal

One script that opens the block with power (`$BLK_PWR`), makes a coarse placement of the standard cells, sets the pin constraints,
lets the tool place the signal pins, checks the result against the decisions above, writes the pin order to a report (this is what
the top-level team receives), and saves the next checkpoint block.

## Part A — what to write

### A1. `pnr/pin_place.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/power.tcl`. Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin pin_place run <library>`; the library must exist;
   refuse to run if `$BLK_PINS` exists; open `$BLK_PWR`. Preconditions (CHECK each): the block has no signal terminals yet (the
   terminals are the power ones from `power.tcl`: VDD/VSS only; count them with `get_terminals` and compare with the stripe count you
   can read the same way `power.tcl` did); `EXPECT_PORTS` ports (204); no cell is placed yet (VERIFY how to tell; if it cannot be
   told, a Warning).
2. Coarse placement: `create_placement -floorplan` (usage: "Run design planning styled placement"). Capture the output. This
   placement exists only to give the pin placer something to work with; `placement.tcl` (next task) redoes the placement with the
   pins fixed. After it, count the cells that are placed (VERIFY the attribute, for example `is_placed` or `physical_status`) and
   CHECK that all standard cells are placed (zero unplaced); if the count cannot be read, a Warning.
3. Pin constraints (real options from the usage files; any option you use must be in the usage text):
   - `set_block_pin_constraints -self` with `-width $PIN_WIDTH -length $PIN_LENGTH` and the minimum pin distance
     (`-pin_spacing_distance`, see the usage: decide from the text whether it is centre-to-centre or edge-to-edge and WRITE the
     reading in a comment; the check in step 5 measures the real pitch, so a wrong reading is caught);
   - per group, `set_individual_pin_constraints -ports <the group's ports> -sides <the side number> -allowed_layers <layer>`, with the
     same width and length. Side numbers: the usage does not say which integer is which edge. New parameters `PIN_SIDE_RIGHT` (default
     3) and `PIN_SIDE_TOP` (default 2), both overridable by `UNPU_PIN_SIDE_RIGHT` / `UNPU_PIN_SIDE_TOP`, with a comment that the
     default is a GUESS (clockwise from the left edge: 1 left, 2 top, 3 right, 4 bottom) that the check in step 5 verifies. Do not
     pass `-location` (that would fix the positions) and do not use `-hard_constraints location`.
   Print `report_block_pin_constraints` and `report_individual_pin_constraints` to `$RPT_DIR/pin_place_constraints.rpt`.
4. `place_pins -self` (usage: `-self` places pins on the current design). Capture the output.
5. Checks after, each one `unpu_check_pass` (unreadable = FAIL), with pure-Tcl procedures in `common.tcl` for the geometry so they
   can be tested here:
   - the number of signal terminals is exactly `EXPECT_PORTS` (204), one per port, none duplicated;
   - every terminal of the right group lies on the right edge (its x equals `DIE_SIZE` within tolerance, or the pin shape touches
     the edge: say which in a comment after you have seen the terminal `bbox` format in `power.tcl`'s use), on layer `PIN_LAYER_RIGHT`;
     every terminal of the top group lies on the top edge on layer `PIN_LAYER_TOP`; no signal terminal on the left or bottom edge;
   - if a group is on the wrong edge, the CHECK message names the edge each group actually landed on and says: set
     `UNPU_PIN_SIDE_RIGHT` / `UNPU_PIN_SIDE_TOP` to the other side numbers (this is the expected failure if the guess is wrong);
   - width and length of the pin shapes equal `PIN_WIDTH` and `PIN_LENGTH` (tolerance);
   - the smallest centre-to-centre distance between two pins on the same edge is at least `PIN_PITCH` minus a tolerance, and no two
     pins overlap; print the smallest and the largest gap per edge;
   - no signal pin within `PIN_CORNER_KEEPOUT_UM` of a corner (new parameter, default 2 x `PIN_PITCH`, a plain safety margin; say so);
   - the pins do not collide with the power terminals (the power terminals are on the bottom edge, so a signal pin on the bottom
     already failed the previous check; check explicitly that no signal terminal box overlaps a power terminal box).
6. Report for the top-level team (not a check): `$RPT_DIR/pin_order.txt`, one line per pin: port, edge, coordinate along the edge,
   layer; sorted by edge and coordinate; plus a short summary per bus (for each bus the list of its bit positions in order, so
   anyone can see how the tool grouped it) and the position of `clk` and `rst_n`. Also `report_pin_placement` (usage in
   `all_wildcards.txt`; VERIFY its options) to `$RPT_DIR/pin_place_report.rpt`. Print the clock pin position as a RESULT: the top
   level and the PM (clock latency and skew at `clk`, question Q14) must be told.
7. `unpu_checks_finish pin_place`, then `unpu_checkpoint $BLK_PINS`, then the summary lines.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `PIN_SIDE_RIGHT` (3) and `PIN_SIDE_TOP` (2) with the environment overrides and validation (a positive integer, the
  two must differ); `PIN_CORNER_KEEPOUT_UM`; `PIN_TOLERANCE_UM` (0.005, geometry tolerance); each with a source comment.
- `pnr/common.tcl`: the geometry procedures named above (edge of a box, pitch/gap per edge, overlap, corner keepout, the wrong-edge
  diagnosis, the pin-order report lines), pure Tcl.
- `pnr/test_common.tcl`: tests with made-up terminal boxes: a correct layout of 102 pins on the right and 102 on the top at pitch
  7.0 and at pitch 6.72; a pin on the left; a group swapped between the edges (the diagnosis message); two pins 3 um apart; a pin in
  a corner; a signal pin overlapping a power terminal; a duplicate port; the order report on a small example.
- `pnr/params.tcl` probe lists: add `get_app_option_value report_constraint report_pin_placement check_pin_placement
  report_pin_constraints report_individual_pin_constraints report_block_pin_constraints remove_individual_pin_constraints
  report_placement report_utilization get_site_defs` to `PROBE_COMMANDS_ICC2` (those not already in it); adjust the test that checks
  the list length/duplicates.
- `pnr/README.md`: row 6 written; the new environment variables.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 355 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `pin_place.tcl` (scratch only) with the logged command sequence in the order of A1, where the stub's
   `place_pins` creates 204 terminals at plausible places (a good layout), and these failure paths firing: library or block `pwr`
   missing; block `pins` present; signal terminals already present; unplaced cells; groups swapped (the diagnosis names the edges);
   a pin on the left; pitch 5 um; a corner pin; a pin overlapping a power terminal; 203 terminals; width 0.5. Show also a run with
   `UNPU_PIN_SIDE_RIGHT=1 UNPU_PIN_SIDE_TOP=4` reaching the constraints. State what the stub proves and does not.
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; no `-location` and no `-hard_constraints location` in
   `pin_place.tcl` (except in a comment saying they are not used); nothing written under `SCL_KIT_ROOT`.
5. `git status`: only `pnr/` changed. Do not commit.

## Part C — server block for the user (in your report)

csh commands with the `$UNPU_REPO` placeholder and the `icc2_shell -file ... pin_place.tcl -output_log_file ...` line, what a good
result looks like, the expected FIRST failure if the side numbers are guessed wrong and how to read it and rerun
(`UNPU_PIN_SIDE_RIGHT`, `UNPU_PIN_SIDE_TOP`), the files to copy back (`pin_order.txt`, the constraint and placement reports, the
log), and the rerun note. Also the `scp` line for the user to copy `rpt` and `logs` afterwards (the user copies files to
`~/server_pull/`; give the commands as in the earlier exchange, without any password).

## Constraints that apply

Standing rules of tasks 038 to 047. Every tool option must be in the real usage text; mark what the text cannot settle `VERIFY`.

## Out of scope

`place_opt` and everything after (the next task), antenna and diode work, the dummy LEF and the top-level pin plan documents,
`rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on the server; committing.

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt that is wrong or
ambiguous, and the Part C block. Stop after reporting.
