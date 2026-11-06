# Task 038 — back-end re-run, script 1: shared parameters and helpers, and the NDM library generator (with filler cells)

First of a sequence of tasks that turn the hand-typed back-end flow into one script per stage (plan:
`docs/planning/backend-rerun-plan.md`, read all of it first). Each later task adds one stage script; they all use
the two shared files you write here, so get those right.

## Goal

Write `pnr/params.tcl` and `pnr/common.tcl` (shared by every stage script), the NDM generator
`pnr/ndm_file_gen.tcl` that puts the **filler cells into the library at generation time** (the first run had to
build a second library later), and the checker `pnr/ndm_check.tcl`.

## Context you must read first

- `docs/session-handoff.md` 18.1 to 18.4 (flow, kit paths, server setup), 18.10 (how the NDM was built), 18.22
  (how the filler library was built, and what went wrong), 18.11 to 18.13 (library creation, so the parameter
  names you choose fit the next scripts).
- `syn/dc_setup.tcl` and `syn/dc_run.tcl`: the style to follow (the `unpu_die` helper, `Info:`/`Warning:`/
  `Error:` lines with the `[unpu]` tag, paths from `[info script]`, the kit root default plus environment
  override, no fallbacks).
- Facts from the first run that you must build in, not rediscover:
  - The ICC2 library manager must be the one that matches `icc2_shell`: `/home/Synopsys_tools/icc2/U-2022.12-SP3/
    bin/icc2_lm_shell`. The bare name `icc2_lm_shell` finds Fusion Compiler V-2023.12-SP4, whose NDM may not open
    in the older `icc2_shell`.
  - `commit_workspace` writes the NDM into the directory where the library manager was started.
  - Main library recipe (18.10): `create_workspace -flow normal -technology <SCL_4LM.tf> scl18fs120`;
    `read_lef <scl18fs120_std.lef>`; `read_db` of the ss and the ff `.db` (library names `tsl18fs120_scl_ss`,
    `tsl18fs120_scl_ff`); `check_workspace`; `commit_workspace`. Result then: 534 cells = the 534 cells of the `.lib`.
    The kit LEF has 540 MACROs; the six LEF-only cells (no timing view) are `feedth`, `feedth3`, `feedth9`,
    `mx08d1`, `mx08d2`, `mx08d4`. They were NOT in the NDM.
  - Filler recipe (18.22): the fillers are `feedth` (1 site), `feedth3` (3), `feedth9` (9). A LEF holding only
    their three MACROs was cut from the kit LEF, built with `create_workspace -flow physical_only`; the cells
    must be typed **filler** (`foreach_in_collection c [get_lib_cells] {set_attribute $c design_type filler}`,
    done in the library manager BEFORE `check_workspace` and `commit_workspace`; it cannot be set in
    `icc2_shell`, `ATTR-25`). Cells left typed `lib_cell` gave `CHF-011` and `CHF-010` in
    `create_stdcell_fillers`.
  - Benign library-manager messages seen: `TECH-001`, `LEFR-064`, `FRAM-066`. Print them, do not suppress them.
- Standing rules: nothing fails silently; nothing hardcoded (every number a named parameter with its source in a
  comment); no fallbacks that hide a missing input; never use `$FOUNDRY` or anything under
  `/home/Cadence_tools/FOUNDRY` (a generic TSMC-style kit, not SCL); kit files are read-only (never write into the
  kit directory); no value from the plan is changed without Planning.

You cannot run any Synopsys tool here (they are on the server only). Write the scripts, check them statically as
Part B says, and give the user a server block (Part C). The user runs it and pastes the logs back.

## Part A — what to write

### A1. `pnr/params.tcl` — every parameter of the whole back-end flow, in one place

A file of `set` commands (and the few derived values), no tool commands, no file access at source time (so it can
be sourced by plain `tclsh`). Each parameter has a comment with its meaning and its source (handoff section, kit
file, or "plan"). Groups and defaults:

- **Environment overrides** (same pattern as `syn/dc_setup.tcl`): `SCL_KIT_ROOT` (default
  `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180`), `UNPU_WORK` (default
  `/storage/EE5239G1/aagams_workspace/icc2_work_v2`), `UNPU_RUN_TAG` (default `run1`). `REPO_ROOT` is derived from
  the location of the script that sources params.tcl (it must work when sourced from any `pnr/*.tcl`).
- **Directory layout** (all derived from the three above): `NDM_DIR = $UNPU_WORK/ndm` (shared by all runs);
  `RUN_DIR = $UNPU_WORK/$UNPU_RUN_TAG`, with `LOG_DIR = $RUN_DIR/logs`, `LIB_DIR = $RUN_DIR/lib` (the design
  library), `OUT_DIR = $RUN_DIR/out`, `RPT_DIR = $RUN_DIR/rpt`, `CALIBRE_DIR = $RUN_DIR/calibre`.
