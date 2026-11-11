# Task 096 — Option B: keep the 0.40 ns clock-path max_transition out of the exported SDC, and the tools for the final verification

Read first: `docs/planning/progress-log-2026-11-10.md` (7.2), `pnr_v2/pv.tcl`, `pnr_v2/cts.tcl` (the 0.40 target), `pnr_v2/clock_latency.tcl` and `pnr_v2/opt_uncertainty.tcl` (the existing exported-SDC checks), `pnr_v2/pt/pt_common.tcl`, `constraints/legacy/unpu_top_legacy.sdc`, the exported SDCs of run 3 in `~/server_pull/run3/pnr_icc2/outputs/unpu_top_pnr_{ss,ff}.sdc`.

## Decision (user, 2026-11-10 night): option B

The line `set_max_transition 0.4 [get_clocks {clk}] -clock_path` comes from the example `cts.tcl` (a CTS target), is not in the legacy constraints or in the instructor's guidance, and the final tree misses it (0.43 to 0.48 ns at ss, 424 PrimeTime entries). It is NOT carried into the exported SDC. It stays in `cts.tcl` as the CTS target, unchanged. Say in the comments: a target of the example script, not a course constraint, user decision 2026-11-10, the tree's actual values are printed in the report.

## Part 1 — `pv.tcl`

Before every `write_sdc`: remove the clock-path max_transition from the block being exported (find the right command: `remove_max_transition`? VERIFY with `help`, print which form worked; per scenario; it must remove ONLY the `-clock_path` limit on `clk` and leave `set_max_transition 3 [current_design]` and `set_max_capacitance 2 [current_design]` in place). Print the state before and after (`>>> 096 <scenario>: clock-path max_transition lines before N, after M`), restore the block's state is NOT needed (the exported block is a copy: the checkpoint mode already works on a copy; in the untagged final export say whether the saved `_pv` block also loses it and that this is intended). After the last `write_sdc`: hard grep of the exported SDCs: a `-clock_path` max_transition line is ERROR 096; the design-wide `set_max_transition 3` and `set_max_capacitance 2` must be present (ERROR otherwise). Tests (pure parts), README paragraph with the evidence (numbers above).

## Part 2 — PrimeTime against the legacy constraints, not only against what ICC2 wrote

Add `UNPU_PT_SDC` (values `exported` = today, DEFAULT, or `legacy`; validated; source printed): with `legacy`, `pt_setup_ss.tcl`/`pt_hold_ff.tcl` read `constraints/legacy/unpu_top_legacy.sdc` (derived from the run root, not typed) instead of the exported SDC, apply the same single change as today (`set_propagated_clock [all_clocks]`, proved from a timing report), and write to a separate folder/log names (tag suffix `_legacy`). Reason: an independent proof that the layout meets the constraints AS GIVEN, not as rewritten by the tool. Possible problems to handle and print: the legacy SDC uses `current_design`/`get_ports` forms valid in PrimeTime; any command PrimeTime rejects is an error with the message. The summary prints the SDC source. Tests; README (one csh command per line).

## Part 3 — an SDC comparison tool (pure Tcl, local test)

`pnr_v2/sdc_compare.tcl` (tclsh): reads two SDC files and prints, for the constraints that matter (create_clock, clock uncertainty, input/output delays with -min/-max, driving cells, loads, max_transition, max_capacitance, clock transition, propagated clock), a table `legacy | exported | status` (SAME / DIFFERENT / ONLY-IN-ONE) and a final verdict; expected differences of the exported SDC listed by name (`set_propagated_clock`, port-attribute lines the tool adds, ...) with a reason each, anything else is DIFFERENT. Run it on the run-3 exported SDCs (ss and ff) and put the result in the report; tests with the real files (copy small excerpts as test data).

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no waiver without approval." The ONLY constraint change is option B (user approval above). Local only: no server work, no commit. Do 096 after 095 (both touch the PrimeTime scripts: keep the diffs separate and say what you merged).

## Report back

Files, tests, the SDC comparison result on the run-3 files, VERIFY list, the csh commands for the server. Stop after reporting.
