# Task 017 — Interim enable/start-trigger protocol (provisional)

## Why this task exists, and why it's provisional

The user is talking to the SoC team tomorrow (2026-09-20 → 21) to settle
how Pico's decoder actually signals the NPU. Until then, the user wants
to implement one concrete option the PM sketched, so there's a working
interface to test against rather than waiting idle. **This is explicitly
provisional** — it may be revised or reverted after tomorrow's
conversation. Keep the change as small and reversible as possible; don't
gold-plate an interim design.

The PM's sketch (`docs/planning/plan.md`, open question 5), quoted
exactly:
> - enabled signal implies that the NPU is the one Pico wants to
>   communicate with.
> - Then processor writes all the required registers in next few cycles
>   (as agreed between pico and npu).
> - Then processor asserts a signal - ready - and that indicates that
>   npu is ready to compute.

**Naming note:** the PM's third signal is called "ready," but that
collides with this design's own established meaning of "ready" —
`mem_ready`/`dma_ready` already mean "slave has completed this
transaction," the opposite direction and a different concept from
"processor is telling us to start." Using the same word for both would
be a standing source of confusion in the RTL and its comments. This task
names it `npu_start_req` instead. Flag this back if the SoC-team
conversation settles on different naming — it's a rename, not a
redesign, if so.

## This reopens the freeze — scope it as tightly as that implies

RTL was frozen at commit `87d31bf` (`docs/freeze-report.md`). This task
reopens it for exactly one file. **Every other module — `unpu_pe`,
`unpu_grid`, `unpu_skew`, `unpu_deskew`, `unpu_seq`, `unpu_wbuf`,
`unpu_actbuf`, `unpu_dma`, `unpu_csr`, `unpu_slave` — must not change.**
The design below is deliberately built to make that possible: both new
signals are handled entirely by gating/combining existing wires inside
`unpu_top`, not by changing any submodule's own behavior or interface.
If you find yourself needing to touch a submodule to make this work,
stop — that means the design below has a gap, not that the submodule
needs to flex.

## Files

- Edit `rtl/unpu_top.sv` only.
- Edit `tb/unpu_top_tb.sv` — **required**, not optional: every existing
  directed and CRV case in this file currently drives register access
  straight through `mem_*` with no gating signal. Once `npu_enable`
  gates that path, every one of those cases will silently do nothing
  (reads return 0, writes have no effect) unless the testbench is
  updated to assert `npu_enable` around its register traffic. This is
  the same situation task 011 was in with `unpu_seq_tb.sv` — the old
  testbench cannot pass unmodified against the new interface, so
  updating it is required, not a scope violation.

## The two new ports

```systemverilog
  input  logic npu_enable,     // decoder: "this bus traffic is addressed to the NPU" (PM's "enabled")
  input  logic npu_start_req,  // processor: "registers are written, start computing" (PM's "ready", renamed — see naming note above)
```

## Behavior

### `npu_enable` gates the register-access path

Don't wire the top-level `mem_valid` straight into `unpu_slave.mem_valid`
anymore. Gate it:

```systemverilog
  logic slave_mem_valid;
  assign slave_mem_valid = mem_valid && npu_enable;
```

...and instantiate `unpu_slave` with `.mem_valid(slave_mem_valid)`
instead of `.mem_valid(mem_valid)`. Everything else about
`unpu_slave`'s instantiation is unchanged. This means: when
`npu_enable=0`, any access on the bus is treated exactly like an
unmapped/reserved offset already is (`unpu_slave`'s own existing,
already-tested behavior — task 010) — reads return 0, writes have no
effect. `unpu_top`'s own `mem_ready` output still ties high on every
cycle regardless of `npu_enable` (it's `unpu_slave.mem_ready`, wired
straight through, and that module already ties it high unconditionally
— task 010) — so this never introduces a hang, consistent with every
"never stall the bus" reasoning already in this design.

### `npu_start_req` is an additional trigger, not a replacement

The existing `npu_ctrl` bit-0 write-1-to-pulse START (via `unpu_csr`,
already fully built and tested) **keeps working exactly as before** —
don't remove or gate it. `npu_start_req` is a second, independent way to
reach the same place: a rising edge on it, while `npu_enable` is
asserted, generates a one-cycle pulse that's OR'd with `unpu_csr`'s own
`start_pulse` before driving `unpu_seq.start`. Both paths existing
side by side is intentional — it keeps the already-verified register-
write START path as a fallback and doesn't require deciding, before
tomorrow's conversation, which one the real system will actually use.

