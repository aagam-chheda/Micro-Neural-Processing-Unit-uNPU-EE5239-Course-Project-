// Input skew bank for the uNPU 4x4 systolic array. Delays each row's raw
// activation by k register stages (row 0 = wire, row 3 = 3 flops) so a
// caller can present A[m][0..3] all together on cycle m and have act_out
// land on unpu_grid's act_in with the west-edge skew the timing contract
// requires: A[m][k] enters west edge of row k at cycle m+k (CLAUDE.md).
//
// Depths (0/1/2/3) are written out explicitly rather than via a generate
// loop over a variable-depth register chain -- same simulator-portability
// call tb/unpu_grid_tb.sv made (see its header comment): only 4 taps
// exist, so unrolling costs nothing and removes any ambiguity about which
// row is the depth-0 wire (the known trap from execution.md: "Row 0's
// skew delay is a wire, not a register").
//
// Simulated with Icarus Verilog (iverilog/vvp) -- Xcelium not available in
// this environment, same as unpu_pe.sv/unpu_grid.sv.
module unpu_skew (
  input  logic              clk,
  input  logic              rst_n,        // async, active-low (matches unpu_pe/unpu_grid)

  input  logic              array_en,     // single global enable/freeze, fans out identically to every stage
  input  logic [3:0][7:0]   a_raw,        // raw A[m][0..3], all four presented together at cycle m

  output logic [3:0][7:0]   act_out       // act_out[k] valid at cycle m+k -- wire straight into unpu_grid's act_in
);

  // Row 0: depth 0, a straight wire -- never registered.
  assign act_out[0] = a_raw[0];

  // Row 1: depth 1.
  logic [7:0] row1_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      row1_q <= 8'h00;
    else if (array_en)
      row1_q <= a_raw[1];
  end
  assign act_out[1] = row1_q;

  // Row 2: depth 2.
  logic [7:0] row2_q1, row2_q2;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      row2_q1 <= 8'h00;
      row2_q2 <= 8'h00;
    end else if (array_en) begin
      row2_q1 <= a_raw[2];
      row2_q2 <= row2_q1;
    end
  end
  assign act_out[2] = row2_q2;

  // Row 3: depth 3.
  logic [7:0] row3_q1, row3_q2, row3_q3;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      row3_q1 <= 8'h00;
      row3_q2 <= 8'h00;
      row3_q3 <= 8'h00;
    end else if (array_en) begin
      row3_q1 <= a_raw[3];
      row3_q2 <= row3_q1;
      row3_q3 <= row3_q2;
    end
  end
  assign act_out[3] = row3_q3;

endmodule
