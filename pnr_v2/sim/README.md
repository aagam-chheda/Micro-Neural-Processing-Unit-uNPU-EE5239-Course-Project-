# Post-layout simulation with the SDF (Xcelium) -- task 075

Proves that the placed, routed and buffered design (with the 15 port buffers and the resized clock root) still works with real cell and wire delays at the 20 ns clock. The SAME frozen testbench `tb/unpu_top_tb.sv` is used (`-define GLS_CLK_HALF_NS=10`, 20 ns clock; the testbench drives the stimulus 2 ns after each edge). Nothing here has been run: the user runs it on the server. csh only, one command per line, no sentence-ending period after a command.

## Why an SDF is needed

The zero-delay gate-level run (commit `e3e7f2a`, `ALL CHECKS PASSED`, 343,341 checks, 1 min 57 s) proves the logic only: the kit's cell models have all specparams zero, so a simulation shows delays only through an SDF. `pv.tcl` writes one SDF per corner from the ICC2 extraction: `unpu_top_ss.sdf` (slow) and `unpu_top_ff.sdf` (fast), with the post-layout netlist `unpu_top_pnr_sim.v` (without PG pins; the module is `unpu_top`; `unpu_top_pnr_pg.v` is NOT used here).

## The four runs

| Run | SDF | Delay selection (`MTM_CONTROL`) | Timing checks | Command arguments |
|---|---|---|---|---|
| A | `unpu_top_ss.sdf` | MAXIMUM (the corner's value; if the file has no min:typ:max triples the choice changes nothing) | OFF (`-notimingchecks`, as in the gate-level run that passed) | `ss nochecks` |
| B | `unpu_top_ss.sdf` | MAXIMUM | ON | `ss checks` |
| C | `unpu_top_ff.sdf` | MINIMUM (the fast corner) | OFF | `ff nochecks` |
| D | `unpu_top_ff.sdf` | MINIMUM | ON | `ff checks` |

- **A is the primary functional proof**: the real delays of the slow corner are applied, the design must still compute the same 343,341 checks.
- **B and D can expose a real setup or hold problem in the placed design**: with the timing checks on, the `$setup`/`$hold`/`$recovery`/`$removal`/`$width` checks of the cell models (with real numbers, for example `tsu_d_h_cp=0.14` of `dfcrq1`) run, and a violation turns the flop output to X through the notifier of the model. The 0.4 ps reg-to-reg hold path of ICC2 is of exactly this kind; hold is a fast-corner problem, so D is the run that matters for it.
- **C is the fast corner without checks**: the functional proof at minimum delays.
- `nochecks` does NOT switch the SDF delays off; it only disables the checks (VERIFY V3: the log must show the SDF annotated in A and C too).

## 1. Environment (the Cadence simulator; a terminal of its own, not the Calibre one)

```
source ~/cad_cshrc
cd /storage/EE5239G1/aagams_workspace2/unpu
git pull
which xrun
ls model/vectors | head -3
ls -l pnr_icc2/outputs/unpu_top_pnr_sim.v pnr_icc2/outputs/unpu_top_ss.sdf pnr_icc2/outputs/unpu_top_ff.sdf
mkdir -p xrun_out pnr_icc2/sim
```

If `model/vectors` is empty (the testbench opens it by a relative path, which is why everything runs from the repo root):

```
gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c
./model/golden
```

## 2. Look at the command first (dry run: prints the SDF command file and the `xrun` line, runs nothing)

csh has no `VAR=value command`, so use `env`:

```
env DRY_RUN=1 bash pnr_v2/sim/run_postlayout_sim.sh ss nochecks
```

Compare the printed `xrun` line with the manual run that passed (handoff 18.7): `-sv -64bit -access +r -timescale 1ns/1ps -notimingchecks -top unpu_top_tb`, plus `-define GLS_CLK_HALF_NS=10` (task 057). The additions are `-sdf_cmd_file`, `-sdf_verbose` and `-xmlibdirname xrun_out/pl_<corner>_<mode>`. The dry run also prints the SDF header and the counts if the SDF is already there.

## 3. Run (one at a time; each prints the verdict at the end)

```
bash pnr_v2/sim/run_postlayout_sim.sh ss nochecks |& tee pnr_icc2/sim/runA_console.txt
bash pnr_v2/sim/run_postlayout_sim.sh ss checks |& tee pnr_icc2/sim/runB_console.txt
bash pnr_v2/sim/run_postlayout_sim.sh ff nochecks |& tee pnr_icc2/sim/runC_console.txt
bash pnr_v2/sim/run_postlayout_sim.sh ff checks |& tee pnr_icc2/sim/runD_console.txt
```

The script prints the tool version, the SDF header (DESIGN, DIVIDER, TIMESCALE, VOLTAGE, TEMPERATURE) and the counts of `IOPATH`, `INTERCONNECT`, `SETUPHOLD`/`SETUP`/`HOLD`, whether the min:typ:max triples differ, the SDF command file and the exact `xrun` command; then it runs `xrun` and judges the LOG (never xrun's exit code, which is 0 after `$finish` even when checks failed). Exit status: 0 PASS, 1 FAIL, 2 environment or usage problem (nothing was judged). Files (all under `pnr_icc2/sim/`, git-ignored): `pl_<corner>_<mode>.log` (xrun `-l`), `.console` (raw stdout/stderr), `.sdfcmd` (the SDF command file), `_annotate.log` (written by Xcelium, if the command file's `LOG_FILE` works).

## 4. The verdict (what PASS means)

PASS only if ALL of these hold:

1. the log has the line `ALL CHECKS PASSED`;
2. `checked 343341 value(s)/assertion(s) total` exactly (the number of checks of this testbench, handoff 18.7, the same in the RTL run and in the zero-delay gate-level run; a different number means the testbench did not run the same sequence, for example it stopped early);
3. no line with `FAIL` (also matches `FAILURE(S)`);
4. no `*E,` or `*F,` Xcelium error or fatal line;
5. an SDF annotation message exists in the log or in the annotation log (otherwise nothing proves that the SDF was applied: a silent run would be a zero-delay run), and the SDF messages are in the accepted set only: `*W,SDFNCAP` is information, `*W,SDFNEP` is accepted ONLY in the bounded class of "Known limitation: SDFNEP" below (a PASS with a caveat). Everything else is a FAIL: any other SDFNEP, `SDFIRE`, `SDFCNC`, any other `*W,SDF...` id, an SDF line saying not found / unmatched / cannot find, or a message cap on another SDF id. The script prints the count per message id and the first five lines of each rejected class. `SDFNEP`/`SDFNCAP` lines are not counted as annotation evidence (they contain the word annotate);
6. in `checks` mode: no timing-check violation message (counted, the first 10 printed with time and instance). In `nochecks` mode violations are not judged (the checks are off).

A missing or empty log is a FAIL. The first 5 `FAIL` lines, the simulated end time (`at time ... NS` of `$finish`; the zero-delay run ended at 138,350,796 ns) and the wall-clock time are printed. The earlier zero-delay run took 1 min 57 s; the run with an SDF will be slower, how much is unknown: read the elapsed time the script prints.

## 5. A FAIL in run A is NOT automatically a layout problem: the three first suspects

The cell delays are real now, so the absolute timing of the testbench matters: the stimulus changes 2 ns after the rising edge and the APB read path is combinational (`paddr` to `prdata`, about 11 to 12 ns at ss), so it settles in time only if the testbench samples late enough (2 ns offset + 11 to 12 ns of logic is far below the 20 ns period). Look at the log to tell the three apart:

1. **SDF instance paths do not match the netlist names** (a back-annotation problem, not a design problem). Signs: the verdict lists SDF not-found warnings; the annotation lines show few annotated delays or "not annotated"/"unmatched" counts; many checks then fail or the run behaves as a zero-delay run. Look: `grep -m5 INSTANCE pnr_icc2/outputs/unpu_top_ss.sdf` and the printed header (`DIVIDER` `/` or `.`, `DESIGN`) against `grep -m5 " u_" pnr_icc2/outputs/unpu_top_pnr_sim.v`; whether the scope `unpu_top_tb.dut` is right.
2. **The testbench samples earlier than the output settles.** Signs: the FAIL lines are read values (`prdata`, `npu_status`, `mem C`) with plausible but old values, not X; the first FAIL is early; the failure appears at ss (A) and not at ff (C), because the ff delays are smaller; `DONE never observed` for a polling bound means the status never changed within the bound. The cure is not in the layout: report it to Planning with the first FAIL line and the time.
3. **A real timing error in the placed design.** Signs: in `checks` mode (B, D) a violation message names an instance and a time BEFORE the first FAIL line; X appears in the failing values (the notifier turned a flop output to X); run A (checks off) passes while B or D fails; the instance is a reg-to-reg path that PrimeTime (task 074) also lists. Compare with `pt_hold_ff.log` and the ICC2 hold path of about -0.0004 ns.

## Known problem: `*E,SDFIRE ... REMOVAL keyword is only allowed in SDFVERSION of 3.0 or later` (first server run, run A)

- **What was seen:** `xmsdfc: *E,SDFIRE: pnr_icc2/outputs/unpu_top_ss.sdf, line 872: Syntax Error: REMOVAL keyword is only allowed in SDFVERSION of 3.0 or later`, then `xmelab: *W,SDFCNC: Cannot compile SDF file - skipping annotation`. The verdict was FAIL, correctly. The run itself was effectively zero-delay: `ALL CHECKS PASSED`, 343,341 checks, but the simulated end time was 276,701,592 ns (the 20 ns clock doubles the 138,350,796 ns of the 10 ns runs); a PASS in that state would have proved nothing about delays.
- **Cause:** the `write_sdf` of this ICC2 writes the header `(SDFVERSION "OVI 2.1")` but the file holds `REMOVAL`, `RECOVERY` and `SETUPHOLD`-type entries, which belong to SDF 3.0. The `write_sdf` of this release has NO `-version` option (usage text: `-include`, `-significant_digits`, `-compress`, `-corner`, `-mode`).
- **Cure:** since task 076 `pv.tcl` rewrites the header line of both files to `(SDFVERSION "3.0")` (only the first 60 lines are edited, the entries are not touched; 3.0 is a superset of 2.1) and stops with `ERROR 076` if the result is not exactly one `SDFVERSION "3.0"` line. Re-run `pv.tcl` (the layout is unchanged, so the Calibre results stay valid), or fix the existing files by hand:

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/outputs
sed -i '1,60s/(SDFVERSION "[^"]*")/(SDFVERSION "3.0")/' unpu_top_ss.sdf
sed -i '1,60s/(SDFVERSION "[^"]*")/(SDFVERSION "3.0")/' unpu_top_ff.sdf
head -n 5 unpu_top_ss.sdf
```

- **How the script helps:** the SDF info block prints the `SDFVERSION` line and the number of `REMOVAL + RECOVERY` entries and warns when the header is not 3.0 but the entries exist; the verdict lists any `SDFIRE`/`SDFCNC` line, says the run had zero delays, and adds the reason "the SDF could not be compiled: check the SDFVERSION (needs 3.0 if it has REMOVAL/RECOVERY entries) and regenerate with pv.tcl".
- **Always check:** the simulated end time of the zero-delay run at the 20 ns clock was 276,701,592 ns; a run that really used the SDF is expected to end at the same time if the testbench is cycle-identical (read it, do not assume it); and the annotation lines must show a large annotated count.

## Known limitation: SDFNEP (a PASS with a caveat, not a clean pass)

- **Decision:** accepted as a documented, BOUNDED limitation by the user on 2026-11-09 (option 1), after run A3 (`pnr_icc2/sim/pl_ss_nochecks.log`): the SDF (3.0) compiled and annotated, `ALL CHECKS PASSED`, 343,341 checks, 0 `FAIL`, 0 `*E,`/`*F,`, simulated end 278,003,892 ns. Only the SDF warnings made the earlier verdict FAIL (722 lines: 222 `*W,SDFNCAP`, 500 `*W,SDFNEP`).
- **What was seen:** `*W,SDFNEP ... Unable to annotate to non-existent path (IOPATH (posedge A) S) of instance unpu_top_tb.dut.u_dma.add_212_3.U3 of module ah01d1 <...sdf, line 31510>`. In the printed part: `mx02d0` 272, `ah01d1` 104, `mx02d1` 52, `xr02d1` 36, `ad01d0` 24, `xn02d1` 4, `mi02d1` 4, `mi02d0` 4; arc forms `(posedge|negedge) S -> Z` (mux select), `(posedge|negedge) A|B -> S` (XOR / adder sum), `A1|A2 -> Z`, `S -> ZN`.
- **Cause:** the library model (`tsl18fs120_scl.v`) declares these paths WITHOUT an edge qualifier, for example for `ah01d1`:
  `if (B == 1'b0) (A => S) = (...);`  `if (B == 1'b1) (A => S) = ...;`  `ifnone (A => S) = ...;`
  while ICC2 writes edge-specific entries `(IOPATH (posedge A) S ...)` and `(IOPATH (negedge A) S ...)`. Xcelium does not match the edge entry to the unqualified, conditional model path, so those arcs keep the model's zero delay.
- **Scope:** about 1 percent of the 52,379 IOPATH entries of the SDF. The run is slightly OPTIMISTIC on those arcs (a mux select, an XOR/XNOR or an adder sum is faster in the simulation than in the layout). Timing sign-off is PrimeTime, not this simulation.
- **What the script accepts (bounded):** every printed `SDFNEP` line must have the form `non-existent path (IOPATH (posedge|negedge X) Y) of instance ... of module <cell>` AND the cell must be one of `SDFNEP_ALLOWED_CELLS` at the top of `run_postlayout_sim.sh` (`mx02d0 mx02d1 mi02d0 mi02d1 ah01d1 ad01d0 xr02d1 xn02d1`; the families are 2-input multiplexers, half adder, full adder, XOR, XNOR; a cell of the same family with another drive strength is NOT accepted until it is added there, knowingly). The table prints the count per cell type, the count per arc form and the total. Anything else is a FAIL with its first 5 lines printed.
- **The final verdict word** when this acceptance was used: `PASS (with the documented SDF limitation: N SDFNEP warnings on mux-select, XOR/XNOR and adder-sum arcs ran at zero delay; the simulation is slightly optimistic on those arcs; timing sign-off is PrimeTime)`, exit status 0. A log with no SDFNEP prints a plain `PASS`. Quote the caveat whenever the result is reported.
- **The 1000-message cap:** Xcelium stops printing a message id after 1000 (`*W,MXWARN: Reached maximum warning limit for 'SDFNEP'(1000)`). The script then prints `NOTE: the message cap of 1000 was reached: the real count is higher`: N is a lower bound and the rule is applied to the printed lines only. A cap on any other SDF id is a FAIL (the rest of that class is hidden).
- **Before widening the list:** read the new cell type's model lines first (is the path declared without an edge?) and record the decision with its date and approver here.

## 6. After the runs

```
grep -c "Timing violation" pnr_icc2/sim/pl_ss_checks.log
grep -n "ALL CHECKS PASSED" pnr_icc2/sim/pl_ss_nochecks.log
tail -n 5 pnr_icc2/sim/pl_ss_nochecks.log
```

Copy the logs back from a LAPTOP terminal (the user types the password):

```
mkdir -p ~/server_pull/sim
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/sim/pl_ss_nochecks.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/sim/pl_ss_nochecks_annotate.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/sim/pl_ss_nochecks.sdfcmd ~/server_pull/sim/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/sim/pl_ss_checks.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/sim/pl_ff_nochecks.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/sim/pl_ff_checks.log ~/server_pull/sim/
```

## 7. Test of the verdict logic (local, no server)

```
bash -n pnr_v2/sim/run_postlayout_sim.sh
bash pnr_v2/sim/test_postlayout_verdict.sh
```

It judges sample log texts: PASS; FAIL for a missing `ALL CHECKS PASSED`, for 343340 and 343342 checks, for a `*E,` and a `*F,` line, for a `FAIL` line, for a violation in `checks` mode (the same text is not judged in `nochecks` mode), for an empty and a missing log, for SDF not-found warnings (also from the separate annotation log) and for a log without any annotation message; and, for the SDF acceptance: the exact run A3 lines (`SDFNCAP`, `SDFNEP` on `ah01d1` and `mx02d0`) give PASS with the caveat and the tables, the same plus an SDFNEP on a cell outside the list, of a non-IOPATH form or without an edge, an unknown SDF id, `SDFCNC`, a cap on another id, no annotation message, an `*E,` line or a wrong check count give FAIL, the `MXWARN` line prints the NOTE, and a log with only `SDFNCAP` gives a plain PASS; and checks the dry-run output and the exit status 2 for bad arguments. The sample message wordings are written from knowledge of Xcelium (VERIFY V5 to V8).

## VERIFY table (nothing has been run)

| # | Item | Look at in the log |
|---|---|---|
| V1 | The SDF command file statement (`SDF_FILE`, `SCOPE`, `MTM_CONTROL`, `SCALE_FACTORS`, `SCALE_TYPE`, `LOG_FILE`) is accepted by this Xcelium (22.09) | no `*E,` about the command file; the annotation lines after the elaboration |
| V2 | `-sdf_cmd_file` and `-sdf_verbose` are the right options; an uncompiled SDF is compiled by the elaborator (otherwise `xmsdfc` and `COMPILED_SDF_FILE`) | the first lines of the `.console` file |
| V3 | `-notimingchecks` does not switch off the SDF delay annotation | the annotation lines in run A and run C show a large annotated count |
| V4 | The scope `unpu_top_tb.dut` matches the SDF `DESIGN` / `INSTANCE` names and the divider | the printed SDF header and the not-found warning count (must be 0) |
| V5 | The wording of the annotation message (`annotat`) and where the counts are printed (log or `_annotate.log`) | the "SDF annotation lines" block of the verdict |
| V6 | The not-found class of SDF warnings (`*W,SDF...` ids, wording) | the "SDF warnings" block with the count per id |
| V7 | The wording of a timing-check violation in this model library (`violation`, `*W,TCHKVIO`, `$setup(`...) | in checks mode, `grep -n -i violation <log>` (the verdict pattern is tuned to the words `violation` and the `$setup(`/`$hold(` forms) |
| V8 | The end-time line `Simulation complete via $finish(1) at time ... NS` | the line `simulated end:` of the verdict |
| V9 | Whether the SDF triples min:typ:max differ, so that `MTM_CONTROL` matters | "triples sampled: N, with min != max: M" |
| V10 | The SDF TIMESCALE / DIVIDER / VOLTAGE / TEMPERATURE of each file match its corner (ss: 125 C, 1.62 V; ff: -40 C, 1.98 V) | the printed SDF header |
| V11 | `-xmlibdirname xrun_out/pl_<corner>_<mode>` needs `xrun_out` to exist (created by the README and the script) | an error about the library directory |
| V12 | The post-layout netlist compiles with the combined cell model (no unresolved cells) | `*E,` lines; the benign messages of the earlier run were 24 `CUVWSP` and one `UDPRDT` |
