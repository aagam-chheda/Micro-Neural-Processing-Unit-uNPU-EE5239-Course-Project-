# Task 005 — Stall rule: global `array_en` freeze

## Goal

Prove that dropping `array_en` mid-stream freezes the skew bank, all 16 PEs,
and the de-skew bank on the same clock edge, and that once resumed the
results are bit-identical to an unstalled run — using the `cross_terms`
vectors and skew→grid→de-skew chain already built in task 004.

## Files

- Create `tb/unpu_stall_tb.sv` only.
- Against `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`, `rtl/unpu_deskew.sv`,
  unchanged. Do not touch `rtl/unpu_pe.sv` either.
- **RTL changes are out of scope unless you find the freeze wiring is
  actually missing.** It should not be: every `always_ff` in `unpu_pe.sv`,
  `unpu_skew.sv`, and `unpu_deskew.sv` already gates its updates on
  `else if (array_en)`, so this task is expected to be a pure testbench
  exercise. If you do find a gap, stop and say so rather than patching it
  silently — that's a correctness bug in frozen RTL, not a stall-test
  detail, and Planning needs to know before it's touched.

## Constraints

- "One global `array_en`; no flow control inside the array" (CLAUDE.md,
  handoff §6) — this task verifies that property, it doesn't change it.
- Timing contract (CLAUDE.md) still applies whenever the array is *not*
  stalled: `A[m][k]` enters west edge of row `k` at cycle `m+k`, `C[m][j]`
  leaves south edge of column `j` at cycle `m+j+4`, whole row `C[m][*]`
  valid at cycle `m+7`. A stall does not change these relationships — it
  just pauses the clock the count is measured against (see "Bookkeeping"
  below).
- Reuse the `cross_terms` vectors from task 004
  (`model/vectors/cross_terms_{a,w,c}.hex`) — do not invent a new case.
  Reuse the same weight-preload style as `tb/unpu_skew_tb.sv` (direct
  `weight_load` forcing from `cross_terms_w.hex`, all 16 PEs pulsed at
  once, before compute starts).

## Bookkeeping: active-cycle count vs. wall-clock cycle

Because a stall pauses the pipeline but not the clock itself, drive and
check against an **active-cycle counter**, not the raw simulation cycle
count:

- Maintain `active_cyc`, incremented once per clock edge on which
  `array_en` was `1` during that cycle (i.e. it only advances on cycles the
  DUT actually acted on).
- Present `a_raw = A[m]` while `active_cyc == m` (`m = 0..3`), hold the last
  value once `active_cyc >= 4` — same driving idea as
  `tb/unpu_skew_tb.sv`, just indexed by `active_cyc` instead of wall-clock
  cycle so a stall doesn't desynchronize the schedule.
- Check `c_out[*]` against `cross_terms_c.hex` row `m` when
  `active_cyc == m+7`, for each `m = 0..3`. This must hold in every run,
  stalled or not — that's the "bit-identical to the un-stalled run"
  criterion, since indexing by `active_cyc` makes wall-clock stall
  placement irrelevant to the expected values.

## Internal signals to probe (freeze check)

Instantiate the three modules directly in this testbench (same chaining
style as `tb/unpu_skew_tb.sv`: `unpu_skew` → `unpu_grid` → `unpu_deskew`),
naming the instances `u_skew`, `u_grid`, `u_deskew` so these hierarchical
paths resolve. Pulled directly from the current RTL — depth-0 paths are
plain wires (no register exists there, so there's nothing to freeze;
don't check them):

- **Skew bank** (`rtl/unpu_skew.sv`): `u_skew.row1_q`, `u_skew.row2_q1`,
  `u_skew.row2_q2`, `u_skew.row3_q1`, `u_skew.row3_q2`, `u_skew.row3_q3`.
  (Row 0 is `assign act_out[0] = a_raw[0]` — no register, skip.)
- **Grid** (`rtl/unpu_grid.sv`): every PE's registered outputs,
  `u_grid.g_row[row].g_col[col].pe.psum_out` and
  `u_grid.g_row[row].g_col[col].pe.act_out`, for `row = 0..3`, `col = 0..3`
  (32 signals — both matter: `psum_out` is the result, `act_out` feeds the
  next PE east).
- **De-skew bank** (`rtl/unpu_deskew.sv`): `u_deskew.col2_q1`,
  `u_deskew.col1_q1`, `u_deskew.col1_q2`, `u_deskew.col0_q1`,
  `u_deskew.col0_q2`, `u_deskew.col0_q3`. (Column 3 is a wire, skip.)

That's 44 probed registers total (6 + 32 + 6).

## Test structure

1. **Baseline run.** `array_en` held high throughout (after reset). Confirm
   all four `C[m][*]` rows match `cross_terms_c.hex` at `active_cyc == m+7`
   — this both re-confirms task 004's result and proves this testbench's
   own `active_cyc` bookkeeping is correct before it's trusted for the
   stalled runs.

2. **Stalled runs — three directed placements, in the same simulation or
   as separate runs, your call:**
   - **(a) Early** — stall while the skew bank is still filling, before
     any row has reached `active_cyc == 7`.
   - **(b) Mid** — stall while multiple rows are simultaneously in flight
     through the grid (more than one `m` has entered but not yet exited).
   - **(c) Late** — stall while the de-skew bank is draining, after the
     last row (`m=3`) has entered the skew bank but before its result has
     appeared.

   For each: drop `array_en` low for a randomised number of cycles (use
   `$random` with a **fixed, `$display`-ed seed** so a failure is
   reproducible — constrain the stall length to something like 1–5
   cycles), hold `a_raw` constant (don't-care, the DUT must ignore it) for
   the duration, then raise `array_en` again and resume the schedule.

   During every cycle the stall is asserted, on the edge where
   `array_en` was low: sample all 44 probed registers and assert each one
   is bit-exact equal to its value on the previous edge. `active_cyc` must
   not advance during the stall either (falls out of the bookkeeping rule
   above, but assert it explicitly too).

3. After each stalled run completes, re-check all four `C[m][*]` rows
   against `cross_terms_c.hex` — same values as the baseline run, just
   arriving at a later wall-clock cycle.

4. Self-checking, pass/fail per row and per stall window, plus a final
   summary — same style as prior testbenches.

## Acceptance test

- All three stall placements (a/b/c) pass: every one of the 44 probed
  registers holds bit-exact across every cycle of its stall window.
- All four `C[m][*]` rows match `cross_terms_c.hex` exactly in the
  baseline run and in every stalled run.
- Random seed(s) used are printed via `$display` so a failure reproduces.
- Simulates clean (Icarus, matching prior tasks); file header notes the
  simulator, same convention as `unpu_pe.sv`/`unpu_grid.sv`/`unpu_skew.sv`.
- Regression: confirm `unpu_pe_tb`, `unpu_grid_tb`, and `unpu_skew_tb` still
  pass clean (no RTL should have changed, but this is cheap insurance).

## Out of scope

- No sequencer, no DMA, no APB, no CSR — that's step 8 onward.
- No new golden-model vectors — `cross_terms` is sufficient for this test.
- No RTL changes unless the freeze wiring is genuinely missing (see
  "Files" above) — if you find that, stop and escalate rather than fixing
  it as part of this task.
