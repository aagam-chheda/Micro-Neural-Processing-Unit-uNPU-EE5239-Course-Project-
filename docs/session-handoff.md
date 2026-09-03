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
| 7 | Native or AHB data plane? | PM said **AHB**. We pushed back — see §5. **Still open.** |
| 8 | Worst-case arbiter grant latency? | No number. We co-design the arbiter with the SoC team; NPU has higher priority. |
| 9 | How does BIST reach us? | PM suggested over the bus. We agreed; no extra wrapper or test port needed. |

### Why we chose signed (Q2)

A layer whose weights cannot be negative cannot learn. Standard INT8
quantisation uses symmetric signed weights so the zero-point terms cancel.

**Consequence worth remembering:** under signed interpretation the mandated
saturation test (`0xFF × 0xFF`) computes `(−1) × (−1) = 1`, four times over,
totalling 4. That would pass on a 4-bit accumulator. The test only proves what
it is meant to prove in unsigned mode. Hence the mode bit, and we run the test
both ways.

## 5. The one blocking issue — Q7, AHB vs native

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

## 7. Still open

1. **Q7 AHB vs native** — blocking the DMA master.
2. Tools for DRC, LVS, formal equivalence, IR drop.
3. Who owns the arbiter RTL, us or the SoC team.
4. MNIST network shape. A 784→64 first layer needs 49 KB of INT8 weights; the
   whole SoC has 32 KB. The reference network does not fit. Options: shrink to
   784→16 (12.5 KB, still ~92%), downsample the input to 14×14, or stream
   weights over SPI.
5. CNN or MLP for the signoff test — the block diagram says CNN, the brief text
   says only "quantized MNIST digit".
6. Scan pins (`scan_en`, `scan_in`, `scan_out`) — not in the port list, not
   mentioned in the brief, but needed for tester access. Must close before
   floorplan.
7. SRAM memory layout — deliberately unfilled until the network size is decided.

## 8. Known errata in the notebook

The notebook was written before the PM's answers arrived. It has not yet been
reconciled. Specifically:

- §13 still lists 12 open questions; most are now answered (see §4 above).
- §16's hour budget and cut list assume tiling might be required. It is not, so
  the schedule buffer is roughly 20% rather than 4%.
- §12.2's pipelining discussion is now moot at 50 MHz.

**Reconciling the notebook against this file is a good first Planning task.**

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
