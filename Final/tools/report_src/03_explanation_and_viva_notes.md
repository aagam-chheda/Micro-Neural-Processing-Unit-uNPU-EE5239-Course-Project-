# uNPU — explanation and viva notes

**Purpose.** A complete walk through the project in plain language, then the questions an examiner is likely to ask, with answers that use our own numbers. Every number is from the project record (`Final/INDEX.md` and the stage READMEs); anything the record does not prove is marked **[unverified]** and is not to be stated as fact in a viva.

How to use: read part A once (it is the story), keep part B (the numbers) in front of you, rehearse part C (questions) aloud, and read part D (the awkward questions) twice.

---

# Part A — The project in plain words

## A.1 What we built

A small accelerator chip block ("macro") that multiplies matrices of 8-bit integers. It is called `unpu_top`. The core is a 4 × 4 grid of multiply-accumulate cells (a *systolic array*): data flows through the grid in a fixed rhythm, each cell multiplies and adds into a 32-bit running total. It is *weight-stationary*: the weights are loaded into the cells once and stay there while the activations stream past.

The block talks to the rest of a chip through two interfaces: an APB register interface (a CPU writes pointers and sizes and starts a job; the registers are `src_A`, `src_B`, `dest_C`, `dim_M`, `dim_N`, `dim_K`, `npu_ctrl`, `npu_status`, in the window 0x4000_0000 to 0x4000_0FFF), and a DMA master interface that the block uses to fetch operands and write results into memory by itself. It runs at 50 MHz (20 ns clock). Each multiplier-accumulator is a single pipeline stage: we did not pipeline the multiplier, because that would change the timing relations between all parts of the array.

The whole thing is built in the SCL 180 nm process with four metal layers, from the design description (SystemVerilog) to a finished layout (the GDS file) that has been checked for design-rule violations, for equivalence with the netlist, for timing and for function with real delays.

## A.2 The steps, in order

1. **Design (RTL).** Written in synthesisable SystemVerilog, then *frozen* so that nothing downstream has to be redone.
2. **Verification of the RTL.** A C golden model produces the expected results; a testbench runs the design against them (30 sequences in the second part, with illegal operations, wrap-around and extreme back-pressure) in Xcelium: 343,341 checks, all pass.
3. **Synthesis.** Design Compiler turns the RTL into a netlist of library cells under timing constraints: 2,465 flip-flops, area 442,296 µm² (cell area 429,161 µm²). Gate-level simulation of that netlist passes the same 343,341 checks (with zero cell delays, so it proves logic only).
4. **Floorplan.** A square die of 885.6 × 885.6 µm, 204 signal pins placed on the edges (APB and `clk`/`rst_n` on the right, DMA on the top) and power pins.
5. **Power plan.** A ring and a mesh of power straps on the upper metals, rails on the lowest metal.
6. **Placement.** The cells are placed. Utilisation at the end is 69.86 %.
7. **Early port buffers.** Our own extra step (see part A.4): small buffers next to the input pins to avoid antenna violations later.
8. **Clock tree synthesis (CTS).** A balanced tree of buffers distributes the clock to the 2,465 flops: 6 levels, 63 repeaters; at the fast corner the clock arrives about 0.56 ns after the pin with a spread of 0.32 ns, at the slow corner 1.26 ns and 0.75 ns.
9. **Routing.** Real wires. After this step we measure timing with real wire parasitics.
10. **Fixes (ECOs).** Small, guarded changes to fix the last few timing and rule violations.
11. **Metal fill and export.** Fill shapes for density rules; export of GDS, LEF (the abstract view), netlists, constraints, delays and parasitics.
12. **Sign-off.** Three independent checks: Calibre DRC and antenna (geometry rules), Calibre LVS (the layout equals the netlist), PrimeTime (timing at the slow corner for setup and the fast corner for hold, with and without crosstalk). Then a simulation of the final netlist with the real delays.

## A.3 What "clean" means here

- **DRC clean:** the geometry obeys the process rules (404 rule checks, 0 results).
- **Antenna clean:** no long wire is attached to a tiny gate with no diode to bleed charge during manufacturing (16 rule checks, 0 results).
- **LVS correct:** the transistors and nets extracted from the layout match the netlist (44,560 nets on both sides).
- **Timing met:** setup (data arrives before the next clock edge) and hold (data does not change too soon after the edge) for every path, with the clock tree and wire delays included. PrimeTime: setup +0.1057 ns, hold +0.0041 ns, 0 violators; with crosstalk on +0.0154 and +0.0038 ns.
- **Design rules met:** limits on signal transition times and capacitance.

