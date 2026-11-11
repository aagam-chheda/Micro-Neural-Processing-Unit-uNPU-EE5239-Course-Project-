# Task 036 — Independently verify the teammate's multi-tile branch (`feature/multitile-dual-fsm`)

## Goal

A teammate pushed a branch that rewrites the sequencer into a dual-FSM,
multi-tile, overlapped design. The user wants it verified by Planning and
Execution before anyone decides anything about it. Planning reviews the RTL by
reading it. **You run and break it.** Nothing here merges, rewrites or touches
the teammate's branch or `main`.

- Branch: `origin/feature/multitile-dual-fsm`, two commits on top of `main`
  at `b9b88c6`: `504b4aa` (feat: dual-FSM engine) and `f18dfb3` (fix:
  run_verilator.sh). Author: Vasudev Krishna.
- Changed files (3,211 additions, 286 deletions): `rtl/unpu_seq.sv` (rewritten,
  +440/−255), `rtl/unpu_csr.sv` (+41/−9), `rtl/unpu_top.sv` (+10),
  `tb/unpu_seq_tb.sv` (+679/−3), `tb/unpu_top_tb.sv` (+361/−19), plus new
  `Makefile`, `scripts/run_verilator.sh`, `.gitignore` (+12), and two long
  docs: `docs/pipelining_spec.md` and `docs/step3_verification_plan.md`.
- `rtl/unpu_pe.sv`, `unpu_grid`, `unpu_skew`, `unpu_deskew`, `unpu_wbuf`,
  `unpu_actbuf`, `unpu_dma`, `unpu_apb` are unchanged (confirm with
  `git diff main...origin/feature/multitile-dual-fsm --stat`).
- A second remote branch, `origin/EssPy15-patch-1`, has no commits beyond
  `main`; ignore it.

**What the branch claims** (from its spec; treat each as a claim to test, not
a fact):
1. 100% backward compatibility: with `num_tiles == 1` and all strides `0`, the
   observable behaviour matches the current RTL.
2. A new per-op field layout: `dim_m/dim_n/dim_k[31:16]` = `stride_a/b/c`
   (byte strides, `0` = contiguous default), `npu_ctrl[31:16]` = `num_tiles`
   (resets to 1). No new register offsets.
3. Tile i+1 is prefetched while tile i computes; tile i's C is drained while
   tile i+1 computes (ping-pong output staging inside `unpu_seq`); cold-start
   and final-tile cases are handled; the final tile prefetches nothing.
4. The timing contract (`M+7`, skew 0/1/2/3, de-skew 3/2/1/0) and the PE are
   untouched.
5. Large speedups (the spec says up to 3.8x). Planning's own estimate is far
   lower (the design is memory-bound: 24 DMA beats vs 11 compute cycles per
   full tile). Do **not** try to settle this; report measured cycles per tile
   in Part D and Planning will compare.

**RTL on `main` stays frozen** (`git diff 9f5deab..HEAD -- rtl/` empty on
`main` before and after). Standing rules: nothing fails silently, nothing
hardcoded, seeds printed, no check weakened or dropped to get green, a
survivor or a failure is a finding to report in full, never to work around.
Do not modify the branch's RTL. Do not commit to `main`. Do not push anything
anywhere until the user says so.

## Method

