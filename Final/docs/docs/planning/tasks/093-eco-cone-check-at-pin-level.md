# Task 093 — Hold ECO: judge the cone at PIN level (a load pin fed by a flop is not on an input-to-output path), keep the ICC2 gate as the final proof

Read first: `docs/planning/tasks/092-hold-eco-register-to-output.md`, your 092 report, `pnr_v2/pt/pt_common.tcl` (the cone procs and `pt_cone_nets_reg2out`), `pnr_v2/pt/pt_eco_probe.tcl` (the AFTER check and the per-insertion classes), `pnr_v2/pt_eco_apply.tcl` (the in2out gate).

## What the server showed (run 3, checkpoint `route3`, 2026-11-10 evening)

PrimeTime on `route3`: setup ss WNS +0.1053 (0 violators); hold ff WNS -0.0188, 7 violators, all register-to-output into `prdata[*]` (targets: `prdata[13]` -0.0188, `[23]` -0.0180, `[21]` -0.0073, `[9]` -0.0070, `[27]` -0.0055, `[17]` -0.0016, `[12]` -0.0008). Calibre on `route3`: DRC 0, antenna 0. The 092 probe (`UNPU_ECO_SCOPE reg2out`): `reg2out: cone nets kept protected: 195; released (driven by a flop): 109`; PrimeTime proposes 9 `insert_buffer` (2 x `dl01d1`, 7 x `buffd1`, +137.96 um2) that bring the 7 targets to 0 remaining in PrimeTime's memory; but the insertion points are LOAD PINS of read-mux cells: `u_csr/U77/A2`, `U77/C2`, `U77/B2`, `U9/B2`, `U74/C2`, `U361/B2`, `U79/B2`, `U72/C2`, `U398/A2`. The probe classifies each as `on a pin of a cone cell` and ends with `ECO RAN BUT TOUCHES THE IN2OUT CONE: 9 of 9`.

## Why the check is too coarse

`insert_buffer` on a LOAD pin isolates only that pin: the buffer sits on the net segment feeding the pin and delays only the arcs from that pin. The cells `U77`, `U361`, ... are `oai222` read-mux gates with six inputs; the `paddr` -> `prdata` input-to-output paths enter through the address-decode inputs (the `A1/B1/C1`-type pins, nets driven by cone cells), while the pins named above (`A2/B2/C2`) are fed by the `QN` outputs of `u_csr` flops (released nets). A path through the flop-side pin starts at the flop and cannot be an input-to-output path. So the right question for a load pin is "is the net feeding this pin on an input-to-output path?", not "is the cell on a cone?".

## Change

1. `pt_eco_probe.tcl` (and the procs in `pt_common.tcl`): for an insertion on a pin P, classify by the NET feeding P: (a) P is an input pin and its net is a RELEASED net of the reg2out net rule (driven by a flop, outside the forward region from the input ports) -> class `load pin on a flop-driven net (safe: starts at a flop)`; (b) P is an input pin whose net is a KEPT cone net (driven by a cone cell or on a cone port) -> `on a cone net` (violation); (c) P is a DRIVER (output) pin of a cone cell or a cone port -> violation as today; (d) a resize/replace of a cone cell -> violation as today; (e) anything else as today. Print for each insertion: pin, cell, reference, the net, the net's driver (flop/cell name), and the class. The AFTER check fails (`ECO RAN BUT TOUCHES THE IN2OUT CONE`) only for (b), (c), (d). The result line for the run-3 case must be `PROBE RESULT: ECO RAN: 9 changes proposed` followed by the class summary (9 of class (a)).
2. Keep the cone protection of the nets exactly as in 092 (kept 195, released 109); do not weaken the cell-level `dont_touch`. The pin-level check judges the PROPOSALS only.
3. `pt_eco_apply.tcl`: unchanged gates (in2out WNS and setup WNS not worse than 0.005 before saving, DRC loop, legality, protection of `earlybuf_*`/`antbuf_*`). This is the final proof that the claim holds in ICC2's timing; state this in the README. Make the apply print, per inserted cell, the class of its pin as computed by the probe if the change file carries it (otherwise nothing new).
4. A defence: if a pin cannot be classified (net or driver unreadable), the class is `unknown` and counts as a violation (no silent pass).
5. Tests: the net-based classification with the 9 real pins and nets of the server run (driver: `u_csr/dest_c_reg_reg_*/QN` etc.; if you do not have the net names, use the pattern: input pin, driver is a sequential cell), a pin on a kept cone net (violation), a driver pin of a cone cell (violation), an unreadable pin (violation), the PROBE RESULT line text for 9 of class (a), and that all existing suites keep their counts (test_eco_scope 62 + new, and the older ones as in 092).
6. README: the rule in words (why a load pin on a flop-driven net is safe), the three violation classes, and the VERIFY (the net/driver attributes in PrimeTime, `get_nets -of_objects`, `all_fanin`/`get_attribute is_sequential` as used by the 092 procs).

## Constraints

"Nothing fails silently; nothing hardcoded; no threshold narrowed; no constraint tuned..." No limit changes. The in2out protection remains: cell-level dont_touch for the proposals' tool run, pin-level classification for the after-check, and the ICC2 apply gate as proof. Local only: no server work, no commit.

## Report back

Files, diffs, tests, the class table for the 9 insertions as the new code would print it (from the real names above), VERIFY list. Stop after reporting.
