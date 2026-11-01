# Task 049 — back-end re-run, script 10: `pnr/placement.tcl` (`place_opt`, checks, and the input-port wire report)

Read first: `docs/planning/backend-rerun-plan.md` (stages B5 and B6), `pnr/README.md`, `pnr/VERIFY_STATUS.md`, the current `pnr/*.tcl`
(reuse `unpu_timing_summary`, `unpu_constraint_count`, the parsers), `docs/session-handoff.md` 18.16 (the first `place_opt`: what it
printed and what the checks showed), and the real usage files `~/server_pull/rpt/help/place_opt.txt`, `report_timing.txt`,
`get_attribute.txt`, `get_nets.txt`, `get_pins.txt`, `get_lib_pins.txt` if present.

## Goal

One script that opens the block with fixed pins (`$BLK_PINS`), runs the full `place_opt`, checks the result the way 18.16 did, writes
a per-input-port report of wire length against what the antenna rule tolerates (plan B6, REPORT ONLY), and saves the placed block.
No buffer, diode or other cell is added here.

## Part A — what to write

### A1. `pnr/placement.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/cts.tcl`. Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin placement run <library>`; the library must exist; refuse to
   run if `$BLK_PLACED` exists; open `$BLK_PINS`. Preconditions (CHECK each): 204 signal terminals exist besides the power ones (use the
   helpers of `pin_place.tcl`, moved into `common.tcl` if they are not already shared); the scenario status is as `design_setup.tcl` left
   it (setup scenario setup-only, hold scenario hold-only; `report_scenarios`, VERIFY).
2. `place_opt -list_only` (usage: lists the sub-steps). Print it and CHECK that it names the five stages of 18.16 (`initial_place`,
   `initial_drc`, `initial_opto`, `final_place`, `final_opto`); a different list is a Warning with the text, not a stop.
3. `place_opt` with no option (all stages; the first run took about 133 s). Capture the output, count the message ids with prefixes
   `FLW-`, `OPT-`, `PLACE-`, `LGL-`, `ZRT-` and print them (the first run printed `LGL-031` about the site symmetry: benign, it must
   be visible, not hidden). RESULT the runtime if the shell prints it; else measure with `clock seconds`.
4. Checks, each `unpu_check_pass` (unreadable = FAIL), reusing the shared procedures:
   - setup in `$SCEN_SETUP`: violating endpoints 0 (18.16: WNS 0.0000, 0 violating in every group); RESULT the worst slack and the
     worst path's endpoints (in the first run `paddr[3]` to `prdata[23]`, slack 0.00);
   - hold in `$SCEN_HOLD`: RESULT the violating-endpoint count and the worst slack, and a Warning if not zero that says: `place_opt`
     does not fix hold (the first run had 2,304 violating endpoints here), `cts.tcl` does; NOT a check;
   - max transition and max capacitance: 0 (CHECK);
   - `check_legality`: 0 (CHECK; the `PDC-003` warning about the GC layer is benign, print it);
   - `check_pg_connectivity`: 0 floating standard cells, wires, vias, terminals (CHECK; this is the check that `power.tcl` could not
     make because nothing was placed; the first run: 11,986 cells, 0 floating).
