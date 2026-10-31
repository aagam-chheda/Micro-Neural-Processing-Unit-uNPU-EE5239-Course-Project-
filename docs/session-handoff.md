# Session handoff

Everything decided before Claude Code sessions began. Read fully before your
first substantive action.

Last updated: start of Claude Code work. Update this file when decisions change.

---

## 1. What the block is

A 4×4 INT8 weight-stationary systolic array, exposed as an MMIO peripheral on a
180 nm IP-validation SoC (codename Frankenstein). The CPU writes pointers and a
start bit over APB; our DMA fetches tensors from shared SRAM without CPU
involvement; the array computes; results are written back; a DONE bit is set.

We deliver validated RTL plus a DRC/LVS-clean macro as `.lef`, `.lib`, `.gds`.

## 2. Environment

- Process: SCL 180 nm
- **SUPERSEDED 2026-09-29 — see §18.** The instructor's RTL-to-GDS flow now
  fixes the tools (Design Compiler, ICC2, Calibre, PrimeTime, Xcelium). The
  two bullets below are kept as the historical record.
- Tools available: Cadence Xcelium (sim), Genus (synth), Tempus (STA),
  Synopsys IC Compiler (P&R)
- **Not yet resolved**: which tools for DRC, LVS, formal equivalence, IR drop.
  None of the four above does DRC/LVS signoff, which is an explicit deliverable.
- Team: 5 people, ~10 hrs/week each, ~8 weeks. 400 person-hours total.

## 3. System context (Project 1 owns all of this)

- RISC-V core is **PicoRV32**, no cache, fetches almost every cycle
- 32 KB SRAM, 4 banks, at `0x0000_0000`–`0x0000_7FFF`
- Our register window: `0x4000_0000`–`0x4000_0FFF`
- SRAM arbiter shared between CPU (instruction + data), our DMA, and the SPI
  controller. **We are higher priority than the CPU** (confirmed by PM).
- SPI controller doubles as a debug backdoor that can master the internal bus —
  so our APB slave may be driven very slowly and must never hang.
- A BIST FSM will exercise hard macros post-fabrication.

## 4. Answers received from the PM

| # | Question | Answer |
|---|---|---|
| 1 | Matrices larger than 4×4? | **Not required.** "Extra marks if you can." Treat tiling as optional bonus. |
| 2 | Signed or unsigned INT8? | Deferred to us. **We chose signed**, with a SIGNED mode bit in a config register. |
| 3 | Extra registers allowed? | Deferred — he asked how many. **We requested two** (0x14, 0x18) plus a reserved range 0x14–0x3F. |
| 4 | Clock frequency? | **~50 MHz.** Confirmed adequate; we do not need more. |
| 5 | Read/write encoding on DMA port? | Deferred to us. **We proposed** `wstrb == 0` means read. |
| 6 | When is `dma_rdata` valid? | Deferred to us. **We proposed** same cycle as `valid & ready`. |
| 7 | Native or AHB data plane? | **Native**, confirmed for both: DMA↔SRAM master port *and* CPU↔NPU register port. APB is out. Resolved — see §5. |
| 8 | Worst-case arbiter grant latency? | No number. We co-design the arbiter with the SoC team; NPU has higher priority. |
| 9 | How does BIST reach us? | PM suggested over the bus. We agreed; no extra wrapper or test port needed. |
| 10 | Scan pins for tester access? | **None.** No scan chain, no `scan_en`/`scan_in`/`scan_out`. Not in scope for this project. |
| 11 | Is the `unpu_top` port list frozen? | **Negotiable**, not frozen — supersedes the "frozen" framing used everywhere below and in CLAUDE.md/execution.md (see §12). |

### Why we chose signed (Q2)

A layer whose weights cannot be negative cannot learn. Standard INT8
quantisation uses symmetric signed weights so the zero-point terms cancel.

**Consequence worth remembering:** under signed interpretation the mandated
saturation test (`0xFF × 0xFF`) computes `(−1) × (−1) = 1`, four times over,
totalling 4. That would pass on a 4-bit accumulator. The test only proves what
it is meant to prove in unsigned mode. Hence the mode bit, and we run the test
both ways.

## 5. Q7, AHB vs native — RESOLVED (native), CPU-facing half later reverted to APB — see §17

The PM confirmed **native** for both interfaces: the DMA↔SRAM master port and
the CPU↔NPU register port. APB is no longer part of the design. This
validates the argument below (kept for the record) and means `unpu_apb.sv`,
wherever it was going to live, becomes a native-protocol slave FSM instead —
a redesign, not a rename. See §12 for the full knock-on effect on the plan.

**2026-09-22: the CPU↔NPU half of this decision was reversed** — a later
cross-team conversation (PM + SoC-top team) landed on APB after all, for
that interface only. The DMA↔SRAM half below stands unchanged. Full
detail in §17; this section is kept as-is as the historical record of
what was decided and why, at the time.

### Original argument (superseded by the answer above, kept for context)

The port list in the brief is labelled "Native Master Interface to SRAM" and
consists of `dma_addr`, `dma_wdata`, `dma_rdata`, `dma_wstrb`, `dma_valid`,
`dma_ready`. None of those are AHB signals — AHB needs `HADDR`, `HWRITE`,
`HTRANS`, `HSIZE`, `HBURST`, `HWDATA`, `HRDATA`, `HREADY`, `HRESP`.

That port list is, signal for signal, **PicoRV32's native memory interface**.
That interface's documented convention also answers Q5 and Q6 exactly as we
proposed: `mem_wstrb == 0` means read, and read data is valid in the same cycle
as `mem_ready`.

The "Native/AHB Data Plane" label in the block diagram sits on the CPU-to-arbiter
arrow, not on our DMA-to-arbiter arrow.

**Our proposal to the PM:** if the fabric must be AHB, Project 1 puts a
native-to-AHB bridge on the arbiter side rather than inside our macro. Our pins
freeze at hardening; their fabric does not. Moving us to AHB would add ~14 pins,
change the floorplan pin budget, and cost 20–30 hours.

**Until this is settled, do not write the DMA master.** Everything else can
proceed.

## 6. Decisions already made

| Decision | Rationale |
|---|---|
| 32-bit partial sums throughout | Un-overflowable for any layer; matches SRAM word width. Accepts 512 wires of vertical routing inside the array. |
| Build the de-skew bank (192 flops) | Alternative is skewing write addresses, which produces out-of-order writes and 4× the write traffic on a contended bus. |
| No hardware requantiser in v1 | ~10% of macro area for something the brief never asks for. Firmware does it. |
| Shift-down weight load, reverse row order, double-buffered | Avoids 128 broadcast wires. Costs 4 cycles, hidden by double-buffering. |
| Three FSMs, not one | APB must answer the bus regardless of compute state; DMA must wait on the arbiter without freezing sequencer counters. |
| One global `array_en`; no flow control inside the array | Partial freezing shears the wavefront into plausible wrong answers. |
| Symmetric weights, zero-point work in software | Keeps the PEs a plain integer dot product. |
| Build the 4-state DMA FSM first, optimise later | Collapsed version is much harder to debug while the arbiter is also under test. |
| Single-stage PE at 50 MHz | Two-stage requires a matching register on the activation path, doubles latency 7→14, and changes every timing number. |
| RTL in SystemVerilog, synthesisable subset only | Brief says Verilog; PM confirmed SV is acceptable. Constrained to the synthesisable subset so the Genus→IC Compiler handoff stays clean. |
| Matmul shape is A[M×K] × B[K×N] = C[M×N] | PM-specified. All of A, B signed int8; C is int32, **no requantization in hardware** — firmware's job, consistent with the existing "no hardware requantiser" decision above. |
| M, N, K each ≤ 4 at runtime, never > 4 | PM-confirmed. No tiling needed — the array's fixed 4×4 geometry covers every case. Sub-4 K/N falls out almost for free: zero-load unused weight rows/columns (`weight_reg` already resets to 0) and only write back the real N columns; no change to the timing contract or skew/de-skew depths. |
| CSR is 8 registers: `src_A`, `src_B`, `dest_C`, `dim_M`, `dim_N`, `dim_K`, `npu_ctrl`, `npu_status` | PM-directed. Supersedes the old 5-fixed-plus-2-optional register map. Register window extends past 0x18 — PM confirmed that's fine. Offset assignment (0x00–0x1C sequential) is Planning's proposal, not yet PM-confirmed — see the architecture snapshot in `docs/planning/unpu-architecture.html`. |
| No scan chain, no scan pins | PM-confirmed — not in scope for this project. Step 15 (scan chain insertion) is removed from the plan entirely. |

## 7. Still open

All four questions that were blocking RTL work (native vs. AHB, extra CSRs,
scan pins, port-list-frozen) are now answered — see §4 and §12. What's left:

1. Tools for DRC, LVS, formal equivalence, IR drop. (DRC/LVS resolved
   2026-09-29: Calibre, see §18. Formal equivalence and IR drop still open.)
2. Who owns the arbiter RTL, us or the SoC team.
3. MNIST network shape. A 784→64 first layer needs 49 KB of INT8 weights; the
   whole SoC has 32 KB. The reference network does not fit. Options: shrink to
   784→16 (12.5 KB, still ~92%), downsample the input to 14×14, or stream
   weights over SPI.
4. CNN or MLP for the signoff test — the block diagram says CNN, the brief text
   says only "quantized MNIST digit".
5. SRAM memory layout — deliberately unfilled until the network size is decided.
6. **A final project document is coming from the PM** — per the user, hold off
   on any new design/planning work until it arrives; it may supersede some of
   §12 below. Finishing already-pending documentation/bookkeeping (this
   update) is fine; drafting new tasks is not, until that document lands.

## 8. Known errata in the notebook

The notebook was written before the PM's answers arrived and **still has not
been reconciled** — checked again as of §12's update, still stale. It is now
considerably further out of date than originally scoped:

- §13 still lists ~12 open questions; nearly all are now answered (§4).
- §16's hour budget and cut list assume tiling might be required. It is not.
- §12.2's pipelining discussion is now moot at 50 MHz.
- The entire control-plane discussion (§B1, the pinout tables, `MATRIX_CFG`,
  the two-phase APB FSM description — 43 APB/CSR/register references total)
  describes a design that no longer exists: control is native, not APB, and
  the register map is the 8-register `src_A`/`src_B`/`dest_C`/`dim_M`/`dim_N`/
  `dim_K`/`npu_ctrl`/`npu_status` list in §12 below, not `MATRIX_CFG`.

**Deliberately not reconciling it right now.** This is a full-section rewrite,
not a documentation-sync edit, and the user is waiting on a final project
document from the PM that may change things further — reconciling now risks
doing it twice. Treat `docs/unpu-notebook.html` as unreliable for anything
touched by §4, §7, or §12 of this file until that document lands and the
notebook gets a proper pass.

## 9. Plan shape

Eight weeks. Front end parallelises across five people; the back end is
sequential and supports about three. Three gates:

- **End W2** — identity test passing on the bare grid, weights forced by the
  testbench, no DMA, no APB, no FSM.
- **End W4** — RTL freeze, plus a real critical path number from a deliberately
  discarded trial hardening pass run in W3.
- **End W7** — STA clean, DRC/LVS clean, abstracts generated.

W8 is real buffer, not finishing touches.

**Build order:** PE → grid → identity → skew banks → sequencer → DMA → APB.
Outward from the arithmetic, one ring at a time. Teams that start from the bus
interface spend three weeks before they can multiply two numbers.

## 10. First tasks

1. Reconcile `docs/unpu-notebook.html` with §4 and §7 of this file.
2. Write `rtl/unpu_pe.v` and its directed unit test (20 vectors: max positive,
   max negative, zero weight, weight-load-while-computing).
3. Stand up the Genus flow on a trivial design — this is a full week of work and
   is the most commonly deferred, most commonly fatal task on the schedule.
   (2026-09-29: the flow is now Design Compiler, not Genus — see §18. The
   "trivial design first" advice stands.)

## 11. Standing rule — commit and push per completed task

**Every completed task gets its own commit and push, immediately.** Do not
batch several tasks into one commit.

**Why:** a lost or wiped machine only loses uncommitted work. Commit-per-task
minimizes that window to at most one in-progress task, instead of however many
happened to accumulate before the next push. Not hypothetical — we already
recovered from exactly this scenario once, and the batched commit (tasks
001-003 together) was the one thing that could have gone wrong, even though it
didn't that time.

**Applies to:** Execution, since Execution is the session that writes code and
lands tasks. Read this before your first commit.

## 12. PM Q&A round 2 — architecture snapshot

Answers received directly from the user, sourced from a PM conversation.
Full detail in §4 (updated), §6 (decisions table, updated), §7 (still-open
list, updated). This section is the consolidated summary.

**Resolved:**
- Q7 — native interface, both DMA↔SRAM and CPU↔NPU. APB is out (§5).
- Extra CSRs — 8 registers, PM-directed list, window extends past 0x18 (§6).
- Scan pins — none. No scan chain in scope (§6). Step 15 removed from the plan.
- Port list — **negotiable**, not frozen. This contradicts CLAUDE.md's current
  hard constraint ("the `unpu_top` port list is frozen... requires instructor
  approval") and `docs/roles/execution.md`'s "do not add ports" line. Both are
  stale and outside Planning's write scope (`docs/planning/`,
  `session-handoff.md` only) — flagged to the user, and to Execution
  separately, for a fix in the files Execution can write.
- Matmul shape: A[M×K] × B[K×N] = C[M×N], signed int8 in, int32 out, no
  requantization in hardware. M, N, K each ≤ 4 at runtime (§6).

