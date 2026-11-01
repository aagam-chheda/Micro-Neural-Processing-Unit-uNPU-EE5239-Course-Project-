# pnr/ -- scripted place-and-route flow (re-run plan: `docs/planning/backend-rerun-plan.md`)

One script per stage; every stage starts from a named checkpoint block and ends by saving a new one.
The scripts are written for the SCL 180 nm kit and ICC2 U-2022.12-SP3; nothing here is run on the laptop
except `test_common.tcl`. The user runs the stage scripts on the server and reads the logs.

## Scripts and order

| # | Script | Runs in | Status |
|---|---|---|---|
| 0 | `params.tcl`, `common.tcl` | sourced by every script (plain `tclsh` can source them) | written (task 038) |
| 1 | `ndm_file_gen.tcl` | `icc2_lm_shell` of U-2022.12-SP3 (full path, see below) | written (task 038) |
| 2 | `ndm_check.tcl` | `icc2_shell` | written (task 038) |
| 3 | `design_setup.tcl` | `icc2_shell` | written (task 039) |
| 4 | `floorplan.tcl` | `icc2_shell` | written (task 040) |
| 5 | `power.tcl` | `icc2_shell` | written (task 041) |
| 6 | `pin_place.tcl` | `icc2_shell` | written (task 048): coarse placement, tool-placed pins (sides and layers fixed per group), geometry checks, `pin_order.txt` for the top level; saves `pins` |
| 7 | `placement.tcl` | `icc2_shell` | written (task 049): `place_opt`, checks, report of the input-port wires (`placed_port_report.csv`, report only); opens `pins`, saves `placed` |
| 8 | `cts.tcl` | `icc2_shell` | written (task 043) |
| 9 | `route.tcl` | `icc2_shell` | written (task 044) |
| 10 | `fill.tcl` | `icc2_shell` | written (task 045): last ICC2 step; opens `routed`, saves `final` (filled) |
| 11 | `outputs.tcl` | `icc2_shell` | written (task 046): netlists, LEF, SPEF/SDF/SDC (both corners), GDS from `final`, then checks every file; saves no block |
| - | `help_probe.tcl` | `icc2_shell`, bare shell | written (task 042): prints `-help` of the commands the flow uses |
| - | `help_probe_lm.tcl` | `icc2_lm_shell` (full path) | written (task 042) |
| - | `test_common.tcl` | `tclsh`, local | written (task 038) |

Then the Calibre and PrimeTime scripts (later tasks). The checkpoint block names (`BLK_*`) are in `params.tcl`.

The library manager must be the one that matches `icc2_shell`:
`/home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell`. The bare name `icc2_lm_shell` finds Fusion Compiler
V-2023.12-SP4 (`docs/session-handoff.md` 18.10). Both scripts check the release string and stop if it differs.

## Environment variables (csh: `setenv NAME value`)