```systemverilog
  logic npu_start_req_q;
  logic start_req_pulse;
  logic seq_start;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      npu_start_req_q <= 1'b0;
    else
      npu_start_req_q <= npu_start_req;
  end

  assign start_req_pulse = npu_start_req && !npu_start_req_q && npu_enable;
  assign seq_start       = start_pulse || start_req_pulse;
```

Wire `unpu_seq`'s `.start` port to `seq_start` instead of `start_pulse`
directly. `start_pulse` (the `unpu_csr` output) still exists and is
still wired into `unpu_csr`'s own instantiation exactly as before —
only what feeds `unpu_seq.start` changes.

**Known trap, same class as several already logged in this project**
(task 007's swap-cycle staleness, task 010's re-pulse boundary, task
011's `rd_row` combinational-vs-registered mixup): the edge detector
above is registered (`npu_start_req_q` lags by one cycle), so
`start_req_pulse` fires the cycle *after* `npu_start_req`'s rising edge,
not the same cycle. Get this backwards (e.g. by computing the pulse
combinationally from the current-cycle value alone, or double-
registering it) and the timing is either one cycle early or one cycle
late relative to what a real external device asserting `npu_start_req`
would expect. Write a directed test that checks the exact cycle
`seq_start` pulses relative to the cycle `npu_start_req` was first
observed high — don't just check that `unpu_seq` eventually starts.

## Testbench (`tb/unpu_top_tb.sv`)

- Add `npu_enable`/`npu_start_req` to the DUT instantiation and drive
  them from the testbench.
- **Every existing directed and CRV case**: wrap the register-write/poll
  sequence with `npu_enable=1` (assert before the first register access,
  hold through the last one — deassert after is fine, doesn't matter
  either way per the design above). This is a mechanical update, not a
  redesign of any test's logic — the sequencing and checks stay the
  same, they just need `npu_enable` held around them now.
- **New directed case — `npu_enable=0` blocks access**: attempt a
  register write with `npu_enable=0`, confirm the register's value is
  unaffected (read it back, still shows the reset/previous value) and
  `mem_ready` is still `1` every cycle (bus never hangs).
- **New directed case — `npu_start_req` triggers a real matmul**:
  run `cross_terms` through the full pipeline exactly like the existing
  anchor case, but configure registers as usual (SIGNED/dims/pointers,
  `npu_enable` held throughout) and trigger START via a rising edge on
  `npu_start_req` instead of writing `npu_ctrl` bit 0. Confirm the same
  correct result as the existing `npu_ctrl`-write path produces.
- **New directed case — edge-timing check**: the specific one-cycle
  boundary named in the known-trap note above — confirm `seq_start`
  (or its observable effect, `unpu_seq` leaving `IDLE`) happens exactly
  one cycle after `npu_start_req`'s rising edge, not the same cycle, not
  two cycles later.
- **New directed case — `npu_start_req` without `npu_enable`**: pulse
  `npu_start_req`'s rising edge while `npu_enable=0`, confirm no start
  occurs (this is what the `&& npu_enable` term in `start_req_pulse`
  exists for — test that it's actually doing something, not just present
  in the RTL).
- **Existing `npu_ctrl`-bit-0 START path still works**: keep at least
  one of the existing cases using the original register-write START
  unchanged, proving both trigger paths coexist correctly.
- CRV: re-run all 64 `crv_*` cases as before, now with `npu_enable`
  wrapped around each case's register traffic — this is the mechanical
  update above applied at CRV scale, not a new CRV axis. No need to add
  randomized `npu_enable`/`npu_start_req` timing variation in this
  pass — that's more thoroughness than an interim, soon-to-be-revisited
  design needs; keep this task's scope to "the new ports work
  correctly," not "the new ports are exhaustively randomized."

## Acceptance

- All directed cases (existing + the four new ones above) pass.
- All 64 CRV cases pass with `npu_enable` wrapping register traffic.
- Full regression on every other testbench (unchanged) still green —
  confirms no submodule was touched.
- `git diff --stat rtl/` shows only `unpu_top.sv` changed.
- Simulate clean under Verilator, consistent with every task since 006.

## Out of scope

- No change to any file other than `rtl/unpu_top.sv` and
  `tb/unpu_top_tb.sv`.
- No randomized `npu_enable`/`npu_start_req` timing sweep — interim
  design, keep the scope matched to that.
- No decision about which START path (register-write vs. discrete pin)
  the real system will actually use — that's tomorrow's SoC-team
  conversation. This task keeps both working, deliberately, so nothing
  here needs to anticipate that answer.
