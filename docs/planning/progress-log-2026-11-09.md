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
| PrimeTime sign-off | not started | |
| Post-layout simulation | not started | |
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
