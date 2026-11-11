// End-to-end skew -> grid -> de-skew timing-contract test for the uNPU
// 4x4 array. Unlike tb/unpu_grid_tb.sv (task 003), this testbench performs
// NO hand-skewing: it drives raw, un-skewed A[m][0..3] into unpu_skew and
// checks unpu_deskew's realigned output, proving the timing contract
// (CLAUDE.md) holds through the real skew/de-skew RTL, not testbench
// arithmetic standing in for it.
//
// Weights are still forced directly per-PE on unpu_grid (shift-down
// weight loading is unpu_wbuf, step 9, out of scope here) -- same
// unrolled-forcing style as tb/unpu_grid_tb.sv, for the same simulator-
// portability reason (Icarus rejects a non-constant [r][c] index pair as
// an lvalue into a 3-level packed array).
//
// Test vectors come from the golden model (model/golden.c, task 002/004):
// model/vectors/cross_terms_{a,w,c}.hex + cross_terms_meta.txt. Run
// `model/golden` from the repo root before this testbench to (re)generate
// them -- this tb does not regenerate them itself.
//
// Simulated with Icarus Verilog (iverilog/vvp) -- Xcelium not available in
// this environment, same as unpu_pe_tb.sv/unpu_grid_tb.sv.
//
// Task 013 (verification-debt retrofit) added the 64-case crv_* sweep
// below, closing plan.md's "one directed non-identity case... no
// randomized matrices or randomized M" gap; simulated with Verilator for
// that addition -- see tb/unpu_pe_tb.sv's header for why the Icarus line
// above is stale.
`timescale 1ns/1ps

module unpu_skew_tb;

  logic clk;
  logic rst_n;
  logic array_en;
  logic mode_unsigned;

  // unpu_skew <-> unpu_grid
  logic [3:0][7:0] a_raw;
  logic [3:0][7:0] skew_act_out;

  // unpu_grid itself
  logic [3:0][3:0]      weight_load;
  logic [3:0][3:0][7:0] weight_in;
  logic [3:0][31:0]     grid_psum_in;   // north edge, unused: tied 0 for the whole run
  logic [3:0][7:0]      grid_act_out;   // east edge, unused by this tb
  logic [3:0][31:0]     grid_psum_out;

  // unpu_grid -> unpu_deskew
  logic [3:0][31:0] c_out;

  int errors;
  int checks;

  unpu_skew u_skew (
    .clk      (clk),
    .rst_n    (rst_n),
    .array_en (array_en),
    .a_raw    (a_raw),
    .act_out  (skew_act_out)
  );

  unpu_grid u_grid (
    .clk           (clk),
    .rst_n         (rst_n),
    .array_en      (array_en),
    .mode_unsigned (mode_unsigned),
    .weight_load   (weight_load),
    .weight_in     (weight_in),
    .act_in        (skew_act_out),
    .psum_in       (grid_psum_in),
    .act_out       (grid_act_out),
    .psum_out      (grid_psum_out)
  );

  unpu_deskew u_deskew (
    .clk      (clk),
    .rst_n    (rst_n),
    .array_en (array_en),
    .psum_in  (grid_psum_out),
    .c_out    (c_out)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1; // allow NBAs to settle before checking
  endtask

  // Case storage, M<=4 (matches cross_terms and every other current case).
  logic [7:0]  A_case [0:3][0:3];
  logic [7:0]  W_case [0:3][0:3];
  logic [31:0] C_case [0:3][0:3];

  int m, j, cyc, cyc_max;
  int case_M;
  int fd, scan_rc;
  string mode_str;

  task automatic run_case(input string name);
    string path;
    begin
      // ---- Load meta (M, MODE); $fatal on setup errors, same rationale
      // as tb/unpu_grid_tb.sv's header comment (Verilator --timing
      // coroutine mode drops writes made inside a conditionally-skipped
      // branch containing an @(posedge); Icarus has no such issue, but
      // $fatal is the right response to a missing vector file regardless).
      path = {"model/vectors/", name, "_meta.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        $fatal(1, "could not open %s -- run model/golden first", path);

      scan_rc = $fscanf(fd, "M=%d\nMODE=%s\n", case_M, mode_str);
      $fclose(fd);
      if (scan_rc != 2)
        $fatal(1, "could not parse %s (got %0d fields)", path, scan_rc);

      if (case_M > 4)
        $fatal(1, "case '%s' has M=%0d, this tb only handles M<=4", name, case_M);

      mode_unsigned = (mode_str == "UNSIGNED") ? 1'b1 : 1'b0;

      $readmemh({"model/vectors/", name, "_a.hex"}, A_case);
      $readmemh({"model/vectors/", name, "_w.hex"}, W_case);
      $readmemh({"model/vectors/", name, "_c.hex"}, C_case);

      $display("---- case '%s': M=%0d MODE=%s ----", name, case_M, mode_str);

      // ---- Reset ----
      rst_n        = 0;
      array_en     = 0;
      weight_load  = '0;
      weight_in    = '0;
      a_raw        = '0;
      grid_psum_in = '0;
      step();
      step();
      rst_n = 1;
      step();

      // ---- Preload weights, direct per-PE forcing (unrolled -- see
      // header comment). a_raw held at 0 so no stray data enters the skew
      // pipeline during this step. ----
      array_en = 1;
      weight_in[0][0] = W_case[0][0]; weight_in[0][1] = W_case[0][1]; weight_in[0][2] = W_case[0][2]; weight_in[0][3] = W_case[0][3];
      weight_in[1][0] = W_case[1][0]; weight_in[1][1] = W_case[1][1]; weight_in[1][2] = W_case[1][2]; weight_in[1][3] = W_case[1][3];
      weight_in[2][0] = W_case[2][0]; weight_in[2][1] = W_case[2][1]; weight_in[2][2] = W_case[2][2]; weight_in[2][3] = W_case[2][3];
      weight_in[3][0] = W_case[3][0]; weight_in[3][1] = W_case[3][1]; weight_in[3][2] = W_case[3][2]; weight_in[3][3] = W_case[3][3];
      weight_load = '1; // pulse all 16 PEs simultaneously
      a_raw = '0;
      step();
      weight_load = '0;

      // ---- Compute pass. Loop index 'cyc' counts edges from this point
      // (cyc=0 is the edge fired by the FIRST step() call below).
      //
      // Drive: a_raw = A[m][0..3] (all 4 lanes at once, RAW/un-skewed) at
      // iteration cyc == m. unpu_skew alone is responsible for making
      // row k's value arrive at unpu_grid's act_in[k] on iteration m+k --
      // this tb does no hand-skewing (contract line 1).
      //
      // Check: c_out[j] is checked against C[m][j] once it has propagated
      // through the full chain. Derivation (register "visible during
      // iteration X" convention, X = the iteration after the edge that
      // last updated the register -- matching tb/unpu_grid_tb.sv's own
      // read-right-after-step() convention):
      //   unpu_grid reproduces tb/unpu_grid_tb.sv's proven result exactly,
      //   edge-for-edge on this same 'cyc' index (unpu_skew's act_out[k]
      //   at iteration cyc equals A[cyc-k][k], identical to that tb's
      //   hand-skewed act_in[k]): grid_psum_out[j] visible during
      //   iteration m+j+4 (contract line 3).
      //   unpu_deskew delays column j by (3-j) stages: output visible
      //   (3-j) iterations later, i.e. at (m+j+4)+(3-j) = m+7 -- for
      //   every j alike (contract line 4).
      //   "Visible during iteration X" is read right after step() at
      //   cyc == X-1, so the check below fires at cyc == m+6, not m+7.
      cyc_max = (case_M - 1) + 6 + 2; // margin past last readout
      for (cyc = 0; cyc <= cyc_max; cyc = cyc + 1) begin
        m = cyc;
        if (m >= 0 && m < case_M) begin
          a_raw[0] = A_case[m][0];
          a_raw[1] = A_case[m][1];
          a_raw[2] = A_case[m][2];
          a_raw[3] = A_case[m][3];
        end else begin
          a_raw = '0;
        end

        step(); // this edge completes cycle 'cyc'

        m = cyc - 6;
        if (m >= 0 && m < case_M) begin
          for (j = 0; j < 4; j = j + 1) begin
            checks = checks + 1;
            if (c_out[j] !== C_case[m][j]) begin
              $display("FAIL [%s]: cycle=%0d c_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        name, cyc, j, m, j, C_case[m][j], c_out[j]);
              errors = errors + 1;
            end else begin
              $display("PASS [%s]: cycle=%0d c_out[%0d] (C[%0d][%0d]) = %0d",
                        name, cyc, j, m, j, c_out[j]);
            end
          end
        end
      end
    end
  endtask

  // ==== Task 021: independent reference model + shared pass-runner for
  // Part A (extreme/structural directed cases) and Part B (adversarial
  // multi-pass sequences), through the full unpu_skew -> unpu_grid ->
  // unpu_deskew chain. Same discipline task 020 already established for
  // the grid-only version: ref_c_elem is a stateless, recomputed-each-
  // call nested dot product derived from the timing contract's matmul
  // shape, not from any module's own per-cycle propagation code --
  // campaign-wide caution from task 019 (whose first-draft PE reference
  // model accumulated from its own prior state instead of each cycle's
  // driven input). The "sanity_walking_one" block further down is the
  // explicit hand-verifiable sanity check for this model, now through
  // the full chain (skew/de-skew's own pipeline depths included, unlike
  // task 020's grid-only version) -- required per the campaign-wide
  // caution to verify before trusting Part B's larger run.
  function automatic int signed to_signed8(input logic [7:0] v);
    if (v[7])
      return int'(v) - 256;
    else
      return int'(v);
  endfunction

  function automatic logic [31:0] ref_c_elem(input logic [7:0] Wm [0:3][0:3], input logic [7:0] Am [0:3][0:3],
                                              input int mrow, input int jcol, input bit mode_uns);
    int kk;
    int unsigned acc_u, uw, ua;
    int signed   acc_s, sw, sa;
    begin
      if (mode_uns) begin
        acc_u = 0;
        for (kk = 0; kk < 4; kk = kk + 1) begin
          uw = {24'd0, Wm[kk][jcol]};
          ua = {24'd0, Am[mrow][kk]};
          acc_u = acc_u + uw * ua;
        end
        ref_c_elem = acc_u;
      end else begin
        acc_s = 0;
        for (kk = 0; kk < 4; kk = kk + 1) begin
          sw = to_signed8(Wm[kk][jcol]);
          sa = to_signed8(Am[mrow][kk]);
          acc_s = acc_s + sw * sa;
        end
        ref_c_elem = acc_s;
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

  // ~1/8 chance of a boundary extreme, same discipline tasks 019/020
  // used -- biases toward the values most likely to expose a wiring/
  // width bug instead of trusting uniform random to find them by chance.
  function automatic logic [7:0] biased_byte(ref logic [31:0] rng);
    logic [31:0] r1, r2;
    begin
      rng = xorshift32(rng); r1 = rng;
      if (r1[3:0] < 4'd2) begin
        rng = xorshift32(rng); r2 = rng;
        case (r2[1:0])
          2'd0: biased_byte = 8'h00;
          2'd1: biased_byte = 8'hFF;
          2'd2: biased_byte = 8'h80;
          default: biased_byte = 8'h7F;
        endcase
      end else begin
        biased_byte = r1[15:8];
      end
    end
  endfunction

  // ~1/2 chance of a boundary extreme -- heavier bias than biased_byte,
  // used only for Part A's dedicated M=1/M=4 "with extreme data" cases,
  // to make them stand out distinctly from Part B's general ~1/8 bias.
  function automatic logic [7:0] heavy_extreme_byte(ref logic [31:0] rng);
    logic [31:0] r1, r2;
    begin
      rng = xorshift32(rng); r1 = rng;
      if (r1[0] == 1'b0) begin
        rng = xorshift32(rng); r2 = rng;
        case (r2[1:0])
          2'd0: heavy_extreme_byte = 8'h00;
          2'd1: heavy_extreme_byte = 8'hFF;
          2'd2: heavy_extreme_byte = 8'h80;
          default: heavy_extreme_byte = 8'h7F;
        endcase
      end else begin
        heavy_extreme_byte = r1[15:8];
      end
    end
  endfunction

  task automatic reset_dut;
    begin
      rst_n        = 0;
      array_en     = 0;
      weight_load  = '0;
      weight_in    = '0;
      a_raw        = '0;
      grid_psum_in = '0;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  // Preloads weights from the module-level W_case, then runs one full
  // pass over the module-level A_case/case_M/mode_unsigned through the
  // real skew->grid->deskew chain, checking c_out against ref_c_elem (not
  // any preloaded C_case file) at the freeze-adjusted active_cyc --
  // task 005's bookkeeping convention, reused directly from
  // tb/unpu_stall_tb.sv's own run_case() (same chain, already proven
  // correct there), not reinvented. Does NOT reset the DUT -- callers
  // running a single isolated pass call reset_dut() first; Part B's
  // back-to-back sequences call reset_dut() once per sequence and then
  // this task repeatedly, deliberately with no reset and no idle gap
  // between passes, and with case_M allowed to differ pass to pass.
  task automatic run_pass(input string label, input bit do_freeze, input int freeze_at_active_cyc,
                           input int freeze_len, output int errs_this_pass);
    int active_cyc, active_cyc_max, m_drv, m, j, s;
    logic [31:0] exp_val;
    logic [3:0][31:0] pre_cout;
    begin
      errs_this_pass = 0;

      // ---- Preload weights, direct per-PE forcing (unrolled, same
      // simulator-portability convention as run_case() above). ----
      array_en = 1;
      weight_in[0][0] = W_case[0][0]; weight_in[0][1] = W_case[0][1]; weight_in[0][2] = W_case[0][2]; weight_in[0][3] = W_case[0][3];
      weight_in[1][0] = W_case[1][0]; weight_in[1][1] = W_case[1][1]; weight_in[1][2] = W_case[1][2]; weight_in[1][3] = W_case[1][3];
      weight_in[2][0] = W_case[2][0]; weight_in[2][1] = W_case[2][1]; weight_in[2][2] = W_case[2][2]; weight_in[2][3] = W_case[2][3];
      weight_in[3][0] = W_case[3][0]; weight_in[3][1] = W_case[3][1]; weight_in[3][2] = W_case[3][2]; weight_in[3][3] = W_case[3][3];
      weight_load = '1;
      a_raw = '0;
      step();
      weight_load = '0;

      // ---- Compute pass, indexed by active_cyc (task 005 convention,
      // identical to tb/unpu_stall_tb.sv's own run_case()): m_drv holds
      // the last row once active_cyc >= case_M (drain phase, unchecked
      // either way); c_out[j] visible at active_cyc == m+7 for every j
      // alike (contract line 4, full chain includes de-skew's
      // realignment). ----
      active_cyc     = 0;
      active_cyc_max = (case_M - 1) + 7 + 2; // margin past last readout, same as unpu_stall_tb.sv

      while (active_cyc <= active_cyc_max) begin
        m_drv = (active_cyc < case_M) ? active_cyc : (case_M - 1);
        a_raw[0] = A_case[m_drv][0];
        a_raw[1] = A_case[m_drv][1];
        a_raw[2] = A_case[m_drv][2];
        a_raw[3] = A_case[m_drv][3];

        if (do_freeze && freeze_len > 0 && active_cyc == freeze_at_active_cyc) begin
          pre_cout = c_out;
          for (s = 0; s < freeze_len; s = s + 1) begin
            array_en = 0;
            a_raw    = {4{8'hA5}}; // don't-care garbage; DUT must ignore it while frozen
            step();   // frozen edge -- active_cyc does NOT advance
            for (j = 0; j < 4; j = j + 1) begin
              checks = checks + 1;
              if (c_out[j] !== pre_cout[j]) begin
                errs_this_pass = errs_this_pass + 1;
                errors = errors + 1;
                $display("FAIL FREEZE [%s]: c_out[%0d] changed during frozen cycle %0d/%0d at active_cyc=%0d (was %0d now %0d)",
                          label, j, s + 1, freeze_len, active_cyc, pre_cout[j], c_out[j]);
              end
            end
          end
          array_en = 1;
          a_raw[0] = A_case[m_drv][0];
          a_raw[1] = A_case[m_drv][1];
          a_raw[2] = A_case[m_drv][2];
          a_raw[3] = A_case[m_drv][3];
        end

        array_en = 1;
        step(); // active edge
        active_cyc = active_cyc + 1;

        m = active_cyc - 7;
        if (m >= 0 && m < case_M) begin
          for (j = 0; j < 4; j = j + 1) begin
            exp_val = ref_c_elem(W_case, A_case, m, j, mode_unsigned);
            checks  = checks + 1;
            if (c_out[j] !== exp_val) begin
              errs_this_pass = errs_this_pass + 1;
              errors = errors + 1;
              $display("FAIL [%s]: active_cyc=%0d c_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        label, active_cyc, j, m, j, exp_val, c_out[j]);
            end
          end
        end
      end
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;

    run_case("cross_terms");

    // ==== Task 013 Part C: verification-debt retrofit -- all 64 crv_*
    // cases from task 006 Part A, through the full skew -> grid ->
    // de-skew chain this file already builds. run_case() above already
    // reads each case's real M from its own _meta.txt and derives
    // cyc_max/the checked m-range from it (not hardcoded to 4), so it
    // generalizes correctly to whatever M each crv_* case reports. This
    // closes plan.md's "one directed non-identity case... no randomized
    // matrices or randomized M" verification-debt note. ====
    begin : crv_sweep
      int ci;
      string crv_name;
      for (ci = 0; ci < 64; ci = ci + 1) begin
        crv_name = $sformatf("crv_%04d", ci);
        run_case(crv_name);
      end
    end

    $display("----------------------------------------");
    $display("checked %0d values total", checks);
    if (errors == 0)
      $display("ALL CHECKS PASSED");
    else
      $display("%0d FAILURE(S) (checks=%0d)", errors, checks);
    $display("----------------------------------------");

    // ==== Task 021, Part A: extreme/structural directed cases, through
    // the full skew->grid->deskew chain. ====
    begin : part_a
      int errs;
      int mm, kk, jj, fp, freeze_upper;

      // ---- Depth-0 wire stress -- the sharpest test this module pair
      // gets. unpu_skew row 0 and unpu_deskew column 3 are documented as
      // plain wires, never registered (execution.md's known trap). ----
      begin : depth0_wire_stress
        int cyc2, change_count;
        logic [7:0]  expected_a0;
        logic [31:0] prev_psum3;
        logic [31:0] rng_d0;

        // unpu_skew row 0: a_raw[0] alternates 0x00/0xFF every single
        // cycle; act_out[0] must track it with zero added latency --
        // deliberately toggling array_en throughout too, since row 0 is
        // an unconditional wire with no array_en gating at all (task
        // 005's own check_frozen() explicitly excludes this exact path
        // for that reason -- it isn't supposed to freeze).
        reset_dut();
        for (cyc2 = 0; cyc2 < 40; cyc2 = cyc2 + 1) begin
          expected_a0 = cyc2[0] ? 8'hFF : 8'h00;
          array_en    = cyc2[2];
          a_raw[0]    = expected_a0;
          a_raw[1] = 8'h00; a_raw[2] = 8'h00; a_raw[3] = 8'h00;
          weight_in = '0; weight_load = '0; grid_psum_in = '0;
          step();
          checks = checks + 1;
          if (skew_act_out[0] !== expected_a0) begin
            errors = errors + 1;
            $display("FAIL [depth0-skew]: cycle=%0d array_en=%0b act_out[0] exp=%0h got=%0h (a_raw[0] alternates every cycle -- zero-latency check)",
                      cyc2, array_en, expected_a0, skew_act_out[0]);
          end
        end
        array_en = 1;
        $display("Part A depth-0 check: unpu_skew row 0 tracked a_raw[0] with zero added latency across 40 cycles (array_en toggled throughout)");

        // unpu_deskew column 3: drive genuinely random-every-cycle
        // activation into all four rows (weights fixed but distinct per
        // row, so each row's contribution is distinguishable) and
        // compare c_out[3] directly against grid_psum_out[3] -- both are
        // plain testbench-visible wires already, so this needs no
        // independent reference value at all. A one-cycle registration
        // bug would show c_out[3] lagging grid_psum_out[3] by exactly
        // one cycle; a value that's genuinely different almost every
        // cycle makes that immediately visible, where a constant or
        // slow-changing value would let a buggy registered path "catch
        // up" and coincidentally match.
        reset_dut();
        weight_in[0][3] = 8'h01; weight_in[1][3] = 8'h02; weight_in[2][3] = 8'h04; weight_in[3][3] = 8'h08;
        weight_load = '1;
        a_raw = '0;
        array_en = 1;
        step();
        weight_load = '0;

        rng_d0       = 32'hBADC0FFE;
        change_count = 0;
        prev_psum3   = grid_psum_out[3];
        for (cyc2 = 0; cyc2 < 60; cyc2 = cyc2 + 1) begin
          rng_d0 = xorshift32(rng_d0); a_raw[0] = rng_d0[7:0];
          rng_d0 = xorshift32(rng_d0); a_raw[1] = rng_d0[7:0];
          rng_d0 = xorshift32(rng_d0); a_raw[2] = rng_d0[7:0];
          rng_d0 = xorshift32(rng_d0); a_raw[3] = rng_d0[7:0];
          step();
          checks = checks + 1;
          if (c_out[3] !== grid_psum_out[3]) begin
            errors = errors + 1;
            $display("FAIL [depth0-deskew]: cycle=%0d c_out[3] (%0d) != grid_psum_out[3] (%0d) -- zero-latency check",
                      cyc2, c_out[3], grid_psum_out[3]);
          end
          if (grid_psum_out[3] !== prev_psum3)
            change_count = change_count + 1;
          prev_psum3 = grid_psum_out[3];
        end
        checks = checks + 1;
        if (change_count < 50) begin
          errors = errors + 1;
          $display("FAIL [depth0-deskew]: only %0d/60 cycles saw grid_psum_out[3] actually change -- stimulus wasn't adversarial enough to trust the zero-latency check above",
                    change_count);
        end
        $display("Part A depth-0 check: unpu_deskew column 3 tracked grid_psum_out[3] with zero added latency across 60 cycles (%0d/60 cycles had a genuinely changed value)",
                  change_count);
      end

      // ---- Explicit reference-model sanity check through the FULL
      // chain (campaign-wide caution: verify before trusting Part B).
      // A single weight[kpos][jpos]=1 (rest zero) gives a trivially
      // hand-verifiable expected pattern: C[m][j] = A[m][kpos] when
      // j==jpos, else 0 -- task 020 got this for free from its 16-
      // position grid-only sweep; two positions here re-confirms it
      // holds with skew/de-skew's own pipeline depths now in the loop
      // too, without redundantly repeating that full 16-position sweep. ----
      begin : sanity_walking_one
        mode_unsigned = 1'b0;
        case_M = 4;

        for (kk = 0; kk < 4; kk = kk + 1)
          for (jj = 0; jj < 4; jj = jj + 1)
            W_case[kk][jj] = (kk == 0 && jj == 0) ? 8'h01 : 8'h00;
        for (mm = 0; mm < 4; mm = mm + 1)
          for (kk = 0; kk < 4; kk = kk + 1)
            A_case[mm][kk] = 8'(16 * mm + kk + 1);
        $display("---- Part A sanity: reference-model hand-check, weight[0][0]=1 through full chain ----");
        reset_dut();
        run_pass("sanity-walking-one[0][0]", 1'b0, 0, 0, errs);

        for (kk = 0; kk < 4; kk = kk + 1)
          for (jj = 0; jj < 4; jj = jj + 1)
            W_case[kk][jj] = (kk == 3 && jj == 3) ? 8'h01 : 8'h00;
        $display("---- Part A sanity: reference-model hand-check, weight[3][3]=1 through full chain ----");
        reset_dut();
        run_pass("sanity-walking-one[3][3]", 1'b0, 0, 0, errs);
      end

      // ---- Max-magnitude through the full chain, both modes. ----
      case_M = 4;
      for (mm = 0; mm < 4; mm = mm + 1)
        for (kk = 0; kk < 4; kk = kk + 1) begin
          A_case[mm][kk] = 8'hFF;
          W_case[mm][kk] = 8'hFF;
        end

      mode_unsigned = 1'b0;
      $display("---- Part A: max-magnitude through full chain, SIGNED ----");
      reset_dut();
      run_pass("maxmag-signed-fullchain", 1'b0, 0, 0, errs);

      mode_unsigned = 1'b1;
      $display("---- Part A: max-magnitude through full chain, UNSIGNED ----");
      reset_dut();
      run_pass("maxmag-unsigned-fullchain", 1'b0, 0, 0, errs);

      // ---- Exhaustive freeze-point sweep on cross_terms, across the
      // FULL chain's timing window this time (task 020 only covered
      // grid's own window) -- active_cyc 0 through (M-1)+7 inclusive,
      // M+7=11 sub-cases for M=4, matching CLAUDE.md's own total-cycle
      // figure exactly. Reuses run_pass()'s active_cyc convention
      // directly (task 005's, already proven on this exact chain).
      // Checked against ref_c_elem, not cross_terms_c.hex, for the same
      // independent-derivation reason as everywhere else in this task --
      // only the case's input vectors (_a.hex/_w.hex) are read from
      // disk. ----
      begin : freeze_point_sweep
        int meta_M;
        string meta_mode;
        int mfd, mrc;
        mfd = $fopen("model/vectors/cross_terms_meta.txt", "r");
        if (mfd == 0)
          $fatal(1, "could not open model/vectors/cross_terms_meta.txt -- run model/golden first");
        mrc = $fscanf(mfd, "M=%d\nMODE=%s\n", meta_M, meta_mode);
        $fclose(mfd);
        if (mrc != 2)
          $fatal(1, "could not parse model/vectors/cross_terms_meta.txt (got %0d fields)", mrc);

        $readmemh("model/vectors/cross_terms_a.hex", A_case);
        $readmemh("model/vectors/cross_terms_w.hex", W_case);
        case_M        = meta_M;
        mode_unsigned = (meta_mode == "UNSIGNED") ? 1'b1 : 1'b0;

        freeze_upper = (case_M - 1) + 7;
        for (fp = 0; fp <= freeze_upper; fp = fp + 1) begin
          $display("---- Part A: cross_terms freeze at active_cyc=%0d (full chain) ----", fp);
          reset_dut();
          run_pass($sformatf("freeze-sweep-fullchain[fp=%0d]", fp), 1'b1, fp, 1, errs);
        end
      end

      // ---- M=1 and M=4 explicitly, with (heavily) extreme data --
      // shortest and longest pipeline-overlap windows this module pair
      // produces, covered directly rather than trusting Part B's random
      // M draws to land on both extremes reliably. ----
      begin : m1_m4_extreme
        logic [31:0] rng_me;
        rng_me = 32'hFEED0021;

        case_M = 1;
        mode_unsigned = 1'b0;
        for (mm = 0; mm < 4; mm = mm + 1)
          for (kk = 0; kk < 4; kk = kk + 1) begin
            A_case[mm][kk] = heavy_extreme_byte(rng_me);
            W_case[mm][kk] = heavy_extreme_byte(rng_me);
          end
        $display("---- Part A: M=1 with heavy extreme data, SIGNED ----");
        reset_dut();
        run_pass("M1-extreme-signed", 1'b0, 0, 0, errs);

        case_M = 1;
        mode_unsigned = 1'b1;
        for (mm = 0; mm < 4; mm = mm + 1)
          for (kk = 0; kk < 4; kk = kk + 1) begin
            A_case[mm][kk] = heavy_extreme_byte(rng_me);
            W_case[mm][kk] = heavy_extreme_byte(rng_me);
          end
        $display("---- Part A: M=1 with heavy extreme data, UNSIGNED ----");
        reset_dut();
        run_pass("M1-extreme-unsigned", 1'b0, 0, 0, errs);

        case_M = 4;
        mode_unsigned = 1'b0;
        for (mm = 0; mm < 4; mm = mm + 1)
          for (kk = 0; kk < 4; kk = kk + 1) begin
            A_case[mm][kk] = heavy_extreme_byte(rng_me);
            W_case[mm][kk] = heavy_extreme_byte(rng_me);
          end
        $display("---- Part A: M=4 with heavy extreme data, SIGNED ----");
        reset_dut();
        run_pass("M4-extreme-signed", 1'b0, 0, 0, errs);

        case_M = 4;
        mode_unsigned = 1'b1;
        for (mm = 0; mm < 4; mm = mm + 1)
          for (kk = 0; kk < 4; kk = kk + 1) begin
            A_case[mm][kk] = heavy_extreme_byte(rng_me);
            W_case[mm][kk] = heavy_extreme_byte(rng_me);
          end
        $display("---- Part A: M=4 with heavy extreme data, UNSIGNED ----");
        reset_dut();
        run_pass("M4-extreme-unsigned", 1'b0, 0, 0, errs);
      end

      $display("----------------------------------------");
      if (errors == 0)
        $display("Part A (depth-0 wire stress x2, sanity walking-one x2, max-magnitude x2, freeze-point-sweep x11, M1/M4 extreme x4): ALL PASSED, checked=%0d total so far", checks);
      else
        $display("Part A: %0d FAILURE(S) SO FAR (checks=%0d)", errors, checks);
      $display("----------------------------------------");
    end

    // ==== Task 021, Part B: long adversarial multi-pass sequences,
    // through the full chain. Not re-testing task 020's grid-only
    // coverage -- the specific thing this is trying to break is whether
    // unpu_skew/unpu_deskew's own pipelined state (up to 3 register
    // stages each) correctly flushes between back-to-back passes of
    // DIFFERING M, with no reset and no idle gap between passes. ====
    begin : part_b
      localparam int NUM_SEQ = 20;

      logic [31:0] master_rng, rng, seq_seed;
      int seq_idx, pass_idx, num_passes, total_passes;
      int mm, kk, jj;
      int this_M, prev_M;
      int freeze_at, freeze_len, active_cyc_max_this_pass;
      bit do_freeze;
      int errs;
      int checks_before_partb;

      master_rng = 32'h5eed0015; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("Skew/de-skew adversarial multi-pass master seed = 32'h%08h", master_rng);
      total_passes        = 0;
      checks_before_partb = checks;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_seed   = master_rng;
        rng        = seq_seed;
        $display("Skew/de-skew adversarial sequence %0d: seed = 32'h%08h", seq_idx, seq_seed);

        rng = xorshift32(rng);
        num_passes = 15 + (rng % 11); // 15..25 passes per sequence

        reset_dut(); // ONE reset for the whole sequence
        prev_M = 0;  // no previous pass yet this sequence

        for (pass_idx = 0; pass_idx < num_passes; pass_idx = pass_idx + 1) begin
          // Sequence 0's first four passes: a deliberate, guaranteed
          // M=4->M=1->M=4->M=1 transition -- the task's own example
          // scenario, exercised explicitly rather than left entirely to
          // the biased-random draws below.
          if (seq_idx == 0 && pass_idx < 4) begin
            this_M = (pass_idx % 2 == 0) ? 4 : 1;
          end else begin
            rng = xorshift32(rng);
            this_M = 1 + (rng % 4);
            if (this_M == prev_M) begin
              rng = xorshift32(rng);
              if (rng[1:0] != 2'd0) begin // 75% chance: redraw once, biasing away from a same-M repeat
                rng = xorshift32(rng);
                this_M = 1 + (rng % 4);
              end
            end
          end
          case_M = this_M;
          prev_M = this_M;

          rng = xorshift32(rng);
          mode_unsigned = rng[0];

          for (mm = 0; mm < 4; mm = mm + 1)
            for (kk = 0; kk < 4; kk = kk + 1)
              A_case[mm][kk] = biased_byte(rng);
          for (kk = 0; kk < 4; kk = kk + 1)
            for (jj = 0; jj < 4; jj = jj + 1)
              W_case[kk][jj] = biased_byte(rng);

          active_cyc_max_this_pass = (case_M - 1) + 7 + 2;
          rng = xorshift32(rng);
          do_freeze = (rng[3:0] != 4'd0); // ~15/16 chance of a freeze this pass
          freeze_at  = 0;
          freeze_len = 0;
          if (do_freeze) begin
            rng = xorshift32(rng);
            freeze_at = rng % (active_cyc_max_this_pass + 1); // random point within this pass's own window
            rng = xorshift32(rng);
            freeze_len = rng % 16; // 0..15 cycles
          end

          run_pass($sformatf("seq%0d/pass%0d/M=%0d", seq_idx, pass_idx, this_M), do_freeze, freeze_at, freeze_len, errs);
          total_passes = total_passes + 1;
        end
      end

      $display("----------------------------------------");
      $display("Part B: %0d sequences, %0d total passes (>=200 required), %0d checks this part (C-values + frozen-output checks), %0d failures",
                NUM_SEQ, total_passes, checks - checks_before_partb, errors);
      if (errors == 0)
        $display("Part B: ALL PASSED");
      $display("----------------------------------------");
    end

    $display("----------------------------------------");
    if (errors == 0)
      $display("ALL TASK 013 + TASK 021 SKEW/DESKEW CHECKS PASSED (cross_terms + 64 crv_* cases + Part A extreme/structural cases + Part B adversarial multi-pass sequences), checked=%0d total", checks);
    else
      $display("%0d TOTAL FAILURE(S) ACROSS ALL SKEW/DESKEW CHECKS (checks=%0d)", errors, checks);
    $display("----------------------------------------");

    $finish;
  end

endmodule
