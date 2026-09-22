# Task 025 — DMA (`unpu_dma`) adversarial stress test (module 7 of 10)

## Goal

Seventh task in the break-it campaign. Same mandate and standing rules
as tasks 019–024 (nothing fails silently, nothing hardcoded, seeds are
whatever gets printed, no threshold narrowed to dodge an inconvenient
case — `docs/planning/plan.md`). RTL not expected to change; if
something breaks, stop and report in full.

## What's already covered — extend past it

Task 008 built the 4-state (`D_IDLE`/`D_REQ`/`D_ACK`/`BUF_LOAD`/`D_FIN`)
FSM with directed fetch/writeback/K-N-masking/held-back-pressure cases,
plus 64 `crv_*` cases with randomized base addresses and 0–5-cycle
per-beat back-pressure — 1,110 checks. What it doesn't reach: back-
pressure far outside that range, address values near 32-bit wraparound,
*exhaustive* (not generic-random) coverage of every possible burst
length, job kinds arriving in random order rather than the natural
fetch-A→fetch-W→writeback-C sequence a real op produces, and whether the
internal staging buffer (`stage[0:3]`, used to absorb back-pressure
before `BUF_LOAD` drains it into the target buffer) ever presents stale
data from an earlier job when a later job's `K`/`M` is smaller.

## Part A — extreme/structural directed cases

- **Address wraparound**: `job_base_addr` near `32'hFFFF_FFF0`, driving
  a full 16-beat writeback (`M=N=4`) so the address counter (`base +
  m*16 + j*4`) genuinely wraps past `32'hFFFF_FFFF`. Confirm the design
  behaves *consistently* with plain 32-bit unsigned wraparound
  arithmetic (the same wraparound a real address counter would do) —
  this isn't necessarily a bug if it wraps, it needs to be *correct*,
  checked against a reference that itself wraps the same way, not one
  that assumes addresses stay in a comfortable range.
- **Exhaustive burst-length coverage**: all `M∈{1,2,3,4}` for fetch-A
  (4 cases), all `K∈{1,2,3,4}` for fetch-W (4 cases), and all 16
  `(M,N)` combinations for writeback-C (beat counts 1 through 16,
  covering the fixed-16-byte-row/real-N-columns-only addressing
  directly) — confirm the exact beat count and exact address sequence
  for every one, not just whatever mix 64 generically-random shapes
  happened to draw.
- **Extreme back-pressure**: a full 16-beat writeback with every single
  beat individually stalled 50–200 cycles (not the 0–5-cycle range
  already exercised) — confirm zero address/data drift across the
  entire job and that it still completes, proving the "hold everything
  stable, never hang" property at an order of magnitude past what's
  already been proven.
- **`BUF_LOAD` staging correctness across differing burst sizes back to
  back**: a `K=4` fetch (fills all 4 `stage[]` slots) immediately
  followed by a `K=1` fetch (only `stage[0]` should get fresh data this
  time) — confirm the second job's `BUF_LOAD` burst presents genuinely
  fresh data for `stage[0]` and that whatever downstream masking applies
  to the unused slots is correct, not leftover content from the first
  job.

## Part B — long adversarial job chains, random kind order

**At least 20 independently-seeded sequences, each with at least 20
back-to-back jobs** (≥400 total jobs), **job kind drawn randomly each
time** (fetch-A, fetch-W, or writeback-C — not the natural sequence
order a real op produces; any kind may follow any other), zero gap
between jobs (`job_start` pulses the cycle after the previous job's
`job_done`). Randomized addresses (including some drawn near the
wraparound boundary), randomized extreme back-pressure per beat,
extreme-value-biased data (~10–20%, same discipline as every prior
module). Self-check every fetch against the model SRAM's known content
(via the downstream buffers, task 008's own verification method) and
every writeback against the model SRAM's written region.

## Files

- Extend `tb/unpu_dma_tb.sv` only. Do not modify `rtl/unpu_dma.sv` or
  any other RTL file.

## Acceptance

- All Part A directed cases pass, including the wraparound case and all
  24 exhaustive-burst-length sub-cases.
- Part B: ≥20 sequences, ≥400 total jobs, 0 failures, every seed
  printed and reproducible, total check count reported (expect well
  past 10,000 given per-beat check density).
- Task 008's existing 1,110-check baseline and 64-`crv_*`-case coverage
  still pass unchanged.
- Full regression on every other testbench unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact seed + job number + beat
  + full signal state at divergence. No RTL fix attempted here, no
  check softened to pass.

## Out of scope

- No RTL changes.
- No other testbench — module 8 (`unpu_csr`) is next.
