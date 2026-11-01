# RUNBOOK — the ICC2 flow, step by step (for the user at the server)

Source of every number: the scripts, the reports of tasks 038 to 049, `pnr/VERIFY_STATUS.md` and the handoff (18.x). A number marked
**(stub)** is what the stub run of the script printed, not a server value; **(guess)** is a guess. Nothing here has run on the server except
steps 0 to 2 (see `VERIFY_STATUS.md`); everything from step 3 on is "expected", and the first run of each script may need a fix.

## Front part

**Shell and setup.** Your login shell is csh. Every command below is ONE line; paste it as it is. Once per session:

```
source ~/cad_cshrc
source ~/synopsys_cshrc
```

Do not use `$FOUNDRY` (handoff 18.4). Run Calibre in a separate terminal later (different licence server).

**Variables, set once per session** (csh syntax):

```
setenv UNPU_REPO <your clone of the repo>
setenv UNPU_WORK /storage/EE5239G1/aagams_workspace/icc2_work_v2
setenv UNPU_RUN_TAG run1
```

`UNPU_REPO` is only a convention for the commands below: the scripts find the repo from their own location. `UNPU_WORK` and
`UNPU_RUN_TAG` default to the values above (`pnr/params.tcl`); set them only to change them. Other variables are named in the step that uses them
and in the table of `pnr/README.md`.

**The two shells.** `icc2_shell` (on the path after `synopsys_cshrc`) for every step except step 1; `icc2_lm_shell` ONLY by its full path
`/home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell` (the bare name finds Fusion Compiler V-2023.12-SP4, handoff 18.10). Both scripts check the release.

**Work directory** (all derived in `params.tcl`):

```
$UNPU_WORK/ndm/                      NDMs (scl18fs120.ndm, scl18fs120_fillf.ndm), feedth.lef, ndm_manifest.txt   (shared by all runs)
$UNPU_WORK/$UNPU_RUN_TAG/logs/       stage logs and manifest_<stage>.txt
$UNPU_WORK/$UNPU_RUN_TAG/rpt/        reports (rpt/help/ and rpt/help_lm/ for the probes)
$UNPU_WORK/$UNPU_RUN_TAG/lib/        the design library unpu2_lib
$UNPU_WORK/$UNPU_RUN_TAG/out/        netlists, LEF, SPEF, SDF, SDC, GDS
$UNPU_WORK/$UNPU_RUN_TAG/calibre/    Calibre runs (not scripted yet)
```

**Before the first run of a tag**, create the log directory (the log file is opened before the script can create it):

```
mkdir -p $UNPU_WORK/$UNPU_RUN_TAG/logs $UNPU_WORK/ndm
```

**The pattern of every step.** Each script prints `Info: [unpu] CHECK <stage> <name> PASS|FAIL ...` and `RESULT <stage> <key> = <value>` lines. At the end it prints
`checks_total` and `checks_failed`; if any check failed it prints `Error: [unpu] ...` and exits non-zero. Look at the log with:

```
grep -E "CHECK|RESULT|Warning: \[unpu\]|Error" $UNPU_WORK/$UNPU_RUN_TAG/logs/<stage>.log
```

**The block chain** (each stage opens one block and saves the next; the earlier block on disk is never touched):
`unpu_top` (design_setup) → `fp` (floorplan) → `pwr` (power) → `pins` (pin_place) → `placed` (placement) → `cts`, `clkopt` (cts) → `routeauto`, `routed` (route) → `final` (fill) → outputs (no block).

**The rerun rule (all steps).** A failed run saves nothing after its last checkpoint; run it again as it is (after fixing the cause). A checkpoint name that already exists is never
reused and the script stops naming it. After a SUCCESSFUL run, to do it again use a new block name `setenv UNPU_BLK_<NAME> <new>` (NAME = IMPORT FP PWR PINS PLACED CTS CLKOPT ROUTE_AUTO ROUTED FINAL;
a Warning is printed for each override) or a new `UNPU_RUN_TAG` (which needs every step from 3 on again). There is no reliable remove-block command.

---

## 0. The probes (optional)

Print the usage of the commands the flow uses. Already run once (`rpt/help/summary.txt`: 140 of 141 found). Run again only to answer the questions listed in
`VERIFY_STATUS.md` (the probe list now also holds `get_app_option_value`, `report_constraint`, `report_pin_placement`, ...).

```
icc2_shell -file $UNPU_REPO/pnr/help_probe.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/help_probe.log
/home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell -file $UNPU_REPO/pnr/help_probe_lm.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/help_probe_lm.log
```

