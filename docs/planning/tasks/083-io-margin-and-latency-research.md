# Task 083 — Research: can ICC2 see PrimeTime's I/O convention? If not, an I/O-only optimisation margin (L1), plus CTS insertion delay options (L2)

Read first: `docs/planning/restart-plan-2026-11-10.md` (L1, L2, L7, L8), `docs/planning/tasks/074-primetime-signoff.md`, `docs/planning/progress-log-2026-11-09.md` (3.9, 3.10), `pnr_v2/cts.tcl` lines 1 to 130, `pnr_v2/route.tcl` lines 55 to 160, `pnr_v2/timing_closure.tcl` (OPT/SPEC uncertainty blocks), `constraints/unpu_top.sdc`.

## Facts you must start from (a correction to your message)

- The uncertainties that count for this flow are the OLD constraints, not the example profile: `SPEC_SETUP_UNC 1.5`, `SPEC_HOLD_UNC 0.5` (`cts.tcl`, `route.tcl`, `timing_closure.tcl`; decision 063 E9). PrimeTime's hold report shows 0.50 uncertainty. The `0.6` and `0.05` you quoted are the example's profile; check which `UNPU_STAGE_SEL` the exported SDC really carried and say so.
- An ICC2-only optimisation margin ALREADY EXISTS in the scripts: `OPT_*_UNC = SPEC_*_UNC + *_SLACK_GOAL`, applied only while the optimiser runs, then restored to SPEC before reports and export. The goals are `0.0` by the user's decision of 2026-11-02 ("no extra margin"). The friend's idea (raise uncertainty in ICC2) is therefore "raise the SLACK_GOALs", a GLOBAL margin. We think a global margin is the wrong tool (it hits reg-to-reg paths and the zero-margin `paddr` -> `prdata` read path), which is why this task looks for an I/O-only one.
- The gap, with numbers: PrimeTime launches/captures I/O at the clk PIN with zero latency; ICC2 gives the external reference the macro insertion delay (0.92 ns at ss, 0.40 ns at ff). Evidence: setup `dma_addr[31]` -0.2423 ns (one endpoint); hold -0.3468 ns on 263 input-to-register endpoints. `paddr` -> `prdata` (in2out) has ~0 margin and both tools agree on it.

## Part A — research only (no flow change, nothing applied)

On the actual tool help or the kit/Synopsys docs available (print the source of every statement; mark VERIFY what is from memory):

1. Does ICC2 U-2022.12-SP3 offer a way to compute I/O paths with the external clock at zero latency (ideal, no insertion delay)? Look at: `set_clock_latency` on the virtual clock or the clock port with `-source`, `set_latency_adjustment_options`, `set_clock_uncertainty` interclock forms, `set_input_delay -network_latency_included/-source_latency_included`, `set_output_delay` equivalents, and any app option listed in `all_appopts.txt` (grep `latency`, `io`, `ideal`). Give for each: does it change what the OPTIMISER sees, and does it change the SDC that PrimeTime reads?
2. Does ICC2 have a per-path margin (`set_path_margin`, `set_timing_derate`, `set_clock_uncertainty -from/-to`, `set_input_delay` adjustments) that can be restricted to (a) input-to-register hold, (b) register-to-output setup, and NOT to input-to-output paths? Give the exact syntax from `man`/`help`, and how to remove it afterwards.
3. CTS insertion delay (L2): which `cts.tcl` options or app options (`cts.*`, `clock_opt.*`) reduce the insertion delay or its dependence on the root, what the run-1 numbers were (0.59 ns / skew 0.31 ns, read them from the run-1 logs in the repo if present, else say they are on the server), and the cost of each.
4. Synthesis side (L8): is there a way in DC, with the same legacy constraints, to check the DMA output paths with a latency allowance as a REPORT (no constraint change)? Give the commands. Do not change `constraints/legacy/`.

## Part B — implementation, only if A finds nothing better than a margin, behind parameters, default OFF

A parameterised I/O-only margin in the ICC2 optimisation phases (`cts.tcl`, `route.tcl`, `timing_closure.tcl`): `IO_HOLD_MARGIN_NS` for input-to-register hold, `IO_SETUP_MARGIN_NS` for register-to-output setup; both default `0.0` (so nothing changes until the user approves values). Requirements:

1. Applied only inside the OPT block, removed before the SPEC block, same pattern as `OPT_*_UNC`. A restore check: print the margin state (the list of margins/derates) after the restore and fail if anything remains.
2. Never touches input-to-output paths. Prove it: the script prints the in2out group WNS with the margin ON and OFF (setup, ss) and fails if it changed.
3. The exported SDC is byte-identical to the one without the margin (test it by diffing a generated SDC with and without; local test with stubs is acceptable if the tool is not available, say so).
4. Suggested starting values for the user to approve (not applied): hold ~0.4 ns, setup ~0.9 ns, each with the written reason from the evidence above.
5. Every parameter has a reason comment in the existing style.

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no constraint tuned to close timing without a written reason and user approval." The exported SDC and PrimeTime sign-off keep the legacy constraints. No value other than `0.0` is the default. Local only: no server work, no commit.

## Acceptance

1. `info complete` = 1 for changed Tcl files; all existing tests pass; new tests for the margin on/off state logic.
2. Part A report: a table (option | optimiser sees it | changes SDC | syntax | source) and a recommendation.
3. VERIFY list in the README.

## Report back

Part A table and recommendation first (stop after Part A if the answer to 1 is "yes, ICC2 can see zero latency": then Part B changes and I decide). Then Part B files, tests, VERIFY list. Stop after reporting.
