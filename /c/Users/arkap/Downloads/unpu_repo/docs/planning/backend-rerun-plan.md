# Back-end re-run plan (DRAFT v2, user decisions of 2026-11-01 applied, nothing dispatched to Execution)

Written by Planning, 2026-11-01. Facts come from `docs/session-handoff.md` 18.x (the first hand-run flow,
2026-10-28 to 2026-10-31). Items marked VERIFY are things I have not seen on the server and that must be
read from `-help` or a log before they are relied on.

User decisions recorded 2026-11-01:
- Hold uncertainty back to **0.5 ns** (the value in `constraints/unpu_top.sdc`; the file labels it an
  assumption, the user chose it as the original constraint). The die may change, so it grows to keep utilisation.
- **`adiode` is not used** (user: its `dont_use` cannot be overridden). Step 0 (diode on the old layout) is dropped.
- Pin order may be chosen by the tool; sides and layers stay as given (APB right, DMA top, power bottom).
- Start the re-run.

## 1. Why re-run, and what it has to achieve

The first run closed DRC (Calibre 404 rules, 0) and the ICC2 checks, but left one antenna failure (18.27).
Causes found, and the change that answers each:

| Cause in the first run | Change in the re-run |
|---|---|
| Pins fixed at computed slots BEFORE placement: `paddr[4]` sits 180 um from its load cell | Place pins AFTER a coarse placement (`place_pins -self`), sides and layers unchanged |
| Input ports have no diffusion inside the macro; ICC2 skips the 80 port nets (`ZRT-311`) | Make ICC2 analyse port nets (port external-antenna options, VERIFY); if Calibre still fails a port net, split the long wire with a buffer placed in the MIDDLE of the run (not at the pin): each half then carries half the metal per gate. A buffer's output drain is NOT assumed to count as a diode (see 2.3) |
| No antenna rule while routing (`ZRT-309`): the router fixed nothing; 241 violations found afterwards | Define the antenna rule BEFORE `route_auto`, with a margin |
| `adiode` unusable (`dont_use`, cannot be overridden) | Not used; see the port-net row above |
| About 90 typed commands, some wrong (power-pin loop, stale frames, wrong block names) | One scripted, parameterised, logged flow in `pnr/` |
| LVS, PrimeTime and simulation all left to the end | Run them on the routed design as an early gate |
| Hold at 0.5 ns left 6 endpoints at -0.0125 ns and `FLW-8004` (unexplained) | See C2: read the stage log, follow with `route_opt`, report what remains |

Acceptance of the re-run (on the FINAL files): Calibre DRC 0, Calibre antenna 0, Calibre LVS clean,
PrimeTime setup met at ss and hold met at ff (any residual recorded and decided in writing), post-layout
gate-level simulation passes, and the flow reproduces from a clean directory with one command.

## 2. Specifications and constraints

### 2.1 Unchanged (hard constraints)

- RTL frozen (SystemVerilog, 4x4 INT8 weight-stationary, 32-bit accumulator, single-stage PE). Timing contract
  untouched: back-end only, no RTL or synthesis change.
- Input netlist `syn/out/pm_flow/unpu_top_cn.dc.v` and `unpu_top_cn.sdc` (from `constraints/pm_unpu_top.sdc`):
  period 20 ns (50 MHz); setup uncertainty 1.5 ns; output load 1 pF; input driver `buffd1`; clock transition
  0.6 ns (ideal clock only); APB input/output budgets 35%/35%, DMA 40%/40%, `rst_n` 40%; `IN_MIN_DELAY` 0.0,
  `OUT_MIN_DELAY` -0.5. Only the period and the 1 pF load are facts; the rest are assumptions pending the SoC
  team. No value changes without a written reason and the user's approval.
- Process: SCL 180 nm, 4 metals (M1, M2, M3, TOP_M), ss 1.62 V/125 C for setup, ff 1.98 V/-40 C for hold, typical
  TLUPlus only. Scenarios `default` (ss, setup) and `ff_hold` (ff, hold).
