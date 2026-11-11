# Task 075 — Post-layout simulation with the SDF (Xcelium): `pnr_v2/sim/`

Read first: `docs/session-handoff.md` 18.6 to 18.8 (the first gate-level simulations and the Xcelium command that passed), 18.32 to 18.35 (this run), `tb/unpu_top_tb.sv` (read the header comments, the macro `GLS_CLK_HALF_NS`, the instance `dut`, the `step` task and the final check lines), `scripts/run_xrun.sh` (how the RTL testbenches are judged: from the LOG, never from the exit code), `docs/planning/progress-log-2026-11-09.md`.
Also read (do NOT modify, do NOT depend on) the untracked, never accepted `scripts/run_gls.sh` and `scripts/test_run_gls.sh`: they hold task 059's ideas about SDF back-annotation (`-sdf_cmd_file`, `-sdf_verbose`, the verdict) with `VERIFY` notes; use them as hints only. The new script must stand alone under `pnr_v2/sim/`.

## Why

The gate-level simulation of the synthesised netlist (zero-delay cell models, commit `e3e7f2a` run: `ALL CHECKS PASSED`, 343,341 checks) proves the logic only. The kit's cell models have all specparams zero, so a simulation shows delays only through an SDF. The ICC2 export gives a post-layout netlist and SDF files for both corners: this run uses them with the SAME testbench to prove that the placed, routed, buffered design (with the 15 port buffers and the resized clock root) still works with real cell and wire delays at the 20 ns clock.

## Inputs (on the server, `/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/outputs/`, written by `pv.tcl`)

`unpu_top_pnr_sim.v` (post-layout netlist without PG pins; the module is `unpu_top`; do not use `unpu_top_pnr_pg.v`), `unpu_top_ss.sdf` (slow corner) and `unpu_top_ff.sdf` (fast corner), written with `write_sdf` per corner (see `pv.tcl`). The cell model file is `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v` (one combined file; do not also pass the per-cell files). The testbench is `tb/unpu_top_tb.sv` (unchanged, frozen) with `-define GLS_CLK_HALF_NS=10` (20 ns clock; the testbench drives the stimulus 2 ns after each edge). Test vectors: `model/vectors/` (git-ignored; made with `gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden`, already present on the server), and the run must start from the repo root because the testbench opens the vectors by a relative path. `mkdir -p xrun_out` first (xrun needs the parent of `-xmlibdirname`).
These files are on the server only. Anything you need from them that you cannot know (the SDF header: DIVIDER, TIMESCALE, VOLTAGE/TEMPERATURE, instance names; whether the triples are min:typ:max or all equal) is READ at run time and printed.

## Run matrix (four runs, each a separate command; the user runs them one at a time)