| Variable | Default | Meaning |
|---|---|---|
| `SCL_KIT_ROOT` | server kit root (`params.tcl`) | kit root; never written to |
| `UNPU_WORK` | `.../icc2_work_v2` (`params.tcl`) | work directory, outside the repo |
| `UNPU_RUN_TAG` | `run1` | run name: one directory per run under `UNPU_WORK` |
| `UNPU_NETLIST`, `UNPU_SDC` | `syn/out/pm_flow/unpu_top_cn.dc.v`, `.sdc` in the repo clone | DC outputs (untracked) |
| `UNPU_NDM_MODE` | `two` | `two` (main NDM + a second NDM with the three fillers) or `single`; `single` does NOT work on this kit (`LM-052` skips the 6 LEF-only cells, 0 of 3 fillers, `single_mode_worked = no`); anything else is an error |
| `UNPU_NDM_OVERWRITE` | unset | `1` allows `ndm_file_gen.tcl` to replace an existing NDM (it warns for each path removed) |
| `UNPU_LIB_OVERWRITE` | unset | `1` lets `design_setup.tcl` remove an existing design library `$LIB_DIR/$LIB_NAME` (it warns); otherwise an existing library stops the script |
| `UNPU_BLK_<NAME>` | the default of `BLK_<NAME>` | override of a checkpoint block name; `<NAME>` is IMPORT FP PWR PINS PLACED CTS CLKOPT ROUTE_AUTO ROUTED or FINAL (letters, digits, `_`); a Warning is printed for each. Lets several experiments (for example hold uncertainties: `clkopt`, `clkopt_h02`) live in one library |
| `UNPU_CTS_STAGE` | `all` | `cts.tcl`: `all` (tree, then hold optimisation), `tree` (stops after saving `cts`), `hold` (opens the saved `cts` block, applies `UNPU_HOLD_UNCERT`, optimises, saves `clkopt`); in the manifest as `CTS_STAGE` |
| `UNPU_OUTPUTS_OVERWRITE` | `0` | `1` lets `outputs.tcl` delete and rewrite output files that exist (a Warning per file); otherwise an existing target stops the script |
| `UNPU_GDS_LAYER_MAP` | the kit map | path of a corrected GDS layer map used by `outputs.tcl` instead of the kit map (Warning; in the manifest) |
| `UNPU_PIN_SIDE_RIGHT`, `UNPU_PIN_SIDE_TOP` | `3`, `2` | side numbers of the pin placer for the right (APB) and top (DMA) pin groups; the defaults are a GUESS (1 left, 2 top, 3 right, 4 bottom clockwise from the left) that `pin_place.tcl` checks and, if wrong, names the numbers to try; positive integers, different |
| `UNPU_FILL_ECO` | `0` | `1` lets `fill.tcl` run `route_eco` once if fillers with violations remain (then repeats the check; never a second round) |
| `UNPU_ROUTE_ACCEPT_HOLD` | `0` | `1` lets `route.tcl` save the routed block although hold violations remain (the hold check only, and only if the count is known); records `hold_accepted = 1` and the endpoints in the manifest. Never set it without a written reason |
| `UNPU_SKIP_VERSION_CHECK` | unset | `1` continues when the tool release cannot be read or differs; prints a Warning. Read the banner first |
| `UNPU_ICC2_ROOT` | `/home/Synopsys_tools/icc2/U-2022.12-SP3` | ICC2 installation matching `icc2_shell` |
| `UNPU_DIE_SIZE`, `UNPU_HOLD_UNCERT` | `868.0`, `0.5` | experiment knobs only (plan A2 and X1: die 817.6, hold 0.2); the defaults are the plan's values |

## Directory layout (all derived in `params.tcl`)

```
$UNPU_WORK/ndm/                 the NDM(s), feedth.lef, ndm_manifest.txt   (shared by all runs)
$UNPU_WORK/$UNPU_RUN_TAG/
    logs/    stage logs and manifest_<stage>.txt
    lib/     the design library
    out/     netlists, LEF, GDS, SPEF, SDF, SDC
    rpt/     reports
    calibre/ Calibre runs
```

## Messages (the same in every script, so a summary script can grep them)

```
Info: [unpu] <text>                               Warning: [unpu] <text>        Error: [unpu] <text>   (then exit 1)
Info: [unpu] RESULT <stage> <key> = <value>       the numbers a reader needs
Info: [unpu] CHECK <stage> <name> PASS|FAIL <detail>
```

## Rules

- Every stage starts from a named checkpoint (`unpu_open_stage`) and ends with `unpu_checkpoint <new name>`; the
  earlier block on disk is never touched, so any stage can be re-run from the one before.
- Every stage writes `manifest_<stage>.txt` (date, user, host, script, git revision, tool version, every
  parameter, SHA-256 of the input files). Nothing in it is typed by hand.
- Nothing fails silently: a missing input, a wrong tool release or a failed check prints `Error: [unpu]` and exits 1.
- Every number is a named parameter in `params.tcl` with its source; no value is changed without Planning.
- Kit files are read-only. Never use `$FOUNDRY` or anything under `/home/Cadence_tools/FOUNDRY` (a generic
  TSMC-style kit, not SCL).
- Tool commands not shown in the handoff carry a `VERIFY` comment in the script; check them against `<cmd> -help`
  or the first log before relying on them.

## Local test

```
UNPU_TEST_TMP=<scratch dir> tclsh pnr/test_common.tcl
```
