# Task 021 — Skew/de-skew adversarial stress test (module 3 of 10)

## Goal

Third task in the break-it campaign. Same mandate as tasks 019/020:
extensive directed + CRV testing trying to find a failure task 013's
retrofit didn't reach, through the full `unpu_skew` → `unpu_grid` →
`unpu_deskew` chain this time (`tb/unpu_skew_tb.sv`'s existing
structure). RTL not expected to change; if something breaks, stop,
report, don't fix here.

**Carry forward both campaign-wide cautions so far**: (1) an independent
reference model must not accidentally accumulate state a module doesn't
actually carry (task 019's finding) — prefer a stateless/recomputed-
each-time reference where practical, matching how task 020 closed that
gap; (2) sanity-check the reference against at least one hand-verifiable
case before trusting a clean first run (task 020's walking-one sweep did
this for free — find an equivalent here if one doesn't fall out
naturally).

## What's already covered — extend past it

`tb/unpu_skew_tb.sv` (task 013) already runs all 64 `crv_*` cases
through the full chain (random data, random `M` 1–4), plus the original
`cross_terms` anchor — 636 checks. `tb/unpu_stall_tb.sv` (task 005)
covers `array_en` freezing on this same chain, but only 3 directed
placements plus random 1–5-cycle duration, on `cross_terms` alone. What
neither covers: adversarial/extreme-value data, many back-to-back passes
with no reset (task 020 just proved this matters at the grid level in
isolation — skew/de-skew add *more* pipeline depth than grid alone, so
this is genuinely new risk surface, not a repeat), and — specific to
this module pair, unlike PE or grid — the **depth-0 wire paths**.

## Part A — extreme/structural directed cases

- **Depth-0 wire stress, the sharpest test this module pair gets.**
  `unpu_skew`'s row 0 and `unpu_deskew`'s column 3 are documented as
  plain wires, not registers (`execution.md`'s known trap: "Row 0's skew
  delay is a wire, not a register. A parameterised loop that
  accidentally infers one register on row 0 shifts the whole wavefront
  and fails the identity test" — same trap named for de-skew's column
  3). Drive `a_raw[0]` with a value that **changes every single cycle**
  (alternate `0x00`/`0xFF`, or a cycling extreme-value sequence) and
  confirm `act_out[0]` reflects it with **zero added latency** — same-
  cycle passthrough, not one cycle behind. Do the equivalent for
  `unpu_deskew`'s `c_out[3]` against `psum_in[3]`. This is a much
  sharper test than the existing identity/`cross_terms` checks for
  specifically this trap, because a signal that changes every cycle
  makes a one-cycle registration error immediately visible, rather than
  possibly-coincidentally matching on static or slow-changing data.
- **Max-magnitude through the full chain**: all-`0xFF` weight × all-`0xFF`
  activation, both modes, checked at the correct `m+7` cycle for all 16
  `C` values.
- **Exhaustive freeze-point sweep on `cross_terms`**, across the full
  chain's timing window this time (not just grid's own window from task
  020) — cycles 0 through `M+7` inclusive, one freeze per sub-case,
  reusing task 005's `active_cyc` bookkeeping directly (already proven
  correct on this exact chain, no need to reinvent it).
- **M=1 and M=4 explicitly, with extreme data** — the shortest and
  longest pipeline-overlap windows this module pair produces, worth
  covering directly rather than trusting the random `M` draws in Part B
  to land on both extremes reliably.

## Part B — long adversarial multi-pass sequences

**At least 20 independently-seeded sequences, each with at least 10
back-to-back passes** (random `M` 1–4 per pass, no reset between
passes — ≥200 total passes, matching task 020's floor). Each pass: fresh
random weight/activation matrices with ~10–20% of byte values forced to
an extreme value (same biasing discipline as tasks 019/020), a randomly
placed/sized `array_en` freeze (0–15 cycles, not every pass needs one),
random `mode_unsigned`.

**What this is specifically trying to break, that task 020's grid-only
version couldn't reach**: `unpu_skew`/`unpu_deskew` carry real
pipelined state across up to 3 register stages each (depths 0/1/2/3 and
3/2/1/0) — task 020's grid-only test used hand-skewed injection with no
real skew/de-skew banks in the loop at all, so it never exercised this
state. Does that deeper pipeline correctly flush between back-to-back
passes of *differing* `M` (e.g. an `M=4` pass immediately followed by an
`M=1` pass) without leaking stale data from the longer pipeline stages?
Bias the random `M` draws to include adjacent-pass transitions across
the full `1→4` range, not just same-`M` runs back to back.

## Files

- Extend `tb/unpu_skew_tb.sv` only. Do not modify `rtl/unpu_pe.sv`,
  `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`, or `rtl/unpu_deskew.sv`.

## Acceptance

- All Part A directed cases pass, including the depth-0 wire
  zero-latency check for both `unpu_skew` row 0 and `unpu_deskew`
  column 3.
- Part B: ≥20 sequences, ≥200 total passes, 0 failures, every seed
  printed and reproducible, total check count reported (aim well past
  10,000 once freeze-hold checks are counted, matching task 020's
  scale).
- Task 013's existing 64-`crv_*`-case run and `cross_terms` still pass
  unchanged.
- Full regression on every other testbench (including `tb/unpu_stall_tb.sv`,
  which shares this chain) unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact seed + pass number +
  cycle + full signal state, no RTL fix attempted here.

## Out of scope

- No RTL changes.
- No other testbench — module 4 (`unpu_stall`, the composite freeze
  test) is next, only after the user reviews this task's results and
  says to continue.
