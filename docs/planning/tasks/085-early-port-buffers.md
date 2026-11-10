# Task 085 — L3: prevent the input-port antenna failures BEFORE routing (`pnr_v2/port_buffers_early.tcl`, flow step 4c, after placement and before CTS)

Read first: `docs/planning/restart-plan-2026-11-10.md` (4b, L3), `pnr_v2/antenna_port_buffers.tcl` (the method that worked in run 1: header, formula, parameters, tier 2, placement), `docs/planning/tasks/067-*.md`, `068-*.md`, `069-*.md` and `071-clk-root-resize.md` (what failed and why), `pnr_v2/placement.tcl`, `pnr_v2/pin_replace.tcl` (parked), `pnr_v2/cts.tcl`.

## Why (run 1, 2026-11-09)

16 input-port nets failed Calibre antenna AFTER routing: pin-to-gate wires of 130 to 478 um against a limit of about 72 um (M2/M3, weight 0.54) or 46 um (top metal, 0.84), gate area about 0.19 um^2, no diodes allowed. They were repaired after the route by `antenna_port_buffers.tcl` (15 buffers, `antbuf_*`) plus the larger clock-root inverter, which meant five extra ECO steps, a changed netlist after sign-off checks started, and a late timing break. Decision 2026-11-10: handle it up front, as a normal part of the flow, with the formula and numbers known before the router runs.

## Goal

A script run once after `placement.tcl` (block `unpu_top_placement`, saved as a new block, same pattern as the other steps) that, for every INPUT port net except the clock, predicts the pin-to-load wire length from the placement and inserts a buffer next to the pin when the prediction says the net would fail, so that the routed design has no antenna violation on input ports without any later ECO.

## Part 1 — the script

1. Take the formula and constants from `antenna_port_buffers.tcl` (do not retype them: name them in one shared place or copy with the source line cited): limit 400, weights 0.54/0.84, wire width, diode area 0.202, gate area from the LEF of the first load. Predict for each input port net: the Manhattan length of the Steiner/placement estimate from the pin to each load, the worst-case ratio with the M2/M3 weight and with the TOP_M weight, and print one table: port, loads, longest pin-to-load distance (um), predicted ratio, decision (BUFFER / OK / CLOCK-SKIPPED), reason. A parameter `PREDICT_MARGIN` (default 0.8: buffer when the predicted ratio exceeds 80 percent of the limit; name it, give the reason: the routed detour is longer than the estimate; run 1's observed route/estimate ratio for the 16 nets is in the progress log or the antenna database: use it if you can find it and cite it) decides.
2. For BUFFER nets: insert one buffer between port and loads (`insert_buffer` as in `antenna_port_buffers.tcl`), choose the cell from DATA as that script does (antenna gate area in the LEF versus the thresholds), place it within `MAX_PIN_BUF_DIST` of the pin on a legal site (there are NO fillers yet: use legal placement of that one cell, `legalize_placement` limited to that cell is NOT safe — it moved cells far in run 1: place at a free site found from the row/occupancy data, verify the final location equals the requested one, retry candidates, same hard checks).
3. Protect the new cells from the later optimisers: they must not be removed, and not moved by `clock_opt`/`route_opt`. Find the right mechanism (`set_dont_touch`, `set_placement_status fixed`, `set_size_only`; VERIFY each with help) and print it; sizing may be allowed if that does not enlarge the pin-to-buffer exposure (decide and state it).
4. The clock port: skip the buffer, but compute and print the pin-to-first-load distance and the predicted ratio with the CTS root cell's gate area, and state whether a bigger root cell is needed (run 1: `inv0d4`, task 071). Only print; CTS sets the root, a separate decision.
5. The `paddr` -> `prdata` combinational read path has about zero margin in both tools. For every buffered net on an input-to-output cone (compute the cone as `pt_eco_probe.tcl` does, structurally), print the added delay of the buffer on that path and the in2out WNS before and after (ICC2, ss). If the in2out WNS drops below its before-value by more than a named tolerance (default 0.005 ns, same reasoning as `pt_eco_apply.tcl`), stop BEFORE saving and list the nets; the user decides. Do not skip these nets silently.
6. Hard checks before saving (error, nothing saved): placement legal (`check_legality` 0), buffer count equals the BUFFER count, every buffer inside `MAX_PIN_BUF_DIST` of its pin, protected cells' attributes read back, the table totals match. Report (not tune) setup/hold WNS before and after per scenario. Print `>>> STAGE 4c COMPLETE ...`, save as a new block (name consistent with the chain: `_placement` -> `_portbuf` -> `_cts`; adapt `cts.tcl` to open `_portbuf` ONLY via a clearly named parameter whose default is the new block; show the diff).
7. After CTS and route the script `antenna_port_buffers.tcl` stays as the repair step for anything the prediction missed; its input is the Calibre antenna database. Do not change it.

## Part 2 — read-only research on the pins (report only)

Why did the second `place_pins` call (after placement, task 067) ignore the 8 um spacing? Using the saved help texts in `~/server_pull/rpt/help` and the app options list, find whether pin constraints (`set_individual_pin_constraints`, `set_pin_length`, `set_app_options -name place_pins.*` or similar) must be set again before the second call, and propose a concrete sequence. Do NOT implement it; one page of findings with VERIFY marks. If it works, a later flow could avoid buffers entirely for nets that matter; the in2out cost of buffers is the argument.

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no constraint tuned to close timing without a written reason and user approval." No diode (`adiode` is dont_use). No change to constraints, uncertainties, goals, limits. Local only: no server work, no commit. Mark every ICC2 command or option not in a local usage text VERIFY.

## Acceptance

1. `info complete` = 1; all existing suites pass with the counts (278/136/149/63/69/48/18/73 + 75 `test_run_root`); new tests for the prediction table (use the run 1 numbers: the 16 failing nets with their lengths if recoverable, e.g. from the antenna database format and the progress log), the decision rule at the boundaries, the in2out gate, the site selection.
2. README: step 4c in the run order, the csh commands one per line, what to read, the VERIFY list.
3. `git status`: only `pnr_v2/` files and this task file.

## Report back

Files, test output, the VERIFY list, the predicted number of buffers for this design and why (what you can say without the server), the in2out nets you expect in the table, Part 2 findings. Stop after reporting.
