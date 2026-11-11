# Task 010 — Native slave (was: APB slave FSM)

## Goal

Build `unpu_slave`, the block that turns the CPU-facing (and SPI-debug-
backdoor-facing) native memory-bus transactions into the register-level
`csr_sel`/`csr_wdata`/`csr_wen`/`csr_rdata` port `unpu_csr` already
exposes (task 009). This is plan.md step 13, listed there as "native
slave FSM (was: APB slave FSM)" — **superseded, not renamed**: Q7
confirmed the CPU↔NPU interface is native (PicoRV32 convention), not
APB, a different protocol, not a drop-in rename of the old design.

## A finding worth stating up front: this doesn't need to be a multi-state FSM

The plan (and the notebook's now-superseded §05 B1 APB design) both frame
this as an "FSM." It isn't one, once you follow through what's already
true of the pieces on either side of it:

- `unpu_csr` (task 009) already reads combinationally — `csr_rdata` is
  valid off `csr_sel` with no read-enable, no settle cycle, ever.
- `unpu_csr` already commits a write in one cycle off a single
  `csr_wen` pulse.
- The notebook's own APB design decided `pready` tied high — "a
  configuration register has no reason to stall a CPU," and, separately,
  "the master might be the SPI debug path, which we must never hang."
  Both of those reasons carry over unchanged to the native protocol.

Put those together and the correct design is **pure combinational glue,
no sequential logic in this module at all**: tie the native `ready`
signal high, decode the low address bits straight into `csr_sel`, gate
`csr_wen` on `valid && wstrb != 0`, wire `csr_rdata` straight out as
`rdata`. Don't invent states, a hold register, or extra latency this
module doesn't need — that would work against the exact "never stall,
never hang" property the notebook's own reasoning (and the SPI-backdoor
constraint in `docs/session-handoff.md` §3) is built around. The "FSM"
framing is about the *job* (bus protocol → register access), not a
mandate that the RTL have multiple states.

## Interface and implementation

```systemverilog
module unpu_slave (
  input  logic         clk,
  input  logic         rst_n,

  // Native slave port. Same PicoRV32-convention signal shapes as
  // unpu_dma's master port (docs/session-handoff.md §4/§5): wstrb==0
  // means read; rdata is valid the same cycle as valid&ready.
  input  logic [31:0]  mem_addr,
  input  logic [31:0]  mem_wdata,
  input  logic [3:0]   mem_wstrb,
  input  logic         mem_valid,
  output logic [31:0]  mem_rdata,
  output logic         mem_ready,

  // Register-level port -- straight into unpu_csr, no protocol here
  output logic [9:0]   csr_sel,
  output logic [31:0]  csr_wdata,
  output logic         csr_wen,
  input  logic [31:0]  csr_rdata
);

  assign mem_ready = 1'b1;
  assign csr_sel   = mem_addr[11:2];
  assign csr_wdata = mem_wdata;
  assign csr_wen   = mem_valid && (mem_wstrb != 4'h0);
  assign mem_rdata = csr_rdata;

endmodule
```

That's the reference design — implement it (or something behaviorally
identical), don't feel obligated to add structure. Two assumptions baked
into it, both flagged so they're easy to revisit if wrong rather than
buried:

