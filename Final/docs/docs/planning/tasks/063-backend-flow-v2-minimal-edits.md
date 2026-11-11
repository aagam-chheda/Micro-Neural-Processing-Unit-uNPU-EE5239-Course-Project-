# Task 063 — `pnr_v2/`: the user's example ICC2 scripts, copied and minimally edited for `unpu_top`

Read first: `docs/planning/reference-scripts-2026-11-02/README.md` (provenance, what each script does, the facts that decide the edits), `docs/session-handoff.md` section 18.9 (Q4: pin sides decided by the top-level team),
`CLAUDE.md`. Nothing from `pnr/` is reused or modified: this is a clean slate (user decision 2026-11-02). Do NOT run anything on the server (the user does that).

## Goal

Create `pnr_v2/` holding the 11 example scripts with the MINIMUM edits listed below, so that the user can run them for `unpu_top` in a new server folder.

## Files

- Source (read-only, do not edit): `docs/planning/reference-scripts-2026-11-02/*.tcl`.
- Create: `pnr_v2/` with the same 11 file names: `build_ndm_std.tcl build_ndm_filler.tcl design_setup.tcl floorplanning.tcl powerplanning.tcl placement.tcl cts.tcl route.tcl fix_antenna.tcl metal_fill.tcl pv.tcl`.
- Create: `pnr_v2/README.md` (run order, section "Edits" = the table below as done, section "Open decisions" = D1 to D5).
- Modify: `.gitignore` — add `pnr_icc2/` with a one-line comment (ICC2 outputs of the pnr_v2 flow; written next to the clone on the server).
- Nothing else.

## Method

1. `cp` each reference file to `pnr_v2/`, then convert CRLF to LF (`tr -d '\r'`) in the four files that have CRLF (`build_ndm_filler`, `build_ndm_std`, `fix_antenna`, `metal_fill`). This is edit E0.
2. Apply ONLY the edits below. Keep the example's structure, names, comments, option values and layout otherwise (do not tidy, do not rename, do not add frameworks, do not add checks). Each edit gets a trailing
   `;# 063: <reason>` or a `# 063:` comment line so that `diff` shows it. The only added behaviour is E5b.
3. The server base path is one literal per file, as in the example: `/storage/EE5239G1/aagams_workspace2/unpu` (call it BASE). It is an ASSUMPTION (the user said "aagams_workspace2/unpu"); the README says "if the folder differs: `sed -i 's#/storage/EE5239G1/aagams_workspace2/unpu#<real path>#' pnr_v2/*.tcl`".

## Edits

