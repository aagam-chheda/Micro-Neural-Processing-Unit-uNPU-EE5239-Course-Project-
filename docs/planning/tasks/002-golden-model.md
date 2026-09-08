# Task 002 — C golden model for matmul

## Goal

Write a standalone C program that computes reference 4×4 weight-stationary
INT8 matmul results and emits them as hex vector files, so every SystemVerilog
testbench from here on (steps 6, 8, 14, and beyond) has a single, trusted
oracle instead of each one hand-deriving expected values independently.

## Files

- Create `model/golden.c`
- Output (generated at run time, not checked in): `model/vectors/*.hex`,
  `model/vectors/*_meta.txt`

This is host-side tooling, not firmware — plain C99, not the bare-metal
subset used in `fw/`. It runs on your dev machine to produce vector files,
it never runs on the target.

## Problem shape

Per the timing contract in CLAUDE.md: activations `A` are `M × 4` (M rows,
K=4 columns, matching the 4×4 array's row count), weights `W` are `4 × 4`
(K=4 × J=4), stationary in the array. Output `C` is `M × 4`:

```
C[m][j] = sum_{k=0}^{3} A[m][k] * W[k][j]
```

Accumulate in a 32-bit signed integer, matching "accumulator is 32 bits
throughout." Support both interpretations of the 8-bit inputs (signed
two's-complement and unsigned) via a mode flag per case — mirrors the PE's
`mode_unsigned` from step 1, and this model needs to stay consistent with
that module's semantics since later steps check the RTL against this oracle.

## Vector file format (this is a contract — later steps depend on it, don't improvise a different shape)

For a case named `<name>` with row count `M` and mode `signed`/`unsigned`,
write three files under `model/vectors/`:

- `<name>_a.hex` — `M*4` lines, one 8-bit hex byte per line, `$readmemh`-
  compatible, row-major (`A[0][0], A[0][1], A[0][2], A[0][3], A[1][0], ...`).
- `<name>_w.hex` — 16 lines, one 8-bit hex byte per line, row-major
  (`W[0][0..3], W[1][0..3], W[2][0..3], W[3][0..3]`).
- `<name>_c.hex` — `M*4` lines, one 32-bit hex value per line (8 hex digits,
  no `0x` prefix — plain `$readmemh` form), row-major, same ordering as `A`.

Plus a companion `<name>_meta.txt` with exactly two lines:
```
M=<value>
MODE=SIGNED
```
(or `MODE=UNSIGNED`) — since `$readmemh` files carry no dimension or mode
information, and a testbench reading `<name>_*.hex` needs both to know how
much to read and how to drive `mode_unsigned`.

## Required cases for this task

Generate at least these two, self-checked against hand-computed values
*inside the C program* (assert or explicit compare-and-report, not just
"trust the matmul loop that generates the file it's supposed to verify"):

1. **`identity`** — `M=4`, `W` = 4×4 identity, `A` = any non-trivial matrix
   (e.g. row `m`, col `k` = `(m*4+k) mod 128` so values vary and stay in
   signed-safe range). Hand-computed expectation: `C == A` exactly (extended
   to 32-bit), since multiplying by the identity is a pass-through. Mode:
   signed.
2. **`all_ones`** — `M=4`, `A` and `W` both all-ones. Hand-computed
   expectation: every `C[m][j] == 4` (four 1×1 products summed). Mode:
   signed.

Structure the generator so a third case is a small addition later (a
`generate_case(name, M, A, W, mode)` -shaped function is enough — don't build
a general-purpose test-vector DSL, that's over-engineering for two cases).

## Acceptance test

- `gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c` compiles clean,
  no warnings.
- Running `model/golden` from the repo root writes the six `.hex` files plus
  two `.txt` meta files under `model/vectors/`, creating the directory if it
  doesn't exist.
- The program itself asserts (or checks-and-reports, exiting nonzero on
  mismatch) that its computed `C` matches the two hand-computed expectations
  above before writing any files — if the check fails, no vectors get written
  and the program exits with an error, since a silently-wrong oracle is worse
  than no oracle.
- Prints a clear pass line per case on success.

## Out of scope

- No DPI-C, no linking into the SystemVerilog sim — file-based vectors only
  (this was an explicit decision in `docs/planning/plan.md`, not an oversight).
- No cases beyond `identity` and `all_ones` right now — later steps will ask
  for specific new cases (a non-identity skew/timing case for step 6, M=1/4/
  non-multiple-of-4 for step 8, full SoC-level cases for step 14) as their own
  tasks, not bundled into this one.
- Don't touch `rtl/`, `tb/`, or anything outside `model/`.
