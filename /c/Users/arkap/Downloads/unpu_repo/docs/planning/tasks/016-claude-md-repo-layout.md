# Task 016 — Fix CLAUDE.md's stale "Repo layout" section

## Goal

Task 015 (RTL freeze) found this while doing a repository hygiene audit
and correctly reported it rather than fixing it in-scope. Small, direct
follow-up: `CLAUDE.md`'s "Repo layout" section lists `.v` extensions and
a module that was removed from the design, and is missing one that
exists. Documentation-only, no design question, no decision needed.

## The problem, exactly

Current text (`CLAUDE.md` lines 57–72):

```
rtl/          Verilog RTL           (unpu_pe.v, unpu_grid.v, unpu_skew.v,
                                     unpu_deskew.v, unpu_dma.v, unpu_actbuf.v,
                                     unpu_wbuf.v, unpu_apb.v, unpu_csr.v,
                                     unpu_seq.v, unpu_top.v)
```

Wrong in three ways:
1. Every extension is `.v`. CLAUDE.md's own "Hard constraints" section
   two screens up requires SystemVerilog (`.sv`) — every file actually
   delivered is `.sv`.
2. `unpu_apb.v` doesn't exist and never will — APB was removed from the
   design entirely when the CPU↔NPU interface was confirmed native
   (`docs/session-handoff.md` §5). Its replacement, `unpu_slave.sv`
   (task 010), isn't listed at all.
3. Nothing in `tb/` is listed by name (fine, that's consistent with how
   the section already treats `tb/` — just noting it wasn't part of what
   needed fixing).

## Files

- Edit `CLAUDE.md`, "Repo layout" section only.

## What to change it to

The eleven files actually delivered, `.sv`, alphabetical or build-order
(your call, match whatever the rest of the section's style implies):

```
rtl/          SystemVerilog RTL     (unpu_pe.sv, unpu_grid.sv, unpu_skew.sv,
                                     unpu_deskew.sv, unpu_dma.sv,
                                     unpu_actbuf.sv, unpu_wbuf.sv,
                                     unpu_csr.sv, unpu_seq.sv,
                                     unpu_slave.sv, unpu_top.sv)
```

Double-check this list against `ls rtl/` before committing — don't
transcribe it from this task file if the two disagree, `ls` wins.

## Acceptance

- `CLAUDE.md`'s repo-layout listing matches `ls rtl/` exactly, in
  extension and file set.
- No other section of `CLAUDE.md` touched.
- No RTL/testbench file touched.

## Out of scope

- No other CLAUDE.md staleness to chase here — this task is scoped to
  exactly the finding task 015 reported. If you notice something else
  stale while in the file, report it rather than fixing it inline.
