# Implementation plan — through RTL freeze

**RTL FROZEN as of commit `87d31bf` (2026-09-15).** Standalone record:
`docs/freeze-report.md`. This plan's stated goal is met; what follows is
now history plus the small amount of tracked follow-up (task 016) and
everything already known to be outside this plan's scope (back-end,
firmware — see below).

**Reopened, provisionally, 2026-09-20** — task 017
(`docs/planning/tasks/017-interim-enable-start.md`) added an interim
`npu_enable`/`npu_start_req` protocol to `rtl/unpu_top.sv` only, ahead of
a SoC-team conversation. Landed (`5767bfc`), then **fully superseded**
below once that conversation happened.

**Reopened again, 2026-09-22** — the SoC-team conversation landed on
**APB**, not a variant of native, for the CPU↔NPU register interface
(DMA↔SRAM stays native, unaffected). Task 017's interim protocol is
removed entirely, not layered under APB. Task written, held pending
dispatch: `docs/planning/tasks/018-apb-revert.md`. See "Open questions"
item 5 below for full detail.

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
≤ 4 at runtime (never greater — no tiling required). The PM also supplied
the main sequencer's own FSM sketch — filed at `docs/pm/sequencer-fsm.txt`,
verified consistent with the timing contract in
`docs/session-handoff.md` §13.

**Hold lifted.** The user has confirmed this is now enough to proceed —
task prompts for steps 8+ can be written going forward. See the new
verification-methodology requirement below before writing any of them.

---

## Open questions — address window: RESOLVED (2026-09-22, CPU↔NPU reverts to APB)

5. **Does the `0x4000_0000`–`0x4000_0FFF` address window still apply
   unchanged now that the control interface is native rather than
   APB-bridged, or does removing APB change how the window is decoded at
   the top level?** Raised 2026-09-14.

   **First answer (PM, 2026-09-17):** "There will be a decoder after the
   Pico and that will assert the npu_ready signal (or some similar
   name). Once this signal is asserted, npu's internal FSM should start
   and get the data from the registers based on the timing agreed with
   the Pico. Once npu is enabled, you don't need to look at the
   addresses. These will be in your window." **Confirms `unpu_slave`'s
   assumption #1 exactly as built** (task 010,
   `docs/planning/tasks/010-native-slave.md`): an external decoder
   filters CPU traffic before it reaches us, so `csr_sel =
   mem_addr[11:2]` with no `0x4000_` prefix check is correct — no RTL
   change needed here.

   **Follow-up sent back** (whether "npu_ready...should start" means a
   per-transaction `valid` matching what's built, or a separate one-time
   enable): **answered, 2026-09-17** — the PM described one possible
   three-signal protocol: (1) an "enabled" signal meaning "Pico wants to
   talk to the NPU," (2) the processor then writes the required
   registers over the next few cycles, (3) the processor asserts a
   separate **"ready"** signal — distinct from the register writes —
   that tells the NPU it's cleared to start computing. He was explicit
   this is only *one* possible shape, not a confirmed spec: "There are
   multiple ways of doing this... I'd recommend you talk to the SoC team
   to figure out a common ground."

   **Status: genuinely open, needs a human cross-team conversation, not
   an RTL decision Planning/Execution can make.** What's already built
   and frozen achieves the same three things (target identification via
   address decode, register writes for config, an explicit start
   trigger) but entirely through the memory-mapped register interface —
   START is `npu_ctrl` bit 0, a write-1-to-pulse **register write**, not
   a discrete physical signal. Functionally equivalent to the PM's
   sketch; not identical in mechanism. If the SoC team is fine with a
   register-write START, **zero RTL changes needed** — the freeze
   stands as-is. If they specifically require a discrete START pin
   separate from the register interface, that's a real (small, but
   real) `unpu_top` port addition, which would reopen the freeze for
   that one port. **Not blocking** anything right now; tracked here
   until the user has that SoC-team conversation and brings back an
   actual answer.

   **Update 2026-09-20 — user's decision: implement the PM's sketch now,
   provisionally, ahead of the SoC-team conversation** (scheduled for
   tomorrow). Rather than wait, build the three-signal shape as one
   concrete option so there's something working to test against. Task
   written: `docs/planning/tasks/017-interim-enable-start.md`. **This
   reopens RTL freeze**, scoped to exactly one file —
   `rtl/unpu_top.sv` — via two new ports (`npu_enable`, `npu_start_req`,
   named to avoid colliding with this design's existing `mem_ready`/
   `dma_ready` meaning) that gate/combine already-existing signals
   rather than changing any submodule. `tb/unpu_top_tb.sv` also needs
   updating (every existing case needs `npu_enable` wrapped around its
   register traffic, same situation task 011 was in with
   `unpu_seq_tb.sv`). The existing `npu_ctrl`-bit-0-write START path is
   kept working alongside the new discrete trigger, not replaced —
   deliberately, so this doesn't have to guess which one the SoC-team
   conversation lands on. **Explicitly provisional** — may be revised or
   reverted once that conversation happens.

   **Done.** Committed `5767bfc`, pushed. (Superseded below,
   2026-09-22 — see the final update to this item.) `git diff --stat rtl/`
   confirmed only `unpu_top.sv` changed — no submodule touched. Four new
   directed cases (`npu_enable=0` blocks access, `npu_start_req`
   triggers a full `cross_terms` matmul, the exact edge-timing boundary,
   `npu_start_req` without `npu_enable` does nothing) plus every
   existing case and all 64 CRV cases re-run with `npu_enable` wrapping
   register traffic. 534 checks, 0 failures. Full regression on all nine
   other (unchanged) testbenches confirmed still green.
   One deliberate, documented exception to `unpu_top_tb.sv`'s black-box-
   only policy (task 012): the edge-timing check needs to observe a
   transient pulse that settles within the same delta-cycle it's
   produced and isn't exposed at any top-level pin (`unpu_seq.busy` is
   left unconnected at `unpu_top`'s own port list) — no black-box
   observation point exists for it. Execution used
   `dut.u_seq.busy` as a registered proxy, worked through the NBA/delta-
   cycle timing by hand before trusting it, and confirmed it correctly
   distinguishes the specified correct RTL from a one-cycle-late
   (double-registered) variant. Narrowly scoped, well-reasoned, flagged
   explicitly rather than silently bent — same standard as every prior
   hierarchical-access exception in this project (task 007's `stage[]`
   check, task 005's stall-register probes).

   **Final resolution, 2026-09-22 — the SoC-team conversation happened.**
   User, PM, and the SoC-top team decided: CPU↔NPU reverts to **APB**,
   not a variant of native. DMA↔SRAM is unaffected, still native. This
   answers the question differently than either option this item's text
   anticipated (per-transaction native `valid`, or a discrete
   enable/start pin over native) — APB was the actual answer, not a
   shape of native.

   Task 017's provisional protocol is **fully superseded, not layered
   under APB** — `psel`/`penable` already provide what `npu_enable`/
   `npu_start_req` were approximating, and START stays a register write
   like it always was. Task written, DMA↔SRAM-native scope confirmed by
   the user, sent to Execution 2026-09-22:
   `docs/planning/tasks/018-apb-revert.md`. `unpu_csr.sv` (task 009) was
   deliberately built bus-protocol-agnostic — this is a bus-transport
   swap, not a register-map or semantics change, and that module needs
   no changes at all. Reopens RTL freeze a second time, scoped to
   `rtl/unpu_top.sv` (rewritten) plus a new `rtl/unpu_apb.sv` replacing
   the retired `rtl/unpu_slave.sv`.

   **Done.** Committed `9f5deab`, pushed. Scope held exactly as
   specified: `git diff --stat rtl/` showed only `unpu_top.sv` changed
   besides the new `unpu_apb.sv` and deleted `unpu_slave.sv`;
   `unpu_csr.sv` confirmed untouched by reading it first, not assumed;
   `unpu_dma.sv` and its wiring untouched, DMA↔SRAM-native boundary
   held. `csr_wen = psel && penable && pwrite` implemented exactly as
   specified, with the SETUP-phase-must-not-commit boundary directly
   tested. `tb/unpu_apb_tb.sv`: 150 CRV iterations, 2259 checks.
   `tb/unpu_top_tb.sv`: task 017's four now-obsolete directed cases
   dropped; 512 checks over APB — an exact match to task 012's original
   native-transport baseline, which makes sense: same test content,
   different bus underneath. Full regression on the eight other
   untouched testbenches green; a whole-design lint pass came back clean
   beyond the same pre-existing `unpu_grid.sv` `GENUNNAMED` warnings
   task 015's freeze report already catalogued as isolated and
   pre-existing — nothing new introduced. `CLAUDE.md`'s repo layout
   fixed (`unpu_slave.sv` → `unpu_apb.sv`), confirmed matching
   `ls rtl/*.sv`.

---

## Verification methodology — constrained random, starting now

**User's directive:** every module gets extensively tested from here on,
including but not limited to constrained random verification (CRV) — not
directed-only. This applies to every task prompt for steps 8 and onward;
see "Verification debt" below for what it means for steps 1–7, already
built against directed tests alone.

What this means concretely, per module, when each task prompt gets written:

- **Randomize the data**, not just the control flow: full-range signed
  int8 for every element of A and B (not hand-picked corner values), across
  many iterations, checked against `model/golden.c`'s output — which
  already exists as an oracle for exactly this purpose.
- **Randomize the shape**: M, N, K independently across their legal range
  (1–4 each), not just the values already covered by directed cases
  (M=1, M=4, non-multiple-of-4 M).
- **Randomize the timing** where a module has timing degrees of freedom:
  arbiter grant latency/back-pressure (step 11 already has this baked into
  its acceptance criterion — extend it to randomize burst length and
  address too, not just grant timing), native-slave access pacing (steps
  12/13 — randomize pacing *and* the read/write sequence across all 8
  offsets, not just slow-pacing directed sweeps), `array_en` stall
  placement and duration (step 7 already did this for cycle count — a
  precedent worth reusing, not reinventing).
- **Self-checking against a reference, every iteration.** The golden model
  is the reference for data/shape; the timing contract is the reference for
  cycle-accuracy. A CRV run that doesn't check itself just burns simulation
  time.
- **Seed, log, and report reproducibly.** Every task prompt with a random
  component must specify: a fixed default seed with a way to override it,
  the iteration count, and a `$display` of the seed on every run — same
  discipline step 7 already used (`32'h5eed0005`, printed).
- **Directed tests don't go away.** CRV finds the cases nobody thought to
  write by hand; directed tests document and pin the specific cases that
  matter (saturation, zero weight, depth-0 paths, the exact timing-contract
  cycle numbers). Both, not one instead of the other.

This is a standing requirement for every future task prompt's acceptance
criteria — it will be called out explicitly in each one, not left implicit.

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

**8. Sequencer FSM — task written, `docs/planning/tasks/006-sequencer.md`**
Files: `rtl/unpu_seq.sv`, `tb/unpu_seq_tb.sv`, plus a Part A extension to
`model/golden.c` (new sub-4 shape cases + CRV case generation).
States, adapted from the PM's own sketch (`docs/pm/sequencer-fsm.txt`):
`IDLE` → `LATCH_CFG` → `LOAD_WEIGHTS` (`K×N` loaded) → `LOAD_INPUT`
(`M×K` loaded) → `COMPUTE` → `READ_OUTPUT` → `WRITE_OUTPUT` (`M×N` values)
→ `DONE`, plus `ERROR`. Both `LATCH_CFG` and `ERROR` are confirmed — the
user's call, given directly, additive and not blocking on the PM (see the
task file's "Two resolutions" section).

**Correction made while writing the task:** the PM sketch's literal
"stop after `M+K+N-2` cycles" does **not** generalize below the full 4×4
case — it only matches the timing contract's `m+7` figure when
`K+N=8`. Since skew/de-skew depths are fixed by physical row/column
position, not runtime K/N (`docs/session-handoff.md` §6), the correct,
general stop condition is "stop when the *same* registered cycle counter
used for row injection reaches `dim_m+6`" — independent of K and N. The
task file derives this in full and requires a black-box differential test
(same M, two different (K,N) pairs, same total cycle count) specifically
to catch an implementation that reverts to the PM's literal formula.
Acceptance: matmul passes for M, N, K each independently at 1 and 4 (not
just M), plus a directed non-square/non-multiple-of-4 case (`seq_mixed`,
M=3/K=2/N=3); total cycle count matches the timing contract exactly each
time and is proven K/N-independent at fixed M; results match the golden
model's vector files. **Plus CRV** per the methodology above: randomized
M/N/K (1–4 each) × randomized full-range signed int8 A/B, 64 iterations,
self-checked against `model/golden.c`, seeded (`32'h5eed0006`) and logged.
Dependencies: steps 6, 7. Blocked: no.

**9. Activation / weight buffers — task written, `docs/planning/tasks/007-buffers.md`**
Files: `rtl/unpu_actbuf.sv`, `rtl/unpu_wbuf.sv`, `tb/unpu_buf_tb.sv`.
Mechanism per notebook §05 B4/B5 (still-good datapath sections, not the
stale control-plane material): `unpu_wbuf` shift-down/reverse-row load
(worked out in full in the task file, including the row-settling trace
table); `unpu_actbuf` natural-order load, sized for one 4×4 tile
double-buffered (32 bytes) — the notebook's provisional 32×32/64×32-bit
sizing predates the M/N/K≤4 no-tiling confirmation and is deliberately
not used.
Acceptance: double-buffered weight swap (shift-down, reversed row order)
completes in the 4 hidden cycles without stalling compute on the active
tile — proven via a concurrent-load-during-compute test, not just
sequential load-then-compute. For K<4 or N<4 (and M<4/K<4 for actbuf),
unused rows/columns are zero-loaded by the buffer itself, not just
trusted from the caller. **Plus CRV**: all 64 `crv_*` cases from task 006
chained back-to-back, each case's load+swap racing the previous case's
compute with randomized swap timing, self-checked against the golden
model.
Dependencies: step 8. Blocked: no.

**10+11. DMA master + randomised back-pressure — task written, `docs/planning/tasks/008-dma.md`**
Files: `rtl/unpu_dma.sv`, `tb/unpu_dma_tb.sv`. Combined into one task —
they share both files and step 11 was already defined as "extends
tb/unpu_dma_tb.sv," not a separate module.
Addressing convention (Planning's choice, not yet firmware-confirmed —
`docs/session-handoff.md` §7 item 5 is still open): word-per-row, fixed
4-byte stride for A/W regardless of real K/N (matches the notebook's
bandwidth-balance argument, no runtime multiply needed); fixed 16-byte
row stride for C, one word per column, only the real N columns written.
FSM: the notebook's exact 4-state `D_IDLE`/`D_REQ`/`D_ACK`/`D_FIN` bus
handshake as the per-beat core, plus one `BUF_LOAD` state that drains a
completed fetch into `unpu_wbuf`/`unpu_actbuf`'s load port (a small
internal staging array absorbs arbiter back-pressure so that hookup can
be a clean gap-free 4-cycle burst, matching task 007's load-port
contract).
Acceptance: matches the native PicoRV32 memory-interface convention
(`wstrb==0`→read, `rdata` valid same cycle as `valid & ready`, address
advances only when `valid & ready` both high); M/N/K-aware addressing
proven via `seq_k1`/`seq_n1`/`seq_mixed`; a directed held-back-pressure
case with zero address/data drift during the stall. **Plus CRV**: all 64
`crv_*` cases at randomized base addresses, with randomized per-beat
arbiter grant latency (0-5 cycles) on every beat, not just a directed
sweep — self-checked against the golden model via `unpu_actbuf`/
`unpu_wbuf` (fetch) and readback of a testbench-modeled SRAM (writeback).
Dependencies: step 9. Blocked: no.

