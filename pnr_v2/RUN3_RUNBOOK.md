# Run 3 runbook: the ordered steps that produced the final state (2026-11-10 19:26 to 2026-11-11 04:43)

Final state (server files read on the PC, `~/server_pull/run3/pnr_icc2`): Calibre `final4` DRC 0 (404 rules) / antenna 0 (16 rules) / LVS CORRECT; PrimeTime SI OFF setup +0.1057 / hold +0.0041, SI ON +0.0154 / +0.0038, legacy SDC identical to SI OFF, 0 violators, design rules MET (`pt/`, `pt_si/`, `pt_legacy/` logs, line `SUMMARY`); post-layout simulation A to D `PASS (with documented SDF limitations)` with `SDF_ACCEPT="nl1_neg net_remrec nep_cond"` (user decision 2026-11-11), 343,341 checks each (`sim/`).

## How to read this document

- **Sources.** Only logs and commits. `R3` = `~/server_pull/run3/pnr_icc2` (on the server `<RUN_DIR>/pnr_icc2`). Times are the modification times of the copied server files and the commit times of this clone (both read as the same clock: server `Date` lines such as `Tue Nov 10 21:10:15 2026` and the commit times agree to the minute; the logs do not record the commit hash).
- **"Commit".** The commit that was in force when the step ran = the newest commit older than the step's time that touches the script, **inferred from timestamps, not recorded in any log**. Where a log line proves a feature of a commit (a `>>> 091`, `>>> 098` line) that is said. The "minimum commit" is the commit that introduced the feature the step needs.
- **Commands.** The shell history of the server is not among the copied files. Every command below is reconstructed from the READMEs / script headers of that commit and checked against what the log shows (the `>>> 0NN` parameter lines, the `-sdf_cmd_file` lines, the `pt_shell_command.log` / `*.history` files). Marked **[reconstructed]** where no log shows the exact line.
- **Shell.** csh at the server; `bash` is called explicitly for the `.sh` scripts. Every command is ONE line. `$RUN_DIR` = the clone, `source ~/cad_cshrc` once per terminal.
- **Deterministic / tool-run dependent.** Each step is marked `D` (the script and its inputs determine the result; I have no second run of run 3 to prove repeatability, so this means: no random choice in our scripts) or `T` (the result depends on the tool's run: the specific cells, nets, counts and slacks of THIS run will differ in a fresh run).

## Step overview

| # | Step | Server time | Commit in force | Result line to expect | D/T |
|---|---|---|---|---|---|
| 1 | Synthesis (legacy profile) + zero-delay GLS | 11-10 19:30 | 0196348 | `Elapsed time for this session 43 seconds`; GLS `ALL CHECKS PASSED`, `checked 343341` | D (netlist) |
| 2 | NDM libraries | 19:35 | 0196348 | `Elapsed time ... 11 seconds` / `5 seconds` | D |
| 3 | ICC2 stages 1 to 6 (incl. 4c early port buffers, CTS, route) | 19:47-20:09 | 0196348 | `STAGE 6 COMPLETE: unpu_top_route saved successfully` | T |
| 4 | Checkpoint `route`, PrimeTime, Calibre `route1` | 20:23-20:28 | f179d05 | hold -0.0238 (7 endpoints), antenna 10 | T |
| 5 | Antenna loop: `fix_antenna`, checkpoint `route2`, Calibre `route2`, `antenna_port_buffers`, checkpoint `route3`, Calibre `route3` | 20:34-20:50 | f179d05 | antenna 10 -> 4 -> 0 | T |
| 6 | Route-level hold ECO (9 cells): probe, apply, checkpoint `route4`, PrimeTime, Calibre | 20:59-21:07 | d3f3409 | hold -0.0188 -> +0.0002 | T |
| 7 | Fill, export, PrimeTime, Calibre `final` | 21:09-21:13 | d3f3409 | 0 / 0 / CORRECT; design rules VIOLATED (510) | T |
| 8 | Data-limit ECO (9 resizes) and its chain | 22:39-23:45 | 615ac84 | 86 -> 0 data-limit entries; Calibre `final2` 0/0/CORRECT | T |
| 9 | Option B (clock-path limit out of the SDC), SDC compare | with step 8 | 73f169d | `CHECK exported SDCs` | D |
| 10 | SI-on ECO round (hold buffer, setup resize, 2nd hold buffer, 2nd antenna fix) and its chain | 00:55-03:53 | 779283a | SI ON: 4 setup endpoints + 1 hold -> 0 / 0 | T |
| 11 | PrimeTime SI OFF, SI ON, legacy SDC on the final export | 03:51-03:52 | 779283a | `both MET` | D given the layout |
| 12 | Post-layout simulation A to D with `SDF_ACCEPT` | 04:22-04:43 | 73340be | `=== PASS (with documented SDF limitations ...)` | D given the layout |

---

## 1. Synthesis (legacy constraints) and zero-delay gate-level simulation

- **Commit:** 0196348 (constraints/legacy and `dc_script_legacy.tcl` unchanged since e3e7f2a). **Env:** none (`UNPU_STAGE` NOT set for the legacy profile, `constraints/legacy/dc_script_legacy.tcl` header lines 77-85).
- **Command [reconstructed from the script header]:**
```
cd $RUN_DIR
source ~/cad_cshrc
source ~/synopsys_cshrc
mkdir -p syn/out ; dc_shell -f constraints/legacy/dc_script_legacy.tcl |& tee syn/out/legacy_dc.log
```
- **Key output:** `syn/out/legacy_dc.log` ends `Elapsed time for this session 43 seconds`; `syn/out/legacy/unpu_top.profile`: `legacy constraints: period 20.0 ns, setup uncertainty 1.5 ns, hold uncertainty 0.5 ns`; `syn/out/legacy/unpu_top.timing`: `slack (MET) 0.01`. Time 19:30-19:31.
- **GLS (zero delay) on the synthesized netlist:** `syn/out/gls/xrun_cn.log` (19:30:13 to 19:32:08 IST, `total: 00:01:55`): `-sv -64bit -access +r -timescale 1ns/1ps -notimingchecks -top unpu_top_tb -define GLS_CLK_HALF_NS=10 -xmlibdirname xrun_out/gls`, then `checked 343341 value(s)/assertion(s) total` and `ALL CHECKS PASSED` (`:1680-1681`). **Cannot verify which script started it:** `scripts/run_gls.sh` is referenced by `syn/RUNBOOK.md` but is untracked (`??`) in this PC clone.
- **D.** DC and xrun results follow from the inputs.

## 2. NDM libraries

- **Commit:** 0196348. **Env:** none. **Tool:** `icc2_lm_shell`.
```
cd $RUN_DIR/pnr_icc2
icc2_lm_shell -f ../pnr_v2/build_ndm_std.tcl |& tee build_ndm_std_console.log
icc2_lm_shell -f ../pnr_v2/build_ndm_filler.tcl |& tee build_ndm_filler_console.log
```
- **Key output:** `Elapsed time for this session: 11 seconds` / `5 seconds` (19:35). Marked **[reconstructed]**: the README table lists the scripts and the tool, the console file names come from `R3/`.
- **D.**

## 3. ICC2 stages 1 to 6 (all with default parameters)

- **Commit:** 0196348 (the logs print `>>> 088`, `>>> 089`, `>>> 090` lines of tasks 088 to 090, committed in 0196348). **Env:** none set: the parameter lines say `default` (`logs/4c_port_buffers_early.log:2` `PLAN_ONLY 0 (default) ... CONE_POLICY skip (default)`; `logs/5_cts.log:236` `scope flops (default), setup goal 0.05 ns (default), hold goal 0.10 ns (default)`; `UNPU_CTS_SPLIT` default 1).
```
cd $RUN_DIR/pnr_icc2
icc2_shell -f ../pnr_v2/design_setup.tcl |& tee design_setup_console.log
icc2_shell -f ../pnr_v2/floorplanning.tcl |& tee floorplanning_console.log
icc2_shell -f ../pnr_v2/powerplanning.tcl |& tee powerplanning_console.log
icc2_shell -f ../pnr_v2/placement.tcl |& tee placement_console.log
icc2_shell -f ../pnr_v2/port_buffers_early.tcl |& tee port_buffers_early_console.log
icc2_shell -f ../pnr_v2/cts.tcl |& tee cts_console.log
icc2_shell -f ../pnr_v2/route.tcl |& tee route_console.log
```
(each ends with `exit` typed at the prompt unless the console shows the script ended itself; the README says the scripts do not call `exit`.)
- **Key output lines** (`R3/logs/`): `STAGE 1 COMPLETE: unpu_top_setup saved` (19:47); `STAGE 2 ... unpu_top_floorplan` (19:47); `STAGE 3 ... unpu_top_powerplan` (19:48); `STAGE 4 ... unpu_top_placement` (19:52, 265 s); `STAGE 4c COMPLETE: 54 input-port nets buffered with scl180_std/buffd1, unpu_top_portbuf saved` (19:53; CONE-SKIPPED decisions for `paddr[3]` and others); `STAGE 5 COMPLETE: unpu_top_cts saved successfully` (19:58, 326 s; 2 tool-made `set_clock_latency` lines removed after `build_clock`); `STAGE 6 COMPLETE: unpu_top_route saved successfully` (20:09, 582 s).
- **T.** The early port buffers (54 nets), the CTS tree, the route and every number after them depend on the tool run. A fresh run gives a different layout.

## 4. Checkpoint of the route block, PrimeTime, Calibre `route1`

- **Commit:** f179d05 (task 091; `logs/7_pv_route.log:2` prints `091 PV block unpu_top_route, tag 'route'`). **Env:** `UNPU_PV_BLOCK=unpu_top_route`, `UNPU_PV_TAG=route`; PrimeTime `UNPU_PT_TAG=route`.
```
cd $RUN_DIR/pnr_icc2
setenv UNPU_PV_BLOCK unpu_top_route
setenv UNPU_PV_TAG route
icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_route_console.log
unsetenv UNPU_PV_BLOCK
unsetenv UNPU_PV_TAG
mkdir -p pt_route
cd pt_route
setenv UNPU_PT_TAG route
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_TAG
```
Calibre (a Calibre terminal, `source ~/siemens_cshrc_clean`; the control files from `pnr_v2/calibre/`; the `LAYOUT PATH` is changed to `outputs_route` with `sed`, README "Checkpoint after route"):
```
cd $RUN_DIR
mkdir -p pnr_icc2/calibre/route1/drc pnr_icc2/calibre/route1/ant
cp pnr_v2/calibre/drc.ctrl pnr_icc2/calibre/route1/drc/
cp pnr_v2/calibre/ant.ctrl pnr_icc2/calibre/route1/ant/
sed -i '/^LAYOUT PATH/s#/outputs/#/outputs_route/#' pnr_icc2/calibre/route1/drc/drc.ctrl
sed -i '/^LAYOUT PATH/s#/outputs/#/outputs_route/#' pnr_icc2/calibre/route1/ant/ant.ctrl
cd pnr_icc2/calibre/route1/drc
calibre -drc -hier drc.ctrl |& tee drc.log
cd ../ant
calibre -drc -hier ant.ctrl |& tee ant.log
```
- **Key output:** `logs/7_pv_route.log` `STAGE 7 COMPLETE ... outputs_route` (20:23, 72 s); `091 checkpoint: working on the copy unpu_top_pv_route of unpu_top_route; unpu_top_route itself is not modified`; PrimeTime `pt_route`: setup +0.1031 / hold **-0.0238, 7 endpoints** (all register-to-output into `prdata[*]`); Calibre `route1` DRC `TOTAL RESULTS GENERATED = 0`, antenna `TOTAL RESULTS GENERATED = 10`.
- **T** (all numbers). **D** for the script behaviour.

## 5. The antenna loop (repair loop 1)

Calibre antenna results of `route1` (10 polygons on M2/M3/TOP_M) are the input of `fix_antenna.tcl` (it reads the Calibre antenna database copied to `pv/drc/unpu_top_antenna_bkp.db`).

- **Commit:** f179d05. **Env:** none.
```
cd $RUN_DIR
mkdir -p pv/drc
cp pnr_icc2/calibre/route1/ant/unpu_top.ant.db pv/drc/unpu_top_antenna_bkp.db
cd pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_portbuf
icc2_shell -f ../pnr_v2/fix_antenna.tcl |& tee fix_antenna_console.log
```
- **Key output:** `logs/fix_antenna.log` `UNIVERSAL SURGICAL ANTENNA FIX (M1/M2/M3/TOP_M) COMPLETE!` (20:34; `fix_antenna_console.log` 11 `Fixing` lines, 76 s).
- Then checkpoint `route2` (same command as step 4 with `UNPU_PV_TAG route2`, `logs/7_pv_route2.log` 20:35) and Calibre `route2`: antenna **4** results.
- Then the targeted fix for the long input-port net (step 6c):
```
cd $RUN_DIR
cp pnr_icc2/calibre/route2/ant/unpu_top.ant.db pv/drc/unpu_top_antenna_bkp.db
cd pnr_icc2
icc2_shell -f ../pnr_v2/antenna_port_buffers.tcl |& tee antenna_port_buffers_console.log
```
  `logs/6c_antenna_port_buffers.log`: `STAGE 6c COMPLETE: 1 port nets buffered with scl180_std/buffd1, unpu_top_route overwritten in place` (20:43, 121 s). Checkpoint `route3` (`7_pv_route3.log` 20:47), PrimeTime `pt_route3` (setup +0.1053 / hold -0.0188, 7), Calibre `route3`: DRC 0, antenna **0**.
- **T** (counts per round). The `bak_pre_portbuf` backup of 6b is the way back for both (the README sequence takes it once before the loop). The antenna database for 6c is the one of the NEW Calibre run (`route2`): `antenna_port_buffers.tcl` reads `pv/drc/unpu_top_antenna_bkp.db`, and the README says never to repeat the loop on a stale database.

## 6. Route-level hold ECO for the 7 register-to-output endpoints (repair loop 2)

- **Commit:** d3f3409 (task 092 + 093 + the 093 follow-up; `pt_route3/pt_eco_probe.log` prints `093 insertion N ... original net ... after the ECO the pin sees net`, the follow-up's wording). **Env:** `UNPU_ECO_SCOPE=reg2out`, `UNPU_PT_TAG=route3` for the probe; `UNPU_PT_TAG=route3` for the apply.
```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_reg2out
cd $RUN_DIR/pnr_icc2/pt_route3
setenv UNPU_ECO_SCOPE reg2out
setenv UNPU_PT_TAG route3
pt_shell -f ../../pnr_v2/pt/pt_eco_probe.tcl |& tee pt_eco_probe.log
unsetenv UNPU_ECO_SCOPE
unsetenv UNPU_PT_TAG
cd $RUN_DIR/pnr_icc2
setenv UNPU_PT_TAG route3
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_console.log
unsetenv UNPU_PT_TAG
```
- **Key output:** probe (20:59-21:01): `092 scope reg2out: 7 of 7 hold violators are targets of this scope`, `reg2out: cone nets kept protected ... 195; released ... 109`, the collection form of `-buffer_list` gives `PTECO-017` and the bare-name form `commands proposed '9'` (2 `dl01d1`, 7 `buffd1`), `PROBE RESULT: ECO RAN: 9 changes ...`; apply (21:03, 123 s): `CHECK protected cells (56): reference, origin and orientation identical`, `GATE ok: the in2out group: before +0.0362 ns, after +0.0385 ns`, `GATE hold ok: the whole-design hold WNS: before -0.0158 ns, after -0.0028 ns` (`pt_eco_apply_console.log:9175-9178`), `STAGE 6g COMPLETE: 9 cells inserted, 0 cells resized`.
- Checkpoint `route4` (`7_pv_route4.log` 21:05), PrimeTime `pt_route4`: setup +0.1058 / hold **+0.0002, 0 violators**; Calibre `route4` 0 / 0.
- **T.** The 7 endpoints, the 9 insertion pins (`u_csr/U77/A2`, `U77/C2`, `U77/B2`, `U9/B2`, `U74/C2`, `U361/B2`, `U79/B2`, `U72/C2`, `U398/A2`) and the cell choices are from THIS run's timing; a fresh run has different targets (possibly none).

## 7. Fill, export, sign-off of the first final state

- **Commit:** d3f3409. **Env:** none.
```
cd $RUN_DIR/pnr_icc2
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_console.log
mkdir -p pt
cd pt
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
```
Calibre `final` (DRC, antenna, LVS): the commands of `calibre/README.md` (sections 4 to 8): `calibre -drc -hier drc.ctrl`, `calibre -drc -hier ant.ctrl`, `v2lvs -v $RUN_DIR/pnr_icc2/outputs/unpu_top_pnr_pg.v -s .../scl18fs120_supply_pins.cdl -s0 VSS -s1 VDD -o unpu_top.sp`, `calibre -lvs -hier lvs.ctrl`, each `|& tee <name>.log` in `pnr_icc2/calibre/final/{drc,ant,lvs}`.
- **Key output:** `logs/metal_fill.log` `METAL FILL COMPLETE: unpu_top_filled saved` (21:09); `logs/7_pv.log` `STAGE 7 COMPLETE ... outputs` (21:11); `pt_run3_final`: setup +0.1058 / hold +0.0002; Calibre `final`: DRC 0, antenna 0, LVS CORRECT. The PrimeTime design-rule report (`pt_run3_final/pt_setup_ss_design_rules.rpt`) shows **510 max_transition entries** (424 clock-path limit 0.40 ns, 86 data limit 3.0 ns): the trigger of steps 8 and 9.
- A first post-layout simulation round on this layout also ran (the files in `sim/` are the later ones: see step 12). **T.**

## 8. Data-limit ECO: the 9 resizes (repair loop 3)

- **Commit:** probe 22:39 with ec39550 (task 095, with the 096 changes of 73f169d from 22:29 on the server: `7_pv.log` prints `>>> 096` lines); apply 23:38 with **615ac84** (task 097 relocation: `pt_eco_apply_drc_console.log:4304` `097 a resized cell that does not fit in place is relocated ...`). The first apply (before 615ac84) applied 4 of 9 and stopped with nothing saved (Planning's report; its console is not among the copied files). **Env:** `UNPU_ECO_KIND=drc`.
```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_maxtrans
cd $RUN_DIR/pnr_icc2/pt
pt_shell -f ../../pnr_v2/pt/pt_eco_drc_probe.tcl |& tee pt_eco_drc_probe.log
cd $RUN_DIR/pnr_icc2
setenv UNPU_ECO_KIND drc
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_drc_console.log
unsetenv UNPU_ECO_KIND
```
- **Key output:** probe: `BEFORE: 86 max_transition entries of the DATA limit`, `the 86 entries sit on 9 NETS`, `clock network protected: 63 clock cells ... 215 clock nets`, `PROBE RESULT: ECO RAN: 9 changes proposed ... data-limit violators 86 -> 0`; apply (23:38, 116 s): `097 SIZE change 1: cell u_dma/U157 an02d4 -> an02d7, relocated by 1.68 um` (and changes 4, 6, 7, 8 relocated, 2/3/5/9 in place), `GATE hold ok: ... -0.0028 -> -0.0025`, `STAGE 6g COMPLETE: 0 cells inserted, 9 cells resized`.
- Then the chain of step 7 again after moving the earlier results aside: `mv outputs outputs_run3_final ; mv pt pt_run3_final ; mv sim sim_run3_final` (the folder names present in `R3`), `metal_fill.tcl`, `pv.tcl`, PrimeTime (`pt_before_si`: SI OFF setup +0.1041 / hold +0.0008, `TIMING AND DESIGN RULES: both MET`), Calibre `final2` (23:45): 0 / 0 / CORRECT.
- **T.** The 9 nets (two `buffd1` HFS buffers `u_seq/HFSBUF_1163_489` and `u_actbuf/HFSBUF_21543_531`, seven `an02d4` drivers of `dma_wdata[*]`) and the relocations depend on this run's placement.

## 9. Option B and the SDC comparison

- **Commit:** 73f169d. **Env:** none (`UNPU_PT_SDC` unset).
- `pv.tcl` removes the clock-path max_transition before `write_sdc`: `logs/7_pv.log:8198-8242` `096 func_ss: clock-path max_transition lines before the removal 1 ... trying: remove_max_transition -clock_path %C ... that form failed ... trying: remove_max_transition %C ... clock-path max_transition lines before 1, after 0 ... CHECK exported SDCs: no clock-path max_transition line, the design-wide max_transition and max_capacitance lines are those of the block`. Nothing to type: it is part of `pv.tcl`.
- Comparison tool (local or server, no EDA tool):
```
cd $RUN_DIR
tclsh pnr_v2/sdc_compare.tcl constraints/legacy/unpu_top_legacy.sdc pnr_icc2/outputs/unpu_top_pnr_ss.sdc
tclsh pnr_v2/sdc_compare.tcl constraints/legacy/unpu_top_legacy.sdc pnr_icc2/outputs/unpu_top_pnr_ff.sdc
```
  Final result (Planning's report, files read on the PC): 722 compared, 718 SAME, 4 EXPECTED, 0 DIFFERENCES.
- **D.**

## 10. The SI-on ECO round (repair loop 4)

Trigger: PrimeTime SI ON on the step-8 layout (`pt_si_before_si`): setup **-0.0364** (4 endpoints, `paddr[3]` -> `prdata[20]`, `[10]`, `[22]`, `[17]`), hold **-0.0114** (1 endpoint `prdata[9]` from `u_csr/src_a_reg_reg_9_/CP`); SI OFF still +0.1041 / +0.0008.

- **Commit:** probes 00:55 with **65ff234** (task 098); applies 03:31/03:35 with **779283a** (the setup call failed first on the class-file row count, fixed in 779283a at 03:29). **Env:** `UNPU_PT_SI=1`; probe hold also `UNPU_ECO_SCOPE=reg2out`; apply `UNPU_ECO_KIND=hold`, then `setup`.
```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_si
mkdir -p pt_si
cd $RUN_DIR/pnr_icc2/pt_si
setenv UNPU_PT_SI 1
setenv UNPU_ECO_SCOPE reg2out
pt_shell -f ../../pnr_v2/pt/pt_eco_probe.tcl |& tee pt_eco_probe_hold.log
unsetenv UNPU_ECO_SCOPE
pt_shell -f ../../pnr_v2/pt/pt_eco_setup_probe.tcl |& tee pt_eco_setup_probe.log
cd $RUN_DIR/pnr_icc2
setenv UNPU_ECO_KIND hold
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_si_hold_console.log
setenv UNPU_ECO_KIND setup
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_si_setup_console.log
unsetenv UNPU_ECO_KIND
unsetenv UNPU_PT_SI
```
- **Key output:** setup probe (`pt_si_before_si/pt_eco_setup_probe.log`): `BEFORE, SI ON view: violating endpoints 4, setup WNS -0.0364 ns`, `BEFORE, SI OFF view (same session ...): ... +0.1041 ns`, `AFTER, SI ON view: violating endpoints 0, setup WNS +0.0034 ns`, `AFTER, SI OFF view ...: +0.1041 ns`, `PROBE RESULT (SI ON): ECO RAN: 1 size_cell changes proposed`; hold probe: `092 scope reg2out: 1 of 1 hold violators are targets`; applies: hold `GATE ok: the in2out group: before +0.0373 ns, after +0.0394 ns` / `GATE hold ok: ... -0.0025 -> -0.0012`, `STAGE 6g COMPLETE: 1 cells inserted` (03:31, **buffd1 on `u_csr/U361/C2`**, cell `U_PTECO_HOLD_BUF10`); setup `098 change 1: size_cell u_apb/U29 -> buffd3: class cone_faster`, `STAGE 6g COMPLETE: 0 cells inserted, 1 cells resized` (03:35, **`u_apb/U29` buffd1 -> buffd3**).
- Chain after the two applies (outputs and results of 03:38-03:41): export `final3` (`outputs_final3`, `pt_final3`, `pt_si_final3`, `pt_legacy_final3`): SI OFF setup +0.1040 / hold +0.0043, **SI ON setup +0.0037 / hold -0.0002 (1 endpoint)**; Calibre `final3`: DRC 0, **antenna 3 results**. Two consequences:
  - a second SI-on hold probe in `pt_si_final3` and a second hold apply (`pt_eco_apply_si_hold2_console.log`, 03:46, `STAGE 6g COMPLETE: 1 cells inserted`: **buffd1 on `u_csr/U376/B2`**, cell `U_PTECO_HOLD_BUF11`, `GATE ok`);
  - the antenna loop again: `fix_antenna.tcl` on the `final3` Calibre database (`fix_antenna_si_console.log`, 03:47, 74 s, 4 `Fixing` lines):
```
cd $RUN_DIR
cp pnr_icc2/calibre/final3/ant/unpu_top.ant.db pv/drc/unpu_top_antenna_bkp.db
cd pnr_icc2
icc2_shell -f ../pnr_v2/fix_antenna.tcl |& tee fix_antenna_si_console.log
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_console.log
```
  `metal_fill.log` `METAL FILL COMPLETE` (03:49), `7_pv.log` `STAGE 7 COMPLETE` (03:51). The second hold probe/apply were run with the same commands as above (probe from `pt_si`, `UNPU_PT_SI 1`, `UNPU_ECO_SCOPE reg2out`, apply `UNPU_ECO_KIND hold`); the console of the second probe is `pt_si_final3/pt_eco_probe_hold.log`. **[order of the 03:3x to 03:46 commands reconstructed from the file times; the exact typing is not recorded]**.
- **Before this round**, the previous results were moved aside: `mv outputs outputs_before_si ; mv pt pt_before_si ; mv pt_si pt_si_before_si ; mv pt_legacy pt_legacy_before_si ; mv sim sim_before_si ; mv calibre/final2 calibre/final2_before_si` (README "SI-on ECO round", folder names as in `R3`).
- **Known gap:** in these applies the cells resized by the data-limit ECO were not protected by name (`098 no earlier max-transition change file .../pt/pt_eco_drc_changes_icc2.tcl`) because `pt/` had been moved aside; the end checks passed. See `VERIFY_STATUS_RUN3.md`, main V88.
- **T.** The three inserted/resized cells are specific to this run.

## 11. Final sign-off views and Calibre `final4`

- **Commit:** 779283a (PrimeTime scripts unchanged since 6970448). **Env:** none for SI OFF; `UNPU_PT_SI=1` for SI ON; `UNPU_PT_SDC=legacy` for the legacy view.
```
mkdir -p $RUN_DIR/pnr_icc2/pt
cd $RUN_DIR/pnr_icc2/pt
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
mkdir -p $RUN_DIR/pnr_icc2/pt_si
cd $RUN_DIR/pnr_icc2/pt_si
setenv UNPU_PT_SI 1
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_SI
mkdir -p $RUN_DIR/pnr_icc2/pt_legacy
cd $RUN_DIR/pnr_icc2/pt_legacy
setenv UNPU_PT_SDC legacy
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_SDC
```
- **Key output** (the `SUMMARY` lines): `pt/`: `SETUP corner ss: WNS +0.1057 ns ... violating endpoints 0, SI OFF` / `HOLD ... +0.0041`, `TIMING AND DESIGN RULES: both MET`; `pt_si/`: `+0.0154 ... SI ON` / `+0.0038`; `pt_legacy/`: `+0.1057` / `+0.0041`, `SDC: legacy (.../constraints/legacy/unpu_top_legacy.sdc)`. The annotation check passes with 16,573 nets (Planning's report) / the table in each log. Each run takes about 2 minutes (`Elapsed time` in the log).
- Calibre `final4` (03:53, new run folder, same commands as step 7): `drc.log` `TOTAL RESULTS GENERATED = 0 (0)`, `REAL TIME = 77`; `ant`: 0 results; `lvs`: `CORRECT`.
- **D** given the layout.

## 12. Post-layout simulation A to D

- **Commit:** 73340be (verdict from 73f169d, `PL_LABEL`/`PL_SDF` from 73340be). **Env:** `SDF_ACCEPT="nl1_neg net_remrec nep_cond"` (user approval 2026-11-11, "go with your recommendation, approve all three"); optional `LICENSE_RETRIES` / `LICENSE_WAIT_S`.
```
cd $RUN_DIR
source ~/cad_cshrc
mkdir -p xrun_out pnr_icc2/sim
env SDF_ACCEPT="nl1_neg net_remrec nep_cond" bash pnr_v2/sim/run_postlayout_sim.sh ss nochecks |& tee pnr_icc2/sim/runA_console.txt
env SDF_ACCEPT="nl1_neg net_remrec nep_cond" bash pnr_v2/sim/run_postlayout_sim.sh ss checks |& tee pnr_icc2/sim/runB_console.txt
env SDF_ACCEPT="nl1_neg net_remrec nep_cond" bash pnr_v2/sim/run_postlayout_sim.sh ff nochecks |& tee pnr_icc2/sim/runC_console.txt
env SDF_ACCEPT="nl1_neg net_remrec nep_cond" LICENSE_RETRIES=6 LICENSE_WAIT_S=600 bash pnr_v2/sim/run_postlayout_sim.sh ff checks |& tee pnr_icc2/sim/runD_console.txt
```
(`DRY_RUN=1` prints the commands only. The licence variables are optional: run D failed on `NOLICN` twice in an earlier round.)
- **Key output:** each console ends `=== PASS (with documented SDF limitations, SDF_ACCEPT='...')`; the logs `sim/pl_<corner>_<mode>.log`: `checked 343341`, `ALL CHECKS PASSED`, end time `278003892 NS` (ss) / `276701592 NS` (ff), `Annotation completed with 0 Errors and 22534 Warnings` (nochecks) / `38518` (ss checks) / `37079` (ff checks), `No. of Disabled Tchecks = 0` in the checks runs. Wall-clock (Planning's report of the approved reruns): A 4 m 29, B 6 m 45, C 4 m 11, D 6 m 12. Without `SDF_ACCEPT` the same logs give FAIL for exactly the three unapproved classes (re-judged on the PC: reconciliation difference 0 in all four).
- **D** given the layout (the simulation is deterministic for the same netlist, SDF and testbench).

---

## Traps (from the READMEs, the logs and csh semantics; the ones marked [Planning] come from your list and have no log of their own)

- **csh, not bash.** `2>&1` does not exist in csh: use `|&` (every command above) or `>&`. A trailing `&` in csh with `|& tee` backgrounds the whole pipeline and loses the prompt; run the long steps in the foreground or under `nohup ... >& file &` explicitly. [Planning, csh semantics]
- **One-off variables in csh:** `env VAR=value command` (there is no `VAR=value command`); `setenv` / `unsetenv` for the rest. A forgotten `unsetenv` carries into the next command: `UNPU_PT_SI`, `UNPU_PT_TAG`, `UNPU_ECO_KIND` change which folder a script reads or writes (the scripts print the value and its source in the first lines: read them).
- **`foreach` on one line is not accepted by csh**; chain the runs with `;` (README of the simulation).
- **Interactive tools do not exit by themselves:** the `icc2_shell -f ...` scripts do not call `exit`; add `< /dev/null` (as in the 092 to 098 sequences) or type `exit`. The PrimeTime scripts end with `exit`. [README]
- **Pager.** If a tool pipes `help` or long reports through a pager the session stops waiting; use `|& tee` and `< /dev/null`, and do not run interactive `man`/`help` inside a script session. [Planning; not seen in the copied logs]
- **A dropped ssh session kills the run.** Use `nohup` or `tmux`/`screen` for the Calibre and simulation runs (4 to 7 minutes each; PrimeTime and ICC2 steps 1 to 2 minutes). [Planning]
- **X display for `calibredrv`.** `calibredrv -a layout peek ...` and any GUI needs `DISPLAY`; run it in the foreground (`fg`) of a terminal with X forwarding. The DRC/antenna/LVS runs themselves are batch. [Planning; `calibredrv` was not used in the final4 run]
- **Calibre environment:** `source ~/siemens_cshrc_clean` (the original `/home/Siemens_cshrc` has CRLF line endings), then `setenv MGC_HOME ...` and `setenv CALIBRE_HOME ...` by hand (path with a space), `rehash`, `which calibre` (README). Start each check FROM its run folder: the `LAYOUT PATH` is relative (`../../../outputs/unpu_top_routed.gds`).
- **Back up the library before every ECO step** (`cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_<name>`): the apply scripts overwrite `unpu_top_route` in place when all gates pass, and save nothing when one fails.
- **Move results aside BEFORE a repeat** (`mv outputs outputs_before_si` and the like), but note that the apply of the next round reads the earlier ECO change file from `pt/` (main V88): keep it or do the moves after the applies.
- **License messages that are not failures:** `Error: Library Compiler executable path is not set. (PT-063)` in every PrimeTime log; `Error: Unrecognized feature name 'PrimeTime-ECO'. (PT-002)` before an ECO command that then runs; `FlexNet Licensing checkout error: No such feature exists. Feature: Synopsys` in `fix_antenna_si_console.log`; the `Synopsys_stack_trace_*.txt` written when the 095 probe's pt_shell closed (after `PROBE RESULT`). A real licence problem in the simulation is `*F,NOLICN` (the script exits 2 and prints the FlexNet lines; `LICENSE_RETRIES` waits).
- **Logs are buffered:** read `parasitics_command.log` only after a PrimeTime session ends; the script reads the table from the session text instead (`pt V19`).
- **Copying results to the PC:** `rsync -av --exclude 'blocks*' --exclude 'xrun_out' --exclude '*.ndm' --exclude 'flex*.log' --exclude 'xcelium.d' EE5239G1@<server>:<RUN_DIR>/pnr_icc2 ... ~/server_pull/run3/` (the command the user used; the `blocks` folder, about 1 GB, is excluded on purpose).
- **A fresh clone needs `git pull` first:** the scripts derive their root from where they live (task 082), so the clone you run in is the run root: the first line `>>> RUN ROOT:` of every log shows it; stop if it is another clone.

## What a fresh run reproduces and what it does not

- **Reproduces (deterministic by construction):** the synthesized netlist, the constraints (the exported SDC equals the legacy SDC apart from the 4 expected differences), the sequence and the gates of every script, the verdict logic and the list of approved SDF classes, the SDF warning totals' structure (the unmatched COND/edge entries are a property of the SDF/model pair; their numbers change with the netlist).
- **Does NOT reproduce (tool-run dependent):** the placement and routing, every slack, which endpoints violate, which hold/setup/data-limit ECO targets PrimeTime proposes (the 9 `u_csr` delay cells, the 9 data-limit drivers, the 4 SI endpoints, the three SI-round cells), where the early port buffers go (54 nets), how many antenna results each round has and which nets they are on, which relocations the resize ECO needs, the Calibre/PrimeTime figures quoted above. A fresh run may need fewer, more or different repair loops; the READMEs describe each loop as a rule, not as a fixed list.
- **Unverified here:** repeatability of ICC2 (no second run of run 3 exists); the exact typing of the commands of steps 4 to 7, 10 and 12 (reconstructed); the commit hashes (inferred from times).
