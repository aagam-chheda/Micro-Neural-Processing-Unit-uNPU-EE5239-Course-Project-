# PrimeTime sign-off of the final layout (task 074)

PrimeTime is the authority. ICC2 says: setup WNS +0.0143 ns (`func_ss`), hold WNS about -0.0004 ns (`func_ff`, one reg-to-reg path). These scripts read what ICC2 wrote and say whether PrimeTime confirms it. Nothing has been run: the user runs it on the server. csh only, one command per line, no sentence-ending period after a command.

Nothing in PrimeTime changes a constraint: no uncertainty, limit, exception, case analysis. The only action that is not a pure read is `set_propagated_clock [all_clocks]`, applied ALWAYS after `read_sdc` (the SDC text is not trusted: UITE-305 resets the clock to ideal) and then proved from a timing report.

## Files

| File | Purpose |
|---|---|
| `pt_common.tcl` | paths and parameters in ONE place (top of the file), the procs; sourced by the two scripts; only `set` and `proc` at the top level, so `tclsh` can source it |
| `pt_setup_ss.tcl` | setup at the slow corner: library `tsl18fs120_scl_ss`, SPEF of `corner_ss`, `unpu_top_pnr_ss.sdc` |
| `pt_hold_ff.tcl` | hold at the fast corner: library `tsl18fs120_scl_ff`, SPEF of `corner_ff`, `unpu_top_pnr_ff.sdc` |
| `pt_eco_probe.tcl` | task 078: read-only probe of PrimeTime's own ECO commands (hold, ff), see section 8; ends with one `PROBE RESULT` line |
| `check_annotation.tcl` | the post-run annotation check (see 3b): `tclsh` on the finished `parasitics_command.log`, same parser and policy as the scripts; prints `ANNOTATION CHECK PASSED` or `FAILED` |
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

## 3b. The parasitics log is written buffered (why the annotation check may need a second step)

PrimeTime T-2022.03-SP2 does not print the text of `read_parasitics` and `report_annotated_parasitics` into the session. It prints `Information: Log for '<command> command' will be generated in 'parasitics_command.log'. (PARA-107)` and writes the text to that file in the CURRENT directory. In the rerun the file stayed at 0 bytes during the session and was complete only afterwards, and each `pt_shell` run recreates it. The annotation check is MANDATORY (it is the proof that the parasitics of every net with timing arcs were applied), so:

1. **In-session (the method to verify on the server).** Before `read_parasitics` the script prints `printvar parasitics_log_file`, sets the variable to an empty string (`set_app_var parasitics_log_file ""`, VERIFY V19) and prints it again; the text is then expected in the session and is parsed there (`annotation table read from the session text of report_annotated_parasitics`). If this works, nothing else is needed. If it works, the README should be updated with that result.
2. **Fallback, two steps, still mandatory.** If the table is still not in the session the script STOPS and says so. To continue anyway the user declares the post-run check (csh):

```
setenv PT_ANNOTATION_CHECKED_AFTER 1
pt_shell -f ../../pnr_v2/pt/pt_setup_ss.tcl |& tee pt_setup_ss.log
cp parasitics_command.log parasitics_command_ss.log
tclsh ../../pnr_v2/pt/check_annotation.tcl parasitics_command_ss.log TYPICAL_RC_125 |& tee pt_annotation_check_ss.log
pt_shell -f ../../pnr_v2/pt/pt_hold_ff.tcl |& tee pt_hold_ff.log
cp parasitics_command.log parasitics_command_ff.log
tclsh ../../pnr_v2/pt/check_annotation.tcl parasitics_command_ff.log TYPICAL_RC_-40 |& tee pt_annotation_check_ff.log
unsetenv PT_ANNOTATION_CHECKED_AFTER
```

   The last argument is the tag of the SPEF that the script decided for the corner (the line `SPEF for corner ss decided from the text` in the log); `check_annotation.tcl` fails if that text is not in the file, which catches a file of the wrong run. The `cp` before the next run is needed because each run recreates the file. With the declaration, the log prints `ANNOTATION NOT CHECKED IN-SESSION: run check_annotation after the session` and the SUMMARY block carries the line `CAVEAT: ANNOTATION NOT CHECKED IN-SESSION ...`. The sign-off result counts only when the matching `check_annotation.tcl` run printed `ANNOTATION CHECK PASSED`. The check applies the same rules as in-session (read_parasitics errors, pin-to-pin nets not annotated above `PT_MAX_UNANNOTATED_PCT`, table consistency) and cannot be waived.
