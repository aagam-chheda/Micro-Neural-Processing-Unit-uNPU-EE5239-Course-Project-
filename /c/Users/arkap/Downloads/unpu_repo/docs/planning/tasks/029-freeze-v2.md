# Task 029 — RTL freeze v2: post-campaign re-certification

## Goal

Second freeze pass. The first (task 015, `87d31bf`) certified functional
correctness before the APB revert and the break-it campaign existed.
Since then: the CPU-facing interface reverted from native to APB (task
018, `9f5deab`), and every module was adversarially stress-tested —
~744,837 checks across ten tasks, zero RTL defects found
(`docs/planning/plan.md`'s campaign summary). **RTL has not changed
since the APB revert.** This pass exists to prove that precisely, lock
in the campaign's results as the new certified floor, and produce a
freeze report that supersedes the first one.

**User's instruction: every pass criterion in this task is strictly
tighter than task 015's.** Where task 015 asked for "at or above a
floor," this asks for exact, reconciled numbers. Where task 015 checked
RTL hadn't changed by inspection, this checks it by diff against a named
commit. Where task 015 trusted the test suite's results, this task adds
a part that deliberately breaks the RTL in an isolated copy to prove the
suite would actually catch it. This is meant to be the most rigorous
single verification pass in the project's history — treat it that way.
**Standing campaign rules still apply**: nothing fails silently, nothing
hardcoded, no threshold softened to get a clean report. If any part of
this task finds something wrong, stop, report it in full, and do not
proceed to write the freeze report until it's resolved.

## Part A — full regression, exact reconciliation (not just a floor)

Run every one of the ten testbenches (`unpu_pe_tb` through
`unpu_top_tb`) to completion, record each one's **exact** self-reported
total check count and pass/fail result. For each, reconcile that number
against the sum of every task's own reported increment for that file,
per `docs/planning/plan.md`'s task-by-task write-ups (task 013's
baseline + each break-it task's own reported count). **If the actual
total doesn't match that sum, stop and investigate why before
proceeding** — don't accept a higher or lower number without
understanding the discrepancy; a higher number might just mean two
tasks' counts overlap in what they're counting (fine, but explain it),
a lower number is a real problem.

Record every testbench's exact count in a table — this becomes the new
authoritative floor, replacing task 015's now-stale one.

## Part B — RTL identity, verified by diff against a named commit

`git diff 9f5deab..HEAD -- rtl/` must show **zero differences**. Run it,
paste the (empty) output into the freeze report as evidence, not just a
claim. If it's not empty, stop immediately and report exactly what
changed and when — that would mean RTL drifted outside the task process,
a serious finding on its own regardless of what changed.

Also confirm the current `rtl/` file list (`ls rtl/*.sv`) matches
`CLAUDE.md`'s repo-layout listing exactly, and matches the eleven files
named in task 018's completion record — no file added, removed, or
renamed since.

## Part C — fresh-seed re-run, at full original scale (not reduced)

For each of the ten break-it tasks (019–028), re-run that testbench's
adversarial long-sequence/CRV portion with a **freshly-drawn master
seed**, at the **same scale its original task required** (e.g. task
019's ≥20 sequences/≥10,000 checks gets re-run at ≥20 sequences/≥10,000
checks again, not a token handful of iterations). This is substantially
more work than task 015's Part B (which only re-ran the lighter task-013
baseline) — it's re-proving the campaign's actual depth with independent
randomness, not just checking the suite still runs. Print every seed
used. 0 failures required across all ten.

## Part D — golden-model determinism, cross-checked from a clean checkout

1. `rm -rf model/vectors`, rebuild `model/golden.c`
   (`gcc -std=c99 -Wall -Wextra`, zero warnings), confirm every self-
   check passes before any file is written (fail-fast discipline
   unchanged).
2. Confirm the regenerated vectors are byte-identical to a copy saved
   immediately before the `rm -rf` (same method task 015 used).
3. **New this pass**: also build `model/golden.c` from a completely
   separate clean checkout (`git worktree add` into a throwaway
   directory at the current commit, build there, diff the two binaries'
   *output* — not necessarily the binaries themselves, which may differ
   for build-path reasons, but their generated vector files must be
   byte-identical). Remove the throwaway worktree when done
   (`git worktree remove`) — leave zero trace in the main tree.

## Part E — whole-design lint, diffed against the first freeze report's documented output

`verilator --lint-only -Wall` on `unpu_top` + all ten submodules. The
first freeze report (`docs/freeze-report.md`, Part D) documented exactly
four pre-existing `GENUNNAMED` warnings from `unpu_grid.sv`, confirmed
isolated and cosmetic. This pass must produce **the exact same four
warnings, textually, and nothing else** — diff the new lint output
against that report's documented text, don't just count warnings. Any
new warning, any changed warning, any missing warning is a finding to
report, not to explain away.

