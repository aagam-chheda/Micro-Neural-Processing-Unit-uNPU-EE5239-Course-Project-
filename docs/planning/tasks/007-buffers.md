# Task 007 — Activation and weight buffers

## Goal

Build `unpu_wbuf` (double-buffered weight staging, shift-down/reverse-row
loading) and `unpu_actbuf` (double-buffered activation staging, natural-
order loading), replacing the direct-forcing stand-ins every prior task
has used for weights and activations. Prove double-buffering actually
decouples background loading from active compute — the entire point of
building it.

No new golden-model work this task — reuse the vector files task 006 Part
A already generated (`cross_terms`, `seq_m1`, `seq_k1`, `seq_n1`,
`seq_mixed`, `crv_0000..crv_0063`).

## Design source

`docs/unpu-notebook.html` §05, sections B4 (weight buffer) and B5
(activation buffer). These sections are **not** part of the control-plane
material `docs/session-handoff.md` §8 flags as stale (that's B1/APB/CSR
only) — B4/B5 are datapath decisions, still good. Quoted below because the
mechanism matters and shouldn't be re-derived from memory.

**B4, weight buffer (quoted):**
> Weights arrive as four 32-bit words and must end up in sixteen different
> PEs. Shift-down chain, reusing vertical neighbours: 4 buses of 8 bits, 4
> cycles. ... Shift-down chain, and load in reverse row order — row 3's
> weights pushed first, so after four shifts every value has settled in
> its intended row. This off-by-one is the most common bug in a first
> systolic array. Write it as a testbench assertion before writing the
> loader. Double-buffer the weight bank so the next tile's weights load
> while the current one streams.

**B5, activation buffer (quoted):**
> A register-file-based buffer rather than a second SRAM macro. ... Size
> is a live question ... We are provisionally taking 32×32 bits.

The B5 sizing question is now moot: it predates the PM's M/N/K≤4,
no-tiling confirmation (`docs/session-handoff.md` §6/§12). With no
tiling, one activation tile is at most 4×4 bytes (16 bytes), not the
32×32-bit/64×32-bit region the notebook was sizing for a still-open
tiling question. **Build `unpu_actbuf` sized for one 4×4 tile,
double-buffered (32 bytes total), not the notebook's provisional
figure** — this is a deliberate, reasoned departure from the notebook,
not an oversight; don't "fix" it back.

`unpu_grid.sv`'s weight-side ports are already frozen at full parallel
width (`weight_in[3:0][3:0][7:0]`, `weight_load[3:0][3:0]`, task 003) —
the "128 broadcast wires" the notebook worried about are already baked
into that interface and can't be un-baked by this task. What `unpu_wbuf`
still buys, despite that: it models the *actual* narrow arrival path
(weights will really arrive one 32-bit row at a time from `unpu_dma`,
step 10) and provides the double-buffering that decouples that slow
narrow trickle from the grid's need for all 128 bits at once, instantly,
on a tile swap.

## Files

- Create `rtl/unpu_wbuf.sv`
- Create `rtl/unpu_actbuf.sv`
- Create `tb/unpu_buf_tb.sv`

Do not modify `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`,
`rtl/unpu_deskew.sv`, `rtl/unpu_seq.sv`, or any existing testbench — all
frozen from prior tasks. This task's testbench drives `unpu_wbuf`/
`unpu_actbuf` directly; it does not go through `unpu_seq` (wiring those
together is top-level integration, step 14 — `unpu_seq` doesn't know
these buffers' load/swap protocol yet, and this task isn't the one that
teaches it).

## `unpu_wbuf`

```systemverilog
module unpu_wbuf (
  input  logic                  clk,
  input  logic                  rst_n,          // async, active-low
  input  logic                  array_en,       // same global freeze as grid/skew/deskew

  // Loading side -- fills the INACTIVE bank, one row of 4 weight bytes
  // (one per column) per cycle, presented in REVERSE row order: row 3
  // first, then 2, 1, 0. After 4 cycles every row has shifted down into
  // its correct position (see derivation below). This is the shape
  // unpu_dma will eventually feed (one 32-bit SRAM word per row); this
  // task's testbench drives it directly, no DMA yet.
  input  logic                  load_start,     // 1-cycle pulse; load_row must carry row 3's data on this same cycle
  input  logic [2:0]            load_k,         // real K (1-4) for this tile, latched at load_start
  input  logic [2:0]            load_n,         // real N (1-4) for this tile, latched at load_start
  input  logic [3:0][7:0]       load_row,       // this cycle's row of 4 weight bytes, one per column
  output logic                  load_busy,      // high for exactly the 4 loading cycles
  output logic                  load_done,      // 1-cycle pulse, the cycle after the 4th row is accepted

  // Swap side
  input  logic                  swap,           // 1-cycle pulse; only meaningful after load_done has fired since the last swap

  // Grid-facing side -- always reflects the ACTIVE bank
  output logic [3:0][3:0]       weight_load,    // -> unpu_grid.weight_load; pulsed '1 for exactly one cycle, on swap
  output logic [3:0][3:0][7:0]  weight_in       // -> unpu_grid.weight_in
);
```

