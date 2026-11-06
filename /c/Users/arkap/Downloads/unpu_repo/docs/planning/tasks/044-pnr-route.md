# Task 044 — back-end re-run, script 6: `pnr/route.tcl` (antenna rule first, then routing and route optimisation)

Read first: `docs/planning/backend-rerun-plan.md` (stage D and its antenna discussion), `pnr/README.md`, the current
`pnr/*.tcl`, `docs/session-handoff.md` 18.20 (`route_auto`, `route_opt`, the checks and what they did not do), 18.22
(the last paragraphs: `route_opt` deletes all fillers), 18.25 and 18.26 (the antenna rule that worked in ICC2 and
what ICC2 cannot see), 18.27 (why the port nets matter).

## Goal

One script that opens the block after clock optimisation, defines the antenna rule BEFORE any routing, routes,
optimises, checks everything the way the first run did (and the antenna and port-net facts it learned), and saves
the routed, unfilled block. Fillers are NOT inserted here (they are the last step and `route_opt` removes them).

## Part A — what to write

### A1. `pnr/route.tcl` — runs in `icc2_shell` (U-2022.12-SP3)

Same header style as `pnr/cts.tcl`. Behaviour, in this order:

1. `unpu_require_tool_version`, `UNPU_CHECK_CONTINUE 1`, `unpu_stage_begin route run <library>`; the library must
   exist; refuse to run if `$BLK_ROUTE_AUTO` or `$BLK_ROUTED` already exists (new parameter `BLK_ROUTE_AUTO`, default
   `routeauto`); open `$BLK_CLKOPT`. The block must have no routed nets yet (VERIFY how to tell; if it cannot be told,
   say so in a Warning). `check_legality` on it must be 0 (CHECK; stop if not).
2. The antenna rule, before any route command (18.25: `define_antenna_rule -mode 4 -diode_mode 1 -metal_ratio <r>
   -cut_ratio 0`, which applied to M1, M2, M3 and TOP_M): `define_antenna_rule -mode $ANT_MODE -diode_mode
   $ANT_DIODE_MODE -metal_ratio $ANT_RATIO -cut_ratio $ANT_CUT_RATIO`. Then print the antenna-related application
   options with their values (`get_app_options route.detail.antenna*`; VERIFY the form). The first run's routing log
   said "Turn off antenna since no rule is specified" / `ZRT-309`; here that message must NOT appear in the routing
   output: count the occurrences of `ZRT-309` in the output of every route command and make it a CHECK (0). Do NOT set
   any diode option (`adiode` cannot be used; 18.25 shows diode insertion failing with `ZRT-301/302`) and do not set
   `route.detail.antenna_fixing_preference` (its valid values are unknown until the help probe is read). The metal
   ratio here is `ANT_RATIO` (300), stricter than Calibre's 400, for the reason in the plan (2.3 D3).
