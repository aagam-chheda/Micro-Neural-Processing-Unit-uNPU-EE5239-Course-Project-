# µNPU Quick Reference — EE5239

A 4×4 INT8 weight-stationary systolic array that computes **C = A × W** in hardware. Targets 50 MHz on SCL 180 nm.

---

## What the design does

The CPU programs a handful of registers over APB, writes the `START` bit, and polls `DONE`. In the background the hardware:
1. **Fetches** weights (W) and activations (A) from shared SRAM into on-chip double-buffers via DMA.
2. **Computes** the matrix multiply through a 4×4 grid of processing elements (PEs).
3. **Writes** the result matrix (C) back to SRAM.

---

## File layout

```
rtl/        RTL source (SystemVerilog)
tb/         Self-checking testbenches
model/      C golden model + test vectors
fw/         Bare-metal firmware
constraints/  SDC timing
syn/        Synthesis (Genus)
pnr/        Place-and-route (ICC)
```

---

## RTL modules at a glance

| File | Role |
|------|------|
| `unpu_top.sv` | Top-level — pure wiring, no logic |
| `unpu_apb.sv` | APB slave — translates CPU bus transactions to register accesses |
| `unpu_csr.sv` | 8 control/status registers (src_a, src_b, dest_c, dim_m/n/k, ctrl, status) |
| `unpu_seq.sv` | Main FSM — orchestrates the entire operation (fetch → compute → writeback) |
| `unpu_dma.sv` | DMA engine — moves data between SRAM and buffers |
| `unpu_wbuf.sv` | Double-buffered weight staging (shift-register load, reverse order) |
| `unpu_actbuf.sv` | Double-buffered activation staging (direct-write load, natural order) |
| `unpu_skew.sv` | Delays each activation row by 0/1/2/3 cycles before the grid |
| `unpu_grid.sv` | 4×4 grid of PEs (generated with `genvar`) |
| `unpu_pe.sv` | Single MAC unit — one multiply-accumulate per clock |
| `unpu_deskew.sv` | Delays each result column by 3/2/1/0 cycles to realign outputs |

**Instantiation tree:** `unpu_top` → {`unpu_apb`, `unpu_csr`, `unpu_seq`, `unpu_dma`, `unpu_wbuf`, `unpu_actbuf`, `unpu_skew`, `unpu_grid` → 16× `unpu_pe`, `unpu_deskew`}

---

## Signal flow (one operation)

```
CPU  →[APB]→  unpu_apb  →  unpu_csr  →  unpu_seq
                                              │
                           ┌──────────────────┤ job dispatch
                           ↓                  ↓
                        unpu_dma  ←→  SRAM (via dma_* port)
                           │
              ┌────────────┴────────────┐
              ↓                         ↓
          unpu_wbuf               unpu_actbuf
              │                         │
              └──── unpu_grid ←── unpu_skew
                        │
                    unpu_deskew
                        │
               c_out → unpu_seq (captured into c_dst) → unpu_dma → SRAM
```

---

## Sequencer FSM states

`IDLE → LATCH_CFG → W_FETCH → W_SWAP → A_FETCH → A_SWAP → COMPUTE → READ_OUTPUT → WRITE_OUTPUT → DONE → IDLE`

Error path: `LATCH_CFG` goes to `ERROR` if any dim is 0 or > 4. Stays in `ERROR` until next `START`.

---

## Key register map

| Offset | Name | Notes |
|--------|------|-------|
| `0x00` | `src_a` | SRAM address of activation matrix A |
| `0x04` | `src_b` | SRAM address of weight matrix W |
| `0x08` | `dest_c` | SRAM address to write result C |
| `0x0C–0x14` | `dim_m/n/k` | Dimensions 1–4 each |
| `0x18` | `npu_ctrl` | bit0 = START (write-1-to-pulse), bit1 = SIGNED mode |
| `0x1C` | `npu_status` | bit0 = DONE (sticky), bit1 = ERROR, bits[4:2] = error code |

---

## Testbenches at a glance

| Testbench | Tests |
|-----------|-------|
| `unpu_pe_tb` | PE MAC — exhaustive 256×256 operand sweep |
| `unpu_grid_tb` | 4×4 array matmul with hand-skewed inputs |
| `unpu_skew_tb` | Full skew → grid → deskew chain |
| `unpu_stall_tb` | `array_en` freeze/resume correctness |
| `unpu_buf_tb` | Double-buffer concurrent load & compute |
| `unpu_dma_tb` | DMA with randomised SRAM back-pressure |
| `unpu_csr_tb` | Register semantics vs. shadow model |
| `unpu_apb_tb` | APB protocol + CSR together |
| `unpu_seq_tb` | Full-stack: seq + DMA + buffers + datapath |
| `unpu_top_tb` | CPU's-eye-view end-to-end test |
| `unpu_ext1/2_tb` | Adapted external peer testbenches |

All testbenches are **self-checking** and run with **Verilator** (`--binary --timing`).

---

## Golden model (`model/golden.c`)

Run `model/golden` from the repo root to generate reference hex vectors under `model/vectors/`. Testbenches load these files; do not hand-derive expected values.

---

## Three things to know before reading the RTL

1. **`array_en`** is a single global freeze — when low, every register in the entire datapath holds. No per-module enable.
2. **Weight buffer loads rows in reverse order** (3 → 0). Natural order (0 → 3) silently produces wrong results.
3. **`mode_unsigned = ~SIGNED_bit`** — writing 1 to `npu_ctrl[1]` selects *signed* arithmetic; the PE convention is inverted.
