# Task 095 — Fix the max-transition violations of the DATA limit (3.0 ns), report design rules in the PrimeTime summary, and an SI-on switch for PrimeTime

Read first: `docs/planning/progress-log-2026-11-10.md`, `~/server_pull/run3/pnr_icc2/pt/pt_setup_ss_design_rules.rpt` (the final ss design-rule report), `~/server_pull/run3/pnr_icc2/reports/unpu_top_final_violators.rpt` and `unpu_top_final_qor.rpt` (ICC2's view), `pnr_v2/pt/pt_common.tcl`, `pnr_v2/pt/pt_setup_ss.tcl`, `pnr_v2/pt/pt_eco_probe.tcl`, `pnr_v2/pt_eco_apply.tcl`, tasks 092/093.

## What the final PrimeTime run showed (run 3, final filled layout, ss, 2026-11-10 night)

`report_constraint -all_violators -max_capacitance -max_transition -min_pulse_width`: 510 max_transition entries, 0 max_capacitance, 0 min pulse width. Two groups:
1. The clock-path limit 0.40 ns (`set_max_transition 0.4 [get_clocks {clk}] -clock_path`, from the example `cts.tcl`, exported in the SDC; NOT in the legacy constraints): 424 entries, actual 0.43 to 0.48. NOT part of this task: the user decides separately (option A: tune CTS; option B: drop from the exported SDC).
2. The DATA limit 3.0 ns (`set_max_transition 3 [current_design]`, from the legacy SDC, i.e. a course constraint): 86 entries, actual 3.03 to 3.05 (30 to 50 ps over): ports `dma_wdata[25]` 3.05, `[27]` 3.04, `[29]` 3.03; pins `u_actbuf/U419/A2`, `U431/A2`, `U414/A2`, `U463/A2`, `U453/A2`, ... (10+ of them, 3.03). ICC2's final QoR reports 10 violating nets (mostly the clock ones). The hold ff report has none.
The PrimeTime SUMMARY says `SETUP: MET` / `HOLD: MET` and does not mention design rules at all.

## Part 1 — fix the 86 data-limit entries

1. Extract the data-limit violators from the report into a machine-readable list (net/pin/port, required, actual, the DRIVER cell and its reference, the fan-out/load), printed and written under `pt_<tag>/`. Group the entries by NET (86 entries are probably 10 to 20 nets; say how many). Show for each net why the transition is high (weak driver for the load? long wire? the output port load of 1 pF at `dma_wdata`?).
2. Use PrimeTime's own fixer if it exists in T-2022.03-SP2 (`fix_eco_drc -type max_transition` with `-methods {size_cell insert_buffer}`; print `help fix_eco_drc`; VERIFY; the licence probe for `PrimeTime-ECO` printed PT-002 'Unrecognized feature name' earlier but `fix_eco_timing` worked, so try). Same probe machinery as 092: change files in `pt_<tag>/`, count file, per-insertion/resize class, AFTER check, cone protection of the read path (`paddr` -> `prdata` group) with the PIN-level rule of 093: a resize of a cone cell is allowed only if it is a speed-up and the apply gate confirms it (state your rule; the apply gate in ICC2 is the proof). Remaining violators after the ECO in PrimeTime's memory printed.
3. Apply in ICC2 with `pt_eco_apply.tcl` (extend it for `size_cell` of a driver and for `insert_buffer` on a driver pin if needed; the setup ECO form of 079 already handled `size_cell`): same hard gates (in2out WNS and setup WNS not worse than 0.005 before saving, DRC 0, legality 0, open nets 0, `earlybuf_*`/`antbuf_*` and the 9 `PTECO_HOLD` cells protected and unchanged). A resize can change the HOLD slack (hold WNS is only +0.0002 ns): the apply must report the hold WNS before/after in ICC2 and the README must say that the next checkpoint's PrimeTime hold run decides.
4. README: the sequence for run 3 in csh, one command per line: backup `blocks/unpu_top.dlib.bak_pre_maxtrans`, the probe from `pt_route4`'s sibling folder of the FINAL outputs (the final run is in `pnr_icc2/pt/` with `outputs/`; it is untagged, so use the untagged folders and say so, or export a new checkpoint tag; your choice, explain), the apply, then metal_fill is already done: say whether the ECO must be applied on `unpu_top_route` and the fill/export redone (`metal_fill.tcl`, `pv.tcl`), then the three Calibre runs (final folder `final2`), both PrimeTime runs, the simulation. Keep the sequence as short as it can be and say why each step is needed.

## Part 2 — design rules in the PrimeTime summary

`pt_setup_ss.tcl` and `pt_hold_ff.tcl`: after the summary, print a block `DESIGN RULES (report_constraint ...)`: the number of max_transition violators split by the limit that applies (clock-path limit vs the design limit; read both values from the SDC as the script already does), max_capacitance, min pulse width, with the worst actual/required/slack of each group, and an overall line `DESIGN RULES: MET` / `VIOLATED (N)`. The summary must NOT say that sign-off is clean if design-rule violators exist. Do not change the setup/hold verdict words. Tests with the real numbers above (424 / 86 / 0 / 0).

Also: the summary prints `HOLD WNS: PrimeTime ..., ICC2 -0.0004 ns` and `SETUP WNS: ..., ICC2 +0.0143` taken from constants in `pt_common.tcl` (`PT_ICC2_SETUP_WNS`, `PT_ICC2_HOLD_WNS`), which are RUN-1 numbers. Nothing hardcoded: read the ICC2 reference from the export (ICC2's final report of the block that was exported: `reports*/unpu_top_final_global_timing.rpt` of the same tag) or leave it out; print where it came from.

## Part 3 — PrimeTime with SI (crosstalk) ON, switchable from the environment

An environment variable `UNPU_PT_SI` (0/1, validated, source printed; default as now, 0) that sets `PT_SI_ENABLE` for `pt_setup_ss.tcl`/`pt_hold_ff.tcl` with the licence check that already exists. With SI on, the output folder/log names must not overwrite the SI-off ones: use a tag suffix (for example `UNPU_PT_TAG` + `_si`) or a separate folder, print it, and add the SI state to the summary line. README: the command sequence for an SI-on run (csh, one line each). Tests for the switch.

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no constraint tuned..." No limit, uncertainty or I/O delay changes; the 0.40 clock-path limit stays as it is for now (the user decides later). Local only: no server work, no commit.

## Report back

Files, tests, the list of the data-limit nets with the driver and the proposed fix, the VERIFY list, the README sequence, and what you expect the hold slack to do. Stop after reporting.
