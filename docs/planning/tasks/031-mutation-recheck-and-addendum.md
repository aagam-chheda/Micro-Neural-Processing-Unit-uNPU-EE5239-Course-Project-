# Task 031 — Re-run the mutation spot-check against the post-030 testbenches; freeze-report addendum

## Goal

Two things.

**A. Close a gap in freeze v2's central claim.** Task 029 Part F proved the
test suite catches planted RTL bugs — but against the testbenches as they
were at `bd3a814`. Task 030 (`aba94f7`, `7151a60`) then materially edited
`unpu_dma_tb`, `unpu_seq_tb`, `unpu_top_tb` and `unpu_stall_tb` (widened
model SRAMs, bounds checks, `wrap_expected` exemption windows, a new
random-number source). Nothing since has shown those edits didn't quietly
weaken a check. Re-prove the suite has teeth **at current HEAD**, and add
mutations aimed specifically at what task 030 changed.

**B. Record the Xcelium result and task 030 in the freeze report.** The
user ran `bash scripts/run_xrun.sh` on the server (Xcelium 22.09-s003,
repo at `649bab6` or later, RTL identical to `9f5deab`): **all ten
testbenches PASS**, with counts identical to Verilator's for every
testbench, including `stall` `frozen_checks=250560`. This is now the
first cross-simulator result in the project and belongs in the record.

Standing campaign rules apply: nothing fails silently, nothing hardcoded,
no threshold or check softened, no mutation chosen because it is known to
be easy to catch. **A mutation that survives is a stop-and-report finding,
not something to explain away.**

## Part A — mutation re-check

Method identical to task 029 Part F:

1. `git worktree add ../unpu-mutation-check HEAD` (outside the tracked
   tree; never inside `rtl/`/`tb/` of the real working directory).
2. **Control first**: in the unmutated worktree, run the relevant
   testbenches and confirm each passes with the expected counts. A
   mutation result is meaningless without a same-tree control.
3. Apply **one mutation at a time** to RTL in the worktree only; run
   the testbenches that should catch it (run **all ten** for at least
   the first mutation to see whether anything catches it *unexpectedly
   early or late* — note which testbench fails first and how many
   failures each reports); record; **revert** the mutation before the
   next (`git checkout -- rtl/` in the worktree) and re-run a control.
4. Record for every mutation: the exact diff applied (paste it), which
   testbench(es) failed, failure counts, the first FAIL line, and whether
   that first failure points near the mutation.

Mutations — the first three repeat task 029's (now against the edited
testbenches); the last four are new and target the task 030 edits:

1. `unpu_seq.sv`: `COMPUTE` stop `cycle == m_lat + 6` → `+ 5`.
2. `unpu_pe.sv`: invert `mode_unsigned` polarity in the product logic.
3. `unpu_dma.sv`: writeback row stride `m*16` → `m*15`.
4. **Address-alias bug (the exact gap task 030 item 2 says the old
   testbenches could not see):** make `unpu_dma.sv` (or the top-level
   address path — whichever actually forms the address) drop or force a
   high address bit, e.g. bit 15 or 16, so distinct-base cases alias to
   the same SRAM location. Before task 030 this class was invisible to
   the CRV portions of `dma`/`seq`/`top` because their model SRAMs
   wrapped the same way. Expect the widened models + distinct per-case
   bases to catch it. **If it survives, that is the most important
   finding of this task.** Try at least two different bit positions.
5. **`wrap_expected` exemption hole:** the window monitor exempts beats
   while `wrap_expected` is set. Mutate the DMA address increment so it
   goes wrong *in an ordinary, non-wraparound op* (e.g. a stuck-at on
   an address bit above the decode width for non-wrap ops) and confirm
   the monitor / data checks still catch it — i.e. that the exemption
   is not wider than the intended wraparound windows.
