# What we did differently

**uNPU — 4x4 INT8 weight-stationary systolic matrix-multiply macro, SCL 180 nm, 50 MHz.**
Companion to the project report. This document answers one question: *what did we do differently from a straightforward run of the course flow, and what did each difference buy us?* Every number comes from the project record (progress logs, `Final/INDEX.md`, the stage READMEs). Statements that the record does not prove are marked **[unverified]** and collected in section 13.

Reading guide: sections 1 and 2 are the summary and the before/after table; sections 3 to 10 are the eight individual differences, each with the evidence, the change and the result; section 11 lists what did not work; section 12 what a reader should not conclude; section 13 the limits of this text.

---

## 1. Summary in one page

We ran the physical design flow three times. The first run (run 1, 2026-11-09) produced a complete layout that was clean in Calibre (DRC 0, antenna 0, LVS correct) but **failed PrimeTime sign-off**: setup −0.2423 ns at one endpoint, hold −0.3468 ns at 263 endpoints. The second run was a short diagnostic run. The third run (run 3, 2026-11-10 to 11-11) is the final one: Calibre DRC 0, antenna 0, LVS correct, and PrimeTime met in every view we looked at (setup +0.1057 ns, hold +0.0041 ns with crosstalk off; +0.0154 ns and +0.0038 ns with crosstalk on; identical results against the original constraint file), with 0 violators and design rules met.

The difference between run 1 and run 3 is not luck and not a larger margin. It is **eight deliberate changes**, each driven by a measurement:

1. We found that ICC2 was optimising the input/output paths against a clock latency that PrimeTime does not use, and removed the cause (a tool-written `set_clock_latency` line) inside the flow.
2. We prevented the antenna failures of the input ports up front, with a prediction from the antenna formula, instead of repairing them after the route.
3. We used an optimisation-only clock-uncertainty margin, scoped to register endpoints so that it cannot damage the one zero-margin path, and we proved after every use that it was restored.
4. We judged the routed layout with PrimeTime and Calibre at **checkpoints before the fill**, instead of at the very end.
5. We drove every late fix (hold, data transition, crosstalk) with PrimeTime-guided ECOs behind hard gates that refuse to save a worse design.
6. We refused to carry a limit that was not a course constraint into the exported constraints, and we proved with a comparison tool that the exported constraints equal the original ones.
7. We rebuilt the post-layout simulation verdict so that it reports true counts, and we corrected an earlier statement that had been based on truncated tool output.
8. We organised the work so that every result can be re-checked: self-contained run directories, backups, a verification script for the record, and a deliverable package with its own checks.

---

## 2. Before and after

| Item | Run 1 (first complete layout) | Run 3 (final) |
|---|---|---|
| Calibre DRC | 404 rules, 0 results | 404 rules, 0 results |
| Calibre antenna | 16 rules, 0 results, but only after five repair steps (55, 50, 46, 1, 0 findings) | 16 rules, 0 results, after two short loops (10 findings, then 4, then 0; a second loop for 3 findings after the last ECO) |
| Calibre LVS | correct (with the approved `FILTER_DWN2PSUB` switch) | correct (same switch; 44,560 nets matched on both sides) |
| PrimeTime setup (ss), crosstalk off | −0.2423 ns, 1 violating endpoint (`dma_addr[31]`) | +0.1057 ns, 0 violators |
| PrimeTime hold (ff), crosstalk off | −0.3468 ns, 263 violating endpoints | +0.0041 ns, 0 violators |
| Crosstalk on (PrimeTime-SI) | not run | setup +0.0154 ns, hold +0.0038 ns, 0 violators |
| Against the original constraint file | not run | identical numbers (+0.1057 / +0.0041 ns) |
| Design rules (transition, capacitance) | not reported by the summary; 510 entries found later | met; the data limit (3.0 ns) fixed by a 9-cell ECO |
| Late fixes | a 109-cell hold ECO that broke the read path (−0.5899 ns) and was never accepted | 11 hold buffers, 10 driver resizes, 1 antenna buffer, each accepted behind gates |
| Post-layout simulation | passed with a verdict that hid the true share of unmatched delay arcs | passes with the true shares stated (see section 9) |
| How the result is checked | by reading logs | a verification script, an index with a hash of every file, and checks of more than 80 key numbers against the logs |

The "what stays the same" list is as important: the RTL (frozen), the synthesis result (identical netlist in all runs: 2,465 flops, 442,296 µm²), the constraints (the original, deliberately pessimistic set of 2026-11-02: clock 20 ns, uncertainties 1.5 and 0.5 ns), the die (885.6 × 885.6 µm) and the standard-cell flow.

---

## 3. Difference 1: removing the cause of the sign-off gap instead of compensating for it

