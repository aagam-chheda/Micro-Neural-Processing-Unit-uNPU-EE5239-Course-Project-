# Task 054 — `pnr/`: die size from the new synthesis area, utilisation and congestion checks, netlist growth report

Read first: `docs/planning/constraints-update-2026-11-02.md` section 5 (PnR consequences) and 9 (decisions), `docs/planning/instructor-guidance-2026-10-27.md` POST 2 (utilisation and growth tables, verbatim),
`pnr/README.md`, `pnr/RUNBOOK.md`, `pnr/VERIFY_STATUS.md` (K1 to K42), and the scripts you change (`params.tcl`, `floorplan.tcl`, `pin_place.tcl`, `placement.tcl`, `cts.tcl`, `route.tcl`, `fill.tcl`, `common.tcl`).
Task 053 is done and accepted; the profile machinery, `UNPU_SYN_PROFILE` and the netlist-derived counts exist. Build on them.

## Goal

The 868.0 um die was sized for the OLD netlist (429,161 um2 at DC round 3). The new synthesis (syn20/18/16) has a different cell area, and the instructor gave utilisation limits per stage and a growth
budget. This task derives the die from the chosen synthesis, checks utilisation and congestion at each stage against the instructor's limits, and reports how much the netlist grew and where.

## Part A — what to write

### A1. Die size from the synthesis area (no typed die)

- Source of the cell area: the DC area report of the chosen profile, `$REPO_ROOT/syn/out/$SYN_PROFILE/unpu_top.area` ("Total cell area"). Parameter `SYN_AREA_FILE`, derived from `SYN_PROFILE`; a pure-Tcl parser
  `unpu_parse_syn_area` in `common.tcl` that is STRICT (the line must be found exactly once and the value must be a positive number; otherwise STOP with the file name and the lines that were seen). Look at
  `docs/planning/synthesis-reports/round3-2026-10-14/` for the real layout of the area report (the old name of the file may differ; the layout of "Total cell area" is what matters).
- Rule (parameters, each with its source in a comment): start utilisation `FP_START_UTIL 0.60` (instructor: 60 to 70 percent; the most pessimistic end = the most room); core area = cell area / `FP_START_UTIL`; the core
  is square; core side = the smallest MULTIPLE OF THE ROW HEIGHT (5.6 um) that is >= sqrt(core area); die side = core side + 2 x `CORE_OFFSET` (5.6, so +11.2). All other consistency checks of `unpu_floorplan_check`
  (rows integer, sites integer, offset a multiple of site and row) stay and must pass for the derived value. Pure-Tcl `unpu_die_from_area` with tests: a hand-computed example from the OLD area (429,161 um2 at 0.60:
  core area 715,268.3, side 845.7, 151.0 rows rounds UP to 152 rows = 851.2 um, die 862.4 um; recompute these in the test independently), an exact-multiple case (must NOT add a row), a tiny area, a
  non-positive area (STOP), a start utilisation outside 0.3 to 0.9 (STOP).
- `PLAN_DIE_SIZE 868.0` is removed. `UNPU_DIE_SIZE` stays ONLY as an experiment knob that overrides the derived value with a Warning that prints both (as the old override did). Scripts that need no die
  (probes, NDM scripts, `ndm_check`, `design_setup` before the floorplan) must still run with `UNPU_SYN_PROFILE` unset; the die is computed when `floorplan.tcl` needs it (your design; say how).
- The derived die, core, rows, start utilisation, the cell area and the profile are RESULT lines in `floorplan.tcl` and are written to the manifest. Scripts that follow (`pin_place`, `placement`, ...) must not
  recompute silently with a different `UNPU_SYN_PROFILE`: record the profile in the floorplan block (an attribute or the manifest/`UNPU_RUN_TAG` mechanism you already have) and make `placement.tcl` CHECK that
  `UNPU_SYN_PROFILE` equals the profile the floorplan was made from (a mismatch = FAIL with both names). Say what you chose.
- `EXPECT_ROWS`, `FP_ROWS` and everything derived from the die follow automatically; check `grep` for other uses of `PLAN_DIE_SIZE` and `868`/`817.6` in code (comments excepted) and fix them.
- The expected macro size is told to the top-level team by Planning later; the script prints the die in um and in um2 as RESULT.

### A2. Utilisation checks (instructor POST 2, the pessimistic end where a range is given)

