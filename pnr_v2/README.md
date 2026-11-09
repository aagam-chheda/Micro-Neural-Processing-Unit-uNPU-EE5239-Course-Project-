# pnr_v2 -- the user's example ICC2 scripts, minimally edited for `unpu_top` (task 063)

Pristine originals: `docs/planning/reference-scripts-2026-11-02/` (do not edit; `sha256sum -c SHA256SUMS`).
Every edited line carries a `063` marker (`;# 063 En: ...` or a `# 063 En:` comment line), so `diff` shows exactly what changed.
Nothing here has been run: the user runs it on the server.

## Run order

Server folder (ASSUMED, decision D1): `/storage/EE5239G1/aagams_workspace2/unpu`, with this repo cloned there. Outputs go to `<BASE>/pnr_icc2/` (`blocks logs reports outputs`; git-ignored).
If the folder differs: `sed -i 's#/storage/EE5239G1/aagams_workspace2/unpu#<real path>#' pnr_v2/*.tcl`

| Step | Script | Tool |
|---|---|---|
| 0a | `build_ndm_std.tcl` | `icc2_lm_shell` |
| 0b | `build_ndm_filler.tcl` | `icc2_lm_shell` |
| 1 | `design_setup.tcl` | `icc2_shell` (needs `syn/out/legacy/unpu_top_cn.dc.v` and `.sdc` from the synthesis with the old constraints, next task) |
| 2 | `floorplanning.tcl` | `icc2_shell` |
| 3 | `powerplanning.tcl` | `icc2_shell` |
| 4 | `placement.tcl` | `icc2_shell` |
| 4b | `pin_replace.tcl` | PARKED (task 068, see "Why step 4b"): not part of the flow; it reads `_placement` and writes `_pinplace`, which `cts.tcl` no longer reads |
| 5 | `cts.tcl` | `icc2_shell` |
| 6 | `route.tcl` | `icc2_shell` |
| 6b | `fix_antenna.tcl` | `icc2_shell` (after the first Calibre antenna run; needs `<BASE>/pv/drc/unpu_top_antenna_bkp.db`) |
| 6c | `antenna_port_buffers.tcl` | `icc2_shell` (task 068: after `fix_antenna.tcl`, before `metal_fill.tcl`; a buffer next to the pin of each long INPUT PORT net, an ECO on the netlist; reads the same `unpu_top_antenna_bkp.db`, overwrites `_route` in place; `clk` is never buffered) |
| 6d | `antenna_clk_root.tcl` | `icc2_shell` (task 071: after `antenna_port_buffers.tcl`, before `metal_fill.tcl`; replaces the CTS root inverter on the `clk` port net by a larger inverter, a size-only ECO on one clock-tree cell; reads the same `unpu_top_antenna_bkp.db`, overwrites `_route` in place) |
| 6e | `timing_closure.tcl` | `icc2_shell` (task 072: after `antenna_clk_root.tcl`, before `metal_fill.tcl`; `route_opt` again with the same goals and options as `route.tcl`, the 15 `antbuf_*` buffers and the clock root protected, fillers removed during the pass and re-created; can resize cells and add hold buffers, so it changes the netlist; overwrites `_route` in place) |
| 6g | `pt_eco_apply.tcl` | `icc2_shell` (task 079: after `timing_closure.tcl`, before `metal_fill.tcl`; applies PrimeTime's own hold ECO (109 `insert_buffer` commands of `pt_eco_hold_changes_icc2.tcl`) and, if present, the setup ECO (`size_cell`), each new cell placed on a filler run next to its pin; the 15 `antbuf_*` buffers and the clock root protected; changes the netlist; overwrites `_route` in place) |
| 7 | `metal_fill.tcl` | `icc2_shell` |
| 8 | `pv.tcl` | `icc2_shell` (task 073: the LEF is the macro `unpu_top` only, from `create_frame` + `write_lef -include cell`, with hard checks; read the `>>> 073 LEF CHECK PASSED` line in the log, a `FAILED` line makes the run end with `ERROR 073`) |

Block chain: `_setup` -> `_floorplan` -> `_powerplan` -> `_placement` -> `_cts` -> `_route` -> `_filled` -> `_pv`.
PARKED (task 068): the chain with `_pinplace` between `_placement` and `_cts` (step 4b) is not used.

## Why step 4b (task 067) -- PARKED (task 068)

Result of the run (task 068): the second `place_pins` moved 196 of 204 pins but ignored the 8 um spacing (pitch 0.56 and 0.61 um), its legality check could not read its result, and the measured pin-to-load distances stayed 100 to 250 um for most nets, so it cannot fix the antenna problem. `pin_replace.tcl` stays in the repo unchanged and `cts.tcl` reads `_placement` again. The text below is kept as it was.

In the clean-slate run `floorplanning.tcl` places the 204 pins once, before any cell exists (`place_pins -self`); the tool filled each edge from both ends in alternating pairs, so for example `clk` is at offset 7.33 um (bottom of the right edge) and `rst_n` at 869.87 um (top) while the logic they drive sits near the middle.
After route, Calibre antenna reported 55 results and one round of `fix_antenna.tcl` left 50 and made setup worse; the nets it names are mostly input port nets (`pwdata[*]`, `psel`, `clk`, `rst_n`, `dma_rdata[9]`, `dma_rdata[11]`), which have no diode inside the macro, so the whole pin-to-gate wire counts against a gate area of about 0.19 um^2 (about 144 um of M3 or about 92 um of TOP_M per net).
Routing cannot shorten a net whose pin is far from its load, but pin position can: placing the pins after the cells are placed is the standard way to put each pin near its load.

`pin_replace.tcl` keeps the pin constraints of the floorplan untouched (same ports, sides, layers, spacing) and only lets the tool choose new positions along the same edges. Then it runs `place_opt` again with the same options as `placement.tcl`, `legalize_placement` and the same checks, and saves `_pinplace`. Pin-release method (plan A `place_pins -self` again, plan B `remove_terminals -force` on the 204 signal terminals only) and every check are in the script header and log.

### Run sequence for step 4b (csh, from the server; one command per line)

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2
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
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2
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
cd /storage/EE5239G1/aagams_workspace2/unpu
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

If `antenna_port_buffers.tcl` reports `0 usable candidates` or a net FAILED: run the read-only diagnostic `pnr_v2/diag_filler_runs.tcl` (task 070; net = `DIAG_NET` at its top, nothing is saved): `cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2`, then `icc2_shell -f ../pnr_v2/diag_filler_runs.tcl |& tee diag_filler_runs_console.log`, then `exit`.

### Step 6d: the `clk` antenna result (task 071)

After step 6c the only Calibre antenna result left is the `clk` port net (rule `AN.MTL.1.M3`): about 490 um of M3 from the pin to the CTS root inverter, whose input gate is only about 0.19 um^2 (ratio about 2,670 against 400). `antenna_clk_root.tcl` replaces that root inverter by a larger inverter of the same function and pins (a size-only ECO on one clock-tree cell; tell the PM): the gate area needed is perimeter x 0.54 / 400 x 1.10 (about 1.43 um^2 for the polygon of the last run), and the cell is the inverter with the smallest gate area that reaches it, chosen from the kit LEF. A buffer at the pin was rejected for the first try (it delays the whole clock tree). The script maps the polygon of the database to its net with the same functions as 6c and stops if the database holds anything but the clock-source port net.

One command per line (csh, from the server). The database is the one of the last Calibre antenna run (here `run2`; take the folder of the run that reported the `clk` result):

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2
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
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2
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

Why: PrimeTime is the sign-off and reads the I/O references at the clock pin with zero latency, so it found hold -0.3468 ns on 263 endpoints (255 flop D pins fed by `dma_rdata[*]` / `pwdata[*]`) and setup -0.2423 ns on `dma_addr[31]`. The user decided (2026-11-09) to fix the design to pass PrimeTime. PrimeTime's `fix_eco_timing -type hold` closed hold in its memory (263 -> 0, WNS +0.0002 ns) with 109 `insert_buffer` commands (`dl01d1` 64, `dl02d1` 31, `buffd1` 12, `dl01d2` 2; 2687.50 um^2). `pt_eco_apply.tcl` applies the same change list to `unpu_top_route`:

- the change file is parsed in Tcl (`current_instance {x}` sets the hierarchy of the following pins; an empty one resets to the top; `insert_buffer [get_pins {P}] REF -new_net_names {N} -new_cell_names {C}`; `insert_buffer [get_ports {PORT}] REF ...` for a top-level input port (5 of the 109 hold changes, `dma_rdata[14]` ...; only with an empty `current_instance`); `size_cell {INSTANCE} {REFERENCE}` as PrimeTime wrote it for the setup file: `size_cell {HFSINV_13_284} {inv0d7}`, braces optional, `[get_cells {I}]` accepted); any other line stops the script and is listed; nothing is changed before all pins, references (in `scl180_std`, not don't-use) and names (PrimeTime's `U_PTECO_HOLD_BUF<n>` / `net_PTECO_HOLD_NET<n>` are kept, a clash stops) are checked;
- DRIVER pin versus LOAD pin: a buffer on a driver pin (`U46/Z`, `U81/ZN`) takes ALL loads of that net, on a load pin (`dest_c_reg_reg_2_/D`, `copt_h_inst_3971/I`) it isolates that one load. After every insertion the leaf pins of both nets are compared with exactly that rule; any difference stops the script (nothing saved);
- PORT insertions (`get_ports`): the port stays on the net with the new cell's input and ALL loads move behind the new cell (as the antenna buffers of 6c); the topology rule `port` checks exactly that. The pin location is the port terminal (as `antenna_port_buffers.tcl`). The new cell must be within the tier-1 limit of 6c (`MAX_PIN_BUF_DIST`, read from `antenna_port_buffers.tcl`, not retyped) AND within the distance at which the predicted antenna ratio of the port wire (Calibre limit, M2/M3 weight, wire width, all read from `antenna_port_buffers.tcl`; input gate area of the cell from the LEF) stays under the limit. TIER 2 for ports (when no filler run works within tier 1): the distance at which the predicted ratio, computed with the TOP_M weight (0.84, the worst case; the Calibre ratio limit for tier 2 is 360, 10 percent under 400; both read from `antenna_port_buffers.tcl`) and the delay cell's OWN input gate area from the LEF, stays under the limit; for `dl01d1` (0.371 um^2) that is about 79 um. The limits per reference are printed before any change; a change placed in tier 2 prints `TIER 2`, the distance and the predicted ratio on its `CHANGE` line and is listed in the ANTENNA WATCH block with the figures. If the port already has an `antbuf_*`, the new cell goes BETWEEN the port and the `antbuf_*`: the script prints `CASE change n: port ... already has an antenna buffer`, the `antbuf_*` is not touched (reference, origin, orientation unchanged), and its input pin legitimately ends on a PrimeTime net: that single, verified move is printed as `EXPECTED protected pin move`; any other change of a protected cell fails;
- every new cell is placed on a free filler run NEXT TO the pin (tier 1 within 30 um, tier 2 within 120 um; the cell width is read from the LEF, the delay cells are wider than `buffd1`), verified at that site and retried with the next candidate (up to 5); a change that cannot be placed is listed as FAILED and the script ends with an error BEFORE routing;
- only the touched nets are re-routed (`route_eco -nets`, `route_detail -incremental`), fillers and `connect_pg_net` as in 6c;
- a change that cannot be placed after all tiers is FAILED with the reason: per tier the limit and what was found (no run within the limit, or the candidates with their rejection reasons), the nearest free run wide enough in the whole design with its distance, and the limit it exceeds; every later change that uses a pin of the cell that change should have created (for example change 106 on `U_PTECO_HOLD_BUF4/Z`, whose cell change 4 creates) is named as a knock-on instead of "pin not found";
- `ALLOW_PARTIAL` (default 0 = strict: any FAILED change ends the script, nothing saved). With `set ALLOW_PARTIAL 1` such a change is SKIPPED together with its dependants (tracked by the PrimeTime cell name), the script continues, prints a `SKIPPED CHANGES` block (change number, line in the change file, pin, reason, dependants), the count checks use applied = total - skipped (both printed) and the last line is `STAGE 6g COMPLETE (PARTIAL: N of T changes skipped: <numbers>)`, T counting all commands of the files read (hold file and setup file). All other hard checks are unchanged. A partial result is NOT what PrimeTime assumed: PrimeTime must be re-run on it (`pt_hold_ff.tcl`, `pt_setup_ss.tcl`) and a second ECO round may be needed;
- the hard checks (nothing is saved if one fails): `check_routes` DRC 0 and open nets 0, `check_legality` 0, the inserted cells equal the insertions of the change file (109 expected for the hold file; a file with another number stops at the start), every inserted cell has the reference PrimeTime wrote, the protected cells (15 `antbuf_*` + the clock root) are identical to their snapshot, 15 `antbuf_*` cells;
- ANTENNA WATCH: every inserted cell whose net is driven by an input port or by the output of an `antbuf_*`, and every insertion on a port (`kind=port`, with the input gate area, the predicted ratio, the distance limit and, for the antbuf case, whether the new cell is closer to the port pin than the `antbuf_*`) is listed with the net and the distances. Calibre decides afterwards; none is skipped;
- timing is REPORTED before and after (`report_global_timing`, WNS/TNS/violations per scenario), not tuned. ICC2's view of the I/O paths is more lenient than PrimeTime's; PrimeTime is the sign-off.

Order on the server (the setup probe first, because its change file is the optional second input):

1. PrimeTime, `pnr_icc2/pt` (see `pnr_v2/pt/README.md` sections 8 and 9): `pt_shell -f ../../pnr_v2/pt/pt_eco_setup_probe.tcl |& tee pt_eco_setup_probe.log` produces `pt_eco_setup_changes_icc2.tcl`; `pt_eco_hold_changes_icc2.tcl` exists from the hold probe. Both files stay in `pnr_icc2/pt/`.
2. ICC2, one command per line (csh):

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2
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

## Decided (user, 2026-11-02)

- **D1** BASE path `/storage/EE5239G1/aagams_workspace2/unpu` is right (no change to the scripts).
- **D2** `HOLD_SLACK_GOAL` and `SETUP_SLACK_GOAL` are 0.0 in `cts.tcl` and `route.tcl` (task 065; the example had 0.70 and 0.3/0.30), so the optimiser sees exactly the course constraints (setup 1.5, hold 0.5). Lines marked `065`.
- **D3** Pin ORDER (bits ascending, handoff 18.9 Q5) is not enforced by the example's commands; only sides, layers and spacing are. The tool's placement was accepted after the floorplan (handoff 18.32, `pins_floorplan.txt`). Task 067 (step 4b, `pin_replace.tcl`) was tried and PARKED (task 068), so the decided pin positions are the floorplan's (`pins_floorplan.txt`); that is what the top-level team gets.

## Open decisions (the user decides; NOT decided here)

- **D4** Power pins: one terminal per net on an interior `TOP_M` stripe (example behaviour), not the bottom-edge pins of handoff 18.21. Revisit after the first layout.
- **D5** Start utilisation 0.60 instead of the example's 0.85 (E6).