**Situation.** In run 1, ICC2 reported timing met (setup +0.0143 ns, hold −0.0004 ns) while PrimeTime reported −0.2423 ns and −0.3468 ns. The gap was in the input/output paths.

**Hypotheses we tested.** (a) A global increase of the clock uncertainty during optimisation, suggested from outside. (b) A margin on the I/O delays. (c) A different reading of the I/O reference clock between the two tools.

**Evidence.** A read-only ICC2 diagnostic on a *copy* of the run-1 library showed that ICC2 placed a clock latency on the I/O reference (0.8069 ns at the slow corner, 0.3798 ns at the fast corner), while PrimeTime launched and captured at the clock pin with zero latency. The exported constraint files of run 1 contained one line that no script of ours had written: `set_clock_latency 0.806866 [get_clocks {clk}]` (slow) and `0.379753` (fast). A what-if in memory, removing that line, made ICC2 reproduce PrimeTime's numbers on the four example paths: hold slack −0.3494 ns (PrimeTime −0.35), output required time 10.5000 ns (PrimeTime 10.50), source-flop launch 0.9188 ns (PrimeTime 0.92). Register-to-register slacks did not move. The two SDC-text alternatives (`-network_latency_included`, `-source_latency_included`) fixed only the input side or nothing, and an offset emulation over-shot (hold −0.61 ns).

**Where the line comes from.** A probe of the blocks of run 3 showed that it first exists in the power-plan block, is re-created inside `place_opt` and inside the clock-tree build, and that the clock-tree stage never replaced the pre-clock-tree estimate. So `place_opt`, the early buffer step and the old clock-tree stage had all timed the I/O paths against the wrong reference.

**Change.** A shared procedure removes the line, per scenario, at the start and end of every script that times or optimises, with printed before/after counts and a hard error if any line remains. The clock-tree command is split into its three steps so that the final optimisation runs after the removal. The export script removes it before writing the constraints and then greps the exported files.

**Result.** After the clock tree of run 3, ICC2 reported output capture latency 0.0000 ns and an input launch of 0.2403 ns (the port stage only), the PrimeTime convention. The routed layout met PrimeTime setup at the first checkpoint without any ECO for the output path that had failed in run 1.

**Why this is different.** The usual reaction to a sign-off gap is a margin. We did not add margin; we found out what the optimiser believed and made it believe the same as the sign-off tool.

---

## 4. Difference 2: preventing the input-port antenna failures

**Situation.** In run 1, 16 input-port nets failed the antenna rule after the route: wires of 130 to 478 µm against a limit of about 72 µm (middle metals) or 46 µm (top metal), with a gate area of about 0.19 µm² and no diodes available. The repair needed five iterations and a late timing break.

**Change.** A step between placement and clock-tree synthesis predicts, for every input port, the pin-to-load wire length from the placement and the antenna ratio from the rule's formula, and inserts a buffer next to the pin only where the prediction exceeds 80 % of the limit. The prediction is printed as a table and stored as a CSV. The buffers are protected from later optimisation. Nets on the zero-margin read path are not buffered by default (the first real run showed that buffering them would have cost 0.12 ns on that path); they are listed and left to the repair step.

**Result.** 54 buffers up front (102 input ports: 54 buffered, 20 fine, 22 with no load, 1 clock, 5 skipped on the read path). After the route the first Calibre antenna run found 10 findings instead of 46 to 55; two short loops (layer hopping, one buffer on `paddr[7]`) took it to 0.

**Honest note.** The prediction is an upper bound. In run 1 only 16 of roughly 80 data nets failed although most pins are far from their loads, because the router splits long wires into layer islands. We accepted the extra buffers (54 cells of 12.54 µm², about 680 µm², roughly 0.1 % of the 715,039 µm² core) as cheap insurance.

---

## 5. Difference 3: a scoped, provably restored optimisation margin

