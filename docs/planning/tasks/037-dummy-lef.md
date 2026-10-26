# Task 037 — Generate the dummy LEF for `unpu_top` (provisional pin plan)

## Goal

The top-level team needs a LEF for the hard macro `unpu_top` before the real one
exists. Write a small generator that produces a dummy LEF (LEF 5.8) from a parameter
block, and a checker that proves the result is self-consistent. The pin plan below is
Planning's PROVISIONAL proposal (`docs/session-handoff.md` 18.9); the PM and the
top-level team have not confirmed sides, order, power or size. Everything that could
change must be a named parameter at the top of the script, so a changed answer is a
rerun, not an edit. Do not touch `rtl/`, `tb/` or `constraints/`.

A teammate may be producing a dummy LEF as well. Before starting, check with the user
that this task is wanted, and say in your report how your output differs from theirs
if they have one.

## Inputs

1. The port list from `rtl/unpu_top.sv`, parsed by the script (names, directions,
   widths). Do not type the 204 pin names by hand. Cross-check against the DC netlist
   `unpu_top_cn.dc.v` if the user supplies it.
2. The SCL tech LEF and std-cell LEF. They live on the server only
   (`/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/lef/scl18fs120_tech.lef`
   and `scl18fs120_std.lef`). Ask the user to copy them into a git-ignored directory
   (for example `temp/kit/`) and read layer names, directions, pitch, width, area,
   track OFFSET, spacing and wide-metal rules, the site and the power pin names from
   those files, not from this prompt. The values below are what the user already
   read and are for cross-checking only:
   M1 horizontal pitch 0.56 width 0.23; M2 vertical 0.56 / 0.28; M3 horizontal 0.84 /
   0.28; TOP_M vertical 1.12 / 0.44; min area 0.202 (M1..M3), 0.562 (TOP_M); site
   `CoreSite` 0.56 x 5.6; power pins `VDD`, `VSS`. If the files disagree with these,
   stop and report the difference.

## Provisional plan (all parameters)

- Macro `unpu_top`, `CLASS BLOCK`, `ORIGIN 0 0`, size 817.6 x 817.6 um, which is a
  multiple of the site width and row height. `SYMMETRY` and `SITE` lines as the
  tools expect for a block; justify what you chose.
- TOP edge: `clk`, `rst_n`, then the APB group (`paddr`, `pwdata`, `pwrite`, `psel`,
  `penable`, `prdata`, `pready`), pins on M2. 102 pins.
- RIGHT edge: the DMA group (`dma_addr`, `dma_wdata`, `dma_rdata`, `dma_wstrb`,
  `dma_valid`, `dma_ready`), pins on M3. 102 pins.
- LEFT edge: `VDD` and `VSS` as `USE POWER` / `USE GROUND` pins on TOP_M, a
  parameterised stripe width (start at 10 um; the real width comes later from a
  power estimate; check the wide-metal spacing rule before choosing).
- BOTTOM: no pins.
- Pin pitch: one common value that is a whole number of tracks on both M2 and M3
  (6.72 um = 12 M2 tracks = 8 M3 tracks); pins centred on tracks, the whole group
  centred on the edge as closely as the track grid allows. Order: grouped by bus, bit
  0 first, direction ascending left to right on top and bottom to top on the right
  (a parameter).
- Pin geometry: width = the layer's minimum width, length about 1 um into the
  block, and at least what the minimum-area rule needs (state the area you check).
- `OBS` on M1, M2, M3 and TOP_M over the interior, leaving the pin strips and the
  power stripes free so the pins stay accessible. Explain how you handled the overlap of
  pins with OBS.
- Orientation R0 is assumed; write it in a comment in the LEF header together with the
  pin plan and "PROVISIONAL DUMMY, not signoff".

## Checker (must be a separate script, run by you)

Parse the LEF the generator wrote (do not reuse its internal data) and check: 204
signal pins + 2 power pins and nothing else; names and directions equal the RTL port
list; every pin rectangle inside the macro boundary, on the stated layer, on the track
grid, with the layer's min width and min area; no two pins closer than the layer
spacing; every pin on the side the parameters say; the macro size is a multiple of the
site width and row height. Print a table of counts per side and layer. Nothing fails
silently: any violation stops the script with the full message.

## Report back

Files written (`scripts/gen_dummy_lef.py`, `scripts/check_dummy_lef.py`, the LEF in a
git-ignored `pnr/out/` unless the user wants it tracked), the per-side table, every
assumption you had to make, and anything in the kit LEF that disagreed with this prompt.
Tell the user how to load the LEF in ICC2 (`icc2_lm_shell`) to check it; do not claim
the LEF is tool-clean until they have done that.
