# Task 042 — back-end re-run: the command-usage probe (stops the guessing before the placement, CTS and routing scripts)

## Why this task comes now

Every script so far marks the tool commands it could not check as `VERIFY`. The next scripts (pin placement, placement,
CTS, routing, fill, outputs) use many commands and options that the first run never showed in the handoff, and the
tool's own `-help` is the only reliable source. You cannot run the tools; the user can, in a minute. So this task
writes two small scripts that print the usage of every command the flow uses (and discover the ones we do not know
the names of) into files. The user runs them once and pastes the output back; Planning then writes the remaining tasks
against the real syntax instead of guesses, and the `VERIFY` list of the earlier scripts is closed or corrected.

## Goal

`pnr/help_probe.tcl` (runs in `icc2_shell`) and `pnr/help_probe_lm.tcl` (runs in `icc2_lm_shell`): they collect the
usage text of a list of commands, the commands that exist for a list of name patterns, and the application options for a
list of patterns, into `$RPT_DIR/help/`, with one summary file that says which commands were found.

## Part A — what to write

### A1. Parameters (`pnr/params.tcl`, additive)

Three lists, each commented with why it is there:

- `PROBE_COMMANDS_ICC2`: the commands of `icc2_shell` whose usage we need. At least these (add any other tool command
  your own scripts use; the list must contain every tool command used in `pnr/*.tcl` that carries a `VERIFY`
  comment): `create_lib open_lib close_lib save_lib open_block save_block close_blocks get_blocks current_block
  current_lib report_ref_libs read_parasitic_tech read_verilog link_block read_sdc create_corner create_scenario
  current_scenario set_scenario_status set_operating_conditions set_parasitic_parameters report_corners report_scenarios
  report_parasitic_parameters check_timing get_timing_paths report_timing report_qor report_design report_utilization
  initialize_floorplan get_site_rows get_site_defs set_dont_use get_lib_cells get_attribute set_attribute
  create_net connect_pg_net create_pg_std_cell_conn_pattern create_pg_mesh_pattern set_pg_strategy compile_pg
  check_pg_drc check_pg_connectivity create_shape create_terminal get_terminals get_shapes remove_terminals remove_shapes
  set_block_pin_constraints set_individual_pin_constraints place_pins create_placement place_opt legalize_placement
  check_legality refine_placement set_app_options get_app_options report_app_options set_lib_cell_purpose clock_opt
  set_clock_uncertainty report_clock_qor report_clock_timing route_auto route_global route_track route_detail route_opt
  route_eco check_routes check_lvs define_antenna_rule remove_routes set_routing_rule create_stdcell_fillers
  remove_stdcell_fillers_with_violation create_frame write_lef write_verilog write_parasitics write_sdf write_sdc
  write_gds add_port_protection_diodes report_port_protection_diodes insert_buffer create_cell index_collection
  redirect foreach_in_collection sizeof_collection`.
- `PROBE_WILDCARDS_ICC2`: patterns passed to `help` (a pattern such as `*pin*` lists the commands whose name matches;
  `help *protection_diode*` worked in the first run): `*pin*`, `*place*`, `*cts*`, `*clock*`, `*route*`, `*routing*`,
  `*antenna*`, `*diode*`, `*filler*`, `*frame*`, `*write_*`, `*buffer*`, `*terminal*`, `*scenario*`, `*site*`,
  `*floorplan*`, `*hold*`, `*uncertainty*`, `*lef*`, `*gds*`, `*parasitic*`.
- `PROBE_APPOPT_PATTERNS_ICC2`: patterns for `report_app_options` (or `get_app_options`): `place.*`, `place_opt.*`,
  `clock_opt.*`, `cts.*`, `opt.*`, `route.common.*`, `route.global.*`, `route.track.*`, `route.detail.*`,
  `*hold*`, `*antenna*`, `*pin*`, `*port*`, `time.*`.
- `PROBE_COMMANDS_LM`: `create_workspace read_lef read_db read_lib check_workspace commit_workspace set_attribute
  get_lib_cells get_cells report_workspace remove_workspace`; `PROBE_WILDCARDS_LM`: `*workspace*`, `*lef*`, `*db*`,
  `*lib*`, `*attribute*`, `*filler*`.

### A2. `pnr/help_probe.tcl` and `pnr/help_probe_lm.tcl`