**12. CSR / register map — task written, `docs/planning/tasks/009-csr.md`**
Files: `rtl/unpu_csr.sv`, `tb/unpu_csr_tb.sv`
8 registers: `src_A`, `src_B`, `dest_C`, `dim_M`, `dim_N`, `dim_K`,
`npu_ctrl`, `npu_status` — see `docs/planning/unpu-architecture.html` §3
for the proposed (not yet PM-confirmed) offset layout, 0x00–0x1C.
Bus-protocol-agnostic by design: a plain `csr_sel[9:0]`/`csr_wdata`/
`csr_wen`/`csr_rdata` port, decoded down from the real bus address by
step 13's native slave FSM, not this module. `npu_status` gets two
Planning-added bits beyond the confirmed DONE (bit1 ERROR, bits[4:2]
error_code) — the hookup task 006 built `unpu_seq.error`/`error_code`
for. `dim_M`/`dim_N`/`dim_K` legality is deliberately not validated
here — already `unpu_seq`'s `LATCH_CFG` job.
Acceptance: directed register test covers all 8 offsets; SIGNED mode bit
(folded into `npu_ctrl` bit 1) round-trips, including the bit1→
`mode_unsigned` **polarity** check (bit1=1 means signed, so
`mode_unsigned=~bit1` — flagged as the one thing worth getting wrong
silently); `npu_ctrl` START is write-1-to-pulse and reads back 0;
`npu_status` is read-only and DONE is sticky-until-next-start, not a
pulse-through; reserved-range accesses (`csr_sel` 8–1023) read 0 and
write nowhere.
**Plus CRV**: randomized read/write sequences across the full
`csr_sel[9:0]` range (including back-to-back and reserved-range
accesses), self-checked against a shadow model the testbench maintains
(no golden-C oracle applies to a control-plane module).
Dependencies: step 1. Blocked: no.

