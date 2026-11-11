# Task 035 — Design Compiler bring-up scripts, first on `unpu_pe`, then `unpu_top`

## Goal

Write the scripts that take the frozen RTL through Design Compiler
(`dc_shell`, T-2022.03-SP5) with the SCL 180 nm libraries and the SDC from
task 034, and write a small summary script so the results are quick to read.
The user runs them on the server and pastes results back. You cannot run any
Synopsys tool here (they are on the server only), so this task is scripts
written and checked statically, then the results analysed when the user
returns with logs (Part B).

Context: back-end flow is fixed in `docs/session-handoff.md` §18 (Design
Compiler, ICC2, Calibre, PrimeTime, Xcelium). Read §18 fully first: it holds
the SCL kit paths, corners, don't-use cells, licence findings and the server
setup.

**RTL is frozen** (`git diff 9f5deab..HEAD -- rtl/` is empty and must stay
empty). Standing rules apply: nothing fails silently, nothing hardcoded, no
constraint value tuned to make timing pass, stop and report real failures in
full.

## Part A — what to write

### A1. `syn/dc_setup.tcl` — libraries and don't-use cells

- Target library: the **ss** `.db` of the FS120 4M1L library, library name
  `tsl18fs120_scl_ss` (typical corner does not exist; ss is the setup
  corner). `link_library` is `*` plus the target library. Use the `.db`, not
  the `.lib`.
- Path: build it from a variable `SCL_KIT_ROOT` that defaults to
  `/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180` and can be overridden from the
  environment (`$::env(SCL_KIT_ROOT)`). The file is
  `stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db` (note the
  directory really is spelled `4M1IL`). If the file does not exist, stop with
  a loud error naming the path. Do not fall back to anything else.
- **Never** point at `$FOUNDRY`, `$STDCELL` or anything under
  `/home/Cadence_tools/FOUNDRY`: that is a generic TSMC-style kit, not SCL
  (handoff §18.4).
- **Don't-use cells** (`doc/std_cell_guidelines.pdf`): `slnht*`, `skbrb*`,
  `slbhb*`, `slnhn*`, `slnln*`, `mx08d*`. Keep them in one list variable at
  the top, with the source noted in a comment. Apply `set_dont_use` per
  pattern. For each pattern, print how many library cells it matched; a
  pattern that matches **zero** cells is printed as a warning line, not
  skipped silently (it may mean a wrong name or a wrong library).
- Print `report_lib` (or the equivalent) into the log so the library's units,
  operating condition and cell count are on record. Do not set operating
  conditions yourself; the library's own default is used, and the log must
  show which.

### A2. `syn/dc_run.tcl` — the run

- Take the design name from `$::env(DESIGN)`. It must be `unpu_pe` or
  `unpu_top`; anything else, or unset, is a loud error.
- Paths: derive the repo root from the script location
  (`[file dirname [file normalize [info script]]]`), no absolute repo paths.
  Write everything under `syn/out/$DESIGN/` (create it), and run with that as
  the working directory so DC's own droppings (`default.svf`, `WORK/`,
  `command.log`) land there and nowhere else.
- RTL file list: `unpu_pe` reads only `rtl/unpu_pe.sv`. `unpu_top` reads
  all eleven files in `rtl/` (list them explicitly in one variable; do not
  glob, so a stray file is not silently included). `analyze -format sverilog`,
  then `elaborate $DESIGN`, `current_design`, `link`. Every `Error`, and any
  unresolved reference, stops the run.
- Constraints: `read_sdc` (or `source`) `constraints/$DESIGN.sdc`. See A4
  for the `unpu_pe` SDC. Stop on any error from it.
- Compile with plain `compile`. Reason: `DC-Expert` is confirmed on the
  licence server; `compile_ultra` needs licence features nobody has checked.
  Do not use `compile_ultra`; do not add compile options that are not needed.
  (Say this in a comment.)
- Checks and reports, each to `syn/out/$DESIGN/rpt/<name>.rpt`:
  `check_design` (before and after compile), `check_timing`,
  `report_port -verbose`, `report_clock`, `report_constraint -all_violators`,
  `report_timing` (setup, `-delay_type max`, several paths, all path groups),
  `report_area`, `report_power`, `report_qor`, `report_hierarchy`,
  `report_reference`. **No hold report:** DC runs only the ss library, so hold
  is meaningless here; hold is checked in PrimeTime with the ff library. Say
  that in a comment.
- Outputs: gate-level Verilog netlist `write -format verilog -hierarchy`,
  the `.ddc`, and `write_sdc` of the constrained result, all in
  `syn/out/$DESIGN/`.

### A3. `scripts/dc_summary.sh` — quick read of a run (bash)

Given a design name, print from `syn/out/$DESIGN/`: the count of `Error:` and
`Warning:` lines, and the **distinct warning message IDs with counts** (so
nothing hides in a long log); any line containing `latch` (case-insensitive);
any `unconstrained` from `check_timing`; the worst setup slack per path
group; the total cell count and area; and a scan of the netlist that prints
every cell instance whose reference name matches a don't-use pattern (the
same patterns as `syn/dc_setup.tcl`, taken from one shared list; expected
count: 0). A missing report file is printed as MISSING, never treated as OK.
Test it locally on a small made-up sample directory, and say that you did.

