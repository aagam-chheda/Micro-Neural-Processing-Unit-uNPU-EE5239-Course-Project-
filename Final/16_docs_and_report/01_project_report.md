# uNPU — a 4x4 INT8 systolic matrix-multiply accelerator, from RTL to a sign-off-clean 180 nm macro

**Course project EE5239 — Project 2 (Frankenstein 180 nm IP-validation SoC)**
Final project report. Status of this text: generated from the project record on 2026-11-11; every number in a table marked "(log)" is re-read from the cited file by `Final/tools/verify_final.sh`. Statements that could not be proven from a file are marked **[unverified]**. Section 14 lists them.

---

## Abstract

We designed, verified, synthesised, placed, routed and signed off a 4x4 INT8 weight-stationary systolic array, `unpu_top`, as a hard macro in the SCL 180 nm process (four metal layers). The macro has a 32-bit APB register interface and a DMA master port; it multiplies matrices up to 4x4 with 32-bit accumulation at 50 MHz.

The final layout (run 3) is a single macro of 885.6 x 885.6 um with 206 pins, 2465 registers and 14674 leaf cells, utilisation 0.6986. It is **clean in all sign-off checks**: Calibre DRC 0 results from 404 rules, Calibre antenna 0 results from 16 rules, LVS **CORRECT** (44560 nets matched); PrimeTime reports no violating endpoint in setup (ss corner) and hold (ff corner) with crosstalk analysis off (worst slack +0.1057 / +0.0041 ns), with crosstalk on (+0.0154 / +0.0038 ns) and against the original constraint file (+0.1057 / +0.0041 ns); the design rules are MET. The delay-annotated post-layout simulation passes in all four configurations (343341 checks each) with documented limitations of the delay-file annotation.

The report describes the specification, the architecture and its verification (about 745,000 checks in the RTL campaign), the constraints and synthesis, each physical-design stage, the four repair loops that were needed to close timing and antenna rules (antenna buffers, a hold ECO, a data-transition ECO and an SI-aware ECO round), the sign-off, the simulation, the full run history (three complete runs) and the limitations. A companion document, `02_what_we_did_differently.md`, lists the engineering choices that differ from the course's reference flow; `03_explanation_and_viva_notes.md` is a plain-language walkthrough for the oral explanation.

---

## Contents

1. Introduction and scope
2. Specification and system context
3. Architecture and RTL
4. Functional verification of the RTL
5. Constraints and logic synthesis
6. Physical design flow (run 3)
7. Closing timing and antenna rules: the repair loops
8. Sign-off
9. Post-layout simulation
10. Final results
11. Run history: runs 1, 2 and 3
12. Reproducibility, records and deliverables
13. Lessons learned
14. Limitations, open items and unverified statements
Appendix A — Glossary
Appendix B — Where each result lives in `Final/`
Appendix C — The ECO cells of run 3
Appendix D — Server and shell traps

---

## 1. Introduction and scope

### 1.1 The project

The task is to take a block of RTL — here a small neural-network accelerator — through the complete digital implementation flow of the course (Design Compiler, IC Compiler II, Calibre, PrimeTime, Xcelium) and to deliver a macro that is DRC- and LVS-clean in the SCL 180 nm process. The macro is intended for a larger IP-validation SoC ("Frankenstein") whose other parts are owned by other groups: a PicoRV32 RISC-V core, a 32 KB SRAM in four banks, an SRAM arbiter shared by the CPU, our DMA and an SPI controller, and a BIST finite-state machine. Our block is memory-mapped at `0x4000_0000`–`0x4000_0FFF`.

### 1.2 What was delivered

| item | form |
|---|---|
| validated RTL | SystemVerilog, synthesisable subset, 11 files in `rtl/` |
| verification | 10 self-checking testbenches, a C golden model, two independently written peer testbenches |
| macro | GDS, LEF (one macro, 206 pins), DEF, post-layout netlists (with and without power pins), SDC (ss, ff), SDF 3.0 (ss, ff), SPEF (two corners) |
| sign-off | Calibre DRC / antenna / LVS reports, PrimeTime reports in three views, post-layout simulation results |
| records | `Final/` (one folder per flow stage with scripts as run, logs, reports), `Final/scripts/` and `Final/docs/` (complete pinned sets) |
| top-level hand-off | a separate integration package for the SoC team (datasheet, pin list, interface timing, open items) |

The brief asked for `.lef`, `.lib` and `.gds`. A `.lib` timing model of the macro was **not** produced: the library compiler is not available in our environment (PrimeTime reports that its executable path is not set when `write_lib` is attempted). This is a known gap (section 14).

### 1.3 Constraints that framed the work

- **Process and libraries.** SCL 180 nm, standard-cell library `fs120` (10-track, 1.8 V), four metal layers (M1, M2, M3, TOP_M). Only two characterised corners exist, no typical: `ss` (process 1.2, 125 C, 1.62 V) used for setup and `ff` (process 0.8, -40 C, 1.98 V) used for hold. Parasitics: TLUPlus typical only.
- **Frequency.** 50 MHz, 20 ns period (the PM confirmed ~50 MHz is adequate).
- **Microarchitecture.** Single-stage processing element; the multiplier is not pipelined (pipelining would change every number of the timing contract).
- **No DFT.** No scan chain and no scan pins (PM-confirmed).
- **Language.** Brief says Verilog; the PM confirmed SystemVerilog is acceptable; the synthesisable subset is used.
- **Tools.** Fixed by the instructor's flow: Xcelium 22.09 (simulation), Design Compiler T-2022.03-SP5 (synthesis), IC Compiler II U-2022.12-SP3 (layout), Calibre 2022.4_37.20 (DRC/LVS), PrimeTime T-2022.03-SP2 (sign-off timing).
- **Rule of the project.** Nothing fails silently; nothing is hard-coded; no threshold is narrowed and no constraint tuned to close timing without a written reason and the user's approval; no waiver without approval.

### 1.4 How the work was organised

The team had five members (about 10 hours per week each over about eight weeks, per the project handoff). The implementation work in this repository was carried out in a two-session protocol: a *Planning* session decided what to do next and wrote task prompts (and owned `docs/planning/`), and an *Execution* session implemented them (RTL, testbenches, scripts), always against the user's decisions. Every decision that changes a number or relaxes a rule was taken by the user and is recorded with its date in `docs/session-handoff.md` and the progress logs. The user ran all tools on the institute server (the AI sessions had no server access) and pasted the results back. This is mentioned so that the provenance of the records in `Final/` is clear; delete or rephrase the paragraph if the course does not need it.

