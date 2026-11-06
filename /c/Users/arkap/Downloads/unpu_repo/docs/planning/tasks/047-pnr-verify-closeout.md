# Task 047 — close the `VERIFY` items against the real tool output, fix what is wrong

The user ran the two help probes and the first two scripts on the server and copied the results to this machine. You can
now read real facts instead of guessing. Files (read-only for you; do NOT write there):

- `~/server_pull/rpt/help/` (icc2_shell): one `<command>.txt` per command with its usage, `summary.txt`, `version.txt`,
  `all_commands.txt`, `all_wildcards.txt` (command names matching `*pin*`, `*place*`, ...), `all_appopts.txt`
  (application options), `appopt_<pattern>.txt`; `~/server_pull/rpt/help_lm/` (icc2_lm_shell), same layout;
  `~/server_pull/rpt/help_pick.txt` (a selection of the above).
- `~/server_pull/logs/` and `~/server_pull/ndm_file_gen.log`, `ndm_manifest.txt`, `manifest_ndm_file_gen.txt`: the real logs
  of `help_probe*.tcl`, `ndm_file_gen.tcl` (mode single) and `ndm_check.tcl`.

## What the server run already showed (verified by Planning from those files)

- `-file` and `-output_log_file` work in both shells. `sh_product_version` holds `U-2022.12-SP3` in both; no pager.
- 140 of 141 icc2 commands and 23 of 24 library-manager probes exist. **`set_dont_use` is NOT a command in this version**
  (`help set_dont_use`: "No commands matched", `CMD-040`); `floorplan.tcl` uses it. 18.15 of the handoff says the first
  run got `dont_use==true` on 18 cells with `ATTR-12` "block-level overrides", which is what `set_attribute` on library
  cells prints; the command used there was most likely `set_attribute`, and the handoff text is wrong.
- **Mode `single` of `ndm_file_gen.tcl` cannot work on this kit.** The log: `Read LEF into a new library
  'scl18fs120_std'. (LEFR-022)`, then at `check_workspace`: `Skipped 6 physical designs (LM-052)` and
  `Workspace check succeeded!`; `get_lib_cells` listed 0 of the 3 fillers; `ndm_check`: 534 cells, 0 fillers,
  `single_mode_worked = no`. The six LEF-only cells have no logical view and the workspace skips them.
  Mode `two` (the fillers in a second NDM built in the same run) is the way.
- `ndm_check.tcl`: `get_libs`, `get_lib_cells`, `get_attribute dont_use`, the `-filter "dont_use==true"` form all worked
  (`adiode`, `bh01d1`, `cload1` are `dont_use` in the library, count 3 as expected).
- `set_clock_uncertainty` (usage file): without `-modes`/`-corners`/`-scenarios` it acts on the current scenario; `route_opt` has
  NO options; `create_placement` has `-floorplan -timing_driven -congestion`; `place_opt` has `-list_only -from -to`;
  `place_pins` has `-self -legalize -nets -pins -ports`; `set_block_pin_constraints` has `-sides -pin_spacing_distance
  -width -length -allowed_layers -self -hard_constraints`; `set_individual_pin_constraints` has `-ports -sides -offset -width
  -length -allowed_layers -location`.

## Goal

1. Go through every `VERIFY` comment in `pnr/*.tcl`. For each, find the evidence in the files above and decide:
   CONFIRMED (cite file and line), CONTRADICTED (cite, then fix the code), or STILL UNKNOWN (say what output would settle it).
2. Fix every contradicted item, with tests.
3. Make mode `two` the default NDM mode.
4. Write `pnr/VERIFY_STATUS.md` with the table.

## Part A — what to do

### A1. The VERIFY table

`pnr/VERIFY_STATUS.md`: one row per `VERIFY` item (script, line or procedure, the command or behaviour, status, evidence
file and line or the reason it is unknown). Items about command or option EXISTENCE and spelling are settled by the usage
files: read the actual `<command>.txt` for every command your scripts call, and compare option names AND argument forms
(for example `report_timing -slack_lesser_than`, `get_site_rows -quiet`, `get_blocks -quiet`, `current_scenario <name>`,
`create_stdcell_fillers -lib_cells -prefix -rules`, `remove_stdcell_fillers_with_violation -check_only true`,
`define_antenna_rule -mode -diode_mode -metal_ratio -cut_ratio`, `create_shape`/`create_terminal`, `initialize_floorplan`,
`create_lib`, `read_parasitic_tech`, `report_design -floorplan` (read `report_design.txt` for the option), `report_utilization`,
`report_clock_qor -type summary`, `check_routes`, `check_lvs`, `write_*`). Items about OUTPUT TEXT layouts (for example
`report_corners`, `report_clock_qor`) stay unknown unless the files show them; say so.

### A2. Fixes

- `floorplan.tcl`: replace `set_dont_use` by the real mechanism (`set_attribute` on the library cells, usage in
  `set_attribute.txt`; confirm the argument form, object first or `-objects`); keep the counts and the checks (matched 15, total
  18, the three library-flagged cells). Update the tests, README and comments.
- `cts.tcl`: `set_clock_uncertainty -hold` must name the scenario explicitly (`-scenarios $SCEN_HOLD`), per the usage text.
- `ndm_file_gen.tcl`, `ndm_check.tcl`, `params.tcl`, `README.md`: default `NDM_MODE` becomes `two`. Mode `single` stays as an
  option but its header and Warning must now say, with the evidence (`LM-052`, 0 of 3, `single_mode_worked = no`), that it does not
  work on this kit. In mode `two` `ndm_check.tcl` must check both NDMs (534 cells in the first, the 3 fillers typed `filler` in
  the second, 537 in total, `design_type` filler, none `dont_use`); read the existing code and make sure those checks are right
  for two reference libraries; `ndm_manifest.txt` lists both, main first.
- Anything else the table shows to be contradicted: fix it; if the fix is bigger than a few lines in one script, stop and
  tell me instead of doing it.
- Do not change a plan value; do not add a feature; do not touch the output-text parsers except where a real text from the files
  above shows them wrong (the only real texts available are the library-manager messages and the `ndm_check`/`help_probe` logs).

### A3. Parsers against real text

The `check_workspace` success test, the `unpu_reflib_open` parser (given the real `report_ref_libs` in
`~/server_pull/logs/ndm_check.log` if it is printed there), and the version probe are the only ones with real text. Run
them on the real text (copy the lines into a test fixture inside `test_common.tcl`, not a path to the home directory) and say if
they hold.

## Part B — checks

1. `tclsh pnr/test_common.tcl` passes (the old 338 tests still pass, new ones added; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. Stub runs of `floorplan.tcl` and `cts.tcl` after the change (scratch only), showing the new commands in the log sequence.
4. `grep`: no `set_dont_use` remains in code (only in comments saying it does not exist); no absolute `/storage` besides the
   two defaults; no `~/server_pull` path in any script or test.
5. `git status`: only `pnr/` changed. Do not commit.

## Report back

The VERIFY table (summarised: counts confirmed / contradicted / unknown, and the list of the contradicted ones with the fix),
Part B output, the parsers-on-real-text result, anything in this prompt that is wrong or ambiguous. Stop after reporting.

## Out of scope

New stage scripts (pin placement and placement come next, in their own tasks); Calibre; PrimeTime; `rtl/`, `constraints/`, `syn/`,
`docs/planning/`; running anything on the server; committing.
