# RTL freeze report — task 015

**Frozen commit:** `87d31bf4b99def1bb0b26a84dcba8f1b9fee033e`

This is that commit's own freeze-gate task (`docs/planning/tasks/015-freeze.md`,
plan.md step 16). This hash was filled in by a one-line follow-up commit
immediately after the one that first added this file, since a commit cannot
name its own hash in advance.

This document is meant to stand alone: read only this file, without any of
the fourteen prior task files or `docs/planning/plan.md`'s history, and know
exactly what "frozen" means at this commit.

## What "frozen" means here

Every module built across tasks 001–014 (`unpu_pe`, `unpu_grid`, `unpu_skew`,
`unpu_deskew`, `unpu_dma`, `unpu_actbuf`, `unpu_wbuf`, `unpu_csr`, `unpu_seq`,
`unpu_slave`, `unpu_top`) passes its full testbench, at or above every
previously-recorded minimum check count, under three independent conditions:
the documented seed (Part A), a freshly-drawn seed per CRV-bearing
testbench (Part B), and a clean rebuild of the golden-model vector files
from scratch (Part C). No RTL or testbench change was made to reach this
state — this task is a verification pass, not a repair pass; see "Open
findings" below for the two things it surfaced without fixing.

**Freeze is functional correctness only.** See "What this freeze does not
cover" below — this is not a timing, DRC/LVS, or firmware signoff.

## Toolchain used

- Simulator: Verilator 5.053 (`verilator --binary --timing`), not Xcelium —
  Xcelium is unavailable in this environment. This has been the standing
  simulator since task 006; see the "Icarus header sweep" finding below for
  why some file headers still mention Icarus Verilog.
- Golden model: `model/golden.c`, compiled with `gcc -std=c99 -Wall -Wextra`.
- Lint: `verilator --lint-only -Wall`.

## Part A — full regression, documented seeds

Every testbench run to completion exactly as committed, against
`model/vectors/*` regenerated fresh from `model/golden.c` with its
documented `CRV_SEED = 32'h5eed0006` (and each testbench's own documented
internal seed, where it has one). All ten pass; every floor is met exactly
(these floors were themselves derived from this class of run, so an exact
match is expected, not a coincidence).

| Testbench | Result | Floor | Met? |
|---|---|---|---|
| `unpu_pe_tb` | 131,072 exhaustive (65,536 signed + 65,536 unsigned) + 256 accumulator + 50 iterations/255 cycle-checks timing, 0 failures | 131,072 exhaustive + 256 accumulator + 50 timing | Yes (exact) |
| `unpu_grid_tb` | 68 cases (64 `crv_*` + 4 directed), 684 checks, 0 failures | 64 `crv_*` (~684 checks) + identity test | Yes (exact) |
| `unpu_skew_tb` | 636 checks, 0 failures | 64 `crv_*` (~636 checks) + `cross_terms` | Yes (exact) |
| `unpu_stall_tb` | 2,544 C-checks + 26,055 freeze-register checks, 0 failures | 64 `crv_*`, ≥2544 C-checks + ≥26055 freeze-register checks | Yes (exact) |
| `unpu_seq_tb` | 539 checks, 0 failures | 64 `crv_*`, ≥539 checks | Yes (exact) |
| `unpu_buf_tb` | 531 checks, 0 failures | 64 `crv_*`, ≥531 checks | Yes (exact) |
| `unpu_dma_tb` | 1,110 checks, 0 failures | 64 `crv_*`, ≥1110 checks | Yes (exact) |
| `unpu_csr_tb` | 200 iterations, 1,838 checks, 0 failures | ≥200 iterations, ≥1838 checks | Yes (exact) |
| `unpu_slave_tb` | 150 iterations, 2,115 checks, 0 failures | ≥150 iterations, ≥2115 checks | Yes (exact) |
| `unpu_top_tb` | 512 checks, 0 failures | 64 `crv_*`, ≥512 checks | Yes (exact) |

No testbench reported fewer checks than its floor. No freeze blocker from
Part A.

