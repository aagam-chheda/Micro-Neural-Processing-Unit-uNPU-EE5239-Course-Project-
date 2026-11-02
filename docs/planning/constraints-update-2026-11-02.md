# Constraint update from the instructor's guidance (DRAFT for the user's decisions, 2026-11-02)

Source: `docs/planning/instructor-guidance-2026-10-27.md` (verbatim). The user's rule: **take the most pessimistic value the guidance allows.**
Nothing in `constraints/`, `syn/` or `pnr/` has been changed yet; this document says what would change and why, and asks three questions
(section 6). After the answers, the work goes to Execution as tasks (section 8). Execution owns `constraints/`, Planning does not edit it.

## 1. What changes, in one table

| Item | Now (our own HARSH assumptions) | New (instructor, most pessimistic end) | Direction |
|---|---|---|---|
| Clock period, synthesis | 20 ns | **16 ns** (range 16-18); must also meet at the real 20 ns | tighter |
| Clock period, placement and CTS | 20 ns | **18 ns** (range 18-19) | tighter |
| Clock period, route and signoff | 20 ns | 20 ns | same |
| Jitter used in the uncertainty | 0.5 ns | **200 ps** (range 150-200) | smaller |
| Setup uncertainty, before CTS (synthesis, placement) | 1.5 ns | **1.2 ns** (200 jitter + 600 skew + 400 margin) | smaller |
| Setup uncertainty, after CTS, route, signoff | 1.5 ns | **0.6 ns** (200 + 400) | smaller |
| Hold uncertainty, all stages | 0.5 ns (0.2 ns was used from CTS on) | **0.05 ns** | **much smaller** |
| APB inputs `pwdata pwrite psel penable`, max delay | 35% T | **70% T** | tighter |
| APB input `paddr` and output `prdata` (the combinational read path) | 35% / 35% | 35% / 35% (the guidance's feedthrough row) | same |
| DMA inputs `dma_rdata dma_ready`, max delay | 40% T | **70% T** | tighter |
| DMA outputs, max delay | 40% T | **70% T** | tighter |
| `rst_n`, max delay | 40% T | 70% T, still TIMED (see Q2) | tighter |
| Input min delay | 0.0 ns | **5% T** | looser |
| Output min delay | -0.5 ns | **0 ns** | looser |
| Setup WNS target per stage | 0 everywhere (our checks) | placement >= -1.0 ns, CTS >= -0.4 ns, route >= 0, signoff >= 0 | looser early |
| Hold target | 0 from CTS on | CTS: small violations OK; route >= 0; signoff >= 0 | same at the end |
| Floorplan start utilisation | 66% at the 0.2 ns hold run | **60%** (range 60-70) | lower |
| Utilisation limits | none | placement <= 75%, route <= 80% (range 80-85), congestion overflow <= 1% (range 1-2) | new checks |
| Netlist growth to budget | not planned | 20% (range 10-20) | new |

Unchanged: input driver `buffd1`, 0.2 pF input wire load, 1 pF output load (the instructor's own value), max transition 3.0 ns (library limit),
max capacitance 2.0 pF, clock transition 0.6 ns (ideal clock only).

## 2. How "most pessimistic" was applied

- A range: the end that leaves the design LESS time or LESS hold margin (period 16 not 18; jitter 200 not 150; I/O delay 70 not 60; input min delay 5%
  not 10%; output min delay 0 not 5%; WNS target -0.4 not -0.6; utilisation 60 not 70 and limit 80 not 85, because lower utilisation and a lower limit are the
  safer side for routability).
- A single value: used as given (hold uncertainty 50 ps; the stage uncertainty sums).
- A choice between rows: the row that fits the real path. The read path `paddr -> prdata` has no flop in it (checked in `rtl/unpu_csr.sv`: `csr_rdata` is a
  combinational function of `csr_sel = paddr[11:2]`; `unpu_apb.sv` is pure glue), so it is the guidance's "feedthrough" row, 35% each. Using 70% on both
  ends would leave a negative budget: 140% of the period.
- Where our own earlier value was already more pessimistic than the instructor's range (input min delay 0.0, output min delay -0.5, hold uncertainty 0.5 ns, setup
  uncertainty 1.5 ns), the INSTRUCTOR'S value wins because the instruction is to follow the guidance and those numbers were my labelled assumptions
  ("HARSH ASSUMPTION" in the SDC). That loosens four numbers and is the part that needs your decision (Q1).

## 3. Stage profiles

Every I/O delay below is a percentage of the period OF THE STAGE (the guidance says "share of the clock period T").

| Profile | Used in | Period T | Setup uncertainty | Hold uncertainty |
|---|---|---|---|---|
| `syn20` | synthesis, mandatory | 20 ns | 1.2 ns | 0.05 ns |
| `syn18` | synthesis, tighter | 18 ns | 1.2 ns | 0.05 ns |
| `syn16` | synthesis, tightest (target) | 16 ns | 1.2 ns | 0.05 ns |
| `place` | `place_opt` (ideal clock) | 18 ns | 1.2 ns | 0.05 ns |
| `cts` | `clock_opt` | 18 ns | 0.6 ns | 0.05 ns |
| `route` | `route_auto`, `route_opt`, fill, outputs | 20 ns | 0.6 ns | 0.05 ns |
| `signoff` | PrimeTime (ss setup, ff hold), simulation | 20 ns | 0.6 ns | 0.05 ns |

Notes: the guidance offers "5-10% tighter OR +1-2 ns uncertainty" for placement/CTS; I took the tighter period (18 ns) and did NOT stack +2 ns on top, because the
two are alternatives. If you want both, say so.

## 4. I/O delay table (max, as % of T; min as given)

| Port group | Facts from the RTL | Rule used | Max delay | Min delay |
|---|---|---|---|---|
| `paddr[11:2]` | feeds the combinational read mux (-> `prdata`) AND the write decode (-> flops) | feedthrough row | 35% | 5% T |
| `pwdata[*] pwrite psel penable` | only into flops (`csr_wen` gates on `psel && penable && pwrite`) | neighbour unknown -> "logic at the port" | 70% | 5% T |
| `prdata[*]` | combinational from `paddr` | feedthrough row | 35% | 0 |
| `pready` | tied to 1, constant, nothing to time | same as `prdata` | 35% | 0 |
| `dma_rdata[*] dma_ready` | into flops (`stage`, `state`) | logic at the port | 70% | 5% T |
| `dma_addr dma_wdata dma_wstrb dma_valid` | from flops through combinational selects (a 16-to-1 pick of `c_src[cur_m][cur_j]` for `dma_wdata`) | logic at the port | 70% | 0 |
| `rst_n` | asynchronous clear of the flops | see Q2 | 70% | 5% T |
| `paddr[31:12]`, `paddr[1:0]` | unused (no load) | nothing to time | follow `paddr` | - |

A caveat that the budgets make visible: at 70% on the DMA outputs our side has 30% of T. At 16 ns that is 4.8 ns minus 1.2 ns of uncertainty = 3.6 ns
for flop clock-to-Q, the select logic and an output buffer into 1 pF (about 0.64 ns). It may be tight at `syn16`. The guidance says only "ideally" for
16-18 ns, so `syn20` is the pass/fail, `syn16` is reported.

Feedthrough budget by profile (period x 30% minus setup uncertainty), against the 4.49 ns that the present path needs (round 3, already sized to just fit 4.5 ns):

| Profile | Budget | Verdict |
|---|---|---|
| `syn20` | 6.0 - 1.2 = 4.8 ns | fits (+0.3) |
| `syn18` | 5.4 - 1.2 = 4.2 ns | needs sizing; unknown |
| `syn16` | 4.8 - 1.2 = 3.6 ns | needs sizing; may not fit |
| `place` | 5.4 - 1.2 = 4.2 ns | as `syn18`, plus wire delay |
| `cts` | 5.4 - 0.6 = 4.8 ns | fits on paper |
| `route`, `signoff` | 6.0 - 0.6 = 5.4 ns | fits (+0.9) |

The path is input driver (`buffd1` into 0.2 pF) 1.07 ns + about 2 ns of decode + output buffer 0.64 ns: only the gates between can shrink.

## 5. What the new numbers do to the flow

1. **One constraint source, stage-selectable.** Today ICC2 reads the SDC that DC wrote (period 20 ns, 1.5 ns, 0.5 ns baked in). With stage periods the
   flow must apply a stage profile at the START of each stage script (synthesis, `place_opt`, `clock_opt`, route): re-read the parameterised SDC with that stage's
   numbers, in both scenarios, then keep the ff operating condition. This replaces `HOLD_UNCERT` in `cts.tcl` (it becomes part of the profile) and removes the
   reliance on `unpu_top_cn.sdc`.
2. **Checks per stage, not zero everywhere.** `placement.tcl`: setup WNS >= -1.0 ns; `cts.tcl`: >= -0.4 ns, hold violations allowed (route_opt fixes); `route.tcl`:
   setup >= 0 and hold >= 0; PrimeTime: both >= 0. The present checks count violating endpoints == 0 at placement and CTS, which would fail the tightened `place` profile
   for no real reason. WNS thresholds become parameters per stage, the "or >= -200 ps if a PrimeTime ECO follows" is NOT used.
3. **Hold buffers.** The guidance says to watch the hold buffer count after `final_opto` and `route_opt`: both scripts must report the number of delay cells added
   and the area change. With 50 ps instead of 0.5 ns the +13% area seen at 0.5 ns should not appear.
4. **Synthesis is repeated at three periods** (`syn20` mandatory, `syn18`, `syn16`), each with its own reports; the netlist that goes forward is the one from `syn16`
   if it meets timing at 20 ns and at 16 ns, otherwise the best one that meets 20 ns; the choice is yours.
5. **Die size from the NEW cell area.** Start utilisation 60%, growth budget 20%: core area = cell area / 0.60 (rounded to whole rows and sites), and the
   post-growth utilisation 1.2 x 60% = 72% stays under the 75% placement and 80% route limits. The 868.0 um die was sized for the 0.5 ns hold run (484,572 um2);
   the new die follows the new synthesis area. New checks: utilisation after `place_opt` <= 75%, after CTS and route <= 80%, congestion overflow after placement <= 1%
   (`report_congestion`, VERIFY the command; it was not in the help probe).
6. **Expected counts change**: flops stay 2,465 if the RTL is unchanged; ports 204; leaf cells, modules and area change with the new netlist. `params.tcl` expectations
   (`EXPECT_LEAF_CELLS`, `EXPECT_NETLIST_MODULES`, the filler arithmetic) are re-derived from the new synthesis, never copied.
7. **Antenna and pins**: unchanged (ratio 300, pins placed by the tool). Reset and diodes: unchanged.
8. **The server work of 2026-11-01 is not lost**: the scripts, the NDM, the parsers fixed on real text all stay. What is thrown away are layouts from the old constraints,
   and those never existed in the scripted flow (the scripted `design_setup` onward has not run yet).

## 6. Questions for the user (the answers change numbers)

- **Q1, hold uncertainty.** The guidance says 50 ps at every stage. You told me earlier to keep 0.5 ns "because that was the original constraint". Taking the
  guidance means 0.05 ns. Recommended: 0.05 ns.
- **Q2, `rst_n`.** The guidance says asynchronous IO such as resets should not be timed with I/O delays but with a synchroniser and `set_false_path`/`set_max_delay`.
  Our macro has no synchroniser inside (the RTL is frozen) and the top level drives `rst_n` synchronously; our SDC deliberately keeps the release timed so that
  recovery/removal checks exist. Recommended: keep it TIMED at 70% (the stricter reading, consistent with "most pessimistic").
- **Q3, `paddr`.** One port has two kinds of path: to `prdata` (feedthrough, 35%) and to flops (write decode). One input delay per port applies to both. Recommended:
  35% for `paddr[11:2]` (simple, one delay). The alternative is a second, virtual clock that carries 70% for the flop paths and a false path between the virtual and the
  real output, which is exact but complicated and needs care in ICC2 and PrimeTime.

## 7. Risks

- The feedthrough budget at `syn16` and `place` may not close; the guidance allows it ("ideally").
- A 50 ps hold uncertainty is thin against a real post-CTS skew of 0.36 ns (ff) seen in the first run: hold closure depends on `route_opt` fixing it, and signoff in
  PrimeTime may differ from ICC2. This is the instructor's number; the area saving is large.
- Synthesising at 16 ns usually costs area; the die is sized from the result.
- The DMA output paths after flops include a 16:1 select; at 70% they are the most likely reg-to-output violators.

## 8. Tasks that follow the answers (not written yet)

1. `constraints/`: stage-parameterised SDC (one file, profile table in one place, the two twins kept in step), with a self-test that prints the numbers of every profile.
2. DC scripts: run at `syn20`, `syn18`, `syn16`; reports per run (`docs/planning/synthesis-reports/` layout), pre-layout simulation of the chosen netlist.
3. `pnr/`: stage profile applied at the start of each stage script; per-stage WNS thresholds; hold-buffer and area reporting; utilisation and congestion checks; die size
   computed from the synthesis area; `params.tcl` expectations from the new netlist.
4. Re-run the flow from `ndm_file_gen` (the NDM stays valid) through `outputs`, then Calibre and PrimeTime as planned.

## 9. Decisions (user, 2026-11-02)

- Q1 hold uncertainty: **0.05 ns at every stage** (the instructor's value). The earlier 0.5 ns decision is superseded.
- Q2 `rst_n`: **timed at 70%**, no false path (recovery/removal checks stay).
- Q3 `paddr`: **35% for `paddr[*]`** (feedthrough row), one input delay; no virtual clock.
- Everything else as in sections 1 to 5 (most pessimistic end of every range).
