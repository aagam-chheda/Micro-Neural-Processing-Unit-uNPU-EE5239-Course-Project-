# Implementation plan — through RTL freeze

Live status document. Update step status here as work completes. Task prompts
are written one at a time, only when asked, as `docs/planning/tasks/NNN-*.md`.

Scope: this plan is organized around one goal, RTL freeze. Real work that
isn't RTL work — PDK access, DRC/LVS tooling, IC Compiler setup, MNIST
network shape, arbiter ownership — is tracked but kept out of the critical
path. See "Back-end prerequisites" below.

RTL is SystemVerilog (`.sv`), synthesisable subset only, per CLAUDE.md.

---

## Questions going into the PM meeting

Only the items that would change a module we have to write. Paste answers
back in and the plan gets updated accordingly.

1. **Q7 — native or AHB memory interface for the DMA port?** Port list as
   written is signal-for-signal PicoRV32's native interface; PM previously
   said AHB. Our proposal: bridge lives on the arbiter side, not in our macro.
   **Answer:**

2. **Are the two extra CSRs at 0x14/0x18 approved?** We asked how many we
   needed and answered two; never got a yes. If no, the design changes: one
   pointer register instead of two, K derived from a fixed memory layout
   instead of read from hardware.
   **Answer:**

3. **Scan pins** (`scan_en`, `scan_in`, `scan_out`) — not in the current port
   list, not in the brief, needed for tester access. Scan chains get inserted
   into RTL, not layout, so this has to close before freeze, not before
   floorplan.
   **Answer:**

4. **Is the `unpu_top` port list actually frozen, or still negotiable?**
   Everything above assumes it's frozen and we design around it (bridges,
   fixed layouts, etc.) rather than asking for new pins. If it's still
   movable, some of those workarounds are unnecessary work.
   **Answer:**

---

## Steps

**1. PE module + unit test**
Files: `rtl/unpu_pe.sv`, `tb/unpu_pe_tb.sv`
Acceptance: 20 directed vectors (max positive, max negative, zero weight,
weight-load-while-computing, signed/unsigned mode saturation pair) pass in sim.
Dependencies: none. Blocked: no.

**2. C golden model for matmul**
Files: `model/*.c`
Oracle mechanism: file-based vectors, not DPI-C. The golden model is a
standalone C program invoked ahead of simulation to emit hex input/expected-
output vector files; SV testbenches read them with `$readmemh`.
Acceptance: model output matches hand-computed results for identity and
all-ones 4×4 signed INT8 cases; emitted vector files are the oracle for every
sim step below.
Dependencies: none. Blocked: no.

**3. Genus bring-up on a trivial design**
Files: `syn/*`
Acceptance: `unpu_pe.sv` synthesizes cleanly through Genus to a gate-level
netlist with a timing report, using real SCL 180 nm libs.
Dependencies: step 1. Blocked: **yes — back-end prerequisite, PDK access.**
Not on the RTL-freeze critical path (see below).

**4. Grid module + identity test (W2 gate)**
Files: `rtl/unpu_grid.sv`, `tb/unpu_grid_tb.sv`
Acceptance: the testbench contains **no skew module**. It injects hand-skewed
activations directly — `entry(A[m][k])` driven at the west edge of row `k` at
cycle `m+k`, per the timing contract — with identity weights preloaded. Grid
outputs must match the source activations at the correct cycle latency.
Dependencies: step 1. Blocked: no.

**5. Trial hardening pass on the grid (throwaway, parallel track)**
Files: `pnr/*` (trial run only)
Purpose: learn the real critical-path/congestion story (512 vertical psum
wires) early. This step has **its own gate and is explicitly decoupled from
RTL freeze** — see "Freeze gate" below. Keep scripts and numbers; discard the
netlist/DEF.
Acceptance: a real critical-path number and a congestion read-out come back
from IC Compiler on `unpu_grid.sv`.
Dependencies: steps 3, 4. Blocked: **yes — back-end prerequisite, PDK + IC
Compiler access.** Not on the RTL-freeze critical path.

**6. Skew / de-skew banks**
Files: `rtl/unpu_skew.sv`, `rtl/unpu_deskew.sv`, `tb/unpu_skew_tb.sv`
Acceptance: raw (un-skewed) matrix input produces correctly aligned output
matching the timing contract exactly (`m+k+j` entry, `m+j+4` exit, `m+7` row
valid) for a non-identity matrix, checked against the golden model's vector
files.
Dependencies: steps 2, 4. Blocked: no.

