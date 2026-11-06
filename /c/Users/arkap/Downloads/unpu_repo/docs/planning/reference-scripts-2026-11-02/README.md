# Reference ICC2 backend scripts (user's example set), received 2026-11-02

**These 11 files are PRISTINE. Do not edit them.** The working copies with the minimal edits are in `pnr_v2/` (task 063). Checksums: `SHA256SUMS`
(`sha256sum -c SHA256SUMS` must print only OK).

## Provenance

- Given by the user from `C:\Users\Aagam Chheda\Downloads\tcl_scripts_for_vlsi_backend_flow\` (WSL: `/mnt/c/Users/Aagam Chheda/Downloads/...`), copied 2026-11-02 with `cp -p` (bytes unchanged).
- They were written for a different design: `baseband_crypto_macro` under `/storage/EE5239G2/RFID_v2/` (the header comments and paths say so; another account on the same server).
  Same kit, same tool: `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180`, `icc2_shell` U-2022.12-SP3 (named in every header; our server's version is the same, handoff section 18).
- Four files have CRLF line endings (`build_ndm_filler`, `build_ndm_std`, `fix_antenna`, `metal_fill`); the other seven have LF. A trailing backslash before a CR breaks Tcl line continuations, so the working copies use LF.
- Why this set: user decision 2026-11-02, "clean slate": start in a new server folder with these scripts and minimal edits, the OLD constraints (20 ns, setup uncertainty 1.5, hold uncertainty 0.5,
  APB 35/35, DMA 40/40, `rst_n` 40, min delays 0 / -0.5), synthesis first, then gate-level simulation, then layout. The scripted `pnr/` flow (tasks 038 to 062) stays in the repo as an alternative; nothing is deleted.

## What each script does (flow order)

| Step | File | Tool | What it does | Design-specific content (what task 063 changes) |
|---|---|---|---|---|
| 0a | `build_ndm_std.tcl` | `icc2_lm_shell` | Reference library `scl180_std.ndm` from tech file, TLUPlus, std-cell LEF, ss and ff `.db` | output directory |
| 0b | `build_ndm_filler.tcl` | `icc2_lm_shell` | Physical-only `scl180_filler.ndm` (flow `physical_only`) from the same LEF | output directory |
| 1 | `design_setup.tcl` | `icc2_shell` | `.dlib`, read netlist, link, two scenarios (`func_ss` setup, `func_ff` hold), `read_sdc`, parasitics, hold cell purposes; saves `_setup` | design name, paths, netlist and SDC names, ff operating condition |
| 2 | `floorplanning.tcl` | `icc2_shell` | `initialize_floorplan`, pin constraints, `place_pins -self`; saves `_floorplan` | die/utilisation, the whole port list and sides |
| 3 | `powerplanning.tcl` | `icc2_shell` | M3/TOP_M ring, M3+TOP_M mesh, M1 rails, PG checks, VDD/VSS ports and terminals; saves `_powerplan` | design name, paths |
| 4 | `placement.tcl` | `icc2_shell` | `place_opt`, legalise, PG connect, reports; saves `_placement` | design name, paths |
| 5 | `cts.tcl` | `icc2_shell` | `clock_opt` with temporary extra uncertainty (hold goal +0.70, setup goal +0.30), restore spec; saves `_cts` | design name, paths, spec uncertainties |
| 6 | `route.tcl` | `icc2_shell` | antenna rules, global/track/detail route, redundant vias, `route_opt`, feedthrough fillers, ECO, checks; saves `_route` | design name, paths, spec uncertainties |
| 6b | `fix_antenna.tcl` | `icc2_shell` | reads a Calibre antenna DB, blocks and re-routes violating nets (loop after the first Calibre run) | design name, paths, the Calibre DB path |
| 7 | `metal_fill.tcl` | `icc2_shell` | `signoff_create_metal_fill`; saves `_filled` | design name, paths, one hard-coded coordinate window |
| 8 | `pv.tcl` | `icc2_shell` | final checks and reports, LEF, GDS (merged with std-cell and pad GDS), DEF, SPEF, Verilog (PG and sim), SDC and SDF per corner; saves `_pv` | design name, paths |

Block chain: `_setup` -> `_floorplan` -> `_powerplan` -> `_placement` -> `_cts` -> `_route` -> (`fix_antenna` rewrites `_route`) -> `_filled` -> `_pv`. Outputs under `pnr_icc2/` (`blocks`, `logs`, `reports`, `outputs`).

## Facts about the example set that matter for us (read before running)

1. Pins: the example places pins on all four sides with per-side spacing numbers sized for its own port count. Ours are fixed by the top-level team (handoff 18.9 Q4): RIGHT edge APB (100) plus `clk`, `rst_n` on M3; TOP edge DMA (102) on M2; none elsewhere.
2. The example reads the DC-written SDC in BOTH scenarios. Our DC-written SDC contains `set_operating_conditions tsl18fs120_scl_ss -library tsl18fs120_scl_ss` (see `docs/planning/synthesis-reports/round1-2026-10-08/unpu_top.sdc`), so the hold scenario would silently run at the ss
   condition. Task 063 sets the ff condition explicitly after the second `read_sdc` and prints `report_corners` (this is the one added behaviour; the real-tool command form `set_operating_conditions <lib> -library <lib>` was used in the earlier `pnr/` work).
3. `cts.tcl` and `route.tcl` raise the uncertainty temporarily (spec + goal), then restore the spec value typed in the script. The typed spec values (0.15 setup, 0.05 hold) belong to the example's own SDC; ours are 1.5 and 0.5, so they are edited. The goals (hold +0.70, setup +0.30) are the example's own tuning:
   kept as given, flagged for the user (task 063 open decisions).
4. Power pins: `powerplanning.tcl` creates ONE terminal per net on the first `TOP_M` shape it finds (an interior stripe), not on the die edge. The earlier decision (handoff 18.21: pins on the bottom edge) is not implemented; revisit after the first layout.
5. Not set by the example: the don't-use list (15 pattern cells plus the library's own `adiode`, `bh01d1`, `cload1`; handoff 18.15). The hold/optimisation cell purposes use `*/*BUF*` etc. and would also match drive strengths we may not want. Left as given; observed only.
6. The `get_lib_cells -quiet {scl180_std/...}` patterns assume the NDM library is named `scl180_std`; if it matches nothing the script silently skips the step (nothing in the log says so). Check the log lines; the earlier `pnr/` work found that `get_lib_cells` returns `lib/cell/view` names.
7. `route.tcl` antenna rule numbers (M3 diode ratio 100/45 and so on) were tuned by the example's author against their own Calibre result ("to clear the 14 M3 errors"). Kept as given; our earlier antenna problem (`paddr[4]`, handoff 18.27) is a separate matter.
8. `metal_fill.tcl` step 2 removes fill inside a 3 x 3 um window at (33..36, 374..377) that was a violation of the example's own layout; it means nothing for our die and is commented out in the working copy.