6. **Freeze bug:** in the datapath, remove the `array_en` hold from one
   skew or de-skew FIFO stage (or one PE's psum register — pick one, say
   which). Expect `unpu_stall_tb`'s freeze checks to catch it. Since
   task 030 replaced that testbench's random source, this proves the new
   stimulus still exercises stalls that reach that register.
7. **Bounds-check mutation:** temporarily revert only the model-SRAM
   width in one of `dma`/`seq`/`top` (scratch, worktree only) and
   confirm the new `mem bounds`/`mem window` failures fire again. (Task
   030 reported 1,259 + 686; confirm the same numbers reproduce, or
   explain any difference.)

If any of 1–7 survives (no testbench fails), stop, report exactly which
and why, do not proceed to Part B.

Cleanup: `git worktree remove --force ../unpu-mutation-check`; confirm
`git worktree list` shows only the main tree and `git status` in the
main tree is clean apart from Part B's edit. **Nothing from Part A is
ever committed.**

## Part B — freeze-report addendum

Append to `docs/freeze-report-v2.md` (do **not** rewrite existing text —
it is the certified record of that pass; add a clearly-marked
"Addendum 1" section at the end and one line at the top pointing to it):

- **Xcelium cross-check result**: tool/version (Xcelium 22.09-s003), host
  class (institute server; no hostname needed), commit run against, the
  ten PASS rows with exact counts as printed by `run_xrun.sh` (use the
  table below), and the two informational `*W` warnings per run — say
  what they are (they are the `DSEMEL`/`DSEM2009` IEEE-1800-2009
  semantics notices; confirm from `xrun_out/*.log` if available, else
  state that you inferred it from the earlier manual run's log text).
- **What task 030 changed and why**, in a few lines each: the
  use-before-declaration fixes; the out-of-range-index finding (state
  plainly that Verilator wrapped the index, so the old `dma`/`seq`/`top`
  CRV passes were genuine but did not exercise address separation, and
  that this is now covered); the `$random(seed)` → xorshift32 change.
- **Floor revision**: `unpu_stall` `frozen_checks` 250,245 → **250,560**,
  reason (stimulus source changed, not what is checked), and the
  arithmetic (250,560 = 45 × 5,568).
- **Part A's results** as a table: mutation, testbench(es) that caught it,
  failure counts, first-failure location, control status, worktree
  cleaned. Make this prominent — it re-establishes the "the suite has
  teeth" claim at the current commit.
- Restate what the freeze still does **not** cover (timing/STA, DRC/LVS,
  firmware).
- Add: RTL identity re-verified — `git diff 9f5deab..HEAD -- rtl/` empty.

Xcelium counts to record (as reported by the user's server run):

| TB | Xcelium count |
|---|---|
| pe | 65,536 + 65,536 sweeps; 256; 255 cycle-checks; 11,702 cycle-checks / 35,106 signal-checks |
| grid | 12,474 |
| skew | 17,665 |
| stall | checks=5,732, frozen_checks=250,560 |
| buf | 17,975 |
| dma | 19,009 |
| csr | 20,041 |
| seq | 19,840 |
| apb | 32,545 |
| top | 343,341 |

## Acceptance

- Control passes for every mutation batch; every mutation 1–7 is caught
  by at least one testbench; exact diff, failing testbench(es), failure
  counts and first-FAIL line recorded for each.
- Mutation 4 (address alias) is caught — or, if not, reported in full.
- Worktree removed; `git worktree list` and `git status` evidence pasted.
- Addendum written as specified; existing report text untouched
  (`git diff` of the file shows additions only).
- Full Verilator regression green at the final commit (all ten).
- **You cannot run Xcelium.** The addendum's Xcelium section is from the
  user's server run, quoted above — say so in the text. Do not claim
  you observed it.

## Out of scope

- No RTL changes committed; no testbench changes (unless a mutation
  survives, in which case stop and report first).
- No new adversarial coverage beyond the seven mutations.
