# Task 011 — Revise `unpu_seq` for real DMA/buffer orchestration

## Why this task exists (read this before the interface below)

Step 14 (top-level integration) is next in the plan, and its dependencies
(steps 1, 4, 6–10, 12–13) are all done. But going through them to wire
`unpu_top` together surfaces a real gap: **`unpu_seq` as built in task
006 cannot actually drive `unpu_dma`, `unpu_wbuf`, or `unpu_actbuf`.**

Task 006 built `unpu_seq` against `a_src`/`w_src` (whole matrices
presented up front) and direct `weight_load`/`weight_in`/`a_raw` outputs
wired straight to `unpu_skew`/`unpu_grid` — explicitly a stand-in, since
`unpu_wbuf`/`unpu_actbuf`/`unpu_dma` didn't exist yet (task 006's own
"out of scope" section says so). Tasks 007–010 then built the real
buffers, DMA, CSR, and native slave — but every one of them, correctly
scoped at the time, left `unpu_seq` untouched and testbench-driven
directly. Nothing in the codebase currently has a signal path from
`unpu_seq` to `unpu_dma`'s job port or `unpu_wbuf`/`unpu_actbuf`'s
load/swap port. That path has to exist for `docs/CLAUDE.md`'s own
system description to be true — "our DMA fetches tensors from shared
SRAM without CPU involvement" is not optional, it's the point of the
block.

The alternative (keep `unpu_seq` frozen, build a shim in `unpu_top` that
pre-fetches everything into `a_src`/`w_src` before calling `unpu_seq`)
was considered and rejected: it would leave `unpu_wbuf`/`unpu_actbuf`
completely unused in the real macro despite `unpu_dma` already being
built and tested (task 008) to feed them directly — throwing away real,
working integration to avoid touching a tested module. Revising
`unpu_seq` is the correct call, not the convenient one.

**This un-freezes `rtl/unpu_seq.sv` and `tb/unpu_seq_tb.sv`, which every
task since 006 has listed as untouchable.** That instruction is
superseded for this task only. Every other file's freeze stands
unchanged (`unpu_pe.sv`, `unpu_grid.sv`, `unpu_skew.sv`,
`unpu_deskew.sv`, `unpu_wbuf.sv`, `unpu_actbuf.sv`, `unpu_dma.sv`,
`unpu_csr.sv`, `unpu_slave.sv` are all still frozen — this task changes
what calls them, not the modules themselves).

**What does not change:** the timing contract. `COMPUTE`'s stop
condition, the `LATCH_CFG` legality check, the `ERROR` state, and
`DONE`'s pulse behavior are untouched — this is an orchestration change
around the compute core, not a change to it.

## The revised interface

```systemverilog
module unpu_seq (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  start,
  input  logic [2:0]            dim_m,
  input  logic [2:0]            dim_n,
  input  logic [2:0]            dim_k,
  input  logic                  mode_unsigned,
  input  logic [31:0]           src_a,          // NEW -- from unpu_csr, latched in LATCH_CFG alongside dims
  input  logic [31:0]           src_b,          // NEW
  input  logic [31:0]           dest_c,         // NEW

  output logic [3:0][3:0][31:0] c_dst,          // unchanged shape; wire straight to unpu_dma.c_src at unpu_top
  output logic                  done,
  output logic                  busy,
  output logic                  error,
  output logic [2:0]            error_code,

  output logic                  array_en,       // unchanged role, now ALSO drives unpu_wbuf/unpu_actbuf's array_en (see note below)
  output logic                  mode_unsigned_o,

  // DMA job dispatch -- NEW, replaces a_src/w_src/weight_load/weight_in
  output logic                  job_start,
  output logic [1:0]            job_kind,       // MUST match unpu_dma's encoding exactly: 2'd0=FETCH_A, 2'd1=FETCH_W, 2'd2=WRITE_C (task 008) -- double check this against rtl/unpu_dma.sv, don't re-derive it from memory
  output logic [31:0]           job_base_addr,
  output logic [2:0]            job_m,          // drive all three on every job regardless of kind -- unpu_dma's BUF_LOAD phase needs the full triple even for a single-tensor fetch (e.g. FETCH_A still needs job_k for unpu_actbuf's own masking)
  output logic [2:0]            job_n,
  output logic [2:0]            job_k,
  input  logic                  job_done,

  // Buffer swap triggers -- NEW
  output logic                  w_swap,         // -> unpu_wbuf.swap
  output logic                  a_swap,         // -> unpu_actbuf.swap

  output logic [1:0]            rd_row,         // NEW, replaces a_raw -- -> unpu_actbuf.rd_row

  input  logic [3:0][31:0]      c_in            // unchanged, from unpu_deskew.c_out
);
```

