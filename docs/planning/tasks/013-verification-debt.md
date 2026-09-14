# Task 013 — Verification debt retrofit (PE, grid, skew/de-skew, stall)

## Goal

Close the verification debt `docs/planning/plan.md` has tracked since
task 005: steps 1 (PE), 4 (grid), 6 (skew/de-skew), and 7 (stall) were
built against directed tests only, before the CRV directive existed. The
user decided (full retrofit, not partial or accepted-risk) to bring all
four up to the same CRV bar every module since task 006 has had.

**This is testbench-only work.** `unpu_pe.sv`, `unpu_grid.sv`,
`unpu_skew.sv`, `unpu_deskew.sv` are unchanged and stay frozen — nothing
here should require touching them. If a CRV pass surfaces an actual RTL
bug in one of them, stop and flag it rather than patching a frozen file
inside this task; that would be a much bigger finding than "add more
tests."

**No new golden-model work needed.** Parts B, C, and D all reuse the 64
`crv_0000..crv_0063` vector files task 006 Part A already generated
(random M/K/N 1–4, full-range signed/unsigned data, zero-padded to a
valid 4×4 case — see that task file's "Why new cases are needed" section
for why the zero-padded files are already correct full-4×4 matrices, not
just valid for their originally-recorded M/K/N). Part A (PE) needs no
external vectors at all — it's a single MAC unit operating on scalars,
not matrices.

## Files

- Extend `tb/unpu_pe_tb.sv`
- Extend `tb/unpu_grid_tb.sv`
- Extend `tb/unpu_skew_tb.sv`
- Extend `tb/unpu_stall_tb.sv`

Do not modify `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`,
`rtl/unpu_deskew.sv`, or any other file. Keep every existing directed
case in each file — this is additive, not a replacement.

## Part A — PE (`tb/unpu_pe_tb.sv`)

The full operand space is small enough to cover completely — 256×256
signed pairs and 256×256 unsigned pairs, 131,072 combinations total.
**Exhaustive coverage of this space is strictly better than random
sampling of it and should be done instead of calling it "CRV"** — pseudo-
random sampling of a space this small would just be a worse version of
testing all of it. Reserve genuine randomization for the one part of this
module that has a large space: *timing*.

- **Exhaustive operand sweep**: all 256×256 signed pairs and all 256×256
  unsigned pairs, `psum_in` held at a fixed value (e.g. 0) for this part
  — varying it too would needlessly triple an already-large space.
  Self-check against `expected = psum_in + (mode_unsigned ?
  $unsigned(weight)*$unsigned(act) : $signed(weight)*$signed(act))`,
  written independently in the testbench from the INT8/32-bit-
  accumulator description in CLAUDE.md — don't derive the check by
  mirroring `unpu_pe.sv`'s own combinational logic back at itself, that
  would just prove the RTL agrees with a copy of itself.
- **Accumulator sweep**: a smaller randomized set (≥200 iterations) that
  also varies `psum_in` randomly across its full 32-bit range, covering
  the addition path with non-trivial carry-in.
- **Randomized weight-load timing**: extend the existing directed
  "weight-load-while-computing" case into a randomized version — a
  random cycle offset for when a fresh `weight_load` pulse lands relative
  to an ongoing sequence of accumulate cycles. Confirm the same-cycle-
  non-effect property `unpu_pe.sv`'s own header comment documents ("a
  weight_load happening this same cycle cannot affect the product
  computed this same cycle") holds under random placement, not just the
  one directed placement task 001 already covered. ≥50 iterations.
- Seed every randomized component, print it, reproducible.

## Part B — Grid (`tb/unpu_grid_tb.sv`)

Task 003's methodology is unchanged (hand-skewed injection, no skew
module — grid is tested in isolation, same as the existing identity
test). Add: for each of the 64 `crv_*` cases, hand-skew-inject the
case's `_a.hex`/`_w.hex` values (full 4×4, treat the recorded shape as
irrelevant here — these files are valid random 4×4 matrices regardless
of what M/K/N they were tagged for), preload weights directly (same
per-PE forcing style already used), and check all 16 `C[m][j]` positions
against `_c.hex` at the correct contract cycle. This directly closes the
"identity-weight test only... no randomized weight/activation matrices"
gap `plan.md`'s verification-debt note names.

## Part C — Skew / de-skew (`tb/unpu_skew_tb.sv`)

Same reuse, through the full skew→grid→de-skew chain this file already
builds for `cross_terms`. Loop across all 64 `crv_*` cases (keep
`cross_terms` as the original anchor case, don't remove it), reading
each case's real `M` from its `_meta.txt` (reuse the same parse
convention already established — task 004/005/006 all read `M=`/`MODE=`
from these files), and check `C[m][j]` at exactly cycle `m+7` for the
real `M` rows. This closes "one directed non-identity case... no
randomized matrices or randomized M."

## Part D — Stall (`tb/unpu_stall_tb.sv`)

This one is already closest to the bar (`plan.md`: "already has a
randomized component... just narrow in scope, timing only, not
data/shape"). Extend the existing randomized stall-duration/placement
logic (1–5 cycle stalls, the baseline + three placements pattern already
built) to run across multiple `crv_*` cases as the data/shape source
instead of only `cross_terms` — at least 16 of the 64, ideally all 64 if
runtime allows (your call; note which you picked and why). Keep the
existing bit-exact freeze-register check exactly as it is, now proven
across varied data/shape in addition to varied stall timing, and check
final `C` values against each case's `_c.hex`.

## Acceptance

- Part A: exhaustive 131,072-combination operand sweep passes; ≥200
  accumulator-sweep iterations pass; ≥50 randomized weight-load-timing
  iterations pass; all existing directed vectors still pass.
- Part B: all 64 `crv_*` cases pass through the grid in isolation; the
  existing identity test still passes.
- Part C: all 64 `crv_*` cases pass through skew→grid→de-skew; existing
  `cross_terms` check still passes.
- Part D: the chosen subset (≥16, ideally all 64) of `crv_*` cases pass
  under randomized stall placement/duration; existing freeze-register
  checks and the original `cross_terms` stall checks still pass.
- Every seed printed, every random component reproducible from it.
- Full regression green (this task doesn't touch anything downstream of
  these four files, so this is confirming nothing broke).
- Simulate clean; state which simulator (Verilator has been used the
  last seven tasks — continue unless the open tooling decision in
  `docs/planning/plan.md` changes).

## Out of scope

- No changes to `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`,
  or `rtl/unpu_deskew.sv`. If a CRV pass here surfaces something that
  looks like a real RTL bug, stop and report it rather than fixing it
  inside this task.
- No new golden-model work — reuse the existing 64 `crv_*` files as-is.
- No changes to any file outside the four testbenches listed above.
