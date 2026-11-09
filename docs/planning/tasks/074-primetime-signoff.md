# Task 074 — PrimeTime sign-off of the final layout: `pnr_v2/pt/` (scripts and runbook)

Read first: `docs/session-handoff.md` sections 18.2 to 18.4 (corners, libraries), 18.5 and 18.9 (the constraints), 18.12 and 18.23 (what `pv.tcl` exports), 18.32 to 18.35 (this run), `pnr_v2/pv.tcl` (the export commands and their file names), `pnr_v2/build_ndm_std.tcl` (paths of the ss and ff `.db` libraries and of the technology), `pnr_v2/design_setup.tcl` (the two scenarios: `func_ss` = corner `corner_ss` for setup, `func_ff` = corner `corner_ff` for hold), `constraints/legacy/unpu_top_legacy.sdc` (the course constraints), `docs/planning/progress-log-2026-11-09.md`.

## Goal

Sign off the final layout with PrimeTime: setup at the slow corner (ss), hold at the fast corner (ff), with the extracted parasitics of the ICC2 export. PrimeTime is the authority. ICC2 says setup WNS +0.0143 ns (func_ss) and one reg-to-reg hold path at about -0.0004 ns (func_ff); PrimeTime has to confirm or contradict this. The user runs it on the server (`pt_shell`, T-2022.03-SP2 per the handoff; `source ~/cad_cshrc` and `source ~/synopsys_cshrc` first, same terminal rules as for ICC2). You write the scripts and the runbook; you do not run anything on the server.

## Inputs (all on the server in `/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/outputs/`, written by `pv.tcl`)

`unpu_top_pnr_pg.v` (netlist with PG pins), `unpu_top_pnr_sim.v` (netlist without PG pins), `unpu_top_spef.TYPICAL_RC_125.spef` and `unpu_top_spef.TYPICAL_RC_-40.spef` (parasitics; two files, one per RC corner temperature), `unpu_top_spef.spef_scenario` (a 308-byte text file that says which scenario/corner each SPEF belongs to), `unpu_top_pnr_ss.sdc` and `unpu_top_pnr_ff.sdc` (the constraints ICC2 wrote per scenario), `unpu_top_ss.sdf` and `unpu_top_ff.sdf` (not needed for STA), and the kit libraries named in `build_ndm_std.tcl` (`tsl18fs120_scl_ss.db`, `tsl18fs120_scl_ff.db`, library names `tsl18fs120_scl_ss` and `tsl18fs120_scl_ff`).
These files are NOT on this machine. Everything you need to know about them must be read from the repo scripts; where you cannot know a fact (for example which SPEF belongs to which corner), the script must READ it from the server file at run time and stop with a clear error if it cannot decide. Do not guess a mapping silently.

## Files to create (only under `pnr_v2/pt/`)

- `pt_common.tcl`: shared procs and settings (paths in ONE place at the top, file-existence checks that stop with a clear message, a procedure that prints a banner with the corner, library, SPEF and SDC actually used, a summary printer).
- `pt_setup_ss.tcl`: setup analysis at the slow corner (library ss, parasitics of the corner that ICC2 used for `corner_ss`, constraints from `unpu_top_pnr_ss.sdc`).
- `pt_hold_ff.tcl`: hold analysis at the fast corner (library ff, parasitics for `corner_ff`, constraints from `unpu_top_pnr_ff.sdc`).
- `README.md`: the runbook, csh only, ONE command per line: environment, running the two scripts (each in its own `pt_shell -f ... |& tee ...` line), what to read in the log, how to copy the results back with `scp` (laptop terminal; the user types the password), and a VERIFY table.
- `test_pt_common.tcl`: tests (passes with `tclsh`) for the pure-Tcl parts.
Do not edit anything else (no flow script, no SDC, no `constraints/`, no kit file). The SDC files written by ICC2 are inputs, read-only.

## What the scripts must do (decide the PrimeTime commands from your knowledge of `pt_shell` and the help texts in `/home/aagam_chheda/server_pull/rpt/help` if PrimeTime commands are in there; mark every unverified command or option `VERIFY`)