Needs/saves no block. Outputs: `rpt/help/`, `rpt/help_lm/` (`summary.txt`, `all_commands.txt`, one file per command). Takes about a minute.

## 1. `ndm_file_gen.tcl` — the reference libraries (icc2_lm_shell)

Mode `two` is the default (the main NDM with 534 cells, then a second NDM with the 3 fillers; mode `single` does not work on this kit: `LM-052`, 0 of 3 fillers). Needs no block; saves no block.

```
setenv UNPU_NDM_OVERWRITE 1
/home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell -file $UNPU_REPO/pnr/ndm_file_gen.tcl -output_log_file $UNPU_WORK/ndm/ndm_file_gen.log
```

(`UNPU_NDM_OVERWRITE 1` only when the NDM already exists — the first run of 2026-11-01 left `scl18fs120.ndm`; the script prints a Warning for every path it removes. Leave it unset otherwise.)

Good result: `Workspace check succeeded!` twice; `Skipped 6 physical designs (LM-052)` in the MAIN workspace (expected: the six LEF-only cells); `CHECK ndm_file_gen fillers_typed`: 3 of 3 typed filler;
`RESULT ndm_file_gen workspaces_committed = 2`; `ndm_manifest.txt` lists `scl18fs120.ndm` then `scl18fs120_fillf.ndm`. Run time: about 9 seconds in the first (single) run (`Elapsed time` at the end of `ndm_file_gen.log`).
Predicted failures: the second workspace form (`create_workspace -flow physical_only -technology ...`) has not run yet (VERIFY_STATUS K24); a wrong `icc2_lm_shell` (release check stops).
Rerun: as above; with `UNPU_NDM_OVERWRITE 1`.

## 2. `ndm_check.tcl` — check the NDMs (icc2_shell)

```
icc2_shell -file $UNPU_REPO/pnr/ndm_check.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/ndm_check.log
```

Needs/saves no block (it makes a scratch library `ndm_check_lib_<time>` that stays on disk; delete by hand later).
Good result (mode two): `opens_scl18fs120` and `opens_scl18fs120_fillf` PASS; `cells_total` 537 = 534 + 3; main NDM 534 cells and 0 fillers; fillers NDM exactly the 3; `fillers_typed_filler`, `fillers_not_dont_use`; the three
library cells `adiode bh01d1 cload1` are `dont_use` (count 3). 15 checks **(stub)**. `single_mode_worked = no` is expected in mode two.
Predicted failure: `create_lib -ref_libs` with a LIST of two paths has not run yet (K23).

## 3. `design_setup.tcl` — import, scenarios (icc2_shell)

Needs no block (creates the library `$UNPU_WORK/$UNPU_RUN_TAG/lib/unpu2_lib`; an existing library stops the script unless `setenv UNPU_LIB_OVERWRITE 1`). Saves `unpu_top`.

```
icc2_shell -file $UNPU_REPO/pnr/design_setup.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/design_setup.log
```

Good result: both reference libraries open (`reflib_open_*`); 204 ports, 2,465 sequential cells, 12,487 leaf cells; the netlist links; corner `default` = ss 1.62 V / 125 C, corner `ff` = ff 1.98 V / -40 C;
scenario `default` setup-only, `ff_hold` hold-only; `check_timing` shows only the `pready` constant warning; 11 checks **(stub)**. Informational first timing: about +0.82 ns setup, -0.50 ns hold (first run).
Predicted failures (output layouts never seen, VERIFY_STATUS K3, K4, K13, K14, K30): the `report_corners` parser, the `link_block` wording, the scenario status attribute, the timing-path attribute (a fallback to `report_timing` exists). Fix the parser, not the check.
Re-run: a failed run can be repeated after `UNPU_LIB_OVERWRITE 1`.

## 4. `floorplan.tcl` (icc2_shell)

Needs `unpu_top`; saves `fp`.

```
icc2_shell -file $UNPU_REPO/pnr/floorplan.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/floorplan.log
```

Good result: die 868.0 um square, core offset 5.6, 153 rows, core area 734,106.24 um2; site `unit` 0.56 x 5.6; dont_use: 15 cells matched by the patterns, 18 in total, the three library cells among them
(`set_attribute ... dont_use`, `ATTR-12` is expected); 8 checks **(stub)**. Experiment knob (not for the plan run): `setenv UNPU_DIE_SIZE 817.6` is the old run's die.
Predicted failures: the `report_design -floorplan` parser (K5) and the `boundary_bbox` / site attributes (K15, K16).

## 5. `power.tcl` (icc2_shell)

Needs `fp`; saves `pwr`.

```
icc2_shell -file $UNPU_REPO/pnr/power.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/power.log
```