5. RESULT lines (informational; the first run's values in a comment): area (426,097.72 um2), instances (11,986), buffers (161),
   inverters (1,353), utilisation, wire length if reported. Note that the cell count differs from the netlist's leaf count because
   `place_opt` merges and removes cells (501 in the first run): print both numbers (the netlist's `EXPECT_LEAF_CELLS` and the placed
   count) and their difference; no check.
6. The input-port report (plan B6; nothing is added or changed). For every input port except `clk` (the 80 nets ICC2 does not
   analyse for antennas are the input-port nets; take them from `get_ports -filter` on direction, VERIFY; or the list of port names
   from the netlist ports minus the outputs):
   - the net of the port, the number of load pins, the half-perimeter wire length (HPWL) of the net from the placement (VERIFY how:
     the net `bbox` attribute, or the min/max of the pin locations `get_attribute <pin> bbox`; say which you used);
   - the gate area of the loads if it can be read from the library pins (VERIFY the attribute name; look at the usage of
     `get_attribute` and `list_attributes` if available); if it cannot, use the new parameter `MIN_GATE_AREA` (0.108 um2, the
     smallest gate area ICC2 itself printed in the first run's antenna listing) and say so in the report, per port;
   - the estimated antenna ratio for a single-layer run: `2 * HPWL * HPWL_DETOUR * ANT_WEIGHT_TOP / gate_area` with
     `ANT_WEIGHT_TOP` 0.84 (the Calibre deck's weight for the top metal, the worst case; new parameter) and the flag
     `estimate > ANT_RATIO` (300);
   - write `$RPT_DIR/placed_port_report.csv` (port, net, loads, hpwl_um, gate_area_um2, gate_area_source, estimated_ratio, flag),
     sorted by estimated ratio, worst first; print the worst 10; RESULT the number flagged, the largest HPWL (the first run's
     `paddr[4]` was 180 um) and its port, and the count of ports with HPWL above 50 um. A Warning (not a check) lists the flagged
     ports and says that Calibre decides and that the later fix loop starts from them.
7. `unpu_checks_finish placement`, then `unpu_checkpoint $BLK_PLACED`, then the summary lines. The last log line says: this block still
   has no clock tree and no hold fixing; `cts.tcl` is next.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `PLACE_OPT_STAGES` (the five, 18.16), `MIN_GATE_AREA 0.108`, `ANT_WEIGHT_TOP 0.84` (source: the Calibre deck rule
  `AN.MTL.1.MT`, `perimeter*0.84/gate area`, handoff 18.27), `PORT_REPORT_LONG_UM 50`, each with a source comment.
- `pnr/common.tcl`: the estimated-ratio and flag procedures (pure Tcl), the CSV writer, the parser of the `place_opt -list_only` text,
  and any pin helper you move from `pin_place.tcl`.
- `pnr/test_common.tcl`: tests with made-up numbers: the estimate for the first run's `paddr[4]` (HPWL 180 um, detour 1.2, weight 0.84,
  gate 0.1944: the estimate is `2*180*1.2*0.84/0.1944` = 1866.7 and it is flagged), a short net (10 um, 0.108: not flagged), the CSV
  ordering and columns, the stage-list parser (the five, a missing one).
- `pnr/README.md`: row 7 written.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 397 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `placement.tcl` (scratch only) with the logged command sequence in order and these failure paths firing:
   library or block `pins` missing; block `placed` present; 203 signal terminals; setup violations; max transition violations; legality
   violations; floating cells; the stage list missing a stage (Warning); hold violations (Warning, saves); a port whose HPWL cannot be
   read (the report line says so and the run goes on). Show the CSV the stub produced. State what the stub proves and does not.
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; no `insert_buffer`, `create_cell`, `add_port_protection_diodes` or
   `reset_placement` in `placement.tcl`; nothing written under `SCL_KIT_ROOT`.
5. `git status`: only `pnr/` changed. Do not commit.

## Part C — server block for the user (in your report)

csh commands with the `$UNPU_REPO` placeholder, the `icc2_shell -file ... placement.tcl -output_log_file ...` line, a good result (CHECK lines,
the first run's reference numbers), what to copy back (`placed_port_report.csv`, the logs, the manifest), the `scp` commands (user, host
and paths as in the earlier exchange: `EE5239G1@172.16.82.70`, `/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/{rpt,logs}` to
`~/server_pull/`), and the rerun note.

## Constraints that apply

Standing rules of tasks 038 to 048. Every option must be in the usage text; mark the rest `VERIFY`.

## Out of scope

Clock tree and everything after; adding cells; diodes; changing pins; `rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on the
server; committing.

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt that is wrong or ambiguous,
and the Part C block. Stop after reporting.
