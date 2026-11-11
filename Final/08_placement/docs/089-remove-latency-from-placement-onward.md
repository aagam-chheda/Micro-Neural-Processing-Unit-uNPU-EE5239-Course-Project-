# Task 089 — The tool-made `set_clock_latency` exists from the power plan on: remove it from placement onward too

Read first: `docs/planning/tasks/088-remove-tool-clock-latency.md`, your 088 report, `pnr_v2/clock_latency.tcl`, `pnr_v2/placement.tcl`, `pnr_v2/port_buffers_early.tcl`, `pnr_v2/cts.tcl`.

## What the server showed (user's run, 2026-11-10, `diag_clock_latency_origin.tcl` on run 2's own library)

Count of `set_clock_latency` lines in the SDC written from each block:

| block | func_ff | func_ss |
|---|---|---|
| unpu_top_setup | 0 | 0 |
| unpu_top_floorplan | 0 | 0 |
| unpu_top_powerplan | 1 (0.138485) | 1 (0.356843) |
| unpu_top_placement | 1 (0.138485) | 1 (0.356843) |
| unpu_top_portbuf | 1 (0.367671) | 1 (0.806847) |
| unpu_top_cts (made from portbuf by the OLD cts.tcl, before task 088) | 1 (0.367671) | 1 (0.806847) |

So the line is NOT created by CTS. It first exists in the power-plan block (`powerplanning.tcl` has only `check_pg_*` commands and no timing command: something in that step or its save triggers the tool's clock-latency estimate; find out what if the help texts allow, VERIFY), keeps its value through placement, is re-estimated in step 4c (values change from 0.138/0.357 to 0.368/0.807 after the early buffers: probably the `update_timing -full` of `port_buffers_early.tcl`), and CTS leaves the PRE-CTS ESTIMATE in place (the real tree latencies are 0.60 ff / 1.36 ss; the old `cts.tcl` ran with the estimate on the I/O reference). Consequences: `place_opt` and step 4c measured and optimised the I/O paths with the estimate as the I/O reference latency, CTS (before 088) too.

## Decision (Planning, within the user's approval of 088 "yes go with your recommendation"; reasoning: the same artefact, same evidence, earlier in the flow)

Remove the line at the START of every script that times or optimises, from placement on, and again at the END before saving, so that every saved block is clean and every optimisation sees PrimeTime's I/O convention. The tool may re-create it inside its own steps (the estimate): the printed before-count at the end of each script tells; that is a finding, not an error.

## Changes

1. `placement.tcl`: call `unpu_remove_clock_latency` right after the block is opened (label placement-input) and again after `place_opt` / before `save_block` (label placement-final). Print both counts as `>>> 088` lines (the proc does). If the count after `place_opt` is not 0 before the second removal, add a `>>> 089 NOTE: the tool re-created the line inside place_opt (value ...)` line.
2. `port_buffers_early.tcl`: the same pair (port-buffers-input right after open; port-buffers-final right before `save_block -as ${OUT_BLOCK}`), BEFORE the first `update_timing`/timing measure, so the BEFORE/AFTER numbers of its gates and the in2out check use the clean convention. In `PLAN_ONLY` mode the first removal still runs (it changes the in-memory block only, nothing is saved: say so in the output). Keep the gate tolerances unchanged.
3. `powerplanning.tcl`: add the final removal before `save_block` (label powerplan-final) so the saved block is clean, if the counts show the line exists at that point (the proc prints it). If it is created by the save itself, say so in a NOTE (the placement-input removal then covers it).
4. `cts.tcl` is already covered by 088 (`cts-input` and after each clock_opt step). Nothing to change except that its input is now clean.
5. The origin diagnostic: keep as is; the README gets a line that the expected table after the redo is 0 in every block from `unpu_top_placement` on (the powerplan block stays as it is unless step 3 cleans it).
6. Tests: source checks for the two new call pairs, the position relative to `open_block`, `update_timing` and `save_block`; the `>>> 089 NOTE` text; all existing suites keep their counts (test_timing_closure ranges may shift again: adjust with a comment as before).

## Constraints

Same as 088: nothing is tuned; a tool artefact is deleted; no uncertainty, I/O delay, goal or limit changes. Local only: no server work, no commit.

## What the user will do after the commit (so that the README matches)

Rerun from placement on: `placement.tcl`, `port_buffers_early.tcl` (first with `UNPU_PBE_PLAN_ONLY 1` to compare the table with the earlier one: the BUFFER set may change), then `cts.tcl`. The earlier steps (synthesis ... power plan) are kept. Write that sequence (csh, one command per line, and the origin diagnostic after each) into the README of the flow under the 088 section.

## Report back

Files, diffs, tests, VERIFY, and what you can say about the trigger in `powerplanning.tcl`. Stop after reporting.