Parameters: `UTIL_MAX_PLACE 0.75` (post-placement, instructor "<= 75%"), `UTIL_MAX_CTS 0.80`, `UTIL_MAX_ROUTE 0.80` (post-CTS/post-route, instructor "<= 80-85%": the user's rule takes the lower value).
The definition is standard-cell area / core area (what `report_utilization` prints; VERIFY which number the tool calls "utilization"; take it from the report text and cross-check it by computing
cell area / core area yourself from the area you parse: if the two differ by more than 0.5 percentage points, print a Warning with both). New CHECKS: after `place_opt` in `placement.tcl`, after the hold
optimisation in `cts.tcl`, after `route_opt` and after `route_auto` (Warning only) in `route.tcl`: utilisation <= the stage limit, with the margin as RESULT. An unreadable utilisation is a FAIL
(nothing fails silently), not a skip. The final fill is not checked (fillers bring it to 100 percent).

### A3. Congestion after placement

`placement.tcl` runs `report_congestion` (on the placed block; read its usage text in `~/server_pull/rpt/help/` if the probe was run, otherwise mark every option VERIFY), saves the text to `$RPT_DIR`, and CHECKS the
overflow against `CONGESTION_MAX_PCT 1.0` (instructor: "above about 1-2 percent: lower the utilisation or spread the cells"; the lower value is the pessimistic one). A pure-Tcl parser
`unpu_parse_congestion` for the overflow percentage (or the overflow counts the report prints: decide from the real layout if you have one; if not, make the parser strict, assume the common
"Both Dirs / H routing / V routing  ... overflow ..." table of ICC2 and mark the layout VERIFY). Unreadable = FAIL. A FAIL message says what the instructor says to do (lower the start utilisation or spread the cells) but
the script does not try to fix it. Run it again in `cts.tcl` after the tree and in `route.tcl` before `route_auto` as RESULT lines only (no check: the instructor gives the limit for placement).

### A4. Netlist growth report (where the area went)

At four points: synthesis (from the area report), after `place_opt`, after the clock tree (`cts` block), after the hold optimisation (`clkopt`), after `route_opt` (`routed`): record total standard-cell area,
instance count, and the counts and areas of three classes, found by the REFERENCE NAME (patterns in ONE parameter list in `params.tcl`; the clock buffers/inverters of the tree are the cells added by CTS, so count
cells that are not in the previous block's netlist where the tool allows it; otherwise count by name pattern and say so): buffers, inverters, and delay cells (the hold-fix cells; take the delay cell
names from the library listing in `~/server_pull`, never guess them; the don't-use list is in `syn/dc_setup.tcl` and `pnr/params.tcl`). Print a table at the end of `route.tcl` (and each stage prints its own row):
growth in percent of the synthesis area per stage, next to the instructor's typical budget (placement 3-8, CTS 2-5, hold fix 2-5, total 10-20). These are Warnings when exceeded, NOT checks (the instructor
calls them typical); the utilisation limits of A2 are the checks. The instructor's advice "watch the hold-buffer count after `final_opto` and `route_opt`" is the delay-cell count after the hold optimisation and
after `route_opt`; print both counts and the difference. Spare cells and tie cells: counted if the library cell names are in the listing, else printed as "not counted".

Implementation hint (your decision): one shared procedure `unpu_growth_row <tag>` in `common.tcl` that takes the numbers from `report_utilization`/`report_qor`/`get_cells` through procedures you already
have (`unpu_find_numbers`, the cell-count helper of `placement.tcl`), plus a pure-Tcl `unpu_growth_table` that renders the rows and computes the percentages, tested without the tool.

### A5. Stubs for the scripts task 053 did not stub-run, and the RUNBOOK

- Rebuild the stub runs for `floorplan.tcl`, `pin_place.tcl`, `power.tcl`, `fill.tcl`, `outputs.tcl` (task 053 changed `power`, `fill`, `outputs` without stub runs) in addition to the four scripts that
  change here; show the logged command sequence for each and the failure paths below.
- `pnr/RUNBOOK.md`: the new variable flow (the die is derived; `UNPU_DIE_SIZE` is an experiment), the new checks and the growth table, what to do on a utilisation or congestion FAIL (new start utilisation is a decision for
  the user, never a silent change; the knob is `FP_START_UTIL` as a parameter documented as "needs a written reason"). `pnr/README.md` and `pnr/VERIFY_STATUS.md` (K43 onward: the report layouts, the delay cell names,
  `report_congestion` options and layout, the utilisation definition).
- `syn/RUNBOOK.md` section 8 still says the `pnr/` defaults are stale: update that sentence (and only that) to say they now follow `UNPU_SYN_PROFILE` and that the die is derived from `syn/out/<profile>/unpu_top.area`.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (new tests for every new pure-Tcl helper and parameter, the changed ones listed); `tclsh constraints/test_stages.tcl`; `bash scripts/test_syn_compare.sh`; all `pnr/*.tcl` complete Tcl.
2. The derived-die examples, printed: for the OLD area 429,161 um2 at 0.60 (862.4 um expected), and for 400,000 and 500,000 um2 and for each of the areas a profile might produce (+-10 percent around the old one), with rows and sites.
3. Stub runs (floorplan, pin_place, placement, cts all three modes, route, power, fill, outputs) with: the die derived; `UNPU_SYN_PROFILE` unset at floorplan (STOP) and set to `syn17` (STOP); the area file missing,
   ambiguous (two "Total cell area" lines) and non-numeric (STOP each); a profile mismatch between floorplan and placement (FAIL); utilisation 0.76 at placement (FAIL) and 0.75 (pass); 0.81 at CTS (FAIL) and 0.80
   (pass); 0.81 at route (FAIL); congestion 1.5 percent (FAIL) and 0.8 (pass); unreadable utilisation (FAIL); unreadable congestion (FAIL); the growth table with the total above 20 percent (Warning, not FAIL).
4. `grep`: no `PLAN_DIE_SIZE`, no `868`, no `817.6` in code outside comments; no `~/server_pull` path in code; no password text.
5. `git status`: `pnr/` and `syn/RUNBOOK.md` only. Do not commit.

## Constraints that apply

Standing rules of tasks 038 to 053. No limit is changed to make a check pass; the limits above are the instructor's table at its pessimistic end. Every tool command or attribute not in a usage text is VERIFY.
The die is never typed; the area is never typed.

## Out of scope

`constraints/`, `scripts/`, `rtl/`, `docs/planning/`; running anything on the server; Calibre/PrimeTime scripts; committing.

## Report back

Files changed, per-item account of A1 to A5, Part B output (including the die table), every new `VERIFY`, anything in this prompt that is wrong or ambiguous. Stop after reporting.
