# Task 015 — RTL freeze regression / sign-off

## Goal

Plan.md step 16. This is the freeze gate: one consolidated pass over
everything built across tasks 001–014, checked against explicit,
recorded thresholds, ending in a written sign-off record. Nothing here
should require an RTL change — if it does, that's a real finding to stop
and report, not something to quietly patch inside this task.

**User's instruction: make this as thorough as possible.** This task is
larger than the usual "does it pass" regression because of that — six
parts, not one, each checking a different way the suite could be
silently weaker than it looks.

## Files

- No RTL, no testbench changes expected.
- Create `docs/freeze-report.md` (the sign-off record — see Part F).
- If Part D's lint sweep or Part E's hygiene audit finds something
  genuinely wrong, stop, do not fix it inside this task, report it back
  instead — this task verifies, it doesn't repair.

## Part A — Full regression, as-is

Run every existing testbench exactly as currently written, to
completion: `unpu_pe_tb`, `unpu_grid_tb`, `unpu_skew_tb`, `unpu_stall_tb`,
`unpu_seq_tb`, `unpu_buf_tb`, `unpu_dma_tb`, `unpu_csr_tb`,
`unpu_slave_tb`, `unpu_top_tb`. Record the actual check/iteration count
each one reports and compare against the floor below — a regression that
silently ran fewer iterations than it used to (a truncated loop, an early
exit) would still print "PASS" without this table:

| Testbench | Minimum checks/iterations (last known) |
|---|---|
| `unpu_pe_tb` | 131,072 exhaustive + 256 accumulator + 50 timing |
| `unpu_grid_tb` | 64 `crv_*` cases (~684 checks) + identity test |
| `unpu_skew_tb` | 64 `crv_*` cases (~636 checks) + `cross_terms` |
| `unpu_stall_tb` | 64 `crv_*` cases, ≥2544 C-checks + ≥26055 freeze-register checks |
| `unpu_seq_tb` | 64 `crv_*` cases, ≥539 checks |
| `unpu_buf_tb` | 64 `crv_*` cases, ≥531 checks |
| `unpu_dma_tb` | 64 `crv_*` cases, ≥1110 checks |
| `unpu_csr_tb` | ≥200 iterations, ≥1838 checks |
| `unpu_slave_tb` | ≥150 iterations, ≥2115 checks |
| `unpu_top_tb` | 64 `crv_*` cases, ≥512 checks |

Any testbench reporting fewer checks than its floor is a freeze blocker
— stop and report, don't average it away against the others.

## Part B — Fresh-seed re-run (flakiness/seed-dependence check)

Every CRV suite in this project has been run so far against one fixed,
documented, printed seed per testbench. That proves reproducibility, not
robustness to *which* seed — a suite could, in principle, happen to pass
cleanly for its one documented seed and fail for another. Re-run every
CRV-bearing testbench listed in Part A a second time, each with a freshly
drawn seed (different from its documented one, still printed for the
record), same iteration counts as Part A. All must still pass. This is
new work this task adds, not a repeat of anything already done.

## Part C — Golden-model determinism

`rm -rf model/vectors`, rebuild and rerun `model/golden.c` from a clean
tree, confirm:
- It still compiles clean (`gcc -std=c99 -Wall -Wextra`, zero warnings).
- Every self-check (`identity`, `all_ones`, `cross_terms`) still passes
  before any file is written, same fail-fast discipline as every prior
  task.
- The regenerated `model/vectors/*.hex`/`*.txt` files are **byte-
  identical** to what's already committed (or, if `model/vectors/` isn't
  committed to the repo, byte-identical to a fresh copy saved before the
  `rm -rf` — confirm which is actually the case and use whichever
  comparison is real). This is the check that nobody hand-edited a
  vector file at some point, or that the generator has drifted from what
  the RTL was actually verified against.
- Re-run all of Part A's suites against the regenerated vectors, confirm
  identical pass/fail results to Part A's original run.

## Part D — Whole-design lint sweep

Every prior task's lint results were per-module or per-testbench,
reported in isolation. Elaborate the full `unpu_top` design (all ten
instantiated modules together, as built in task 012) through Verilator's
lint pass and collect every warning that surfaces only at whole-design
elaboration time — cross-module port-width mismatches, multiply-driven
nets, unconnected outputs beyond the ones already known-expected
(`unpu_grid.act_out`, per task 012's own note), anything Verilator
flags about the aggregate design that no single module's isolated lint
run would have caught. Every warning found must be either genuinely
harmless and documented (matching the standing convention — lint
directives with a comment explaining why, same as task 012's
`GENUNNAMED`/`UNUSEDSIGNAL`/`PINCONNECTEMPTY` handling) or flagged back
as a real finding. Do not add blanket warning suppression to make this
pass quietly.

## Part E — Repository hygiene audit

- Every file CLAUDE.md's "Repo layout" section names under `rtl/` exists
  and matches (`unpu_pe.v` is listed there as `.v` — confirm whether the
  actual delivered files are `.sv` as CLAUDE.md's hard-constraints
  section requires, and if the repo-layout listing itself is stale
  relative to the hard-constraints section, note that as a documentation
  finding, not something to silently "fix" by renaming files).
- No stray, orphaned, or leftover files under `rtl/`/`tb/`/`model/` that
  don't trace back to a task (a scratch file, a `.bak`, a duplicate).
- `git status` is clean at the end of this task — nothing uncommitted,
  nothing untracked that should be tracked.
- Confirm the two files task 014 fixed (`unpu_skew.sv`, `unpu_deskew.sv`)
  and don't have any other file still claiming a simulator that isn't
  what actually verified it (a final grep sweep, not a re-litigation of
  task 014's decision).

## Part F — Freeze report

Write `docs/freeze-report.md`: the exact commit hash being frozen (after
this task's own commit, so include the commit that follows), a table of
every module with its test counts (Part A's table, filled in with actual
results), confirmation that Parts B–E all passed with no open findings
(or, if something in D or E surfaced a real issue, that it's listed here
explicitly rather than silently absorbed), and an explicit statement of
what freeze does **not** cover per `plan.md`'s own "Freeze gate" section
— no timing/STA confirmation (steps 3/5 still pending PDK/server access),
no DRC/LVS/formal signoff, no firmware. This is the single document a
reader should be able to open later and know exactly what "frozen" meant
at this point in the project, without having to reconstruct it from
fourteen task files and a long-running planning doc.

## Acceptance

- Parts A–E all pass with results matching or exceeding every stated
  floor; any finding from D or E is reported, not silently fixed.
- `docs/freeze-report.md` exists, accurate, and stands alone (a reader
  shouldn't need this task file open beside it to understand what it
  says).
- Full regression green, twice (Part A's original seeds, Part B's fresh
  ones), plus Part C's determinism re-run — three total passes agreeing.

## Out of scope

- No RTL changes. If Part D or E turns up something that looks like it
  needs one, stop and report rather than fixing it here.
- No timing/STA, no DRC/LVS, no back-end work of any kind — explicitly
  decoupled from this gate per `plan.md`.
- No firmware.
