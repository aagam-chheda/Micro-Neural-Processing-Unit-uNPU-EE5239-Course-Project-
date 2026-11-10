# Task 094 — Post-layout simulation: make the verdict honest in `checks` mode and for the new SDF message forms (nothing is waived without the user's approval)

Read first: `pnr_v2/sim/README.md` (esp. "Known limitation: SDFNEP"), `pnr_v2/sim/run_postlayout_sim.sh`, `pnr_v2/sim/test_postlayout_verdict.sh`, and the run-3 logs copied to the PC (`~/server_pull/run3/pnr_icc2/sim/`: `pl_ss_nochecks.log`, `pl_ss_checks.log`, `pl_ff_nochecks.log`, `pl_ff_checks.log`, the `.console` and `*_annotate.log` files, and `runA..D_console.txt`). The user is copying them now; wait for the folder to exist.

## What the server showed (run 3, final layout, 2026-11-10 night; the script judged FAIL for all four runs)

| run | functional result in the log | why the script says FAIL |
|---|---|---|
| A ss nochecks | `ALL CHECKS PASSED`, 343,341 checks, 0 FAIL, 0 `*E/*F`, end 278,003,892 ns | 24 `*W,SDFNEP` outside the accepted class: the form `(COND ((B===0)&&(CI===0)) (IOPATH A S))` (conditional arcs) on `ad01d0`, instance `u_dma.mult_117_U4`; the accepted class is only the edge form `(IOPATH (posedge\|negedge X) Y)`. In run 1 the 24 `ad01d0` messages had the edge form. |
| B ss checks | `ALL CHECKS PASSED`, 343,341 | (1) 1000 SDF warnings of ids that are not accepted: `*W,SDFNL1` ("Attempt to annotate a negative value to a 1 limit timing check ..., setting to 0") and `*W,SDFNET` ("Unable to annotate to non-existent timing check (REMOVAL (posedge CDN) (posedge CP) (0.43))") on reset flops `dfcrn2`/`dfcrq2` (e.g. `u_seq.cycle_reg_1_`, `u_seq.n_lat_reg_1_`); the message cap is reached for these ids, so the rest of the class is hidden; (2) "500 timing-check violations" |
| C ff nochecks | `ALL CHECKS PASSED`, 343,341 | the same 24 SDFNEP as run A |
| D ff checks | NOT RUN: `xmsim: *F,NOLICN: Unable to checkout license for the simulation. 'lic_error LMF-03015'` (twice, both after 2 min 43 s) | licence, not the design |

Evidence that the "500 violations" are FALSE POSITIVES: `grep -c "Timing violation"` on `pl_ss_checks.log` and `pl_ff_checks.log` = 0; the lines the script prints are Xcelium's SOURCE-CONTEXT lines under the SDFNL1 warnings, for example log line 1394 `$hold  (posedge CP &&& (CDN==1'b1),posedge D &&& (CDN==1'b1),th_cp_d_l,notifier);` followed by a `|` caret line; and the count is exactly 500 (the cap). In run B the testbench passed all 343,341 checks with the timing checks ON (a real violation would X the flop through its notifier).

## Goal

(1) A verdict that does not call a context line a violation, and that detects a REAL timing-check violation (find the exact runtime message format of Xcelium for a `$setup/$hold/$recovery/$removal/$width` violation from the cell model: read the model `tsl18fs120_scl.v` for the notifier/`$display` pattern and the Xcelium message ids (`*W,TCHKVD`-style? VERIFY, do not guess); add a test with an invented real-violation log). (2) The new SDF message forms classified one by one with the evidence, and a PROPOSAL for the user: for each of (a) `SDFNEP` conditional-arc form on `ad01d0`, (b) `SDFNL1` negative limit set to 0, (c) `SDFNET` non-existent REMOVAL/RECOVERY check: the cell/instance families involved (counts per cell and per instance from the full `*_annotate.log`), the cause in the model versus the SDF (read the specify block of `dfcrn2`/`dfcrq2` and `ad01d0` in the model), what simulation behaviour results (the arc keeps the model's zero delay / the check is not active), whether it can hide a real problem, and a bounded rule for the script (specific forms, cell lists, count lower bounds), written as a proposal. Do NOT make the script accept anything new by default: the acceptance stays disabled until the user approves; implement the proposed rules behind an explicit switch (an environment variable naming the approved classes, printed in the verdict) so the user's decision is a one-line change, and so the verdict words say exactly what was accepted (`PASS (with documented SDF limitations: ...)`).
(3) The 1000-message cap: find the Xcelium way to see the true counts (an option to raise the limit for SDF message ids, or to read the counts from the `-sdf_verbose` annotation log `*_annotate.log`; VERIFY) so the classification is not made on the first 1000 lines only.
(4) For run D: a retry helper (or a documented wait-and-retry) for `NOLICN`: print the licence feature and the Cadence licence message around log line `*F,NOLICN` (the user will paste it), and make the script exit 2 (environment problem) with a clear text, not a plain FAIL, when the only `*F` is `NOLICN`.

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no waiver without the user's approval." Do not change the testbench, the RTL or `-notimingchecks`/`-nospecify` usage. The documented SDFNEP acceptance of 2026-11-09 stays as it is. Local only: no server work, no commit.

## Acceptance

`bash -n` for the shell files; `bash pnr_v2/sim/test_postlayout_verdict.sh` passes with new cases (the run-3 shapes: COND-form SDFNEP, SDFNL1/SDFNET with source context lines, a log with 0 real violations, an invented log with a real violation, NOLICN only); all other suites keep their counts; README updated (new section with the evidence table above).

## Report back

Files, tests, the classification table with counts, your proposal per class with the risk, what the real-violation message looks like, and the exact commands the user should run (csh, one per line). Stop after reporting.