**Verification debt closed.** `docs/session-handoff.md` §14 tracked steps
1–7 (built directed-only, before CRV became standing policy) as debt to be
decided explicitly at this gate rather than left to slide. Task 013
retrofitted CRV onto `unpu_pe_tb`, `unpu_grid_tb`, `unpu_skew_tb`, and
`unpu_stall_tb` — the four Part-A testbenches above that predate the CRV
mandate — and all four now carry `crv_*`/randomized coverage as shown in
the table. Every testbench in this project now has CRV coverage; the debt
is fully closed, not carried forward.

## Part B — fresh-seed re-run (flakiness / seed-dependence check)

Every CRV-bearing testbench (all ten — `unpu_pe_tb`'s accumulator-sweep and
weight-load-timing draws count as CRV even though it has no `crv_*` vector
files of its own) was re-run with a freshly-drawn seed, distinct from its
documented one, same case/iteration counts as Part A:

- `model/golden.c`'s `CRV_SEED`: `0x5eed0006` → `0xf00d1006` (regenerates
  all 64 `crv_*` vector files with new M/K/N shapes and data — this is what
  drove the fresh run for `unpu_grid_tb`, `unpu_skew_tb`, `unpu_stall_tb`,
  `unpu_seq_tb`, `unpu_buf_tb`, `unpu_dma_tb`, and `unpu_top_tb`, since all
  of them consume the shared `crv_*` vector files).
- Each testbench's own internal RNG/back-pressure seed constant (`rng`,
  `swap_seed`, `addr_rng`/`bp_rng`, `g_seed`) was likewise bumped to a
  fresh, distinct value in `unpu_pe_tb.sv`, `unpu_buf_tb.sv`,
  `unpu_csr_tb.sv`, `unpu_dma_tb.sv`, `unpu_slave_tb.sv`, `unpu_stall_tb.sv`,
  `unpu_seq_tb.sv`, and `unpu_top_tb.sv`.

All ten testbenches passed, 0 failures, same case/iteration counts as Part A
(check *counts* differ slightly where they're data-dependent — e.g.
`unpu_grid_tb` reported 672 checks against the new seed vs. 684 against the
old one — because the new seed drew a different, still-valid, mix of M/K/N
shapes; this is expected, not a discrepancy). No seed-dependent flakiness
found.

These seed edits were **temporary, for this verification run only** — every
file was reverted with `git checkout` immediately after Part B's runs
completed, confirmed by an empty `git diff` against the nine touched files.
Nothing from Part B is a permanent testbench change; see "No RTL/testbench
changes" below.

## Part C — golden-model determinism

From the Part-A/B state (original `CRV_SEED`, all edits reverted):

1. `model/golden.c` recompiled with `gcc -std=c99 -Wall -Wextra`: zero
   warnings.
2. Every self-check (`identity`, `all_ones`, `cross_terms`, plus
   `random_signed`/`random_unsigned`) passed and printed **before** any
   vector file was written — fail-fast discipline intact.
3. `model/vectors/` is **gitignored, not committed** (confirmed via
   `.gitignore` and `git ls-files model/vectors` returning nothing) — so
   the byte-identical comparison used is against a copy saved immediately
   before `rm -rf model/vectors`, not a git-tracked baseline. After
   `rm -rf model/vectors` and a clean rebuild, `diff -rq` against that
   saved copy reported **zero differences across all 292 files**.
4. All ten testbenches were re-run against the regenerated vectors (tag
   "C"). Every run's output is **identical** to its Part-A run, byte for
   byte (excluding Verilator's own non-deterministic walltime/speed report
   lines) — same pass/fail, same check counts, same per-case values.