### A4. `constraints/unpu_pe.sdc` — bring-up constraints for the PE alone

New file, same style and the same rules as `constraints/unpu_top.sdc`: header
with assumptions, variable block, explicit port lists (no `all_inputs` /
`all_outputs`), every number a named variable, only `CLK_PERIOD` a project
fact, all else labelled ASSUMPTION, no false path on reset if the PE has one.
Take the port list from `rtl/unpu_pe.sv`. Its header must say that this file
exists only so the single module can be synthesised on its own as a first
check, and is **not** the constraint set for the hard macro. Use the same
placeholder fractions as the top SDC.

### A5. Add `set_units` to both SDC files

Add `set_units -time ns` to `constraints/unpu_top.sdc` (a small, additive
edit; the diff must show additions only, 0 lines removed) and to the new
`constraints/unpu_pe.sdc`. Reasons to put in the comment: the ss library
declares `time_unit : 1ns` (read from its `.lib` header on the server; the ff
library's header was not read, so it is assumed to match and must be confirmed
before PrimeTime), and every number in the SDC is a time.

Time only. **Do not** set a capacitance unit yet: the library's capacitive
unit was not read, and no capacitance is used until `set_load` is added. Say
in a comment that the capacitance unit is added together with `set_load`.
Place it before the variable block, add no numeric literals (the
no-bare-numbers rule still holds), and update the header's "Time unit" note
only if it needs to mention the new line. If DC rejects the command, that is
a finding: the run script must not remove it silently, and your summary must
report the exact message.

Have the run script print `report_units` (or the library's unit lines) into
the log, so any mismatch between the SDC and the library is visible.

### A6. `.gitignore`

Add an ignore rule for `syn/out/` (logs, netlists and reports are generated
and stay untracked, same as any other generated output in this repo; follow
whatever the repo already does for `xrun_out/`).

## Part A — checks you can run

1. Tcl syntax: `tclsh` is now installed. Source each new `.tcl` and `.sdc`
   under a stub interpreter (an `unknown` handler that logs the commands and
   returns empty) with `DESIGN` set to both allowed values, and show that the
   file parses and reaches the end. State what this proves (valid Tcl) and
   what it does not (that DC accepts each command and option). The library
   file-existence guard is expected to trip locally, because the kit is on the
   server: make the guard testable (for example by overriding
   `SCL_KIT_ROOT` to a scratch directory containing a dummy `.db` file) and
   show it fires with the real path, and passes with the dummy.
2. `bash -n` and a sample run for `scripts/dc_summary.sh`.
3. `git diff 9f5deab..HEAD -- rtl/` empty. `git diff --stat` shows only the
   files listed in Part A, and the change to `constraints/unpu_top.sdc` is
   additions only.
4. Port coverage for `constraints/unpu_pe.sdc`, same table as task 034: every
   port of `unpu_pe` is constrained or is the clock.

## Part B — after the user's server run

You cannot run this. At the end of Part A hand the user the exact command
block for the server (csh; the server login shell is csh), for example:

```csh
cd ~/aagams_workspace/unpu
git pull --ff-only
source ~/cad_cshrc
source ~/synopsys_cshrc
setenv DESIGN unpu_pe
mkdir -p syn/out/$DESIGN
cd syn/out/$DESIGN
dc_shell -f ../../dc_run.tcl |& tee dc.log
cd ../../..
bash scripts/dc_summary.sh unpu_pe
```

(Adjust as your scripts need; test nothing in csh that you have not written
csh-safely: no `2>`, quote braces.) Then the same with `unpu_top`. Tell the
user exactly what to paste back: the summary output, and the full log if the
summary shows any error, latch, unconstrained port, negative slack or
don't-use hit.

When the user pastes results, analyse them:
- **Any `Error:` stops everything.** Report it in full with the line and its
  cause; do not work around it.
- Every distinct warning ID: explain it or mark it unexplained. Unexplained
  warnings are reported, not waived.
- **Latches must be zero.** Any inferred latch is a finding; the RTL is
  frozen, so report and stop.
- Unconstrained ports, `check_timing` complaints, unresolved references,
  don't-use hits: report.
- Negative setup slack: report it with the path. **Do not change any
  constraint or budget to make it pass.** The user and Planning decide.
- Report whether `set_units -time ns` was accepted.
- State what DC does **not** tell us: no hold analysis, no wire delay from
  layout, ss library only, assumed I/O budgets.

## Acceptance

- Part A files exist as specified; checks above shown; RTL untouched.
- The server command block is in your report, with the list of what to paste.
- Committed and pushed (`git pull --rebase origin main` first if rejected).
  Commit message ends with `Co-Authored-By: Claude Sonnet 5.5
  <noreply@anthropic.com>`.
- Part B is done when the user has pasted the `unpu_pe` and `unpu_top`
  results and you have reported per the list above. If the run cannot start,
  stop after Part A and say what is blocking.

## Out of scope

- No RTL, testbench or model change. No change to any budget value in the
  SDC files. No `set_driving_cell`, `set_load`, `set_clock_transition`,
  design-rule limits or `set_units` for capacitance: those wait for data or
  for DC's report.
- No ICC2, PrimeTime or Calibre setup. No gate-level simulation.
- No `compile_ultra`, no hierarchical synthesis, no retiming, no DFT.
- No editing of `docs/planning/`.
