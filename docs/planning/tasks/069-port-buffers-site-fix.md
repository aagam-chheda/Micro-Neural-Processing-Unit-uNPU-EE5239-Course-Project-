# Task 069 — `antenna_port_buffers.tcl`: put each buffer on a free filler site next to its pin; fix the timing-line bug

Read first: `docs/planning/tasks/068-antenna-port-buffers.md`, `pnr_v2/antenna_port_buffers.tcl`, and the first real server run of it: `/home/aagam_chheda/server_pull/calibre/run1/ant/` is NOT that run; the log lines are quoted below (the full log is
`/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/antenna_port_buffers_console.log` on the server, not on this machine; the user can scp it to `~/server_pull/calibre/run1/` if you ask in your report).

## What the first server run showed (facts)

- Mapping worked: 46 of 46 polygons resolved, 16 port nets found, equal to the expected 16; 15 nets to buffer (the 14 `pwdata` bits and `dma_rdata[9]`), `clk` left alone. `clk`: pin (885.24, 878.27), root load `ZCTSINV_121581_2576/I` at (408.55, 862.55), 492.4 um.
- The buffer cell chosen by the LEF rule was `buffd1`.
- 13 buffers passed their checks. Two failed and the script correctly saved nothing:
  - `dma_rdata[9]`: pin (375.60, 885.24), requested position (374.48, 860.00), `1 filler cells removed in its window`, final buffer position (861.68, 291.60), 1079.7 um from the pin.
  - `pwdata[7]`: pin (885.24, 630.61), requested position (863.36, 630.40), `0 filler cells removed in its window`, final position (864.48, 291.60), 359.8 um from the pin.
  Both ended in the same row (y = 291.60): the legaliser found no free site near the target (nothing, or too little, was cleared there) and took a free gap far away, probably a hole left by fillers removed for other nets. `legalize_placement -cells` moves a cell as far as needed; it does not fail.
- Every `>>> 068 TIMING <net>` line printed `setup error: -> error:, hold error: -> error:` because `get_timing_paths` rejects the `-quiet` option in this ICC2 (`Error: unknown option '-quiet' (CMD-010)`).

## Changes (only in `pnr_v2/antenna_port_buffers.tcl`, markers `# 069:`, plus the README line below)

1. Pick the buffer site from the fillers instead of asking the legaliser to find one. For each net: from the filler cells (`feedth*`, as route.tcl creates them) present in the design, find the position closest to the pin where a contiguous run of filler sites in ONE row is at least as wide as the chosen buffer cell (width from the LEF `SIZE`, in sites of 0.56 um; the rows are 5.6 um high). Remove exactly the filler cells covering that run (and nothing else), insert the buffer, place it with its origin at the run's first site and the row's orientation, and legalise only that cell. Do not clear a large window and let the tool choose. If a filler is wider than needed, remove it and re-create fillers in the leftover gap afterwards, as the script already does for the whole design.
2. Verify per buffer, immediately after placing it: the final position equals the requested site (to 1e-3 um) and the Manhattan distance from the pin centre to the buffer input is within the limit (40 um, the existing parameter). If not, undo for that net (remove the buffer, restore the net) and retry with the next candidate run (closest first), up to 5 candidates. If none works, the net is listed as FAILED and the script ends with an error before the re-routing step (nothing saved).
3. Print one line per buffer with: net, pin, filler run chosen (row y, x range, fillers removed), final buffer position, distance. Print this line for ALL nets, not only for failures.
4. Fix the timing lines: remove the unsupported `-quiet` (check the real option list of `get_timing_paths` in the help texts; use `catch` around a call and print the caught message once, not per net, if the command fails). The TIMING line must show numbers or one clear message "per-net timing unavailable: <reason>", never `error:` fields printed as results. Keep the before/after global timing tables.
5. README: change the stale line D3 ("SUPERSEDED by task 067") to say that task 067 was tried and PARKED (task 068), so the decided pin positions are the floorplan's (`pins_floorplan.txt`). Do not touch other README lines.

## Constraints that apply

Same as task 068: no timing option, goal or limit changes, no diode, no waiver. Do not run anything on the server, do not commit. Do not change the buffer-cell choice, the polygon-to-net mapping, the ECO re-route order or the final checks of task 068 beyond what is listed above.

## Acceptance test (local)

1. `info complete` = 1 for the script; `tclsh pnr_v2/test_antenna_port_buffers.tcl` still passes, with new tests for the pure-Tcl part of the site search: a table of filler runs per row, the nearest run that fits, a run too narrow, runs across two rows, and the retry order. Report the new test count.
2. `grep -n "069" pnr_v2/antenna_port_buffers.tcl | wc -l` and the `diff` of the script against `git show 2460320:pnr_v2/antenna_port_buffers.tcl` (paste it).
3. List every new `VERIFY` item with what to look for in the log (for example how to read the fillers' positions and sizes, cell orientation, and the removal of a filler).
4. `git status`: only the script, its test and `pnr_v2/README.md` changed.

## Report back

Files changed, the diff, test output, the `VERIFY` list, anything ambiguous. Stop after reporting.
