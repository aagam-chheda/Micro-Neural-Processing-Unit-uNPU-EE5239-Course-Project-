# Progress log of the clean-slate run, 2026-11-09

Kept by Planning so that everything done today (and what comes next) can be explained step by step at the end. Newest information is appended at the bottom of each section. Times are the server clock (IST), taken from the logs. Numbers are quoted from the user's pasted server output.

## 1. Where we are (status table, updated after every step)

| Check / stage | Status | Detail |
|---|---|---|
| RTL | frozen | 4x4 INT8 systolic matmul, 50 MHz, 32-bit accumulator |
| Synthesis (legacy constraints) | done | 2,465 flops, area 442,295.8 um2, only `max_area` violated, 0 latches |
| Gate-level simulation | PASS | 343,341 checks, 0 failures (zero-delay cell models: function only) |
| Floorplan, power, placement, CTS, route, fill, export | done once | die 885.6 x 885.6 um |
| Calibre DRC | 404 rules, 0 results | final layout (after the closure pass, fill and export) |
| Calibre antenna | 16 rules, 0 results | sequence 55 -> 50 -> 46 -> 1 -> 0; still 0 on the final layout |
| Calibre LVS | CORRECT | needed the deck's `FILTER_DWN2PSUB` switch (approved, reason written); re-run CORRECT on the final layout |
| Timing in ICC2 | nearly closed | after the 6e pass and fill: no setup violations; hold: 1 reg-to-reg path, about -0.0004 ns (0.4 ps). PrimeTime to judge |
| LEF for the top-level team | done, check passed | one `MACRO unpu_top`, 206 pins, 885.6 x 885.6 um |
| PrimeTime sign-off | ran: setup VIOLATED (-0.2423 ns, 1 endpoint, dma_addr[31]); hold VIOLATED (-0.3468 ns, 263 endpoints, input-to-register) | fix by a targeted ECO (decision A) |
| Post-layout simulation | scripts written; run A failed correctly (SDF header 2.1 with 3.0 entries) | fix in `pv.tcl`, rerun `pv`, then runs A to D |
| PM message, `Final/` folder | not done | |

## 2. Why this run exists

On 2026-11-02 the user decided on a clean slate: a new server folder `/storage/EE5239G1/aagams_workspace2/unpu`, the user's own 11 example ICC2 scripts with minimal edits (`pnr_v2/`), the OLD constraints (20 ns clock, setup uncertainty 1.5, hold 0.5, APB 35 percent, DMA 40 percent, `rst_n` 40 percent, min delays 0 and -0.5), order: synthesis, gate-level simulation, layout. The earlier scripted flow (`pnr/`, tasks 038 to 062) stays in the repo as an alternative.

## 3. Timeline of today

### 3.1 Synthesis (about 11:35)
- Cloned the repo on the server (hash `e3e7f2a`), ran `dc_shell -f constraints/legacy/dc_script_legacy.tcl`.
- Result: 0 errors, 14 output files, 2,465 sequential cells, area 442,295.8 um2 (old round-3 figure was 429,161), only `max_area` violated, no latch, `check_timing` clean, none of the six forbidden cell patterns. Worst setup slack +0.01 ns on the combinational path `paddr[3]` to `prdata[18]`.

### 3.2 Gate-level simulation (about 11:40)
- Xcelium on the new netlist with the 20 ns clock: `ALL CHECKS PASSED`, 343,341 checks, 0 failures, same count as the RTL run. The cell models have zero delay, so this proves function, not timing.
- A small trap: `xrun -xmlibdirname` needs the parent folder to exist (`mkdir -p xrun_out`).

