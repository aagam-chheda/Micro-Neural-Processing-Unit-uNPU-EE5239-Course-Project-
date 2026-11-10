# VERIFY status after run 3 (final layout, 2026-11-11)

Scope: every `VERIFY` item of the four READMEs of the clean flow (`pnr_v2/README.md`, `pnr_v2/pt/README.md`, `pnr_v2/sim/README.md`, `pnr_v2/calibre/README.md`). The older parked flow is NOT covered here (`pnr/VERIFY_STATUS.md` is untouched).

**Numbering.** The four READMEs number their items independently and overlap, so every item is written with its README: `main V19` to `main V89` (pnr_v2/README.md), `pt V1` to `pt V31` (pt/README.md), `sim V1` to `sim V16` (sim/README.md), `cal V1` to `cal V18` (calibre/README.md). `pt V19` (the `parasitics_log_file` variable) is a different item from `main V19` (`[info script]`).

**Statuses.** `VERIFIED` = a log line of run 3 shows the behaviour directly. `VERIFIED (indirect)` = the step that depends on it ran and passed its own checks, and the dependency is named. `STILL OPEN` = no run-3 log shows it, with the reason. `NOT APPLICABLE` = the item belongs to a script or option that is not part of the run-3 chain.

**Evidence base.** Only the files that were copied to the PC: `~/server_pull/run3/pnr_icc2` (written `R3` below: `logs/`, `*_console.log`, `pt/`, `pt_si/`, `pt_legacy/`, `pt_route3/`, `pt_si_before_si/`, `pt_run3_final/`, `calibre/final4/`, `sim/`, `outputs*/`) and `~/server_pull/run3/syn`. `file:line` are lines of those files as copied on 2026-11-11. Nothing was run to produce this table; where the copied files do not show an item it is marked STILL OPEN, not assumed. Many probe logs echo the script source: only the output lines (`>>> NNN ...`) are cited.

**Count.** 136 items: VERIFIED 105 (some of them partly: marked `(partly)` or `(value corrected)` in the table), VERIFIED (indirect) 8, STILL OPEN 14, NOT APPLICABLE 9 (main V33-V40 count 8, main V74 counts 1). See the summary at the end.

---

## Calibre README (cal V1-V18)

| ID | Item | Status | Evidence (R3/calibre/final4 unless stated) |
|---|---|---|---|
| cal V1 | `v2lvs` on the path, `calibre -version` 2022.4_37.20 | VERIFIED | `lvs/v2lvs.log:1` `v2lvs v2022.4_37.20`; `lvs/lvs.log:1` `Calibre v2022.4_37.20` |
| cal V2 | LVS deck present in the working copy of the decks | VERIFIED | `drc/drc.ctrl:16` `INCLUDE ".../calibre_run/scr/DRC_TS18SL_SCL_CALIBRE"` and the LVS run `lvs/lvs.log` finishing with `CORRECT` (`lvs/unpu_top.lvs.rpt:45`) |
| cal V3 | top cell is `unpu_top` | VERIFIED | `lvs/unpu_top.lvs.rpt:45` `CORRECT unpu_top unpu_top`; `drc/drc.ctrl` `LAYOUT PRIMARY` |
| cal V4 | the top cell is the last design-named structure in the GDS | VERIFIED (indirect) | DRC/LVS ran with `LAYOUT PRIMARY unpu_top` and produced results; the `gds_names.txt` step was not repeated in run 3 |
| cal V5 | `calibredrv -a layout peek ... -topcell` is a valid command | STILL OPEN | no `calibredrv` output in the run-3 files (the top cell is proven by cal V3 instead) |
| cal V6 | DRC duration 10 to 15 minutes | VERIFIED (value corrected) | `drc/drc.log` `TOTAL CPU TIME = 76  REAL TIME = 77`: 77 s for the filled GDS, not 10 to 15 minutes |
| cal V7 | report wording `TOTAL Result Count` | VERIFIED | `drc/drc.log:25157` `TOTAL RESULTS GENERATED = 0 (0)`; `ant/unpu_top.ant.rpt:90` `RULECHECK AN.GC.1 ....... TOTAL Result Count = 0 (0)` |
| cal V8 | antenna runs as `calibre -drc -hier ant.ctrl` | VERIFIED | `ant/ant.log` ends with the summary (`SUMMARY REPORT FILE = unpu_top.ant.rpt`); 16 rules reported |
| cal V9 | `antenna_results.ant` is written by the antenna deck | VERIFIED | `ant/ant.log:2337` `RDB antenna_results.ant GC_STI GATE`; the file exists in `ant/` |
| cal V10 | `unpu_top.ant.db` has the `AN.` / `p <id> <n>` format `fix_antenna.tcl` parses | VERIFIED | `calibre/route1/ant/unpu_top.ant.db` has `AN.MTL.1.M2` and 10 lines `p ...`; `logs/fix_antenna.log` `Fixing AN.MTL.1.M3 (M3) #1 on net ...` parsed them. The final4 database has 0 `p` lines (0 results) |
| cal V11 | SETTLED: deck defines `4M1L`, `FILTER_DWN2PSUB` | VERIFIED | `lvs/lvs.ctrl:10` comment on `FILTER_DWN2PSUB`; LVS `CORRECT` |
| cal V12 | SETTLED: instance counts match | VERIFIED | `lvs/unpu_top.lvs.rpt` (44,560 nets both sides per the sign-off notes; `CORRECT` at line 31) |
| cal V13 | SETTLED: `v2lvs -v -s -s0 -s1 -o` works | VERIFIED | `lvs/v2lvs.log:20` command line, `Info: Design Conversion completed` |
| cal V14 | SETTLED: `calibre -lvs -hier lvs.ctrl` | VERIFIED | `lvs/lvs.log` `GRAND TOTAL ... LVS COMPARE TOTAL CPU TIME = 27 REAL TIME = 29` |
| cal V15 | SETTLED: report structure | VERIFIED | `lvs/unpu_top.lvs.rpt:31,45` |
| cal V16 | SETTLED: filler diode `D(DWN2PSUB)` handled | VERIFIED | `lvs/lvs.ctrl:10`; `CORRECT` |
| cal V17 | the CDL file exists at the assembled path | VERIFIED | `lvs/v2lvs.log:20` `-s /storage/PDK_iitg/.../cdl/scl18fs120_supply_pins.cdl` and the conversion completed |
| cal V18 | Calibre resolves the relative `LAYOUT PATH` | VERIFIED | `drc/drc.ctrl:117` `LAYOUT PATH "../../../outputs/unpu_top_routed.gds"`; `calibre/route1/drc/drc.log:117` `../../../outputs_route/unpu_top_routed.gds` (the checkpoint folder, so the right clone and the right export were read) |

