# pnr_v2 -- the user's example ICC2 scripts, minimally edited for `unpu_top` (task 063)

Pristine originals: `docs/planning/reference-scripts-2026-11-02/` (do not edit; `sha256sum -c SHA256SUMS`).
Every edited line carries a `063` marker (`;# 063 En: ...` or a `# 063 En:` comment line), so `diff` shows exactly what changed.
Nothing here has been run: the user runs it on the server.

## Run order

**RUN_DIR** is the folder of the clone you run in (for example `/storage/EE5239G1/aagams_workspace2/unpu_run2`; the name does not matter, run 1 is the clone `unpu`). Set it once per terminal (csh): `setenv RUN_DIR <full path of the clone>`. In the `scp` lines (typed on your own machine) write the path itself where `<RUN_DIR>` stands. The Tcl scripts do NOT read `RUN_DIR`: each derives its own root from where the script file lives (task 082, `pnr_v2/run_root.tcl`) and prints `>>> RUN ROOT: <path>` at its start and in its log; if that line shows another clone than the one you meant, stop. A WARNING line is printed if the shell's current directory is inside a different clone than the script's.
Outputs go to `<RUN_DIR>/pnr_icc2/` (`blocks logs reports outputs`; git-ignored), the synthesis output to `<RUN_DIR>/syn/out/`, the Calibre databases to `<RUN_DIR>/pv/drc/`: all inside the clone. `VERIFY V19` (task 082): `[info script]` returns the script path inside `icc2_shell -f <file>` and `source <file>` (`pt_shell` scripts already rely on it; ICC2 is untested). If it is empty the script stops at its first lines with `ERROR 082: cannot load run_root.tcl ...`: then start it with `source <file>` inside the shell. Since task 082 no `sed` on the scripts is needed for a new run: clone the repository to a new folder and start there. Each run folder is self-contained; the old one is never written.

