# Task 022 — Composite stall (`array_en` freeze) adversarial stress test (module 4 of 10)

## Goal

Fourth task in the break-it campaign, on `tb/unpu_stall_tb.sv`
specifically — the skew→grid→de-skew chain again (same chain task 021
just hammered), but this testbench's own distinctive job is different
and worth keeping distinct: **bit-exact verification of all 44 internal
registers** (6 skew + 32 grid + 6 de-skew) holding through a freeze, not
just that the final `C` values come out right. Don't duplicate task
021's coverage; extend *this* module's specific strength — freeze
correctness at the register level — into combinations neither task
005/013 nor task 021 tried. RTL not expected to change; if something
breaks, stop, report, don't fix here.

## What's already covered — extend past it

Task 005 built the core check: drop `array_en` mid-stream, confirm all
44 registers freeze on the same edge, resume bit-identical to an
unstalled run. Task 013 extended it to all 64 `crv_*` cases (data/shape
variety) with the same style of stall — **one randomized 1–5-cycle
freeze per run**, three directed placements (early/mid/late) plus one
random. Task 021 (module 3) separately did an *exhaustive* freeze-
*position* sweep and single-freeze-per-pass multi-pass sequences, but
through skew/de-skew's own lens (checking `C` correctness and the
depth-0 wire specifically), not this module's all-44-register bit-exact
discipline at freeze *combinations* beyond one-freeze-per-run.

**What neither has tried**: multiple freezes within one pass, freeze
durations far outside the 1–5-cycle range already exercised, freezes
landing exactly on the cycles data actually becomes valid (the highest-
risk boundary), and freeze density varying across many back-to-back
passes — all while holding this module's actual distinctive bar: every
one of the 44 registers checked bit-exact on every held cycle, not
sampled.

## Part A — extreme freeze-combination directed cases

Reuse `tb/unpu_stall_tb.sv`'s existing `capture_snapshot()`/
`check_frozen()` machinery (44-register bit-exact comparison, already
correct — don't rebuild it) for all of these:

- **Multiple freezes in one pass**: within a single `M=4` pass, three
  separate freezes at fixed cycles (e.g. `active_cyc` 1, 4, and 8), each
  a random 1–10-cycle duration, all 44 registers checked bit-exact
  through each one, final `C` values checked correct at the end.
- **Extreme-duration freeze**: one freeze of 50–100 cycles (well past
  the 1–5-cycle range used so far), all 44 registers checked bit-exact
  on *every* cycle of the hold, not just spot-checked at the ends.
- **Freeze exactly on a data-validity boundary**: a freeze whose start
  cycle is exactly `active_cyc==7` (the cycle the first `C` row would
  normally become valid, per the timing contract) and, separately, one
  at exactly `active_cyc==(M-1)+7` (the last row's validity cycle) — the
  two highest-risk moments for any subtle off-by-one in what's gated by
  `array_en`.
- **Back-to-back freezes with zero gap**: freeze, resume for exactly one
  cycle, freeze again immediately, repeated 3–4 times within one pass.

## Part B — long multi-pass sequences with varying freeze density

**At least 20 independently-seeded sequences, each with at least 10
back-to-back passes** (random `M` 1–4, no reset between passes — ≥200
total passes, matching the floor tasks 020/021 already used). Each
pass: fresh random weight/activation data with the same ~10–20%
extreme-value biasing tasks 019–021 used, and a **random number of
freezes per pass (0 to 4)**, each independently placed and durationed
(1–20 cycles). All 44 registers checked bit-exact through every held
cycle of every freeze — this is the specific thing worth pushing hard:
does the single global `array_en` correctly gate *every* register,
every time, under adversarial density, across hundreds of passes,
without ever once drifting?

Report the total register-state-check count achieved (aim well past
15,000 in Part B alone, given the higher freeze density per pass — task
013's baseline already hit ~26,000 with a much lighter freeze schedule,
so this should clear that comfortably; if it doesn't, that's worth
noting, not silently padding the count to hit a number).

## Files

- Extend `tb/unpu_stall_tb.sv` only. Do not modify `rtl/unpu_pe.sv`,
  `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`, or `rtl/unpu_deskew.sv`.

## Acceptance

- All Part A directed cases pass, including both data-validity-boundary
  freezes and the zero-gap back-to-back sequence.
- Part B: ≥20 sequences, ≥200 total passes, 0 failures, every seed
  printed and reproducible, total register-check count reported.
- Task 005/013's existing directed placements and 64-`crv_*`-case run
  still pass unchanged.
- Full regression on every other testbench (including `tb/unpu_skew_tb.sv`,
  which shares this chain) unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact seed + pass number +
  freeze position + which register(s) diverged, no RTL fix attempted
  here.

## Out of scope

- No RTL changes.
- No other testbench — module 5 (`unpu_seq`) is next, only after the
  user reviews this task's results and says to continue.
