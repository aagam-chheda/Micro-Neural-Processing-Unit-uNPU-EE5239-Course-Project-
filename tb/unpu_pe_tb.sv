// Directed unit test for unpu_pe. Self-checking, 20 vectors.
// Simulated with Icarus Verilog (iverilog/vvp) -- Xcelium not available in
// this environment. No SystemVerilog constructs used beyond what iverilog
// supports (logic, always_ff/comb, $signed/$unsigned, size casts).
`timescale 1ns/1ps

module unpu_pe_tb;

  logic        clk;
  logic        rst_n;
  logic        array_en;
  logic        weight_load;
  logic        mode_unsigned;
  logic [7:0]  weight_in;
  logic [7:0]  act_in;
  logic [31:0] psum_in;
  logic [7:0]  act_out;
  logic [31:0] psum_out;

  int errors;
  int vec_num;

  unpu_pe dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .array_en      (array_en),
    .weight_load   (weight_load),
    .mode_unsigned (mode_unsigned),
    .weight_in     (weight_in),
    .act_in        (act_in),
    .psum_in       (psum_in),
    .act_out       (act_out),
    .psum_out      (psum_out)
  );

  // 50 MHz-equivalent period is irrelevant to functional sim; use 10ns.
  initial clk = 0;
  always #5 clk = ~clk;

  // Drive one clock edge and settle.
  task automatic step;
    @(posedge clk);
    #1; // allow NBAs to settle before checking
  endtask

  task automatic check_act(input logic [7:0] exp, input string what);
    if (act_out !== exp) begin
      $display("VECTOR %0d FAIL (act_out): %s -- exp=%0h got=%0h", vec_num, what, exp, act_out);
      errors++;
    end
  endtask

  task automatic check_psum(input logic [31:0] exp, input string what);
    if (psum_out !== exp) begin
      $display("VECTOR %0d FAIL (psum_out): %s -- exp=%0d got=%0d", vec_num, what, exp, psum_out);
      errors++;
    end
  endtask

  task automatic pass_report(input string what);
    $display("VECTOR %0d PASS: %s", vec_num, what);
  endtask

  // Load weight_reg with a known value via a clean weight_load pulse while
  // array_en is high, with act_in held at 0 so psum is untouched.
  task automatic load_weight(input logic [7:0] w);
    weight_load = 1;
    weight_in   = w;
    act_in      = 8'h00;
    step();
    weight_load = 0;
  endtask

  initial begin
    errors        = 0;
    vec_num       = 0;
    rst_n         = 0;
    array_en      = 0;
    weight_load   = 0;
    mode_unsigned = 0;
    weight_in     = 8'h00;
    act_in        = 8'h00;
    psum_in       = 32'h0;

    // Reset pulse.
    step();
    step();
    rst_n = 1;
    array_en = 1;
    step();

    // ---- Vector 1: max positive, signed mode, nonzero psum_in ----
    vec_num = 1;
    mode_unsigned = 0;
    load_weight(8'h7F);
    act_in  = 8'h7F;
    psum_in = 32'd1000;
    step();
    check_psum(32'd1000 + 32'd16129, "max positive 127*127 on top of psum_in=1000");
    pass_report("max positive signed");

    // ---- Vector 2: max negative, signed mode ----
    vec_num = 2;
    load_weight(8'h80); // -128
    act_in  = 8'h80;    // -128
    psum_in = 32'd500;
    step();
    check_psum(32'd500 + 32'd16384, "max negative (-128)*(-128)=16384 on top of psum_in=500");
    pass_report("max negative signed");

    // ---- Vector 3: zero weight ----
    vec_num = 3;
    load_weight(8'h00);
    act_in  = 8'h55;
    psum_in = 32'd777;
    step();
    check_psum(32'd777, "zero weight contributes nothing");
    check_act(8'h55, "act_out passes activation through even with zero weight");
    pass_report("zero weight");

    // ---- Vector 4: weight-load-while-computing ----
    vec_num = 4;
    load_weight(8'h02); // stationary weight = 2
    // stream a few cycles with the loaded weight
    act_in  = 8'h03;
    psum_in = 32'd0;
    step(); // psum_out = 0 + 3*2 = 6
    check_psum(32'd6, "stream cycle 1 with weight=2");
    act_in  = 8'h04;
    psum_in = 32'd6;
    step(); // psum_out = 6 + 4*2 = 14
    check_psum(32'd14, "stream cycle 2 with weight=2");
    // Now assert weight_load with a new weight AND nonzero act_in on the same cycle.
    weight_load = 1;
    weight_in   = 8'h09; // new weight = 9, should not affect this cycle's product
    act_in      = 8'h05;
    psum_in     = 32'd14;
    step(); // this cycle's product must still use OLD weight (2): 14 + 5*2 = 24
    check_psum(32'd24, "product this cycle uses OLD weight despite simultaneous load");
    weight_load = 0;
    // Next cycle: new weight (9) must now be in effect.
    act_in  = 8'h05;
    psum_in = 32'd24;
    step(); // 24 + 5*9 = 69
    check_psum(32'd69, "new weight in effect the following cycle");
    pass_report("weight-load-while-computing");

    // ---- Vector 5a: 0xFF*0xFF signed ----
    vec_num = 5;
    load_weight(8'hFF);
    mode_unsigned = 0;
    act_in  = 8'hFF;
    psum_in = 32'd0;
    step();
    check_psum(32'd1, "signed 0xFF*0xFF = (-1)*(-1) = 1");
    pass_report("0xFF*0xFF signed");

    // ---- Vector 6: 0xFF*0xFF unsigned ----
    vec_num = 6;
    // weight_reg already holds 0xFF from vector 5; just flip mode.
    mode_unsigned = 1;
    act_in  = 8'hFF;
    psum_in = 32'd0;
    step();
    check_psum(32'd65025, "unsigned 0xFF*0xFF = 255*255 = 65025");
    pass_report("0xFF*0xFF unsigned");
    mode_unsigned = 0;

    // ---- Vector 7: array_en freeze ----
    vec_num = 7;
    load_weight(8'h03);
    act_in  = 8'h02;
    psum_in = 32'd0;
    step(); // psum_out = 0 + 2*3 = 6
    check_psum(32'd6, "pre-freeze baseline");
    array_en = 0;
    // Toggle everything that should be ignored while frozen.
    act_in      = 8'hAA;
    weight_in   = 8'hBB;
    weight_load = 1;
    psum_in     = 32'hFFFF_FFFF;
    step();
    check_psum(32'd6, "psum_out frozen despite psum_in/act_in change");
    check_act(8'h02, "act_out frozen despite act_in change");
    act_in      = 8'hCC;
    weight_load = 0;
    step();
    check_psum(32'd6, "psum_out still frozen on 2nd frozen cycle");
    check_act(8'h02, "act_out still frozen on 2nd frozen cycle");
    array_en = 1;
    pass_report("array_en freeze holds psum/act");

    // ---- Vector 8: weight register also frozen (weight_load ignored while array_en=0) ----
    vec_num = 8;
    // weight_load pulse above (vector 7, while array_en=0) requested weight=0xBB;
    // since array_en was low it must have been ignored -- weight_reg should
    // still be 0x03 from before the freeze.
    act_in  = 8'h04;
    psum_in = 32'd0;
    step(); // if weight_reg is still 3: 0 + 4*3 = 12; if it wrongly captured 0xBB, wrong result
    check_psum(32'd12, "weight_load during freeze was ignored; weight_reg still 3");
    pass_report("weight register frozen during array_en=0");

    // ---- Vector 9: reset behavior ----
    vec_num = 9;
    rst_n = 0;
    step();
    check_act(8'h00, "act_out clears on reset");
    check_psum(32'd0, "psum_out clears on reset");
    rst_n = 1;
    step();
    pass_report("reset clears act_out and psum_out");

    // ---- Vector 10: weight_reg also clears on reset ----
    vec_num = 10;
    act_in  = 8'h07;
    psum_in = 32'd0;
    step(); // weight_reg should be 0 post-reset: 0 + 7*0 = 0
    check_psum(32'd0, "weight_reg cleared by reset, product is zero");
    pass_report("weight register cleared by reset");

    // ---- Vector 11: back-to-back weight loads, only last one sticks ----
    vec_num = 11;
    weight_load = 1;
    weight_in   = 8'h05;
    act_in      = 8'h00;
    step();
    weight_in   = 8'h0A;
    step(); // weight_reg now 0x0A
    weight_load = 0;
    act_in  = 8'h02;
    psum_in = 32'd0;
    step();
    check_psum(32'd20, "back-to-back loads: only final value (0x0A=10) sticks, 2*10=20");
    pass_report("back-to-back weight loads");

    // ---- Vector 12: mid-range signed values, positive*negative ----
    vec_num = 12;
    load_weight(8'd50);        // +50
    act_in  = -8'sd20;         // -20 as 8-bit two's complement
    psum_in = 32'd1000;
    mode_unsigned = 0;
    step(); // 1000 + 50*(-20) = 1000 - 1000 = 0
    check_psum(32'd0, "mid-range signed 50 * -20 = -1000, psum_in=1000 -> 0");
    pass_report("mid-range signed positive*negative");

    // ---- Vector 13: mid-range signed values, negative*negative ----
    vec_num = 13;
    load_weight(-8'sd30);      // -30
    act_in  = -8'sd4;          // -4
    psum_in = 32'd10;
    step(); // 10 + (-30)*(-4) = 10 + 120 = 130
    check_psum(32'd130, "mid-range signed -30 * -4 = 120, psum_in=10 -> 130");
    pass_report("mid-range signed negative*negative");

    // ---- Vector 14: psum_in near 0x7FFFFFFF, no accidental narrowing ----
    vec_num = 14;
    load_weight(8'h01);
    act_in  = 8'h01;
    psum_in = 32'h7FFF_FFFE;
    step(); // 0x7FFFFFFE + 1 = 0x7FFFFFFF, must not narrow/wrap
    check_psum(32'h7FFF_FFFF, "psum_in near max positive, +1, no narrowing");
    pass_report("psum near 0x7FFFFFFF no narrowing");

    // ---- Vector 15: psum_in that would overflow if accumulator were narrower ----
    vec_num = 15;
    load_weight(8'h7F);
    act_in  = 8'h7F;
    psum_in = 32'hFFFF_0000; // large existing accumulation
    step(); // 0xFFFF0000 + 16129, full 32-bit wraparound arithmetic is fine/expected
    check_psum(32'hFFFF_0000 + 32'd16129, "large psum_in + max product, full 32-bit add");
    pass_report("large psum_in plus max product");

    // ---- Vector 16: zero activation ----
    vec_num = 16;
    load_weight(8'h64); // 100
    act_in  = 8'h00;
    psum_in = 32'd42;
    step();
    check_psum(32'd42, "zero activation contributes nothing regardless of weight");
    check_act(8'h00, "act_out passes zero activation through");
    pass_report("zero activation");

    // ---- Vector 17: act_out pass-through is registered (one-cycle latency) ----
    vec_num = 17;
    act_in = 8'h33;
    psum_in = 32'd0;
    step();
    check_act(8'h33, "act_out reflects the act_in from the just-completed edge");
    act_in = 8'h44;
    // Before the next edge, act_out must still show the old value (not yet updated).
    if (act_out !== 8'h33) begin
      $display("VECTOR %0d FAIL: act_out changed combinationally, expected registered behavior", vec_num);
      errors++;
    end
    step();
    check_act(8'h44, "act_out updates to new act_in only after the next edge");
    pass_report("act_out registered pass-through latency");

    // ---- Vector 18: weight_load with array_en high but act_in nonzero same cycle (no simultaneity trap) ----
    vec_num = 18;
    weight_load = 1;
    weight_in   = 8'h06;
    act_in      = 8'h07;
    psum_in     = 32'd0;
    step(); // must use weight BEFORE this load (0x64=100 from vector 16): 100*7=700
    weight_load = 0;
    check_psum(32'd700, "load pulse this cycle does not affect this cycle's product (old weight=100)");
    act_in  = 8'h07;
    psum_in = 32'd0;
    step(); // now weight=6: 6*7=42
    check_psum(32'd42, "new weight (6) in effect next cycle");
    pass_report("weight_load simultaneity, second confirmation");

    // ---- Vector 19: unsigned mode with small values (sanity, not just 0xFF case) ----
    vec_num = 19;
    mode_unsigned = 1;
    load_weight(8'd12);
    act_in  = 8'd10;
    psum_in = 32'd5;
    step(); // 5 + 12*10 = 125
    check_psum(32'd125, "unsigned mode small-value sanity 12*10=120, +5=125");
    mode_unsigned = 0;
    pass_report("unsigned mode small values");

    // ---- Vector 20: signed mode with small values (sanity) ----
    vec_num = 20;
    load_weight(8'd12);
    act_in  = -8'sd10;
    psum_in = 32'd5;
    step(); // 5 + 12*(-10) = -115
    check_psum(32'd5 - 32'd120, "signed mode small-value sanity 12*-10=-120, +5=-115");
    pass_report("signed mode small values");

    $display("----------------------------------------");
    if (errors == 0)
      $display("ALL 20 VECTORS PASSED");
    else
      $display("%0d FAILURE(S) OUT OF 20 VECTORS", errors);
    $display("----------------------------------------");

    $finish;
  end

endmodule
