// Directed unit test for unpu_pe. Self-checking, 20 vectors, plus (task
// 013, verification-debt retrofit) an exhaustive 256x256 signed and
// 256x256 unsigned operand sweep, a randomized accumulator sweep, and
// randomized weight-load timing -- the full operand space is small
// enough to cover completely, so exhaustive coverage is used there
// instead of calling a random subset of it "CRV"; randomization is
// reserved for the one part of this module with a genuinely large space
// (weight-load timing relative to ongoing accumulation).
//
// Task 013's later additions were simulated with Verilator
// (--binary --timing) -- iverilog is not installed in this environment
// (no root to apt-get install it); the "Simulated with Icarus Verilog"
// line below is stale for this environment (flagged in task 006's
// commit already) but left as written since fixing it is outside this
// task's scope (testbench additions only, not a documentation pass).
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

  // ---- Task 013 Part A: independent expected-value derivation. Sign
  // extension here is done by arithmetic (subtract 256 if the top bit is
  // set), deliberately NOT via SystemVerilog's $signed() cast -- using
  // $signed()/$unsigned() here would just mirror unpu_pe.sv's own
  // combinational logic back at itself, proving the RTL agrees with a
  // copy of itself rather than with an independently-derived value from
  // CLAUDE.md's INT8/32-bit-accumulator description. ----
  function automatic int signed to_signed8(input logic [7:0] v);
    if (v[7])
      return int'(v) - 256;
    else
      return int'(v);
  endfunction

  function automatic logic [31:0] expected_mac(input logic [7:0] w, input logic [7:0] a,
                                                input logic [31:0] psum, input bit mode_uns);
    int unsigned uw, ua, uprod;
    int signed   sw, sa, sprod;
    begin
      if (mode_uns) begin
        uw = {24'd0, w};
        ua = {24'd0, a};
        uprod = uw * ua;
        expected_mac = psum + uprod;
      end else begin
        sw = to_signed8(w);
        sa = to_signed8(a);
        sprod = sw * sa;
        expected_mac = psum + sprod;
      end
    end
  endfunction

  function automatic logic [31:0] xorshift32(input logic [31:0] x);
    logic [31:0] y;
    begin
      y = x;
      y = y ^ (y << 13);
      y = y ^ (y >> 17);
      y = y ^ (y << 5);
      xorshift32 = y;
    end
  endfunction

  task automatic check_weight_reg(input logic [7:0] exp, input string what);
    if (dut.weight_reg !== exp) begin
      $display("VECTOR %0d FAIL (weight_reg, hierarchical): %s -- exp=%0h got=%0h", vec_num, what, exp, dut.weight_reg);
      errors++;
    end
  endtask

  // ---- Task 019: biased random draws for the adversarial long-sequence
  // test. ~1/8 of draws land on a boundary extreme instead of a plain
  // uniform value -- deliberately, per the task's own instruction not to
  // rely on uniform random to find the boundaries by chance. Each call
  // advances rng by reference, same one-call-per-draw discipline the
  // rest of this file already uses (rng = xorshift32(rng); ...), just
  // packaged so the adversarial loop below isn't three lines of biasing
  // logic per field. ----
  function automatic logic [7:0] biased_byte(ref logic [31:0] rng);
    logic [31:0] r1, r2;
    begin
      rng = xorshift32(rng); r1 = rng;
      if (r1[3:0] < 4'd2) begin // ~1/8 chance
        rng = xorshift32(rng); r2 = rng;
        case (r2[1:0])
          2'd0: biased_byte = 8'h00;
          2'd1: biased_byte = 8'hFF;
          2'd2: biased_byte = 8'h80;
          default: biased_byte = 8'h7F;
        endcase
      end else begin
        biased_byte = r1[15:8]; // reuse this draw's other bits rather than a second xorshift call
      end
    end
  endfunction

  function automatic logic [31:0] biased_word32(ref logic [31:0] rng);
    logic [31:0] r1, r2;
    begin
      rng = xorshift32(rng); r1 = rng;
      if (r1[3:0] < 4'd2) begin // ~1/8 chance
        rng = xorshift32(rng); r2 = rng;
        case (r2[1:0])
          2'd0: biased_word32 = 32'h0000_0000;
          2'd1: biased_word32 = 32'hFFFF_FFFF;
          2'd2: biased_word32 = 32'h8000_0000;
          default: biased_word32 = 32'h7FFF_FFFF;
        endcase
      end else begin
        biased_word32 = r1;
      end
    end
  endfunction

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

    // ==== Task 013 Part A: exhaustive operand sweep. psum_in held at 0
    // throughout -- varying it too would needlessly triple an already-
    // large (131,072-combination) space; that's what the accumulator
    // sweep below is for. ====
    begin : exhaustive_sweep
      int w, a;
      int sweep_checks, sweep_errors;
      logic [31:0] exp_val;

      mode_unsigned = 1'b0;
      sweep_checks = 0;
      sweep_errors = 0;
      for (w = 0; w < 256; w = w + 1) begin
        load_weight(w[7:0]);
        for (a = 0; a < 256; a = a + 1) begin
          act_in  = a[7:0];
          psum_in = 32'd0;
          step();
          exp_val = expected_mac(w[7:0], a[7:0], 32'd0, 1'b0);
          sweep_checks = sweep_checks + 1;
          if (psum_out !== exp_val) begin
            sweep_errors = sweep_errors + 1;
            errors = errors + 1;
            $display("FAIL exhaustive-signed: w=%0d a=%0d got=%0d expected=%0d", w, a, psum_out, exp_val);
          end
        end
      end
      $display("exhaustive signed sweep: %0d checks, %0d failures (256x256)", sweep_checks, sweep_errors);

      mode_unsigned = 1'b1;
      sweep_checks = 0;
      sweep_errors = 0;
      for (w = 0; w < 256; w = w + 1) begin
        load_weight(w[7:0]);
        for (a = 0; a < 256; a = a + 1) begin
          act_in  = a[7:0];
          psum_in = 32'd0;
          step();
          exp_val = expected_mac(w[7:0], a[7:0], 32'd0, 1'b1);
          sweep_checks = sweep_checks + 1;
          if (psum_out !== exp_val) begin
            sweep_errors = sweep_errors + 1;
            errors = errors + 1;
            $display("FAIL exhaustive-unsigned: w=%0d a=%0d got=%0d expected=%0d", w, a, psum_out, exp_val);
          end
        end
      end
      $display("exhaustive unsigned sweep: %0d checks, %0d failures (256x256)", sweep_checks, sweep_errors);
      mode_unsigned = 1'b0;
    end

    // ==== Task 013 Part A: accumulator sweep -- randomized psum_in
    // across its full 32-bit range, covering the addition path with
    // non-trivial carry-in (>=200 iterations required; 256 used). ====
    begin : accum_sweep
      logic [31:0] rng;
      int idx;
      logic [7:0]  aw, aa;
      logic [31:0] apsum, exp_val;
      bit          amode;
      int accum_checks, accum_errors;

      rng = 32'h5eed000d;
      $display("PE accumulator-sweep seed = 32'h%08h", rng);
      accum_checks = 0;
      accum_errors = 0;

      for (idx = 0; idx < 256; idx = idx + 1) begin
        rng = xorshift32(rng); aw    = rng[7:0];
        rng = xorshift32(rng); aa    = rng[7:0];
        rng = xorshift32(rng); apsum = rng;
        rng = xorshift32(rng); amode = rng[0];

        mode_unsigned = amode;
        load_weight(aw);
        act_in  = aa;
        psum_in = apsum;
        step();
        exp_val = expected_mac(aw, aa, apsum, amode);
        accum_checks = accum_checks + 1;
        if (psum_out !== exp_val) begin
          accum_errors = accum_errors + 1;
          errors = errors + 1;
          $display("FAIL accum-sweep[%0d]: w=%0d a=%0d psum_in=%0d mode_uns=%0b got=%0d expected=%0d",
                    idx, aw, aa, apsum, amode, psum_out, exp_val);
        end
      end
      $display("PE accumulator sweep: %0d checks, %0d failures", accum_checks, accum_errors);
      mode_unsigned = 1'b0;
    end

    // ==== Task 013 Part A: randomized weight-load timing -- extends the
    // directed "weight-load-while-computing" case (vector 4 above) with
    // a random cycle offset for when a fresh weight_load pulse lands
    // relative to an ongoing sequence of accumulate cycles. Confirms the
    // same-cycle-non-effect property holds under random placement, not
    // just the one fixed placement vector 4 covers (>=50 iterations
    // required; 50 used). ====
    begin : rand_weight_timing
      logic [31:0] rng;
      int iter, s, total_len, pulse_pos;
      logic [7:0]  w_old, w_new, act_val;
      bit          tmode;
      logic [31:0] psum_acc, exp_val;
      logic [7:0]  eff_w;
      int timing_checks, timing_errors;

      rng = 32'h5eed000e;
      $display("PE weight-load-timing seed = 32'h%08h", rng);
      timing_checks = 0;
      timing_errors = 0;

      for (iter = 0; iter < 50; iter = iter + 1) begin
        rng = xorshift32(rng); total_len = 3 + (rng % 5);  // 3..7 cycles
        rng = xorshift32(rng); pulse_pos = rng % total_len; // 0..total_len-1
        rng = xorshift32(rng); w_old = rng[7:0];
        rng = xorshift32(rng); w_new = rng[7:0];
        rng = xorshift32(rng); tmode = rng[0];

        mode_unsigned = tmode;
        load_weight(w_old);
        psum_acc = 32'd0;

        for (s = 0; s < total_len; s = s + 1) begin
          rng = xorshift32(rng);
          act_val = rng[7:0];
          // Guard against a drawn act_val of exactly 0 on the pulse
          // cycle: old_weight*0 == new_weight*0 == 0, which would make
          // this specific check unable to distinguish "correctly used
          // old weight" from "incorrectly used new weight" -- force a
          // nonzero activation only on that one cycle so the property
          // is always actually exercised, not accidentally masked.
          if (s == pulse_pos && act_val == 8'h00)
            act_val = 8'h01;

          if (s == pulse_pos) begin
            weight_load = 1;
            weight_in   = w_new;
          end

          eff_w   = (s <= pulse_pos) ? w_old : w_new; // same-cycle load doesn't affect this cycle's product
          act_in  = act_val;
          psum_in = psum_acc;
          exp_val = expected_mac(eff_w, act_val, psum_acc, tmode);
          step();

          timing_checks = timing_checks + 1;
          if (psum_out !== exp_val) begin
            timing_errors = timing_errors + 1;
            errors = errors + 1;
            $display("FAIL weight-timing[iter=%0d,s=%0d,pulse_pos=%0d]: eff_w=%0d act=%0d psum_in=%0d got=%0d expected=%0d",
                      iter, s, pulse_pos, eff_w, act_val, psum_acc, psum_out, exp_val);
          end
          psum_acc = exp_val; // chain forward from our own tracked value, not the DUT's, so one mismatch doesn't cascade

          if (s == pulse_pos)
            weight_load = 0;
        end
      end
      $display("PE randomized weight-load timing: 50 iterations, %0d cycle-checks, %0d failures", timing_checks, timing_errors);
      mode_unsigned = 1'b0;
    end

    // ==== Task 019: directed boundary cases the adversarial random
    // sequences below might not reliably hit on their own. ====

    // ---- Vector 21: weight_load asserted on the very first cycle
    // after reset. ----
    vec_num = 21;
    rst_n = 0; array_en = 0; weight_load = 0; mode_unsigned = 0;
    weight_in = 8'h00; act_in = 8'h00; psum_in = 32'd0;
    step();
    step();
    rst_n    = 1;
    array_en = 1;
    weight_load = 1;
    weight_in   = 8'hA5;
    act_in      = 8'h00;
    psum_in     = 32'd0;
    step(); // first cycle after reset, weight_load asserted immediately
    weight_load = 0;
    check_weight_reg(8'hA5, "weight_load asserted on the very first post-reset cycle latches correctly");
    act_in  = 8'h02;
    psum_in = 32'd0;
    step();
    check_psum(expected_mac(8'hA5, 8'h02, 32'd0, 1'b0), "product uses the weight latched on the very first post-reset cycle");
    pass_report("weight_load on the very first cycle after reset");

    // ---- Vector 22: weight_load=1 while array_en=0, simultaneously --
    // confirm nothing latches (matches unpu_pe.sv's own documented
    // behavior: "array_en == 0: every register holds, including
    // weight_reg even if weight_load happens to be asserted"). ----
    vec_num = 22;
    load_weight(8'h11);
    begin : vec22_scope
      logic [7:0]  pre_act;
      logic [31:0] pre_psum;
      pre_act  = act_out;
      pre_psum = psum_out;
      array_en    = 0;
      weight_load = 1;
      weight_in   = 8'h99;
      act_in      = 8'hFF;
      psum_in     = 32'hDEAD_BEEF;
      step();
      weight_load = 0;
      array_en    = 1;
      check_weight_reg(8'h11, "weight_load while array_en=0 does not latch weight_reg");
      check_act(pre_act, "act_out also frozen (unaffected) while array_en=0 despite weight_load");
      check_psum(pre_psum, "psum_out also frozen (unaffected) while array_en=0 despite weight_load");
    end
    pass_report("weight_load simultaneous with array_en=0 latches nothing");

    // ---- Vector 23: rst_n deasserted for one cycle in the MIDDLE of an
    // otherwise-normal sequence -- confirm every register clears
    // immediately and the sequence resumes correctly afterward. ----
    vec_num = 23;
    load_weight(8'h07);
    act_in  = 8'h03;
    psum_in = 32'd50;
    step(); // normal operation: 50 + 3*7 = 71
    check_psum(32'd71, "pre-mid-sequence-reset baseline");
    rst_n = 0;
    step();
    check_act(8'h00, "act_out clears immediately on mid-sequence reset");
    check_psum(32'd0, "psum_out clears immediately on mid-sequence reset");
    check_weight_reg(8'h00, "weight_reg clears immediately on mid-sequence reset");
    rst_n = 1;
    act_in  = 8'h05;
    psum_in = 32'd0;
    step(); // weight_reg cleared, product is 0: 0 + 5*0 = 0
    check_psum(32'd0, "resumes correctly post-reset: cleared weight_reg gives zero product");
    load_weight(8'h04);
    act_in  = 8'h06;
    psum_in = 32'd0;
    step(); // 0 + 6*4 = 24
    check_psum(32'd24, "normal operation fully restored after the mid-sequence reset");
    pass_report("mid-sequence single-cycle reset clears and resumes correctly");

    // ---- Vector 24: weight_load held high for >=5 consecutive cycles
    // with a distinct weight_in each cycle, array_en=1 throughout --
    // confirm weight_reg updates every one of those cycles, not just the
    // first (task 013's 50-iteration sweep only exercised single
    // pulses). ----
    vec_num = 24;
    array_en    = 1;
    weight_load = 1;
    weight_in = 8'h01; act_in = 8'h00; psum_in = 32'd0;
    step();
    check_weight_reg(8'h01, "consecutive weight_load hold, cycle 1 of >=5");
    weight_in = 8'h02;
    step();
    check_weight_reg(8'h02, "consecutive weight_load hold, cycle 2 of >=5");
    weight_in = 8'h03;
    step();
    check_weight_reg(8'h03, "consecutive weight_load hold, cycle 3 of >=5");
    weight_in = 8'h04;
    step();
    check_weight_reg(8'h04, "consecutive weight_load hold, cycle 4 of >=5");
    weight_in = 8'h05;
    step();
    check_weight_reg(8'h05, "consecutive weight_load hold, cycle 5 of >=5");
    weight_load = 0;
    weight_in = 8'hFF; // should now be ignored
    act_in  = 8'h02;
    psum_in = 32'd0;
    step();
    check_weight_reg(8'h05, "weight_reg holds the final consecutive-load value once weight_load deasserts");
    check_psum(32'd10, "product uses the held final weight (5) once loading stops: 2*5=10");
    pass_report("weight_load held >=5 consecutive cycles, distinct weight_in each cycle, updates every cycle");

    $display("----------------------------------------");
    if (errors == 0)
      $display("ALL TASK 019 DIRECTED BOUNDARY CASES PASSED (vectors 21-24)");
    else
      $display("%0d TOTAL FAILURE(S) ACROSS ALL PE CHECKS SO FAR", errors);
    $display("----------------------------------------");

    // ==== Task 019: adversarial long-sequence test -- the core of this
    // task. Independent, cycle-accurate reference model (shadow state:
    // sh_weight_reg/sh_act_out/sh_psum_out, all reset to 0), derived
    // from unpu_pe.sv's own documented header/comment behavior, not
    // transcribed from its code -- expected_mac() above already carries
    // that same independent-derivation discipline forward from task 013
    // (arithmetic sign extension, not a $signed() cast mirroring the
    // RTL's own operator back at itself); this block adds the
    // surrounding sequential control (array_en freeze, weight_reg
    // latch-on-load, registered act_out pass-through) fresh, since that
    // part of the model is new here. Not re-proving task 013's
    // operand-space coverage (131,072 combinations already exhaustive,
    // nothing left to sample) -- this is about long, adversarial,
    // multi-cycle sequences where many interacting decisions (freeze,
    // reload, mode-switch, extreme values) compound over hundreds of
    // cycles, which an isolated single-cycle check structurally can't
    // reach. If this finds a real divergence: stop, report the seed +
    // cycle + full signal state, do not tune the bias to avoid it and do
    // not patch rtl/unpu_pe.sv here -- that's this task's actual job,
    // not a problem with the task. ====
    begin : adversarial_break_test
      localparam int NUM_SEQ = 20;

      logic [31:0] master_rng, rng, seq_seed;
      int seq_idx, seq_len, cyc;

      logic [7:0]  sh_weight_reg, sh_act_out, next_sh_weight_reg, next_sh_act_out;
      logic [31:0] sh_psum_out, next_sh_psum_out;

      bit          d_array_en, d_weight_load, d_mode_unsigned;
      logic [7:0]  d_weight_in, d_act_in;
      logic [31:0] d_psum_in;

      int freeze_remaining, wload_remaining;
      bit just_ended_freeze, force_freeze_now;

      longint total_cyc_checks, total_sig_checks;
      int     total_seq_errors;

      master_rng = 32'h5eed0013; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("PE adversarial long-sequence master seed = 32'h%08h", master_rng);
      total_cyc_checks = 0;
      total_sig_checks = 0;
      total_seq_errors = 0;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_seed   = master_rng;
        rng        = seq_seed;
        $display("PE adversarial sequence %0d: seed = 32'h%08h", seq_idx, seq_seed);

        rng = xorshift32(rng);
        seq_len = 500 + (rng % 201); // 500..700 cycles -- reproducible from the printed seed alone

        // ---- Reset DUT and shadow model together. ----
        rst_n = 0; array_en = 0; weight_load = 0; mode_unsigned = 0;
        weight_in = 8'h00; act_in = 8'h00; psum_in = 32'd0;
        step();
        step();
        rst_n = 1;
        step();
        sh_weight_reg = 8'h00;
        sh_act_out    = 8'h00;
        sh_psum_out   = 32'd0;

        freeze_remaining  = 0;
        wload_remaining   = 0;
        just_ended_freeze = 1'b0;
        force_freeze_now  = 1'b0;

        for (cyc = 0; cyc < seq_len; cyc = cyc + 1) begin
          // ---- array_en: freeze bursts (1-20 cycles typical, up to
          // ~50 occasionally), including deliberate back-to-back
          // freezes separated by only a 1-cycle gap. ----
          if (freeze_remaining > 0) begin
            d_array_en = 1'b0;
            freeze_remaining = freeze_remaining - 1;
            if (freeze_remaining == 0)
              just_ended_freeze = 1'b1;
          end else if (force_freeze_now) begin
            force_freeze_now = 1'b0;
            d_array_en = 1'b0;
            rng = xorshift32(rng);
            freeze_remaining = rng % 15; // this cycle + 0..14 more = 1..15 total
          end else begin
            d_array_en = 1'b1;
            if (just_ended_freeze) begin
              just_ended_freeze = 1'b0;
              rng = xorshift32(rng);
              if (rng[1:0] == 2'd0) // ~25% of the time: re-freeze right after this exact 1-cycle gap
                force_freeze_now = 1'b1;
            end else begin
              rng = xorshift32(rng);
              if (rng[4:0] == 5'h0) begin // ~1/32 chance to start a fresh freeze burst
                d_array_en = 1'b0;
                rng = xorshift32(rng);
                if (rng[4:0] == 5'h0) begin // occasionally a long freeze
                  rng = xorshift32(rng);
                  freeze_remaining = 29 + (rng % 21); // this cycle + 29..49 more = 30..50 total
                end else begin
                  rng = xorshift32(rng);
                  freeze_remaining = rng % 20; // this cycle + 0..19 more = 1..20 total
                end
              end
            end
          end

          // ---- weight_load: random pulses, biased toward multi-cycle
          // holds with a different weight_in each held cycle. ----
          if (wload_remaining > 0) begin
            d_weight_load = 1'b1;
            d_weight_in   = biased_byte(rng);
            wload_remaining = wload_remaining - 1;
          end else begin
            rng = xorshift32(rng);
            if (rng[3:0] < 4'd3) begin // ~3/16 chance to start a load event
              d_weight_load = 1'b1;
              d_weight_in   = biased_byte(rng);
              rng = xorshift32(rng);
              if (rng[1:0] == 2'd0) begin // ~1/4 of load-starts become a multi-cycle hold
                rng = xorshift32(rng);
                wload_remaining = 1 + (rng % 5); // 1..5 MORE held cycles (2..6 total incl. this one)
              end
            end else begin
              d_weight_load = 1'b0;
              d_weight_in   = biased_byte(rng); // driven but ignored -- realistic bus noise
            end
          end

          // ---- act_in / psum_in: full-range, biased toward extremes. ----
          d_act_in  = biased_byte(rng);
          d_psum_in = biased_word32(rng);

          // ---- mode_unsigned: random toggle every cycle. ----
          rng = xorshift32(rng);
          d_mode_unsigned = rng[0];

          // ---- Drive the DUT. ----
          array_en      = d_array_en;
          weight_load   = d_weight_load;
          weight_in     = d_weight_in;
          act_in        = d_act_in;
          psum_in       = d_psum_in;
          mode_unsigned = d_mode_unsigned;

          // ---- Advance the reference model, using sh_weight_reg's
          // PRE-update value for this cycle's product -- a same-cycle
          // weight_load must not affect this cycle's product. ----
          if (d_array_en) begin
            next_sh_psum_out   = expected_mac(sh_weight_reg, d_act_in, d_psum_in, d_mode_unsigned);
            next_sh_act_out    = d_act_in;
            next_sh_weight_reg = d_weight_load ? d_weight_in : sh_weight_reg;
          end else begin
            next_sh_psum_out   = sh_psum_out;
            next_sh_act_out    = sh_act_out;
            next_sh_weight_reg = sh_weight_reg;
          end

          step();

          sh_psum_out   = next_sh_psum_out;
          sh_act_out    = next_sh_act_out;
          sh_weight_reg = next_sh_weight_reg;

          total_cyc_checks = total_cyc_checks + 1;
          if (act_out !== sh_act_out) begin
            total_seq_errors = total_seq_errors + 1;
            errors = errors + 1;
            $display("FAIL adversarial[seq=%0d seed=32'h%08h cyc=%0d]: act_out got=%0h expected=%0h (array_en=%0b weight_load=%0b weight_in=%0h act_in=%0h psum_in=%0h mode_unsigned=%0b)",
                      seq_idx, seq_seed, cyc, act_out, sh_act_out, d_array_en, d_weight_load, d_weight_in, d_act_in, d_psum_in, d_mode_unsigned);
          end
          total_sig_checks = total_sig_checks + 1;

          if (psum_out !== sh_psum_out) begin
            total_seq_errors = total_seq_errors + 1;
            errors = errors + 1;
            $display("FAIL adversarial[seq=%0d seed=32'h%08h cyc=%0d]: psum_out got=%0d expected=%0d (array_en=%0b weight_load=%0b weight_in=%0h act_in=%0h psum_in=%0h mode_unsigned=%0b)",
                      seq_idx, seq_seed, cyc, psum_out, sh_psum_out, d_array_en, d_weight_load, d_weight_in, d_act_in, d_psum_in, d_mode_unsigned);
          end
          total_sig_checks = total_sig_checks + 1;

          if (dut.weight_reg !== sh_weight_reg) begin
            total_seq_errors = total_seq_errors + 1;
            errors = errors + 1;
            $display("FAIL adversarial[seq=%0d seed=32'h%08h cyc=%0d]: weight_reg (hierarchical) got=%0h expected=%0h (array_en=%0b weight_load=%0b weight_in=%0h act_in=%0h psum_in=%0h mode_unsigned=%0b)",
                      seq_idx, seq_seed, cyc, dut.weight_reg, sh_weight_reg, d_array_en, d_weight_load, d_weight_in, d_act_in, d_psum_in, d_mode_unsigned);
          end
          total_sig_checks = total_sig_checks + 1;
        end
      end

      $display("PE adversarial long-sequence testing: %0d sequences, %0d total cycle-checks, %0d individual signal-checks, %0d failures",
                NUM_SEQ, total_cyc_checks, total_sig_checks, total_seq_errors);
    end

    $display("----------------------------------------");
    if (errors == 0)
      $display("ALL TASK 013 + TASK 019 PE CHECKS PASSED (20 directed vectors + exhaustive operand sweep + accumulator sweep + randomized weight-load timing + 4 task-019 directed boundary vectors + adversarial long-sequence testing)");
    else
      $display("%0d TOTAL FAILURE(S) ACROSS ALL PE CHECKS", errors);
    $display("----------------------------------------");

    $finish;
  end

endmodule
