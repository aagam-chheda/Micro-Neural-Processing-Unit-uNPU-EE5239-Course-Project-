# Task 028 — Top-level (`unpu_top`) adversarial stress test (module 10 of 10, final)

## Goal

Final and most important task in the break-it campaign. Every submodule
(`unpu_pe` through `unpu_apb`) has now been individually hammered —
zero RTL defects found across 9 modules and roughly 200,000 checks
combined. **This task is the only place integration-level risk can even
exist**, since it's the only test that drives the whole wired-together
system through its real external interfaces at once. Treat it
accordingly: this is not "run the same recipe on module 10," it's
"combine every adversarial technique the campaign has built, plus
whatever only shows up when everything is connected." Same standing
rules as every prior task, but hold to them hardest here — nothing fails
silently, nothing hardcoded, seeds are whatever gets printed, no
threshold narrowed to dodge an inconvenient case
(`docs/planning/plan.md`). RTL not expected to change; if something
breaks, stop and report in full, immediately — this is the last gate
before a freeze pass.

## What's already covered — extend past it

Task 012 built the full ten-module wiring, tested only through the two
native ports at the time; task 018 reverted the CPU-facing port to APB
and re-proved the same content (directed cases, 64 `crv_*` cases) over
the new protocol — 512 checks. What it doesn't reach: any of the
extreme conditions modules 1–9 individually proved their own pieces
survive (extreme DMA back-pressure, extreme APB pacing, address
wraparound, illegal-config injection at volume) **combined together, at
the same time, through the real end-to-end path** — and two risks that
are structurally invisible to any single-module test:

- **Mid-flight register writes**: firmware could write new config
  registers before polling `npu_status` for `DONE` on the previous op.
  `unpu_seq`'s `LATCH_CFG` shadow-copies its config specifically so this
  can't corrupt an in-flight op — proven at the signal level in module
  5's break test, but never proven end-to-end through the real APB
  register path while a real DMA-backed op is genuinely in flight.
- **Mid-flight status polling**: does reading `npu_status` via APB while
  a DMA fetch/writeback is mid-beat (under back-pressure) ever disturb
  the ongoing operation? No single-module test can produce this
  condition — it needs the CSR, APB, DMA, and sequencer all live at
  once.

## Part A — top-level-specific structural directed cases

- **Address wraparound with real data correctness**: a full op with
  `src_A`/`src_B`/`dest_C` near `32'hFFFF_FFF0`. Module 7 proved the DMA
  address sequence itself wraps correctly in isolation but couldn't
  check content (its model SRAM only decodes a limited range). At the
  top level, use the *same* address-decode convention the model SRAM
  already applies and confirm the actual computed `C` values read back
  correctly at whatever addresses the wraparound resolves to — this is
  the first point in the campaign that can actually prove wraparound
  doesn't corrupt data, not just addressing.
- **Mid-flight register write during an active op**: start a legal op
  (e.g. `cross_terms`), and *while it's still running* (well before
  `DONE`), issue APB writes to `src_A`/`dim_M`/other config registers
  with different values. Confirm the in-flight op completes correctly,
  unaffected. Then issue a second, real op and confirm it correctly
  picks up the values written during the first op's run (proving the
  shadow-copy protects the *current* op without silently discarding the
  *next* one's config).
- **Mid-flight status polling during active DMA beats**: interleave
  rapid `npu_status` APB reads with a DMA fetch/writeback that's
  genuinely stalled mid-beat (drive real back-pressure to hold it
  there), confirm polling never disturbs the stalled operation and
  `DONE` eventually reads correctly once it actually completes.
- **Maximum-speed config write**: a full 7-register config sequence
  (`src_A`/`src_B`/`dest_C`/`dim_M`/`dim_N`/`dim_K`/`npu_ctrl`-START)
  issued as zero-gap back-to-back APB transactions (module 9's
  fastest-possible-rate pattern), repeated across several ops.
- **Combined extreme APB pacing through a real op**: mix long-SETUP
  phases (module 9's adversarial pattern) with zero-gap bursts within
  the same op's register-write sequence.

## Part B — the maximal adversarial long-chain campaign

This is the core of the task, and should be the largest, most combined
stress test in the entire campaign. **At least 30 independently-seeded
sequences, each with at least 15 back-to-back full ops, zero reset
between ops** (≥450 total ops — deeper than any prior module's chain).
Each op combines, simultaneously:

- Random legal `M`/`N`/`K`/mode, random per-op SRAM addresses
  (occasionally drawn near the wraparound boundary, not excluded)
- Extreme-value-biased `A`/`W` data (~10–20%, same discipline as every
  prior module)
- **~10–15% of ops deliberately illegal**, interspersed among legal ones
  (module 5's finding: this needs to be mixed in, not run separately)
- Extreme DMA back-pressure, mixing the original moderate range with
  module 7's 50–200-cycle extreme range
- Extreme APB pacing, mixing tight zero-gap register writes with
  occasional long-SETUP phases and sparse/idle status-polling gaps

Self-check every legal op's `C` result (stateless reference, same
no-persistent-state discipline every prior module used) and every
illegal op's error reporting via `npu_status`. Confirm no op — legal or
illegal — ever corrupts, delays, or leaks into the next one, across the
deepest chain this campaign has built.

## Files

- Extend `tb/unpu_top_tb.sv` only. Do not modify any RTL file — this
  task touches the fully-integrated system, so a defect here could in
  principle point at any of the ten modules; if something breaks, report
  which signals/values diverged and let that guide where the problem
  actually is, don't guess and patch.

## Acceptance

- All Part A directed cases pass, including wraparound-with-data-
  correctness, both mid-flight cases, and the combined-pacing case.
- Part B: ≥30 sequences, ≥450 total ops, 0 failures, every seed printed
  and reproducible, total check count reported. Given the op count and
  the combined adversarial axes, this should be the largest total in
  the whole campaign — report the actual number, don't pad toward one.
- Task 012/018's existing 512-check baseline still passes unchanged.
- Full regression on all nine other testbenches green.
- Simulate clean under Verilator.
- **If anything fails**: stop immediately, report the exact seed + op
  number + every relevant signal's state at divergence, in enough detail
  that root-causing it doesn't require re-deriving what happened. No RTL
  fix attempted here, no check softened to pass. This is the last gate
  before a freeze pass — a real finding here matters more than a clean-
  looking report.

## Out of scope

- No RTL changes.
- No other testbench — this is the last module in the campaign.
