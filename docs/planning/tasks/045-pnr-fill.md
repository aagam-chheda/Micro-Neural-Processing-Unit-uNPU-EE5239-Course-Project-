# Task 045 — back-end re-run, script 7: `pnr/fill.tcl` (filler cells, last step in ICC2 before the outputs)

Read first: `docs/planning/backend-rerun-plan.md` (stage E1), `pnr/README.md`, the current `pnr/*.tcl`,
`docs/session-handoff.md` 18.22 (fillers: what went wrong, the order that works, the hold residual and the decision
about it) and 18.23 (what the outputs need).

## Goal

One script that opens the routed, unfilled block, inserts the three filler cells everywhere there is a free site,
connects their power pins, checks the filled block, and saves it as the final block of the ICC2 flow. The fillers come
from the library that `ndm_file_gen.tcl` built (task 038): their presence and type are checked, not repaired.

## Part A — what to write

### A1. `pnr/fill.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/route.tcl`. Say in the header that fill is the LAST step: any later `route_opt` deletes all
fillers and does not put them back (18.22), so a routing change means going back to `$BLK_ROUTED` and filling again.
Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin fill run <library>`; the library must
   exist; refuse to run if `$BLK_FINAL` already exists; open `$BLK_ROUTED`.
2. Preconditions, each a CHECK: `get_lib_cells -quiet <FILLER_PATTERN>` returns exactly the three cells of
   `FILLER_CELLS` and each has `design_type` `filler` (otherwise `create_stdcell_fillers` fails with `CHF-010/011` as
   in 18.22; the message must say that `ndm_file_gen.tcl` / `ndm_check.tcl` is where to fix it, not here); the block has
   no filler cell yet (count the cells whose reference matches the filler names; must be 0); `check_routes` on the
   input is clean (open nets 0, DRCs 0); the input block's `check_legality` is 0.
3. Insert: `create_stdcell_fillers -lib_cells [get_lib_cells <FILLER_PATTERN>] -prefix <FILLER_PREFIX> -rules
   post_route_auto_delete` (18.22, the exact form that worked), output captured. Parse the lines it prints per cell
   (the first run's form: `... 4159 of regular filler feedth9 inserted`, `... 7451 of regular filler feedth3
   inserted`, `... 10902 of regular filler feedth inserted`) into counts per cell and a total, with a pure-Tcl
   procedure in `common.tcl`. CHECK: the total is greater than 0 and each of the three cells appears.
4. Connect the power pins at once (18.22: the fillers' `VDD`/`VSS` pins stay unconnected until this; without it the
   DRC engine reported about 17,766 false M1 shorts): `connect_pg_net -automatic`, output captured and parsed (the
   table `Power net VDD   previous/current` and the line `connections of N power/ground pin(s) are created or
   changed`; the first run: VDD 12041/34553, VSS 12041/34553, 45,024 pins). CHECK: the number of pins connected
   equals 2 x the number of fillers inserted; the new VDD and VSS counts equal the leaf-cell count before plus the
   number of fillers (read the leaf-cell count before the insertion as a number: it is what `connect_pg_net` printed
   as `previous`).
5. Coverage check (a consistency check on the fill itself): the sites covered by fillers
   (`9*n(feedth9) + 3*n(feedth3) + 1*n(feedth)`) must equal the free sites: the total number of sites in the rows
   (rows x sites per row, from `FP_ROWS` and the core width over `SITE_WIDTH`) minus the sites taken by the standard
   cells (cell area / (SITE_WIDTH x ROW_HEIGHT), the cell area from the tool's report; VERIFY which report gives
   the standard-cell area without the fillers; read it BEFORE the insertion). In the first run this was exact:
   cell area 428,609.66 um2 / 3.136 = 136,674 sites; 144 rows x 1,440 sites = 207,360; free 70,686; the fillers
   covered 9 x 4,159 + 3 x 7,451 + 10,902 = 70,686. CHECK equality within 2 sites; if the cell area cannot be read, a
   Warning and the arithmetic printed as RESULT, not a check.
6. Checks on the filled block, one `unpu_check_pass` each (unreadable = FAIL "unavailable"):
   - `check_routes`: open nets 0, DRCs 0, antenna violations 0 (ICC2's view; the 80 skipped port nets are counted and
     printed as in `route.tcl`: Calibre decides), reuse the parsers of `route.tcl`;
   - `remove_stdcell_fillers_with_violation -check_only true` (18.22): the number of fillers with violations must be
     0 (VERIFY the output; 18.22 says it lists them in `<block>_fillers_with_violation.rpt`). If it is not 0, the
     script stops without saving and says what 18.22 did (one real violation after the power connection was fixed
     with `route_eco`, one net moved). OPTIONAL: if the environment variable `UNPU_FILL_ECO` is `1`, run `route_eco`
     once, print the nets it changed, and repeat this check; never more than one round; default off;
   - `check_legality` 0; `check_pg_connectivity` 0 floating cells, wires, vias, terminals;
   - setup: violating endpoints 0 in `$SCEN_SETUP` (CHECK);
   - hold in `$SCEN_HOLD`: the decision of 2026-10-29 (18.22, option A) was to accept a SUB-PICOSECOND residual caused
     by the filler capacitance and let PrimeTime judge. New parameter `FILL_HOLD_TOLERANCE_NS 0.001`. Rule: zero
     violating endpoints = CHECK PASS; violating endpoints whose worst slack is not worse than
     `-FILL_HOLD_TOLERANCE_NS` = a Warning that quotes the endpoints and the decision, recorded in the manifest
     (`hold_residual_accepted = 1`, endpoints, worst slack), not a failed check; anything worse, or an
     unavailable count = CHECK FAIL. Reuse `unpu_timing_summary`;
   - max transition and max capacitance: 0 (CHECK);
   - RESULT lines: filler counts per cell and total, filler sites and free sites, area and utilisation before and after
     (the fillers add cell area), wire length unchanged from the routed block.
7. `unpu_checks_finish fill`, then `unpu_checkpoint $BLK_FINAL`, then the summary lines. The last log line must say:
   the final block is FILLED; do not run `route_opt` on it; the outputs come from this block.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `FILL_HOLD_TOLERANCE_NS 0.001` (with the decision of 2026-10-29 as its source), `FILL_ECO` from
  `UNPU_FILL_ECO` (0|1, validated, default 0).
- `pnr/common.tcl`: the filler-count parser, the `connect_pg_net`-summary parser if the existing one does not return the
  "pins created or changed" line (extend it, do not copy), a procedure that computes the free sites from rows, sites
  per row and cell area, and the check of the filler coverage.
- `pnr/test_common.tcl`: tests for each, with the first run's numbers (`4159 / 7451 / 10902`, 45,024, 428,609.66, 144
  rows, 1,440 sites per row, 70,686 free sites), the new die's geometry (153 rows, 1,530 sites per row), a wrong
  coverage, a missing cell type, and the hold rule (0 violations; 1 ps residual accepted with a Warning; 5 ps residual
  fails; unavailable fails).
- `pnr/README.md`: row 10 written; `UNPU_FILL_ECO` in the environment table.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 240 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `fill.tcl` (scratch only) with the logged command sequence in the order of A1 and these
   failure paths firing: library or block `routed` missing; block `final` present; fillers not typed filler; fillers
   already in the block; input `check_routes` not clean; wrong pin count; coverage off by 50 sites; fillers with
   violations (with and without `UNPU_FILL_ECO=1`); setup violations; hold residual of 0.4 ps (Warning, saves, manifest
   line) and of 5 ps (fails); floating cells. State what the stub proves and does not.
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; nothing written under `SCL_KIT_ROOT`; no `route_opt`
   anywhere in `fill.tcl` except in comments.
5. `git status`: only `pnr/` changed.

## Part C — server block for the user (in your report)

csh commands with the `$UNPU_REPO` placeholder and the `icc2_shell -file ... fill.tcl -output_log_file ...` line, what a
good result looks like (the coverage CHECK, pin count = 2 x fillers, hold residual Warning possible), the grep and the
files to paste back (the filler counts, the `connect_pg_net` table, the violation report), and the rerun note (fill is
re-done from `$BLK_ROUTED` under a new `UNPU_BLK_FINAL` name or a new run tag).

## Constraints that apply

Standing rules of tasks 038 to 044. Mark every tool command or option not shown in the handoff `VERIFY`. Do not add
any fill option beyond the one in 18.22.

## Out of scope

Outputs (netlists, LEF, GDS, SPEF, SDF, SDC), Calibre, PrimeTime, pin placement, placement; antenna repair;
`rtl/`, `constraints/`, `syn/`, `docs/planning/`; running anything on the server; committing.

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt
that is wrong or ambiguous, and the Part C block. Stop after reporting.