---

## 2. Specification and system context

### 2.1 Answers received from the project manager (PM)

| # | question | answer |
|---|---|---|
| 1 | matrices larger than 4x4 | not required; tiling optional ("extra marks") |
| 2 | signed or unsigned INT8 | deferred to us; **signed**, with a SIGNED mode bit in a configuration register |
| 3 | extra registers | deferred; the final map has **8 registers** |
| 4 | clock | **~50 MHz** |
| 5 | DMA read/write encoding | deferred; `wstrb == 0` means read |
| 6 | when is `dma_rdata` valid | deferred; same cycle as `valid & ready` |
| 7 | native or bus interface | native for the DMA/SRAM port; the CPU-facing register port was first native, then **reverted to APB** after a meeting of the user, the PM and the SoC team (2026-09-22) |
| 8 | arbiter latency | no number; our DMA has higher priority than the CPU |
| 9 | BIST access | over the bus; no wrapper or test port |
| 10 | scan pins | none |
| 11 | port list frozen? | negotiable, not frozen |

### 2.2 Decisions taken by the team

| decision | rationale |
|---|---|
| 32-bit partial sums throughout | cannot overflow for any layer; matches the SRAM word width; costs 512 vertical wires inside the array |
| a 192-flop output de-skew bank | the alternative (skewed write addresses) produces out-of-order writes and four times the write traffic on a contended bus |
| no hardware requantiser | about 10 percent of macro area for something the brief never asks for; firmware does it |
| weights loaded by shifting down, reverse row order, double-buffered | avoids 128 broadcast wires; the 4-cycle cost is hidden by double buffering |
| three small FSMs instead of one | the APB side must answer regardless of compute state; the DMA must wait for the arbiter without freezing the sequencer |
| one global array enable; no flow control inside the array | partial freezing shears the wavefront into plausible wrong answers |
| symmetric weights, zero-point handled in software | keeps the PE a plain integer dot product |
| single-stage PE at 50 MHz | a two-stage PE doubles latency from 7 to 14 and changes all timing numbers |
| matmul shape A[MxK] x B[KxN] = C[MxN], M, N, K <= 4 | PM-specified; smaller K or N fall out by zero-loading unused weights and writing back only real columns |

### 2.3 Interfaces of the macro

`unpu_top` has 102 input and 102 output signal pins:

| group | signals |
|---|---|
| clock / reset | `clk`, `rst_n` (active low) |
| APB slave (CPU side) | `paddr[31:0]`, `pwdata[31:0]`, `pwrite`, `psel`, `penable`, `prdata[31:0]`, `pready` |
| DMA master (SRAM side) | `dma_addr[31:0]`, `dma_wdata[31:0]`, `dma_rdata[31:0]`, `dma_wstrb[3:0]`, `dma_valid`, `dma_ready` |

