# Task 003 — Grid module + identity test (W2 gate)

## Goal

Wire 16 `unpu_pe` instances into the 4×4 systolic array and prove it holds
the timing contract with weights forced directly by the testbench — no
skew/de-skew, no sequencer, no DMA. This is the End-W2 gate from
`docs/session-handoff.md` §9.

## Files

- Create `rtl/unpu_grid.sv`
- Create `tb/unpu_grid_tb.sv`

Do not modify `rtl/unpu_pe.sv` — its interface is frozen (task 001). If you
find you need to change it to build the grid, stop and say so instead of
editing it.

## Interface (fixed — don't improvise a different shape)

```systemverilog
module unpu_grid (
  input  logic                 clk,
  input  logic                 rst_n,        // match unpu_pe's reset style

  input  logic                 array_en,     // single global enable/freeze, fans out to all 16 PEs
  input  logic                 mode_unsigned,// fans out to all 16 PEs

  input  logic [3:0][3:0]      weight_load,  // weight_load[row][col], per-PE pulse
  input  logic [3:0][3:0][7:0] weight_in,    // weight_in[row][col]

  input  logic [3:0][7:0]      act_in,       // west edge: act_in[row], row = 0..3
  input  logic [3:0][31:0]     psum_in,      // north edge: psum_in[col], col = 0..3

  output logic [3:0][7:0]      act_out,      // east edge: act_out[row]
  output logic [3:0][31:0]     psum_out      // south edge: psum_out[col]
);
```

Instantiate 16 `unpu_pe` as a `pe[row][col]` structure (generate block or
explicit instances, your call). Wiring:

- **Activation (west → east):** `pe[row][0].act_in = act_in[row]`.
  For `col > 0`: `pe[row][col].act_in = pe[row][col-1].act_out`.
  `act_out[row] = pe[row][3].act_out` (east edge, last column — exposed even
  though nothing consumes it yet, matching the PE's own port list).
- **Partial sum (north → south):** `pe[0][col].psum_in = psum_in[col]`.
  For `row > 0`: `pe[row][col].psum_in = pe[row-1][col].psum_out`.
  `psum_out[col] = pe[3][col].psum_out` (south edge, the real output).
- **Weight, enable, mode:** `pe[row][col].weight_load = weight_load[row][col]`,
  `weight_in` likewise per-PE. `array_en` and `mode_unsigned` fan out
  identically to all 16 instances — one global enable, no per-PE gating
  (CLAUDE.md: "One global `array_en`. No flow control inside the array.").

## Constraints (from CLAUDE.md and the handoff doc — quoted, not paraphrased)

- "RTL is SystemVerilog... synthesisable subset only — `logic`, `always_ff` /
  `always_comb`, packed structs, enums for FSM states."
- Timing contract (CLAUDE.md): `A[m][k] arrives at PE(k,j) at cycle m+k+j`.
  This governs how you drive `act_in` in the testbench — see below.
- "One global `array_en`; no flow control inside the array" (handoff §6) —
  the grid must not add any per-row/per-column enable logic. It only fans
  the single `array_en` out.
- One module per file, filename matches module name.

## Testbench requirements

`tb/unpu_grid_tb.sv` contains **no skew module** — do not write one, do not
stub one in. Inject hand-skewed activations directly:

- Drive `act_in[k]` with `A[m][k]` on the cycle where the testbench's own
  cycle counter equals `m + k` (per the timing contract's first line — this
  is you, the testbench, performing the skew that a real skew bank would do
  later in step 6).
- Preload identity weights before compute starts: `weight_in[row][col] = (row
  == col) ? 8'h01 : 8'h00`, pulse `weight_load[row][col] = 1` for one cycle
  for all 16 PEs simultaneously (this is direct forcing, not the shift-down
  network — that network is `unpu_wbuf`, step 9, out of scope here).
- Tie `psum_in[*] = 32'h0` for the whole run (nothing feeds the array from
  the north in this test).
- Use a non-trivial `A` (M=4, e.g. `A[m][k] = (m*4+k) mod 128` — same shape
  as the golden model's `identity` case from task 002, so you can generate
  expected values by inspection: with `W = I`, `C[m][j] = A[m][j]`).
- Check `psum_out[j]` equals `A[m][j]` (sign-extended to 32 bits) at cycle
  `m + j + 4`, per the timing contract's third line — this is the grid's own
  latency (input-arrival latency `k+j` plus the PE pipeline depth through 4
  rows), independent of the skew/de-skew banks that don't exist yet.
- Self-checking, pass/fail per checked value plus a final summary, same
  style as `tb/unpu_pe_tb.sv`.

You may cross-check expected values against `model/vectors/identity_*.hex`
(from task 002) if convenient, but the pass/fail arithmetic above is
sufficient on its own — don't add a `$readmemh` dependency if you don't need
it for this identity-only case.

## Acceptance test

- All 16 `A[m][j]` values (M=4, J=4) appear correctly and at the correct
  cycle (`m+j+4`) at `psum_out[j]`.
- Simulate clean (Icarus/Verilator, note which — Xcelium unavailable per
  task 001's precedent) with no unmatched checks.
- Note in the file header which simulator was used, same convention as
  `unpu_pe.sv`/`unpu_pe_tb.sv`.

## Out of scope

- No skew or de-skew banks (`unpu_skew.sv`/`unpu_deskew.sv`) — that's step 6,
  a separate task.
- No shift-down weight loading network — that's `unpu_wbuf.sv`, step 9. This
  task's weight loading is direct per-PE forcing by the testbench only.
- No sequencer, no DMA, no APB, no CSR — grid in isolation, per the W2 gate.
- Don't touch `rtl/unpu_pe.sv` or its testbench.