Work in throwaway `git worktree`s outside the repo directory (task 031/032
method: control before and after each change, `git worktree remove --force` at
the end, `git worktree list` pasted). Define three trees and name them in your
report:
- **MAIN**: `main` as is.
- **BRANCH**: the branch tip as pushed (RTL **and** the teammate's testbenches).
- **HYBRID**: the branch's `rtl/` with `main`'s `tb/`, `model/`, `scripts/`
  (i.e. the original, unmodified testbenches against the new RTL).

## Part A — backward compatibility (the headline claim)

A1. **Original testbenches on the new RTL.** In HYBRID run every testbench that
exists on `main`: the frozen ten, `ext1`, `ext2`, with the same flags and
random-init seeds used in Addenda 1 and 2, and compare each check count with
`docs/freeze-report-v2.md` (pe 65,536+65,536 sweeps etc.; `ext1` 34,
`ext2` 15,231 with `rounds: 325 run, 325 passed`). Report every number. Any
failure: decide with evidence whether it is (a) a documented, intended change
(the unmapped-offset and field-layout text in the CSR header) or (b) a
regression, and report both readings. The two independent peer testbenches are
the most valuable here: they were written without knowledge of this branch.

A2. **Differential test, MAIN vs BRANCH, single tile.** Write a throwaway
differential testbench (one clock, both DUTs instantiated side by side, same
APB stimulus, one shared bounds-checked SRAM model per DUT driven by the same
back-pressure sequence) and run a few thousand random single-tile ops:
dims 1..4 each, signed/unsigned, back-pressure always-ready / random /
periodic, random start gaps, ops with illegal dims, back-to-back ops, reset
mid-op. For each op compare the full DMA bus transcript (cycle, address, data,
strobe, valid for every beat), the `done` pulse cycle, `npu_status` over time,
and the final SRAM image. Report: how many ops, and whether anything differs,
**including cycle timing**. A cycle-count difference with identical function is
not automatically a bug; it is a finding to state precisely (by how many cycles,
under which conditions).

## Part B — the teammate's own testbenches

B1. Run BRANCH's `unpu_seq_tb` and `unpu_top_tb` as pushed. Report pass/fail,
check counts, warnings. Run with randomized power-up init too (seeds 1, 7,
12345, 99, 4242, 31337) as in earlier campaigns.

B2. **Audit what was changed in existing tests.** The branch removes or edits
pre-existing lines in the testbenches: `run_case_via_cpu` in
`tb/unpu_top_tb.sv` (the original task is replaced), a `dma_ready` assignment
and two `e_a_case`/`e_w_case` initialisation lines in `tb/unpu_seq_tb.sv`.
For each removed or modified line, state what it did, what replaced it, and
whether any original check or threshold got weaker. Show that every original
single-tile check still exists, running with the same expected values. A
pre-existing check that no longer runs is a finding.

## Part C — do the new tests have teeth? (mutation sanity)

In BRANCH worktrees, apply at least the following mutations to the new RTL,
one at a time, with a clean control before and after each, and record which of
the teammate's testbenches (and the ext pair) catch each, with failure counts
and the first FAIL line. A survivor is a stop-and-report finding.

1. The barrier fires on `compute_done` alone (ignores `prefetch_done`).
2. The barrier fires on `prefetch_done` alone (ignores `compute_done`).
3. The final tile still issues a prefetch (reads past the last tile).
4. The output ping-pong bank select is inverted for tile 1.
5. Tile 0 is not treated as cold-start (drain writes C for a non-existent
   previous tile).
6. `num_tiles` is off by one (one tile too many, then one too few).
7. `stride_c` is applied to the A or B pointer instead.
8. The weight swap for tile i+1 happens one cycle early.
9. The three earlier mutations of tasks 031/032: `m_lat+6 -> +5`, the PE
   `mode_unsigned` polarity, the DMA stride `m*16 -> m*15`, and the address-bit
   alias on bit 15, 16 and 20 (re-derive, do not copy numbers).

Mutation 8 is the one to think hardest about, see the hazard below.

## Part D — independent multi-tile campaign

The teammate's multi-tile tests were written by the same person as the RTL.
Write your own, from the **spec and the CSR header only**, as a new
testbench (name it `tb/unpu_mt_xcheck_tb.sv`, in the scratch worktree until
the user says to commit it):

- Own golden model inside the testbench, computed from operands the TB wrote
  to SRAM, 32-bit accumulate, signed and unsigned. Do not import the teammate's
  model or vectors; do not use `$urandom` (xorshift32, print seeds).
- SRAM model bounds-checked: any access outside the allocated regions is a
  loud, counted error (task 030 lesson), and any access to a word not belonging
  to the current or next tile's A/B regions or the C regions of a tile
  already computed is flagged.
- Per tile distinct, random, high-contrast weights and activations (so a stale
  or early weight swap cannot hide).
- Cases: `num_tiles` = 1, 2, 3, 4, 8, 16 and a few large ones; dims 1..4
  independently for M/N/K including the smallest (M=1, short compute, long
  DMA) and the largest (4x4x4); strides `0` (default), contiguous explicit,
  larger than the tile, and per-matrix differing; signed and unsigned;
  back-pressure always-ready, random, periodic, and slow-SRAM-faster-than-compute
  vs fast-SRAM-slower-than-compute (so each of the two engines is the
  bottleneck in turn).
- Address check per beat: derive the expected address of every A, W and C beat
  for every tile **from the spec's stride formulas** and check every beat the DUT
  issues. If the spec is ambiguous on a formula (for example byte vs word stride,
  or what `0` means when `num_tiles > 1`), stop on that case and report the
  ambiguity; do not pick a reading silently.
- Checks specific to this design: `DONE` pulses once per op (not per tile);
  final tile issues no read beyond its own tile; no C beat is written twice to
  the same address for different tiles unless the strides make that so; the
  total C writes equal `num_tiles * M * N`.
- CSR/firmware sequences that legacy and new firmware could plausibly issue:
  `num_tiles` left over from a previous op (does the next op silently reuse
  it?), a write to `npu_ctrl` with START but upper bits zero, a write with
  upper bits set but no START, writing `dim_*` with stray upper bits (legacy
  code did this safely before), dims or strides changed while an op is running,
  reset in the middle of a multi-tile op, a second START while busy, and an
  illegal dim in a multi-tile op.
- Measure, and print, cycles per op for `num_tiles` = 1 and for large
  `num_tiles`, at several back-pressure settings, MAIN versus BRANCH. That is the
  evidence for the speedup claim. Planning estimates a best case near 1.45x for
  a full 4x4x4 tile against an always-ready SRAM; report what you measure.

## The hazard to think about (Part C mutation 8 and Part D data)

PE weights are shared by all rows of a tile and are swapped in one cycle
(`w_swap`). Tile i's last activation row enters row k at cycle `m+k` and
reaches PE(k,j) at `m+k+j` (CLAUDE.md timing contract), so PE(3,3) is still
working on tile i until about cycle `M+5` after tile i's first injection. A
weight swap, or the start of tile i+1's injection, that is earlier than the
pipeline allows corrupts tile i's tail or tile i+1's head. The spec argues the
barrier prevents this. Test the argument, do not assume it: small M (1 or 2),
large weight differences between consecutive tiles, every back-pressure
combination.

## What you cannot do here

- You cannot run Synopsys tools (server only). Synthesisability is checked
  statically here: Verilator `--lint-only -Wall` on BRANCH RTL (zero new
  warnings versus MAIN), a list of every always_comb for full default
  assignment (no inferred latch), and a table of every new register
  (name, width, purpose) so Planning can estimate the area added by the
  output ping-pong staging. The user runs Design Compiler on the branch
  themselves later if the branch is considered.
- You cannot run Xcelium. If the new testbench is worth running there, say so
  and give the command; the user runs it.

## Report

Reply with:
1. Part A numbers (A1 table with every check count against the freeze report,
   A2 ops compared and every difference with cycle detail).
2. Part B results, and the full list from the B2 audit.
3. Part C table (mutation, which testbench caught it, counts, first FAIL line,
   survivors in bold).
4. Part D: testbench description, case matrix, results, every ambiguity found
   in the spec, and the cycles-per-op table (MAIN vs BRANCH).
5. Static synthesisability notes and the new-register table.
6. A plain verdict list: what is confirmed, what is refuted, what could not
   be checked.
7. Cleanup evidence: `git worktree list`, `git status` on the main clone,
   `git diff 9f5deab..HEAD -- rtl/` empty on `main`.

Do not edit anything under `docs/planning/`. If you want to keep the new
testbench or a short review note, put them on a **local** branch named
`review/multitile-dual-fsm-verification` (based on the teammate's tip) and
leave it unpushed; the user decides. Commit nothing to `main` and never to the
teammate's branch.

## Out of scope

- No fix to the teammate's RTL. No opinion on whether to merge; report facts.
- No change to `main`'s RTL, testbenches, model, or scripts.
- No Design Compiler, ICC2, PrimeTime or Calibre run.