### 3.3 Layout flow (12:00 to 12:40)
| Step | Script | Result |
|---|---|---|
| Libraries | `build_ndm_std`, `build_ndm_filler` | both NDMs built, 0 errors (540 library `FRAM-066` warnings are harmless) |
| 1 design setup | `design_setup.tcl` | 0 errors; `func_ss` is setup-only, `func_ff` hold-only; `PVT-032` no mismatch; the ff operating condition (edit E5b) took effect |
| 2 floorplan | `floorplanning.tcl` | die 885.6 x 885.6 um, core utilisation 60.02 percent, 204 pins placed (102 top M2 `dma_*`, 102 right M3 APB + `clk`/`rst_n`). The tool filled each edge from both ends, buses interleaved. DECISION (user): accept the tool placement |
| 3 power plan | `powerplanning.tcl` | PG DRC clean, 0 floating, 0 missing vias, 2 terminals |
| 4 placement | `placement.tcl` | legality 0, congestion 0, setup met, hold 2,322 violations (clock still ideal), area 429,184 um2 |
| 5 CTS | `cts.tcl` | 2,465 sinks, 6 levels, 63 clock buffers, latency 0.59 ns, skew 0.31 ns, hold down to 3 tiny violations, area 487,497 um2. The one console error is the obsolete option `clock_opt.hold.effort` (the script catches it) |
| 6 route | `route.tcl` | 0 DRC, 0 shorts, 0 opens, 0 diodes. After `route_opt` setup WNS 0.00 and 15 hold violations; at the end of the script setup -0.07 ns (one in-to-out path) and 18 hold violations |
| 7 metal fill | `metal_fill.tcl` | done; track fill on all four metals |
| 8 export | `pv.tcl` | all outputs written. Found: (a) the LEF has 122 library macros and NO `unpu_top` macro; (b) the report `UIC-057` ran in the wrong scenario; (c) 454 clock-path max-transition entries against the example script's own 0.40 ns limit (course SDC says 3.0 ns) |

### 3.4 Calibre baseline (about 13:00)
- Tasks 066 produced the control files and runbook (`pnr_v2/calibre/`). Calibre needs its own terminal and a cleaned `Siemens_cshrc`; the first terminal was bash, not csh (a mistake on my side: the `setenv` lines failed at parse time, nothing ran).
- DRC: 404 rules, 0 results (fill included: M1 320k shapes against 238k without fill). Antenna: 55 results (`AN.MTL.1.M2` 12, `M3` 25, `MT` 18).

