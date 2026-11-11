# Task 053 — `pnr/`: the layout flow follows the stage profiles (constraints per stage, per-stage WNS limits, netlist from the chosen synthesis)

Read first: `docs/planning/constraints-update-2026-11-02.md` (all of it; sections 3, 5 and 9 matter most), the profile table in `constraints/unpu_top.sdc` and `constraints/test_stages.tcl` (task 051),
`syn/RUNBOOK.md` section 8 (task 052: what the layout flow receives), `pnr/README.md`, `pnr/RUNBOOK.md`, `pnr/VERIFY_STATUS.md`, and the scripts you change.
Real tool facts you must use are in `~/server_pull/` (help usage files `rpt/help/<cmd>.txt`, logs); do not copy a `~/server_pull` path into any script or test.

## Goal

Until now the layout flow read the SDC that Design Compiler wrote (`unpu_top_cn.sdc`: period 20 ns, uncertainty 1.5 / 0.5 ns baked in) and held ONE hold uncertainty (`HOLD_UNCERT`). The
instructor's guidance wants a different constraint set in each stage, and different pass limits in each stage. This task makes the flow do that. The die size and the utilisation checks are
the next task (054); do not do them here.

## Part A — what to write

### A1. Inputs: which synthesis, which SDC

- New required environment variable `UNPU_SYN_PROFILE` (`syn20`, `syn18` or `syn16`; anything else is an error, no default): the profile whose netlist is used. `NETLIST` defaults to
  `$REPO_ROOT/syn/out/$SYN_PROFILE/unpu_top_cn.dc.v` (still overridable by `UNPU_NETLIST`, with the existing Warning). Print the choice in every manifest.
- The SDC is no longer `unpu_top_cn.sdc`: it is `$REPO_ROOT/constraints/unpu_top.sdc` (parameter `PROFILE_SDC`), read with the stage profile in the environment variable `UNPU_STAGE` (the SDC
  stops if it is unset). Remove `SDC_FILE`/`UNPU_SDC` or keep them only as an explicit override that is refused unless the user sets a second variable saying so (your choice; justify it in the report).
- Stage → profile map as parameters: `design_setup` and `placement` use `place`; `cts` uses `cts`; `route`, `fill`, `outputs` use `route`. (`floorplan`, `power`, `pin_place` do no timing.)

### A2. Applying a profile (a shared tool procedure)

`unpu_apply_profile <profile>` in `common.tcl`, used at the START of `design_setup.tcl` (first application, replacing the `read_sdc $SDC_FILE` steps), `placement.tcl`, `cts.tcl` and
`route.tcl` (and from there `fill.tcl`, `outputs.tcl` simply check that the profile of the block they open is `route`, see below). It must, for each of the two scenarios (select the scenario
explicitly with `current_scenario`): set `UNPU_STAGE`, `read_sdc` the profile SDC (a re-read redefines the clock `clk`: expected, `UIC-034`), set the operating condition of the scenario
(`tsl18fs120_scl_ss` for the setup scenario, `tsl18fs120_scl_ff` for the hold scenario: **the DC-written SDC used to carry the ss operating condition, the profile SDC does not, so
`design_setup.tcl` must now set BOTH explicitly**), and, for a post-CTS profile (`cts`, `route`, `signoff`), make the clock propagated again after the re-read (`set_propagated_clock` on the clock
`clk`; read the usage text; a re-read of `create_clock` may reset it). Then READ BACK and CHECK, for each scenario: the clock period, the setup and hold uncertainty (from a `report_timing` text or the
tool's report of clocks; `report_clocks` exists? read `~/server_pull/rpt/help/` before you choose; mark VERIFY what the usage cannot settle), whether the clock is propagated (it must be for
`cts`/`route`, ideal for `place`), and the operating condition (the existing `report_corners` check); the values must equal the profile table (compute the expected numbers by reading the SDC's own
printed profile line, `Info: [unpu] SDC profile <name>: period .. setup uncertainty .. hold uncertainty ..`, captured with `unpu_run_logged`). A mismatch is a CHECK FAIL. Also record
`UNPU_PROFILE_APPLIED` in the manifest. Pure-Tcl helpers for the parsing go in `common.tcl` with tests.

If re-reading the SDC in a block that already has a clock tree turns out to be unsafe (you cannot tell without the tool), say so, and use the minimum that is safe: `create_clock` is NOT re-run, only
`set_clock_uncertainty` and the input and output delays are re-applied by the same commands the SDC uses, and the period is changed with the documented command if one exists; this is the part to
mark VERIFY most clearly.

### A3. Per-stage limits instead of "zero violators everywhere"

