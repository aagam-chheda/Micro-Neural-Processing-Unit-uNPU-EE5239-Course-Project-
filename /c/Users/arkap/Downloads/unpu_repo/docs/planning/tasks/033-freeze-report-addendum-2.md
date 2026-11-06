# Task 033 — Freeze-report Addendum 2: peer-testbench cross-check (task 032)

## Goal

Record task 032 in the certified record. `docs/freeze-report-v2.md` already
carries Addendum 1 (Xcelium result, task 030, mutation re-check). Add
**Addendum 2** for the independent cross-check with the adapted peer
testbenches `ext1` / `ext2`. Documentation only.

Planning cannot edit `docs/freeze-report-v2.md` (role rule), so this task
goes to Execution, same as task 031 Part B.

Standing rules apply: nothing overstated, nothing softened, numbers come
from the runs, not from memory. Where a number below is Planning's copy of
what Execution or the user reported, re-derive it or quote its source; if
it does not reproduce, stop and report.

## Constraints on the edit

- **Append-only.** Do not rewrite or reflow any existing text; `git diff`
  of the file must show additions only (0 lines removed), same as
  Addendum 1.
- Add **one line** at the top pointing at Addendum 2, directly below the
  existing Addendum 1 pointer (that pointer line itself stays unchanged).
- Heading style follows Addendum 1: `# Addendum 2 — ...` and sections
  `A2.1`, `A2.2`, ...
- No RTL, testbench, script or model change. `git diff 9f5deab..HEAD --
  rtl/` stays empty.

## Content

**A2.1 What was run and where it came from.** `tb/unpu_ext1_tb.sv` and
`tb/unpu_ext2_tb.sv` (commit `f374e60`), adapted in task 032 from two
testbenches written by a peer for a DiP-array (diagonal-input,
permuted-weight) implementation of the same course project. Do not name the
person. State that they were written independently of this repo's
testbenches and of `model/golden.c`, that the peer's in-testbench golden
model was kept (extended to 32-bit accumulate, signed and unsigned), and
that this is what makes them an independent check. State that the peer
agreed to the adapted versions being committed.

**A2.2 Per-test disposition.** A table of every original test →
ADAPTED / REPLACED / DROPPED, with the one-line reason, taken from the
header of `tb/unpu_ext2_tb.sv` (verify the table against the file). Include
the signed corner cases and the per-beat DMA address-sequence check that
were added, the protocol checker and watchdog that were kept, and the
`$urandom` → xorshift32 replacement.

**A2.3 Results.** Two rows, Verilator and Xcelium:

| | ext1 | ext2 |
|---|---|---|
| Verilator (clean RTL) | 34 checks | 15,231 checks, rounds: 325 run, 325 passed |
| Xcelium 22.09-s003 (institute server, `f374e60`) | 34 checks, PASS | 15,231 checks, PASS, rounds: 325 run, 325 passed |

Seeds printed by `ext2` (`SEED_MAIN=0x5EEDE200`, `SEED_SRAM=0x5EEDE201`),
and the six randomized-init Verilator seeds that gave identical counts (1,
7, 12345, 99, 4242, 31337). State plainly that the Xcelium row is quoted
from the user's server run and that you did not observe it. State the two
informational `*W` warnings per run as in Addendum 1.
Also record the TB bug found by randomized init (monitor firing on
power-up state before the first reset edge; fixed by gating with `rst_n`).

**A2.4 Mutation table.** Mutations from task 031 #1–#4 against the ext
testbenches, run in task 032 in a throwaway worktree with clean controls
before and after each. Columns: mutation, ext1 result, ext2 result,
failure counts, first FAIL line. From task 032's report:

| Mutation | ext1 | ext2 |
|---|---|---|
| #1 `seq` `m_lat+6→+5` | caught (8) | caught (2,032) |
| #2 `pe` `mode_unsigned` polarity | **not caught** (34 checks pass) | caught (6,636) |
| #3 `dma` stride `m*16→m*15` | caught (26) | caught (5,152) |
| #4a address bit 15 | not caught | caught (3,872) |
| #4b address bit 16 | not caught | caught (3,712) |
| #4c address bit 20 | not caught | caught (3,632) |

Re-verify these by re-running them (same method, throwaway worktree,
control before and after, nothing committed, `git worktree remove --force`
at the end, `git worktree list` pasted) rather than copying them. If any
number differs, report the difference; do not adjust the table to match.
Explain **why ext1 alone misses #2 and #4** (its 1..16 data is identical
signed and unsigned; its 4 KiB window never sets the high address bits):
this is a property of the peer's test as written, not a defect; `ext2`
catches every mutation, so no mutation survived the pair.

**A2.5 Observations about the design (not defects, RTL unchanged).**
1. `npu_status[4:2]` (error_code) keeps its last value while ERROR=0. After
   an illegal-config op, later legal ops read status `0x5` (DONE + code 1)
   until reset. It is by the documented "meaningful only while error=1"
   (`unpu_seq`, passed through ungated by `unpu_csr`). Firmware must test
   `npu_status[1:0]` for done/error, and read the code only when ERROR=1.
2. There is no hardware watchdog: a never-ready SRAM hangs the block until
   `rst_n`. No requirement in the record asks for one. If wanted, it belongs
   in the SoC arbiter or as a firmware-side software timeout.
3. `ext2`'s random sweep covers a 2 MiB window and cannot reach address
   bits above it. Full-width address exactness under wraparound remains
   carried by `unpu_dma_tb` and, for data, `unpu_top_tb` (see A1.4 known
   limit).

**A2.6 RTL identity.** `git diff 9f5deab..HEAD -- rtl/` empty, output
pasted.

**A2.7 What this freeze still does not cover.** Restate: timing/STA,
DRC/LVS, firmware. Also that `ext1` / `ext2` are additional to, not part of,
the frozen ten; `scripts/run_xrun.sh` default list is unchanged.

## Acceptance

- Addendum 2 written as specified; `git diff` shows additions only;
  existing text untouched; top pointer line added.
- Mutation results re-derived (or discrepancies reported); worktree
  removed, `git worktree list` and `git status` evidence pasted.
- Full Verilator regression of the frozen ten still green at the final
  commit (counts as in Addendum 1), plus `ext1`/`ext2` green.
- You cannot run Xcelium. Say so in the text; the Xcelium row is from the
  user's server run.
- Commit and push (`git pull --rebase origin main` first if rejected).
  Commit message ends with `Co-Authored-By: Claude Sonnet 5
  <noreply@anthropic.com>`.

## Out of scope

- No RTL change, no testbench change, no runner change, no new mutations
  beyond those listed.