- **Kit inputs** (built from `SCL_KIT_ROOT`; the directory under `stdcell/fs120/` really is spelled `4M1IL`, the
  one under `digital_pnr_kit/snps/non_rh/` is `4M1L`): technology file `SCL_4LM.tf`; TLUPlus
  `SCL_TLUPLUS_4M1L_TYP.tlup` and map `SCL_TLUPLUS_4M1L.map`; `scl18fs120_std.lef`; the ss and ff `.db`
  (`lib_flow_ss/tsl18fs120_scl_ss.db`, `lib_flow_ff/tsl18fs120_scl_ff.db`) and their library names; the standard-cell
  GDS `stdcell/fs120/4M1IL/gds/scl18fs120.gds`; the GDS layer map `icc_gds_out_4LM.map`; the CDL files under
  `stdcell/fs120/4M1IL/cdl/` (both `scl18fs120_supply_pins.cdl` and `scl18fs120_scl_no_supply_pins.cdl`).
- **Design inputs**: `NETLIST = $REPO_ROOT/syn/out/pm_flow/unpu_top_cn.dc.v` and `SDC_FILE =
  $REPO_ROOT/syn/out/pm_flow/unpu_top_cn.sdc` (these are untracked DC outputs that exist in the user's server
  clone; each overridable by an environment variable), `TOP_NAME unpu_top`.
- **Names**: library `LIB_NAME unpu2_lib`; NDM workspace name `scl18fs120`; the filler cell list `FILLER_CELLS
  {feedth feedth3 feedth9}`; the checkpoint block names, one per stage, as variables: `BLK_IMPORT unpu_top`,
  `BLK_FP fp`, `BLK_PWR pwr`, `BLK_PINS pins`, `BLK_PLACED placed`, `BLK_CTS cts`, `BLK_CLKOPT clkopt`,
  `BLK_ROUTED routed`, `BLK_FINAL final`.
- **Floorplan** (plan 2.2): `DIE_SIZE 868.0`, `CORE_OFFSET 5.6`, `ROW_HEIGHT 5.6`, `SITE_WIDTH 0.56`. Derived and
  checked at source time (die with a message, not silently): core side = DIE_SIZE − 2·CORE_OFFSET; the core side
  divided by ROW_HEIGHT is an integer (row count) and DIE_SIZE divided by SITE_WIDTH is an integer. Use a small
  tolerance for the floating-point test and print the derived values (core side, rows, core area). The floorplan
  boundary for `initialize_floorplan` is `{{CORE_OFFSET CORE_OFFSET} {DIE−CORE_OFFSET DIE−CORE_OFFSET}}`.
- **Timing**: `HOLD_UNCERT 0.5` (plan: back to the SDC value; comment that the SDC labels it an assumption and that
  the user chose it on 2026-11-01). Do not add a setup parameter (it stays 1.5 in the SDC).
- **Don't-use**: `DONT_USE_PATTERNS {slnht* skbrb* slbhb* slnhn* slnln* mx08d*}` on ONE line in this exact form
  (same list as `syn/dc_setup.tcl:39`); note in a comment that three more cells (`adiode`, `bh01d1`, `cload1`) are
  flagged `dont_use` by the library itself and that `adiode` cannot be used.
- **Power grid** (18.15, 18.21): M1 rail width 0.74; TOP_M stripe width 2.24, pitch 112, VDD/VSS interleaved;
  `PG_PIN_HEIGHT 6.0` (height of the extension shape at the bottom boundary).
- **Pins** (plan 2.2): `PIN_WIDTH 0.28`, `PIN_LENGTH 1.0`, `PIN_PITCH 6.72` (minimum), right-edge layer `M3`,
  top-edge layer `M2`; port groups as lists: right edge = `paddr[*] pwdata[*] prdata[*] pwrite psel penable
  pready clk rst_n`; top edge = `dma_addr[*] dma_wdata[*] dma_rdata[*] dma_wstrb[*] dma_valid dma_ready`.
- **CTS**: `CTS_EXCLUDE_PATTERN */dl*` (the 12 delay cells, kept for hold fixing).
- **Antenna** (plan 2.3 D3): `ANT_MODE 4`, `ANT_DIODE_MODE 1`, `ANT_CUT_RATIO 0`, `ANT_RATIO 300`; and
  `ANT_CALIBRE_LIMIT 400` (informational: the foundry limit; comment why ICC2 uses 300); `HPWL_DETOUR 1.2`.
