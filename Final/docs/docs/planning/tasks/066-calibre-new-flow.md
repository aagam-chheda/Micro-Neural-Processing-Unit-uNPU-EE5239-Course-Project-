# Task 066 — Calibre DRC, antenna and LVS control files and runbook for the clean-slate layout (`pnr_v2/calibre/`)

Read first: `docs/session-handoff.md` sections 18.22 to 18.28 (the earlier Calibre work: decks, control files, antenna findings, LVS plan) and 18.32 (the new run), `pnr_v2/pv.tcl` (what it exports), `pnr_v2/README.md`,
and the two control files that worked before, copied to this machine by the user: `/home/aagam_chheda/server_pull/calibre/drc.ctrl` and `ant.ctrl` (read them with `cat -A`, they are short). Nothing in `pnr/` is reused or changed.

## Goal

The user can run Calibre DRC, the antenna check and LVS on the GDS of the new flow, `pnr_icc2/outputs/unpu_top_routed.gds` (written by `pnr_v2/pv.tcl` from the block `unpu_top_filled`, `write_gds -units 1000`, kit layer map, std-cell GDS merged),
each in its own run folder, with one-line csh commands and a list of what to look for. Calibre is not run by you: the user runs it on the server.

## Facts already known (do not re-derive; check them against the handoff)

- Calibre 2022.4_37.20. The shared setup file `/home/Siemens_cshrc` has CRLF line endings; the working recipe (cleaned copy, `MGC_HOME`/`CALIBRE_HOME` set by hand because the install path has a space, separate terminal because the license server differs from Synopsys) is in 18.24. Put the exact csh lines in the runbook.
- Decks are the kit's, read-only; the user's working copy is `/storage/EE5239G1/aagams_workspace/calibre_run/scr` (DRC `DRC_TS18SL_SCL_CALIBRE`, antenna `ANTENNA_TS18SL_SCL_CALIBRE`, LVS `LVS_TS18SL_SCL_CALIBRE`, headers). The old control files `INCLUDE` the deck by that absolute path. Keep exactly that path (it is the verified working copy; say in the README that the folder must be copied if the old workspace is removed).
- Old control file settings that worked: `#define 4M1L`, `#define BLOCK`, `#define 3V` (the voltage choice is an assumption, 18.24), `DRC ICSTATION YES`, `VIRTUAL CONNECT COLON NO`. The antenna control file differs (no `BLOCK`/`3V`, `DRC CELL NAME YES CELL SPACE XFORM`). Keep every line; change ONLY the layout path (and the primary cell if it differs).
- Expected `AN.*` and `DRC` rule counts from the old runs: DRC 404 rules; antenna 16 rules.
- Known trap for the new GDS: `LAYOUT PRIMARY` must equal the top cell name inside the GDS. The old GDS top cell worked as `unpu_top`; the new GDS is written from the block `unpu_top_filled` (and `-hierarchy all -long_names`), so the name may differ. Give the user a command to list the top cell name (for example `strings` on the GDS, or the first Calibre error text) and say how to set `LAYOUT PRIMARY`. Mark anything you cannot verify with `VERIFY`.
- LVS: the source netlist for the new flow is `pnr_icc2/outputs/unpu_top_pnr_pg.v` (written with PG pins by `pv.tcl`; the script rewrites names like `N12` to `N_uc_12` with `sed`). The earlier plan (18.23/18.24) was `v2lvs` against the kit CDL
  `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/cdl/scl18fs120_supply_pins.cdl`. Read what 18.22 to 18.24 say about the LVS deck, headers, text-label layers (`GDS-017`, the `T` lines of the layer map were rejected again in the new run) and the pin names; write what is known and what is not. LVS may fail on pin labels: the runbook must say what to read first in the LVS report to tell a label problem from a real mismatch.

## Files to create (only under `pnr_v2/calibre/`)

- `drc.ctrl`, `ant.ctrl`, `lvs.ctrl`: Calibre control files for the new flow (layout path `/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/outputs/unpu_top_routed.gds`; result and report files relative, named `unpu_top.*`).
- `README.md`: the runbook, csh only, ONE command per line, nothing needing a multi-line `foreach`:
  1. one-time Calibre environment lines (separate terminal), and a check line (`which calibre`);
  2. creating the run folder `pnr_icc2/calibre/run1/` and copying the control files into it (`cp` lines);
  3. finding the GDS top cell name;
  4. DRC: the `calibre -drc -hier drc.ctrl |& tee drc.log` line, expected duration (the old GDS took about 160 s; the new one is 4 times larger because of metal fill, say so), and what to look for (`TOTAL RULECHECKS EXECUTED`, `TOTAL RESULTS GENERATED`, the rule names of any result);
  5. antenna: the command and what to look for (number of results, rule names, `NETNAME`);
  6. LVS: the `v2lvs` line, the `calibre -lvs -hier ... lvs.ctrl` line, which report lines to read (CORRECT/INCORRECT, counts of nets/instances, discrepancies, which pins);
  7. which files to copy back with `scp` into `~/server_pull/calibre/` (the user types the password; do not write passwords or keys).
- Do not edit any other file. Do not touch the kit, `pnr/`, `pnr_v2/*.tcl`, `constraints/`, `syn/`, `rtl/`, `tb/`.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." The rule files are the kit's: no rule is disabled, no waiver is written. Do not use `$FOUNDRY`. Do not run anything on the server, do not commit.

## Acceptance test (local, no server)

1. `diff` of `pnr_v2/calibre/drc.ctrl` and `ant.ctrl` against the old files in `/home/aagam_chheda/server_pull/calibre/`: only the layout path (and primary cell, if you changed it) differ; paste both diffs.
2. Every path named in the three control files and the README exists in the handoff or is marked as created by the run; list the paths and where each is documented (a path you cannot trace is marked `VERIFY`).
3. The README has one command per line, no command ends with a sentence period, and every `VERIFY` item is listed at the end with what the user should look at to confirm it.
4. `git status`: new files only in `pnr_v2/calibre/`.

## Report back

Files created, the two diffs, the list of `VERIFY` items, what you know and do not know about LVS and the text-label layers, anything in this prompt that is wrong or ambiguous. Stop after reporting.