**A full architecture snapshot** (SoC context diagram, uNPU block diagram,
proposed CSR table, build-status-against-plan) was published as an artifact
and a static copy checked into the repo at
`docs/planning/unpu-architecture.html` for the record. Two assumptions in it
are flagged as unconfirmed, not PM fact: the CPU→uNPU register path bypassing
the SRAM arbiter entirely (inferred from the address ranges), and the
sequential 0x00–0x1C CSR offset assignment (Planning's proposal).

**Status as of this update:** the user is waiting on a final project document
from the PM. Per their instruction, no new design or planning work — task
drafting included — until it arrives. This section, and the rest of this
update pass, is closing out documentation that was already pending, not new
work.

## 13. PM-supplied sequencer FSM — analysis

Filed verbatim at `docs/pm/sequencer-fsm.txt`. This is the PM's own sketch
of the main sequencer FSM (weight load → input load → compute → output
readback → writeback), separate from the DMA handshake FSM and the native
slave FSM. 7 states: `IDLE`, `LOAD_WEIGHTS`, `LOAD_INPUT`, `COMPUTE`,
`READ_OUTPUT`, `WRITE_OUTPUT`, `DONE`.

**Checked against the timing contract — consistent, not a conflict.** First
pass looked like a 1-cycle discrepancy (`COMPUTE` stops after `M+K+N-2`
cycles vs. our `M+7` total-cycle figure), but those are two different kinds
of quantity, not two competing answers to the same question:

- Our contract's "`M+7` total cycles" is an inclusive *count* (cycles 0
  through the last valid cycle, inclusive).
- The PM's `M+K+N-2` is a cycle *index* — literally the same "cycle"
  variable their own injection rule uses (`inject A[i][k] when i+k==cycle`,
  which is exactly our `A[m][k]` enters at `m+k`, with `i=m`).

Worked against the **already-passing** task 004/005 result (`cross_terms`,
M=4, K=N=4): last row (m=3) valid at cycle `3+7=10`. PM's formula for the
same case: `M+K+N-2 = 4+4+4-2 = 10`. They match exactly, verified against
real passing RTL, not just algebra.

**One implementation trap to carry into the step 8 task prompt, once
written:** this only holds if `unpu_seq`'s stop condition checks the *same*
registered cycle counter, at the *same* point in the cycle, as the
injection rule — i.e. "stop when `cycle == M+K+N-2`", not a separately
free-running tick count that could land one cycle off. Worth an explicit
directed check in `unpu_seq`'s testbench.

**Other structural notes, all consistent with what's already decided:**
- `LOAD_WEIGHTS` before `LOAD_INPUT` — matches notebook §7.1's `W_FETCH`/
  `W_LOAD` before `A_FETCH` order.
- No tiling/`NEXT_TILE` state — **directly confirms** the M/N/K≤4,
  no-tiling decision (§6, §12). Where I previously guessed `NEXT_TILE`
  would "shrink to trivial," the PM's own FSM shows it's just gone.
- No `LATCH_CFG`/`ERROR` states shown — likely omitted for sketch brevity,
  not necessarily a rejection of config-legality checking or error
  handling. Don't assume either way without asking.
- `READ_OUTPUT` and `WRITE_OUTPUT` as two separate states, vs. the
  notebook's single `WRITEBACK` — minor granularity difference (capture
  from the array vs. DMA burst to SRAM), doesn't conflict with the
  existing skew→grid→de-skew→DMA architecture. Worth matching this
  two-state naming when `unpu_seq` actually gets built.
- `K x N loaded` / `M x K loaded` / `M x N values` match `src_B`'s [K×N],
  `src_A`'s [M×K], `dest_C`'s [M×N] exactly.

**Net effect:** this substantially de-risks step 8 (sequencer) — the PM's
own FSM shape is now available and lines up with our architecture.

## 14. Hold lifted; constrained random verification is now standing policy

The user has confirmed enough is known to proceed — task prompts for steps
8 onward can be written. Full detail on what changed is in
`docs/planning/plan.md` (Q&A section, new "Verification methodology"
section, and per-step acceptance criteria).

**New standing rule: every module gets extensively tested from here on,
including but not limited to CRV** — randomized data (full-range signed
int8), randomized shape (M/N/K each 1–4), and randomized timing where a
module has timing degrees of freedom, self-checked against `model/golden.c`
or the timing contract, seeded and logged reproducibly. Directed tests stay
— CRV is additive, not a replacement.

**Why:** the user's own directive, given directly — extensive testing
including CRV is now required for all modules. No further rationale given;
treat as authoritative.

**How to apply:** every task prompt for steps 8–16 must fold this into its
acceptance criteria explicitly (`docs/planning/plan.md` already does this
per-step). Steps 1–7 were built directed-only, before this directive —
tracked as "Verification debt" in `plan.md`, not retroactively blocking,
but flagged for the step 16 freeze checklist to decide on explicitly
rather than let slide.

## 15. RTL FROZEN — 2026-09-15

Steps 8 through 16 all landed (tasks 006–015), including one unplanned
but necessary detour: `unpu_seq` (task 006) had been built against
direct-forced data as a stand-in, and turned out to have no way to
actually drive the real `unpu_dma`/`unpu_wbuf`/`unpu_actbuf` built in
tasks 007–010. Found while starting to plan top-level integration,
resolved by revising `unpu_seq` itself (task 011, un-freezing it for
that one task) rather than building a shim around it that would have
left the buffers unused — full reasoning in
`docs/planning/tasks/011-seq-revision.md`. Top-level integration
(`unpu_top`, task 012) then wired cleanly on the first full run.

The user also decided the verification debt flagged in §14 above gets a
**full retrofit**, not accepted as residual risk — task 013 closed it;
every module now carries CRV coverage, zero RTL bugs found in the
process.

Freeze itself (task 015, plan.md step 16) ran six parts at the user's
explicit request for maximum thoroughness — full regression against
recorded floors, a fresh-seed re-run of every CRV suite, a from-scratch
golden-model rebuild, a whole-design lint sweep, and a repository hygiene
audit — on top of the standalone `docs/freeze-report.md` sign-off record
that resulted. All passed. Frozen at commit `87d31bf`.

**Freeze is functional only** — no timing/STA, no DRC/LVS, no firmware.
Steps 3/5 (back-end, PDK/server access) and firmware remain open,
tracked in `plan.md`, and don't reopen this freeze unless back-end work
later reveals a real problem (accepted risk, decided early — see
`plan.md`'s "Freeze gate" section).

One documentation finding surfaced at freeze and not yet fixed: CLAUDE.md's
"Repo layout" section still references `.v` extensions and a nonexistent
`unpu_apb.v`, and doesn't list `unpu_slave.sv`. Small follow-up task
written (`docs/planning/tasks/016-claude-md-repo-layout.md`), not a
design question.

## 16. Address-window question — partially resolved, pending a cross-team conversation

`docs/planning/plan.md`'s open question 5 (does the `0x4000_0000`–
`0x4000_0FFF` window still apply, and who decodes it, now that the
CPU↔NPU interface is native) got two rounds of PM answer, 2026-09-17,
both relayed by the user.

**First answer** confirmed `unpu_slave`'s assumption #1 exactly as
already built and frozen (task 010): an external decoder filters CPU
traffic before it reaches us; `csr_sel = mem_addr[11:2]` with no prefix
check is correct. No RTL change, nothing to reopen from that part.

**Follow-up answer** — whether the PM's "npu_ready...should start"
phrasing meant the per-transaction `valid` already built, or a separate
enable signal — came back describing one *possible* three-signal
protocol instead: (1) an "enabled" signal meaning Pico wants to talk to
the NPU, (2) the processor writes the required registers over the next
few cycles, (3) the processor asserts a separate **"ready"** signal,
distinct from the register writes, telling the NPU to start computing.
The PM was explicit this is only one option, not a confirmed spec:
"There are multiple ways of doing this... I'd recommend you talk to the
SoC team to figure out a common ground."

**This is now a cross-team decision, not something Planning/Execution
can resolve alone.** What's built and frozen already achieves the same
three things — target ID via address decode, register writes for
config, an explicit start trigger — entirely through the memory-mapped
register interface: START is `npu_ctrl` bit 0, a write-1-to-pulse
register write, not a discrete signal. Functionally equivalent to the
PM's sketch, not mechanically identical. If the SoC team accepts a
register-write START: zero RTL changes, freeze stands. If they require
a discrete START pin: one new `unpu_top` input port, small but real, and
would reopen the freeze for it. Not blocking anything now; tracked in
`docs/planning/plan.md`'s "Open questions" section until the user has
that conversation and brings back an answer.

**Update, 2026-09-20:** the user chose not to wait — the SoC-team
conversation is scheduled for tomorrow, but they asked to implement the
PM's sketch now as a provisional interface, so there's something
concrete to test in the meantime. Task written and dispatched:
`docs/planning/tasks/017-interim-enable-start.md`. This reopens the
freeze, scoped to `rtl/unpu_top.sv` only — two new ports
(`npu_enable`, `npu_start_req`) that gate/combine existing signals,
without touching any already-frozen submodule. The existing `npu_ctrl`
register-write START path is kept working alongside the new pin, not
replaced, so this doesn't have to pre-guess which mechanism the SoC
conversation settles on. Expect a follow-up task after that
conversation, to either confirm, adjust, or revert this.

**Landed, 2026-09-20:** committed `5767bfc`, pushed, `rtl/unpu_top.sv`
the only file changed under `rtl/`. Full detail and test results are in
`docs/planning/plan.md`'s open-question-5 entry, not duplicated here —
this note exists so a reader of this file's chronological history
doesn't have to guess whether the provisional task above ever actually
landed. **Still provisional** until the SoC-team conversation happens;
this is what's live in the meantime.

## 17. SoC-team conversation happened — CPU↔NPU interface reverts to APB

2026-09-22, the user, the PM, and the SoC-top team met and decided: the
CPU↔NPU register interface goes back to APB. This resolves what §16's
provisional task (017) was a placeholder for, and answers it differently
than either signal-shape option that task's own text anticipated (a
per-transaction native `valid`, or a discrete enable/start pin) — APB
was the actual answer all along, not a variant of native.

**Scope: CPU↔NPU only.** The DMA↔SRAM master port (`unpu_dma`'s native
port) is unaffected — §5's native resolution stands for that half. If
this scope understanding turns out wrong, that's a much bigger change
than task 018 below is scoped for.

**Task 017's provisional `npu_enable`/`npu_start_req` protocol is fully
superseded**, not layered under APB — APB's own `psel`/`penable`
handshake already does what those two signals were approximating
(`psel` = target identification, the role `npu_enable` was standing in
for; `penable` qualifies real access, and START stays an ordinary
register write, same as it always was — no discrete start signal needed
at all). Both signals are removed entirely in task 018.

**A genuine irony worth noting**: `docs/unpu-notebook.html` §05 B1 (the
original APB slave design) was flagged stale in §8 above the moment the
native pivot happened ("describes a design that no longer exists").
That flag was correct *then*. As of this reversal, §05 B1 is relevant
again — not stale, not to be "un-flagged" retroactively (§8 stands as
the historical record of when and why it was marked stale), but worth
knowing that a document once marked obsolete became current again. This
is exactly the kind of thing that makes wholesale-editing a stale
document risky versus flagging it and moving on, which is why §8 never
rewrote or deleted that section in the first place.

**What doesn't change**: the 8-register map, its offsets, and all
register semantics (`unpu_csr.sv`, task 009) — this is a bus-transport
swap, not a register-map revision. `unpu_csr` was deliberately built
bus-protocol-agnostic specifically so a change like this wouldn't
cascade into it.

Task written, DMA↔SRAM-native scope confirmed by the user, sent to
Execution 2026-09-22: `docs/planning/tasks/018-apb-revert.md`. Reopens
RTL freeze again (third time: task 017, now task 018), scoped to
`rtl/unpu_top.sv`
(rewritten), a new `rtl/unpu_apb.sv`, and the retirement of
`rtl/unpu_slave.sv`/`tb/unpu_slave_tb.sv` — no other module touched.

**Landed, 2026-09-22:** committed `9f5deab`, pushed. Scope confirmed
exactly as intended — `unpu_csr.sv` and `unpu_dma.sv` both untouched
(verified by reading, not assumed), only `unpu_top.sv` changed besides
the new `unpu_apb.sv` and the deleted `unpu_slave.sv`. Full detail and
test results in `docs/planning/plan.md`'s open-question-5 entry, not
duplicated here.

---

## 18. Back-end flow and SCL kit — fixed 2026-09-29

Source: the instructor's RTL-to-GDS flow (handwritten, photographed by the
user; the instructor said to follow it, some steps may be omitted). Kit and
tool facts below come from the user's server sessions (pasted output);
Planning did not observe the server directly. Nothing has been run in the
back-end yet.

### 18.1 The flow

| Step | Tool |
|---|---|
| RTL simulation | Xcelium 22.09 |
| Synthesis | Design Compiler (`dc_shell` T-2022.03-SP5) |
| DFT | **Omitted** — PM confirmed no scan (§4 Q10, §6) |
| Pre-layout gate-level simulation | Xcelium, on the DC netlist |
| Floorplan, power, place and route, chip finishing | ICC2 (`icc2_shell` U-2022.12-SP3) |
| DRC and LVS | Calibre 2022.4_37.20 |
| STA signoff | PrimeTime (`pt_shell` T-2022.03-SP2) |
| Post-layout simulation | Xcelium |
| Final DRC and LVS clean, tapeout | |

This replaces the §2 tool list. Genus and Tempus are installed but are not
part of the flow. Pre- and post-layout gate-level simulation did not exist
in our plan before; they are new verification work. Formal equivalence
(Formality V-2023.12-SP4 and Conformal are installed) and IR drop remain
open, and the instructor's flow does not list them.

### 18.2 Metal stack and corners

