// Single-stage systolic processing element for the uNPU 4x4 INT8 array.
// One multiply-accumulate per clock, no pipelining (50 MHz target).
module unpu_pe (
  input  logic              clk,
  input  logic              rst_n,        // async, active-low

  input  logic              array_en,     // single global enable/freeze signal
  input  logic              weight_load,  // pulse: capture weight_in this cycle
  input  logic              mode_unsigned,// 0 = signed interpretation, 1 = unsigned

  input  logic [7:0]        weight_in,
  input  logic [7:0]        act_in,
  input  logic [31:0]       psum_in,

  output logic [7:0]        act_out,      // registered pass-through, feeds PE to the east
  output logic [31:0]       psum_out      // registered accumulate, feeds PE to the south
);

  logic [7:0]  weight_reg;
  logic [31:0] product;

  // Combinational multiply, interpretation selected by mode_unsigned.
  // weight_reg is the value already latched (previous cycle's load, if any) --
  // this is a plain read, so a weight_load happening this same cycle cannot
  // affect the product computed this same cycle.
  always_comb begin
    if (mode_unsigned)
      product = $unsigned(weight_reg) * $unsigned(act_in);
    else
      product = 32'($signed(weight_reg) * $signed(act_in));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_reg <= 8'h00;
      act_out    <= 8'h00;
      psum_out   <= 32'h0000_0000;
    end else if (array_en) begin
      if (weight_load)
        weight_reg <= weight_in;
      act_out  <= act_in;
      psum_out <= psum_in + product;
    end
    // array_en == 0: every register holds, including weight_reg even if
    // weight_load happens to be asserted.
  end

endmodule
