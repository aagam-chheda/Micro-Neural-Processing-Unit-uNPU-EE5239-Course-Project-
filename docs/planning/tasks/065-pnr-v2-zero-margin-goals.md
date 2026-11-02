# Task 065 — `pnr_v2/`: set the optimiser margin goals to 0.0 (user decision 2026-11-02)

Run this AFTER task 064 is reported. Same rules as task 063 (minimal edit, `063`-style marker: use `065`).

## Decisions from the user (2026-11-02)
- D1: the server path `/storage/EE5239G1/aagams_workspace2/unpu` is right (no change to the scripts).
- D2: set both margin goals to 0.0, so that the optimiser sees exactly the course constraints (setup 1.5, hold 0.5).

## Edit
- `pnr_v2/cts.tcl`: `HOLD_SLACK_GOAL 0.70` -> `0.0`; `SETUP_SLACK_GOAL 0.3` -> `0.0`.
- `pnr_v2/route.tcl`: `HOLD_SLACK_GOAL 0.70` -> `0.0`; `SETUP_SLACK_GOAL 0.30` -> `0.0`.
- Each edited line keeps a trailing `;# 065: user decision 2026-11-02, no extra margin on top of the course uncertainties (the example had <old value>)`. Fix the stale header text in `cts.tcl` ("target +0.50 ns hold slack") with a `# 065:` note beside it; do not delete it.
- `pnr_v2/README.md`: D1 and D2 move from "Open decisions" to "Decided" with the date. D3 to D5 stay open.

## Acceptance
`diff` of `cts.tcl` and `route.tcl` against the task-063 state shows only these lines; `info complete` returns 1 for both; `grep -n "SLACK_GOAL" pnr_v2/*.tcl` shows every definition at 0.0. Do not commit; nothing on the server.

## Report back
The diff and the grep. Stop after reporting.