3. `route_auto` (18.20), output captured. Parse, with pure-Tcl procedures in `common.tcl`: the detail-route
   iteration lines (violations per iteration; the first run had 4 in iteration 0 and 0 in iteration 1, "Finish DR since
   reached 0 DRC"), the total wire length and the per-layer wire lengths, the number of contacts / vias, and the
   open-net count. RESULT lines for all of them. Count the message ids with prefix `ZRT-` and print them (a new ZRT
   message must be visible). Checkpoint `unpu_checkpoint $BLK_ROUTE_AUTO` only if the checks of step 4 pass (see 4).
4. Checks after `route_auto`, same as after `route_opt` in step 6, but the hold check is a Warning here (the first run
   had a hold residual of -0.01 ns after `route_auto` which `route_opt` cleared). If the checks that must pass fail
   (open nets, DRC, shorts), stop WITHOUT saving; otherwise save `$BLK_ROUTE_AUTO` (the fallback if `route_opt` goes
   wrong, as `unpu_top_routed` was in the first run).
5. `route_opt` (18.20), output captured. Count and print message ids with prefixes `ZRT-`, `OPT-`, `FLW-`; the first
   run printed `OPT-209` ("unreasonable large hold violation") twice with a clean QoR: report the count and say in the
   Warning that the QoR decides, and if the output says that fillers were deleted, say so (there are none here).
6. Checks after `route_opt` (18.20), one `unpu_check_pass` each, every unreadable value FAILS as "unavailable":
   - `check_routes`: parse the "Verify Summary" block of its output, whose lines are known from the first run:
     `Total number of nets = N, of which 0 are not extracted`, `Total number of open nets = 0, of which 0 are frozen`,
     `Total number of DRCs = 0`, `Total number of antenna violations = 0`, and the two "tie to rail ... not checked"
     lines: CHECK open nets 0, DRCs 0, antenna violations 0; RESULT the net count; the tie-to-rail lines are RESULT
     `not checked` (a known gap, 18.20); also count the `ZRT-311` lines ("Skipping antenna analysis for net X ...
     not enough gate area information") and print the net names as RESULT `antenna_port_nets_skipped` (80 in the first
     run): ICC2 does not analyse input-port nets, so "antenna 0" here is NOT the final word and Calibre decides;
     say that in the log;
   - `check_lvs`: 0 shorts, 0 opens, 0 floating routes (VERIFY the text; 18.20 gives the numbers);
   - `check_legality`: 0; `check_pg_connectivity`: 0 floating cells, wires, vias (including the stripes' terminals);
   - setup (in `$SCEN_SETUP`): violating endpoints 0 and the worst slack; hold (in `$SCEN_HOLD`): violating endpoints
     0 and the worst slack. Reuse `ct_paths` / `ct_timing_summary` from `cts.tcl` by moving them into `common.tcl`
     (a shared procedure, not a copy). HOLD IS A CHECK HERE (plan D2: setup and hold met in both scenarios). If the
     hold check fails, the script stops without saving UNLESS the environment variable `UNPU_ROUTE_ACCEPT_HOLD` is
     `1`: then it saves, records `hold_accepted = 1` and the endpoint list in the manifest, and prints a Warning with
     the worst 10 endpoints. That switch exists so the user can decide consciously (with a written reason) to go on
     with a hold residual; it must never default to 1 and no other check may be overridden this way;
   - max transition and max capacitance violations: 0 (as in `cts.tcl`).
   - RESULT lines: area, instances, utilisation (as `cts.tcl`), the routed wire length per layer, the number of
     vias per layer.
7. `unpu_checks_finish route`, then `unpu_checkpoint $BLK_ROUTED`, then the summary `unpu_result route` lines. Say in
   the header and in the last log line: the routed block is UNFILLED on purpose and is the fallback for every later
   step; fill, outputs and the Calibre antenna check come next, and Calibre decides the antenna question.

### A2. Additive edits to earlier files (tell me exactly what changed)

- `pnr/params.tcl`: `BLK_ROUTE_AUTO routeauto` with a comment; and a general rule for the checkpoint block names: every
  `BLK_*` can be overridden by an environment variable `UNPU_BLK_<NAME>` (for example `UNPU_BLK_CLKOPT`), a Warning is
  printed for each override, and the names land in the manifest like any parameter. Validate the names (letters,
  digits, `_`). Reason: several hold-uncertainty experiments must be able to live in one library
  (`clkopt`, `clkopt_h02`, ...), and the later stages must be able to start from any of them.
- `pnr/cts.tcl` (the rerun problem found in the review of task 043): add `UNPU_CTS_STAGE` with the values `all` (the
  default, the present behaviour), `tree` (builds the tree, saves `$BLK_CTS`, stops) and `hold` (does NOT touch the
  tree: opens `$BLK_CTS`, applies the hold uncertainty, runs the optimisation, saves `$BLK_CLKOPT`). In mode `hold`
  the guard is only that `$BLK_CLKOPT` must not exist; with `UNPU_BLK_CLKOPT` it is a different name each time. A
  Warning in the log says which mode ran, and `cts_stage` is in the manifest. Update the header's rerun note.
- `pnr/common.tcl`: the parsers named in A1, the shared `ct_paths` / `ct_timing_summary`, and a procedure that parses
  the `check_routes` "Verify Summary" block (strict: anything not found is "not parsed").
- `pnr/test_common.tcl`: tests for each, with made-up texts that use the lines quoted above (the check_routes summary of
  18.20/18.25/18.26 exactly as printed in the first run's log: you have them in this prompt), a `route_auto` text with
  the iteration lines, an `OPT-209` text; the `BLK_*` override rule (accepted, rejected name, Warning printed); the
  `UNPU_CTS_STAGE` values (pure-Tcl check of the value and of the guard logic if you can separate it).
- `pnr/README.md`: row 9 written; `UNPU_BLK_*` and `UNPU_CTS_STAGE`, `UNPU_ROUTE_ACCEPT_HOLD` in the environment table.

## Part B — checks you can run here

1. `tclsh pnr/test_common.tcl` passes (the old 203 tests still pass; show the output).
2. All `pnr/*.tcl` are complete Tcl.
3. A stub-interpreter run of `route.tcl` (scratch only) with the logged command sequence in the order of A1
   (`define_antenna_rule` BEFORE the first route command is the thing to show), and these failure paths firing:
   library or block `clkopt` missing; block `routeauto` or `routed` present; non-legal input; `ZRT-309` in the output;
   open nets 1; DRCs 2; antenna violations 3 (a CHECK failure here); `check_lvs` with a short; setup violations;
   hold violations without and with `UNPU_ROUTE_ACCEPT_HOLD=1`; floating cells; `ZRT-311` lines counted (80);
   `route_opt` printing `OPT-209` twice. Also run `cts.tcl` in its three `UNPU_CTS_STAGE` modes on the stub and show
   which blocks each saves. State what the stubs prove and do not.
4. `grep`: no absolute `/storage` in the new code; no `FOUNDRY`; no diode option anywhere; nothing written under
   `SCL_KIT_ROOT`.
5. `git status`: only `pnr/` changed.

## Part C — server block for the user (in your report)

csh commands with the `$UNPU_REPO` placeholder, the `icc2_shell -file ... route.tcl -output_log_file ...` line (run
time: the first run's `route_auto` took about 1 minute and `route_opt` 45 s), what a good result looks like, the grep
and files to paste back (the `check_routes` and `check_lvs` outputs, the `ZRT-` and `OPT-` lines, the route reports),
how to run `cts.tcl` for a second hold uncertainty from the saved `cts` block (`UNPU_CTS_STAGE hold`, `UNPU_HOLD_UNCERT`,
`UNPU_BLK_CLKOPT`) and how `route.tcl` then starts from that block (`UNPU_BLK_CLKOPT`), and the rerun note.

## Constraints that apply

Standing rules of tasks 038 to 043. Mark every tool command or option not shown in the handoff `VERIFY`. No route
option beyond those in the handoff, no antenna option beyond `define_antenna_rule` (and reading the options).

## Out of scope

Fill, outputs, Calibre, PrimeTime; pin placement and placement (waiting for the help probe); diodes, buffers and any
antenna repair (decided after Calibre shows what is left); `rtl/`, `constraints/`, `syn/`, `docs/planning/`; running
anything on the server; committing.

## Report back

Files changed or added, per-item account of A1 and A2, Part B output, every `VERIFY` item, anything in this prompt
that is wrong or ambiguous, and the Part C block. Stop after reporting.
