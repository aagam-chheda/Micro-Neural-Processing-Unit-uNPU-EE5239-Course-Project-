# Session handoff

Everything decided before Claude Code sessions began. Read fully before your
first substantive action.

Last updated: start of Claude Code work. Update this file when decisions change.

---

## 1. What the block is

A 4×4 INT8 weight-stationary systolic array, exposed as an MMIO peripheral on a
180 nm IP-validation SoC (codename Frankenstein). The CPU writes pointers and a
start bit over APB; our DMA fetches tensors from shared SRAM without CPU
involvement; the array computes; results are written back; a DONE bit is set.

We deliver validated RTL plus a DRC/LVS-clean macro as `.lef`, `.lib`, `.gds`.

## 2. Environment

- Process: SCL 180 nm
- Tools available: Cadence Xcelium (sim), Genus (synth), Tempus (STA),
  Synopsys IC Compiler (P&R)
- **Not yet resolved**: which tools for DRC, LVS, formal equivalence, IR drop.
  None of the four above does DRC/LVS signoff, which is an explicit deliverable.
- Team: 5 people, ~10 hrs/week each, ~8 weeks. 400 person-hours total.

## 3. System context (Project 1 owns all of this)

- RISC-V core is **PicoRV32**, no cache, fetches almost every cycle
- 32 KB SRAM, 4 banks, at `0x0000_0000`–`0x0000_7FFF`
- Our register window: `0x4000_0000`–`0x4000_0FFF`
- SRAM arbiter shared between CPU (instruction + data), our DMA, and the SPI
  controller. **We are higher priority than the CPU** (confirmed by PM).
- SPI controller doubles as a debug backdoor that can master the internal bus —
  so our APB slave may be driven very slowly and must never hang.
- A BIST FSM will exercise hard macros post-fabrication.

## 4. Answers received from the PM

| # | Question | Answer |
|---|---|---|
| 1 | Matrices larger than 4×4? | **Not required.** "Extra marks if you can." Treat tiling as optional bonus. |
| 2 | Signed or unsigned INT8? | Deferred to us. **We chose signed**, with a SIGNED mode bit in a config register. |
| 3 | Extra registers allowed? | Deferred — he asked how many. **We requested two** (0x14, 0x18) plus a reserved range 0x14–0x3F. |
| 4 | Clock frequency? | **~50 MHz.** Confirmed adequate; we do not need more. |
| 5 | Read/write encoding on DMA port? | Deferred to us. **We proposed** `wstrb == 0` means read. |
| 6 | When is `dma_rdata` valid? | Deferred to us. **We proposed** same cycle as `valid & ready`. |
| 7 | Native or AHB data plane? | **Native**, confirmed for both: DMA↔SRAM master port *and* CPU↔NPU register port. APB is out. Resolved — see §5. |
| 8 | Worst-case arbiter grant latency? | No number. We co-design the arbiter with the SoC team; NPU has higher priority. |
| 9 | How does BIST reach us? | PM suggested over the bus. We agreed; no extra wrapper or test port needed. |
| 10 | Scan pins for tester access? | **None.** No scan chain, no `scan_en`/`scan_in`/`scan_out`. Not in scope for this project. |
| 11 | Is the `unpu_top` port list frozen? | **Negotiable**, not frozen — supersedes the "frozen" framing used everywhere below and in CLAUDE.md/execution.md (see §12). |

### Why we chose signed (Q2)

A layer whose weights cannot be negative cannot learn. Standard INT8
quantisation uses symmetric signed weights so the zero-point terms cancel.

**Consequence worth remembering:** under signed interpretation the mandated
saturation test (`0xFF × 0xFF`) computes `(−1) × (−1) = 1`, four times over,
totalling 4. That would pass on a 4-bit accumulator. The test only proves what
it is meant to prove in unsigned mode. Hence the mode bit, and we run the test
both ways.

## 5. Q7, AHB vs native — RESOLVED (native)

The PM confirmed **native** for both interfaces: the DMA↔SRAM master port and
the CPU↔NPU register port. APB is no longer part of the design. This
validates the argument below (kept for the record) and means `unpu_apb.sv`,
wherever it was going to live, becomes a native-protocol slave FSM instead —
a redesign, not a rename. See §12 for the full knock-on effect on the plan.

### Original argument (superseded by the answer above, kept for context)

The port list in the brief is labelled "Native Master Interface to SRAM" and
consists of `dma_addr`, `dma_wdata`, `dma_rdata`, `dma_wstrb`, `dma_valid`,
`dma_ready`. None of those are AHB signals — AHB needs `HADDR`, `HWRITE`,
`HTRANS`, `HSIZE`, `HBURST`, `HWDATA`, `HRDATA`, `HREADY`, `HRESP`.

