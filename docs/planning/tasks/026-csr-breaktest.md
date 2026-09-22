# Task 026 — CSR (`unpu_csr`) adversarial stress test (module 8 of 10)

## Goal

Eighth task in the break-it campaign. Same mandate and standing rules as
tasks 019–025 (nothing fails silently, nothing hardcoded, seeds are
whatever gets printed, no threshold narrowed — `docs/planning/plan.md`).
RTL not expected to change; if something breaks, stop and report in
full.

## What's already covered — extend past it

Task 009 built the 8-register file with directed tests (all 8 offsets,
START self-clear, SIGNED-bit polarity, DONE sticky/start-clear behavior,
`npu_status` write-discard, a sample of reserved offsets) and 200-
iteration CRV (1,838 checks) against a shadow model. What it doesn't
reach: the *full* extreme-value range on the 32-bit pointer registers
and the full 3-bit range on the dimension registers (only 0 and 7 were
ever tried, not every value), a direct register-to-register cross-talk
matrix (does writing one register ever leak into another — never
explicitly proven, only inferred from individual reads staying stable),
sustained multi-cycle `START` writes (only single-cycle pulses tried),
and a much denser reserved-offset sweep (only 3 sample points tried
against a 1,016-value reserved range).

`unpu_csr` is purely combinational with no pipelined state, so unlike
modules 1–7 there's no long-sequence state-leak risk to chase — the
break-it value here is in *exhaustive value coverage* and *volume*, not
sequence depth.

## Part A — extreme/structural directed cases

- **Full extreme-value sweep on `src_A`/`src_B`/`dest_C`**: write and
  read back `32'h0000_0000`, `32'hFFFF_FFFF`, `32'h8000_0000`,
  `32'h7FFF_FFFF`, `32'h5555_5555`, `32'hAAAA_AAAA` for each of the
  three registers — confirm exact bit-for-bit match, no bit ever
  dropped or stuck.
- **Full 3-bit range on `dim_M`/`dim_N`/`dim_K`**: all 8 values (`0`
  through `7`), not just the two boundary values task 009 tried —
  confirm verbatim storage for every one (still no legality validation,
  that's `unpu_seq`'s job, unchanged from task 009's own scope note).
- **Register cross-talk matrix**: for each of the 8 real registers in
  turn, write a distinct, recognizable, non-overlapping bit pattern,
  then read back **all 8 registers** (including the one just written)
  and confirm only the intended one changed — the other 7 show zero
  trace of it. 8 rounds × 8 reads, using patterns chosen so any leak
  would be immediately obvious (not all-zero/all-one patterns that
  could coincidentally match).
- **Sustained `START` write**: hold `csr_wen=1`, `csr_sel==6`
  (`npu_ctrl`), `csr_wdata[0]=1` for 10 consecutive cycles (not the
  single-cycle pulse already tested) — confirm `start_pulse` fires on
  **every one** of those 10 cycles (the design registers the write
  condition directly each cycle, it isn't edge-detected — confirm that's
  actually what happens, don't assume it), and confirm `npu_ctrl` still
  reads back bit 0 as `0` throughout, never latching `1`.
- **Denser reserved-offset sweep**: all of `csr_sel` 8–31 directly
  (24 cases) plus ≥50 randomly-sampled values from 32–1023 — confirm
  every one reads `0` and none affect any real register.

## Part B — high-volume extreme-biased CRV

Extend task 009's CRV loop to **≥2,000 iterations** (well past the
original 200), ~15–20% of drawn data forced to an extreme value (same
discipline as every prior module), across the full `csr_sel[9:0]` range,
self-checked against the same shadow model task 009 built (extend it if
Part A's new behaviors — sustained-write, cross-talk — need shadow-model
support it doesn't already have). Seed printed, reproducible.

## Files

- Extend `tb/unpu_csr_tb.sv` only. Do not modify `rtl/unpu_csr.sv` or
  any other RTL file.

## Acceptance

- All Part A directed cases pass, including all 6 extreme values × 3
  registers, all 8 dimension values × 3 registers, the full 64-check
  cross-talk matrix, sustained-write, and the denser reserved sweep.
- Part B: ≥2,000 iterations, 0 failures, seed printed and reproducible,
  total check count reported (expect well past 10,000).
- Task 009's existing 1,838-check baseline still passes unchanged.
- Full regression on every other testbench unaffected.
- Simulate clean under Verilator.
- **If anything fails**: stop, report the exact register/offset/value
  and iteration/seed at divergence. No RTL fix attempted here, no check
  softened to pass.

## Out of scope

- No RTL changes.
- No other testbench — module 9 (`unpu_apb`) is next.
