# Task 039 — back-end re-run, script 2: `pnr/design_setup.tcl` (library, netlist, constraints, corners)

Second script of the sequence. Read first: `docs/planning/backend-rerun-plan.md` (stage B1), `pnr/README.md`, the
files of task 038 (`pnr/params.tcl`, `pnr/common.tcl`, `pnr/ndm_check.tcl`: reuse their procedures and message
format, do not duplicate them), `docs/session-handoff.md` 18.11, 18.12, 18.13 (the commands that worked, and what
the log showed).

## Goal

One script that, starting from the NDM(s) written by `ndm_file_gen.tcl`, creates the design library `unpu2_lib`,
reads the TLUPlus, the DC netlist and the DC-written SDC, sets up the two corners and scenarios, checks that what
was read is what the first run read, and saves the first checkpoint block.

## Part A — what to write

### A1. `pnr/design_setup.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/ndm_check.tcl` (what it does, the csh run command with `$UNPU_REPO` as placeholder,
inputs, outputs, what it never does). Behaviour, in this order:

1. `unpu_require_tool_version`, `unpu_stage_begin design_setup run <files>` with the input files in the manifest
   (technology file, TLUPlus and its map, netlist, SDC, `ndm_manifest.txt`). Inputs must exist
   (`unpu_need_file`); the NDM paths come from `$NDM_DIR/ndm_manifest.txt` through ONE shared procedure
   `unpu_read_ndm_manifest` that you add to `common.tcl` (it dies on a missing file, an empty file, or a listed NDM
   that does not exist); change `ndm_check.tcl` to use it too.
2. The design library is `$LIB_DIR/$LIB_NAME`. It must not exist: if it does, die with a message, unless the
   environment variable `UNPU_LIB_OVERWRITE` is `1` (then print a Warning and remove it, with the kit-write guard).
   Never reuse a library silently.
3. `create_lib -technology $TECH_FILE -ref_libs <the NDM list> <path>` (18.11). Print `report_ref_libs`. Check
   that every reference library of the manifest is listed and open.
4. `read_parasitic_tech -name typ -tlup $TLUPLUS_FILE -layermap $TLUPLUS_MAP` (18.11; nine `TLUP-011` warnings are
   benign and expected: print them, do not hide them).
5. `read_verilog -top $TOP_NAME $NETLIST` then `link_block` (18.12). Capture the output and require
   "successfully linked" in it; no unresolved references. Then check, one `unpu_check_pass` each: top-level ports
   equal `EXPECT_PORTS` (204); sequential cells (`is_sequential==true`) equal `EXPECT_SEQ_CELLS` (2465); leaf cells
   (`is_hierarchical==false`) equal the new parameter `EXPECT_LEAF_CELLS` (12487, handoff 18.14). The netlist is
   unchanged by the plan; if a count differs, that is a finding, not something to loosen.
6. `read_sdc $SDC_FILE` into the first scenario (named by the new parameter `SCEN_SETUP`, default `default`, the
   one `read_sdc` creates; the shell has no rename command, 18.13). Capture the output. The first run saw exactly
   two ignored constraints, `set_wire_load_model` and `set_max_area` (`SDC-3`, `SDC-4`). Print every line with an
   `SDC-` message id; compare the set of ids with the new parameter `EXPECT_SDC_IGNORED` ({SDC-3 SDC-4}) and print
   a Warning naming any id that is not expected (do not die: the message ids are from the handoff, not verified).
7. Corners and scenarios (18.13): `create_corner $CORNER_HOLD` (new parameter, `ff`); `create_scenario -name
   $SCEN_HOLD -mode default -corner $CORNER_HOLD` (new parameters `SCEN_HOLD` = `ff_hold`, mode name `default`);
   make that scenario current and read the SAME SDC into it (`UIC-034` "Redefining clock" is benign); then
   `set_operating_conditions tsl18fs120_scl_ff -library tsl18fs120_scl_ff` (names from `LIB_FF_NAME`) to override
   the ss operating condition that the SDC sets. VERIFY the command that selects the current scenario; it is not
   in the handoff.
   `set_scenario_status` as in 18.13: `$SCEN_SETUP -setup true -hold false`, `$SCEN_HOLD -setup false -hold true`.
   `set_parasitic_parameters -corners <corner> -early_spec typ -late_spec typ` for both corners (the corner of the
   first scenario is named `default`, VERIFY by `report_corners`).
   Do NOT change the hold uncertainty here: the SDC value (0.5) stays in force; `cts.tcl` (a later task) applies
   `HOLD_UNCERT` explicitly. Say that in a comment.
8. Reports, each written to `$RPT_DIR/design_setup_<name>.rpt` by `redirect -file` and also summarised in the log:
   `report_corners` (must show ss 1.62 V / 125 C for the first corner and ff 1.98 V / -40 C for the second;
   parse or compare the voltage and temperature numbers and `unpu_check_pass` them: this is the guard against the
   wrong operating condition being active), `report_scenarios` (setup/hold status as set),
   `report_parasitic_parameters`, and `check_timing` in each scenario. The first run's `check_timing` gave one
   warning, `pready` unconstrained because it is a constant (`rtl/unpu_apb.sv:87`): count the warnings and print a
   Warning if the count differs from the new parameter `EXPECT_CHECK_TIMING_WARNINGS` (1), naming them.