## Part F — mutation spot-check: prove the test suite has teeth

**This is new, not in task 015 — the strongest possible confidence check
this project can do without a second independent simulator.** ~745,000
checks passing is only meaningful if the checks are actually capable of
catching a real defect. Prove it, in a fully isolated, fully cleaned-up
way:

1. `git worktree add ../unpu-mutation-check HEAD` (or equivalent —
   anywhere clearly outside the main tracked tree, never inside `rtl/`
   or `tb/` in the real working directory).
2. In that isolated copy **only**, introduce one small, deliberate,
   documented mutation at a time, from this list (pick at least these
   three, each targeting a different module's already-proven-strong
   coverage):
   - `unpu_seq.sv`: change `COMPUTE`'s stop condition from `cycle ==
     m_lat + 6` to `cycle == m_lat + 5` (a one-cycle-early bug — exactly
     the bug class this project caught once already in the PM's own
     sketch, task 006). Expect task 023's Part D (exhaustive
     `(dim_k,dim_n)` independence sweep) to catch it.
   - `unpu_pe.sv`: invert the `mode_unsigned` polarity in the
     combinational product logic. Expect task 019's exhaustive operand
     sweep to catch it immediately (every unsigned case would fail).
   - `unpu_dma.sv`: change the writeback row stride from `m*16` to
     `m*15`. Expect task 025's exhaustive burst-length sweep or task
     028's wraparound case to catch it.
3. For each mutation: run the relevant testbench(es) against the
   mutated copy, confirm they **fail** (and roughly where/how — does the
   failure point at something close to the actual mutation, or somewhere
   unrelated, which would itself be worth noting). Record the result.
4. **Revert every mutation and remove the worktree
   (`git worktree remove --force ../unpu-mutation-check`) before this
   task is considered done.** Nothing from this part may ever be
   committed, merged, or left behind — confirm with `git worktree list`
   and `git status` in the main tree afterward that no trace remains.

If any mutation *doesn't* get caught, that's a real, significant
finding about the test suite's actual coverage — stop, report exactly
which mutation survived and why, and do not write the freeze report
until this is resolved (the campaign's "0 defects found" claim would
need re-examining in that light).

## Part G — exhaustive repository hygiene audit

- Every file under `rtl/`, `tb/`, `model/`, `docs/planning/tasks/`
  accounted for — traced back to the task that created or last modified
  it, no orphans, no scratch files, no duplicates.
- `git status` clean, nothing uncommitted, nothing untracked that should
  be tracked.
- `CLAUDE.md` accuracy re-confirmed (repo layout, hard constraints —
  should already be correct from tasks 016/018, this is a re-check, not
  expected to find anything new).
- Confirm the `git worktree` used in Parts D and F left no trace
  (`git worktree list` shows only the main tree).

## Part H — freeze report v2

Write `docs/freeze-report-v2.md` (don't overwrite the first one — it's
the historical record of the pre-APB-revert, pre-campaign state; this
one supersedes it going forward but both stay). Must stand alone, same
bar as the first report: a reader should be able to open only this file
and know exactly what "frozen" means at this commit, without needing any
other document open beside it. Include:

- The frozen commit hash and a link back to `87d31bf`/`9f5deab` as the
  lineage (first freeze → APB revert → this re-certification).
- Part A's exact-count table (the new floor).
- Part B's diff evidence (empty, pasted in).
- Part C's fresh-seed results.
- Part D's triple-cross-checked determinism result.
- Part E's exact lint-output match.
- **Part F's mutation results — this is the report's strongest claim,
  make it prominent**: which mutations were tried, which tests caught
  each one, confirmation nothing was left behind.
- The same "what this freeze does not cover" section as the first
  report (no timing/STA, no DRC/LVS, no firmware) — still true, still
  worth stating plainly rather than assuming the reader remembers it
  from the first report.

## Acceptance

- Parts A–G all pass with zero unexplained discrepancies.
- Part F's mutations are all caught, and the worktree is provably
  cleaned up.
- `docs/freeze-report-v2.md` exists, accurate, stands alone.
- **If anything in Parts A–F fails or finds something wrong**: stop,
  report in full, do not write Part H until resolved.

## Out of scope

- No RTL changes to the real tracked tree — Part F's mutations exist
  only in a throwaway worktree that gets deleted before this task ends.
- No timing/STA, no DRC/LVS, no firmware — same scope boundary as the
  first freeze.