**13. Native slave (was: APB slave FSM) — task written, `docs/planning/tasks/010-native-slave.md`**
Files: `rtl/unpu_slave.sv`, `tb/unpu_slave_tb.sv`.
**Superseded, not just renamed.** Q7 confirmed the CPU↔NPU interface is
native (PicoRV32-convention `valid`/`ready`/`wstrb`), not APB — a different
protocol, not a drop-in replacement.
**Finding while writing the task: this collapses to pure combinational
glue, not a genuine multi-state FSM.** `unpu_csr` (task 009) already
reads combinationally and commits a write in one cycle; the old APB
design's own `pready`-tied-high decision (never stall a config register,
never hang the SPI debug backdoor) carries over unchanged to native. Tie
`mem_ready` high, decode `mem_addr[11:2]` straight to `csr_sel`, gate
`csr_wen` on `valid && wstrb!=0`, wire `csr_rdata` straight to `mem_rdata`
— no sequential logic needed. Two flagged assumptions: address decode
trusts `mem_addr` is already window-filtered by the time `mem_valid`
arrives (ties into the still-open address-window question above — a
one-line fix if that resolves differently); any nonzero `wstrb` commits
the full word, no partial-byte merge (same simplification `unpu_dma`
already made).
Acceptance: correct read/write semantics with no hang against the
8-register CSR map, proven with a real `unpu_csr` instance, not a mock;
`mem_ready==1` checked as its own standalone property, not just inferred
from transactions completing. **Plus CRV**: randomized access pacing
(mimicking the SPI backdoor's arbitrary slowness) *and* randomized
read/write sequencing, self-checked against a shadow model extending
task 009's.
Dependencies: step 12. Blocked: no.

**13.5 (new). Revise `unpu_seq` for real DMA/buffer orchestration — task written, `docs/planning/tasks/011-seq-revision.md`**
Found while starting to plan step 14: `unpu_seq` as built in task 006
cannot actually drive `unpu_dma`'s job port or `unpu_wbuf`/`unpu_actbuf`'s
load/swap port — it was built against direct-forced `a_src`/`w_src` and
outputs straight to `unpu_grid`/`unpu_skew`, deliberately as a stand-in
at the time (task 006 said so explicitly). Tasks 007–010 built the real
buffers/DMA/CSR/slave but never wired anything to `unpu_seq`, since that
wasn't their job. Something has to connect them for step 14 to be real
integration rather than a shim that leaves `unpu_wbuf`/`unpu_actbuf`
unused — considered keeping `unpu_seq` frozen and building that shim in
`unpu_top` instead, rejected: it would throw away task 008's already-
working DMA→buffer integration to avoid touching a tested module. Revising
`unpu_seq` is the correct call, not the convenient one — decided and
executed without stopping to ask, same footing as the `M+K+N-2`
correction in task 006 (a plan-flaw fix within an already-clear
requirement, not a judgment call needing a decision from the user).
This un-freezes `rtl/unpu_seq.sv`/`tb/unpu_seq_tb.sv` for this task only
— every other module's freeze is unchanged.
New states: `W_FETCH`/`W_SWAP`/`A_FETCH`/`A_SWAP` replace
`LOAD_WEIGHTS`/`LOAD_INPUT`; `WRITE_OUTPUT` now dispatches a real
`unpu_dma` writeback job. `COMPUTE`'s stop condition, `LATCH_CFG`'s
legality check, and `ERROR` are untouched. A single `array_en` still
spans the whole op including arbitrarily long DMA waits — worked out
carefully in the task file why this can't corrupt in-flight psum state
(`unpu_pe`'s accumulation is a pure per-cycle function of `psum_in`, not
self-referential, so garbage during a DMA wait is fully flushed by the
time `COMPUTE` starts trusting data at `cycle>=7`) rather than splitting
into a separate buffer-enable/compute-enable looking for a problem that
isn't there.
Acceptance: full pipeline (DMA fetch → swap → compute → DMA writeback)
correct for `cross_terms` and the sub-4 shape cases; two ops back to back
with no reset between them, proving no cross-op contamination; the
job_start-re-pulse boundary explicitly checked (same bug class as tasks
007/010, now on the RTL side). **Plus CRV**: all 64 `crv_*` cases run end
to end through `unpu_seq` itself (not testbench-driven DMA jobs), back to
back with no reset, randomized back-pressure — the strongest correctness
proof this task has.
Dependencies: steps 6, 7, 8, 9, 10. Blocked: no.

**14. Top-level integration (functional) — task written, `docs/planning/tasks/012-top.md`**
Files: `rtl/unpu_top.sv`, `tb/unpu_top_tb.sv`. Two-port shape: native
slave (`mem_*`, CPU-facing) + native master (`dma_*`, SRAM-facing) —
matches the already-built `unpu_slave`/`unpu_dma` interfaces exactly, per
CLAUDE.md's "negotiable, not frozen" port list. Full ten-instance wiring
table worked out in the task file — every signal name checked against
each module's actual current port list, not re-derived from memory.
Acceptance: full SoC-level directed test driven **only through the two
native ports** (no internal probing) — CPU writes pointers + dims +
START via the confirmed CSR offsets, polls `npu_status` for DONE, SRAM
writeback checked against golden vectors. **Plus CRV**: all 64 `crv_*`
cases back to back with no reset, randomized per-case SRAM addresses,
randomized DMA-side back-pressure, and randomized sparse CPU-side polling
pacing — self-checked against the golden model.
Dependencies: steps 1, 4, 6, 7, 8 (revised, 13.5), 9, 10, 12, 13.
Blocked: no.

**15. ~~Scan chain insertion~~ — REMOVED**
**Question 3 answered: no scan chain, no scan pins.** Not in scope for this
project. This step is dropped from the plan entirely — step 16 no longer
depends on it.

**16. RTL freeze regression / sign-off — task written, `docs/planning/tasks/015-freeze.md`**
Files: no RTL/testbench changes expected; produces `docs/freeze-report.md`
as the sign-off record. Made deliberately more thorough than a plain
regression re-run per the user's explicit instruction: six parts — (A)
full regression against recorded per-module minimum check/iteration
floors, so a silently-truncated run can't slip through; (B) a *fresh-seed*
re-run of every CRV suite, not just re-confirming the one documented seed
still works; (C) golden-model determinism (`rm -rf model/vectors`,
rebuild, byte-identical regeneration, full re-run against the
regenerated vectors); (D) a whole-design lint sweep at full `unpu_top`
elaboration, catching cross-module issues no single module's isolated
lint run would surface; (E) a repository hygiene audit (stray files,
`git status` clean, CLAUDE.md's repo-layout listing checked against what
actually exists); (F) the written freeze report itself.
Freeze gate is **functional correctness only**: no timing/STA, no
DRC/LVS, no firmware — explicitly decoupled, see "Freeze gate" below.
No scan-mode sim — step 15 removed.
Sent to Execution 2026-09-15 (held overnight per the user's request on
2026-09-14, now released).
Dependencies: step 14 (done). Blocked: no.

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
8. **Done.** `docs/planning/tasks/006-sequencer.md`, committed `2dd20c3`,
   pushed. `model/golden.c` extended (append-only meta format, four new
   directed shape cases, 64-case CRV batch, seed `32'h5eed0006`) —
   `unpu_stall_tb` re-run against regenerated `cross_terms` vectors,
   confirmed the format change didn't break its parser. `rtl/unpu_seq.sv`
   (9-state FSM) + `tb/unpu_seq_tb.sv` implement the corrected
   `dim_m+6`-based COMPUTE-exit condition from the task file, not the PM
   sketch's `M+K+N-2` — the required differential test (dim_m=4 across
   K=4,N=4 vs K=1,N=1) confirms identical cycle counts (17 total,
   dim_m+7=11 compute cycles). All directed cases, illegal-config/error-
   recovery, and all 64 CRV cases pass (985 checks, 452 opportunistic K/N-
   independence pairs, all matching). Full regression still green.
   Execution flagged one thing worth recording: a first-draft bug (Mealy-
   style outputs registered off the old state) would have delayed
   `weight_load`'s pulse and shown `done` a cycle late — caught and fixed
   before finalizing by switching to pure Moore (combinational-from-
   `state`) outputs. Not retroactive to anything else; noted here as the
   kind of subtle timing bug worth watching for in step 9/10's FSMs too.
9. **Done.** `docs/planning/tasks/007-buffers.md`, committed `2a77a0a`,
   pushed. `rtl/unpu_wbuf.sv` + `rtl/unpu_actbuf.sv` + `tb/unpu_buf_tb.sv`,
   both buffers built on two fully independent bank arrays (not one array
   with a runtime select), loading/swap gated on `array_en` per the
   project's freeze convention. Whitebox settling assertion done as
   required (`stage[col][row]` checked against `W[row][col]` for all 16
   positions, separate from the end-to-end matmul check). Concurrent-
   load-during-compute test passes bit-identical to the no-concurrency
   baseline — the actual double-buffering property, not just sequential
   load-then-compute. 64-case CRV chain with randomized early/mid/late
   swap timing: 531 checks, 0 failures. Full regression still green.
   Simulated with Verilator (per the tooling note below).
   Execution flagged a real bug caught pre-commit: `weight_in` initially
   read straight off the registered `active_sel`, which only updates the
   cycle *after* `swap` is sampled — so on the swap cycle itself,
   `weight_in` still reflected the old bank at the exact moment
   `weight_load` pulsed and `unpu_pe` latched it (symptom: all-zero
   output, failed outright rather than subtly). Fixed with a same-cycle
   lookahead (`effective_sel = active_sel ^ (swap && array_en)`), the same
   idiom used for `unpu_seq`'s `LATCH_CFG` illegal-dim check in task 006.
   Execution's own note, worth keeping: this is the second time this
   "registered-select driving a same-cycle output" pattern has bitten a
   first draft — `unpu_dma` (step 10) will likely face the same
   active/inactive-buffer-selection question and should watch for it.
   This belongs in `docs/roles/execution.md`'s known-traps material, which
   is outside Planning's write scope (same situation as the port-list/
   register-map fixes noted in `docs/session-handoff.md` §12) — flagged
   here for Execution to add when convenient, not chased further by
   Planning.
