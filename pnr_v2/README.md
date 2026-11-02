# pnr_v2 -- the user's example ICC2 scripts, minimally edited for `unpu_top` (task 063)

Pristine originals: `docs/planning/reference-scripts-2026-11-02/` (do not edit; `sha256sum -c SHA256SUMS`).
Every edited line carries a `063` marker (`;# 063 En: ...` or a `# 063 En:` comment line), so `diff` shows exactly what changed.
Nothing here has been run: the user runs it on the server.

## Run order

Server folder (ASSUMED, decision D1): `/storage/EE5239G1/aagams_workspace2/unpu`, with this repo cloned there. Outputs go to `<BASE>/pnr_icc2/` (`blocks logs reports outputs`; git-ignored).
If the folder differs: `sed -i 's#/storage/EE5239G1/aagams_workspace2/unpu#<real path>#' pnr_v2/*.tcl`

| Step | Script | Tool |
|---|---|---|
| 0a | `build_ndm_std.tcl` | `icc2_lm_shell` |
| 0b | `build_ndm_filler.tcl` | `icc2_lm_shell` |
| 1 | `design_setup.tcl` | `icc2_shell` (needs `syn/out/legacy/unpu_top_cn.dc.v` and `.sdc` from the synthesis with the old constraints, next task) |
| 2 | `floorplanning.tcl` | `icc2_shell` |
| 3 | `powerplanning.tcl` | `icc2_shell` |
| 4 | `placement.tcl` | `icc2_shell` |
| 5 | `cts.tcl` | `icc2_shell` |
| 6 | `route.tcl` | `icc2_shell` |
| 6b | `fix_antenna.tcl` | `icc2_shell` (after the first Calibre antenna run; needs `<BASE>/pv/drc/unpu_top_antenna_bkp.db`) |
| 7 | `metal_fill.tcl` | `icc2_shell` |
| 8 | `pv.tcl` | `icc2_shell` |

Block chain: `_setup` -> `_floorplan` -> `_powerplan` -> `_placement` -> `_cts` -> `_route` -> `_filled` -> `_pv`.

## Edits

| # | Files | Edit as done |
|---|---|---|
| E0 | `build_ndm_filler build_ndm_std fix_antenna metal_fill` | CRLF -> LF (a trailing backslash before a CR breaks Tcl line continuation) |
| E1 | all 11 | header `# Path  :` / `# File:` line names `<BASE>/pnr_v2/<file>` (comment only) |
| E2 | all but the two `build_ndm_*` | `DESIGN_NAME` `"unpu_top"` |
| E3 | `build_ndm_std build_ndm_filler` | `OUT_NDM_DIR` = `<BASE>/pnr_icc2` |
| E3b | all other scripts | `PNR_DIR` = `<BASE>/pnr_icc2`; `design_setup.tcl`: `PROJ_DIR` = `<BASE>` (its `PNR_DIR` follows `PROJ_DIR`, text unchanged) |
| E4 | `design_setup.tcl` | `SYN_OUT_DIR` = `${PROJ_DIR}/syn/out/legacy`, `NETLIST_FILE` = `unpu_top_cn.dc.v`, `SDC_FILE` = `unpu_top_cn.sdc` |
| E5b | `design_setup.tcl` | after the second `read_sdc`: `set_operating_conditions tsl18fs120_scl_ff -library tsl18fs120_scl_ff`; at the end of step 5: `report_corners` (the DC-written SDC carries the ss operating condition) |
| E6 | `floorplanning.tcl` | `initialize_floorplan -control_type core -core_utilization 0.60 -core_offset {20 20 20 20}` (die from the tool), step-3 comment fixed |
| E7 | `floorplanning.tcl` | side 2 (top, M2) = DMA port, side 3 (right, M3) = APB port + `clk` `rst_n`, spacing 8 um; side 1 and side 4 groups deleted |
| E8 | `floorplanning.tcl` | the two VDD/VSS `set_individual_pin_constraints` lines deleted; `assigned_ports` updated; `unassigned ports` count printed (expected 0) |
| E9 | `cts.tcl route.tcl` | `SPEC_SETUP_UNC` 1.5, `SPEC_HOLD_UNC` 0.5 (every occurrence) |
| E10 | `metal_fill.tcl` | step 2 (remove-fill window of the example's own layout) commented out |
| E11 | `fix_antenna.tcl` | `ANT_DB` = `<BASE>/pv/drc/unpu_top_antenna_bkp.db` |

## Decided (user, 2026-11-02)

- **D1** BASE path `/storage/EE5239G1/aagams_workspace2/unpu` is right (no change to the scripts).
- **D2** `HOLD_SLACK_GOAL` and `SETUP_SLACK_GOAL` are 0.0 in `cts.tcl` and `route.tcl` (task 065; the example had 0.70 and 0.3/0.30), so the optimiser sees exactly the course constraints (setup 1.5, hold 0.5). Lines marked `065`.

## Open decisions (the user decides; NOT decided here)

- **D3** Pin ORDER (bits ascending, top edge bit 0 at the left, right edge bit 0 at the bottom, handoff 18.9 Q5) is not enforced by the example's commands; only sides, layers and spacing are. Check `report_pin_placement` after `floorplanning.tcl`.
- **D4** Power pins: one terminal per net on an interior `TOP_M` stripe (example behaviour), not the bottom-edge pins of handoff 18.21. Revisit after the first layout.
- **D5** Start utilisation 0.60 instead of the example's 0.85 (E6).
