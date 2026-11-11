# Task 099 — Build the `Final/` folder: one numbered directory per flow stage, on git, with the confidential and the big material kept local

Read first: `docs/planning/progress-log-2026-11-10.md` (the whole file, especially sections 6 to 9), `pnr_v2/RUN3_RUNBOOK.md` and `pnr_v2/VERIFY_STATUS_RUN3.md` (your own documents: the steps, the commits, the expected key lines), `docs/session-handoff.md` 18.32 to 18.36, `.gitignore`, `CLAUDE.md` (repository layout).

## Decisions of the user (2026-11-11)

1. The folder is for OUR use (a complete record of the project), not a delivery for the top-level team.
2. Layout: one numbered directory per flow stage, with everything of that stage inside: docs, scripts, logs, reports, outputs. The RTL and the testbench are in it too.
3. It is on git. The GitHub repository is PUBLIC. Whatever is confidential (PDK kit files, the Calibre decks, anything derived from the kit that carries its terms) is NOT in git: git-ignored, kept in `Final/_local_only/`. The user will also back up the whole `Final/` (including `_local_only/`) on the server.
4. Size policy: final results + reports + logs + scripts go to git (about 250 to 350 MB before compression; compress large files, see below). The ICC2 databases (`*.dlib`, about 158 MB each), the NDM libraries, the early checkpoint exports (`outputs_route*`, `*_before_si`, `*_final3`, 158 MB each) and the raw server copy stay in `_local_only/` with an index (name, size, sha256) committed.
5. Every stage folder holds COPIES of the scripts exactly as they were run (pinned to a commit, the hash written in the stage README), not pointers. The live scripts in `pnr_v2/` etc. stay unchanged.

## Layout (confirmed)

```
Final/
  INDEX.md                    map of the folder, the final numbers, sizes + sha256 of every file, what is in _local_only
  01_rtl/                     rtl/*.sv, the architecture notes that describe it
  02_tb_and_model/            tb/, model/golden.c (not the generated vectors), scripts that run the RTL simulation, results that exist
  03_synthesis/               constraints/legacy (SDC + DC script), syn/RUNBOOK_legacy.md, the 14 reports/netlists of syn/out/legacy
                              (area, power, timing, constraint, qor, check_timing, check_design, profile, dc.v, cn.dc.v, sdc, ddc),
                              the zero-delay gate-level simulation (script, log: 343,341 checks)
  04_ndm/                     build_ndm_*.tcl, logs (NDM libraries themselves go to _local_only)
  05_design_setup/            design_setup.tcl + log + reports
  06_floorplanning/
  07_powerplanning/
  08_placement/               placement.tcl, step 4c (port_buffers_early.tcl + its table CSV and logs), clock_latency.tcl
  09_cts/
  10_routing/                 route.tcl, the route checkpoints route..route4 (pv logs, PrimeTime and Calibre results of the checkpoints)
  11_eco_and_antenna/         antenna loop (fix_antenna, antenna_port_buffers), hold ECO of 9 cells, data-limit ECO (9 resizes), SI round
                              (2 hold buffers + 1 resize + second fix_antenna): probes, change files, apply logs, gates, before/after table
  12_fill_and_export/         metal_fill.tcl, pv.tcl, the FINAL outputs (compressed): GDS, LEF, DEF, netlists, SDC, SPEF, SDF + sha256 of the originals,
                              the sdc_compare result
  13_signoff_calibre/         final4 (DRC, antenna, LVS: ctrl files, logs, rpt, the LVS cell summary) + a table of all Calibre runs (route1..4, final2, final3, final4)
  14_signoff_primetime/       pt (SI off), pt_si (SI on), pt_legacy: logs, reports, violation CSVs; the earlier runs (before the SI round) in a subfolder
  15_post_layout_sim/         run_postlayout_sim.sh, A to D (approved verdicts) and the earlier unapproved ones, the experiments (_eqeq, _negtchk) and
                              their summary; annotate logs gzip-compressed
  16_docs_and_report/         progress logs, handoff, restart plan, all task prompts (066 to 099), RUN3_RUNBOOK, VERIFY_STATUS_RUN3, READMEs, lessons;
                              room for the report text (written later by Planning)
  tools/                      verify_final.sh (below)
  _local_only/                git-ignored: server_run3_raw/ (the full raw copy incl. blocks/*.dlib and the *.ndm), kit/ (PDK parts), env/ (cshrc files)
```

