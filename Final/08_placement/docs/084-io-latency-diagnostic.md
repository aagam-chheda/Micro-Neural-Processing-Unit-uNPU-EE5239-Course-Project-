# Task 084 — Read-only ICC2 diagnostic: what launch/capture latency does ICC2 use on the I/O paths? (decides H1)

Read first: your own 083 Part A report (table and recommendation), `docs/planning/progress-log-2026-11-09.md` (3.9, 3.10, 3.11), `pnr_v2/pt/pt_hold_ff.tcl` and `pt_setup_ss.tcl` (how PrimeTime printed its paths), `pnr_v2/pt_eco_apply.tcl` (how it opens a library and a block).

## Why

Hypothesis H1: ICC2 adds the macro's clock-tree latency to the I/O reference clock, PrimeTime does not (it launches/captures at the clk pin, `clock network delay (propagated) 0.00`). Evidence so far is indirect (ICC2 stopped hold fixing at ~0 slack on paths that PrimeTime sees at -0.35). We have never seen ICC2's own path report with the launch latency. The choice between the principled fix (`-network_latency_included` / `-source_latency_included`, changes the SDC text), the I/O-only margin (083 row 8) and doing nothing depends on this one fact. Decision 2026-11-10: the user wants the facts before any margin.

## What to build: `pnr_v2/diag_io_latency.tcl` (ICC2, read-only, saves NOTHING)

1. Input: a library path and a block name as named parameters at the top (defaults for the saved RUN-1 state: the library copy described below, block `unpu_top_route`). Print them. RUN 1 IS THE FALLBACK AND MUST NOT BE WRITTEN: the user will first copy run 1's library to a place inside this clone (`cp -r <run 1>/pnr_icc2/blocks/unpu_top.dlib <this clone>/pnr_icc2/blocks_diag/`), and the script refuses to start if the library path is inside a different clone than the script (print both) or if the block is not found (print the blocks that exist). Open with the read-only option if it exists (mark VERIFY), and never call `save_block`/`save_lib`/`write_*` into the library. Output files only under `<RUN_ROOT>/pnr_icc2/diag/`.
2. Switch to each scenario (`func_ss` for setup, `func_ff` for hold; read the scenario names from the design, do not type them blindly; print them).
3. Print, with `-significant_digits 4` and including the clock network lines (`-input_pins -nets` and the options that make the launch and capture clock path visible; VERIFY the option names with `help report_timing`):
   - hold, ff: `-delay_type min` from the input port `dma_rdata[14]` to `u_dma/stage_reg_1__14_/D` (this is the PrimeTime example: data arrival 0.56, required 0.90, slack -0.35 in PrimeTime);
   - hold, ff: the worst path from any input port among the 263 PrimeTime violators (use the same endpoint if you can resolve it, otherwise the worst path `-from [all_inputs]`);
   - setup, ss: `-delay_type max -to [get_ports {dma_addr[31]}]` (PrimeTime: launch clock arrival 0.92 ns at `u_dma/beat_idx_reg_0_/CP`, data arrival 10.74, required 10.50, slack -0.24);
   - setup, ss: one in2out path, `paddr[3]` to `prdata[*]` (PrimeTime: ~0 slack).
4. Print `report_clocks` and `report_clock_timing -type latency` (and skew), per scenario, `report_clock_tree_options` if it exists, and the state of: `get_attribute [get_clocks clk] is_propagated` (per scenario), `time.all_clocks_propagated`, `time.enable_io_path_groups`, `time.allow_port_latency_for_feedthrough`, and whether any `set_clock_latency` / `set_input_delay` option such as `-network_latency_included`/`-source_latency_included` is present in the active constraints (`report_port -verbose` or `write_sdc` to the diag folder; print the I/O delay lines).
5. At the end print a labelled verdict table, one line each, from the numbers read (no guessing), then a plain sentence:
   - `ICC2 launch clock latency at the input port path: X ns (PrimeTime: 0.00)`
   - `ICC2 capture clock latency at the endpoint flop: X ns (PrimeTime: 0.40 ff)`
   - `ICC2 launch latency at the dma_addr[31] source flop: X (PrimeTime 0.92 ss)`
   - `ICC2 required time at the output port for dma_addr[31]: X (PrimeTime 10.50)`
   - `H1 CONFIRMED (ICC2 adds latency to the I/O reference)` / `H1 REFUTED (ICC2 shows 0.00 like PrimeTime: the cause is elsewhere: list the differences found)` / `INCONCLUSIVE: <what is missing>`.
   Parse the values from the report text with tested procs; if a line cannot be found print `n/a` and say so.
6. Also dump `help *margin*`, `help set_clock_latency`, `help set_input_delay`, `help set_output_delay`, `help set_clock_tree_options`, `help set_latency_adjustment_options` into `<RUN_ROOT>/pnr_icc2/diag/help_*.txt` (and print the one-line command list of `help *margin*`), so 083's [M] items become [L].
7. Nothing in the script changes a constraint, an app option or the design. Every message printed; errors are caught per report and printed, the script continues with the next report (a diagnostic must give as much as possible), and ends with a count of reports that failed.

## README

A short section in `pnr_v2/README.md`: the copy command (csh, one line), the run command, `exit`, what to read (the verdict table), and that run 1 stays unwritten (check: `ls -ld` times of the run-1 library before/after, command given).

## Constraints

"Nothing fails silently; nothing hardcoded; no constraint tuned..." Read-only. Local only: no server work, no commit. Tests for the parsers (use the PrimeTime example lines from the progress log 3.9/3.11 as sample text, plus an invented ICC2-style sample).

## Acceptance

`info complete` = 1; all existing suites pass with their counts (278/136/149/63/69/48/18/73 + 75 `test_run_root`); new parser tests; the VERIFY list.

## Report back

File, tests, VERIFY list, the exact commands the user runs. Stop after reporting.