## PrimeTime README (pt V1-V31)

(`pt/` = final SI-off run, `pt_si/`, `pt_legacy/` as copied; probe logs: `pt_route3/pt_eco_probe.log` hold probe, `pt_run3_final/pt_eco_drc_probe.log`, `pt_si_before_si/pt_eco_*_probe*.log`.)

| ID | Item | Status | Evidence |
|---|---|---|---|
| pt V1 | `pt_shell` T-2022.03-SP2 | VERIFIED | `pt/pt_setup_ss.log:28` `Version T-2022.03-SP2 for linux64 - Jun 01, 2022` |
| pt V2 | netlist links with `link_design unpu_top` | VERIFIED | `pt/pt_setup_ss.log:162` `linked unpu_top: 14674 leaf cells, 75 hierarchical cells, ... 0` |
| pt V3 | `link_path` with `search_path` | VERIFIED | `pt/pt_setup_ss.log:149` `link_path: * tsl18fs120_scl_ss.db` |
| pt V4 | wording of `spef_scenario` | VERIFIED | `pt/pt_setup_ss.log:125,134` `content of ...spef_scenario:` then `SPEF for corner ss decided from the text: ...TYPICAL_RC_125.spef` |
| pt V5 | `read_parasitics -format spef` (`-keep_capacitive_coupling` with SI) | VERIFIED | `pt/pt_setup_ss.log:165` `reading parasitics`; SI: `pt_si_before_si/pt_setup_ss.log` (annotation 3,477 RC + 13,094 coupled nets) |
| pt V6 | `report_annotated_parasitics` table wording | VERIFIED | `pt/pt_setup_ss.log:215` `ANNOTATION: read_parasitics errors '0'`; the verbatim table is `pnr_v2/testdata/annotation_si_{off,on}.txt` (two-line header, extra `Coupled network` column with SI on) |
| pt V7 | clock attributes `period`, `setup_uncertainty`, `hold_uncertainty` | VERIFIED | `pt/pt_setup_ss.log:226` `DESIGN values ... period '20.000000', setup_uncertainty '1.500000', hold_uncertainty '0.500000'` |
| pt V8 | `report_design` prints `Operating Conditions: ... Library:` | STILL OPEN (wording is different) | `pt/pt_setup_ss.log:284,285` `NOTE: report_design printed no 'Operating Conditions: ... Library: ...' line`; the fallback (only one library is linked) is used and printed |
| pt V9 | `check_timing` warning wording | VERIFIED | `pt/pt_setup_ss.log:321` `check_timing: checks run: no_input_delay no_driving_cell unconstrained_endpoints ...` |
| pt V10 | `report_clock -skew`, `report_clock_timing` | VERIFIED | `pt/pt_setup_ss_clock.rpt:2` `Report : clock` |
| pt V11 | `report_global_timing` exists | VERIFIED | `pt/pt_setup_ss_global_timing.rpt:2` `Report : global_timing` |
| pt V12 | `report_constraint -all_violators -max_delay` / `-min_delay` and `(VIOLATED)` | VERIFIED | `pt_si_before_si/pt_setup_ss.log:543` `report_constraint text: 4 lines marked VIOLATED, worst -0.04` against 4 violating endpoints (the `NOTE: the endpoint count ... differs` line never appears as output); `pt/pt_setup_ss_violators.rpt` |
| pt V13 | `get_path_groups`, `report_timing -group` | VERIFIED | `pt/pt_setup_ss.log:514` `path groups: **async_default** **clock_gating_default** **default** clk`; files `pt/pt_setup_ss_paths_group_clk.rpt`, `..._group___default__.rpt`, `..._async_default__.rpt`, `..._clock_gating_default__.rpt` |
| pt V14 | `get_timing_paths -delay_type -slack_lesser_than -max_paths`, attributes `slack`, `endpoint`, `startpoint` | VERIFIED | `pt/pt_setup_ss.log:602` `SETUP corner ss: WNS +0.1057 ns, TNS +0.0000 ns, violating endpoints 0, SI OFF`; `pt_si_before_si/pt_hold_ff_violated_prdata_9_.rpt` |
| pt V15 | `report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width` in one call | VERIFIED | `pt_run3_final/pt_setup_ss_design_rules.rpt` (510 max_transition entries); `pt/pt_setup_ss_design_rules.rpt:2` |
| pt V16 | `get_license PrimeTime-SI` | VERIFIED | `pt_si_before_si/pt_setup_ss.log:153` `SI/crosstalk analysis ON (licence acquired)` |
| pt V17 | `get_cells -hierarchical -filter "is_hierarchical == false"`, `get_lib_cells -filter is_black_box` | VERIFIED | `pt/pt_setup_ss.log:162` leaf cells 14674, black boxes 0 |
| pt V18 | per-endpoint `report_timing -from -to` finds objects by name | VERIFIED | `pt_si_before_si/pt_hold_ff_violated_prdata_9_.rpt` |
| pt V19 | `parasitics_log_file`: `printvar`, `set_app_var ... ""` puts the text into the session | VERIFIED | `pt/pt_setup_ss.log:163` `parasitics_log_file before: ... "parasitics_command.log"`; `:214` `annotation table read from the session text of report_annotated_parasitics` |
| pt V20 | `report_timing -path_type full_clock_expanded` prints `clock network delay (propagated)` | VERIFIED | `pt/pt_setup_ss.log:354` `clock tag: clock network delay (propagated) 0.84 0.84` |
| pt V21 | `get_attribute [get_clocks clk] sources` | VERIFIED | the `NOTE: the clock source port could not be read` line does NOT appear in `pt/pt_setup_ss.log` (0 matches), so the attribute was read |
| pt V22 | `get_timing_paths ... -nworst 1` per violated endpoint and the path/point attributes | VERIFIED | `pt/pt_setup_ss_violations.csv` header `endpoint;startpoint;startpoint_kind;endpoint_kind;slack_ns;path_group;n_cells;cells;incr_ns`; `pt_si_before_si/pt_setup_ss_violations.csv` rows for the 4 endpoints. (`pt_setup_ss.log` shows only the source line of a `could not be written` message, not an output) |
| pt V23 | `info commands` lists `fix_eco_timing`, `set_eco_options`, `write_changes` | VERIFIED | `pt_route3/pt_eco_probe.log` `>>> 078 existing: fix_eco_timing fix_eco_drc fix_eco_power set_eco_options write_changes` (`fix_eco_hold` does NOT exist; `fix_eco_timing` is used) |
| pt V24 | `list_licenses`, `get_license PrimeTime-ECO` | VERIFIED | `pt_route3/pt_eco_probe.log` `get_license PrimeTime-ECO: ok (0)`; the message `Error: Unrecognized feature name 'PrimeTime-ECO'. (PT-002)` also appears but the ECO command ran |
| pt V25 | `get_lib_cells`, `is_buffer`, `area`, lib pin and arc attributes | VERIFIED (partly) | `pt_route3/pt_eco_probe.log` candidate table: `is_buffer=''` (the attribute prints empty), `area 40.77`, delay `n/a`: the name pattern fallback was used (buffer list 13 cells). Lib pin `function` and arc delays are NOT readable: `function-buffer=n/a`, `delay n/a` |
| pt V26 | `set_eco_options -log_file`; `fix_eco_timing -type hold -methods {insert_buffer} -buffer_list -hold_margin` without `-to/-from` | VERIFIED | `pt_route3/pt_eco_probe.log:1174` `bare_names form: commands proposed '9'`; the collection form `:1102` gave `PTECO-017 ... buffer list is empty` (so the bare-name list is the form that works) |
| pt V27 | `write_changes -format icctcl / icc2tcl / text` | VERIFIED | `pt_route3/pt_eco_probe.log` `write_changes -format icctcl -> .../pt_route3/pt_eco_hold_changes.tcl`; the files exist (`pt_route3/pt_eco_hold_changes{,_icc2}.tcl`, `.txt`) |
| pt V28 | `timing_save_pin_arrival_and_slack`, `help -verbose fix_eco_timing`, `-buffer_list` collection, physical options | VERIFIED (partly) | `timing_save_pin_arrival_and_slack set to true` and `the ECO is LOGICAL only` in `pt_route3/pt_eco_probe.log`. The collection form is REJECTED by this release (`PTECO-017`); the physical options (`PT_ECO_PHYSICAL 1`) were never used in run 3: STILL OPEN for those |
| pt V29 | `Number of insert_buffer commands`, area, cell table; `fix_eco_timing -type setup -methods {size_cell}`; `size_cell` line syntax | VERIFIED | `pt_route3/pt_eco_probe.log` `Number of insert_buffer commands 9`; `pt_si_before_si/pt_eco_setup_probe.log` `trying (size_cell, -setup_margin 0.02)`; `pt_run3_final/pt_eco_drc_changes_icc2.tcl` (9 `size_cell`, 0 `insert_buffer`) |
| pt V30 | `all_connected -leaf`, `is_sequential`, `get_nets -of_objects <port>`, `all_fanout/all_fanin` | VERIFIED (partly) | `pt_route3/pt_eco_probe.log` `in2out cone: methods with a result: c c2 a3; ... FINAL cone = union = 109 cells`; `(sequential: 1)` in the class lines. `get_nets -of_objects <port>` for the geometry report: see main V83 (STILL OPEN) |
| pt V31 | (ICC2 apply) `get_path_groups`, `get_timing_paths -groups`, group `**in2out_default**` | VERIFIED | `pt_eco_apply_si_hold_console.log:7689-7692` `GATE ok: the in2out group: before +0.0373 ns, after +0.0394 ns` and `GATE hold ok: ... before -0.0025 ns, after -0.0012 ns` |