| Step | Script | Tool |
|---|---|---|
| 0a | `build_ndm_std.tcl` | `icc2_lm_shell` |
| 0b | `build_ndm_filler.tcl` | `icc2_lm_shell` |
| 1 | `design_setup.tcl` | `icc2_shell` (needs `syn/out/legacy/unpu_top_cn.dc.v` and `.sdc` from the synthesis with the old constraints, next task) |
| 2 | `floorplanning.tcl` | `icc2_shell` |
| 3 | `powerplanning.tcl` | `icc2_shell` |
| 4 | `placement.tcl` | `icc2_shell` |
| 4b | `pin_replace.tcl` | PARKED (task 068, see "Why step 4b"): not part of the flow; it reads `_placement` and writes `_pinplace`, which `cts.tcl` no longer reads |
| 4c | `port_buffers_early.tcl` | `icc2_shell` (task 085: after `placement.tcl`, before `cts.tcl`; predicts the pin-to-load wire of every INPUT port net from the placement and puts one buffer next to the pin of each net the antenna formula says would fail; an ECO on the netlist; reads `_placement`, writes the NEW block `_portbuf`; `clk` is never buffered; the buffers are protected from `clock_opt` / `route_opt`) |
| 5 | `cts.tcl` | `icc2_shell` (reads `_portbuf` through the parameter `CTS_INPUT_BLOCK` at the top; set it to `unpu_top_placement` to run without step 4c) |
| 6 | `route.tcl` | `icc2_shell` |
| 6b | `fix_antenna.tcl` | `icc2_shell` (after the first Calibre antenna run; needs `<BASE>/pv/drc/unpu_top_antenna_bkp.db`) |
| 6c | `antenna_port_buffers.tcl` | `icc2_shell` (task 068: after `fix_antenna.tcl`, before `metal_fill.tcl`; a buffer next to the pin of each long INPUT PORT net, an ECO on the netlist; reads the same `unpu_top_antenna_bkp.db`, overwrites `_route` in place; `clk` is never buffered) |
| 6d | `antenna_clk_root.tcl` | `icc2_shell` (task 071: after `antenna_port_buffers.tcl`, before `metal_fill.tcl`; replaces the CTS root inverter on the `clk` port net by a larger inverter, a size-only ECO on one clock-tree cell; reads the same `unpu_top_antenna_bkp.db`, overwrites `_route` in place) |
| 6e | `timing_closure.tcl` | `icc2_shell` (task 072: after `antenna_clk_root.tcl`, before `metal_fill.tcl`; `route_opt` again with the same goals and options as `route.tcl`, the 15 `antbuf_*` buffers and the clock root protected, fillers removed during the pass and re-created; can resize cells and add hold buffers, so it changes the netlist; overwrites `_route` in place) |
| 6g | `pt_eco_apply.tcl` | `icc2_shell` (task 079: after `timing_closure.tcl`, before `metal_fill.tcl`; applies PrimeTime's own hold ECO (the `insert_buffer` commands of `pt_eco_hold_changes_icc2.tcl`: 109 in the first try, 112 in the current run with the in2out cone protected) and, if present, the setup ECO (`size_cell`), each new cell placed on a filler run next to its pin; the 15 `antbuf_*` buffers and the clock root protected; changes the netlist; overwrites `_route` in place) |
| 7 | `metal_fill.tcl` | `icc2_shell` |
| 8 | `pv.tcl` | `icc2_shell` (task 073: the LEF is the macro `unpu_top` only, from `create_frame` + `write_lef -include cell`, with hard checks; read the `>>> 073 LEF CHECK PASSED` line in the log, a `FAILED` line makes the run end with `ERROR 073`) |

Block chain: `_setup` -> `_floorplan` -> `_powerplan` -> `_placement` -> `_portbuf` (step 4c) -> `_cts` -> `_route` -> `_filled` -> `_pv`.
PARKED (task 068): the chain with `_pinplace` between `_placement` and `_cts` (step 4b) is not used.

## Step 4c: port_buffers_early.tcl (task 085): input-port antenna protection BEFORE routing

Why: an input port net has no driver and no diffusion inside the macro, so Calibre counts the whole pin-to-gate wire against a gate area of about 0.19 um^2 (limit about 72 um on M2/M3, about 46 um on TOP_M, `no diode allowed`). Run 1 found 16 failing nets only after the route (wires 130 to 478 um) and repaired them with five late ECO steps. Re-placing the pins does not help (see `PIN_SPACING_RESEARCH.md`). Step 4c does it once, up front.

How it decides (all numbers come from `antenna_port_buffers.tcl`, read from its text): for each input port except the clock it measures the Manhattan distance from the pin to every load pin in the placed block, takes the longest, and computes the predicted ratio `2 x (length + width) x weight / gate area` (smallest load gate area from the kit LEF) with the M2/M3 weight and the TOP_M weight. A net is BUFFERED when the predicted ratio is more than `PREDICT_MARGIN` (0.8) times the limit 400. The printed table lists every port with its loads, longest distance, both ratios and the decision; the same numbers go to `pnr_icc2/reports/port_buffers_early_table.csv`.

**Read this before applying.** The prediction is an upper bound: the router splits a long wire into layer islands, and in run 1 only 16 of roughly 80 input data nets failed although most pins are 100 to 250 um from their loads. A distance-based rule with margin 0.8 will therefore buffer MOST input nets (the table tells how many, before anything is inserted). Each buffer costs about 0.1 to 0.3 ns on its input path (good for the input hold paths, bad for setup) and the `paddr` -> `prdata` read path has no margin. So run it first with `PLAN_ONLY 1` (`setenv UNPU_PBE_PLAN_ONLY 1`, see below; no edit of the script), read the count and the cone list, and only then decide whether to keep `PREDICT_MARGIN 0.8` or to change it (a user decision with a written reason; the CSV and the Calibre antenna database of the first routed run give the data to calibrate it).

**Cone policy (task 087).** The user's real run of 085 stopped at its own gate: 59 BUFFER nets, 5 of them on the paddr -> prdata cone (`paddr[11]`, `[9]`, `[7]`, `[5]`, `[3]`), in2out WNS 0.0206 -> -0.1198 ns, nothing saved. `CONE_POLICY` (default `skip`, environment `UNPU_PBE_CONE_POLICY`) decides what happens to a net that the prediction wants to buffer but that lies on an input-to-output cone: with `skip` the decision is `CONE-SKIPPED` (counted in the totals, listed in one block at the end with its predicted ratio and distance, and left for the post-route repair `antenna_port_buffers.tcl` / the Calibre antenna run); the gate still runs on the rest. With `buffer` all BUFFER nets get a buffer, as in 085 (the gate then decides). Which cell would be the fastest suitable one is printed for the cone nets as information only and is NOT used.

Steps 4c (csh, from the server, one command per line; `RUN_DIR` = this clone):

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_portbuf
icc2_shell -f ../pnr_v2/port_buffers_early.tcl |& tee port_buffers_early_console.log
```

(first with `PLAN_ONLY 1`, then without), then `exit`. The three parameters can be given from the shell WITHOUT editing the script (the clone stays clean for `git pull`): `UNPU_PBE_PLAN_ONLY` (0 or 1), `UNPU_PBE_PREDICT_MARGIN` (a number above 0, at most 10), `UNPU_PBE_PREDICT_WEIGHT` (`m23` or `top`), `UNPU_PBE_CONE_POLICY` (`skip` or `buffer`, task 087); an unset variable keeps the default of the file, an invalid value is `ERROR 085`, and the `>>> 085 parameters` line shows for each value whether it came from the default or the environment. First run, one csh command per line:

```
setenv UNPU_PBE_PLAN_ONLY 1
icc2_shell -f ../pnr_v2/port_buffers_early.tcl |& tee port_buffers_early_console.log
unsetenv UNPU_PBE_PLAN_ONLY
```

Type `exit` after each run. `unsetenv` matters: a variable left set would make the second run a plan-only run again (the parameters line says so). The script opens `_placement`, never overwrites it, and saves `_portbuf`; `cts.tcl` reads `_portbuf`. What to read in the log (`>>> 085` lines): the CHOSEN buffer cell (smallest footprint that passes the gate-area, diffusion and don't-use rules); the PREDICTION TABLE and TOTALS (BUFFER + OK + NO-LOADS + CLOCK-SKIPPED + CONE-SKIPPED = all input ports); the CLOCK line (pin-to-first-load distance and the predicted ratio with the CTS root cell `inv0d4`: only printed, CTS decides the root); `CONE-SKIPPED NETS` (the block at the end: net, predicted ratio, longest pin-to-load distance, and the fastest suitable buffer as information only) and `BUFFER nets on an input-to-output cone that ARE buffered`; BEFORE/AFTER setup, hold and in2out WNS; per cone net the delay added by its buffer; `PROTECTION` (dont_touch and fixed placement read back); `GATE` lines; `STAGE 4c COMPLETE`. The script stops BEFORE saving (`ERROR 085`, the nets are named) when: the in2out WNS or the setup WNS drops by more than `GATE_TOL_IN2OUT` / `GATE_TOL_SETUP` (0.005 ns, as in `pt_eco_apply.tcl`), a buffer cannot get a free site within `MAX_PIN_BUF_DIST` (40 um), a buffer is not where it was put, `check_legality` is not 0 or not readable, the buffer count differs from the BUFFER count, or the protection reads back wrong.

Sites: there are no fillers before CTS, so the free sites are computed from the site-row boxes and the cell boxes (the same `ant_site_candidates` rules as `antenna_port_buffers.tcl`); the buffer is put with `set_cell_location` and NOT with `legalize_placement`. The new cells are named `earlybuf_*` (not `antbuf_*`: `antenna_port_buffers.tcl` counts `antbuf_*` cells against its own targets, and `pt_eco_apply.tcl` protects `antbuf_*`; the early buffers are protected by `dont_touch` instead, so a later PrimeTime ECO that names one of their pins is not protected by that script and must be read by hand). `antenna_port_buffers.tcl` stays the repair step after the route for anything the prediction missed. `pt_eco_apply.tcl` is left as is (Planning handles `earlybuf_*` there only if the ECO path is used again).

VERIFY list (task 085): V26 `get_cells -hierarchical -filter "is_hierarchical == false"` returns every leaf cell and the `bbox` / `orientation` attributes read as strings (the script stops if fewer than 1000 boxes are read or a cell is not on a row); V27 `get_site_rows` boxes and the row `y0` equal the `y0` of the cells in the row (otherwise `stray` cells stop the script); V28 `all_fanout -flat -endpoints_only -from <port>` lists endpoints including output ports (the timing-path cross-check covers it, a disagreement is printed and counted as ON the cone); V29 `set_dont_touch <cells> true` and `set_attribute -name physical_status -value fixed` exist and read back as `dont_touch=true`, `physical_status=fixed`; V30b `get_timing_paths -from <port collection> -to [all_outputs] -slack_lesser_than 0` forms; V31b `insert_buffer` on a port and `remove_buffers` (as `antenna_port_buffers.tcl`); V32 clock attribute `sources`. Test: `tclsh pnr_v2/test_port_buffers_early.tcl`.

## Why step 4b (task 067) -- PARKED (task 068)

Result of the run (task 068): the second `place_pins` moved 196 of 204 pins but ignored the 8 um spacing (pitch 0.56 and 0.61 um), its legality check could not read its result, and the measured pin-to-load distances stayed 100 to 250 um for most nets, so it cannot fix the antenna problem. `pin_replace.tcl` stays in the repo unchanged and `cts.tcl` reads `_placement` again. The text below is kept as it was.

In the clean-slate run `floorplanning.tcl` places the 204 pins once, before any cell exists (`place_pins -self`); the tool filled each edge from both ends in alternating pairs, so for example `clk` is at offset 7.33 um (bottom of the right edge) and `rst_n` at 869.87 um (top) while the logic they drive sits near the middle.
After route, Calibre antenna reported 55 results and one round of `fix_antenna.tcl` left 50 and made setup worse; the nets it names are mostly input port nets (`pwdata[*]`, `psel`, `clk`, `rst_n`, `dma_rdata[9]`, `dma_rdata[11]`), which have no diode inside the macro, so the whole pin-to-gate wire counts against a gate area of about 0.19 um^2 (about 144 um of M3 or about 92 um of TOP_M per net).
Routing cannot shorten a net whose pin is far from its load, but pin position can: placing the pins after the cells are placed is the standard way to put each pin near its load.

`pin_replace.tcl` keeps the pin constraints of the floorplan untouched (same ports, sides, layers, spacing) and only lets the tool choose new positions along the same edges. Then it runs `place_opt` again with the same options as `placement.tcl`, `legalize_placement` and the same checks, and saves `_pinplace`. Pin-release method (plan A `place_pins -self` again, plan B `remove_terminals -force` on the 204 signal terminals only) and every check are in the script header and log.

### Run sequence for step 4b (csh, from the server; one command per line)

```
cd $RUN_DIR/pnr_icc2
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

## Loop after the Calibre antenna run (task 068)

Why 6c: the antenna polygons that remain after `fix_antenna.tcl` are on INPUT PORT nets (no driver and no diffusion inside the macro), and no layer can carry a 130 to 250 um pin-to-load run. A buffer within a few um of the pin shortens the wire that counts against the tiny gate to about 20 to 30 um and gives the rest of the net a driver with diffusion. `adiode` is not usable, step 4b did not shorten the nets. The buffers are an ECO: the netlist written by `pv.tcl` has one extra buffer per fixed net (tell the PM).
The script reads the Calibre antenna database of a Calibre run, finds the port net of every polygon (it lists and counts any polygon it cannot decide and stops BEFORE changing anything), prints the set of nets, picks the buffer from the antenna areas in the kit LEF, and prints `clk` but does not buffer it.

One command per line (csh, from the server). Take the databases from a NEW Calibre run of the current `unpu_top_routed.gds`; never repeat the loop on a stale database:

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_portbuf
cp calibre/run1/ant/unpu_top.ant.db ../pv/drc/unpu_top_antenna_bkp.db
cp calibre/run1/drc/unpu_top.drc.db ../pv/drc/unpu_top_drc_bkp.db
icc2_shell -f ../pnr_v2/antenna_port_buffers.tcl |& tee antenna_port_buffers_console.log
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl |& tee pv_console.log
```

(`unpu_top_drc_bkp.db` is optional: it only gives the script the location of a leftover DRC marker such as `M3.S.1`.) Type `exit` at each `icc2_shell` prompt. If `antenna_port_buffers.tcl` stops with an error nothing was saved; restore with `rm -r blocks/unpu_top.dlib` and `mv blocks/unpu_top.dlib.bak_pre_portbuf blocks/unpu_top.dlib` only if the library was changed.
Then the two Calibre runs of `pnr_v2/calibre/README.md` (sections 4 and 5), in a NEW run folder so the earlier results stay:

```
cd $RUN_DIR
mkdir -p pnr_icc2/calibre/run2/drc pnr_icc2/calibre/run2/ant
cp pnr_v2/calibre/drc.ctrl pnr_icc2/calibre/run2/drc/
cp pnr_v2/calibre/ant.ctrl pnr_icc2/calibre/run2/ant/
cd pnr_icc2/calibre/run2/drc
calibre -drc -hier drc.ctrl |& tee drc.log
cd ../ant
calibre -drc -hier ant.ctrl |& tee ant.log
```

What to read after each step:

- `antenna_port_buffers_console.log` (also `logs/6c_antenna_port_buffers.log`), lines that start with `>>> 068`:
  - `POLY` lines: one per polygon with the rule, bbox, the ranked candidate nets (`net:tier:score`, tier 3 = shape with the polygon bbox, 2 = shape containing it, 1 = overlap), the chosen net and the status. `UNRESOLVED` lines stop the script before any change.
  - `port nets with antenna polygons` and the comparison with the 16 nets expected by task 068.
  - `CLOCK clk`: the polygons and the distance from the pin to the first loads of the CTS root. Not buffered, decision for Planning.
  - `candidate table` and `CHOSEN buffer`: the cell and why. `fillers removed` per net, then `inserted`.
  - `CHECK` lines: DRC 0, open nets 0, legality 0, buffer count equal to nets buffered, loads before and after per net, pin-to-buffer distance and predicted antenna ratio.
  - `TIMING` lines: setup and hold slack of the paths from each port before and after (reported, not tuned; `WORSE` is a flag for the user).
  - `STAGE 6c COMPLETE`. Any `ERROR 068` means nothing was saved.
- `metal_fill_console.log` and `pv_console.log` as before; the exported netlist and GDS now contain the buffers.
- Calibre: `drc.log` 0 results, `ant.log` the number of results per rule and which nets remain. A net that remains after its buffer is a new finding, not a reason to repeat the script on the old database.

If `antenna_port_buffers.tcl` reports `0 usable candidates` or a net FAILED: run the read-only diagnostic `pnr_v2/diag_filler_runs.tcl` (task 070; net = `DIAG_NET` at its top, nothing is saved): `cd <RUN_DIR>/pnr_icc2`, then `icc2_shell -f ../pnr_v2/diag_filler_runs.tcl |& tee diag_filler_runs_console.log`, then `exit`.

### Step 6d: the `clk` antenna result (task 071)

After step 6c the only Calibre antenna result left is the `clk` port net (rule `AN.MTL.1.M3`): about 490 um of M3 from the pin to the CTS root inverter, whose input gate is only about 0.19 um^2 (ratio about 2,670 against 400). `antenna_clk_root.tcl` replaces that root inverter by a larger inverter of the same function and pins (a size-only ECO on one clock-tree cell; tell the PM): the gate area needed is perimeter x 0.54 / 400 x 1.10 (about 1.43 um^2 for the polygon of the last run), and the cell is the inverter with the smallest gate area that reaches it, chosen from the kit LEF. A buffer at the pin was rejected for the first try (it delays the whole clock tree). The script maps the polygon of the database to its net with the same functions as 6c and stops if the database holds anything but the clock-source port net.

One command per line (csh, from the server). The database is the one of the last Calibre antenna run (here `run2`; take the folder of the run that reported the `clk` result):

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_clkroot
cp calibre/run2/ant/unpu_top.ant.db ../pv/drc/unpu_top_antenna_bkp.db
icc2_shell -f ../pnr_v2/antenna_clk_root.tcl |& tee antenna_clk_root_console.log
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl |& tee pv_console.log
```

Then the two Calibre runs in a NEW run folder (the same commands as above with `run3`: `mkdir -p pnr_icc2/calibre/run3/drc pnr_icc2/calibre/run3/ant`, the two `cp` of the control files, `cd` into each folder, `calibre -drc -hier drc.ctrl |& tee drc.log` and `calibre -drc -hier ant.ctrl |& tee ant.log`). Type `exit` at each `icc2_shell` prompt.

What to read in `antenna_clk_root_console.log` (also `logs/6d_antenna_clk_root.log`), lines that start with `>>> 071`:

- `POLY` line: the polygon, its perimeter (about 960.86 um) and the chosen net `clk`. `ROOT cell`: reference, box, orientation, distance to the pin. `NEED`: the gate area needed, also for the TOP_M weight.
- `candidate table` and `CHOSEN`: the inverter, why, its width against the old one. If no inverter reaches the need the script stops with the five largest gate areas: then the choice is between a buffer at the pin and a waiver (not made by the script).
- `PLAN`: how the extra width is taken (fillers on the right or the left). An error that a real cell is in the way stops the script before any change.
- `BEFORE METRICS` and `AFTER METRICS` lines (global skew, setup and hold WNS, transition and capacitance violations) and the raw `report_clock_qor` / `report_global_timing` texts between them.
- `CHECK` lines: DRC 0, open nets 0, legality 0, every pin of the root on the same net as before, reference as chosen, `clk` still has the root as its only load. Any failure ends with `ERROR 071` and nothing is saved.
- `VERDICT OK`, `WORSE` or `UNKNOWN`. `WORSE`: the global skew grew by more than 0.05 ns, the setup or hold WNS got worse by more than 0.02 ns, or a transition or capacitance violation appeared. The script still saves; to undo, restore the backup (`rm -r blocks/unpu_top.dlib` then `mv blocks/unpu_top.dlib.bak_pre_clkroot blocks/unpu_top.dlib`) and tell Planning. `UNKNOWN`: a number could not be read from a report; read the BEFORE and AFTER texts by hand.
- `STAGE 6d COMPLETE`, then after `metal_fill.tcl`, `pv.tcl` and the new Calibre run the antenna result count should be 0.

### Step 6e: timing closure after the antenna ECOs (task 072)

The exported layout is DRC 0 and antenna 0 in Calibre but setup WNS is -0.10 ns (2 in-to-out paths) and hold has 53 violations (worst -0.04 ns). `route.tcl` ended with setup 0.00 and 15 hold violations; the fillers, the `route_eco` steps and the antenna ECOs moved both. `timing_closure.tcl` gives `route_opt` the SAME settings as `route.tcl` once more (uncertainties 1.5 / 0.5, goals 0.0, the same app options and antenna rules, copied line by line; `pnr_v2/test_timing_closure.tcl` compares them with `route.tcl`). The antenna cells exist only for the antenna rule, so they are protected (`set_dont_touch` on the 15 `antbuf_*` buffers, the clock root and their nets, fixed placement), the fillers are removed during the pass (they occupy every free site) and re-created as `route.tcl` does, and a snapshot of every protected cell (reference, origin, orientation, pin connections) is compared afterwards. Up to 3 `route_opt` passes; the loop stops when both WNS are >= 0, when a pass improves neither WNS by more than 0.001 ns, or at the maximum.

One command per line (csh, from the server):

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_closure
icc2_shell -f ../pnr_v2/timing_closure.tcl |& tee timing_closure_console.log
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl |& tee pv_console.log
```

Then the two Calibre runs in a NEW run folder (the commands of the 6d block above with `run4`: `mkdir -p pnr_icc2/calibre/run4/drc pnr_icc2/calibre/run4/ant`, the two `cp` of the control files, `cd` into each folder, `calibre -drc -hier drc.ctrl |& tee drc.log` and `calibre -drc -hier ant.ctrl |& tee ant.log`). Type `exit` at each `icc2_shell` prompt.

What to read in `timing_closure_console.log` (also `logs/6e_timing_closure.log`), lines that start with `>>> 072`:

- `SETTINGS used`: 1.5 / 0.5 / 0.0 / 0.0, as `route.tcl`.
- `BEFORE` and `AFTER` blocks: `CELLS` (cells, area, buffers, inverters, fillers), `SETUP` / `HOLD` lines with WNS, TNS and the number of violating endpoints, the same per path group, the worst `in2out` setup path and the worst `reg2out` hold path in full (which cells are on them), `report_clock_qor`, `check_routes`.
- `PROTECTED` and `PROTECTION` lines: the cells that were protected, with `dont_touch=true` expected.
- `PASS DECISION` lines: why the loop went on or stopped. `PROTECTED CELL CHANGED` means a pass changed an antenna cell: the script then fails and saves nothing.
- `CHECK` lines: DRC 0, open nets 0, legality 0, protected cells identical to the snapshot, `antbuf_*` count unchanged, `clk` root unchanged, fillers (count within 1 percent, or explained by the site balance). Any failure ends with `ERROR 072` and nothing is saved.
- `ADDED by the pass`: cells, area, buffers, inverters added (hold buffers, resizing). The netlist changed by this much; tell the PM.
- `timing after route_opt and legalisation, before the fillers / route_eco steps` against `AFTER`: the difference is what the filler and `route_eco` steps of `route.tcl` cost.
- `VERDICT`: `CLOSED` (both WNS >= 0), `IMPROVED`, `UNCHANGED`, `WORSE` (a WNS dropped by more than 0.005 ns) or `UNKNOWN` (a number could not be read, never printed as CLOSED). The script saves in all four cases (only a failed check stops it). If `WORSE`: restore the backup (`rm -r blocks/unpu_top.dlib`, then `mv blocks/unpu_top.dlib.bak_pre_closure blocks/unpu_top.dlib`) and tell Planning.
- After `metal_fill.tcl`, `pv.tcl` and the new Calibre runs: DRC and antenna must both be 0 again. If antenna is not 0, compare the `PROTECTED` lines and the `CHECK protected cells` line to see which antenna cell changed.

### Step 6g: apply PrimeTime's ECO in ICC2 (task 079)

Why: PrimeTime is the sign-off and reads the I/O references at the clock pin with zero latency, so it found hold -0.3468 ns on 263 endpoints (255 flop D pins fed by `dma_rdata[*]` / `pwdata[*]`) and setup -0.2423 ns on `dma_addr[31]`. The user decided (2026-11-09) to fix the design to pass PrimeTime. PrimeTime's `fix_eco_timing -type hold` closed hold in its memory (263 -> 0, WNS +0.0002 ns) with 109 `insert_buffer` commands in the first try (`dl01d1` 64, `dl02d1` 31, `buffd1` 12, `dl01d2` 2; 2687.50 um^2; 112 commands in the current run with the in2out cone protected, see `pnr_v2/pt/README.md` section 10). `pt_eco_apply.tcl` applies the same change list to `unpu_top_route`:

- the change file is parsed in Tcl (`current_instance {x}` sets the hierarchy of the following pins; an empty one resets to the top; `insert_buffer [get_pins {P}] REF -new_net_names {N} -new_cell_names {C}`; `insert_buffer [get_ports {PORT}] REF ...` for a top-level input port (5 of the 109 hold changes, `dma_rdata[14]` ...; only with an empty `current_instance`); `size_cell {INSTANCE} {REFERENCE}` as PrimeTime wrote it for the setup file: `size_cell {HFSINV_13_284} {inv0d7}`, braces optional, `[get_cells {I}]` accepted); any other line stops the script and is listed; nothing is changed before all pins, references (in `scl180_std`, not don't-use) and names (PrimeTime's `U_PTECO_HOLD_BUF<n>` / `net_PTECO_HOLD_NET<n>` are kept, a clash stops) are checked;
- DRIVER pin versus LOAD pin: a buffer on a driver pin (`U46/Z`, `U81/ZN`) takes ALL loads of that net, on a load pin (`dest_c_reg_reg_2_/D`, `copt_h_inst_3971/I`) it isolates that one load. After every insertion the leaf pins of both nets are compared with exactly that rule; any difference stops the script (nothing saved);
- PORT insertions (`get_ports`): the port stays on the net with the new cell's input and ALL loads move behind the new cell (as the antenna buffers of 6c); the topology rule `port` checks exactly that. The pin location is the port terminal (as `antenna_port_buffers.tcl`). The new cell must be within the tier-1 limit of 6c (`MAX_PIN_BUF_DIST`, read from `antenna_port_buffers.tcl`, not retyped) AND within the distance at which the predicted antenna ratio of the port wire (Calibre limit, M2/M3 weight, wire width, all read from `antenna_port_buffers.tcl`; input gate area of the cell from the LEF) stays under the limit. TIER 2 for ports (when no filler run works within tier 1): the distance at which the predicted ratio, computed with the TOP_M weight (0.84, the worst case; the Calibre ratio limit for tier 2 is 360, 10 percent under 400; both read from `antenna_port_buffers.tcl`) and the delay cell's OWN input gate area from the LEF, stays under the limit; for `dl01d1` (0.371 um^2) that is about 79 um. The limits per reference are printed before any change; a change placed in tier 2 prints `TIER 2`, the distance and the predicted ratio on its `CHANGE` line and is listed in the ANTENNA WATCH block with the figures. If the port already has an `antbuf_*`, the new cell goes BETWEEN the port and the `antbuf_*`: the script prints `CASE change n: port ... already has an antenna buffer`, the `antbuf_*` is not touched (reference, origin, orientation unchanged), and its input pin legitimately ends on a PrimeTime net: that single, verified move is printed as `EXPECTED protected pin move`; any other change of a protected cell fails;
- every new cell is placed on a free filler run NEXT TO the pin (tier 1 within 30 um, tier 2 within 120 um; the cell width is read from the LEF, the delay cells are wider than `buffd1`), verified at that site and retried with the next candidate (up to 5); a change that cannot be placed is listed as FAILED and the script ends with an error BEFORE routing;
- only the touched nets are re-routed (`route_eco -nets`, `route_detail -incremental`), fillers and `connect_pg_net` as in 6c;
- a change that cannot be placed after all tiers is FAILED with the reason: per tier the limit and what was found (no run within the limit, or the candidates with their rejection reasons), the nearest free run wide enough in the whole design with its distance, and the limit it exceeds; every later change that uses a pin of the cell that change should have created (for example change 106 on `U_PTECO_HOLD_BUF4/Z`, whose cell change 4 creates) is named as a knock-on instead of "pin not found";
- `ALLOW_PARTIAL` (default 0 = strict: any FAILED change ends the script, nothing saved). With `set ALLOW_PARTIAL 1` such a change is SKIPPED together with its dependants (tracked by the PrimeTime cell name), the script continues, prints a `SKIPPED CHANGES` block (change number, line in the change file, pin, reason, dependants), the count checks use applied = total - skipped (both printed) and the last line is `STAGE 6g COMPLETE (PARTIAL: N of T changes skipped: <numbers>)`, T counting all commands of the files read (hold file and setup file). All other hard checks are unchanged. A partial result is NOT what PrimeTime assumed: PrimeTime must be re-run on it (`pt_hold_ff.tcl`, `pt_setup_ss.tcl`) and a second ECO round may be needed;
- the DRC clean-up (task 081): the first server run on the final change file ended with ONE DRC after the ECO and the checks stopped the save. After routing, if `check_routes` reports DRCs, up to `DRC_ROUNDS` (3) rounds run: the DRC errors are listed (`>>> 081 DRC: rule, layer, box, nets`; the error data `zroute.err` is opened first, ERRDM-043; every failing command is printed raw), `route_detail -incremental true -max_number_iterations 40` runs, and if DRCs remain the error boxes (plus `DRC_WINDOW_MARGIN` 5 um) are re-routed as windows and their nets with `route_eco -nets ... -reuse_existing_global_route false` (the protected antbuf_* / clock-root nets are not re-routed; the snapshot comparison at the end still guards the protected cells). The DRC count is printed after every step (`DRC counts per step`, also the count before the ECO). DRCs left after the last round: the remaining errors are printed as `REMAINING DRC` and the script stops, nothing saved. The same step is also where the unused input ports (TIM-010 'not a timing startpoint') are left out of the in2out query, with a printed count;
- the GATE on the read path (task 080): the first run of this script without it made the in2out group (path group `**in2out_default**`, the combinational `paddr -> prdata` read path) fail by -0.59 ns while the 109 inserted cells looked fine in every other check. After the AFTER metrics the script compares: the setup WNS of the in2out group and the whole-design setup WNS must not be worse than before by more than `GATE_TOL_SETUP` (0.005 ns: ICC2's numbers are repeatable to the picosecond, re-routing only the touched nets moves a path by a few ps, the in2out margin before is only +0.0143 ns); otherwise `ERROR 079: the ECO made the in2out group worse (before X, after Y, tolerance T): nothing saved` and nothing is saved. The group is found by `GATE_GROUP_PATTERN` ("in2out") among `get_path_groups`; when no such group is readable the worst setup path from an input port to an output port is used (the log says which, VERIFY V31). The violating endpoints before and after are printed (`GATE setup violating endpoints`). An unreadable number is an error too. Hold (whole design) only gives a `WARNING` when it is worse than before by more than `GATE_TOL_HOLD` (0.005 ns): PrimeTime is the sign-off for hold. The change file must come from the protected probe run (`pnr_v2/pt/README.md` section 10: the hold ECO is kept out of the in2out cone); to rerun, restore the library from `blocks/unpu_top.dlib.bak_pre_pteco` first;
- the hard checks (nothing is saved if one fails): `check_routes` DRC 0 and open nets 0, `check_legality` 0, the inserted cells equal the insertions of the change file (the expected number comes from `pt_eco_hold_expected_count.txt`, written by the probe: 112 in the current run, 109 was the first try; a change file with another number stops at the start with both numbers printed; without the count file the parameter `EXPECT_HOLD_CMDS` is used with a printed WARNING that it is an assumption), every inserted cell has the reference PrimeTime wrote, the protected cells (15 `antbuf_*` + the clock root) are identical to their snapshot, 15 `antbuf_*` cells;
- ANTENNA WATCH: every inserted cell whose net is driven by an input port or by the output of an `antbuf_*`, and every insertion on a port (`kind=port`, with the input gate area, the predicted ratio, the distance limit and, for the antbuf case, whether the new cell is closer to the port pin than the `antbuf_*`) is listed with the net and the distances. Calibre decides afterwards; none is skipped;
- timing is REPORTED before and after (`report_global_timing`, WNS/TNS/violations per scenario), not tuned. ICC2's view of the I/O paths is more lenient than PrimeTime's; PrimeTime is the sign-off.

Order on the server (the setup probe first, because its change file is the optional second input):

1. PrimeTime, `pnr_icc2/pt` (see `pnr_v2/pt/README.md` sections 8 and 9): `pt_shell -f ../../pnr_v2/pt/pt_eco_setup_probe.tcl |& tee pt_eco_setup_probe.log` produces `pt_eco_setup_changes_icc2.tcl`; `pt_eco_hold_changes_icc2.tcl` exists from the hold probe. Both files stay in `pnr_icc2/pt/`.
2. ICC2, one command per line (csh):

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_pteco
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl |& tee pt_eco_apply_console.log
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl |& tee pv_console.log
```

3. Then: the three Calibre runs in a NEW run folder (DRC, antenna, LVS: the commands of the 6e block above with `run5`; the LVS commands are in `pnr_v2/calibre/README.md`), the two PrimeTime runs (`pt_setup_ss.tcl`, `pt_hold_ff.tcl`, in `pnr_icc2/pt`) and the post-layout simulation (`pnr_v2/sim/README.md`).

What to read after each: `pt_eco_apply_console.log` (lines `>>> 079`): `reference table` (counts as above, all in library, none don't-use); every `CHANGE n ... OK`; `ANTENNA WATCH`; `CHECK` lines; `STAGE 6g COMPLETE`. After `pv.tcl`: the LEF and SDF checks pass. Calibre: DRC 0, antenna 0 (if not, look at the ANTENNA WATCH cells first), LVS CORRECT. PrimeTime: `SETUP: MET` and `HOLD: MET` with zero violating endpoints in the SUMMARY and the CSV files. The simulation: PASS (with the documented SDF limitation).

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

## diag_io_latency.tcl (task 084): read-only look at ICC2's I/O latency (run it before CTS of a new run)

Why: PrimeTime launches/captures the I/O at the clk pin with zero latency; ICC2 seems to count the clock-tree latency there (hypothesis H1, see `IO_LATENCY_RESEARCH.md`). The script prints ICC2's own path reports and ends with a verdict table (H1 CONFIRMED / REFUTED / INCONCLUSIVE). It SAVES NOTHING and refuses to start if the library is not inside this clone, so run 1 (the fallback) is never opened for writing.

Steps (csh, one command per line; `<RUN_DIR>` = this clone, `<RUN1_DIR>` = the run-1 clone):

```
ls -ld --time-style=full-iso <RUN1_DIR>/pnr_icc2/blocks/unpu_top.dlib
mkdir -p $RUN_DIR/pnr_icc2/blocks_diag
cp -r <RUN1_DIR>/pnr_icc2/blocks/unpu_top.dlib $RUN_DIR/pnr_icc2/blocks_diag/
cd $RUN_DIR/pnr_icc2
icc2_shell -f ../pnr_v2/diag_io_latency.tcl |& tee diag_io_latency_console.log
```

then type `exit`. Afterwards run the first `ls -ld` again: the time must be unchanged (run 1 untouched). The copy is large; the library of run 1 holds all its backup blocks (`bak_*`), which the script does not touch (only `unpu_top_route` is opened).

What to read: the table at the end of the console log (`ICC2 launch clock latency at the input port path ... H1 ...`), then `pnr_icc2/diag/hold_input_port.rpt`, `setup_dma_addr31.rpt` (the launch and capture clock lines) and `diag/sdc_*.sdc` (the I/O delay lines and whether `-network_latency_included` / `set_clock_latency` appear). The help texts `diag/help_*.txt` turn the `[M]` items of the research into `[L]`. Send the console log and the table to Planning. The last line before `exit` gives the number of reports that failed (a failing report is printed raw and the script goes on).

Parameters at the top of the script: `DIAG_LIB` (the copy), `DIAG_BLOCK` (default `unpu_top_route`), the ports/pins of the four examples, the scenario patterns (`*ss*`, `*ff*`; the names are read from the design and must match exactly one), `H1_MIN_LATENCY_NS 0.05`. Test: `tclsh pnr_v2/test_diag_io_latency.tcl`.

VERIFY list (task 084): V20 `open_lib -read` / `open_block -read` accept the copied library (usage text [L]; the option behaviour is not); V21 `get_blocks -all -quiet` lists the blocks of the library and `get_object_name` gives `lib:block`, `lib:block/label.view` or `block` (all three are accepted); V22 `redirect -variable` captures the text of the report commands; V23 `report_timing -path_type full_clock_expanded -input_pins -nets` prints the clock path in the form the parser reads (rows `name incr path [r|f]`, `clock network delay`, `input external delay`); if not, the verdict says `n/a`/INCONCLUSIVE and the raw report is in `diag/`; V24 `report_clocks`, `report_clock_tree_options`, the attribute `is_propagated` and `help <command>` forms; V25 `write_sdc -scenario <s> -output <file>` works on a read-only block (usage text [L]).

## diag_io_whatif.tcl (task 086): in-memory what-if on the same copy (run after diag_io_latency.tcl)

Why: the 084 run confirmed H1 (ICC2 counts a clock latency on the I/O reference where PrimeTime counts 0.00). Run 1's exported SDCs carry one tool-written line `set_clock_latency 0.806866 [get_clocks {clk}]` (ss) / `0.379753` (ff), equal to the measured I/O reference latencies. The script answers, with experiments in memory on the copy of run 1's library (the same guards as 084: other clone / missing library / missing block are refused; nothing is saved; the block is REOPENED after every experiment and a RESTORE CHECK re-runs the paths):

- **A0 (first, the cheapest fix candidate).** (a) `write_sdc` of every block of the chain that exists in the copy (placement, cts, route, filled, pv), per scenario: the count of `set_clock_latency` lines tells at which block the attribute FIRST exists; (b) remove it per scenario (`remove_clock_latency`, three forms tried in turn, the first that works is printed) and re-report the four example paths: do launch (input) and capture (output) go to 0.00? (c) the reg-to-reg setup and hold slacks must not change (a pure source latency); (d) the same line is searched in the exported SDCs (`pnr_icc2/outputs/unpu_top*.sdc` of this clone, or of run 1 with the environment variable `UNPU_WI_EXPORT_DIR`, read only).
- **A1a / A1b / A1c.** Every `set_input_delay` / `set_output_delay` of the active constraints (read from `write_sdc`, values and clocks kept) is re-issued with `-network_latency_included`, with `-source_latency_included`, and with both: which one matters? The exact command lines are printed and written to `pnr_icc2/diag/whatif_<label>_commands.txt`. This changes the SDC TEXT; applying it for real needs the user's approval.
- **A2.** Emulation by offsets: input MIN delay lowered by the measured ICC2 launch latency, output MAX delay raised by the measured capture latency, only on ports that are not on an input-to-output cone (the cone is computed from the netlist with `all_fanout`, as in step 4c). Judged by the slacks against PrimeTime's (the latency rows are not expected to change).
- **B.** The 0.27 ns data-delay difference on the hold input path, stage by stage beside PrimeTime's rows (input delay 0.00, port 0.26, `copt_h_inst_3910` buffd1 0.17, `U588` mx02d0 0.12), the first rows of the launch half printed raw, a second report with slew / capacitance / derate columns, `report_port -verbose` of the port, the drive/load lines of the SDC, the same path run from PrimeTime's start flop `u_dma/beat_idx_reg_0_` (the 084 path started at `u_dma/cur_m_reg_0_`: a different flop), and the baseline repeated on `_filled` and `_pv` if they exist in the copy (PrimeTime read the filled layout). Note: if the true ICC2 reference latency is the SDC value 0.3798 and not 0.6413, the ICC2 data delay is 0.9340 - 0.3798 = 0.5542 ns, which is PrimeTime's 0.56 ns; the printed rows decide.

Commands (csh, one per line; the copy of run 1's library is the one made for 084, see that section):

```
cd $RUN_DIR/pnr_icc2
icc2_shell -f ../pnr_v2/diag_io_whatif.tcl |& tee diag_io_whatif_console.log
```

then `exit`. Optional first, to search run 1's exported SDCs (read only): `setenv UNPU_WI_EXPORT_DIR <RUN1_DIR>/pnr_icc2/outputs` (and `unsetenv UNPU_WI_EXPORT_DIR` afterwards). After the run: `ls -ld --time-style=full-iso <RUN1_DIR>/pnr_icc2/blocks/unpu_top.dlib` must show the same time as before 084. The same path from PrimeTime's side, for part B (pt_shell on the same netlist and SPEF): `report_timing -delay_type min -from [get_ports {dma_rdata[14]}] -input_pins -nets -transition_time -capacitance -derate -significant_digits 4` and `report_annotated_parasitics -list_not_annotated` plus `report_net -connections` / `report_net_delay` style listings for the nets of the three stages (VERIFY the PrimeTime names).

What to read: the SUMMARY table at the end (one row per experiment: launch, capture, arrival, required, slack, in2out, reg-to-reg, constraints changed, failures), the verdict lines (SHOWS THE PRIMETIME CONVENTION / does NOT show it, in2out unchanged / CHANGED, reg-to-reg unchanged / CHANGED), the `A0(a)` table, the `A0(d)` lines, `RESTORE CHECK` lines, and the `FAILED` count. Test: `tclsh pnr_v2/test_diag_io_whatif.tcl`.

How the exported SDC could keep the line out (PROPOSAL, not implemented; VERIFY): in `pv.tcl`, `remove_clock_latency` (the form A0 found) per scenario on the block that is exported, before `write_sdc`; after the write, grep the exported files for `set_clock_latency` and stop with an error if any is left. If A0 shows that ICC2 then uses 0.00 like PrimeTime and the reg-to-reg slacks do not move, the same removal belongs right after `clock_opt` in `cts.tcl` and again before the later optimisations (`route.tcl`, `timing_closure.tcl`), so the optimiser sees the PrimeTime convention. That would be a flow change for the user to approve.

VERIFY list (task 086): V33 `remove_clock_latency` forms (help text saved as `diag/help_remove_clock_latency.txt`); V34 `-network_latency_included` / `-source_latency_included` accepted by `set_input_delay` / `set_output_delay` and re-issuing the same command replaces the value; V35 `open_lib` on the copy for EDIT is needed for the constraint edits (nothing is saved; the guard keeps it inside this clone); V36 `all_registers -edge_triggered` as `-from` / `-to` for the reg-to-reg slack; V37 `report_port -verbose`; V38 `list_attributes -class clock` and `report_clocks -nosplit`; V39 `report_app_options <one name>` per call; V40 the block names `unpu_top_cts`, `_filled`, `_pv` exist in the copy (otherwise they are skipped and printed).

## Task 088: the tool-made clock latency (the L1 fix)

Evidence. ICC2 writes `set_clock_latency <v> [get_clocks {clk}]` into the block (run 1's exported SDCs: 0.806866 in the ss SDC, 0.379753 in the ff SDC); no script of ours sets it. ICC2 then counts it as the I/O reference latency, PrimeTime (propagated clock) ignores it and reads the I/O at the clock pin. Task 086 experiment A0 (`remove_clock_latency [get_clocks -filter "is_virtual == false"]` per scenario, then a re-report on the copy of run 1) gave PrimeTime's numbers: hold slack -0.3494 (PrimeTime -0.35), output required 10.5000 (PrimeTime 10.50), source-flop launch 0.9188 (PrimeTime 0.92), reg-to-reg slacks unchanged, in2out setup 0.0212 -> 0.0081. Decision (user, 2026-11-10): remove the line inside the flow so that ICC2 optimises in PrimeTime's convention. This is NOT a tuned constraint: no margin, no uncertainty, no I/O delay, no goal, no limit changes; a tool artefact the instructor never gave is deleted.

Part 0 (read-only, run it FIRST on run 2's own library): where does the line first exist? `diag_clock_latency_origin.tcl` opens `unpu_top_placement`, `unpu_top_portbuf`, `unpu_top_cts`, `unpu_top_route` (those that exist; others are skipped and printed) with `open_block -read`, writes the SDC of every scenario into `pnr_icc2/diag/origin_*.sdc` and prints the table (block, scenario, count, value) and the first block per scenario. Optional environment variables: `UNPU_WI_LIB` (a library path inside this clone) and `UNPU_WI_BLOCKS` (a list of block names). Commands (csh, one per line):

```
cd $RUN_DIR/pnr_icc2
icc2_shell -f ../pnr_v2/diag_clock_latency_origin.tcl |& tee diag_clock_latency_origin_console.log
```

then `exit`. If the line is first in `unpu_top_cts`, it is created inside `clock_opt`; the split of `clock_opt` in `cts.tcl` (below) prints the count before each removal and so names the sub-step. If it is already in `_placement` / `_portbuf`, an earlier step creates it (`cts.tcl` also removes it from its input block).

Part 1 (the flow change). `clock_latency.tcl` is a shared file, sourced by the 4th bootstrap line (right after `set RUN_ROOT`) of `cts.tcl`, `route.tcl`, `fix_antenna.tcl`, `timing_closure.tcl`, `pt_eco_apply.tcl`, `antenna_port_buffers.tcl`, `antenna_clk_root.tcl`, `metal_fill.tcl` and `pv.tcl`. `unpu_remove_clock_latency <label>` counts the `set_clock_latency` lines per scenario (`write_sdc -scenario -include clock_latency` into `pnr_icc2/diag/clock_latency_<scenario>.sdc`), removes them with `remove_clock_latency` on the real clocks only when there are any, counts again, prints `>>> 088 <label> <scenario>: set_clock_latency lines before N, after M` and ends with `ERROR 088` if M is not 0 or a count cannot be read. A clean block issues NO command. It touches nothing else (uncertainty, propagated state) and restores `current_scenario`.

- `cts.tcl`: `clock_opt` is split at its sub-steps (usage text: `clock_opt [-list_only] [-from <step>] [-to <step>]`, steps `build_clock route_clock final_opto`): `clock_opt -to build_clock`, removal, `clock_opt -from route_clock -to route_clock`, removal, `clock_opt -from final_opto`, removal. `final_opto` (the optimisation and hold fixing) therefore runs WITHOUT the line unless the log shows it re-created inside `final_opto` (read the `before` count of `cts-after-final_opto`). `UNPU_CTS_SPLIT 0` (environment, no edit) runs one `clock_opt` and removes the line after it; then `final_opto` ran WITH the line (the log says so). The removal also runs on the input block (`cts-input`). The obsolete `clock_opt.hold.effort` line (error NDMUI-439, caught but noise) is deleted. At the end the log prints `>>> 088 I/O reference latency after the removal: input launch X ..., output capture Y ... (expected 0.00)` plus the first rows of the hold path, so the port stage of the driving cell can be told from a clock latency.
- the other scripts call the proc right after `link_block` (a no-op when clean), so a block saved by an older script is cleaned too; `port_buffers_early.tcl` runs before CTS and does nothing.
- `pv.tcl` calls it again before the first `write_sdc` and, after the last, greps `unpu_top_pnr_ss.sdc` and `unpu_top_pnr_ff.sdc`: any `set_clock_latency` line left ends the run with `ERROR 088`; the log shows `exported SDC files checked (2): 0 set_clock_latency lines`.

What to read in the logs: all `>>> 088` lines (`removing the tool-made line`, the before/after counts per scenario, `none left`, the I/O reference line, the `pv-exported-sdc` line). Redo: the CTS of run 2 must be run again (`cts.tcl` removes the old `_cts` itself); the later blocks are rebuilt by the following steps, each of which cleans its input.

What to expect. ICC2 now sees the I/O the way PrimeTime does: the input hold paths lose about 0.4 ns (ff) of apparent slack, so the optimiser inserts hold buffers on them (the 263 PrimeTime hold violators of run 1 are exactly these; the delay cells come from `final_opto`, not from a later ECO). On the output side the required time loses the output reference latency (about 0.8 ns at ss): the 086 numbers of run 1 put `dma_addr[31]` setup at about -0.475 ns in ICC2. The optimiser can only resize or buffer the path from the source flop to the port (the `ah01d1` carry chain and the `HFSINV_13_284` driver into the 1.0 pF load); whether it closes it will show in the CTS and route logs. No constraint is relaxed to help it; if it stays negative that is a result to report, not something to tune.

VERIFY list (task 088): V41 `write_sdc -scenario <s> -include clock_latency -output <f>` writes a file with the `set_clock_latency` lines (the counter reads only those lines, so a wider output is harmless); V42 `current_scenario` without argument returns the current scenario (otherwise it is not restored; printed nothing); V43 `clock_opt -list_only` prints the three step names, and `clock_opt -to build_clock`, `-from route_clock -to route_clock`, `-from final_opto` run the flow in pieces with the same result as one call (if not: `UNPU_CTS_SPLIT 0`); V44 `remove_clock_latency [get_clocks -filter "is_virtual == false"]` (the form of the 086 run); V45 the scenario names are all switchable (an inactive scenario would stop with ERROR 088 naming it); V46 the 4th bootstrap line is accepted by `icc2_shell -f` like the first three. Tests: `tclsh pnr_v2/test_clock_latency.tcl`.

### Task 089: the line exists from the power plan on; removal from placement onward

What the origin check showed (run 2's own library): `unpu_top_setup` and `unpu_top_floorplan` 0 lines; `unpu_top_powerplan` 1 line (ff 0.138485, ss 0.356843); `unpu_top_placement` the same; `unpu_top_portbuf` 0.367671 / 0.806847; `unpu_top_cts` (made by the OLD `cts.tcl`) the same as `_portbuf`. So CTS does not create the line; it leaves the pre-CTS ESTIMATE in place (the real tree latencies are about 0.60 ff / 1.36 ss), and `place_opt`, step 4c and the old CTS measured and optimised the I/O with the estimate as the I/O reference. Change: `placement.tcl` removes it right after `link_block` (`placement-input`) and again right after `place_opt` (`placement-final`, before the checks and the save); `port_buffers_early.tcl` removes it right after `link_block` (`port-buffers-input`, before the first timing update, in PLAN_ONLY too: the block is changed in memory only and the log says so), after every `update_timing -full` (a clean second update if the update re-created it) and before `save_block -as` (`port-buffers-final`); `powerplanning.tcl` removes it before `save_block` (`powerplan-final`). Every call prints the `>>> 088` counts; a line found again after a tool step prints `>>> 089 NOTE: <label>: the tool re-created the line inside <step> ...` (a finding, not an error). The gate tolerances of step 4c are unchanged. The `cts.tcl` removals of task 088 (`cts-input`, after each `clock_opt` part) stay.

The trigger in `powerplanning.tcl` (not found in the help texts): `powerplanning.tcl` has no timing command, and the usage texts in `~/server_pull/rpt/help` of `compile_pg`, `connect_pg_net`, `create_net`, `set_app_options`, `check_pg_connectivity` contain no word about timing or latency (`check_pg_drc` only mentions clock nets). The line therefore comes from something the tool does implicitly in that step (a first timing-graph build or the clock-latency estimate that goes with it, VERIFY). To name the command, `powerplanning.tcl` now has three count-only probes (`powerplan-probe-open`, `powerplan-probe-after-compile_pg`, `powerplan-probe-after-check_pg`); the first probe that shows 1 names the command group. Re-running `powerplanning.tcl` is optional and costs the later steps; the removals from placement on make it unnecessary for the result.

Rerun after the commit (csh, one command per line; `RUN_DIR` = this clone; the earlier steps up to the power plan are kept; type `exit` after each icc2_shell run):

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre089
icc2_shell -f ../pnr_v2/placement.tcl |& tee placement_console.log
setenv UNPU_WI_BLOCKS "unpu_top_placement"
icc2_shell -f ../pnr_v2/diag_clock_latency_origin.tcl |& tee diag_origin_placement.log
setenv UNPU_PBE_PLAN_ONLY 1
icc2_shell -f ../pnr_v2/port_buffers_early.tcl |& tee port_buffers_early_plan_console.log
unsetenv UNPU_PBE_PLAN_ONLY
icc2_shell -f ../pnr_v2/port_buffers_early.tcl |& tee port_buffers_early_console.log
setenv UNPU_WI_BLOCKS "unpu_top_portbuf"
icc2_shell -f ../pnr_v2/diag_clock_latency_origin.tcl |& tee diag_origin_portbuf.log
unsetenv UNPU_WI_BLOCKS
icc2_shell -f ../pnr_v2/cts.tcl |& tee cts_console.log
```

(compare the PLAN_ONLY table with the earlier one: with the clean convention the BUFFER set may change; the second `port_buffers_early.tcl` run is the real one, with the environment variables you decide on.) Expected table of the origin check after the redo: 0 lines in every block from `unpu_top_placement` on; the power-plan block stays as saved (1 line) unless `powerplanning.tcl` is run again, in which case `powerplan-final` cleans it. VERIFY V47: the probes and removals in `powerplanning.tcl` and `placement.tcl` run in the same scenarios as the later steps (all scenarios of the block are switched; an inactive one stops with ERROR 088).

## Task 090: optimisation-only uncertainty margin (cts, route, timing_closure)

User decision 2026-11-10: ICC2 optimises to `SPEC + goal`, the SPEC values (setup 1.5, hold 0.5), the exported SDC and the sign-off stay. Reason: ICC2's parasitic estimate and PrimeTime's SPEF differ by tens of ps. All code is in `opt_uncertainty.tcl` (sourced by `cts.tcl`, `route.tcl`, `timing_closure.tcl`, `pv.tcl`); the three scripts call `unc090_params`, `unc090_open_opt` (before the optimiser) and `unc090_close_opt` (after it).

**The trap.** A clock-wide x also reaches the input-to-output group (`paddr` to `prdata`, budget 20 - 1.5 - 7 - 7, margin about 0 in both tools: setup +0.0081, hold +0.0068). ICC2 sees it x worse in setup AND hold, the hold part adds delay and breaks the setup part (-0.59 ns, 2026-11-09). So the margin must reach register endpoints and not output-port endpoints.

| `UNPU_UNC_SCOPE` | what is set while the optimiser runs | endpoints at output ports |
|---|---|---|
| `flops` (DEFAULT) | clock-level stays SPEC; `SPEC + goal` on the clock pins of `all_registers -edge_triggered` (absolute value: a pin-level value replaces the clock-level one) | keep SPEC |
| `outputs` | clock-level `SPEC + goal`; the SPEC value pinned on `all_outputs` | keep SPEC (pinned) |
| `clock` | clock-level `SPEC + goal` (the old form, comparison only) | get the margin (the trap) |

Goals: setup in `func_ss` only, hold in `func_ff` only. Defaults setup 0.05, hold 0.10 (starting values; hold larger because the sign-off failures were hold). Environment (csh, one per line; `unsetenv` returns to the defaults; the source of each value is printed in `>>> 090 parameters`):

```
setenv UNPU_SETUP_SLACK_GOAL 0.05
setenv UNPU_HOLD_SLACK_GOAL 0.10
setenv UNPU_UNC_SCOPE flops
setenv UNPU_UNC_PROBE 1
unsetenv UNPU_HOLD_SLACK_GOAL
```

A goal must be a number 0 <= v <= 1.0, the scope `flops`, `outputs` or `clock`, the probe flag 0 or 1; anything else is ERROR 090 naming the variable. Goal 0 for a kind sets nothing at pin level for that kind.

**Lines to read (`>>> 090`):**
- `parameters:` scope, goals, sources, targets.
- `<label> scope flops: N clock pins of M edge-triggered registers (<command used>)` / `scope outputs: N output ports pinned`.
- `<label> in2out: setup WNS ... hold WNS ...` before (SPEC state) and the line `in2out (scope ..): setup WNS a -> b, hold WNS c -> d` after the restore; `WARNING: the margin made the in2out group worse` when the drop is more than 0.005 ns (no stop; the end state counts).
- `probe ...`: ONE known path with the pin/port-level value set and removed: flops form `dma_rdata[14]` to `u_dma/stage_reg_1__14_/D` (setup and hold): the slack must move by -goal; outputs form `dma_addr[31]` setup and `prdata[0]` hold: the slack with the port pinned must be +goal above the one without. `the value acts` = ok; `WARNING ... the SAME. ICC2 ignored ...` = the form does not work in this ICC2 (use the other scope); `WARNING ... expected` = it moved by another amount. A port or pin that is not in the design prints a WARNING and is skipped.
- `SDC check <scenario> (<kind>, scope ..): ok` right after the OPT values (the scratch SDC `pnr_icc2/diag/uncertainty_*.sdc` shows them); `RESTORE PROOF <scenario>: pin/port-level uncertainty lines left 0 (0 names), clock-level values: ...`. Any line left or any clock-level value not at SPEC is ERROR 090 and nothing is saved.
- `pv.tcl`: `pv-exported-sdc` lists every `set_clock_uncertainty` line of the two exported SDCs; a pin/port-level line or a value that differs from SPEC is ERROR 090 (a count other than 4 lines is a NOTE).

Expected effect: more hold cells on input-to-register and register-to-register paths (area), a small setup effort on register endpoints; output-port paths are unchanged. If a probe says `SAME`, the margin does not act (flops) or leaks (outputs): do not trust the run, switch the scope.

VERIFY list (task 090): V48 `all_registers -edge_triggered -clock_pins` (else the fallback `get_pins -of_objects <regs> -filter "is_clock_pin == true"` is used and printed); V49 `set_clock_uncertainty -setup|-hold <v> <pins or ports>` takes effect for paths ending at those objects and replaces the clock-level value there (the probes test it); V50 `remove_clock_uncertainty -setup|-hold <objects>` (else the form without the option is used and a NOTE is printed; the proof catches a failed removal); V51 `write_sdc -scenario <s> -include clock_uncertainty -nosplit -output <f>` writes the pin/port-level lines (the proof and the SDC check read them; if the SDC does not show pin-level values the SDC check stops with ERROR 090 rather than pass); V52 `get_ports -quiet -exact <name with brackets>`, `get_pins -quiet -exact <pin>`; V53 `all_outputs` as the object list of `set_clock_uncertainty`; V54 the pre-CTS in2out numbers (before CTS the clock is ideal) are comparable to the post-CTS ones (the in2out path does not use the clock tree). Tests: `tclsh pnr_v2/test_opt_uncertainty.tcl` (151 checks, a stateful mock of the three scopes, the restore proof, a failed removal, ports ignored by the tool).

## Checkpoint after route (task 091)

Lesson L5: PrimeTime and Calibre are run on the ROUTED block before fill, while every fix is cheap (in run 1 PrimeTime came last and found 264 violations). `pv.tcl`, the PrimeTime scripts and the Calibre control files get an optional checkpoint mode; the default (final export of `unpu_top_filled` into `pnr_icc2/outputs/`) is unchanged and nothing of it is overwritten.

| variable | meaning |
|---|---|
| `UNPU_PV_BLOCK` | block to export (default `unpu_top_filled`). A block other than the default without `UNPU_PV_TAG` is ERROR 091 (it would overwrite the final export). |
| `UNPU_PV_TAG` | letters, digits, underscore. Everything goes to tagged places: `pnr_icc2/outputs_<tag>/` (same file names as the final export), `pnr_icc2/reports_<tag>/`, `logs/7_pv_<tag>.log`; the saved block is `unpu_top_pv_<tag>`. The block is COPIED first (`save_block -force -as unpu_top_pv_<tag>`, closed and reopened), so `unpu_top_route` itself is not modified (no `connect_pg_net`, `create_frame`, latency removal in it). |
| `UNPU_PT_TAG` | the same tag for `pt_setup_ss.tcl` / `pt_hold_ff.tcl` / the ECO probes: inputs from `outputs_<tag>/`, reports in `pnr_icc2/pt_<tag>/`. The folder must exist (ERROR otherwise, naming `pv.tcl`). |
| `PL_OUT_DIR`, `PL_SIM_DIR` | (existing since task 075) the simulation script reads another export folder and writes another sim folder. |

All hard checks of `pv.tcl` run unchanged in both modes (LEF check with `MACRO unpu_top`, SDF 3.0 header, the 088 `set_clock_latency` grep, the 090 `unc090_export_check`). New: the exported `unpu_top_pnr_sim.v` must hold a module called `unpu_top` (PrimeTime does `link_design unpu_top`): printed in both modes, ERROR 091 in a tagged run. The line `>>> 091 PV block ..., tag ..., output folder ...` is the first line to read.

**1. Export the routed block (icc2_shell; csh, one command per line):**

```
cd $RUN_DIR/pnr_icc2
setenv UNPU_PV_BLOCK unpu_top_route
setenv UNPU_PV_TAG route
icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_route_console.log
unsetenv UNPU_PV_BLOCK
unsetenv UNPU_PV_TAG
ls -l outputs_route
grep ">>> 091\|ERROR\|CHECK PASSED\|CHECK FAILED\|STAGE 7" pv_route_console.log
```

Read: `>>> 091 PV block unpu_top_route, tag 'route', output folder .../outputs_route`; `checkpoint: working on the copy unpu_top_pv_route`; `LEF CHECK PASSED`; `SDF CHECK PASSED` twice; `091 netlist ...: module unpu_top present`; the `pv-exported-sdc` lines (4 clock-level lines at SPEC); `STAGE 7 COMPLETE`. `outputs_route` must hold `unpu_top_routed.gds`, `unpu_top.lef`, `unpu_top.def`, `unpu_top_pnr_sim.v`, `unpu_top_pnr_pg.v`, `unpu_top_spef.*`, `unpu_top_ss.sdf`, `unpu_top_ff.sdf`, `unpu_top_pnr_ss.sdc`, `unpu_top_pnr_ff.sdc`. `ls -ld outputs` must show the time of the earlier final export or none: the checkpoint did not touch it. The ICC2 checks of `pv.tcl` (`check_routes`, `check_legality`, PG) are in `reports_route/`.

**2. PrimeTime on the checkpoint (pt_shell terminal, `pnr_v2/pt/README.md` sections 1 to 3b apply unchanged):**

```
cd $RUN_DIR
mkdir -p pnr_icc2/pt_route
cd pnr_icc2/pt_route
setenv UNPU_PT_TAG route
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_TAG
```

The first lines show `>>> 091 PT CHECKPOINT tag route: inputs from .../outputs_route, reports in .../pt_route`. Run from `pt_route` (the folder you are in): `parasitics_command.log` is written to the current directory. If the annotation fallback (pt README 3b) is needed, use the same commands there from this folder. Read the `SUMMARY` block of each log: zero violating endpoints is the goal (setup ss, hold ff), plus the annotation check. Run 1 ended with 263 hold violators, all on input-to-register and register-to-register paths; the 090 margin is meant to prevent them.

**3. Calibre DRC and antenna on the checkpoint GDS (a Calibre terminal, `calibre/README.md` section 1; LVS later on the final layout).** The control files are NOT edited on the server: the run folder copy gets ONE `sed` per file that changes only the folder name in the `LAYOUT PATH` line.

```
cd $RUN_DIR
mkdir -p pnr_icc2/calibre/route1/drc pnr_icc2/calibre/route1/ant
cp pnr_v2/calibre/drc.ctrl pnr_icc2/calibre/route1/drc/
cp pnr_v2/calibre/ant.ctrl pnr_icc2/calibre/route1/ant/
sed -i '/^LAYOUT PATH/s#/outputs/#/outputs_route/#' pnr_icc2/calibre/route1/drc/drc.ctrl
sed -i '/^LAYOUT PATH/s#/outputs/#/outputs_route/#' pnr_icc2/calibre/route1/ant/ant.ctrl
cd pnr_icc2/calibre/route1/drc
pwd -P
grep '^LAYOUT PATH' drc.ctrl
ls -lL ../../../outputs_route/unpu_top_routed.gds
calibre -drc -hier drc.ctrl |& tee drc.log
cd ../ant
pwd -P
grep '^LAYOUT PATH' ant.ctrl
ls -lL ../../../outputs_route/unpu_top_routed.gds
calibre -drc -hier ant.ctrl |& tee ant.log
```

Before each run the printed line must be `LAYOUT PATH "../../../outputs_route/unpu_top_routed.gds"`, `pwd -P` must be under `$RUN_DIR`, and `ls -lL` must show the file (about 15 to 20 MB: no metal fill yet). Read the results with the commands of `calibre/README.md` sections 4 and 5 (`TOTAL RULECHECKS EXECUTED` 404 for DRC and 16 for antenna, `TOTAL RESULTS GENERATED`, `grep "TOTAL Result Count" ... | grep -v "= 0 "`, layer statistics, `grep -i error`). Goal: DRC 0 and antenna 0. A non-zero antenna result is expected to be possible (ICC2 counted 87 violations at the end of route; Calibre decides, and its input-port nets are the ones ICC2 skips): the antenna database of the checkpoint feeds the existing loop (`fix_antenna.tcl`, `calibre/README.md` section 5): `mkdir -p $RUN_DIR/pv/drc` and `cp $RUN_DIR/pnr_icc2/calibre/route1/ant/unpu_top.ant.db $RUN_DIR/pv/drc/unpu_top_antenna_bkp.db`. The GDS top cell must be `unpu_top`: check it as in `calibre/README.md` section 3 with `strings -n 3 ../../outputs_route/unpu_top_routed.gds | grep -n "^unpu_top"`.

**4. Simulation (optional).** `env PL_OUT_DIR=pnr_icc2/outputs_route PL_SIM_DIR=pnr_icc2/sim_route bash pnr_v2/sim/run_postlayout_sim.sh ss nochecks` (repo-root relative folders; the script prints the folders it uses).

**Cost (estimates, nothing measured for the checkpoint yet):** `pv.tcl` on the route block is the same work as on the filled block (GDS merge, SPEF, SDF, reports) minus the fill, so the same order of minutes as the final export; PrimeTime a few minutes per corner (the task 074 runs); Calibre DRC: the old 15.7 MB GDS took about 160 s (`calibre/README.md` section 4) and the checkpoint GDS has no fill, so expect a few minutes; antenna tens of seconds. The checkpoint can be repeated after each later ECO step with another tag (`UNPU_PV_TAG route_eco1`, `UNPU_PT_TAG route_eco1`, a new `route2` Calibre folder).

VERIFY list (task 091): V55 `save_block -force -as <name>` then `close_blocks` and `open_block <lib>:<name>` leaves the copy as the current block and the source block unmodified (`ls -l --time-style=full-iso` of the library folder of `unpu_top_route` before and after, or the block list); V56 the LEF macro rename for the block name `unpu_top_pv_route` (the generic rename of task 073 renames any single macro to `unpu_top`; the log line `LEF macro renamed ... -> unpu_top` or `already called` says which); V57 the Verilog module of the checkpoint netlist is `unpu_top` (checked by the script) and the GDS top cell is `unpu_top` (the `strings` check above); V58 Calibre resolves the relative `LAYOUT PATH` from `route1/drc` (`drc.log` names the GDS); V59 `route_global -congestion_map_only true`, `check_lvs` etc. behave on the route block as on the filled one (the reports go to `reports_route/`). Tests: `tclsh pnr_v2/test_pv_checkpoint.tcl`.

## Hold ECO for register-to-output violators on the route checkpoint (task 092)

Evidence (run 3, PrimeTime on `unpu_top_route`, `UNPU_PT_TAG route`): setup ss 0 violators; hold ff WNS -0.0238 ns, 7 violating endpoints, ALL register-to-output paths into `prdata[*]` from `u_csr` flops (`dest_c_reg_reg_*`, `src_a_reg_reg_*`, `src_b_reg_reg_*`) through the read mux (`oai222d1/d2`) and a tool buffer to the port. They are not input-to-output paths. The 090 margin (scope `flops`) does not reach output-port endpoints on purpose, so ICC2 did not fix them (ICC2 sees -0.0004).

**What the new scope does** (`UNPU_ECO_SCOPE`, `in2reg` = the behaviour of tasks 078 to 081 and the DEFAULT, `reg2out` = new; validated, the source is printed in `>>> 092 ECO scope`):
- The targets are the hold violators whose startpoint is a register pin and whose endpoint is an output port; they are listed with their count (`>>> 092   target:`). `fix_eco_timing` itself is still run WITHOUT a `-from` / `-to` restriction (the form that worked in tasks 078 to 081; no restriction option is known from a usage text), so it may also fix violators outside the scope; the count of other violators is printed and the targets that remain after the ECO are listed. Same data-chosen delay-cell list, same hold margin `PT_ECO_HOLD_MARGIN` 0.05 ns (a few ps to tens of ps of SPEF versus ICC2 difference; a fix closed at exactly 0.00 would not survive it).
- **The finding behind the scope.** The cone protection of task 080 puts `dont_touch` on the cone CELLS and on every NET that touches a cone cell. The net from a flop's `QN` into the read mux touches a cone cell (`oai222`), so with the old rule PrimeTime may not insert a delay at the only place where a register-to-output delay belongs, and the 7 violators would remain with the message "every remaining violator crosses the cone". In `reg2out` the cone cells stay protected, but a cone NET stays protected only if it is DRIVEN by a cone cell or lies on a cone port. A net driven by a flop carries no input-to-output path (a flop ends a path), so it is released (`>>> 092 reg2out: cone nets kept protected ... released ...`).
- **The cone-safety claim, and how it is checked.** (1) No input-to-output path runs on a released net by construction (driver is outside the cone). (2) The cone cells and the cone-driven nets and ports stay `dont_touch` during the ECO. (3) AFTER the ECO the written change file is parsed and every change is tested against the cone cells and ports: one change on a cone cell pin, a cone port or a resize of a cone cell ends the probe with `ECO RAN BUT TOUCHES THE IN2OUT CONE`. (4) Every insertion is printed with its pin and class (`>>> 092 insertion N: pin ...: on a flop output pin outside the cone (the expected form)`), and `>>> 092 insertions by class` sums them; anything that is not a flop output pin is listed and called out (outside the cone, but read it before applying). (5) The apply script's gate: in2out WNS and whole-design setup WNS in ICC2 must not worsen by more than 0.005 ns, else nothing is saved.
- The change files and the count file (`pt_eco_hold_expected_count.txt`, with a `scope` line) go to the folder of `UNPU_PT_TAG` (`pnr_icc2/pt_<tag>/`); nothing is written into the final folders.

**`pt_eco_apply.tcl`:** `UNPU_PT_TAG` selects the folder of the change files (`pnr_icc2/pt_<tag>/`, ERROR 092 if it does not exist). The typed `EXPECT_ANTBUF 15` is gone (run 3 has no `antbuf_*` yet): the 54 `earlybuf_*` buffers and any `antbuf_*` are protected like before (snapshot of reference, origin, orientation and pins, `dont_touch` switched off during the apply and on again), their counts are printed before and after and must be equal; a block with neither set is refused. All earlier gates stay (in2out and setup WNS tolerance 0.005, hold only a warning, DRC clean-up loop, 0 open nets, legality, each new cell placed next to its pin). It saves over `unpu_top_route`; the apply does no backup, the user copies the library first.

**Sequence (csh, one command per line). Library backup first:**

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_reg2out
ls -ld blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_reg2out
```

PrimeTime terminal (the checkpoint folder is the one of the PrimeTime run of task 091):

```
cd $RUN_DIR/pnr_icc2/pt_route
setenv UNPU_ECO_SCOPE reg2out
setenv UNPU_PT_TAG route
pt_shell -f ../../pnr_v2/pt/pt_eco_probe.tcl |& tee pt_eco_probe_reg2out.log
unsetenv UNPU_ECO_SCOPE
unsetenv UNPU_PT_TAG
grep ">>> 092\|PROBE RESULT\|AFTER-CHECK\|>>> 081" pt_eco_probe_reg2out.log
```

Read: `ECO scope reg2out (environment UNPU_ECO_SCOPE)`; `scope reg2out: 7 of 7 hold violators are targets` (if more than 7 appear, read the other ones: they are fixed too); `cone nets kept protected ... released ...` (released must be above 0); `PROBE RESULT: ECO RAN: N changes proposed ... (none touches the in2out cone)`; `insertions by class: N on a flop output pin outside the cone (expected)` with N equal to the number of changes; `remaining target` lines (none expected). If the result is `TOUCHES THE IN2OUT CONE`, stop: do not apply.

ICC2 terminal:

```
cd $RUN_DIR/pnr_icc2
setenv UNPU_PT_TAG route
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_reg2out_console.log
unsetenv UNPU_PT_TAG
grep ">>> 092\|GATE\|CHECK\|STAGE 6g\|ERROR" pt_eco_apply_reg2out_console.log
```

Read: `change files from .../pt_route (UNPU_PT_TAG route)`; `0 antbuf_* and 54 earlybuf_* cells are protected`; `CHECK earlybuf_* count: 54 (before the ECO 54)`; `GATE setup ... ok` for the in2out group and the whole design; `check_routes AFTER: DRCs 0, open nets 0`; `STAGE 6g COMPLETE`. A GATE failure saves nothing (the library is untouched except the backup you made).

Then the checkpoint again with a NEW tag and PrimeTime on it (setup and hold), the sequence of "Checkpoint after route (task 091)" with `route2`:

```
cd $RUN_DIR/pnr_icc2
setenv UNPU_PV_BLOCK unpu_top_route
setenv UNPU_PV_TAG route2
icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_route2_console.log
unsetenv UNPU_PV_BLOCK
unsetenv UNPU_PV_TAG
mkdir -p pt_route2
cd pt_route2
setenv UNPU_PT_TAG route2
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_TAG
```

Goal: setup ss 0 violators (unchanged), hold ff 0 violators. **Not in this pass:** the antenna repair for the 5 cone-skipped input nets and whatever the Calibre antenna run finds (Calibre has not run yet): the user tells Planning the Calibre result first; one combined sequence (antenna ECO, this hold ECO, checkpoint, PrimeTime, Calibre) can then be written. If the Calibre antenna pass is done BEFORE this ECO, run the ECO after it (the ECO needs the final netlist of the routed block).

**Expectation for the 7 endpoints.** One delay cell per violating flop output, so at most 7 cells (fewer when several endpoints share a flop; each `prdata` bit has its own read-mux input, so about 7); the area change is printed by `fix_eco_timing` (`>>> 079 changes proposed ... area change`). Delay cells are slow at ss (0.4 to 0.9 ns, task 080), so a cell needed for 0.03 ns of hold at ff adds far more at ss.

**What could hurt setup of the same flop's other paths.** A delay cell on the `QN` pin sits in front of ALL loads of that net, not only the read mux. Another path from the same flop (for example into the sequencer or the DMA address logic) gets the delay at ss, and register-to-register setup has about zero margin. PrimeTime's hold session is the ff corner only and cannot see it. The checks: the apply script's whole-design setup gate (ICC2 ss, 0.005 ns tolerance, nothing saved on a violation), then PrimeTime setup ss on `route2`. If the gate fails: read the setup report to find the path, then the options are a smaller delay cell on that flop only (a hold margin below 0.05 needs a written reason and the user's approval) or inserting at the read-mux input pin to isolate the one load (that pin belongs to a cone cell and the cone check forbids it; it needs a decision).

VERIFY list (task 092): V60 `UNPU_ECO_SCOPE reg2out` run: the released nets are above 0 and PrimeTime really inserts on the `QN` pins (the class lines say so); V61 `get_attribute <pin> direction` returns `out`/`in` and `is_sequential` returns `true`/`false` for the flops (otherwise the class is `unknown` and printed); V62 `fix_eco_timing` still accepts the form without `-from` / `-to` on this netlist (as in tasks 078 to 081); V63 `earlybuf_*` cell and pin snapshots compare equal after the apply (the existing snapshot code; a difference ends the run with nothing saved). Tests: `tclsh pnr_v2/test_eco_scope.tcl`.

### The cone check at PIN level (task 093)

**Why.** On `route3` the `reg2out` probe proposed 9 `insert_buffer` (2 `dl01d1`, 7 `buffd1`, +137.96 um2) that bring the 7 targets to 0 in PrimeTime's memory, but all 9 sit on LOAD pins of read-mux cells (`u_csr/U77/A2`, `U77/C2`, `U77/B2`, `U9/B2`, `U74/C2`, `U361/B2`, `U79/B2`, `U72/C2`, `U398/A2`). The 092 check judged the CELL (`oai222` is a cone cell) and ended with `ECO RAN BUT TOUCHES THE IN2OUT CONE: 9 of 9`.

**The rule.** `insert_buffer` on a LOAD (input) pin puts the buffer on the net segment that feeds that pin; only the arcs from that pin are delayed. The `paddr` to `prdata` paths enter the same cell through OTHER pins. A pin whose net is driven by a flop (the `QN` net of a `u_csr` flop) starts a register-to-output path and cannot be on an input-to-output path. So the check asks: is the NET that feeds the pin on an input-to-output path? Every proposed insertion gets one class (printed as `>>> 093 insertion N: pin ...; net ...; driver ... (sequential: ...); net state ...: <class text>`):

| class | meaning | AFTER check |
|---|---|---|
| `load_flop` | input pin of a cone cell, its net is a RELEASED net (task 092 rule) and every driver of the net is a sequential cell | safe |
| `load_comb` | same, a driver is a combinational cell outside the cone (safe by the cone definition: a driver reachable from an input port would be in the cone); printed with a NOTE | not a violation, read it |
| `flop_output`, `flop_input`, `other`, `port` | pin of a cell outside the cone, or a port outside the cone: classes of task 092 | not a violation |
| `cone_net` | input pin whose net is a KEPT cone net (driven by a cone cell or on a cone port) | **violation** |
| `cone_driver` | output pin of a cone cell | **violation** |
| `cone_port` | a cone port | **violation** |
| `cone_resize` | `size_cell` of a cone cell (reported as a hit with that text) | **violation** |
| `unknown` | direction, net, driver or `is_sequential` unreadable; or a net that is in neither list | **violation** (no silent pass) |

The AFTER check fails (`PROBE RESULT: ECO RAN BUT TOUCHES THE IN2OUT CONE`) only for the four violation classes and `unknown`. A clean run ends with `PROBE RESULT: ECO RAN: 9 changes proposed, change file ... (none touches the in2out cone). Pin classes: 9 load pin on a flop-driven net (safe: starts at a flop)`. In scope `in2reg` nothing is released, so every pin of a cone cell stays a violation (`cone_net` or `cone_driver`) exactly as the old cell-level check said.

**Which net is judged (follow-up of the first server run).** The class is computed AFTER `fix_eco_timing` has inserted the buffers in PrimeTime's memory, so the load pin already sits on the NEW net (`net_PTECO_HOLD_NET<n>`), driven by the new buffer (`U_PTECO_HOLD_BUF<n>/Z`, not sequential). That net is in neither the kept nor the released list, which made all 9 `unknown` on `route3`. Now the buffer named in the change file (`-new_cell_names`) is recognised: when the only driver of the pin's net is that buffer, the net and the driver are taken from the buffer's INPUT pin, i.e. the ORIGINAL net that existed before the ECO (kept/released state, flop or not). If the pin's net is driven by any other cell, the rule is the one above on that net. A buffer whose input pin or input net cannot be found stays `unknown`. The printed line shows both: `>>> 093 insertion N: pin ...; original net ..., original driver ... (sequential: 1); net state released; after the ECO the pin sees net u_csr/net_PTECO_HOLD_NET<n> driven by u_csr/U_PTECO_HOLD_BUF<n>/Z: <class>`. The class file keeps the original net and driver.

**What does not change.** The protection during `fix_eco_timing` is the one of task 092: cone CELLS `dont_touch`, kept cone nets `dont_touch` (195 kept, 109 released on `route3`). The pin-level class judges the PROPOSALS only. The probe also writes `pt_<tag>/pt_eco_hold_pin_classes.txt` (one line per insertion: index, pin, reference, class, net, drivers).

**`pt_eco_apply.tcl`.** Gates unchanged: in2out and whole-design setup WNS must not get worse than 0.005 ns, DRC loop, legality, `earlybuf_*` / `antbuf_*` protection. The class file is read from the same folder as the change files: each hold insertion is printed with its class (`>>> 093 change N: ...`); a class file of another change file (different pin, missing or extra line) or a violation class ends the run with `ERROR 093`, nothing changed. Without the class file one line says so and nothing else changes. **The ICC2 gates are the final proof** that the claim holds in ICC2's own timing: the in2out WNS before and after the insertions is compared there (an input-to-output path through a load pin of the same cell would show up as a change of that WNS).

**Sequence.** Unchanged from task 092 (the same commands); only the probe's verdict differs. After the probe read: the 9 `>>> 093 insertion` lines (net and driver of every pin), `>>> 093 insertions by class`, the `PROBE RESULT` line. Apply only when the result line is `ECO RAN:` and the classes are `load_flop`.

VERIFY list (task 093): V64 `get_nets -quiet -of_objects <pin>` on a pin of a cell inside a hierarchy returns the same net NAME as the cone traversal used for the kept and released lists (a mismatch makes the state `none` and the class `unknown`, which is printed, never a silent pass); V65 `pt_cone_net_pins <net> out` (`all_connected -leaf`) lists the QN pin of the flop as the driver of the net; V66 `get_attribute <flop cell> is_sequential` is `true`; V67 `get_pins -quiet -exact <full pin>` finds the pins of the change file; V68 `get_pins -of_objects <new buffer cell> -filter "direction == in"` returns the buffer's one input pin and `get_nets -of_objects` of it the original net (otherwise `unknown`, printed). Tests: `tclsh pnr_v2/test_eco_scope.tcl` (114 checks, 52 of them new for 093, with the 9 real pins of `route3` in the shape PrimeTime shows after the insertion).

## Max-transition ECO for the DATA limit, design rules in the PrimeTime summary, UNPU_PT_SI (task 095)

**Evidence (run 3, final filled layout, ss).** `report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width`: 510 `max_transition` entries, 0 `max_capacitance`, 0 min pulse width (the parser of `pt_parse_design_rules` reproduces these numbers from the real report, `pnr_v2/testdata/095_run3_ss_design_rules.rpt`; the ff report has none). Two groups: 424 on the CLOCK-PATH limit 0.40 ns (not part of this task: the user dropped it from the exported SDC, task 096) and **86 on the DATA limit 3.0 ns** (`set_max_transition 3 [current_design]`, legacy SDC): actual 3.00 to 3.05 ns; the entries with slack `0.00 (VIOLATED: increase significant digits)` are over by less than 5 ps.

**The 86 entries are on 9 nets** (traced from the post-layout netlist of run 3 with a throw-away script; the probe prints the same table from PrimeTime, `pt_eco_drc_ss_nets.csv`):

| Net | Driver | Load pins | Entries | Why the transition is high |
|---|---|---|---|---|
| `u_seq/HFSNET_137` | `buffd1` `u_seq/HFSBUF_1163_489` | 40 | 41 (the load pins `A2`/`B2` of `U367..U390`, the select pins `U97/S`, `U396/S`) | the high-fanout synthesis buffer is the SMALLEST buffer (`buffd1`) and drives 40 loads |
| `u_actbuf/HFSNET_29` | `buffd1` `u_actbuf/HFSBUF_21543_531` | 37 | 38 (37 load pins `A2` of `U412..U481` and the driver pin `HFSBUF_21543_531/Z` itself, 3.02) | the same: a `buffd1` on 37 loads |
| `dma_wdata[7], [11], [21], [25], [27], [29], [31]` | `an02d4` (`U150`, `U210`, `U99`, `U157`, `U220`, `U198`, `U101`) | 0 (an OUTPUT PORT) | 7 (the port) | the port load of the SDC (`set_load -pin_load 1` = 1 pF) on an AND gate |

**Proposed fix (what the ECO is expected to do; PrimeTime chooses):** size up the two `buffd1` (to `buffd3`/`buffd7`), or split the net with buffers; for the 7 ports a stronger driver or a buffer in front of the port (`an02d4` may already be the largest AND: then `insert_buffer`). The area cost is a few cells.

**Part 1: `pt/pt_eco_drc_probe.tcl` (new) and `pt_eco_apply.tcl` with `UNPU_ECO_KIND drc`.**
- The probe (ss) runs `pt_prepare_session`, the design-rule report BEFORE, selects the entries whose required value is the design-wide limit (read from the SDC, not typed), writes the net table, runs `fix_eco_drc -type max_transition -methods {size_cell insert_buffer} -buffer_list <plain buffers>` (forms in order: collection, bare names, no list, type only; an option error tries the next form; the help text is printed first), writes `pt_eco_drc_changes{.tcl,_icc2.tcl,.txt}`, `pt_eco_drc_expected_count.txt` and `pt_eco_drc_pin_classes.txt`, and prints the AFTER design rules in PrimeTime's memory (remaining data-limit violators listed, the clock-path count before/after: it must not change).
- **Protection, stated rule.** The in2out cone is `dont_touch` as in 092/093 (cells, and the nets that carry an input-to-output path; the nets that a flop drives into the cone are released) and the CLOCK NETWORK is `dont_touch` too (cells with an output pin on the clock network and the clock nets; an empty clock network or a failed read-back of the attribute is an error: `PROBE RESULT: ECO NOT RUN, CLOCK NETWORK NOT PROTECTED`). A resize of a cone cell is therefore NOT allowed in this probe (stricter than "allowed if it is a speed-up"; a violator that sits only on a protected net is listed as remaining). After the ECO every change is checked at pin level (the 093 classes plus the new class `clock_net`); a `size_cell` of a cone or clock cell and any violation class gives `PROBE RESULT: ECO RAN BUT TOUCHES THE IN2OUT CONE`. The buffer candidates are plain buffers (`buff*`, `bufbd*`); the `dl*` delay cells are NOT candidates.
- The apply (`setenv UNPU_ECO_KIND drc`, default `hold`, validated, printed in `>>> 095 ECO kind`) reads `pt_eco_drc_changes_icc2.tcl`, `pt_eco_drc_expected_count.txt` and `pt_eco_drc_pin_classes.txt` (REQUIRED for this kind; a violation class stops it before anything is changed). `insert_buffer` on a driver pin and `size_cell` were already supported (079). The 9 `U_PTECO_HOLD_BUF` cells of the hold ECO are protected like the `earlybuf_*` cells: snapshot (reference, origin, orientation, pin nets) compared at the end, their count must be unchanged, and they are not counted as "new cells" or as "applied before". **The gates are unchanged:** in2out WNS and whole-design setup WNS not worse than 0.005 ns before saving, DRC 0 (clean-up loop), legality 0, open nets 0, `earlybuf_*`/`antbuf_*` unchanged. The hold WNS before/after is printed (`GATE hold ...`, a WARNING, not an error).
- **Hold.** Hold at ff is only +0.0002 ns. A resize or a buffer on these nets can change it: a stronger driver makes the signals through the HFS nets arrive EARLIER (less hold slack on endpoints they feed), a buffer in front of an output port adds delay (more hold slack at that port). The 7 `dma_wdata` ports are register-to-output hold endpoints of the same kind as the `prdata` ones fixed in 092, so they are the ones to watch. Expectation: the two HFS nets feed long reg-to-reg control paths (hold slack of tenths of a ns); the ports are the risk. ICC2 prints its hold WNS before/after; **the next PrimeTime hold run decides**; if it goes negative, a second hold ECO round (`UNPU_ECO_SCOPE reg2out` or the default scope) is the remedy.

**Sequence for run 3 (csh, one command per line).** The probe runs on the UNTAGGED final export (`pnr_icc2/outputs`, folder `pnr_icc2/pt`): that is the run that showed the violators, and its netlist equals `unpu_top_route` plus fillers (physical-only cells), so the change file applies to `_route`; no new checkpoint is needed.

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_maxtrans
ls -ld blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_maxtrans
```

PrimeTime terminal (probe; reads `outputs/`, writes into `pt/`):

```
cd $RUN_DIR/pnr_icc2/pt
pt_shell -f ../../pnr_v2/pt/pt_eco_drc_probe.tcl |& tee pt_eco_drc_probe.log
grep ">>> 095\|PROBE RESULT" pt_eco_drc_probe.log
```

Read: `BEFORE: 86 max_transition entries of the DATA limit`, `the 86 entries sit on 9 NETS`, the `buffer list`, `clock network protected`, `AFTER the ECO ... data-limit max_transition violators 0 (before 86)`, `clock-path max_transition entries: before 424, after 424`, `insertions by class`, `PROBE RESULT: ECO RAN: N changes proposed ... (none touches the in2out cone or the clock network)`.

ICC2 terminal:

```
cd $RUN_DIR/pnr_icc2
setenv UNPU_ECO_KIND drc
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_drc_console.log
unsetenv UNPU_ECO_KIND
grep ">>> 095\|>>> 093\|GATE\|CHECK\|STAGE 6g\|ERROR" pt_eco_apply_drc_console.log
```

Read: `ECO kind drc (environment UNPU_ECO_KIND)`, `the block already holds 9 cells of the hold ECO`, `CHECK hold-ECO cells (PTECO_HOLD): 9 before the ECO, 9 after it`, `GATE setup ... ok` (in2out and whole design), `GATE hold ...` (the hold WNS before/after), `check_routes AFTER: DRCs 0, open nets 0`, `STAGE 6g COMPLETE`.

Then the ECO is in `unpu_top_route`, so the fill and the export are redone (the filled block and `outputs/` were written before the ECO). Keep run 3's results first, then fill, export, the three Calibre runs in a NEW folder `final2`, both PrimeTime runs and the simulation:

```
cd $RUN_DIR/pnr_icc2
mv pt pt_run3_final
mv sim sim_run3_final
cp -r outputs outputs_run3_final
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl |& tee pv_console.log
```

Calibre DRC, antenna and LVS: the commands of `calibre/README.md` for the final layout (run folder `pnr_icc2/calibre/final2/{drc,ant,lvs}`, as `final` of run 3). PrimeTime on the new export (`mkdir -p pt` first, `cd` into it):

```
mkdir -p $RUN_DIR/pnr_icc2/pt
cd $RUN_DIR/pnr_icc2/pt
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
```

Why each step: the backup (the apply overwrites `_route`); the probe (PrimeTime proposes, nothing is written to the design); the apply (the ICC2 netlist and routes change); fill + export (they were produced before the ECO); Calibre (the layout changed); PrimeTime (the sign-off of timing AND of the design rules, including hold); the simulation (post-layout netlist and SDF changed, `sim/README.md`).

**Part 2: design rules in the summary.** `pt_setup_ss.tcl` and `pt_hold_ff.tcl` call `pt_design_rules_run`: the DESIGN RULES block is printed in the log and in the SUMMARY (max_transition split by the limit that applies, read from the SDC: clock-path vs design; max_capacitance; min pulse width; worst actual/required/slack of each group; `DESIGN RULES: MET` / `VIOLATED (N)` / `UNKNOWN (...)` when the report cannot be read) and a line `SIGN-OFF IS NOT CLEAN: DESIGN RULES VIOLATED (510)` (or `TIMING AND DESIGN RULES: both MET`). The `SETUP: MET` / `HOLD: MET` words are unchanged. With the run-3 report the block reads 424 / 86 / 0 / 0. The reports `pt_<kind>_<corner>_design_rules.rpt` keep their names. The ICC2 reference of the comparison line is no longer a constant (`PT_ICC2_SETUP_WNS`/`PT_ICC2_HOLD_WNS`, run-1 numbers, are gone): it is the worst `slack (MET|VIOLATED)` of ICC2's own report of the same export (`reports[_<tag>]/unpu_top_final_setup_ss.rpt` and `unpu_top_final_hold_ff.rpt`, the first 50 paths, 2 decimals), and the SUMMARY says where it came from; when the report is missing or unreadable the comparison says `difference UNKNOWN`.

**Part 3: PrimeTime with SI.** `UNPU_PT_SI` (0 = default, 1 = SI/crosstalk analysis on; anything else is `PT ERROR`; source printed in `>>> 095 SI state`). With 1 the PrimeTime-SI licence is checked (existing check), the inputs stay (`outputs[_<tag>]`) and the REPORTS go to `pt_<tag>_si` (or `pt_si` without a tag), so the SI-off reports are never overwritten; the summary line ends with `SI ON`/`SI OFF`. The ECO probes refuse `UNPU_PT_SI=1` (their change files are read by the apply from the SI-off folder). SI-on run (csh), for the route4 checkpoint and for the final export:

```
cd $RUN_DIR/pnr_icc2
mkdir -p pt_route4_si
cd pt_route4_si
setenv UNPU_PT_TAG route4
setenv UNPU_PT_SI 1
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_SI
unsetenv UNPU_PT_TAG
```

```
cd $RUN_DIR/pnr_icc2
mkdir -p pt_si
cd pt_si
setenv UNPU_PT_SI 1
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_SI
```

**Tests:** `tclsh pnr_v2/test_drc_eco.tcl` (103 checks: the real report 424/86/0/0 and the ff report, unreadable and synthetic reports, the summary block, the ICC2 reference, the SI variable also in a child `tclsh`, the net grouping with the 9 real nets, the class file with `clock_net`, the kind/files/hold-cell logic of the apply, source checks of the probe). The other suites keep their counts (`test_eco_scope` 114, `pt/test_pt_common` 278 with one check replaced: the run-1 constants).

**VERIFY (task 095), read in the logs:** V69 `help fix_eco_drc` exists in T-2022.03-SP2 and accepts `-type max_transition -methods {size_cell insert_buffer} -buffer_list` (the form that ran is printed); V70 the licence for `fix_eco_drc` (PT-002 'PrimeTime-ECO' is printed for `get_license` but `fix_eco_timing` worked: the command itself decides); V71 `report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width` prints the headings `max_transition` etc. (the parser is checked on the real run-3 text); V72 `is_clock_network` on pins and nets and the protection read-back (`clock network protected: N clock cells`); V73 `get_nets -of_objects <port>` and `all_connected` give the net and the load count for the net table; V74 the buffer names `U_PTECO_*` of `fix_eco_drc` (the apply counts new cells by NAME with the marker `PTECO`, hold cells `PTECO_HOLD` excluded); V75 the hold WNS of ICC2 before/after the ECO in the apply log, then PrimeTime hold; V76 `UNPU_PT_SI=1`: `get_license PrimeTime-SI` and `si_enable_analysis` are accepted.

## Option B: the 0.40 ns clock-path max_transition stays out of the exported SDC; PrimeTime against the legacy SDC; sdc_compare.tcl (task 096)

**Decision (user, 2026-11-10 night).** `set_max_transition 0.4 [get_clocks {clk}] -clock_path` comes from the example `cts.tcl` (the CTS TARGET: `set_max_transition 0.40 -clock_path $real_clks`, unchanged there), is not in the legacy constraints or in the instructor's guidance, and the final tree misses it (0.43 to 0.48 ns at ss; 424 entries in the PrimeTime design-rule report of run 3). It is NOT carried into the exported SDC. A target of the example script, not a course constraint; the tree's actual values stay in the reports.

**Part 1: `pv.tcl`.** Before the first `write_sdc`, for each scenario (`func_ss`, `func_ff`) `pv096_remove_clock_path`: a temporary SDC of the scenario is written and read back (and deleted) to count the clock-path lines and the design-wide limit lines before and after; the removal command is tried in this order, for the commands that exist: `remove_max_transition -clock_path <clocks>`, `remove_max_transition <clocks> -clock_path`, `reset_max_transition -clock_path <clocks>`, `remove_max_transition <clocks>` (VERIFY V77: the form that worked is printed; none worked = `ERROR 096` with the `help *max_transition*` text and NOTHING exported). A form that also removes the design-wide lines is detected and those exact lines are restored from the state before. Printed per scenario: `>>> 096 func_ss: clock-path max_transition lines before 1, after 0; design-wide lines after: set_max_transition 3 [current_design] | set_max_capacitance 2 [current_design]`. After the last `write_sdc` the two exported files are read again: any clock-path max_transition line is `ERROR 096`; the design-wide `set_max_transition` and `set_max_capacitance` lines must be present and equal to the ones the block had before the removal (`>>> 096 CHECK exported SDCs`). The block that is saved at the end (`unpu_top_pv`, or `unpu_top_pv_<tag>`) loses the limit too: that is intended, it is the exported block; `unpu_top_filled`, `unpu_top_route` and the CTS target are not touched. The layout, the GDS, the SPEF and the SDF are unchanged, so the Calibre results stay valid; only `pv.tcl` has to be re-run.

**Part 2: `UNPU_PT_SDC` (PrimeTime against the legacy constraints themselves).** `exported` (default, today) or `legacy` (anything else is `PT ERROR`; the source is printed in `>>> 096 SDC source`). With `legacy`, `pt_setup_ss.tcl` and `pt_hold_ff.tcl` read `constraints/legacy/unpu_top_legacy.sdc` (path derived from the run root) for both corners, apply the same single change as today (`set_propagated_clock [all_clocks]`, proved from a timing report), and write to `pnr_icc2/pt_<tag>_legacy` (with SI also: `..._legacy_si`); the SUMMARY prints `SDC: legacy (<path>)`. The legacy file keeps its numbers in variables (`set CLK_UNCERT_SETUP 1.5`, `set MAX_TRANSITION 3.0`): `pt_sdc_resolve_vars` substitutes them for the text checks (period, uncertainties, limits), PrimeTime evaluates the file itself. A command PrimeTime rejects is a `PT ERROR` with its message (existing check on `Error:` in the `read_sdc` text). Why: an independent proof that the layout meets the constraints AS GIVEN, not as rewritten by the tool. The ECO probes refuse `UNPU_PT_SDC=legacy` (their change files are read by the apply from the exported-SDC folder). csh:

```
cd $RUN_DIR/pnr_icc2
mkdir -p pt_legacy
cd pt_legacy
setenv UNPU_PT_SDC legacy
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_SDC
```

For a checkpoint (`route4`): `mkdir -p pt_route4_legacy`, `cd` into it, `setenv UNPU_PT_TAG route4` as well. With the legacy SDC there is no clock-path limit, so the design-rule block shows only the data-limit entries (86 until the ECO of task 095 is applied).

**Part 3: `sdc_compare.tcl`.** `tclsh pnr_v2/sdc_compare.tcl constraints/legacy/unpu_top_legacy.sdc pnr_icc2/outputs/unpu_top_pnr_ss.sdc` (and `_ff.sdc`). Pure Tcl, no EDA tool: both files are evaluated in a SAFE Tcl interpreter in which every SDC command only records its arguments (so the variables and `expr` of the legacy file are resolved by Tcl), then compared: `create_clock` (period and waveform), clock uncertainty, clock transition, input and output delays (-min/-max, per port), driving cells, loads, `max_transition` (design-wide and `-clock_path`), `max_capacitance`, propagated clock. Port patterns of the legacy file are expanded against the port names of the exported file; `all_inputs`/`all_outputs` = the ports that carry an input/output delay there. The table is `constraint | legacy | exported | status` (the same value on many ports is one line with the count); status `SAME`, `DIFFERENT`, `ONLY-IN-LEGACY`, `ONLY-IN-EXPORTED` or `EXPECTED` (listed by name in the script with a reason: `set_propagated_clock`, the explicit `-waveform`, `set_operating_conditions`, `set_units`); anything else is a difference. Commands that are not compared are named. Exit 0 equal, 1 a difference, 2 an unreadable file.

**Result on the run-3 exports (ss and ff give the same table):** 723 constraints compared; SAME 718 (clock 20, uncertainty setup 1.5 / hold 0.5, clock transition 0.6, input delays 7 on 67 APB ports / 8 on 34 DMA+reset ports / 0 min, output delays 7 on 33 / 8 on 69 / -0.5 min on 102, driving cell `buffd1`/`Z` on 101 ports, loads 1 pF on 102 and 0.2 pF on 101 ports, `max_transition` 3 and `max_capacitance` 2 design-wide); EXPECTED 4 (propagated clock, waveform, operating conditions, units); **DIFFERENCES 1: `max_transition clock_path` 0.4 on `clk`, only in the exported file** = the line that option B removes. With that line deleted the verdict is `EQUAL apart from the 4 expected difference(s)` (tested on a copy).

**Tests:** `tclsh pnr_v2/test_sdc_limits.tcl` (65 checks: the pure parts of `pv.tcl` on the real exported SDC, the variables of the legacy SDC, `UNPU_PT_SDC` also in a child `tclsh`, `sdc_compare.tcl` on the real files and on changed copies). Test data: `pnr_v2/testdata/096_run3_exported_{ss,ff}.sdc` (comment lines stripped). `test_clock_latency` has one source check re-pointed at the export `write_sdc` (the 096 helper writes a temporary one before it).

**csh for the server (after task 095's ECO or on the current layout):**

```
cd $RUN_DIR/pnr_icc2
icc2_shell -f ../pnr_v2/pv.tcl < /dev/null |& tee pv_console.log
grep ">>> 096\|ERROR" pv_console.log
grep -c "clock_path" outputs/unpu_top_pnr_ss.sdc outputs/unpu_top_pnr_ff.sdc
cd $RUN_DIR
tclsh pnr_v2/sdc_compare.tcl constraints/legacy/unpu_top_legacy.sdc pnr_icc2/outputs/unpu_top_pnr_ss.sdc
tclsh pnr_v2/sdc_compare.tcl constraints/legacy/unpu_top_legacy.sdc pnr_icc2/outputs/unpu_top_pnr_ff.sdc
```

Read: `clock-path max_transition lines before 1, after 0` for both scenarios, `the form that worked: ...`, `CHECK exported SDCs`; the two `grep -c` give 0; both comparisons end with `EQUAL apart from the 4 expected difference(s)`.

**VERIFY (task 096):** V77 the removal command and its form (`remove_max_transition` / `reset_max_transition`; the form that worked is printed; the temporary-SDC read-back is the proof); V78 `write_sdc -scenario <s> -output <tmp>` works for a scenario that is not the only one (it is what `pv.tcl` already does for the export); V79 PrimeTime `read_sdc` accepts the legacy file as it is (variables, `expr`, `get_ports $LIST`, `set_driving_cell -lib_cell buffd1 -pin Z` without `-library`): an `Error:` stops the run with the text; V80 with the legacy SDC `check_timing` and the clock proof of `pt_checks_and_clock` still pass (the clock is made propagated by the same single change).

## A resized cell that does not fit in place is relocated (task 097)

**Evidence (run 3, `UNPU_ECO_KIND=drc`, commit 73f169d).** The probe proposed 9 `size_cell` changes (+94.13 um2; 86 data-limit entries -> 0 in PrimeTime's memory). The apply placed 4 of 9 and stopped (nothing saved): the resize only grew a cell into the filler run that touches its RIGHT edge, and 5 cells had none wide enough: `an02d4 -> an02d7` needs 2.24 um more (free run 0.56 / none / none / 1.12 um), `buffd1 -> buffd3` needs 0.56 um (no free filler run at the right edge).

**The rule (`pt_eco_apply.tcl`, size_cell branch).**
1. First in place, exactly as before (`eco079_grow_plan`: the filler run at the right edge, then `size_cell` and `legalize_placement`, the position must not change). The log line stays `>>> 079 SIZE change N: ...`, and `>>> 097 SIZE change N: cell A -> B, in place` is added.
2. If it does not fit: RELOCATION. The candidates come from the SAME filler table as the insertions (`ant_filler_runs`, `ant_site_candidates`), with the old cell's own footprint counted as free, so a cell can also grow to the LEFT or be shifted by a few sites. A candidate is a run that fits the NEW width in whole sites; its start site is the one nearest to the old cell's centre; the distance is the Manhattan distance between the old and the new cell centre and must not exceed `MAX_RESIZE_MOVE_UM`; nearest first, at most `MAX_SITE_TRIES` (5) tried per change. Per candidate: the fillers of the run are removed (the real ones; the free sites that earlier relocations left are pseudo rows of the table), `size_cell` (once), `set_cell_location -coordinates {x y} -orientation <that of the row's fillers>`, then the position, the orientation and the reference are READ BACK and must be those requested (NO `legalize_placement` in this branch: nothing is moved by a legalizer); on a mismatch the next candidate is tried. After a success the old footprint and the unused rest of the removed fillers go back into the table as free rows (a later change may use them) and the real fillers are re-created for all free sites at the end (`create_stdcell_fillers`, as before). The nets of the cell (inputs and outputs) are re-routed with the touched nets (`route_eco -nets`, incremental detail route, the DRC clean-up loop of 081), as for the insertions.
3. The limit is `MAX_RESIZE_MOVE_UM` (the line `set MAX_RESIZE_MOVE_UM $PORT_MAX_PIN_BUF_DIST` in `pt_eco_apply.tcl`, 40 um): the SAME value and reason as the pin-to-buffer limit of step 6c (a cell that moves farther adds wire delay on its nets that PrimeTime did not see; the timing gates judge what is left). Edit the line to change it; it is printed at the start (`>>> 097 a resized cell ...`).
4. Geometry, printed for every change (`>>> 097   change N geometry`): the driver position, the driver-to-PORT distance before and after (the `dma_wdata[*]` drivers; `n/a` when the net has no port) and the distance from the driver to the centroid of the loads before and after (the 40-load nets `u_seq/HFSNET_137`, `u_actbuf/HFSNET_29`). A relocated cell whose driver-to-port distance grew by more than `RESIZE_PORT_WARN_UM` (20 um) gets a WARNING; it is not an error, the gates decide.
5. Log lines per change: `>>> 097 SIZE change N: cell A -> B, in place` or `..., relocated by X um to (x, y), run [x0,x1], distance Y` (X = origin shift, Y = centre-to-centre distance), the candidate summary (`needs 2.24 um more width (...); relocation: K candidate run(s) within 40.0 um`), and `N free row(s) added to the occupancy table`.
6. If NO candidate works the change FAILS (nothing saved, as before) with the text: why in place failed, the candidates that were rejected and why, and `no free site run within MAX_RESIZE_MOVE_UM = 40.0 um is wide enough for the new cell (5.04 um = 9 sites); the 3 nearest runs: row y=... x=...  width=... needed=... : <reason> | ...` and that the user decides: raise `MAX_RESIZE_MOVE_UM`, or ask the probe for `-methods {insert_buffer}` only for that net.

**Unchanged:** the hard checks: applied == total, DRC 0 (clean-up loop), open nets 0, legality 0, the protected cells (`earlybuf_*`, `antbuf_*`, the 9 `PTECO_HOLD` cells) identical, in2out and whole-design setup WNS not worse than 0.005 ns before saving, hold WNS before/after reported (WARNING). The insertions treat the pseudo rows (free sites of earlier relocations) as free runs too (only real filler instances are looked up and removed).

**What to expect for the 5 failing changes (from the numbers in the server report; the filler table of the layout is not in my hands, so the places are not known).** The cells: `an02d4 -> an02d7` (4 sites more) for `dma_wdata` drivers U157, U101, U150 (the 4th `an02d4`, change 8, has a free run of 1.12 um = 2 sites at its right edge), `buffd1 -> buffd3` (1 site more) for the HFS buffers `u_actbuf/HFSBUF_21543_531` and `u_seq/HFSBUF_1163_489`. The 1-site growth of the buffers is the easy case: any single free site next to the cell, left OR right, or a run of 4 sites within 40 um works; the rows are full of 1-, 3- and 9-site fillers, so a free site on the LEFT edge is likely. The `an02d7` cells need 9 consecutive free sites (5.04 um) including their own 5: either 4 free sites left/right of the old cell (not available on the right: 0.56 / none / none / 1.12 um; the left side is unknown) or a free 9-site run (a `feedth9` filler) within 40 um. The data is not enough to say where each cell goes; if a 9-site run does not exist within 40 um the failure text lists the 3 nearest runs with their widths and the user decides (raise the limit, or `insert_buffer` instead of the upsizing for the 3 ports).

**csh to repeat the apply (the library was not changed by the failed run; the backup `blocks/unpu_top.dlib.bak_pre_maxtrans` is already there):**

```
cd $RUN_DIR/pnr_icc2
git pull
setenv UNPU_ECO_KIND drc
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_drc_console.log
unsetenv UNPU_ECO_KIND
grep ">>> 097\|SIZE change\|GATE\|CHECK\|STAGE 6g\|ERROR" pt_eco_apply_drc_console.log
```

**Tests:** `tclsh pnr_v2/test_pt_eco_apply.tcl` (169 checks: the 136 older ones plus 33 for the 097 rules: the five real failures (growth plan fails as on the server), growth to the left into the neighbouring filler, shift by own footprint plus a free run, nearest run first, too narrow, too far, the 3-run failure text, orientation of pseudo rows, the occupancy update and its reuse by the next change, the port-distance flag, the log lines, source checks).

**VERIFY (task 097):** V81 `size_cell` on a cell that overlaps its neighbours for the moment (the master is wider before `set_cell_location` moves it) is accepted by this ICC2; if it is refused the log shows `size_cell failed` for the first candidate; V82 `set_cell_location -coordinates -orientation` on a cell with a new master, and the read-back of `bbox`/`orientation`; V83 `get_ports -of_objects <net>` for the driver-to-port distance; V84 a filler's `orientation` attribute equals the orientation a cell needs in that row (the run's orientation is taken from the first filler of the run).

## SI-on ECO round (task 098): close the SI-on setup and hold endpoints without losing the SI-off sign-off

**Evidence (run 3, final filled layout after 092-097, commit 6970448).** SI OFF (the default sign-off): setup ss +0.1041 ns, hold ff +0.0008 ns, 0 violators, design rules MET. SI ON (`UNPU_PT_SI=1`, annotation 3,477 RC + 13,094 coupled nets): setup ss **-0.0364 ns, TNS -0.0755, 4 endpoints**, all `paddr[3]` -> `prdata[20]` -0.0364, `[10]` -0.0242, `[22]` -0.0090, `[17]` -0.0059 (the zero-margin combinational read path; the net `paddr[3]` is about 210 um long and was left unbuffered on purpose by the early port buffers, CONE-SKIPPED); hold ff **-0.0114 ns, 1 endpoint** `prdata[9]` from `u_csr/src_a_reg_reg_9_/CP` (register to output, the family of task 092). The current state is the FALLBACK; the new state replaces it only if everything passes.

**What changed.**
1. *SI-on probes.* The hold probe (`pt_eco_probe.tcl`) and the setup probe (`pt_eco_setup_probe.tcl`) now run with `UNPU_PT_SI=1` (the max-transition probe still refuses it). The session is the SI-on session of the sign-off run (coupled parasitics, `si_enable_analysis`), the change files go to the SI folder (`pnr_icc2/pt_si/`, or `pt_<tag>_si/` with a tag), and the SI state is printed in the banner, the probe header and the result line (`PROBE RESULT (SI ON): ...`). `pt_eco_apply.tcl` reads the folder named by the same variable (`UNPU_PT_SI=1`, ERROR 092 if the folder does not exist); a hold run with SI on does not read the optional setup file (one kind per call). **The change files must come from ONE probe run per kind**: a second probe run in the same folder overwrites the first, the count and class files are rewritten with it (the setup probe deletes stale ones first).
2. *Setup kind (`UNPU_ECO_KIND=setup`).* `fix_eco_timing -type setup -methods {size_cell} -setup_margin 0.02` (`PT_ECO_SETUP_MARGIN`; if this release does not know `-setup_margin` the form without it is tried, and said). Size-only first; the probe does NOT ask for insertions. The in2out cone is NOT protected (the read path IS the cone) but every change is classified: a `size_cell` of a cone cell is allowed only if the new reference is FASTER (a larger drive of the same function, decided from the library names: same family prefix, larger drive number: `oai222d1` -> `oai222d2`; a name that cannot be compared, `buffda`, is NOT provably faster and is a violation, `cone_slower`); the clock network, the `earlybuf_*`/`antbuf_*` buffers, the `PTECO_HOLD` cells and the 9 resized drivers of task 095 are `dont_touch` in the probe and protected (snapshot) in the apply, and a change that targets one of them is an ERROR 098. Per proposed change the probe prints: the cell, old and new reference (the old one recorded for every cone cell before the ECO), the speed relation, the output net, whether it is on the read path, the area (old -> new) and the class. If PrimeTime proposes an INSERTION anyway, or the size changes do not close the violators, the probe STOPS and says so (`ECO NEEDS A DECISION` / `SIZE-ONLY ECO DOES NOT CLOSE THE VIOLATORS (the user decides)`) with the options (a buffer on the cone net and its delay cost, a stronger early buffer on `paddr[3]` replacing the CONE-SKIPPED decision, a margin approach): no count file and no class file are written then, so the apply cannot run on it. The measurement is printed BEFORE and AFTER in the SI-on view and, in the same session, in the SI-OFF view (`si_enable_analysis false`, restored to true; VERIFY V85; if it cannot be switched the line says so and the two-run procedure applies: the SI-off sign-off run of the final export, below).
3. *Hold kind for `prdata[9]`.* The 092 scope `reg2out` with SI on: `setenv UNPU_ECO_SCOPE reg2out`, the delay cell on a flop-driven load pin, pin-level classes, cone cells protected. `PT_ECO_HOLD_MARGIN` stays 0.05 ns: the SI-on slack is -0.0114 ns, a delay cell at ff is 0.2 to 0.4 ns, so the margin is about 4 times the violation and covers the picoseconds of difference between PrimeTime and the ICC2 re-route; no reason to change it.
4. *Apply.* One kind per call; order **hold, then setup**, each with its own gates. Reason: the hold insertion is a delay cell on a flop-driven load pin of `prdata[9]`, which is not one of the four read-path endpoints; the setup resizes do not touch it, and the second apply protects it (the cells of the first call are earlier-round cells: snapshot compared, count still present, not counted as new). The setup probe does not see the hold cell (it runs on the export before the hold ECO); the PrimeTime runs on the new export are the proof. The gates after EACH call are the existing ones: in2out WNS and whole-design setup WNS not worse than 0.005 ns before saving (for the setup kind the in2out WNS is printed before and after: it should IMPROVE; it is an SI-on measurement in ICC2 and will not match PrimeTime's SI-on exactly), DRC 0 (clean-up loop), legality 0, open nets 0, `earlybuf_*`/`antbuf_*`/`PTECO_HOLD` and the 9 resized drivers unchanged. The relocation of task 097 applies to every `size_cell`.

**Sequence for run 3 (csh, one command per line; `$RUN_DIR` set).** The state to keep is the FALLBACK: nothing below overwrites it until the `mv` lines.

```
cd $RUN_DIR/pnr_icc2
cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_si
ls -ld blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_si
mkdir -p pt_si
```

PrimeTime probes (SI on, from `pt_si`; the two can run in two terminals at the same time, they write different file names; about 2 to 4 minutes each, SI on is slower than the 2 minutes of a sign-off run):

```
cd $RUN_DIR/pnr_icc2/pt_si
setenv UNPU_PT_SI 1
setenv UNPU_ECO_SCOPE reg2out
pt_shell -f ../../pnr_v2/pt/pt_eco_probe.tcl |& tee pt_eco_probe_hold.log
unsetenv UNPU_ECO_SCOPE
grep "PROBE RESULT\|>>> 092\|>>> 093\|AFTER" pt_eco_probe_hold.log
```

```
cd $RUN_DIR/pnr_icc2/pt_si
setenv UNPU_PT_SI 1
pt_shell -f ../../pnr_v2/pt/pt_eco_setup_probe.tcl |& tee pt_eco_setup_probe.log
grep "PROBE RESULT\|>>> 098" pt_eco_setup_probe.log
```

Read: hold `PROBE RESULT (SI ON): ECO RAN: 1 changes proposed ... (none touches the in2out cone)` with the class `load pin on a flop-driven net`; setup `PROBE RESULT (SI ON): ECO RAN: N size_cell changes proposed ... violating endpoints 4 -> 0 in this view; SI-off view: violating endpoints 0 ...`. **If either says `NEEDS A DECISION`, `DOES NOT CLOSE` or `TOUCHES`, STOP and report to Planning: do not go on.**

ICC2 (hold first, then setup; each call opens `unpu_top_route` and overwrites it, the gates run in each):

```
cd $RUN_DIR/pnr_icc2
setenv UNPU_PT_SI 1
setenv UNPU_ECO_KIND hold
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_si_hold_console.log
grep ">>> 098\|>>> 097\|GATE\|CHECK\|STAGE 6g\|ERROR" pt_eco_apply_si_hold_console.log
setenv UNPU_ECO_KIND setup
icc2_shell -f ../pnr_v2/pt_eco_apply.tcl < /dev/null |& tee pt_eco_apply_si_setup_console.log
grep ">>> 098\|>>> 097\|GATE\|CHECK\|STAGE 6g\|ERROR" pt_eco_apply_si_setup_console.log
unsetenv UNPU_ECO_KIND
unsetenv UNPU_PT_SI
```

Run the second call only if the first ended with `STAGE 6g COMPLETE`. A failure saves nothing; the library backup `bak_pre_si` is for a call that must be undone.

Then the chain that must be redone (the filled block and `outputs/` are from before the ECO). Keep the fallback results FIRST:

```
cd $RUN_DIR/pnr_icc2
mv outputs outputs_before_si
mv pt pt_before_si
mv pt_si pt_si_before_si
mv pt_legacy pt_legacy_before_si
mv sim sim_before_si
mv calibre/final2 calibre/final2_before_si
icc2_shell -f ../pnr_v2/metal_fill.tcl |& tee metal_fill_console.log
icc2_shell -f ../pnr_v2/pv.tcl |& tee pv_console.log
```

(`pt_si` is moved away together with the probe files: the change files are no longer needed after the apply; copy them to `pt_si_before_si` first happens by the `mv`.) `metal_fill.tcl` about 1 to 2 minutes, `pv.tcl` about 1 to 2 minutes (run-3 log timestamps: 21:09:54 and 21:11:09).

Calibre DRC, antenna and LVS in a NEW folder `final3` (the commands of `calibre/README.md`, as `final2`; the three runs can run in three terminals at the same time; the run times were not recorded in the logs I have: read the Calibre logs). PrimeTime on the new export, SI OFF, SI ON and the legacy SDC (six runs of about 2 minutes, all independent: three terminals at the same time, each in its own folder):

```
mkdir -p $RUN_DIR/pnr_icc2/pt
cd $RUN_DIR/pnr_icc2/pt
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
```

```
mkdir -p $RUN_DIR/pnr_icc2/pt_si
cd $RUN_DIR/pnr_icc2/pt_si
setenv UNPU_PT_SI 1
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_SI
```

```
mkdir -p $RUN_DIR/pnr_icc2/pt_legacy
cd $RUN_DIR/pnr_icc2/pt_legacy
setenv UNPU_PT_SDC legacy
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
unsetenv UNPU_PT_SDC
```

The post-layout simulation (`sim/README.md`; A 4.4 min, B 6.6 min, C 4.5 min, D about 6 to 7 min plus the licence wait; independent of Calibre and PrimeTime, can start right after `pv.tcl`). **Accept the new state only if:** both SI-off and SI-on PrimeTime runs show 0 violators (setup ss, hold ff), the legacy run is identical to the SI-off one, DESIGN RULES MET, Calibre `final3` DRC 0 / antenna 0 / LVS CORRECT, the simulation passes as before. Otherwise go back: `mv` the `*_before_si` folders back and restore the library from `bak_pre_si`.

**What to expect for the 5 endpoints (from the numbers in the task; the cells are not known until the probe has run).** The 4 setup endpoints share the input `paddr[3]` and the first stages of the read mux; -0.0364 ns on `prdata[20]` is the worst, the others are -0.0242 / -0.0090 / -0.0059, so one or two larger-drive cells in the shared part (the address decode / the cell that `paddr[3]` drives and its fan-out cone) close all four, and the 36 ps is a small speed-up for a cell on a 4.5 ns path (a `d1` -> `d2` step typically gains tens of picoseconds). The cost is the extra input capacitance a larger cell puts on the driving net (here the long unbuffered `paddr[3]`, driven by the input driver `buffd1` of the SDC): the probe's AFTER numbers include it. The hold endpoint `prdata[9]` needs 11 ps: one delay cell on the flop output, which the SI-off sign-off may see as +0.2 to 0.4 ns on the same path at ss (setup of the register-to-output path has large margin there, 092). **Risk to the SI-off numbers (setup +0.1041, hold +0.0008):** the setup resizes make the read path faster, so SI-off setup should improve or stay; a faster cell in the cone can only reduce hold on in-to-out hold paths if any exist (the in2out hold is not the worst endpoint: +0.0008 is a register-to-output / input-to-register path, to be re-read in the new hold run); the new delay cell lowers the hold risk of its own path and adds to its setup path (register-to-output, large margin); a re-route of the touched nets changes coupling by picoseconds. The new PrimeTime runs decide; hold at +0.0008 has the least margin and is the one to read first.

**Fix after the first SI round (setup call stopped at the class check):** `ERROR 098: ... the class file has 2 rows for 1 size_cell changes`. The comment line was NOT counted; the apply compared `[llength <dict of rows>]` with the number of changes, and `llength` of a dict counts keys AND values (2 per row). It now counts rows with `dict size` (`eco098_rows_problem`); comment and blank lines never become rows (`eco093_parse_classes` skips them), two real rows for one change and a missing row are still refused. The hold and drc readers never counted rows that way (they compare per change number). Tested with the verbatim two-line file of the server.

**Tests:** `tclsh pnr_v2/test_si_eco.tcl` (53 checks: the SI folder of the probes and the apply, the kinds, the setup change file with `size_cell` lines, the speed-up check, the class rules and the equality of the violation lists of the probe and the apply side, the size class file check, the result lines and guards, source checks of the probe and the apply). `test_drc_eco` keeps 103 (the kind `setup` is now valid).

**VERIFY (task 098):** V85 `set_app_var si_enable_analysis false` / `true` followed by `update_timing -full` works in the SI-on session (the SI-off view of the same session); V86 `fix_eco_timing -type setup -methods {size_cell} -setup_margin` accepts these options (the form that ran is printed); V87 `size_cell` proposals of PrimeTime use references of the same family (the speed relation is decided from the names; a line `not provable` is a violation and stops the apply); V88 `get_cells -hierarchical earlybuf_*` etc. return the protected cells in the probe session (the line `protected during the ECO` counts them); V89 the SI-on hold probe finds `prdata[9]` as a reg2out target (`>>> 092 scope reg2out: 1 of 1`).

## Decided (user, 2026-11-02)

- **D1** BASE path: was one typed literal per script (the clone `unpu`); since task 082 it is derived from the script location (`<RUN_DIR>` = the clone), so a second clone is a second, independent run.
- **D2** `HOLD_SLACK_GOAL` and `SETUP_SLACK_GOAL` are 0.0 in `cts.tcl` and `route.tcl` (task 065; the example had 0.70 and 0.3/0.30), so the optimiser sees exactly the course constraints (setup 1.5, hold 0.5). Lines marked `065`.
- **D3** Pin ORDER (bits ascending, handoff 18.9 Q5) is not enforced by the example's commands; only sides, layers and spacing are. The tool's placement was accepted after the floorplan (handoff 18.32, `pins_floorplan.txt`). Task 067 (step 4b, `pin_replace.tcl`) was tried and PARKED (task 068), so the decided pin positions are the floorplan's (`pins_floorplan.txt`); that is what the top-level team gets.

## Open decisions (the user decides; NOT decided here)

- **D4** Power pins: one terminal per net on an interior `TOP_M` stripe (example behaviour), not the bottom-edge pins of handoff 18.21. Revisit after the first layout.
- **D5** Start utilisation 0.60 instead of the example's 0.85 (E6).
