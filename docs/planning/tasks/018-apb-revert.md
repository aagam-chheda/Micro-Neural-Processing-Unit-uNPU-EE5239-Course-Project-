# Task 018 — Revert CPU↔NPU interface from native to APB

## Why this task exists

The user, the PM, and the SoC-top team met and decided: the CPU↔NPU
register interface reverts from native (PicoRV32-convention) back to
APB. `docs/session-handoff.md` §5 originally resolved Q7 to native for
**both** the DMA↔SRAM port and the CPU↔NPU register port; this task
reverses only the second half. **The DMA↔SRAM master port
(`unpu_dma`'s port, `dma_*` at `unpu_top`) is unaffected and stays
native** — the decision was specifically about "communication between
the NPU and the Pico CPU," not the SRAM-arbiter side. If that scope
understanding is wrong, stop before touching `unpu_dma.sv` or its
`unpu_top` wiring — flag it back rather than extending this task's
blast radius on an assumption.

This also **fully supersedes task 017**'s provisional `npu_enable`/
`npu_start_req` protocol. That was explicitly built as one hedge ahead
of the SoC-team conversation (`docs/planning/tasks/017-interim-enable-
start.md`'s own framing: "may be revised or reverted"); the conversation
happened, and APB is the actual answer. Remove both signals entirely —
APB's own `psel`/`penable` handshake already provides everything they
were approximating (`psel` is target identification, exactly what
`npu_enable` was standing in for; `penable` qualifies real access from
setup, and START stays a register write over the bus like it always
was — no discrete "start" signal needed, so `npu_start_req` isn't
replaced by anything, it's just gone).

**This reopens RTL freeze** (`docs/freeze-report.md`, commit `87d31bf`,
already reopened once by task 017 and now reopened again). Scope it as
tightly as the design below makes possible.

## The good news: `unpu_csr` doesn't change at all

Task 009 built `unpu_csr` **deliberately bus-protocol-agnostic** — a
plain `csr_sel[9:0]`/`csr_wdata`/`csr_wen`/`csr_rdata` register-level
port, with literally no awareness of what talks to it. That decision
pays off directly here: an APB slave decoding down to that exact same
port is a drop-in replacement for the native slave that used to. **Do
not touch `rtl/unpu_csr.sv`.** The 8-register map, all offsets, the
START/SIGNED/DONE/ERROR semantics — none of it changes. This task is a
bus-transport swap, not a register-map or semantics change.

## The APB design (notebook §05 B1, still valid — that section predates the native pivot and is relevant again)

Quoted from `docs/unpu-notebook.html`, still correct except the address
width noted below:
> APB is deliberately the simplest bus in AMBA. Two phases: SETUP
> (`psel`=1, `penable`=0) then ACCESS (`psel`=1, `penable`=1). The slave
> completes by driving `pready`=1 during ACCESS. No bursts, no IDs, no
> out-of-order.
>
> Decided: `pready` tied high — a configuration register has no reason
> to stall a CPU, and the master might be the SPI debug path, which we
> must never hang. Unmapped offsets read as zero and ignore writes —
> never stall them. `NPU_CTRL[0]` START is write-1-to-pulse. `NPU_STATUS`
> writes are silently discarded.

Every one of those decisions is **already implemented in `unpu_csr.sv`**
(task 009) — this task doesn't re-decide any of them, just needs to not
break them.

**One correction to the notebook**: it says "decode `paddr[7:2]`" — that
was sized for the old 5-register design's smaller window. The current,
already-built `unpu_csr` takes a 10-bit `csr_sel` (the actual 4 KB
window, 1024 words) — use `paddr[11:2]`, matching what's already built,
not the notebook's stale bit range.

**Address-decode assumption carries over unchanged** from task 010's
native slave, now re-confirmed by the PM's own answer on this exact
point (`docs/session-handoff.md` §16): an external decoder asserts our
`psel` specifically — that decoder's job (and APB's own convention) is
exactly "generate a peripheral-specific select," so `csr_sel =
paddr[11:2]` with no `0x4000_` prefix check remains correct.

### Because of `pready` tied high, this is (again) pure combinational glue

Same finding as task 010's native slave, worth restating because it's
the reason this task is smaller than it might look: with `pready` always
high, every transaction resolves in a single ACCESS cycle, and `unpu_csr`
already reads/writes in a single cycle. No sequential logic is needed —
trust the master to sequence SETUP before ACCESS (standard APB
discipline; this slave doesn't need to independently track which phase
it's in), and react combinationally to whatever's presented:

```systemverilog
module unpu_apb (
  input  logic         clk,
  input  logic         rst_n,

  // APB slave port
  input  logic [31:0]  paddr,
  input  logic [31:0]  pwdata,
  input  logic         pwrite,   // 1 = write, 0 = read
  input  logic         psel,
  input  logic         penable,
  output logic [31:0]  prdata,
  output logic         pready,

  // Register-level port -- straight into unpu_csr, unchanged (task 009)
  output logic [9:0]   csr_sel,
  output logic [31:0]  csr_wdata,
  output logic         csr_wen,
  input  logic [31:0]  csr_rdata
);

  assign pready    = 1'b1;
  assign csr_sel   = paddr[11:2];
  assign csr_wdata = pwdata;
  assign csr_wen   = psel && penable && pwrite;
  assign prdata    = csr_rdata;

endmodule
```

That's the reference design — implement it or something behaviorally
identical. `csr_wen` gating on `penable` (not `psel` alone) is what
correctly refuses to commit a write during SETUP, before the master has
actually reached the ACCESS phase — get this wrong (e.g. gate on `psel`
alone) and a write commits one phase early, using `pwdata`/`paddr` that
may not have settled yet.

No `PSTRB` (byte-lane strobes): every write is a full-word write, no
partial-byte merge — same simplification `unpu_dma` (task 008) and the
old native slave (task 010) both already made, carried over for
consistency. No `PSLVERR`: every transaction returns success, matching
the "never stall, never error, a stray pointer shouldn't hang the SoC"
philosophy already built into `unpu_csr`'s unmapped-offset handling.

## Files

- **Create** `rtl/unpu_apb.sv` (the module above).
- **Delete** `rtl/unpu_slave.sv` and `tb/unpu_slave_tb.sv` — the native
  slave is retired, not kept alongside. Confirm via `git status`/`git
  log` that the deletion is clean (recoverable from history if ever
  needed, not a concern to work around).
- **Create** `tb/unpu_apb_tb.sv` (replaces `unpu_slave_tb.sv`'s role;
  see below).
- **Rewrite** `rtl/unpu_top.sv`'s port list and instantiation (see
  below).
- **Rewrite** `tb/unpu_top_tb.sv` to drive the DUT via APB instead of
  native `mem_*`, and drop the four task-017-specific directed cases
  that no longer apply (see below).
- Small mechanical fix while in the area: `CLAUDE.md`'s "Repo layout"
  section (fixed once already in task 016, now needs the reverse edit)
  — swap `unpu_slave.sv` back out for `unpu_apb.sv` in the file list.
  Don't touch anything else in `CLAUDE.md`.

Do not modify `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`,
`rtl/unpu_deskew.sv`, `rtl/unpu_seq.sv`, `rtl/unpu_wbuf.sv`,
`rtl/unpu_actbuf.sv`, `rtl/unpu_dma.sv`, or `rtl/unpu_csr.sv`. None of
them have any awareness of the CPU-facing bus protocol, and none of
their ports reference it.

## `unpu_top.sv` changes

**Remove entirely**: the native slave port (`mem_addr`/`mem_wdata`/
`mem_wstrb`/`mem_valid`/`mem_rdata`/`mem_ready`), the task-017 ports
(`npu_enable`/`npu_start_req`), the `slave_mem_valid` gating logic, the
`npu_start_req_q`/`start_req_pulse`/`seq_start` edge-detector logic, and
the `unpu_slave` instantiation.

**Add**: the APB port (`paddr`/`pwdata`/`pwrite`/`psel`/`penable`/
`prdata`/`pready`) at the top level, and an `unpu_apb` instantiation
wired to it and to the same `csr_sel`/`csr_wdata`/`csr_wen`/`csr_rdata`
nets that already exist (these net declarations don't change — only
what drives/reads them does).

**Revert**: `unpu_seq`'s `.start(...)` port goes back to
`.start(start_pulse)` directly — `start_pulse` is `unpu_csr`'s own
output, completely unchanged; only the now-removed `seq_start`
OR-combination (task 017) goes away.

**Unchanged**: everything from `unpu_csr` downstream — `unpu_seq`,
`unpu_dma`, `unpu_wbuf`, `unpu_actbuf`, `unpu_skew`, `unpu_grid`,
`unpu_deskew`, and the entire `dma_*` native master port. Not one wire
in that part of the file should need to move.

## `tb/unpu_apb_tb.sv`

Same shape as task 010's `unpu_slave_tb.sv` (which this replaces),
translated to APB mechanics. Instantiate `unpu_apb` with a real
`unpu_csr`.

### Directed
- Write then read back real registers (`src_A`, `npu_ctrl`) through a
  proper SETUP-then-ACCESS sequence, confirming `unpu_csr`'s semantics
  (START self-clears, `npu_status` stays read-only) survive the APB
  translation unchanged.
- **SETUP-phase write must not commit**: assert `psel=1, penable=0,
  pwrite=1` with real data on `pwdata` for one or more cycles, confirm
  no register changes; only once `penable=1` is also asserted does the
  write land. This is the specific thing `csr_wen`'s `&& penable` term
  exists to prevent — test that it actually does.
- A read (`pwrite=0`) during ACCESS doesn't disturb any register.
- Any nonzero-vs-zero `pwrite` dispatch correctly distinguishes
  read/write (APB doesn't have a `wstrb`-style field here, `pwrite` is
  the whole story — confirm it's being read correctly, not inverted).
- Sparse/idle `psel` pacing (mimicking the SPI debug backdoor's
  arbitrary slowness, same property task 010 tested for the native
  slave) — confirm no dependency on tight timing.
- `pready==1` on every single cycle of the run, checked as its own
  standalone property (same discipline task 010 used for `mem_ready`).
- Reserved-offset access (`paddr[11:2]` outside 0–7): reads 0, writes
  have no effect.

### Plus CRV
Randomized access pacing and randomized read/write sequencing (random
address, random data, random `pwrite`), self-checked against a shadow
model extending task 009's — at least 150 iterations (matching or
exceeding the native slave's own bar from task 010), seeded and printed.

## `tb/unpu_top_tb.sv` changes

Same test *content* as task 012 built and task 017 extended — same
directed cases (`cross_terms`, `seq_m1`/`seq_k1`/`seq_n1`/`seq_mixed`,
illegal-config recovery, sparse polling) and the same 64-case CRV sweep
with randomized addresses and DMA-side back-pressure — but every
register access now goes through a proper APB SETUP→ACCESS sequence
instead of native `mem_valid`/`wstrb`. **Drop the four task-017-specific
directed cases** (`npu_enable=0` blocks access, `npu_start_req` triggers
a matmul, the edge-timing boundary, `npu_start_req` without
`npu_enable`) — those signals don't exist anymore, so those tests have
nothing left to test.

## Acceptance

- All `unpu_apb_tb.sv` directed cases + ≥150 CRV iterations pass.
- All `unpu_top_tb.sv` directed cases (task 012's set, re-expressed over
  APB) pass; all 64 CRV cases pass.
- `git status` confirms `rtl/unpu_slave.sv`/`tb/unpu_slave_tb.sv` are
  deleted and no other file under `rtl/` besides `unpu_top.sv` (and the
  new `unpu_apb.sv`) changed.
- `CLAUDE.md`'s repo-layout listing matches `ls rtl/*.sv` exactly.
- Full regression on every other, untouched testbench (`unpu_pe_tb`
  through `unpu_dma_tb`, `unpu_csr_tb`, `unpu_seq_tb`, `unpu_buf_tb`)
  still green.
- Simulate clean under Verilator, consistent with every task since 006.

## Out of scope

- No change to the DMA↔SRAM native master port or `unpu_dma.sv` — this
  task is CPU-facing only. Flag back if that scope assumption is wrong.
- No change to the 8-register map, offsets, or any register semantics —
  `unpu_csr.sv` is untouched.
- No firmware changes (none exist yet).
- Don't touch any file not listed above.