Removed from task 006's interface: `a_src`, `w_src`, `weight_load`,
`weight_in`, `a_raw`. Weight/activation data now flows
`unpu_dma → unpu_wbuf/unpu_actbuf → unpu_grid/unpu_skew` directly — none
of it passes through `unpu_seq` anymore. `unpu_seq` only *sequences* that
flow (job dispatch + swap timing) and *reads* the result stream
(`rd_row` selects which activation row is being presented, `c_in` is
still the captured output stream, both unchanged in spirit from task
006).

## Why a single `array_en` spanning the whole op — including arbitrarily long DMA waits — is still correct

This needs stating explicitly because it's easy to get backwards (this
task's author got it wrong on a first pass before checking
`unpu_pe.sv` again). The worry: if `array_en=1` for the entire op,
including the (potentially long, arbiter-contended) DMA fetch waits,
won't the grid "accumulate garbage" before real compute even starts?

**No — `unpu_pe.sv`'s `psum_out <= psum_in + product` is a pure
per-cycle function of that cycle's `psum_in` and `product`, not a
self-referential accumulator.** Nothing about a PE's own *previous*
`psum_out` feeds back into its next value — only what arrives at
`psum_in` this cycle, plus this cycle's product, ever matters. Row 0's
`psum_in` is permanently tied to 0 (every testbench so far), so row 0's
`psum_out` is fully overwritten (not accumulated) every single cycle
regardless of what garbage flowed through before. By the same logic,
every row downstream only ever reflects "whatever the row above output
last cycle" + "this cycle's own product" — there is no cross-cycle memory
beyond one register stage anywhere in the chain. Since `COMPUTE` only
starts trusting/capturing `c_in` at `cycle>=7` — exactly the pipeline's
own depth — any activity during the preceding DMA-wait states has fully
drained and been overwritten by real data before a single value is
captured. **Keep the single global `array_en`, spanning `W_FETCH` through
`WRITE_OUTPUT`, same footprint as task 006's original `LOAD_WEIGHTS`-
through-`WRITE_OUTPUT` span** — don't split it into a separate
buffer-enable and compute-enable looking for a problem that isn't there;
that would just be unnecessary complexity chasing a bug that doesn't
exist. If you find a hole in this argument, stop and flag it rather than
silently adding the split — this is exactly the kind of cross-cutting
timing question CLAUDE.md says to raise, not route around.

## Revised FSM

Eleven states: `IDLE`, `LATCH_CFG`, `W_FETCH`, `W_SWAP`, `A_FETCH`,
`A_SWAP`, `COMPUTE`, `READ_OUTPUT`, `WRITE_OUTPUT`, `DONE`, `ERROR`.
`LOAD_WEIGHTS`/`LOAD_INPUT` are gone, replaced by the four new states
below — this is a bigger FSM than task 006's, which is the expected cost
of doing real orchestration instead of a stand-in.

