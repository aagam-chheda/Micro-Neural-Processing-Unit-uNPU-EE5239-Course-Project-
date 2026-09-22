# Task 019 — PE adversarial stress test (module 1 of 10)

## Goal

First task in a module-by-module "try to break it" campaign, run before
the next freeze pass. User's framing, exactly: write extensive directed
and CRV testing (~10,000 checks, varying seeds) for every module,
starting at `unpu_pe` and working up to `unpu_top`, one module at a time
— **if it doesn't break, we're golden.** This is not about hitting a
number; it's about genuinely trying to find a failure mode task 013's
retrofit didn't reach. If you find one: stop, do not tune the test to
avoid it, do not fix the RTL inside this task — report the exact
scenario (seed, cycle, signal values) in full so it can be root-caused
deliberately. A found bug is this task doing its job, not a problem with
the task.

**RTL is not expected to change.** This is testbench-only, same as task
013. `rtl/unpu_pe.sv` stays frozen unless this task finds a real defect
in it — which would be reported, not patched here.

## What task 013 already covers — don't repeat it, extend past it

`tb/unpu_pe_tb.sv` already has: an exhaustive 256×256 signed + 256×256
unsigned operand sweep (131,072 combinations — every possible
`weight`×`act` pair, both modes, so there is no operand *value* left to
randomly sample), a 256-iteration accumulator-carry sweep, and a
50-iteration randomized weight-load-timing sweep. That's a strong
baseline on **values**. What it doesn't cover: long, adversarial,
multi-cycle **sequences** — many interacting decisions (freeze, reload,
mode-switch, extreme values) compounding over hundreds of cycles, which
is exactly the kind of thing that finds a bug an isolated single-cycle
check can't.

## The adversarial long-sequence test — the core of this task

Build an independent, cycle-accurate reference model of `unpu_pe` in the
testbench — **derive it from the module's documented behavior, don't
transcribe `unpu_pe.sv`'s own code** (same discipline task 013 already
used for its operand-sweep reference):

- State: `weight_reg` (8b), `act_out` (8b), `psum_out` (32b). All reset
  to 0 on `rst_n=0`.
- Each cycle where `array_en=1`:
  - `product = mode_unsigned ? unsigned(weight_reg) * unsigned(act_in)
    : signed(weight_reg) * signed(act_in)` — using `weight_reg`'s value
    from *before* this cycle's update (a same-cycle `weight_load` must
    not affect this cycle's product — this is the property under test).
  - `psum_out' = psum_in + product`; `act_out' = act_in`; `weight_reg' =
    weight_load ? weight_in : weight_reg`.
  - All three update together on the clock edge.
- Each cycle where `array_en=0`: nothing changes, all three hold.

Run **at least 20 independently-seeded sequences, each at least 500
cycles** (≥10,000 total cycle-checks — report the actual total
achieved). Each sequence: print its own seed, drive every input with a
per-cycle random decision, compare DUT `act_out`/`psum_out` (and
`weight_reg` via hierarchical read, same precedent as prior whitebox
checks in this project) against the reference model **every single
cycle**, not just at sequence end.

Per-cycle random decision process — bias it toward adversarial
conditions, don't just draw uniformly and call it done:

- **`array_en`**: mostly 1, but inject freeze bursts of random duration
  (1–20 cycles), including back-to-back freezes with only a 1-cycle gap
  between them, and occasionally a long freeze (up to ~50 cycles) to
  stress long-held state.
- **`weight_load`**: random each cycle, but bias so it's sometimes held
  high for several *consecutive* cycles (not just isolated pulses) with
  a *different* `weight_in` each of those cycles — this checks
  `weight_reg` tracks the latest value every held cycle, not just the
  first (an under-tested pattern; task 013's 50-iteration sweep only
  exercised single pulses).
- **`weight_in`/`act_in`/`psum_in`**: full-range random, but force
  roughly 10–20% of draws to an extreme value instead (`0x00`, `0xFF`,
  `0x80`, `0x7F` for the 8-bit fields; the `32'h0`/`32'hFFFF_FFFF`/
  `32'h8000_0000`/`32'h7FFF_FFFF` analogues for `psum_in`) — bias toward
  the boundaries, don't rely on uniform random to find them by chance.
- **`mode_unsigned`**: random toggle each cycle.

## Directed boundary cases (beyond what the random sequences might not reliably hit)

- `weight_load` asserted on the very first cycle after reset.
- `weight_load=1` while `array_en=0`, simultaneously: confirm *nothing*
  latches (matches `unpu_pe.sv`'s own documented behavior — "array_en ==
  0: every register holds, including weight_reg even if weight_load
  happens to be asserted"). Don't just trust the random sequences to hit
  this combination; force it directly.
- `rst_n` deasserted for one cycle in the *middle* of an otherwise-normal
  sequence (not just at the start of a test): confirm every register
  clears immediately and the sequence resumes correctly afterward.
- `weight_load` held high for ≥5 consecutive cycles with a distinct
  `weight_in` each cycle, `array_en=1` throughout: confirm `weight_reg`
  updates every one of those cycles, not just the first.

## Files

- Extend `tb/unpu_pe_tb.sv` only. Do not modify `rtl/unpu_pe.sv`.

## Acceptance

- All directed boundary cases pass.
- ≥20 independently-seeded long sequences, ≥10,000 total cycle-checks,
  0 failures, every seed printed and reproducible.
- Task 013's existing exhaustive/accumulator/timing sweeps still pass
  unchanged (regression on this same file).
- Full regression on every other testbench unaffected (this task
  touches nothing else).
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact seed + cycle number +
  full signal state at the point of divergence, and do not attempt an
  RTL fix as part of this task.

## Out of scope

- No RTL changes.
- No other testbench — this is PE only. Grid is next, but only after
  the user reviews this task's results and says to continue.
