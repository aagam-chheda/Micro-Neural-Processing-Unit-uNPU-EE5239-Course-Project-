# PrimeTime sign-off of the final layout (task 074)

PrimeTime is the authority. ICC2 says: setup WNS +0.0143 ns (`func_ss`), hold WNS about -0.0004 ns (`func_ff`, one reg-to-reg path). These scripts read what ICC2 wrote and say whether PrimeTime confirms it. Nothing has been run: the user runs it on the server. csh only, one command per line, no sentence-ending period after a command.

Nothing in PrimeTime changes a constraint: no uncertainty, limit, exception, case analysis. The only action that is not a pure read is `set_propagated_clock [all_clocks]` when the SDC did not already propagate the clocks (the script prints which case it was).

## Files

| File | Purpose |
|---|---|
| `pt_common.tcl` | paths and parameters in ONE place (top of the file), the procs; sourced by the two scripts; only `set` and `proc` at the top level, so `tclsh` can source it |
| `pt_setup_ss.tcl` | setup at the slow corner: library `tsl18fs120_scl_ss`, SPEF of `corner_ss`, `unpu_top_pnr_ss.sdc` |
| `pt_hold_ff.tcl` | hold at the fast corner: library `tsl18fs120_scl_ff`, SPEF of `corner_ff`, `unpu_top_pnr_ff.sdc` |
| `test_pt_common.tcl` | local tests of the pure-Tcl procs (`tclsh pnr_v2/pt/test_pt_common.tcl`) |

Inputs (written by `pv.tcl` into `pnr_icc2/outputs/`): `unpu_top_pnr_sim.v` (the netlist WITHOUT PG pins: PrimeTime without UPF does not know the PG pins, and `pv.tcl` renames the nets `N<digits>` to `N_uc_<digits>` only in the PG netlist, so the SPEF would not match it), `unpu_top_spef.TYPICAL_RC_125.spef`, `unpu_top_spef.TYPICAL_RC_-40.spef`, `unpu_top_spef.spef_scenario`, `unpu_top_pnr_ss.sdc`, `unpu_top_pnr_ff.sdc`, and the two kit `.db` libraries. The `.sdf` files are not needed for STA.

## 1. Environment (a terminal of its own for Synopsys tools; Calibre needs another)

```
source ~/cad_cshrc
source ~/synopsys_cshrc
which pt_shell
cd /storage/EE5239G1/aagams_workspace2/unpu
git pull
mkdir -p pnr_icc2/pt
cd pnr_icc2/pt
```

Look at the inputs first (a missing or empty file stops the scripts with a message, but it is faster to see it here):

```
ls -l ../outputs/unpu_top_pnr_sim.v ../outputs/unpu_top_spef.TYPICAL_RC_125.spef ../outputs/unpu_top_spef.TYPICAL_RC_-40.spef ../outputs/unpu_top_spef.spef_scenario ../outputs/unpu_top_pnr_ss.sdc ../outputs/unpu_top_pnr_ff.sdc
cat ../outputs/unpu_top_spef.spef_scenario
```

## 2. Run (each script in its own command; each ends with `exit`)

```
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
```

The logs are in `pnr_icc2/pt/` (the folder you are in), the reports too, with the corner in the name: `pt_setup_ss_*.rpt`, `pt_hold_ff_*.rpt`.

## 3. How the SPEF is chosen (and what to do if the script stops there)

The two SPEF files are named by temperature; the file name is NEVER used to decide. `pt_choose_spef` reads `unpu_top_spef.spef_scenario` at run time, prints its whole content (`>>> 074 content of ...`), and looks for lines (or blank-line separated blocks) that mention exactly one SPEF file (its full name, its base name, or its tag `TYPICAL_RC_125` / `TYPICAL_RC_-40`) and exactly one corner name (`func_ss` or `corner_ss` for ss, `func_ff` or `corner_ff` for ff). It stops with a `PT ERROR` that prints the content when:

- no line or block links a SPEF file to a corner (for example the text only has temperatures);
- a line names both corners or two files (ambiguous);
- the corner gets no file, or two different files;
- one file is named for both corners.

If it stops: read the printed content, decide by eye which file belongs to which scenario, and set `PT_SPEF_OVERRIDE(ss)` / `PT_SPEF_OVERRIDE(ff)` in `pt_common.tcl` to the file name (the script then prints `OVERRIDE`). Do not set it without having read the content. The mapping, once known, goes into the progress log.

## 4. What to read in the log

Lines that start with `>>> 074`, in this order:

1. `content of ...spef_scenario` and `SPEF for corner ... decided from the text`.
2. The banner (corner, library, netlist, SPEF, SDC, SI on/off).
3. `linked unpu_top: N leaf cells ... library cells missing 0`; any `PT ERROR` about unresolved references.
4. `ANNOTATION: total N, annotated N, unannotated 0`. A stop here lists some of the unannotated nets. The limit is `PT_MAX_UNANNOTATED_PCT` (0 = any unannotated net is an error).
5. `SDC text values` and `DESIGN values`, then `clock clk: period 20.0 ns, setup uncertainty 1.5 ns, hold uncertainty 0.5 ns (expected 20.0 / 1.5 / 0.5 ...)`. A different value stops the script. `clocks are propagated: the SDC already carries ...` or the line saying that `set_propagated_clock` was applied.
6. `operating conditions read from report_design`: must be the library of the corner.
7. `limit read:` lines: every `set_max_transition` / `set_max_capacitance` that PrimeTime read, and `a CLOCK-PATH limit of 0.4 ... is part of the constraints that are signed off` if the 0.40 ns clock-path limit of the example `cts.tcl` is in the SDC. The design-wide values must be 3.0 ns and 2.0 pF.
8. `check_timing: ... not in the known list`: only `pready` may be unconstrained.
9. `CTS values to compare with` and the clock reports `pt_<kind>_<corner>_clock.rpt` (min and max latency and global skew; ICC2 after CTS: about 0.59 ns latency, 0.31 ns skew).
10. The SUMMARY block at the end:

```
SUMMARY
   SETUP corner ss: WNS <x> ns, TNS <y> ns, violating endpoints <n>
   SETUP: MET            (or VIOLATED, or UNKNOWN when a number could not be read)
   SETUP WNS: PrimeTime <x> ns, ICC2 +0.0143 ns, difference <d> ns (PrimeTime minus ICC2)
```

and the same for `HOLD` with the ICC2 figure -0.0004 ns. For hold, every violated endpoint is listed (`HOLD violated endpoint ... slack ... startpoint ...`) with one report file per endpoint (`pt_hold_ff_violated_<endpoint>.rpt`): the full clock-expanded path shows the clock arrival of the launching and the capturing flop (their difference is the skew), so a one-path fix is possible.

Reports (setup): `_global_timing.rpt`, `_violators.rpt` (`report_constraint -all_violators -max_delay`), `_paths_group_<group>.rpt` (worst 10 per path group, full clock expansion), `_paths_in2out_paddr_prdata.rpt` (the combinational `paddr` to `prdata` paths), `_design_rules.rpt` (max transition, max capacitance, minimum pulse width). Hold: the same with `-min_delay` and `_paths_worst20.rpt`.

## 5. Signal integrity (crosstalk) and why the numbers can differ from ICC2

`PT_SI_ENABLE` is 0 (OFF) by default, because PrimeTime-SI may not be licensed. ICC2 computed its numbers with SI ON (`route.tcl`: `time.si_enable_analysis true`). With SI OFF PrimeTime sees no crosstalk delta delay (coupling capacitance is treated as ground capacitance), so expect PrimeTime to be the same or LESS pessimistic than ICC2: a larger setup slack and a larger (better) hold slack. A PrimeTime number that is worse than ICC2 with SI off is therefore a real finding, not a crosstalk effect. To turn SI on, set `PT_SI_ENABLE 1` in `pt_common.tcl`: the script checks the licence (`get_license PrimeTime-SI`) and stops with a message if it cannot get it. Other expected sources of difference: PrimeTime's own delay calculation and clock-reconvergence-pessimism default, which are not changed here.