That port list is, signal for signal, **PicoRV32's native memory interface**.
That interface's documented convention also answers Q5 and Q6 exactly as we
proposed: `mem_wstrb == 0` means read, and read data is valid in the same cycle
as `mem_ready`.

The "Native/AHB Data Plane" label in the block diagram sits on the CPU-to-arbiter
arrow, not on our DMA-to-arbiter arrow.

**Our proposal to the PM:** if the fabric must be AHB, Project 1 puts a
native-to-AHB bridge on the arbiter side rather than inside our macro. Our pins
freeze at hardening; their fabric does not. Moving us to AHB would add ~14 pins,
change the floorplan pin budget, and cost 20–30 hours.

**Until this is settled, do not write the DMA master.** Everything else can
proceed.

## 6. Decisions already made

| Decision | Rationale |
|---|---|
| 32-bit partial sums throughout | Un-overflowable for any layer; matches SRAM word width. Accepts 512 wires of vertical routing inside the array. |
| Build the de-skew bank (192 flops) | Alternative is skewing write addresses, which produces out-of-order writes and 4× the write traffic on a contended bus. |
| No hardware requantiser in v1 | ~10% of macro area for something the brief never asks for. Firmware does it. |
| Shift-down weight load, reverse row order, double-buffered | Avoids 128 broadcast wires. Costs 4 cycles, hidden by double-buffering. |
| Three FSMs, not one | APB must answer the bus regardless of compute state; DMA must wait on the arbiter without freezing sequencer counters. |
| One global `array_en`; no flow control inside the array | Partial freezing shears the wavefront into plausible wrong answers. |
| Symmetric weights, zero-point work in software | Keeps the PEs a plain integer dot product. |
| Build the 4-state DMA FSM first, optimise later | Collapsed version is much harder to debug while the arbiter is also under test. |
| Single-stage PE at 50 MHz | Two-stage requires a matching register on the activation path, doubles latency 7→14, and changes every timing number. |
| RTL in SystemVerilog, synthesisable subset only | Brief says Verilog; PM confirmed SV is acceptable. Constrained to the synthesisable subset so the Genus→IC Compiler handoff stays clean. |
| Matmul shape is A[M×K] × B[K×N] = C[M×N] | PM-specified. All of A, B signed int8; C is int32, **no requantization in hardware** — firmware's job, consistent with the existing "no hardware requantiser" decision above. |
| M, N, K each ≤ 4 at runtime, never > 4 | PM-confirmed. No tiling needed — the array's fixed 4×4 geometry covers every case. Sub-4 K/N falls out almost for free: zero-load unused weight rows/columns (`weight_reg` already resets to 0) and only write back the real N columns; no change to the timing contract or skew/de-skew depths. |
| CSR is 8 registers: `src_A`, `src_B`, `dest_C`, `dim_M`, `dim_N`, `dim_K`, `npu_ctrl`, `npu_status` | PM-directed. Supersedes the old 5-fixed-plus-2-optional register map. Register window extends past 0x18 — PM confirmed that's fine. Offset assignment (0x00–0x1C sequential) is Planning's proposal, not yet PM-confirmed — see the architecture snapshot in `docs/planning/unpu-architecture.html`. |
| No scan chain, no scan pins | PM-confirmed — not in scope for this project. Step 15 (scan chain insertion) is removed from the plan entirely. |

## 7. Still open

All four questions that were blocking RTL work (native vs. AHB, extra CSRs,
scan pins, port-list-frozen) are now answered — see §4 and §12. What's left:

1. Tools for DRC, LVS, formal equivalence, IR drop.
2. Who owns the arbiter RTL, us or the SoC team.
3. MNIST network shape. A 784→64 first layer needs 49 KB of INT8 weights; the
   whole SoC has 32 KB. The reference network does not fit. Options: shrink to
   784→16 (12.5 KB, still ~92%), downsample the input to 14×14, or stream
   weights over SPI.
4. CNN or MLP for the signoff test — the block diagram says CNN, the brief text
   says only "quantized MNIST digit".
5. SRAM memory layout — deliberately unfilled until the network size is decided.
6. **A final project document is coming from the PM** — per the user, hold off
   on any new design/planning work until it arrives; it may supersede some of
   §12 below. Finishing already-pending documentation/bookkeeping (this
   update) is fine; drafting new tasks is not, until that document lands.

## 8. Known errata in the notebook

