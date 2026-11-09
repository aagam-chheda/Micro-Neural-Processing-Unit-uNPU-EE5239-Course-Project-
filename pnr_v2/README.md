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
| 4b | `pin_replace.tcl` | `icc2_shell` (task 067: re-places the pins after the cells are placed; reads `_placement`, writes `_pinplace`) |
| 5 | `cts.tcl` | `icc2_shell` (reads `_pinplace` since task 067) |
| 6 | `route.tcl` | `icc2_shell` |
| 6b | `fix_antenna.tcl` | `icc2_shell` (after the first Calibre antenna run; needs `<BASE>/pv/drc/unpu_top_antenna_bkp.db`) |
| 7 | `metal_fill.tcl` | `icc2_shell` |
| 8 | `pv.tcl` | `icc2_shell` |

Block chain: `_setup` -> `_floorplan` -> `_powerplan` -> `_placement` -> `_pinplace` -> `_cts` -> `_route` -> `_filled` -> `_pv`.

## Why step 4b (task 067)

In the clean-slate run `floorplanning.tcl` places the 204 pins once, before any cell exists (`place_pins -self`); the tool filled each edge from both ends in alternating pairs, so for example `clk` is at offset 7.33 um (bottom of the right edge) and `rst_n` at 869.87 um (top) while the logic they drive sits near the middle.
After route, Calibre antenna reported 55 results and one round of `fix_antenna.tcl` left 50 and made setup worse; the nets it names are mostly input port nets (`pwdata[*]`, `psel`, `clk`, `rst_n`, `dma_rdata[9]`, `dma_rdata[11]`), which have no diode inside the macro, so the whole pin-to-gate wire counts against a gate area of about 0.19 um^2 (about 144 um of M3 or about 92 um of TOP_M per net).
Routing cannot shorten a net whose pin is far from its load, but pin position can: placing the pins after the cells are placed is the standard way to put each pin near its load.

`pin_replace.tcl` keeps the pin constraints of the floorplan untouched (same ports, sides, layers, spacing) and only lets the tool choose new positions along the same edges. Then it runs `place_opt` again with the same options as `placement.tcl`, `legalize_placement` and the same checks, and saves `_pinplace`. Pin-release method (plan A `place_pins -self` again, plan B `remove_terminals -force` on the 204 signal terminals only) and every check are in the script header and log.

### Run sequence for step 4b (csh, from the server; one command per line)

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_pinplace
icc2_shell -f ../pnr_v2/pin_replace.tcl |& tee pin_replace_console.log
```

Type `exit` at the `icc2_shell` prompt (the scripts do not call it). The steps after it must be run again, because the blocks `_cts`, `_route`, `_filled`, `_pv` of an earlier run were built from `_placement` (`cts.tcl` removes the old `_cts` itself):

```
icc2_shell -f ../pnr_v2/cts.tcl |& tee cts_console.log
icc2_shell -f ../pnr_v2/route.tcl |& tee route_console.log
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl |& tee pv_console.log
```

If step 4b fails or the result is not wanted: `rm -r blocks/unpu_top.dlib` and `mv blocks/unpu_top.dlib.bak_pre_pinplace blocks/unpu_top.dlib` restores the library as it was before 4b (the script saves nothing when a check fails, but `place_opt` has changed the open block in memory only).

### What to read after step 4b

In `pin_replace_console.log` (also `logs/4b_pin_replace.log`), lines that start with `>>> 067`:

- `signal ports 204, top group 102, right group 102` and `terminals in the block before` / `after` (equal).
- `plan A ... moved pins N of 204`: N must be above 0. If plan A did not release the pins, `plan B` lines follow. `statuses seen` lists the `physical_status` values of the terminals before the move.
- `BEFORE clk` / `BEFORE rst_n` offsets: compare with `pins_floorplan.txt` (7.33 and 869.87 um in the first run) to confirm that the offset in the pin list means the same thing; `AFTER clk` / `AFTER rst_n` are the new ones.
- `CHECK` lines: legality violations 0, pins moved by `place_opt` 0, pins on side 2 / M2 = 102 and side 3 / M3 = 102, smallest centre pitch per edge at least 8 um, `check_pin_placement -self` no problem line. Any failed check stops the script with `ERROR 067` and nothing is saved.
- `EVIDENCE` lines: for `clk rst_n psel pwdata[0] pwdata[10] pwdata[26] dma_rdata[9] dma_rdata[11]` the nearest and farthest load distance from the pin before and after. The experiment worked if these distances got shorter.
- Timing in the `report_qor` / `report_global_timing` output of this step: compare setup and hold with the end of `placement.tcl` (the pins moved, the cells were optimised again).
- `STAGE 4b COMPLETE`. New files: `pnr_icc2/reports/pins_before_replace.txt`, `pins_after_replace.txt` (the pin list for the top-level team, format `block unpu_top pin <name> layer <L> side <S> offset <um>`) and `pins_after_replace_report.txt` (the tool's own `report_pin_placement -self`).

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
- **D3** Pin ORDER (bits ascending, handoff 18.9 Q5) is not enforced by the example's commands; only sides, layers and spacing are. The tool's placement was accepted after the floorplan (handoff 18.32, `pins_floorplan.txt`). SUPERSEDED by task 067: the first pin positions (floorplan) are replaced by the ones of step 4b (`pin_replace.tcl`); the top-level team gets the positions written by 4b (`pnr_icc2/reports/pins_after_replace.txt`).

## Open decisions (the user decides; NOT decided here)

- **D4** Power pins: one terminal per net on an interior `TOP_M` stripe (example behaviour), not the bottom-edge pins of handoff 18.21. Revisit after the first layout.
- **D5** Start utilisation 0.60 instead of the example's 0.85 (E6).