### The shift-down/reverse-row mechanism, worked out

Internally: one 4-deep shift register per column (16 bytes total per
bank), `stage[col][0..3]`. Each cycle while loading: shift every stage
down by one and inject the new row at `stage[col][0]`:
```
stage[col][3] <= stage[col][2]
stage[col][2] <= stage[col][1]
stage[col][1] <= stage[col][0]
stage[col][0] <= load_row[col]   (masked per load_k/load_n, see below)
```
Trace it through, presenting rows in order 3, 2, 1, 0 (this is *why*
reverse order is required — verify this arithmetic before writing the
RTL, don't take it on faith):

| cycle | injected | stage[0] | stage[1] | stage[2] | stage[3] |
|---|---|---|---|---|---|
| 0 | row 3 | row3 | – | – | – |
| 1 | row 2 | row2 | row3 | – | – |
| 2 | row 1 | row1 | row2 | row3 | – |
| 3 | row 0 | row0 | row1 | row2 | row3 |

After cycle 3, `stage[col][r] == row r`'s data for every `r` — each row
has settled into the stage index matching its own row number. That's the
"off-by-one is the most common bug" the notebook warns about: get the
push order backwards (0,1,2,3 instead of 3,2,1,0) and every row ends up
one position away from where it belongs, and every downstream matmul
result is wrong in a way that still looks like plausible output. `stage`
IS the inactive bank; on `swap`, its contents (indexed `stage[col][row]`
→ `weight_in[row][col]`) become what's fed to the grid.

### K<4 / N<4 masking

Latch `load_k`/`load_n` on `load_start` (shadow copy — don't let them
change mid-load). Track an internal row-index counter for "which row is
being injected this cycle" (cycle 0 → row 3, cycle 1 → row 2, cycle 2 →
row 1, cycle 3 → row 0 — i.e. `row_idx = 3 - internal_cycle`). Before
injecting, force to zero:
- the whole row, if `row_idx >= load_k_latched`
- any column `j >= load_n_latched` within the row, regardless

This makes `unpu_wbuf` self-contained for zero-loading rather than
trusting the caller to pre-zero `load_row` — this is what plan.md step 9
means by "the buffer's loading sequence needs the real K/N to know how
much to load."

### Known trap

`unpu_pe.sv`'s weight latch only fires when `array_en` and `weight_load`
are both 1 on the same cycle (same trap task 006 hit for `LOAD_WEIGHTS`).
Assert `array_en=1` on the swap cycle, not just before/after it, or the
grid never actually latches the new bank.

## `unpu_actbuf`

```systemverilog
module unpu_actbuf (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  array_en,

  // Loading side -- fills the INACTIVE bank, one row of 4 activation
  // bytes (one per K-column) per cycle, in NATURAL row order (0, 1, 2, 3
  // -- no reversal). Activations are already consumed row-by-row in the
  // same order they arrive (unpu_skew takes A[m][*] at cycle m), so
  // there's no settling trick to get backwards here -- this is
  // deliberately simpler than unpu_wbuf, not an inconsistency.
  input  logic                  load_start,     // 1-cycle pulse; load_row must carry row 0's data on this same cycle
  input  logic [2:0]            load_m,         // real M (1-4), latched at load_start
  input  logic [2:0]            load_k,         // real K (1-4), latched at load_start
  input  logic [3:0][7:0]       load_row,       // this cycle's row of 4 activation bytes, one per K-column
  output logic                  load_busy,      // high for exactly the 4 loading cycles
  output logic                  load_done,      // 1-cycle pulse, the cycle after the 4th row is accepted

  input  logic                  swap,           // 1-cycle pulse; only meaningful after load_done has fired since the last swap

  // Read side -- combinational read of the ACTIVE bank
  input  logic [1:0]            rd_row,         // 0-3
  output logic [3:0][7:0]       rd_data         // active_bank[rd_row][*] -- wire straight into unpu_skew.a_raw
);
```

Internally: a plain 4×4×8-bit register file per bank (no shift network
needed — see above), written directly at row index = internal cycle
counter (0,1,2,3, in that order) while loading, masked the same way as
`unpu_wbuf` (rows `>= load_m_latched` forced to 0, columns `>=
load_k_latched` within a row forced to 0). `rd_data` is a plain
combinational read of the active bank at `rd_row`, no clock involved.

## Double buffering — the property this task exists to prove

