# Progress log of run 2, 2026-11-10 (continues `progress-log-2026-11-09.md`)

Run 2 = the whole flow again from synthesis, with the lessons of run 1 built in. Run 1 stays untouched as the fallback in `/storage/EE5239G1/aagams_workspace2/unpu`; run 2 lives in `/storage/EE5239G1/aagams_workspace2/unpu_run2` (a fresh clone). Newest information at the bottom of each section.

## 1. Status

| Stage | Status | Detail |
|---|---|---|
| Run directory | done | fresh clone `unpu_run2`; task 082 makes every script derive its root from its own location (`>>> RUN ROOT` line); run 1 is never written (its library timestamp was checked twice) |
| Synthesis (legacy constraints) | done, = run 1 | 0 errors, 14 files, 2,465 flops, area 442,295.84 um2, 0 latches, `check_timing` 0 warnings, worst slack +0.01 ns |
| Gate-level simulation | PASS | 343,341 checks, ALL CHECKS PASSED, 0 FAIL, 0 `*E` (1 min 57 s) |
| NDM build, design setup, floorplan, power plan, placement | done | 0 errors; placement clean (no setup / transition / capacitance violations) |
| Early port buffers (step 4c, task 085/087) | done | 54 buffers (`buffd1`), 5 read-path nets skipped (`paddr[3,5,7,9,11]`), gates ok (in2out 0.0206 -> 0.0205, setup 0.0039 -> 0.0037); block `unpu_top_portbuf` |
| CTS | done once, to be REDONE | latency ff 0.60 / ss 1.36 ns, skew ff 0.33 / ss 0.76 ns, 62 repeaters, 6 levels; redo after task 088 (latency line removal) |
| Route, fill, export, Calibre, PrimeTime, post-layout simulation | not started | |

## 2. Timeline

### 2.1 Start (about 10:00 to 10:55)
- The user asked for a new directory for the run and asked whether raising the clock uncertainty (a friend's idea) would make the PrimeTime sign-off easier. Answer: the idea is right in kind (optimise tighter than sign-off, ICC2-only) but wrong as a global uncertainty increase: the gap is path-specific (I/O paths), the read path `paddr` -> `prdata` has ~0 margin in both tools, and the flow ALREADY has an ICC2-only margin (`OPT_*_UNC = SPEC_*_UNC + *_SLACK_GOAL`, goals 0.0 by the user's decision of 2026-11-02). Execution's quoted uncertainties (0.6 / 0.05) were the example profile; the flow reads the old constraints (1.5 setup, 0.5 hold).
- Decisions (user: "lets go with your recommendations"): L1/L2 research first, no global margin; L3 buffer input ports up front; L7 keep the 0.40 ns clock-path limit as a CTS target; L8 DC check of the DMA outputs as a report only; the PM question is dropped (no answer); the parked 059/062 files stay parked.
- Synthesis and the gate-level simulation re-run in `unpu_run2`: identical to run 1.

### 2.2 Tasks of the day (Planning -> Execution)
- 082 relocatable scripts (done, `1a06fd4`), 083 research (Part A answered: no ICC2 switch found for zero-latency I/O, a diagnostic needed), 084 read-only I/O latency diagnostic (`1b68ba2`), 085 early port buffers (`07cbbac`), 087 cone policy for them (`9d28d28`), 086 what-if experiments (`4a1baaa`), 088 remove the tool-made clock latency in the flow (written, in progress).

### 2.3 Finding: why ICC2 and PrimeTime disagree on the I/O paths (about 11:00 to 11:40)
- Diagnostic 084 on a COPY of run 1's `unpu_top_route` block: ICC2 counts a clock latency on the I/O reference (output capture 0.8069 ns at ss) where PrimeTime counts 0.00. H1 confirmed.
- The exported SDCs of run 1 contain one line each, written by the tool and never by us: `set_clock_latency 0.806866 [get_clocks {clk}]` (ss) and `set_clock_latency 0.379753 [get_clocks {clk}]` (ff). No log, no script mentions it.
- What-if 086, experiment A0 (remove that line in memory, per scenario): the four example paths become PrimeTime's: hold slack -0.3494 (PrimeTime -0.35), output required 10.5000 (PrimeTime 10.50), `dma_addr[31]` source-flop launch 0.9188 (PrimeTime 0.92). reg-to-reg slacks unchanged; in2out setup 0.0212 -> 0.0081 (still met, now in PrimeTime's convention). The other options fail: `-network_latency_included` / `-source_latency_included` fix only the input side or nothing; the offset emulation overshoots (hold -0.61).
- The earlier "0.27 ns data-delay difference" was a parsing artefact of the diagnostic: the 0.6413 launch was the 0.3798 latency plus the 0.2615 port stage.
- DECISION (user: "yes go with your recommendation"): remove the line inside the ICC2 flow, with printed checks (task 088): in `cts.tcl` at the earliest point it exists, in `route.tcl` and `timing_closure.tcl` after opening the block, in `pv.tcl` before `write_sdc` with a hard check that the exported SDC has none. No margin, no SDC text from the PM, no uncertainty change.

