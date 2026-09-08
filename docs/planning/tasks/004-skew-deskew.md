# Task 004 — Skew / de-skew banks

## Goal

Build the input skew bank and output de-skew bank around the (already
verified) `unpu_grid`, and prove the full timing contract holds end to end
— raw, un-skewed matrix in, correctly aligned matrix out — for a matrix
that actually exercises multi-term accumulation and column wiring, not just
pass-through.

This task has two parts: a small extension to the golden model (a new test
case), then the skew/de-skew RTL and its testbench.

## Part A — new golden-model case

### Files

- Edit `model/golden.c` only. Do not touch `rtl/`, `tb/`, or anything else
  in this part.

### Why a new case

`model/vectors/identity_*` and `model/vectors/all_ones_*` already exist
from task 002, but neither is a good discriminator for skew/wiring bugs:
`identity` has at most one nonzero product per output (no real
accumulation), and `all_ones` is fully symmetric — every product is `1*1`,
so a row/column swap in the skew or de-skew wiring would still produce the
"correct-looking" sum of 4 by coincidence. This task needs a case where
each output is a sum of *two* distinct nonzero products, and every value
differs, so any wiring mistake changes the answer.

### Case to add: `cross_terms`, M=4, mode signed

`A` (row-major, `A[m][k]`):
```
A[0] = 1,  2,  3,  4
A[1] = 5,  6,  7,  8
A[2] = 9,  10, 11, 12
A[3] = 13, 14, 15, 16
```

`W` (row-major, `W[k][j]`):
```
W[0] = 1, 0, 2, 0
W[1] = 0, 1, 0, 2
W[2] = 2, 0, 1, 0
W[3] = 0, 2, 0, 1
```

All values fit comfortably in signed INT8 with no overflow risk at any
stage (max product `2*16=32`, max sum `46`), so this is a plain-arithmetic
case, no sign-mode edge behavior being tested here.

Hand-computed expected `C` (verify these against your C implementation
before writing files — these are the "hand-computed" reference values, do
not derive them by trusting the loop that generates them):
```
C[0] = 7,  10, 5,  8
C[1] = 19, 22, 17, 20
C[2] = 31, 34, 29, 32
C[3] = 43, 46, 41, 44
```

Add this as a third call alongside `identity` and `all_ones` using the same
`generate_case(name, M, A, W, mode)`-shaped function from task 002 — this is
exactly the "small addition later" that function was built for. Same
self-check-before-write discipline as the existing two cases: if the
computed `C` doesn't match the table above, exit nonzero and write nothing.

### Acceptance (Part A)

- `model/golden.c` still compiles clean (`gcc -std=c99 -Wall -Wextra`).
- Running it now writes nine files total (three per case ×3 cases):
  `cross_terms_a.hex`, `cross_terms_w.hex`, `cross_terms_c.hex`,
  `cross_terms_meta.txt`, plus the existing six from `identity`/`all_ones`.
- Prints a pass line for `cross_terms` alongside the existing two.

## Part B — skew and de-skew RTL

### Files

- Create `rtl/unpu_skew.sv`
- Create `rtl/unpu_deskew.sv`
- Create `tb/unpu_skew_tb.sv`

Do not modify `rtl/unpu_pe.sv` or `rtl/unpu_grid.sv` — both are frozen from
prior tasks. `unpu_grid`'s port list (for reference, do not redeclare it,
just instantiate it):

```systemverilog
module unpu_grid (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 array_en,
  input  logic                 mode_unsigned,
  input  logic [3:0][3:0]      weight_load,
  input  logic [3:0][3:0][7:0] weight_in,
  input  logic [3:0][7:0]      act_in,
  input  logic [3:0][31:0]     psum_in,
  output logic [3:0][7:0]      act_out,
  output logic [3:0][31:0]     psum_out
);
```

### Interfaces (fixed — don't improvise a different shape)

```systemverilog
module unpu_skew (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              array_en,
  input  logic [3:0][7:0]   a_raw,    // raw A[m][0..3], all four presented together at cycle m
  output logic [3:0][7:0]   act_out   // act_out[k] valid at cycle m+k -- wire straight into unpu_grid's act_in
);
```
```systemverilog
module unpu_deskew (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               array_en,
  input  logic [3:0][31:0]   psum_in,  // wire straight from unpu_grid's psum_out; column j arrives at cycle m+j+4
  output logic [3:0][31:0]   c_out     // all four columns of row m valid together at cycle m+7
);
```

### Skew depths (from CLAUDE.md, quoted, not paraphrased)

"Skew FIFO depths are 0/1/2/3 on the input side, 3/2/1/0 on the output
side." Concretely:
- `unpu_skew`: `act_out[k]` is `a_raw[k]` delayed by `k` register stages
  (`k=0` → straight wire, `k=1` → 1 flop, `k=2` → 2 flops, `k=3` → 3 flops).
- `unpu_deskew`: `c_out[j]` is `psum_in[j]` delayed by `3-j` register
  stages (`j=3` → straight wire, `j=0` → 3 flops).

**Known trap (execution.md, quoted):** "Depth-0 FIFO. Row 0's skew delay is
a wire, not a register. A parameterised loop that accidentally infers one
register on row 0 shifts the whole wavefront and fails the identity test."
The same applies to `unpu_deskew`'s column-3 (depth 0) path — make sure a
generate loop doesn't silently register it.

`array_en` gates every stage identically — holding it low freezes the skew
and de-skew shift registers along with the grid, same "one global enable,
no flow control inside the array" rule from CLAUDE.md/execution.md.

### Testbench

`tb/unpu_skew_tb.sv` chains `unpu_skew` → `unpu_grid` → `unpu_deskew`:

1. Preload weights on the grid directly from the `cross_terms_w.hex` values
   (same direct per-PE forcing style as task 003's grid testbench — pulse
   all 16 `weight_load` simultaneously before compute starts; this task
   still does not build the shift-down weight-loading network, that's
   `unpu_wbuf`, step 9).
2. Drive `a_raw = A[m]` (all 4 columns at once) on `unpu_skew`'s input on
   the cycle corresponding to `m`, for `m = 0..3` — this is what makes the
   input "raw, un-skewed": unlike task 003's testbench, you are not
   hand-delaying `act_in[k]` yourselves anymore; `unpu_skew` does that now.
3. Check `unpu_deskew`'s `c_out[*]` against `cross_terms_c.hex` at cycle
   `m+7` for each `m` (per the timing contract's fourth line: "whole row
   `C[m][*]` valid after de-skew at cycle `m+7`"). You may read the vector
   files with `$readmemh` (this is exactly the case they exist for) or
   transcribe the table from Part A directly — your call.
4. Self-checking, pass/fail per row plus a final summary, same style as the
   existing testbenches.

### Acceptance (Part B)

- All 4 rows (`C[0]` through `C[3]`, 16 values total) match
  `cross_terms_c.hex` at exactly cycle `m+7`.
- Simulate clean (Icarus/Verilator — note which, same convention as prior
  tasks).
- File headers note simulator used, matching `unpu_pe.sv`/`unpu_grid.sv`.

## Out of scope

- No sequencer, no DMA, no APB, no CSR.
- No shift-down weight loading network (`unpu_wbuf`) — still direct forcing.
- No `array_en` mid-stream stall test — that's step 7, a separate task,
  once this one is in and passing.
- Don't touch `rtl/unpu_pe.sv` or `rtl/unpu_grid.sv`.