| # | Files | Edit |
|---|---|---|
| E0 | the four CRLF files | line endings to LF (see Method 1) |
| E1 | all 11 | header comment `# Path  : ...` (or `# File:`) line: new path `BASE/pnr_v2/<file>` (comment only) |
| E2 | all but the two `build_ndm_*` | `DESIGN_NAME` `"baseband_crypto_macro"` -> `"unpu_top"` |
| E3 | `build_ndm_std`, `build_ndm_filler` | `OUT_NDM_DIR` -> `BASE/pnr_icc2` |
| E3b | all other scripts | `PNR_DIR` -> `BASE/pnr_icc2`; `PROJ_DIR` (design_setup only) -> `BASE` |
| E4 | `design_setup.tcl` | `SYN_OUT_DIR` -> `"${PROJ_DIR}/syn/out/legacy"`; `NETLIST_FILE` -> `"${SYN_OUT_DIR}/unpu_top_cn.dc.v"`; `SDC_FILE` -> `"${SYN_OUT_DIR}/unpu_top_cn.sdc"`. (`syn/out/legacy/` is produced by the next task, the synthesis with the old constraints; say so in the comment.) |
| E5a | `design_setup.tcl` | none other than E4 in step 5 except E5b |
| E5b | `design_setup.tcl` | right after the SECOND `read_sdc ${SDC_FILE}` (scenario `func_ff`) add `set_operating_conditions tsl18fs120_scl_ff -library tsl18fs120_scl_ff`, and at the end of step 5 (after `set_scenario_status func_ff ...`) add `report_corners`. Reason in the comment: the DC-written SDC carries the ss operating condition, so without this the hold scenario is analysed at ss. The library names are `LIB_SS_NAME`/`LIB_FF_NAME` of the old `pnr/params.tcl` (`tsl18fs120_scl_ss`, `tsl18fs120_scl_ff`). |
| E6 | `floorplanning.tcl` | `initialize_floorplan -control_type die -boundary {{0 0} {530 530}} -core_offset {20 20 20 20} -core_utilization 0.85` -> `initialize_floorplan -control_type core -core_utilization 0.60 -core_offset {20 20 20 20}` (die derived by the tool from the netlist area; 0.60 = instructor guidance "start utilisation 60 to 70 percent", pessimistic end; the offset 20 stays because the PDN ring in `powerplanning.tcl` sits in it). Fix the step-3 comment to match. |
| E7 | `floorplanning.tcl` | pins per the top-level team (handoff 18.9 Q4): delete the `side1_ports` and `side4_ports` definitions and their `if` blocks. `side3_ports` (RIGHT, M3) = `{paddr[*] pwdata[*] prdata[*] pwrite psel penable pready clk rst_n}` (102 pins), `-pin_spacing_distance 8`. `side2_ports` (TOP, M2) = `{dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] dma_valid dma_ready}` (102 pins), `-pin_spacing_distance 8`. (8 um >= the old flow's minimum pitch 6.72 um; 102 pins x 8 um fits one edge of a die near 900 um.) Keep the example's `set_block_pin_constraints -self`, the `place_pins -self` and the checks. |
| E8 | `floorplanning.tcl` | delete the three `VDD`/`VSS` `set_individual_pin_constraints` lines of the `power_ports` block (those ports do not exist before `powerplanning.tcl`, and the sides used there belong to the deleted groups); update `assigned_ports` to `{paddr[*] pwdata[*] prdata[*] dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] pwrite psel penable pready clk rst_n dma_valid dma_ready}` and keep the catch-all (it must stay empty: add one `puts ">>> unassigned ports: [sizeof_collection $misc_ports]"` line before it, expected 0). |
| E9 | `cts.tcl`, `route.tcl` | `SPEC_HOLD_UNC` 0.05 -> 0.5 and `SPEC_SETUP_UNC` 0.15 -> 1.5 (every occurrence; `route.tcl` has its own copies). Reason: these are the values the typed restore steps put back, and the old constraints (the SDC the flow reads) have setup 1.5, hold 0.5. `HOLD_SLACK_GOAL` (0.70) and `SETUP_SLACK_GOAL` (0.3, 0.30) are NOT changed (open decision D2). |
| E10 | `metal_fill.tcl` | comment out step 2 (`signoff_create_metal_fill -mode remove ... -coordinates {{{33.0 374.0} {36.0 377.0}}}`), with a comment: window specific to the example's own layout. |
| E11 | `fix_antenna.tcl` | `ANT_DB` -> `BASE/pv/drc/unpu_top_antenna_bkp.db` with a comment "path of the Calibre antenna result; created later; the script stops with its own error if the file is missing". No other change. |
| E12 | `powerplanning.tcl`, `placement.tcl`, `pv.tcl`, `route.tcl`, `metal_fill.tcl` | only E1, E2, E3b (plus E9 for `route.tcl`, E10 for `metal_fill.tcl`). |

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." The example hard-codes its paths (one literal per file); keep that style, with BASE
the only literal. No limit, goal or tool option is changed except as listed. Do not add `set_dont_use`, checks, or new options (observations in the reference README, items 5 to 7, are for the user to decide).

## Acceptance test

1. `cd docs/planning/reference-scripts-2026-11-02 ; sha256sum -c SHA256SUMS` prints only OK (pristine files untouched).
2. For each file: `diff -u <(tr -d '\r' < reference) pnr_v2/<file>` — paste the whole diff into the report; every hunk must map to a row of the table (E-number named in the report). Lines without a `063` marker that differ are a defect.
3. `grep -rnE "EE5239G2|RFID|baseband|crypto|PADDR|PRDATA|PWDATA|530" pnr_v2/*.tcl` prints nothing (comments included, except the E1 header lines must not contain them either).
4. Each file is complete Tcl: `tclsh` with `info complete [read $f]` returns 1 for all 11 (this only checks brace balance; no ICC2 command is run).
5. `file pnr_v2/*.tcl` shows no CRLF; `git status` shows only `pnr_v2/`, `.gitignore` (and the files already changed by the earlier uncommitted tasks, which you must not touch).
6. Do not commit. Do not run anything on the server.

## Open decisions to put in `pnr_v2/README.md` (the user decides; do not decide them)

- D1 BASE path (assumed `/storage/EE5239G1/aagams_workspace2/unpu`).
- D2 `HOLD_SLACK_GOAL 0.70` and `SETUP_SLACK_GOAL 0.30` are the example's own margins on top of our already large uncertainties (hold 0.5 -> optimiser sees 1.2 ns; setup 1.5 -> 1.8 ns). Planning's recommendation: set both to 0.0 (the optimiser then
  sees exactly the course constraints) before the `cts` run; it is one line each in `cts.tcl` and `route.tcl`. Not done here because it is a constraint choice.
- D3 pin ORDER (bits ascending, top edge bit 0 at the left, right edge bit 0 at the bottom, handoff 18.9 Q5) is not enforced by the example's commands; only the sides, layers and spacing are. Check `report_pin_placement` output after `floorplanning.tcl`.
- D4 power pins: one terminal per net on an interior TOP_M stripe (example behaviour) instead of the bottom-edge pins of handoff 18.21 — revisit after the first layout.
- D5 start utilisation 0.60 instead of the example's 0.85 (E6).

## Out of scope

`pnr/`, `constraints/`, `syn/`, `scripts/`, `rtl/`, `tb/`, `docs/planning/`; the synthesis with the old constraints (next task); running anything; committing.

## Report back

The full `diff -u` output, the E-number of every hunk, results of acceptance checks 1 to 5, anything in this prompt that is wrong or ambiguous. Stop after reporting.
