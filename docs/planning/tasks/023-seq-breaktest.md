# Task 023 — Sequencer (`unpu_seq`) adversarial stress test (module 5 of 10)

## Goal

Fifth task in the break-it campaign. Same mandate as tasks 019–022:
find a failure the existing coverage (tasks 006, 011) didn't reach. RTL
not expected to change; if something breaks, **stop and report in full
detail — nothing in this campaign fails silently.** Do not narrow a
check, loosen a threshold, or quietly drop a sub-case to make a run
pass; if a check can't be satisfied, that is the result, report it
exactly as found.

## What's already covered — extend past it

Task 006 built the FSM with directed illegal-config/error-recovery (one
illegal case, one recovery) and 64-`crv_*`-case CRV with a K/N-
independence differential check on two `(K,N)` pairs at fixed `M=4`.
Task 011 revised it for real orchestration and proved: full pipeline
correctness, two-ops-back-to-back, the `job_start` re-pulse boundary
under moderate back-pressure, and all 64 `crv_*` cases end to end — 539
checks. What neither reaches: the *full* illegal-value space (only one
illegal case was ever tried), rapid-fire consecutive errors, stray
`start` pulses during an active op, extreme (not moderate) DMA back-
pressure, exhaustive `(dim_k, dim_n)` coverage of the stop-condition
independence proof (only 2 pairs were ever compared), and long chains
mixing legal and illegal ops together.

Reuse `tb/unpu_seq_tb.sv`'s existing full-stack setup (real `unpu_dma` +
`unpu_wbuf` + `unpu_actbuf` + `unpu_skew` + `unpu_grid` + `unpu_deskew`
+ the model SRAM) — this module can't be meaningfully tested any other
way, and that infrastructure is already correct.

## Part A — exhaustive illegal-config sweep + rapid-fire errors

- **Exhaustive illegal-value sweep**: `dim_m`, `dim_n`, `dim_k` are each
  3 bits (legal range 1–4). For each of the three dims independently,
  test all four illegal values (`0`, `5`, `6`, `7`) with the other two
  dims legal — 12 directed sub-cases. Confirm `error=1`,
  `error_code==3'd1` every time, and confirm the **exact boundary**:
  `1` and `4` are accepted, `0` and `5` are not, for all three dims (not
  just spot-checked on one).
- **Multi-dim illegal combinations**: at least 3 cases with two or three
  dims simultaneously illegal.
- **Rapid-fire consecutive errors**: ≥30 illegal `start` attempts in a
  row, different illegal combination each time, no legal op in between
  — confirm the FSM never gets stuck in `ERROR`, `error_code` always
  reflects the *latest* attempt, not a stale one from several attempts
  back.

## Part B — stray `start`-pulse immunity

`start` is documented as sampled only in `IDLE`/`ERROR`. Prove it,
don't just trust the state-machine design: during a real op, inject
extra `start` pulses while the FSM is in each of `W_FETCH`, `W_SWAP`,
`A_FETCH`, `A_SWAP`, `COMPUTE`, `READ_OUTPUT`, `WRITE_OUTPUT` (at least
once each, directed) and confirm the op continues completely
undisturbed — no restart, no corrupted result, no dropped state. Also
inject stray pulses at random points across several long op sequences
(random timing, not just the seven directed placements).

## Part C — extreme DMA back-pressure

Re-run the `job_start` re-pulse-count proof from task 011 (exactly 3
pulses per op: fetch-W, fetch-A, writeback-C) but push the model SRAM's
per-beat grant latency much harder than before — up to 50–100 cycles per
beat, not the moderate range already exercised — across at least 10 full
ops. Confirm the count still holds and no op ever hangs, proving the
"wait indefinitely for `job_done`, no timeout" design genuinely never
breaks under extreme stalling, not just moderate stalling.

## Part D — exhaustive K/N-independence of the COMPUTE stop condition

This is the sharpest test this module gets, because getting it wrong is
exactly the bug class this project already caught once (the PM sketch's
`M+K+N-2` formula, corrected in task 006). Task 006/011 only ever
differential-checked 2 `(dim_k, dim_n)` pairs at `dim_m=4`. This time:
for **each of `dim_m ∈ {1,2,3,4}`**, run at least **6 different
`(dim_k, dim_n)` pairs** spanning the full `1..4` range for each, and
confirm the total `start`→`done` cycle count is **exactly `dim_m+7`**
every single time — independent of `dim_k`/`dim_n`, no exceptions.

## Part E — long adversarial multi-op chains

**At least 20 independently-seeded sequences, each with at least 10
back-to-back full ops, no reset between ops** (≥200 total ops). Each
op: random legal `M`/`N`/`K`/mode, random SRAM addresses (per-op, not
reused), extreme-value-biased `A`/`W` data (same ~10–20% biasing
discipline as tasks 019–022) preloaded into the model SRAM, randomized
DMA back-pressure, and — new for this task — **~10–15% of ops
deliberately configured illegal** (drawn from Part A's illegal-value
set), interspersed among the legal ones, not run as a separate batch.
Self-check every legal op's `C` result and every illegal op's
`error`/`error_code`, and confirm an illegal op never corrupts or
delays the *next* op in the chain — this is the specific thing neither
task 006 (tested error recovery once, in isolation) nor task 011 (never
injected illegal configs into its back-to-back chains) has tried.

## Files

- Extend `tb/unpu_seq_tb.sv` only. Do not modify `rtl/unpu_seq.sv` or
  any other RTL file.

## Acceptance

- All Part A/B/C/D directed and randomized cases pass.
- Part E: ≥20 sequences, ≥200 total ops, 0 failures, every seed printed
  and reproducible, total check count reported (expect well past
  10,000 given the op count and per-op check density).
- Task 006/011's existing 539-check baseline and all 64 `crv_*` cases
  still pass unchanged.
- Full regression on every other testbench unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact seed + op number +
  state + full signal state at divergence. No RTL fix attempted here,
  and no softening of any check to make it pass.

## Out of scope

- No RTL changes.
- No other testbench — module 6 (`unpu_wbuf`/`unpu_actbuf`) is next.
