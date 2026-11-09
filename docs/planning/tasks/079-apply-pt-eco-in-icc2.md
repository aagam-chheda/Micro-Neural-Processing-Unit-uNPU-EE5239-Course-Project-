# Task 079 — Apply PrimeTime's hold ECO (and a setup ECO) in ICC2: `pnr_v2/pt_eco_apply.tcl` (step 6g) and a PrimeTime setup-ECO probe

Read first: `docs/planning/progress-log-2026-11-09.md` (3.11 and the entries below it), `docs/planning/tasks/078-pt-violation-lists-and-eco-probe.md`, `pnr_v2/pt/README.md` (section 8, the ECO probe), `pnr_v2/pt/pt_eco_probe.tcl`, `pnr_v2/antenna_port_buffers.tcl` and `pnr_v2/timing_closure.tcl` (the filler-table placement, the protection of ECO cells, the hard checks, the style), `pnr_v2/README.md`.

## What the server run of the ECO probe showed (user's run, 2026-11-09, commit `f2d96a0`)

- PrimeTime's own ECO works (`fix_eco_timing -type hold -methods {insert_buffer} -buffer_list <collection of library cells> -hold_margin 0.05`, logical only). Result in PrimeTime's memory: hold violators 263 -> 0, WNS -0.3468 -> +0.0002 ns.
- ECO summary: `Number of insert_buffer commands 109`, area increased 2687.50 um^2: `dl01d1` 64 (25.09 um^2 each), `dl02d1` 31 (28.22), `buffd1` 12 (12.54), `dl01d2` 2 (28.22). (The probe's closing line said "0 changes proposed" because its counter does not know the verb format: a bug to fix in the probe as part of this task.)
- The change files (`pnr_icc2/pt/pt_eco_hold_changes.tcl`, `pt_eco_hold_changes_icc2.tcl`: identical content, "formatted for IC Compiler", 203 lines; `pt_eco_hold_changes.txt`, 111 lines) look like:
  ```
  current_instance
  current_instance {u_apb}
  insert_buffer [get_pins {U46/Z}] dl02d1 -new_net_names {net_PTECO_HOLD_NET1} -new_cell_names {U_PTECO_HOLD_BUF1}
  current_instance
  insert_buffer [get_pins {U61/Z}] dl01d2 -new_net_names {net_PTECO_HOLD_NET2} -new_cell_names {U_PTECO_HOLD_BUF2}
  current_instance
  ```
  The `.txt` file has lines such as `16. insert_buffer in u_dma: added one 'dl02d1' 'I' to 'Z' on pin 'copt_h_inst_3080/Z' named 'net_PTECO_HOLD_NET16' 'U_PTECO_HOLD_BUF16'`. Pins are relative to the hierarchical instance named by `current_instance` (`u_apb`, `u_dma`, `u_csr`, ...; the top has an empty `current_instance`). Insertion points are driver pins (`U46/Z`, `copt_h_inst_3080/Z`), load pins (`dest_c_reg_reg_2_/D`, `copt_h_inst_3971/I`) and gate output pins (`U81/ZN`). A buffer on a DRIVER pin takes all loads of that net; a buffer on a LOAD pin isolates that one load. Reproduce exactly the pin-level topology PrimeTime assumed.
- The remaining PrimeTime violation after the hold ECO is nothing at hold; the setup violation (ss, `SETUP corner ss: WNS -0.2423 ns`, one endpoint `dma_addr[31]`, last stage `HFSINV_13_284 (inv0d4)` takes 1.61 ns into the 1.0 pF output load) is not yet covered by an ECO.
- The PrimeTime-SI licence is available (checked out during the probe).

## Part 1 — PrimeTime setup ECO probe (`pnr_v2/pt/pt_eco_setup_probe.tcl`)

A copy-by-reuse of `pt_eco_probe.tcl` for setup at ss: same preparation (`pt_prepare_session` for ss; the preparation of `pt_setup_ss.tcl`), same licence and help printing, `fix_eco_timing -type setup -methods {size_cell}` (print what `help` says about `-methods` for setup: if `size_cell` needs a list or `-cell_list`, use the real form; mark VERIFY) restricted to nothing (all setup violators; there is one). Write `pt_eco_setup_changes.tcl` / `_icc2.tcl` / `.txt`, print the AFTER setup status in PrimeTime's memory, and end with the same three-way `PROBE RESULT` line. Reuse the log parser; do not duplicate it. Also FIX the bug in the existing probe: the counter of proposed changes must understand the real verbs (`insert_buffer` lines in the `.txt`/`.tcl` format above; `size_cell` lines of the setup run) and report the number from "Final ECO Summary: Total number of commands N" first, then from the change files; the closing line must read `ECO RAN: 109 changes proposed` for the hold run. Tests with the real hold excerpt (109, area 2687.50, the cell table) and the 3 sample lines above.

## Part 2 — `pnr_v2/pt_eco_apply.tcl` (ICC2, flow step 6g)

Runs on the block `unpu_top_route` (the state after step 6e; the user takes a library backup first), overwrites it in place as `fix_antenna.tcl` and `timing_closure.tcl` do, and applies the change lists of PrimeTime: the hold file (required) and the setup file (optional, parameter; skipped with a printed line when absent).

1. Parse the change file in Tcl (pure procs, tested): tokens `current_instance {x}` (set the hierarchy for the following lines; an empty `current_instance` resets to the top), `insert_buffer [get_pins {P}] <ref> -new_net_names {N} -new_cell_names {C}`, and for the setup file `size_cell {instance} <ref>` (print the real syntax PrimeTime wrote; support what is in the file, stop with an error listing any command you do not understand). Resolve the pin as `<hierarchical instance>/<pin>` in the ICC2 design (print an error list for pins not found; nothing is applied if any is missing). Keep PrimeTime's new cell and net names (`U_PTECO_HOLD_BUF<n>`, `net_PTECO_HOLD_NET<n>`); stop if a name already exists.
2. Library cell mapping: the reference names in the file (`dl01d1`, `dl02d1`, `dl01d2`, `buffd1`) exist in `scl180_std` (take the library prefix from the design, do not type it); stop if one is missing. Check against the don't-use list of handoff 18.15 (the delay cells are normal library cells; do not use `adiode`, `bh01d1`, `cload1` or the six pattern cells) and print the table of references with counts.
3. Apply each insertion in ICC2 with `insert_buffer` (the working syntax from `antenna_port_buffers.tcl`), one change at a time, and place the new cell legally NEXT TO the pin it was inserted on: use the filler-table method of `antenna_port_buffers.tcl` (read the 21k fillers once into a table, find the free filler run nearest to the pin that fits the cell width (delay cells are wider than `buffd1`: take the width from the LEF), remove exactly those fillers, place, legalize that one cell, verify the final position equals the requested site, retry with the next candidate up to 5, tier 2 with a larger distance for crowded places; every distance limit a named parameter with a reason; a net/cell that cannot be placed is listed as FAILED and the script ends with an error before routing). Print one line per inserted cell: PrimeTime's change number, pin, reference, site, distance, OK/FAILED.
4. Protection: the 15 `antbuf_*` buffers and the clock root must be unchanged (reuse the snapshot and comparison procs of `timing_closure.tcl`; PrimeTime's insertions on the same nets as an `antbuf_*` are allowed but the antbuf cell itself must keep its reference, location and pin connections). An inserted cell on a PORT net (a net driven directly by an input port) changes the gate area seen by the port and can bring back an antenna violation: list every inserted cell whose net is a port net or is driven by the output of an `antbuf_*`, with the net name and the pin-to-load distance, as a warning block "ANTENNA WATCH" (Calibre decides afterwards; do not skip them).
5. Re-route only the touched nets (`route_eco -nets`, then `route_detail -incremental`, as the other scripts), the `connect_pg_net` and the filler re-creation as `antenna_port_buffers.tcl` does, then the hard checks, each a number and a hard `error` (nothing is saved on error): `check_routes` DRC 0 and open nets 0; `check_legality` 0; the count of inserted cells equals the count of insertions in the change file (print both: 109 expected for the hold file); every inserted cell has the reference PrimeTime wrote; the protected cells identical to the snapshot; `antbuf_*` count 15.
6. Report (not tune) timing in ICC2 before and after: `report_global_timing` setup and hold WNS/TNS/NUM per scenario, with the note that ICC2's view of the I/O paths is more lenient than PrimeTime's (insertion delay on the reference clock) and that PrimeTime is the sign-off. Print `>>> STAGE 6g COMPLETE ...`, save the block over `unpu_top_route`, `save_lib`.
7. Do NOT change any constraint, uncertainty, goal, limit or app option.

## README (`pnr_v2/README.md` and `pnr_v2/pt/README.md`)

Step 6g in the run order; the new sequence after the ECO as ONE csh command per line: backup (`cp -r blocks/unpu_top.dlib blocks/unpu_top.dlib.bak_pre_pteco`), `icc2_shell -f ../pnr_v2/pt_eco_apply.tcl |& tee pt_eco_apply_console.log`, then `metal_fill.tcl`, `pv.tcl` (it now checks the LEF and the SDF), the three Calibre runs, the two PrimeTime runs (setup ss, hold ff) and the simulation, with what to read after each (zero PrimeTime violations, antenna 0, DRC 0, LVS CORRECT). Also the order: the setup probe is run first on the server to produce `pt_eco_setup_changes.tcl`.

## Constraints that apply

"Nothing fails silently; nothing hardcoded; seeds printed; no thresholds narrowed; no constraint tuned to close timing without a written reason and user approval." No constraint, uncertainty, goal or limit changes. Do not touch the flow scripts other than as stated. No diode. Do not run anything on the server and do not commit.

## Acceptance test (local)

1. `info complete` = 1 for the new/changed Tcl files; all existing tests still pass (`test_antenna_port_buffers`, `test_antenna_clk_root`, `test_timing_closure`, `test_pv_*`, `pt/test_pt_common`).
2. New test `pnr_v2/test_pt_eco_apply.tcl` on the pure Tcl parts with the real file excerpts above: the parser (hierarchy handling, an empty `current_instance`, the three insert lines of the excerpt, an unknown command -> error), the pin-name resolution rule, the reference table, the placement candidate choice for wide cells, the count checks (109 expected, 108 found -> error). Put a copy of the first 20 lines of a real change file as test data.
3. `grep -c VERIFY` and the full VERIFY list in the READMEs.
4. `git status`: only the new/changed files under `pnr_v2/`, plus this task file.

## Report back

Files, diffs, test output, the VERIFY list, your handling of load-pin versus driver-pin insertions, where you expect placement to be crowded, what the ANTENNA WATCH block will list, anything ambiguous. Stop after reporting.