- **Fill**: `FILLER_PATTERN */feedth*`, `FILLER_PREFIX FILLER`.
- **Outputs**: GDS database units `GDS_UNITS 1000` (comment: the Calibre rule precision is 1000; without it the
  deck stops with a precision error).
- **Expected facts** (checks, not inputs), each with its source: `EXPECT_TIMING_CELLS 534` (18.10),
  `EXPECT_LEF_MACROS 540` (18.10), `EXPECT_PORTS 204`, `EXPECT_SEQ_CELLS 2465` (18.12).
- **NDM mode**: `NDM_MODE` from `$::env(UNPU_NDM_MODE)`, default `single`; allowed `single` or `two`; anything else
  is a loud error (see A3).

### A2. `pnr/common.tcl` — shared procedures

Pure Tcl at source time (no Synopsys command may run when the file is sourced); procedures that call tool commands
are only defined, not executed.

- `unpu_die msg` (prints `Error: [unpu] msg`, exits 1), `unpu_warn msg`, `unpu_info msg`.
- `unpu_result stage key value`: prints exactly `Info: [unpu] RESULT <stage> <key> = <value>`. Every stage script
  uses it for the numbers a reader needs, so a later summary script can grep them.
- `unpu_need_file path what` (die if missing, naming `what`), `unpu_ensure_dir path`.
- `unpu_sha256 file`, `unpu_git_rev` (short commit of `REPO_ROOT`, plus `+dirty` if `pnr/` has uncommitted
  changes; `unknown` plus a warning if git is unavailable), `unpu_manifest stage files` writing
  `$LOG_DIR/manifest_<stage>.txt`: date, user, host, script path, git rev, the tool version string, every parameter
  of params.tcl (name = value), and the checksum of each file in `files`. Nothing in it may be hand-typed.
- `unpu_extract_lef_macros lef names outfile`: writes `outfile` containing the LEF header (everything before the
  first `MACRO`), then each requested MACRO block (`MACRO <name>` through `END <name>`), then `END LIBRARY`. It
  dies unless every requested name is found exactly once, and returns the number of blocks written. Pure Tcl.
- Tool procedures (defined, VERIFY comments on every tool command not shown in the handoff):
  `unpu_stage_begin stage` (source params, create the directories, write the manifest, make the shell stop on error
  as in `syn/dc_run.tcl`), `unpu_open_stage lib_dir lib_name block` (`open_lib`, `open_block`),
  `unpu_checkpoint new_name` (the pattern that worked: `save_block -as <new>`, then `close_blocks -force`, then
  `open_block <new>`; `save_block -as` keeps the old in-memory name, so reopening is what makes the new block the
  current one, and the old block on disk stays untouched), `unpu_check_pass stage name cond detail` (prints
  PASS/FAIL, dies on FAIL).

### A3. `pnr/ndm_file_gen.tcl` — runs in `icc2_lm_shell`

Header: purpose, exact run command in csh (using the full path to the library manager), where outputs go, what it
needs. Behaviour:

1. Checks before doing anything: the shell is the library manager of U-2022.12-SP3 (read the version string; die
   otherwise, naming what was found; VERIFY how the version is exposed); params load; all kit files exist
   (`unpu_need_file`); `NDM_MODE` valid. Never overwrite an existing NDM silently: if the target exists, die unless
   the environment variable `UNPU_NDM_OVERWRITE` is `1`.
2. `cd $NDM_DIR` (created if needed) and print the working directory: the NDM lands there.
3. Write `$NDM_DIR/feedth.lef` with `unpu_extract_lef_macros` (exactly the three `FILLER_CELLS`).
4. Main workspace as in 18.10. **Fillers in the same library (mode `single`)**: the goal is ONE NDM that contains
   the 534 timing cells and the three fillers typed `filler`. The first run lost the LEF-only cells at library
   build; we do not know why from the log. In `single` mode, also read `feedth.lef` into the same workspace, set
   `design_type filler` on the three cells before `check_workspace`, and print every library-manager message that
   mentions them. VERIFY the commands; where you cannot be sure a command or option exists, write the line with a
   `VERIFY` comment and a guard (`info commands`) so a failure is a clear message, not a stack trace.
5. Mode `two`: build the main NDM as in 18.10 (`scl18fs120.ndm`) and then a second workspace with
   `-flow physical_only` from `feedth.lef`, typed `filler` before check and commit, producing
   `scl18fs120_fillf.ndm`, both in the same script run (so the filler library is part of generation, not a later
   step). The mode is chosen by `UNPU_NDM_MODE`, never decided silently at run time; `ndm_check.tcl` tells the
   user whether `single` worked.
