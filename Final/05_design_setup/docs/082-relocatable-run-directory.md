# Task 082 — Make every script relocatable: one clone = one self-contained run

Read first: `docs/planning/restart-plan-2026-11-10.md`, `docs/planning/progress-log-2026-11-09.md` (3.14), your own message of 2026-11-10 listing the hardcoded paths.

## Why

Run 2 starts in a fresh `git clone` on the server (`/storage/EE5239G1/aagams_workspace2/unpu_run2` or whatever name the user picks; the name must not matter). Run 1 stays in `/storage/EE5239G1/aagams_workspace2/unpu`, untouched. About 20 scripts hardcode the run 1 path, so a second clone would silently write into run 1. That would be a disaster: it overwrites the fallback.

## Goal

Every Tcl script derives the project root from its own location. No script, test or README command may write into any directory other than its own clone.

## Part 1 — scripts

1. Replace the literal `/storage/EE5239G1/aagams_workspace2/unpu` everywhere you listed (PNR_DIR, PROJ_DIR, SCRIPT_DIR, ANT_DB, DRC_DB, PT_BASE) by a value computed from `[info script]`: `file dirname` of `file dirname` of `file normalize [info script]` (pnr_v2 -> project root). Guard: if `[info script]` is empty (script pasted into a shell) or the directory `pnr_v2` is missing under the root, stop with a clear error that says what was found. Put the derivation in ONE shared place if the scripts can source it safely (your choice; if not, repeat the same 4 lines and test that all copies are identical). `pnr_v2/pt/pt_common.tcl`: same, one level deeper.
2. The workspace subdirectories (`pnr_icc2`, `syn/out`, ...) stay as they are, now under the derived root.
3. Print at the start of every script one line: `>>> RUN ROOT: <path>` (so a log shows which clone wrote it). The user can see at a glance if a run went to the wrong place.
4. Safety net: if the derived root differs from the current working directory's clone (for example the user starts `icc2_shell` in run 1's `pnr_icc2` but sources run 2's script), print a WARNING line with both paths. Do not block (the user may do it on purpose), but never silent.

## Part 2 — Calibre control files and READMEs

1. `pnr_v2/calibre/{drc,ant,lvs}.ctrl` cannot compute paths. Options: relative path if Calibre is started in the run directory (check how the kit's rule decks resolve `LAYOUT PATH`; mark VERIFY), otherwise a documented one-line edit per run plus a script-side check that prints the `LAYOUT PATH` line and the root it expects. Pick the safest and say why.
2. READMEs (`pnr_v2/README.md`, `calibre`, `sim`, `pt`, `syn/RUNBOOK_legacy.md`): replace the literal path by `<RUN_DIR>` with a first line saying what it is and how to set it (`setenv RUN_DIR <path>` is fine if every command uses it; otherwise a note). Keep ONE command per line, csh syntax.

## Constraints

"Nothing fails silently; nothing hardcoded." No flow behaviour changes: only paths. Do not touch constraints, app options or any numeric value. Local only: no server work, no commit.

## Acceptance

1. `info complete` = 1 for all changed Tcl files; every existing test passes (counts as at 7e8c1ed: `pt/test_pt_common` 278, `test_pt_eco_apply` 136, `antenna_port_buffers` 149, `antenna_clk_root` 63, `timing_closure` 69, `pv_lef_check` 48, `pv_sdf_check` 18, sim verdict 73) plus new tests for the derivation (a copy of the tree under another directory name resolves to ITS OWN root; empty `[info script]` errors; missing `pnr_v2` errors).
2. `grep -rn "aagams_workspace2" .` over tracked files: the only hits allowed are in comments or docs that explain the layout, listed in your report.
3. A dry check you can do locally: copy the tree to a temporary directory with a different name, `grep` that no script string still points at the old path.
4. `git status`: changed files only.

## Report back

Files changed, where the derivation lives, test output, the grep result, the Calibre decision with the VERIFY, anything ambiguous. Stop after reporting.
