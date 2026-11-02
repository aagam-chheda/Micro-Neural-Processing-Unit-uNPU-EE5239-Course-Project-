# pnr/ — status of the `VERIFY` items (task 047)

Evidence is the server pull of 2026-11-01: `rpt/help/<cmd>.txt` and `rpt/help_lm/<cmd>.txt` (usage texts of the help probes),
`rpt/help/summary.txt`, `rpt/help/version.txt`, `rpt/help/appopt_*.txt`, `logs/ndm_check.log`, `logs/help_probe*.log`,
`ndm_file_gen.log`. Those two scripts and the probes are the only things that have run in scripted form; every other script
has so far run only on the stub interpreter. So:

- **CONFIRMED (usage)** = the command and the options/argument forms the script uses are in the usage text. It does NOT show that
  the script's flow works or what the command prints.
- **CONFIRMED (run)** = the command actually ran in `ndm_check.tcl`, `ndm_file_gen.tcl` or a probe and behaved as the script assumes.
- **CONTRADICTED** = the real files show the script is wrong; fixed in task 047 (see the fix column).
- **UNKNOWN** = no real text exists yet; "settled by" says which output would decide it.

Totals: **CONTRADICTED 5** (all fixed), **CONFIRMED 53** (12 by run, 41 by usage), **UNKNOWN 32** (+ 9 added by task 053 and 6 by task 054 at the end of this file).

## Contradicted (fixed)

| # | Script / procedure | What the script assumed | What the files show | Fix |
|---|---|---|---|---|
| C1 | `floorplan.tcl` (dont_use loop), params `PROBE_COMMANDS_ICC2` | `set_dont_use <cells>` is a command | `summary.txt`: `set_dont_use` NOT_FOUND, `help set_dont_use`: "No commands matched (CMD-040)". The handoff text of 18.15 is wrong on this; the `ATTR-12` "block-level overrides" it quotes is what `set_attribute` on library cells prints | `set_attribute -objects $coll -name dont_use -value true` (usage `set_attribute.txt`: `-objects`, `-name`, `-value`; the positional form also exists). Counts and checks (15 matched, 18 total, the 3 library cells) unchanged. `set_dont_use` stays in the probe list only as the record of the NOT_FOUND |
| C2 | `cts.tcl` hold uncertainty | `set_clock_uncertainty -hold 0.5 [get_clocks clk]` acts on the scenario made current just before | `set_clock_uncertainty.txt`: without `-modes/-corners/-scenarios` it acts on the current scenario, and for the default of corners "all corners" is the wording; the safe form names the scenario | `set_clock_uncertainty -hold -scenarios $SCEN_HOLD $HOLD_UNCERT [get_clocks clk]`; the read-back check stays |
| C3 | `params.tcl` `NDM_MODE`, `ndm_file_gen.tcl`, `ndm_check.tcl`, README | mode `single` (fillers in the main NDM) is the goal and the default | `ndm_file_gen.log`: `Skipped 6 physical designs (LM-052)` then `Workspace check succeeded!`; 0 of 3 fillers listed; `ndm_check.log`: 534 cells, 0 fillers, `single_mode_worked = no` | default is now `two`; `single` stays as an option with a Warning that quotes the evidence; `ndm_check.tcl` in mode `two` checks the manifest order (main, fillers), 534 cells and 0 fillers in the main NDM, exactly the 3 fillers in the second, 537 in total; `ndm_file_gen.tcl` prints the LM-052 skipped count as a RESULT |
| C4 | `common.tcl` `unpu_reflib_open` (used by `design_setup.tcl`) | an open reference library is on a line that contains the word "open" | the real `report_ref_libs` (`ndm_check.log`) marks open libraries with `*` in a flag column: `*+  scl18fs120 <path> <path>`; the word "open" is only in the legend. The old parser returned 0 and `design_setup.tcl` would have FAILED its `reflib_open_*` check | the parser accepts a line whose flags contain `*` (name must be the first word after the flags), and still the word "open"; tests with the real text |
| C5 | `common.tcl` `unpu_app_option_from_report` (route.tcl antenna switch) | layout unknown (columns guessed) | `appopt_XantennaX.txt`: columns `Name Type Value User-value User-default System-default Scope Status Source`, `--` for empty; `route.detail.antenna bool -- -- -- true block normal --`. The old rule would have called a `Value false / System-default true` row ambiguous | for a `bool` row the effective value is the first column of Value, User-value, User-default, System-default that is not `--`; the old rule remains for other layouts. Tests with the real rows |