## Simulation README (sim V1-V16)

(`sim/` = the four approved reruns of 2026-11-11 04:22 to 04:43.)

| ID | Item | Status | Evidence |
|---|---|---|---|
| sim V1 | SDF command file statement accepted | VERIFIED | `sim/pl_ss_nochecks.log:27` `Annotating SDF timing data:`; `sim/pl_ss_nochecks.sdfcmd` |
| sim V2 | `-sdf_cmd_file`, `-sdf_verbose` are the right options | VERIFIED | `sim/pl_ss_nochecks.log:11` `-sdf_cmd_file pnr_icc2/sim/pl_ss_nochecks.sdfcmd`; annotation log written (`pl_ss_nochecks_annotate.log`) |
| sim V3 | `-notimingchecks` does not switch off the SDF delays | VERIFIED | `sim/pl_ss_nochecks.log:536,539` `Annotation completed with 0 Errors and 22534 Warnings` together with `No. of Disabled Tchecks = 25065`; end time differs from the zero-delay run (278,003,892 ns vs 276,701,592 ns) |
| sim V4 | scope `unpu_top_tb.dut` matches the SDF | VERIFIED | `sim/pl_ss_nochecks.log:30` `Backannotation scope: unpu_top_tb.dut`; 0 `not found` lines |
| sim V5 | wording and place of the annotation message | VERIFIED | `sim/pl_ss_nochecks.log:27,536-539` (the statistics block is in the main log, not only in the annotation log) |
| sim V6 | the not-found class of SDF warnings | VERIFIED | the ids actually printed are `SDFNEP`, `SDFNCAP`, `SDFNL1`, `SDFNET`; no not-found class occurred (`sim/pl_ss_checks.log` id count) |
| sim V7 | wording of a timing-check violation | STILL OPEN | no violation occurred in any run: 0 matches of `Timing violation` or `TCHKVIO` in `sim/pl_ss_checks.log`, `sim/pl_ff_checks.log`. The tests use an invented message (see sim V13) |
| sim V8 | end-time line | VERIFIED | `sim/pl_ss_nochecks.log:1242` `Simulation complete via $finish(1) at time 278003892 NS + 0` |
| sim V9 | min:typ:max triples differ | VERIFIED | `sim/runA_console.txt:17` `triples sampled: 8896, with min != max: 297` |
| sim V10 | SDF header (TIMESCALE, DIVIDER, VOLTAGE, TEMPERATURE) matches the corner | VERIFIED (partly) | `sim/runA_console.txt` prints `(DIVIDER /)`, `(TIMESCALE 1ns)`, `(DESIGN "unpu_top")`; the SDF header written by this ICC2 has NO VOLTAGE / TEMPERATURE lines, so that part cannot be checked |
| sim V11 | `-xmlibdirname xrun_out/...` | VERIFIED | `sim/pl_ss_nochecks.history:1` and `sim/runA_console.txt:26` |
| sim V12 | netlist compiles with the combined model (benign messages) | VERIFIED | `sim/pl_ss_nochecks.log:1204` `*W,UDPRDT ... UDP table entry is redundant`; ids in the log: `DSEM2009 1, DSEMEL 1, MXWARN 1, SDFNCAP 220, SDFNEP 500, UDPRDT 1`; no `CUVWSP` any more |
| sim V13 | text of a REAL violation | STILL OPEN | none seen (see sim V7). Detector accepts two forms; test sample is invented |
| sim V14 | an option that raises the message cap | STILL OPEN (not needed) | the cap (500 per id) was handled by the SDF-based reconciliation (difference 0 in all four runs); the option was not looked up |
| sim V15 | `-define neg_tchk` with `-neg_tchk` removes `nl1_neg` / `net_remrec` | STILL OPEN | experiment not run (`pnr_v2/sim/run_experiments.sh negtchk` prepared) |
| sim V16 | `===` -> `==` in a COPY of the SDF makes the COND entries annotate | STILL OPEN | experiment not run (`run_experiments.sh eqeq` prepared) |

