# Task 027 — APB slave (`unpu_apb`) adversarial stress test (module 9 of 10)

## Goal

Ninth task in the break-it campaign. Same mandate and standing rules as
tasks 019–026 (nothing fails silently, nothing hardcoded, seeds are
whatever gets printed, no threshold narrowed — `docs/planning/plan.md`).
RTL not expected to change; if something breaks, stop and report in
full.

## What's already covered — extend past it

Task 018 built `unpu_apb` and `tb/unpu_apb_tb.sv` with directed cases
(SETUP-phase-must-not-commit, `PWRITE` read/write dispatch, sparse
`psel` pacing, `pready==1` as a standalone property, reserved-offset
access) and 150-iteration CRV (2,259 checks). Like `unpu_csr`, this
module is pure combinational glue — no pipelined state, so the break-it
value here is exhaustive/adversarial *protocol* conditions, not sequence
depth.

What's not reached yet: whether the bits of `paddr` this design
deliberately ignores (everything outside `[11:2]`) are *actually*
ignored under adversarial values, not just untested; `penable` asserted
without `psel` (confirming `psel` is genuinely load-bearing in the AND,
not redundant); an adversarially long SETUP phase with changing data,
confirming only the final pre-ACCESS values commit; back-to-back
transactions with zero idle cycles at maximum throughput; and `pwrite`
changing value between SETUP and ACCESS.

## Part A — extreme/structural directed cases

- **Ignored-bits immunity**: randomize `paddr[31:12]` and `paddr[1:0]`
  across many draws while holding `paddr[11:2]` fixed at a known
  register's offset — confirm behavior is completely unaffected by
  whatever garbage sits in the bits this design deliberately doesn't
  decode. This is the direct proof that `csr_sel = paddr[11:2]` really
  does ignore everything else, not just that it happens to work on
  clean test addresses.
- **`penable` without `psel`**: `psel=0`, `penable=1`, `pwrite=1`, real
  write data present — confirm no write commits. This specifically
  proves `psel` is a necessary term in `csr_wen`'s AND, not redundant
  with `penable` in practice.
- **Adversarially long SETUP phase**: hold `psel=1, penable=0` for
  ≥50 cycles, with `paddr`/`pwdata` **changing every cycle** during
  that hold, then assert `penable=1` on one final, distinct set of
  values — confirm only *those* final values commit, and none of the
  transient SETUP-phase values that appeared during the long hold ever
  leak through.
- **Zero-gap back-to-back transactions**: SETUP, ACCESS, SETUP, ACCESS,
  every single cycle with no idle gap — the fastest possible APB
  transaction rate — for at least 20 consecutive transactions. Confirm
  every one commits or reads correctly, none dropped, none duplicated.
- **`pwrite` flips between SETUP and ACCESS**: `pwrite=1` during SETUP,
  flipped to `pwrite=0` at the exact ACCESS cycle — confirm this is
  treated as a **read**, matching the same-cycle sampling
  (`csr_wen = psel && penable && pwrite`, evaluated at ACCESS, not
  latched from SETUP).

## Part B — high-volume extreme-biased CRV

Extend the existing CRV loop to **≥2,000 iterations** (matching the
scale used for `unpu_csr`, task 026), ~15–20% extreme-biased data,
randomized pacing that includes occasional long-SETUP and zero-gap
patterns mixed in with ordinary single-cycle-SETUP transactions, self-
checked against the shadow model already built for this module (extend
it if the new Part A behaviors need support it doesn't already have).

## Files

- Extend `tb/unpu_apb_tb.sv` only. Do not modify `rtl/unpu_apb.sv`,
  `rtl/unpu_csr.sv`, or any other RTL file.

## Acceptance

- All Part A directed cases pass, including the ignored-bits sweep,
  the `penable`-without-`psel` case, the long-SETUP case, the zero-gap
  back-to-back sequence, and the `pwrite`-flip case.
- Part B: ≥2,000 iterations, 0 failures, seed printed and reproducible,
  total check count reported (expect well past 10,000).
- Task 018's existing 2,259-check baseline still passes unchanged.
- Full regression on every other testbench unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact scenario and
  iteration/seed at divergence. No RTL fix attempted here, no check
  softened to pass.

## Out of scope

- No RTL changes.
- No other testbench — module 10 (`unpu_top`) is next, the last one.
