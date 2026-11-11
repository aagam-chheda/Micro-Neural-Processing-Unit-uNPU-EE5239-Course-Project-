// Double-buffered weight staging for the uNPU 4x4 systolic array.
// Notebook §05/B4: weights arrive as one 32-bit row (4 bytes) per cycle
// and must land in all 16 PEs at once on a tile swap -- a 4-deep shift
// register per column, loaded in REVERSE row order (row 3 first), is what
// makes every row settle into its own stage index after exactly 4 shifts.
// See docs/planning/tasks/007-buffers.md for the full worked trace; the
// short version:
//
//   cycle | injected | stage[0] | stage[1] | stage[2] | stage[3]
//   0     | row 3    | row3     | -        | -        | -
//   1     | row 2    | row2     | row3     | -        | -
//   2     | row 1    | row1     | row2     | row3     | -
//   3     | row 0    | row0     | row1     | row2     | row3
//
// After cycle 3, stage[col][r] == row r's data for every r. Load in
// natural order (0,1,2,3) instead and every row lands one position away
// from where it belongs -- "the most common bug in a first systolic
// array" per the notebook, silently producing plausible-looking wrong
// answers rather than an obvious failure.
//
// Double buffering: bank_a and bank_b are two FULLY SEPARATE register
// arrays (not one array indexed by a runtime select) -- loading always
// targets whichever bank `active_sel` says is currently INACTIVE, so a
// background load can run to completion, and `swap` can fire, while the
// grid is mid-compute against the other, active bank with array_en high
// throughout. That decoupling is the entire point of this module; a
// design where the loading write path and the active-bank read path
// share any state would fail the concurrent-load test in
// tb/unpu_buf_tb.sv even though it might pass a sequential
// load-then-compute test.
//
// array_en is the same global freeze used by unpu_pe/unpu_skew/
// unpu_deskew: every registered update here (the loading shift, the
// active-bank select) holds when array_en=0, same convention, same
// reasoning (CLAUDE.md/handoff §6: one global array_en, no independent
// flow control). weight_load is a direct combinational pass-through of
// `swap` regardless of array_en -- harmless if array_en happens to be 0
// on a swap cycle (unpu_pe only latches weight_in when array_en and
// weight_load are BOTH 1, so the grid simply ignores a swap pulse that
// arrives with array_en low), while active_sel itself only advances when
// array_en is also 1, so this module's own notion of "which bank is
// active" never drifts ahead of what the grid actually captured. The
// known trap this exists to dodge: assert array_en=1 on the exact swap
// cycle, not just before/after it, or the grid never latches the new
// bank (same trap unpu_seq's LOAD_WEIGHTS state hit).
//
// Simulated with Verilator (--binary --timing) -- iverilog is still not
// installed in this environment (no root); see docs/planning/plan.md's
// "Tooling note" for the open, non-blocking decision on standardizing.
module unpu_wbuf (
  input  logic                  clk,
  input  logic                  rst_n,          // async, active-low
  input  logic                  array_en,       // same global freeze as grid/skew/deskew

  input  logic                  load_start,     // 1-cycle pulse; load_row must carry row 3's data on this same cycle
  input  logic [2:0]            load_k,         // real K (1-4) for this tile, latched at load_start
  input  logic [2:0]            load_n,         // real N (1-4) for this tile, latched at load_start
  input  logic [3:0][7:0]       load_row,       // this cycle's row of 4 weight bytes, one per column
  output logic                  load_busy,      // high for exactly the 4 loading cycles
  output logic                  load_done,      // 1-cycle pulse, the cycle after the 4th row is accepted

  input  logic                  swap,           // 1-cycle pulse; only meaningful after load_done has fired since the last swap

  output logic [3:0][3:0]       weight_load,    // -> unpu_grid.weight_load
  output logic [3:0][3:0][7:0]  weight_in       // -> unpu_grid.weight_in
);

  // Two fully independent banks, stage[col][row] (matches the notebook's
  // own indexing -- transposed into weight_in[row][col] only at the
  // grid-facing read below).
  logic [3:0][3:0][7:0] bank_a;
  logic [3:0][3:0][7:0] bank_b;
  logic                 active_sel; // 0: bank_a active (bank_b loads). 1: bank_b active (bank_a loads).

  // ---- Loading sequencing: 4 shift cycles, cycle 0 == the load_start
  // cycle itself (load_row already carries row 3 that same cycle, per the
  // port comment), cycles 1-3 driven by the registered `active_load` +
  // `cyc_idx`. ----
  logic       active_load;
  logic [1:0] cyc_idx;
  logic       shifting;
  logic [1:0] cur_cyc;
  logic [2:0] row_idx;

  assign shifting = load_start || active_load;
  assign cur_cyc  = load_start ? 2'd0 : cyc_idx;
  assign row_idx  = 3'd3 - {1'b0, cur_cyc}; // reverse order: cur_cyc 0->row3, 1->row2, 2->row1, 3->row0

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_load <= 1'b0;
      cyc_idx     <= 2'd0;
    end else if (array_en) begin
      if (load_start) begin
        active_load <= 1'b1;
        cyc_idx     <= 2'd1; // cycle 0 is this cycle (load_start itself); next cycle is 1
      end else if (active_load) begin
        if (cyc_idx == 2'd3)
          active_load <= 1'b0; // cycle 3 (row 0) just shifted; stop after this
        else
          cyc_idx <= cyc_idx + 2'd1;
      end
    end
  end

  assign load_busy = shifting;

  logic load_done_reg;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      load_done_reg <= 1'b0;
    else if (array_en)
      load_done_reg <= (active_load && cyc_idx == 2'd3); // true only on the cycle-3 edge; visible one cycle later
  end
  assign load_done = load_done_reg;

  // ---- Shadow-latched K/N: live load_k/load_n on the load_start cycle
  // itself, the registered shadow copy on every cycle after (same
  // "don't let it change mid-load" rationale as unpu_seq's m_lat/k_lat/
  // n_lat). ----
  logic [2:0] k_lat, n_lat;
  logic [2:0] eff_k, eff_n;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      k_lat <= 3'd0;
      n_lat <= 3'd0;
    end else if (array_en && load_start) begin
      k_lat <= load_k;
      n_lat <= load_n;
    end
  end

  assign eff_k = load_start ? load_k : k_lat;
  assign eff_n = load_start ? load_n : n_lat;

  // ---- K/N masking: force the whole row to 0 if this row is beyond
  // load_k; force any column beyond load_n to 0 regardless of row.
  // Self-contained so the caller doesn't have to pre-zero load_row. ----
  logic [3:0][7:0] masked_row;
  genvar gm;
  generate
    for (gm = 0; gm < 4; gm = gm + 1) begin : g_mask
      assign masked_row[gm] = (row_idx >= eff_k) ? 8'h00 :
                               ((3'(gm) >= eff_n) ? 8'h00 : load_row[gm]);
    end
  endgenerate

  // ---- Bank storage: two separate shift-register arrays, each written
  // only while it is the INACTIVE (loading) bank. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bank_a <= '0;
    end else if (array_en && shifting && active_sel) begin // active_sel==1: bank_a is inactive
      for (int c = 0; c < 4; c++) begin
        bank_a[c][3] <= bank_a[c][2];
        bank_a[c][2] <= bank_a[c][1];
        bank_a[c][1] <= bank_a[c][0];
        bank_a[c][0] <= masked_row[c];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bank_b <= '0;
    end else if (array_en && shifting && !active_sel) begin // active_sel==0: bank_b is inactive
      for (int c = 0; c < 4; c++) begin
        bank_b[c][3] <= bank_b[c][2];
        bank_b[c][2] <= bank_b[c][1];
        bank_b[c][1] <= bank_b[c][0];
        bank_b[c][0] <= masked_row[c];
      end
    end
  end

  // ---- Swap: flips which bank is active. Gated on array_en so this
  // module's own notion of "active" never advances ahead of what the
  // grid actually captured (see header comment). ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      active_sel <= 1'b0;
    else if (array_en && swap)
      active_sel <= ~active_sel;
  end

  // ---- Grid-facing outputs: always reflect the ACTIVE bank.
  //
  // `active_sel` is a register that only updates on the clock edge AFTER
  // `swap` is sampled -- so on the swap cycle itself, active_sel still
  // reads its OLD value. Deriving active_bank straight from active_sel
  // would make weight_in show the OLD bank on the very cycle weight_load
  // pulses, and unpu_pe latches weight_in on that same edge -- capturing
  // stale (pre-swap) weights, one cycle before weight_in ever reflects
  // the new bank. `effective_sel` looks ahead to what active_sel is
  // ABOUT TO become this cycle (same same-cycle-lookahead idiom
  // unpu_seq's LATCH_CFG uses for dim_illegal), so weight_in already
  // shows the new bank on the exact cycle weight_load pulses, matching
  // the port's own contract ("pulsed for exactly one cycle, on swap") and
  // the known trap (array_en=1 that same cycle is what makes the grid
  // actually latch it). ----
  assign weight_load = swap ? '1 : '0;

  logic                 effective_sel;
  logic [3:0][3:0][7:0] active_bank; // active_bank[col][row]
  assign effective_sel = active_sel ^ (swap && array_en);
  assign active_bank   = effective_sel ? bank_b : bank_a;

  genvar gr, gc;
  generate
    for (gr = 0; gr < 4; gr = gr + 1) begin : g_wr
      for (gc = 0; gc < 4; gc = gc + 1) begin : g_wc
        assign weight_in[gr][gc] = active_bank[gc][gr]; // transpose: stage[col][row] -> weight_in[row][col]
      end
    end
  endgenerate

endmodule
