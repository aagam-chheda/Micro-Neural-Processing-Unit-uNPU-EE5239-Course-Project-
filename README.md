# uNPU — Micro Neural Processing Unit

A 4×4 INT8 weight-stationary systolic matrix-multiply accelerator, taken from RTL
toward a DRC/LVS-clean hard macro on SCL 180 nm.

**EE5239 · Chip Design and Tapeout · Project 2** — the uNPU subsystem of the
*Frankenstein* 180 nm IP-validation SoC.

| | |
|---|---|
| **Function** | `C = A × B`, where A is M×K, B is K×N, C is M×N |
| **Data types** | int8 in (signed or unsigned, selectable), int32 out |
| **Shape limits** | M, N, K each 1–4. No tiling. |
| **Array** | 4×4 = 16 processing elements, weight-stationary |
| **Target clock** | 50 MHz *(target — not yet confirmed by timing analysis)* |
| **Process** | SCL 180 nm |
| **Language** | SystemVerilog, synthesisable subset only |
| **RTL status** | Frozen at `87d31bf` (2026-09-15), reopened once for task 017 |

---

## Contents

- [What it does](#what-it-does)
- [Status](#status)
- [Quick start](#quick-start)
- [Repository layout](#repository-layout)
- [Architecture](#architecture)
- [Module reference](#module-reference)
- [Programming model](#programming-model)
- [The timing contract](#the-timing-contract)
- [Bus protocol](#bus-protocol)
- [Simulation](#simulation)
- [Verification](#verification)
- [Design decisions](#design-decisions)
- [Known limitations and open items](#known-limitations-and-open-items)
- [Coding conventions](#coding-conventions)
- [Documentation](#documentation)

---

## What it does

The uNPU is a memory-mapped peripheral on a small RISC-V SoC. The CPU writes three
pointers and three dimensions into its registers and sets a START bit. The block then
runs autonomously: its DMA fetches A and B from shared SRAM, the systolic array
computes `A × B`, and the result is written back to SRAM. A sticky DONE bit tells the
CPU when it can collect the answer.

Two properties shape the whole design:

**Weight-stationary.** The weights are loaded into the array once and held there while
activations stream past. This is the right strategy when the same weights are reused
across many inputs — which is exactly what inference does.

**M, N, K ≤ 4, always.** The array is physically 4×4 and no operand is larger, so there
is no tiling logic, no loop counters and no partial-result storage anywhere in the
design. Smaller shapes are handled by zero-padding: a zero weight nullifies its product
regardless of the activation it meets.

Results come back as raw int32 sums. There is no hardware requantiser — scaling back to
int8 is firmware's job.

---

## Status

| Area | State |
|---|---|
| RTL, all 11 modules | ✅ complete |
| Unit + constrained-random testing | ✅ 10/10 testbenches pass, 0 failures |
| Whole-design lint | ✅ clean (`-Wno-GENUNNAMED`) |
| C golden model | ✅ complete, self-checking |
| Synthesis (Genus) | ❌ not started — blocked on PDK access |
| Timing closure at 50 MHz | ❌ unconfirmed |
| Place & route (IC Compiler) | ❌ not started |
| DRC / LVS clean macro | ❌ not started — signoff tool not yet chosen |
| Bare-metal firmware | ❌ `fw/` is an empty placeholder |
| MNIST end-to-end demo | ❌ blocked on network-shape decision |

**"Frozen" here means functional correctness in simulation, and nothing else.** It does
not cover timing, physical verification or firmware.

---

## Quick start

Requires [Verilator](https://verilator.org) 5.x (with `--binary --timing` support) and
a C99 compiler.

```bash
git clone https://github.com/aagam-chheda/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project-.git
cd Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project-

# 1. Build the golden model and generate the reference vectors (292 files).
#    model/vectors/ is gitignored — you must generate it before running any test.
gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c
./model/golden

# 2. Build and run one testbench.
verilator --binary --timing -Wno-fatal \
          --top-module unpu_pe_tb --Mdir obj_dir/unpu_pe_tb \
          rtl/*.sv tb/unpu_pe_tb.sv
./obj_dir/unpu_pe_tb/Vunpu_pe_tb
```

> **Always run from the repository root.** The testbenches open their vectors at the
> relative path `model/vectors/<case>_a.hex`, so the working directory matters.

With the [Makefile](#simulation) below in the repo root, all of that collapses to:

```bash
make            # generate vectors, then build and run all ten testbenches
make unpu_pe_tb # or just one
make lint       # whole-design lint
```

---

## Repository layout

```
rtl/            SystemVerilog RTL — 11 modules, one per file
tb/             Testbenches — 10, one per module or module group
model/          golden.c, the C reference model (vectors/ is generated, gitignored)
fw/             Bare-metal C firmware                        (empty — not written yet)
constraints/    SDC timing constraints                       (empty — not written yet)
syn/            Genus synthesis scripts and reports          (empty — blocked on PDK)
pnr/            IC Compiler scripts and reports              (empty — blocked on PDK)
scripts/        Utility scripts
docs/           Design notebook, planning records, session handoff, freeze report
```

---

## Architecture

Three independent state machines and two buses. The split is deliberate: the bus
interface must answer the CPU regardless of compute state, the DMA must be able to wait
indefinitely on a contended arbiter, and the sequencer must count compute cycles without
those waits perturbing it.

```
   CPU / SPI                                                    done / error
   backdoor                                                          │
       │  mem_*                                                      ▼
       ▼         ┌────────────┐      ┌──────────┐      ┌─────────────────────┐
   ────────────► │ unpu_slave │ ───► │ unpu_csr │ ───► │       unpu_seq      │
                 │  bus glue  │      │ 8 regs   │      │  11-state sequencer │
                 └────────────┘      └──────────┘      └──────────┬──────────┘
                                                                  │
                                            job_start / kind / addr│    ▲ c_in
                                                                  ▼    │
        SRAM arbiter  ◄───────── dma_* ─────────────  ┌─────────────────┴───┐
                                                      │      unpu_dma       │
                                                      └──┬───────────────┬──┘
                                              weights ───┘               └─── activations
   ┌─────────────────────────────────────────────────────┼───────────────┼──────────┐
   │ DATAPATH — one global array_en freezes every register in here together          │
   │                                                     ▼               ▼           │
   │   ┌─────────────┐                          ┌──────────────┐                     │
   │   │  unpu_wbuf  │ ──── weight_in ────────► │              │                     │
   │   │   2 banks   │      weight_load         │  unpu_grid   │    ┌──────────────┐ │
   │   └─────────────┘                          │   4×4 PEs    │───►│ unpu_deskew  │─┼──► c_in
   │   ┌─────────────┐   ┌────────────┐         │ weight-stat. │psum│   3/2/1/0    │ │
   │   │ unpu_actbuf │──►│ unpu_skew  │───────► │              │    └──────────────┘ │
   │   │   2 banks   │   │  0/1/2/3   │  act_in └──────────────┘                     │
   │   └─────────────┘   └────────────┘                                              │
   └────────────────────────────────────────────────────────────────────────────────┘
```

**Life of one job**

1. CPU writes `src_a`, `src_b`, `dest_c`, `dim_m`, `dim_n`, `dim_k`, then sets START.
2. `LATCH_CFG` — sequencer takes a private shadow copy of every register and validates
   that M, N, K are all in 1–4. Illegal dimensions go straight to `ERROR`.
3. `W_FETCH` — DMA reads K words from `src_b`, stages them, then bursts four clean
   cycles into `unpu_wbuf`'s inactive bank, **bottom row first**.
4. `W_SWAP` — one pulse; all 16 PEs latch their weight simultaneously.
5. `A_FETCH` / `A_SWAP` — the same for M words from `src_a` into `unpu_actbuf`.
6. `COMPUTE` — M+7 cycles. One activation row is presented per cycle; the skew bank
   staggers it into the array; from cycle 7 one finished row of C is captured per cycle.
7. `WRITE_OUTPUT` — DMA writes M×N words back to `dest_c`.
8. `DONE` pulses; `npu_status.DONE` latches and holds until the next START.

For a 4×4×4 job on an idle bus, roughly 11 of ~75 cycles are the arithmetic. Most of a
job is memory traffic — which is why the arbiter gives this block higher priority than
the CPU.

---

## Module reference

| File | Lines | Role |
|---|---:|---|
| `rtl/unpu_pe.sv` | 48 | One MAC: multiply stored weight by incoming activation, add the partial sum from the north, pass the activation east and the sum south. Single-stage, not pipelined. |
| `rtl/unpu_grid.sv` | 70 | 16 PEs in a 4×4 mesh. Pure wiring. North edge tied to 0 (no accumulate mode); east edge unconnected by design. |
| `rtl/unpu_skew.sv` | 73 | Input delay bank — row *k* delayed by *k* cycles (0/1/2/3). Row 0 is a wire, not a register. |
| `rtl/unpu_deskew.sv` | 71 | Output alignment bank — column *j* delayed by (3−*j*) cycles (3/2/1/0). Column 3 is a wire. |
| `rtl/unpu_wbuf.sv` | 218 | Weight storage. Two independent banks, 4-deep shift register per column, **loaded in reverse row order**. Zero-masks rows past K and columns past N. |
| `rtl/unpu_actbuf.sv` | 155 | Activation storage. Two independent banks, plain indexed write in natural order. Read side is purely combinational. |
| `rtl/unpu_dma.sv` | 234 | Bus master. One job at a time: fetch A, fetch B, write back C. 4-state handshake plus a `BUF_LOAD` state that decouples the bus from the buffers' gap-free load requirement. |
| `rtl/unpu_seq.sv` | 338 | The sequencer. 11 states, shadow-latched config, single shared cycle counter, one long `array_en` window. |
| `rtl/unpu_csr.sv` | 170 | The eight registers, plus write-1-to-pulse START, sticky DONE and the inverted SIGNED polarity. |
| `rtl/unpu_slave.sv` | 69 | Bus slave. Pure combinational glue — `mem_ready` tied high so it can never stall or hang. |
| `rtl/unpu_top.sv` | 314 | Integration. Ten instances, plus the two provisional `npu_enable` / `npu_start_req` pins. |

---

## Programming model

### Register map

Window: `0x4000_0000` – `0x4000_0FFF`.

| Offset | Name | Access | Contents |
|---|---|---|---|
| `0x00` | `src_a` | R/W | Byte address of A in SRAM |
| `0x04` | `src_b` | R/W | Byte address of B (weights) in SRAM |
| `0x08` | `dest_c` | R/W | Byte address to write C to |
| `0x0C` | `dim_m` | R/W | M, bits `[2:0]`, legal 1–4 |
| `0x10` | `dim_n` | R/W | N, bits `[2:0]`, legal 1–4 |
| `0x14` | `dim_k` | R/W | K, bits `[2:0]`, legal 1–4 |
| `0x18` | `npu_ctrl` | R/W | bit0 `START` (write-1-to-pulse, always reads 0) · bit1 `SIGNED` |
| `0x1C` | `npu_status` | RO | bit0 `DONE` (sticky) · bit1 `ERROR` · bits `[4:2]` error code |

Anything past `0x1C` reads as 0 and ignores writes.

> ⚠️ **The eight-register list is confirmed; the specific offsets above are Planning's
> proposal and have not been signed off.** Treat them as provisional.

Two behaviours worth knowing:

- **`SIGNED` is inverted internally.** The register stores the bit as written, but the
  PE port is named `mode_unsigned`, so `unpu_csr` drives `mode_unsigned = ~ctrl_signed_reg`.
  A register round-trip test cannot catch a mistake here — only an output-polarity check can.
- **`DONE` is sticky.** `unpu_seq.done` is a single-cycle pulse; the register latches it
  and holds it until the next START, so firmware can poll at its own pace.

Error codes: `3'd1` = illegal `dim_m` / `dim_n` / `dim_k`. No others are implemented.

### Memory layout

| Tensor | Address | Words fetched/written | Notes |
|---|---|---|---|
| A | `src_a + row*4` | M | One 32-bit word per row. Byte *i* of a word is element *i* of that row, byte 0 in bits `[7:0]`. |
| B | `src_b + row*4` | K | Same shape. The DMA pushes rows into the weight buffer last-row-first. |
| C | `dest_c + m*16 + j*4` | M×N | Fixed 16-byte row stride whatever N is, but only the N real words per row are written — unused slots are skipped, not zeroed. |

The fixed stride means firmware can index C identically regardless of N, while no bus
cycles are spent on columns nobody asked for.

> ⚠️ This addressing convention is the design team's proposal and has not been confirmed
> against firmware, which does not exist yet.

### Example firmware

```c
#include <stdint.h>

#define UNPU_BASE    0x40000000u
#define UNPU_REG(o)  (*(volatile uint32_t *)(UNPU_BASE + (o)))

#define UNPU_SRC_A   UNPU_REG(0x00)
#define UNPU_SRC_B   UNPU_REG(0x04)
#define UNPU_DEST_C  UNPU_REG(0x08)
#define UNPU_DIM_M   UNPU_REG(0x0C)
#define UNPU_DIM_N   UNPU_REG(0x10)
#define UNPU_DIM_K   UNPU_REG(0x14)
#define UNPU_CTRL    UNPU_REG(0x18)
#define UNPU_STATUS  UNPU_REG(0x1C)

#define CTRL_START   (1u << 0)
#define CTRL_SIGNED  (1u << 1)
#define STAT_DONE    (1u << 0)
#define STAT_ERROR   (1u << 1)
#define STAT_CODE(s) (((s) >> 2) & 0x7u)

/* Computes C = A * B. Returns 0 on success, or the error code on failure. */
int unpu_matmul(const void *a, const void *b, void *c,
                unsigned m, unsigned n, unsigned k, int is_signed)
{
    UNPU_SRC_A  = (uint32_t)a;
    UNPU_SRC_B  = (uint32_t)b;
    UNPU_DEST_C = (uint32_t)c;
    UNPU_DIM_M  = m;               /* 1..4 */
    UNPU_DIM_N  = n;               /* 1..4 */
    UNPU_DIM_K  = k;               /* 1..4 */

    UNPU_CTRL = CTRL_START | (is_signed ? CTRL_SIGNED : 0u);

    for (;;) {
        uint32_t s = UNPU_STATUS;
        if (s & STAT_ERROR) return (int)STAT_CODE(s);   /* 1 = illegal M/N/K */
        if (s & STAT_DONE)  return 0;
    }
    /* Note: there is no timeout in hardware. See "Known limitations". */
}
```

Laying out an operand is just packing four bytes per row:

```c
/* A[m][k], M=2 K=3 -> two words, columns past K zero-padded by the hardware */
uint32_t A[4] = {
    (uint32_t)(uint8_t)a00 | ((uint32_t)(uint8_t)a01 << 8) | ((uint32_t)(uint8_t)a02 << 16),
    (uint32_t)(uint8_t)a10 | ((uint32_t)(uint8_t)a11 << 8) | ((uint32_t)(uint8_t)a12 << 16),
};
/* C comes back as int32, 16-byte row stride: C[m][j] is at ((int32_t *)c)[m*4 + j] */
```

---

## The timing contract

Every module agrees with these. They are derived from the array geometry, not chosen.

| Event | Cycle |
|---|---|
| `A[m][k]` enters the west edge of row *k* | `m + k` |
| `A[m][k]` reaches `PE(k, j)` | `m + k + j` |
| `C[m][j]` leaves the south edge of column *j* | `m + j + 4` |
| Row `C[m][*]` aligned after de-skew | `m + 7` |
| Total compute cycles for M rows | `M + 7` |
| Skew depths, in / out | `0,1,2,3` / `3,2,1,0` |

Each eastward hop through a PE costs one cycle (hence the `+j`); each southward hop
costs one cycle (hence the `+4`); the de-skew bank adds the remaining `+3`.

**Any change that would alter one of these is cross-cutting, not local.** It ripples
through the skew depths, the sequencer's stop condition, the capture window and the
golden model. The most obvious such change is pipelining the PE multiplier — it would
need a matching register on the activation path and double the latency from 7 to 14.
At 50 MHz there is no need, which is why the single-stage PE and the 50 MHz target are
really one decision.

---

## Bus protocol

Both ports use PicoRV32's native memory convention. (An earlier revision used APB; that
was removed once native was confirmed for both sides.)

| Port | Direction | Purpose |
|---|---|---|
| `mem_*` | Slave | The CPU, or the SPI debug backdoor, reads and writes our registers. |
| `dma_*` | Master | We read and write shared SRAM on our own initiative. |

The convention, identical on both:

- `wstrb == 4'h0` means **read**; `4'hF` means write all four bytes. No partial writes
  exist anywhere in this design.
- Read data is valid on the **same cycle** that `valid` and `ready` are both high — not
  the cycle after.
- A transfer happens, and the address advances, **only** on a cycle where both are high.
  In `unpu_dma` this is structural: the counters can only change in `D_ACK`, which is
  only reachable once `dma_ready` has been observed high.
- `mem_ready` is tied high permanently. A configuration register has no business
  stalling a CPU, and the SPI backdoor that may also drive this port must never hang.

`unpu_slave` assumes an external decoder has already filtered traffic to our window —
it takes `mem_addr[11:2]` as the word offset and does not check the `0x4000_` prefix.
This assumption has been confirmed.

### Provisional top-level pins

`unpu_top` carries two extra inputs added after the freeze, implementing one sketch of a
possible handshake with the SoC's address decoder:

- `npu_enable` — gates `mem_valid` into the slave. When low, reads return 0 and writes
  do nothing, while `mem_ready` still ties high so the bus never stalls.
- `npu_start_req` — a registered rising-edge detector, OR'd with the existing
  register-write START.

Both are handled entirely inside `unpu_top` by gating existing wires; no submodule was
touched. The register-write START path still works alongside them. **This is provisional
pending a cross-team conversation** and may be confirmed, adjusted or reverted.

---

## Simulation

Verilator 5.x is the standing simulator (Xcelium was the original intent but is not
available in the development environment). Some file headers still mention Icarus
Verilog from early tasks; each carries an adjacent note saying the line is stale.

Drop this `Makefile` in the repository root:

```makefile
# ---- tools -------------------------------------------------------------------
VERILATOR ?= verilator
CC        ?= gcc
VFLAGS    ?= --binary --timing -Wno-fatal -j 0

RTL  := $(wildcard rtl/*.sv)
TBS  := $(notdir $(basename $(wildcard tb/*_tb.sv)))

.PHONY: all test vectors lint clean $(TBS)

all: test

# ---- golden model and reference vectors --------------------------------------
model/golden: model/golden.c
	$(CC) -std=c99 -Wall -Wextra -o $@ $<

model/vectors/.stamp: model/golden
	./model/golden > /dev/null && touch $@

vectors: model/vectors/.stamp

# ---- one testbench:  make unpu_pe_tb -----------------------------------------
$(TBS): %: model/vectors/.stamp
	$(VERILATOR) $(VFLAGS) --top-module $@ --Mdir obj_dir/$@ $(RTL) tb/$@.sv
	./obj_dir/$@/V$@

# ---- the whole regression ----------------------------------------------------
test: $(TBS)

# ---- whole-design lint -------------------------------------------------------
lint:
	$(VERILATOR) --lint-only -Wall -Wno-GENUNNAMED --top-module unpu_top $(RTL)

clean:
	rm -rf obj_dir model/golden model/golden.exe model/vectors
```

Then:

```bash
make               # vectors + all ten testbenches
make unpu_seq_tb   # one testbench
make lint          # elaborate unpu_top and lint the whole design
make clean
```

### What each testbench covers

| Testbench | Modules under test |
|---|---|
| `unpu_pe_tb` | `unpu_pe` |
| `unpu_grid_tb` | `unpu_grid` |
| `unpu_skew_tb` | `unpu_skew` → `unpu_grid` → `unpu_deskew` |
| `unpu_stall_tb` | same chain, exercising `array_en` freeze behaviour |
| `unpu_buf_tb` | `unpu_wbuf`, `unpu_actbuf` + the compute chain |
| `unpu_dma_tb` | `unpu_dma` driving `unpu_wbuf` / `unpu_actbuf` |
| `unpu_seq_tb` | `unpu_seq` orchestrating the real DMA, buffers and array |
| `unpu_csr_tb` | `unpu_csr` |
| `unpu_slave_tb` | `unpu_slave` → `unpu_csr` |
| `unpu_top_tb` | `unpu_top`, driven only through its real external ports |

---

## Verification

`model/golden.c` is a host-side C reference that computes the same matmul and emits
`$readmemh`-compatible vector files under `model/vectors/`. Every testbench checks
against it rather than against hand-derived expected values — a systolic array that is
wrong produces plausible numbers, not crashes, so a trusted independent oracle is the
only way to be sure.

The model self-checks before writing anything: `identity`, `all_ones` and `cross_terms`
are verified against known results, and the run aborts without writing vectors if any
fails.

**Two tests aimed at two specific bugs.** The **identity test** multiplies by the
identity matrix — the output must be exactly the input, so any wavefront misalignment is
immediately visible. The **saturation test** multiplies maximum-magnitude bytes to prove
the accumulator does not wrap; note it only proves anything in *unsigned* mode, since
signed `0xFF × 0xFF` is `(−1) × (−1) = 1`. This is why the mode bit exists and the test
runs both ways.

**Constrained random on top of that.** Random data across the full signed byte range,
random M/N/K, random bus back-pressure, random swap and stall placement — all from
printed seeds (`CRV_SEED = 32'h5eed0006` in `golden.c`) so any failure replays exactly.

Freeze-gate results (all zero failures):

| Testbench | Reported |
|---|---|
| `unpu_pe_tb` | 131,072 exhaustive (every input pair × both sign modes) + 256 accumulator + 50 timing iterations |
| `unpu_grid_tb` | 68 cases, 684 checks |
| `unpu_skew_tb` | 636 checks |
| `unpu_stall_tb` | 2,544 result checks + 26,055 frozen-register checks |
| `unpu_seq_tb` | 539 checks |
| `unpu_buf_tb` | 531 checks, including loading during an active computation |
| `unpu_dma_tb` | 1,110 checks with randomised back-pressure |
| `unpu_csr_tb` | 200 iterations, 1,838 checks |
| `unpu_slave_tb` | 150 iterations, 2,115 checks |
| `unpu_top_tb` | 512 checks through the external ports only |

Run three independent ways at the freeze gate: with the recorded seed, with a freshly
drawn seed, and against a from-scratch rebuild of all 292 vector files (byte-identical).
Full detail in `docs/freeze-report.md`.

---

## Design decisions

| Decision | Why | Cost |
|---|---|---|
| 32-bit accumulators throughout | Un-overflowable for any realistic layer; matches the SRAM word width | 512 wires of vertical routing inside the array |
| Build the de-skew bank | The alternative is out-of-order writes and ~4× the write traffic on a contended bus | 192 flip-flops |
| No hardware requantiser | ~10% of macro area for something the brief never asks for | Firmware must do it |
| Weights shifted in, reverse row order, double-buffered | Avoids 128 broadcast wires across the array | 4 load cycles, fully hidden by the second bank |
| Three FSMs, not one | The bus must answer regardless of compute state; the DMA must wait on the arbiter without freezing the sequencer's counters | More modules, but each small enough to reason about completely |
| One global `array_en`, no flow control inside the array | Freezing part of a systolic array shears the wavefront and turns a stall into wrong answers | The whole datapath stalls together |
| Single-stage PE at 50 MHz | Two stages would double latency 7→14 and change every timing number | The design is pinned near this clock speed |
| Signed by default, unsigned mode bit | A layer whose weights cannot go negative cannot learn; but the mandated saturation test is meaningless in signed mode | One easy-to-invert-by-accident polarity |
| M, N, K capped at 4 | No tiling logic, no loop counters, no partial-result storage | Firmware must split anything larger |
| Native bus both sides, not APB/AHB | The port list in the brief is, signal for signal, PicoRV32's native interface | If the fabric needs AHB, a bridge goes outside this macro |
| DMA as four un-collapsed states | A collapsed handshake is much harder to debug while the arbiter is also under test | A couple of cycles per beat |
| No scan chain, no scan pins | Confirmed out of scope | No structured manufacturing test; BIST reaches the block over the normal bus |

---

## Known limitations and open items

**Hardware limitations**

- **No timeout or bus-error path.** The only error code implemented is `3'd1` (illegal
  dimensions). A DMA job that never receives a response waits forever with `busy` high.
  Given the "must never hang" requirement on the slave port, a watchdog is worth
  considering.
- **No accumulate mode.** The array's north edge is tied to zero; every job starts from
  nothing.
- **No requantisation, no activation function, no bias.** Raw int32 out.
- **M, N, K > 4 are rejected**, not split. Anything larger must be tiled in software.

**Open project items**

| Item | Where it stands |
|---|---|
| PDK and tool-server access | Not available. Blocks synthesis, P&R, STA and everything below the freeze line. |
| MNIST network shape | A 784→64 first layer needs ~49 KB of int8 weights; the SoC has 32 KB. Options: shrink to 784→16 (12.5 KB, ~92% accurate), downsample inputs to 14×14, or stream weights over SPI. The memory map cannot be finalised until this is decided. |
| CNN or MLP for the signoff test | The brief's block diagram and its text disagree. Affects firmware, not hardware. |
| `npu_enable` / `npu_start_req` | Provisional, pending the SoC-team conversation. A discrete START pin would change the top-level port list and force re-hardening. |
| Arbiter ownership | Undecided between this team and the SoC team. |
| DRC / LVS / formal / IR-drop tools | None chosen. A DRC/LVS-clean macro is an explicit deliverable, so this gap needs closing before the back-end phase. |
| CSR offset assignment | Proposed, not confirmed. |

**Documentation debt**

- `CLAUDE.md`'s repo-layout section lists `.v` extensions and a `unpu_apb.v` that was
  designed out, and omits `unpu_slave.sv`. The files on disk are correct; only the
  description is stale. (Task 016.)
- `docs/unpu-notebook.html` predates the supervisor's answers and is unreliable for
  anything touching the control plane, the register map or the open-questions list.
  Treat `docs/session-handoff.md` as authoritative instead.

---

## Coding conventions

- **SystemVerilog, synthesisable subset only.** `logic`, `always_ff` / `always_comb`,
  packed arrays, enums for FSM states. Anything Genus rejects is not worth the elegance.
- **Reset is asynchronous, active-low, everywhere:**
  `always_ff @(posedge clk or negedge rst_n)`.
- **FSM outputs are Moore** — pure combinational functions of the current state.
  Registering them reads the old state on the same edge the state updates, which
  delayed `weight_load` and `done` by a cycle in an early draft.
- **`array_en` gates every register in the datapath**, including the delay banks and the
  buffers' bank selects.
- **Anything that must be correct on the same cycle as a pulse looks *ahead*** to what a
  register is about to become, rather than reading what it currently is. See
  `effective_sel` in `unpu_wbuf.sv` and `rd_row` in `unpu_seq.sv`.
- One module per file; the filename matches the module name.
- Signal names are written exactly as in the RTL in prose — `dma_ready`, not "the ready
  signal".
- Nothing lands on `main` until its unit test passes; one commit per completed task.

> **The recurring bug in this project.** Three separate times, in three different
> modules, the same shape appeared: *reading a register on the same edge that changes
> it*, and acting on a value one cycle out of date. It showed up as a stale bank select
> on a swap, an activation row presented a cycle late, and outputs registered off the old
> FSM state. The last two conventions above exist specifically to prevent it.

---

## Documentation

| File | What it is |
|---|---|
| `docs/session-handoff.md` | **Authoritative.** Every decision made, every answer received, and what is still open. Read this first. |
| `docs/freeze-report.md` | The six-part RTL freeze verification record. Stands alone. |
| `docs/planning/plan.md` | Step-by-step build plan with per-step status. |
| `docs/planning/tasks/` | One file per task, with the reasoning behind each module. |
| `docs/planning/unpu-architecture.html` | Architecture snapshot: SoC context, block diagram, proposed CSR table. |
| `docs/pm/sequencer-fsm.txt` | The supervisor's own sequencer FSM sketch, filed verbatim. |
| `docs/unpu-notebook.html` | Original design notebook. **Stale** — see documentation debt above. |
| `docs/unpu-simulator.html` | Interactive dataflow simulator. |

---

## Credits

Course project for **EE5239, RTL to GDSII**. Team of five, ~8 weeks.

The block is Project 2 of the *Frankenstein* 180 nm IP-validation SoC; Project 1 owns the
PicoRV32 core, the 32 KB SRAM, the arbiter and the SPI controller.
