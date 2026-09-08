// 4x4 systolic array of unpu_pe. Weight-stationary, single-stage PEs.
// One global array_en/mode_unsigned fan-out; no per-row/per-column flow
// control inside the array (CLAUDE.md, handoff §6).
module unpu_grid (
  input  logic                 clk,
  input  logic                 rst_n,        // async, active-low (matches unpu_pe)

  input  logic                 array_en,     // single global enable/freeze, fans out to all 16 PEs
  input  logic                 mode_unsigned,// fans out to all 16 PEs

  input  logic [3:0][3:0]      weight_load,  // weight_load[row][col], per-PE pulse
  input  logic [3:0][3:0][7:0] weight_in,    // weight_in[row][col]

  input  logic [3:0][7:0]      act_in,       // west edge: act_in[row], row = 0..3
  input  logic [3:0][31:0]     psum_in,      // north edge: psum_in[col], col = 0..3

  output logic [3:0][7:0]      act_out,      // east edge: act_out[row]
  output logic [3:0][31:0]     psum_out      // south edge: psum_out[col]
);

  // Internal link wires: act_link[row][col] / psum_link[row][col] are the
  // registered outputs of pe[row][col].
  logic [3:0][3:0][7:0]  act_link;
  logic [3:0][3:0][31:0] psum_link;

  genvar row, col;
  generate
    for (row = 0; row < 4; row = row + 1) begin : g_row
      for (col = 0; col < 4; col = col + 1) begin : g_col

        logic [7:0]  pe_act_in;
        logic [31:0] pe_psum_in;

        if (col == 0)
          assign pe_act_in = act_in[row];
        else
          assign pe_act_in = act_link[row][col-1];

        if (row == 0)
          assign pe_psum_in = psum_in[col];
        else
          assign pe_psum_in = psum_link[row-1][col];

        unpu_pe pe (
          .clk           (clk),
          .rst_n         (rst_n),
          .array_en      (array_en),
          .weight_load   (weight_load[row][col]),
          .mode_unsigned (mode_unsigned),
          .weight_in     (weight_in[row][col]),
          .act_in        (pe_act_in),
          .psum_in       (pe_psum_in),
          .act_out       (act_link[row][col]),
          .psum_out      (psum_link[row][col])
        );

      end
    end
  endgenerate

  generate
    for (row = 0; row < 4; row = row + 1) begin : g_act_out
      assign act_out[row] = act_link[row][3];
    end
    for (col = 0; col < 4; col = col + 1) begin : g_psum_out
      assign psum_out[col] = psum_link[3][col];
    end
  endgenerate

endmodule