- Kit files are read-only; work on copies. Don't-use stays (`slnht*`, `skbrb*`, `slbhb*`, `slnhn*`, `slnln*`,
  `mx08d*`, plus the library-flagged `adiode`, `bh01d1`, `cload1`). No pads, no I/O ring, clock tree built inside
  the macro, 10 um halo kept by the top level (instructor).
- Working rules: nothing fails silently; nothing hardcoded (every number a script parameter); tool versions and
  parameters in a run manifest; no threshold narrowed and no constraint tuned to close timing without a written
  reason and the user's approval.

### 2.2 Changed or new

| Item | First run | Re-run |
|---|---|---|
| Hold uncertainty (`ff_hold`) | 0.5 in the SDC, 0.2 applied from CTS on | **0.5 ns** (script parameter `HOLD_UNCERT`, default 0.5) |
| Die and core | 817.6 um die, 806.4 um core, 144 rows, 66.0% (at 0.2 ns hold) | **868.0 um die, 856.8 um core, 153 rows, core 734,106.24 um2**; 484,572 um2 of cells (the 0.5 ns run) gives 66.0% |
| Floorplan command | `-boundary {{5.6 5.6} {812.0 812.0}} -core_offset 5.6` | `-boundary {{5.6 5.6} {862.4 862.4}} -core_offset 5.6` (parameter D = 868.0) |
| Pin positions | fixed slots, pitch 6.72, ascending order, set before placement | tool-chosen order via `place_pins -self` after a coarse placement; same sides and layers, width 0.28 um, length 1.0 um, pitch at least 6.72 um |
| Pin sides and layers | right: APB + `clk` + `rst_n`, M3; top: DMA, M2; power planned left, moved to the bottom after routing | right: same; top: same; bottom: `VDD`/`VSS` on TOP_M; left: none. `clk` is also tool-placed (user, 2026-11-01), on the right edge; the top-level answer of 2026-10-28 asked for it near the middle in a gap between buses, so the top level and the PM (Q14, clock latency and skew at `clk`) must be told where it lands |
| Power pins | added after routing by hand (duplicate terminal) | created with the power grid: stripes extended to the bottom boundary, one terminal per stripe (14 in the first run; the count may differ on the larger die) |
| Antenna | rule defined after routing; port nets skipped | rule defined before `route_auto`: mode 4, diode mode 1, cut ratio 0, metal ratio 300 on all layers (Calibre limit stays 400); port nets analysed (VERIFY); mid-run buffer only as a measured last resort |
| Library, directory | `unpu_lib` in `icc2_work`; the filler library was built later as a second NDM | new library `unpu2_lib` in `icc2_work_v2`; the NDM(s) are regenerated by `ndm_file_gen.tcl` with the three filler cells (`feedth*`, typed filler) included at generation time |
| Fillers | last step, then `connect_pg_net -automatic` | same; never followed by `route_opt` |
| GDS, LEF | `-units 1000`; `write_lef -design <block>` | same; the `GDS-017` line-8 problem is investigated in A3 |

A bigger die changes the macro footprint: the top-level team and the owner of the dummy LEF (817.6 um) must be
told before delivery. The user stated the area is allowed to change.

### 2.3 Recommendations on the open points (for the user to confirm)

- D3 ICC2 antenna ratio 300 against Calibre's 400. Reason: ICC2 and Calibre agreed within about 2% on M2/M3
  (395 against 402) and the top-metal weight (Calibre 0.84 against 0.54) is unverified in ICC2. Stricter only.
- D4 (diode) is moot. If mid-run buffers prove insufficient, the cheap probe is `create_cell` with `adiode`
  (the `dont_use` flag may only bind the optimiser, not an explicit instance); the user says no, so it stays
  a last resort.
