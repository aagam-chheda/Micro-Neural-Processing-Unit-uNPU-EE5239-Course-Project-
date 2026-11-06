
# µNPU — Architecture & Hierarchy Guide

> **EE5239 Course Project** — A 4×4 INT8 weight-stationary systolic matrix-multiply accelerator (SCL 180 nm)

This document is a self-contained guide for anyone trying to understand the RTL, testbench, and golden-model files in this repository. It walks through the file structure, the top-level architecture, every module's role and interfaces, the systolic timing contract, and how the testbenches verify the design.

---

## Table of Contents

1. [Repository File Structure](#1-repository-file-structure)
2. [High-Level Architecture Overview](#2-high-level-architecture-overview)
3. [Module Hierarchy & Signal Flow](#3-module-hierarchy--signal-flow)
4. [Detailed Module Descriptions (RTL)](#4-detailed-module-descriptions-rtl)
   - 4.1 [unpu_top — Top-Level Integration](#41-unpu_top--top-level-integration)
   - 4.2 [unpu_apb — APB Slave Interface](#42-unpu_apb--apb-slave-interface)
   - 4.3 [unpu_csr — Control/Status Register File](#43-unpu_csr--controlstatus-register-file)
   - 4.4 [unpu_seq — Main Sequencer FSM](#44-unpu_seq--main-sequencer-fsm)
   - 4.5 [unpu_dma — DMA Engine](#45-unpu_dma--dma-engine)
   - 4.6 [unpu_wbuf — Weight Double-Buffer](#46-unpu_wbuf--weight-double-buffer)
   - 4.7 [unpu_actbuf — Activation Double-Buffer](#47-unpu_actbuf--activation-double-buffer)
   - 4.8 [unpu_skew — Input Skew Network](#48-unpu_skew--input-skew-network)
   - 4.9 [unpu_grid — 4×4 Systolic PE Array](#49-unpu_grid--44-systolic-pe-array)
   - 4.10 [unpu_pe — Processing Element](#410-unpu_pe--processing-element)
   - 4.11 [unpu_deskew — Output De-skew Network](#411-unpu_deskew--output-de-skew-network)
5. [The Systolic Timing Contract](#5-the-systolic-timing-contract)
6. [CSR Register Map](#6-csr-register-map)
7. [Sequencer FSM State Machine](#7-sequencer-fsm-state-machine)
8. [DMA Engine State Machine](#8-dma-engine-state-machine)
9. [Golden Model (model/)](#9-golden-model-model)
10. [Testbench Guide (tb/)](#10-testbench-guide-tb)
11. [Design Conventions & Key Traps](#11-design-conventions--key-traps)

---

## 1. Repository File Structure

```
.
├── rtl/                        # Synthesisable SystemVerilog RTL
│   ├── unpu_top.sv             # Top-level integration (pure wiring)
│   ├── unpu_apb.sv             # APB slave — CPU ↔ NPU register interface
│   ├── unpu_csr.sv             # Control/Status register file (8 registers)
│   ├── unpu_seq.sv             # Main sequencer FSM (orchestrates the entire op)
│   ├── unpu_dma.sv             # DMA master — SRAM ↔ buffers data movement
│   ├── unpu_wbuf.sv            # Double-buffered weight staging
│   ├── unpu_actbuf.sv          # Double-buffered activation staging
│   ├── unpu_skew.sv            # Input skew network (0/1/2/3 cycle delays)
│   ├── unpu_grid.sv            # 4×4 systolic PE array (generates 16 unpu_pe)
│   ├── unpu_pe.sv              # Single processing element (INT8 MAC)
│   └── unpu_deskew.sv          # Output de-skew network (3/2/1/0 cycle delays)
│
├── tb/                         # Self-checking SystemVerilog testbenches
│   ├── unpu_pe_tb.sv           # PE unit test: directed + exhaustive sweep
│   ├── unpu_grid_tb.sv         # Grid-level matmul test (hand-skewed inputs)
│   ├── unpu_skew_tb.sv         # End-to-end skew → grid → deskew chain
│   ├── unpu_stall_tb.sv        # Freeze/resume via array_en
│   ├── unpu_buf_tb.sv          # Double-buffer integration (concurrent load/compute)
│   ├── unpu_dma_tb.sv          # DMA + buffers + behavioural SRAM
│   ├── unpu_csr_tb.sv          # CSR directed + CRV vs. shadow model
│   ├── unpu_apb_tb.sv          # APB + CSR integration
│   ├── unpu_seq_tb.sv          # Full-stack: seq + DMA + buffers + datapath
│   ├── unpu_top_tb.sv          # CPU's-eye-view integration (APB + SRAM)
│   ├── unpu_ext1_tb.sv         # External peer smoke test (adapted)
│   └── unpu_ext2_tb.sv         # External peer stress test (adapted)
│
├── model/                      # C golden model & test vectors
│   └── golden.c                # Reference C = A × W computation
│
├── fw/                         # Bare-metal C firmware (for the SoC CPU)
├── constraints/                # SDC timing constraints
├── syn/                        # Synthesis scripts & reports (Genus)
├── pnr/                        # Place-and-route scripts & reports (ICC)
├── scripts/                    # Utility / run scripts
└── docs/                       # Design notebook, handoff docs, planning
```

---

## 2. High-Level Architecture Overview

The µNPU is a **weight-stationary 4×4 INT8 systolic array** accelerator designed to compute matrix multiplications of the form **C = A × W**, where:

- **A** (activation matrix): up to 4×4, INT8
- **W** (weight matrix): up to 4×4, INT8
- **C** (result matrix): up to 4×4, INT32 (32-bit accumulator)

The design supports both **signed** and **unsigned** INT8 arithmetic, selectable via a control register.

### Key Design Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Array size | 4 × 4 | 16 PEs in a 2D grid |
| Data width | INT8 | Weights and activations |
| Accumulator | 32-bit | Partial-sum width throughout |
| Target clock | 50 MHz | Single-stage PE (no pipelining) |
| Dimensions M, N, K | 1–4 each | Configurable per operation |
| CPU interface | APB slave | 4 KB register window |
| Memory interface | Native master | To shared SRAM via arbiter |

### External Ports (unpu_top)

The design presents exactly **two interfaces** to the rest of the SoC:

1. **APB Slave Port** — CPU-facing (or SPI debug backdoor), for register reads/writes
2. **Native Master Port** — SRAM-facing, for DMA data transfers

```
                ┌──────────────────────────────────────────┐
   APB Bus      │                                          │   Native Bus
  (CPU side)    │              unpu_top                     │   (SRAM side)
                │                                          │
  paddr    ───▸ │                                          │ ◂──▸ dma_addr
  pwdata   ───▸ │     ┌─────┐  ┌─────┐  ┌──────┐          │ ◂──▸ dma_wdata
  pwrite   ───▸ │     │ APB │─▸│ CSR │─▸│ SEQ  │─▸┌─────┐ │ ◂──▸ dma_rdata
  psel     ───▸ │     └─────┘  └─────┘  └──────┘  │ DMA │─┼─────▸ dma_wstrb
  penable  ───▸ │                           │      └─────┘ │ ────▸ dma_valid
  prdata   ◂─── │                    ┌──────┘              │ ◂──── dma_ready
  pready   ◂─── │              ┌─────┼─────┐               │
                │              │  Buffers   │               │
                │              │ wbuf  actbuf│              │
                │              └─────┼─────┘               │
                │              ┌─────┼─────┐               │
                │              │  Datapath  │               │
                │              │skew→grid→  │               │
                │              │   deskew   │               │
                │              └───────────┘               │
                └──────────────────────────────────────────┘
```

---

## 3. Module Hierarchy & Signal Flow

### Instantiation Hierarchy

```
unpu_top
├── unpu_apb       (u_apb)       — APB protocol → CSR port translation
├── unpu_csr       (u_csr)       — 8 control/status registers
├── unpu_seq       (u_seq)       — Main sequencer FSM
├── unpu_dma       (u_dma)       — DMA engine (SRAM ↔ buffers)
├── unpu_wbuf      (u_wbuf)      — Double-buffered weight staging
├── unpu_actbuf    (u_actbuf)    — Double-buffered activation staging
├── unpu_skew      (u_skew)      — Input skew (row-delay) network
├── unpu_grid      (u_grid)      — 4×4 systolic array
│   └── unpu_pe    (pe) × 16    — Individual processing elements
└── unpu_deskew    (u_deskew)    — Output de-skew (column-delay) network
```

### End-to-End Data Flow

The complete signal path for one matrix-multiply operation:

```
CPU writes registers via APB
         │
         ▼
    ┌─────────┐     ┌─────────┐     ┌──────────┐
    │ unpu_apb│────▸│ unpu_csr│────▸│ unpu_seq │
    └─────────┘     └─────────┘     └────┬─────┘
                                         │ job dispatch
                                         ▼
                                    ┌──────────┐     ┌──────┐
                                    │ unpu_dma │◂───▸│ SRAM │
                                    └────┬─────┘     └──────┘
                              ┌──────────┼──────────┐
                              ▼                      ▼
                         ┌─────────┐           ┌──────────┐
                         │unpu_wbuf│           │unpu_actbuf│
                         └────┬────┘           └─────┬─────┘
                              │ weight_load/in       │ rd_data
                              ▼                      ▼
                         ┌─────────┐           ┌──────────┐
                         │         │◂──────────│ unpu_skew│
                         │unpu_grid│           └──────────┘
                         │  (4×4)  │
                         └────┬────┘
                              │ psum_out
                              ▼
                         ┌───────────┐
                         │unpu_deskew│
                         └─────┬─────┘
                               │ c_out → c_in back to unpu_seq
                               ▼
                    unpu_seq captures → c_dst → unpu_dma writes back to SRAM
```

---

## 4. Detailed Module Descriptions (RTL)

### 4.1 unpu_top — Top-Level Integration

**File:** `rtl/unpu_top.sv`
**Lines:** 287 | **Instances:** 10 sub-modules

This is **pure wiring** — no logic of its own. It instantiates all ten modules and connects them according to the signal flow above. Key wiring decisions:

- `grid_psum_in` (north edge of the systolic array) is **tied to zero** — no accumulate-across-passes mode exists.
- `grid_act_out` (east edge) is **left unconnected** — activations flow west→east through the PEs but the east-edge output serves no purpose.
- `c_dst` from `unpu_seq` connects **directly** to `c_src` on `unpu_dma` — the shapes were deliberately built to match, requiring no adapter.

### 4.2 unpu_apb — APB Slave Interface

**File:** `rtl/unpu_apb.sv`
**Lines:** 94 | **Logic:** Pure combinational (no flip-flops)

Translates APB bus transactions into the simple `csr_sel`/`csr_wdata`/`csr_wen`/`csr_rdata` port that `unpu_csr` exposes.

- **`pready`** is tied to `1'b1` — the CSR never stalls.
- **`csr_sel`** = `paddr[11:2]` — word offset within the 4 KB window (10 bits, 1024 words).
- **`csr_wen`** = `psel && penable && pwrite` — only the ACCESS phase commits a write (not SETUP alone).
- No PSLVERR — every transaction succeeds.

**Assumptions baked in:**
1. `paddr` is already window-filtered (an external decoder asserts `psel` for this peripheral).
2. Full-word writes only — no byte-lane strobes (PSTRB).

### 4.3 unpu_csr — Control/Status Register File

**File:** `rtl/unpu_csr.sv`
**Lines:** 171

Pure control-plane storage. Implements 8 registers with specific access semantics (see [§6 CSR Register Map](#6-csr-register-map)). Key behaviors:

- **START** (`npu_ctrl[0]`) is **write-1-to-pulse** — writing 1 to bit 0 generates a one-cycle `start_pulse` to the sequencer (registered, one cycle after the qualifying write). Reads back as 0 always.
- **SIGNED** (`npu_ctrl[1]`): bit1=1 means "signed mode." The output `mode_unsigned` is the **inverse** (`~ctrl_signed_reg`).
- **DONE** (`npu_status[0]`): **sticky** — latched when `done_i` pulses, cleared by the next `start_pulse`. Priority: start-clear wins over done-set on coincidence.
- **ERROR/error_code** (`npu_status[1]`, `npu_status[4:2]`): combinational pass-through from `unpu_seq` (already latched upstream).
- Unmapped registers (offsets 8–1023): reads return 0, writes are silently ignored.

### 4.4 unpu_seq — Main Sequencer FSM

**File:** `rtl/unpu_seq.sv`
**Lines:** 339

The brain of the accelerator. Orchestrates the entire operation: DMA fetch → buffer swap → compute → DMA writeback. See [§7 Sequencer FSM](#7-sequencer-fsm-state-machine) for the full state diagram.

**Key responsibilities:**
- Shadow-latches configuration (`dim_m/n/k`, `mode_unsigned`, `src_a/b`, `dest_c`) to prevent mid-operation corruption.
- Validates dimensions (1–4 legal, else ERROR with `error_code = 3'd1`).
- Dispatches DMA jobs via `job_start`/`job_kind`/`job_base_addr`.
- Controls buffer swaps (`w_swap`, `a_swap`) and activation row selection (`rd_row`).
- Drives `array_en` (global datapath enable) and `mode_unsigned_o`.
- Captures output results into `c_dst[m][j]` from `c_in` starting at cycle ≥ 7.

**Critical design detail:** `rd_row` is a **combinational** output (not registered) — matching the zero-latency read of `unpu_actbuf`.

### 4.5 unpu_dma — DMA Engine

**File:** `rtl/unpu_dma.sv`
**Lines:** 235

Moves data between shared SRAM and the internal buffers. Handles three job types:

| `job_kind` | Value | Direction | Description |
|------------|-------|-----------|-------------|
| `JOB_FETCH_A` | `2'd0` | SRAM → actbuf | Fetch activation matrix (M words) |
| `JOB_FETCH_W` | `2'd1` | SRAM → wbuf | Fetch weight matrix (K words) |
| `JOB_WRITE_C` | `2'd2` | NPU → SRAM | Write result matrix (M×N words) |

See [§8 DMA State Machine](#8-dma-engine-state-machine) for the FSM details.

**Key architectural feature:** A 4-entry `stage` array decouples bus back-pressure from buffer loading — fetched words are accumulated across potentially stalled bus beats, then drained in a clean 4-cycle burst during `BUF_LOAD`.

**Addressing convention:**
- A/W fetch: `addr = base + row × 4` (one 32-bit word per row)
- C writeback: `addr = dest_C + m × 16 + j × 4` (16-byte row stride, N actual words per row)

### 4.6 unpu_wbuf — Weight Double-Buffer

**File:** `rtl/unpu_wbuf.sv`
**Lines:** 219

Double-buffered weight staging with **4-deep shift registers** per column. Two fully independent banks (`bank_a`, `bank_b`) allow background loading while the grid computes from the active bank.

**Critical: Reverse row loading order.** Rows are loaded in order 3→2→1→0 (not 0→1→2→3). After 4 shift cycles, each row settles into its correct stage index. Loading in natural order is "the most common bug in a first systolic array."

```
cycle | injected | stage[0] | stage[1] | stage[2] | stage[3]
  0   | row 3    | row3     | -        | -        | -
  1   | row 2    | row2     | row3     | -        | -
  2   | row 1    | row1     | row2     | row3     | -
  3   | row 0    | row0     | row1     | row2     | row3
```

**Swap lookahead:** On the swap cycle, `effective_sel` looks ahead to what `active_sel` is **about to become** so `weight_in` shows the new bank immediately — otherwise the PE would latch stale pre-swap weights.

**K/N masking:** Rows beyond `load_k` and columns beyond `load_n` are forced to zero.

### 4.7 unpu_actbuf — Activation Double-Buffer

**File:** `rtl/unpu_actbuf.sv`
**Lines:** 156

Similar to `unpu_wbuf` but simpler — uses **direct indexed writes** (not a shift register) because activations are consumed in natural row order.

- **Load order:** Natural (0, 1, 2, 3) — no reversal needed.
- **Read side:** Pure combinational read (`rd_data = active_bank[rd_row]`), no clock involved.
- **M/K masking:** Rows beyond `load_m` and columns beyond `load_k` are zeroed.

### 4.8 unpu_skew — Input Skew Network

**File:** `rtl/unpu_skew.sv`
**Lines:** 74

Delays each row's activation by a different number of clock cycles so they arrive at the systolic grid with the correct diagonal timing:

| Row | Delay (cycles) | Implementation |
|-----|---------------|----------------|
| 0   | 0             | Wire (no register) |
| 1   | 1             | 1 flip-flop |
| 2   | 2             | 2 flip-flops (shift chain) |
| 3   | 3             | 3 flip-flops (shift chain) |

**Trap:** Row 0's delay is a **wire**, not a register. This is correct — registering it would add an extra cycle of latency to row 0 only, breaking the timing contract.

### 4.9 unpu_grid — 4×4 Systolic PE Array

**File:** `rtl/unpu_grid.sv`
**Lines:** 71

A `generate`-based 4×4 grid of `unpu_pe` instances with systematic interconnection:

- **Activations flow west → east** (horizontally): Column 0 gets external `act_in[row]`; each subsequent column gets the previous column's `act_out`.
- **Partial sums flow north → south** (vertically): Row 0 gets external `psum_in[col]` (tied to 0); each subsequent row gets the previous row's `psum_out`.
- **Weights** are loaded per-PE via individual `weight_load[row][col]` and `weight_in[row][col]` signals.

```
          psum_in[0]  psum_in[1]  psum_in[2]  psum_in[3]
              │           │           │           │
              ▼           ▼           ▼           ▼
act_in[0] ─▸ PE(0,0) ──▸ PE(0,1) ──▸ PE(0,2) ──▸ PE(0,3) ──▸ act_out[0]
              │           │           │           │
              ▼           ▼           ▼           ▼
act_in[1] ─▸ PE(1,0) ──▸ PE(1,1) ──▸ PE(1,2) ──▸ PE(1,3) ──▸ act_out[1]
              │           │           │           │
              ▼           ▼           ▼           ▼
act_in[2] ─▸ PE(2,0) ──▸ PE(2,1) ──▸ PE(2,2) ──▸ PE(2,3) ──▸ act_out[2]
              │           │           │           │
              ▼           ▼           ▼           ▼
act_in[3] ─▸ PE(3,0) ──▸ PE(3,1) ──▸ PE(3,2) ──▸ PE(3,3) ──▸ act_out[3]
              │           │           │           │
              ▼           ▼           ▼           ▼
         psum_out[0] psum_out[1] psum_out[2] psum_out[3]
```

### 4.10 unpu_pe — Processing Element

**File:** `rtl/unpu_pe.sv`
**Lines:** 49

The fundamental compute unit. One **multiply-accumulate per clock**, no pipelining (50 MHz target).

**Operation each enabled clock cycle:**
```
psum_out ← psum_in + (weight_reg × act_in)     // signed or unsigned per mode
act_out  ← act_in                               // registered pass-through
```

- **Weight capture:** On `weight_load` pulse (while `array_en` is high), `weight_reg ← weight_in`. The captured weight is used for all subsequent multiplications until the next load.
- **Mode select:** `mode_unsigned = 1` → unsigned multiply; `mode_unsigned = 0` → signed (two's-complement) multiply.
- **Freeze:** When `array_en = 0`, all registers hold their values — including `weight_reg`, even if `weight_load` is asserted.

### 4.11 unpu_deskew — Output De-skew Network

**File:** `rtl/unpu_deskew.sv`
**Lines:** 72

The mirror image of `unpu_skew`, applied to the partial-sum outputs. Realigns staggered column outputs so all four columns of a result row become valid simultaneously.

| Column | Delay (cycles) | Implementation |
|--------|---------------|----------------|
| 0      | 3             | 3 flip-flops (shift chain) |
| 1      | 2             | 2 flip-flops (shift chain) |
| 2      | 1             | 1 flip-flop |
| 3      | 0             | Wire (no register) |

After de-skew, `c_out[0..3]` presents a complete result row at cycle **m + 7** for row m.

---

## 5. The Systolic Timing Contract

These four equations govern every module's design. They are **derived** from the array geometry, not chosen arbitrarily.

```
A[m][k] enters west edge of row k        at cycle   m + k
A[m][k] arrives at PE(k, j)              at cycle   m + k + j
C[m][j] leaves south edge of column j   at cycle   m + j + 4
whole row C[m][*] valid after de-skew    at cycle   m + 7
total cycles for a pass of M rows                   M + 7
```

**Skew depths:**
- Input side (unpu_skew): rows 0/1/2/3 → delays 0/1/2/3
- Output side (unpu_deskew): columns 0/1/2/3 → delays 3/2/1/0

**Any change that alters these numbers is a cross-cutting change**, not a local one.

---

## 6. CSR Register Map

The µNPU has 8 software-visible registers in a 4 KB window (base `0x4000_0000`):

| Offset | Word Sel | Name | Access | Description |
|--------|----------|------|--------|-------------|
| `0x00` | 0 | `src_a` | R/W | Pointer to activation matrix A in SRAM |
| `0x04` | 1 | `src_b` | R/W | Pointer to weight matrix W in SRAM |
| `0x08` | 2 | `dest_c` | R/W | Pointer to result matrix C in SRAM |
| `0x0C` | 3 | `dim_m` | R/W | Rows of A / C (bits[2:0] only, valid 1–4) |
| `0x10` | 4 | `dim_n` | R/W | Columns of W / C (bits[2:0] only, valid 1–4) |
| `0x14` | 5 | `dim_k` | R/W | Contraction dim / rows of W (bits[2:0] only, valid 1–4) |
| `0x18` | 6 | `npu_ctrl` | R/W | Control: bit0 = **START** (W1P), bit1 = **SIGNED** mode |
| `0x1C` | 7 | `npu_status` | RO | Status: bit0 = **DONE**, bit1 = **ERROR**, bits[4:2] = **error_code** |

**Programming sequence for a matmul:**
1. Write `src_a`, `src_b`, `dest_c` with SRAM addresses
2. Write `dim_m`, `dim_n`, `dim_k` with dimensions (1–4 each)
3. Write `npu_ctrl` = `{SIGNED_bit, 1'b1}` to start (bit1 selects signed/unsigned, bit0 triggers)
4. Poll `npu_status` until bit0 (DONE) = 1
5. Result matrix C is now in SRAM at `dest_c`

---

## 7. Sequencer FSM State Machine

The sequencer has **11 states**:

```
                    start                     dim_illegal
        ┌────┐    pulse     ┌───────────┐    ┌───────┐
   ────▸│IDLE│────────────▸│ LATCH_CFG │───▸│ ERROR │◂─┐
        └────┘              └─────┬─────┘    └───┬───┘  │
          ▲                       │ dims OK       │start │
          │                       ▼               └──────┘
          │                 ┌─────────┐
          │                 │ W_FETCH │──(job_done)──▸┐
          │                 └─────────┘               │
          │                 ┌────────┐                │
          │                 │ W_SWAP │◂───────────────┘
          │                 └───┬────┘
          │                     ▼
          │                 ┌─────────┐
          │                 │ A_FETCH │──(job_done)──▸┐
          │                 └─────────┘               │
          │                 ┌────────┐                │
          │                 │ A_SWAP │◂───────────────┘
          │                 └───┬────┘
          │                     ▼
          │                 ┌─────────┐
          │                 │ COMPUTE │──(cycle == m+6)──▸┐
          │                 └─────────┘                    │
          │                 ┌─────────────┐                │
          │                 │ READ_OUTPUT │◂───────────────┘
          │                 └──────┬──────┘
          │                        ▼
          │                 ┌──────────────┐
          │                 │ WRITE_OUTPUT │──(job_done)──▸┐
          │                 └──────────────┘               │
          │                 ┌──────┐                       │
          └─────────────────│ DONE │◂──────────────────────┘
                            └──────┘
```

**State descriptions:**

| State | Purpose |
|-------|---------|
| `IDLE` | Waiting for start. `array_en = 0`. |
| `LATCH_CFG` | Shadow-copies dims and pointers. Validates dims (1–4 legal). |
| `W_FETCH` | Dispatches `JOB_FETCH_W` to DMA, waits for `job_done`. |
| `W_SWAP` | Pulses `w_swap` (one cycle) to flip weight buffer banks. |
| `A_FETCH` | Dispatches `JOB_FETCH_A` to DMA, waits for `job_done`. |
| `A_SWAP` | Pulses `a_swap` (one cycle) to flip activation buffer banks. |
| `COMPUTE` | Runs M+7 cycles. `rd_row` selects activation rows. Captures `c_in` into `c_dst` from cycle 7 onward. |
| `READ_OUTPUT` | One transition cycle before writeback. |
| `WRITE_OUTPUT` | Dispatches `JOB_WRITE_C` to DMA, waits for `job_done`. |
| `DONE` | Pulses `done` for exactly one cycle, then returns to IDLE. |
| `ERROR` | Sticky error state. `error = 1`, holds until next `start`. |

---

## 8. DMA Engine State Machine

The DMA uses a **5-state FSM** for each job:

```
          job_start
   ┌──────┐      ┌───────┐  dma_ready   ┌───────┐
──▸│D_IDLE│─────▸│ D_REQ │────────────▸│ D_ACK │
   └──────┘      └───────┘              └───┬───┘
      ▲                ▲                     │
      │                │              ┌──────┴───────┐
      │                │              │ more beats?  │
      │                │              ├───YES────────┘
      │                │              │
      │          ┌─────┴──┐           │ last beat (fetch)
      │          │BUF_LOAD│◂──────────┘
      │          └────┬───┘
      │               │ 4 cycles done
      │          ┌────┴──┐
      └──────────│ D_FIN │  (pulses job_done)
                 └───────┘
```

| State | Purpose |
|-------|---------|
| `D_IDLE` | Waiting for `job_start`. Latches job parameters. |
| `D_REQ` | Asserts `dma_valid`, holds address/data stable until `dma_ready`. |
| `D_ACK` | Captures read data into `stage[]` (for fetch). Advances beat. |
| `BUF_LOAD` | Drains `stage[]` into actbuf/wbuf load port over 4 clean cycles. |
| `D_FIN` | Pulses `job_done` for one cycle. |

For `JOB_WRITE_C`, the flow skips `BUF_LOAD` (no staging needed, data is read combinationally from `c_src`).

---

## 9. Golden Model (model/)

**File:** `model/golden.c` — Plain C99, host-side tool.

Computes reference **C = A × W** and emits `$readmemh`-compatible hex vector files under `model/vectors/` for use by RTL testbenches.

### Test Vector Cases Generated

| Case Name | M | K | N | Mode | Purpose |
|-----------|---|---|---|------|---------|
| `identity` | 4 | 4 | 4 | Signed | W = I₄, verifies C == A |
| `all_ones` | 4 | 4 | 4 | Signed | All 1s, verifies every C[m][j] == 4 |
| `cross_terms` | 4 | 4 | 4 | Signed | Non-trivial W, catches row/col swap bugs |
| `random_signed` | 4 | 4 | 4 | Signed | Full-byte-range PRNG (seed `0xC0FFEE`) |
| `random_unsigned` | 4 | 4 | 4 | Unsigned | Full-byte-range PRNG (seed `0xDEADBEEF`) |
| `seq_m1` | 1 | 4 | 4 | Signed | M < 4 edge case |
| `seq_k1` | 4 | 1 | 4 | Signed | K < 4 edge case |
| `seq_n1` | 4 | 4 | 1 | Signed | N < 4 edge case |
| `seq_mixed` | 3 | 2 | 3 | Signed | Non-square, non-power-of-2 |
| `crv_0000`–`crv_0063` | 1–4 | 1–4 | 1–4 | Random | 64 CRV cases (seed `0x5eed0006`) |

**PRNG:** Deterministic xorshift32 — bit-for-bit reproducible across machines/compilers.

**Output files per case:**
- `<name>_a.hex` — Activation bytes (16 bytes, 4×4 zero-padded)
- `<name>_w.hex` — Weight bytes (16 bytes)
- `<name>_c.hex` — Expected result words (M×4 int32)
- `<name>_meta.txt` — M, MODE, K, N metadata

**Usage:** Run `model/golden` from the repo root to (re)generate all vectors before running testbenches.

---

## 10. Testbench Guide (tb/)

All testbenches are **self-checking** — they print PASS/FAIL and exit with a non-zero status on failure. Simulated with **Verilator** (`--binary --timing`).

### Testbench Coverage Matrix

| Testbench | DUT(s) Under Test | What It Proves | Test Strategy |
|-----------|--------------------|----------------|---------------|
| ``unpu_pe_tb`` | `unpu_pe` | MAC correctness, weight capture, freeze | 20 directed + 256×256 exhaustive (both modes) + randomised timing |
| ``unpu_grid_tb`` | `unpu_grid` (16 PEs) | Full-array matmul with hand-skewed inputs | Golden-model vectors + 64-case CRV sweep |
| ``unpu_skew_tb`` | `unpu_skew` + `unpu_grid` + `unpu_deskew` | Timing contract through real skew/deskew RTL | Golden-model vectors + 64-case CRV sweep |
| ``unpu_stall_tb`` | skew + grid + deskew | `array_en` freeze/resume bit-identical to unstalled | Baseline + early/mid/late stalls × 64 CRV cases |
| ``unpu_buf_tb`` | `unpu_wbuf` + `unpu_actbuf` + datapath | Double-buffering (concurrent load & compute) | `fork…join` concurrent processes |
| ``unpu_dma_tb`` | `unpu_dma` + buffers | DMA fetch/writeback with SRAM back-pressure | Behavioural SRAM + randomised `dma_ready` |
| ``unpu_csr_tb`` | `unpu_csr` | Register semantics, start_pulse timing, polarity | Directed + CRV vs. shadow model |
| ``unpu_apb_tb`` | `unpu_apb` + `unpu_csr` | APB protocol correctness, SETUP vs ACCESS | Directed (pready always checked) |
| ``unpu_seq_tb`` | `unpu_seq` + DMA + buffers + full datapath | Full orchestration: fetch → swap → compute → writeback | Behavioural SRAM + golden vectors |
| ``unpu_top_tb`` | `unpu_top` (full design) | CPU's-eye-view: APB register programming → result check | APB transactions + behavioural SRAM |
| ``unpu_ext1_tb`` | `unpu_top` | External peer smoke test (adapted from DiP-array) | Independent reference model, both modes |
| ``unpu_ext2_tb`` | `unpu_top` | External peer stress test (adapted) | All 64 M×N×K combos, back-pressure, corner values |

### Verification Hierarchy (Bottom-Up)

```
Level 1 (Unit):      unpu_pe_tb
                          │
Level 2 (Block):     unpu_grid_tb       unpu_csr_tb
                          │                  │
Level 3 (Chain):     unpu_skew_tb       unpu_apb_tb
                     unpu_stall_tb
                          │
Level 4 (Subsystem): unpu_buf_tb
                     unpu_dma_tb
                          │
Level 5 (Integration): unpu_seq_tb
                          │
Level 6 (Top):       unpu_top_tb
                     unpu_ext1_tb
                     unpu_ext2_tb
```

---

## 11. Design Conventions & Key Traps

### Conventions

| Convention | Description |
|------------|-------------|
| **One module per file** | Filename matches module name (`unpu_pe.sv` → `module unpu_pe`) |
| **Single global `array_en`** | One enable signal freezes the entire datapath — no per-row/per-column flow control |
| **Moore outputs** | FSM outputs are combinational functions of the current state (no extra register delay) |
| **Async active-low reset** | All modules use `negedge rst_n` |
| **Shadow-latched config** | Sequencer and DMA latch their inputs at job start to prevent mid-operation corruption |
| **Bounded wait loops** | Every testbench uses bounded `for` loops with explicit caps, never open-ended `while` |

### Known Traps (Documented in Source)

| Trap | Where | Description |
|------|-------|-------------|
| **Weight load order** | `unpu_wbuf` | Must load rows in **reverse** order (3→0). Natural order silently produces wrong results. |
| **Swap-cycle lookahead** | `unpu_wbuf` | `weight_in` must reflect the **new** bank on the swap cycle, not the old one. Uses `effective_sel = active_sel ^ (swap && array_en)`. |
| **Skew row 0 is a wire** | `unpu_skew` | Row 0 has **zero** delay. Adding a register breaks the timing contract. Same applies to `unpu_deskew` column 3. |
| **`rd_row` must be combinational** | `unpu_seq` | Registering `rd_row` would introduce a 1-cycle lag, presenting the wrong activation row to the grid. |
| **`job_issued` flag** | `unpu_seq` | DMA dispatch states must pulse `job_start` exactly **once** per visit, then hold it low. The `job_issued` flag prevents re-firing. |
| **`array_en` on swap cycle** | `unpu_wbuf`/`unpu_actbuf` | `array_en` must be 1 on the exact swap cycle, or the grid never latches the new weights. |
| **DONE → IDLE settle** | `unpu_seq` | `start` must not be issued until one cycle **after** `done=1` is observed — the FSM is still in DONE state on that cycle and only transitions to IDLE on the next edge. |
| **SIGNED polarity** | `unpu_csr` | `npu_ctrl[1]=1` means **signed mode**. The PE uses `mode_unsigned`. The CSR inverts: `mode_unsigned = ~ctrl_signed_reg`. Getting this backwards silently runs every matmul with the wrong sign interpretation. |

---

*Document generated from source code analysis of all files in `rtl/`, `tb/`, and `model/` directories.*