Each stage folder: `README.md` (what the stage does, the commit and the commands, the key result lines with the numbers, the decisions of that stage with the date and who decided, the problems found and how they were solved), `scripts/` (copies, with the commit hash in the README; use `git show <hash>:<path>` for the version in force at that step per RUN3_RUNBOOK; where the hash is only inferred, say so), `logs/`, `reports/`, `outputs/` (only what is small or compressed), `docs/` (the task prompts and notes that belong to the stage).

## Sources

- The raw server copy will be at `~/Final_raw/` (outside the repository, on the PC) when the user has run the full rsync (the command is given to him now): the whole clone `unpu_run3` incl. `pnr_icc2/blocks/`, `*.ndm`, `pv/`, `syn/`, all outputs and checkpoints, and `kit/`, `env/`. Until it exists, `~/server_pull/run3/` (1.5 GB, final state, no databases) is the interim source for logs and reports; do not wait for it to write the structure, the scripts and the READMEs.
- The repository itself at the latest commit and its history.
- If a needed file is not on the PC, say exactly which and give the user the one `rsync`/`scp` line (csh-free, WSL bash).

## Rules

1. FIRST step, before any large file enters the repository tree: add the git-ignore rules (`Final/_local_only/`, and make sure the stage `logs/` are NOT ignored: the current `.gitignore` ignores `*.log`; add negation rules for `Final/**` and verify with `git check-ignore -v` for a sample of every file type you plan to commit). Print the result.
2. Compression: any single file over 20 MB is gzip-compressed (`.gz`), original name kept plus `.gz`; the sha256 of the ORIGINAL goes into INDEX.md. No single file over 50 MB in git (GitHub warns at 50, rejects at 100). Print a table of the biggest files and the total size of what will be committed. If the total is over 400 MB, stop and tell the user before committing anything (report the options).
3. Nothing confidential in git: no kit file, no Calibre deck (the `scr` folder), no rule-deck-derived files, no NDM, no `.dlib`. The Calibre control files of the project (`pnr_v2/calibre/*.ctrl`) and logs are ours and fine, but check that no log prints a kit path that matters as a secret (paths are fine; contents of decks are not). Say what you checked.
4. `tools/verify_final.sh` (bash): checks the INDEX against the folder (sha256 of every file; for the compressed ones the sha256 of the decompressed original), that no file over the size limit exists, that `_local_only` is ignored, that the key numbers in the READMEs equal the numbers in the log files they cite (PrimeTime setup/hold of the three views, Calibre totals, the simulation verdict lines, the LEF pin count) and prints PASS/FAIL per check. Test it locally; a failed check is an error exit.
5. INDEX.md at the top: the final results table (Calibre, PrimeTime x 3 views, design rules, simulation A to D, utilization, congestion, clock tree, power with the caveat, area), the timeline of the ECOs with the numbers before/after, the list of known limitations (SDF classes and their shares, SI margin, congestion at the upper end, ICC2's remaining clock-path transition nets and the 18 missing PG vias, V83 and V88 findings), and where the server backup is (the path will be given by the user).
6. Do not modify the live scripts, constraints or any file outside `Final/` except `.gitignore` (and say what you changed there). No commit: report; Planning commits when the user says so.
7. Nothing fails silently; nothing hardcoded; mark every statement that you could not verify from a file.

## Acceptance

`bash Final/tools/verify_final.sh` passes on the local tree; `git status` shows only `Final/` (without `_local_only`) and `.gitignore`; the total size to commit is printed; every stage README has the five parts; INDEX.md lists every file.

## Report back

The tree (depth 2), the size table, the `.gitignore` change, the verify output, the list of facts you could not verify, and the exact rsync lines the user still has to run. Stop after reporting.

## Addendum (user, 2026-11-11, same day): two more top-level folders

In addition to the stage folders, `Final/` gets:

- `Final/scripts/`: the COMPLETE set of scripts needed to run the whole flow from RTL simulation to the post-layout simulation, in ONE place, pinned to the final commit (hash in a `MANIFEST.md` and in the folder README). Organised in flow order or mirroring the repository (your choice, say which and why), covering: RTL simulation and golden model scripts (`scripts/`, `model/`), synthesis (`constraints/legacy/*`, the DC script and its runbook), all ICC2 scripts of `pnr_v2/` (incl. `run_root.tcl`, `clock_latency.tcl`, `opt_uncertainty.tcl`, the ECO scripts, `pv.tcl`, `metal_fill.tcl`), `pnr_v2/pt/` (PrimeTime), `pnr_v2/calibre/*.ctrl` (our control files only, NOT the decks), `pnr_v2/sim/` (post-layout simulation and experiments), the diagnostics, the tests (so the tools can be re-verified), and `tools/`. `MANIFEST.md`: for each file its path, the stage(s) that use it, its sha256, and the one-line purpose. A top README says in which order they are run and points to `RUN3_RUNBOOK.md`; the environment needed (tool versions, the `cshrc` setup, the csh/bash traps) is written there, not the kit files. The run-root bootstrap must still work if the folder is copied elsewhere (test: copy `Final/scripts` to a temporary place and run the pure-Tcl tests that do not need the tools).
- `Final/docs/`: ALL documentation in one place, pinned to the same commit: the design notebook (`docs/unpu-notebook.html`), the architecture documents, `docs/session-handoff.md`, all of `docs/planning/` (plan, progress logs, restart plan, instructor guidance, constraints update, all task prompts 001 to 099, the synthesis reports of the rounds), the READMEs of `pnr_v2/`, `pnr_v2/pt/`, `pnr_v2/calibre/`, `pnr_v2/sim/`, `syn/`, `RUN3_RUNBOOK.md`, `VERIFY_STATUS_RUN3.md`, `CLAUDE.md` and the role files (`docs/roles/*`), and an `INDEX` of the documents (title, date, one-line summary, which stage it belongs to). The stage folders keep the documents of their own stage (copies); `Final/docs/` is the complete set.

The stage folders stay as specified: they hold the scripts, logs and results AS RUN for that stage; `Final/scripts/` and `Final/docs/` are the consolidated, complete sets. Update `INDEX.md`, the sha256 index and `tools/verify_final.sh` to cover both. The size and confidentiality rules are the same (no kit, no decks, no NDM, no databases in git).

## Addendum 2 (user, 2026-11-11): no PDK, no tool setup in Final

The user does NOT want the PDK/kit files nor the Cadence/Synopsys/Siemens tool-setup files in `Final/` at all: they stay on the server. So: no `Final/_local_only/kit/`, no `Final/_local_only/env/`, no `calibre_scr`. `Final/` holds only what belongs to our project. The raw copy is complete at `~/Final_raw/server_run3/` (2.6 GB incl. `pnr_icc2/blocks/*.dlib`, the NDM libraries and the experiment files); `~/Final_raw/kit` and `~/Final_raw/env` exist but are NOT to be used (the user removes them). `Final/_local_only/` therefore holds only: `server_run3_raw/` (the raw copy incl. databases, NDM, the early checkpoint exports), nothing from the kit. In INDEX.md say plainly that the kit and the tool-setup files live on the server and give the paths that the scripts reference (paths only, no content). Everything else of the task is unchanged. The NDM libraries (`scl180_std.ndm`, `scl180_filler.ndm`) are generated by our own script from the kit and are needed to open the databases: keep them in `_local_only/` (git-ignored), flagged as derived from the kit.

## Addendum 3 (user, 2026-11-11): no `_local_only/` in Final

The user removes `Final/_local_only/` from the plan. `Final/` contains ONLY what is committed to git: the stage folders, `scripts/`, `docs/`, `tools/`, `INDEX.md`. The ICC2 databases (`*.dlib` and the backups), the NDM libraries, the early checkpoint exports and the raw server copy are NOT part of `Final/`: they stay outside the repository in `~/Final_raw/server_run3/` (staging copy on the PC) and in the original run folder on the server. Consequences for the work: (1) no `.gitignore` rule for `_local_only` is needed any more, only the negations that let the stage logs into git (the current `.gitignore` ignores `*.log`); (2) INDEX.md has a section "Not in Final" that lists, with name, size and sha256, what stays outside (the final database `unpu_top.dlib` with its stage blocks, the six `bak_*` copies, the two NDM libraries, the checkpoint export folders `outputs_route*`, `*_before_si`, `*_final3`, `*_run3_final`) and where it lives (`~/Final_raw/server_run3/pnr_icc2/...` on the PC and `/storage/EE5239G1/aagams_workspace2/unpu_run3/pnr_icc2/...` on the server, paths only); (3) the verify script checks that nothing from that list is inside `Final/`; (4) the server backup of `Final/` (rsync, given to the user by Planning) therefore holds the git content only. Everything else stands.
