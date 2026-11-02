# syn/RUNBOOK.md — Design Compiler at three periods, comparison, choice of netlist, gate-level simulation

For the user at the server. The server login shell is **csh**; every command is ONE line. Sources: `constraints/pm_dc_script_unpu.tcl` and
`constraints/unpu_top.sdc` (task 051), handoff 18.6 to 18.8 (the earlier DC runs, the clean-name step, the gate-level simulation),
`scripts/syn_compare.sh` (task 052). Things I could not check without the server are marked **(guess)** or **VERIFY**.

The three runs, one per stage profile of `constraints/unpu_top.sdc`:

| Profile | Period | Setup uncertainty | Role |
|---|---|---|---|
| `syn20` | 20 ns | 1.2 ns | mandatory, the real period: it must PASS |
| `syn18` | 18 ns | 1.2 ns | tighter, reported |
| `syn16` | 16 ns | 1.2 ns | tightest, the target; reported ("ideally also at 16-18 ns", instructor) |

Hold uncertainty is 0.05 ns in all of them; hold is not checked in synthesis (ideal clock).

## 1. On the server: get the repository and the tools

```
cd /storage/EE5239G1/aagams_workspace/unpu_without_claude
git pull
source ~/cad_cshrc
source ~/synopsys_cshrc
```

(The clone is the one named in the copy-back paths; if yours is elsewhere, `cd` there. `git pull` needs a clean clone; if `git status` shows changes in `constraints/`, stop and tell Planning.)
The model vectors for the simulation (step 7) are git-ignored; they exist if `ls model/vectors` is not empty, else generate them (handoff 18.7):

```
gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c
./model/golden
```

## 2. The three DC runs, `syn20` first

Each run is one profile. Do the three in this order and look at each before the next one. From the repo root:

```
mkdir -p syn/out
setenv UNPU_STAGE syn20
dc_shell -f constraints/pm_dc_script_unpu.tcl | tee syn/out/dc_syn20.log
```

Then the same with `syn18` and `syn16`:

```
setenv UNPU_STAGE syn18
dc_shell -f constraints/pm_dc_script_unpu.tcl | tee syn/out/dc_syn18.log
setenv UNPU_STAGE syn16
dc_shell -f constraints/pm_dc_script_unpu.tcl | tee syn/out/dc_syn16.log
```

Without `UNPU_STAGE` the script stops at its first line and lists the valid names. The run time is NOT known for these runs (the earlier runs of 18.6/18.8 are not timed in the handoff); allow some minutes **(guess)**.
The tool is `dc_shell` T-2022.03-SP5 (18.6).

After EACH run, look at:

```
grep -c "^Error:" syn/out/dc_syn20.log
grep "SDC profile" syn/out/dc_syn20.log
ls syn/out/syn20
head -n 1 syn/out/syn20/unpu_top.profile
```

What should be there:

- `grep -c "^Error:"` prints `0`. Any `Error:` line stops the profile: send the log to Planning.
- One line `Info: [unpu] SDC profile syn20: period 20.0 ns, setup uncertainty 1.2 ns, hold uncertainty 0.05 ns, feedthrough budget 4.8 ns` (budgets: syn20 4.8, syn18 4.2, syn16 3.6). If it is missing, `read_sdc` did not run the profile section: **VERIFY** (task 051 lists this as unchecked: `puts` and `error` inside `read_sdc`). If the script stops with "UNPU_STAGE ... is not set" you forgot `setenv`.
- `ls syn/out/<profile>` shows, at least: `unpu_top.area  unpu_top.power  unpu_top.timing  unpu_top.timing_top5  unpu_top.constraint  unpu_top.qor  unpu_top.check_timing  unpu_top.check_design  unpu_top.profile  unpu_top.dc.v  unpu_top.sdc  unpu_top_cn.dc.v  unpu_top_cn.sdc  unpu_top_cn.ddc`.
- `unpu_top.constraint`: only `max_area` violated (the PM's `set_max_area 0` means "minimise" and DC reports it violated by definition; handoff 18.8). Nothing else is expected; a `max_transition` or `max_delay/setup` entry is a finding.
- `unpu_top.check_timing`: no `Warning:` lines (clean).
- `unpu_top.check_design`: no `Error:` lines; only the benign `LINT-28`, `LINT-32`, `LINT-33` warnings of 18.8 (unused `paddr[31:12]` / `[1:0]`, DW adder bits, constant bits).
- `unpu_top.timing_top5` and `unpu_top.timing`: the slack of the worst path. At `syn20` the worst path is the combinational `paddr` to `prdata` path (budget 4.8 ns); a negative slack at `syn18`/`syn16` is possible and is reported, not an error.
- A `clk` redefinition warning from DC (the PM's `create_clock -period 20`, then the profile's) is expected: **VERIFY** the text on the first run.

If `syn20` fails, do not go on to the others without telling Planning.

## 3. Copy-back to the laptop (from a LAPTOP terminal, WSL; not from the server)

`scp` asks for the password: type it there, never in a command or a file. One NEW folder per profile; the netlists are about 1.2 MB each, the rest is small: copy the whole folder, plus the log.

```
mkdir -p ~/server_pull/syn
scp -r EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/unpu_without_claude/syn/out/syn20 ~/server_pull/syn/
scp -r EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/unpu_without_claude/syn/out/syn18 ~/server_pull/syn/
scp -r EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/unpu_without_claude/syn/out/syn16 ~/server_pull/syn/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/unpu_without_claude/syn/out/dc_syn20.log ~/server_pull/syn/syn20/dc.log
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/unpu_without_claude/syn/out/dc_syn18.log ~/server_pull/syn/syn18/dc.log
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace/unpu_without_claude/syn/out/dc_syn16.log ~/server_pull/syn/syn16/dc.log
```

(`scp -r <folder> ~/server_pull/syn/` puts the folder `syn20` INSIDE `~/server_pull/syn/`, so the result is `~/server_pull/syn/syn20/`. A second pull of the same profile overwrites it: rename the old folder first, for example `mv ~/server_pull/syn ~/server_pull/syn_before`.) The log is renamed `dc.log` because `syn_compare.sh` looks for that name.
These `scp` lines are the ones of the earlier exchanges with the paths of this task; **VERIFY** that the server path is where you ran the commands (`pwd` in step 1).

## 4. Compare the three runs

On the laptop, in the repo (the `~` is expanded by the shell; bash):

```
cd <your clone on the laptop>
SYN_OUT=~/server_pull/syn bash scripts/syn_compare.sh
```

It prints, per profile, the profile line, worst setup slack per path group, the violators, area, flops, power, `check_timing` / `check_design` counts, latch lines and don't-use hits; then a side-by-side table and the verdicts.
Read it like this:

- `syn20: PASS` is required. `FAIL` lists the reason (negative slack, a violator other than `max_area`, a latch, a don't-use cell) and the exit status is 1.
- `syn18` and `syn16` are `MET` or `NOT MET (ideal target, instructor)`; never `FAIL`.
- `MISSING`, `UNPARSED` and `WRONG PROFILE` lines mean a file is absent, has an unexpected layout (the layouts of `.timing_top5`, `.constraint`, `.qor`, `.check_*`, `.profile` were written without a real example: **VERIFY** on the first real run and tell Planning) or belongs to another profile. They are never treated as OK.
- The flop count is expected to be **2465** while the RTL is unchanged; another number is flagged.
- Exit status 0 only if `syn20` PASSES and nothing is missing, unreadable or flagged.

## 5. Choose the netlist (the rule)

**Take the TIGHTEST profile that is MET at its own period:** `syn16` if its worst setup slack is >= 0, else `syn18` if its worst setup slack is >= 0, else `syn20` (which must PASS). `syn_compare.sh` prints this as the
`RECOMMENDATION` line, or says that none qualifies (when `syn20` does not PASS).
Why: a netlist that meets a tighter period has margin at the real 20 ns. What it costs is area, and the layout flow absorbs that through the die size (core area = cell area / 0.60). The script only recommends: the user may override the rule in writing (write the reason down next to the choice).

## 6. Gate-level simulation of the chosen clean-name netlist

On the server, from the repo root (the testbench opens `model/vectors/...` by a relative path), with the chosen profile in place of `<profile>`:

```
xrun -sv -64bit -access +r -timescale 1ns/1ps -notimingchecks -top unpu_top_tb syn/out/<profile>/unpu_top_cn.dc.v /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v tb/unpu_top_tb.sv -l syn/out/<profile>/gls.log
```

This is the command of 18.7 with the netlist path replaced; the flags are the ones that passed there (`-sv -64bit -access +r -timescale 1ns/1ps -notimingchecks -top unpu_top_tb`), the cell delays of the models ON, setup/hold checks OFF, no SDF. Do NOT use `-nospecify` (18.7: it fails for this design). The single combined model file is used; do not also pass the per-cell files. The order of the three files on the line is my reconstruction of 18.7 (**VERIFY**). Xcelium needs `source ~/cad_cshrc` (done in step 1). The log goes to `syn/out/<profile>/gls.log` (git-ignored).

Look at the result:

```
grep -E "ALL CHECKS PASSED|FAILURE|checked .* value" syn/out/<profile>/gls.log
grep -cE "\*E,|\*F," syn/out/<profile>/gls.log
```

Expected (18.7 and 18.8, for the previous netlist): `checked 343341 value(s)/assertion(s) total`, `ALL CHECKS PASSED`, 0 `*E` / `*F` lines, `$finish` at 138,350,796 ns, about 2 minutes. Benign: 24 `CUVWSP` and one `UDPRDT` message (18.7). The check count equals the RTL run of the same testbench, so:

- if `tb/unpu_top_tb.sv` and the RTL are unchanged since 18.7, the number must be 343,341; a different number with `ALL CHECKS PASSED` is not a failure of the netlist by itself but means the testbench or the RTL changed. Tell them apart by running the RTL control: `bash scripts/run_xrun.sh top` prints the count of the same testbench on the RTL; the netlist run must print the SAME number. If the two differ, it is the netlist;
- `FAILURE(S)`, any `*E` / `*F`, or no `ALL CHECKS PASSED` line is a failure of the netlist.

## 7. Publish the reports for the PM

The PM reads the reports in `docs/planning/synthesis-reports/` (layout of `round3-2026-10-14/`: `unpu_top.area`, `unpu_top.power`, `unpu_top.timing`, `violators.rpt`). `docs/planning/` is Planning's directory: the user copies the files and commits them. Netlists are NOT copied (1.2 MB each) unless asked. On the laptop, in the repo, with today's date as `<date>` (for example 2026-11-02):

```
mkdir -p docs/planning/synthesis-reports/round4-<date>-syn20
cp ~/server_pull/syn/syn20/unpu_top.area ~/server_pull/syn/syn20/unpu_top.power ~/server_pull/syn/syn20/unpu_top.timing ~/server_pull/syn/syn20/unpu_top.timing_top5 ~/server_pull/syn/syn20/unpu_top.constraint ~/server_pull/syn/syn20/unpu_top.qor ~/server_pull/syn/syn20/unpu_top.check_timing ~/server_pull/syn/syn20/unpu_top.check_design ~/server_pull/syn/syn20/unpu_top.profile docs/planning/synthesis-reports/round4-<date>-syn20/
```

and the same for `syn18` and `syn16` (replace the profile in both places). Add one line per folder to `docs/planning/synthesis-reports/README.md`: the profile, the date, the verdict printed by `syn_compare.sh` (PASS / MET / NOT MET with the worst slack), the cell area and the flop count. Keep the output of `syn_compare.sh` next to them:

```
SYN_OUT=~/server_pull/syn bash scripts/syn_compare.sh > docs/planning/synthesis-reports/round4-<date>-compare.txt
```

## 8. Hand-over to the layout flow

Three things go on: the **chosen profile's** `unpu_top_cn.dc.v` (clean names: 18.8), the profile name (it tells the layout flow which SDC profile to apply: `place`, `cts`, `route` use their own profiles of `constraints/unpu_top.sdc`, never the synthesis one) and the written reason for the choice (the rule of step 5 or the override).
`unpu_top_cn.sdc` is kept for reference only: the layout flow reads the profile SDC, not the SDC that DC wrote. `unpu_top_cn.ddc` is kept as well.
The `pnr/` defaults now follow `UNPU_SYN_PROFILE` (the netlist is `syn/out/<profile>/unpu_top_cn.dc.v`), and the layout flow derives its die from `syn/out/<profile>/unpu_top.area` (so copy both files of the chosen profile into the layout clone and set `UNPU_SYN_PROFILE` before `floorplan.tcl`).
