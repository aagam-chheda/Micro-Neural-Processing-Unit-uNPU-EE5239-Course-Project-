# Task 078 — PrimeTime: machine-readable violation lists for all violators, and a probe of PrimeTime's own ECO commands (`pnr_v2/pt/`)

Read first: `docs/planning/progress-log-2026-11-09.md` (3.9 and 3.10), `pnr_v2/pt/README.md`, `pnr_v2/pt/pt_common.tcl`, `pnr_v2/pt/pt_setup_ss.tcl`, `pnr_v2/pt/pt_hold_ff.tcl`, and the server results of the first complete PrimeTime runs (quoted below).

## What the PrimeTime sign-off found (user's server run, 2026-11-09, commit `7ca9e93`)

User decision (2026-11-09, "go with option A, and lets go with the stricter PrimeTime reading"): the design is fixed to pass PrimeTime; ICC2's more lenient reading of the I/O reference latency is not used. Cause (verified on a full path): PrimeTime launches input data and captures output data at the clock PIN with zero latency (`clock network delay (propagated) 0.00`), so the macro's clock-tree insertion delay (0.92 ns at ss on the launching flop of `dma_addr[31]`, 0.40 ns at ff on the capturing flop of `stage_reg_1__14_`) counts against the interface budgets; ICC2 gave the external clock the same insertion delay.
- Setup, ss, `SETUP corner ss: WNS -0.2423 ns, TNS -0.2423 ns, violating endpoints 1`: endpoint `dma_addr[31]` (output port), startpoint `u_dma/beat_idx_reg_0_/CP`; the path goes through the address adder `u_dma/add_212_3` (a chain of `ah01d1` half-adder CO outputs) and ends in `HFSINV_13_284 (inv0d4)` which takes 1.61 ns to drive the 1.0 pF output load; arrival 10.74 ns against required 10.50 (= 20 - 1.5 - 8.0). The `paddr` -> `prdata` group has "No paths with slack less than 0.00".
- Hold, ff, `HOLD corner ff: WNS -0.3468 ns, TNS -44.5685 ns, violating endpoints 263`: 255 violating endpoints that are cell pins (all `/D` pins of flops: `u_dma/stage_reg_<0..3>_<bit>_/D` and `u_csr/{src_a,src_b,dest_c}_reg_reg_*/D`) and the rest ports; startpoints are the input ports `dma_rdata[*]` and `pwdata[*]`. Example: `dma_rdata[14]` (input delay 0.00, port 0.26, `u_dma/copt_h_inst_3910 (buffd1)` 0.17, `u_dma/U588 (mx02d0)` 0.12, D at 0.56) against required 0.40 (capture clock) + 0.50 (uncertainty) + 0.00 (hold time) = 0.90, slack -0.35.
- Also reported: about 150 entries `0.40 0.40 0.00 (VIOLATED: increase significant digits)` of the clock-path max-transition limit 0.40 ns (`set_max_transition 0.4 [get_clocks {clk}] -clock_path`, from the example `cts.tcl`; it is in the SDC that ICC2 wrote). Not part of this task.
- The existing PrimeTime scripts only write detail reports for the first `PT_MAX_VIOLATED_DETAIL` (50) violated endpoints (`pt_hold_ff_violated_<endpoint>.rpt`), so the 263 hold violators are not all described with their startpoints and path cells.

## Goal

Two small additions that prepare the fix (the fix itself is the next task and depends on what you deliver here):
(1) every violated endpoint, setup and hold, listed in a file that a Tcl script can read (no limit of 50);
(2) a probe that tells whether PrimeTime's own ECO commands (`fix_eco_timing`, `fix_eco_hold`, `write_changes`) can be used here (licence, behaviour, output format), without changing anything.

## Part 1 — full violation lists (`pt_common.tcl`, `pt_setup_ss.tcl`, `pt_hold_ff.tcl`)