9. First timing, informational only (no placement, zero interconnect, ideal clock): the worst setup slack in
   `$SCEN_SETUP` and the worst hold slack in `$SCEN_HOLD`, as `unpu_result design_setup` lines (use
   `get_timing_paths` and the `slack` attribute, VERIFY; fall back to a captured `report_timing -max_paths 1` only
   if that fails, with a Warning). Not asserted: the first run saw +0.82 ns setup and -0.50 ns hold, both of
   which change after placement and CTS. Print them next to those reference values in a comment.
10. `save_block` (the block is named after `$TOP_NAME`; it must equal `$BLK_IMPORT`: check it), then `save_lib`.
    Print the block name and the library path with `unpu_result`.
11. A final summary `unpu_result design_setup` block: library path, number of reference libraries, ports,
    sequential cells, leaf cells, ignored SDC ids, scenarios and their status, the two worst slacks.

### A2. Edits to the task-038 files (additive, tell me exactly what changed)

- `pnr/params.tcl`: new parameters with their sources in comments: `EXPECT_LEAF_CELLS 12487` (18.14),
  `SCEN_SETUP default`, `SCEN_HOLD ff_hold`, `CORNER_SETUP default`, `CORNER_HOLD ff`, `MODE_NAME default`,
  `PARA_TECH_NAME typ`, `EXPECT_SDC_IGNORED {SDC-3 SDC-4}`, `EXPECT_CHECK_TIMING_WARNINGS 1`, and the expected
  operating points `EXPECT_SS_VOLT 1.62`, `EXPECT_SS_TEMP 125`, `EXPECT_FF_VOLT 1.98`, `EXPECT_FF_TEMP -40` (18.2).
- `pnr/common.tcl`: `unpu_read_ndm_manifest`; any other pure-Tcl helper you need (for example a function that
  extracts voltage and temperature from the text of `report_corners`, or the set of message ids from captured
  output) goes here so it can be tested locally.
- `pnr/ndm_check.tcl`: use `unpu_read_ndm_manifest`.
- `pnr/test_common.tcl`: tests for every new pure-Tcl procedure and parameter, with made-up captured text
  (include a text that contains the success phrase, one that lacks it, one with unexpected message ids).
- `pnr/README.md`: mark `design_setup.tcl` written; add `UNPU_LIB_OVERWRITE` to the table.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (show the output; the old 70 tests still pass).
2. All `pnr/*.tcl` are complete Tcl (`info complete`).
3. A stub-interpreter run of `design_setup.tcl` and of `ndm_check.tcl` on a fake setup (scratch directory only):
   show the logged command sequence of `design_setup.tcl` and that it matches the order in A1 (`create_lib`,
   `report_ref_libs`, `read_parasitic_tech`, `read_verilog`, `link_block`, `read_sdc`, `create_corner`,
   `create_scenario`, the scenario selection, `read_sdc` again, `set_operating_conditions`, `set_scenario_status` x2,
   `set_parasitic_parameters` x2, the reports, `check_timing` x2, `save_block`, `save_lib`). Also show these
   failure paths firing: library exists without `UNPU_LIB_OVERWRITE`; linked text without "successfully linked";
   port count 203; `report_corners` text with 1.8 V at the first corner. State what this proves and does not.
4. `grep`: no absolute `/storage` path in the new code; no `FOUNDRY`; nothing written under `SCL_KIT_ROOT`.
5. `git status`: only `pnr/` files changed or added (nothing under `rtl/`, `constraints/`, `syn/`).

## Part C — server block for the user (in your report)

csh commands in order, with `$UNPU_REPO` as the clone path placeholder: environment, `mkdir -p` of the log
directory, `icc2_shell -file ... design_setup.tcl -output_log_file ...`; what a good result looks like (the
RESULT/CHECK lines, counts 204 / 2465 / 12487, `report_corners` numbers); the grep to paste back; and the
rerun recipe if it must be repeated (`UNPU_LIB_OVERWRITE 1`).

## Constraints that apply

Standing rules of task 038 (nothing fails silently; nothing hardcoded; no fallbacks that hide a missing input;
no `$FOUNDRY`; kit files read-only; do not change a plan value; mark every tool command or option not shown in the
handoff `VERIFY`, do not guess). Do not read or write the libraries of the first run (`icc2_work/unpu_lib`).

## Out of scope

Floorplan, don't-use cells, power, pins, placement and everything after (later tasks); the hold uncertainty (the SDC
value stays); the Calibre and PrimeTime scripts; `rtl/`, `constraints/`, `syn/`; `docs/planning/`; running anything on
the server; committing (wait for Planning).

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item with the command involved,
anything in this prompt that is wrong or ambiguous, and the Part C block. Stop after reporting.
