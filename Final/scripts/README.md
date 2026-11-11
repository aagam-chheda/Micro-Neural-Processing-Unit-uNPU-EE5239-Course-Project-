# Final/scripts — the complete script set, pinned to commit `e2469b1`

Layout: **mirrors the repository** (`constraints/`, `syn/`, `pnr_v2/`, `tb/`, `model/`, `scripts/`, `rtl/`, `pnr/`, `fw/`). Why: the scripts find their root from their own location (`pnr_v2/run_root.tcl`, task 082) and the tests read `../testdata` and the sibling scripts; a mirrored layout keeps every relative reference valid, so the folder can be copied anywhere and the tool-free tests still run. The flow order is given by the stage column of `MANIFEST.md`.

Source of every file: `git show e2469b1:<path>`, except the three files flagged `WORKTREE` in MANIFEST.md.

## Order of the flow

1. RTL simulation: `scripts/run_xrun.sh` (golden model `model/golden.c` first, see `tb/`).
2. Synthesis with the legacy constraints (`constraints/legacy/dc_script_legacy.tcl`, `syn/dc_run.tcl`) and the zero-delay gate-level simulation (`scripts/run_gls.sh`).
3. ICC2: `pnr_v2/build_ndm_*.tcl`, then stages 1 to 6 (`design_setup`, `floorplanning`, `powerplanning`, `placement` incl. `port_buffers_early`, `cts`, `route`), the repair loops (`fix_antenna`, `antenna_port_buffers`, `pt_eco_apply` with the PrimeTime probes of `pnr_v2/pt/`), `metal_fill`, `pv`.
4. Sign-off: Calibre (`pnr_v2/calibre/*.ctrl`, our control files only) and PrimeTime (`pnr_v2/pt/`), then the post-layout simulation (`pnr_v2/sim/run_postlayout_sim.sh`, optional `run_experiments.sh`).

The exact command sequence with variables and expected key lines is `pnr_v2/RUN3_RUNBOOK.md` (also in `../docs/pnr_v2/RUN3_RUNBOOK.md`); the status of every unverified item is `pnr_v2/VERIFY_STATUS_RUN3.md`.

## Environment (names only; no kit file and no tool-setup file is in this folder)

- Tools: ICC2 U-2022.12-SP3, PrimeTime T-2022.03-SP2, Design Compiler T-2022.03-SP5 (from `syn/out/legacy_dc.log:44`), Xcelium 22.09, Calibre 2022.4_37.20. The versions of ICC2/PrimeTime/Xcelium come from the logs of the run [the line numbers are in `pnr_v2/VERIFY_STATUS_RUN3.md`].
- The tool setup (the `cad_cshrc` / `synopsys_cshrc` / Siemens `siemens_cshrc_clean` scripts, `MGC_HOME`, `CALIBRE_HOME`) and the PDK kit (`/storage/PDK_iitg/SCLPDK_V3.0_KIT/...`) live **on the server**; the scripts reference them by path. Their contents are not in this repository by decision of the user (2026-11-11).
- The server shell is **csh**: no `foreach` on one line, no `2>`/`2>&1` redirection (use `|&` or `>&`), `env VAR=val cmd` to set a variable for one command, a trailing `&` puts the whole `;` chain in the background, `git --no-pager`, background jobs started alone with `< /dev/null`. Calibre needs its own terminal with the Siemens environment. A `git pull` is needed in the clone before running a script committed after the clone. (progress-log-2026-11-10.md 6.4 and 9.3)

## Tests that need no tool (`tclsh`, `bash`)

`bash sim/test_postlayout_verdict.sh` needs the golden-model vectors (they are generated, not stored): in the root of this folder run `gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden` first (without it 7 of its 151 tests fail with exit 2: "model/vectors/ is missing or empty"; observed when this folder was tested in a temporary copy).

From `scripts/pnr_v2/`: `tclsh pt/test_pt_common.tcl`, `tclsh test_pt_eco_apply.tcl`, `tclsh test_eco_scope.tcl`, `tclsh test_drc_eco.tcl`, `tclsh test_sdc_limits.tcl`, `tclsh test_run_root.tcl`, `bash sim/test_postlayout_verdict.sh` and the other `test_*.tcl`. `tools/verify_final.sh` runs a copy of them in a temporary directory (the run-root test of task 082).
