# Task 073 — Bring the repo in line with the first LVS run (`lvs.ctrl`, runbook) and fix the LEF export in `pv.tcl`

Read first: `docs/session-handoff.md` 18.25 (the LEF pitfall: `create_frame` and `write_lef -include cell`), 18.32 (the `pv.tcl` run: LEF with 122 MACROs and no `unpu_top` macro), 18.34 (the LVS run), `pnr_v2/pv.tcl`, `pnr_v2/calibre/lvs.ctrl`, `pnr_v2/calibre/README.md`, `pnr_v2/README.md`, and the server data on this machine in `/home/aagam_chheda/server_pull/calibre/run1/lvs/` (`unpu_top.lvs.rpt`, `lvs.log`).

## Part A — `lvs.ctrl` and the Calibre runbook (facts from the server run)

- The LVS ran and the result is `CORRECT` (44,615 nets, 67,472 instances matched, all 204 signal ports + VDD/VSS matched by name) after exactly two changes to the control file used on the server (a COPY in the run folder): (1) the two lines `VIRTUAL CONNECT COLON NO` and `VIRTUAL CONNECT REPORT NO` were deleted (error SPC1 "superfluous specification statement: virtual connect colon", the deck sets it itself at line 257); (2) the line `#define FILTER_DWN2PSUB` was added after `#define 4M1L`.
- Written reason for (2), approved by the user on 2026-11-09: the layout has one extra device `D(DWN2PSUB)` (N-well to P-substrate diode, 76 parallel diodes reduced to 1, from the N-well of the `feedth*` filler cells); it is a parasitic junction with no schematic equivalent; the kit CDL defines `feedth`, `feedth3`, `feedth9` as EMPTY subcircuits so the source cannot carry it; the deck provides `FILTER_DWN2PSUB` (`LVS FILTER D(dwn2psub) OPEN`, deck lines 4016 to 4018) for this. Nets and instances match 100 percent with it. `BLOCK_DWN2PSUB` (extraction off) was not used.

Do:
1. `pnr_v2/calibre/lvs.ctrl`: remove the two `VIRTUAL CONNECT` lines and their comment, add `#define FILTER_DWN2PSUB` after `#define 4M1L` with a comment giving the reason above in 3 lines and "user approved 2026-11-09". Keep every other line. Show the diff.
2. `pnr_v2/calibre/README.md`: update steps 6 to 8 with what the real run showed: the metal-level `#define` of the deck (`4M1L` maps to `4LM`), that the deck already sets `LVS POWER NAME`/`LVS GROUND NAME`, the duplicate-statement error and its cure, the `FILTER_DWN2PSUB` decision and its reason, the `v2lvs` facts (the 'No module declaration' warnings are normal because the cell pin order comes from the CDL; the `-s0/-s1` mapping is not needed when the netlist has no `1'b0/1'b1`, check with the grep of step 7), the real result lines to read (`LVS completed. CORRECT.` in `lvs.log`; the transformed-object counts; 'Initial Correspondence Points' list the matched ports), and the benign messages (ambiguity warning for the 22 unused `paddr` inputs). Replace the VERIFY items V11 to V16 that the run settled by the answer (keep the ones it did not settle). State that LVS, DRC and antenna must all be re-run after every change of layout or netlist (6c, 6d, 6e, any ECO). One command per line, csh, no sentence-ending period after a command.
3. Do not change `drc.ctrl` or `ant.ctrl`.

## Part B — LEF export in `pv.tcl`

Problem (log of the run, handoff 18.32): `outputs/unpu_top.lef` has 122 `MACRO` entries, all standard-cell masters (first `inv0d4`, last `feedth`), and NO macro `unpu_top`. `pv.tcl` runs `write_lef -design ${current_block_name} ${OUT_DIR}/${DESIGN_NAME}.lef` with no frame view. The deliverable for the top-level team is the LEF of the macro (the block abstract: its size, pins, layers, obstructions), not the library cells.

Do, in `pnr_v2/pv.tcl` only, with `;# 073:` markers, the minimal change that makes the file hold ONE `MACRO unpu_top` and the technology needed for it, following what worked in the old flow (handoff 18.25: `create_frame -block_all true` leaves one frame per block, so use `write_lef -design <the current block> -include cell`, and that gives one macro; check the real option text in `/home/aagam_chheda/server_pull/rpt/help` and write down what you verified and what is `VERIFY`). Requirements:
1. Name: the macro must be called `unpu_top` (the design name), not `unpu_top_filled` or `unpu_top_route`. The block name is not the cell name; handle this (for example by naming the frame/cell, or by a final `sed` on the one `MACRO` line, with a check that exactly one line was changed and that the `END` line matches); explain the choice.
2. Checks inside `pv.tcl` after the write, hard `error` (so the export does not look successful): the file exists and is non-empty; exactly one `MACRO unpu_top` line and one `END unpu_top` line; the number of `PIN` entries of that macro equals the number of signal ports plus power ports found in the design (print both numbers; 204 signal + VDD + VSS expected); the `SIZE` of the macro equals the die box (885.6 x 885.6 um expected) to 1e-3 um. Print the counts.
3. Do not change anything else in `pv.tcl` EXCEPT the following small fix of an error seen in the log: the report `report_constraints -all_violators` (or whichever command printed `Error: None of the specified scenarios are active for hold analysis. (UIC-057)`) ran while `func_ss` was current; make that report run for the scenario(s) that support it (setup in `func_ss`, hold in `func_ff`), as the script already does for the timing reports, with a `;# 073:` marker. If you cannot identify the command, say so and leave it.
4. Do not touch `write_gds`, `write_def`, parasitics, netlists, SDC/SDF, `-units 1000`, the layer map (the `GDS-017` message stays; the LVS run shows the pin labels are read correctly).

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." Do not run anything on the server, do not commit. Do not edit any other flow script.

## Acceptance test (local, no server)

1. `diff` of `pnr_v2/calibre/lvs.ctrl` against `git show HEAD:pnr_v2/calibre/lvs.ctrl` (paste it); `info complete` = 1 for `pnr_v2/pv.tcl`; `diff` of `pnr_v2/pv.tcl` against `git show HEAD:pnr_v2/pv.tcl` (paste it; every changed line has a `073` marker).
2. A small test `pnr_v2/test_pv_lef_check.tcl` (passes with `tclsh`) for the pure-Tcl LEF check: write sample LEF texts (one correct macro; the real bad case with 122 library macros and no `unpu_top`; two `unpu_top` macros; wrong SIZE; wrong PIN count) and check that the check function accepts the first and rejects the others with a clear message. The check function must be in a form that the test can source without ICC2.
3. `git status`: only `pnr_v2/calibre/lvs.ctrl`, `pnr_v2/calibre/README.md`, `pnr_v2/pv.tcl`, `pnr_v2/test_pv_lef_check.tcl`, `pnr_v2/README.md` if you add one line to its run order for the `pv.tcl` LEF check, plus this task file.

## Report back

Files changed, the diffs, the test output, what you verified in the help texts and the `VERIFY` list for the LEF commands (with what to look at in the `pv` log: the LEF check lines), anything ambiguous. Stop after reporting.