1. **`IDLE`** — unchanged. `array_en=0`. On `start`: → `LATCH_CFG`.
2. **`LATCH_CFG`** — unchanged legality check on `dim_m`/`dim_n`/`dim_k`
   (illegal → `ERROR`, same as task 006). On success, latch the same
   shadow copies as before (`m_lat`/`k_lat`/`n_lat`/`mode_lat`) **plus
   `src_a_lat`/`src_b_lat`/`dest_c_lat`** (no legality check on
   addresses, they're just pointers) → `W_FETCH`.
3. **`W_FETCH`** — `array_en=1`. On the entry cycle only (use an internal
   "already issued" flag — see the known trap below, this is exactly
   task 006/007's one-cycle-staleness bug class in a new spot): pulse
   `job_start=1`, `job_kind=JOB_FETCH_W`, `job_base_addr=src_b_lat`,
   `job_m/n/k` = latched dims (hold these three for the entire state,
   harmless since `unpu_dma` only samples at its own `job_start`). Then
   wait — `job_start=0`, everything else held — until `job_done` pulses.
   No timeout; an unbounded wait here is correct (this is exactly the
   arbiter back-pressure the DMA was built to absorb, `docs/session-
   handoff.md` §4 Q8 — "no number, NPU has priority," not "bounded").
   → `W_SWAP`.
4. **`W_SWAP`** — `array_en=1`. Pulse `w_swap=1` for exactly this one
   cycle. → `A_FETCH` the following cycle (the swap's `weight_load` pulse
   into the grid happens combinationally on this same cycle per
   `unpu_wbuf`'s own design, task 007 — one full cycle of margin before
   moving on is already built into the state transition, nothing extra
   needed).
5. **`A_FETCH`** — same pattern as `W_FETCH`: pulse `job_start=1`,
   `job_kind=JOB_FETCH_A`, `job_base_addr=src_a_lat`, `job_m/n/k` held.
   Wait for `job_done`. → `A_SWAP`.
6. **`A_SWAP`** — pulse `a_swap=1` for one cycle. → `COMPUTE`.
7. **`COMPUTE`** — **unchanged from task 006 except the injection target.**
   Same `cycle` register, same stop condition
   (`cycle == m_lat+6`, checked against the *same* registered counter
   used for injection — the one-cycle-early requirement from task 006 is
   untouched and still applies). Only the injection line changes:
   `rd_row <= (cycle < m_lat) ? cycle[1:0] : rd_row` (or any stable
   don't-care value once `cycle >= m_lat` — nothing reads it after the
   last real row). Capture logic unchanged: `if (cycle>=7) c_dst[cycle-7]
   <= c_in`. → `READ_OUTPUT` on `cycle==m_lat+6`.
8. **`READ_OUTPUT`** — unchanged, one cycle, no action. → `WRITE_OUTPUT`.
9. **`WRITE_OUTPUT`** — same job-dispatch pattern as `W_FETCH`/`A_FETCH`:
   pulse `job_start=1`, `job_kind=JOB_WRITE_C`, `job_base_addr=dest_c_lat`,
   `job_m/n/k` held. `unpu_dma`'s `c_src` input is wired straight to this
   module's own `c_dst` output at `unpu_top` — no new signal needed here,
   `c_dst` already has exactly the shape `unpu_dma.c_src` expects (task
   008 built it that way deliberately). Wait for `job_done`. → `DONE`.
10. **`DONE`** — unchanged. `done=1` for one cycle → `IDLE`.
11. **`ERROR`** — unchanged.

### Known trap — the "already issued" flag

Three states (`W_FETCH`, `A_FETCH`, `WRITE_OUTPUT`) need to pulse
`job_start` exactly once on entry and then hold it low while waiting —
not re-pulse it every cycle of the wait, and not miss the entry cycle
either. Use a single shared 1-bit register (e.g. `job_issued`, cleared on
entering any of these three states, set the cycle `job_start` fires) —
this is the same "did I already act on this edge" bug class that hit
task 007 (stale bank-select) and task 010 (extra `step()`), now on the
RTL side rather than a testbench. Write a directed test for the exact
boundary (see acceptance below) rather than trusting it by inspection.

## Files

- **Replace** `rtl/unpu_seq.sv` with the revised module (same filename).
- **Replace** `tb/unpu_seq_tb.sv` with a testbench against the new
  interface (same filename — the old one cannot compile against the new
  ports, so this isn't optional).

Do not modify any other file. `unpu_pe.sv`, `unpu_grid.sv`,
`unpu_skew.sv`, `unpu_deskew.sv`, `unpu_wbuf.sv`, `unpu_actbuf.sv`,
`unpu_dma.sv`, `unpu_csr.sv`, `unpu_slave.sv` are all still frozen.

## Testbench (`tb/unpu_seq_tb.sv`)

This now needs to be close to a full-stack test to mean anything — the
new states only do something meaningful when wired to the real modules
they orchestrate. Instantiate: `unpu_seq` + `unpu_dma` + `unpu_wbuf` +
`unpu_actbuf` + `unpu_skew` + `unpu_grid` + `unpu_deskew`, plus a
behavioral model SRAM (same one task 008 built, with randomized per-beat
back-pressure available for the CRV pass). Wire it exactly per the
signal names above and task 008's `unpu_dma` port names. `unpu_seq` is
driven directly with `start`/`dim_m`/`dim_n`/`dim_k`/`mode_unsigned`/
`src_a`/`src_b`/`dest_c` (no CSR/native-slave yet — that's step 14/task
012); the point of this task is proving the orchestration works, not the
CPU-facing path.

### Directed

- **`cross_terms` (M=K=N=4)** end to end: preload the model SRAM,
  pulse `start` with the case's addresses/dims, wait for `done`, check
  `c_dst` (or the model SRAM's writeback region) against
  `cross_terms_c.hex`. This is the whole pipeline for the first time —
  DMA fetch → buffer swap → compute → DMA writeback — treat it as the
  primary regression anchor.
- **`seq_m1`/`seq_k1`/`seq_n1`/`seq_mixed`** through the same full path.
- **The `job_start` re-pulse boundary** (the known trap above): confirm
  directly (whitebox, or via counting exactly one `job_start` pulse per
  `W_FETCH`/`A_FETCH`/`WRITE_OUTPUT` visit, even when `job_done` is
  delayed by many cycles of back-pressure) that `job_start` never
  re-fires mid-wait.
- **Two ops back to back, no reset in between**: run `cross_terms`, let
  it finish (`done` pulses, → `IDLE`), then immediately start
  `seq_mixed` with `start` on a later cycle — confirm the second op's
  result is correct and uncontaminated by the first (this is the direct
  test of the array_en/psum-safety argument above — if that reasoning is
  wrong, this is where it would show up).
- **Illegal-config / error-recovery**: same directed case task 006 had
  (illegal `dim_m`), confirming `ERROR` still works and a subsequent
  legal `start` recovers, now with the new states downstream unaffected.

### Plus CRV

All 64 `crv_*` cases from task 006, run end to end through `unpu_seq`
(not testbench-driven DMA jobs like task 008 — `unpu_seq` does the
dispatching now), back to back without reset between them (extending the
"two ops back to back" directed check above into the full CRV sweep),
with the model SRAM's randomized per-beat back-pressure enabled. This is
the task's strongest correctness proof — if it passes, the orchestration
is genuinely working across every shape and every degree of arbiter
contention already validated. Self-check against each case's `_c.hex`.
Print the seed once (reuse `32'h5eed0006`, or pick a fresh one and print
it).

### Regression

`unpu_pe_tb`, `unpu_grid_tb`, `unpu_skew_tb`, `unpu_stall_tb`,
`unpu_buf_tb`, `unpu_dma_tb`, `unpu_csr_tb`, `unpu_slave_tb` all still
pass unchanged (none of their modules changed).

## Acceptance

- All directed cases pass, including the back-to-back-no-reset case and
  the `job_start` re-pulse boundary check.
- All 64 CRV cases pass, run back to back with randomized back-pressure.
- Full regression green (everything except `unpu_seq_tb` itself is
  untouched and must still pass as-is).
- Simulate clean; state which simulator (Verilator has been used the
  last five tasks — continue unless the open tooling decision in
  `docs/planning/plan.md` changes).

## Out of scope

- No `unpu_csr`/`unpu_slave` integration — `unpu_seq` is still driven
  directly, not through the register map or native bus. That's task 012
  (`unpu_top`).
- No changes to `unpu_pe.sv`, `unpu_grid.sv`, `unpu_skew.sv`,
  `unpu_deskew.sv`, `unpu_wbuf.sv`, `unpu_actbuf.sv`, `unpu_dma.sv`,
  `unpu_csr.sv`, or `unpu_slave.sv`.
