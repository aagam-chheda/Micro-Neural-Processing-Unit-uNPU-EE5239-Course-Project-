# Task 091 — Checkpoint export of the ROUTE block (before fill), so PrimeTime and Calibre can judge it early (lesson L5)

Read first: `docs/planning/restart-plan-2026-11-10.md` (L5), `docs/planning/progress-log-2026-11-10.md`, `pnr_v2/pv.tcl`, `pnr_v2/pt/README.md`, `pnr_v2/pt/pt_common.tcl`, `pnr_v2/pt/pt_setup_ss.tcl`, `pnr_v2/pt/pt_hold_ff.tcl`, `pnr_v2/calibre/README.md` and the three `.ctrl` files, `pnr_v2/sim/README.md`, `pnr_v2/opt_uncertainty.tcl` (`unc090_export_check`), `pnr_v2/clock_latency.tcl`.

## Why

In run 1 PrimeTime was run LAST and found 264 violations at the end. In run 3 (clone `unpu_run3`, commit `0196348` + this task) the route block `unpu_top_route` exists. We want PrimeTime (setup ss, hold ff, with SPEF) and the Calibre DRC and antenna checks on the routed design BEFORE fill, while every fix is still cheap. Today `pv.tcl` exports only the block `unpu_top_filled`, always into `pnr_icc2/outputs/` with fixed file names that PrimeTime, Calibre and the simulation read.

## Facts from the server (run 3, 2026-11-10 evening, route done)

Route-opt final QoR: 1 setup violating endpoint, hold violations 8 (worst 0.0078 ns); `Total number of antenna violations = 87` (ICC2's own count); shorts 0, open nets 0. The route log says the in2out setup WNS went from +0.010302 (after CTS, SPEC state) to -0.010565 ns (the 090 report, tolerance 0.005): the zero-margin read path is now 10 ps negative in ICC2. The margin probes worked (in2reg hold slack moves by -0.10, setup by -0.05).

## Goal

A "checkpoint" mode of `pv.tcl` and the matching switches for the PrimeTime scripts, the Calibre control files and the simulation script, so that the routed (not yet filled) block can be exported and judged without touching the files of the final export and without editing any script on the server.

## Changes

1. `pv.tcl`: optional environment variables `UNPU_PV_BLOCK` (default `unpu_top_filled`, the final export as today) and `UNPU_PV_TAG` (default empty). With a tag (for example `route`) every output goes to `pnr_icc2/outputs_<tag>/` instead of `pnr_icc2/outputs/` (GDS, LEF, netlists, SPEF, SDF, SDC; same file names as the final export), so nothing of the final export is overwritten; any pv.tcl log is named with the tag. Validate both (block name must exist in the library: ERROR with the list of blocks; tag: letters/digits/underscore). The summary line prints block, tag and output folder. All existing hard checks (LEF check with `MACRO unpu_top`, SDF 3.0 header, `unc090_export_check`, the task 088 exported-SDC grep) run unchanged in both modes. The block name of the macro in the LEF stays `unpu_top` (the existing rename logic must work for `unpu_top_route`; VERIFY).
2. `pnr_v2/pt/pt_common.tcl` (and through it `pt_setup_ss.tcl`, `pt_hold_ff.tcl`, the ECO probes): optional environment variable `UNPU_PT_TAG` selecting `PT_OUT_DIR` = `outputs_<tag>` and naming the reports/logs/CSV files with the tag so the checkpoint and final results do not overwrite each other. Print the folder in the first lines. Default unchanged.
3. Calibre: the `.ctrl` files use the relative layout path `../../../outputs/unpu_top_routed.gds`. Do NOT edit the control files on the server. Provide in the README a csh command sequence for the checkpoint: a run folder `pnr_icc2/calibre/route1/{drc,ant}/` with `cp` of the control files and ONE `sed` command per file that changes only the folder name `outputs` to `outputs_route` in the `LAYOUT PATH` line (print the resulting line and the resolved file with `ls -lL` before the run, as the README does now). Keep it to DRC and antenna (LVS later on the final layout). Explain how to read the results.
4. Simulation (`pnr_v2/sim/run_postlayout_sim.sh`): an optional environment variable for the output folder (default unchanged) so a checkpoint netlist+SDF can be simulated if wanted; printed. Low priority: skip if it needs more than a few lines.
5. README (`pnr_v2/README.md` and the pt/calibre READMEs): a section "Checkpoint after route (task 091)" with the full csh sequence, one command per line: `setenv UNPU_PV_BLOCK unpu_top_route`, `setenv UNPU_PV_TAG route`, `icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_route_console.log`, `unsetenv` both; then `pt_shell` setup/hold with `UNPU_PT_TAG route`; then the two Calibre runs; and what to read after each (zero PrimeTime violations; antenna 0; DRC 0), plus the expected cost (PrimeTime runs a few minutes each, Calibre minutes; pv export time) and that the checkpoint repeats after each later ECO step with another tag if wanted.
6. Tests: env validation for both new variables (accept/reject), the output folder rule, that no tagged run can write to `outputs/` (source check + a mock), the PT tag naming, the sed command output on the real `.ctrl` text (resolves to `../../../outputs_route/unpu_top_routed.gds`), and that all existing suites keep their counts (test_opt_uncertainty 151, test_clock_latency 120, test_diag_io_whatif 68, test_run_root 81, test_diag_io_latency 70, test_port_buffers_early 130, pt/test_pt_common 278 (+ new), test_pt_eco_apply 136, test_antenna_port_buffers 149, test_antenna_clk_root 63, test_timing_closure 69, test_pv_lef_check 48, test_pv_sdf_check 18, sim verdict 73). The identical-bootstrap test must include any new file.

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no constraint tuned..." This task only adds an optional output location and tags; the default behaviour is unchanged. Local only: no server work, no commit.

## Report back

Files, diffs, the exact csh sequence, tests, VERIFY list (especially the macro rename for `unpu_top_route`), time estimates you can justify. Stop after reporting.