- **4 metal layers (4M1L)**, a course requirement stated by the user. The
  directory is spelled `4M1IL` under `stdcell/fs120/`, `4M1L` elsewhere.
- Standard cells: `tsl18fs120` (FS120), 1.8 V svt only, 10-track.
- Only two libraries exist, no typical:
  `tsl18fs120_scl_ss` (process 1.2, 125 C, 1.62 V) for setup, and
  `tsl18fs120_scl_ff` (process 0.8, -40 C, 1.98 V) for hold.
- Parasitics: TLUPlus **typical only**
  (`SCL_TLUPLUS_4M1L_TYP.tlup`). No min/max RC.

### 18.3 Where things are on the server

Kit root: `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/`

| Item | Path under the kit root |
|---|---|
| `.lib` / `.db` (ss, ff) | `stdcell/fs120/4M1IL/liberty/lib_flow_{ss,ff}/tsl18fs120_scl_{ss,ff}.{lib,db}` |
| Tech LEF, cell LEF | `stdcell/fs120/4M1IL/lef/scl18fs120_tech.lef`, `scl18fs120_std.lef` |
| Std-cell GDS, CDL | `stdcell/fs120/4M1IL/gds`, `cdl` |
| Simulation models | `stdcell/fs120/4M1IL/verilog/vcs_sim_model` |
| Milkyway (old ICC format) | `stdcell/fs120/4M1IL/milkyway/SCL_4LM/` |
| Synopsys tech file, TLUPlus, GDS map | `digital_pnr_kit/snps/non_rh/4M1L/` (`SCL_4LM.tf`, `SCL_TLUPLUS_4M1L.map`, `SCL_TLUPLUS_4M1L_TYP.tlup`, `icc_gds_out_4LM.map`) |
| Calibre DRC/LVS/PEX setup | `pdk/cdns/sclpdk_v3/HOTCODE/techs/generic/calibre/` |
| Documents | `doc/` (README, DRM, std_cell_guidelines, chip_finishing, io_guidelines) |
| SRAM cuts | `memory/spram`, `memory/dpram` (not used; the macro has no SRAM) |

Standard-cell rules (`doc/std_cell_guidelines.pdf`):
- **Don't-use cells:** `slnht*`, `skbrb*`, `slbhb*`, `slnhn*`, `slnln*`,
  `mx08d*`.
- No tap cells needed. Fillers: `feedth`, `feedth3`, `feedth9`.
- P&R GDS holds abstract layer data only; it must be merged with the
  standard-cell GDS for the final deliverable.

### 18.4 Server setup

- Login shell is csh. Per session: `source ~/cad_cshrc`, then
  `source ~/synopsys_cshrc`. For Calibre, `~/mentor.cshrc` sets the path
  correctly; the path line in `cad_cshrc` does not resolve.
- `starrc` and the classic `icc_shell` are not on the PATH.
  `icc2_lm_shell` is under Fusion Compiler V-2023.12-SP4.
- csh has no `2>/dev/null`; use `|&` or `>&`.
- **Do not use `$FOUNDRY`.** `cad_cshrc` points it at
  `/home/Cadence_tools/FOUNDRY`, a generic TSMC-style 0.18 um kit
  (`tpz973g*.lib`, `all.lef`, `t018s6m*` RC). It is not the SCL process.

### 18.4a Library facts read from the ss and ff `.lib` (user's server run, 2026-09-30)

- The ss library `tsl18fs120_scl_ss` has 534 cells.
- Units, ss: time 1 ns, capacitance 1 pF (`capacitive_load_unit(1, pf)`),
  voltage 1 V, current 1 uA, resistance 1 kohm, leakage power 1 pW.
- ff library: time 1 ns and capacitance 1 pF, the same as ss.
- Plain buffers: the `buffd*` family (`buffd1`, `2`, `3`, `4`, `7`, `da`).
  `buffd2` was inspected: input `I`, output `Z`, function `"I"`, area 18.82.
  The `buftd*`/`invtd*` and `bufbd*`/`invbd*` families were not inspected
  (probably tri-state and balanced/clock buffers, from the names only).
- Latch cells (`lachq4`, `lanhq1`) and scan-type flops (`sd*`, `se*`) exist in
  the library, so the latch check on the DC netlist matters.
- The don't-use pattern `slbhb*` matches at least one cell (`slbhb2`);
  `slnhq2` and `slnlb2` do not match their patterns (`slnhn*`, `slnln*`).
- The SDC now drives the inputs with `buffd1`, pin `Z` (`set_driving_cell
  -lib_cell buffd1 -pin Z`); DC accepted it on 2026-10-08, so `buffd1` has a
  `Z` pin. The drive strength is an assumption until the SoC team says what
  drives the inputs.

### 18.5 Open items

- ICC2 needs a library built from the SCL LEF and tech file (Milkyway is the
  older format). `icc2_lm_shell` should do it; untested.
- Which Calibre deck runs DRC and LVS, and how it is invoked, is untested.
- Pre-layout gate-level simulation: RESOLVED 2026-10-12 for the top-level
  testbench, see 18.7. Not yet done: post-layout GLS with an SDF, and the unit
  testbenches (they cannot run on this netlist, which uniquifies `unpu_pe` into
  `unpu_pe_0` to `unpu_pe_15`).
- `constraints/unpu_top.sdc` (task 034, `2f271c3`, extended 2026-10-08) has been
  read by DC through `constraints/pm_unpu_top.sdc`, its identical twin (see
  18.6). It has not been read by ICC2 or PrimeTime. Its interface budget,
  driver, wire load and limits are deliberately harsh assumptions; only the
  20 ns clock period and the 1 pF output load (instructor) are facts.
- Answers received 2026-10-14 (reported by the user, not yet confirmed in writing):
  - Pads: none. The macro is a bare macro with pins; ICC2 places pins on the macro
    boundary (no I/O ring, no pad cells, no pad ESD in scope); power pins (VDD/VSS)
    still have to be brought out.
  - Deliverable: the final deliverable is a GDS. A DUMMY LEF has to be handed to the
    top-level team now; a teammate is working on it. (A dummy LEF needs at least the
    macro size and the pin names, layers and rough positions, so the pin and size
    questions below block it.)
  - "Clean" means DRC clean, LVS clean AND timing signoff.
  - Clock: the macro builds its own clock tree (CTS inside the macro).
  - Reset: the top-level team uses a synchronous `rst_n` (see the Reset bullet at the end
    of this part). Whether it comes straight from a flop and whether the macro should
    include a reset synchronizer are not known.
  - Interface timing (input/output delays, drivers, loads): not known yet; the top-level
    team is working on it. The constraints keep their assumed values until then.
- Still to ask the PM: how the macro `.lib` is produced and by whom; pin side, order,
  spacing and metal layers; how VDD/VSS come out (pins or ring, which layers); any
  maximum size, aspect ratio or area budget; clock insertion-delay or skew limits at
  the macro clock pin.

### 18.6 First DC run of the PM script (user's server run, 2026-10-08)

The user ran `constraints/pm_dc_script_unpu.tcl` (reads `constraints/pm_unpu_top.sdc`) in their
own clone, ss corner. The reports are on the server and in the user's scratch copy
(`syn/out/pm_flow_server/`, git-ignored); this section keeps the facts, and
`docs/planning/dc-run-2026-10-08.md` holds the same run as quick-reference tables.

- The script completes. `set_operating_conditions -library tsl18fs120_scl_ss
  tsl18fs120_scl_ss` and `set_wire_load_model -name 140000` both resolve (the PM
  script's SCL branch works), as do `buffd1`/`Z`, `set_max_transition` and
  `set_max_capacitance`. `write_sdc` shows every constraint applied.
- Worst setup path (the only one reported): combinational `paddr[2]` to
  `prdata[4]`, slack +0.02 ns of a 4.5 ns budget (20 - 7 - 7 - 1.5). DC stops
  once slack is positive, so this is not margin. Register-to-register paths were
  not reported.
- Area: total 454,915 um2 (0.455 mm2), cell area 441,671 um2; 2,465 flops
  (628 in `unpu_seq`, which holds the 512-bit `c_dst`; 267 each in `unpu_wbuf`,
  `unpu_actbuf`; 768 in the 16 PEs).
- Power (6.57 mW dynamic, 94% ideal clock network, no switching annotation) is
  not meaningful yet.
- Netlist: no don't-use cell appears; 16 `assign` statements and escaped names
  remain because `change_names` is not run (known script defect, matters for
  ICC2 and gate-level simulation).
- The PM's `set_input_delay 0 [all_inputs]` also lands on the `clk` port;
  harmless in DC, may warn in PrimeTime.
- Constraint history (all in `constraints/`): PM script split into a pure SDC plus
  flow script; clock transition, setup/hold uncertainty, driving cell, wire and
  output loads, max limits added; assumptions then made harsh on request; the
  PM's `set_drive 0` / `set_load 0` removed; `unpu_top.sdc` kept identical.
- Reset: the unpu RTL uses an asynchronous active-low reset in all 28 `always_ff`
  blocks (chosen by Planning/Execution in tasks 001 to 009; the PM never specified
  it). The user reports (2026-10-08, second-hand, not yet confirmed in writing)
  that the top-level SoC team uses synchronous resets. Not a conflict: an
  async-reset flop can be driven by a reset that the SoC releases synchronously.
  To confirm with the SoC team: `rst_n` comes straight from a flop (no
  combinational logic that could glitch and reset the macro asynchronously),
  and it is released synchronously to `clk`. Changing the macro to a
  synchronous reset is not needed for compatibility and would reopen the RTL
  freeze.

### 18.7 Pre-layout gate-level simulation (user's server run, 2026-10-12)

Result: PASS. `tb/unpu_top_tb.sv` (unchanged) run against the DC netlist of
18.6 with the SCL cell models: 343,341 checks, "ALL CHECKS PASSED", 0 FAIL / `*E` /
`*F`, `$finish` at 138,350,796 ns, 1 min 57 s wall time. The check count equals
the RTL run of the same testbench (`bash scripts/run_xrun.sh top`), which is the
control and also passed.

- Tool: Xcelium 22.09-s003 (`xrun`), after `source ~/cad_cshrc`. Run from the repo
  root, because the testbench opens `model/vectors/...` by relative path; the
  vectors are git-ignored and must be generated first
  (`gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden`).
- Files: `syn/out/pm_flow/unpu_top.dc.v` (the netlist), the single combined model
  file `.../4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v` (do not also pass the
  per-cell files, they are the same modules), and `tb/unpu_top_tb.sv`.
- Flags that passed: `-sv -64bit -access +r -timescale 1ns/1ps -notimingchecks
  -top unpu_top_tb`. The cell delays from the models' specify blocks were ON; the
  setup/hold checks were OFF; there is no SDF yet.
- Benign messages: 24 `CUVWSP` (DC leaves unused output ports unconnected) and one
  `UDPRDT` (redundant row in a cell model). No unresolved cells.
- VCS (U-2023.03, licensed) was tried first and does not compile the testbench:
  `ICPD` errors because `mem` and `bp_rng` are written by an `always_ff` and by
  other processes (Xcelium accepts it). Not worked around in the repo; the
  testbench is frozen. A scratch `sed` copy (`always_ff` to `always`) would
  compile; not needed since Xcelium works.
- Caveat: this proves function only. It says nothing about setup/hold; that is
  post-layout PrimeTime and an SDF-annotated run.

Parked, not important: the same run with `-nospecify` (all cells zero delay)
FAILS ("DONE never observed", `mem C = x`). Waves show the sequencer goes
IDLE to LATCH_CFG to W_FETCH and stays there, and `dma_valid` never rises. The
leading, unproven theory is a zero-delay race: `job_start` is a one-cycle
combinational pulse (`state == W_FETCH && !job_issued`) and the DMA flop may see
it already dropped when `job_issued` and the DMA flop update in the same time
step. The netlist and the RTL are not implicated (RTL control passes, and the run
with cell delays passes). Do not use `-nospecify` for GLS of this design. The
check that would confirm it: in `u_seq` and `u_dma`, `job_start` high for one
cycle but `u_dma` `state` staying 0 afterwards.

### 18.8 DC cleanup round and the input-transition decision (user's server run, 2026-10-14)

Done in the user's own clone after the 18.6 run: the same script, then reports,
`change_names -rules verilog -hierarchy`, and a rewrite of the outputs.

- New files (git-ignored, in the user's `syn/out/pm_flow/`): `unpu_top_cn.dc.v`,
  `unpu_top_cn.sdc`, `unpu_top_cn.ddc`; these are the hand-off to ICC2 (not the
  un-renamed ones). `change_names` gave one harmless `UCN-4` warning. Escaped-name
  lines went from 9,142 to 0 and `assign` statements from 16 to 0.
- GLS on `unpu_top_cn.dc.v`, same command as 18.7: 343,341 checks, ALL CHECKS
  PASSED, finish at 138,350,796 ns, identical to the original netlist.
- Register-to-register timing: worst slack +1.80 ns (five reported paths, all the
  PE multiply-accumulate path, a ripple-carry adder), at the harsh settings and
  before layout (ideal clock, wire-load model). The single +0.02 ns seen in 18.6
  is the combinational `paddr` to `prdata` path, a different path.
- `check_timing`: clean (no loops, unconstrained endpoints, missing input delays or
  driving cells). `check_design`: no errors; only expected `LINT-28/32/33`
  (unused `paddr[31:12]`/`[1:0]`, DW adder `CI`/`CO` and constant `B` bits, `psum_in`
  rows and `error_code_i[2:1]` tied to 0).
- `report_constraint -all_violators`: 80 `max_transition` violations. 79 were on the
  data input ports (2.43 ns against the 1.0 ns design-wide limit, -1.43 ns each):
  the assumed `buffd1` driver into 0.2 pF already gives 2.43 ns, so the limit and
  the input assumptions contradicted each other and DC could not fix it. The 80th is
  real and internal: net `n45` in `pe_10` (the enable of 8 `weight_reg` flops,
  1.46 ns against 1.0 ns); ICC2 will buffer it. `max_area` is violated by the PM's
  `set_max_area 0`, which only means "minimise".
- DECISIONS on the 79 input-port violations (the user, 2026-10-14):
  1. Option 1 first: a per-port `set_max_transition 3.0` on the data inputs with the
     design-wide 1.0 ns kept. Tried in a second DC run (`f9b734e`): DC wrote the
     per-port limits into the SDC, but `report_constraint` still checked those nets
     against 1.00 ns and still reported 248 VIOLATED lines. A port-level
     `set_max_transition` does not override a tighter design-wide one; the tighter
     value wins. The earlier claim in the SDC comment that the port value applies
     was wrong.
  2. Option A then chosen: drop the design-wide 1.0 ns (my own harsh guess, no
     library basis) and use the library's own `max_transition : 3` ns everywhere
     (`MAX_TRANSITION 3.0`, the per-port lines removed). The input driver (`buffd1`)
     and wire (0.2 pF) assumptions are NOT relaxed; the output load stays 1 pF; max
     capacitance stays 2.0 pF. Written reason is comments d) and e) in
     `constraints/pm_unpu_top.sdc` and `constraints/unpu_top.sdc`.
  Result of the third DC run (`3bb17b5`, 2026-10-14): `report_constraint
  -all_violators` lists only the PM's `max_area` 0 entry (actual 442,295.8 um2); no
  `max_transition` violation. Worst setup slack +0.01 ns (the combinational `paddr[3]`
  to `prdata[14]` path, 4.49 ns of the 4.5 ns budget; DC stops at just-positive).
  Area 442,296 um2 total (cell area 429,161), down 2.8% from the first run because the
  unreachable 1.0 ns limit no longer forces extra buffering (buf/inv area 29,398 to
  19,857); 2,465 flops (noncombinational area 172,266 to 178,149, larger flop variants);
  dynamic power 6.40 mW and leakage 5.57 uW (still not meaningful: ideal clock, no
  switching annotation). The un-violated count was confirmed from the user's pasted
  `violators.rpt`; reports copied locally to `syn/out/pm_flow_server_r3/` (git-ignored).
  The clean-name hand-off set for ICC2 was regenerated from this run
  (`unpu_top_cn.*` in the user's `syn/out/pm_flow/`). GLS of that netlist (same
  command as 18.7, log `syn/out/gls/xrun_cn2.log`): 343,341 checks, ALL CHECKS PASSED,
  finish at 138,350,796 ns, 1 min 52 s. The DC output is ready for ICC2.

