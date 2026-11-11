# Task 090 — Optimisation-only clock-uncertainty margin in cts / route / timing_closure (user decision 2026-11-10), scoped so it cannot break the read path

Read first: `docs/planning/progress-log-2026-11-10.md`, `pnr_v2/cts.tcl` lines 1 to 130, `pnr_v2/route.tcl` lines 55 to 160, `pnr_v2/timing_closure.tcl` (the OPT/SPEC blocks), `pnr_v2/clock_latency.tcl`, your 083 table (row 6, `set_clock_uncertainty` usage), `~/server_pull/rpt/help` usage text of `set_clock_uncertainty` and `remove_clock_uncertainty`.

## Decision (user, 2026-11-10)

"Before optimisation increase the clock uncertainty, after optimisation change it back; this helped my friend for the PrimeTime sign-off; the instructor says redo the whole flow in a new directory." The user approves an ICC2-only optimisation margin. Reason to write in the scripts: ICC2's parasitic estimate and PrimeTime's SPEF differ by tens of picoseconds; optimising to a slightly stricter target leaves the sign-off slack positive. It is NOT a change of the constraint: the SPEC values (setup 1.5, hold 0.5), the exported SDC and the sign-off stay as they are.

## What already exists

`cts.tcl`, `route.tcl`, `timing_closure.tcl` set, only while the optimiser runs, `OPT_SETUP_UNC = SPEC_SETUP_UNC + SETUP_SLACK_GOAL` and `OPT_HOLD_UNC = SPEC_HOLD_UNC + HOLD_SLACK_GOAL` on `[get_clocks -filter "is_virtual == false"]` and restore SPEC afterwards. Both goals are 0.0 (decision 2026-11-02). So the mechanism is there: the change is to make the goals non-zero and to scope them.

## The trap that must be avoided (evidence from run 1 and the 086 numbers)

A clock-wide uncertainty also applies to the input-to-output group (`paddr` -> `prdata`): its budget is 20 - 1.5 - 7 - 7 with about ZERO margin in both tools (setup 0.0081 in the PrimeTime convention, hold only +0.0068). Raising the uncertainty on the whole clock by x makes ICC2 see the group x worse in setup AND in hold; ICC2 then adds delay for the hold part, which breaks the setup part (the break of 2026-11-09, -0.59 ns). So the margin must reach the paths that END AT REGISTERS (input-to-register, register-to-register: the 263 PrimeTime hold violators of run 1 are of this kind) and must NOT reach paths that end at output ports (in2out, reg2out).

## Changes

1. Parameters (named, with reasons in the file's style): `SETUP_SLACK_GOAL` default 0.05, `HOLD_SLACK_GOAL` default 0.10 (starting values for the user's confirmation; reasons: hold needs the larger one because the sign-off failures were hold; setup reg-to-reg has about zero margin already, so only a small one). Environment overrides `UNPU_SETUP_SLACK_GOAL`, `UNPU_HOLD_SLACK_GOAL` (number, 0 <= v <= 1.0, else ERROR 090 naming the variable) with the source (default / environment) printed in a `>>> 090 parameters` line. `UNPU_UNC_SCOPE` = `flops` (DEFAULT) or `clock` (today's clock-wide form; for comparison only): validated the same way.
2. Scope `flops`: during the optimiser keep the clock-level uncertainty at SPEC and set the OPT value on the CLOCK PINS OF THE REGISTERS (find the right object: the clock pins of `all_registers -edge_triggered`, e.g. `[get_pins -of_objects [all_registers -edge_triggered] -filter "is_clock_pin == true"]` or `all_registers -clock_pins`; VERIFY). `set_clock_uncertainty -setup <v> <pins>` and `-hold <v> <pins>` (usage text [L]: the object list may be clocks, ports or pins). Because a pin-level value REPLACES the clock-level one for paths into that pin, set the ABSOLUTE value SPEC + goal. State in a comment that an endpoint at an output port keeps the SPEC value.
3. Restore: `remove_clock_uncertainty` on exactly those pins (VERIFY the command and options; the clock-level SPEC values stay), then PROVE it: count the pins that still carry a pin-level uncertainty (0 expected; ERROR 090 otherwise) and print the clock-level values. Apply this to every optimisation block (cts: the CCD/final_opto part and the post-clock_opt checks; route: `route_opt`; timing_closure: the pass), in all scenarios (setup in `func_ss`, hold in `func_ff`, as the existing code does; read the scenario names from the design).
4. In2out protection report: before the optimisation block and after it, print the in2out setup and hold WNS (the 085 helper `pbe085_in2out` or the 084/086 parser; reuse, do not duplicate) with the scope and the goals; if the in2out setup WNS dropped by more than 0.005 ns (the tolerance of the other gates) after the OPT block, print `>>> 090 WARNING: the margin made the in2out group worse` with both numbers (no stop: the optimiser's end state is what counts; the user decides).
5. `pv.tcl`: after the last `write_sdc`, check the exported SDC files: any `set_clock_uncertainty` line that names pins (not `[get_clocks ...]`) or whose value differs from SPEC is ERROR 090 (the exported SDC has only the clock-level SPEC values). Print the lines found (expected 4 lines: setup and hold in each of the two files).
6. `cts.tcl`: the existing SPEC/OPT printing stays; add the scope and the pin counts to it.

## README and tests

README section "Task 090" with the evidence above, the `>>> 090` lines to read, the setenv forms (one per line, csh) and `unsetenv`; VERIFY list. Tests: parsing/validation of the three environment variables (accept, reject: negative, > 1.0, text, empty, wrong scope word), the source text in the parameters line, the restore proof logic (n pins left -> error), the pv.tcl check on sample SDC text (clock-level only: ok; a pin-level line: error; a changed value: error), source checks that every listed script sets the pin-level values only inside the OPT block and restores before the reports/export, that no `set_clock_uncertainty` outside the OPT/SPEC blocks was added. All existing suites keep their counts (test_clock_latency 120, test_diag_io_whatif 68, test_run_root 81, test_diag_io_latency 70, test_port_buffers_early 130, pt/test_pt_common 278, test_pt_eco_apply 136, test_antenna_port_buffers 149, test_antenna_clk_root 63, test_timing_closure 69 (adjust ranges with a comment if lines shift), test_pv_lef_check 48, test_pv_sdf_check 18, sim verdict 73).

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no constraint tuned to close timing without a written reason and user approval." The reason is written above and the user approved the margin concept; the VALUES are starting values the user confirms or changes through the environment variables. The exported SDC keeps the SPEC values. Local only: no server work, no commit.

## Report back

Files, diffs, how the pins are found and the VERIFY for the commands, tests, the expected effect (hold cells on input-to-register paths; area), and anything that could make the margin leak into output-port endpoints. Stop after reporting.