6. After the commits: check that each expected NDM exists and is non-empty (an NDM is a directory in some
   versions; test with `file exists` and report type and size); write `$NDM_DIR/ndm_manifest.txt`, one absolute
   NDM path per line, in the order they must be given as reference libraries. Write the stage manifest.
7. Print counts at the end with `unpu_result ndm_file_gen`: mode, LEF macros read, timing libraries read, workspaces
   committed, NDM paths.

### A4. `pnr/ndm_check.tcl` — runs in `icc2_shell`

Reads `$NDM_DIR/ndm_manifest.txt`, creates a scratch design library under `$RUN_DIR/ndm_check_lib` (technology
file plus the NDMs as reference libraries; refuses to reuse an existing scratch library), and checks, one
`unpu_check_pass` line each: every NDM listed opens; the total number of library cells equals
`EXPECT_TIMING_CELLS` plus the number of fillers; `get_lib_cells */feedth*` returns exactly the three fillers and
their `design_type` is `filler`; none of the three is `dont_use`; `adiode`, `bh01d1`, `cload1` exist and are
`dont_use`; the count of `dont_use` cells before `set_dont_use` is 3. Also print, per reference library, its
name and cell count, and which NDM holds the fillers (that answers "did `single` work"). Exit non-zero if any check
fails. Do not modify the NDMs.

### A5. `pnr/test_common.tcl` — local test (plain `tclsh`)

Tests with synthetic fixtures created in a temporary directory under the session scratchpad (not in the repo): the
derived floorplan values for the defaults (core side 856.8, rows 153, die/site 1550); a die size that is not a
multiple (e.g. 868.3) is rejected with the message; `unpu_extract_lef_macros` on a made-up LEF with five macros
(three requested: found, written, correct blocks, header kept), a missing name (dies), a duplicated name (dies);
`unpu_result` output format; an invalid `UNPU_NDM_MODE` is rejected. Each test prints PASS/FAIL, exit code non-zero
on any FAIL. Because `unpu_die` exits, run the dying cases in a child `tclsh`.

### A6. `pnr/README.md`

Short: the planned scripts and their order, with the shell each runs in (this task creates the first four rows):
`ndm_file_gen.tcl` (lm_shell), `ndm_check.tcl`, then planned and not yet written: `design_setup.tcl`,
`floorplan.tcl`, `power.tcl`, `pin_place.tcl`, `placement.tcl`, `cts.tcl`, `route.tcl`, `fill.tcl`,
`outputs.tcl`. The environment variables, the directory layout, the message format, and the rule that every
stage starts from a named checkpoint and ends by saving a new one.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes; show the output.
2. Every `pnr/*.tcl` is syntactically complete Tcl (`info complete` on the whole file, or source it under a stub
   interpreter whose `unknown` handler logs the commands and returns empty, with the library-manager and
   `icc2_shell` commands stubbed). For `ndm_file_gen.tcl` and `ndm_check.tcl` show the logged command sequence
   (it must show `create_workspace`, the reads, `set_attribute ... design_type filler`, `check_workspace`,
   `commit_workspace`) and that the script reaches the end. State what this proves (valid Tcl, intended order) and
   what it does not (that the library manager accepts each command and option).
3. `grep` proves: no absolute `/storage` path outside the two defaults in params.tcl; no `FOUNDRY`; no write to a
   path under `SCL_KIT_ROOT`.
4. `git status` shows only the new files in `pnr/` (and nothing under `rtl/`, `constraints/`, `syn/`).

## Part C — server block for the user (put it in your report)

csh commands, one per line: `source ~/cad_cshrc`, `source ~/synopsys_cshrc`, `setenv UNPU_WORK ...` only if the
default is not wanted, run `ndm_file_gen.tcl` with the full-path library manager and `-output_log_file`, then
`ndm_check.tcl` with `icc2_shell`. For each: what a good result looks like (the RESULT lines, counts) and what to
paste back. Also the sentence "if `single` mode loses the fillers, set `UNPU_NDM_MODE two` and run again, with
`UNPU_NDM_OVERWRITE 1`".

## Out of scope

Any stage after the NDM (design setup, floorplan, and so on: later tasks); the Calibre and PrimeTime scripts;
changing anything in `rtl/`, `constraints/`, `syn/`; editing `docs/planning/` (report to Planning instead); running
anything on the server.

## Report back

The list of files, the Part B output, every `VERIFY` item with the command or option involved, anything in this
prompt you think is wrong or ambiguous (say so rather than guess), and the Part C block. Stop after reporting; the
next task will come from Planning.
