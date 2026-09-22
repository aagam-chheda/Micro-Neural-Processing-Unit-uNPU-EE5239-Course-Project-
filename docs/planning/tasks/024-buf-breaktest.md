# Task 024 — Buffer (`unpu_wbuf`/`unpu_actbuf`) adversarial stress test (module 6 of 10)

## Goal

Sixth task in the break-it campaign. Same mandate as tasks 019–023:
find a failure existing coverage didn't reach. RTL not expected to
change; if something breaks, stop and report in full — nothing fails
silently, nothing hardcoded, no seed swapped after the fact, no
threshold narrowed to dodge an inconvenient case (standing campaign
rules, `docs/planning/plan.md`).

## What's already covered — extend past it

Task 007 built both buffers with 64-`crv_*`-case CRV (531 checks): a
concurrent-load-during-compute test (one background load+swap racing
one active compute pass), a whitebox settling assertion for `unpu_wbuf`'s
reverse-row shift-in (one case), and generic K/N masking via the
`crv_*` cases' naturally varied shapes. What it doesn't reach: adversarial
extreme-value data, exhaustive (not generic-random) coverage of every
`(K,N)` masking boundary, settling correctness across *every* `K` value
individually, rapid-fire back-to-back swap cycles, and *many* concurrent
loads racing *many* computes in a chain (task 007 proved the concept
once; this proves it holds under density).

## Part A — extreme/structural directed cases

- **Exhaustive `(K,N)` masking boundary sweep**: all 16 `(K,N)`
  combinations (`K,N ∈ {1,2,3,4}`), with **extreme-value data placed
  specifically at the boundary row** (`K-1`, the last real row, and `K`
  if `K<4`, the first masked row) **and boundary column** (`N-1`/`N`
  analogously). Confirm the masking cutoff is exactly right — no
  off-by-one — via both a whitebox bank/`stage[]` read and the existing
  grid-based functional verification (task 007's own method).
- **`unpu_wbuf` reverse-row settling, every `K` individually**: task
  007's whitebox settling check only ever confirmed one case (`K=4`).
  Repeat it explicitly for `K=1`, `K=2`, `K=3` as well — confirm
  `stage[col][row]` settles correctly (including the masked rows reading
  zero) for each.
- **`unpu_actbuf` combinational-read stress**: drive `rd_row` with a
  rapidly-changing (every cycle, no repeats where avoidable) random
  address sequence over many cycles, both before and after a bank swap,
  and confirm `rd_data` reflects the addressed row **with zero added
  latency** every single cycle — this is the read-side analogue of the
  depth-0-wire zero-latency checks module 3 already did for skew/de-skew,
  applied here to confirm the "purely combinational read" contract
  actually holds under adversarial addressing, not just typical
  sequential access.
- **Rapid-fire back-to-back load→swap cycles**: ≥20 consecutive
  load+swap operations on both buffers in immediate succession (swap the
  instant `load_done` fires, then start the next load immediately), no
  compute in between — confirm the ping-pong bank-select never gets
  confused under maximum swap frequency, and every swap's data is
  correct (whitebox or grid-verified, your call which is more direct
  here).

## Part B — long adversarial chains of concurrent load/swap racing compute

**At least 20 independently-seeded sequences, each with at least 10
back-to-back compute passes** (random `K`/`N` 1–4, extreme-value-biased
data ~10–20%, no reset between passes). For each pass, a background
load+swap for the *next* pass's weights/activations runs concurrently
with the *current* pass's compute, with the load's start point
randomized relative to the current pass's progress (early/mid/late —
task 007 only ever tried one relative timing; this randomizes it across
the whole campaign's chain). Self-check every pass's result against the
stateless `ref_c_elem`-style reference (reuse it if `tb/unpu_buf_tb.sv`'s
existing structure already has an equivalent; derive one the same way
modules 2–4 did if not — same "no accumulation from a shadow's own
prior state" caution as always).

## Files

- Extend `tb/unpu_buf_tb.sv` only. Do not modify `rtl/unpu_wbuf.sv`,
  `rtl/unpu_actbuf.sv`, or any other RTL file.

## Acceptance

- All Part A directed cases pass, including all 16 `(K,N)` boundary
  combinations and the per-`K` settling checks.
- Part B: ≥20 sequences, ≥200 total passes, 0 failures, every seed
  printed and reproducible, total check count reported (expect well
  past 10,000).
- Task 007's existing 531-check baseline and 64-`crv_*`-case coverage
  still pass unchanged.
- Full regression on every other testbench unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact seed + pass number +
  bank state + full signal state at divergence. No RTL fix attempted
  here, no check softened to pass.

## Out of scope

- No RTL changes.
- No other testbench — module 7 (`unpu_dma`) is next.
