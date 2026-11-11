# Task 046 — back-end re-run, script 8: `pnr/outputs.tcl` (netlists, LEF, parasitics, delays, constraints, GDS, and checks of each file)

Read first: `docs/planning/backend-rerun-plan.md` (stage E2), `pnr/README.md`, the current `pnr/*.tcl`,
`docs/session-handoff.md` 18.23 (every command that worked, the traps: `-include`/`-exclude`, the empty LEF without a
frame, `-units 1000`, the `GDS-017` message), 18.24 (why `-units 1000` matters to Calibre), and the end of 18.25/18.26
(the LEF with two MACROs, which happened because a stale frame existed and `write_lef` was called without `-design`).

## Goal

One script that opens the final (filled) block and writes every deliverable of the ICC2 flow into `$OUT_DIR`, and then
CHECKS each file from the outside, so that a wrong file is found here and not in Calibre or the top-level team's tools.
Every file comes from the final block only.

## Part A — what to write

### A1. `pnr/outputs.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/fill.tcl` (the files written, the checks, never). Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin outputs run <library>`; the library must
   exist; open `$BLK_FINAL`. Refuse to overwrite: if any target file already exists, die naming it unless
   `UNPU_OUTPUTS_OVERWRITE` is `1` (Warning per file replaced). The output directory is `$OUT_DIR`.
2. Netlists (18.23), file names from a new parameter `OUT_PREFIX` (default `unpu_top`):
   - `write_verilog -hierarchy all -exclude {all_physical_cells leaf_module_declarations pg_netlist pg_objects
     supply_statements} <prefix>_sim.v` (the simulation netlist: no power pins, no cell stubs);
   - `write_verilog -hierarchy all -include {pg_netlist} <prefix>_lvs.v` (the LVS netlist: `.VDD`/`.VSS` on instances;
     `-include` and `-exclude` cannot be combined, `CMD-001`).
3. LEF (18.23, and the 18.25/18.26 trap): `create_frame -block_all true`, then `write_lef -design $BLK_FINAL
   -include cell <prefix>.lef`. Always with `-design`.
4. Parasitics, delays, constraints for BOTH corners (18.23): `write_parasitics -corner default -output
   <prefix>_ss.spef` and `-corner ff -output <prefix>_ff.spef` (the tool adds `.typ_125.spef` and `.typ_-40.spef`, plus
   `.spef_scenario` helper files: record the real names it wrote by listing the directory before and after);
   `write_sdf -corner default <prefix>_ss.sdf` and `-corner ff <prefix>_ff.sdf`; `write_sdc -scenario $SCEN_SETUP
   -output <prefix>_ss.sdc` and `-scenario $SCEN_HOLD -output <prefix>_ff.sdc` (the "Multiply cell derates are skipped"
   warnings are benign; print them).