### 18.9 Dummy LEF: kit facts and working proposal (2026-10-26)

A teammate's question list for the dummy LEF was reviewed (Planning's answers one by
one in chat). Facts read from the SCL tech LEF and std-cell LEF by the user on the server
(`scl18fs120_tech.lef`, `scl18fs120_std.lef`, paths in 18.3):

| Layer | Direction | Pitch (um) | Min width (um) | Min area (um2) |
|---|---|---|---|---|
| M1 | horizontal | 0.56 | 0.23 | 0.202 |
| M2 | vertical | 0.56 | 0.28 | 0.202 |
| M3 | horizontal | 0.84 | 0.28 | 0.202 |
| TOP_M (the 4th metal) | vertical | 1.12 | 0.44 | 0.562 |

Vias are V2, V3, TOP_V. There is no layer called METAL1..METAL4 (the teammate's
document used those names; the LEF names are M1, M2, M3, TOP_M). Std-cell site
`CoreSite`: 0.56 x 5.6 um (row height 5.6 um). The cells' power pins are named `VDD`
(USE POWER) and `VSS` (USE GROUND). Not yet read: track OFFSET values, spacing and
wide-metal rules, the full layer blocks.

Port counts, from `rtl/unpu_top.sv`: 102 inputs, 102 outputs, 204 pins including `clk`
and `rst_n`. APB 100 pins (`paddr` 32, `pwdata` 32, `pwrite`, `psel`, `penable`, `prdata`
32, `pready`), DMA 102 pins (`dma_addr` 32, `dma_wdata` 32, `dma_rdata` 32, `dma_wstrb`
4, `dma_valid`, `dma_ready`), plus `clk`, `rst_n`. The teammate's 99/103 were off.

Working proposal for the dummy LEF (PROVISIONAL, none of it confirmed by the PM or the
top-level team; every item is a parameter so a changed answer costs a rerun):
- Size 817.6 x 817.6 um (a multiple of both 0.56 and 5.6; 429,161 / 668,478 = 64.2%
  utilisation). A placeholder until place and route gives the real size.
- Top edge: `clk`, `rst_n`, APB (102 pins) on M2. Right edge: DMA (102 pins) on M3. Left
  edge: `VDD`, `VSS` on TOP_M. Bottom: no pins. No signal pins on M1 or TOP_M.
- Common pin pitch 6.72 um (12 M2 tracks = 8 M3 tracks), so 102 pins span ~679 um and
  fit on both edges; the M3 minimum of 3 tracks would not have fitted at 8.4 um.
- Pin width = layer minimum width, length about 1 um into the block; OBS on all four
  metals in the interior; orientation R0 assumed.
- Still needed from others: top-level floorplan (which side faces the CPU and which the
  SRAM arbiter), pin order direction, power net names and layout, halo, rotation, grid,
  clock latency/skew limit at `clk`, and which files (LEF only, or `.lib` too) and when.
Task 037 (not dispatched) writes the generator and checker.

Decisions from the question-by-question review (user, 2026-10-26). The teammate owns the
dummy LEF itself; the user relays these answers. Task 037 is withdrawn (not dispatched).
- Q1 size: 64% utilisation, so 817.6 x 817.6 um as a placeholder (no area limit known).
- Q2 shape: square.
- Q9 power: names `VDD`/`VSS` (user: "works"); layout as recommended, vertical TOP_M
  stripes in several pairs, no ring; width and count later from a power estimate.
- Q10: no top-level routing over the macro; OBS on all four metals.
- Q11 halo: 10 um (the instructor said so).
- Q12: no rotation or flip, so R0.
- Q13 grid: the site grid (width a multiple of 0.56 um, height of 5.6 um); the top level
  has not been asked about a coarser grid, user accepted the recommendation.
- Q15 interface timing: keep the assumed budgets (APB 35%, DMA and `rst_n` 40%, 1 pF).
- Q16 files and deadline: the teammate handles it.
- Q6, Q7, Q8 are settled by the kit (18.9 table), not asked.
- STILL OPEN (user to ask the top-level team, answer expected 2026-10-27): Q3 floorplan
  and which side faces the CPU/APB bridge and the SRAM arbiter; Q4 pin sides (follows
  Q3); Q5 pin order direction; Q14 clock latency/skew limit at `clk` and the `clk` pin
  position.

Top-level answers received 2026-10-28 (user-reported) and the resulting pin plan. This
SUPERSEDES the sides in the provisional plan above (APB top / DMA right):
- Q3: the CPU sits on the RIGHT of the macro, the SRAM arbiter on the TOP.
- Q4: RIGHT edge: APB (100 pins) plus `clk` and `rst_n` (102), on M3 (horizontal).
  TOP edge: DMA (102 pins), on M2 (vertical). LEFT: `VDD`/`VSS` on TOP_M. BOTTOM: no
  pins. `clk` near the middle of the right edge, in a gap between buses.
- Q5: pins grouped by bus, bits ascending; top edge bit 0 at the left, rising to the
  right; right edge bit 0 at the bottom, rising upward. (Planning's recommendation; the
  top-level team has no order of their own, user: "go with your recommendation".)
- Still open: Q14 clock latency and skew limit at `clk`.
- Power pins stay on the LEFT edge (user asked about moving them to top/right, no reason
  found, 2026-10-28). Q14 stays open; the clock tree is built for MINIMUM SKEW and the
  resulting insertion delay is reported; the PM is asked for latency/skew limits later.

### 18.10 ICC2 reference library built (user's server run, 2026-10-28)

- The two library managers differ: `which icc2_lm_shell` found Fusion Compiler V-2023.12-SP4
  (`/home/Synopsys_tools/fusioncompiler/V-2023.12-SP4/bin/`), `icc2_shell` is U-2022.12-SP3
  (`/home/Synopsys_tools/icc2/U-2022.12-SP3/bin/`). An NDM from a newer release may not open
  in an older one, so the library was built with the matching
  `/home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell` (banner: Library Manager
  U-2022.12-SP3). Use that full path; the bare name picks the wrong one.
- Work directory outside the repo: `/storage/EE5239G1/aagams_workspace/icc2_work`. Result:
  `scl18fs120.ndm` there (the workspace is removed after the commit).