Register window `0x4000_0000`–`0x4000_0FFF`; the macro decodes only `paddr[11:2]` and relies on an external decoder to assert `psel` for the window (PM-confirmed). The eight registers (offsets are the design team's proposal and **not PM-confirmed**):

| offset | register | access | contents |
|---|---|---|---|
| 0x00 | `src_a` | R/W | pointer to A in SRAM |
| 0x04 | `src_b` | R/W | pointer to B |
| 0x08 | `dest_c` | R/W | pointer to C |
| 0x0C | `dim_m` | R/W | bits [2:0] |
| 0x10 | `dim_n` | R/W | bits [2:0] |
| 0x14 | `dim_k` | R/W | bits [2:0] |
| 0x18 | `npu_ctrl` | R/W | bit 0 START (write-1-to-pulse, reads 0); bit 1 SIGNED |
| 0x1C | `npu_status` | R/O | bit 0 DONE (sticky), bit 1 ERROR, bits [4:2] error code |

---

## 3. Architecture and RTL

### 3.1 Block diagram

```
                   APB (CPU)                              native master (SRAM arbiter)
                       |                                              ^
                  +----v----+      +-------+      +--------+     +----+-----+
 paddr/pwdata --> | unpu_apb | --> |unpu_csr| --> |unpu_seq| <-> | unpu_dma |
 prdata  <------- | (glue)   | <-- |(8 regs)| <-- |(FSM)   |     | (4-state)|
                  +----------+      +-------+      +---+----+     +----+-----+
                                                       |               | A rows / W rows
                                                       v               v
                                              +--------+--+      +-----+-----+
                       C words <------------- | unpu_deskew|      | actbuf/wbuf|
                                              +--------+--+      +-----+-----+
                                                       ^               |
                                                       |         +-----v-----+
                                                +------+------+  | unpu_skew |
                                                | unpu_grid   | <+-----------+
                                                | 4x4 PEs     |
                                                +-------------+
```

### 3.2 Modules

| module | role | notes |
|---|---|---|
| `unpu_pe` | one processing element: 8x8 multiply-accumulate with a 32-bit accumulator, weight register, signed/unsigned mode | single stage; 48 flops per PE |
| `unpu_grid` | 4x4 array of PEs, activations flow east, partial sums flow south | the array's north partial-sum inputs are tied to 0 (no accumulate mode); the east activation outputs are unused and optimised away |
| `unpu_skew` / `unpu_deskew` | input skew registers (depth 0/1/2/3) and output de-skew registers (depth 3/2/1/0) | de-skew bank is 192 flops |
| `unpu_wbuf` / `unpu_actbuf` | double-buffered weight and activation buffers (267 flops each) | shift-down weight load |
| `unpu_dma` | DMA master, one job at a time: fetch A, fetch W, write back C | 4-state per-beat handshake plus a buffer-load state; the address advances only on a cycle where `dma_valid` and `dma_ready` are both 1 |
| `unpu_seq` | sequencer: latches configuration, validates dimensions, dispatches the DMA jobs, runs the array, captures C | 628 flops (it holds the 512-bit C staging register) |
| `unpu_csr` | register file with the special behaviours (START pulse, sticky DONE, read-only status) | bus-protocol agnostic by design |
| `unpu_apb` | APB slave: pure combinational glue; `pready` tied to 1; write qualified by `psel && penable && pwrite`; no `PSLVERR` | `csr_sel = paddr[11:2]` |
| `unpu_top` | wiring of the above | no new mechanism |

Total: 2465 flops (768 in the 16 PEs, 267 + 267 in the buffers, 192 in the de-skew, 628 in the sequencer and the rest in skew, DMA and CSR). All 28 sequential blocks use an **asynchronously asserted, active-low reset**; the release is not synchronised inside the macro (the top-level reset driver is synchronous according to the user, second-hand and not confirmed in writing **[unverified]**; an asynchronously-reset flop can be driven by a synchronously released reset, so there is no conflict, but `rst_n` must come from a flop and be released synchronously to `clk` — to be confirmed with the SoC team). The course task text for the integration package assumed a synchronous reset; the RTL, the datasheet and this report state the asynchronous assertion.

### 3.3 The timing contract

Every module agrees with four equations, which were derived, not chosen:

| event | cycle (relative to the first activation injection) |
|---|---|
| `A[m][k]` enters the west edge of row `k` | `m + k` |
| `A[m][k]` arrives at PE(k, j) | `m + k + j` |
| `C[m][j]` leaves the south edge of column `j` | `m + j + 4` |
| a whole row `C[m][*]` is valid after de-skew | `m + 7` |
| a pass of M rows takes | `M + 7` cycles |

Skew depths are 0/1/2/3 on the input side and 3/2/1/0 on the output side. Because a change to any of these would alter every module, the project rule is: if a change would alter the contract, stop and raise it.

### 3.4 The combinational read path

`prdata` is the CSR read multiplexer driven directly by `paddr[11:2]`; there is no register between `paddr` and `prdata`. With the course's I/O budgets (APB input and output delays 35 percent of the period each), the path has 20 - 1.5 (uncertainty) - 7 - 7 = 4.5 ns. Synthesis found this path at 4.49 ns of the 4.5 ns budget (slack +0.01 ns): it is the design's critical path in every tool and the reason that the later sections spend so much effort on a path with essentially zero margin.

---

## 4. Functional verification of the RTL

### 4.1 Method

- **Self-checking testbenches**, one per module plus a system testbench, simulated with Verilator 5.053 and cross-checked with Xcelium 22.09. PASS/FAIL is decided from each testbench's own log, never from the simulator's exit code (testbenches end in `$finish`, so the simulator exits 0 even when checks failed).
- **A golden model in C** (`model/golden.c`) that writes directed cases and 64 constrained-random cases (hex vectors for A, W and C and a metadata file). Constrained-random verification with committed seeds is standing policy.
- **Adversarial "break-it" campaign** (tasks 019–028): ten modules, about 745,000 checks, zero RTL defects found.
- **Mutation spot-check**: three deliberate defects were injected in an isolated copy (stopping the compute state one cycle early; inverted unsigned/signed polarity; DMA row stride 16 -> 15). All three were caught by the earliest directed cases (6,537, 106,276 and 1,775 failures respectively), i.e. the passing counts are not vacuous.
- **Independent cross-check.** Two testbenches written by a peer for a different implementation (a diagonal-input array) of the same project were adapted (`ext1`: 34 checks; `ext2`: 15,231 checks, 325 rounds) and pass on both simulators. They were written independently of our golden model, so a shared misreading would have shown up there.
- **Lint**: whole-design `verilator --lint-only -Wall`.

### 4.2 Results (frozen commit 862d840, re-certified)

| module | testbench | self-reported checks | result |
|---|---|---|---|
| `unpu_grid` | `unpu_grid_tb` | 12,474 | 0 failures |
| `unpu_skew`/`unpu_deskew` | `unpu_skew_tb` | 17,665 | 0 failures |
| `unpu_stall` (composite) | `unpu_stall_tb` | 5,732 + 250,560 freeze checks | 0 failures |
| `unpu_seq` | `unpu_seq_tb` | 19,840 | 0 failures |
| `unpu_wbuf`/`unpu_actbuf` | `unpu_buf_tb` | 17,975 | 0 failures |
| `unpu_dma` | `unpu_dma_tb` | 19,009 | 0 failures |
| `unpu_csr` | `unpu_csr_tb` | 20,041 | 0 failures |
| `unpu_apb` | `unpu_apb_tb` | 32,545 | 0 failures |
| `unpu_pe` | `unpu_pe_tb` | exhaustive signed and unsigned sweeps (65,536 each) plus directed and adversarial phases | 0 failures |
| `unpu_top` | `unpu_top_tb` | 343,341 | 0 failures |

The same system testbench (`unpu_top_tb`) is reused unchanged for the pre-layout gate-level simulation and for the post-layout simulations, which is why the count 343,341 appears throughout this report: it is the control that proves that the netlist, with and without delays, computes what the RTL computes. (Freeze report: `Final/docs/docs/freeze-report-v2.md`.)

---

## 5. Constraints and logic synthesis

### 5.1 Constraints

The synthesis constraints ("legacy" set) are the course reference script split into a pure SDC plus a flow script:

- clock `clk`, period 20 ns, waveform {0 10}; setup uncertainty 1.5 ns, hold uncertainty 0.5 ns; clock transition 0.6 ns
- input delays: APB inputs 7 ns (35 percent of the period); DMA inputs and `rst_n` 8 ns (40 percent); minimum input delay 0
- output delays: APB outputs 7 ns; DMA outputs 8 ns; minimum output delay -0.5 ns
- inputs driven by a `buffd1` cell with 0.2 pF wire load; outputs load 1.0 pF
- `max_transition` 3 ns and `max_capacitance` 2 pF (the library's own limit)
- operating condition `tsl18fs120_scl_ss`; wire-load model 140000

The history of these constraints is a story of decisions, each taken by the user with a written reason:

1. The first assumptions were made deliberately harsh. A design-wide `max_transition` of 1.0 ns turned out to contradict the input assumptions (a `buffd1` driving 0.2 pF already gives 2.43 ns), so 79 data input ports violated a limit that no tool could fix. A per-port `max_transition` 3.0 was tried and did **not** work (a tighter design-wide value wins over a port-level one); the design-wide 1.0 ns was dropped and the library's own 3 ns used. The input-driver and wire assumptions were not relaxed.
2. On 2026-10-27 the instructor posted rules for closure margins and I/O delays; the user decided to follow the most pessimistic value of every range and re-ran synthesis at 20, 18 and 16 ns. On 2026-11-02 the user then restarted from the instructor's example scripts with the **old** constraint set (setup 1.5 / hold 0.5), which is the set used for the final run. The stage-profile approach is documented but not used in the final flow.

### 5.2 Synthesis result (run 3, Design Compiler T-2022.03-SP5)

| item | value | source |
|---|---|---|
| errors / latches | 0 / 0 | `03_synthesis/logs/legacy_dc.log` |
| sequential cells (flops) | 2465 | `03_synthesis/reports/unpu_top.area` (log) |
| total cell area | 429161.242546 um2 | same (log) |
| total area including interconnect estimate | 442295.849131 um2 | same (log) |
| violated constraints | only `max_area` (the PM script's `set_max_area 0` means "minimise") | `unpu_top.constraint` |
| worst setup slack | +0.01 ns, `paddr[3]` -> `prdata[14]` (combinational, 4.49 ns of 4.5 ns) | `unpu_top.qor` |
| register-to-register worst slack | +1.80 ns (ripple-carry adder in the PE) | handoff 18.8 |
| dynamic power | 6.40 mW (ideal clock, no switching annotation: not meaningful) | `unpu_top.power` |
| `check_timing` | clean | `unpu_top.check_timing` |

The netlist is renamed (`change_names -rules verilog -hierarchy`: 9,142 escaped-name lines and 16 `assign` statements removed) and written as `unpu_top_cn.dc.v` for ICC2. The run 1, 2 and 3 syntheses are identical (deterministic).

### 5.3 Pre-layout gate-level simulation

The renamed netlist, with the SCL cell models and zero delays, passes the system testbench: **343341 checks, ALL CHECKS PASSED**, 0 FAIL, 0 `*E`/`*F` (about 2 minutes).

---

## 6. Physical design flow (run 3)

### 6.1 Overview

All steps use the course's reference ICC2 scripts, minimally edited (every edit carries a marker; the pristine originals and their SHA-256 sums are kept). The block chain inside the design library is
`_setup -> _floorplan -> _powerplan -> _placement -> _portbuf -> _cts -> _route -> _filled -> _pv`, with checkpoints saved after each step so that any stage can be inspected or restarted.

| step | script | content |
|---|---|---|
| 0 | `build_ndm_std.tcl`, `build_ndm_filler.tcl` | NDM reference libraries from the kit (540 `FRAM-066` frame warnings) |
| 1 | `design_setup.tcl` | library, netlist, SDC; `func_ss` scenario setup-only, `func_ff` hold-only; no PVT mismatch for either corner |
| 2 | `floorplanning.tcl` | core utilisation 60.02 percent, die 885.6 x 885.6 um, pins: DMA on the top edge (M2), APB + `clk` + `rst_n` on the right edge (M3), spacing 8 um |
| 3 | `powerplanning.tcl` | M3 / TOP_M ring, M3 + TOP_M mesh, M1 rails |
| 4 | `placement.tcl` | `place_opt`, legalisation, congestion check |
| 4c | `port_buffers_early.tcl` | early input-port buffers (section 7.1) |
| 5 | `cts.tcl` | `clock_opt`: clock tree synthesis |
| 6 | `route.tcl` | global/detail routing, `route_opt` |
| 6b–6g | `fix_antenna`, `antenna_port_buffers`, `pt_eco_apply` | repair loops (section 7) |
| 7 | `metal_fill.tcl` | track fill on M1…TOP_M |
| 8 | `pv.tcl` | exports: GDS (merged with the standard-cell and I/O library GDS), LEF, DEF, netlists, SDC, SDF, SPEF |

### 6.2 Floorplan, power plan, placement

- **Die and core.** The die side 885.6 um comes from the tool for a core utilisation of 0.60 (the example script used 0.85; 0.60 was chosen to leave room for buffering and routing). The row height is 5.6 um (site `CoreSite` 0.56 x 5.6 um).
- **Pins.** 204 signal pins: 102 on the top edge (all `dma_*`, M2, vertical) and 102 on the right edge (APB, `clk`, `rst_n`, M3, horizontal), as agreed with the top-level team. The tool placed the pins of each edge from both ends in alternating pairs, so the buses are interleaved and the bit order is descending; the user accepted the tool's placement and the positions are reported to the top-level team. An attempt to re-place the pins after placement (to shorten port wires) was parked because the second `place_pins` ignored the 8 um spacing.
- **Power pins.** Following the example script, `VDD` and `VSS` are one terminal each on an interior vertical TOP_M stripe (VDD at x = 830 um, VSS at x = 860 um). This differs from the earlier plan of a row of bottom-edge pins and is recorded as an open item for the top-level team.
- **Placement.** The automatic density control selected max density 0.60; the run-1 record shows legality 0 violations and no congestion issue [run 1; the run-3 log was not re-read for these two items].

### 6.3 Clock tree synthesis

| item | value (log) |
|---|---|
| sinks | 2465 |
| levels / repeaters | 6 / 63 |
| insertion delay (clock pin to registers), fast corner | 0.56 ns, skew 0.32 ns |
| insertion delay, slow corner | 1.26 ns, skew 0.75 ns |

No latency or skew limit was ever given by the top level (open question to the PM); the tree is built for minimum skew and the result is reported. The CTS script carried an example target of `max_transition 0.40 -clock_path`; its consequences are discussed in 7.5.

### 6.4 Routing and the route checkpoint

After routing, `route_opt` and the checks: no shorts, no opens, **open nets 0**, total wire length 830822 um, 135767 contacts (`check_routes`). The global-route overflow at the final state is 1.97 percent (worst cell 7 tracks).

A *checkpoint export* of the route block (with its own tag) allowed PrimeTime and Calibre to be run **before** metal fill and before any repair, so that each later change could be measured against the previous state (section 7).

### 6.5 Metal fill and export

Track fill is inserted on M1…TOP_M, the final block is written out, and `pv.tcl` runs hard checks on its own output: the LEF must contain exactly one `MACRO unpu_top` with the right size and **206 PIN entries** (206 = 204 signal + `VDD` + `VSS`); the SDF must be version 3.0; the exported SDC must contain no tool-made `set_clock_latency` line and no clock-path `max_transition` line. The GDS is 59 MB (fill included).

### 6.6 Area and utilisation

| stage | cell area (um2) |
|---|---|
| after synthesis (cells only) | 429161.242546 |
| final layout, netlist cells | 499549.12 |
| final layout, cells + physical-only cells (fill, etc.) | 715039.36 |
| utilisation of the core | 0.6986 |

The growth of about 16 percent over the synthesis netlist comes from the clock tree, high-fanout buffering (HFS buffers and inverters), the 54 early port buffers, hold buffers, and the repair loops (Appendix C lists the cells added by the repair loops; the counts of every category are in the deliverables' `netlist_counts.txt`).

---

## 7. Closing timing and antenna rules: the repair loops

### 7.1 Antenna protection of the input ports (step 4c)

**Problem found in run 1.** Calibre's antenna check failed on 16 nets, all *input port* nets: they have no driver or diffusion inside the macro, so the whole wire from the pin to the gate counts against a tiny gate (about 0.19 um2). The tool had placed the 102 pins of each edge once, before any cell existed, spread over the whole edge, while the loads sit in one cluster, so wires were 130–478 um against a limit of about 72 um (M2/M3). Diodes are not allowed.

**Run 1 repair.** A buffer was put on a free filler site next to the pin of each offending net (15 `antbuf_*` buffers) after routing; this closed the antenna rules (55 -> 50 -> 46 -> 1 -> 0 results over the loops) but cost a loop and disturbed timing.

**Run 3 prevention.** The same idea, moved *before* clock tree synthesis and driven by a formula: `port_buffers_early.tcl` predicts, for every input port, the pin-to-load wire from the placement, computes the antenna ratio with the foundry weights (M2/M3 0.54, TOP_M 0.84, wire width 0.28 um, limit 400, margin 0.8) and inserts one `buffd1` next to the pin where the prediction would fail. The prediction table (`08_placement/reports/port_buffers_early_table.csv`) has 54 rows BUFFER, 5 CONE-SKIPPED, 20 OK, 22 NO-LOADS and 1 CLOCK-SKIPPED. Five nets on the combinational read path (`paddr[3,5,7,9,11]`) are *skipped* by default (`CONE_POLICY skip`): in run 2 the first real attempt put buffers on them and the step's own gate stopped it (in2out slack 0.0206 -> -0.1198 ns). Their predicted ratios (565 to 1172, limit 400) mean Calibre found antenna results on them later (10 at the route checkpoint), which the second loop repaired (7.2).

### 7.2 Antenna loop on the route checkpoint

| step | Calibre antenna results | note |
|---|---|---|
| route checkpoint (route1) | 10 | 8 on `paddr[7]`/`paddr[11]` (the skipped read-path nets), 2 internal |
| after `fix_antenna.tcl` (layer hopping) | 4 | all M2 on `paddr[7]` |
| after `antenna_port_buffers.tcl` on `paddr[7]` only (one `antbuf_`) | 0 | DRC stays 0 throughout |

The per-run table of all Calibre runs is `13_signoff_calibre/reports/all_runs.md`.

### 7.3 The I/O clock-latency finding (the largest single cause of the run-1 sign-off gap)

At the end of run 1 the layout was DRC/LVS-clean and ICC2 said setup +0.0143 / hold -0.0004 ns, but **PrimeTime said setup -0.2423 ns (1 endpoint, `dma_addr[31]`) and hold -0.3468 ns (263 endpoints, input to register)**. The investigation (a read-only diagnostic, then an in-memory what-if on a copy of the block) found:

- ICC2 wrote a `set_clock_latency <v> [get_clocks {clk}]` line into the block by itself (first in the power-plan block, re-created inside `place_opt` and `build_clock`). It acted as the I/O reference latency in ICC2 (0.8069 ns at ss, 0.3798 ns at ff), i.e. ICC2 assumed the outside world was *behind* the macro's clock tree, while PrimeTime launches and captures I/O at the `clk` **pin** with zero latency.
- No log and no script mentioned the line; it appeared in the exported SDC of run 1 as a line "written by the tool and never by us".
- Removing the line in memory reproduced PrimeTime's numbers on the four example paths (hold slack -0.3494 vs PrimeTime -0.35; output required 10.5000 vs 10.50; launch 0.9188 vs 0.92), and reg-to-reg slacks were unchanged.
- The other options (`-network_latency_included`, `-source_latency_included`, an offset emulation) fix only one side or overshoot.

**Decision (user):** remove the line inside the ICC2 flow with printed checks, at the earliest point it exists, after every step that can recreate it, and with a hard check in `pv.tcl` that the exported SDC has none. No margin, no change of uncertainty, no SDC text from the PM. In run 3 the I/O reference after CTS is PrimeTime's (output capture 0.0000, input launch 0.2403 ns = the port stage).

### 7.4 Optimisation-only margin

Following a friend's experience, the user asked whether raising the clock uncertainty would make the sign-off easier. The analysis: the idea is right in kind (optimise tighter than sign-off, in ICC2 only) but wrong as a global increase, because the gap is path-specific and the read path has no margin to give. The compromise implemented (task 090) is an optimisation-only margin (setup +0.05 ns, hold +0.10 ns) **scoped to paths that end at registers**, restored after the optimiser and proven by a read-back and by checking the exported SDC.

### 7.5 PrimeTime-driven ECOs

**ECO** = *engineering change order*: a small local fix on a nearly finished layout, applied with gates before and after, and a fresh checkpoint. The method used for all ECOs of run 3:

1. A **probe** in PrimeTime (sign-off view, with the real parasitics) finds the violating endpoints, protects the *cone* of the zero-margin read path (cells and nets), classifies each candidate by pin ("flop-driven net" vs "load pin") and writes a change file plus an expected count.
2. The **apply** script in ICC2 executes the change file behind gates: in2out WNS and whole-design setup WNS must not get worse than 0.005 ns, DRC 0, legality 0, open nets 0, and the protected cells (`earlybuf_*`, `antbuf_*`, the hold cells, previously resized drivers) must be unchanged. A cell that does not fit in place is relocated to a free filler run near its pin.
3. A new checkpoint, then PrimeTime and Calibre again.

| ECO | what | before -> after |
|---|---|---|
| hold ECO, 9 cells (+138 um2) | delay cells / buffers on flop-driven pins (`reg2out` scope: 7 register-to-output endpoints into `prdata`) | PrimeTime hold -0.0188 -> +0.0002 ns; setup +0.1058 ns; ICC2 hold -0.0158 -> -0.0028 |
| data-limit ECO, 9 resizes | driver upsizing on 9 nets whose slew exceeded the 3 ns data limit (86 entries) | data-limit entries 86 -> 0; the clock-path 0.40 ns entries are a separate matter (below) |
| SI round | first: PrimeTime with crosstalk ON found 4 setup endpoints (`paddr[3]` -> `prdata`, WNS -0.0364 ns) and 1 hold endpoint (-0.0114 ns): one hold buffer on `u_csr/U361/C2` and a resize of `u_apb/U29` `buffd1` -> `buffd3` (relocated 5.6 um); a second hold buffer on `u_csr/U376/B2` and a second `fix_antenna` followed | final: SI ON setup +0.0154 / hold +0.0038 ns, SI OFF +0.1057 / +0.0041 ns |

The cost of each ECO was an extra complete chain (fill, export, three Calibre checks, three PrimeTime views, simulation); this is why the runbook lists which steps can run in parallel.

### 7.6 The clock-path max-transition limit (option B)

The example `cts.tcl` carries `set_max_transition 0.40 -clock_path`, and the exported SDC then contains it. On the first final export PrimeTime reported 510 `max_transition` entries on the ss design-rule report: 424 on the 0.40 ns clock-path limit (actual 0.43–0.48 ns) and 86 on the 3 ns data limit. The 86 were fixed by the data-limit ECO. For the 424 the user chose **option B**: the clock-path limit is removed from the exported SDC with a written reason (it is an optimisation target of the example script, not a course requirement; the legacy constraints, which are the reference, do not contain it) and `pv.tcl` checks that the exported SDC does not have it. PrimeTime is then also run against the legacy SDC as a second reference. ICC2's own final QoR still lists 8 nets with a max-transition violation (clock-path nets); this is disclosed as a limitation (section 14).

### 7.7 Constraint comparison

`sdc_compare.tcl` evaluates the legacy SDC and the exported SDC in a safe Tcl interpreter and compares them constraint by constraint. On the final exports: **722 constraints compared, 4 expected differences (propagated clock, units, explicit waveform, operating conditions), 0 unexpected differences** (same for ss and ff).

---

## 8. Sign-off

### 8.1 Calibre

| check | result (log) |
|---|---|
| DRC (final4) | 404 rule checks executed, **0 results** |
| antenna (final4) | 16 rule checks, **0 results** |
| LVS (final4) | **CORRECT**, 44560 nets matched |

LVS needed two changes to the project's control file, both approved by the user with written reasons: (1) deletion of two `VIRTUAL CONNECT` lines that the deck sets itself ("superfluous specification statement"); (2) the deck's own switch `FILTER_DWN2PSUB`. Without it the layout shows one extra device, an N-well to P-substrate diode (`DWN2PSUB`, 76 parallel diodes), which does not exist in the source netlist. Calibre must be re-run after every step that changes the layout or the netlist; the table of all runs (route1…4, final…final4) is in `13_signoff_calibre/reports/all_runs.md`: antenna 10 -> 4 -> 0 over the antenna loop, and 3 results at `final3` (the first SI-round applies disturbed routing) -> 0 at `final4`.

### 8.2 PrimeTime

Setup is checked in the ss corner and hold in the ff corner on the exported SDC with the real parasitics (SPEF), propagated clock proven, annotation proven (the two-line annotation table is parsed and compared: all 16573 nets annotated).

| view | setup (ss) WNS | hold (ff) WNS | violating endpoints | design rules |
|---|---|---|---|---|
| crosstalk off (default sign-off) | +0.1057 ns | +0.0041 ns | 0 | MET |
| crosstalk on (SI) | +0.0154 ns | +0.0038 ns | 0 | MET |
| legacy SDC | +0.1057 ns | +0.0041 ns | 0 | MET |

"SI" = signal integrity: coupling capacitance to switching neighbours changes delay by tens of picoseconds. PrimeTime without SI is less pessimistic than ICC2 with SI. The crosstalk-on margins are thin (setup +0.0154 ns, hold +0.0038 ns) and are disclosed as such.

### 8.3 Summary of the checks

| check | result |
|---|---|
| DRC | clean |
| antenna | clean |
| LVS | CORRECT |
| setup, hold (3 views) | 0 violating endpoints in all six runs |
| design rules | MET |
| LEF | one macro, 206 pins, size equal to the die |
| exported SDC vs legacy | 722 compared, 0 unexpected differences |
| power-grid vias | 18 missing VSS vias reported by ICC2 (V2 6, V3 12) while Calibre is clean |

---

## 9. Post-layout simulation

### 9.1 Setup

The post-layout netlist `unpu_top_pnr_sim.v` is simulated in Xcelium with the SDF (3.0) for the slow corner (setup) and the fast corner (hold), each with and without timing checks, using the unchanged system testbench:

| run | corner | timing checks | verdict (log) | checks |
|---|---|---|---|---|
| A | ss | off | PASS | 343341 |
| B | ss | on | PASS | 343341 |
| C | ff | off | PASS | 343341 |
| D | ff | on | PASS | 343341 |

Simulation ends at 278003892 ns (ss) and 276701592 ns (ff). With timing checks on, 25,065 timing checks are active and none is disabled; no timing violation occurs.

### 9.2 The honesty fix of the verdict

The first version of the simulation script printed FAIL for harmless reasons and PASS for an acceptance based on a wrong number. The investigation (task 094) found that the "500 violations" were Xcelium source-context lines (the real count was 0, `Disabled Tchecks = 0`), and that the earlier acceptance of the unmatched SDF share ("about 1 percent") had been derived from the 500 printed warning lines, whereas the true share, counted from the SDF itself, was **42.8 percent** of 52,656 path-delay entries. The verdict logic now counts every warning class from the SDF and compares it with the simulator's own total, prints the classes, and is `PASS (with documented SDF limitations)` only for classes the user has approved through an explicit switch (`SDF_ACCEPT`).

### 9.3 SDF warning classes

| class | meaning | count | share | status |
|---|---|---|---|---|
| `nep_edge` | edge-form conditional arcs not annotated | 3,510 | 6.7 percent | accepted 2026-11-09 |
| `nep_cond` | COND-form arcs on full adders (`ad01*`, `xr03d1`): the adder-sum output has zero delay in the simulation | 19,024 | 36.1 percent | approved 2026-11-11; PrimeTime is the timing sign-off |
| `nl1_neg` | negative timing limit clamped to 0 | 8,589 (ss) / 7,150 (ff) | | approved; shown unnecessary by experiment 1 |
| `net_remrec` | removal/recovery value not annotated | 7,395 | | approved; reduced to 4,930 by experiment 1 |

### 9.4 The two optional experiments

Two experiments on the final layout tested whether the warnings could be removed instead of accepted.
1. **`===` to `==` in a copy of the SDF** (the 19,024 COND lines): warnings unchanged (22,534), same pass — the `===` was **not** the cause; the `nep_cond` class stays a documented, approved limitation.
2. **`-define neg_tchk`**: the clamped negative limits (`SDFNL1`) drop to 0 (the negative limits are applied; no violation was hidden by clamping), and the removal/recovery entries drop from 7,395 to 4,930 (the model has no check for the negedge-CDN entries). Cost: 17 min 44 s (ss) and 13 min 36 s (ff) instead of 6–7 minutes.

---

## 10. Final results

All values are re-read from the logs (the source of each is in `Final/INDEX.md`, section 2).

| quantity | value |
|---|---|
| macro size | 885.6 x 885.6 um, 206 pins (204 signal + VDD + VSS) |
| flops / leaf cells | 2465 / 14674 |
| utilisation / cell area | 0.6986 / 499549.12 um2 (715039.36 um2 with physical-only cells) |
| clock tree | 2465 sinks, 6 levels, 63 repeaters; latency 0.56 ns ff / 1.26 ns ss; skew 0.32 / 0.75 ns |
| DRC / antenna / LVS | 0 / 0 / CORRECT |
| PrimeTime setup / hold, SI off | +0.1057 / +0.0041 ns |
| PrimeTime setup / hold, SI on | +0.0154 / +0.0038 ns |
| global-route overflow | 1.97 percent |
| ICC2 dynamic power | 8.42e+09 pW (default activity: **not meaningful**) |
| zero-delay GLS / post-layout A–D | 343341 checks pass / 343341 checks each, all pass |
| frequency | 50 MHz |

The ICC2 power figure is reported at the tool's default switching activity (`No. of simulation cycles = 6` in the report), in the ss scenario (1.62 V and 125 C according to the project notes **[unverified in the report file]**): it is an order of magnitude only. A power estimate with annotated switching activity from the gate-level simulation was not made.

---

## 11. Run history

The flow was executed three times in three separate clones, so that each run is a self-contained record.

| run | clone | what it was | outcome |
|---|---|---|---|
| 1 | `unpu` (clean-slate restart 2026-11-02, results up to 2026-11-09) | first clean-slate run with the example scripts | complete physically clean layout (DRC 0, antenna 0, LVS CORRECT) but PrimeTime sign-off failed: setup -0.2423 ns (1 endpoint), hold -0.3468 ns (263 endpoints). Kept untouched as the fallback |
| 2 | `unpu_run2` (2026-11-10 morning) | the whole flow again with the lessons built in; synthesis, GLS, NDM, floorplan, placement, 54 early port buffers and CTS done once | stopped after CTS when the tool-made clock latency was found to start at the power plan |
| 3 | `unpu_run3` (2026-11-10 19:26 – 2026-11-11 04:43) | the whole flow from synthesis in a new clone, one commit lineage | final layout: all sign-off checks clean (section 10) |

Runs 1 and 2 (and run 3) are kept in the server backup (`/storage/EE5239G1/aagams_workspace2/backup/`; file counts 9988, 1861 and 6329 reported by Planning **[unverified here]**). Run 3 was a full re-run because the instructor said it is better that way and for a clean single-lineage deliverable; the earlier steps were technically unaffected (synthesis is deterministic and gave the identical netlist).

Timeline of run 3 (server times, from `RUN3_RUNBOOK.md`): synthesis and GLS 19:30; NDM 19:35; stages 1–6 19:47–20:09; route checkpoint, PrimeTime, Calibre 20:23–20:28; antenna loop 20:34–20:50; hold ECO 20:59–21:07; fill, export, sign-off of the first final state 21:09–21:13; data-limit ECO and its chain 22:39–23:45; SI round 00:55–03:53; final views 03:51–03:52; post-layout simulation 04:22–04:43. Two network outages (licence server and GitHub unreachable) interrupted the evening; nothing was lost because every run state is on disk and every script is committed.

---

## 12. Reproducibility, records and deliverables

### 12.1 What was done to make the work checkable

- **Relocatable run directories.** Every script derives its root from its own location (`run_root.tcl`), so one clone is one self-contained run; the tests copy the script set to a temporary place and still pass.
- **Every parameter is printed.** Each script prints its parameters with `default` or `ENV`, so a log shows which values were used.
- **Gates.** Every ECO and optimisation step has numeric gates that stop the run (not warnings).
- **Tests of the pure parts.** The pure-Tcl parts of the ICC2 and PrimeTime scripts are tested with `tclsh` mocks: 20 suites with 2019 numbered tests pass from a temporary copy of the script set (`Final/tools/verify_final.sh`, check 12).
- **VERIFY items.** Every statement about a tool command that could not be checked locally is marked `VERIFY`; `pnr_v2/VERIFY_STATUS_RUN3.md` tracks 136 of them against the run-3 logs (105 verified, 8 verified indirectly, 14 still open, 9 not applicable).
- **Run runbook.** `pnr_v2/RUN3_RUNBOOK.md` records the 12 ordered steps with commands, variables and expected key lines. Not verified there: the commit per step (inferred from timestamps), the exact typed commands (reconstructed from the READMEs), ICC2 repeatability (no second run).

### 12.2 The `Final/` folder

One numbered folder per flow stage (01 RTL … 15 post-layout simulation, 16 documents), each with a README of five parts (what the stage does; commit and commands; key results; decisions with date and who; problems and solutions), plus complete, pinned sets in `Final/scripts/` and `Final/docs/`. `Final/INDEX.md` lists every file with size and SHA-256; `bash Final/tools/verify_final.sh` checks the index, size limits, confidentiality rules and the key numbers against the logs (16 checks). The GDS, the DEF, the databases, the NDM libraries and the checkpoint exports are *not* in `Final/` (public repository); they are listed with size and SHA-256 in `INDEX.md`.

### 12.3 The integration package

A separate package (outside the repository) for the SoC integration team contains the GDS, DEF, LEF, netlists, SDC, SDF, SPEF, RTL and testbenches, pin list, interface-timing note, sign-off reports and a datasheet with an open-items list; it is verified by its own script (12 checks) and was sent as the zip `uNPU_deliverables_2026-11-11.zip` (sha256 `1bb6f6566b820df86fb601dad8c50f3275ce6d05aa40b390de1eff14e47d1d30`, checked on the PC after copying). The package states the delivery boundary: no PDK kit files, no rule decks, no tool-setup files, no databases.

---

## 13. Lessons learned

| # | lesson (evidence) | consequence |
|---|---|---|
| L1 | PrimeTime measures I/O at the clk pin with zero latency; ICC2 added the outside world's insertion delay. Output setup lost 0.92 ns, input hold needed +0.4 ns | find the tool-made latency line, remove it with printed checks |
| L2 | pins were placed before the cells, so input-port wires were up to 478 um | buffer the input ports before routing from a formula |
| L3 | PrimeTime was run last and found 264 violations at the end | run PrimeTime and Calibre at checkpoints after CTS and after route |
| L4 | a single-corner hold ECO from PrimeTime broke the read-mux setup | protect the read-path cone by cells *and* nets; classify by pin |
| L5 | the example `cts.tcl` carried a clock-path transition limit into the SDC | decide explicitly (option B), with a written reason and a hard check |
| L6 | a verdict printed from warning lines is not a measurement | count classes from the SDF itself and compare with the simulator's total |
| L7 | a test with reconstructed data passes while the real tool output fails | use verbatim tool output as test data (the annotation-table parser was fixed twice before this was done) |
| L8 | a threshold that is changed to close timing is not a result | no narrowed threshold, no constraint tuned without a written reason and approval |
| L9 | csh is not bash | see Appendix D |

---

## 14. Limitations, open items and unverified statements

### 14.1 Limitations of the sign-off (disclosed)

- **SDF annotation classes** in the post-layout simulation: 3,510 + 19,024 conditional arcs (the adder-sum outputs run with zero delay in the simulation), clamped negative limits and 7,395 removal/recovery entries (sections 9.3, 9.4). The timing sign-off is PrimeTime.
- **SI margin is thin**: SI on setup +0.0154 ns, hold +0.0038 ns; the read path `paddr` -> `prdata` has no spare time.
- **Congestion** at the upper end: overflow 1.97 percent (worst cell 7 tracks); routing itself is clean.
- **ICC2 reports 8 nets with a max-transition violation** (clock-path nets against the 0.40 ns CTS target that is not part of the delivered constraints). PrimeTime design rules: MET.
- **18 missing VSS power-grid vias** reported by ICC2's `check_pg_missing_vias` (V2 6, V3 12) while Calibre DRC and LVS are clean.
- **No decoupling capacitors**: the PDK has no decap cells; nothing in the flow inserts them. Power integrity was not analysed (no IR-drop tool in the flow).
- **Power numbers are not meaningful** (default activity).
- **No macro `.lib`.**
- **Findings V83 and V88** (`VERIFY_STATUS_RUN3.md`): in the data-limit apply, the driver-to-port distance printed n/a so the 20 um growth warning never had a value to test (the timing gates, the final Calibre and the final PrimeTime runs are the proof); in the SI-round applies the resized drivers of the earlier ECO were not protected by name because the folder holding their change file had been moved aside (the end checks of the other protected cells held, the final results are clean).
- **Repeatability of ICC2** is unverified (no second run of run 3); the commit per step is inferred from timestamps.

### 14.2 Open items for others

Latency/skew limit at `clk` (PM question); acceptance by the top-level team of the pin order, the position of `clk` and `rst_n`, and the two interior power stripes; confirmation of the register-map offsets and of the DMA address convention; the macro `.lib` question; whether the macro should be delivered with ICC2's metal fill or the chip-finishing flow adds dummy fill.

### 14.3 Statements that could not be proven from a file

The date of the PM's confirmation of SystemVerilog; the date of the approval of `FILTER_DWN2PSUB`; whether `pin_replace.tcl` ran in run 3; the corner and voltage of the power report (ss, 1.62 V, 125 C, from the project notes); the stage assignment of the `check_design*.log` files (by time); the server-side file counts of the backups; and the results of the Xcelium runs of the RTL campaign (quoted from the user's server runs, not observed by the assistant).

---

## Appendix A — Glossary

| term | meaning |
|---|---|
| ECO | engineering change order: a small local fix on a nearly finished layout, with gates and a fresh checkpoint |
| SI | signal integrity (crosstalk): delay changes caused by coupling to switching neighbours |
| setup / hold | the two timing checks of a flop: data must arrive before the next clock edge (setup) and must not change too soon after the edge (hold) |
| WNS / TNS | worst / total negative slack |
| ss / ff corner | slow (125 C, 1.62 V) / fast (-40 C, 1.98 V) library |
| antenna rule | during manufacturing a long metal wire connected to a gate collects charge; the ratio of wire area to gate area must stay below a limit unless a diode or a driver protects the gate |
| CTS | clock tree synthesis |
| NDM | the ICC2 reference-library format |
| SDC / SDF / SPEF / LEF / DEF / GDS | constraints / delay file / parasitics / abstract view / placement-and-routing description / mask layout |
| LVS | layout versus schematic |
| in2out | the combinational path from an input port to an output port (here `paddr` -> `prdata`) |
| cone | the set of cells and nets on the in2out paths; protected from ECOs that would slow them |
| checkpoint | a saved block (and its exports) at a stage, used to measure the next change |

## Appendix B — Where each result lives in `Final/`

| result | location |
|---|---|
| synthesis reports and netlists | `03_synthesis/` |
| early port buffers table | `08_placement/reports/port_buffers_early_table.csv` |
| route checkpoint PrimeTime results | `10_routing/pt_route*/` |
| ECO probes, change files, apply logs | `11_eco_and_antenna/` |
| final reports, exported SDC, SDF, SPEF, LEF, netlists | `12_fill_and_export/` |
| Calibre runs | `13_signoff_calibre/` (all-run table in `reports/all_runs.md`) |
| PrimeTime views and earlier runs | `14_signoff_primetime/` |
| post-layout simulation, experiments | `15_post_layout_sim/` |
| runbook, status of the VERIFY items | `pnr_v2/RUN3_RUNBOOK.md`, `pnr_v2/VERIFY_STATUS_RUN3.md` (also in `docs/`) |

## Appendix C — The ECO cells of run 3

| category | count | names / notes |
|---|---|---|
| early port buffers | 54 | `earlybuf_*`, `buffd1` |
| antenna buffer | 1 | `antbuf_*` on `paddr[7]` |
| hold buffers / delay cells | 11 | `U_PTECO_HOLD_BUF1…11` (9 from the hold ECO, 2 from the SI round: `u_csr/U361/C2`, `u_csr/U376/B2`) |
| resizes | 10 | 9 data-limit drivers (for example `u_dma/U157`, `u_dma/U220` -> `an02d7`) and `u_apb/U29` `buffd1` -> `buffd3` |

The change files and the apply logs of each ECO are in `11_eco_and_antenna/reports/` and `/logs/`.

## Appendix D — Server and shell traps

The server login shell is csh. No `foreach` on one line; `2>` and `2>&1` are "Ambiguous output redirect" (use `|&` or `>&`); `env VAR=val cmd` sets a variable for one command; a trailing `&` puts the whole `;` chain in the background (and `git log` then waits on its pager: use `git --no-pager` and start background jobs alone with `< /dev/null`); a dropped ssh connection kills foreground jobs but not `nohup` jobs; Calibre needs its own terminal with the Siemens environment; a `git pull` is needed in the clone before running a script committed after the clone; `source ~/cad_cshrc` and `~/synopsys_cshrc` per session; the `$FOUNDRY` variable points to a different (TSMC-style) kit and must not be used; killing the `icc2_shell` wrapper does not stop `icc2_exec`.
