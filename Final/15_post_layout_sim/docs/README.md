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

**RUN_DIR** is the folder of the clone you run in (for example `/storage/EE5239G1/aagams_workspace2/unpu_run2`; the name does not matter, run 1 is the clone `unpu`). Set it once per terminal (csh): `setenv RUN_DIR <full path of the clone>`. In the `scp` lines (typed on your own machine) write the path itself where `<RUN_DIR>` stands. The Tcl scripts do NOT read `RUN_DIR`: each derives its own root from where the script file lives (task 082, `pnr_v2/run_root.tcl`) and prints `>>> RUN ROOT: <path>` at its start and in its log; if that line shows another clone than the one you meant, stop. A WARNING line is printed if the shell's current directory is inside a different clone than the script's.

```
source ~/cad_cshrc
cd $RUN_DIR
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
cd $RUN_DIR/pnr_icc2/outputs
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
- **Scope (corrected by task 094):** the edge-form class is 3,510 of the 52,656 IOPATH entries (6.7%); the first estimate "about 1 percent" came from the printed lines only (see "Task 094"). The run is slightly OPTIMISTIC on those arcs (a mux select, an XOR/XNOR or an adder sum is faster in the simulation than in the layout). Timing sign-off is PrimeTime, not this simulation.
- **What the script accepts (bounded):** every printed `SDFNEP` line must have the form `non-existent path (IOPATH (posedge|negedge X) Y) of instance ... of module <cell>` AND the cell must be one of `SDFNEP_ALLOWED_CELLS` at the top of `run_postlayout_sim.sh` (`mx02d0 mx02d1 mi02d0 mi02d1 ah01d1 ad01d0 xr02d1 xn02d1`; the families are 2-input multiplexers, half adder, full adder, XOR, XNOR; a cell of the same family with another drive strength is NOT accepted until it is added there, knowingly). The table prints the count per cell type, the count per arc form and the total. Anything else is a FAIL with its first 5 lines printed.
- **The final verdict word** when this acceptance was used: `PASS (with the documented SDF limitation: N SDFNEP warnings on mux-select, XOR/XNOR and adder-sum arcs ran at zero delay; the simulation is slightly optimistic on those arcs; timing sign-off is PrimeTime)`, exit status 0. A log with no SDFNEP prints a plain `PASS`. Quote the caveat whenever the result is reported.
- **The 1000-message cap:** Xcelium stops printing a message id after 1000 (`*W,MXWARN: Reached maximum warning limit for 'SDFNEP'(1000)`). The script then prints `NOTE: the message cap of 1000 was reached: the real count is higher`: N is a lower bound and the rule is applied to the printed lines only. A cap on any other SDF id is a FAIL (the rest of that class is hidden).
- **Before widening the list:** read the new cell type's model lines first (is the path declared without an edge?) and record the decision with its date and approver here.

## Task 094: the verdict on the run-3 logs (checks mode, the new SDF message forms, the 500-line cap, NOLICN)

**What the run-3 logs showed (final layout, 2026-11-10).** Runs A, B, C: `ALL CHECKS PASSED`, 343,341 checks, 0 `FAIL`, 0 `*E,`/`*F,`. The script said FAIL for all four runs:

| Run | Reason the script gave | Cause |
|---|---|---|
| A ss nochecks, C ff nochecks | 24 `*W,SDFNEP` outside the accepted class | the form is `(COND ((B===0)&&(CI===0)) (IOPATH A S))` on `ad01d0`, not the edge form |
| B ss checks | 1000 SDF warnings of ids not accepted (`SDFNL1` 500, `SDFNET` 500, the cap) and "500 timing-check violations" | new message ids of the timing checks (reset flops); the 500 "violations" are Xcelium's SOURCE-CONTEXT lines |
| D ff checks | `*F,NOLICN` | the license server did not answer |

**1. The false violations.** Xcelium prints, before a warning that has a source location, the source line and a caret line (`     |`). In run B those were model lines (`$hold  (posedge CP &&& (CDN==1'b1),...,notifier);`, `$recovery (...)`) under the `SDFNL1` warnings. The old pattern matched the word `$hold`/`$recovery` and counted exactly the cap (500). The verdict now strips every line that is followed by a caret-only line and counts violations only in the rest. `grep -c "Timing violation"` on both checks logs is 0, and the testbench passed all 343,341 checks with the checks ON (a violation turns the flop output to X through the notifier). **What a real violation looks like: not yet seen.** The detector accepts two independent forms, counts events as the larger of the two and prints both numbers: the message `Timing violation` / `*W,TCHKVIO` (line count), and a check line with measured times, `$setup( posedge D:5000 ps, posedge CP:5050 ps, 140 ps )` (the model's own source lines have no time units, so they never match). The format in the tests is invented from the NC-Verilog form (`Warning!  Timing violation` / `$setup( ... )` / `File:` / `Scope:` / `Time:`); VERIFY V13 on the first real one. The model has no `$display` for violations (read: `tsl18fs120_scl.v`, `dfcrn2`: only `notifier`). New: in a checks run the statistics line `No. of Tchecks = 25065 ... No. of Disabled Tchecks = 0` must show 0 disabled (a checks run with the checks off would report "0 violations" and mean nothing); in the nochecks runs it shows all 25065 disabled.

**2. The true counts (the cap).** Xcelium prints at most 500 lines per message id into the log AND into the `-sdf_verbose` annotation log (`MXWARN ... (1000)` counts both), so the annotation log does not help and the earlier statement "about 1 percent of the IOPATH entries" (from the printed lines) was wrong. Two exact sources exist that need no option: (a) the line `Annotation completed with 0 Errors and N Warnings` (nochecks 22,534 in both corners; checks ss 38,516, ff 37,079; the 220 `SDFNCAP` are not in it), and (b) the SDF itself. The script now counts the entries in the SDF that cannot be annotated (awk over `JUDGE_SDF`, set by `main`) per class and per cell, and checks `Warnings(Xcelium) == sum of the known classes`: on all four logs the difference is **0** (exact). A difference is a FAIL (the hidden part of the cap is not classified). The classes are then judged on the TRUE counts. (An option that raises the cap was not looked up: the reconciliation above makes it unnecessary; `xrun -helpall |& grep -i -E "maxwarn|mxwarn"` would show it. VERIFY, optional.)

**3. Classification (true counts from the SDF; cells and families from the model).** Total SDF `IOPATH` entries 52,656 (annotated 30,122 = 57.2%).

| Class (approval word) | Message | Entries (ss / ff) | Cells | Cause (model vs SDF) | What the simulation does |
|---|---|---|---|---|---|
| `nep_edge` (accepted 2026-11-09, always on) | SDFNEP `(IOPATH (posedge\|negedge X) Y)` | 3,510 (6.7%) | `xr02d1` 2,280, `ah01d1` 676, `mx02d0` 312, `mx02d1` 162, `xn02d1` 72, `mi02d1` 6, `mi02d0` 2 | the model declares the path without an edge | the arc keeps the model's zero delay |
| `nep_cond` | SDFNEP `(COND (...) (IOPATH A S))` | 19,024 (36.1%) | `ad01d0` 18,232 (1,633 cells), `ad01d1` 720 (60), `ad01d4` 60 (5), `xr03d1` 12 (1) | the model's path conditions are `if ((CI == 1'b0) && (B == 1'b0)) (A => S)` plus `ifnone`; the SDF writes `COND B===1'b0 && CI===1'b0`: Xcelium finds no matching conditional path (the `===` / operand order is the visible difference; not proven to be the cause) | the sum output `S` of every full adder (the multiplier of `u_dma`) has ZERO delay; the carry `CO` arcs are annotated |
| `nl1_neg` (checks only) | SDFNL1 "negative value to a 1 limit timing check ... setting to 0" | ss 8,587 / ff 7,150 | `dfcrq2` 3,907 / 2,820, `decrq1` 3,600 / 3,600, `dfcrn2` 1,074 / 725, `dfcrn1` 6 / 5 | the model's `$hold`/`$recovery` take one non-negative limit; the SDF has negative HOLD (about -0.07) and RECOVERY (-0.32) values; `-0.00` is not counted | the limit is set to 0: STRICTER than the SDF (a violation can only be reported earlier). Conservative: it cannot hide a real violation, it can add a false one |
| `net_remrec` (checks only) | SDFNET "non-existent timing check (REMOVAL ...)" / "(RECOVERY (negedge CDN) ...)" | 7,395 | `dfcrq2` 4,155, `decrq1` 2,160, `dfcrn2` 1,074, `dfcrn1` 6 | the reset-flop models have `$recovery (posedge CDN, posedge CP)` and `$hold (posedge CP, posedge CDN, th_cp_cdn_l)` only: no `$removal`, no negedge recovery (the negedge entries are the SDF's 0-valued "assertion" side: nothing to check) | the SDF removal value (ss 0.43, ff 0.13) is not annotated; the model's own `th_cp_cdn_l` (0.29 to 0.33) applies. At ff that is stricter than the SDF, at ss it is LOOSER by about 0.12 ns: a reset-removal violation between the two could pass. PrimeTime checks removal/recovery in STA (run 3: setup +0.1058 / hold +0.0002 with 100% annotation), so this is a covered corner of the simulation |

**Can any of it hide a real problem?** `nep_cond`/`nep_edge`: the simulation is optimistic on those arcs (they are zero delay), so a functional race that needs the missing delay would not show in simulation; sign-off timing is PrimeTime. It is a large share of the adder cells (36% of all arcs), larger than the 2026-11-09 estimate; the functional proof of run A still holds (the flops, the carry chains and 57% of the arcs carry real delays) but it is a weaker timing proof than "about 1 percent" suggested. `nl1_neg`: conservative. `net_remrec`: the ss removal window above.

**Proposal for the user (nothing new is accepted until it is approved).** The script accepts a class only if its word is in the environment variable `SDF_ACCEPT` (space or comma separated; csh needs `env`):
- Proposal 1: approve `nl1_neg` (conservative, no risk), bounded to the reset flops `dfcrn1 dfcrn2 dfcrq2 decrq1` (`SDFCHK_CELLS`) and to the known form.
- Proposal 2: approve `net_remrec` only for the ff checks run (D), where the model is stricter, and accept the ss window for run B because PrimeTime signs off removal; the cell list is the same.
- Proposal 3: approve `nep_cond` on `SDFNEP_COND_CELLS` (`ad01d0 ad01d1 ad01d4 xr03d1`) as the COND counterpart of the 2026-11-09 decision, with the share above stated in the verdict. Alternatively try to REMOVE the cause instead of waiving it: (a) `sed` the `===` to `==` in the COND lines of a copy of the SDF and re-run A (does the count of `nep_cond` fall to 0?); (b) the model has an `ifdef neg_tchk` branch with `$setuphold`/`$recrem` and delayed signals: compiling with `-define neg_tchk` (and Xcelium's negative-timing-check option, `-neg_tchk`, VERIFY) should remove `nl1_neg` and `net_remrec` altogether. Both are experiments, not defaults: `env XRUN_FLAGS="-define neg_tchk -neg_tchk" ...`.

The verdict words then say what was accepted, for example `PASS (with documented SDF limitations, SDF_ACCEPT='nep_cond nl1_neg net_remrec': 3510 SDFNEP edge-form arcs ... ran at zero delay; 19024 SDFNEP COND-form arcs ... ; 8587 negative hold/recovery limits ... clamped to 0 ...; 7395 REMOVAL/RECOVERY(negedge) entries ... not annotated ...; timing sign-off is PrimeTime)`. An approved class that has entries on a cell outside its list, or a printed line outside its form, is a FAIL. An unknown word in `SDF_ACCEPT` is exit 2.

**4. NOLICN.** Run D never ran: the log has the six `Xcelium_*` features all `Failed` and `*F,NOLICN ... LMF-03015`; the console has the FlexNet text `Cannot connect to license server system` for `Incisive_HDL_Simulator`, `Incisive_Enterprise_Simulator` and `Xcelium_Limited_Single_Core`, with `License path: 5280@<server>`, `FlexNet Licensing error:-15,570. System Error: 115 "Operation now in progress"`. So the license SERVER did not answer (network or `lmgrd`), it is not "all licenses in use". The script now exits **2** with `ENVIRONMENT PROBLEM` (no design verdict, no reasons) when the only `*E,`/`*F,` line is `*F,NOLICN` and there is no check line; it prints the checkout lines of the log and the features, paths and errors of the console (counted). With any other error or a `FAIL` line it is a plain FAIL. Retry: `LICENSE_RETRIES=<n>` (default 0) and `LICENSE_WAIT_S=<seconds>` (default 600): after a licence-only death the script waits and runs again; each failed attempt's log is kept as `pl_<corner>_<mode>.attemptN.log`; the retries used up gives exit 2 again.

**Commands (csh, one per line).** Look at the verdict of the existing logs without running anything (the logs are in `pnr_icc2/sim/`; the verdict function reads the SDF of `pnr_icc2/outputs/`):

```
cd $RUN_DIR
bash pnr_v2/sim/test_postlayout_verdict.sh
env SDF_ACCEPT="nl1_neg net_remrec nep_cond" bash pnr_v2/sim/run_postlayout_sim.sh ss nochecks |& tee pnr_icc2/sim/runA_console.txt
```

(with the approval words the user chose; without `env SDF_ACCEPT=...` nothing new is accepted and the COND/SDFNL1/SDFNET classes are reported as FAIL with their true counts). Run D when the licence server answers, waiting by itself:

```
env LICENSE_RETRIES=6 LICENSE_WAIT_S=600 SDF_ACCEPT="nl1_neg net_remrec nep_cond" bash pnr_v2/sim/run_postlayout_sim.sh ff checks |& tee pnr_icc2/sim/runD_console.txt
```

To check the licence server by hand before a run: `echo $LM_LICENSE_FILE` and the FlexNet tool of the Cadence installation (`lmutil lmstat -c <port@host> -a`, VERIFY the path). **Tests:** `bash pnr_v2/sim/test_postlayout_verdict.sh` (129 checks; the 73 older ones unchanged).

**VERIFY (task 094), status after the experiments of 2026-11-11:** V13 the text of a REAL timing-check violation of this Xcelium: STILL OPEN (none occurred, not even with the true negative limits of the `neg_tchk` runs; the sample in the tests is invented); V14 the optional message-cap option: STILL OPEN and not needed (the SDF reconciliation replaced it); V15 `-define neg_tchk` removes `nl1_neg`/`net_remrec`: **VERIFIED for the define alone** (`SDFNL1` 0; `net_remrec` reduced to 4,930; the option `-neg_tchk` does not exist in this xrun); V16 `===` -> `==` makes the COND entries annotate: **DISPROVED** (warnings unchanged).

## Experiments that remove the causes instead of approving the classes (task 094, for the final layout)

**STATUS: both experiments were run on the final layout (2026-11-11, `run_experiments.sh`, about 55 minutes in total); the measured outcomes are in the boxes "Measured outcome" below. The wording "proposal" / "what changes the decision" in the rest of this section is the plan as it was written BEFORE the runs; the measured outcome replaces it.**

| Experiment | Outcome | Consequence for the approvals |
|---|---|---|
| 2: `===` -> `==` in a copy of the SDF | **Disproved**: warnings UNCHANGED (22,534), COND warnings unchanged (19,024), `ALL CHECKS PASSED` 343,341, 0 violations, no race | the `===` is NOT the cause of the COND mismatch; `nep_cond` (36.1% of the arcs, the adder sums, at zero delay) stays a documented, user-approved limitation |
| 1: `-define neg_tchk` (no extra option) | **`nl1_neg` removed** (`SDFNL1` 8,589 ss / 7,150 ff -> 0); **`net_remrec` reduced** to 4,930 (from 7,395); checks pass, 0 violations | `nl1_neg` is removable by the define; `net_remrec` is smaller but not gone |

Final layout (SI round, commit 779283a): the post-layout simulation A to D passed every check (343,341, 0 FAIL, 0 `*E/*F`, 0 violations, 25,065 checks / 0 disabled) and the verdict is FAIL only for the classes that are not approved: `nep_cond` 19,024, `nl1_neg` 8,589 (ss checks) / 7,150 (ff checks), `net_remrec` 7,395. Two experiments test whether the CAUSE can be removed. Both are optional; nothing below changes the default behaviour or any original file. Two environment variables of `run_postlayout_sim.sh` serve them (both optional, validated, printed as `=== EXPERIMENT run ...`): `PL_LABEL=<word>` (1 to 23 letters, digits, underscore) puts a suffix on every file name of the run (`pl_ss_checks_<word>.log`, `.console`, `.sdfcmd`, `_annotate.log`, `xrun_out/pl_ss_checks_<word>`), so the standard logs are never overwritten; `PL_SDF=<file>` is the SDF to use instead of `pnr_icc2/outputs/unpu_top_<corner>.sdf` (a path relative to `$RUN_DIR`, the script only READS it). The extra compile/elaborate flags go through the existing `XRUN_FLAGS`. The verdict reads the SDF that was used. **Read the numbers, not the verdict word, in an experiment:** a removed cause changes Xcelium's warning total, and the reconciliation then reports `MISMATCH` (exactly the removed count): that is the result, not an error of the run.

### Experiment 1: `nl1_neg` and `net_remrec` (negative timing checks with `neg_tchk`)

> **Measured outcome (final layout, 2026-11-11).** Command: `XRUN_FLAGS="-define neg_tchk"` (the define alone). `xrun -helpall |& grep -i neg` lists `-noneg_tchk`, `-negdelay` and `-ntc_neglim`, and NO `-neg_tchk`: **the option `-neg_tchk` of my first text does not exist in this xrun** (`run_experiments.sh` looks for it in the list and used the define alone). Runs B and D: `ALL CHECKS PASSED` 343,341, 0 `FAIL`, 0 `*E/*F`, 0 violation lines, 25,065 checks. Warnings: **38,518 -> 27,464 (ss) and 37,079 -> 27,464 (ff)**. `SDFNL1`: 8,589 (ss) / 7,150 (ff) -> **0**: the negative limits are no longer clamped, the cause is removed by the define. `SDFNET`: printed 501 (the cap); the true remaining count is 27,464 - 22,534 (the SDFNEP warnings of the nochecks runs) = **4,930 = 2 x 2,465 flops**, against 7,395 = 3 x 2,465 before: with the define the model takes 1 of the 3 removal/recovery entries per flop into account (2,465 entries disappear, consistent with the posedge-CDN removal being annotated now through `$recrem`) and the other 2 (the zero-valued negedge-CDN entries) remain. That reading comes from the COUNTS (the printed lines are capped at 500) and was not checked line by line. **Cost:** wall-clock 17 min 44 s (ss) and 13 min 36 s (ff) against 6 min 45 s and 6 min 12 s without the define, about 2.6 and 2.2 times slower.
>
> **What it means.** The `nl1_neg` approval is not needed for a run that carries the define (the class is empty there); the default runs still need it. The checks runs with the define use the TRUE negative limits and still pass with 0 violations, which is stronger evidence than the clamped default. `net_remrec` is reduced to 4,930 entries of the zero-valued negedge-CDN kind; if the 2,465 that disappeared are the posedge-CDN removals, the "about 0.12 ns looser at ss" window of the default runs is closed in the runs with the define (inferred, not proven by a line-level check). The verdict of these experiment runs says FAIL because no class was approved in them and because the SDF prediction still counts `nl1_neg`: the reconciliation reports `Xcelium counted FEWER warnings than the SDF predicts (difference -11054)` (27,464 against 38,518 at ss): this is the artefact of an experiment run that removed a cause, NOT warnings hidden by the cap (that reason text exists only for a positive difference).


**What it is.** The reset-flop models (`dfcrn1/2`, `dfcrq2`, `decrq1` in `tsl18fs120_scl.v`) have two versions of the checks: the default (`$setup`, `$hold`, `$recovery`, which take one non-negative limit and have no `$removal`) and an `ifdef neg_tchk` version with `$setuphold` and `$recrem` and the delayed signals `d_CP`, `d_D`, `d_CDN`, which accept negative limits and map the SDF `SETUP`/`HOLD` and `RECOVERY`/`REMOVAL` entries. Defining `neg_tchk` selects the second one. Only the checks runs (B and D) are affected; the nochecks runs have no timing checks.

**SDF: no new `write_sdf` is needed.** The SDF of the run already holds the negative `HOLD` / `RECOVERY` values and the `REMOVAL` / `RECOVERY` entries (that is what Xcelium complained about). The `write_sdf` of this ICC2 has no option that writes another form (its usage text: `-include` takes `cell_delays, net_delays, timing_checks, input_port_nets, output_port_nets, disabled_arcs`, no `SETUPHOLD`/`RECREM`), so a new file from the saved `unpu_top_pv` block would be the same. VERIFY V15: Xcelium maps separate `SETUP` and `HOLD` entries onto one `$setuphold` and the `RECOVERY`/`REMOVAL` pair onto `$recrem` (SDF 3.0 allows it). If it does not, the messages stay and the experiment is negative.

**The Xcelium option.** The define is certain (`ifdef neg_tchk` in the model). (Written before the run: the simulator option was assumed to be `-neg_tchk`. It does not exist in this xrun, see the measured outcome above; the define alone did the job.) First list the real options:

```
cd $RUN_DIR
xrun -helpall |& grep -i neg | head -20
```

Run B and D with the define and the option (replace `-neg_tchk` by the option the list shows if it differs; if the list shows none, run with the define alone and say so in the report):

```
cd $RUN_DIR
env PL_LABEL=negtchk XRUN_FLAGS="-define neg_tchk -neg_tchk" bash pnr_v2/sim/run_postlayout_sim.sh ss checks |& tee pnr_icc2/sim/runB_negtchk_console.txt
env PL_LABEL=negtchk XRUN_FLAGS="-define neg_tchk -neg_tchk" LICENSE_RETRIES=6 LICENSE_WAIT_S=600 bash pnr_v2/sim/run_postlayout_sim.sh ff checks |& tee pnr_icc2/sim/runD_negtchk_console.txt
grep -c "SDFNL1" pnr_icc2/sim/pl_ss_checks_negtchk.log pnr_icc2/sim/pl_ff_checks_negtchk.log
grep -c "SDFNET" pnr_icc2/sim/pl_ss_checks_negtchk.log pnr_icc2/sim/pl_ff_checks_negtchk.log
grep "Annotation completed\|ALL CHECKS PASSED\|checked \|Timing violation\|TCHKVIO" pnr_icc2/sim/pl_ss_checks_negtchk.log
grep "Annotation completed\|ALL CHECKS PASSED\|checked \|Timing violation\|TCHKVIO" pnr_icc2/sim/pl_ff_checks_negtchk.log
```

**Time.** B about 6.6 minutes (run 3 final: 6 min 37 s), D about the same plus the licence wait (the retry variables are the ones of the NOLICN fix); the `neg_tchk` version of the models has delayed signals and may be slower: read the `wall-clock time` line.

**What changes the decision.**
- `SDFNL1` and `SDFNET` counts 0, `Annotation completed with 0 Errors and N Warnings` with N = 22,534 (ss and ff: only the SDFNEP warnings remain, so the difference to the 38,516 / 37,079 of the default runs is 15,982 / 14,545), `ALL CHECKS PASSED` 343,341, no violation message: the cause is removed, `nl1_neg` and `net_remrec` need NO approval, and the checks runs are STRONGER than before (the true negative limits, the true removal limits). Report B and D with this evidence and keep the default runs as the record.
- The messages remain (the define or the option has no effect): nothing is learned, the approval question stays as proposed.
- New `Timing violation` / `*W,TCHKVIO` messages, or `ALL CHECKS PASSED` missing: with the real limits a check is violated. That is a REAL finding (a hold or removal violation the clamped limits hid at ff, or a failing reset path): it goes to Planning before any approval, because it can mean a design problem the default runs cannot see.

### Experiment 2: `nep_cond` (`===` to `==` in a COPY of the SDF)

> **Measured outcome (final layout, 2026-11-11).** The copies were made with the `sed` below (19,024 `===` lines, all COND lines; originals checksummed before and after: unchanged). Runs A and C on the copies: warnings **unchanged at 22,534**, the COND warnings unchanged (19,024 entries), `ALL CHECKS PASSED` 343,341, 0 `FAIL`, 0 `*E/*F`, 0 violations. **The hypothesis is disproved: the `===` is NOT the cause of the COND mismatch.** The copy changed nothing in the simulation, so no race was exposed either. The cause of the `nep_cond` class is therefore still unknown (the conditions are written `B==1'b0 && CI==1'b0` in the SDF copy and `(CI == 1'b0) && (B == 1'b0)` in the model, with the operands in another order; another candidate not tested is the `ifnone` paths of the model, which the SDF has no entry for). `nep_cond` stays what it was: a documented limitation (36.1% of the arcs, the adder sums, at zero delay) that the user approved on 2026-11-11. Cost: the two runs and the copies are part of the 55 minutes of the pair of experiments (17 min 44 s + 13 min 36 s for experiment 1, the rest, about 24 minutes, for experiment 2 by subtraction; per-run times of experiment 2 were not recorded in what I have).


**What it is.** In the SDF the 19,024 conditional arcs of the full adders and the 3-input XOR are written `(COND B===1'b0 && CI===1'b0 (IOPATH A S ...))`; the model's path conditions are `if ((CI == 1'b0) && (B == 1'b0))`. The only visible difference is `===` against `==` (and the operand order, which an SDF condition does not depend on). The experiment changes `===` to `==` in the COND lines of a COPY and runs the simulation on the copy. The original stays unchanged and stays the file of record (it is the ICC2 output); the copy is for the simulation only. `===` (case equality) and `==` give the same result for 0 and 1; they differ only for X/Z, which the adders see only during reset/initialisation.

**Make the copies (all 19,024 lines with `===` are COND lines; the original is only READ):**

```
cd $RUN_DIR/pnr_icc2
mkdir -p sdf_experiment
sed '/(COND/ s/===/==/g' outputs/unpu_top_ss.sdf > sdf_experiment/unpu_top_ss_eqeq.sdf
sed '/(COND/ s/===/==/g' outputs/unpu_top_ff.sdf > sdf_experiment/unpu_top_ff_eqeq.sdf
grep -c "===" outputs/unpu_top_ss.sdf sdf_experiment/unpu_top_ss_eqeq.sdf
diff outputs/unpu_top_ss.sdf sdf_experiment/unpu_top_ss_eqeq.sdf | grep -c "^<"
ls -l outputs/unpu_top_ss.sdf sdf_experiment/unpu_top_ss_eqeq.sdf
```

Expected: 19024 and 0 for the two `grep -c`, 19024 for the `diff` count (only the COND lines differ), and the copy is shorter by one byte per replaced `===` (the run-3 ss file has 38,048 of them: 9,464,184 bytes become 9,426,136; the numbers of your final layout may differ slightly: read them, do not assume). Run the nochecks simulation on the copy (the SDFNEP warnings are in the nochecks runs; A about 4.4 minutes, C about 4.5 minutes):

```
cd $RUN_DIR
env PL_SDF=pnr_icc2/sdf_experiment/unpu_top_ss_eqeq.sdf PL_LABEL=eqeq bash pnr_v2/sim/run_postlayout_sim.sh ss nochecks |& tee pnr_icc2/sim/runA_eqeq_console.txt
env PL_SDF=pnr_icc2/sdf_experiment/unpu_top_ff_eqeq.sdf PL_LABEL=eqeq bash pnr_v2/sim/run_postlayout_sim.sh ff nochecks |& tee pnr_icc2/sim/runC_eqeq_console.txt
grep "Annotation completed\|Pathdelays\|ALL CHECKS PASSED\|checked " pnr_icc2/sim/pl_ss_nochecks_eqeq.log
grep -c "SDFNEP.*COND" pnr_icc2/sim/pl_ss_nochecks_eqeq.log
```

**What changes the decision.**
- `Annotation completed with 0 Errors and 3510 Warnings` (22,534 minus 19,024: only the edge-form class remains), the `Pathdelays ... Annotated` figure rises from 47.56% (30,122 of 63,337) to about 77.6% (49,146 of 63,337, my expectation from the counts of run 3), `grep -c "SDFNEP.*COND"` is 0 and the run passes (343,341 checks): the adder-sum arcs now carry their SDF delays, `nep_cond` needs NO approval, and the simulation is a stronger timing proof (the multiplier sums are no longer zero delay). If the results of the copy differ from the default run in a functional check (`FAIL`), the delayed sums expose a real race: report to Planning, do not approve anything.
- The COND warnings remain (same 22,534): the difference was not the cause; `nep_cond` stays an approval question (the alternative is to leave the class unapproved and say that 36% of the arcs run at zero delay).
- The warnings drop but another SDF message appears: report it with the first 5 lines.

The verdict of these runs will say FAIL with `Xcelium counted 3510 SDF warnings, the SDF explains 22534 ... MISMATCH` when the experiment works: that is the removed class showing up as a difference between Xcelium and the prediction from the SDF (the prediction reads the SDF that was used and still lists the COND entries as unmatched). The numbers above are the result.

## 6. After the runs

```
grep -c "Timing violation" pnr_icc2/sim/pl_ss_checks.log
grep -n "ALL CHECKS PASSED" pnr_icc2/sim/pl_ss_nochecks.log
tail -n 5 pnr_icc2/sim/pl_ss_nochecks.log
```

Copy the logs back from a LAPTOP terminal (the user types the password):

```
mkdir -p ~/server_pull/sim
scp EE5239G1@172.16.82.70:<RUN_DIR>/pnr_icc2/sim/pl_ss_nochecks.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:<RUN_DIR>/pnr_icc2/sim/pl_ss_nochecks_annotate.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:<RUN_DIR>/pnr_icc2/sim/pl_ss_nochecks.sdfcmd ~/server_pull/sim/
scp EE5239G1@172.16.82.70:<RUN_DIR>/pnr_icc2/sim/pl_ss_checks.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:<RUN_DIR>/pnr_icc2/sim/pl_ff_nochecks.log ~/server_pull/sim/
scp EE5239G1@172.16.82.70:<RUN_DIR>/pnr_icc2/sim/pl_ff_checks.log ~/server_pull/sim/
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

**One command for both experiments (instead of the single commands above):** `bash pnr_v2/sim/run_experiments.sh |& tee pnr_icc2/sim/experiments_console.txt` (about 25 minutes; `eqeq` or `negtchk` as an argument runs one experiment only). It makes the SDF copies with the checks above (it stops if a `===` is outside a COND line or the copy is not what the sed should make), checksums the originals before and after, finds the `neg_tchk` simulator option in `xrun -helpall` (or uses `NEG_TCHK_OPT`; the define alone if none is listed), runs A and C on the copies and B and D with the flags (licence retries 6 x 600 s by default), and prints ONE summary block (also in `pnr_icc2/sim/experiments_summary.txt`) with the numbers and a `READING:` line per experiment according to the decision rules above. The verdict words of the single runs are FAIL by design when a cause is removed.