### 2.4 Server results worth remembering
- Early port buffers: prediction (margin 0.8): 59 BUFFER + 20 OK + 22 NO-LOADS + 1 CLOCK; the first real run was stopped by its own gate (5 buffers on the read path: in2out 0.0206 -> -0.1198); with `CONE_POLICY skip` (default) it passed. The 5 skipped nets have predicted ratios 565 to 1172 (limit 400): expect Calibre antenna findings there after the route, to be handled by `antenna_port_buffers.tcl` as in run 1. The clock port: predicted ratio 440 with `inv0d4` (limit 400).
- CTS log: `clock_opt.hold.effort` is obsolete (NDMUI-439, caught by a `catch`, harmless; remove it); `FLW-8004 Incomplete clock_opt / final_opto` warning to watch; ICC2 view after CTS: setup WNS 0, hold 11 violating endpoints, worst 0.085.
- csh traps again: `2>` is "Ambiguous output redirect" (use no redirect or `>&`); `< /dev/null` makes `icc2_shell -f` exit by itself.

## 3. Mistakes and corrections
- Execution quoted the example's uncertainty profile; corrected (the flow reads the legacy SDC).
- The 084 parser mixed port stage and clock latency; explained by the 086 raw rows.
- My ETA for the diag: none of the 25 reports crashed the run; one failed for the wrong call form (`report_app_options` with several names), fixed in 086.

## 4. Next (in order)
1. Task 088 (Execution) -> commit -> pull in `unpu_run2`.
2. Redo CTS in run 2 with the removal; check the latency report and that the SDC line is gone from the block after each step.
3. PrimeTime checkpoint right after CTS (needs an export of the CTS state: ask Execution whether `pv.tcl` can run on `_cts` for this), then route, then PrimeTime again before fill (lesson L5).
4. Antenna repair for the 5 skipped nets if Calibre needs it; fill; export; the three Calibre checks; both PrimeTime runs; post-layout simulation.
5. The "what we did differently" section for the course report: relocatable run directories, early port buffers with a formula-based prediction, the tool-made clock latency found and removed, the checkpoints.

## 5. Later on 2026-11-10 (after the origin check)

### 5.1 The line starts at the power plan; task 089
- `diag_clock_latency_origin.tcl` on run 2's own library: 0 lines in `_setup` and `_floorplan`; 1 line from `_powerplan` on (ff 0.138485, ss 0.356843); `_portbuf` and `_cts` hold 0.367671 / 0.806847. CTS never replaced the pre-CTS estimate. So `place_opt`, step 4c and the old CTS timed the I/O paths against the estimate.
- Task 089: remove the line at the start and end of `placement.tcl` and `port_buffers_early.tcl` (every `update_timing -full` through a helper that cleans up and prints a NOTE if the tool re-created it), a final removal and three count-only probes in `powerplanning.tcl` to name the trigger. Done locally, 120 checks in `test_clock_latency.tcl`.