Parameters in `params.tcl`, each with the instructor's row as its source: setup WNS limit `WNS_SETUP_PLACE -1.0`, `WNS_SETUP_CTS -0.4` (the most pessimistic end of -400 to -600 ps), `WNS_SETUP_ROUTE 0.0`,
`WNS_SETUP_FILL 0.0`; hold: no limit at placement; at CTS violations are reported (Warning, as now); `WNS_HOLD_ROUTE 0.0`; the fill rule of the 2026-10-29 decision stays as it is. The "-0.2 ns if a
PrimeTime ECO follows" option is NOT used (a comment says so).
Change the checks: `placement.tcl` and `cts.tcl` currently require zero setup-violating endpoints; they must require the WORST setup slack >= the limit of the stage (keep the violating-endpoint count as
a RESULT). `route.tcl` and `fill.tcl`: worst slack >= 0 (equivalent to zero violators; keep the existing check text but express it as the limit). Each RESULT line prints the margin to the limit.
The max-transition and max-capacitance checks stay at zero in every stage (the guidance says they must be clean).

### A4. The hold uncertainty

`HOLD_UNCERT` and `UNPU_HOLD_UNCERT` disappear from `params.tcl` (the hold uncertainty is a property of the profile, 0.05 ns). `cts.tcl`'s explicit `set_clock_uncertainty -hold` step is replaced by
`unpu_apply_profile cts` and its read-back check (the existing "hold uncertainty read back equals the parameter" check now compares with the profile). The stage switch `UNPU_CTS_STAGE`
(`all`/`tree`/`hold`) stays and works with profiles: in mode `hold` the profile `cts` is applied to the saved `cts` block. The block name overrides stay. Update the experiment text in both RUNBOOKs: the
hold uncertainty is no longer an experiment variable; the remaining experiment variables are listed.

### A5. Expectations derived from the netlist, not typed

`EXPECT_LEAF_CELLS` (12,487) and `EXPECT_NETLIST_MODULES` (76) are facts about the OLD netlist. Make them computed at run time from the chosen netlist file with the existing pure-Tcl netlist helpers
(`unpu_verilog_modules`, `unpu_verilog_cell_types`; the leaf-cell count is the number of instances of library cell types), printed as `RESULT` and used by the checks that used the constants
(`design_setup.tcl`, `power.tcl`, `outputs.tcl`, the `connect_pg_net` check). `EXPECT_PORTS` (204) and `EXPECT_SEQ_CELLS` (2465) stay constants: they follow from the unchanged RTL. If a computed count
differs from the previous netlist's (12,487 / 76), print it as an Info with the old values for comparison, not as a failure.

### A6. Probe list

Add to `PROBE_COMMANDS_ICC2` (and the test that counts the list): `report_clocks`, `set_propagated_clock`, `report_congestion`, `report_clock_tree` if it exists, `get_clocks`, `all_clocks`. The user will run the
probe again before the first run.

### A7. Tests, README, RUNBOOK

Tests for every new pure-Tcl helper and for the parameter validation; a stub run of each changed script showing the profile application and the new limits; `pnr/README.md` and `pnr/RUNBOOK.md`
updated (new variable `UNPU_SYN_PROFILE`, the profile per stage, where the netlist comes from, the removed variables, the new limits, the new first step: the probe). `pnr/VERIFY_STATUS.md`: add the new
VERIFY items.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old tests that tested the removed behaviour are changed, not deleted without a replacement; say which); all `pnr/*.tcl` complete Tcl; `tclsh constraints/test_stages.tcl`
   still passes.
2. Stub runs of `design_setup.tcl`, `placement.tcl`, `cts.tcl` (all three stage modes) and `route.tcl`, showing the logged command sequence with the profile applied first, and these failure paths: the
   profile read back with a wrong period; wrong uncertainty; the clock not propagated at `cts`; `UNPU_SYN_PROFILE` unset or `syn17`; setup WNS -1.5 at placement (FAIL) and -0.9 (pass); -0.5 at CTS (FAIL) and
   -0.3 (pass); setup -0.01 at route (FAIL); hold WNS -0.01 at route (FAIL).
3. `grep`: no `HOLD_UNCERT`, no `unpu_top_cn.sdc` as an input, no stale `syn/out/pm_flow` default anywhere in `pnr/` code (comments excepted); no `~/server_pull` path.
4. `git status`: only `pnr/` (plus nothing else). Do not commit.

## Constraints that apply

Standing rules of tasks 038 to 052. Every tool option must be in a usage text or marked VERIFY. No limit is changed to make a check pass: the limits are the instructor's table.

## Out of scope

Die size and utilisation checks, congestion, hold-buffer reporting (task 054); `constraints/`, `syn/`, `scripts/`, `rtl/`, `docs/planning/`; running anything on the server; committing.

## Report back

Files changed, per-item account of A1 to A7, Part B output, every `VERIFY` item (especially the clock re-definition and propagation), anything in this prompt that is wrong or ambiguous. Stop after reporting.
