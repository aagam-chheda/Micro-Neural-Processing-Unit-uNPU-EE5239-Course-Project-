# Task 052 — synthesis at 20, 18 and 16 ns: runbook, comparison script, and the choice of netlist

Read first: `docs/planning/constraints-update-2026-11-02.md` (sections 3, 4, 5.4 and 7), `constraints/pm_dc_script_unpu.tcl` and `constraints/unpu_top.sdc` as changed by task 051,
`docs/session-handoff.md` 18.6 to 18.8 (how the earlier DC runs, the clean-name step and the gate-level simulation were done), `docs/planning/synthesis-reports/README.md` (the report
layout already published for the PM), `scripts/dc_summary.sh` and `scripts/run_xrun.sh` (style; the first reads another folder layout and stays as it is).

## Goal

The user will run Design Compiler three times on the server, once per profile (`syn20` mandatory, `syn18`, `syn16` target), copy the results to this machine, and then needs: (1) one
document to follow for those runs and the simulation of the chosen netlist, (2) one script that compares the three runs and says which are acceptable, and (3) a fixed rule for
choosing the netlist that goes into the layout flow.

## Part A — what to write

### A1. `syn/RUNBOOK.md`

Short, step by step, csh, one command per line, with what to look for after each:

1. On the server: pull the repository; `source ~/cad_cshrc`, `source ~/synopsys_cshrc`; go to the repo root; the model vectors for the simulation exist or are generated (handoff 18.7).
2. The three DC runs, `syn20` first. Use the command from your task 051 report (`setenv UNPU_STAGE ...`, `dc_shell -f constraints/pm_dc_script_unpu.tcl | tee syn/out/dc_<profile>.log`). After
   each run: the lines to look for in the log (no `Error:`; the profile line `Info: [unpu] SDC profile ...`), the files that must exist in `syn/out/<profile>/`, the expected content of
   `unpu_top.constraint` (only `max_area` violated: it is the PM's `set_max_area 0` and is expected), `check_timing` clean, `check_design` with only the benign LINT messages of 18.8.
   Run time is not known; say so.
3. Copy-back from a laptop terminal (`scp`, `EE5239G1@172.16.82.70`, source `/storage/EE5239G1/aagams_workspace/unpu_without_claude/syn/out/<profile>/`, destination a NEW folder
   `~/server_pull/syn/<profile>/` per profile; no password in any command). The folders are small except the netlists (about 1.2 MB each): copy all.
4. Compare: `bash scripts/syn_compare.sh` (A2) with `SYN_OUT=~/server_pull/syn`.
5. Choose the netlist by the rule in A3.
6. Gate-level simulation of the chosen clean-name netlist: the command of 18.7 with the netlist path replaced (`syn/out/<profile>/unpu_top_cn.dc.v`), including where the log goes and the expected
   result (343,341 checks if the testbench and the design are unchanged; a different number is not a failure of the netlist if the testbench changed, say how to tell).
7. Publish for the PM: copy the three folders' reports into `docs/planning/synthesis-reports/` in the layout already used there (`round4-<date>-syn20/` and so on) with a README line each; the
   user commits them. Do not copy netlists unless asked.
8. Hand-over to the layout flow: which three files go on (`unpu_top_cn.dc.v`, `unpu_top_cn.sdc` is NOT used by the layout flow any more because the layout flow reads the profile SDC; say that
   it is kept for reference), and that `pnr/` defaults still point at `syn/out/pm_flow/` and must be updated by the next task.

### A2. `scripts/syn_compare.sh` (bash, in the style of `scripts/dc_summary.sh`)

Reads `$SYN_OUT/<profile>/` (default `<repo>/syn/out`) for the profiles given on the command line (default `syn20 syn18 syn16`). For each profile it prints, from the files written by task 051:
the profile line from `unpu_top.profile`; the worst setup slack per path group and the worst overall (from `unpu_top.timing_top5` and `unpu_top.timing`); the number of reported paths with a negative
slack; the violators from `unpu_top.constraint` (the names of the violated constraints: `max_area` expected, anything else listed); total cell area, total area, cell count, flops (2,465 expected for the
unchanged RTL; a different number is flagged), buf/inv area (from `unpu_top.area`); dynamic power and leakage (from `unpu_top.power`); the number of `check_timing` warnings and `check_design`
errors; any line containing `latch` in the reports and the log if present; the netlist's instances whose reference matches a don't-use pattern (patterns from the single list in `syn/dc_setup.tcl`,
expected 0). A missing file is MISSING, never OK. Then a side-by-side table of the key numbers (worst slack, area, flops, power) for the profiles, and the verdicts:

- `syn20`: PASS only if worst setup slack >= 0, no violator except `max_area`, no latch, no don't-use hit; otherwise FAIL.
- `syn18` and `syn16`: reported as MET or "NOT MET (ideal target, instructor)" with the worst slack; never a FAIL (the guidance says "ideally also at 16-18 ns").
- The recommendation line, from the rule in A3, naming the profile whose netlist goes on, or saying that none qualifies.

Exit status 0 only if `syn20` PASSES and nothing is MISSING for the profiles asked. Test it on sample directories you make from the REAL round-3 reports in
`docs/planning/synthesis-reports/round3-2026-10-14/` (copy their text into fixtures inside a test script; the new files `timing_top5`, `constraint`, `qor`, `check_timing`, `check_design`, `profile`
have no real example yet: write them in the format the DC commands print, say that this is an assumption, and make the parser strict so that an unexpected layout is reported, not skipped).
A test script `scripts/test_syn_compare.sh` runs: a good set, a `syn16` with negative slack, a `syn20` with negative slack, a missing file, a violator other than `max_area`, a flop count of 2,464.

### A3. The rule for the netlist that goes on (write it in the RUNBOOK and implement it in the script)

Choose the tightest profile that is MET at its own period: `syn16` if its worst setup slack >= 0, else `syn18` if >= 0, else `syn20` (which must PASS). Reason to write down: a netlist that
meets a tighter period has margin at the real 20 ns; the cost is area, which the layout flow absorbs through the die size (core area = cell area / 0.60). The user may override the rule in
writing; the script only recommends.

## Part B — checks you can run here

1. `bash scripts/test_syn_compare.sh` passes (show the output); `bash -n` on both scripts; no `\r`.
2. The comparison table on the sample set, as printed.
3. `git status`: only `syn/` (the RUNBOOK) and `scripts/` changed; nothing under `constraints/`, `pnr/`, `rtl/`, `docs/planning/`. Do not commit.
4. List what could not be checked without the server (the real file layouts of the new reports, the run times, the scp lines) and mark them.

## Constraints that apply

RTL frozen; nothing fails silently; no value of the constraints may be changed here; no `$FOUNDRY`.

## Out of scope

`pnr/` (next task), `constraints/`, running anything on the server, `docs/planning/`, committing.

## Report back

Files, Part B output, the table, every assumption about report formats, anything in this prompt that is wrong or ambiguous. Stop after reporting.
