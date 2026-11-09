# Calibre DRC, antenna and LVS for the clean-slate layout (task 066)

Nothing here has been run. The user runs it on the server, csh only, one command per line. Every item marked `VERIFY` is untested; they are collected at the end.

Input: `pnr_icc2/outputs/unpu_top_routed.gds`, written by `pnr_v2/pv.tcl` from the block `unpu_top_filled` (`write_gds -units 1000 -fill include -hierarchy all -long_names`, kit layer map, standard-cell GDS and the I/O pad GDS merged; handoff 18.32). About 59 MB (the old GDS without metal fill was 15.7 MB).
Base folder on the server: `/storage/EE5239G1/aagams_workspace2/unpu` (called BASE below). The three control files are in this repository folder `pnr_v2/calibre/`; they reach BASE with `git pull` after they are committed (Planning/user decide when), or copy them by hand.

Decks are the kit's, read-only: the working copy `/storage/EE5239G1/aagams_workspace/calibre_run/scr` (handoff 18.24) is the path the control files `INCLUDE`. If the old workspace `/storage/EE5239G1/aagams_workspace` is removed, copy that folder first and change the `INCLUDE` path in the three control files. No rule is disabled and no waiver is written.

## 1. Calibre environment (once per terminal; a SEPARATE terminal from icc2_shell, dc_shell, PrimeTime: the licence server differs, handoff 18.24)

```
tr -d '\r' < /home/Siemens_cshrc > ~/siemens_cshrc_clean
source ~/siemens_cshrc_clean
setenv MGC_HOME /home/mentor_tools/calibre/aok_cal_2022.4_37.20
setenv CALIBRE_HOME /home/mentor_tools/calibre/aok_cal_2022.4_37.20
set path = ( $MGC_HOME/bin $path )
rehash
which calibre
which v2lvs
calibre -version
```

Why: `/home/Siemens_cshrc` has CRLF line endings (hence the cleaned copy); the install path under `/home/MentorGraphics` has a space, so `MGC_HOME`/`CALIBRE_HOME` are set by hand (18.24). Expect `calibre` under `$MGC_HOME/bin`, version 2022.4_37.20. `which v2lvs` and `calibre -version`: `VERIFY V1`.

## 2. Run folders

Three folders under `pnr_icc2/calibre/run1/` (git-ignored with `pnr_icc2/`), one per check, so that the reports, databases and `svdb` of one check never overwrite another. Each check is run from its own folder.

```
cd /storage/EE5239G1/aagams_workspace2/unpu
mkdir -p pnr_icc2/calibre/run1/drc pnr_icc2/calibre/run1/ant pnr_icc2/calibre/run1/lvs
cp pnr_v2/calibre/drc.ctrl pnr_icc2/calibre/run1/drc/
cp pnr_v2/calibre/ant.ctrl pnr_icc2/calibre/run1/ant/
cp pnr_v2/calibre/lvs.ctrl pnr_icc2/calibre/run1/lvs/
ls -l pnr_icc2/outputs/unpu_top_routed.gds
ls /storage/EE5239G1/aagams_workspace/calibre_run/scr
```

The `ls` of the GDS must show about 59 MB; the `ls` of the deck folder must list `DRC_TS18SL_SCL_CALIBRE`, `ANTENNA_TS18SL_SCL_CALIBRE`, `LVS_TS18SL_SCL_CALIBRE` and `headers` (`VERIFY V2`: the LVS deck in the working copy).

## 3. Find the GDS top cell name (do this BEFORE the first run)