1. Set the search path, link path and target library for the corner; read the netlist; `link_design unpu_top`; stop on unresolved references or on any `Error` after linking, and print the number of cells linked and the library cells missing (if any).
2. Read the parasitics: `read_parasitics` with the SPEF that belongs to the corner. Decide the mapping from `unpu_top_spef.spef_scenario` (read the text at run time; the file lists the scenario or corner of each SPEF). If the text does not name the corner, STOP with an error that prints the file content; do not choose by the temperature in the file name. After reading, print the annotation summary (`report_annotated_parasitics -check` or equivalent) and stop if a large part of the nets is not annotated (print the percentage; threshold as a named parameter with the reason, default: any unannotated net with a driver is an error unless the count is printed and explained).
3. Read the constraints (`read_sdc`) from the per-scenario SDC. The SDC must carry setup uncertainty 1.5 ns and hold uncertainty 0.5 ns, the I/O delays (APB 35, DMA 40, `rst_n` 40 percent of 20 ns, min delays 0 and -0.5), the driving cell, input and output loads, transition and capacitance limits: print the clock period, the uncertainties and the operating condition read back from the design (`report_clock`, `get_attribute`, `report_design` or equivalent) and compare with the values in `constraints/legacy/unpu_top_legacy.sdc` (20.0, 1.5, 0.5): a mismatch is an error. Make the clocks propagated for the analysis (the CTS tree is real) unless the SDC already does it; say which.
4. Run `update_timing` and print the checks: `check_timing -verbose` (stop on unconstrained endpoints other than the known constants such as `pready`, print them), `report_design`, `report_clock -skew` and the clock latency (`report_clock_timing -type latency` / `skew` or equivalent: min and max latency, global skew, to compare with CTS's 0.59 ns and 0.31 ns).
5. Setup script: `report_global_timing` (or `report_constraint -all_violators -max_delay`), the worst 10 paths per path group with full clock expansion (`report_timing -delay_type max -path_type full_clock_expanded -max_paths 10 -nworst 1 -group ...` as available), and the in2out group in particular (`paddr` -> `prdata`). Print a SUMMARY block of the form `SETUP corner ss: WNS <x> ns, TNS <y> ns, violating endpoints <n>` and the verdict `SETUP: MET` / `SETUP: VIOLATED`.
6. Hold script: the same for `-delay_type min`: worst 20 hold paths with full clock expansion, `report_constraint -all_violators -min_delay`, the SUMMARY block and `HOLD: MET` / `HOLD: VIOLATED`. For every violated endpoint print the endpoint, the slack, the startpoint and the clock arrival times of both ends (the skew), so that a one-path fix is possible.
7. Design-rule checks in both scripts: `report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width` (as available). Max transition limit 3.0 ns and max capacitance 2.0 pF are in the SDC. The ICC2 flow also set `set_max_transition 0.40 -clock_path` (example `cts.tcl`) which may appear in the written SDC: print which limits PrimeTime actually reads (for the clock path) so that the user sees whether the 0.40 ns limit is part of the signed-off constraints.
8. Signal-integrity/crosstalk: PrimeTime-SI may or may not be licensed. Make it a parameter (default OFF) with a comment; if it is turned on, the script must check the licence and stop with a clear message if it fails; say in the README that the ICC2 numbers were computed with SI/crosstalk analysis ON, so a difference is expected when SI is off, and the direction of the difference.
9. All reports go to `pnr_icc2/pt/` (create it) with the corner in the name; the logs `pt_setup_ss.log`, `pt_hold_ff.log`. The scripts end with `exit` after printing the summary so that nothing waits at a prompt (unlike icc2_shell).
10. Compare with ICC2: print, at the end of each script, the ICC2 figure for the same check (parameters at the top, from the user's run: setup WNS +0.0143 ns, hold WNS about -0.0004 ns; handoff 18.35) next to the PrimeTime one and the difference.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No constraint, uncertainty or limit is changed in PrimeTime: you only read what ICC2 wrote. Do not use `$FOUNDRY`. Do not run anything on the server and do not commit. Do not use `set_false_path`, `set_disable_timing`, case analysis or any exception that is not already in the SDC read.

## Acceptance test (local, no server)

1. `info complete` = 1 for the three Tcl scripts; `tclsh pnr_v2/pt/test_pt_common.tcl` passes.
2. The tests cover the pure-Tcl parts: the file-existence check (missing, empty), the SPEF-to-corner decision from sample `spef_scenario` texts (a clear mapping, an ambiguous text -> error, a text without the corner -> error), the summary parser (parse of a PrimeTime `report_global_timing`-style or `report_constraint` text you write from your knowledge of the format; mark it `VERIFY`), the verdict function (`MET` for WNS >= 0, `VIOLATED` otherwise, `UNKNOWN` if unreadable, never `MET` on an unreadable number), and the ICC2-versus-PrimeTime comparison line.
3. `grep -c "VERIFY" pnr_v2/pt/*.tcl` and the full `VERIFY` list in the README with what the user should look at in the log.
4. `git status`: only `pnr_v2/pt/*` and this task file.

## Report back

Files created, test output, the `VERIFY` list, how the SPEF-to-corner decision works and what the user should look at if it stops, what PrimeTime commands you were not sure of, anything ambiguous. Stop after reporting.