Both modules hold two full banks. Loading always targets the bank that
is *not* currently active; `swap` flips which bank is active and (for
`unpu_wbuf`) re-latches the grid's weight registers. **The load sequence
must run to completion, and `swap` must be able to fire, while
`array_en` is high and the grid is mid-compute against the other,
currently-active bank — that's the entire reason to double-buffer.** If
your first-draft RTL has the inactive-bank shift register or write
sharing any state with the active-bank output path (a single bank
selected by index rather than two independent storage arrays with a
1-bit active-select register), it will not have this property and will
fail the concurrent-load test below.

## Testbench (`tb/unpu_buf_tb.sv`)

Instantiate `unpu_wbuf` + `unpu_actbuf` + `unpu_skew` + `unpu_grid` +
`unpu_deskew`, wired: `unpu_actbuf.rd_data` → (testbench presents it as)
`unpu_skew.a_raw`, driving `rd_row` with the same `m`-per-cycle pattern
`tb/unpu_skew_tb.sv`/`tb/unpu_stall_tb.sv` already use; `unpu_wbuf`'s
`weight_load`/`weight_in` → `unpu_grid`'s matching inputs;
`unpu_grid.psum_in` tied to 0. The testbench itself plays the role
`unpu_seq` will eventually play — driving `load_start`/`load_row`/`swap`
by hand — since this task doesn't touch `unpu_seq`.

### Directed

- **`cross_terms` (M=K=N=4) through both buffers**, load+swap both banks
  once, run the full matmul, check against `cross_terms_c.hex`. This is
  also the reverse-row-order regression: `cross_terms`'s `W` is
  asymmetric per row (same property that made it useful in task 004), so
  a reversed-row bug changes the answer, not just plausibly-wrong output.
- **Explicit whitebox settling check** (the notebook's own
  recommendation: "write it as a testbench assertion before writing the
  loader"): after `unpu_wbuf`'s 4-cycle load completes, before `swap`,
  read `stage[col][row]` hierarchically for all 16 positions and assert
  `stage[col][row] == W[row][col]` directly against the source data —
  independent of and in addition to the end-to-end matmul check above.
- **`seq_k1` (K=1), `seq_n1` (N=1), `seq_mixed` (M=3,K=2,N=3)** through
  both buffers, each checked against its own `_c.hex` over the true
  `M×N` submatrix — proves the K/N and M/K masking.
- **Concurrent-load-during-compute** (the double-buffering property
  itself): with bank A already active (loaded+swapped from one case,
  e.g. `cross_terms`), start streaming a full matmul against bank A
  while *simultaneously* driving a background `unpu_wbuf`/`unpu_actbuf`
  load of a *different* case (e.g. `seq_mixed`) into the inactive banks,
  `array_en=1` throughout. Assert: (a) the in-flight matmul against bank
  A still produces `cross_terms_c.hex` exactly, undisturbed by the
  concurrent load; (b) only after that matmul's results are fully read
  out, `swap` both buffers, run a second matmul, and confirm it now
  matches `seq_mixed_c.hex` — proving the swap correctly re-latches all
  16 PE weight registers and the new activation bank.

### Plus CRV

Iterate the 64 `crv_*` cases from task 006 Part A. For each: load+swap
into an already-active-and-computing setup from the *previous* iteration
(i.e. chain iterations back-to-back — case `i`'s load/swap happens
concurrently with case `i-1`'s compute, mirroring the directed
concurrent-load test above, not just a full reset-and-reload each time),
with the load-start point relative to case `i-1`'s compute stream
**also randomized** (early/mid/late in the compute, drawn from the same
seeded PRNG stream) — this is the "randomized weight-swap timing
relative to active compute" plan.md step 9 asks for. Self-check each
case's result against its `_c.hex` over its true `M×N` submatrix. Print
the seed once at the top (reuse `32'h5eed0006` from task 006, or a new
`32'h5eed0007` if you need an independent draw for the swap-timing
randomization — your call, just print whichever is used).

### Regression

`unpu_pe_tb`, `unpu_grid_tb`, `unpu_skew_tb`, `unpu_stall_tb`,
`unpu_seq_tb` still pass unchanged.

## Acceptance

- All directed cases pass, including the whitebox settling assertion.
- All 64 CRV cases pass with randomized concurrent swap timing, matching
  the golden model over each case's true `M×N` submatrix.
- The concurrent-load test demonstrates zero interference: bank-A compute
  results are bit-identical to a run with no concurrent load happening at
  all.
- Full regression green.
- Simulate clean — see the tooling note in `docs/planning/plan.md` before
  picking a simulator and writing the file header (Icarus vs. Verilator
  is currently an open, non-blocking decision; state which one you used
  and why, same as task 006 did).

## Out of scope

- No `unpu_dma` (step 10) — loading is still testbench-driven, not
  SRAM-sourced.
- No `unpu_seq` integration (step 14) — `unpu_seq` doesn't call these
  buffers' load/swap protocol yet.
- No CSR/register-map wiring.
- Don't touch `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`,
  `rtl/unpu_deskew.sv`, `rtl/unpu_seq.sv`, or any existing testbench.
