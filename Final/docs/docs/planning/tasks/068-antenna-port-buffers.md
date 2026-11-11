# Task 068 — Targeted antenna fix for the long input-port nets: a buffer at the pin (step 6c), plus parking step 4b

Read first: `docs/session-handoff.md` 18.15 (the don't-use list), 18.25 to 18.27 (the earlier antenna work and the `paddr[4]` case), 18.32 (the clean-slate run), `docs/planning/tasks/067-pin-replace-after-placement.md`,
`pnr_v2/fix_antenna.tcl` (how it reads the Calibre database and finds nets), `pnr_v2/route.tcl`, `pnr_v2/README.md`, `pnr_v2/calibre/README.md`, and the real Calibre/ICC2 data now on this machine in `/home/aagam_chheda/server_pull/calibre/run1/` (`ant/unpu_top.ant.db`, `ant/unpu_top.ant.rpt`,
`ant/fix_antenna_console.log`, `ant/fix_antenna2_console.log`, `drc/unpu_top.drc.db`, `drc/unpu_top.drc.rpt`). The ICC2 help texts you used for task 067 are in `/home/aagam_chheda/server_pull/rpt/help`.

## Why (the evidence; do not re-derive it)

- Calibre antenna on the routed, filled layout: 55 results at the baseline, 50 after one `fix_antenna.tcl` pass, 46 after a second (M2 9, M3 13, MT 24; the MT count rose from 18 to 24). The DRC deck: 0 results at baseline, now ONE: `M3.S.1` at about (127.8, 287.0) um (marker 0.13 x 0.38 um), created by the second pass (ICC2 `check_routes` also reports 1 DRC).
- The 46 markers are only about 16 NETS (a long wire is reported as several polygons). From the `>>> Fixing` lines of `fix_antenna2_console.log`: `pwdata[0] [2] [6] [7] [8] [10] [12] [14] [16] [20] [22] [26] [28] [30]`, `clk`, `dma_rdata[9]`. They are INPUT PORT nets: no driver and no diffusion inside the macro. A port net is checked as `perimeter x layer weight / gate area > 400` with a gate area of about 0.19 um^2:
  about 72 um of M2 or M3 (weight 0.54) or 46 um of TOP_M (weight 0.84) per layer island. With a diode on the net the limit becomes very lenient (`AN.MTL.2.*`, the deck only counts diffusion of at least 0.202 um^2, `M3_good_dio` / `MT_good_dio` in the Calibre log).
- Pin to load distances are 130 to 250 um for these nets: for example `pwdata[30]` has one M2 run from y=161 to y=413 um, `pwdata[20]` about 234 um, `clk` an M3 run of about 470 um (pin at x=885, y about 880; root inverter near x=410). The loads (`u_csr` registers) sit around y=420 to 435 um; the pins are spread along the whole right edge at 8 um pitch. Task 067 (pins re-placed after placement) did not shorten them enough and was refused by its own checks (pin pitch 0.56 um, legality count unreadable); the pins stay as the floorplan placed them.
- `adiode` cannot be used (not available). Layer hopping (`fix_antenna.tcl`) cannot reach beyond about 190 um in total. A buffer next to the pin makes the pin-to-buffer wire short and gives the rest of the net a driver with diffusion.

## Part A — park step 4b (small, mechanical)

1. `pnr_v2/cts.tcl`: restore the `open_block` line to exactly the committed line before task 067 (`git show 519ebfb:pnr_v2/cts.tcl` is the reference; `${DESIGN_NAME}_placement`). Keep a `;# 068: back to _placement, step 4b is parked` marker.
2. `pnr_v2/README.md`: mark row 4b and the block chain as PARKED (do not delete the text), with the result in three sentences: the second `place_pins` moved 196 of 204 pins but ignored the 8 um spacing (0.56 and 0.61 um pitch), its legality check could not read its result, and the measured pin-to-load distances stayed 100 to 250 um for most nets, so it cannot fix the antenna problem. Block chain back to `_placement` -> `_cts`. Move nothing else.
3. Keep `pnr_v2/pin_replace.tcl` in the repo unchanged, with a one-line comment at its top: `# PARKED (task 068): see README`.

## Part B — `pnr_v2/antenna_port_buffers.tcl` (flow step 6c)

Runs on the block `unpu_top_route` AFTER the second `fix_antenna.tcl` pass and BEFORE `metal_fill.tcl`, reads the Calibre antenna database exactly where `fix_antenna.tcl` does (`/storage/EE5239G1/aagams_workspace2/unpu/pv/drc/unpu_top_antenna_bkp.db`), and overwrites `_route` in place (as `fix_antenna.tcl` does; the README line tells the user to back up the library first with `cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_<name>`).

Behaviour (decide the ICC2 commands from the real help texts; mark each unverified command or option `VERIFY`):

1. Parse the database (copy the parser logic of `fix_antenna.tcl`; the format is on this machine: header `unpu_top 1000`, rule names `AN.MTL.1.M2|M3|MT`, polygons `p <id> <nverts>`, coordinates in 1/1000 um).
2. For every polygon find the nets it covers. The `fix_antenna.tcl` method returns SEVERAL nets for one polygon in some cases (`get_shapes -within/-intersect` plus `get_nets -of_objects` is unreliable, handoff 18.26). Make the identification robust: restrict to nets that are connected to a port (the 204 signal ports), prefer the net whose shape bbox equals or contains the polygon, and print, for every polygon, the rule, polygon bbox, the nets found and the net chosen. A polygon whose net cannot be decided is listed and counted, never silently skipped, and the script ends with an error if any remains unresolved.
3. Print the resulting SET of port nets (expect about 16, including `clk`). Compare it with the 16 listed above and print the difference (nothing hardcoded: the list above is only the expectation to compare, not an input).
4. `clk` is NOT buffered by this script. It is a clock net (a buffer before the CTS root changes the clock latency and the I/O timing), so print the `clk` polygons and the root distance and leave it for a decision by Planning. Everything else in the set is buffered.
5. Choose the buffer cell by data, not by name: the library pins carry the antenna data from the kit LEF (`ANTENNAGATEAREA` on input pins, `ANTENNADIFFAREA` on output pins; handoff 18.26 quotes `ad01d0` as an example of these LEF attributes). Requirements: (a) the output pin diffusion area is at least 0.202 um^2 (the deck's threshold for "has a diode"); (b) the input gate area is large enough that a pin-to-buffer wire of up to about 20 um on M3 passes `perimeter x 0.54 / gate area <= 400`; (c) the cell is NOT on the don't-use list of handoff 18.15 (15 pattern cells plus the library's own `adiode`, `bh01d1`, `cload1`; note that ICC2 in this flow has no don't-use list set, so check the name against the list explicitly); (d) it is a plain non-inverting buffer. Print the candidates with their areas and the one chosen and why. If no cell meets (a) and (b), stop with an error and list what was found.
6. For each net, insert one buffer next to the port pin and legalise it. Place it within a few um of the pin, not at the middle of the route. After insertion the pin-to-buffer wire must be short. Print, per net, the buffer instance name and its distance to the pin.
7. Re-route only the nets touched, keeping the rest unchanged (`route_eco` with the nets, as `fix_antenna.tcl` does, then `route_detail -incremental true`), then clean up: the single leftover DRC `M3.S.1` at about (127.8, 287.0) um must be found (print the DRC error list with locations, `VERIFY` the command) and cleared by the same incremental routing, or reported with its net if it cannot be.
8. Final checks, each a number and a hard `error` if wrong, nothing is saved on error: `check_routes` DRC = 0 and open nets = 0; `check_legality` 0 violations; buffer count equals the number of nets buffered; connectivity of the buffered nets unchanged (print the loads count before and after per net).
9. Timing is reported, not tuned: `report_global_timing` before and after the ECO (setup and hold WNS/TNS/NUM), and the slack of the paths through the buffered nets. These nets are input-to-register paths (large setup slack, input min delay 0 for hold); report if any of them gets worse than before.
10. `save_block` over `${DESIGN_NAME}_route` and `save_lib` (as `fix_antenna.tcl`), print `>>> STAGE 6c COMPLETE: ...`.

## README (pnr_v2/README.md)

Add step 6c to the run order after `fix_antenna.tcl`, and a short section "Loop after the Calibre antenna run": the sequence as ONE csh command per line (backup `cp -r`, copy the antenna `.db` to `pv/drc/unpu_top_antenna_bkp.db`, `icc2_shell -f ../pnr_v2/antenna_port_buffers.tcl |& tee antenna_port_buffers_console.log`, then `metal_fill.tcl`, `pv.tcl`, the two Calibre commands of `pnr_v2/calibre/README.md`), and what to read after each (`>>> STAGE 6c`, buffer list, DRC 0, Calibre results). State: iterate the buffer ECO only with a database from a NEW Calibre run, never repeat on a stale one.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No timing option, uncertainty, goal or limit is changed. No diode, no waiver, no change to a Calibre rule or control file. The buffers are an ECO on the netlist: say so in the header of the script (the PM must be told). Use only the files and commands named; do not run anything on the server, do not commit.

## Acceptance test (local, no server)

1. `info complete` = 1 for `pnr_v2/antenna_port_buffers.tcl`, and for `pnr_v2/cts.tcl` and `pnr_v2/pin_replace.tcl`.
2. `diff` of `pnr_v2/cts.tcl` against `git show 519ebfb:pnr_v2/cts.tcl`: only the `068` marker comment differs. Paste it.
3. The pure-Tcl parts (database parser, polygon bbox, the choice among candidate cells given a table of areas) are tested with `tclsh` on `/home/aagam_chheda/server_pull/calibre/run1/ant/unpu_top.ant.db`: 46 polygons, rules M2 9 / M3 13 / MT 24, and bbox values that agree with the polygon list in `fix_antenna2_console.log` for at least five markers. Put the test in `pnr_v2/test_antenna_port_buffers.tcl`; it passes with `tclsh`.
4. `grep -n "068" pnr_v2/antenna_port_buffers.tcl | wc -l` and the list of every `VERIFY` item, each with what the user should look at in the log.
5. `git status`: only `pnr_v2/antenna_port_buffers.tcl`, `pnr_v2/test_antenna_port_buffers.tcl`, `pnr_v2/cts.tcl`, `pnr_v2/pin_replace.tcl`, `pnr_v2/README.md` changed or new, plus this task file.

## Report back

Files changed, the `cts.tcl` diff, the test output, the `VERIFY` list, how you identify the net of a polygon and what happens to an ambiguous one, how the buffer cell is chosen (and the candidate table you expect), what you propose for `clk`, anything in this prompt that is wrong or ambiguous. Stop after reporting.