### 5.2 Decisions (user)
- Redo the WHOLE flow from synthesis in a NEW clone (run 3, `unpu_run3`), because the instructor said it is better that way. Run 1 and run 2 stay as they are. Planning's earlier view (steps before placement are unaffected by the line, synthesis is deterministic and gave the identical netlist) is kept in the record: the full rerun is for a clean, single-commit deliverable, not because of a technical need.
- Raise the clock uncertainty only while the optimiser runs, restore it afterwards (a friend's experience for the PrimeTime sign-off). Planning's caveat: a clock-wide margin hits the zero-margin read path (`paddr` -> `prdata`, setup +0.0081, hold +0.0068 in PrimeTime's convention); hence task 090 scopes the margin to paths that end at registers (`flops`, default) with an `outputs` alternative and a `clock` comparison form; starting values setup 0.05, hold 0.10 (environment overrides); restore proof and an exported-SDC check; probes that test the unverified ICC2 behaviour on the server. Done locally, 151 checks in `test_opt_uncertainty.tcl`.

### 5.3 Waiting for
- The user's "commit and push" for 089 and 090, then `unpu_run3`: synthesis, gate-level simulation, NDM, setup, floorplan, power plan, placement, port buffers, CTS, route with PrimeTime and Calibre checkpoints (lesson L5), then fill, export, Calibre, PrimeTime, post-layout simulation.

## 6. Run 3 (clone `unpu_run3`, commit `0196348` and later): results so far

### 6.1 Front end and route
- Synthesis, GLS: identical to runs 1 and 2 (2,465 flops, 442,295.85 um2, 343,341 checks). NDM, setup, floorplan, power plan, placement, early port buffers (54 buffers, 5 read-path nets skipped by the default `CONE_POLICY skip`), CTS, route: all complete, 0 errors.
- The tool-made `set_clock_latency` line: created again inside `place_opt` and inside `build_clock`; removed each time by the proc of task 088; after CTS the I/O reference is PrimeTime's (output capture 0.0000, input launch 0.2403 = port stage). The 090 margin probes work (in2reg hold -0.1000, setup -0.0500; scope `flops`).
- Route: 0 shorts, 0 opens; 090 report: in2out setup +0.0103 (after CTS) -> -0.0106 after route_opt in ICC2's view.

### 6.2 Checkpoint after route (task 091), before fill and before any antenna ECO
- PrimeTime on the route block (`UNPU_PT_TAG route`): SETUP ss: 0 violating endpoints (the run-1 `dma_addr[31]` failure is gone); HOLD ff: WNS -0.0238, TNS -0.0667, 7 violating endpoints, all register-to-output into `prdata[*]` from `u_csr` flops (PrimeTime sees up to 24 ps more than ICC2: parasitics). Run 1 had -0.24 / -0.35 on 1 / 263 endpoints.
- Calibre on the route GDS: DRC 404 rules, 0 results; antenna 10 results (AN.MTL.1.M2 4, M3 2, MT 4): 8 on `paddr[7]`/`paddr[11]` (the skipped read-path nets), 2 on internal nets.
- `fix_antenna.tcl` (layer hopping) then a second checkpoint (`route2`): antenna 4 results left, all M2 on `paddr[7]`; DRC 0 (re-run result pending when this was written; the antenna log showed 4).
- Next: `antenna_port_buffers.tcl` for `paddr[7]` only (new antenna database from route2), then closure if the read path moves, then the hold ECO of task 092 (`reg2out` scope: 7 endpoints, flop-output nets released from the cone protection, read-mux cells still protected), checkpoint `route3`, PrimeTime and Calibre, then fill, final export, the three Calibre checks, both PrimeTime runs, the post-layout simulation.

### 6.3 Tasks 091 and 092
- 091 checkpoint export (`f179d05`): `pv.tcl` with `UNPU_PV_BLOCK` and `UNPU_PV_TAG`, `UNPU_PT_TAG` for PrimeTime, Calibre `sed` on the layout path.
- 092 hold ECO for register-to-output violators (committed after this entry): `UNPU_ECO_SCOPE reg2out`, flop-driven nets released from the cone protection, tagged input folder, `earlybuf_*` protected.

### 6.4 Server traps of this evening (for the explanation)
- csh: a `foreach` loop cannot be written on one line; `2>` is "Ambiguous output redirect"; an escaped quote inside a double-quoted grep pattern gives "Unmatched". Calibre needs its own terminal with `siemens_cshrc_clean`, `MGC_HOME`, `CALIBRE_HOME` and `$MGC_HOME/bin` on the path. A `git pull` is needed in the clone before running a script that was committed after the clone.

### 6.5 Note from the user (2026-11-10, evening)
- The PDK has no decap cells, so no decoupling capacitors are added to the design for now. Nothing in the flow inserts them (the filler step uses `feedth`, `feedth3`, `feedth9` only). Mention it in the course report as a known limitation if the instructor asks about power integrity.

## 7. Run 3 final layout: sign-off results and review (night of 2026-11-10)

### 7.1 Results on the final filled layout (all copied to `~/server_pull/run3/`)
- Hold ECO of task 092/093 applied (9 cells, +138 um2, all on flop-driven pins, gates ok: in2out +0.0362 -> +0.0385, hold in ICC2 -0.0158 -> -0.0028); checkpoint `route4`: PrimeTime setup +0.1058 / hold +0.0002, 0 violators; Calibre DRC 0, antenna 0. Metal fill and final export: LEF check passed (one macro `unpu_top`, 206 pins), SDF 3.0, exported SDC without `set_clock_latency` and with only the clock-level 1.5/0.5 uncertainty.
- Final: Calibre DRC 404 rules / 0, antenna 16 rules / 0, LVS CORRECT (with the approved `FILTER_DWN2PSUB`); PrimeTime setup ss +0.1058 ns, hold ff +0.0002 ns, 0 violators, 100 percent annotated, propagated clock proved, SI OFF.
- Numbers for the report: utilization 69.83 percent (cells 499,289 um2 in a 715,039 um2 core), global-route overflow 1.96 percent (H 1.79, V 2.12, worst cell 7 tracks), clock tree 2,465 sinks / 6 levels / 63 repeaters, ff latency 0.56 skew 0.32, ss latency 1.26 skew 0.75; ICC2 total dynamic power 8.43 mW (default activity, not meaningful); `check_pg_missing_vias` 9 (V2 5, V3 4) while Calibre is clean.
- Post-layout simulation: runs A (ss nochecks), B (ss checks), C (ff nochecks): `ALL CHECKS PASSED`, 343,341, 0 FAIL, 0 `*E/*F`; the script says FAIL because of new SDF message forms (24 conditional-arc SDFNEP on `ad01d0`; SDFNL1 / SDFNET on reset flops in checks mode) and a violation counter that matches specify-source context lines (`grep "Timing violation"` = 0); run D failed twice with `NOLICN` (all six Xcelium licence features failed: seats in use). Task 094 (verdict honesty, classification, user approval switch).

### 7.2 Review findings
- REAL GAP: the final ss design-rule report has 510 max_transition entries: 424 on the clock-path limit 0.40 ns (actual 0.43-0.48; the limit comes from the example `cts.tcl`, exported in the SDC, not in the legacy SDC: the L7 item, user decision pending: option A tune CTS, option B drop from the exported SDC with a written reason; Planning recommends asking whether the limit is a required sign-off limit) and 86 on the DATA limit 3.0 ns (legacy SDC; actual 3.03-3.05; `dma_wdata[25/27/29]`, `u_actbuf/U4xx/A2`). ICC2's own final QoR shows 10 violating nets. The PrimeTime summary did not report design rules. USER DECISION: fix the 86 by an ECO (task 095). 
- The PrimeTime summary prints run-1 constants as the ICC2 reference (hardcoded): to be removed (task 095).
- Hold margin is +0.0002 ns with SI OFF; an SI-on run is a robustness check (task 095, part 3).

### 7.3 Explanations given to the user today (for the final explanation)
- ECO = engineering change order, a small local fix on a nearly finished layout, with gates and a fresh checkpoint after each.
- SI = signal integrity (crosstalk): coupling capacitance to switching neighbours changes delay by tens of ps; PrimeTime without SI is less pessimistic than ICC2 with SI.
- Max transition = slew limit; clock-path limit 0.40 ns versus the course's data limit 3.0 ns.

## 8. Tasks 095, 096, 094 reported (night of 2026-11-10); server network outage

### 8.1 095 / 096 / 094 results (local; committed together)
- 095: the 86 data-limit (3.0 ns) max_transition entries sit on 9 nets: `u_seq/HFSNET_137` (40 loads on one `buffd1`, 41 entries), `u_actbuf/HFSNET_29` (37 loads on one `buffd1`, 38 entries) and 7 `dma_wdata` ports (`an02d4`, 1 pF load). `pt_eco_drc_probe.tcl` + `UNPU_ECO_KIND=drc` in the apply; design-rule block in the PrimeTime summary ("SIGN-OFF IS NOT CLEAN: DESIGN RULES VIOLATED (510)" on run 3); `UNPU_PT_SI`.
- 096 (option B decided by the user): the clock-path 0.40 ns limit is removed from the exported SDC by `pv.tcl` with a hard check; `UNPU_PT_SDC=legacy` signs off against the legacy constraints; `sdc_compare.tcl`: run-3 exports vs legacy: 723 constraints, 718 SAME, 4 EXPECTED (propagated clock, units, explicit waveform, operating conditions), 1 DIFFERENCE = the clock-path line.
- 094: post-layout verdict. The "500 violations" were Xcelium source-context lines (real count 0; `Disabled Tchecks = 0`); the SDF warnings classified with TRUE counts from the SDF itself: 22,534 of 52,656 IOPATH entries (42.8 percent) cannot be annotated: 3,510 edge-form (6.7 percent, the class accepted on 2026-11-09), 19,024 COND-form on full adders (ad01d0 18,232 in 1,633 cells; ad01d1 720; ad01d4 60; xr03d1 12): the adder SUM output has zero delay in the simulation. CORRECTION of the record: the "about 1 percent" of 2026-11-09 came from the 500 printed lines and was wrong. In checks mode: SDFNL1 (negative limit clamped to 0: ss 8,587 / ff 7,150) and SDFNET (removal value not annotated: 7,395). Nothing new is accepted unless the user approves (switch `SDF_ACCEPT`); two experiments proposed to remove the causes instead (`neg_tchk`, `===` to `==` in a copy of the SDF). Run D: `NOLICN` = licence server unreachable (not seats in use).

### 8.2 Server network outage
- From about 22:15 IST the server cannot reach the licence server (14.139.1.126:27020: ping 100 percent loss) nor GitHub (SSL error): PrimeTime/ICC2/Calibre/Xcelium and `git pull` are blocked. Nothing lost: run 3 is on disk, copied to the PC (`~/server_pull/run3/`), code committed. The library backup `blocks/unpu_top.dlib.bak_pre_maxtrans` exists. Pending on the server: pull, the 095 probe + apply, `pv.tcl`, Calibre `final2`, PrimeTime (SI off/on, legacy SDC), simulation (with the 094 approvals), run D.

## 9. SI-on round (night of 2026-11-10 to 11-11)

### 9.1 Where run 3 stands (fallback, verified, copied to the PC `~/server_pull/run3/`)
- Final filled layout after tasks 092 to 097: Calibre DRC 404 rules / 0, antenna 16 rules / 0, LVS CORRECT (`final2`); PrimeTime SI OFF: setup ss +0.1041 ns, hold ff +0.0008 ns, 0 violators, DESIGN RULES MET (exported SDC and legacy SDC give identical numbers); exported SDC = legacy constraints apart from 4 expected tool lines (`sdc_compare`: 723 compared, 718 SAME, 4 EXPECTED, the 1 DIFFERENCE was the clock-path limit, now removed); post-layout simulation A to D: `ALL CHECKS PASSED` 343,341, 0 FAIL, 0 `*E/*F`, 0 timing violations; verdict word FAIL only because the SDF classes `nep_cond`, `nl1_neg`, `net_remrec` are not yet approved (task 094).
- PrimeTime SI ON (after the two-line-header parser fix, commit 6970448): setup ss -0.0364 ns / 4 endpoints (all `paddr[3]` -> `prdata[20,10,22,17]`: -0.0364, -0.0242, -0.0090, -0.0059), hold ff -0.0114 / 1 endpoint (`prdata[9]` from `u_csr/src_a_reg_reg_9_`); design rules MET; annotation 100 percent with 13,094 coupled nets.

### 9.2 Decision and ECO round (task 098, commit 65ff234)
- User (2026-11-11): do the SI ECO round, so that the design is clean with SI on and off. Library backup `blocks/unpu_top.dlib.bak_pre_si` made. Probes (SI ON, `pt_si/`): hold: ONE `buffd1` on the load pin `u_csr/U361/C2` (original net `u_csr/n69` driven by `src_a_reg_reg_9_/QN`: class load pin on a flop-driven net); setup: ONE resize `u_apb/U29` `buffd1` -> `buffd3` (same function, faster; net `u_apb/csr_sel[1]`, on the read path, +3.14 um2). In PrimeTime's memory: SI-on violators 4 -> 0, setup WNS -0.0364 -> +0.0034, read-path slack -0.0364 -> +0.0592; SI-off: setup WNS +0.1041 unchanged, read-path slack +0.1164 -> +0.1421.
- The ICC2 apply (hold, then setup) could NOT start at 03:18: licence server unreachable (FlexNet -15,570); ping to 14.139.1.126 and `curl` to github.com both fail (second outage of the night, the first was 22:15 to about 23:30). Nothing was changed; the apply is to be repeated when the network is back.

### 9.3 Server traps of the night (for the explanation)
- csh: a trailing `&` puts the whole `;` chain in the background; `git log` then waits on its pager and the job is `Suspended (tty output)`: use `git --no-pager` and start background jobs alone, with `< /dev/null`. `2>&1` is "Ambiguous output redirect" in csh. A dropped ssh connection kills foreground jobs but not `nohup` jobs (run D of the simulation and the SI probes survived). `tmux` exists on the server (`/bin/tmux`), `screen` does not.
- Honest corrections of the record: the first post-layout acceptance ("about 1 percent") was based on 500 printed warnings; the true share of unmatched SDF IOPATH entries is 42.8 percent (task 094); the PrimeTime annotation parser was tested on a paraphrased table twice before the verbatim two-line header was used (tasks 098 follow-ups).