## A.4 What was hard, and what we did about it

The first complete layout (run 1) passed Calibre but failed PrimeTime: setup −0.2423 ns at one endpoint, hold −0.3468 ns at 263 endpoints. Three things turned out to matter.

**(1) The two timing tools disagreed about the clock on the input/output paths.** ICC2 (the place-and-route tool) believed that the external world's clock arrives with the same delay as the macro's own clock tree; PrimeTime (the sign-off tool) assumes it arrives at the clock pin with no delay. The difference was a line `set_clock_latency` that the tool itself had written. We found it with a read-only experiment, removed it inside the flow with a procedure that checks itself, and ICC2's numbers then matched PrimeTime's.

**(2) Antenna violations on the long input wires.** Instead of repairing them after routing, we predict them from the rule's formula right after placement and add small buffers next to the pins where needed (54 buffers).

**(3) Late fixes can break more than they fix.** In run 1 a hold fix inserted delay cells on shared logic and destroyed the combinational read path (−0.5899 ns). Now every fix is a small, PrimeTime-proposed change, applied only if a set of checks passes (the read path not worse than 5 ps, DRC 0, legality 0, no open nets, protected cells unchanged); otherwise nothing is saved.

## A.5 How we know the result is real

- Three independent tools agree: Calibre, PrimeTime (three views) and simulation.
- PrimeTime was also run directly on the *original* constraint file, not just the one the layout tool wrote, and gave the same numbers; a comparison tool lists every constraint and found no difference apart from four expected tool lines.
- The record checks itself: `Final/` has a verification script (16 checks) that re-reads key numbers from the logs and re-runs 2,019 script tests.
- We have written down what we could *not* prove (section D).

---

# Part B — Numbers to keep at hand

| Quantity | Value |
|---|---|
| Process | SCL 180 nm, 4 metals (M1 to M3 and top metal) |
| Clock | 50 MHz (20 ns); uncertainty used in all checks: setup 1.5 ns, hold 0.5 ns |
| Array | 4 × 4 INT8, 32-bit accumulators, single-stage PE |
| Timing contract | row C[m][*] valid at cycle m + 7; a pass of M rows takes M + 7 cycles; skew FIFO depths 0/1/2/3 on the input side, 3/2/1/0 on the output side |
| RTL check count | 343,341 (testbench) |
| Flops / cell area / synthesis area | 2,465 / 429,161 µm² / 442,296 µm² |
| Die / core | 885.6 × 885.6 µm / 715,039 µm² core |
| Placed cell area | 499,549 µm² (utilisation 69.86 %) |
| Pins | 206 = 204 signal + VDD + VSS; 102 on the right edge (M3), 102 on the top edge (M2) |
| Clock tree | 2,465 sinks, 6 levels, 63 repeaters; ff latency 0.56 ns / skew 0.32 ns; ss latency 1.26 ns / skew 0.75 ns |
| Congestion | global-route overflow 1.97 % (H 1.79, V 2.15) |
| Calibre | DRC 404 rules / 0; antenna 16 rules / 0; LVS correct (44,560 nets) |
| PrimeTime (ss setup / ff hold) | crosstalk off +0.1057 / +0.0041 ns; crosstalk on +0.0154 / +0.0038 ns; original SDC +0.1057 / +0.0041 ns; 0 violators |
| ECO cells in the final layout | 54 early buffers, 1 antenna buffer, 11 hold buffers, 10 driver resizes |
| Post-layout simulation | 4 runs (ss/ff, with/without timing checks), each 343,341 checks, 0 failures, 0 violations; 25,065 timing checks active |
| Simulation limits (approved) | 3,510 + 19,024 delay arcs unmatched (42.8 % of 52,656), clamped limits 8,589 (ss) / 7,150 (ff), removal entries 7,395 |
| Run 1 → run 3 | setup −0.2423 → +0.1057 ns; hold −0.3468 (263 endpoints) → +0.0041 ns (0) |
| Records | about 1,200 files in `Final/` (about 89 MB); 140 files in the deliverable zip (134 indexed files plus its index and 5 tools; 35.6 MiB) |

---

# Part C — Questions and answers

## C.1 The design

**1. What is a systolic array and why use one here?**
A regular grid of simple cells where data moves from cell to cell in lock-step. Each cell does a multiply-add. It reuses each fetched value many times (low memory traffic), needs only local wiring (short wires, easy timing) and scales by repeating a cell. For matrix multiplication it is the standard accelerator structure.

