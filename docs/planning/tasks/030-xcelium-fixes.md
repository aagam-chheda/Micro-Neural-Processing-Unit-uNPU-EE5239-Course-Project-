# Task 030 — Xcelium cross-check findings: testbench portability fixes

## Goal

The first Xcelium 22.09-s003 run of all ten testbenches (server, 2026-09-23,
repo at `bd3a814`, RTL unchanged since `9f5deab`) found **testbench**
portability defects that Verilator's two-state, lenient semantics had
hidden. No RTL defect is indicated by anything below — but nothing here
is to be assumed; each item must be root-caused and shown, not asserted.

Standing campaign rules still apply: nothing fails silently, nothing
hardcoded, no check softened or count padded to get a clean result. If
any fix changes a testbench's total check count, say so and say why.

Xcelium results already in hand (Verilator floor from
`docs/freeze-report-v2.md` in brackets):

| TB | Xcelium result |
|---|---|
| pe | all pass |
| grid | 12,474 [12,474] pass |
| skew | 17,665 [17,665] pass |
| stall | `checks`=5,732 [5,732], `frozen_checks`=**252,225** [**250,245**] — passes but counts differ |
| buf | 17,975 [17,975] pass |
| **dma** | **753 FAILURES**, checks=19,009 [19,009, 0 failures] |
| csr | "ALL CHECKS PASSED" (count not captured) |
| **seq** | **compile error**, never ran |
| apb | "ALL CHECKS PASSED" (count not captured) |
| **top** | **compile error**, never ran |

## Item 1 — use-before-declaration compile errors (`seq`, `top`)

- `tb/unpu_seq_tb.sv:373` uses `job_start_count`, declared at line 479.
- `tb/unpu_top_tb.sv:134` uses `force_stall`, declared at line 314.

IEEE 1800 requires declaration before use; Xcelium enforces it
(`xmvlog: *E,UNDIDN`), Verilator does not. Move each declaration above its
first use. Then **grep every testbench for the same class** (any identifier
used textually before its declaration) — do not fix only the two Xcelium
happened to reach first; `top` failed at its first error and may hide
more behind it.

## Item 2 — `unpu_dma_tb` CRV loop indexes its SRAM model out of range

Symptom (server log, `xrun_out/dma.log`): every failure begins at
`crv_0000` — `actbuf active[..][..]=x expected <real value>` and
`mem C[..][..]=x expected <real value>`. All directed cases before the CRV
loop pass. The expected values are real, so the vector files loaded; the
DUT-side data is `x`.