### 3.5 The antenna problem (13:00 to 16:15) - the main story of the day
1. **What the failing nets were.** The 55 markers were only about 16 nets, and almost all were INPUT PORT nets: `pwdata` (14 bits), `dma_rdata[9]`, `clk`. A port net has no driver and no diffusion inside the macro, so Calibre counts its whole pin-to-gate wire against a tiny gate (about 0.19 um2). Limit: about 72 um of M2/M3 or 46 um of top metal. The tool had placed the 102 pins of each edge once, before any cell existed, spread across the whole 885 um edge, while the loads sit in one cluster (`u_csr`, y about 420 um). Wires were 130 to 250 um; `clk` was 478 um.
2. **`fix_antenna.tcl`, pass 1 (layer hopping):** 55 -> 50, setup -0.07 -> -0.10 ns.
3. **Step 4b experiment (pins re-placed after placement, task 067):** the second `place_pins` moved 196 of 204 pins but ignored the 8 um spacing (0.56 um pitch) and its legality check was unreadable; it refused to save. Measured pin-to-load distances stayed 100 to 250 um for most nets. PARKED (not deleted).
4. **`fix_antenna.tcl`, pass 2:** 50 -> 46, but created one DRC (`M3.S.1`). The user's friend had suggested iterating the script on the same database; we ran it on the database matching the current layout, which is the only valid reading. Progress was 4 to 5 markers per pass, too slow.
5. **Diodes ruled out** (`adiode` not available, user decision). The fix chosen: a buffer next to the pin of each offending port net (tasks 068 to 070).
   - 068 wrote the script (reads the Calibre database, maps polygons to nets, picks a buffer by LEF antenna data, inserts it, re-routes only those nets, hard checks).
   - First server run: 13 of 15 buffers fine (21 to 29 um from the pin); two moved by the legaliser to far rows; the script refused to save. Also the timing lines printed errors (`get_timing_paths -quiet`).
   - 069 changed the placement to pick a free run of filler sites and verify each buffer; second server run: all 15 nets "0 usable candidates". Cause (found with the user's read-only query): `get_cells -intersect <rectangle>` returns only cells crossing the rectangle's border, not the cells inside. 070 reads all 21,620 fillers into a table and selects the window in Tcl.
   - Third run: all 15 buffers placed correctly (tier 1); the only stop was one leftover DRC from pass 2, cleared by a window re-route around the Calibre marker. Fourth run: `STAGE 6c COMPLETE`. Calibre: DRC 0, antenna 1 (only `clk`).
6. **`clk` (task 071):** the root inverter `ZCTSINV_121581_2576` was an `inv0d2` (gate 0.961 um2, ratio 540). Replaced by `inv0d4` (gate 1.922 um2, predicted 270): a size-only change, no extra cell. Calibre antenna: **0 results**. Cost: hold WNS -0.015 -> -0.044 ns, hold violations 21 -> 53 (the faster clock root arrives earlier). The script reported `WORSE` for that, and the user chose to keep the change.

### 3.6 LVS (16:25 to 16:35)
- `v2lvs` converted the netlist (`unpu_top_pnr_pg.v`, 14,465 instances) against the kit CDL; its "No module declaration" warnings are normal (pin order comes from the CDL).
- First `calibre -lvs` stopped at rule compilation: `SPC1 superfluous specification statement: virtual connect colon` (the deck sets it itself). Removed the two `VIRTUAL CONNECT` lines from the run-folder copy.
- Second run: `INCORRECT`, but only one discrepancy: an extra layout device `D(DWN2PSUB)`, an N-well to P-substrate diode (76 parallel diodes reduced to 1) from the N-well of the `feedth` filler cells. 44,615 nets and 67,472 instances matched, every one of the 204 signal ports plus VDD/VSS matched by name (so the pin text labels are fine despite `GDS-017`).
- The kit CDL defines the fillers as empty subcircuits, so the source cannot carry the diode. The deck provides `FILTER_DWN2PSUB` (`LVS FILTER D(dwn2psub) OPEN`) for exactly this. USER APPROVED using it, with the written reason in handoff 18.34.
- Third run: **`LVS completed. CORRECT.`**

### 3.7 Timing closure pass, step 6e (about 16:50 to 17:10)
- First attempt stopped at once: `Unknown attribute 'is_buffer'` (that attribute exists on library cells only). Execution fixed the cell counting and wrapped every unproven attribute so a missing one degrades a metric to UNKNOWN instead of killing the pass (commit `bae68fa`).
- Second attempt, `timing_closure.tcl`: settings printed as 1.5 / 0.5 / 0.0 / 0.0 (identical to `route.tcl`). The 15 `antbuf_*` buffers and the clock root were protected (`dont_touch=true`, `physical_status=fixed`). Three `route_opt` passes; each improved a WNS, the loop stopped at the maximum of 3.
- Result: **setup WNS -0.0975 -> +0.0143 ns (closed); hold WNS -0.0441 -> -0.0004 ns (0.4 ps short).** Verdict `IMPROVED`. Checks: legality 0, protected cells identical to the snapshot, `antbuf_*` count 15 before and after, clock root still `inv0d4` and the only load of `clk`, fillers 21,642 -> 21,498 (0.67 percent).
- Limits of the report: the cell statistics count only the top-level hierarchical cells (198 cells, area UNKNOWN), so "ADDED: 2 cells" is not the number of hold buffers; and the per-group report printed `Nothing matched for path_group_list` (the group names differ). Neither affects the result.
- DRC 0 and open nets 0 confirmed in the log (ICC2 antenna estimate 70, was 78).
- `metal_fill` + `pv` on that layout (final numbers, after fill): NO setup violations; hold: one reg-to-reg violation of about -0.0004 ns. The LEF now holds the `unpu_top` macro (204 signal + 2 power pins, 885.6 x 885.6 um), but the new check wrongly rejected the file: the "second macro" `expanded_util` is a property-definition line in the LEF header (`  MACRO expanded_util REAL ;`), not a cell. Check fixed (counts only column-0 `MACRO <name>` lines outside the property block), 48 tests. The `UIC-057` message is gone (it only appears in the script's comments).
- A second 6e run (3 more `route_opt` passes) made things slightly worse: setup +0.0143 -> +0.0081, hold -0.00043 -> -0.00258 ns. The optimiser reached hold -0.0007 after its third pass, then the filler re-insertion and the two `route_eco` steps gave a little back. Verdict `UNCHANGED` (the script's worse-tolerance is 5 ps). DECISION: restore the first 6e result from the backup `bak_post_closure1` (the worse one is kept as `unpu_top.dlib.closure3_worse`), stop iterating, and let PrimeTime sign-off judge the 0.4 ps residual.
- Still to do on that layout: `metal_fill`, `pv` (with the fixed LEF check), and all three Calibre checks (DRC, antenna, `v2lvs` + LVS; antenna must be 0 and LVS CORRECT).

### 3.8 Final layout checks (about 18:00 to 18:35)
- Restored the first 6e result, re-ran `metal_fill` and `pv` (LEF check PASSED), then all three Calibre checks on the final GDS and netlist: **DRC 404 rules 0 results; antenna 16 rules 0 results; LVS CORRECT.** Timing after fill: no setup violations; one hold violation of about 0.4 ps (reg to reg).
- This is the layout to hand over unless PrimeTime asks for more.

### 3.9 PrimeTime and post-layout simulation: first server runs (about 18:50 to 19:15)
- **Tasks 074 / 075 written and run for the first time.** Both stopped on the first run at a problem that the script's own guard caught (nothing fails silently).
- **PrimeTime setup run (ss):** linking worked (14,397 leaf cells, 75 hierarchical cells, 0 black boxes); the SPEF was chosen from `unpu_top_spef.spef_scenario` (`TYPICAL_RC_125` for `func_ss`, `TYPICAL_RC_-40` for `func_ff`, read from the text, not from the temperature). The annotation check stopped it: PrimeTime does not print the `report_annotated_parasitics` text into the session; it writes `parasitics_command.log`, and that file is only flushed when the session ends (0 bytes during the run). The file itself shows the ss parasitics are complete: 16,113 internal and 182 boundary pin-to-pin nets, all annotated; the 393 unannotated nets are driverless (323) or loadless (48 + 22, the unused `paddr` inputs), so they carry no timing arc. Fix written: set `parasitics_log_file` to an empty string so the text comes into the session, and a mandatory post-run check (`check_annotation.tcl`) as fallback; the sign-off result carries a caveat line if it has to use the fallback.
- **Post-layout simulation, run A (ss SDF, timing checks off):** the verdict said FAIL, correctly. `xmsdfc: *E,SDFIRE ... "REMOVAL keyword is only allowed in SDFVERSION of 3.0 or later"` and `*W,SDFCNC: Cannot compile SDF file - skipping annotation`: ICC2's SDF header says `OVI 2.1` but the file has REMOVAL/RECOVERY entries. Xcelium skipped the annotation, so that run was effectively zero-delay (ALL CHECKS PASSED, 343,341 checks, simulated end 276,701,592 ns = the 20 ns clock doubling the 138,350,796 ns of the 10 ns runs). A PASS there would have proved nothing; the rule "an SDF annotation message must exist and no SDF warning" caught it. `write_sdf` has no `-version` option in this ICC2 (usage text checked by Execution), so `pv.tcl` now rewrites only the SDFVERSION header line to 3.0 after the writes and checks it (hard stop otherwise). The layout is unchanged, so the Calibre results stay valid.
- **A mix-up:** a stopped terminal left an `xmsim` process (PID 11819) running; killed. Nothing in the layout was affected (these runs are read-only).

### 3.10 Second server runs of PrimeTime and the post-layout simulation (about 19:10 to 19:30)
- **`pv.tcl` rerun:** LEF CHECK PASSED; the SDF headers were `OVI 2.1` with 9,860 entries that exist only in SDF 3.0 (REMOVAL, RECOVERY); `pv.tcl` rewrote the header line to 3.0 and re-checked both files (SDF CHECK PASSED). `write_sdf` has no `-version` option in this ICC2.
- **PrimeTime setup run (ss):** the annotation check now works in the session (`parasitics_log_file` set to an empty string): 16,295 pin-to-pin nets, 0 unannotated, 0 errors. New stops found: (1) the `check_timing` parser took the line `Information: Checking 'unconstrained_endpoints'.` (the name of a check) for a finding - fixed; (2) while reading the SDC PrimeTime printed `UITE-305 Converting a propagated clock 'clk' to an ideal clock`, so the clock was probably ideal although the SDC says propagated - the script now always applies `set_propagated_clock [all_clocks]` and proves it from a timing report ("(propagated)" tag) or stops. Also seen: the SDC carries `set_max_transition 0.4 [get_clocks clk] -clock_path` (the example `cts.tcl` limit), so PrimeTime will check it; if it reports violations a decision is needed (not a course constraint).
- **Post-layout simulation, run A3 (ss SDF 3.0, timing checks off, 4 min 46 s):** the SDF compiled and was annotated; `ALL CHECKS PASSED`, 343,341 checks, 0 FAIL, 0 `*E`/`*F`; simulated end 278,003,892 ns (zero-delay run: 276,701,592 ns; they differ because real delays now act). The script still said FAIL because of 722 SDF warnings: 222 `SDFNCAP` (informational: "the port annotation will still occur") and 500+ `SDFNEP` ("Unable to annotate to non-existent path"; Xcelium capped the messages at 1,000). The `SDFNEP` arcs are only on `mx02d0`, `mx02d1`, `mi02d0/1` (mux select to output), `ah01d1`, `ad01d0` (adder sum), `xr02d1`, `xn02d1` (XOR/XNOR) and a few `A1/A2 -> Z`: the cell model declares those paths without an edge qualifier (`(A => S)` with conditions on the other input) while ICC2 writes edge-specific entries (`(posedge A) S`, `(negedge A) S`), and Xcelium does not match them. About 1 percent of the 52,379 IOPATH delays; those arcs keep the model's zero delay, so the run is slightly OPTIMISTIC on XOR, adder-sum and mux-select arcs.
- **DECISION (user, 2026-11-09): option 1** - accept this as a documented, bounded limitation, no SDF rewriting. Reason: the model/SDF mismatch is a representation difference in the kit's cell models, it affects about 1 percent of the arcs and only the listed cell types; timing sign-off is PrimeTime's job, and it reads the SDF-independent parasitics and library timing in full. Scope: `SDFNCAP` is informational; `SDFNEP` is accepted only for the listed cell types and arc forms, with a count per cell and per arc form printed; any other cell type, any other SDF warning class, or any `SDFIRE/SDFCNC` still fails. The report must state the optimism in plain words.

### 3.11 PrimeTime sign-off results and the decision (about 19:15 to 19:50)
- **Setup, ss (clock proved propagated):** WNS -0.2423 ns, ONE violating endpoint: `dma_addr[31]` (output), startpoint `u_dma/beat_idx_reg_0_/CP`. Path: clock latency 0.92 ns + clk-to-Q 0.59 + the DMA address adder (twelve `ah01d1` carry cells, about 0.32 ns each) + `HFSINV_13_284 (inv0d4)` 1.61 ns into the 1.0 pF load = 10.74 ns against 20 - 1.5 - 8.0 = 10.50. The `paddr` -> `prdata` group, ICC2's problem group, is MET ("No paths with slack less than 0.00").
- **Hold, ff:** WNS -0.3468 ns, TNS -44.57 ns, 263 violating endpoints; 255 are flop `/D` pins (`u_dma/stage_reg_*` and `u_csr/{src_a,src_b,dest_c}_reg_reg_*`), startpoints the input ports `dma_rdata[*]` and `pwdata[*]`. Example `dma_rdata[14]`: input delay 0, data at the flop 0.56 ns (port 0.26 + `copt_h_inst` buffd1 0.17 + mux 0.12), required = capture clock 0.40 + uncertainty 0.50 + hold time 0.00 = 0.90, slack -0.35.
- **Cause (verified on the path reports):** PrimeTime launches input data and captures output data at the clock PIN (zero latency: `clock network delay (propagated) 0.00`), so the macro's clock-tree insertion delay (0.92 ns at ss, 0.40 ns at ff) counts against the interface budgets. ICC2 gave the external clock the same insertion delay as the internal tree, which made I/O paths look 0.4 to 0.9 ns easier. ICC2's sign-off-like numbers (setup +0.0143, hold -0.0004) were therefore optimistic for I/O paths only.
- **Also in the PrimeTime log:** about 150 entries of the clock-path max-transition limit 0.40 ns (from the example `cts.tcl`, carried in the SDC), exceeded by amounts below 0.01 ns; the PM question (draft written, to be sent by the user) asks whether that limit is a requirement.
- **DECISIONS (user, 2026-11-09):** (1) go with the STRICTER PrimeTime reading: fix the design to pass PrimeTime. (2) Option A: a targeted ECO driven by PrimeTime's violator lists: delay on the failing input paths (hold, about 100 input ports), a larger driver on the failing output (setup), with the 15 antenna buffers and the clock root protected, then the whole verification chain again (fill, `pv`, Calibre DRC / antenna / LVS, PrimeTime setup and hold, post-layout simulation). (3) The PM question about the clock-latency convention is sent in parallel; if there is no answer, the stricter reading stands.
- **Post-layout simulation verdict** (task 077): the bounded acceptance of the `SDFNEP`/`SDFNCAP` warnings (user option 1) is implemented in `run_postlayout_sim.sh`; the 73-check test passes; the A3 run itself has not been re-judged (no judge-only mode; the simulation is rerun after the ECO anyway).
- **Task 078** (written): PrimeTime CSV lists of all violators + a probe of PrimeTime's own ECO commands; the ICC2-side ECO script follows, depending on the probe result.

### 3.12 PrimeTime ECO probe: it works (about 21:40)
- First two probe runs failed in the probe itself (selector compared the raw `is_buffer` text wrongly; then PTECO-099 "Ignoring lib cell ... definition does not exist" because the buffer list was given as bare names). Third run (buffer list as a COLLECTION of library cells, logical ECO): `fix_eco_timing -type hold -methods {insert_buffer} -buffer_list <collection> -hold_margin 0.05` proposed 109 `insert_buffer` commands (`dl01d1` 64, `dl02d1` 31, `buffd1` 12, `dl01d2` 2; area +2687.50 um2, about 0.6 percent of the cell area) and PrimeTime's memory then showed 0 hold violators, WNS +0.0002 ns (before: 263, -0.3468 ns). Insertion points are shared driver pins (e.g. `copt_h_inst_3080/Z`, `U46/Z`) and load pins (`dest_c_reg_reg_2_/D`); one delay cell fixes several endpoints.
- The probe's closing line said "0 changes proposed" (counter bug: it did not know the verb format); fix is part of task 079.
- Change files in `pnr_icc2/pt/`: `pt_eco_hold_changes.tcl` and `_icc2.tcl` (identical, "formatted for IC Compiler": `current_instance {x}` + `insert_buffer [get_pins {P}] <ref> -new_net_names {N} -new_cell_names {C}`), `pt_eco_hold_changes.txt`. PrimeTime-SI licence is available.
- Next: task 079 (a PrimeTime setup-ECO probe for `dma_addr[31]`, and the ICC2 script that applies the change lists with legal placement, protection of the antenna cells, an antenna-watch list and hard checks), then the whole chain again (fill, `pv`, DRC / antenna / LVS, PrimeTime setup + hold, post-layout simulation).

## 4. Tasks written today (Planning -> Execution)
| Task | What | State |
|---|---|---|
| 063 to 065 | `pnr_v2/` scripts with minimal edits, legacy-constraint synthesis, zero-margin goals | done, committed (`e3e7f2a`) |
| 066 | Calibre DRC/antenna/LVS control files and runbook | done, committed (`519ebfb`) |
| 067 | Step 4b pin re-placement | tried, PARKED (`2af2808`) |
| 068 | Port buffers at the pins (step 6c) | done (`2460320`) |
| 069 | Buffers on free filler sites, per-buffer checks, tier 2 | done (`3a6b2b3`) |
| 070 | Filler table instead of geometric query, reasons, diagnostic | done (`ed881de`) |
| 071 | Clock root inverter resize (step 6d) | done (`a221b3b`) |
| 072 | Timing closure pass (step 6e) | written (`c827159`); first server run stopped at `is_buffer` (design cells have no such attribute); fix written, not yet committed or run |
| 073 | `lvs.ctrl` + runbook update, LEF export fix and checks, hold-report scenario fix | written, not yet committed or run |

## 5. Decisions made today
- Accept the tool's pin placement and report the positions to the top-level team (user). Later we found the layout needed buffers because of it; the positions in `pins_floorplan.txt` are still what the team gets, but note the first run's `clk` was at the far end of the edge.
- Use the old constraints with no extra margin goals (setup/hold goals 0.0).
- No diodes; buffers at the pins and a bigger clock root instead (user).
- Keep the clock-root change although it makes hold worse (user): the hold residual goes into the timing pass 6e.
- Use the LVS deck's `FILTER_DWN2PSUB` (user approved, reason written).
- Commit only when the user says so; the parked task 059/062 files are not part of any commit.

## 6. Mistakes and corrections (so the story stays honest)
- I first quoted the antenna wire limits as 144 and 92 um; they are perimeter figures. The wire-length limits are about 72 um (M2/M3) and 46 um (top metal).
- I first called the pin order a defect; it was an open decision (D3), and the user had already chosen the tool placement.
- My first test for the ff corner used a max-delay report on a hold-only scenario; the corrected test (min delay) and `PVT-032` gave the evidence.
- The Calibre commands were first pasted into a bash terminal (csh syntax), and one `scp` was run on the server instead of the laptop. No data was affected.
- A `scp` of the 55-result antenna database was overwritten by later Calibre runs; the dlib backups made it unnecessary.
- The 071 polarity check reads `is_inverter` on a DESIGN cell, which does not exist (the log shows empty values). The reference check still holds; the check should read the library cell. A small fix is pending, low priority.

## 7. Tool facts learned (useful for the explanation)
- ICC2: `get_cells -intersect <rectangle>` returns cells crossing the rectangle border only; read all cells once and filter in Tcl.
- ICC2: `is_buffer`, `is_inverter` are library-cell attributes, not design-cell attributes; `get_timing_paths` has no `-quiet`; `report_clock_timing -through` cannot be combined with `-type transition`.
- ICC2: `legalize_placement -cells` never fails, it moves the cell as far as needed; always check the final position.
- ICC2: the second `place_pins` moves placed pins but does not honour the spacing constraint.
- Calibre antenna rule: ratio = polygon perimeter x layer weight (M2/M3 0.54, top metal 0.84) / gate area, limit 400; a diffusion of at least 0.202 um2 on the net switches to a lenient rule.
- Calibre LVS: the deck sets power names and some statements itself; a duplicate in our control file is an error. The well diode of the filler cells needs the deck's own filter switch.
- Licence: a transient licence-server outage (about 15 min) stopped ICC2 once; waiting fixed it.

## 8. Commits of the day
`e3e7f2a` (start), `519ebfb` (Calibre files, handoff 18.32), `2af2808` (4b), `2460320` (068), `3a6b2b3` (069), `ed881de` (070), `a221b3b` (071), `c827159` (072, handoff 18.33 and 18.34). The next commit holds task 073, the 072 fix and this log.

## 9. What comes next (in order)
1. (done) 6e timing closure, `metal_fill`, `pv`, DRC / antenna / LVS on the final layout: all clean.
2. PrimeTime sign-off with the SPEF (ss setup, ff hold) - the authority for the 0.4 ps hold residual.
3. Post-layout simulation with the SDF (the cell models have zero delay, so the SDF is what adds delays).
4. The PM message (port antenna handling, the netlist ECOs 6c/6d, the LEF, the pin list with the tool's positions, the die size), and the files for the top-level team.
5. The 0.40 ns clock-path transition limit of the example `cts.tcl` (454 entries after fill; not a course constraint): decide.
6. The `Final/` folder (user's idea) for frozen results and per-stage reports; the parked 059/062 files; round-3 bookkeeping; the small 071 polarity-check fix.
7. At the end: a full explanation of the day for the user, from this log.

## 10. How I would explain it (outline for the end)
1. What the design and flow are; why a clean slate. 2. Synthesis and what the numbers mean. 3. Why gate-level simulation is function-only. 4. The physical steps in order and what each produces. 5. What an antenna violation is and why input ports were the problem. 6. Why pin placement caused it, and what we tried (hopping, 4b, buffers, bigger root inverter). 7. What LVS checks and why the well diode needed a filter. 8. Why timing is the remaining issue and what the sign-off will be. 9. The tool traps we hit and how each was found.