- D5 (Step 0) dropped.
- D6 Execution writes the `pnr/` scripts after the user approves this plan; the user runs them on the server
  and reads the logs, as before.
- Port buffers (corrected 2026-11-01): a buffer does not shorten the route. It helps only by splitting one long
  net into two, so each gate sees only the metal of its own net, and the buffer must sit in the middle of the
  run to halve it. A buffer at the pin does NOT help unless its output drain counts as a diode in Calibre, and the
  evidence says it may not (an inference, not a test): `AN.MTL.1.*` is by definition the no-diode rule, and it
  flagged `N48`, `N69` and `n472`, internal nets that have a cell driver (driver types not looked up); the other
  241 first-run failures were not examined one by one, and some may be port nets. So no upfront buffers. The tolerance a
  wire has is L_max = ratio x gate_area / (2 x weight), weight 0.54 (seen in the deck for M2; M1 and M3 assumed equal, VERIFY in the deck) or 0.84 (top metal, seen); with ratio 300:
  gate 0.108 um2 gives 30 um on M2 and 19 um on the top metal; 0.1692 gives 47 and 30 um; 0.1944 gives 54 and
  35 um. The script reports, per input port, the estimated ratio 2 x (HPWL x 1.2) x 0.84 / (sum of load gate
  areas) so the long ports are known before routing; no cell is added from it.
- Build order of runs: one baseline run at 0.5 ns and 868.0 um. The old 0.2 ns result is the comparison.

## 3. The flow, step by step

Every step ends with a saved checkpoint block, a log file and pass criteria. Nothing moves on if a criterion
fails: the failure is recorded and brought to the user.

### Stage A: preparation

- A1 One script per stage in `pnr/` (user decision 2026-11-01), written by Execution one task at a time
  (tasks 038 onward), each inspected by Planning before the next is sent: `params.tcl` and `common.tcl` (shared),
  `ndm_file_gen.tcl` and `ndm_check.tcl` (library generation, fillers INCLUDED at generation time), `design_setup.tcl`,
  `floorplan.tcl`, `power.tcl`, `pin_place.tcl`, `placement.tcl`, `cts.tcl`, `route.tcl`, `fill.tcl`, `outputs.tcl`,
  then the Calibre and PrimeTime scripts. One parameter file (die, offset, `HOLD_UNCERT`, `ANT_RATIO`, pin pitch,
  HPWL detour factor, paths, names). A manifest per stage: tool versions, parameters, git commit of the scripts,
  checksum of netlist and SDC.
- A2 Regression: with the OLD parameters (die 817.6, fixed pin slots, hold 0.2) the script must
  reproduce 18.14 to 18.16: core 650,280.96 um2, 144 rows, 66.00%, area after `place_opt` 426,097.72 um2, setup
  WNS 0.0000. Same numbers proves the script is faithful and the flow deterministic. Otherwise investigate first.
- A3 GDS layer map: read `icc_gds_out_4LM.map` lines 1 to 15, find why line 8 (first `T` line) is rejected, decide
  whether a corrected COPY is needed so pin labels land where Calibre LVS expects. Judge: LVS in stage E.
- A4 Read `-help` of `place_pins`, `create_placement`, `insert_buffer`, and the app options
  `route.detail.default_port_external_*` and `route.detail.port_antenna_mode`. Record in the handoff.

### Stage B: floorplan, power, pins, placement

- B1 Library `unpu2_lib`, TLUPlus `typ`, netlist, link, SDC, corner `ff`, scenario `ff_hold`, status, parasitic
  parameters (as 18.11 to 18.13). Pass: 204 ports, 2,465 sequential cells, `check_timing` only warns on `pready`.