3. Without the declaration the default stands: the script stops.

## 4. What to read in the log

Lines that start with `>>> 074`, in this order:

1. `content of ...spef_scenario` and `SPEF for corner ... decided from the text`.
2. The banner (corner, library, netlist, SPEF, SDC, SI on/off).
3. `linked unpu_top: N leaf cells ... library cells missing 0`; any `PT ERROR` about unresolved references.
4. `ANNOTATION:` lines. In this PrimeTime `read_parasitics` and `report_annotated_parasitics` write their text to the file `parasitics_command.log` of the CURRENT directory (message `PARA-107`), appended by both commands; the script reads only the part each command added and prints it (`read_parasitics text from parasitics_command.log`). The table (`Net Type | Total | Lumped | RC pi | RC network | Not Annotated`) is parsed: it is an ERROR if `read_parasitics` printed `N error(s)` with N > 0, if the table cannot be found, if the rows do not add up to the total row, or if a `Pin to pin nets` row (internal or boundary) has not-annotated nets above `PT_MAX_UNANNOTATED_PCT` (0 = any). Unannotated driverless and loadless nets are INFORMATION (printed per row with the first 10 names): they have no driver or no load, so they carry no timing arc.
5. `SDC text values` and `DESIGN values`, then `clock clk: period 20.0 ns, setup uncertainty 1.5 ns, hold uncertainty 0.5 ns (expected 20.0 / 1.5 / 0.5 ...)`. A different value stops the script. The messages `UITE-305` / `UITE-489` of `read_sdc` as information, then `APPLIED: set_propagated_clock [all_clocks]`.
6. `operating conditions read from report_design`: must be the library of the corner.
7. `limit read:` lines: every `set_max_transition` / `set_max_capacitance` that PrimeTime read, and `a CLOCK-PATH limit of 0.4 ... is part of the constraints that are signed off` if the 0.40 ns clock-path limit of the example `cts.tcl` is in the SDC. The design-wide values must be 3.0 ns and 2.0 pF.
8. `check_timing: checks run: ...; findings (Warning/Error blocks): N`. The `Information: Checking 'x'.` lines are only the names of the checks and are NOT findings. Only a `Warning:`/`Error:` block is a finding: unconstrained endpoints are an ERROR unless all are in the known list (`pready`; the names are read and their number must equal the count in the message); a port without driving cell is information when it is the clock source (`clk`) and a WARNING otherwise; any other warning is printed as `WARNING check_timing:`.
8b. `PROVED: the clock is propagated`: the worst path (`report_timing -path_type full_clock_expanded`, and the default `full` form; `-delay_type max` in the setup script, `min` in the hold one) must carry `(propagated)` tags and no `(ideal)` tag. The lines `clock tag:` and `clock network delay values` show the latency. Only `ideal` or no tag at all stops the script (`PT ERROR: the clock is not proved propagated`).
9. `CTS values to compare with` and the clock reports `pt_<kind>_<corner>_clock.rpt` (min and max latency and global skew; ICC2 after CTS: about 0.59 ns latency, 0.31 ns skew).
10. The SUMMARY block at the end:

```
SUMMARY
   SETUP corner ss: WNS <x> ns, TNS <y> ns, violating endpoints <n>
   SETUP: MET            (or VIOLATED, or UNKNOWN when a number could not be read)
   SETUP WNS: PrimeTime <x> ns, ICC2 +0.0143 ns, difference <d> ns (PrimeTime minus ICC2)
```

and the same for `HOLD` with the ICC2 figure -0.0004 ns. For hold, every violated endpoint is listed (`HOLD violated endpoint ... slack ... startpoint ...`) with one report file per endpoint (`pt_hold_ff_violated_<endpoint>.rpt`): the full clock-expanded path shows the clock arrival of the launching and the capturing flop (their difference is the skew), so a one-path fix is possible.

Every violated endpoint is also in a CSV (section 7). Reports (setup): `_global_timing.rpt`, `_violators.rpt` (`report_constraint -all_violators -max_delay`), `_paths_group_<group>.rpt` (worst 10 per path group, full clock expansion), `_paths_in2out_paddr_prdata.rpt` (the combinational `paddr` to `prdata` paths), `_design_rules.rpt` (max transition, max capacitance, minimum pulse width). Hold: the same with `-min_delay` and `_paths_worst20.rpt`.

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

