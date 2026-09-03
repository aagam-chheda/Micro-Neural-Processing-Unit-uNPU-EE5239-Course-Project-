# uNPU — Project 2, Frankenstein 180 nm IP-Validation SoC

Course project EE5239. A 4×4 INT8 weight-stationary systolic matrix-multiply
accelerator, taken from RTL to a DRC/LVS-clean hard macro on SCL 180 nm.

## Read this first

Before doing anything substantive, read `docs/session-handoff.md`. It carries
every decision made so far, the answers received from the PM, and what is still
open. The full design reference is `docs/unpu-notebook.html` — open it in a
browser rather than reading the raw HTML unless you need a specific fact.

## Hard constraints — do not violate without an explicit decision

- **RTL is SystemVerilog.** The course brief says Verilog, but the PM has
  confirmed SystemVerilog is acceptable. Stick to the **synthesisable subset** —
  `logic`, `always_ff` / `always_comb`, packed structs, enums for FSM states,
  interfaces only if Genus and IC Compiler both handle them cleanly. Verify with
  a synthesis run early rather than late; anything Genus rejects is not worth
  the elegance.
- **Firmware is bare-metal C.**
- The `unpu_top` port list is **frozen** (see handoff doc). Adding pins requires
  instructor approval and would force re-hardening the macro.
- Register map: the five specified offsets (0x00–0x10) **do not move**.
  Additions go at 0x14 and 0x18 inside our 0x4000_0000–0x4000_0FFF window.
- Target clock: **50 MHz**. This means a **single-stage PE** — do not pipeline
  the multiplier. Pipelining changes the skew depths and every number in the
  timing contract.
- Accumulator is **32 bits** throughout.

## The timing contract

Every module must agree with these four equations. They are derived, not chosen.

```
A[m][k] enters west edge of row k     at cycle  m + k
A[m][k] arrives at PE(k,j)            at cycle  m + k + j
C[m][j] leaves south edge of column j at cycle  m + j + 4
whole row C[m][*] valid after de-skew at cycle  m + 7
total cycles for a pass of M rows              M + 7
```

Skew FIFO depths are 0/1/2/3 on the input side, 3/2/1/0 on the output side.
If a change would alter any of the above, stop and raise it — it is a
cross-cutting change, not a local one.

## Repo layout

```
rtl/          Verilog RTL           (unpu_pe.v, unpu_grid.v, unpu_skew.v,
                                     unpu_deskew.v, unpu_dma.v, unpu_actbuf.v,
                                     unpu_wbuf.v, unpu_apb.v, unpu_csr.v,
                                     unpu_seq.v, unpu_top.v)
tb/           Testbenches, assertions, SoC harness
model/        C golden model
fw/           Bare-metal C firmware
constraints/  SDC
syn/          Genus scripts and reports
pnr/          IC Compiler scripts and reports
scripts/      Utility scripts
docs/         Design notebook, simulator, handoff, planning output
```

## Conventions

- Signal names in prose are written exactly as in RTL: `dma_ready`, not "the
  ready signal".
- Cycle numbers are relative to the first activation injection unless stated.
- One module per file, filename matches module name.
- No module lands on `main` until its unit test passes.

## Two-session protocol

Two Claude Code sessions run against this repo.

- **Planning** decides what to do next and writes prompts for Execution. It
  writes only to `docs/planning/` and may edit `docs/session-handoff.md`. It
  does not edit RTL, testbenches, firmware or scripts.
- **Execution** implements. It writes code anywhere except `docs/planning/`.

At session start, read your role file: `docs/roles/planning.md` or
`docs/roles/execution.md`.

If you are unsure which session you are, ask before writing anything.