After the existing summary logic, write for each script (setup and hold) into `pnr_icc2/pt/`:
1. `pt_<setup|hold>_<corner>_violations.csv`: one line per violated endpoint (worst path to that endpoint, `-nworst 1`), no limit on the count (`get_timing_paths -slack_lesser_than 0 -max_paths <large> -nworst 1`; keep the existing parameter style: a named parameter with the reason). Columns separated by `;`: endpoint; startpoint; startpoint kind (`port` or `pin`); endpoint kind (`port` or `pin`); slack (ns, 4 decimals); path group; number of cells on the data path; the data-path cells in order as `instance/pin(ref)` joined by `,`; and, for each cell, the incremental delay (a second column with the same order, joined by `,`). The first line is a header. If a path attribute needed for a column cannot be read, the field is `n/a` and a single line says so; nothing fails silently.
2. A count line in the log and the SUMMARY block: "violations file: N endpoints written to <file>", and a consistency check against the summary count (they must be equal; a difference is an error and is explained in the message).
3. Extend the tests with sample rows (the real `dma_rdata[14]` path above: endpoint `u_dma/stage_reg_1__14_/D`, startpoint `dma_rdata[14]`, slack -0.35, cells `copt_h_inst_3910/Z(buffd1), U588/Z(mx02d0)`, incrementals 0.17 and 0.12) for the CSV line builder, parsing back, and the consistency check.
Do not change what the scripts already do.

## Part 2 — `pnr_v2/pt/pt_eco_probe.tcl` (a third PrimeTime script, hold at ff)

Purpose: find out in one run whether PrimeTime's ECO feature works here. It must be read-only for the design files (it writes only reports and one change file). Steps:
1. The same preparation as `pt_hold_ff.tcl` (same environment: library, netlist, SPEF decision, SDC, propagated clock proved, annotation check). Reuse the procs from `pt_common.tcl`; do not copy logic.
2. Licence probe, printed clearly: try `get_license`/`list_licenses` for the ECO-related features (for example `PrimeTime-ECO`) and print which are available; do not guess the feature name, print what PrimeTime says.
3. Try the ECO on hold: `set_eco_options` (logical ECO first: no physical data), `fix_eco_timing -type hold -methods {insert_buffer}` (or `fix_eco_hold`, whichever exists in T-2022.03-SP2; print `help *eco*` / `man` output first so the log shows what exists) with a `-buffer_list` made of delay cells taken from the library: print the candidate cells with their delays at this corner (from the `.db`: query the library cells whose name starts with `dl`, `buff`, and print `is_buffer`, area and, if readable, the delay) and choose by data, not by name. Use a hold margin parameter (default 0.05 ns) and say why (the PrimeTime and ICC2 parasitic estimates differ by picoseconds; the 0.5 ns uncertainty is already in the constraints). Restrict the fix to endpoints whose startpoint is an input port (the 255 `/D` pins) by passing the endpoints or `-from` the input ports. Any error or licence failure is caught and printed as one clear PROBE RESULT line (`PROBE RESULT: ECO NOT AVAILABLE: <message>` or `PROBE RESULT: ECO RAN: N changes proposed, change file <path>`), and the script exits 0 in both cases (a failed probe is an answer, not a script error).
4. If it ran: `write_changes -format icctcl` (and also `-format text`) into `pnr_icc2/pt/pt_eco_hold_changes.tcl`/`.txt`; print the first 30 lines, the number of cells to be inserted per reference, and the per-endpoint slack after the ECO (`report_constraint -all_violators -min_delay`) so that the user sees whether PrimeTime thinks the ECO closes hold. Do NOT apply the ICC2 side in this task.
5. The README: a section "ECO probe" with the csh commands (one per line), what to read, and what each outcome means for the next step.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No constraint, SDC value or limit is changed in PrimeTime; the ECO probe only proposes netlist changes. Do not use `$FOUNDRY`. Do not run anything on the server, do not commit.

## Acceptance test (local, no server)

1. `info complete` = 1 for every Tcl file in `pnr_v2/pt/`; `tclsh pnr_v2/pt/test_pt_common.tcl` passes with the new tests.
2. The CSV builder and parser are pure procs and tested with the real example row above, including a row with `n/a` fields and a startpoint that is a pin (a register-to-register path).
3. `grep -c VERIFY pnr_v2/pt/pt_eco_probe.tcl` and the full VERIFY list in the README (every PrimeTime ECO command and option is from your knowledge, not from a usage text: mark each).
4. `git status`: only `pnr_v2/pt/*` and this task file.

## Report back

Files changed, the diff summary, test output, the VERIFY list, which ECO commands you expect to exist in T-2022.03-SP2 and which you are unsure of, what the user should look at first in the probe log, anything ambiguous. Stop after reporting.
