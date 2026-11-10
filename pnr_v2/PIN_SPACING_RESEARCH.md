# Why the second `place_pins` ignored the 8 um spacing, and what pin placement can and cannot do for the antenna problem (task 085 Part 2, read-only research)

Nothing here is implemented. Sources: `[L]` = read in `~/server_pull/rpt/help` (usage texts and the app-option list), `[R]` = the repo (floorplan script, task 067/068 files, progress log), `[M]` = from memory, VERIFY.

## 1. What is known

- Constraints of the floorplan (`floorplanning.tcl`) [R]: `set_block_pin_constraints -self -allowed_layers {M2 M3 TOP_M} -pin_spacing 2` (2 TRACKS), then per port group `set_individual_pin_constraints -ports <side 2: dma_*> -sides 2 -allowed_layers {M2} -pin_spacing_distance 8` and the same for side 3 (APB, clk, rst_n; M3), then `place_pins -self`. Die 885.6 x 885.6 um, 102 pins on the top edge (M2) and 102 on the right edge (M3).
- Task 067 (`pin_replace.tcl`, parked) [R]: the second `place_pins -self` after placement moved 196 of 204 pins, produced a centre pitch of 0.56 to 0.61 um (the track pitch, so the spacing constraint was not honoured at all), and its legality count was unreadable. Constraints were NOT removed or re-set between the two calls; the pins' physical status was not shown to be fixed.
- Measured pin-to-load distances stayed 100 to 250 um after the second call [R].

## 2. What pin placement can do at most (the geometry)

- 102 pins x 8 um spacing = 101 gaps x 8 = 808 um of an edge of 885.6 um: 91 percent of the edge. With the spacing honoured, a pin can only change its ORDER along the edge; there is almost no free space to cluster the pins near their loads.
- The loads sit near the middle (`u_csr` registers at y about 420 to 435 um [R, task 068]); the pins are on the edges. Even a perfect ordering leaves the distance from the edge to the load as a floor (about the half die, 440 um, for a load in the middle; the horizontal part alone is far above the 72 um (M2/M3) and 46 um (TOP_M) limits). Only about 10 pins fit within +-40 um (8 um pitch) of one load y.
- With the spacing IGNORED (pitch 0.56) the pins can cluster, which is why the second call looked attractive, but then the top-level team's pin rule (8 um) is broken.
- Conclusion: for this design (loads in the middle, 8 um pitch, 102 pins per edge), re-placing the pins cannot bring most input nets under the antenna limit. A buffer next to the pin (step 4c) is needed whatever the pin placement. The statement "if it works, a later flow could avoid buffers entirely" holds at best for a handful of nets whose loads happen to be near an edge. The in2out argument against buffers therefore has to be settled with the cone gate of step 4c, not with pins.

## 3. Why the spacing was ignored: candidate causes, in order of likelihood (none verified)

1. Spacing is a SOFT constraint unless declared hard. `set_block_pin_constraints` has `-hard_constraints off | location | spacing | layer | length` [L] (the default is not printed in the usage text). In the first call nothing pulls the pins together; in the second call the placed cells pull each pin towards its loads and a soft spacing loses. Test: `set_block_pin_constraints -self -hard_constraints spacing` (and `layer`) before the second call.
2. The second call is incremental in the sense that existing pins are treated as the starting point, and `plan.pins.incremental` (bool, false) [L] plus `plan.pins.pin_range` (10), `plan.pins.layer_range` (2), `plan.pins.strict_alignment` (false) [L] decide how far and how they may move. The usage of `place_pins` [L] has `-legalize` ("Only legalize pin placement"): a call `place_pins -self -legalize` AFTER the second placement should push pins that violate spacing/layer rules back to legal positions with minimal moves.
3. The spacing is stated in two different units: the block constraint in tracks (`-pin_spacing 2` = 2 tracks, 0.56 um x 2) and the individual constraint in micrometres (`-pin_spacing_distance 8`). If the block-level value wins in the second call, the observed 0.56 to 0.61 um pitch is exactly "1 to 2 tracks". Test: set the block-level constraint in micrometres as well (`-pin_spacing_distance 8`) and `-hard_constraints spacing`.
4. After `powerplanning.tcl` the power mesh exists; `plan.pins.ignore_pin_spacing_constraint_to_pg` (false) and `plan.pins.treat_pg_as_shield` (false) [L] affect how pins avoid power straps; a conflict could make the placer drop the spacing rule. Lower likelihood; check with the pin-placement report.

## 4. A concrete sequence to try (NOT implemented; each item VERIFY)

1. Before the second call: print the terminal status (`physical_status`) and the pitch per edge (as `pin_replace.tcl` does); `report_pin_placement -self` [M] and `check_pin_placement -self` [R: used in the floorplan script].
2. `set_block_pin_constraints -self -allowed_layers {M2 M3 TOP_M} -pin_spacing_distance 8 -hard_constraints {spacing layer}` [L option names; whether a list is accepted: VERIFY] (units in micrometres; the individual constraints stay as they are).
3. `place_pins -self`; measure the centre pitch per edge; if any pitch is below 8 um: `place_pins -self -legalize`; measure again.
4. If the pitch is still wrong: plan B of `pin_replace.tcl` (`remove_terminals -force` on the signal terminals, then `place_pins -self` from the constraints) is the clean-slate repeat of the first call and must give the first call's pitch.
5. Decision gate: if the spacing is honoured, compare the pin-to-load distances with the 46 / 72 um limits for every input net. Expected from section 2: most nets stay above the limit, so the value of the exercise is small; do it only if the cheap steps 1 to 3 are quick.

## 5. VERIFY list

P1 the default of `-hard_constraints`; P2 whether `-hard_constraints` takes a list; P3 `place_pins -legalize` semantics; P4 `plan.pins.incremental` semantics; P5 the unit of the block-level `-pin_spacing` (tracks) against `-pin_spacing_distance` (um); P6 the horizontal position of the loads (the x of the `u_csr` registers) to turn the floor of section 2 into a number.
