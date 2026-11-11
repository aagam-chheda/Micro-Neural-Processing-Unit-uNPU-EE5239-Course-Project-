# Task 070 — `antenna_port_buffers.tcl`: find out why every net got "0 usable candidate sites", make the reasons visible

Read first: `docs/planning/tasks/069-port-buffers-site-fix.md`, `pnr_v2/antenna_port_buffers.tcl` (procs `ant_filler_runs`, `ant_site_candidates`, `ant069_filler_rows`, and the per-net loop around line 770 to 860).

## What the second server run (commit 3a6b2b3) showed

- All 15 nets failed with "0 usable candidate sites" in tier 1 and tier 2, for example `dma_rdata[9] tier 1: limit 40.0 um, 33 fillers in the search window, 15 runs, 0 usable candidate sites`, `pwdata[7] tier 1: ... 15 fillers, 7 runs, 0 usable`. The message "nearest free filler run at N um" gave 298.7 to 328.4 um for EVERY net, wherever the pin is (pins at y = 161 to 631 um and (375.6, 885.2)); that is the edge of the +-300 um window, which is suspicious.
- Ground truth from the design (user's read-only query on block `unpu_top_route`, `get_cells -quiet -intersect {{850 158} {886 166}}` and `{{850 214} {886 222}}`): the fillers are plentiful and contiguous, for example in the row y = 154.4 to 160.0: `xofiller!feedth9!x8471200y1544000 | feedth9 | {847.1200 154.4000} {852.1600 160.0000} | MX`, then feedth9 852.16 to 857.20, feedth9 857.20 to 862.24, feedth3 862.24 to 863.92, feedth3 863.92 to 865.60; row y = 165.6 to 171.2: x 846.0 to 865.6 (feedth9, feedth9, feedth9, feedth3, feedth3, feedth, feedth); row y = 210.4 to 216.0: 852.72 to 865.6; row y = 221.6 to 227.2: 848.8 to 865.6. Real cells in the same window: `ad01d0` at {845.44 160.0}-{856.08 165.6} (orientation MY), `aor22d1` at {848.24 210.4}-{852.72 216.0} (R180). `bbox` prints as `{x0 y0} {x1 y1}`; `orientation` is `MX` for fillers.
- Offline check done by Planning (do not repeat it): sourcing the pure-Tcl block of the script and feeding `ant_filler_runs` / `ant_site_candidates` with exactly those fillers (buffer 2.24 um, site 0.56 um, pin (885.24, 160.91), limit 40) gives 2 runs and ONE candidate (site x = 863.36, y = 154.4, distance 24.47 um). So the pure procs are right on this data; the cause is in what is passed to them inside ICC2, or in the code around the call.

## Task

1. Find the cause by reading the code path with the real data in mind (types, units, list nesting of `ab_pin_xy`, the window `win`, the `-intersect` window corners and their order or sign, the values of `lim`, `ab_bw`, `ab_bh`, `ab_site_w`, `tried`, anything that could make `dist` or the width test fail). If you find it, fix it and say how you know.
2. Whether or not you find it, make the script explain itself (nothing fails silently): in the per-net lines, when there are zero usable candidates, print for the nearest 3 runs (by distance of the run's nearest point to the pin) the row y, x range, width, the width needed, the distance, and the reason it was rejected (`too narrow` / `too far: dist D > limit L`). Print the first 3 filler rows (name, bbox, orientation) the query returned for the FIRST net only, and the pin coordinates and window used.
3. Write a read-only diagnostic `pnr_v2/diag_filler_runs.tcl` that the user can run in `icc2_shell` (no saving, no ECO): open the block `unpu_top_route`, for ONE net given by a variable at the top (default `pwdata[30]`), repeat exactly the pin-xy lookup, the window, the filler query, `ant_filler_runs` and `ant_site_candidates` with the same proc code (source the pure-Tcl block from `antenna_port_buffers.tcl` or copy it; do not duplicate logic differently) and print every intermediate value. It must end without saving anything and say so.
4. README: one line under the step 6c block pointing to the diagnostic.

## Constraints

No change to the ECO, the buffer cell choice, the mapping, the limits or the final checks. No commit, nothing run on the server.

## Acceptance (local)

1. `info complete` for both Tcl files; `tclsh pnr_v2/test_antenna_port_buffers.tcl` passes with new tests for the rejection-reason lines (too narrow, too far, none in window) using the real filler rows quoted above as test data (the offline result: 2 runs, 1 candidate at (863.36, 154.4), distance 24.47 um).
2. A short written statement of the cause if found, or the list of the hypotheses you checked and ruled out by reading the code.
3. `git status`: only the script, the test, the diagnostic and the README line changed or new.

## Report back

The cause (or the list of ruled-out hypotheses), the diff, the test output, how the user should run the diagnostic (csh, one command per line). Stop after reporting.
