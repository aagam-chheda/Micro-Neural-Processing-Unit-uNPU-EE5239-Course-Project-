# Task 014 — Fix stale simulator headers on `unpu_skew.sv`/`unpu_deskew.sv`

## Goal

Close the open Icarus-vs-Verilator tooling item in `docs/planning/plan.md`.
Decision: standardize on Verilator (de facto standard since task 006, no
simulator-attributable failures across 8 tasks). Two files still claim
otherwise with no correction.

## What's actually stale (checked directly, not assumed)

- `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`: never had a simulator note. Nothing
  to fix.
- `tb/unpu_pe_tb.sv`, `tb/unpu_skew_tb.sv`, `tb/unpu_grid_tb.sv`,
  `tb/unpu_stall_tb.sv`: task 013 already added a clarifying note about
  later Verilator-run additions alongside the original Icarus line.
  Nothing to fix.
- **`rtl/unpu_skew.sv`, `rtl/unpu_deskew.sv`**: still claim only "Simulated
  with Icarus Verilog... Xcelium not available in this environment," with
  no acknowledgment that every regression since task 006 (`unpu_seq_tb`,
  `unpu_buf_tb`, `unpu_dma_tb`, `unpu_stall_tb`, `unpu_top_tb`, task 013's
  own retrofit) has actually re-verified these two files under Verilator.
  These are the two to fix.

## Files

- Edit `rtl/unpu_skew.sv` header only.
- Edit `rtl/unpu_deskew.sv` header only.

Do not touch anything else — this is a comment-only change, no RTL
behavior changes, no other file.

## What to add

Keep the existing "Simulated with Icarus Verilog... Xcelium not
available" line as-is — it's an accurate historical record of task 004.
Add a short note after it, matching the pattern already used in
`tb/unpu_pe_tb.sv`'s header (task 013): every regression since task 006
has actually run this file under Verilator (`iverilog` isn't installed in
that environment), and it's passed clean every time. Point at
`tb/unpu_pe_tb.sv`'s header as the reference for the fuller explanation
rather than repeating it — keep this addition to 2-3 lines.

## Acceptance

- Both files compile/simulate clean under Verilator (they already do —
  this is a comment-only change, just confirm nothing broke).
- Full regression still green.
- No RTL diff — `git diff rtl/unpu_skew.sv rtl/unpu_deskew.sv` should show
  only comment lines changed.

## Out of scope

- No other file.
- No decision-making — the standardize-on-Verilator call is already made;
  this task just documents it accurately in the two places it's missing.