## Confirmed by a run (12)

| # | Where | Behaviour | Evidence |
|---|---|---|---|
| R1 | `-file`, `-output_log_file` in `icc2_shell` and `icc2_lm_shell` (every script header) | work | `logs/*.log` were produced that way |
| R2 | `common.tcl` `unpu_tool_version` and every `unpu_require_tool_version` | `sh_product_version` is a Tcl variable and readable by `get_app_var` and `printvar`: `U-2022.12-SP3` in both shells; no pager (`sh_enable_page_mode` false) | `rpt/help/version.txt`, `rpt/help_lm/version.txt`, `logs/ndm_check.log` ("tool version ... matches") |
| R3 | `common.tcl` `unpu_stage_begin` | `set_app_var sh_continue_on_error false` works in both shells | no "could not set" Warning in any log |
| R4 | `common.tcl` `unpu_run_logged` | `redirect -variable ::VAR {script}` captures the messages of a command | `ndm_file_gen.log`: "Workspace check succeeded!" was found in the captured text (the script would have stopped otherwise) |
| R5 | `ndm_check.tcl` | `create_lib -technology <tf> -ref_libs <one path> <path>` | `ndm_check.log` scratch library created |
| R6 | `ndm_check.tcl` | `report_ref_libs` | `ndm_check.log` (the table quoted in C4) |
| R7 | `ndm_check.tcl` | `get_libs -quiet <name>` finds a reference library | `ndm_check.log` CHECK `opens_scl18fs120` PASS |
| R8 | `ndm_check.tcl` | `get_lib_cells <lib>/*`, `get_lib_cells -quiet */feedth*` | `ndm_check.log` 534 cells, 0 fillers |
| R9 | `ndm_check.tcl` | `get_attribute <lib_cell> dont_use` / `design_type`; `get_lib_cells -quiet -filter "dont_use==true" */*` | `ndm_check.log` `{scl18fs120/adiode scl18fs120/bh01d1 scl18fs120/cload1}`, count 3 |
| R10 | `ndm_check.tcl` | `close_lib` | `ndm_check.log` ends normally |
| R11 | `ndm_file_gen.tcl` | in `icc2_lm_shell`: `create_workspace -flow normal -technology`, `read_lef`, `read_db`, `check_workspace`, `commit_workspace`, `get_lib_cells`, `foreach_in_collection`, `get_object_name`, `set_attribute <obj> design_type filler` | `ndm_file_gen.log` (mode single ran to the end) |
| R12 | `ndm_file_gen.tcl` | the success text of `check_workspace` is "Workspace check succeeded!" (and `Information: Skipped 6 physical designs (LM-052)` precedes it) | `ndm_file_gen.log` lines 6819 and 6921 |

## Confirmed by usage text (41)

Option names and argument forms in the scripts match the usage files. The output text of these commands is a separate matter (see Unknown).