10+11. **Done.** `docs/planning/tasks/008-dma.md`, committed `880d5e6`,
   pushed. `rtl/unpu_dma.sv` (`D_IDLE`/`D_REQ`/`D_ACK`/`BUF_LOAD`/`D_FIN`)
   drains a completed fetch into real `unpu_actbuf`/`unpu_wbuf` instances
   as a clean 4-cycle burst; addressing follows the task file's
   provisional convention exactly, no improvisation. Checked specifically
   for a recurrence of task 007's registered-select staleness bug —
   confirmed clean, every `BUF_LOAD`-cycle output is combinational off
   the current `ld_cnt`/`row_idx`. `tb/unpu_dma_tb.sv`: real buffer
   instances, inline behavioral SRAM with randomized 0-5 cycle per-beat
   back-pressure, directed + all 64 CRV cases. 1110 checks, 0 failures,
   full regression green. Simulated with Verilator.
   Two bugs found and fixed, both in the testbench, not the RTL (isolated
   via a zero-latency-memory probe of `unpu_dma` alone before adding
   buffers/back-pressure): (1) a wait loop read `job_done` one cycle
   before the FSM actually settled back to `D_IDLE`, which — since
   `job_start` is only sampled in `D_IDLE` — looked exactly like a DMA
   hang; (2) the held-back-pressure directed case forced a stall a fixed
   number of cycles after `job_start`, racing the model's own randomized
   (possibly zero-cycle) grant — fixed by asserting the stall before
   `job_start` instead of timing it relative to the DUT's own progress.
12. **Done.** `docs/planning/tasks/009-csr.md`, committed `89fcdea`,
   pushed. `rtl/unpu_csr.sv` per spec. Polarity handled correctly and
   tested explicitly (`mode_unsigned = ~ctrl_signed_reg`, checked as an
   output-value assertion, not just a bit round-trip). `npu_status.DONE`
   sticky/start-clear behavior implemented and tested. CRV: 200
   iterations (above the 64 minimum) against a shadow model, seed
   `32'h5eed0009` — 1838 checks, 0 failures. Every consumer-facing port
   and `csr_rdata` turned out to be pure combinational reads of
   already-updated registers, so the CRV loop is genuinely back-to-back
   writes with zero idle cycles by construction. Full regression green.
   Simulated with Verilator.
13. **Done.** `docs/planning/tasks/010-native-slave.md`, committed
   `826f91d`, pushed. `rtl/unpu_slave.sv` is the reference design
   essentially verbatim — pure combinational glue, no `always_ff`. Both
   flagged assumptions (pre-filtered address, no partial-byte merge)
   carried over as documented, not independently resolved.
   `tb/unpu_slave_tb.sv` pairs it with a real `unpu_csr`; `mem_ready==1`
   is checked on literally every cycle of the whole run (baked into the
   step helper itself), not inferred from transactions completing. CRV:
   150 iterations, seed `32'h5eed000a`, extends task 009's shadow model
   with the native dispatch rule and randomized idle pacing — 2115
   checks, 0 failures. Full regression green. Simulated with Verilator.
13.5. **Done.** `docs/planning/tasks/011-seq-revision.md`, committed
   `f2db3e8`, pushed. `job_kind` encoding double-checked directly against
   `rtl/unpu_dma.sv` rather than trusted from the task file (matched, no
   discrepancy). The `array_en`-spans-DMA-waits timing argument
   independently re-verified, no hole found, single span kept as
   specified. Full-stack testbench (real `unpu_dma`/`unpu_wbuf`/
   `unpu_actbuf`/`unpu_skew`/`unpu_grid`/`unpu_deskew`): `job_start`
   re-pulse boundary directly counted (exactly 3 per op under randomized
   multi-cycle back-pressure), two-ops-back-to-back and all 64 CRV cases
   through the real orchestration path — 539 checks, 0 failures, full
   regression green. Simulated with Verilator.

   **One real deviation from the task file, caught and flagged rather
   than silently routed around, per this task's own instruction to stop
   on a timing-argument hole:** the task file gave `rd_row` as a
   *registered* update (`rd_row <= ... ? cycle[1:0] : rd_row`). Traced
   edge-by-edge, that reads `cycle` one cycle stale relative to when
   `unpu_actbuf`'s purely-combinational `rd_data` needs it, which would
   have injected every row one cycle late with nothing downstream to
   absorb the lag. Execution checked task 006's original `a_raw` (which
   my task 006 file *also* wrote in registered `<=` notation) and found
   it was actually implemented as `assign a_raw = ...` — pure
   combinational — confirmed directly against the frozen
   `rtl/unpu_seq.sv` from commit `2dd20c3`. Implemented `rd_row` the same
   way (`assign`), matching what apparently already made task 006's own
   timing work. **Lesson for future task files: write injection-mux
   pseudocode as `assign`, not `<=`, when the intent is "pure function of
   the current cycle register" — the `<=` notation has now been
   imprecise in two task files (006 and 011) for the exact same signal
   shape, caught both times by Execution rather than by this file being
   right.**
14. **Done.** `docs/planning/tasks/012-top.md`, committed `ebe2c69`,
   pushed. All ten modules' port lists checked directly against source
   before wiring (including the just-revised `unpu_seq`), not trusted
   from the task file's table — no discrepancies found. `rtl/unpu_top.sv`
   wired exactly per the table; `psum_in` tied to 0 as flagged; lint
   noise limited to pre-existing frozen-file warnings and expected
   unused-port notices, all documented. `tb/unpu_top_tb.sv` drives
   `unpu_top` only through `mem_*`/`dma_*` throughout, including the
   illegal-config test (reads `npu_status` back over the native port, no
   hierarchical access). Polarity handled correctly and consistently
   across directed and CRV. All 64 CRV cases back to back through one
   instance, randomized addresses/back-pressure/polling pacing — 512
   checks, 0 failures, full regression green. Simulated with Verilator.
   Nothing flagged back — first full run came together cleanly.
16. **Done. RTL FROZEN.** `docs/planning/tasks/015-freeze.md`, committed
   `87d31bf` (+ hash follow-up `3c860ec`), pushed. Standalone record:
   `docs/freeze-report.md`. All six parts passed, all ten testbenches at
   or above their floors under three independent conditions (documented
   seed, fresh seed, clean-rebuilt vectors) — full detail in the report
   itself, not duplicated here. Verification debt formally recorded as
   closed at this gate. Zero RTL/testbench changes made; Part B's
   temporary seed edits were reverted and confirmed via empty `git diff`
   before Part C ran.
   One finding, reported not fixed (correct per the task's verify-don't-
   repair scope): `CLAUDE.md`'s "Repo layout" section still lists `.v`
   files and a nonexistent `unpu_apb.v`, doesn't list `unpu_slave.sv`,
   and contradicts CLAUDE.md's own `.sv` hard-constraint two screens up.
   **Done.** `docs/planning/tasks/016-claude-md-repo-layout.md`, committed
   `9da38f8`, pushed. Verified against `ls rtl/*.sv` before editing (11
   files, matched exactly); only the repo-layout code block changed.
3: not started (back-end, pending institute-server access). 15 removed
from scope (no scan chain, Q3).

**RTL functionally complete as of this step.** Every step from 1 through
14 that isn't a back-end prerequisite (3, 5) is done. Step 16 (freeze
regression/sign-off) is next and is now unblocked.

## Recurring pattern — register-timing off-by-one in testbenches, third occurrence

Worth tracking as a pattern now, not just a one-off note: task 007 (a
registered bank-select read stale on the swap cycle), task 008 (a wait
loop read `job_done` one cycle before the FSM settled), and now task 010
(an extra `step()` called after a helper that already consumed the edge
`start_pulse` needed) are all the same underlying class of bug —
one-cycle timing misalignment between when a signal is *meant* to be
sampled and when a test actually samples it, in both directions (too
early and too late). None have been RTL bugs since task 007; the last two
were testbench-only. Not a new decision to make, just a pattern worth
having in mind for step 14 (top-level integration), which will have the
deepest, most composed timing of any module so far and is exactly where
this class of bug is most likely to recur and hardest to isolate.

## Verilator quirk — open-ended `while` wait loops may hang

Flagged by Execution during task 008, not confident enough to call a
firm tooling conclusion, but worth carrying forward: an early debug probe
using `while (job_done !== 1'b1) step();` hung indefinitely under this
environment's Verilator (`--binary --timing`) for a reason not fully
root-caused, while a bounded `for` loop driving the identical DUT worked
fine and matched a cycle-accurate trace of the real FSM. Execution
rewrote every "wait for done" loop in `tb/unpu_dma_tb.sv` to bounded
`for`-loops with an explicit cycle cap + pass/fail flag rather than chase
the root cause further.

**How to apply:** if task 009+ hits an unexplained hang in a
`while`-loop-based wait, try a bounded `for`-loop with a cap first before
assuming it's a new RTL bug — this may be the same simulator quirk
recurring, not a fresh issue. Folds into the still-open Icarus/Verilator
tooling decision below; not urgent on its own.

## Tooling note — Icarus vs. Verilator — resolved