1. **Address decode assumes `mem_addr` is already known to be in our
   window whenever `mem_valid` is asserted** — `csr_sel` just takes
   `mem_addr[11:2]` (the low 12 bits, the 4 KB window's word offset) and
   never checks the `0x4000_` prefix. This mirrors the APB design's own
   "decode `paddr[7:2]`" (already-relative addressing from an upstream
   bridge) and is the natural reading of `docs/planning/plan.md`'s still-
   open question ("does the 0x4000_0000–0x4000_0FFF window still apply
   unchanged... or does removing APB change how the window is decoded at
   the top level?") — if that question resolves to "no, we must check
   the prefix ourselves," it's a one-line change to this module, not a
   restructure.
2. **Any nonzero `mem_wstrb` commits the full 32-bit `mem_wdata`, no
   partial-byte merge.** Same simplification `unpu_dma` already made
   (task 008: "no partial writes in this design") — our registers are
   all firmware-facing 32-bit values a `sw` will target; don't build
   byte-merge logic for a case that shouldn't arise.

## Files

- Create `rtl/unpu_slave.sv`
- Create `tb/unpu_slave_tb.sv`

Do not modify `rtl/unpu_csr.sv` or any other existing file.

## Testbench (`tb/unpu_slave_tb.sv`)

Instantiate `unpu_slave` **with a real `unpu_csr`** wired to its
register-level port (not a mock/shadow of `unpu_csr` — the module under
test is a thin pass-through, so the simplest correct test structure is
the real pair together, checked against the same kind of shadow model
task 009's testbench already built for expected register semantics,
extended to also model the native-bus dispatch rule: `wstrb==0` → read,
nonzero → full-word write, `valid` gates everything).

### Directed

- Write then read back a few real registers through the native port
  (`src_A`, `npu_ctrl`), confirming `unpu_csr`'s own semantics (task 009)
  come through unchanged — START self-clears, `npu_status` stays
  read-only, etc.
- `wstrb==0` on an address that was just written: confirms a read, not a
  second write (the value doesn't change even though `mem_wdata` may
  still be driven with something on the bus).
- Any nonzero `wstrb` (try more than one pattern — `4'hF`, `4'h1`,
  `4'h3`) commits the *full* `mem_wdata`, confirming the no-partial-merge
  simplification is what's actually built, not silently doing per-byte
  merge or dropping the write.
- `mem_valid=0` with `mem_wstrb` nonzero: confirm no write occurs —
  `csr_wen` must gate on `valid`, not fire off `wstrb` alone.
- Sparse/idle pacing: hold `mem_valid` low for an arbitrary run of
  cycles (mimicking the SPI debug backdoor's "arbitrarily slow" master,
  `docs/session-handoff.md` §3), then assert it — confirm the very next
  cycle completes the transaction (`mem_ready` was never the thing making
  the master wait; only the master's own pacing was).
- **`mem_ready` is `1'b1` on every single cycle of the entire run,
  regardless of state** — assert this directly, it's the actual "never
  hang" guarantee, worth checking as its own property rather than only
  inferring it from transactions completing.
- Reserved-offset access through the native port (`mem_addr[11:2]` = 8,
  and one near the top of the window, e.g. 1023): reads 0, writes have no
  effect on any real register — re-confirms task 009's reserved-range
  behavior survives the native-bus translation.

### Plus CRV

Randomized access pacing (random idle-cycle gaps between transactions,
0 up to a generous bound — mimicking arbitrary backdoor slowness) *and*
randomized read/write sequencing (random `csr_sel`-equivalent address,
random data, random choice of read vs. write via `wstrb`), self-checked
against the shadow model. At least 64 iterations, seeded (e.g.
`32'h5eed000a`, or your own draw — print whichever), reproducible.

### Regression

`unpu_pe_tb`, `unpu_grid_tb`, `unpu_skew_tb`, `unpu_stall_tb`,
`unpu_seq_tb`, `unpu_buf_tb`, `unpu_dma_tb`, `unpu_csr_tb` all still pass
unchanged.

## Acceptance

- All directed cases pass, including the standalone `mem_ready==1`
  property check.
- CRV passes against the shadow model, ≥64 iterations, seed printed.
- Full regression green.
- Simulate clean; state which simulator (Verilator has been used the
  last four tasks — continue unless the open tooling decision in
  `docs/planning/plan.md` changes).

## Out of scope

- No top-level address-window decode (`0x4000_xxxx` prefix checking) —
  see assumption 1 above; flag back if you think this task needs it
  rather than building it in unasked.
- No `unpu_seq`/`unpu_dma` integration (step 14).
- Don't touch `rtl/unpu_csr.sv` or any other existing file.
