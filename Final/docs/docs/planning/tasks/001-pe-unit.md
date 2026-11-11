# Task 001 — PE module + unit test

## Goal

Implement the single-stage systolic processing element and prove it correct
in isolation with a directed unit test.

## Files

- Create `rtl/unpu_pe.sv`
- Create `tb/unpu_pe_tb.sv`

## Interface (fixed — this becomes the grid's building block in a later step, don't improvise a different shape)

```systemverilog
module unpu_pe (
  input  logic              clk,
  input  logic              rst_n,        // async or sync reset, your call, document which

  input  logic              array_en,     // single global enable/freeze signal
  input  logic              weight_load,  // pulse: capture weight_in this cycle
  input  logic              mode_unsigned,// 0 = signed interpretation, 1 = unsigned

  input  logic [7:0]        weight_in,
  input  logic [7:0]        act_in,
  input  logic [31:0]       psum_in,

  output logic [7:0]        act_out,      // registered pass-through, feeds PE to the east
  output logic [31:0]       psum_out      // registered accumulate, feeds PE to the south
);
```

Behavior, each clock edge where `array_en == 1`:
- if `weight_load == 1`: capture `weight_in` into the stationary weight register.
- always: `act_out <= act_in` (registered pass-through — this is what produces the
  `+1` cycle of latency per column in the timing contract).
- always: `psum_out <= psum_in + (act_in * weight_reg)`, where the multiply and
  add are single-stage — combinational into the same output register, not a
  separate pipelined multiply stage.

When `array_en == 0`, **every** register in the PE — weight register, `act_out`,
`psum_out` — holds. Nothing updates, including the weight register even if
`weight_load` happens to be asserted. This is a hard constraint, not a
convenience: a later step tests that `array_en` freezes the whole array
(PEs, skew bank, de-skew bank) on the same edge, bit-identically, and a PE
that updates its weight register while frozen would break that test silently
right now, before it's even written.

`mode_unsigned` selects how `weight_in`/`act_in`'s 8 bits are interpreted for
the multiply: two's-complement signed when 0, unsigned when 1. `psum_in`/
`psum_out` are always plain 32-bit accumulation of whatever the multiply
produces — no separate signed/unsigned handling on the accumulator itself.

## Constraints (from CLAUDE.md — quoted, not paraphrased)

- "RTL is SystemVerilog... Stick to the synthesisable subset — `logic`,
  `always_ff` / `always_comb`, packed structs, enums for FSM states."
- "Target clock: 50 MHz. This means a single-stage PE — do not pipeline the
  multiplier." The multiply-accumulate above must resolve combinationally
  into one register stage, not two.
- "Accumulator is 32 bits throughout." `psum_in`/`psum_out` are 32 bits, full
  stop — do not narrow or saturate internally.
- One module per file, filename matches module name.

## Acceptance test

`tb/unpu_pe_tb.sv` runs 20 directed vectors and all must pass (self-checking,
report pass/fail per vector and a final summary). Cover at minimum:

1. **Max positive** — signed mode, weight and activation both `0x7F` (127),
   confirm `psum_out` accumulates `127*127 = 16129` correctly on top of a
   nonzero `psum_in`.
2. **Max negative** — signed mode, weight and activation both `0x80` (−128),
   confirm `(-128)*(-128) = 16384` accumulates correctly.
3. **Zero weight** — weight register loaded with `0x00`, any activation,
   confirm `psum_out == psum_in` (product contributes nothing) and that
   `act_out` still passes the activation through unchanged.
4. **Weight-load-while-computing** — stream a few cycles of activations
   through a loaded weight, then assert `weight_load` with a new weight value
   on a cycle where `act_in` is simultaneously nonzero, and confirm: the
   product computed *that same cycle* still uses the *old* weight (the load
   takes effect for the next cycle's multiply, not the current one), and the
   new weight is in effect from the following cycle on.
5. **Signed/unsigned saturation pair** — the mandated `0xFF * 0xFF` case, run
   once with `mode_unsigned = 0` (expect `(-1)*(-1) = 1`) and once with
   `mode_unsigned = 1` (expect `255*255 = 65025`), on top of a zero
   `psum_in`, to prove the mode bit actually changes the interpretation
   rather than just being wired but unused.
6. **`array_en` freeze** — mid-stream, hold `array_en = 0` for a few cycles
   while toggling `act_in`, `weight_in`, and `weight_load`; confirm `act_out`,
   `psum_out`, and the internal weight register (observe via a subsequent
   compute) are all unchanged until `array_en` returns to 1.
7. Remaining vectors: your judgment — reset behavior, back-to-back weight
   loads, a couple of mid-range signed values, `psum_in` near `0x7FFF_FFFF`
   to confirm no accidental narrowing. Keep the total at 20 and keep each
   vector's intent legible from a comment on the vector, not from the test
   structure.

Run in Xcelium (or your simulator of choice if Xcelium isn't set up yet on
your end — note which you used). All 20 vectors passing is the bar; nothing
else is deliverable-complete for this task.

## Out of scope

- No grid, no skew/de-skew, no sequencer — this is the PE in total isolation.
- No synthesis. Genus bring-up is a separate, currently-blocked task.
- Don't invent additional ports (no scan, no debug taps) — the interface
  above is what the grid step will instantiate 16 of; changing it later is a
  cross-cutting change, not a local fix.