Diagnosis to confirm (Planning's read of the source, not yet proven):
`tb/unpu_dma_tb.sv:145` `MEM_WORDS = 8192`, and the model SRAM decodes
`dma_addr[14:2]`. The CRV loop (line ~715) picks
`base_a = 32'h0001_0000 + i*1024 + …`; `preload_case` (line 222) then
writes `mem[(base_a >> 2) + r]` — word index ≥ 16,384, **outside**
`[0:8191]`. A 4-state simulator drops an out-of-range write; the DUT then
reads `mem[dma_addr[14:2]]` = `mem[0]`-region, never written → `x`.
Directed cases use bases ≤ 0x7000 and stay in range, which fits why only
the CRV portion fails. Verilator apparently wraps or otherwise tolerates
the out-of-range write, so write and read aliased consistently and the
test passed for a reason unrelated to what it claimed to test.

Required:
1. **Prove or refute the diagnosis** before fixing (e.g. print the index
   range at the first failing write, or run Verilator with array bounds
   checking / `--assert` if it supports it). Report what Verilator was
   actually doing with those out-of-range writes — this matters for how
   much weight the prior "0 failures" carries for this file's CRV portion.
2. Fix by making the per-case bases genuinely in range **by construction**
   (keep the per-case distinct-base property, the 64-case count and the
   jitter — do not shrink to a token subset; widen `MEM_WORDS` and the
   decode width, or re-band the bases, whichever keeps coverage intact).
3. **Make out-of-range access fail loudly, not silently**: every testbench
   that preloads or reads a model SRAM by computed index gets a bounds
   check (`if (idx >= MEM_WORDS) → error + $display`) so this class can
   never again pass or fail by accident of simulator semantics. Apply to
   `dma`, `seq`, `top` (each has its own `mem`), plus any other TB with
   an indexed model array you find.
4. Audit the same pattern in `unpu_seq_tb.sv` and `unpu_top_tb.sv`
   (different `MEM_WORDS`, different decode widths — check each base
   address band against its own decode, including the wraparound cases
   near `32'hFFFF_FFF0`, where address→index aliasing is *intended*; those
   must be made explicit and checked, not incidental).

## Item 3 — `unpu_stall_tb` `frozen_checks` differs between simulators

Xcelium 252,225 vs Verilator 250,245 (Δ = 1,980), with `checks` identical
(5,732) and 0 failures in both. A check count that depends on the
simulator means some control flow, random draw or event ordering differs.
Find out which and why. Do not simply update the floor to the new number.
Acceptable outcomes: (a) explained as an intended, deterministic
difference (state the mechanism and show it), or (b) a real
nondeterminism/race in the TB, which is then fixed so both simulators
report the same count. "Unexplained but passes" is not acceptable.

## Item 4 — a runner that prints the counts (`scripts/run_xrun.sh`)

The manual csh loop printed only `tail -n 6`, which dropped the counts for
`csr`/`apb`. Add `scripts/run_xrun.sh` (bash, `#!/usr/bin/env bash`; the
server login shell is csh but it exports the Cadence env, so a bash script
inherits it) that:
- takes an optional list of testbench names (default: all ten),
- compiles each with the full RTL file list and
  `xrun -sv -64bit -access +r -timescale 1ns/1ps -top unpu_<t>_tb -xmlibdirname xrun_out/<t> -l xrun_out/<t>.log`,
- **does not trust `xrun`'s exit code** (testbenches end in `$finish`, so
  exit is 0 even on failure) — decides pass/fail from the log: fail on any
  `*E,` compile error, any line matching `FAIL`, any
  `FAILURE(S)`, or absence of the testbench's own ALL-PASSED line,
- prints one summary row per testbench: name, PASS/FAIL, and the
  self-reported total count line(s),
- exits nonzero if any testbench failed,
- creates `xrun_out/` itself and works when invoked from the repo root.
Also add `xrun_out/` and `xcelium.d/`, `*.log`, `.simvision/` (whatever
Xcelium actually drops in the tree — check what the run created) to
`.gitignore`.

## Files

- `tb/unpu_seq_tb.sv`, `tb/unpu_top_tb.sv`, `tb/unpu_dma_tb.sv`,
  `tb/unpu_stall_tb.sv` (and any other TB the audits touch)
- `scripts/run_xrun.sh` (new), `.gitignore`
- **No RTL file.** If any evidence points at RTL, stop and report; do not
  patch it.

## Acceptance

- All ten testbenches compile with zero errors **and** zero new warnings
  under Verilator, and each reports the same or an explained total.
- Every changed check count is listed old → new with the reason; the
  Verilator regression is re-run in full (all ten, all green).
- Item 2's diagnosis is confirmed or replaced with the real cause, with
  evidence, and Verilator's actual prior behaviour on the out-of-range
  writes is stated.
- Bounds checks exist and are demonstrated to fire: temporarily force one
  out-of-range index in a scratch copy (not committed) and show the new
  check reports it.
- `scripts/run_xrun.sh` exists, is executable, and has been shell-checked
  (`bash -n`, and `shellcheck` if available). **Execution cannot run
  Xcelium** (local WSL, no license) — say so plainly; the Xcelium
  acceptance is done by the user on the server after pulling.
- Handoff note listing exactly what the user runs on the server:
  `git pull && bash scripts/run_xrun.sh`, and what a fully-green result
  must look like (per-TB counts to compare).
- **If any fix changes what a test actually checks (not just how it
  indexes), or Item 3 turns out to be a real race, stop and report before
  committing.**

## Out of scope

- No RTL changes. No changes to `model/golden.c`.
- No new adversarial coverage — this task only makes existing tests
  portable and honest. (Once Xcelium is green, the freeze report gets an
  addendum from Planning; Execution does not write it.)