- B2 Floorplan with D = 868.0. Pass: boundary {0 0}{868 868}, 153 rows, core 734,106.24 um2.
- B3 Don't-use (18 cells), power nets, `connect_pg_net -automatic`, grid (M1 rails 0.74 um, TOP_M vertical stripes
  2.24 um, pitch 112 um, interleaved), stripes extended to the bottom boundary with their terminals. Pass:
  `check_pg_drc` 0, terminals equal to the number of stripes, none duplicated; record the stripe count.
- B4 Coarse placement with no final pins (`create_placement` or the first `place_opt` stage; VERIFY), pin
  constraints for sides, layers, width, length and pitch, `place_pins -self` with `clk` constrained to the right edge and M3 only. Pass: 204 signal pins on the right
  side and layer (`clk` on the right edge, M3), pitch at least 6.72 um, none on left or bottom.
- B5 `place_opt` from the pin-aware placement. Pass: legality 0, setup WNS 0, max transition/capacitance 0,
  `check_pg_connectivity` 0 floating.
- B6 Report only: for every input port, HPWL, sum of load gate areas (library pins; VERIFY the attribute name; the
  first run's ICC2 gate areas matched Calibre's for flop D pins, 0.169) and the estimated ratio of section 2.3.
  No cells are added. Pass: the list is written and the worst ports are visible. Checkpoint `placed`.

### Stage C: clock tree and hold at 0.5 ns

- C1 `set_lib_cell_purpose -exclude cts [get_lib_cells {*/dl*}]`, `clock_opt -to build_clock`. Record sinks (2,465),
  levels, repeaters, latency and skew (first run: ss 1.22 / 0.95 ns, ff 0.49 / 0.36 ns).
- C2 `set_clock_uncertainty -hold 0.5` in `ff_hold`, `clock_opt -from route_clock -to final_opto`. Then READ the
  log of the stage: `FLW-8004` ("Incomplete final_opto") appeared in both earlier runs and may be why 6 hold
  endpoints stayed (first 0.5 ns run: worst -0.0125 ns, four self-loops in `u_wbuf` and two neighbouring-PE
  shifts). Hypothesis, not tested: `route_opt` (which fixed the last hold endpoints in the 0.2 ns run) clears
  them. If hold violations remain after `route_opt`: list endpoints, try the hold-effort options (VERIFY from
  `-help`) and a CTS skew experiment, and if it still does not close bring it to the user (accept the residual
  with a written reason, or return to 0.2 ns with a written reason). Never narrow silently.
  Pass target: setup and hold NSV/NHV 0, legality 0; record area (expect about 485,000 um2) and utilisation (66%).

### Stage D: routing with the antenna rule on

- D1 Before routing: `define_antenna_rule -mode 4 -diode_mode 1 -metal_ratio $ANT_RATIO -cut_ratio 0`;
  `route.detail.antenna true`; port external-antenna options as read in A4. Print the active rule.
- D2 `route_auto`, `route_opt`. Pass: `check_routes` 0 DRC / 0 opens / antenna 0; `check_lvs` 0 shorts and opens;
  legality 0; `check_pg_connectivity` 0; setup and hold met in both scenarios. Checkpoint `routed` (unfilled,
  untouched; the fallback for every later failure).

### Stage E: fill, outputs, early signoff gate

- E1 `create_stdcell_fillers ... -rules post_route_auto_delete`, `connect_pg_net -automatic`, checks, save `final`.
  A sub-picosecond hold residual (as 18.22) is recorded and, per the decision of 2026-10-29, left to PrimeTime.
- E2 Outputs to a numbered folder from the FINAL block: `create_frame -block_all true`, `write_lef -design <final>
  -include cell` (one MACRO, `grep -c`), netlists, SPEF/SDF/SDC for both corners, GDS `-units 1000` merged with the
  standard-cell GDS.
