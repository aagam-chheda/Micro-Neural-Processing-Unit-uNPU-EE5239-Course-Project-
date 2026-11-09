# Restart plan for 2026-11-10: the whole flow again, knowing what 2026-11-09 taught us

Decision (user, 2026-11-09, late evening): redo the whole process from synthesis tomorrow morning, with the lessons below built in. Planning stands by until then. Nothing on the server is running.

## 1. State left behind (do not lose it)

- Repo at `0316327` (+ uncommitted: this file, progress log 3.14). Server clone `/storage/EE5239G1/aagams_workspace2/unpu`, workspace `pnr_icc2/`.
- The 2026-11-09 result is a COMPLETE, physically clean layout (DRC 404 rules 0, antenna 16 rules 0, LVS CORRECT after the deck's `FILTER_DWN2PSUB`), exported (GDS, LEF with one `MACRO unpu_top`, netlists, SPEF, SDF 3.0, SDC). Its sign-off state: ICC2 says setup +0.0143 / hold -0.0004; PrimeTime says setup -0.2423 ns (1 endpoint, `dma_addr[31]`), hold -0.3468 ns (263 endpoints, input-to-register). Library backups in `pnr_icc2/blocks/`: `unpu_top.dlib` (= pre-ECO state, same as `bak_pre_pteco`), `bak_pre_buffers`, `bak_pre_clkroot`, `bak_pre_closure`, `bak_post_closure1`, `closure3_worse`, `pteco_try1`. KEEP this run as the fallback: copy `pnr_icc2` to `pnr_icc2_run1` before anything new is written (see 4).
- In Execution's queue: a DRC clean-up loop for `pt_eco_apply.tcl` (task 081 follow-up). Harmless; it is not needed by the restart unless the ECO path is used again.
- Open and NOT done: the PM message (draft exists in the conversation: clock-latency convention, 0.40 ns clock-path limit), the `Final/` folder, the parked 059/062 files, the 071 polarity-check fix, the user's decision on the 150 clock-path `0.40 ns` entries.

## 2. What stays (reusable as is)

`pnr_v2/` scripts (NDM build, design setup, floorplan, power, placement, CTS, route, fill, `pv.tcl` with its LEF and SDF checks), `pnr_v2/calibre/` (control files, runbook, `lvs.ctrl` with the approved filter), `pnr_v2/pt/` (setup/hold sign-off scripts with annotation, clock-propagation and check_timing logic, violation CSVs, ECO probe with the in2out cone), `pnr_v2/sim/` (post-layout simulation, bounded SDF warning acceptance), `pnr_v2/pt_eco_apply.tcl`, `antenna_port_buffers.tcl`, `antenna_clk_root.tcl`, `timing_closure.tcl` (only if needed again), `constraints/legacy/` (synthesis), `syn/RUNBOOK_legacy.md`. The tool traps found (see progress log section 7 and 3.x) are written into the scripts.

## 3. Lessons -> concrete changes to decide tomorrow (each needs the user's yes/no)

| # | Lesson (2026-11-09 evidence) | Change in the new run | Where | Cost / risk |
|---|---|---|---|---|
| L1 | PrimeTime measures I/O at the clk PIN with zero latency; ICC2 gave the outside the macro's insertion delay. Output setup lost 0.92 ns (`dma_addr[31]` -0.24), input hold needed +0.4 ns (263 endpoints, -0.35). | Make ICC2's optimisation see what PrimeTime sees. First find out whether ICC2 has an option for it (search `all_appopts.txt`, `help set_clock_latency`, `set_latency_adjustment_options`); otherwise give the optimiser margins on the I/O paths only (an ICC2-optimisation-only margin, restored afterwards) with a written reason. Ask the PM the convention question (draft ready) in parallel. | CTS/route scripts (`cts.tcl`, `route.tcl`, `timing_closure.tcl`) | needs approval if it is a margin; research cost small |
| L2 | The clock insertion delay (0.4 ns ff, 0.9 ns ss) is what hurts both. | Ask CTS for a smaller insertion delay (fewer levels / stronger buffers), report latency and skew at CTS; compare with the 0.59 ns / 0.31 ns of run 1. | `cts.tcl` | tool-option research |
| L3 | 16 input-port nets failed Calibre antenna because pins were placed BEFORE cells and spread over the whole edge (wires 130 to 478 um; limit about 72 um M2/M3, 46 um top metal). No diodes allowed. | Buffer every input port at the start: either in synthesis (DC port buffering / `set_isolate_ports`-style, check what the library allows) or as the first ICC2 step (a buffer cell placed at the pin). AND/OR place the pins AFTER placement with the 8 um spacing honoured (the second `place_pins` ignored the spacing in task 067: find the right way, e.g. set the pin constraints again before the second call). The clock port needs a root cell with enough input gate area (run 1: `inv0d4`). | synthesis script / `placement.tcl` / pins | medium |
| L4 | `get_cells -intersect <rect>` returns only cells crossing the border; `is_buffer` is a library-cell attribute; `legalize_placement -cells` moves cells as far as needed; killing the `icc2_shell` wrapper does not stop `icc2_exec`. | Already in the scripts; keep the notes in the runbooks. | - | none |
| L5 | PrimeTime was run LAST and found 264 violations at the end. | Run PrimeTime (setup ss + hold ff, scripts exist) right after CTS and again after route, before fill; fix there. Run Calibre DRC/antenna right after route as well. | runbooks | none |
| L6 | The hold ECO of PrimeTime (single corner) broke the read-mux setup; the cone protection (cells AND nets) fixed it. | If an ECO is still needed: use the cone-protected probe, the count file, the apply script with the in2out gate. | - | already built |
| L7 | The example `cts.tcl` carries `set_max_transition 0.40 -clock_path` into the SDC: 150 PrimeTime entries, 454 in ICC2 after fill. | Decide at the start: keep as a target and meet it in CTS, or drop it from the exported SDC with the PM's answer. | `cts.tcl`, `pv.tcl` | needs a decision |
| L8 | Synthesis: the DMA address adder (ripple carry, 12 `ah01d1` stages) and the 1.0 pF output load put `dma_addr[31]` at the limit once the clock latency counts. | Re-run DC with the same legacy constraints but check the output paths with a latency allowance (a report only, or a synthesis margin on the DMA outputs if the user approves). RTL stays frozen. | `constraints/legacy/` | needs approval if a margin is used |

## 4. Proposed order of work (to confirm tomorrow)

0. Preserve run 1: on the server `cd /storage/EE5239G1/aagams_workspace2/unpu ; cp -r pnr_icc2 pnr_icc2_run1` (large; or `mv` after confirming nothing needs the old path) and note the repo hash.
1. Decide L1, L3, L7, L8 with the user (15 minutes); send the PM question.
2. Execution: tasks for the changes that need scripts (research of ICC2 options for L1/L2; port buffering and pin placement for L3).
3. Run the flow in the same order as run 1 (synthesis -> GLS -> NDM -> setup -> floorplan -> power -> placement -> CTS -> route), with PrimeTime and Calibre checkpoints (L5).
4. Fill, export, LEF/SDF checks, the three Calibre checks, both PrimeTime runs, the post-layout simulation.
5. Write the "what we did differently" section for the course report from this file and the progress log.

## 5. What I need from the user tomorrow

- Yes/no on L1 (the margin approach, if ICC2 has no latency option), L3 (port buffering where), L7 and L8.
- Whether to send the PM question before starting (it can run in parallel).
- Whether the parked 059/062 files should be committed, dropped or left.