**Decision (user): standardize on Verilator.** It's been the de facto
tool since task 006 with zero simulator-attributable failures across
eight tasks (one documented, worked-around quirk — the open-ended
`while`-wait-loop hang, `plan.md` above). `iverilog` isn't worth chasing:
no root in Execution's environment, and no evidence Verilator has been
unreliable. Xcelium is actually the course's intended tool
(`docs/session-handoff.md` §2's tools list) and needs the same
institute-server access already being pursued for steps 3/5 — once that
access exists, one full regression cross-check on Xcelium is worth doing
as a sanity check before anything signoff-adjacent, but that rides along
with the back-end access work rather than being chased separately now.

Checked what was actually stale before writing the fix, rather than
assuming every header needed touching: `unpu_pe.sv`/`unpu_grid.sv` never
had a simulator note (nothing to fix); the four testbenches task 013
touched already got a clarifying Verilator note appended alongside the
original Icarus line. Only `rtl/unpu_skew.sv` and `rtl/unpu_deskew.sv`
were genuinely misleading — pure RTL files claiming only Icarus with no
acknowledgment that six tasks' worth of regressions since (`seq`, `buf`,
`dma`, `stall`, `top`, task 013's own retrofit) have actually re-verified
them under Verilator. **Done.** `docs/planning/tasks/014-sim-header-update.md`,
committed `c24912b`, pushed. Comment-only, confirmed via `git diff`
(only comment lines changed on both files). Full regression green.

## Blocks RTL freeze — none remain

All functional RTL work (steps 1, 4, 6–14) is done, including the
unplanned-but-necessary 13.5 (`unpu_seq` revision) found and resolved
along the way. Nothing is task-prompted-but-unbuilt anymore. What
remains before freeze is step 16 itself: a consolidated regression run
plus the W4 gate checklist, and a decision on the verification debt
below. Steps 3 and 5 stay parked on back-end/PDK access, off the freeze
critical path per the "Freeze gate" section above.

## Verification debt — steps 1–7 — done

`docs/planning/tasks/013-verification-debt.md`, committed `fe30ede`,
pushed. All four RTL files confirmed untouched (`git diff --stat rtl/`
empty) — **no RTL bugs surfaced**, consistent with the zero-shipped-bugs
track record across all twelve prior tasks. Part A (PE): exhaustive
131,072-combination operand sweep, self-checked against an
independently-derived reference (arithmetic sign-extension, not a
`$signed()` mirror of the RTL's own cast) — plus a defensive catch worth
noting: the randomized weight-load-timing sweep guards against the
drawn activation landing on exactly 0 on the pulse cycle, since
`old_weight*0 == new_weight*0` would silently be unable to distinguish
correct from incorrect behavior on that specific draw. 256-iteration
accumulator sweep, 50-iteration timing sweep, all pass, ~0.2s wall time.
Parts B/C (grid, skew/de-skew): both existing test-runner tasks already
derived bounds from each case's own parsed `M` rather than a hardcoded
4, so no logic changes were needed — just looped across all 64 `crv_*`
cases. 684 and 636 checks respectively. Part D (stall): ran all 64 cases
(not just the ≥16 floor) since runtime cost was negligible — 2544
C-value checks + 26055 frozen-register checks. Full regression green
across everything downstream. Simulated with Verilator.

Decision made directly by the user (not left to the step 16 checklist,
resolved before it instead): **full retrofit**, all four modules, not
partial and not accepted-as-risk. Considered and explicitly not chosen:
accept as documented residual risk (given the substantial *incidental*
random coverage PE/grid/skew/deskew had already received via every CRV
suite since task 006 running the same 64 randomized cases through this
exact datapath, and zero RTL bugs shipped across all twelve tasks up to
that point) and a PE-only targeted retrofit.

Testbench-only — `unpu_pe.sv`/`unpu_grid.sv`/`unpu_skew.sv`/
`unpu_deskew.sv` stay frozen. No new golden-model work: all four reuse
the existing 64 `crv_*` files from task 006 Part A (PE needs none at all
— it's scalar, not matrix). PE's operand space (256×256 signed + 256×256
unsigned) is small enough to cover **exhaustively** rather than randomly
sampling it — genuine randomization is reserved for weight-load timing,
the one large-space axis PE actually has.

- **Step 1 (PE):** was 20 directed vectors only. Now: exhaustive
  131,072-combination operand sweep, ≥200 randomized accumulator-carry
  iterations, ≥50 randomized weight-load-timing iterations.
- **Step 4 (grid):** was identity-weight test only. Now: all 64 `crv_*`
  cases hand-skew-injected, full random weight/activation matrices.
- **Step 6 (skew/de-skew):** was one directed case (`cross_terms`, M=4).
  Now: all 64 `crv_*` cases through the full skew→grid→de-skew chain,
  random data and random M.
- **Step 7 (stall):** already had randomized stall timing, narrow in data/
  shape. Now: the same randomized stall logic run across ≥16 (ideally all
  64) `crv_*` cases instead of only `cross_terms`.

---

## Adversarial "break it" testing campaign — pre-freeze-pass, 2026-09-22

User's directive, ahead of the next freeze pass: extensive directed +
~10,000-check CRV testing, varying seeds, module by module, explicitly
trying to break the system rather than just re-confirm it. Not a repeat
of task 013 (which already gave every module a solid CRV baseline) —
each task here is scoped to extend *past* that baseline into whatever
axis each module's prior coverage left thinnest (long adversarial
sequences for PE, for example — see task 019).

**Dispatch mode changed after module 4** (user, 2026-09-25): no longer
pausing for review after every module — write and send the next
module's task immediately once the current one lands clean, straight
through to module 10. **The one standing rule this doesn't relax:
nothing fails silently.** Any RTL defect, any check that can't be made
to pass, gets stopped on and reported in full — never softened,
narrowed, or quietly dropped to keep a run green. Pause and wait for the
user only once all ten modules are done, or the moment anything actually
fails.

**Standing rule (user, 2026-09-25): don't hardcode anything.** Expected
values in every check must come from a genuine computation — a
reference model, a formula derived from the timing contract, something
independently arrived at — never a constant typed in because it matched
an observed DUT output. No cherry-picked seeds swapped in because a
different one produced a cleaner-looking result; the seed that's used is
the seed that's printed. No thresholds or iteration counts quietly
narrowed to dodge a case that's inconvenient to compute a reference for
— if a corner case is genuinely hard to verify, that gets flagged, not
silently asserted as passing. This generalizes exactly what task 019's
reference-model bug already demonstrated: a wrong "expected" side that
happens to look plausible is worse than no check at all, because it
reads as verified when it isn't. Applies to every task in this
campaign, task 023 (already dispatched) included.

Module order (matches the project's own build order and the freeze
report's ten-testbench table, `unpu_apb` replacing the retired
`unpu_slave`):

| # | Module | Task | Status |
|---|---|---|---|
| 1 | `unpu_pe` | `docs/planning/tasks/019-pe-breaktest.md` | **Done** — see below |
| 2 | `unpu_grid` | `docs/planning/tasks/020-grid-breaktest.md` | **Done** — see below |
| 3 | `unpu_skew`/`unpu_deskew` | `docs/planning/tasks/021-skew-deskew-breaktest.md` | **Done** — see below |
| 4 | `unpu_stall` (composite) | `docs/planning/tasks/022-stall-breaktest.md` | **Done** — see below |
| 5 | `unpu_seq` | `docs/planning/tasks/023-seq-breaktest.md` | **Done** — see below |
| 6 | `unpu_wbuf`/`unpu_actbuf` | `docs/planning/tasks/024-buf-breaktest.md` | **Done** — see below |
| 7 | `unpu_dma` | `docs/planning/tasks/025-dma-breaktest.md` | **Done** — see below |
| 8 | `unpu_csr` | `docs/planning/tasks/026-csr-breaktest.md` | **Done** — see below |
| 9 | `unpu_apb` | `docs/planning/tasks/027-apb-breaktest.md` | **Done** — see below |
| 10 | `unpu_top` | `docs/planning/tasks/028-top-breaktest.md` | **Done** — see below. **Campaign complete.** |

If any task in this campaign finds a real RTL defect, that task reports
it rather than fixing it in place, per the campaign's own instruction —
a found bug pauses this list for a deliberate fix-and-verify cycle, not
a quiet patch.

### Module 1 — `unpu_pe` — done, no RTL defect found

Committed `551ea26`, pushed. 20 independently-seeded adversarial
sequences (500–700 cycles each), 11,702 total cycle-checks (35,106
individual signal-checks across `act_out`/`psum_out`/`weight_reg`), 0
failures. All 4 directed boundary cases pass. Task 013's baseline
sweeps unchanged and still pass. `rtl/unpu_pe.sv` untouched — confirmed
via `git status`, only `tb/unpu_pe_tb.sv` changed.

**Worth recording, not as an RTL finding but as a campaign-wide
caution**: Execution's first-draft independent reference model had a
real bug — it accumulated `psum_out` from the shadow model's own prior
value instead of from each cycle's freshly-driven external `psum_in`.
`unpu_pe` doesn't accumulate internally; that's the real systolic
chain's job (north-neighbor `psum_in` wiring), absent in this isolated
per-module test. All 20 sequences failed from cycle 0 on the first run;
the DUT's values were confirmed correct by hand, the *reference* was
wrong. Caught and fixed within the same task (same standard as any other
testbench bug found during development, task 007/008/010/011 all had
one). **Flagged forward**: this is an easy, specific way for a
from-scratch reference model to accidentally end up "accumulating" state
a module doesn't actually carry — worth double-checking on every
subsequent module in this campaign, not just assumed fixed here.

### Module 2 — `unpu_grid` — done, no RTL defect found, reference model verified clean this time

Committed `da39f61`, pushed. Execution took the module-1 caution
seriously: made the independent reference a **stateless pure function**
(recomputes each `C[m][j]` from scratch off the current `A`/`W`
snapshots every call), which structurally rules out the accumulation-bug
class task 019 hit — and used Part A's 16-position walking-one sweep as
a built-in sanity check of that model itself (each sub-case has a
trivially hand-verifiable expected pattern, `C[m][j] = A[m][k_pos]` when
`j==j_pos` else `0`; all 16 passed clean).

Part A: max-magnitude both modes, the 16-position walking-one sweep, and
the exhaustive freeze-point sweep on `cross_terms` (11 sub-cases,
`active_cyc` 0 through `(M-1)+7` inclusive, matching CLAUDE.md's `M+7`
figure exactly) — reused task 005's `active_cyc` convention directly via
a shared `run_pass()` task, nothing reinvented. Part B: 20 sequences, 401
total passes (comfortably over the 200 floor), one reset per sequence
and zero idle gap between passes — the specific thing this part was
built to break. 11,306 checks in Part B alone. **12,474 total checks
across the file, 0 failures.** `rtl/unpu_pe.sv`/`rtl/unpu_grid.sv`
untouched, confirmed via `git status`. Task 013's existing coverage and
a four-testbench regression sanity check both still green.

### Module 3 — `unpu_skew`/`unpu_deskew` — done, no RTL defect found

Committed `f27972d`, pushed. Same stateless `ref_c_elem` as task 020
(structurally rules out task 019's accumulation-bug class); sanity-
checked against two hand-verifiable walking-one positions through the
full chain rather than repeating all 16 (task 020 already proved the
underlying math, so this only needed to confirm skew/de-skew's own
pipeline depths didn't disturb it).

**Depth-0 wire stress turned up a real nuance worth keeping**: for
`unpu_skew` row 0, Execution also toggled `array_en` throughout the
rapidly-alternating-value check, since that wire has *zero* `array_en`
gating at all — `tb/unpu_stall_tb.sv`'s own `check_frozen()` already
excludes it for exactly that reason. For `unpu_deskew` column 3, no
reference model was even needed — `c_out[3]` was compared directly
against `grid_psum_out[3]` every cycle, both already testbench-visible.
Drove genuinely-random-every-cycle data (tracked: 54/60 cycles actually
changed, gated on a ≥50 threshold) specifically to prevent a
buggy one-cycle-registered column 3 from "catching up" on static data
and coincidentally passing — the exact false-pass risk the task
description called out, closed with a concrete, checked guarantee
rather than an assumption.

Part A: max-magnitude both modes, the exhaustive 11-sub-case freeze-
point sweep across the *full* chain's window (reused
`unpu_stall_tb.sv`'s `active_cyc` convention directly), `M=1`/`M=4`
explicit cases. Part B: 20 sequences, 406 total passes, `M` transitions
biased (75% redraw-once on a same-`M` repeat, plus an explicit forced
`4→1→4→1` opening on sequence 0) — 16,604 checks in Part B alone.
**17,665 total checks, 0 failures.** All four RTL files confirmed
untouched. Task 013's existing coverage and a four-testbench regression
(including `unpu_stall_tb`, which shares this exact chain) all still
green.

**Process note, not a concern**: this task was reported directly to
this session rather than relayed through the peer session that
originally dispatched it, which had gone unreachable under its prior
name by completion time — the same session-identity churn noted after
task 021 was sent. No impact on the result.

### Module 4 — `unpu_stall` (composite) — done, no RTL defect found, strongest result in the campaign so far

Committed `126f0af`, pushed. Reused `capture_snapshot()`/
`check_frozen()` completely unmodified via a new `run_pass_freezes()`
task generalizing the existing single-freeze design to an array of
independent freeze windows per pass — no rebuild of already-correct
machinery.

Part A: all 4 sub-cases pass — 3 freezes within one pass, a 50-cycle
extreme-duration freeze checked bit-exact on *every* held cycle (not
spot-checked), both data-validity-boundary freezes
(`active_cyc==7` and `==(M-1)+7=10` for `cross_terms`), and 4 zero-gap
back-to-back freezes. 2,624 `C`-checks + 29,700 register-checks. Part
B: 20 sequences, 305 total passes, 0–4 freezes per pass at random
positions/durations — **220,545 register-checks in Part B alone**,
clearing the 15,000 floor by more than an order of magnitude, no
padding needed (as instructed, and confirmed genuinely, not adjusted to
hit a number).

**Total: 5,732 `C`-checks + 250,245 register-checks, 0 failures on the
first run.** No RTL defect, no reference-model bug (reused the same
stateless `ref_c_elem` from tasks 020/021). All four RTL files
confirmed untouched. Task 005/013's existing baseline and 64-`crv_*`-
case counts matched exactly (2,544/26,055), confirming this task didn't
disturb the existing suite while adding to it. Four-testbench regression
green, including `unpu_skew_tb`, which shares this chain.

### Module 5 — `unpu_seq` — done, no RTL defect found

Committed `4768791`, pushed. Already built to the "don't hardcode
anything" standard before that instruction landed — confirmed and
documented explicitly rather than just asserted: Part D's `dim_m+7`
check and Part E's `C`-value checks both use genuine derivations
(externally-measured cycle span; the stateless `ref_c_elem`).

**One honest limitation flagged, worth recording precisely rather than
smoothing over**: Part A/E's `error_code==3'd1` check is a fixed literal
— but it's the RTL's own single defined protocol constant
(`unpu_seq.sv`'s own header: "3'd1 = illegal `dim_m`/`dim_n`/`dim_k`,
others reserved"), not a guessed or first-run value. With only one error
code ever defined in the design, the 32-attempt rapid-fire test can
prove the FSM never hangs and `error_code` never reads anything but that
one defined value across 30+ consecutive attempts — but it structurally
*cannot* distinguish "correctly re-latched each time" from "stuck at the
only value that ever gets set," the way a second distinct code would
let it. This is a real, permanent limitation of testing a single-error-
code design, not a gap in this task's effort — noted in-file rather than
overclaimed. Worth remembering if `npu_status`'s error-code field ever
grows a second defined value later; this exact test would become
meaningfully stronger for free.

Part A: 12 exhaustive illegal cases + 6 boundary-legal + 3 multi-illegal
+ 32 rapid-fire, one reset, no legal op between attempts. Part B: 7
directed stray-`start` placements across every non-`IDLE`/`ERROR`
state (located via already-trusted `w_swap`/`a_swap`/`job_start`
outputs, not hierarchical access) plus 10 randomly-timed. Part C: 10 ops
under extreme 50–100-cycle/beat back-pressure, via a new default-off
model that leaves the original 0–5-cycle model untouched except a mux
on `dma_ready`. Part D: 24 `(dim_m,dim_k,dim_n)` triples, `COMPUTE` span
exactly `dim_m+7` every time, fully independent of `dim_k`/`dim_n`. Part
E: 20 sequences, 2,981 total ops, ~12% deliberately illegal and
interspersed, zero idle gap, one reset per sequence.

**19,840 total checks, 0 failures on the first run.** `rtl/unpu_seq.sv`
untouched. Task 006/011's baseline and all 64 `crv_*` cases still pass
unchanged. Full regression on all nine other testbenches green.

### Module 6 — `unpu_wbuf`/`unpu_actbuf` — done, no RTL defect found

Committed `12f505b`, pushed. `tb/unpu_buf_tb.sv` had no existing
stateless-reference equivalent to reuse (its CRV loop checks against
`golden.c`'s precomputed files, not an inline function) — Execution
derived one fresh with the same no-persistent-state discipline as
modules 2–5, taking `dim_k` as an explicit parameter since it genuinely
varies here.

**Part A1's design choice is worth recording, since it's a sharper
version of what the task asked for**: rather than placing extreme data
only at the two named boundary rows/columns, Execution filled the whole
`W`/`A` matrix with `0xFF` for all 16 `(K,N)` combinations — which
strictly includes the boundary as a subset while making an off-by-one
visible at *every* position simultaneously (any masked cell reading
non-zero, or any real cell reading anything but `0xFF`, fails
immediately). Part A2 then correctly used *distinct* per-position data
for `K=1,2,3` specifically, since uniform data can't catch a
transposition — every real cell would look identical regardless of
where it actually landed. Two different data strategies for two
different failure modes, not an accidental substitution of one for the
other.

Part A3 (the read-side zero-latency check): an 80-cycle rapidly-
changing, non-repeating `rd_row` sequence across two different active
banks, checked with **no clock edge at all** (pure settle) to directly
confirm the combinational contract, then reconfirmed after a real edge
too. Part A4: 24 rapid-fire load→swap cycles, zero gap, ping-pong
checked directly via `active_sel`, not inferred from data correctness
alone. Part B: 20 sequences, 2,279 total passes, extreme-biased
synthetic data, freshly-randomized load-start delay every single pass
(task 007 only ever tried one fixed relative timing).

**17,975 total checks, 0 failures on the first run.** Both RTL files
confirmed untouched. Task 007's 531-check baseline and all 64 `crv_*`
cases still pass unchanged. Full regression on all nine other
testbenches green.

---

### Module 7 — `unpu_dma` — done, no RTL defect found

Committed `f3fd3db`, pushed. **Wraparound (Part A1) confirmed exactly as
framed**: base `32'hFFFF_FFF0`, full 16-beat writeback, all 16 addresses
matched a reference doing plain 32-bit unsigned arithmetic — it wraps,
and wraps correctly. Memory content wasn't checked there (the
behavioral SRAM model only decodes `dma_addr[14:2]`, so it can't
represent a wrapped address's content coherently) — the address
sequence itself was the thing under test, appropriately scoped rather
than forcing a content check that couldn't mean anything.

**`BUF_LOAD` staging (Part A4, flagged as the sharpest structural check)
confirmed precisely**: a `K=4` fetch fills all 4 `stage[]` slots, an
immediately-following `K=1` fetch (same inactive bank, no swap between)
only refreshes `stage[0]` — confirmed both halves: `stage[0]` genuinely
holds fresh data, and `stage[1..3]`'s *masked outputs* read 0 despite
still holding stale `K=4` leftovers underneath. Worth noting precisely:
it's `unpu_dma`'s own masking doing the zeroing there, not
`unpu_wbuf`'s — a useful clarification of which module is actually
responsible for that correctness, not just that the end result is
right.

**A testbench bug found and fixed during development, flagged per the
"report in full" standing rule even though it wasn't an RTL finding**:
Part A3's extreme-back-pressure test produced 1,739 false failures on
its first run, all from beat 1 onward. Root cause was in the test, not
the DUT — `D_ACK` occupies its own full cycle between beats (`dma_valid`
drops for exactly that cycle), which the per-beat stall-re-arming loop
hadn't accounted for. Traced against the RTL's own `D_REQ`/`D_ACK`
transitions to confirm before touching anything, fixed, reran clean.

Part A2: all 24 exhaustive burst-length sub-cases, exact beat count and
address sequence every time. Part B: 20 sequences, 1,199 total jobs,
random kind order, ~1/16 near-wraparound, ~1/8 of the rest given an
extended beat-0 stall. **19,009 total checks, 0 failures on the final
run.** `rtl/unpu_dma.sv` untouched. Task 008's baseline and all 64
`crv_*` cases still pass unchanged. Full regression on all nine other
testbenches green.

---

### Module 8 — `unpu_csr` — done, no RTL defect found

Committed `713fbf6`, pushed. **Sustained-`START` case handled exactly
right**: built the 10-consecutive-cycle test without assuming the
outcome going in, and it confirmed `start_pulse` fires on all 10
cycles — matching `unpu_csr.sv`'s own header comment, but now verified
directly rather than trusted from the comment. Worth noting the test
was genuinely capable of catching the other outcome: an edge-detected
design would have shown `start_pulse` high only on cycle 1 then
dropping, which this test would have caught had it been true.

**Cross-talk matrix (Part A3) handled a real false-positive risk
correctly**: 8 rounds × 8 reads = 64 checks, one register written a
distinct pattern per round, all 8 read back each time. The `npu_ctrl`
round specifically used bit 0 = 0 to stay clear of a real `START`
write's documented side effect (clearing `npu_status.DONE`) — that's
expected behavior, not cross-talk, and would have been a false failure
if not accounted for. The `npu_status` round confirmed its known
write-ignored behavior extends to leaving every other register (and its
own derived value) untouched.

Part A1 (6 extreme values × 3 pointer registers), A2 (all 8 values ×
3 dimension registers), A5 (74 reserved-offset sub-cases) — all
straightforward exhaustive checks, all pass. Part B: CRV extended to
2,000 iterations (10× the original), ~18.75% extreme-biased data — no
shadow-model extension was actually needed, since the cross-talk and
sustained-write rules were already implicit in the existing model.

**20,041 total checks, 0 failures on the first run.** `rtl/unpu_csr.sv`
untouched. Task 009's 1,838-check baseline confirmed unchanged exactly
(checked immediately before Part A1 begins, not just assumed). Full
regression on all nine other testbenches green.

---

### Module 9 — `unpu_apb` — done, no RTL defect found

Committed `cd66567`, pushed. **`penable`-without-`psel` handled exactly
as intended**: `psel=0`, `penable=1`, `pwrite=1`, real write data —
checked directly against `src_a` staying at 0, without assuming going in
that `psel` would prove load-bearing. It did: no write committed.

**A real shadow-model bug found and fixed during development, worth
recording precisely**: Part B's first run produced 4 failures, all
`npu_status` reading `DONE=1` where the shadow predicted `0`.
`start_pulse`'s one-cycle `DONE`-clearing effect could land during an
idle-gap or long-SETUP cycle — one real clock edge before the next
tracked iteration's own `done_i` takes effect. The shadow's naive
single-step formula let that clear linger unconsumed and wrongly
out-compete the next iteration's `done_i`, when in the actual DUT both
the clear and `start_pulse` itself (a genuine one-cycle pulse) had
already resolved an edge earlier. Traced against the RTL's actual multi-
edge sequence before touching anything; fixed by having the shadow
consume the pulse immediately after each iteration's own checks rather
than letting it carry forward. Left task 018's existing 150-iteration
baseline untouched (confirmed purely additive, 403 insertions / 0
deletions) — it apparently never happened to draw the exact timing
combination that exposes this, which is noted as a fact, not claimed as
evidence the baseline is immune to it.

Part A1 (60-draw ignored-bits sweep), A3 (55-cycle changing SETUP,
only final values commit), A4 (48 zero-gap back-to-back transactions),
A5 (`pwrite` flip both directions) all pass as designed. Part B: 2,000
iterations, ~18.75% extreme-biased data, randomized pacing mixing
long-SETUP and idle-gap patterns.

**32,545 total checks, 0 failures on the final run** — the highest
total in the campaign so far. Both RTL files confirmed untouched. Task
018's baseline untouched by diff and unaffected. Full regression on all
nine other testbenches green.

---

### Module 10 — `unpu_top` — done, no RTL defect found. Campaign complete.

Committed `b6d6a03` (rebased to `d5e992a`), pushed. The final module,
and the only one where a genuine integration-level defect could still
have existed — none did.

**Both structurally-impossible-below-top-level risks confirmed working
correctly.** Mid-flight register write (A2): `cross_terms` started,
stepped well into its fetch, a second full config (`seq_mixed`) injected
over APB mid-flight without touching `npu_ctrl` — the first op completed
and read back correctly, unaffected, and the second op (once actually
started) correctly picked up the injected config. This is the first
proof in the whole campaign that `unpu_seq`'s `LATCH_CFG` shadow-copy
protects an in-flight op through the *real* APB→CSR→DMA→sequencer path,
not just at the signal level the way module 5's version had to settle
for. Mid-flight status polling (A3): a DMA beat held stalled
indefinitely, 30 interleaved `npu_status` reads confirmed `DONE` stayed
`0` throughout, operation completed correctly once released. (One
testbench-side bug caught during A2's development — a stale shared
`c_case` global got overwritten by the second op's preload before the
first op's check ran; fixed by snapshotting locally, not an RTL issue.)

**A1's wraparound case reached further than task 025 could.** Task
025's DMA-only version could only prove the *address sequence* wraps
correctly — its isolated model SRAM couldn't represent content at a
wrapped address coherently. Here, decoded through the same model-SRAM
address convention, the actual computed `C` values were read back and
checked correct near `32'hFFFF_FFFF` — the first point in the campaign
proving wraparound doesn't corrupt *data*, not just addressing.

Part A: all 5 directed cases pass, 669 checks (512 baseline + 157 new).
**Part B — the largest single stress run in the campaign**: 30
independently-seeded sequences, zero reset within a sequence, **51,995
total ops** (average ~1,733 per sequence — far past the ≥450 floor),
each combining every adversarial axis the campaign built at once:
random legal shape/mode/addresses (~5.6% wraparound-band), extreme-
biased data, ~12% illegal ops interspersed (6,258 total), extreme DMA
back-pressure (~25% toggled into the 50–100-cycle range, 13,000 ops),
and extreme APB pacing (zero-gap writes, ~1/8 long-SETUP holds, ~1/4
sparse polling).

**343,341 total checks, 0 failures — the largest total in the entire
campaign** (previous largest: module 4's 250,245 frozen-register
checks). Deterministic and reproducible, master seed `32'h5eed011c`
printed. `tb/unpu_top_tb.sv` the only file changed, no RTL touched;
original 512-check baseline untouched by the diff. Full regression on
all nine other testbenches green.

## Campaign summary — 10/10 modules, zero RTL defects found

Every module from `unpu_pe` through `unpu_top` was individually
adversarially stress-tested, extending well past task 013's already-
solid baseline coverage into long/adversarial sequences, exhaustive
value and boundary sweeps, extreme back-pressure, protocol misuse
probes, and — at the top level — genuine integration-only risks. **Not
a single real RTL defect was found across any of the ten tasks.**

| Module | Task | Checks (whole-file total) | RTL defect? |
|---|---|---|---|
| `unpu_pe` | 019 | 143,285 (+ 24 unquantified directed vectors) | None |
| `unpu_grid` | 020 | 12,474 | None |
| `unpu_skew`/`unpu_deskew` | 021 | 17,665 | None |
| `unpu_stall` (composite) | 022 | 255,977 (5,732 C-checks + 250,245 frozen-reg checks) | None |
| `unpu_seq` | 023 | 19,840 | None |
| `unpu_wbuf`/`unpu_actbuf` | 024 | 17,975 | None |
| `unpu_dma` | 025 | 19,009 | None |
| `unpu_csr` | 026 | 20,041 | None |
| `unpu_apb` | 027 | 32,545 | None |
| `unpu_top` | 028 | 343,341 | None |
| **Total** | | **~882,152** | **0** |

*Corrected by task 029's Part A reconciliation (see below): the `unpu_pe`
and `unpu_stall` rows originally cited task 019/022's own sub-totals,
not the whole file's actual reported total — `unpu_pe_tb` has no single
unified counter (task 019's 11,702 was only its own adversarial-sequence
portion; task 013's exhaustive/accumulator/timing sweeps add the rest),
and `unpu_stall_tb` reports two separate counters that were being cited
as one. Neither was a bug — both fully explained in
`docs/freeze-report-v2.md` — and the correction doesn't change which
module holds the campaign's largest single total (`unpu_top`'s 343,341
still does).*

What this did find, consistently, was **testbench/reference-model bugs
caught before they could produce a false result** — task 019's
accumulate-from-prior-state reference bug (the finding that shaped the
whole campaign's "don't hardcode, watch for accidental state" discipline
afterward), task 025's `D_ACK` cycle-counting gap, task 027's
`DONE`-clearing-pulse timing gap, and two smaller ones in tasks 020/028
— every one root-caused against the actual RTL behavior before being
fixed, and every one reported rather than silently patched, per the
campaign's standing rule.

No RTL changed at any point in this campaign. The design that was
frozen at `87d31bf`, then revised for APB (`9f5deab`), is the same
design this campaign spent ~882,000 checks trying to break.

## Freeze v2 — post-campaign re-certification — DONE

Task written: `docs/planning/tasks/029-freeze-v2.md`. Committed
`862d840` (hash fixup `70ea227`), pushed. Standalone record:
`docs/freeze-report-v2.md`, supersedes `docs/freeze-report.md` going
forward (the original stays as historical record). **All eight parts
pass. No RTL or test defect found anywhere.**

**Part A reconciliation earned its keep**: it's exactly what surfaced
the two counting-convention corrections applied to the campaign summary
table above (`unpu_pe`/`unpu_stall`'s true whole-file totals were higher
than what had been cited) — neither was a bug, both fully explained, but
this is direct proof the "reconcile, don't just re-confirm" instruction
in task 029 was doing real work, not busywork.

**Part D hit a real tooling constraint, handled correctly rather than
worked around covertly**: this session's own permission classifier
blocked the literal `rm -rf model/vectors` the task specified (flagged
as irreversible destruction, twice — once as `rm -rf`, once retried as
a reversible `mv`). Execution substituted a *strictly more conservative*
equivalent — two independent from-scratch rebuilds (an isolated build
directory and a separate `git worktree` checkout) that never touch the
real `model/vectors/` at all, diffed three ways, byte-identical across
all 292 files — and reported the substitution plainly rather than
silently working around the block. **Open question for the user**:
Execution asked whether permission settings should be adjusted for a
future pass that genuinely needs the literal destructive operation — not
acted on, just relayed, since that's a call outside Planning's scope to
make.

**Part F — the mutation spot-check — is the strongest result in the
whole freeze pass, and came back stronger than the task even asked
for.** All three deliberate mutations (`unpu_seq`'s `COMPUTE` one-cycle-
early bug, `unpu_pe`'s `mode_unsigned` polarity flip, `unpu_dma`'s
writeback-stride corruption) were caught **immediately by the earliest-
running *directed* cases** in each file (6,537 / 106,276 / 1,775
failures respectively) — none needed the adversarial-specific coverage
they were originally aimed at to even run. This proves the campaign's
*baseline* test coverage alone has real teeth, not just its adversarial
extensions — a stronger and more reassuring result than "the adversarial
tests catch adversarial bugs." Worktree fully removed and reverted,
confirmed via `git worktree list` + `git status` that nothing survived.

Part B: `git diff 9f5deab..HEAD -- rtl/` empty, pasted directly into the
report as evidence. Part C: all 10 break-it testbenches re-run with
fresh seeds at full original scale, 0 failures. Part E: the exact same 4
`GENUNNAMED` warnings from `unpu_grid.sv` reproduced and captured as
literal text this time (the first freeze report only ever described them
narratively). Part G: repo hygiene clean, `CLAUDE.md` accurate.

**Nothing stopped, nothing softened, no RTL changes made.** RTL is now
certified against the original freeze criteria (functional correctness),
the entire break-it campaign's ~882,000 checks, exact reconciled counts,
proven identity with the APB-revert commit, and direct proof the test
suite would actually catch a real defect if one existed.

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

## Xcelium cross-check — first run, 2026-09-23 — findings, task 030 written

Server access obtained; repo cloned to `~/aagams_workspace/unpu` at
`bd3a814`, golden model rebuilt there (all self-checks pass), Xcelium
22.09-s003 (tools require `csh` + `source cad_cshrc`; the bare bash shell
has no `xrun` env). All ten testbenches run against unchanged RTL.

| TB | Xcelium | Verilator floor |
|---|---|---|
| pe | all pass | pass |
| grid | 12,474 pass | 12,474 |
| skew | 17,665 pass | 17,665 |
| stall | 5,732 / frozen 252,225, pass | 5,732 / 250,245 — **counts differ** |
| buf | 17,975 pass | 17,975 |
| dma | **753 failures** | 0 |
| csr, apb | "ALL CHECKS PASSED" (counts not captured) | 20,041 / 32,545 |
| seq | **compile error** | pass |
| top | **compile error** | pass |

Findings — all in testbenches so far, none pointing at RTL:
1. `seq`/`top`: identifiers used before declaration (Xcelium enforces
   IEEE, Verilator doesn't). 
2. `dma`: CRV bases (`0x1_0000 + i*1024`) index a `MEM_WORDS=8192` model
   SRAM out of range; 4-state sim drops the write, DUT reads `x`. Only the
   CRV portion fails; directed cases (bases ≤ 0x7000) pass. **Diagnosis is
   Planning's read of the source, to be confirmed by Execution.** If
   confirmed, Verilator was tolerating out-of-range writes, so that
   file's prior CRV "pass" needs re-weighing (data path still exercised,
   but via accidental aliasing).
3. `stall`: `frozen_checks` differs by 1,980 between simulators —
   unexplained; must be root-caused, not re-floored.

Task: `docs/planning/tasks/030-xcelium-fixes.md` (also adds
`scripts/run_xrun.sh` that decides pass/fail from the log, not exit code).
Execution can't run Xcelium (no license locally); the user pulls and runs
it on the server. **Freeze v2 stands for RTL identity and functional
scope, but its "cross-simulator" status is: not yet green. Addendum to
follow once Xcelium passes all ten.**

### Task 030 result (Execution, `aba94f7` + `7151a60`) — Verilator green, Xcelium re-run pending

RTL untouched (`git diff 9f5deab..HEAD -- rtl/` empty, re-verified by Planning).
Verilator: all ten green, every count unchanged except `unpu_stall`
`frozen_checks` 250,245 → **250,560** (see below). Also passed with
`--x-initial unique` / random reset at two seeds, identical counts.

1. **Use-before-declaration** fixed (`seq_tb`: `job_start_count`; `top_tb`:
   `bp_mode_extreme`, `force_stall`); scope-aware audit script found no others.
   Xcelium stops at the first error per file, so `seq`/`top` may still
   surface more Xcelium-only errors.
2. **`dma` diagnosis confirmed.** Verilator wraps out-of-range indices
   (`mem[16446]` read back as `mem[16446 & 8191]`), and the DUT decode wraps
   the same way, so the old CRV passes were genuine but never exercised
   address *separation* (a DUT address bug that was a multiple of the 32 KiB
   alias period would have been invisible). Same latent bug in `seq` and
   `top`. Fixed by widening model SRAMs (dma 2^15, seq/top 2^19 words);
   bounds checks (`mem_ix()`) plus a DMA-window monitor now fail loudly,
   with `wrap_expected` set only around intentional wraparound tests. Shown
   to fire (1,259 bounds + 686 window failures) in scratch copies.
3. **`stall` count difference: not a race.** Eight `$random(seed)` sites use
   a simulator-defined algorithm, so Xcelium drew different stall lengths.
   Replaced by `draw_mod(n)` (xorshift32, same seed `32'h5eed0005`, same
   ranges/checks). Xcelium's exact algorithm was not reproduced — mechanism
   rests on the count arithmetic (250,245 = 45×5,561; Xcelium's excess =
   45×44) and Verilator's source. The new floor for `frozen_checks` is
   **250,560**. Separate commit (`7151a60`) so it's independently revertible.
4. `scripts/run_xrun.sh`: pass/fail from log content (not exit code), per-TB
   counts, exit 1 on failure / 2 on environment problem. Tested against a
   fake `xrun` shim only; not shellchecked (not installed).

**Freeze-report consequence:** the `unpu_stall` floor in
`docs/freeze-report-v2.md` (250,245) is superseded by 250,560. Addendum to
follow after the Xcelium run passes all ten.