## 6. Copy the results back (from a LAPTOP terminal, not from the server)

The user types the password at the prompt; nothing here contains it.

```
mkdir -p ~/server_pull/pt
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt/pt_setup_ss.log ~/server_pull/pt/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt/pt_hold_ff.log ~/server_pull/pt/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt/pt_setup_ss_violators.rpt ~/server_pull/pt/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt/pt_hold_ff_violators.rpt ~/server_pull/pt/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt/pt_hold_ff_paths_worst20.rpt ~/server_pull/pt/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/outputs/unpu_top_spef.spef_scenario ~/server_pull/pt/
```

Hold violators have their own files: copy `pt_hold_ff_violated_*.rpt` too (`scp ... pt_hold_ff_violated_*.rpt` needs the quotes escaped in csh; or copy the folder with `scp -r`).

## VERIFY table (nothing here has been run)

| # | Item | Look at |
|---|---|---|
| V1 | `pt_shell` is the T-2022.03-SP2 build and `source ~/synopsys_cshrc` puts it on the path | `which pt_shell`, the first lines of the log |
| V2 | `unpu_top_pnr_sim.v` links against the ss/ff `.db` with `link_design unpu_top` (hierarchical netlist, no PG pins) | `linked unpu_top: N leaf cells` and no `PT ERROR` |
| V3 | `set_app_var link_path [list * <db file>]` with `search_path` finds the `.db`; `target_library` is not used | `search_path:` / `link_path:` lines |
| V4 | The wording of `unpu_top_spef.spef_scenario` is what `pt_spef_decide` expects (or the stop prints it) | `content of ...spef_scenario`, the decision line |
| V5 | `read_parasitics -format spef` (and `-keep_capacitive_coupling` with SI) are accepted | the lines after `reading parasitics` |
| V6 | `report_annotated_parasitics -check` prints a net summary the parser reads | `ANNOTATION:` line (a failure to read stops the script unless `PT_ALLOW_UNREADABLE_ANNOTATION` is 1) |
| V7 | The clock attributes `period`, `setup_uncertainty`, `hold_uncertainty`, `is_propagated` exist | `DESIGN values` line (a missing one is noted and the SDC text value is used) |
| V8 | `report_design` prints `Operating Conditions: ... Library: ...` | `operating conditions read from report_design` |
| V9 | `check_timing -verbose` wording for unconstrained endpoints | `check_timing:` line (heading found, names) |
| V10 | `report_clock -skew`, `report_clock_timing -type latency|skew` | `pt_<kind>_<corner>_clock.rpt` (empty section = not available) |
| V11 | `report_global_timing` exists in this release | `_global_timing.rpt` |
| V12 | `report_constraint -all_violators -max_delay|-min_delay` and the `(VIOLATED)` wording the cross-check reads | `report_constraint text: N lines marked VIOLATED` against the endpoint count |
| V13 | `get_path_groups`, and `report_timing ... -group` | `path groups:` line and the `_paths_group_*.rpt` files |
| V14 | `get_timing_paths -delay_type -slack_lesser_than -max_paths` and the attributes `slack`, `endpoint`, `startpoint` | the SUMMARY numbers (n/a = not readable, verdict UNKNOWN) |
| V15 | `report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width` in one call | `_design_rules.rpt` |
| V16 | `get_license PrimeTime-SI` (only with `PT_SI_ENABLE 1`) | the line `SI/crosstalk analysis ON` or the stop message |
| V17 | `get_cells -hierarchical -filter "is_hierarchical == false"` and `get_lib_cells -filter "is_black_box == true"` | the `linked` line |
| V18 | The per-endpoint `report_timing -from <startpoint> -to <endpoint>` finds the objects by name | the `pt_hold_ff_violated_*.rpt` files |