## Main README (main V19-V89)

| ID | Item | Status | Evidence |
|---|---|---|---|
| main V19 | `[info script]` inside `icc2_shell -f` | VERIFIED | `logs/1_design_setup.log:1` `>>> RUN ROOT: .../unpu_run3` (printed from the script's own location) |
| main V20 | `open_lib -read` / `open_block -read` on a copied library (diag_io_latency) | STILL OPEN | `diag_io_latency.tcl` was not run in run 3 (`R3/diag/` has only SDC files from tasks 088/090) |
| main V21 | `get_blocks -all` and name forms | STILL OPEN | same: diagnostic not run in run 3 |
| main V22 | `redirect -variable` captures report text | VERIFIED (indirect) | used in every step; e.g. `logs/6g_pt_eco_apply.log` GATE metrics are read from captured report text |
| main V23 | `report_timing -path_type full_clock_expanded -input_pins -nets` parser form | STILL OPEN | diagnostic not run in run 3 |
| main V24 | `report_clocks`, `report_clock_tree_options`, `is_propagated` | STILL OPEN | diagnostic not run in run 3 |
| main V25 | `write_sdc -scenario <s> -output <file>` on a block | VERIFIED | `logs/7_pv.log` writes `unpu_top_pnr_{ss,ff}.sdc`; `R3/diag/clock_latency_func_ss.sdc` |
| main V26 | `get_cells -hierarchical -filter "is_hierarchical == false"`, `bbox` / `orientation` | VERIFIED | `logs/4c_port_buffers_early.log` `085 rows 151, cell boxes read 12039` |
| main V27 | `get_site_rows` boxes equal the cell row `y0` | VERIFIED (indirect) | `4c_port_buffers_early.log` completed (a stray cell would stop it); `rows 151` |
| main V28 | `all_fanout -flat -endpoints_only -from <port>` (cone cross-check) | VERIFIED (indirect) | `4c_port_buffers_early.log` `CONE-SKIPPED ... the net is on an input-to-output cone` decisions for `paddr[3]`, `[5]`, `[7]`, `[9]`, `[11]` |
| main V29 | `set_dont_touch` and `physical_status fixed` read back | VERIFIED | `4c_port_buffers_early.log:2655` `PROTECTION: 54 cells have dont_touch true and physical_status fixed (read back)` |
| main V30b | `get_timing_paths -from <ports> -to [all_outputs] -slack_lesser_than 0` | VERIFIED | `4c_port_buffers_early.log:1514,2971` `in2out WNS (func_ss) 0.020578 ... 0.020537` before/after |
| main V31b | `insert_buffer` on a port, `remove_buffers` | VERIFIED (partly) | `4c_port_buffers_early.log` `STAGE 4c COMPLETE: 54 input-port nets buffered`. `remove_buffers` (undo of a rejected candidate) never ran in run 3: STILL OPEN for it |
| main V32 | clock attribute `sources` | VERIFIED | `4c_port_buffers_early.log:59` `clock ports (not buffered): clk` |
| main V33-V40 | task 086 what-if script (`remove_clock_latency` forms, `report_port -verbose`, `report_app_options`, block names ...) | NOT APPLICABLE | `diag_io_whatif.tcl` is a read-only diagnostic of 2026-11-10 morning, not part of the run-3 chain; no log. (`remove_clock_latency` itself is verified under main V44) |
| main V41 | `write_sdc -include clock_latency` counts the lines | VERIFIED | `logs/5_cts.log:9-11` `088 cts-input func_ff: set_clock_latency lines before 0, after 0`; `:9074` `before 1, after 0` |
| main V42 | `current_scenario` without argument | VERIFIED (indirect) | the 088 procs restore the scenario; every `088` line of every step ran without an error |
| main V43 | `clock_opt` in three calls | VERIFIED | `logs/5_cts.log:9074-9078` `cts-after-build_clock ... removing the tool-made line`; `:9770` `cts-after-route_clock` (CTS_SPLIT 1) |
| main V44 | `remove_clock_latency [get_clocks ...]` | VERIFIED | `logs/5_cts.log:9074,9076` removed `set_clock_latency 0.379734` (ff) and `0.806847` (ss); `:9078` `2 set_clock_latency line(s) removed, none left` |
| main V45 | all scenarios switchable | VERIFIED | every `088` block lists `func_ff` and `func_ss` |
| main V46 | 4th bootstrap line accepted by `icc2_shell -f` | VERIFIED (indirect) | all steps start with `>>> RUN ROOT` |
| main V47 | probes and removals in `powerplanning.tcl` / `placement.tcl` run in the same scenarios as the later steps | VERIFIED | `logs/3_powerplanning.log:9-10,235-236,286-287` `088 powerplan-probe-... func_ff / func_ss: set_clock_latency lines before 0, after 0` (both scenarios switched, no ERROR 088); `logs/4_placement.log` likewise |
| main V48 | `all_registers -edge_triggered -clock_pins` | VERIFIED | `logs/5_cts.log:323` `cts scope flops: 2465 clock pins of 2465 edge-triggered registers (all_registers -edge_triggered -clock_pins)` |
| main V49 | `set_clock_uncertainty` on pins takes effect | VERIFIED | `logs/5_cts.log:512,698` `probe in2reg-setup: ... change -0.0500 ns (expected -0.05): the value acts`; `in2reg-hold ... -0.1000` |
| main V50 | `remove_clock_uncertainty` removes the pin-level value | VERIFIED | `logs/5_cts.log:13479-13481` `RESTORE PROOF ... pin/port-level uncertainty lines left 0` |
| main V51 | `write_sdc -include clock_uncertainty` shows pin-level lines | VERIFIED | `logs/5_cts.log:699-700` `cts SDC check func_ss (setup, scope flops): ok; pin/port names carrying the value: 2465` |
| main V52 | `get_ports/get_pins -quiet -exact` with brackets | VERIFIED (indirect) | `5_cts.log:699-700` 2465 objects set and found; ports in `4c_port_buffers_early.log` (`paddr[3]` ...) |
| main V53 | `all_outputs` as the object list of `set_clock_uncertainty` | STILL OPEN | run 3 used the default scope `flops` only (`logs/6_route.log:236,368` `scope flops`); the `outputs` / `all` scopes did not run, so `all_outputs` was not exercised |
| main V54 | pre-CTS in2out numbers comparable to post-CTS | STILL OPEN (observed to differ) | `logs/5_cts.log:322,13611-13614` in2out setup WNS 0.020537 -> 0.010302, hold 0.089552 -> 0.032668, with `WARNING: the margin made the in2out group worse`; the cause (margin or CTS) is not separated by the logs |
| main V55 | `save_block -force -as` then `open_block` leaves the copy current, source unmodified | VERIFIED | `logs/7_pv_route.log:17` `checkpoint: working on the copy unpu_top_pv_route of unpu_top_route; unpu_top_route itself is not modified`; `:11` `Saving ... to ...unpu_top_pv_route.design` |
| main V56 | LEF macro rename for `unpu_top_pv_route` | VERIFIED | `logs/7_pv_route.log:8038` `073 LEF macro is already called unpu_top, no rename`; `:8041` `LEF CHECK PASSED: one MACRO unpu_top with 206 PIN entries` |
| main V57 | Verilog module of the checkpoint netlist is `unpu_top`, GDS top cell too | VERIFIED | `logs/7_pv_route.log:8199` `netlist ...: 76 module(s) ...; module unpu_top present`; Calibre route1 DRC ran with `LAYOUT PRIMARY unpu_top` |
| main V58 | Calibre resolves the relative `LAYOUT PATH` from `route1/drc` | VERIFIED | `calibre/route1/drc/drc.log:117` `LAYOUT PATH "../../../outputs_route/unpu_top_routed.gds"` |
| main V59 | `route_global -congestion_map_only`, `check_lvs` on the route block | VERIFIED | `reports_route/` has `congestion.rpt`, `unpu_top_check_lvs.rpt`, `unpu_top_check_legality.rpt` ... |
| main V60 | `UNPU_ECO_SCOPE reg2out`: released nets above 0 | VERIFIED | `pt_route3/pt_eco_probe.log:1065` `reg2out: cone nets kept protected ... 195; released ... 109`; `:726` `scope reg2out: 7 of 7 hold violators are targets` |
| main V61 | `direction` and `is_sequential` read for the flops | VERIFIED | `pt_route3/pt_eco_probe.log:1228` `original driver u_csr/src_b_reg_reg_23_/QN (sequential: 1)`; class file `pt_route3/pt_eco_hold_pin_classes.txt` all `load_flop` |
| main V62 | `fix_eco_timing` accepts the form without `-from/-to` | VERIFIED | `pt_route3/pt_eco_probe.log:1174` `bare_names form: commands proposed '9', PTECO-099 warnings 0` |
| main V63 | `earlybuf_*` snapshots equal after the apply | VERIFIED | `pt_eco_apply_console.log:8887` `CHECK protected cells (56): reference, origin and orientation identical; every pin on the same net except the [llength $ea_exp] expected move(s) listed above` (note: that line prints the literal text `[llength $ea_exp]`, an unexpanded variable in the message; the check itself passed) |
| main V64 | `get_nets -of_objects <pin>` name equals the cone traversal's | VERIFIED | `pt_route3/pt_eco_probe.log:1228-1236` all 9 insertions `net state released` (a mismatch would give `none` / `unknown`) |
| main V65 | `pt_cone_net_pins <net> out` lists the flop `QN` pin | VERIFIED | `:1228` `original driver u_csr/src_b_reg_reg_23_/QN` |
| main V66 | `is_sequential` of the flop is true | VERIFIED | `:1228` `(sequential: 1)` |
| main V67 | `get_pins -quiet -exact <full pin>` finds the change-file pins | VERIFIED | `:1228-1236` 9 of 9 insertions classified with pin and cell found |
| main V68 | `get_pins -of_objects <new buffer> -filter "direction == in"` gives the original net | VERIFIED | `:1228` `after the ECO the pin sees net u_csr/net_PTECO_HOLD_NET1 driven by ...` with `original net u_csr/n52` (all 9 classified `load_flop`) |
| main V69 | `fix_eco_drc` exists and accepts `-type max_transition -methods {size_cell insert_buffer} -buffer_list` | VERIFIED | `pt_run3_final/pt_eco_drc_probe.log:845` `trying (size_cell + insert_buffer, -buffer_list a collection of library cells)`; `:979` `PROBE RESULT: ECO RAN: 9 changes proposed` |
| main V70 | licence for `fix_eco_drc` | VERIFIED | `pt_eco_drc_probe.log:741` `get_license PrimeTime-ECO: ok (0)` and the command ran |
| main V71 | `report_constraint ... -max_transition -max_capacitance -min_pulse_width` headings; parser | VERIFIED | `pt_eco_drc_probe.log:634` DESIGN RULES block; the parser reproduced 510 = 424 + 86 on `pt_run3_final/pt_setup_ss_design_rules.rpt` (test fixture `testdata/095_run3_ss_design_rules.rpt`) |
| main V72 | `is_clock_network` and the protection read-back | VERIFIED | `pt_eco_drc_probe.log:844` `clock network protected: 63 clock cells (63 switched on, ...), 215 clock nets; read back of the first cell: dont_touch = true` |
| main V73 | `get_nets -of_objects <port>`, `all_connected` for the net table | VERIFIED (partly) | `pt_eco_drc_probe.log:643` `the 86 entries sit on 9 NETS (0 entries with unreadable facts)`. The port-to-net relation used by the geometry report in the apply is the open item main V83 |
| main V74 | buffer names `U_PTECO_*` of `fix_eco_drc` | NOT APPLICABLE | the 9 changes were all `size_cell` (`pt_run3_final/pt_eco_drc_changes_icc2.tcl`: 9 `size_cell`, 0 `insert_buffer`), no new cell was named |
| main V75 | hold WNS of ICC2 before/after in the apply log | VERIFIED | `pt_eco_apply_drc_console.log:8206` `GATE hold ok: ... before -0.0028 ns, after -0.0025 ns, change +0.0003 ns` |
| main V76 | PrimeTime-SI licence and `si_enable_analysis` accepted | VERIFIED | `pt_si_before_si/pt_setup_ss.log:153` `SI/crosstalk analysis ON (licence acquired)` and the SI run (setup -0.0364, 4 endpoints) |
| main V77 | the removal command and its form (`remove_max_transition`) | VERIFIED | `logs/7_pv.log:8198-8211` forms 1 (`-clock_path %C`) and 2 (`%C -clock_path`) `that form failed:` (empty message), form 3 `remove_max_transition %C` worked: `clock-path max_transition lines before 1, after 0` |
| main V78 | `write_sdc -scenario <s> -output <tmp>` works as a read-back | VERIFIED | `logs/7_pv.log:8198` counts read from the temporary SDC; `:8242` `CHECK exported SDCs: no clock-path max_transition line ...` |
| main V79 | PrimeTime `read_sdc` accepts the legacy SDC as it is | VERIFIED | `pt_legacy/pt_setup_ss.log:604` `SDC: legacy (.../constraints/legacy/unpu_top_legacy.sdc)` and `SETUP corner ss: WNS +0.1057 ... violating endpoints 0`. Messages seen, not errors: `Warning: Setting input delay on clock port (clk) ... Command is ignored. (UITE-489)` (`:221`) and `Error: Library Compiler executable path is not set. (PT-063)` (`:18`, present in every PT log of run 3, does not stop the run) |
| main V80 | clock proof and check_timing pass with the legacy SDC | VERIFIED | `pt_legacy/pt_setup_ss.log:230,354` `APPLIED: set_propagated_clock [all_clocks]` and `clock tag: clock network delay (propagated) 0.84` |
| main V81 | `size_cell` on a cell that overlaps its neighbours before `set_cell_location` | VERIFIED | `pt_eco_apply_drc_console.log:4307` `SIZE change 1: cell u_dma/U157 an02d4 -> an02d7, relocated by 1.68 um to (594.560, 854.400)` and the other relocations (changes 4, 6, 7, 8), all accepted by the read-back |
| main V82 | `set_cell_location -coordinates -orientation` plus read-back | VERIFIED | same lines; `STAGE 6g COMPLETE: 0 cells inserted, 9 cells resized` |
| main V83 | `get_ports -of_objects <net>` for the driver-to-port distance | STILL OPEN | `pt_eco_apply_drc_console.log:4308,4455,4597,4744,4753,4758,4899` every `dma_wdata` driver prints `driver-to-port distance n/a -> n/a um`: the distance could not be read, so the port-growth WARNING never had a value to test (the relocated U101 moved by 10.64 um). The centroid distances of the two 40-load nets were read (`:4601` 94.7 -> 95.8 um, `:4748` 71.7 -> 72.2 um). The gates (setup, in2out, hold, DRC, legality, open nets) passed |
| main V84 | a filler's orientation equals the cell orientation in that row | VERIFIED (indirect) | the relocation read-back compares `orientation` with the row orientation taken from the fillers; all 5 relocations passed |
| main V85 | `si_enable_analysis false/true` + `update_timing -full` in an SI-on session | VERIFIED | `pt_si_before_si/pt_eco_setup_probe.log:597,620,831,854` `BEFORE, SI ON view: ... -0.0364`; `BEFORE, SI OFF view (same session ...): ... +0.1041`; `AFTER, SI ON ... +0.0034`; `AFTER, SI OFF ... +0.1041` |
| main V86 | `fix_eco_timing -type setup -methods {size_cell} -setup_margin` accepted | VERIFIED | `pt_si_before_si/pt_eco_setup_probe.log:765` `trying (size_cell, -setup_margin 0.02)`; no `that form failed` follows; `:859` `PROBE RESULT (SI ON): ECO RAN: 1 size_cell changes proposed` |
| main V87 | same-family references from PrimeTime (speed relation by name) | VERIFIED | `pt_eco_apply_si_setup_console.log:3559` `change 1: size_cell u_apb/U29 -> buffd3: class cone_faster` (buffd1 -> buffd3) |
| main V88 | protected cells found in the probe session | VERIFIED (partly) | `pt_si_before_si/pt_eco_setup_probe.log:764` `protected during the ECO (buffers and cells of earlier rounds): 64 cells dont_touch`. In the SI-round APPLY the earlier resized drivers of 095 were NOT protected by name: `pt_eco_apply_si_*_console.log` `098 no earlier max-transition change file .../pt/pt_eco_drc_changes_icc2.tcl: the resized drivers of task 095 are not protected by name` (the user had moved `pt/` aside); the end check of the other protected cells held |
| main V89 | the SI-on hold probe finds `prdata[9]` as a reg2out target | VERIFIED | `pt_si_before_si/pt_eco_probe_hold.log:741` `scope reg2out: 1 of 1 hold violators are targets of this scope (0 other)` |

---

## Summary and what the open items mean

Counts by status (computed from the tables above): VERIFIED 105, VERIFIED (indirect) 8, STILL OPEN 14, NOT APPLICABLE 9; total 136.

STILL OPEN, grouped by reason:
- **Diagnostics that were not run in run 3** (no log, not in the chain): main V20, V21, V23, V24; cal V5.
- **Scopes not exercised**: main V53 (`all_outputs`; only the default scope `flops` ran).
- **Never exercised by the final run**: main V31b (`remove_buffers` undo; the other half of V31b is verified), pt V28 (the physical-ECO options; the rest of V28 is verified), pt V25 (lib pin function and arc delays; the rest is verified); sim V7 / V13 (a REAL violation message did not occur, which is the good outcome), sim V14 (cap option, replaced by the reconciliation), sim V15 / V16 (the two optional experiments).
- **Looked at and found different or unreadable**: pt V8 (`report_design` has no `Operating Conditions` line; a fallback is used), main V54 (in2out numbers before and after CTS differ), main V83 (**the driver-to-port distance of the relocated `dma_wdata` drivers was unreadable (`n/a`)**: the WARNING for port growth had nothing to test; the gates passed, the final PrimeTime/Calibre results are the proof).
- **A fix to remember**: main V88 (the earlier resized drivers were not protected by name in the SI round because `pt/` had been moved; the apply prints this and continues). If this matters in a fresh run, the apply should read the 095 change file from a path that survives the `mv` steps.

Notes on the evidence:
- Values corrected by run 3: cal V6 (DRC takes 77 s, not 10 to 15 minutes), pt V26 (the collection form of `-buffer_list` is rejected with PTECO-017, the bare-name list works), pt V24 (the licence name `PrimeTime-ECO` prints PT-002 but the ECO runs).
- A cosmetic defect in a log message, not a failure: `pt_eco_apply_console.log:8887` prints the unexpanded text `[llength $ea_exp]` inside the `CHECK protected cells` line.
- The PrimeTime crash trace: `pt_run3_final/Synopsys_stack_trace_93929.txt` (2026-11-10 22:38) was written when the max-transition probe session closed, after `PROBE RESULT: ECO RAN` (`pt_eco_drc_probe.log:979`) and `Thank you for using pt_shell!` (`:1139`); the probe's results are complete. Cause not investigated.