The notebook was written before the PM's answers arrived and **still has not
been reconciled** — checked again as of §12's update, still stale. It is now
considerably further out of date than originally scoped:

- §13 still lists ~12 open questions; nearly all are now answered (§4).
- §16's hour budget and cut list assume tiling might be required. It is not.
- §12.2's pipelining discussion is now moot at 50 MHz.
- The entire control-plane discussion (§B1, the pinout tables, `MATRIX_CFG`,
  the two-phase APB FSM description — 43 APB/CSR/register references total)
  describes a design that no longer exists: control is native, not APB, and
  the register map is the 8-register `src_A`/`src_B`/`dest_C`/`dim_M`/`dim_N`/
  `dim_K`/`npu_ctrl`/`npu_status` list in §12 below, not `MATRIX_CFG`.

**Deliberately not reconciling it right now.** This is a full-section rewrite,
not a documentation-sync edit, and the user is waiting on a final project
document from the PM that may change things further — reconciling now risks
doing it twice. Treat `docs/unpu-notebook.html` as unreliable for anything
touched by §4, §7, or §12 of this file until that document lands and the
notebook gets a proper pass.

## 9. Plan shape

Eight weeks. Front end parallelises across five people; the back end is
sequential and supports about three. Three gates:

- **End W2** — identity test passing on the bare grid, weights forced by the
  testbench, no DMA, no APB, no FSM.
- **End W4** — RTL freeze, plus a real critical path number from a deliberately
  discarded trial hardening pass run in W3.
- **End W7** — STA clean, DRC/LVS clean, abstracts generated.

W8 is real buffer, not finishing touches.

**Build order:** PE → grid → identity → skew banks → sequencer → DMA → APB.
Outward from the arithmetic, one ring at a time. Teams that start from the bus
interface spend three weeks before they can multiply two numbers.

## 10. First tasks

1. Reconcile `docs/unpu-notebook.html` with §4 and §7 of this file.
2. Write `rtl/unpu_pe.v` and its directed unit test (20 vectors: max positive,
   max negative, zero weight, weight-load-while-computing).
3. Stand up the Genus flow on a trivial design — this is a full week of work and
   is the most commonly deferred, most commonly fatal task on the schedule.

## 11. Standing rule — commit and push per completed task

**Every completed task gets its own commit and push, immediately.** Do not
batch several tasks into one commit.

**Why:** a lost or wiped machine only loses uncommitted work. Commit-per-task
minimizes that window to at most one in-progress task, instead of however many
happened to accumulate before the next push. Not hypothetical — we already
recovered from exactly this scenario once, and the batched commit (tasks
001-003 together) was the one thing that could have gone wrong, even though it
didn't that time.

**Applies to:** Execution, since Execution is the session that writes code and
lands tasks. Read this before your first commit.

## 12. PM Q&A round 2 — architecture snapshot

Answers received directly from the user, sourced from a PM conversation.
Full detail in §4 (updated), §6 (decisions table, updated), §7 (still-open
list, updated). This section is the consolidated summary.

**Resolved:**
- Q7 — native interface, both DMA↔SRAM and CPU↔NPU. APB is out (§5).
- Extra CSRs — 8 registers, PM-directed list, window extends past 0x18 (§6).
- Scan pins — none. No scan chain in scope (§6). Step 15 removed from the plan.
- Port list — **negotiable**, not frozen. This contradicts CLAUDE.md's current
  hard constraint ("the `unpu_top` port list is frozen... requires instructor
  approval") and `docs/roles/execution.md`'s "do not add ports" line. Both are
  stale and outside Planning's write scope (`docs/planning/`,
  `session-handoff.md` only) — flagged to the user, and to Execution
  separately, for a fix in the files Execution can write.
- Matmul shape: A[M×K] × B[K×N] = C[M×N], signed int8 in, int32 out, no
  requantization in hardware. M, N, K each ≤ 4 at runtime (§6).

**A full architecture snapshot** (SoC context diagram, uNPU block diagram,
proposed CSR table, build-status-against-plan) was published as an artifact
and a static copy checked into the repo at
`docs/planning/unpu-architecture.html` for the record. Two assumptions in it
are flagged as unconfirmed, not PM fact: the CPU→uNPU register path bypassing
the SRAM arbiter entirely (inferred from the address ranges), and the
sequential 0x00–0x1C CSR offset assignment (Planning's proposal).

**Status as of this update:** the user is waiting on a final project document
from the PM. Per their instruction, no new design or planning work — task
drafting included — until it arrives. This section, and the rest of this
update pass, is closing out documentation that was already pending, not new
work.
