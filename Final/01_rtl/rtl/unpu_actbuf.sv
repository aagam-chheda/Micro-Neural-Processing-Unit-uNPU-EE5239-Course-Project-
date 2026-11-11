// Double-buffered activation staging for the uNPU 4x4 systolic array.
// Notebook §05/B5: a register-file-based buffer, natural row order (0,1,
// 2,3) -- activations are already consumed row-by-row in the same order
// they arrive (unpu_skew takes A[m][*] at cycle m), so unlike unpu_wbuf
// there is no settling trick to get backwards here. Deliberately simpler
// than unpu_wbuf (a plain indexed write, not a shift register) -- that is
// correct, not an inconsistency with unpu_wbuf.
//
// Sized for one 4x4 tile, double-buffered (32 bytes total), not the
// notebook's provisional 32x32-bit figure -- that number predates the
// PM's M/N/K<=4, no-tiling confirmation (handoff §6/§12); with no tiling,
// one activation tile is at most 4x4 bytes. This is a deliberate,
// reasoned departure from the notebook, not an oversight.
//
// Double buffering: bank_a and bank_b are two fully independent 4x4
// register files (not one array indexed by a runtime select), so a
// background load can complete, and `swap` can fire, while `rd_data` is
// being read combinationally from the other, active bank with array_en
// high throughout -- same property unpu_wbuf exists to prove, see its
// header comment for the failure mode a shared-state implementation
// would hit.
//
// array_en is the same global freeze used by unpu_pe/unpu_skew/
// unpu_deskew/unpu_wbuf: every registered update here (the loading write,
// the active-bank select) holds when array_en=0. rd_data has no clock
// involved at all -- a plain combinational read of the active bank,
// per the port comment.
//
// Simulated with Verilator (--binary --timing) -- iverilog is still not
// installed in this environment (no root); see docs/planning/plan.md's
// "Tooling note" for the open, non-blocking decision on standardizing.
module unpu_actbuf (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  array_en,

  input  logic                  load_start,     // 1-cycle pulse; load_row must carry row 0's data on this same cycle
  input  logic [2:0]            load_m,         // real M (1-4), latched at load_start
  input  logic [2:0]            load_k,         // real K (1-4), latched at load_start
  input  logic [3:0][7:0]       load_row,       // this cycle's row of 4 activation bytes, one per K-column
  output logic                  load_busy,      // high for exactly the 4 loading cycles
  output logic                  load_done,      // 1-cycle pulse, the cycle after the 4th row is accepted

  input  logic                  swap,           // 1-cycle pulse; only meaningful after load_done has fired since the last swap

  input  logic [1:0]            rd_row,         // 0-3
  output logic [3:0][7:0]       rd_data         // active_bank[rd_row][*] -- wire straight into unpu_skew.a_raw
);

  logic [3:0][3:0][7:0] bank_a; // bank_a[row][col]
  logic [3:0][3:0][7:0] bank_b;
  logic                 active_sel; // 0: bank_a active (bank_b loads). 1: bank_b active (bank_a loads).

  // ---- Loading sequencing: identical structure to unpu_wbuf, but
  // natural order -- cur_cyc IS the row index directly, no reversal. ----
  logic       active_load;
  logic [1:0] cyc_idx;
  logic       shifting;
  logic [1:0] cur_cyc;
  logic [2:0] row_idx;

  assign shifting = load_start || active_load;
  assign cur_cyc  = load_start ? 2'd0 : cyc_idx;
  assign row_idx  = {1'b0, cur_cyc}; // natural order: cur_cyc IS the row being written

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_load <= 1'b0;
      cyc_idx     <= 2'd0;
    end else if (array_en) begin
      if (load_start) begin
        active_load <= 1'b1;
        cyc_idx     <= 2'd1;
      end else if (active_load) begin
        if (cyc_idx == 2'd3)
          active_load <= 1'b0;
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
      load_done_reg <= (active_load && cyc_idx == 2'd3);
  end
  assign load_done = load_done_reg;

  // ---- Shadow-latched M/K, same rationale as unpu_wbuf's K/N. ----
  logic [2:0] m_lat, k_lat;
  logic [2:0] eff_m, eff_k;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_lat <= 3'd0;
      k_lat <= 3'd0;
    end else if (array_en && load_start) begin
      m_lat <= load_m;
      k_lat <= load_k;
    end
  end

  assign eff_m = load_start ? load_m : m_lat;
  assign eff_k = load_start ? load_k : k_lat;

  // ---- M/K masking: force the whole row to 0 if this row is beyond
  // load_m; force any column beyond load_k to 0 regardless of row. ----
  logic [3:0][7:0] masked_row;
  genvar gm;
  generate
    for (gm = 0; gm < 4; gm = gm + 1) begin : g_mask
      assign masked_row[gm] = (row_idx >= eff_m) ? 8'h00 :
                               ((3'(gm) >= eff_k) ? 8'h00 : load_row[gm]);
    end
  endgenerate

  // ---- Bank storage: direct indexed write (no shift network needed),
  // each bank written only while it is the INACTIVE (loading) bank. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bank_a <= '0;
    end else if (array_en && shifting && active_sel) begin // active_sel==1: bank_a is inactive
      bank_a[row_idx[1:0]] <= masked_row;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bank_b <= '0;
    end else if (array_en && shifting && !active_sel) begin // active_sel==0: bank_b is inactive
      bank_b[row_idx[1:0]] <= masked_row;
    end
  end

  // ---- Swap: flips which bank is active. Gated on array_en, same
  // rationale as unpu_wbuf. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      active_sel <= 1'b0;
    else if (array_en && swap)
      active_sel <= ~active_sel;
  end

  // ---- Read side: plain combinational read of the active bank, no
  // clock involved. ----
  logic [3:0][3:0][7:0] active_bank;
  assign active_bank = active_sel ? bank_b : bank_a;
  assign rd_data      = active_bank[rd_row];

endmodule