**2. What does weight-stationary mean?**
The weights (one matrix) are loaded into the cells and stay; the other matrix (activations) flows through. The weights are loaded once per tile, so their movement cost is paid once.

**3. Why 8-bit inputs and 32-bit accumulators?**
INT8 is enough precision for inference-style work and gives small multipliers. A product of two 8-bit numbers is 16 bits and a dot product adds up to several of them, so a 32-bit accumulator cannot overflow for realistic sizes.

**4. Why a single pipeline stage in the PE?**
At 50 MHz (20 ns) a multiply-add fits in one cycle with room to spare; pipelining the multiplier would change the arrival cycles of every value and break the timing contract (A enters at cycle m + k, arrives at PE(k, j) at m + k + j, C leaves column j at m + j + 4, and the whole row is valid at m + 7).

**5. What are the skew FIFOs for?**
The array expects row k's data k cycles later than row 0. Input FIFOs of depth 0/1/2/3 delay rows to create the diagonal wave; output FIFOs of depth 3/2/1/0 re-align the columns so that a whole result row appears at once.

**6. How does the CPU use it?**
It writes the source pointers, destination pointer and sizes into the registers through APB, sets a start bit in `npu_ctrl`, and polls `npu_status`. The block then reads the operands and writes the results by DMA. The register map and some DMA address conventions are **not confirmed by the PM** (they are in the open-items list).

**7. Is reset synchronous?**
No: the RTL uses asynchronous assertion (`always_ff @(posedge clk or negedge rst_n)`) in all eight sequential modules. The top-level chip drives a synchronous `rst_n`; the recommendation to the integrator is a synchronous release. (An earlier note in our records said "synchronous"; that was about the top-level driver, and the RTL is the reference.)

**8. What is the combinational read path and why is it special?**
Reading a register through APB goes from `paddr` straight to `prdata` with no flip-flop in between. Its budget is 20 ns minus 1.5 ns uncertainty minus 7 ns input delay minus 7 ns output delay, i.e. 4.5 ns, and synthesis stopped at about +0.01 ns of slack. Any extra delay on it breaks timing, which is why we protect it in every fix.

## C.2 Verification

**9. How was the RTL verified?**
A C golden model generates vectors and expected results; the testbench checks the design against them in two parts, the second with 30 sequences including illegal operations, wrap-around and extreme back-pressure: 343,341 checks passed. The same testbench was then run on the synthesised netlist and on the final layout netlist with delays.

**10. What does the gate-level simulation prove that RTL simulation does not?**
That synthesis did not change the function. With the cell models' zero delays it proves logic only. The post-layout run with the delay file also checks that the circuit still works with real cell and wire delays at 20 ns.

**11. Why does the post-layout run say "PASS with documented limitations"?**
The delay file contains entries the simulator cannot attach to the library models. Counted from the file itself: 22,534 of 52,656 path-delay entries (42.8 %): 3,510 of one kind and 19,024 conditional arcs on full-adder cells (the adder sum outputs run with zero delay). In checks mode, 8,589 (ss) or 7,150 (ff) negative timing limits are set to 0 by the simulator (stricter than the file), and 7,395 removal entries are not annotated. The project owner approved these classes on 2026-11-11; timing sign-off is PrimeTime.

**12. Did you try to remove those limitations?**
Yes, two experiments on the final layout. Changing `===` to `==` in a copy of the delay file did not change the warnings (hypothesis disproved; the cause is unknown). A model switch for negative timing checks removed the clamping completely (0 clamped limits, still 343,341 checks, 0 violations), so the clamping had hidden nothing; it reduced the unannotated removal entries to 4,930.

## C.3 Synthesis and constraints

**13. Which constraints did you use and why those?**
The original, deliberately pessimistic set chosen on 2026-11-02: clock 20 ns; setup uncertainty 1.5 ns and hold 0.5 ns; input delays 35 % (APB) and 40 % (DMA, reset) of the period; output delays the same; input minimum delay 0 and output minimum −0.5 ns; a weak `buffd1` as input driver; 0.2 pF on inputs and 1.0 pF on outputs; max transition 3.0 ns; max capacitance 2.0 pF. The instructor's guidance allows more relaxed numbers; we kept the stricter ones as a decision, so our results hold under both.