| # | Script (lines) | Command and forms used | Usage file |
|---|---|---|---|
| U1 | `cts/route/fill/floorplan/power.tcl` | `get_blocks -quiet <name>` | `get_blocks.txt` |
| U2 | `common.tcl` | `open_lib <path>`, `open_block <lib>:<block>`, `current_block`, `current_lib`, `save_block -as`, `close_blocks -force`, `save_lib` | `open_lib/open_block/current_block/current_lib/save_block/close_blocks/save_lib.txt` |
| U3 | `design_setup.tcl` | `create_lib -technology -ref_libs` (option names) | `create_lib.txt` (`-ref_libs paths`) |
| U4 | `design_setup.tcl` | `read_parasitic_tech -name -tlup -layermap` | `read_parasitic_tech.txt` |
| U5 | `design_setup.tcl` | `read_verilog -top <module> <file>`, `link_block`, `read_sdc <file>` | `read_verilog/link_block/read_sdc.txt` |
| U6 | `design_setup.tcl` | `create_corner <name>`, `create_scenario -name -mode -corner`, `current_scenario <name>`, `set_scenario_status <s> -setup <b> -hold <b>`, `set_operating_conditions <cond> -library`, `set_parasitic_parameters -corners -early_spec -late_spec` | the same-named usage files |
| U7 | `design_setup.tcl` | `report_corners`, `report_scenarios`, `report_parasitic_parameters`, `check_timing` exist | usage files |
| U8 | `design_setup.tcl` | `get_timing_paths -delay_type -max_paths`, `get_scenarios`, `report_timing -delay_type -max_paths` | `get_timing_paths.txt`, `report_timing.txt` |
| U9 | `floorplan.tcl` | `initialize_floorplan -boundary -core_offset` | `initialize_floorplan.txt` |
| U10 | `floorplan.tcl` | `get_site_rows [-quiet]`, `get_site_defs <name>`, `index_collection` | usage files |
| U11 | `floorplan.tcl` | `report_design -floorplan` | `report_design.txt` (`-floorplan`: "site rows/ plan groups/ ...") |
| U12 | `floorplan.tcl` | `set_attribute -objects -name -value` (C1) | `set_attribute.txt` |
| U13 | `power.tcl` | `create_net -power / -ground <name>` | `create_net.txt` |
| U14 | `power.tcl`, `fill.tcl` | `connect_pg_net -automatic` | `connect_pg_net.txt` |
| U15 | `common.tcl unpu_pg_commands` | `create_pg_std_cell_conn_pattern -layers -rail_width`, `create_pg_mesh_pattern -layers`, `set_pg_strategy -core -pattern`, `compile_pg -strategies` | usage files |
| U16 | `power.tcl` | `create_shape -shape_type rect -layer -boundary -net -shape_use`; `shape_use` values include `stripe` and `follow_pin` (so `PG_RAIL_SHAPE_USE follow_pin` is a valid VALUE; whether `get_shapes -filter shape_use==follow_pin` matches is U-unknown, below) | `create_shape.txt` |
| U17 | `power.tcl` | `create_terminal -of_objects <shapes>`; `get_terminals -of_objects <net>`; `get_shapes -of_objects -filter -quiet`; `get_pins -leaf -of_objects`; `get_nets -quiet` | usage files |
| U18 | `power.tcl` | `check_pg_drc`, `check_pg_connectivity` (no options used) | usage files |
| U19 | `cts.tcl` | `set_lib_cell_purpose -exclude cts <lib_cell_list>` (values `all cts hold none optimization power`) | `set_lib_cell_purpose.txt` |
| U20 | `cts.tcl` | `clock_opt -to build_clock`, `clock_opt -from route_clock -to final_opto`; the step names are `build_clock route_clock final_opto` | `clock_opt.txt` (`-list_only` text) |
| U21 | `cts.tcl` | `set_clock_uncertainty -hold -scenarios <s> <v> <clocks>` (C2) | `set_clock_uncertainty.txt` |
| U22 | `cts.tcl`, `common.tcl` | `report_clock_qor -type summary` | `report_clock_qor.txt` (`summary` among the types) |
| U23 | `common.tcl` `unpu_paths` | `report_timing -delay_type <max|min> -slack_lesser_than -max_paths -nosplit` | `report_timing.txt` |
| U24 | `cts/route/fill.tcl` | `check_legality` (no options) | `check_legality.txt` |
| U25 | `cts/route/fill.tcl` | `report_utilization`, `report_qor` exist (no options used) | usage files |
| U26 | `route.tcl` | `define_antenna_rule -mode -diode_mode -metal_ratio -cut_ratio` (ranges 1..6 and 0..23) | `define_antenna_rule.txt` |
| U27 | `route.tcl` | `route_auto`, `route_opt` (NO options, as used), `check_routes`, `check_lvs` (no options) | usage files |
| U28 | `route.tcl` | `report_app_options <pattern>` and `get_app_options <pattern>` exist; the application option `route.detail.antenna` exists, type bool, default true | `report_app_options.txt`, `appopt_XantennaX.txt` |
| U29 | `fill.tcl` | `create_stdcell_fillers -lib_cells <collection> -prefix <s> -rules post_route_auto_delete` | `create_stdcell_fillers.txt` |
| U30 | `fill.tcl` | `remove_stdcell_fillers_with_violation -check_only true` | `remove_stdcell_fillers_with_violation.txt` |
| U31 | `fill.tcl` | `route_eco` (no options) | `route_eco.txt` |
| U32 | `fill.tcl` | `get_cells -quiet -hierarchical -filter <expr>`; `get_lib_cells -quiet <pattern>` | usage files |
| U33 | `outputs.tcl` | `write_verilog -hierarchy <scope> -include/-exclude {...}` with the values `all_physical_cells leaf_module_declarations pg_netlist pg_objects supply_statements` | `write_verilog.txt` |
| U34 | `outputs.tcl` | `create_frame -block_all true`; `write_lef -design <d> -include cell <file>` (values `cell tech`) | `create_frame.txt`, `write_lef.txt` |
| U35 | `outputs.tcl` | `write_parasitics -corner <c> -output <f>`; `write_sdf -corner <c> <file>`; `write_sdc -scenario <s> -output <f>` | `write_parasitics/write_sdf/write_sdc.txt` |
| U36 | `outputs.tcl` | `write_gds -design -units -layer_map_format -layer_map -merge_files -output_pin <file>` | `write_gds.txt` |
| U37 | `outputs.tcl` | `get_ports`, `get_object_name` | usage files |
| U38 | `common.tcl` | `redirect -file <f> <cmd>` and `-variable` (target then command string) | `redirect.txt` |
| U39 | `common.tcl` | `sizeof_collection`, `foreach_in_collection`, `index_collection`, `get_app_var`, `printvar`, `set_app_var` | usage files |
| U40 | `help_probe*.tcl` | `help <pattern>`, `-help` per command | the probe logs and `summary.txt`: 140/141 and 23/24 found |
| U41 | `ndm_file_gen.tcl` | `create_workspace -flow physical_only -technology <tf> <name>` (the form for the second NDM; option names and the flow value are in the usage; the form has not RUN yet) | `rpt/help_lm/create_workspace.txt` |