`LAYOUT PRIMARY` in the control files must equal the top cell name inside the GDS. The control files say `unpu_top`. Reason it should be right: the old GDS was written from blocks named `unpu_top_fill2`, `unpu_top_final2`, ... (made with `save_block -as`) and its top cell was `unpu_top`; the new block `unpu_top_filled` is made the same way. But `-hierarchy all -long_names` is new, and the name is `VERIFY V3`.

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1
strings -n 3 ../../outputs/unpu_top_routed.gds | grep -n "^unpu_top" > gds_names.txt
cat gds_names.txt
```

Read the list: the candidates are the names that begin with `unpu_top` (for example `unpu_top`, `unpu_top_filled`, or a long name). In a GDS written by ICC2 the top cell is normally written LAST among the design's own structures (children first), so the highest line number among the design names is the likely top cell (`VERIFY V4`; `strings` shows names, not which cell is instantiated by which). Two other ways to confirm, both `VERIFY V5`:

```
calibredrv -a layout peek ../../outputs/unpu_top_routed.gds -topcell
```

or run the DRC (step 4) and read the first lines of `drc.log`: Calibre stops with an error naming the primary cell it could not find.

If the name is not `unpu_top`, set it in the three COPIES in the run folders (not in the repository files; tell Planning the name so the repository files can be changed):

```
sed -i 's/^LAYOUT PRIMARY .*/LAYOUT PRIMARY "NAME"/' drc/drc.ctrl ant/ant.ctrl lvs/lvs.ctrl
```

(replace `NAME` by the cell name; the `SOURCE PRIMARY` line of `lvs.ctrl` is the top subckt of the SPICE file, step 7, and is not changed by this.)

## 4. DRC

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/drc
calibre -drc -hier drc.ctrl |& tee drc.log
```

Duration: the old GDS (15.7 MB) took about 160 s on 1 CPU (18.24; a later note in `docs/planning/backend-rerun-plan.md` says 45 s, the two disagree). The new GDS is about 4 times larger because of the metal fill, so expect several minutes up to roughly 10 to 15 minutes (`VERIFY V6`: scaling is a guess; fill shapes are flat polygons and may cost more than linearly). Ctrl-C kills it; do not interrupt.

What to look for:

```
grep -n "TOTAL RULECHECKS EXECUTED\|TOTAL RESULTS GENERATED" drc.log unpu_top.drc.rpt
grep "TOTAL Result Count" unpu_top.drc.rpt | grep -v "= 0 "
grep -n -i "error" drc.log
grep -n -A40 "ORIGINAL LAYER STATISTICS" drc.log
```

- `TOTAL RULECHECKS EXECUTED` must be 404 (old runs, 18.24 to 18.27). A different number means a different deck or switch set.
- `TOTAL RESULTS GENERATED`: 0 in every old run, but those layouts had NO metal fill and no pad GDS. Any non-zero result is new: note the rule names (second command) and the cell/coordinates in `unpu_top.drc.db` (ASCII). The text `TOTAL Result Count` is the expected report wording (`VERIFY V7`); if the second command prints nothing, read `unpu_top.drc.rpt` by eye.
- The layer statistics: every layer line (`WN GC AA CS M1 M2 M3 V2 V3 MTOP VTOP PRBoundary`) must be non-zero. If one is zero, the layer map or the top cell is wrong. Old counts (18.24) are not comparable now (fill adds shapes).
- `grep -i error`: the old traps were `ERROR USER1 ... PLEASE SELECT VOLTAGE OPTION` (switch missing) and `Rule file precision 1000 is not consistent with database precision 10000` (GDS written without `-units 1000`; `pv.tcl` has it).
- Still an assumption (18.24): the voltage option `3V`, BLOCK mode only, no DUMMY/density runset.