**14. What is clock uncertainty?**
A margin subtracted from the usable period to cover clock jitter and skew you have not modelled. Setup gets a larger one (jitter + skew + margin), hold a smaller one.

**15. What did synthesis give?**
2,465 flip-flops, cell area 429,161 µm², no latches, the only violated constraint the artificial maximum-area one; worst setup slack +0.01 ns on the read path (the tool stops once the constraint is met).

## C.4 Physical design

**16. Why did you choose that die size?**
The floorplan used a core utilisation of about 60 % (cell area / core area) as the instructor suggests (60 to 70 %), giving 885.6 µm square. Utilisation grew to 69.86 % after clock tree, buffers and fixes.

**17. What is CTS and what does the result mean?**
Clock tree synthesis builds a buffer tree so that all 2,465 flop clock pins see the clock at nearly the same time. Our tree has 6 levels and 63 repeaters. *Latency* is the delay from the clock pin to the flops (0.56 ns fast, 1.26 ns slow); *skew* is the spread between the earliest and latest flop (0.32 and 0.75 ns). We built it for minimum skew; the target of 0.2 ns was not reached and no limit was given by the top level.

**18. What is an antenna violation and how did you fix it?**
During manufacturing, a long metal wire that is attached only to a gate (no diode, no driver) collects charge and can damage the thin gate oxide; the rule limits the ratio of wire area to gate area (limit 400). Input ports have no driver inside the macro, so a long wire from the pin to the first gate is the worst case. We predict it from the formula and add a buffer next to the pin (it shortens the exposed wire and gives the rest of the net a driver with diffusion); remaining cases were fixed by moving wires to a higher layer. No diodes were available.

**19. Why was `set_clock_latency` such a problem?**
It made ICC2 time the input/output paths against a clock latency of 0.8069 ns (slow) / 0.3798 ns (fast) that PrimeTime does not use, so ICC2 thought the paths were fine and fixed the wrong thing. See A.4 and the "what we did differently" document.

**20. What is an ECO and why use it?**
Engineering change order: a small, local change to an almost finished layout, instead of rerunning placement and routing, which would reshuffle everything. Each of ours is proposed by PrimeTime and applied behind checks that refuse to save a worse design.

**21. What do the checks in the ECO script protect?**
The combinational read path (not worse by more than 5 ps), the whole-design setup slack, DRC, legality, open nets, and the exact identity of all cells added earlier. If any check fails, nothing is saved and the previous library state stays.

**22. What is crosstalk (SI) and why did you also run it?**
Neighbouring wires act as small capacitors to each other; a switching neighbour speeds up or slows down a signal by tens of picoseconds. ICC2 optimised with it on; PrimeTime's default sign-off runs with it off, which is less pessimistic. We ran both: with it on, setup first failed by 36 ps on four paths from `paddr[3]` and hold by 11 ps on one path; an ECO round fixed both (one resize and two buffers).

**23. What are the power pins and is that a problem?**
Two vertical top-metal stripes inside the macro (VDD at x = 830 µm, VSS at x = 860 µm, 2.5 µm wide), not the agreed row of edge pins. The top level has to run its own top-metal straps over them. It is documented as an open question for the top-level team; electrically the load is small (about 5 mA at 1.62 V).

## C.5 Sign-off

**24. What is the difference between setup and hold?**
Setup: data launched at one clock edge must arrive before the next edge minus the flop's setup time. Fix: faster logic. Hold: data must not change until the flop's hold time after the capturing edge. Fix: add delay. Setup is checked at the slow corner (worst case: slow cells), hold at the fast corner.

**25. Why different corners?**
Because the worst case for each is opposite: slow silicon makes long paths too slow, fast silicon makes short paths too fast.

**26. What is "propagated clock" in the PrimeTime run?**
That the real clock-tree delays are used, not an ideal clock. Our script proves it from the timing report (every path shows "(propagated)" tags).

**27. Why run PrimeTime on the original SDC as well?**
To prove the layout meets the constraints *as given*, not as rewritten by the layout tool. The numbers were identical.

**28. What does "design rules met" cover?**
Maximum transition (3.0 ns for data), maximum capacitance (2.0 pF) and minimum pulse width. In run 1 these had 86 data-limit entries over the limit by 30 to 50 ps; a 9-cell resize ECO fixed them. A 0.40 ns clock transition target from an example script was deliberately not carried into the exported constraints (it was not a course constraint).

