# I/O clock-latency research (task 083 Part A, 2026-11-10) and its diagnostic (task 084)

Question: can ICC2 U-2022.12-SP3 see PrimeTime's I/O convention (external launch/capture at the clk PIN, zero latency), and if not, what are the options?
Answer so far: **not shown**. The cause of the ICC2/PrimeTime difference is a hypothesis (H1) until `diag_io_latency.tcl` (task 084) has been run. Nothing in this file is applied to the flow.

Sources: `[L]` = read from a usage text or option list in `~/server_pull/rpt/help` (the local help dumps hold full usage for only 106 commands, the complete app-option list, and the name lists of `help *clock*` / `help *pin*`); `[M]` = from memory, VERIFY. The diagnostic saves the missing help texts (`diag/help_*.txt`), after which `[M]` becomes `[L]`.

## Facts the research starts from

- The constraints of the flow are the OLD ones: `syn/out/legacy/unpu_top_cn.sdc`, made from `constraints/legacy/unpu_top_legacy.sdc`: period 20 ns, setup uncertainty 1.5, hold uncertainty 0.5, input max delay 35% (APB) / 40% (DMA, rst_n), input min 0.0, output max 35% / 40%, output min -0.5, driving cell buffd1, output load 1.0 pF. (The stage profiles 1.2/0.6/0.05 of `constraints/unpu_top.sdc` are not read by the P&R flow.)
- An ICC2-only optimisation margin exists: `OPT_*_UNC = SPEC_*_UNC + *_SLACK_GOAL` (`cts.tcl`, `route.tcl`, `timing_closure.tcl`), clock-wide, setup in `func_ss`, hold in `func_ff`, restored before reports; the goals are 0.0 (user, 2026-11-02).
- PrimeTime (progress log 3.11): input launch `clock network delay (propagated) 0.00`; capture flop clock 0.40 ns (ff) / 0.92 ns (ss). Setup `dma_addr[31]` -0.2423 ns, hold -0.3468 ns on 263 input-to-register endpoints. ICC2 stopped hold fixing at about 0 slack on those paths (they contain `copt_h_inst` buffers, ICC2's own hold cells), so ICC2 saw about 0.4 ns less requirement. This is **consistent with** ICC2 launching the input later, but ICC2's own path report was never seen.

## Table (option | optimiser sees it | changes the SDC PrimeTime reads | syntax | source)

| # | Option | Optimiser sees | SDC changes | Syntax | Source |
|---|---|---|---|---|---|
| 1 | `set_clock_latency -source` on clk | yes, but it shifts launch and capture of internal flops AND the I/O reference together: the gap stays | yes (one line) | `set_clock_latency -source <v> [get_clocks clk]` | [M]; command exists [L] |
| 2 | separate virtual clock for the I/O delays | yes | yes: every I/O delay line; the legacy SDC is fixed | `create_clock -name vclk -period 20`, `set_input_delay -clock vclk` | [M]; not allowed for the sign-off SDC |
| 3 | `-network_latency_included` / `-source_latency_included` on `set_input_delay` / `set_output_delay` | yes: tells the tool the external delay already contains the clock latency, so it must not add it | yes (option on the I/O lines) | `set_input_delay -clock clk -network_latency_included ...` | [M] VERIFY. If H1 is true this is the principled fix; it changes the SDC text, so it needs the user's approval (the PM is not answering) |
| 4 | `set_latency_adjustment_options` | clock-tree latency adjustment for hierarchical blocks / CCD | not as remembered | `set_latency_adjustment_options` | [M]; semantics unknown, not relied on |
| 5 | `time.*` app options | none is a zero-latency I/O switch | no | `set_app_options -name time.<x>` | [L] `time.allow_port_latency_for_feedthrough` (false, feedthrough = in2out), `time.enable_io_path_groups` (true), `time.deprioritize_io_path_groups` (true: I/O groups are optimised after the others, a possible reason for weaker I/O optimisation, not verified), `time.all_clocks_propagated` (false), `time.edge_specific_source_latency` (true); `cts.balance_groups.honor_source_latency`, `.balance_by_source_latency` (false), `opt.common.estimate_clock_gate_latency` |
| 6 | `set_clock_uncertainty` | yes | no, if applied only inside the OPT block | `set_clock_uncertainty [-setup\|-hold] [-from clk] [-to clk] <value> [object_list]`; object_list may be clocks, ports or pins; remove with `remove_clock_uncertainty` | [L] usage text; the remove command is in the command list [L]. VERIFY: whether a port object gives an uncertainty only to paths ending at that port; on flop pins it hits every path into the flop, not only input paths |
| 7 | `set_path_margin` | yes, as remembered | no | PrimeTime: `set_path_margin -setup\|-hold <v> -from ... -to ...`; existence in ICC2 U-2022.12-SP3 unknown | [M]; `help *margin*` is dumped by the diagnostic |
| 8 | temporary change of the I/O delays inside the OPT block (same pattern as `OPT_*_UNC`) | yes | no, if restored | hold: `set_input_delay -clock clk -min <IN_MIN_DELAY - 0.4>` on input ports that have no path to an output; setup: `set_output_delay -clock clk -max <orig + 0.9>` on `dma_addr`, `dma_wdata`, `dma_wstrb`, `dma_valid` only | [M] semantics; original values in `constraints/legacy/unpu_top_legacy.sdc`. The only I/O-only mechanism believed to exist |

Notes on row 8: no in2out path ends at the DMA output ports, so the setup margin cannot touch the `paddr` -> `prdata` read path. For hold the margin must not be applied to `paddr[*]` (the in2out source); take the port list from the cone computation, not by hand. `rst_n` is a recovery/removal check and is left out unless decided separately. Restore by re-issuing the original values; the restore check compares one path per group and the exported SDC with and without the margin. A global `*_SLACK_GOAL` increase is NOT recommended: it hits reg-to-reg paths and the zero-margin read path, and adds hold cells everywhere.

## CTS insertion delay (L2)

Run-1 CTS: 2,465 sinks, 6 levels, 63 clock buffers, latency 0.59 ns, skew 0.31 ns (corner of the 0.59 not in the repo; the CTS log is on the server). PrimeTime later showed 0.40 ns (ff) and 0.92 ns (ss). Local option list [L]: `cts.compile.enable_local_skew`, `cts.optimize.enable_local_skew` (false), `cts.common.max_fanout`, `cts.compile.enable_global_route` (set true), `clock_opt.flow.enable_ccd` (set true); commands `set_clock_balance_points`, `create_clock_balance_group`, `create_clock_skew_group`. `set_clock_tree_options -target_skew 0.2` is set now; a `-target_latency` option is from memory [M]. A smaller insertion delay shrinks the gap proportionally but never removes it (PrimeTime's reference is zero); the run-1 skew 0.31 already misses its 0.2 target. Partial help only.

## Synthesis side (L8): a report, not a constraint

In `dc_shell` on the compiled design (VERIFY the forms): `set ALLOW 0.92` (PrimeTime's ss insertion delay, a report allowance), then for the paths to the DMA outputs print `slack` and `slack - ALLOW` (`get_timing_paths -delay_type max -max_paths 200 -to [get_ports {dma_addr[*] dma_wdata[*] dma_wstrb[*] dma_valid}]`, `get_attribute $p slack`), and `report_timing -delay_type max -to [get_ports dma_addr*] -nworst 1 -significant_digits 4`. Nothing under `constraints/legacy/` changes.

## The decision tree after the diagnostic

- H1 CONFIRMED: row 3 is the principled fix (SDC text, user approval); row 8 is the fallback that leaves the SDC alone (values 0.4 hold / 0.9 setup for the user to approve, default OFF).
- H1 REFUTED: neither fix is justified; the diagnostic lists the differences found (arrival, required, slack against PrimeTime's numbers).
- INCONCLUSIVE: read the saved reports in `pnr_icc2/diag/` by hand and send them to Planning.