## Unknown (32): what would settle each

| # | Where | Item | Settled by |
|---|---|---|---|
| K1 | `route.tcl` 85 | `get_app_option_value -name` — NOT in the probe list (only `get_app_options` / `report_app_options` were probed) | next probe: add `get_app_option_value` to `PROBE_COMMANDS_ICC2`; until then the script falls back to the printed `report_app_options` row (C5), which is now known to work |
| K2 | `cts.tcl` 174, `common.tcl` 1468 | `report_constraint -all_violators -max_transition / -max_capacitance` — not probed (only `report_constraint_mapping_file` appeared in the wildcard list) | next probe: add `report_constraint` |
| K3 | `common.tcl` 306 | wording of unresolved references in the `link_block` output | the log of `design_setup.tcl` |
| K4 | `common.tcl` 331 | `report_corners` text (voltage/temperature layout) | the log of `design_setup.tcl` |
| K5 | `common.tcl` 380 | `report_design -floorplan` text (chip area / core area / utilisation layout) | the log of `floorplan.tcl` |
| K6 | `common.tcl` 458 | `connect_pg_net -automatic` summary layout (note: usage has `-report_connection_summary (false|true)`; whether the plain call prints the table of 18.22 is unknown) | the log of `power.tcl` |
| K7 | `common.tcl` 591–634 | `report_clock_qor -type summary` text layout | the log of `cts.tcl` |
| K8 | `common.tcl` 732–800 | `check_routes` Verify Summary, `check_lvs`, route summary, DR iterations, `ZRT-311` line layout | the log of `route.tcl` |
| K9 | `fill.tcl` | per-cell "N of regular filler X inserted" lines, `connect_pg_net` previous/current table, `remove_stdcell_fillers_with_violation` output text | the log of `fill.tcl` |
| K10 | `common.tcl` 1003 | netlist instance layout `<type> <name> (` | the log of `outputs.tcl` |
| K11 | `common.tcl` 1068 | `write_sdc` uncertainty line layout | the log of `outputs.tcl` |
| K12 | `outputs.tcl` | GDS text records: port names exactly as the ports; LEF VDD/VSS rectangle count = stripe count | the log of `outputs.tcl` |
| K13 | `design_setup.tcl` 69–72 | `get_attribute <timing_path> slack` | the log of `design_setup.tcl` (a fallback to `report_timing` exists) |
| K14 | `design_setup.tcl` 191 | `get_attribute <scenario> setup/hold` | the log of `design_setup.tcl` |
| K15 | `floorplan.tcl` 88 | `boundary_bbox` attribute value format `{llx lly} {urx ury}` | the log of `floorplan.tcl` |
| K16 | `floorplan.tcl` 103–111 | attributes `site_name` (site row), `width`, `height` (site def) | the log of `floorplan.tcl` |
| K17 | `power.tcl` 57–61 | `get_nets -quiet` / `get_shapes -of_objects` on an empty block | the log of `power.tcl` |
| K18 | `power.tcl` 127 | `get_shapes -filter "layer_name==M1 && shape_use==follow_pin"` matches the rails | the log of `power.tcl` (a fallback to the layer alone exists) |
| K19 | `power.tcl` 162, 181 | attribute `layer` and `bbox` on a terminal | the log of `power.tcl` |
| K20 | `power.tcl` 194 | texts of `check_pg_drc` and `check_pg_connectivity` | the log of `power.tcl` |
| K21 | `common.tcl` 1262 | `save_lib` with the new block open persists the library and reference list | the log of `design_setup.tcl` / `floorplan.tcl` |
| K22 | `common.tcl` 1230–1252 | `current_block` name format after `open_block` / checkpoint | the log of `design_setup.tcl` |
| K23 | `ndm_check.tcl` 51 | `create_lib -ref_libs` with a LIST of two paths | `ndm_check.tcl` in mode two |
| K24 | `ndm_file_gen.tcl` | the second workspace form (`-flow physical_only -technology`) runs | `ndm_file_gen.tcl` in mode two |
| K25 | `route.tcl` 66 | whether a block already has routed nets (no command known) | stays a Warning; a `route_auto` summary would show |
| K26 | `route.tcl` | wording and count of `OPT-209`, `ZRT-309` after `define_antenna_rule` | the log of `route.tcl` |
| K27 | `cts.tcl` 210, `route/fill.tcl` | `report_utilization` / `report_qor` texts (area, instances, utilisation, wire length) | the logs of `cts.tcl` / `route.tcl` |
| K28 | `fill.tcl` | `get_cells -filter "ref_name==<cell>"` attribute name | the log of `fill.tcl` |
| K29 | `fill.tcl` | `route_eco` output: names of nets changed | only if `UNPU_FILL_ECO=1` is used |
| K30 | `design_setup.tcl` 131 | the "Design 'unpu_top' was successfully linked" text | the log of `design_setup.tcl` |
| K31 | `design_setup.tcl` 102 | `create_lib ... -ref_libs` with a list and the library persisting its reference list | as K23 |
| K32 | `common.tcl` 1425 | `current_scenario <name>` also prints the old name | the log of `design_setup.tcl` |

