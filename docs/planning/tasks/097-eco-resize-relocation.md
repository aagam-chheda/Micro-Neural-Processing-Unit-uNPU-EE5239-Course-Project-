# Task 097 — `pt_eco_apply.tcl`: place a RESIZED cell that does not fit in place (bounded relocation to a free filler run)

Read first: `pnr_v2/pt_eco_apply.tcl` (the size_cell branch and the filler-table placement of the insertions), `pnr_v2/antenna_port_buffers.tcl` (the filler-table procs and the tier logic), task 079/095 text, `~/server_pull/run3` is not needed: the server log is quoted below.

## What the server showed (run 3, 2026-11-10 22:36, `UNPU_ECO_KIND=drc`, commit 73f169d)

The PrimeTime probe proposed 9 `size_cell` changes (all drivers of the 9 nets with a data-limit max_transition violation; area change +94.13 um2; in PrimeTime's memory the 86 entries go to 0, setup and in2out slack unchanged). The ICC2 apply: `fillers removed: 8; changes applied: 4 of 9, skipped: 0` and then `ERROR 079: 5 change(s) FAILED, nothing saved and nothing routed`:
- change 1: `u_dma/U157 an02d4 -> an02d7` needs 2.24 um more width: the free run at the right edge is 0.56 um wide
- change 4: `u_actbuf/HFSBUF_21543_531 buffd1 -> buffd3` needs 0.56 um more width: no free filler run starts at the right edge of the cell
- change 6: `u_seq/HFSBUF_1163_489 buffd1 -> buffd3` needs 0.56 um more width: no free filler run at the right edge
- change 7: `u_dma/U101 an02d4 -> an02d7` needs 2.24 um more width: no free filler run at the right edge
- change 8: `u_dma/U150 an02d4 -> an02d7` needs 2.24 um more width: the free run is 1.12 um wide, 2.24 needed
So the resize currently grows the cell only into the filler run touching its RIGHT edge. Nothing is wrong with the design (the library is unchanged: nothing was saved).

## Goal

A resized cell that does not fit in place is RELOCATED to the nearest free site run that is wide enough for the NEW cell, within a named distance limit; everything else stays as strict as now.

## Changes

1. In the size_cell branch: first try in place (today's method). If it does not fit, collect the candidate runs from the filler table (the same table and procs as the insertions; the old cell's own sites count as free: its footprint plus the free run next to it, left or right, is a candidate too, so a cell may also grow to the LEFT or be shifted by a few sites), choose the candidate with the smallest Manhattan distance from the old cell's location whose run fits the new width on the site grid with the correct row orientation, up to `MAX_SITE_TRIES` (reuse the parameter), distance limit named parameter `MAX_RESIZE_MOVE_UM` (default 40, the same value and reason as `MAX_PIN_BUF_DIST` unless you have a better reason; print the reason). Procedure per change: remove exactly the fillers of the chosen run, `size_cell` (or `replace_cell`/the form already working for the 4 successful changes), `set_cell_location` with coordinates AND orientation, verify the final location equals the requested one (no `legalize_placement` that moves cells away; a check like the insertions have), update the occupancy table (the old footprint becomes free: add it back as a free run so later changes can use it), retry the next candidate on failure with the undo that the insertions use.
2. Port-connected drivers (`dma_wdata[*]` drivers `an02d4`): moving the driver must not push the output net far from the port pin: print the Manhattan distance driver-to-port before/after for every relocated cell and flag (WARNING, not an error) when it grows by more than 20 um; the timing gates decide afterwards. For the 40-load nets (`u_seq/HFSNET_137`, `u_actbuf/HFSNET_29`) print the centroid-to-driver distance before/after.
3. Re-route: all nets of every changed or relocated cell (inputs and outputs) with `route_eco -nets` and the incremental detail route, as the insertions do; DRC clean-up loop (081) unchanged; `create_stdcell_fillers` to refill every site freed by a relocation.
4. Hard checks unchanged: applied == total, every change printed with its old and new location and distance, DRC 0, open nets 0, legality 0, the protected cells (`earlybuf_*`, `antbuf_*`, the 9 `PTECO_HOLD` cells) identical, in2out and whole-design setup WNS not worse than 0.005 before saving, hold WNS reported before and after (WARNING). Print per change: `>>> 097 SIZE change N: cell A -> B, in place | relocated by X um to (x, y), run [x0,x1], distance Y`.
5. If NO candidate exists within the limit for a change, the failure text lists the 3 nearest runs with their widths (as the insertion code does) and states that `MAX_RESIZE_MOVE_UM` can be raised or the probe asked for `-methods {insert_buffer}` only for that net: the user decides.
6. Tests for the pure parts: run selection (fits, too narrow, too far, left growth, own-footprint candidate, orientation), occupancy update after a relocation, the distance flag, using the 5 real failures above (new width minus old width = 2.24 and 0.56, free-run widths 0.56, none, none, 1.12); all existing suites keep their counts (test_drc_eco 103, test_eco_scope 114, test_sdc_limits 65, test_clock_latency 120, test_opt_uncertainty 151, test_diag_io_whatif 68, test_run_root 81, test_diag_io_latency 70, test_port_buffers_early 130, test_pt_common 278, test_pt_eco_apply 136 (+new), test_antenna_port_buffers 149, test_antenna_clk_root 63, test_timing_closure 69, test_pv_lef_check 48, test_pv_sdf_check 18, sim verdict 122). README: the rule in words, the parameter, the log lines, the VERIFY.

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no waiver without approval." No constraint, limit or uncertainty change. A relocation is bounded and printed; nothing is moved by an unbounded legalizer. Local only: no server work, no commit.

## Report back

Files, tests, the VERIFY list, what you expect for the 5 failing changes (where each cell would go, from the numbers you have; say if the data is not enough), and the csh command to rerun the apply on the server (the library is unchanged: the backup `bak_pre_maxtrans` is already there; the apply can be repeated directly). Stop after reporting.