Both have the standard header (csh run line with `$UNPU_REPO`, output files, never) and use `common.tcl`/`params.tcl`.
No design, no library, no checkpoint: a bare shell. Behaviour:

1. `unpu_require_tool_version` (the matching release for each shell), `unpu_stage_begin help_probe run` (shared
   `RPT_DIR`; the output directory is `$RPT_DIR/help/` for icc2, `$RPT_DIR/help_lm/` for the library manager).
2. Print, to the log and to `version.txt`: the version variable (try `sh_product_version` by `puts`, by `printvar`, by
   `get_app_var`; all three, each in a `catch`, each result recorded) and `info patchlevel`. This answers the open
   question about how the release string is exposed (`unpu_tool_version` in `common.tcl` currently guesses).
3. For each command: capture `<cmd> -help` (and, if that fails, `help <cmd>`) into `help/<cmd>.txt` with `redirect
   -file`, each call in a `catch`; record FOUND (text non-empty and not an error), NOT_FOUND, or ERROR with the message.
4. For each wildcard: capture `help <pattern>` into `help/wild_<name>.txt` (replace `*` with `X` in the file name).
5. For each app-option pattern (icc2 only): capture `report_app_options <pattern>`, or `get_app_options <pattern>` if
   that fails, into `help/appopt_<name>.txt`; record FOUND / NOT_FOUND / ERROR. VERIFY which of the two exists.
6. Write `help/summary.txt`: one line per probe (`FOUND|NOT_FOUND|ERROR  <kind>  <name>  <file or message>`) and the
   totals; print the totals and the list of NOT_FOUND names with `unpu_result`. Never stop at the first failure:
   every probe runs.
7. Also write `help/all_commands.txt`: every command of the icc2 probe list concatenated (a banner line `===== <cmd>
   =====` before each text) so the user can paste ONE file; same for the library manager. Keep each captured text as
   the tool printed it.
8. The scripts exit 0 even when probes fail (a missing command is the finding, not an error), but print
   `Warning: [unpu]` for each NOT_FOUND.

### A3. Pure-Tcl helpers and tests

In `common.tcl`: a procedure that classifies a captured text as FOUND/NOT_FOUND/ERROR (empty text, an `Error:` line,
"unknown command", "invalid command name", "no commands match" -> not found/error; anything else FOUND) and one that
builds the file-safe name of a pattern. In `test_common.tcl`: tests with made-up captured texts (a usage text, an empty
text, an `Error: unknown command` text, a `help *pin*` listing), the file-name rule, and that the lists in
`params.tcl` contain no duplicates and include a given core set (`place_pins set_block_pin_constraints
set_individual_pin_constraints create_placement place_opt clock_opt route_auto route_opt define_antenna_rule
create_stdcell_fillers write_gds create_frame`). Update `pnr/README.md`.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 156 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of each probe script (scratch only): a stub in which some commands print a usage, some
   print `Error: unknown command`, one raises a Tcl error. Show the produced `summary.txt` and `all_commands.txt` head,
   and that every probe ran (counts equal the list lengths) and the script exited 0. State what this proves.
4. Show that every tool command with a `VERIFY` comment in `pnr/*.tcl` is in `PROBE_COMMANDS_ICC2` or
   `PROBE_COMMANDS_LM`, or say which is not and why (a short report from a `grep`, not a clever parser).
5. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; nothing written under `SCL_KIT_ROOT`.
6. `git status`: only `pnr/` changed.

## Part C — server block for the user (in your report)

csh commands for both probes (the library manager by its full path), the files to paste back: `help/summary.txt` of
both and `help/all_commands.txt` of both (and `version.txt`), and how large they will be (you can only estimate).
Say which probes take a long time or may hang (an interactive pager is the risk: `help` or `-help` output must never
wait for a key; if you know a way to switch a pager off in these shells, use it, else say it is unknown).

## Constraints that apply

Standing rules of tasks 038 to 041. These scripts only read tool help; they must not create a library, open a block,
or change any state.

## Out of scope

Everything after the power stage; changing the earlier scripts' commands (the probe's results come back to Planning
first); `rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on the server; committing.

## Report back

Files changed or added, Part B output, the `VERIFY` coverage list (item 4), anything in this prompt that is wrong or
ambiguous, and the Part C block. Stop after reporting.