**7. Stall rule — global `array_en` freeze**
Files: `tb/unpu_stall_tb.sv` against `rtl/unpu_grid.sv` + `rtl/unpu_skew.sv` +
`rtl/unpu_deskew.sv`; RTL changes only if the freeze wiring turns out missing.
Acceptance: drop `array_en` mid-stream, hold it low for a randomised number of
cycles, confirm skew bank + all 16 PEs + de-skew bank freeze on the same edge
and results are bit-identical to the un-stalled run.
Dependencies: step 6. Blocked: no.

**8. Sequencer FSM**
Files: `rtl/unpu_seq.sv`, `tb/unpu_seq_tb.sv`
Acceptance: matmul passes for M = 1, 4, and a non-multiple-of-4 M, total
cycle count equals `M+7` each time, results match the golden model's vector
files.
Dependencies: steps 6, 7. Blocked: no.

**9. Activation / weight buffers**
Files: `rtl/unpu_actbuf.sv`, `rtl/unpu_wbuf.sv`, `tb/unpu_buf_tb.sv`
Acceptance: double-buffered weight swap (shift-down, reversed row order)
completes in the 4 hidden cycles without stalling compute on the active tile.
Dependencies: step 8. Blocked: no.

**10. DMA master**
Files: `rtl/unpu_dma.sv`, `tb/unpu_dma_tb.sv`
Acceptance: 4-state FSM moves tensors between shared SRAM and the
activation/weight buffers with the arbiter, matching the native PicoRV32
memory-interface convention (`wstrb==0`→read, `rdata` valid same cycle as
`valid & ready`).
Dependencies: step 9. Blocked: **yes — RTL-blocking, Q7 (question 1 above).**

**11. Randomised back-pressure test**
Files: extends `tb/unpu_dma_tb.sv`
Acceptance: with randomised arbiter grant latency/back-pressure injected on
the DMA side, results still match the golden model and the DMA FSM never
hangs or corrupts in-flight state.
Dependencies: step 10. Blocked: **yes — same as step 10 (question 1).**

**12. CSR / register map**
Files: `rtl/unpu_csr.sv`, `tb/unpu_csr_tb.sv`
Two variants pending the 0x14/0x18 approval (question 2): **if approved** —
two pointer registers at 0x14/0x18, K read from hardware. **If not** — one
pointer register, K derived from a fixed memory layout, 0x14/0x18 stay
reserved/unimplemented.
Acceptance: directed register test covers all offsets for whichever variant
is confirmed; SIGNED mode bit round-trips; reserved range reads defined/inert
values.
Dependencies: step 1. Blocked: **yes — RTL-blocking, question 2.**

**13. APB slave FSM**
Files: `rtl/unpu_apb.sv`, `tb/unpu_apb_tb.sv`
Acceptance: sim drives APB at variable, very slow pacing (mimicking the SPI
backdoor) and confirms correct read/write semantics with no hang, against
whichever CSR map variant step 12 lands on.
Dependencies: step 12. Blocked: yes, transitively — via 12.

**14. Top-level integration (functional)**
Files: `rtl/unpu_top.sv`, `tb/unpu_top_tb.sv`
Acceptance: full SoC-level directed test (CPU writes pointers + start bit,
DMA fetches, grid computes, results written back, DONE set) matches the
golden model's vector files end to end, using the frozen port list.
Dependencies: steps 1, 4, 6, 7, 8, 9, 10, 12, 13. Blocked: **yes,
transitively — via 10 and 12.**

**15. Scan chain insertion**
Files: `rtl/unpu_top.sv` (add `scan_en`/`scan_in`/`scan_out` ports), scan mux
wiring across the sequential modules it stitches together.
This is an RTL concern, not a back-end one — the chain gets built into the
RTL, and it has to be settled before freeze, not before floorplan.
Acceptance: scan-mode sim shifts a known pattern through the full chain and
reads it back bit-exact, with functional mode unaffected when `scan_en=0`.
Dependencies: step 14 (needs the final flop list). Blocked: **yes —
RTL-blocking, questions 3 and 4.** Whether there are dedicated scan pins and
whether the port list is truly frozen both change how this is built.

**16. RTL freeze regression / sign-off**
Files: none new — full regression run across all directed + golden-model
vectors at SoC level, plus the W4 gate checklist.
Freeze gate is **functional correctness only**: full regression (directed +
golden-model, including scan-mode sim) passes clean at top level. This step
does **not** depend on step 5 — see "Freeze gate" below.
Dependencies: steps 14, 15. Blocked: yes, transitively — via 14 and 15.