## 5. Antenna

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/ant
calibre -drc -hier ant.ctrl |& tee ant.log
```

The command line of the old antenna run is not recorded in the handoff; this is the DRC form with the antenna control file (`VERIFY V8`). Old duration: about 5 s on the 15.7 MB GDS (`backend-rerun-plan.md`); a few tens of seconds now.

What to look for:

```
grep -n "TOTAL RULECHECKS EXECUTED\|TOTAL RESULTS GENERATED" ant.log unpu_top.ant.rpt
grep "TOTAL Result Count" unpu_top.ant.rpt | grep -v "= 0 "
grep -n NETNAME unpu_top.ant.db
ls antenna_results.ant
```

- 16 rules (`AN.*`) is the old count. Results by rule name: `AN.MTL.1.M1`, `.M2`, `.M3` and `.MT` (top metal) are the layers. Old limit: ratio 400, no diode, top metal weighted 0.84 against 0.54 for M2 (18.27).
- Each result carries a `VALUE` (the ratio) and, once the pin label sits on the right layer, `NETNAME=<port>` (18.27: `paddr[4]`). Without `NETNAME` only a net number is printed: that is the same text-label problem as in LVS (step 7).
- ICC2's own count in the last route was 76 antenna violations (18.32); Calibre decides. The old deck found port nets (input ports have no diffusion in the macro and ICC2 skipped them, `ZRT-311`).
- The deck may also write `antenna_results.ant` (it was in the old run folder, 18.26); where it comes from is not documented (`VERIFY V9`).
- `pnr_v2/fix_antenna.tcl` reads the antenna database from `BASE/pv/drc/unpu_top_antenna_bkp.db` (edit E11). After a run with results, put the ASCII database there:

```
mkdir -p /storage/EE5239G1/aagams_workspace2/unpu/pv/drc
cp unpu_top.ant.db /storage/EE5239G1/aagams_workspace2/unpu/pv/drc/unpu_top_antenna_bkp.db
```

The script parses lines `AN.<rule>` and `p <id> <nverts>` followed by vertex lines, dividing coordinates by 1000 (database units of `-units 1000`). Check the format first: `grep -c "^p " unpu_top.ant.db` must be non-zero when there are results (`VERIFY V10`).

## 6. LVS: the deck switches (settled by the first real run, 2026-11-09)

The first LVS run on the server ended `CORRECT` (44,615 nets and 67,472 instances matched, all 204 signal ports and `VDD`/`VSS` matched by name) with `pnr_v2/calibre/lvs.ctrl` as it is now. The copy used on the server needed exactly two changes to the file written in task 066, and both are made in the committed file:

1. The two lines `VIRTUAL CONNECT COLON NO` and `VIRTUAL CONNECT REPORT NO` are gone. Calibre stopped with error `SPC1` "superfluous specification statement: virtual connect colon", because the LVS deck sets it itself (deck line 257). The rule for any statement of `lvs.ctrl`: if Calibre reports a duplicate or superfluous statement, delete it from the COPY in the run folder, never edit the deck. The same two lines are correct in `drc.ctrl` (that deck does not set them).
2. `#define FILTER_DWN2PSUB` is added after `#define 4M1L`. Reason (written, user approved 2026-11-09): the layout has one extra device `D(DWN2PSUB)`, an N-well to P-substrate diode (the report says "76 parallel layout diodes were reduced to 1"), from the N-well of the `feedth`, `feedth3`, `feedth9` filler cells. It is a parasitic junction with no schematic equivalent, and the kit CDL defines the three fillers as EMPTY subcircuits, so the source netlist cannot carry it. Without the switch the report is `INCORRECT` with "Different numbers of instances" and ONE incorrect instance (`X8/D5(19.700,19.700) D(DWN2PSUB)`, "missing instance"); everything else already matched. The deck provides `FILTER_DWN2PSUB` for exactly this (`LVS FILTER D(dwn2psub) OPEN`, deck lines 4016 to 4018). The other switch of the deck, `BLOCK_DWN2PSUB` (switches the extraction of that device off), was NOT used.

Facts about the deck found in the run:

- The metal-level switch `#define 4M1L` is enough: the deck maps it to its `4LM` setting. No other `#define` was needed.
- The deck already sets `LVS POWER NAME` (`VDD`, `vdd`, `VCC`, ...) and `LVS GROUND NAME` (`GND`, `gnd`, `VSS`, ...), `LVS GLOBALS ARE PORTS YES`, `LVS COMPARE CASE NO`. `lvs.ctrl` does not set them (do not add them).
- The deck reads the pin text labels correctly: the signal ports are matched by name in "Initial Correspondence Points", although `write_gds` prints `GDS-017` for line 8 of the kit layer map.