## 7. Every violated endpoint in a file (task 078)

Both sign-off scripts now also write `pt_setup_ss_violations.csv` and `pt_hold_ff_violations.csv` into `pnr_icc2/pt/`: ONE line per violated endpoint (the worst path to it), no limit of 50 (`get_timing_paths -slack_lesser_than 0 -max_paths PT_VIOL_MAX_PATHS -nworst 1`; a list as long as the bound `PT_VIOL_MAX_PATHS` = 100000 is an error, because it could be truncated). Columns, separated by `;`, first line is the header:

`endpoint;startpoint;startpoint_kind;endpoint_kind;slack_ns;path_group;n_cells;cells;incr_ns`

- `startpoint_kind` / `endpoint_kind`: `port` or `pin`.
- `cells`: the cells of the DATA path in order as `instance/pin(ref)` joined by `,` (a cell = an output pin of the path; the launching flop's `Q` is the first one for a register-to-register path); `incr_ns`: the incremental delay of each (same order, joined by `,`) = arrival at that pin minus the arrival at the previous path point (the `Incr` column of `report_timing`).
- Example (hold, ff): `u_dma/stage_reg_1__14_/D;dma_rdata[14];port;pin;-0.3500;clk;2;copt_h_inst_3910/Z(buffd1),U588/Z(mx02d0);0.1700,0.1200`
- A field that cannot be read is `n/a`; one `>>> 078 NOTE: <column> could not be read for N of M endpoints` line per such column.
- The log has `>>> 078 violations file: N endpoints written to <file>`, the SUMMARY block repeats it, and the count is checked against the summary count (`violating endpoints n`): a difference is an error AFTER the SUMMARY block (the message says what to suspect). Nothing else the scripts do has changed.

Copy back (laptop terminal, the user types the password):

```
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt/pt_hold_ff_violations.csv ~/server_pull/pt/
scp EE5239G1@172.16.82.70:/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt/pt_setup_ss_violations.csv ~/server_pull/pt/
```

## 8. ECO probe (`pt_eco_probe.tcl`): can PrimeTime's own ECO commands be used here?

Read-only for the design: it proposes netlist changes in PrimeTime's memory, writes reports and change files into `pnr_icc2/pt/`, and ends with `exit 0` whatever the answer. Run (one command per line, in the PrimeTime terminal as for the other scripts):

```
cd /storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2/pt
pt_shell -f ../../pnr_v2/pt/pt_eco_probe.tcl |& tee pt_eco_probe.log
```

What it does, in the log (`>>> 078`): the same preparation as `pt_hold_ff.tcl` (library, netlist, SPEF decision, SDC, annotation check, clock propagation PROVED) -> the hold violators BEFORE (CSV `pt_eco_hold_ff_before_violations.csv`) -> `help *eco*` and which of `fix_eco_timing`, `fix_eco_hold`, `write_changes` exist -> `list_licenses` lines that mention ECO and the answer of `get_license` for each name in `PT_ECO_LICENSE_TRIES` (a failure here is printed, but the ECO command is still tried, because it is the real test) -> the buffer candidates from the library (patterns `PT_ECO_LIB_PATTERNS`: name, `is_buffer`, area, delay if readable) and the list handed to `-buffer_list` (chosen by data: buffer cells only, largest delay first, ties by smaller area; by area when no delay is readable, and the line says so) -> `fix_eco_timing -type hold -methods {insert_buffer} -buffer_list ... -hold_margin 0.05` restricted to the hold violators fed by an input port (form 1: `-to <endpoints>`, form 2: `-from <input ports>`, form 3: no restriction with a NOTE; only an "unknown option" error moves to the next form) -> `write_changes` in three formats (`icctcl` -> `pt_eco_hold_changes.tcl` as the task asks, `icc2tcl` -> `pt_eco_hold_changes_icc2.tcl` because ICC2's own Tcl dialect is the one the next task would apply, `text` -> `pt_eco_hold_changes.txt`) -> the first 30 lines of the text file, the number of changes per command and per library cell -> `update_timing` and the violators AFTER (`pt_eco_hold_ff_after_violators.rpt`, `pt_eco_hold_ff_after_violations.csv`, the first 40 lines are printed).

The hold margin 0.05 ns (`PT_ECO_HOLD_MARGIN`) is on top of the 0.5 ns hold uncertainty already in the constraints: the PrimeTime and ICC2 parasitic estimates (and the ICC2 re-route after the ECO) differ by picoseconds to tens of picoseconds, and a fix that closes with exactly 0.00 would not survive that.

The LAST block of the log is the answer:

```
 ECO PROBE (hold, corner ff; hold margin 0.05 ns)
   PROBE RESULT: ECO RAN: N changes proposed, change file <path>
   PROBE RESULT: ECO NOT AVAILABLE: <message>
```

| Outcome | Meaning | Next step |
|---|---|---|
| `ECO RAN: N ...` with N close to the number of port-fed violators, and `AFTER` shows 0 hold violators | PrimeTime can propose the fix and thinks it closes hold | read `pt_eco_hold_changes_icc2.tcl` (is it ICC2 syntax? which cells?) and let the ICC2 task apply it (with the later ICC2 re-route and a new PrimeTime run) |
| `ECO RAN` but `AFTER` still shows violators | the cells or the margin are not enough, or the restriction was not accepted (NOTE line) | read which endpoints remain; the buffer list / margin are parameters at the top of `pt_common.tcl` |
| `ECO RAN: 0 changes` or the WARNING "no change line was recognised" | the change file format differs from the verbs the script counts | open the change file; the count is only a convenience, the file is the result |
| `ECO NOT AVAILABLE: ... licence ...` (an `Unable to checkout` text) | no PrimeTime ECO licence | the hold fix has to be computed from the violation CSV in ICC2 (insert a delay buffer in front of each listed `/D` pin) |
| `ECO NOT AVAILABLE: neither fix_eco_timing nor fix_eco_hold exists` | the command is not in this release | same as above |
| `ECO NOT AVAILABLE: ... rejected every form of the command` | the options differ from what is written here | read the `that form failed:` lines and the `help` output printed first; fix the option names (VERIFY V22 to V26) |

## VERIFY table (nothing here has been run)

| # | Item | Look at |
|---|---|---|
| V1 | `pt_shell` is the T-2022.03-SP2 build and `source ~/synopsys_cshrc` puts it on the path | `which pt_shell`, the first lines of the log |
| V2 | `unpu_top_pnr_sim.v` links against the ss/ff `.db` with `link_design unpu_top` (hierarchical netlist, no PG pins) | `linked unpu_top: N leaf cells` and no `PT ERROR` |
| V3 | `set_app_var link_path [list * <db file>]` with `search_path` finds the `.db`; `target_library` is not used | `search_path:` / `link_path:` lines |
| V4 | The wording of `unpu_top_spef.spef_scenario` is what `pt_spef_decide` expects (or the stop prints it) | `content of ...spef_scenario`, the decision line |
| V5 | `read_parasitics -format spef` (and `-keep_capacitive_coupling` with SI) are accepted | the lines after `reading parasitics` |
| V6 | `report_annotated_parasitics -check -internal_nets -boundary_nets` and the text in `parasitics_command.log` (PARA-107); the table wording the parser reads | the `ANNOTATION:` lines; `parasitics_command.log` in `pnr_icc2/pt/` (a failure to find the table stops the script unless `PT_ALLOW_UNREADABLE_ANNOTATION` is 1) |
| V7 | The clock attributes `period`, `setup_uncertainty`, `hold_uncertainty` exist (`is_propagated` is no longer read) | `DESIGN values` line (a missing one is noted and the SDC text value is used) |
| V8 | `report_design` prints `Operating Conditions: ... Library: ...` | `operating conditions read from report_design` |
| V9 | The wording of the `Warning:` block for unconstrained endpoints (`There are N unconstrained endpoints` followed by a list; the real text of the no-driving-cell warning is tested) | `check_timing:` lines (a count that differs from the names read stops the script) |
| V10 | `report_clock -skew`, `report_clock_timing -type latency|skew` | `pt_<kind>_<corner>_clock.rpt` (empty section = not available) |
| V11 | `report_global_timing` exists in this release | `_global_timing.rpt` |
| V12 | `report_constraint -all_violators -max_delay|-min_delay` and the `(VIOLATED)` wording the cross-check reads | `report_constraint text: N lines marked VIOLATED` against the endpoint count |
| V13 | `get_path_groups`, and `report_timing ... -group` | `path groups:` line and the `_paths_group_*.rpt` files |
| V14 | `get_timing_paths -delay_type -slack_lesser_than -max_paths` and the attributes `slack`, `endpoint`, `startpoint` | the SUMMARY numbers (n/a = not readable, verdict UNKNOWN) |
| V15 | `report_constraint -all_violators -max_transition -max_capacitance -min_pulse_width` in one call | `_design_rules.rpt` |
| V16 | `get_license PrimeTime-SI` (only with `PT_SI_ENABLE 1`) | the line `SI/crosstalk analysis ON` or the stop message |
| V17 | `get_cells -hierarchical -filter "is_hierarchical == false"` and `get_lib_cells -filter "is_black_box == true"` | the `linked` line |
| V18 | The per-endpoint `report_timing -from <startpoint> -to <endpoint>` finds the objects by name | the `pt_hold_ff_violated_*.rpt` files |
| V19 | `parasitics_log_file`: `printvar` shows its value; `set_app_var parasitics_log_file ""` makes `read_parasitics` / `report_annotated_parasitics` print into the session | the lines `parasitics_log_file before:` / `after:` and `annotation table read from the session text` |
| V20 | `report_timing -path_type full_clock_expanded` (and `full`) prints `clock network delay (propagated)` for a propagated clock | the `clock tag:` lines after `clock path of the worst ... path` (if only `full_clock_expanded` omits the tag, the `full` report supplies it) |
| V21 | `get_attribute [get_clocks clk] sources` gives the clock source port (used to recognise the `clk` port in the no-driving-cell warning) | the line `NOTE: the clock source port could not be read ...` (then the clock name `clk` is used) |
| V22 | `get_timing_paths -slack_lesser_than 0.0 -max_paths N -nworst 1` returns one path per violated endpoint, and the path attributes `endpoint`, `startpoint`, `slack`, `path_group`, `points`; the point attributes `object`, `arrival`; the pin attributes `object_class`, `direction` | the `>>> 078 NOTE: <column> could not be read` lines and the `cells` / `incr_ns` columns of the CSV (`n/a` = not readable); the CSV count against the summary count |
| V23 | `help *eco*`, `info commands` list `fix_eco_timing` / `fix_eco_hold`, `set_eco_options`, `write_changes` | the `ECO commands known to this pt_shell` block and the `existing:` line of `pt_eco_probe.log` |
| V24 | `list_licenses` and `get_license <feature>`; the feature name `PrimeTime-ECO` is only TRIED | the `get_license ...:` lines, `list_licenses lines that mention ECO` |
| V25 | `get_lib_cells <lib>/dl*`, the lib cell attributes `is_buffer`, `area`, and the lib timing arc attributes `delay_max_rise/fall`, `delay_min_rise/fall` | the candidate table (delay `n/a` = not readable, then the list is by area and the line says so) |
| V26 | `set_eco_options -log_file`; `fix_eco_timing -type hold -methods {insert_buffer} -buffer_list ... -hold_margin ...` and a restriction by `-to` or `-from` | the `trying:` and `that form failed:` lines |
| V27 | `write_changes -format icctcl`, `icc2tcl` or `text` with `-output <file>`; the verbs of the change file (`insert_buffer`, `size_cell`, ...) | the `write_changes -format ...` lines, the first 30 lines of the text file, the per-command counts |

## Known messages (harmless unless stated)

- At the start: optional-licence errors for `Synopsys-Release`, `PrimeTime-New-Technology`, `PT-063` (Library Compiler path) and `PrimeTime-C-Interface`: features that are not used; harmless.
- `UITE-305` `Converting a propagated clock 'clk' to an ideal clock`: the order of the SDC makes a later `create_clock` reset the clock; this is why the script applies `set_propagated_clock [all_clocks]` itself after `read_sdc` and proves it (step 8b).
- `UITE-489` `Setting input delay on clock port (clk) relative to a clock (clk) defined at the same port. Command is ignored`: harmless, the input delay on the clock port itself has no meaning.
- `Warning: There is 1 port with parasitics but with no driving cell. Ports clk`: the clock source port, expected; printed as information.