## Facts for the handoff

- 18.15 says the 18 dont_use cells came from `set_dont_use`; that command does not exist in this release. The attribute was set with `set_attribute` on library cells.
- Mode `single` of the NDM build cannot work on this kit (C3). The two-NDM layout (`scl18fs120` + `scl18fs120_fillf`, 537 cells) is the default now.
- The icc2 Tcl is 8.6.11 (`info patchlevel`, `version.txt`); the scripts do not rely on 8.5-only behaviour.

## Added by task 053 (stage profiles in the layout flow): all UNKNOWN until the probe and the first run

| # | Where | Item | Settled by |
|---|---|---|---|
| K34 | `common.tcl unpu_clock_facts` | `get_attribute <clock> period` and `is_propagated` (or `propagated_clock`) on the clock `clk` | the probe of `get_clocks` / the first `design_setup` log |
| K35 | `common.tcl unpu_parse_report_clocks` | the layout of `report_clocks` (a table `Clock Period Waveform Attrs Sources`, attribute `p` = propagated) — the fallback when the attributes fail | the probe output of `report_clocks` |
| K36 | `common.tcl unpu_apply_profile` | `set_propagated_clock [get_clocks clk]` (command unprobed) | the probe of `set_propagated_clock` |
| K37 | `common.tcl unpu_apply_profile`, `cts.tcl` mode `hold` | whether a `read_sdc` in a block that already has a clock tree keeps the tree and the propagation, or redefines `clk` destructively; the read-back CHECKS (period, uncertainty, propagation) make a failure loud, no fallback that skips `create_clock` is written | the log of `cts.tcl` (mode hold) and `route.tcl` |
| K38 | `common.tcl unpu_profile_readback` | the `clock uncertainty` line of `report_timing` as the read-back of the setup (max) and hold (min) uncertainty | the log of `design_setup.tcl` |
| K39 | `common.tcl unpu_profile_numbers` | `interp create` inside icc2_shell (Tcl 8.6): the expected profile numbers are computed by running the SDC's table section in a slave interpreter | the log of `design_setup.tcl` |
| K40 | `design_setup.tcl` | that the profile SDC (no wire load model, no `set_max_area`) prints no `SDC-` ids (the DC-written SDC printed SDC-3 and SDC-4); `EXPECT_SDC_IGNORED` is empty | the log of `design_setup.tcl` |
| K41 | `common.tcl unpu_apply_profile` | `puts`, `error`, `foreach`, `expr` and `info exists ::env(...)` inside `read_sdc` of icc2_shell (as for dc_shell, task 051) | the log of `design_setup.tcl` |
| K42 | `common.tcl unpu_netlist_counts` | that the flattened leaf-cell count from the netlist text equals ICC2's `is_hierarchical==false` count (instance lines `<type> <name> (`); a mismatch is the `leaf_cells` CHECK of `design_setup.tcl` | the log of `design_setup.tcl` |

