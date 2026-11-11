# Task 032 — Adapt two externally written testbenches to `unpu_top` and run them as an independent cross-check

## Goal

The user has two testbenches in `temp/` (untracked): `temp/tb1.txt` (252
lines, single-case smoke test) and `temp/tb2.txt` (986 lines, stress
testbench). Both were written for a **different implementation** of the
uNPU, not this repo's RTL. The user wants to modify them and use them to
verify this design as well.

**Provenance (from the user):** the files were written by a friend of the
user who is building the same course project with a different
microarchitecture, the **DiP (diagonal-input, permuted-weight) systolic
array**. The user asked them to share their testbenches so this design can
be cross-verified. Every header in the adapted files must credit that
source ("originally written by a peer for a DiP-array implementation of the
same project; adapted for this design") and record that the adaptation was
done in this repo. Do not name the person; the user can add that.

Value: they were written independently of our testbenches and of
`model/golden.c`. If they pass on our RTL (once adapted), that is a
genuinely independent second opinion on the frozen design. If they fail,
that is a finding, not a nuisance (see the stop rule below).

**RTL is frozen** (`git diff 9f5deab..HEAD -- rtl/` is empty and must stay
empty). This task adds testbenches only.

Standing campaign rules apply: nothing fails silently, nothing hardcoded,
seeds printed, no check softened or dropped to get green, no threshold
narrowed.

## What the files expect vs. what this repo has

Read both files in full first. Known mismatches, from Planning's read of
them (verify each against the RTL; do not trust this table over the source):

| Topic | tb1 / tb2 assume | This repo |
|---|---|---|
| Top parameters | `unpu_top #(TIMEOUT_CYCLES, ADDR_WIDTH, DATA_WIDTH, N, ACT_W, WGT_W, PROD_W, PSUM_W=18)` | `unpu_top` has **no parameters** |
| Top ports | tb1 also drives `dma_rvalid` | `unpu_top` has no `dma_rvalid`; ports are `clk, rst_n, paddr, pwdata, pwrite, psel, penable, prdata, pready, dma_addr, dma_wdata, dma_rdata, dma_wstrb, dma_valid, dma_ready` |
| Registers | `CTRL 0x00, STATUS 0x04, DMA_SRC 0x08, DMA_DST 0x0C, MATRIX 0x10` | eight registers: `src_a, src_b, dest_c, dim_m, dim_n, dim_k, npu_ctrl, npu_status` (`rtl/unpu_csr.sv`, `SEL_*`; offset layout is Planning's provisional proposal, take it from the RTL) |
| Job shape | one `src` region holds 4 weight-row words then 4 activation-row words; `rows`/`cols` in one `MATRIX` word | separate `src_a` / `src_b` / `dest_c`, and 3-bit `dim_m/n/k`; take the SRAM layout and the meaning of M/N/K from `rtl/unpu_dma.sv`, `rtl/unpu_seq.sv` and `model/golden.c` |
| Arithmetic | unsigned 8-bit operands, 18-bit psum, `C = A @ W` | INT8 with a signed/unsigned mode (`mode_unsigned` from `npu_ctrl`), **32-bit** accumulator |
| Status / error | `STATUS[0]=done, [1]=busy, [2]=error`; error on `rows==0`/`cols==0` | `npu_status` layout and `seq_error_code` per RTL |
| Out-of-range APB read | returns `32'hDEAD_BEEF` | whatever `unpu_apb`/`unpu_csr` actually does; test the real, documented behaviour |
| Standalone DMA watchdog test (tb2 test 10) | instantiates `unpu_dma` with `start/soft_reset/src_addr/cfg_rows/cu_*` ports | `unpu_dma` has a different interface (`job_*`); this **will not elaborate** |
| Soft-reset | `CTRL[1]` | per `npu_ctrl` layout in RTL |
| Unit under test | `unpu_cu`, `systolic_array_dip_4x4`, DiP dataflow | different microarchitecture (weight-stationary + skew/de-skew); the tests only observe APB and the SRAM bus, so timing is not embedded, **but read every fixed delay and poll bound** |

## Deliverables

Two new testbenches, modules named to match the file (repo convention: one
module per file):

- `tb/unpu_ext1_tb.sv` (from tb1)
- `tb/unpu_ext2_tb.sv` (from tb2); `behavioral_sram` moves to its own file
  `tb/unpu_ext_sram.sv`, or is folded in as a nested/local model, whichever
  keeps "one module per file". Say which.

Each file's header must state: source file, that it was written externally,
what was changed, and what was dropped and why. **Leave `temp/` untouched**
(it is the user's copy). Do not commit `temp/`. The originals stay out of the
repo; the adapted files are committed only once the user has said the
friend is fine with that (the user relays this; do not assume it).

## Required adaptations

1. **Interface / registers / job shape** as in the table. Prefer the
   existing helpers and idioms in `tb/unpu_top_tb.sv` (APB driver, SRAM
   model, address handling) rather than inventing new ones.
2. **Keep the tb's own golden model.** Both files compute their expected
   results inside the testbench. That independence is the point: do **not**
   swap in `model/golden.c` vectors. Extend the in-TB golden to our
   semantics (32-bit accumulate; signed and unsigned modes) and compute it
   from the operands the tb actually wrote to SRAM, not from constants.
   Run every matrix test in **both** modes where the mode is selectable.
3. **Signed corner cases** that the originals cannot have (they are
   unsigned-only): add `0x80` (−128) and `0x7F` × `0x80`/`0xFF` corners to
   the extreme-value tests. State what you added.
4. **SRAM model honesty (lesson of task 030).** tb2's model masks any
   32-bit address into a 64 KB window; tb2's random test sweeps the whole
   32-bit space. That is exactly the aliasing pattern that hid a coverage
   gap in our own testbenches. Do **not** carry it over silently:
   - out-of-window access must be a loud, counted error, not a mask;
   - keep the random-address sweep, but choose bases that are distinct and
     in range **by construction**, and check that the DUT's *address*
     (not only the data) is what was expected for at least the first and
     last beat of each stream;
   - keep the back-pressure modes (always-ready, random, periodic).
5. **Portable randomness.** `$urandom` / `$urandom_range` are
   simulator-defined; the same seed gives different streams on Verilator
   and Xcelium (task 030 item 3). Replace with the xorshift32 helper
   pattern already used in `tb/unpu_stall_tb.sv`, print the seed, and make
   check counts identical across simulators.
6. **Declaration order.** tb1 uses `dma_rdata_r` (line 102) before its
   declaration (line 112). Fix it and audit both files for the same class
   (task 030 item 1).
7. **Do not drop a check silently.** Every test in the originals ends up
   either (a) adapted, (b) replaced by an equivalent for this design, or
   (c) dropped with a one-line written reason in the file header and in
   your report. Expected (c) candidates: the standalone `unpu_dma`
   watchdog, `DEAD_BEEF` if our behaviour differs (then test ours), and the
   `rows x cols` factorisation test (replace with the legal M/N/K sweep for
   our DMA, not a token subset).
8. Each testbench ends with an unambiguous `ALL TESTS PASSED` / `FAILED`
   line and a total check count, in the same style `scripts/run_xrun.sh`
   already parses, so it can run under that script.
9. Runner: let `scripts/run_xrun.sh` accept `ext1` and `ext2` by name. **Do
   not change its default list** (the frozen ten) — the freeze report
   quotes "ten testbenches"; the ext pair is additional and reported
   separately.

## Verification you must do

1. Compile clean under Verilator (zero warnings on the new files) and run
   both on the unmutated RTL. Report pass/check counts.
2. **Mutation sanity, so the new tbs are shown to have teeth.** In a
   throwaway worktree (task 031 method: control before and after,
   `git worktree remove --force` at the end, nothing committed), apply at
   least these from task 031 and record which ext testbench catches each,
   with counts and the first FAIL line: #1 (`seq` `m_lat+6→+5`),
   #2 (`pe` `mode_unsigned` polarity), #3 (`dma` stride `m*16→m*15`), #4
   (address-alias on a high bit). A survivor is a stop-and-report finding.
3. If an ext testbench fails on clean RTL: first decide, with evidence,
   whether it is an adaptation error in the new tb or a real RTL defect.
   **Do not touch RTL.** Do not weaken the check. Stop and report both
   readings; the user and Planning decide.
4. Full existing Verilator regression (all ten) still green — the new files
   must not disturb it.
5. You cannot run Xcelium. Hand the user the exact server command
   (`git pull --ff-only && bash scripts/run_xrun.sh ext1 ext2`, csh-safe
   invocation as in the earlier handoff) and the expected counts to compare.

## Out of scope

- No RTL change. No change to the ten existing testbenches or their
  floors. No edit to `model/golden.c`. No freeze-report change — if the ext
  pair passes, Planning writes Addendum 2.
- No new adversarial coverage beyond what the originals contain plus the
  signed corners in item 3.