5. GDS (18.23, 18.24): `write_gds -design $BLK_FINAL -units $GDS_UNITS -layer_map_format icc_default -layer_map
   $GDS_LAYER_MAP -merge_files $STD_GDS -output_pin all <prefix>.gds`. The layer map can be replaced by a corrected copy
   through the environment variable `UNPU_GDS_LAYER_MAP` (a Warning says which map is used, and it is in the manifest);
   the default is the kit map. Count the `GDS-017` lines in the output (the kit map gives "Wrong layer map file syntax at
   line 8" for the `T` text lines; the file is still written) and report the count as a RESULT; any OTHER `GDS-` id is
   printed as a Warning.
6. Checks of the files from outside, each one `unpu_check_pass` (unreadable = FAIL), with pure-Tcl procedures in
   `common.tcl` so they can be tested here with made-up files:
   - existence and size > 0 of every file; sha256 of each in the manifest;
   - `<prefix>_sim.v`: the number of `module ` definitions equals the new parameter `EXPECT_NETLIST_MODULES` (76,
     18.23); a module named `unpu_top` exists; there is no `.VDD(`/`.VSS(` connection; no `feedth` anywhere;
   - `<prefix>_lvs.v`: the same module count; `module unpu_top`; `.VDD(` and `.VSS(` present; no `feedth`; the header comment
     names the block `$BLK_FINAL` (print it);
   - LEF: exactly ONE line starting `MACRO` and it is `MACRO unpu_top` (the 18.25/18.26 trap); `SIZE` equals
     `DIE_SIZE BY DIE_SIZE`; the number of `PIN` entries equals 204 signal pins + the power pins (VDD and VSS count as
     one PIN each; 18.23 had 206); the VDD and VSS pins each have as many rectangles on TOP_M as there are stripes of that
     net (read the stripe counts from the manifest/log of `power.tcl`, or compute from the block; VERIFY) at y from 0
     up; every signal pin of the port list is present; the width of the file (non-trivial: more than a few hundred bytes,
     the failure of 18.23 was a 163-byte shell);
   - SPEF (both): starts with `*SPEF`, contains `*DESIGN` naming `unpu_top`, non-trivial size (the first run: 25.7 MB each);
   - SDF (both): contains `(DELAYFILE` and `(DESIGN "unpu_top")`; SDC (both): contains `create_clock` and the clock
     uncertainty line; hold uncertainty in the `ff` SDC equals `HOLD_UNCERT` (parse; report both values);
   - GDS: the file is a GDSII stream (first record is HEADER, bytes `00 06 00 02`); its library units match `GDS_UNITS`
     (read the UNITS record: database unit 1e-3 um per user unit 1e-3... compute and report what it says; VERIFY the
     arithmetic with a made-up record in the test); the top structure name `unpu_top` is present; EVERY port name of the
     top module (the 204 signals) and `VDD` and `VSS` appear as text strings in the stream (pin labels; scan the binary
     for the ASCII string in a TEXT record; the first run's check with `strings -n 3` found labels for all of them); the
     count of labels found per port is printed. Layer and data type of the labels are NOT checked here (they are what
     Calibre LVS will tell us); say so in a comment;
   - GDS merged with the standard-cell GDS: the number of distinct library cell structures is greater than the number of
     cell types in the LVS netlist (print both); a sample: every library cell type instantiated in `<prefix>_lvs.v`
     (parse the cell names with a pure-Tcl procedure) appears as a structure name in the GDS.
7. `unpu_checks_finish outputs`. No checkpoint block is saved (the block is not modified; `create_frame` adds a view,
   which is not saved either): say in a comment why, and `close_blocks -force` at the end WITHOUT saving.
8. Summary lines: every file with its size, the real SPEF names, the `GDS-017` count, label counts, stripe/pin counts.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `OUT_PREFIX unpu_top`, `EXPECT_NETLIST_MODULES 76` (18.23, a fact of the first run's netlist: say that
  place_opt did not change the module count there), `OUTPUTS_OVERWRITE` from `UNPU_OUTPUTS_OVERWRITE` (0|1 validated),
  `GDS_LAYER_MAP` taken from `UNPU_GDS_LAYER_MAP` when set (the kit map otherwise; a Warning when overridden), and
  `FILL_HOLD_MAX_ENDPOINTS 10`.
- `pnr/fill.tcl` (follow-up from the review of task 045): the accepted sub-picosecond hold residual may cover at most
  `FILL_HOLD_MAX_ENDPOINTS` endpoints; more is a CHECK FAIL (the 2026-10-29 decision accepted one path; a widespread
  degradation must not hide behind a small worst slack). Update `unpu_fill_hold_decision` and its tests.
- `pnr/common.tcl`: the file checkers named in A1 (pure Tcl): module counter, LEF checker (macro count, size, pins,
  rectangles on a layer), SPEF/SDF/SDC header checkers, GDS record reader (HEADER, UNITS, STRNAME, TEXT strings) and the
  label scan, cell-type extractor of a netlist.
- `pnr/test_common.tcl`: tests with made-up files: a LEF with one MACRO and a LEF with two (the 18.25 case) and the 163-byte
  shell (18.23); netlists with and without `.VDD(`; a tiny binary GDS stream written by the test (HEADER, BGNLIB, LIBNAME,
  UNITS, BGNSTR, STRNAME, TEXT with a string, ENDSTR, ENDLIB) with a missing label; the SDC hold uncertainty parse; the
  hold-count bound for fill.
- `pnr/README.md`: row 11 written; the new environment variables.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 298 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `outputs.tcl` (scratch only) that creates plausible small files when the write commands run, with
   the logged command sequence in the order of A1, and these failure paths firing: block `final` missing; a target file
   exists (with and without `UNPU_OUTPUTS_OVERWRITE=1`); LEF with two MACROs; LEF without a frame (163 bytes); SIZE 817.6
   when 868.0 is expected; missing pin; netlist with `.VDD(` in the sim file; module count 75; `feedth` in a netlist; GDS
   missing a port label; wrong `UNITS`; `UNPU_GDS_LAYER_MAP` set (Warning). State what the stub proves and does not.
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; nothing written under `SCL_KIT_ROOT`; every `write_lef`
   call has `-design`.
5. `git status`: only `pnr/` changed.

## Part C — server block for the user (in your report)

csh commands with the `$UNPU_REPO` placeholder and the `icc2_shell -file ... outputs.tcl -output_log_file ...` line, the
run time you can estimate (the first run's outputs took a few minutes; SPEF extraction about 3 s per corner, GDS about a
minute), what a good result looks like (the file list with sizes: GDS about 15.7 MB at the old die, SPEF about 25 MB each),
the grep and files to paste back (`manifest_outputs.txt`, the check lines, the `GDS-` lines), and the rerun note.

## Constraints that apply

Standing rules of tasks 038 to 045. Mark every tool command or option not shown in the handoff `VERIFY`. Do not add any
option to the write commands beyond those in 18.23.

## Out of scope

Calibre, PrimeTime, simulation; reading the layer/data type of GDS labels; the dummy fill; the macro `.lib`; pin
placement and placement; `rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on the server; committing.

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt that is
wrong or ambiguous, and the Part C block. Stop after reporting.