Three independent passes (Part A's documented seed, Part B's fresh seed,
Part C's clean rebuild) all agree. No flakiness, no vector-file drift.

## Part D — whole-design lint sweep

`verilator --lint-only -Wall` elaborating `unpu_top` together with all ten
instantiated submodules (13 modules total once PE instances are counted)
surfaced only the four `GENUNNAMED` warnings that `unpu_grid.sv` already
produces under an **isolated** lint pass (unnamed `generate` blocks around
its per-row/per-column `assign`s) — confirmed by re-running the lint pass
on `unpu_grid.sv` + `unpu_pe.sv` alone and getting the identical four
warnings. These are not whole-design-only findings, so they're out of this
part's scope by its own definition ("warnings that surface only at
whole-design elaboration time"); they're pre-existing, cosmetic
(IEEE 1800-2023 §27.6 naming-style suggestions), and were never a synthesis
blocker.

With those four suppressed (`-Wno-GENUNNAMED`), the whole-design lint pass
is **completely clean**: zero warnings. No cross-module port-width
mismatches, no multiply-driven nets, no unconnected pins beyond
`unpu_grid.act_out` (already known-expected and documented at task 012 —
see `docs/planning/tasks/012-top.md`). The `UNUSEDSIGNAL`/`PINCONNECTEMPTY`
waivers already present in `unpu_slave.sv` and `unpu_top.sv` fully contain
what they were written to contain — nothing leaked past them at whole-design
scope.

**No findings from Part D.**

## Part E — repository hygiene audit

- **Documentation finding (not fixed in this task):** `CLAUDE.md`'s "Repo
  layout" section (lines 57–72) lists `rtl/` contents with `.v` extensions
  and names `unpu_apb.v`, which does not exist and never will under the
  native-interface decision (`docs/session-handoff.md` §5) — APB was
  removed from the design, replaced by `unpu_slave.sv`, which the layout
  section doesn't list at all. This directly contradicts CLAUDE.md's own
  "Hard constraints" section two screens up, which requires SystemVerilog
  (`.sv`). The eleven files actually delivered
  (`unpu_pe.sv unpu_grid.sv unpu_skew.sv unpu_deskew.sv unpu_dma.sv
  unpu_actbuf.sv unpu_wbuf.sv unpu_csr.sv unpu_seq.sv unpu_slave.sv
  unpu_top.sv`) are all present and all correctly `.sv` — only the
  documentation text is stale. Per this task's own scope ("verifies,
  doesn't repair"), this is reported here rather than edited.
- No stray, orphaned, or scratch files under `rtl/`, `tb/`, or `model/`:
  `rtl/` holds exactly the eleven module files above; `tb/` holds exactly
  the ten testbenches in the Part A table; `model/` holds `golden.c` plus
  the gitignored `golden` binary and `vectors/` directory. No `.bak` files,
  no duplicates, no leftovers.
- `git status` is clean at the end of this task: nothing uncommitted,
  nothing untracked that should be tracked (the only untracked entries are
  `model/golden` and `model/vectors/`, both correctly gitignored build
  artifacts).
- Icarus-header sweep: six files carry a historical "Simulated with Icarus
  Verilog" line — `rtl/unpu_skew.sv`, `rtl/unpu_deskew.sv` (both fixed by
  task 014), and `tb/unpu_grid_tb.sv`, `tb/unpu_pe_tb.sv`,
  `tb/unpu_skew_tb.sv`, `tb/unpu_stall_tb.sv` (already carrying the same
  clarifying-note pattern since tasks 006/013). Every one of the six has an
  explicit adjacent note stating the line is stale for this environment and
  pointing to `tb/unpu_pe_tb.sv`'s header for the explanation — none is a
  bare, unqualified stale claim. Task 014's fix is confirmed complete and
  consistent; no other file needs the same treatment.

**One finding from Part E** (the CLAUDE.md repo-layout staleness above);
everything else clean.

## No RTL/testbench changes

This task made no permanent change to any file under `rtl/` or `tb/`. Part
B's seed edits were reverted before Part C ran (confirmed by empty
`git diff`); the only files this task adds are this report and the
one-line follow-up commit that fills in the hash above.

## What this freeze does **not** cover

Per `docs/planning/plan.md`'s "Freeze gate" section, freeze at this commit
is **functional correctness only**:

- **No timing/STA.** Steps 3 and 5 (Genus synthesis trial, IC Compiler
  trial hardening) are back-end prerequisites, blocked on PDK/tool server
  access, and explicitly decoupled from this gate. 50 MHz closure is not
  confirmed by anything in this report.
- **No DRC/LVS/formal-equivalence signoff.** Tooling for these is not yet
  selected (`docs/session-handoff.md` §7.1).
- **No firmware.** `fw/` is out of scope for this task and for RTL freeze
  generally.
- **No scan-chain/BIST simulation.** Confirmed out of scope for this
  project (`docs/session-handoff.md` §4 Q10, §6); nothing to cover here.

If back-end work later reveals 50 MHz doesn't close, or DRC/LVS finds a
macro-level problem, that reopens RTL — an accepted risk per plan.md's
freeze-gate section, not a defect in this freeze.
