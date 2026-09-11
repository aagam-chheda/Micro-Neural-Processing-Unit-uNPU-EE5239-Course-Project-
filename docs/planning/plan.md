# Implementation plan — through RTL freeze

Live status document. Update step status here as work completes. Task prompts
are written one at a time, only when asked, as `docs/planning/tasks/NNN-*.md`.

Scope: this plan is organized around one goal, RTL freeze. Real work that
isn't RTL work — PDK access, DRC/LVS tooling, IC Compiler setup, MNIST
network shape, arbiter ownership — is tracked but kept out of the critical
path. See "Back-end prerequisites" below.

RTL is SystemVerilog (`.sv`), synthesisable subset only, per CLAUDE.md.

---

## Questions going into the PM meeting — ANSWERED

All four resolved. Full detail in `docs/session-handoff.md` §4/§5/§6/§12.
Kept here for the record; the plan below is updated accordingly.

1. **Q7 — native or AHB memory interface for the DMA port?**
   **Answer: native, for both the DMA↔SRAM port and the CPU↔NPU register
   port.** APB is out entirely — this was a bigger change than "which bus,"
   it removes APB from the design altogether.

2. **Are the two extra CSRs at 0x14/0x18 approved?**
   **Answer: superseded.** Not "two extras on top of five" — PM specified a
   full 8-register replacement: `src_A`, `src_B`, `dest_C`, `dim_M`, `dim_N`,
   `dim_K`, `npu_ctrl`, `npu_status`. Window extends past 0x18, confirmed
   fine. Offset assignment (0x00–0x1C proposed) is Planning's layout, not
   yet PM-confirmed — see `docs/planning/unpu-architecture.html` §3.

3. **Scan pins** (`scan_en`, `scan_in`, `scan_out`)?
   **Answer: none.** No scan chain in scope for this project. Step 15
   removed from the plan.

4. **Is the `unpu_top` port list actually frozen, or still negotiable?**
   **Answer: negotiable.** Supersedes CLAUDE.md's current "frozen" hard
   constraint — flagged for Execution to fix (outside Planning's write
   scope).

**Also received:** the matmul shape is A[M×K] × B[K×N] = C[M×N], all of A/B
signed int8, C is int32 with no hardware requantization, and M/N/K are each
≤ 4 at runtime (never greater — no tiling required).

