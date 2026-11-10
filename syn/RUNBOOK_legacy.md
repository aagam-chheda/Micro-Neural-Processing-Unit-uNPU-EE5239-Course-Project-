# syn/RUNBOOK_legacy.md -- synthesis with the OLD constraints into `syn/out/legacy/` (task 064)

Clean-slate run (user decision 2026-11-02). Server login shell is **csh**; one command per line. Things not checked without the server are **VERIFY**.
Script: `constraints/legacy/dc_script_legacy.tcl`. SDC: `constraints/legacy/unpu_top_legacy.sdc` (byte-identical to `git show 925bfa9:constraints/pm_unpu_top.sdc`).
Old numbers: period 20 ns, setup uncertainty 1.5, hold uncertainty 0.5, APB 35/35, DMA 40/40, `rst_n` 40, min delays 0 / -0.5. They are the user's decision: do not edit the SDC or the script to close timing.

## 1. Run (from the repo root of the server clone)

**RUN_DIR** is the folder of the clone you run in (for example `/storage/EE5239G1/aagams_workspace2/unpu_run2`; the name does not matter, run 1 is the clone `unpu`). Set it once per terminal (csh): `setenv RUN_DIR <full path of the clone>`. In the `scp` lines (typed on your own machine) write the path itself where `<RUN_DIR>` stands. (The DC script of this runbook uses the current directory, so start it in the clone you mean.)

```
cd $RUN_DIR
git pull
source ~/cad_cshrc
source ~/synopsys_cshrc
mkdir -p syn/out
dc_shell -f constraints/legacy/dc_script_legacy.tcl |& tee syn/out/legacy_dc.log
```

(`git pull` needs a clean clone. The `pnr_v2/` scripts expect the files at `<this folder>/syn/out/legacy/`, so this folder is the one the layout flow runs in.)
Stub-test of the script, no tool needed (laptop or server): `tclsh constraints/legacy/test_legacy_dc_script.tcl` prints `ALL TESTS PASSED`.

## 2. What to look at

```
grep -c "^Error:" syn/out/legacy_dc.log
grep "^Info: .unpu" syn/out/legacy_dc.log
ls syn/out/legacy
head -n 1 syn/out/legacy/unpu_top.profile
ls
```

- `grep -c "^Error:"` prints `0`. A guard of the script prints `Error: unpu DC script: ...` and `STOPPED with exit 1`; the log ends there. Send the log to Planning.
- `Info: [unpu]` lines, in order: `legacy constraints: period 20.0 ns, setup uncertainty 1.5 ns, hold uncertainty 0.5 ns (from constraints/legacy/unpu_top_legacy.sdc); scratch directory .../syn/out/work/legacy`; after `read_sdc` `clock clk period read back from the tool: 20.0 ns (SDC CLK_PERIOD: 20.0 ns) OK`; at the end `DONE legacy: 9 reports and 5 netlist/SDC/ddc files in .../syn/out/legacy, scratch files in .../syn/out/work/legacy`.
  If there is `Warning: unpu DC script: cannot read the period of clock clk back from the tool ...` the attribute name is wrong in this DC version (VERIFY item): the run is valid, tell Planning.
- `ls syn/out/legacy` shows EXACTLY these 14 files (the script checks this itself and prints `Error: unpu DC script: output check: ...` for a missing, extra or empty file; there is no SDF in this flow):
  `unpu_top.area unpu_top.power unpu_top.timing unpu_top.timing_top5 unpu_top.constraint unpu_top.qor unpu_top.check_timing unpu_top.check_design unpu_top.profile unpu_top.dc.v unpu_top.sdc unpu_top_cn.dc.v unpu_top_cn.sdc unpu_top_cn.ddc`.
  The first line of each of the first nine begins `# legacy constraints: period 20.0 ns, ...`.
- `ls` in the repo root shows no `UNPU_*.mr`, `unpu_*-verilog.pvl`, `default.svf`, `alib-*` (they are in `syn/out/work/legacy/`, git-ignored).

Reports (all constraints met except `max_area`, which the PM's `set_max_area 0` always reports violated):

```
cat syn/out/legacy/unpu_top.constraint
grep -i "latch" syn/out/legacy/unpu_top.* syn/out/legacy_dc.log
grep "Number of sequential cells" syn/out/legacy/unpu_top.qor
grep -E "Total cell area|Total area" syn/out/legacy/unpu_top.qor
grep -c "Warning" syn/out/legacy/unpu_top.check_timing
grep -E "^Error" syn/out/legacy/unpu_top.check_design
grep -E -c "^ *(slnht|skbrb|slbhb|slnhn|slnln|mx08d)[a-z0-9_]* " syn/out/legacy/unpu_top_cn.dc.v
```

Expected:
- `unpu_top.constraint`: only `max_area`; a `max_transition`, `max_capacitance` or `max_delay/setup` entry is a finding (report it, do not change the SDC).
- no `latch` line anywhere (the grep prints nothing).
- sequential cells **2465** (RTL unchanged); another number is a finding.
- total cell area: not known in advance for these constraints; copy the number into the message to Planning (the layout core area is cell area / 0.60).
- `check_timing`: 0 warnings; `check_design`: no `Error` lines (only the benign LINT-28/32/33 warnings of handoff 18.8).
- the last grep (the six don't-use patterns of `syn/dc_setup.tcl`) prints `0`. NOTE: neither the committed DC script nor this one reads `syn/dc_setup.tcl` or calls `set_dont_use`, so a non-zero count is possible; it is reported, not worked around.
- worst setup slack in `unpu_top.timing_top5`: reported. Hold is not checked in synthesis.

## 3. Copy-back (laptop terminal, WSL; the password is typed there, never in a command or a file)

```
mkdir -p ~/server_pull/syn
scp -r EE5239G1@172.16.82.70:<RUN_DIR>/syn/out/legacy ~/server_pull/syn/
scp EE5239G1@172.16.82.70:<RUN_DIR>/syn/out/legacy_dc.log ~/server_pull/syn/legacy/dc.log
```

## 4. Follow-up

1. Gate-level simulation of `syn/out/legacy/unpu_top_cn.dc.v` (next task).
2. Layout: `pnr_v2/` (see `pnr_v2/README.md`): `design_setup.tcl` reads `syn/out/legacy/unpu_top_cn.dc.v` and `unpu_top_cn.sdc` (the `write_sdc` output of this run, which carries the ss operating condition; `pnr_v2/design_setup.tcl` sets the ff condition for the hold scenario).
