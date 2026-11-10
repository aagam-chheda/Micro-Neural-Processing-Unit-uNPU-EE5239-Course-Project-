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