| Run | SDF | Delay selection | Timing checks |
|---|---|---|---|
| A | `unpu_top_ss.sdf` | the corner's value (max if the file has triples) | OFF (`-notimingchecks`), as in the gate-level run that passed |
| B | `unpu_top_ss.sdf` | same | ON (the `$setup`/`$hold`/`$width` checks of the cell models and of the SDF; a violation turns the flop output to X through the notifier) |
| C | `unpu_top_ff.sdf` | min (or the corner's value) | OFF |
| D | `unpu_top_ff.sdf` | same | ON |
Run A is the primary functional proof; B and D are the ones that can expose a real setup or hold problem in the placed design (the 0.4 ps hold path of ICC2 is of this kind); C is the fast corner. Explain this table in the README.

## Files to create (only under `pnr_v2/sim/`)

- `run_postlayout_sim.sh`: bash script (the server login shell is csh, so the README calls it as `bash pnr_v2/sim/run_postlayout_sim.sh <ss|ff> <checks|nochecks>`). It: checks the inputs exist and are non-empty (stops with a clear message otherwise); prints the tool version, the exact `xrun` command line, the SDF header lines (DIVIDER, TIMESCALE, VOLTAGE, TEMPERATURE, DESIGN) and the counts of `IOPATH`, `INTERCONNECT` and `SETUPHOLD`/`SETUP`/`HOLD` entries; writes the SDF command file (`-sdf_cmd_file`; scope `unpu_top_tb.dut`; log file; the min/typ/max selection; VERIFY the Xcelium syntax); runs `xrun` with the flags that passed in the gate-level run (`-sv -64bit -access +r -timescale 1ns/1ps -top unpu_top_tb -define GLS_CLK_HALF_NS=10`, plus `-notimingchecks` in the `nochecks` mode, `-xmlibdirname xrun_out/pl_<corner>_<mode>`, the `-l` log goes under `pnr_icc2/sim/`, created by the script, never inside the git-tracked tree); then judges the LOG (see below). Exit status: 0 PASS, 1 FAIL, 2 environment/usage problem.
- `README.md`: the runbook, csh, ONE command per line, how to read each result, the VERIFY table.
- `test_postlayout_verdict.sh`: tests for the verdict logic on sample log texts (bash; passes with `bash`).
Do not modify the testbench, the RTL, `scripts/*`, or any flow script.

## Verdict (decided from the log, never from xrun's exit code, as `scripts/run_xrun.sh` does)

PASS only if ALL of: the log has the line `ALL CHECKS PASSED`; exactly `343341` in `checked N value(s)/assertion(s) total` (the number of checks of this testbench, equal in every earlier run; read it from `docs/session-handoff.md` 18.7, name it as a parameter with that source); no line matching `FAIL`; no `*E,` or `*F,` Xcelium error/fatal lines; the SDF annotation report shows no error (print the annotated/unannotated counts that Xcelium gives; any `*W,SDFNEP` / "not found" / "unmatched" warning count is printed and any non-zero count of SDF instance-not-found warnings is a FAIL unless the README explains a benign class that you identified from the text); in `checks` mode no `$setup`/`$hold`/`$recovery`/`$removal`/`$width` violation message (count them and print the first 10 with time and instance; any is a FAIL). If the log is missing or empty it is a FAIL. Print the first 5 `FAIL` or violation lines. Print the simulated end time and the wall-clock time.

## What to expect and how to report it (put it in the README)

- The cell delays are now real, so the testbench's absolute timing matters: the stimulus changes 2 ns after the rising edge and the APB read path is combinational (`paddr` -> `prdata` about 11 to 12 ns at ss). Explain in the README that a failure in run A is NOT automatically a layout problem and list the three first suspects (SDF instance paths not matching the netlist names; a testbench sampling instant earlier than the output settles; a real timing error) with the log lines that distinguish them.
- The simulation is slower than the zero-delay one (the earlier run took 1 min 57 s): say what to expect (unknown; do not invent a number) and print the elapsed time.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No change to the testbench, no `-nospecify` (the earlier zero-delay-everything run FAILED with a race, handoff 18.7), no waiver of any message. The script prints the full command it runs. Do not run anything on the server, do not commit.

## Acceptance test (local, no server)

1. `bash -n` passes for both shell files; `bash pnr_v2/sim/test_postlayout_verdict.sh` passes: sample logs for PASS; FAIL by a missing `ALL CHECKS PASSED`; FAIL by a wrong check count (343340 and 343342); FAIL by a `*E,` line; FAIL by a setup/hold violation in `checks` mode; FAIL for an empty log; FAIL for SDF "instance not found" warnings; and the same PASS log judged in `nochecks` mode.
2. The generated SDF command file text and the `xrun` line are printed by a dry-run mode (`DRY_RUN=1`): show them in the report for both corners and both modes, so the user can compare them with the manual passed run of 18.7.
3. `grep -c VERIFY pnr_v2/sim/*` and the full `VERIFY` list in the README (SDF command-file syntax and `MTM_CONTROL` spelling, annotation message wording, the instance scope, whether the SDF triples differ, etc.), each with what the user should look at in the log.
4. `git status`: only `pnr_v2/sim/*` and this task file.

## Report back

Files created, test output, the dry-run output, the `VERIFY` list, the lessons you took from `scripts/run_gls.sh` (what you reused as an idea and what you changed), anything ambiguous. Stop after reporting.
