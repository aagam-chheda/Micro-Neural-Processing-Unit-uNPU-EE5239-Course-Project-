# Task 086 — Read-only what-if: which way of removing ICC2's I/O reference latency works, and why ICC2's input data delay differs from PrimeTime's

Read first: `docs/planning/tasks/084-io-latency-diagnostic.md`, `pnr_v2/diag_io_latency.tcl`, `pnr_v2/IO_LATENCY_RESEARCH.md`, and the server result below.

## What the diagnostic showed (user's server run, 2026-11-10, on a copy of run 1's `unpu_top_route`, pre-fill, pre-ECO state)

`H1 CONFIRMED`. ICC2 counts a clock latency on the I/O reference where PrimeTime counts 0.00:

| path | ICC2 | PrimeTime (2026-11-09 sign-off) |
|---|---|---|
| hold ff, `dma_rdata[14]` -> `u_dma/stage_reg_1__14_/D`: launch | 0.6413 | 0.00 |
| same path: capture | 0.3997 | 0.40 |
| same path: data delay (arrival - launch) | 0.2927 (arrival 0.9340) | 0.56 (arrival 0.56) |
| same path: slack | +0.0308 | -0.35 |
| setup ss, `dma_addr[31]`: launch at `u_dma/cur_m_reg_0_` | 0.5913 | 0.92 |
| same path: capture at the output port | 0.8069 | 0.00 |
| same path: required | 11.3069 | 10.50 |
| same path: arrival / slack | 10.9751 / +0.3318 | 10.74 / -0.24 |
| in2out setup `paddr[3]` -> `prdata[27]`: slack | +0.0212 | about 0 |
| in2out hold `paddr[4]` -> `prdata[1]`: slack | +0.0068 | (no violator) |

Two separate differences:
1. the I/O reference latency (0.64 at the input, 0.81 at the output): the main cause;
2. on the hold path ICC2's DATA delay (0.29) is 0.27 ns smaller than PrimeTime's (0.56, of which "port 0.26"), and the setup launch latency of the source flop differs (0.59 vs 0.92). These are not explained. The hold gap 0.38 = 0.64 (reference) - 0.27 (data delay) approx.

One of 25 diagnostic reports failed (the line `>>> 084 REPORT FAILED` is in the user's log; read it in the pasted text that the user will add, or find which one by the code).

## Goal

Answer, with read-only experiments in memory on a copy of the library (same guards as `diag_io_latency.tcl`; nothing saved, no `save_*`/`write_*` into the library):

(A) Which of these makes ICC2's four example paths show the PrimeTime convention (launch 0.00 at the input, capture 0.00 at the output)?
  1. the same I/O delays with `-network_latency_included` and/or `-source_latency_included` (find which of the two is the one that matters; apply to ALL input and ALL output delays, with the original values and clocks read back from the active constraints; use `remove_input_delay`/`remove_output_delay` then re-set, or `set_input_delay -add_delay` as the tool allows; VERIFY);
  2. emulation by offsets: input min delay lowered by the measured ICC2 reference latency, output max delay raised by it, only on ports NOT in the in2out cone (the cone computed as in `pt_eco_probe.tcl`/`port_buffers_early.tcl`);
  3. anything else the help texts in `pnr_icc2/diag/help_*.txt` suggest (read them first; the user can paste them).
For each: print the four paths again (launch, capture, arrival, required, slack), the in2out WNS, the number of I/O constraints changed, and the exact command lines used. After each experiment RESTORE the original constraints (or reopen the block) and print a check that a re-run of one path gives the original numbers.

(B) The 0.27 ns data-delay difference at the hold input. Compare the ICC2 expanded report `pnr_icc2/diag/hold_input_port.rpt` line by line with PrimeTime's path (log 3.9/3.11: input delay 0.00, port 0.26, `copt_h_inst_3910 (buffd1)` 0.17, `U588 (mx02d0)` 0.12). Candidate causes: the input driving cell / transition (SDC `set_driving_cell buffd1`) applied in one tool and not the other, input port parasitics, different net RC (ICC2 estimate vs SPEF), wire load. Report which stage differs, by how much, and a way to check each cause (read-only).

## Constraints

Local only for the script writing: no server work, no commit. The script is run by the user later on the server (same procedure as 084). Nothing in the library or flow scripts changes. The SDC text change in experiment A1 is a WHAT-IF; applying it for real needs the user's approval.

## Acceptance

`info complete` = 1; existing suites pass (list: test_port_buffers_early 106, test_run_root 79 or more, test_diag_io_latency 70, and the older ones); parsers tested; README section with the csh commands (one per line), the VERIFY list.

## Report back

File, tests, VERIFY list, the commands for the user, the expected table of the experiments. Stop after reporting.