## Added by task 054 (die, utilisation, congestion, growth): all UNKNOWN until the first run

| # | Where | Item | Settled by |
|---|---|---|---|
| K43 | `common.tcl unpu_parse_utilization`, `unpu_check_utilization` | which number `report_utilization` / `report_qor` calls "utilization" (assumed: standard-cell area / core area, with or without %); the script cross-checks it with the parsed cell area / the derived core area and warns above 0.5 percentage points | the log of `placement.tcl` |
| K44 | `common.tcl unpu_parse_syn_area` | the real layout of `unpu_top.area` is the round-3 one ("Total cell area:   429161.242546"); the new report is written by the same DC `report_area` | the first `syn20` run |
| K45 | `common.tcl unpu_check_congestion` | `report_congestion` and its options (called bare), whether it needs a global-route congestion map first (`route_global -congestion_map_only` or `-rerun_global_router`), and the layout "Both Dirs: Overflow = N Max = M GRCs = K (x.xx%)" that `unpu_parse_congestion` assumes | the probe of `report_congestion` and the log of `placement.tcl` |
| K46 | `common.tcl unpu_growth_row` | `get_cells -hierarchical -quiet -filter "ref_name=~<pattern>"` (the filter operator and the attribute, as K28) and the cell attribute `area`; the cells added by a stage cannot be told from the earlier ones, so the classes are by name pattern | the log of `placement.tcl` |
| K47 | `params.tcl GROWTH_CLASSES` | the class patterns come from the library listing in the NDM build log: buffers `buf*` (bufbd, buffd, buftd), inverters `inv*` (inv0d, invbd, invtd), delay cells `dl0*` (12 cells); `clk2d2` is not counted; the listing shows no tie or spare cell names, so those are "not counted" | the library listing of a later probe (`get_lib_cells`) |
| K48 | `floorplan.tcl` | that `initialize_floorplan -boundary` with the derived core accepts any number of rows (not only the 153 of the old die) | the log of `floorplan.tcl` |