---

## Freeze gate — decoupled from trial hardening

RTL freeze (step 16) no longer depends on step 5's P&R trial. Freeze is
functional: all directed and golden-model tests passing at top level,
including scan-mode sim. Step 5 stays a parallel track with its own gate (a
real critical-path/congestion number on the grid), useful for catching a
50 MHz problem early, but it does not gate freeze.

**If the PDK is late:** we freeze on function and accept that timing
confirmation (step 5, and later full-chip STA) arrives after freeze, not
before it. If step 5 later reveals 50 MHz doesn't close, that reopens RTL —
an acceptable risk, not a blocked freeze.

---

## Status

1. **Done.** `rtl/unpu_pe.sv` + `tb/unpu_pe_tb.sv`, 20/20 vectors pass.
   Simulated with Icarus Verilog, not Xcelium (unavailable in this
   environment) — noted in both file headers. Verified independently by
   re-running the sim.
2. **Done.** `model/golden.c`, file-based vector oracle
   (`<name>_a/w/c.hex` + `_meta.txt` under `model/vectors/`, not checked in).
   Both required cases (`identity`, `all_ones`) self-check clean before
   writing. Verified independently.
4. **Done. End-W2 gate cleared.** `rtl/unpu_grid.sv` + `tb/unpu_grid_tb.sv`,
   all 16 `C[m][j]` values check out at the exact contract cycles (`m+j+4`).
   Simulated with Icarus Verilog. One bug found and fixed in-task (off-by-one
   in the testbench's output-valid check, not the RTL). Portability note:
   Icarus rejects a variable `[r][c]` double-index as an lvalue into a
   3-level packed array — identity-weight preload is unrolled explicitly in
   the testbench rather than looped; worth rechecking if this ever moves to
   Xcelium, since that restriction may not apply there.
6. **Done.** `docs/planning/tasks/004-skew-deskew.md`, committed `b141d41`.
   `model/golden.c` extended with `cross_terms` case, matches hand-computed
   table exactly. `rtl/unpu_skew.sv` + `rtl/unpu_deskew.sv` (explicit
   unrolled register chains, not generate loops — depth-0 paths on row 0 /
   col 3 are plain wires, matching the known trap). `tb/unpu_skew_tb.sv`
   chains skew → grid → de-skew; all 16 `C[m][j]` values match at exactly
   cycle `m+7`. Regression: `unpu_pe_tb` and `unpu_grid_tb` still pass
   (20/20, 64/64). `unpu_pe.sv`/`unpu_grid.sv` confirmed untouched.
   Verified independently (commit stat + file diff).
   Two notes from Execution, neither blocking: (1) fixed two pre-existing
   MinGW portability breaks in `golden.c` unrelated to this task (`mode_t`
   collision with `sys/stat.h`, two-arg `mkdir`) — needed for the "compiles
   clean" acceptance criterion; (2) task doc's "nine files total" (Part A
   acceptance) is now stale — `random_signed`/`random_unsigned` cases from
   task 002 mean it's actually 15 files across 5 cases. Cosmetic, no
   action needed.
3, 5, 8–16: not started.

## Blocks RTL freeze

Only items whose answer changes a module we have to write. All four are in
"Questions going into the PM meeting" above.

- Question 1 (Q7, native vs AHB) — blocks steps 10, 11, and transitively 14, 16.
- Question 2 (0x14/0x18 approval) — blocks step 12, and transitively 13, 14, 16.
- Question 3 (scan pins) — blocks step 15, and transitively 16.
- Question 4 (port list frozen or negotiable) — blocks step 15, and
  transitively 16; also retroactively affects how steps 10 and 12 should be
  built if the answer is "negotiable."

**Executable now, in order: 1, 2, 4, 6, 7, 8, 9.**

## Back-end prerequisites

Real work, not RTL work, chased by email — does not gate freeze.

- SCL 180 nm PDK access (lib files, tech/LEF, corner definitions) — needed
  for steps 3 and 5.
- IC Compiler access/setup confirmation — needed for step 5.
- DRC/LVS/formal-equivalence/IR-drop tool decision — needed post-freeze, not
  covered by this plan.
- MNIST network shape (784→64 doesn't fit 32 KB SRAM) — needed to fill in
  SRAM memory layout; not needed to write or freeze the RTL itself.
- CNN vs MLP for the signoff test — same, needed for the firmware/test
  content, not the RTL.
- Who owns the arbiter RTL, us or the SoC team — affects co-design of
  back-pressure behavior (step 11) but doesn't block writing our side.
