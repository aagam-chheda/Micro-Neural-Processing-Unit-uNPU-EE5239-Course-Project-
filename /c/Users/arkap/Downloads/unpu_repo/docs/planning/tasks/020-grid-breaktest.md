# Task 020 — Grid adversarial stress test (module 2 of 10)

## Goal

Second task in the break-it campaign (`docs/planning/plan.md`). Same
mandate as task 019: extensive directed + CRV testing (~10,000+ checks,
varying seeds) specifically trying to find a failure task 013's retrofit
didn't reach — not re-proving what's already covered. **RTL is not
expected to change**; `rtl/unpu_pe.sv` and `rtl/unpu_grid.sv` stay
frozen unless this task finds a real defect, which gets reported, not
patched here. If something breaks: stop, don't tune around it, report
the exact seed/cycle/signal state.

**Campaign-wide caution from module 1, carry it forward**: task 019's
first-draft reference model had a real bug (accumulated `psum_out` from
its own prior state instead of each cycle's driven `psum_in` — the PE
doesn't accumulate internally, the systolic chain does). Whatever
reference model this task builds, derive it from the timing contract and
each module's documented behavior, and specifically sanity-check that it
isn't accidentally carrying state the real module doesn't. Worth an
explicit self-check before trusting the first run's results, same as
task 019 ended up doing the hard way.

## What task 013 already covers — extend past it

`tb/unpu_grid_tb.sv` already runs all 64 `crv_*` cases (random weight/
activation matrices, hand-skew-injected — task 003's own methodology,
still unchanged) plus the original identity test, ~684 checks. That's
solid single-pass coverage with one fixed seed's worth of "generic"
random data. What it doesn't cover: **many back-to-back passes with no
reset between them** (grid_tb has always been one-case-at-a-time,
reset-preload-compute), **adversarial/extreme-value data** (the `crv_*`
files are randomly generated but not biased toward boundary values —
they're generically random, not adversarially chosen), and **`array_en`
freeze injection at the grid level specifically** (task 005's stall test
covers this but only with 3 directed placements on one fixed dataset,
`cross_terms`).

## Part A — extreme/structural directed cases

Generate these directly in the testbench (SV, not `model/golden.c` —
keep this task-file-contained, no other file touched), with an inline
reference matmul function derived from the timing contract, not copied
from `unpu_pe.sv`/`unpu_grid.sv`'s own code:

- **Maximum-magnitude**: all-`0xFF` weight matrix × all-`0xFF`
  activation matrix, both modes (signed: `-1×-1` repeated, small
  magnitude but worth confirming explicitly; unsigned: `255×255×4 =
  260,100` per element, well inside the 32-bit accumulator but worth
  checking the actual wiring carries it correctly, not just that it
  doesn't overflow on paper).
- **Walking-one weight matrix**: a single `weight[k][j]=1` at each of
  the 16 positions in turn (rest zero), paired with distinct nonzero
  activations per row (e.g. `A[m][k] = 16*m + k + 1`, all different) —
  this isolates individual wiring paths more precisely than `cross_terms`
  ever needed to (task 004 only needed to rule out row/column swaps in
  the skew/de-skew banks; this isolates the grid's own internal PE-to-PE
  wiring, row by row and column by column).
- **Exhaustive freeze-point sweep on one case**: for a single non-trivial
  dataset (reuse `cross_terms`), inject a 1-cycle `array_en` freeze at
  *every* cycle from entry through drain (cycles 0 through `M+7`, i.e.
  11 directed sub-cases for `M=4`), one freeze point per run, each
  checked against `cross_terms_c.hex` at the correct freeze-adjusted
  cycle (reuse task 005's `active_cyc` bookkeeping convention — substitute
  active-cycle count for wall-clock cycle when frozen, exactly as
  `tb/unpu_stall_tb.sv` already established). This is deliberately
  exhaustive over freeze *position* on one dataset, complementing the
  randomized freeze-timing-and-data combination in Part B.

## Part B — long adversarial multi-pass sequences (the core of this task)

Run **at least 20 independently-seeded sequences**, each consisting of
**at least 10 consecutive full 4×4×4 matmul passes run back-to-back with
no reset between them** (≥200 total passes, ≥3,200 `C`-value checks at
16 per pass — report the actual total achieved, aim well past 10,000
total checks once frozen-register checks from the freeze injections
below are counted in). Each pass:

- Fresh random weight/activation matrices, generated per-pass, with
  ~10–20% of individual byte values forced to an extreme
  (`0x00`/`0xFF`/`0x80`/`0x7F`) instead of drawn uniformly — same
  extreme-value-biasing discipline task 019 used for PE.
- A randomly-placed, randomly-sized `array_en` freeze (0 to ~15 cycles,
  including zero — not every pass needs one) injected at a random point
  within that pass's own timing window.
- Random `mode_unsigned` per pass.

Self-check every pass's 16 `C` values against the inline reference
model, at the freeze-adjusted correct cycle (`active_cyc` convention).
**The specific thing this part is trying to break**: does starting a
fresh pass's weight load correctly happen while the *previous* pass's
psum is still draining through the pipeline in some case (back-to-back
passes with no idle gap between them), and does the grid genuinely not
leak any state between passes even under adversarial freeze timing? This
is the grid-level analogue of task 011's "two ops back to back" and task
012's "64 CRV cases chained" checks, but exercised in isolation at the
grid level, with far more randomized variation in freeze timing and data
than either of those higher-level tests attempted.

## Files

- Extend `tb/unpu_grid_tb.sv` only. Do not modify `rtl/unpu_pe.sv` or
  `rtl/unpu_grid.sv`.

## Acceptance

- All Part A directed cases pass (max-magnitude both modes, walking-one
  sweep, exhaustive freeze-point sweep on `cross_terms`).
- Part B: ≥20 sequences, ≥200 total passes, 0 failures, every seed
  printed and reproducible, total check count reported.
- Task 013's existing 64-`crv_*`-case run and the original identity test
  still pass unchanged (regression on this same file).
- Full regression on every other testbench unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact seed + pass number +
  cycle + full signal state, no RTL fix attempted here.

## Out of scope

- No RTL changes.
- No other testbench — module 3 (skew/de-skew) is next, only after the
  user reviews this task's results and says to continue.
