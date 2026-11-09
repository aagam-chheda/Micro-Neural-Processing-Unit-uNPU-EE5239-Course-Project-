# Task 067 — Re-place the pins once the cells are placed (new step 4b, `pnr_v2/pin_replace.tcl`)

Read first: `docs/session-handoff.md` 18.9 (Q4: pin sides, layers, spacing), 18.27 (the `paddr[4]` antenna case: a long single-layer run from a pin to a tiny gate fails, no diode possible) and 18.32 (the new run, section "Antenna" below), `pnr_v2/floorplanning.tcl` (how the pins are constrained and placed),
`pnr_v2/placement.tcl`, `pnr_v2/cts.tcl`, `pnr_v2/README.md`.

## Why (the evidence, do not re-derive it)

In the clean-slate run `floorplanning.tcl` places the 204 pins once, BEFORE any cell exists (`place_pins -self`). The tool filled each edge from both ends in alternating pairs; for example `clk` is at offset 7.33 um (bottom of the right edge) and `rst_n` at 869.87 um (top), while the logic they drive sits near the middle (y about 440 um).
After route, Calibre antenna reports 55 results (`AN.MTL.1.M2` 12, `.M3` 25, `.MT` 18); one round of `fix_antenna.tcl` (layer hopping) left 50 (M3 14, MT 23, M2 about 13) and made setup worse (-0.07 to -0.10 ns).
The nets named by `fix_antenna.tcl` are mostly INPUT PORT nets: `pwdata[*]`, `psel`, `clk`, `rst_n`, `dma_rdata[9]`, `dma_rdata[11]`. A port net has no diode inside the macro, so its whole pin-to-gate wire counts against a gate area of about 0.19 um^2: the Calibre rules allow about 144 um of M3 or about 92 um of TOP_M per net.
Routing cannot shorten a net whose pin is far from its load. Pin position can. Placing the pins AFTER the cells are placed is the standard way to put each pin near its load.

## Goal

A new script `pnr_v2/pin_replace.tcl` (flow step 4b, between `placement.tcl` and `cts.tcl`) that opens the placed block, places the pins again with the cells known, makes the placement legal and timing-optimised again, checks the result, and saves a new block that `cts.tcl` then reads. The pin constraints stay exactly as the floorplan had them: same ports, same sides (top: `dma_*` on M2; right: APB plus `clk`, `rst_n` on M3; none elsewhere), same layers, same spacing. The tool is only allowed to choose NEW POSITIONS along those edges.

## Files

- Create `pnr_v2/pin_replace.tcl`. Style: the example scripts' (same header, `redirect -tee -file ${LOG_DIR}/4b_pin_replace.log {...}`, same variable names `DESIGN_NAME`, `PNR_DIR`, `BLOCKS_DIR`, `LOG_DIR`, one `BASE` literal as in the others, marker comments `# 067:` on anything that is not copied from the example).
- Modify `pnr_v2/cts.tcl`: ONE line, the `open_block` (line 43) from `${DESIGN_NAME}_placement` to the new block name, with a `;# 067:` marker. Nothing else in `cts.tcl`.
- Modify `pnr_v2/README.md`: add a row 4b to the run-order table and the block chain (`_placement` -> `_pinplace` -> `_cts`), one paragraph "Why step 4b" (the three sentences of the evidence above), and move D3 to "Decided": the first pin positions (floorplan, `pins_floorplan.txt`) are SUPERSEDED by the ones of step 4b; the top-level team gets the positions written by 4b.
- Nothing else. Do not touch `floorplanning.tcl`, `placement.tcl`, `route.tcl`, `fix_antenna.tcl`, `constraints/`, `syn/`, `pnr/`, the kit.

## What `pin_replace.tcl` does (decide the ICC2 details yourself; mark each unverified command or option `VERIFY`)

1. Close any open block/lib as the other scripts do; open `${DESIGN_NAME}.dlib:${DESIGN_NAME}_placement`; `link_block`.
2. Print the pin placement BEFORE (a short summary and the full `report_pin_placement -self` into `${PNR_DIR}/reports/pins_before_replace.txt`), so the two states can be compared.
3. Re-place the pins with the cells known: `place_pins -self`. Think about what the first `place_pins` left behind: pins already placed (and possibly fixed) are not moved by a second call. Find out from the real command help how to release them (for example the pin `physical_status` / fixed attribute, or `remove_pins` / `set_pin_physical_constraints`) WITHOUT losing the side/layer/spacing constraints, and implement it. If you cannot be sure, make the script print the physical status of a few pins before and after, and STOP with an error if no pin moved (nothing fails silently).
4. After the pins move, the cells are no longer optimal: re-optimise the placement. The default plan is `place_opt` again with the SAME app options as `placement.tcl` (copy that block, do not invent options), then `legalize_placement`, then the same checks `placement.tcl` runs (`check_legality`, `check_pg_drc`, `check_pg_connectivity`, `report_qor`, `report_global_timing`). If you think a lighter step is correct (for example `legalize_placement` followed by an incremental refinement), say why in the report, but the default stands unless you can show the lighter one is safe.
5. Checks that must print a number (and a hard `error` if wrong): pin count 204 (102 on side 2 / M2, 102 on side 3 / M3); `check_pin_placement -self` clean; legality 0 violations; the new offsets of `clk` and `rst_n`.
6. Write the pin list the top-level team needs, in the same format as `pins_floorplan.txt` (`block unpu_top pin <name> layer <L> side <S> offset <um>`), to `${PNR_DIR}/reports/pins_after_replace.txt`, and `report_pin_placement -self` into the log.
7. `save_block -as ${DESIGN_NAME}_pinplace`; `save_lib`; print `>>> STAGE 4b COMPLETE: ... saved`.
8. Print the net-length evidence the experiment is about: for the port nets `clk`, `rst_n`, `psel`, `pwdata[0]`, `pwdata[10]`, `pwdata[26]`, `dma_rdata[9]`, `dma_rdata[11]` the distance from the pin to the first load before and after (use cell and pin locations; if you cannot compute it reliably, print the pin offset and the x/y of its first load and say so).

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No timing option, goal, uncertainty or limit is changed. No diode is introduced (`adiode` stays unusable). The die size and the 20 um core offset are unchanged. Do not run anything on the server, do not commit.

## Acceptance test (local, no server)

1. `info complete` returns 1 for `pnr_v2/pin_replace.tcl` and `pnr_v2/cts.tcl` (`tclsh`).
2. `diff` of `pnr_v2/cts.tcl` against `git show HEAD:pnr_v2/cts.tcl`: exactly one changed line, with a `067` marker; paste the diff.
3. `grep -n "067" pnr_v2/pin_replace.tcl | wc -l` and a list of every `VERIFY` item with what the user should look at in the log to confirm it.
4. The README diff shows only the three additions above.
5. `git status`: only `pnr_v2/pin_replace.tcl`, `pnr_v2/cts.tcl`, `pnr_v2/README.md` changed or new, and this task file.
6. The README gives the user the run sequence as one csh command per line (`cd` to `pnr_icc2`, a `cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_pinplace` backup, then `icc2_shell -f ../pnr_v2/pin_replace.tcl |& tee pin_replace_console.log`, then the existing `cts.tcl`, `route.tcl`, `metal_fill.tcl`, `pv.tcl` lines), and the checks to read after step 4b.

## Report back

Files changed, the `cts.tcl` diff, the README diff, the list of `VERIFY` items, how you handle step 3 (releasing already-placed pins) and why, whether step 4 is `place_opt` or lighter and why, anything in this prompt that is wrong or ambiguous. Stop after reporting.