Good result: nets `VDD`/`VSS` created and connected (`connected_*` = the leaf cell count 12,487); TOP_M stripes of 2.24 um at pitch 112 um, M1 rails (rows + 1 = 154); one terminal per stripe at the bottom edge (y from 0 to 6 um);
`check_pg_drc` 0; no floating wires/vias/terminals. Floating CELLS cannot be checked here (nothing is placed): that check is in step 7.
Predicted failures: the `connect_pg_net` summary layout (K6), `get_shapes` filters on rails (K18), terminal attributes (K19), the `check_pg_*` texts (K20). The script has fallbacks and says so in Warnings.

## 6. `pin_place.tcl` (icc2_shell)

Needs `pwr`; saves `pins`. Coarse placement, then the tool places the 204 signal pins: APB group on the right edge (M3), DMA group on the top edge (M2); no pin on the left or bottom.

```
icc2_shell -file $UNPU_REPO/pnr/pin_place.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/pin_place.log
```

Good result: all `CHECK pin_place` lines PASS (18 **(stub)**); `signal_terminals = 204`; `right_group_edges = right 102`, `top_group_edges = top 102`; smallest gap per edge >= 6.72 um; `pin_clk` and `pin_rst_n` printed
(tell the top level and the PM: question Q14); `rpt/pin_order.txt` is the report for the top-level team. Run time: a minute or two **(guess)**.
**Expected FIRST failure: the side numbers are a guess** (3 = right, 2 = top). The group checks FAIL with a DIAGNOSIS naming the edge each group landed on, for example "...The groups are swapped: set UNPU_PIN_SIDE_RIGHT=2 and
UNPU_PIN_SIDE_TOP=3 and run again". Then:

```
setenv UNPU_PIN_SIDE_RIGHT 2
setenv UNPU_PIN_SIDE_TOP 3
icc2_shell -file $UNPU_REPO/pnr/pin_place.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/pin_place.log
```

(use the numbers the DIAGNOSIS prints; a failed run saved nothing, so no new block name is needed). If the DIAGNOSIS says the numbers are unknown, try the numbers 1 to 4 not yet explained.
Other predicted failures: the unplaced-cell attribute (`physical_status`), terminal `bbox`/`layer`/`port` attributes, the three report commands called without options (VERIFY items in the report of task 048).

## 7. `placement.tcl` (icc2_shell)

Needs `pins`; saves `placed`. `place_opt` (all stages), checks, and the report of the input-port wires.

```
icc2_shell -file $UNPU_REPO/pnr/placement.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/placement.log
```

Good result (first run in brackets): 204 signal terminals; the five stages named; setup violating endpoints 0 (WNS 0.0000; worst path `paddr[3]` to `prdata[23]`); max transition and capacitance 0; `check_legality` 0;
`check_pg_connectivity` 0 floating cells/wires/vias/terminals [11,986 cells]; area about 426,097 um2, about 11,986 instances, 161 buffers, 1,353 inverters, `leaf_cells_difference` about 501; `LGL-031` and `PDC-003` are printed and benign;
the HOLD Warning is expected [2,304 endpoints, worst -0.28 ns]: place_opt does not fix hold. 11 checks **(stub)**. Run time: about 133 s for `place_opt` [first run], a few minutes in all.
The port report: `rpt/placed_port_report.csv` (estimated antenna ratio per input port, worst first; an ESTIMATE, Calibre decides). The aim of the pin placement is a longest HPWL far below the first run's 180 um (`paddr[4]`).
Predicted failures: the port direction / net bbox / gate-area attributes (the report then says "unavailable" per port and the run continues), `report_utilization` / `report_qor` texts (K27).

## 8. `cts.tcl` (icc2_shell)

Needs `placed`; saves `cts` (clock tree built, hold not fixed) and `clkopt` (hold optimised at `HOLD_UNCERT`, default 0.5 ns).

```
icc2_shell -file $UNPU_REPO/pnr/cts.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/cts.log
```

Good result: `sinks = 2465` (CHECK); levels about 3 and about 53 repeaters, ss latency about 1.21 ns / skew about 0.95 ns, ff latency about 0.49 / skew about 0.36 [first run, informational]; the hold uncertainty read back = 0.5;
setup violating endpoints 0; max transition/capacitance 0; legality 0; no floating cells. `FLW-8004` may appear (counted, a Warning, cause unknown). Remaining hold endpoints are a Warning with the worst 10, NOT a failure (plan C2:
the user decides). Run time: minutes (the two `clock_opt` stages) **(guess)**. 10 checks **(stub)**.
Predicted failures: the `report_clock_qor -type summary` layout (K7), `report_constraint` (K2, not probed).
Stages: `setenv UNPU_CTS_STAGE all|tree|hold` (default `all`).