To print the deck lines again (for a new deck or a new switch):

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/lvs
grep -n -i "#ifdef\|#ifndef\|#define\|MUST\|ERROR" /storage/EE5239G1/aagams_workspace/calibre_run/scr/LVS_TS18SL_SCL_CALIBRE | head -60
grep -n -i "^ *LVS REPORT\|^ *SOURCE \|^ *LAYOUT \|^ *LVS POWER\|^ *LVS GROUND\|^ *MASK SVDB\|VIRTUAL CONNECT\|DWN2PSUB" /storage/EE5239G1/aagams_workspace/calibre_run/scr/LVS_TS18SL_SCL_CALIBRE | head -60
```

LVS, DRC and antenna must ALL be re-run after every change of the layout or the netlist: steps 6c, 6d and 6e of `pnr_v2/README.md`, any ECO, any new `pv.tcl` run. A result is valid only for the GDS and the netlist it was run on.

## 7. LVS: source netlist and run

Source: `pnr_icc2/outputs/unpu_top_pnr_pg.v`, written by `pv.tcl` with PG pins; `pv.tcl` has already renamed `N<digits>` nets to `N_uc_<digits>` with `sed` so a case-insensitive compare never merges `N33` with `n33`. Check it, then convert with `v2lvs` against the kit CDL (18.24).

```
grep -n "^module unpu_top" ../../../outputs/unpu_top_pnr_pg.v
grep -c "N_uc_" ../../../outputs/unpu_top_pnr_pg.v
grep -c "1'b[01]" ../../../outputs/unpu_top_pnr_pg.v
ls -l /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/cdl/scl18fs120_supply_pins.cdl
v2lvs -h
```

- The first line must show the top module `unpu_top`; the second count is non-zero when nets named `N<digits>` existed.
- The third count shows whether constants are written as `1'b0`/`1'b1` (non-zero) or as `VSS`/`VDD` connections (zero). The library has no tie cells and ICC2 tied 129 gate pins directly to `VSS` (handoff 18.19 and `backend-rerun-plan.md` E3). The `-s0 VSS -s1 VDD` mapping of the next command is only needed when this count is non-zero; when it is 0 the options do nothing and can stay.
- `v2lvs -h` prints its options; the command below worked as written in the first run.

```
v2lvs -v /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/outputs/unpu_top_pnr_pg.v -s /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/cdl/scl18fs120_supply_pins.cdl -s0 VSS -s1 VDD -o unpu_top.sp |& tee v2lvs.log
grep -n -i "^\.subckt unpu_top" unpu_top.sp
grep -n -i "error\|warning\|not found\|undefined" v2lvs.log
```

Read `v2lvs.log`: every cell master of the netlist must be found in the CDL (an "undefined"/"not found" master means the CDL does not hold it; fillers are not in the source netlist by design). The top subckt line must be `unpu_top` (it is `SOURCE PRIMARY` in `lvs.ctrl`). The many "No module declaration" warnings for the library cells are NORMAL: the netlist has no module for a library cell, and the pin order of each cell comes from the CDL (`-s`).

```
calibre -lvs -hier lvs.ctrl |& tee lvs.log
```

`-hier` worked without `-hcell` or `-automatch` in the first run. If a future log says a cell-match list is needed, add `-automatch`; if hierarchical LVS reports cell-name mismatches between layout and source, flat LVS (without `-hier`) is the fallback, that is the user's decision. The control file used must be the committed `pnr_v2/calibre/lvs.ctrl` (it holds the `FILTER_DWN2PSUB` switch and no `VIRTUAL CONNECT` lines, section 6).

## 8. LVS: what to read first in the report

```
grep -n "LVS completed" lvs.log
grep -n "CORRECT" unpu_top.lvs.rpt | head
grep -n -i "discrepanc" unpu_top.lvs.rpt | head -40
grep -n -i "error" lvs.log
```

What the first real run showed (the structure of the report is now known):

1. `lvs.log` ends with `LVS completed. CORRECT. See report file: unpu_top.lvs.rpt` (the line was `LVS completed. INCORRECT.` before the `FILTER_DWN2PSUB` switch). The report starts with `OVERALL COMPARISON RESULTS` and a `CELL SUMMARY` row `CORRECT unpu_top unpu_top`.
2. `NUMBERS OF OBJECTS AFTER TRANSFORMATION`: layout and source equal. Real values of the first run: 44,615 nets and 67,472 instances matched on both sides (CORRECT run). The "INITIAL NUMBERS OF OBJECTS" differ (layout 94,123 nets against source 94,506, transistors counted before reduction) and that is normal: the transformation reduces parallel and split-gate MOS the same way on both sides (6,692 layout and 5,911 source transistors reduced).
3. `Initial Correspondence Points` lists the nets matched by name: `VDD`, `VSS` and all 204 signal ports (printed in upper case, the compare is case-insensitive). This is how you see that the pin text labels are read; a label problem would show no or only `VDD`/`VSS` ports.
4. Benign messages: "Ambiguity points were found and resolved arbitrarily" and "22 isolated layout nets / 22 isolated source nets": these are the 22 unused `paddr` inputs (`PADDR[0]`, `[1]`, `[12]` to `[31]`; no load), identical on both sides. Also "119 source nets had all their pins removed", "21 nets were matched arbitrarily", "146 source nets were deep shorted to 6" (the power nets), the descriptor-limit warning at the top of the log.
5. Without `FILTER_DWN2PSUB` the report listed ONE incorrect instance, `D(DWN2PSUB)` "missing instance" (section 6); any OTHER incorrect object is a real discrepancy: the signal ports are found on both sides by name, so read the named nets in the discrepancy block and compare the instances and pins they connect.
6. If a run shows 0 ports, or only `VDD`/`VSS`, or generic net names, it is a label problem again (the layer map): report it to Planning, do not edit the deck.

## 9. Copy the results back (from a LAPTOP terminal, not from the server)

The user types the password at the prompt; nothing here contains it. `~/server_pull/calibre/run1/` is a new subfolder so the old `drc.ctrl` and `ant.ctrl` in `~/server_pull/calibre/` are not overwritten.

```
mkdir -p ~/server_pull/calibre/run1/drc ~/server_pull/calibre/run1/ant ~/server_pull/calibre/run1/lvs
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/gds_names.txt ~/server_pull/calibre/run1/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/drc/drc.log ~/server_pull/calibre/run1/drc/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/drc/unpu_top.drc.rpt ~/server_pull/calibre/run1/drc/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/drc/unpu_top.drc.db ~/server_pull/calibre/run1/drc/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/ant/ant.log ~/server_pull/calibre/run1/ant/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/ant/unpu_top.ant.rpt ~/server_pull/calibre/run1/ant/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/ant/unpu_top.ant.db ~/server_pull/calibre/run1/ant/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/lvs/v2lvs.log ~/server_pull/calibre/run1/lvs/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/lvs/lvs.log ~/server_pull/calibre/run1/lvs/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/lvs/unpu_top.lvs.rpt ~/server_pull/calibre/run1/lvs/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/calibre/run1/lvs/unpu_top.sp ~/server_pull/calibre/run1/lvs/
```

Also copy `antenna_results.ant` from the `ant` folder if `ls` found it, and the (edited) control files if any were changed in the run folders. Do not copy the `svdb` folder (large). `unpu_top.drc.db` and `unpu_top.ant.db` are small when there are no results and large when there are many.

## 10. Paths used

| Path | Where documented |
|---|---|
| `/storage/EE5239G1/aagams_workspace2/unpu` (BASE) | handoff 18.31, 18.32; `pnr_v2/README.md` D1 |
| `BASE/pnr_icc2/outputs/unpu_top_routed.gds` | CREATED by `pnr_v2/pv.tcl` (`OUT_DIR`, `DESIGN_NAME_routed.gds`); handoff 18.32 |
| `BASE/pnr_icc2/outputs/unpu_top_pnr_pg.v` | CREATED by `pnr_v2/pv.tcl` (`write_verilog`, then `sed`) |
| `BASE/pnr_icc2/calibre/run1/{drc,ant,lvs}` | CREATED by step 2 |
| `unpu_top.drc.db`, `.drc.rpt`, `.ant.db`, `.ant.rpt`, `.lvs.rpt`, `.sp`, `svdb`, logs | CREATED by the runs (names set in the control files / commands) |
| `BASE/pv/drc/unpu_top_antenna_bkp.db` | read by `pnr_v2/fix_antenna.tcl` (E11); CREATED by the `cp` in step 5 |
| `/storage/EE5239G1/aagams_workspace/calibre_run/scr/{DRC,ANTENNA,LVS}_TS18SL_SCL_CALIBRE` | handoff 18.24 (working copy of the kit decks; LVS deck present there: `VERIFY V2`) |
| `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/cdl/scl18fs120_supply_pins.cdl` | handoff 18.24 (relative part) plus the kit prefix of the sibling `gds/scl18fs120.gds` in `pnr_v2/pv.tcl`; existence of the full path `VERIFY V17` |
| `/home/Siemens_cshrc`, `/home/mentor_tools/calibre/aok_cal_2022.4_37.20` | handoff 18.24 |
| `~/server_pull/calibre/` | task 066 (local copy-back folder) |

## VERIFY list (what to look at to confirm)

| # | Item | Look at |
|---|---|---|
| V1 | `v2lvs` is on the path after step 1; `calibre -version` prints 2022.4_37.20 | the two lines after `rehash` |
| V2 | The LVS deck is in the working copy of the decks | `ls /storage/EE5239G1/aagams_workspace/calibre_run/scr` in step 2 |
| V3 | Top cell is `unpu_top` | `gds_names.txt` (step 3), `drc.log` first lines |
| V4 | The top cell is the last design-named structure in the GDS | compare `gds_names.txt` with V5 |
| V5 | `calibredrv -a layout peek <gds> -topcell` is a valid command | its output or error |
| V6 | DRC duration of 10 to 15 minutes | wall time of `drc.log` |
| V7 | Report wording `TOTAL Result Count` | `grep` output, else read `unpu_top.drc.rpt` |
| V8 | Antenna runs as `calibre -drc -hier ant.ctrl` | `ant.log` ends with the summary |
| V9 | `antenna_results.ant` is written by the antenna deck | `ls` in the `ant` folder |
| V10 | `unpu_top.ant.db` has the `AN.` and `p <id> <n>` format that `fix_antenna.tcl` parses | `grep -c "^p " unpu_top.ant.db` and its first lines |
| V11 | SETTLED (first run): the deck needs `#define 4M1L` (maps to `4LM`) and, for the filler N-well diode, `#define FILTER_DWN2PSUB`; it sets the power and ground names and `VIRTUAL CONNECT` itself; it reads the pin labels | section 6 |
| V12 | SETTLED by the result: 67,472 instances matched; the `-s0 VSS -s1 VDD` options are only needed when the netlist has `1'b0`/`1'b1` (the grep count of step 7) | the grep count in step 7 |
| V13 | SETTLED: `v2lvs -v -s -s0 -s1 -o` worked as written | `v2lvs.log` |
| V14 | SETTLED: `calibre -lvs -hier lvs.ctrl` worked without `-hcell`/`-automatch` | `lvs.log` |
| V15 | SETTLED: report structure and wording as in section 8 | `unpu_top.lvs.rpt` |
| V16 | SETTLED: the fillers have no devices, instance counts are equal (67,472); the only layout extra was the parasitic diode `D(DWN2PSUB)` of the filler N-wells, handled by `FILTER_DWN2PSUB` | the instance table of the report |
| V17 | The CDL file exists at the assembled full path | the `ls -l` in step 7 |
| deck switches | SETTLED: `#define 4M1L` and `#define FILTER_DWN2PSUB` are the switches; the `VIRTUAL CONNECT` lines of `drc.ctrl` must NOT be in `lvs.ctrl` (error SPC1); `LVS REPORT` and `MASK SVDB DIRECTORY` did not clash | `lvs.log` first errors |
| `3V` | the DRC voltage option stays an assumption (18.24) | not testable from the layout |