**Situation.** The flow already had an optimisation-only uncertainty mechanism with goals of 0.0. The user wanted a margin on top of the original uncertainty during optimisation (a friend's experience).

**The trap we avoided.** A margin on the whole clock also lands on the combinational read path `paddr` → `prdata`, whose budget is 4.5 ns with about zero spare. In run 1 this very path was broken by a hold fix. So the margin (setup +0.05 ns, hold +0.10 ns) is applied on the **clock pins of the registers only**; paths that end at output ports keep the original value. Probes check on the server that the pin-level value really acts (hold slack moved by exactly −0.1000 ns and setup by −0.0500 ns).

**Proof of restore.** After each optimisation block the script writes the constraints and reads them back: any pin- or port-level value left, or a clock-level value that is not at the original (1.5 / 0.5 ns), stops the run. The export script re-checks the exported files: four lines, all at the original values.

---

## 6. Difference 4: judging the layout at checkpoints, before the fill

**Situation.** In run 1, PrimeTime was run last and found 264 violations at the end.

**Change.** The route block is exported from a *copy* under a tag, and PrimeTime (setup at the slow corner, hold at the fast corner, with extracted parasitics) and Calibre (DRC and antenna) run on it before the fill. The scripts for the sign-off views write to tagged folders so a checkpoint never overwrites the final result.

**Result.** The first checkpoint showed setup met with 0 violators, hold −0.0238 ns at 7 endpoints (all register-to-output into `prdata`), DRC 0 and 10 antenna findings. That is feedback in minutes instead of at the end of the flow. We went through four checkpoints (route to route4) and then the final export.

---

## 7. Difference 5: late fixes as guarded, PrimeTime-driven ECOs

**Principle.** A small local change on a nearly finished layout (an ECO) is allowed only behind gates that refuse to save a worse design, and only where PrimeTime proposes it.

**The gates.** Before saving, the apply script checks: the read-path group and the whole-design setup slack not worse than 5 ps; DRC 0; legality 0; open nets 0; and that every protected cell (early buffers, antenna buffer, earlier ECO cells) is byte-identical in reference, origin, orientation and pins. Hold slack is reported as a warning because PrimeTime is the sign-off for hold.

**What was applied in run 3, and why each was needed.**

| ECO | Trigger | Change | Effect |
|---|---|---|---|
| Hold, register-to-output | 7 endpoints on `prdata`, worst −0.0238 ns | 9 buffers on load pins fed by register outputs (+138 µm²) | hold +0.0002 ns, 0 violators |
| Data transition limit | 86 entries over 3.0 ns (30 to 50 ps) on 9 nets | 9 driver resizes (+94 µm²) | design rules met |
| Crosstalk round | with crosstalk on: setup −0.0364 ns (4 endpoints on `paddr[3]`), hold −0.0114 ns (1 endpoint) | 1 resize (`buffd1` → `buffd3`) on the read path, 2 hold buffers, one more layer-hop pass for 3 new antenna pieces | all views met |

**What we had to invent to make these safe.**
- The earlier hold ECO (in run 1, 109 cells) put delay cells on nets shared with the read path and broke it (−0.5899 ns). We now protect the cone of cells and nets that lie on input-to-output paths, and, after we found that this was too strict, we judge each insertion **by the net feeding its pin**: a buffer on a load pin that is fed by a register output cannot be on an input-to-output path.
- A resized cell that is wider than its free neighbour is relocated to the nearest free run (bounded distance, position verified), instead of letting the legaliser move cells arbitrarily.
- The probes print every insertion with its class, and an unreadable class counts as a violation (no silent pass).

---

## 8. Difference 6: constraints we refused to carry, and proof of equality

**Situation.** The example CTS script sets a 0.40 ns clock-path transition limit. It is not in the original constraint set and not in the instructor's guidance, but it ended up in the exported constraints, and PrimeTime reported 424 violations against it (0.43 to 0.48 ns).

**Decision (user, with Planning's recommendation).** Keep it as a clock-tree target, but do not export it. The reason is written down: it is a tuning knob of an example script, not a course constraint; meeting it would have meant redoing the clock tree and every step after it, for a limit nobody asked for.

**Proof.** A comparison tool evaluates the original constraint file and the exported ones and tabulates every constraint: 722 compared, 718 identical, 4 expected tool lines (propagated clock, units, explicit clock waveform, operating conditions), 0 differences. PrimeTime was also run directly against the original constraint file and gave identical numbers.

**Related.** The summary of the PrimeTime scripts now includes a design-rules block, because "setup met, hold met" had hidden 510 transition entries in run 1; it also no longer prints reference numbers from an older run (a hard-coded constant that we found).

---

## 9. Difference 7: an honest simulation verdict

**Situation.** The post-layout simulation passes all 343,341 checks, but Xcelium prints warnings when the delay file contains entries the cell models cannot take. On 2026-11-09 we accepted "about 1 percent" of such entries. That figure came from the first 500 printed warnings: the tool prints at most 1000 per message type.

**What we found when we counted properly** (from the delay file itself, reconciled with the tool's own total): 22,534 of 52,656 path-delay entries (42.8 %) are not annotated — 3,510 edge-form (6.7 %, the class accepted earlier) and 19,024 conditional arcs on full-adder cells (36.1 %). In checks mode: negative timing limits clamped to 0 (8,589 at the slow corner, 7,150 at the fast corner) and 7,395 removal/recovery entries not annotated. The "500 timing-check violations" that the script had reported were not violations but source lines that the simulator prints as context; the real count is 0 (and Xcelium's statistics show 25,065 checks, 0 disabled).

**Change.** The verdict logic classifies every warning by class with true counts, never accepts a class without an explicit approval word (the user approved three on 2026-11-11), prints the accepted limits inside the verdict text, treats "licence unavailable" as an environment problem and not as a design failure, and keeps the conditional-arc caveat visible: the simulation is optimistic on 36 % of the delay arcs; timing sign-off is PrimeTime.

**Experiments.** Two optional experiments were run on the final layout. Changing `===` to `==` in a copy of the delay file did not change the warning count, so that was not the cause of the conditional-arc mismatch (hypothesis disproved; the cause is still unknown). A model switch for negative timing checks removed the clamping entirely (0 clamped limits, 343,341 checks, 0 violations), so no violation had been hidden by the clamping, and reduced the unannotated removal entries to two thirds (4,930).

---

## 10. Difference 8: working so that results can be re-checked

- **Self-contained run directories.** Every script derives its root from its own location, so a new clone is a new, independent run and cannot write into an older one. This protected run 1 while run 3 was built.
- **A fallback chain.** Each ECO step began with a library backup; earlier states stay in named folders. When a late change was refused by a gate, nothing was lost.
- **Tests with verbatim data.** Parsers are tested on text copied from the real tool logs. Twice (the annotation table, a class-file row count) a test passed on data we had reconstructed instead of copied, and the server run failed; after that the rule became "copy the real text".
- **A record that checks itself.** `Final/` holds one folder per flow stage with the scripts as they were run, logs, reports and results; an index with the hash of every file; and a verification script that re-reads more than 80 key numbers from the cited logs and runs 2,019 script tests from a temporary copy. A negative test shows that it fails when a log value, a compressed file or the index is tampered with.
- **Backups.** A full copy of all three runs and of `Final/` on the server, with file counts verified against the originals (9,988, 1,861 and 6,329 files for the three runs).
- **A deliverable package** for the top-level team with its own verification (12 checks), a datasheet written for a reader who has not seen our work, and a list of open questions that were found while building it (power stripes, pin order, reset style).

---

## 11. What did not work (and what we learned)

| Attempt | Why it failed or was dropped | Lesson |
|---|---|---|
| Hold ECO on shared read-mux nets (run 1) | broke the read path by −0.5899 ns; the gate refused to save | protect the input-to-output cone; judge insertions by pin, not by cell |
| Re-placing pins after placement | the second pin-placement call ignored the 8 µm spacing; geometry showed that pin order cannot shorten the wires anyway (102 pins at 8 µm need 91 % of the edge) | fix the antenna problem with buffers, not with pins |
| A global uncertainty increase | also lands on the zero-margin read path | scope the margin to the registers |
| Offset emulation of the I/O latency | over-shot (hold −0.61 ns) | remove the cause instead |
| `===` → `==` in the delay file | warnings unchanged | write the negative result down |
| Option strings from memory (`-neg_tchk`) | not in this simulator's help | read the tool's own help; the define alone worked |
| Several shell traps | a trailing `&` in csh backgrounds a whole `;`-chain; `2>&1` is invalid in csh; a pager stops background jobs; dropped connections kill foreground jobs | use `|&`, `--no-pager`, `nohup`, and test commands on one line first |
| Two mistakes of our own in this text's subject | the "about 1 percent" figure (from truncated output); a parser tested on reconstructed data | count from the source, copy the data verbatim |

---

## 12. What a reader should not conclude

- **Not that the design is perfect.** Hold margins are thin (+4.1 ps crosstalk off, +3.8 ps on). Congestion is 1.97 % overflow in the global-route estimate (the upper end of the instructor's range), though the real route is clean. The simulation is optimistic on 36 % of the delay arcs. The power pins are two interior top-metal stripes instead of the agreed edge pins (decision D4, deferred in the clean-slate flow). There is no macro timing model, no decoupling capacitors (the library has none), and the power estimate is at default activity.
- **Not that the final result is reproducible to the cell.** The tool was run once for the final state. A fresh run would hit a different small set of hold endpoints and antenna pieces and would need the same *kind* of fixes; the sequence is in the run book.
- **Not that every claim here is machine-checked.** See below.

---

## 13. Items in this text that the record does not prove **[unverified]**

1. The statement that the first complete layout "needed five antenna repair steps" counts the sequence 55 → 50 → 46 → 1 → 0 recorded in the handoff; the intermediate runs are not part of `Final/`.
2. The precise commits in force at each step are inferred from timestamps.
3. That the example scripts' default hold-effort option is obsolete in this tool version comes from one error line in the clock-tree log (NDMUI-439), not from the tool's documentation.
4. Whether ICC2 reproduces a given ECO outcome in a second run was not tested.
5. The date of the project manager's confirmation of SystemVerilog and the date of the `FILTER_DWN2PSUB` approval are not in a file we could cite.