- Steps, all in `lm_shell`: `create_workspace -flow normal -technology .../digital_pnr_kit/snps/non_rh/4M1L/SCL_4LM.tf scl18fs120`;
  `read_lef .../stdcell/fs120/4M1IL/lef/scl18fs120_std.lef`; `read_db` of the ss and ff `.db`
  (library names `tsl18fs120_scl_ss`, `tsl18fs120_scl_ff`); `check_workspace` ("Workspace
  check succeeded!", 534 frames); `commit_workspace`.
- Messages, all benign: `TECH-001` (CapTable/CapModel sections of the `.tf` ignored; RC
  comes from TLUPlus later); `LEFR-064` (LEF site `CoreSite` mapped to tech-file tile
  `unit`, both 0.56 x 5.6 um, checked in `SCL_4LM.tf` line 164); `FRAM-066` (cells with a very
  large regular routing blockage on M1; watch for pin-access problems at routing).
- 540 `MACRO`s in the LEF, 534 in the ss `.lib`, no duplicate names. The six LEF-only
  cells (no timing view): `feedth`, `feedth3`, `feedth9`, `mx08d1`, `mx08d2`, `mx08d4`.
  The netlist `unpu_top_cn.dc.v` uses none (grep count 0). No library cell is missing from
  the LEF.
- Filler/tie cells: no library cell name contains `fill`, `feed`, `tie` or `cap`; only
  `adiode` matched `diode`. Find the filler and tie cell names in the kit's `doc/`
  (`std_cell_guidelines`, `chip_finishing`) before the finishing step.
- Not done yet: TLUPlus is read in `icc2_shell` (typical only); design library creation,
  floorplan, placement, CTS, routing.

### 18.11 ICC2 design library created, step 1 done (user's server run, 2026-10-28)

- In `icc2_shell` (U-2022.12-SP3), in `/storage/EE5239G1/aagams_workspace/icc2_work`:
  `create_lib -technology .../digital_pnr_kit/snps/non_rh/4M1L/SCL_4LM.tf -ref_libs
  /storage/EE5239G1/aagams_workspace/icc2_work/scl18fs120.ndm unpu_lib` (same benign `TECH-001`
  warnings, no version error). `report_ref_libs` lists `scl18fs120` (open, has technology
  information): the 2022.12 `icc2_shell` reads the NDM built by the 2022.12 library manager.
- `help <cmd>` prints only a one-line description in these shells; options come from
  `<cmd> -help`.
- `read_parasitic_tech -name typ -tlup SCL_TLUPLUS_4M1L_TYP.tlup -layermap SCL_TLUPLUS_4M1L.map`
  (kit dir `digital_pnr_kit/snps/non_rh/4M1L/`): nine `TLUP-011` warnings, benign. The map uses
  the tech file's mask names; they resolved as metal1/2/3/4 to M1/M2/M3/TOP_M, poly to GC, CC to CS,
  via1/2/3 to V2/V3/TOP_V. `save_lib` done (typing `save lib` is ambiguous, `CMD-006`).
- Not yet confirmed: that `typ` RC is selected for the corners (done with the scenarios and
  `set_parasitic_parameters`). Next, step 2: read `unpu_top_cn.dc.v` and `unpu_top_cn.sdc`.

### 18.12 ICC2 step 2: netlist and SDC read (user's server run, 2026-10-28)

- `open_lib unpu_lib`; `read_verilog -top unpu_top .../syn/out/pm_flow/unpu_top_cn.dc.v`
  (options of this shell: `-library`, `-design`, `-top`, `-as_block`): 76 modules read, top-level
  ports 204, total ports in all modules 7,452, nets 21,755, instances 12,562 (summed over module
  definitions, not a flat count). `link_block`: "Design 'unpu_top' was successfully linked"
  with libraries `unpu_lib scl18fs120`, no unresolved cells.
- Counts match DC: `get_ports *` 204; `is_sequential==true` cells 2,465.
- `read_sdc .../unpu_top_cn.sdc`: loaded as SDC 2.1; only two constraints ignored,
  `set_wire_load_model` and `set_max_area` ("not supported by icc2", SDC-3/SDC-4). Both were
  expected: ICC2 takes wire parasitics from TLUPlus after placement, and `max_area 0` is the PM's
  minimise-only line. Driving cell `buffd1`, loads, I/O delays and limits loaded without warning.
  `save_block` done (`unpu_lib:unpu_top.design`).
- Not yet done: corner/scenario setup (ss for setup, ff for hold, RC `typ` per corner), then
  floorplan. Cell area against DC's 429,161 um2 not compared yet (optional `report_design -netlist`).

### 18.13 ICC2 step 3: corners and scenarios (user's server run, 2026-10-28)

- `read_sdc` had created one `default` mode, corner and scenario (setup and hold both on). This
  shell has no `rename_mode/corner/scenario`, so `default` was kept as the ss scenario. The SDC's own
  line 9 (`set_operating_conditions tsl18fs120_scl_ss -library tsl18fs120_scl_ss`) already gives it
  1.62 V / 125 C.
- Added: `create_corner ff`; `create_scenario -name ff_hold -mode default -corner ff`; the same SDC read
  into it (`UIC-034` "Redefining clock 'clk'" is harmless: both scenarios share mode `default`); then
  `set_operating_conditions tsl18fs120_scl_ff -library tsl18fs120_scl_ff` overrides line 9.
  `report_corners` shows ff at 1.98 V / -40 C (file/line `--` = set by hand) and default at 1.62 V / 125 C.
- `set_scenario_status default -setup true -hold false`; `set_scenario_status ff_hold -setup false
  -hold true`. `report_scenarios` confirms. Min-cap/max-cap/max-transition stay active in both.
- `set_parasitic_parameters -corners default|ff -early_spec typ -late_spec typ`;
  `report_parasitic_parameters` lists `typ` (`SCL_TLUPLUS_4M1L_TYP.tlup`, map `SCL_TLUPLUS_4M1L.map`)
  as early and late on both corners. `save_block` done. Only a typical TLUPlus exists in the kit, so
  both corners use `typ` RC.
- `check_timing` (default): one warning, `pready` unconstrained, reason `case constant`
  (`rtl/unpu_apb.sv:87`, `assign pready = 1'b1`). Expected, nothing to time.
- First timing (no placement, `TIM-101/102` zero interconnect, ideal clock, so cell delay only):
  - Setup, scenario `default` (ss): worst path `paddr[2]` to `prdata[1]`, slack +0.82 ns (MET).
    DC's +0.01 ns used its wire-load guess; the real figure comes after placement and routing.
  - Hold, scenario `ff_hold` (ff): worst path `u_csr/src_b_reg_reg_4_` to `prdata[4]` (reg2out),
    slack -0.50 ns (VIOLATED). Cause: `OUT_MIN_DELAY` is -0.5 (outside needs outputs held 0.5 ns), so the
    required arrival is 0.5 uncertainty + 0.5 hold = 1.0 ns after an ideal clock at 0, and the path is
    clk-to-Q 0.22 + gates = 0.50 ns. Expected before CTS: the check has not seen the clock tree.
    After CTS the launch flop's clock arrives late by the insertion delay, which adds to the data
    arrival; the output port is checked against an ideal capture edge.
- Consequence to watch after CTS: the same insertion delay costs setup on the reg-to-output paths and
  makes input-to-flop hold tighter (input min delay 0.0 against a late capture clock), so ICC2 will
  add hold buffers on the inputs. That trade is the reason the clock latency/skew limit at `clk`
  (Q14) is still worth asking the PM.
- Licence lines: `ICCompilerII` and `-4` fail ("No such feature"), `-8` and `-NX` check out; normal.
- Next: floorplan (817.6 um square, rows, pins per 18.9, power stripes on TOP_M at the left).

### 18.14 ICC2 step 4: floorplan, power connections, kit guidelines read (user's server run, 2026-10-28)

- **Floorplan.** First attempt `initialize_floorplan -boundary {{0 0} {817.6 817.6}} -core_offset 5.6`
  made that boundary the CORE and added the offset outside it: die 828.8 x 828.8, not the 817.6 of the
  dummy LEF (planning error, caught from `report_design -floorplan`: chip area 686,909.44, 146 rows).
  Correct form: `initialize_floorplan -boundary {{5.6 5.6} {812.0 812.0}} -core_offset 5.6`.
  Result: chip 668,469.76 um2, `boundary_bbox` {0 0} {817.6 817.6}, core 650,280.96 um2 (806.4 square),
  144 rows of site `unit` (0.56 x 5.6), core utilisation 66.00% (DC cell area 429,161 um2). Saved.
- Routing directions are missing from the technology; ICC2 derived M1 horizontal, M2 vertical, M3
  horizontal, TOP_M vertical (`DPUI-924`, `ATTR-11` block override). Same as the kit LEF.
- **M3 pitch.** Tech file `SCL_4LM.tf` pitch: M1 0.56, M2 0.56, M3 0.61, TOP_M 1.12 (the other `pitch`
  lines belong to via layers: TOP_V 0.71 etc.). Kit LEF: M1 0.56, M2 0.56, M3 0.84, TOP_M 1.12. Only M3
  differs. ICC2 uses the tech file (0.61; legal, width 0.28 + spacing 0.28 = 0.56). Risk: right-edge pins
  (APB, on M3) snap to 0.61 tracks, so they will not sit on the 0.84 grid of the dummy LEF / top-level
  router. Confirm with the teammate who owns the LEF; not blocking.
- **Power connections.** `create_net -power VDD`, `create_net -ground VSS`, `connect_pg_net
  -automatic`: 12,487 VDD and 12,487 VSS pins connected = 12,487 leaf cells
  (`get_cells -hierarchical -filter "is_hierarchical==false"`). Logical only; no metal yet.
- **Kit `doc/std_cell_guidelines.pdf` (FAQ):** FS120 is a 10-track library (5.6 um); filler cells
  `feedth`, `feedth3`, `feedth9`, needed to avoid implant spacing DRC (the LEF-only cells found in 18.10);
  NO tap cells needed (substrate/well contacts inside the cells); don't-use cells `slnht*`, `skbrb*`,
  `slbhb*`, `slnhn*`, `slnln*`, `mx08d*` (already in `syn/dc_setup.tcl:39`; the netlist uses none:
  `grep -c` = 0; ICC2 not told yet); `vcs_sim_model` and `tmax_model` folders hold simulation and ATPG
  models; the P&R tool's GDSII has only abstract layer information and must be merged with the IP
  (standard-cell) GDSII in Virtuoso: find the std-cell GDS in the kit before Calibre DRC/LVS.
  Other kit docs: `chip_finishing.pdf` (not read yet), `DRM.pdf`, `DRS.pdf`, `io_guidelines.pdf`,
  `memory_cuts_scl.pdf`.
- **Constants in the netlist.** The library has no tie cells; DC used inverters on constants:
  `inv0d0 U2 (.I(1'b0), .ZN(pready))` (netlist line 20), `U3`/`U9` with `.I(1'b1)` for
  `error_code[2]` and `[1]`, plus `1'b0` literals on the DW01_add sub-module ports (`.B`, `.CI`). OPEN:
  how ICC2 should tie these (connect to VSS/VDD directly, or other) and how LVS (`v2lvs`) maps `1'b0` and
  `1'b1`; decide before routing/finishing.
- Next: `set_dont_use` for the six patterns in ICC2, then the power grid (rails M1, TOP_M stripes at the
  left); widths/pitch from `chip_finishing.pdf`/DRM, not guesses.

### 18.15 ICC2 step 5: don't-use, power grid, signal pins (user's server run, 2026-10-28)

- **Don't-use.** `set_dont_use [get_lib_cells {*/slnht* */skbrb* */slbhb* */slnhn* */slnln* */mx08d*}]`:
  18 lib cells now `dont_use==true`. `*/mx08d*` matched nothing (`mx08d1/2/4` have no timing view, so
  `get_lib_cells` does not return them; ICC2 cannot choose them for timing optimisation anyway). The 15
  matched cells are block-level overrides (`ATTR-12`, saved with the block). The other three are
  flagged by the library itself: `adiode` (ANTENNA DIODE, so antenna fixing at routing may need it named
  explicitly or may be refused), `bh01d1` (bus holder), `cload1` (load cell). OPEN for the route step.
- **`chip_finishing.pdf`** covers chip-level items only: dummy fill by Calibre (SCL `DUMMY.header`,
  produces `top_with_dummy.gds`), seal ring (connect to VSS or VSSO), silicon number. No power-grid
  numbers. OPEN question for PM/teammate: does the macro deliverable include dummy fill, or does the
  top-level team add it?
- **Power grid.** DC power report: 6.4 mW at 1.62 V (default activity), about 4 mA, so IR drop and
  electromigration do not limit the grid. M1 rail 0.74 um (LEF, `inv0d0`: `VDD` y 4.86-5.60, `VSS`
  y 0-0.74; rows alternate, shared rail about 1.48 um). Chosen (no kit number): TOP_M vertical stripes
  2.24 um wide, VDD/VSS interleaved, pitch 112 um (= 100 TOP_M tracks). Commands:
  `create_pg_std_cell_conn_pattern std_rail -layers {M1} -rail_width 0.74`;
  `create_pg_mesh_pattern top_mesh -layers {{{vertical_layer: TOP_M} {width: 2.24} {pitch: 112}
  {spacing: interleaving}}}`; `set_pg_strategy s_rail -core -pattern {{name: std_rail} {nets: {VDD VSS}}}`;
  `set_pg_strategy s_mesh -core -pattern {{name: top_mesh} {nets: {VDD VSS}}}`;
  `compile_pg -strategies {s_rail s_mesh}`. Result: 14 stripes (7 VDD, 7 VSS), 145 rails (73 VDD,
  72 VSS), 1,015 stacked-via locations (3,045 vias). `check_pg_drc`: no errors.
  `check_pg_connectivity`: 0 floating wires or vias, but ALL 12,487 std cells floating on both nets,
  expected because nothing is placed (`compile_pg` saw "Number of Standard Cells: 0"). NOT YET VERIFIED:
  re-run after placement, the floating-cell count must be 0. Also "Terminals: 0": the macro `VDD`/`VSS`
  pins are not created yet (plan: left edge, TOP_M).
- **Signal pins.** `set_block_pin_constraints -self -hard_constraints location`, then per port
  `set_individual_pin_constraints -ports ... -location {x y} -allowed_layers M3|M2 -width 0.28
  -length 1.0`, then `place_pins -self`: 204 pins created, `get_terminals` = 204, locations honoured
  exactly (no snapping), layers confirmed (`get_attribute ... layer`: clk M3, dma_addr[0] M2). Pitch
  6.72 um, first slot at 56.0.
  - Right edge (x = 817.6, M3), bottom to top, slots 0-103: `rst_n`, `pwrite`, `psel`, `penable`,
    `paddr[0..31]`, gap, `clk` (slot 37, y = 304.64), gap, `pwdata[0..31]`, `prdata[0..31]`, `pready`
    (slot 103, y = 748.16).
  - Top edge (y = 817.6, M2), left to right, slots 0-101: `dma_addr[0..31]`, `dma_wdata[0..31]`,
    `dma_wstrb[0..3]`, `dma_valid`, `dma_rdata[0..31]`, `dma_ready` (x = 734.72).
  - `clk` is at about 38% of the edge height, not the exact centre (centring would push the buses off
    the edge). The pins sit at computed positions, not necessarily on routing tracks (M3 0.61, M2 0.56);
    relevant to the M3 pitch question in 18.14.
- The session commands are typed by hand; to be consolidated into a `pnr/` script later (task for
  Execution, once the flow works end to end).
- Next: placement (`check_design`, then `place_opt`), re-run `check_pg_connectivity`, then clock tree.

### 18.16 ICC2 step 6: placement (`place_opt`, user's server run, 2026-10-28)

- `place_opt -list_only` stages: `initial_place` (coarse placement), `initial_drc` (high-fanout synthesis
  and initial DRC fixing), `initial_opto` (datapath optimisation before final coarse placement),
  `final_place` (final coarse placement), `final_opto`. No stage is named legalisation, so legality was
  checked separately. Run time 133 s, peak memory 0.87 GB, scenarios `default` (setup) and `ff_hold` (hold).
- Final QoR: setup WNS 0.0000, TNS 0, 0 violating endpoints in every path group (ICC2 prints 0 when
  nothing is negative); max transition and max capacitance violations 0. Area 426,097.72 um2 (DC:
  429,161), 11,986 instances (netlist had 12,487 leaf cells), 161 buffers, 1,353 inverters. So
  `place_opt` removed or merged 501 cells: the netlist to deliver differs from the DC netlist, and the
  post-layout gate-level simulation is what proves the edits safe.
- Real worst setup path (`report_timing`, scenario `default`): `paddr[3]` to `prdata[23]` (in2out,
  combinational APB read path), slack 0.00 ns (MET): arrival 11.50, required 11.50. The optimiser
  recovers area until slack is just met, so there is NO margin; the path has no flop, so the clock
  tree does not change it, only routing parasitics will. Earlier pre-placement slack was +0.82 ns (cell
  delay only, different path).
- Hold (scenario `ff_hold`): 2,304 violating endpoints, total -383 ns, worst -0.28 ns. By group:
  flop-to-flop (`clk`) 2,260 endpoints worst -0.283; in2reg 230 worst -0.196; reg2out 44 worst -0.275.
  Worst path is a SELF-LOOP: `u_actbuf/bank_b_reg_0__3__1_` QN to its own D through `oai22d1`; arrival
  0.31 ns against required 0.59 (0.06 clock + 0.50 uncertainty + 0.03 hold). Clock skew cannot change
  a path whose launch and capture flop are the same, so after CTS these paths are fixed only by delay
  cells or by the hold uncertainty. `place_opt` does not fix hold.
- DECISION FOR CTS (not taken): `CLK_UNCERT_HOLD` is 0.5 ns, labelled in `constraints/unpu_top.sdc` as
  "skew only", with the note that after CTS the clock becomes propagated and the uncertainty values are
  revisited. After CTS the real skew is in the report, so keeping 0.5 double counts it. Options: keep
  0.5 and accept thousands of hold buffers; reduce to a jitter-only figure; decide with the PM. No
  change without the user's approval and a written reason.
- `check_legality`: 0 violations in every category ("succeeded"); `PDC-003` warning about the GC (poly)
  layer having no routing direction is benign.
- `check_pg_connectivity` (the check deferred from 18.15): 11,986 standard cells, 0 floating cells,
  0 floating wires or vias on `VDD` and `VSS`. Resolved. (Terminals still 0: macro PG pins not created.)
- The log also prints a large table of "Co-efficient Ratio Summary" numbers: internal, ignorable.
- Next: save, then clock tree synthesis (`clock_opt`).

### 18.17 ICC2 step 7: clock tree built (`clock_opt -to build_clock`, user's server run, 2026-10-28)

- Before: `set_lib_cell_purpose -exclude cts [get_lib_cells {*/dl*}]`. Library buffers: `dl01d1/2/4`,
  `dl02d1/2/4`, `dl03d1/2/4`, `dl04d1/2/4` (12 delay cells, kept out of the clock tree, left for hold
  fixing), `buffd1/2/3/4/7/a`, `bufbd1/2/3/4/7/a/f/k`; none is on the don't-use list. `clock_opt` stages:
  `build_clock`, `route_clock` (detail-routes the clock nets), `final_opto`.
- Result (`report_clock_qor -type summary`): 2,465 sinks (= flop count), 3 levels, 53 clock repeaters,
  repeater area 1,517.82 um2, clock wire length 34,405.64 um, 0 transition and 0 capacitance DRC
  violations. Corner `default` (ss): max latency 1.21 ns, global skew 0.95 ns. Corner `ff`: max latency
  0.49 ns, global skew 0.36 ns. Both are inside the assumptions in `constraints/unpu_top.sdc` (setup
  uncertainty 1.5 = 0.5 jitter + 1.0 skew; hold 0.5 = skew only). 0.95 ns is not small for a 3-level tree
  (about 80% of the latency): the default run makes no special skew effort; worth looking at the
  largest/smallest sink paths before routing (`report_clock_qor ... -largest/-smallest` with paths).
- After CTS (propagated clock): setup WNS still 0 in all groups except in2out with 1 endpoint at about
  -0.00 ns (`paddr[3]` to `prdata[23]`, arrival 12.00 = required 12.00; launch and capture both carry 0.50 ns
  propagated latency); no setup margin. Hold: worst -0.397 ns, 2,219 endpoints (flop-to-flop 2,179 worst
  -0.397; in2reg 235 worst -0.329; reg2out 39 worst -0.239). Area 427,618.69 um2, 12,039 instances,
  214 buffers, 1,353 inverters. `save_block -as unpu_top_cts` made a copy (`DES-028`); `unpu_top` on disk is
  the placed design.
- Hold distribution at the ff corner (endpoints still violating if the hold uncertainty were smaller;
  analysis only, nothing changed): 0.5 ns: 2,219; 0.4: 1,797; 0.3: 1,065; 0.2: 31; 0.1: 0; 0.0: 0. The
  worst path has about +0.10 ns slack without any uncertainty, skew included.
- DECISION (user, 2026-10-28): KEEP the hold uncertainty at 0.5 ns for the post-CTS flow. Considered and
  not taken: 0.2 ns (Planning's proposal; reason: skew now measured and in the propagated analysis so
  0.5 counts it twice), 0.3 ns, ask the PM first. Consequence accepted: ICC2 must delay thousands of
  endpoints (up to 2,219 at the start), costing area and leakage; utilisation 66% leaves room.
  Setup uncertainty unchanged (1.5 ns).
- Next: check the hold-fix app options, then `clock_opt -from route_clock -to final_opto`.

### 18.18 ICC2 step 8: hold run at 0.5 ns, then the uncertainty decision CHANGED (user, 2026-10-28)

- Run with hold uncertainty 0.5 ns (the earlier decision, 18.17): `clock_opt -from route_clock -to final_opto`.
  Result: setup NSV 0; hold 2,219 -> 6 violating endpoints, worst -0.0125 ns (four self-loops in
  `u_wbuf` bank flops, two neighbouring-PE `act_out` shifts where the launch clock is 0.10 ns later than the
  capture clock); max transition/capacitance 0; area 427,619 -> 484,572 um2 (+56,953 um2, +13.3%);
  instances 12,039 -> 14,309; buffers 214 -> 2,511 (+2,297, almost all delay cells); core utilisation
  66% -> 74.5% (72.5% of the die); leakage ss 5.47 -> 6.68 uW. `check_legality`: 0 violations
  (115 library cell types in use). Warning `FLW-8004` "Incomplete clock_opt / final_opto": a stage started
  (FLW-8000) without its end line (FLW-8001); cause not known (`icc2_command.log` holds commands only, not
  messages). Not saved; discarded in favour of the run below.
- DECISION (user, 2026-10-28, reverses the 18.17 choice): hold clock uncertainty 0.5 ns -> 0.2 ns in the
  `ff_hold` scenario, as Planning proposed. Reason (written): the 0.5 ns in `constraints/unpu_top.sdc`
  was a pre-CTS stand-in for skew; skew is now measured (ff: 0.36 ns) and enters the propagated-clock
  analysis, so 0.5 counts it twice. 0.2 ns remains as margin for effects not yet modelled (on-chip
  variation, routed parasitics). Evidence: endpoints still failing at the post-CTS ff corner: 0.5 ns:
  2,219; 0.4: 1,797; 0.3: 1,065; 0.2: 31; 0.1: 0; the worst path has +0.10 ns slack with no uncertainty.
  The cost seen at 0.5 ns (+2,297 cells, +13.3% area, 74.5% utilisation) is the reason it is not kept.
  Setup uncertainty (1.5 ns) unchanged. The change lives in the ICC2 flow, not in the SDC (the SDC states
  that post-CTS uncertainty is revisited in the tool). To be copied into the `pnr/` script by Execution.
- How: the hold-fixed block was NOT saved; `unpu_top_cts` (saved right after `build_clock`, hold unfixed)
  is reopened, `set_clock_uncertainty -hold 0.2` set in `ff_hold`, and `clock_opt -from route_clock
  -to final_opto` re-run. The placed design remains on disk as `unpu_top`.
- RESULT at 0.2 ns (`clock_opt -from route_clock -to final_opto` on `unpu_top_cts`): setup NSV 0; hold NHV 0;
  max transition/capacitance 0; area 428,230.22 um2 (+612 um2 over the CTS state's 427,618.69); instances
  12,039 (unchanged, fixes were swaps: buffers 214 -> 252, inverters 1,353 -> 1,273); core utilisation
  65.9%; leakage ss 5.40 uW. Against the 0.5 ns run: area +56,953 vs +612 um2, 2,297 vs 38 added buffers.
- Independent checks after the run: setup worst `paddr[2]` to `prdata[2]` (in2out) slack +0.01 ns (arrival
  11.99, required 12.00); hold worst `u_deskew/col0_q1_reg_23_` to `col0_q2_reg_23_` slack 0.00 ns MET with
  `clock uncertainty 0.20` shown; `check_legality` 0 violations (104 cell types); `check_pg_connectivity`
  0 floating cells/wires/vias (12,039 cells); clock QoR: 2,465 sinks, 3 levels, 53 repeaters, repeater area
  1,492.74 um2, max latency 1.22 ns (ss) / 0.49 ns (ff), global skew 0.95 ns (ss) / 0.36 ns (ff), 0 clock
  DRC. Slacks of 0.00-0.01 ns are after the 1.5 ns setup and 0.2 ns hold uncertainty are subtracted, so
  physical margin exists; the optimiser stops at zero and routed RC will move them.
- `FLW-8004` "Incomplete clock_opt / final_opto" appeared in both final_opto runs (0.5 and 0.2 ns), also with
  every check clean, so it is not tied to leftover violations; `route_clock` ran (53 nets detail-routed
  = 53 clock repeaters) and `final_opto` printed its QoR. Cause unknown; most likely a reporting quirk of
  this version. OPEN, record; re-check at the routing stage.

### 18.19 ICC2 step 9: constants and tie-offs checked, state at end of day 2026-10-28

- `get_pins -hierarchical -filter "constant_value==0 || constant_value==1"` gives 374 pins; the attribute
  marks derived constants too (outputs), so it is not the tie-off count. Pins: `U2` (the `inv0d0` holding
  `pready` high) and, in each of the four row-0 PEs (`u_grid/g_row_0__g_col_{0..3}__pe`), 31 cells of the
  accumulator adder `add_42` (`U1_1`..`U1_31`) with `A = 0`, `CI = 0`, `CO = 0`. Observation, not an
  action (RTL frozen): row 0 adds the product to a constant zero, and the shared DesignWare adder was not
  simplified, so about 124 adder cells compute "B + 0 + 0"; rough guess about 1% of area, not measured.
  `U3` and `U9` (the `1'b1` inverters for `error_code[2:1]`) are gone from the list; not checked why.
- Physical tie: `get_nets -of_objects U2/I` is the net `VSS` (type `ground`): ICC2's auto PG
  connection (`NDM-099`, printed after each flow command) ties the `1'b0` literal to the ground net.
  `connect_tie_cells` does not exist in this version. Count of non-PG pins on `VSS`: 129 (= 1 + 4 x 32),
  on `VDD`: 0. `get_flat_nets` returns nothing for a pin tied to a rail (it has no ordinary signal net).
  Not yet seen: the metal that joins these 129 pins to the M1 rails; routing and the layout checks
  (`check_routes`, LVS) will show it. RISK: gate inputs tied directly to a rail, no tie cells in the
  library; legal by design rules, generally avoided for gate-oxide stress; the LVS netlist conversion must
  map `1'b0` to `VSS` and `1'b1` to `VDD` the same way. Note for the PM discussion.
- Routing commands in this version: `route_auto` (options include `-max_detail_route_iterations`
  default 40, `-reuse_existing_global_route`, `-route_nondefault_nets_first`), `route_opt`.
- State at the end of the day: library `unpu_lib` in `/storage/EE5239G1/aagams_workspace/icc2_work`, blocks
  `unpu_top` (placed, 19:33), `unpu_top_cts` (listing shows 22:28, may or may not still be the
  hold-unfixed state on disk), `unpu_top_clkopt` (CTS built, hold fixed at 0.2 ns; continue from here).
  Backup: `unpu_lib_backup_oct28.tgz` in the same directory. To resume: `open_lib unpu_lib`,
  `open_block unpu_top_clkopt`, check `report_timing -delay_type min -max_paths 1` in `ff_hold` shows
  `clock uncertainty 0.20`.
- Open items: `FLW-8004` unexplained; `DMM-104` (91 notes) not read; M3 pin grid (0.61 tech vs 0.84 LEF)
  to confirm with the teammate who owns the dummy LEF; `adiode` don't-use for antenna fixing; macro
  `VDD`/`VSS` pins not created; dummy fill in the deliverable (PM); std-cell GDS location for the
  merge; clock latency limit at `clk` (PM).
- Next: `route_auto`, `check_routes`, then `route_opt`.

### 18.20 ICC2 step 10: routing (`route_auto`, `route_opt`, user's server run, 2026-10-29)

- Resume: `open_lib unpu_lib`, `open_block unpu_top_clkopt`; scenarios and `clock uncertainty 0.20` survived the
  reopen (hold report `u_deskew/col0_q1_reg_23_` to `col0_q2_reg_23_`, slack 0.00 MET).
- `route_auto` (about 1 min): detail-route iteration 0 had 4 violations (2 diff-net spacing, 2 shorts),
  iteration 1 had 0 ("Finish DR since reached 0 DRC"); 0 open nets of 13,997. Wire length 792,524 um (M1
  16,927; M2 323,338; M3 368,389; TOP_M 81,399); contacts 103,651 (V2 49,073; V3 49,523; TOP_V 5,055).
  `save_block -as unpu_top_routed` taken after it.
- Timing with extracted detailed-route RC: setup worst (in2out `paddr[2]` to `prdata[2]`) slack 0.00 ns MET;
  hold worst -0.01 ns (`psum_out_reg_21_` row 3 to `u_deskew/col1_q1_reg_21_`, launch 0.27, capture 0.36).
- `route_opt` (45 s, no `FLW-8004`; the warning is specific to `clock_opt` `final_opto`): setup NSV 0, hold
  NHV 0 in every path group, max transition/capacitance 0; area 428,230 -> 428,609.66 um2; instances 12,039
  -> 12,041; leakage ss 5.08 uW.
- Independent checks after `route_opt`: `check_routes` 0 open nets (13,999 nets), 0 DRC; `check_lvs` 0 shorts,
  0 opens, 0 floating routes (14,008 nets); `check_legality` 0 violations; `check_pg_connectivity` 12,041
  cells, 0 floating (VDD 80 wires/1,533 vias; VSS 252 wires/1,748 vias, up from 79/1,512 before routing:
  the 129 pins tied to VSS got wired to the ground grid; indirect evidence only).
- Worst paths now: setup is the reg2reg path `u_seq/mode_lat_reg` to `u_grid/g_row_3__g_col_1__pe/
  psum_out_reg_31_`, slack 0.00 ns MET: launch clock 0.61, capture 0.79 ns, Q delay 1.21 ns, high-fanout
  buffering about 2.6 ns, then the 32-bit RIPPLE carry chain of the accumulator adder `add_42`
  (`ad01d0/d1` cells, about 0.43 ns per bit, about 13.5 ns total), setup time 0.35, arrival 18.94 = required
  18.94. The physical margin is the 1.5 ns setup uncertainty that is subtracted. Hold worst is an input path
  `pwdata[1]` to `u_csr/src_a_reg_reg_1_`, slack 0.00 MET with `clock uncertainty 0.20`.
- WHAT THE CHECKS DID NOT DO (not silent failures, recorded):
  - Antenna: `Turn off antenna since no rule is specified` / `No antenna rules defined (ZRT-309)`: not
    checked at all; the technology file has no antenna rules for ICC2. The `adiode` cell is library
    don't-use. Needs the ratios from the DRM, or rely on the Calibre DRC deck.
  - Tie-to-rail: `not checked` in `check_routes` (the help shows no such option).
  - `check_lvs` skips `VDD`/`VSS` (`RT-203`, no valid pin shapes: the macro PG pins do not exist yet). The
    `RT-204` skips are 22 unused `paddr` bits (`[31:12]`, `[1:0]`) and the 32 east-edge `act_out` bits of
    the column-3 PEs, which have a port and no load.
  - Every via is single-cut (redundant via conversion 0%, all layers "un-mapped"): no double-via mapping in
    the setup; a yield/reliability limitation, not a DRC.
  - Coupling capacitance is lumped to ground (`extract.enable_coupling_cap false`), so no crosstalk.
  - The ICC2 checks are not a substitute for Calibre DRC/LVS (untested) and PrimeTime signoff (ff not run).
- Next: `save_block -as unpu_top_ropt`; macro `VDD`/`VSS` pins (left edge, TOP_M); filler cells `feedth`,
  `feedth3`, `feedth9` (LEF-only: `get_lib_cells` may not list them, check); outputs (netlist, LEF, GDS, SPEF,
  SDF); antenna decision; Calibre DRC/LVS; PrimeTime signoff; post-layout GLS.

### 18.21 ICC2 step 11: macro VDD/VSS pins (user's server run, 2026-10-29)

- Checkpoint `unpu_top_ropt` saved first (after `route_opt`).
- Stripe positions (`get_shapes -of_objects [get_nets $n] -filter "layer_name==TOP_M && shape_use==stripe"`):
  14 vertical TOP_M stripes, 2.24 um wide, y 5.6 to 812.0. VSS at x = 60.48, 172.48, 284.48, 396.48, 508.48,
  620.48, 732.48; VDD at x = 116.48, 228.48, 340.48, 452.48, 564.48, 676.48, 788.48 (left edge of each stripe).
- PROBLEM with the left-edge power-pin plan of 18.9: the stripes run parallel to the left edge, the nearest is
  60 um inside, and the macro interior is to be covered by OBS on all four metals, so a pin there cannot be
  reached from outside. DECISION (user, 2026-10-29): option A, power pins on the BOTTOM edge (no signal
  pins there), stripes extended to the die boundary. This replaces "LEFT: VDD/VSS on TOP_M" in 18.9.
  Rejected: B (M3 straps to the left boundary, needs rip-up and re-route), C (ask the top-level team first).
  The top-level team must be told: power pins are on the bottom edge, 14 TOP_M pins at 56 um spacing
  (alternating VSS/VDD from x = 60.48).
- Commands: `create_shape -shape_type rect -layer TOP_M -boundary {{x1 0} {x2 6.0}} -net <VDD|VSS> -shape_use
  stripe` (6.0 um tall, 0.4 um overlap with the stripe end at y = 5.6), then `create_terminal -of_objects
  <shape>` (`-port` cannot be combined with `-of_objects`; the port comes from the shape's net). Tested on one
  stripe first (VSS x = 60.48: `TM_204`, bbox {60.48 0} {62.72 6.0}, layer TOP_M), then a loop over the stripe
  list read from the database.
- MISTAKE (Planning): the loop's skip condition (`lly == 5.6`) selected the original stripes, including the
  one already extended by hand, so the VSS stripe at x = 60.48 got a second extension and a second terminal
  (`TM_218` on `RECT_50_3339`; 219 terminals, VSS 8). No DRC or connectivity effect, but a duplicate LEF pin
  rectangle. Removed with `remove_terminals [get_terminals TM_218]` and `remove_shapes [get_shapes
  RECT_50_3339]`. Result: 218 terminals (204 signal + 7 VDD + 7 VSS).
- Checks after: `check_routes` 0 DRC, 0 open nets, no "ports with no pins" warning; `check_lvs` 0 shorts, 0
  opens, 0 floating routes, and the `RT-203` skips for VDD/VSS are gone (the nets are now checked);
  `check_pg_connectivity` 0 floating cells/wires/vias/terminals (checked with the duplicate present, VDD 7 and
  VSS 8 terminals; not re-run after removing it).
- Still open: antenna (no rules), tie-to-rail not checked, single-cut vias, no crosstalk; fillers; outputs.
- Next: `save_block -as unpu_top_pins`; filler cells (`feedth`, `feedth3`, `feedth9`), then outputs and Calibre.

### 18.22 ICC2 step 12: filler cells (user's server run, 2026-10-29)

- Kit FAQ: fillers `feedth` (1 site, 0.56 um), `feedth3` (3 sites, 1.68), `feedth9` (9 sites, 5.04), class CORE,
  VDD/VSS pins, needed to avoid implant-spacing DRC. They were NOT in `scl18fs120.ndm` (534 cells = the 534
  `.lib` cells; `get_lib_cells */feedth*` found nothing; the six LEF-only cells `feedth*` and `mx08d*` had been
  dropped at library build).
- Filler library: `feedth.lef` cut from the kit LEF with awk (header + 3 macros, in `icc2_work`), built in
  `icc2_lm_shell` with `create_workspace -flow physical_only` into a separate library. First build
  `scl18fs120_fill.ndm` (cells typed `lib_cell`; `create_stdcell_fillers` warned `CHF-011`, and errored
  `CHF-010` with `-rules post_route_auto_delete`). `design_type` cannot be set in icc2_shell (`ATTR-25`);
  set in lm_shell (`foreach_in_collection c [get_lib_cells] {set_attribute $c design_type filler}` before
  `check_workspace` and `commit_workspace`): second build `scl18fs120_fillf.ndm`. The library file is written
  to the directory where lm_shell was started (first time that was the home directory; moved to `icc2_work`).
  Reference list of `unpu_lib`: `scl18fs120` + `scl18fs120_fillf` (`set_ref_libs -library unpu_lib -add <path>`;
  `-remove` takes the PATH, not the name; `save_lib` with no block open persists it; the setting did not
  persist the first time because it was not saved before the shell closed).
- Insertion: `create_stdcell_fillers -lib_cells [get_lib_cells */feedth*] -prefix FILLER -rules
  post_route_auto_delete` inserts 22,512 fillers (4,159 / 7,451 / 10,902). It is NOT a flow command: the
  fillers' VDD/VSS pins stay unconnected until `connect_pg_net -automatic` (45,024 pins). Without it
  the DRC engine reported about 17,766 false M1 shorts (`remove_stdcell_fillers_with_violation -check_only
  true` lists them in `<block>_fillers_with_violation.rpt`); after it, 1 real violation remained (a
  `feedth3` filler rail against a signal wire), fixed by `route_eco` (1 net moved: `u_grid/g_row_1__g_col_0__pe/
  mult_30/n202`). `-rules check_pnet` changed nothing (it concerns pre-routed PG nets).
- With fillers present `route_opt` cannot add or resize cells (no free site): one hold endpoint stayed 0.6 ps
  under. With the fillers typed `filler` and `post_route_auto_delete`, `route_opt` DELETES ALL fillers first
  ("Deleted 22512 filler cells") and does not put them back. So fill is the LAST step; any later
  `route_opt` removes it.
- Order that works: ... `route_opt` (no fill) -> `create_stdcell_fillers ... -rules post_route_auto_delete`
  -> `connect_pg_net -automatic` -> checks. Saved: `unpu_top_ropt2` (clean, no fillers, 0 violations),
  `unpu_top_fill1` (fillers, 0.6 ps hold residual, before the library fix), `unpu_top_fill2` (final fill).
- Final state (`unpu_top_fill2`): 22,512 fillers; `check_routes` 0 DRC / 0 open; filler check 0; `check_legality` 0
  violations; setup worst 0.00 ns MET (in2out `paddr[3]` to `prdata[2]`); hold worst `pwdata[1]` to
  `u_csr/src_a_reg_reg_1_` -0.0006 ns VIOLATED (fill adds a little capacitance), measured after the 0.2 ns
  uncertainty. DECISION (user, 2026-10-29): option A, accept and let PrimeTime decide with its own
  extraction of the filled layout; fix that one path there only if PrimeTime also reports it. Rejected: B (a
  10 ps hold pad, a constraint change needing approval) and C (ask the PM).
- Open: `OPT-209` ("unreasonable large hold violation(s)") printed twice by `route_opt` while the QoR shows no
  hold violations, cause unknown; `LGL-031` (site `unit` has no X/Y symmetry, legal orientations limited);
  the earlier `FLW-8004`; antenna rules; tie-to-rail check; single-cut vias; no crosstalk.
- Next: output files (netlist, LEF, GDS, SPEF, SDC, SDF), timing model, then Calibre DRC/LVS and PrimeTime.

### 18.23 ICC2 step 13: output files (user's server run, 2026-10-29)

All from the final block `unpu_top_fill2` (22,512 fillers, 218 terminals), written to
`/storage/EE5239G1/aagams_workspace/icc2_work/out/`. Not in git (sizes: GDS 15.7 MB, each SPEF 25.7 MB).
- Netlists (`write_verilog -hierarchy all`): `-include` and `-exclude` cannot be combined (`CMD-001`).
  `unpu_top_sim.v`: `-exclude {all_physical_cells leaf_module_declarations pg_netlist pg_objects
  supply_statements}`: 76 modules, no `.VDD`, no `feedth`, no cell stubs (the first try with only
  `-exclude {all_physical_cells}` had 180 modules = 76 + 104 empty library-cell declarations, and PG pins;
  it was overwritten). `unpu_top_lvs.v`: `-include {pg_netlist}`: 76 modules, `.VDD`/`.VSS` on instances,
  no fillers (default leaves them out), top module `module unpu_top`; the header comment says
  "Block Name: unpu_top_fill2". LVS NOTE: no filler instances in the source netlist; Calibre must accept
  that the filler cells (no devices) are layout-only.
- LEF: `write_lef -include cell` first wrote an empty shell (163 bytes, `LEFW-005`: no frame view). Fix:
  `create_frame -block_all true` (`FRAM-045/046`: all of GC M1 M2 M3 TOP_M WN XP XN blocked except pins),
  then `write_lef -include cell .../out/unpu_top.lef`: `MACRO unpu_top`, `SIZE 817.6 BY 817.6`, 206 PINs
  (204 signal + `VDD` + `VSS`), `PIN VDD` USE POWER on TOP_M with 7 rectangles at y 0..6 (x = 116.48 ...
  788.48), `OBS` over GC and M1 (full box), M2 polygon with notches at the top-edge pins, M3 and TOP_M.
  Power pin says `DIRECTION INPUT` (usually INOUT; `USE POWER` is what tools use). The macro name needs no
  rename. The frame view was saved with `save_lib`.
- SPEF: `write_parasitics -corner default|ff -output ...` writes `unpu_top_ss.spef.typ_125.spef` and
  `unpu_top_ff.spef.typ_-40.spef` (tool adds the suffix; `.spef_scenario` helper files). Both 25,737,613 bytes:
  both corners use the same `typ` RC (kit has only a typical TLUPlus).
- SDF: `write_sdf -corner default|ff`: `unpu_top_ss.sdf` 8.3 MB, `unpu_top_ff.sdf` 8.8 MB.
- SDC: `write_sdc -scenario default|ff_hold -output ...`: `unpu_top_ss.sdc`, `unpu_top_ff.sdc` (warnings about
  multiplied derates: none set).
- GDS: `write_gds -design unpu_top_fill2 -layer_map_format icc_default|icc_extended -layer_map
  .../digital_pnr_kit/snps/non_rh/4M1L/icc_gds_out_4LM.map -merge_files
  .../stdcell/fs120/4M1IL/gds/scl18fs120.gds -output_pin all .../out/unpu_top.gds`. The kit map (the only one
  in the kit) gives `GDS-017 "Wrong layer map file syntax at line 8"` in all three formats (line 8 is the
  first of four `T` text lines: `T 40 40 7 ;` ...), but the command continues and writes the file (15.7 MB).
  Checks with `strings`: 96 labels for `paddr`/`prdata`/`dma_addr` (32 each) and 110 for the other signal
  names, so every signal pin has a text label; the merge worked (unused library cells `adiode` and `mx08d1`
  appear as structures; `VDD`/`VSS` text 1,083 each, mostly the library cells' own). NOT YET KNOWN: the GDS
  layer/datatype of the pin labels (the `T` lines were rejected); Calibre LVS decides. Note `strings` needs
  `-n 3` for 3-character names.
- NOT written yet: the timing model (`.lib`) for the macro (PM question open), a final copy of the outputs
  into the repo or handed to the teammate.
- Next: find Calibre and its decks (DRC, LVS, dummy fill), the standard-cell spice netlist for LVS, run DRC,
  then LVS; PrimeTime signoff; post-layout simulation with `unpu_top_sim.v` plus `unpu_top_*.sdf`.

### 18.24 Calibre setup and first DRC (user's server run, 2026-10-29)

- Calibre 2022.4_37.20 is installed. `/home/Siemens_cshrc` has CRLF line endings (`source` fails with "Command not
  found" / "Variable name must begin with a letter"); use a cleaned copy in the home directory (`tr -d '\r' <
  /home/Siemens_cshrc > ~/siemens_cshrc_clean`). It sets `LM_LICENSE_FILE`/`MGLS_LICENSE_FILE` to
  `1717@14.139.1.126` (Synopsys uses 27020): run Calibre in a SEPARATE terminal from icc2_shell/PrimeTime. The
  install path `/home/MentorGraphics/Calibre 2022.4_37/...` has a space and does not work in the csh path; use
  `/home/mentor_tools/calibre/aok_cal_2022.4_37.20` (`setenv MGC_HOME`, `setenv CALIBRE_HOME`,
  `set path = ( $MGC_HOME/bin $path )`, `rehash`). A path entry in the shared setup files is also malformed (two
  entries glued: `.../dfII/bin/home/mentor_tools/...`).
- Decks (kit, read-only): `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/pdk/cdns/sclpdk_v3/HOTCODE/techs/ts18scl/calibre/
  t.00_00_01_scr/` (the `ts18scl_4M1L/calibre/default_scr` folder is only a link to it): `DRC_TS18SL_SCL_CALIBRE`
  (main), `DRC_TS18SLA_CALIBRE`, `DRC_TS18SLAD_CALIBRE` (memory bit-cell variants), `LVS_TS18SL_SCL_CALIBRE`,
  `ANTENNA_TS18SL_SCL_CALIBRE`, `headers/{DRC,LVS,ANTENNA,DUMMY}.header`, XRC decks. The decks under
  `/home/iit_PDK` and `/home/PDK` are TSMC 40/65 nm: NOT usable. The antenna deck answers the open "antenna
  not checked in ICC2" item. Working copy of the kit folder: `/storage/EE5239G1/aagams_workspace/calibre_run/scr`.
- Control file `calibre_run/drc.ctrl`: `#define 4M1L`, `#define BLOCK`, `#define 3V` (voltage choice is an
  ASSUMPTION: no high-voltage devices in the design; "MUST select a voltage" per the deck), `LAYOUT PATH
  .../icc2_work/out/unpu_top.gds`, `LAYOUT PRIMARY "unpu_top"`, results/report names, and an absolute `INCLUDE` of the
  copied deck. MISTAKE (Planning): the first control file used the header's variables (`DRC_TYPE`,
  `DRC_VOLTAGE`), whose translation to the deck's switches lives in the header's `#ifdef` blocks that my file did
  not include: `ERROR USER1 ... PLEASE SELECT VOLTAGE OPTION`. Fix: define the switches directly. Run:
  `calibre -drc -hier drc.ctrl |& tee drc.log` (about 160 s on 1 CPU; Ctrl-C kills it; the first attempt
  was interrupted by mistake).
- GDS precision: `ERROR: Rule file precision 1000 is not consistent with database precision 10000`. The GDS from
  `write_gds` defaulted to 0.1 nm database units. Rewritten with `write_gds -units 1000 ...`; same file size
  (fixed-size integers). The `GDS-017` layer-map message (the `T` text lines) is still printed.
- RESULT: `TOTAL RULECHECKS EXECUTED = 404`, `TOTAL RESULTS GENERATED = 0`; latch-up `LU0` 0. Layer sanity (from
  `ORIGINAL LAYER STATISTICS`): WN 34,553 (= 12,041 cells + 22,512 fillers), GC 88,680, AA 91,281, CS 383,535, M1
  238,212, M2 168,921, M3 89,542, V2 53,137, V3 53,609, MTOP 9,413, VTOP 8,104, PRBoundary 34,554 (all shapes
  flat). `ML.*` and `VL.*` (top metal, top via) rules ran with 0 results on `MTOP`/`VTOP` data.
- Limits of this DRC: `BLOCK` mode only; no dummy fill in the layout (density/DUMMY runset not run; PM question open);
  the antenna deck is a separate run; the voltage option is an assumption; GDS text-label layers still unverified
  (matters for LVS, not DRC).
- Next: antenna run, then LVS (source netlist = `unpu_top_lvs.v` converted to SPICE with `v2lvs` against the kit
  CDL `stdcell/fs120/4M1IL/cdl/scl18fs120_supply_pins.cdl`), then PrimeTime and post-layout simulation.

### 18.25 Antenna check, ICC2 antenna fix, final fill and `out2` (user's server run, 2026-10-29)

State at pause (user took a break; nothing further is running).

- Antenna deck first run on the `out/` GDS: 16 rules, 241 results (`AN.MTL.1.M2` 175, `AN.MTL.1.M3` 66). ICC2 with
  `define_antenna_rule -mode 4 -diode_mode 1 -metal_ratio 400 -cut_ratio 0` (per session, not persistent) found 137
  violations and skipped 80 input-port nets (`ZRT-311`, no gate-area data at macro ports).
- Fix: on unfilled `unpu_top_ropt2`, `route.detail.antenna_fixing_preference use_diodes`,
  `insert_diodes_during_routing true`, `diode_libcell_names adiode`, then `route_detail -incremental true`. Diodes were
  NOT inserted (`ZRT-302`: `adiode` not found or not linkable, count 0); the violations were fixed by layer hopping
  (135 -> 4 -> 0 ports; 225 nets rerouted). `check_routes` DRC 0, opens 0, antenna 0 (ICC2); `check_legality` 0.
  Saved as `unpu_top_ant` (UNFILLED). Timing: setup +0.01 ns MET, hold 0.00 ns MET.
- Final fill on the antenna-fixed design: 22,512 fillers, 45,024 PG pins connected, `check_routes` 0/0/0,
  `check_legality` 0, hold 0.00 ns MET (residual not visible at 2 digits; `-significant_digits 4` not run).
  Saved as `unpu_top_final`. NOTE: `save_block -as` keeps the in-memory name `unpu_top_ropt2`, and the later
  `save_lib` probably wrote the filled state over `unpu_top_ropt2` on disk (not verified); the unfilled reference
  is `unpu_top_ant`.
- Outputs regenerated into `icc2_work/out2/` (same commands as 18.23, `-units 1000` GDS; `GDS-017` still printed):
  `unpu_top_sim.v`, `unpu_top_lvs.v`, `unpu_top.lef`, `unpu_top_{ss,ff}.{spef.*,sdf,sdc}`, `unpu_top.gds` (15.69 MB).
  PITFALL: `create_frame -block_all true` leaves one frame per block; `write_lef -include cell` then wrote TWO
  `MACRO unpu_top` entries (stale `fill2` frame + new `ropt2` frame). Fixed by `write_lef -design unpu_top_ropt2
  -include cell`; one macro, 56,524 bytes, byte-identical to the first LEF. Do this every time.
- Calibre on `out2/unpu_top.gds` (work dir `calibre_run/run2`, copies of the control files with the `out2` path):
  DRC 404 rules, 0 results. Antenna: 16 rules, **7 results, all `AN.MTL.1.M2`** (down from 241), i.e. 4 distinct
  nets (Calibre cell/net ids): `ICV_249` net 3743 (ratio 401.0), `ICV_249` net 2309 (402.2, M2 near x=154 um,
  y=204..266 um), `unpu_top` net 2415 (403.1), `unpu_top` net 1328 (**1023.3**, gate area 0.1944 um^2, M2 perimeter
  368 um, x~811..813 um, y~109..210 um). Net 1328 = `u_grid/g_row_2__g_col_3__pe/mult_28/n27` (driver `U22/CO`,
  load `U5/A`, both `ad01d0`), an INTERNAL net, not a port net (an earlier hypothesis that the failing nets are
  port nets was wrong).
- Why ICC2 misses it: ICC2 at limit 300 flagged 60 instance ports (ratios 300..396, none above 400); at limit 100
  it flagged 750 nets but not `n27`. Kit LEF for `ad01d0`: `PIN CO ANTENNADIFFAREA 0.696` (ICC2 `diode_mode 1`
  treats it as a diode, so exempt) and `PIN A ANTENNAGATEAREA 1.823` (Calibre measures 0.1944 in the layout, about 9x
  smaller). So ICC2 uses library antenna data that is more optimistic than the layout for this cell; a tighter
  ICC2 limit cannot catch it. Other cell types affected: unknown.
- Proposed next step (not started, awaiting user): surgical fix of the 4 nets: remove their routes, give them
  `set_routing_rule -min_routing_layer M3` (M2 left only for pin access, ZRT-707 stub), `route_detail -incremental`,
  then re-fill, rewrite outputs (`out3`), re-run both Calibre checks. Needs the names of nets 3743 and 2415 (get the
  marker coordinates with `grep -n -A14 "NET=3743\|NET=2415" antenna_results.ant` in `run2`, then
  `get_nets -of_objects [get_shapes -intersect {{x y} {x+0.1 y+0.1}} -filter "layer_name==M2"]`; net 2309 near
  (154, 230)). Alternative considered: `define_antenna_rule -diode_mode 0` (ignore LEF diode credit); not tried.
- State of the open ICC2 shell when paused: block `unpu_top_ant` open in EDIT mode with antenna rule at
  `-metal_ratio 100` (probe only; do NOT save this block). Probe log: `icc2_work/ant_probe100.txt` (750 nets).
- Still to do after the antenna fix: LVS (`v2lvs` + kit CDL), PrimeTime (ss setup, ff hold), post-layout simulation,
  commit/push this note, `plan.md` update.

### 18.26 Antenna re-route, final fill 2, `out3`, Calibre `run3` (user's server run, 2026-10-30)

State at stop (user ended the day; nothing running).

- Net names for the 4 Calibre failures (marker coordinates -> `get_nets -of_objects [get_shapes -intersect ...]`):
  `u_grid/g_row_2__g_col_1__pe/N48` (Calibre 2309, 402.2; ICC2 395.2 at limit 300), `u_grid/g_row_2__g_col_3__pe/N69`
  (3743, 401.0; ICC2 394.1), `u_seq/n472` (2415, 403.1; ICC2 396.0), `u_grid/g_row_2__g_col_3__pe/mult_28/n27`
  (1328, 1023.3; not flagged by ICC2 even at limit 100). ICC2 at limit 300 flagged 60 ports (ratios 300..396); at
  limit 100, 750 nets (log `icc2_work/ant_probe100.txt`). LEF for `ad01d0`: `CO ANTENNADIFFAREA 0.696` (ICC2
  `diode_mode 1` exempts), `A ANTENNAGATEAREA 1.823` vs Calibre layout gate 0.1944.
- Fix applied on unfilled `unpu_top_ant`: `set_routing_rule -min_routing_layer M3 -min_layer_mode
  allow_pin_connection` on the 4 nets, `remove_routes -nets $bad -detail_route` (51 shapes), `route_eco`: 42 nets
  changed in total, 0 open, 0 DRC; M2 wire 323,108 -> 322,820 um. Timing unchanged (setup +0.01, hold 0.00).
- Saved blocks: `unpu_top_ant2` (unfilled, re-routed) and `unpu_top_final2` (filled). Fill: 22,512 fillers, 45,024 PG
  pins; `check_routes` DRC 0 / opens 0 / antenna 0 (ICC2, limit 400, 80 port nets skipped); `check_legality` 0.
  Timing with fill: setup 0.00 ns MET (`paddr[3]` -> `prdata[2]`), hold -0.00 VIOLATED on `pwdata[1]` ->
  `u_csr/src_a_reg_reg_1_` (the same filler-capacitance residual accepted as option A; PrimeTime decides).
  Corners unchanged: scenario `default` = corner `default` (ss, setup), `ff_hold` = corner `ff` (hold).
  Workflow that avoids overwriting blocks: `save_block -as NEW`, `close_blocks -force`, `open_block NEW`.
- Outputs `icc2_work/out3/` from `unpu_top_final2` (12 files; LEF has ONE macro using `write_lef -design
  unpu_top_final2 -include cell`; GDS 15,693,824 bytes, 4,087,279 bytes differ from `out2`; `GDS-017` still printed).
- Calibre `run3` (`calibre_run/run3`, GDS `out3`): DRC 404 rules, 0 results. Antenna 16 rules, **3 results**, all
  `AN.MTL.1.M2`, all one net: Calibre net 1329 (was 1328), VALUE 1023.28, M2 perimeter 368.38 um, gate 0.1944 um^2,
  polygon IDENTICAL to the one in `out2` (so the re-route changed nothing for this net). N48, N69, n472 are fixed.
- OPEN QUESTION (not resolved): ICC2 says `n27` is a short route: M2 stubs {804.02,147.865}-{804.30,148.48} and
  {811.30,136.825}-{811.58,137.34}, M3, TOP_M {803.94,137.14}-{804.38,148.56}; cells U22 bbox {800.8,134.4}-
  {811.44,140.0}, U5 {796.88,145.6}-{807.52,151.2} (about 6 um apart). It has NO long M2 wire. Calibre's polygon for
  the net is a ~100+ um structure at x 811.3..813.3 um, y 109.7..210.7+ um (visible vertices only: strip
  x 811.30-811.58 up to y 134.82, wide piece x 811.58-813.26 y 134.82-150.22, strip up to y 203.1, jog to x 812.14
  y 210.7, continues). ICC2 M2 shapes near: `mult_28/n35` x 810.74-811.02 y 109.6-120.4; `paddr[7]` x 810.74-811.02
  y 126.4-130.2; `u_csr/n248` x 810.74-811.02 y 143.8-304.8; `paddr[4]` x 811.30-811.58 y 210.4-289.1.
  `get_shapes -intersect` proved incomplete (it did not list the n27 stub inside its window), so do not trust it
  for connectivity. Possible causes: Calibre merges touching pieces of other nets into this net (would be a short,
  LVS will show), or non-signal shapes (pins, cell geometry) are in the polygon. NEXT, before changing anything:
  `sed -n '6,70p' antenna_results.ant` in `run3` (full 20-vertex outline and the other layers' polygons) and an ICC2
  all-layer `get_shapes -intersect {{812 138} {812.4 142}}` listing layer, net, shape_use, bbox.
  Candidate fixes if it is a genuine antenna: route the net on TOP_M, a buffer in the net, or an explicit diode.
- ICC2 state when stopped: `unpu_top_final2` open in edit mode (frame view created after the last `save_lib`; not
  needed). Exit with `close_blocks -force` then `exit`, no save.
- Still to do: antenna 3 -> 0, LVS (`v2lvs` + kit CDL), PrimeTime, post-layout simulation, commit/push this note
  (§18.25 and §18.26 are uncommitted), `plan.md`.