### The hold-uncertainty experiment (cts.tcl, then route.tcl)

To try another hold uncertainty from the saved tree (for example 0.2 ns, the old run's value) without rebuilding it:

```
setenv UNPU_CTS_STAGE hold
setenv UNPU_HOLD_UNCERT 0.2
setenv UNPU_BLK_CLKOPT clkopt_h02
icc2_shell -file $UNPU_REPO/pnr/cts.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/cts_h02.log
```

Mode `hold` opens `cts`, applies the uncertainty with `-scenarios ff_hold`, optimises and saves `clkopt_h02`; `clkopt` stays untouched. A Warning prints that the value differs from the plan's 0.5. To route from that block keep
`setenv UNPU_BLK_CLKOPT clkopt_h02` set when you run step 9. Unset it (`unsetenv UNPU_BLK_CLKOPT`, `unsetenv UNPU_HOLD_UNCERT`, `unsetenv UNPU_CTS_STAGE`) to return to the plan values. A tree-only run is `UNPU_CTS_STAGE tree`.

## 9. `route.tcl` (icc2_shell)

Needs `clkopt` (or the block named by `UNPU_BLK_CLKOPT`); saves `routeauto` (right after `route_auto`, if its critical checks pass) and `routed` (after `route_opt`; UNFILLED on purpose).

```
icc2_shell -file $UNPU_REPO/pnr/route.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/route.log
```

Good result: `define_antenna_rule` runs BEFORE `route_auto`; `RESULT route antenna_switch_state = on (route.detail.antenna = 'true')` (a loud `!!!` Warning if not); `ZRT-309` count 0 in both routing outputs; open nets 0, DRCs 0,
`check_lvs` shorts/opens/floating 0, ICC2 antenna violations 0 (the 80 input-port nets are skipped by ICC2, `ZRT-311`; Calibre decides), legality 0, no floating PG, setup and hold violating endpoints 0, max transition/capacitance 0.
23 checks **(stub)**. Run time [first run]: `route_auto` about 1 min, `route_opt` about 45 s. `OPT-209` may appear twice (Warning; the QoR decides).
Predicted failures: the `check_routes` / `check_lvs` / route-summary layouts (K8), `report_constraint` (K2). A hold residual after `route_opt` FAILS the stage; see the next paragraph.

**`UNPU_ROUTE_ACCEPT_HOLD`** (default 0; never set it by default). If the hold check fails and you decide, with a WRITTEN REASON in your notes first, to go on: `setenv UNPU_ROUTE_ACCEPT_HOLD 1`
and run again. It saves with `hold_accepted = 1` and the endpoint list in `logs/manifest_route.txt` and prints the worst 10. It works only when the count is known and above zero; no other check can be overridden.
Rerun after a success, or after a failure that came after `routeauto` was saved: `setenv UNPU_BLK_ROUTE_AUTO routeauto2` and `setenv UNPU_BLK_ROUTED routed2`.

## 10. `fill.tcl` (icc2_shell)

Needs `routed`; saves `final` (FILLED). Fill is the LAST step: any later `route_opt` deletes every filler (handoff 18.22). A routing change means going back to `routed` and filling again.

```
icc2_shell -file $UNPU_REPO/pnr/fill.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/fill.log
```

Good result: the three filler cells found and typed `filler`; fillers inserted for all three cells; `pg_pins_connected` = 2 x fillers (first run: 22,512 fillers, 45,024 pins on the 144-row die; the 153-row die gives a different number);
`coverage` difference 0 (within 2 sites); fillers with violations 0; legality 0; PG connectivity 0; setup 0; max transition/capacitance 0. 27 checks **(stub)**.
**The fill hold residual rule** (decision of 2026-10-29, handoff 18.22 option A): 0 hold-violating endpoints is a PASS; a residual of at most `FILL_HOLD_MAX_ENDPOINTS` (10) endpoints, none worse than 1 ps (`FILL_HOLD_TOLERANCE_NS` 0.001),
is accepted with a Warning, `hold_residual_accepted = 1` in `logs/manifest_fill.txt` and the endpoints listed; PrimeTime then judges it. Anything worse FAILS. There is no environment switch for hold here.
Optional: `setenv UNPU_FILL_ECO 1` lets it run `route_eco` ONCE if fillers with violations remain (default 0).
Predicted failures: the per-cell "inserted" lines and the `connect_pg_net` table layout (K9), the area report used for the coverage check (K27; the coverage check then becomes a Warning), the `ref_name` filter (K28).
Rerun: as always, with `setenv UNPU_BLK_FINAL final2` after a success.

## 11. `outputs.tcl` (icc2_shell)

Needs `final`; saves NO block. Writes the files into `$UNPU_WORK/$UNPU_RUN_TAG/out/` and checks each from outside.

```
icc2_shell -file $UNPU_REPO/pnr/outputs.tcl -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/outputs.log
```

Good result: 46 checks **(stub)** all PASS; files `unpu_top_sim.v`, `unpu_top_lvs.v`, `unpu_top.lef` (one `MACRO`, `SIZE 868.0 BY 868.0`), `unpu_top_{ss,ff}.spef.*`, `unpu_top_{ss,ff}.sdf`, `unpu_top_{ss,ff}.sdc`, `unpu_top.gds`;
76 modules in both netlists; `GDS-017` printed a few times (the kit layer map's `T` lines, the file is still written); a text label in the GDS for every port and for VDD/VSS. Sizes at the old die: GDS about 15.7 MB, each SPEF about 25.7 MB, SDF 8 to 9 MB, LEF about 56 KB. Run time: a few minutes.
No file is overwritten: if the targets exist the script stops naming them; `setenv UNPU_OUTPUTS_OVERWRITE 1` deletes and rewrites them. `setenv UNPU_GDS_LAYER_MAP <path>` uses a corrected layer map.
Predicted failures: the GDS label text form (K12), the `write_sdc` uncertainty layout (K11), the LEF power-pin rectangle count (K12), `create_frame` / `write_lef` as in 18.23.

---

## The scp copy-back (from a LAPTOP terminal — WSL — not from the server)

The files are copied to `~/server_pull/` so the Claude sessions can read them. The server is `EE5239G1@172.16.82.70`; `scp` asks for the password: type it there, never in a command or a file.
`scp -r <remote folder> <local folder>` puts the remote folder INSIDE the local folder and overwrites files of the same name. To keep an earlier pull, give each pull its own local folder named by the run tag and the step:

```
mkdir -p ~/server_pull/run1_after_placement
scp -r EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/rpt ~/server_pull/run1_after_placement/
scp -r EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/logs ~/server_pull/run1_after_placement/
```

(`run1` is `UNPU_RUN_TAG`; change it, and the local folder name, for another tag or step. The NDM step also has `.../icc2_work_v2/ndm/ndm_file_gen.log`, `ndm_manifest.txt` and `manifest_ndm_file_gen.txt`: copy them with `scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/ndm/ndm_file_gen.log ~/server_pull/run1_after_placement/`, and so on.)

The `out` folder holds large files. **Big: the two SPEF files (about 25 MB each at the old die), `unpu_top.gds` (about 15.7 MB), the two SDF files (8 to 9 MB each).** Copy only the small ones unless you are asked for a big one:

```
mkdir -p ~/server_pull/run1_out
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/out/unpu_top.lef ~/server_pull/run1_out/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/out/unpu_top_sim.v ~/server_pull/run1_out/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/out/unpu_top_lvs.v ~/server_pull/run1_out/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/out/unpu_top_ss.sdc ~/server_pull/run1_out/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/out/unpu_top_ff.sdc ~/server_pull/run1_out/
```

(The netlists' sizes were not recorded: if one is large, check with `ls -l` on the server first.) A big file, only on request: `scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/icc2_work_v2/run1/out/unpu_top.gds ~/server_pull/run1_out/`.

## After the ICC2 flow: not scripted yet

The flow does NOT end at `outputs.tcl`. Still to do, in this order (none of it is scripted; handoff 18.24 to 18.27 has what the first run did):

1. Calibre DRC on `unpu_top.gds` (404 rules in the first run; GDS written with `-units 1000`).
2. Calibre antenna check (16 rules; the first run's last failure was the input port `paddr[4]`, 180 um from its load; the placement report estimates it now).
3. Calibre LVS: `unpu_top_lvs.v` to SPICE with `v2lvs` against the kit CDL, then LVS (the pin-label layer in the GDS is only settled here).
4. The antenna fix loop if Calibre still reports violations (decided after Calibre shows what is left; port diodes were not insertable in the first run because `adiode` is `dont_use`).
5. PrimeTime signoff: ss setup and ff hold with the SPEF/SDF/SDC of `outputs.tcl` (the filler hold residual of the fill step is judged here).
6. Post-layout gate-level simulation with `unpu_top_sim.v` and the SDF (Xcelium).
7. The macro timing model (`.lib`) for the top level (a PM question, open), the dummy-fill / density run (open), and handing the files to the top-level team.