**Holding point:** the user is waiting on a final project document from the
PM that may supersede some of the above. No new task prompts until it
arrives — this plan update is closing out already-pending bookkeeping, not
opening new design work.

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
**Not yet re-scoped for M/N/K.** Now that K and N are runtime values (≤4,
per the PM's Q&A round 2 — `docs/session-handoff.md` §12), the sequencer
needs to derive loop bounds from `dim_K`/`dim_N`, not just `dim_M`. Task
prompt not written yet — holding per the PM-document pause below.
Dependencies: steps 6, 7. Blocked: no (but not yet reprompted).

**9. Activation / weight buffers**
Files: `rtl/unpu_actbuf.sv`, `rtl/unpu_wbuf.sv`, `tb/unpu_buf_tb.sv`
Acceptance: double-buffered weight swap (shift-down, reversed row order)
completes in the 4 hidden cycles without stalling compute on the active tile.
**Also needs re-scoping**: for K<4 or N<4, unused weight rows/columns must be
zero-loaded (or left at reset, which is already 0) rather than loaded with
real data — falls out mostly free per `unpu_pe`'s existing reset behavior,
but the buffer's loading sequence needs to know the real K/N.
Dependencies: step 8. Blocked: no (but not yet reprompted).

**10. DMA master**
Files: `rtl/unpu_dma.sv`, `tb/unpu_dma_tb.sv`
Acceptance: 4-state FSM moves tensors between shared SRAM and the
activation/weight buffers with the arbiter, matching the native PicoRV32
memory-interface convention (`wstrb==0`→read, `rdata` valid same cycle as
`valid & ready`).
**Unblocked** — Q7 answered native (`docs/session-handoff.md` §5). Also
needs M/N/K-aware addressing now (strides for a 2D tensor, not just a flat
M-row stream) — not yet re-scoped in a task prompt.
Dependencies: step 9. Blocked: no (task prompt not yet written).

**11. Randomised back-pressure test**
Files: extends `tb/unpu_dma_tb.sv`
Acceptance: with randomised arbiter grant latency/back-pressure injected on
the DMA side, results still match the golden model and the DMA FSM never
hangs or corrupts in-flight state.
**Unblocked** — same as step 10.
Dependencies: step 10. Blocked: no (task prompt not yet written).

**12. CSR / register map**
Files: `rtl/unpu_csr.sv`, `tb/unpu_csr_tb.sv`
**Design finalized, not the old two-variant framing.** 8 registers:
`src_A`, `src_B`, `dest_C`, `dim_M`, `dim_N`, `dim_K`, `npu_ctrl`,
`npu_status` — see `docs/planning/unpu-architecture.html` §3 for the
proposed (not yet PM-confirmed) offset layout, 0x00–0x1C.
Acceptance: directed register test covers all 8 offsets; SIGNED mode bit
(now folded into `npu_ctrl` bit 1) round-trips; `npu_ctrl` START is
write-1-to-pulse and reads back 0; `npu_status` is read-only.
Dependencies: step 1. Blocked: no (task prompt not yet written).

**13. Native slave FSM (was: APB slave FSM)**
Files: `rtl/unpu_apb.sv` renamed/redesigned — filename TBD, likely
`rtl/unpu_slave.sv` — `tb/unpu_apb_tb.sv` likewise.
**Superseded, not just renamed.** Q7 confirmed the CPU↔NPU interface is
native (PicoRV32-convention `valid`/`ready`/`wstrb`), not APB. This is a
different protocol, not a drop-in replacement — the whole module needs
redesigning against the native convention instead of APB's two-phase
SETUP/ACCESS.
Acceptance (to be rewritten): sim drives the native interface at variable,
very slow pacing (mimicking the SPI backdoor) and confirms correct
read/write semantics with no hang, against the 8-register CSR map.
Dependencies: step 12. Blocked: no (task prompt not yet written — needs a
native-slave interface spec first, same convention as `unpu_dma`'s port).

**14. Top-level integration (functional)**
Files: `rtl/unpu_top.sv`, `tb/unpu_top_tb.sv`
Acceptance: full SoC-level directed test (CPU writes pointers + start bit,
DMA fetches, grid computes, results written back, DONE set) matches the
golden model's vector files end to end, using the (now negotiable, not
frozen) port list.
Dependencies: steps 1, 4, 6, 7, 8, 9, 10, 12, 13. Blocked: no by question —
transitively blocked only by 8/9/10/12/13 not yet being built.

**15. ~~Scan chain insertion~~ — REMOVED**
**Question 3 answered: no scan chain, no scan pins.** Not in scope for this
project. This step is dropped from the plan entirely — step 16 no longer
depends on it.

**16. RTL freeze regression / sign-off**
Files: none new — full regression run across all directed + golden-model
vectors at SoC level, plus the W4 gate checklist.
Freeze gate is **functional correctness only**: full regression (directed +
golden-model) passes clean at top level. No scan-mode sim — step 15 removed.
This step does **not** depend on step 5 — see "Freeze gate" below.
Dependencies: step 14. Blocked: yes, transitively — via 14.

---

## Freeze gate — decoupled from trial hardening

RTL freeze (step 16) no longer depends on step 5's P&R trial. Freeze is
functional: all directed and golden-model tests passing at top level. Step 5
stays a parallel track with its own gate (a real critical-path/congestion
number on the grid), useful for catching a 50 MHz problem early, but it does
not gate freeze.

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
7. **Done.** `docs/planning/tasks/005-stall.md`, committed `aec4a09`.
   Freeze wiring confirmed already correct (every `always_ff` in
   `unpu_pe.sv`/`unpu_skew.sv`/`unpu_deskew.sv` gates on `array_en`) — pure
   testbench task, no RTL touched. `tb/unpu_stall_tb.sv` ran a baseline plus
   three directed stall placements (early/mid/late in the pipeline) with a
   randomised 1–5 cycle stall from a fixed printed seed (`32'h5eed0005`:
   draws 2/4/1). All 44 probed registers (6 skew + 32 grid + 6 de-skew) held
   bit-exact across all 7 stall edges; all 64 `C`-value checks matched
   `cross_terms_c.hex`. Regression: `unpu_pe_tb`/`unpu_grid_tb`/
   `unpu_skew_tb` still pass. Verified independently (commit stat + file
   diff).
3, 5, 8–14, 16: not started. 15 removed from scope (no scan chain, Q3).

## Blocks RTL freeze — none remain

All four questions are answered (see top of file). Nothing is blocked by an
open PM question anymore. What remains is design/implementation work that
hasn't been re-scoped or task-prompted yet: steps 8, 9 need M/N/K awareness;
10, 11 need M/N/K-aware DMA addressing; 12 needs the 8-register design
turned into a task prompt; 13 needs a native-slave interface spec written
before it can be prompted at all (bigger lift than the others — it's a new
protocol, not an adjustment).

**Holding point:** none of the above gets a task prompt until the user's
final project document from the PM arrives — see "Questions going into the
PM meeting" at the top of this file. This section is accurate as of the
PM Q&A round recorded in `docs/session-handoff.md` §12, but nothing new
should be drafted from it yet.

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