**29. What is LVS and why `FILTER_DWN2PSUB`?**
Layout versus schematic: the tool extracts devices from the layout and compares them with the netlist. The layout contained one extra device, an n-well to p-substrate diode, which has no counterpart in the netlist. The approved filter ignores that one device; with it LVS is correct, 44,560 nets on both sides. (The date of the approval is not in a file we can cite **[unverified]**.)

## C.6 Process and judgement

**30. Why three runs?**
Run 1 gave a complete layout that failed PrimeTime. Run 2 was short and used for diagnostics. Run 3 applied every lesson from the start and is the final one. We kept all three, with backups, so each claim can be traced.

**31. What did the instructor's example scripts give you?**
The base flow (database setup through export). We made minimal edits and listed them; our own additions are the early port buffers, the latency removal, the scoped margin, the checkpoints, the ECO machinery, and the checking tools.

**32. How do you know your scripts are right?**
They are tested without the EDA tools (2,019 numbered tests from a temporary copy of the script folder), they print their decisions, they refuse to continue when a check fails, and each was run on the server with the real tools. Two bugs of ours (a parser tested on reconstructed data, and a row count that counted a dictionary's keys and values) were found only by the server run and are written down.

**33. What would you do with more time?**
Produce the macro timing model (it needs the library compiler); get answers from the top-level team on pin order and power; try to remove the conditional-arc mismatch in the simulation (find its real cause); run a second implementation to measure repeatability.

---

# Part D — The awkward questions

**D.1 "Is the design really clean? Where are the weak points?"**
Yes for every check we ran, with these honest limits: hold margins are +4.1 ps (crosstalk off) and +3.8 ps (on); the read path has no spare time; the simulation is optimistic on 36 % of the delay arcs (approved, stated, PrimeTime is the sign-off); global-route congestion is 1.97 % overflow, at the upper end of the instructor's range, with a clean detailed route; ICC2 still lists 8 clock nets above the 0.40 ns target, and its power-via check lists 18 missing VSS vias while Calibre DRC and LVS are clean; the power pins are interior stripes; there is no macro `.lib`; there are no decoupling capacitors (the library has none).

**D.2 "You said 'about 1 percent' earlier. Why 42.8 percent now?"**
Because the first figure came from the first 500 warnings the simulator printed (it prints at most 1000 per kind). When we counted from the delay file and reconciled with the tool's own total, the true share was 42.8 %. We corrected the record and the verdict logic, and the user approved the classes again with the true numbers.

**D.3 "Why did you accept simulation warnings instead of fixing them?"**
We tried: one hypothesis was disproved by an experiment; the negative-limit clamping was removed with a model switch (no violation hidden); the conditional-arc mismatch remains unexplained. Timing sign-off does not depend on the simulation; PrimeTime covers it, and the function is proven with real delays on 64 % of the arcs plus zero-delay on the adder sums.

**D.4 "Is the final result reproducible?"**
The flow is scripted and every step is in the run book. The tools are not guaranteed to give the same result twice: a fresh run would need the same kinds of fixes on different cells. We did not run a second implementation, so repeatability is **not measured**.

**D.5 "Why should I trust numbers that you collected yourself?"**
Because three tools agree, because the sign-off tool was also run on the original constraints, because more than 80 key numbers are re-read from the logs by a script every time, and because we list what could not be verified.

**D.6 "What was your own contribution versus the tools'?"**
Decisions and diagnoses: finding the hidden clock latency, deciding which limit is a course constraint and which is not, scoping the margin, designing the guarded ECO flow, correcting the simulation verdict, and organising the record. [Adjust this answer to your own role in the team **[unverified]**.]

**D.7 "What if the top-level team rejects the power pins or pin order?"**
Power: add short top-metal stubs from the stripe ends to the bottom boundary (an ECO of about an hour: fill, export, Calibre and PrimeTime again), or redo the power plan with edge pins (a large rerun). Pin order: a rerun of placement and routing.

---

# Part E — Items this document cannot prove **[unverified]**

1. Dates of the PM's confirmation of SystemVerilog and of the `FILTER_DWN2PSUB` approval.
2. That the register map, the signed-bit polarity and the DMA address convention are final (the PM has not confirmed them).
3. Whether the 18 missing VSS vias in ICC2's power-via check are harmless beyond the facts that Calibre DRC and LVS are clean.
4. The cause of the conditional-arc mismatch in the delay file.
5. Repeatability of the implementation tool.
6. The supply corner behind the power estimate (1.62 V is the project's assumption).
7. Your own role statements in D.6.