- E3 Calibre in a new run folder (reuse the control files `drc.ctrl` and `ant.ctrl` with the GDS path changed; the DRC `3V` voltage option stays an open assumption, BLOCK mode only): DRC (404 rules), antenna (16 rules), LVS (first time: `v2lvs` of
  `unpu_top_lvs.v` against the kit CDL; the 129 tie-to-VSS pins and the pin labels must be accepted). Pass: all
  three clean. Antenna fix loop, at most three rounds, scripted: Calibre names the net; split that net with a buffer in the middle
  of its run, or re-route it on a higher layer, on the unfilled `routed` block, `route_eco`, re-check, re-fill, re-output, re-run Calibre.
  Any other failure: back to `routed`, never patch the filled block.
- E4 PrimeTime with the extracted SPEF and SDC: ss setup, ff hold. Pass: both met, or the residual decided in
  writing.

### Stage F: closing

- F1 Post-layout gate-level simulation with `unpu_top_sim.v` plus the SDF (the netlist differs from DC's because
  `place_opt` merged cells). Pass: the top-level testbench passes at both corners.
- F2 Deliver LEF, GDS, Verilog, SDC, SPEF; tell the top-level team the new die size (868.0 um), pin positions and
  bottom power pins. PM: macro `.lib` and dummy fill still open.
- F3 Update `docs/session-handoff.md` and `plan.md`; commit and push after each stage.

## 4. Experiments X1 to X5, only after the baseline passes

- X1 Comparison run at 0.2 ns on 817.6 um (the old result) if a before/after is wanted for the report.
- X2 CTS skew: the first tree had 0.95 ns skew at ss without effort; matters most for closing hold at 0.5.
- X3 Higher utilisation: not recommended (first-run congestion 36 to 40% average, local peaks above 100%).
- X4 Calibre dummy fill (`DUMMY.header`), only if the PM says the deliverable includes it.
- X5 Re-synthesis to drop the about 124 row-0 adder cells that compute B+0+0 and the 129 tie-to-rail pins: needs a
  PM decision and a new DC run; out of scope.

## 5. Risks and fallbacks

| Risk | Fallback |
|---|---|
| Hold at 0.5 ns does not close | C2 ladder: log, `route_opt`, hold-effort options, CTS skew; then the user decides (residual accepted in writing, or 0.2 ns with a written reason) |
| `place_pins -self` cannot satisfy side, layer or pitch | compute the pin order from the coarse placement in a script and use `set_individual_pin_constraints` with locations, as in the first run |
| Mid-run buffer command unusable or the optimiser removes the buffer | `create_cell` plus connect, `dont_touch`; insert after `place_opt` |
| A buffer drain does count as a diode in Calibre | then a buffer at the pin is also enough; test on the first failing net |
| Antenna still fails on a port net | the E3 loop; last resort an explicit `adiode` instance (user says it cannot be used) or moving that pin |
| ICC2 antenna margin lengthens routes and hurts setup | report the effect; the margin may move toward 350, never above 400 |
| Hold residual from fill reappears | same decision as before: PrimeTime judges |
| Bigger die breaks top-level assumptions | the dummy LEF owner regenerates from our LEF; ask before delivery |
| LVS fails on labels or ties | fix on `routed`; A3 comes first |
| Right-edge M3 pins snap to the tech-file pitch 0.61 um while the kit LEF says 0.84 um (open since 18.14) | tell the dummy-LEF owner and the top level with the delivery; not blocking |
| Antenna on a 180 um-class run cannot be fixed by layer hopping alone (one layer tolerates about 19 to 54 um at ratio 300) | pin placement near the loads is the main fix; the E3 loop handles the rest |

## 6. Effort (estimate, not measured)

Tool runtime for the whole flow is short (first run: `place_opt` 133 s, route about 1 min, `route_opt` 45 s, Calibre DRC
45 s, antenna 5 s). The cost is writing and debugging the scripts (A1 to A4) and LVS, which has never been run:
one to two working days plus the stage gates. The first run took four days of hand work.

## 7. Not in this plan

RTL, synthesis, the timing contract, new interface budgets, the PM's open questions beyond those named above,
formal equivalence, IR drop.
