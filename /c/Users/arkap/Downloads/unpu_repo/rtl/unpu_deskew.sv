// Output de-skew bank for the uNPU 4x4 systolic array. Delays each
// column's partial sum by (3-j) register stages (col 3 = wire, col 0 = 3
// flops) so unpu_grid's staggered psum_out (column j arrives at cycle
// m+j+4) is realigned into a single row c_out valid together at cycle
// m+7, per the timing contract (CLAUDE.md).
//
// Depths (3/2/1/0) written out explicitly, same simulator-portability
// rationale as unpu_skew.sv. Column 3 is the depth-0 wire -- the same
// known trap as unpu_skew's row 0 applies here (execution.md: "The same
// applies to unpu_deskew's column-3 (depth 0) path").
//
// Simulated with Icarus Verilog (iverilog/vvp) -- Xcelium not available in
// this environment, same as unpu_pe.sv/unpu_grid.sv.
//
// Standardized on Verilator since task 006 (iverilog isn't installed in
// that environment); every regression since (unpu_seq_tb, unpu_buf_tb,
// unpu_dma_tb, unpu_stall_tb, unpu_top_tb, task 013's own retrofit) has
// re-verified this file under it, clean every time -- see
// tb/unpu_pe_tb.sv's header for the fuller explanation.
module unpu_deskew (
  input  logic               clk,
  input  logic                rst_n,      // async, active-low (matches unpu_pe/unpu_grid)

  input  logic               array_en,    // single global enable/freeze, fans out identically to every stage
  input  logic [3:0][31:0]   psum_in,     // wire straight from unpu_grid's psum_out; column j arrives at cycle m+j+4

  output logic [3:0][31:0]   c_out        // all four columns of row m valid together at cycle m+7
);

  // Column 3: depth 0, a straight wire -- never registered.
  assign c_out[3] = psum_in[3];

  // Column 2: depth 1.
  logic [31:0] col2_q1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      col2_q1 <= 32'h0000_0000;
    else if (array_en)
      col2_q1 <= psum_in[2];
  end
  assign c_out[2] = col2_q1;

  // Column 1: depth 2.
  logic [31:0] col1_q1, col1_q2;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      col1_q1 <= 32'h0000_0000;
      col1_q2 <= 32'h0000_0000;
    end else if (array_en) begin
      col1_q1 <= psum_in[1];
      col1_q2 <= col1_q1;
    end
  end
  assign c_out[1] = col1_q2;

  // Column 0: depth 3.
  logic [31:0] col0_q1, col0_q2, col0_q3;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      col0_q1 <= 32'h0000_0000;
      col0_q2 <= 32'h0000_0000;
      col0_q3 <= 32'h0000_0000;
    end else if (array_en) begin
      col0_q1 <= psum_in[0];
      col0_q2 <= col0_q1;
      col0_q3 <= col0_q2;
    end
  end
  assign c_out[0] = col0_q3;

endmodule
