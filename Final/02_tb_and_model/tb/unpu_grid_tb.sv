// Grid-level identity/matmul test for unpu_grid (End-W2 gate).
//
// No skew/de-skew bank exists yet -- this testbench performs the west-edge
// skew by hand, per the timing contract in CLAUDE.md:
//   A[m][k] enters west edge of row k  at cycle m+k
//   C[m][j] leaves south edge of col j at cycle m+j+4
// Weights are forced directly per-PE from the case's W matrix, not loaded
// through the shift-down network (that's unpu_wbuf, step 9, out of scope
// here).
//
// Test vectors come from the golden model (task 002, model/golden.c):
// model/vectors/<case>_{a,w,c}.hex + <case>_meta.txt. Run `model/golden`
// from the repo root before this testbench to (re)generate them -- this tb
// does not regenerate them itself.
//
// Simulated with Icarus Verilog (iverilog/vvp) -- Xcelium not available in
// this environment, same as tb/unpu_pe_tb.sv.
//
// Task 013 (verification-debt retrofit) added the 64-case crv_* sweep
// below, closing plan.md's "identity-weight test only" gap for this
// module; simulated with Verilator for that addition -- see
// tb/unpu_pe_tb.sv's header for why the Icarus line above is stale.
`timescale 1ns/1ps

module unpu_grid_tb;

  logic clk;
  logic rst_n;
  logic array_en;
  logic mode_unsigned;

  logic [3:0][3:0]      weight_load;
  logic [3:0][3:0][7:0] weight_in;
  logic [3:0][7:0]      act_in;
  logic [3:0][31:0]     psum_in;
  logic [3:0][7:0]      act_out;
  logic [3:0][31:0]     psum_out;

  int errors;
  int checks;
  int cases_run;

  unpu_grid dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .array_en      (array_en),
    .mode_unsigned (mode_unsigned),
    .weight_load   (weight_load),
    .weight_in     (weight_in),
    .act_in        (act_in),
    .psum_in       (psum_in),
    .act_out       (act_out),
    .psum_out      (psum_out)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  // Case storage. Sized for the current cap of M=4 (matches every case
  // model/golden.c produces right now) -- not a general M, per task 002's
  // scope: "no cases beyond identity and all_ones right now."
  logic [7:0]  A_case [0:3][0:3];
  logic [7:0]  W_case [0:3][0:3];
  logic [31:0] C_case [0:3][0:3];

  int m, k, j, cyc, cyc_max;
  int case_M;
  int fd, scan_rc;
  string mode_str;

  task automatic run_case(input string name);
    string path;
    begin
      // ---- Load meta (M, MODE) ----
      // Errors here $fatal (abort) rather than set-a-flag-and-skip: under
      // the Verilator 5.050 --timing coroutine mode, "if (cond) <code
      // that contains an @(posedge)>" silently drops every global-state
      // write made inside that branch for the rest of the run (confirmed
      // with a minimal repro; a genuine tool bug, not a testbench logic
      // error). $fatal sidesteps the pattern entirely -- there is nothing
      // to conditionally skip past when the whole run stops immediately.
      // (Icarus has no such issue; this restructuring is required only
      // for compatibility with that other simulator.) A missing or
      // malformed vector file is a setup error, not a per-case failure,
      // so aborting is the right behavior regardless.
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

      // ---- Load A, W, C via $readmemh, contract from task 002 ----
      $readmemh({"model/vectors/", name, "_a.hex"}, A_case);
      $readmemh({"model/vectors/", name, "_w.hex"}, W_case);
      $readmemh({"model/vectors/", name, "_c.hex"}, C_case);

      $display("---- case '%s': M=%0d MODE=%s ----", name, case_M, mode_str);
      cases_run = cases_run + 1;

      // ---- Reset ----
      rst_n         = 0;
      array_en      = 0;
      weight_load   = '0;
      weight_in     = '0;
      act_in        = '0;
      psum_in       = '0;
      step();
      step();
      rst_n = 1;
      step();

      // ---- Preload weights, direct per-PE forcing. Unrolled (rather
      // than a variable-indexed double for-loop) for simulator
      // portability -- Icarus rejects a non-constant [r][c] index pair
      // as an lvalue into a 3-level packed array. All indices below are
      // literal constants; only the values (from W_case, reloaded per
      // case) vary. ----
      array_en = 1;
      weight_in[0][0] = W_case[0][0]; weight_in[0][1] = W_case[0][1]; weight_in[0][2] = W_case[0][2]; weight_in[0][3] = W_case[0][3];
      weight_in[1][0] = W_case[1][0]; weight_in[1][1] = W_case[1][1]; weight_in[1][2] = W_case[1][2]; weight_in[1][3] = W_case[1][3];
      weight_in[2][0] = W_case[2][0]; weight_in[2][1] = W_case[2][1]; weight_in[2][2] = W_case[2][2]; weight_in[2][3] = W_case[2][3];
      weight_in[3][0] = W_case[3][0]; weight_in[3][1] = W_case[3][1]; weight_in[3][2] = W_case[3][2]; weight_in[3][3] = W_case[3][3];
      weight_load = '1; // pulse all 16 PEs simultaneously
      act_in  = '0;
      psum_in = '0;
      step();
      weight_load = '0;

      // ---- Compute pass: hand-skewed activation injection, cyc = 0 is
      // the first activation-injection edge (this step, right after
      // preload). Drive/check window covers injection (max m+k =
      // (M-1)+3) through readout (max m+j+4, checked via the cyc+1
      // relation below).
      cyc_max = (case_M - 1) + 6; // generous margin past last readout
      for (cyc = 0; cyc <= cyc_max; cyc = cyc + 1) begin
        for (k = 0; k < 4; k = k + 1) begin
          m = cyc - k;
          if (m >= 0 && m < case_M)
            act_in[k] = A_case[m][k];
          else
            act_in[k] = 8'h00;
        end
        psum_in = '0;

        step(); // this edge completes cycle 'cyc'

        // psum_out[j] holds the value valid "during cycle cyc+1" (the
        // edge just taken is the edge ending cycle 'cyc', by the drive
        // convention above; C[m][j] leaves at cycle m+j+4 means valid
        // starting that cycle): solve cyc+1 == m+j+4, i.e. m = cyc-j-3.
        for (j = 0; j < 4; j = j + 1) begin
          m = cyc - j - 3;
          if (m >= 0 && m < case_M) begin
            checks = checks + 1;
            if (psum_out[j] !== C_case[m][j]) begin
              $display("FAIL [%s]: cycle=%0d psum_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        name, cyc, j, m, j, C_case[m][j], psum_out[j]);
              errors = errors + 1;
            end else begin
              $display("PASS [%s]: cycle=%0d psum_out[%0d] (C[%0d][%0d]) = %0d",
                        name, cyc, j, m, j, psum_out[j]);
            end
          end
        end
      end
    end
  endtask

  // ==== Task 020: independent reference model + shared pass-runner for
  // Part A (extreme/structural directed cases) and Part B (adversarial
  // multi-pass sequences). Derived from the matmul shape in the timing
  // contract (A[M x K] x W[K x N] = C[M x N], signed/unsigned int8 in,
  // int32 out -- CLAUDE.md / handoff §6), NOT from unpu_pe.sv's or
  // unpu_grid.sv's own per-cycle systolic MAC code: ref_c_elem below is
  // a plain nested-loop dot product over a snapshot of A_case/W_case,
  // structurally different from the RTL's row-by-row propagating
  // accumulation, computing the same math a different way.
  //
  // Self-check against the campaign-wide caution from task 019 (whose
  // first-draft PE reference model accumulated from its own prior state
  // instead of each cycle's driven input): ref_c_elem carries NO
  // persistent state between calls at all -- every call recomputes its
  // one C[m][j] value from scratch off of A_case/W_case/mode_unsigned as
  // plain inputs, so there is no running/carried variable that could
  // silently diverge from what the real hardware does. Part A2 (walking-
  // one) additionally exercises this model against a hand-verifiable
  // expected pattern (C[m][j] = A[m][kpos] when j==jpos, else 0) at 16
  // independent, trivially-checkable points, standing in as the explicit
  // sanity pass the task asks for before trusting Part B's larger run.
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

  // ~1/8 chance of landing on a boundary extreme instead of a plain
  // uniform byte -- same discipline task 019 used for PE, deliberately
  // biasing toward the values most likely to expose a wiring/width bug
  // rather than trusting uniform random to find them by chance.
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

  task automatic reset_dut;
    begin
      rst_n       = 0;
      array_en    = 0;
      weight_load = '0;
      weight_in   = '0;
      act_in      = '0;
      psum_in     = '0;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  // Preloads weights from the module-level W_case, then runs one full
  // compute pass over the module-level A_case/case_M/mode_unsigned,
  // checking psum_out against ref_c_elem (not any preloaded C_case file)
  // at the freeze-adjusted active_cyc (task 005's bookkeeping convention
  // -- active_cyc increments only on edges where array_en was 1, so a
  // frozen edge doesn't advance the schedule the timing contract is
  // measured against). Does NOT reset the DUT -- callers running a
  // single isolated pass call reset_dut() first; Part B's back-to-back
  // sequences call reset_dut() once per sequence and then this task
  // repeatedly, deliberately with no reset and no idle gap between
  // passes.
  //
  // do_freeze/freeze_at_active_cyc/freeze_len: at most one freeze
  // window, injected the instant active_cyc reaches freeze_at_active_cyc
  // (freeze_len cycles, 0 meaning none). Also checks that psum_out/
  // act_out (the two directly-observable grid outputs) genuinely hold
  // during every frozen cycle, not just that the schedule doesn't
  // advance.
  task automatic run_pass(input string label, input bit do_freeze, input int freeze_at_active_cyc,
                           input int freeze_len, output int errs_this_pass);
    int active_cyc, active_cyc_max;
    int mrow, jcol, kk, s;
    logic [31:0] exp_val;
    logic [3:0][7:0]  pre_act;
    logic [3:0][31:0] pre_psum;
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
      act_in  = '0;
      psum_in = '0;
      step();
      weight_load = '0;

      // ---- Compute pass, indexed by active_cyc. Raw grid (no de-skew
      // here): C[m][j] leaves col j at wall-clock cycle m+j+4, which in
      // active_cyc (post-increment) terms is m = active_cyc - j - 4 --
      // same relationship run_case()'s cyc-based m = cyc - j - 3 already
      // encodes (active_cyc == cyc+1 in the no-freeze case, so the two
      // formulas agree exactly when nothing freezes; active_cyc is what
      // stays correct once something does). ----
      active_cyc     = 0;
      active_cyc_max = (case_M - 1) + 6; // same margin run_case() already uses

      while (active_cyc <= active_cyc_max) begin
        if (do_freeze && freeze_len > 0 && active_cyc == freeze_at_active_cyc) begin
          pre_act  = act_out;
          pre_psum = psum_out;
          for (s = 0; s < freeze_len; s = s + 1) begin
            array_en = 0;
            act_in   = {4{8'hA5}}; // don't-care garbage; DUT must ignore it while frozen
            psum_in  = '0;
            step(); // frozen edge -- active_cyc does NOT advance
            checks = checks + 1;
            if (act_out !== pre_act) begin
              errs_this_pass = errs_this_pass + 1;
              errors = errors + 1;
              $display("FAIL FREEZE [%s]: act_out changed during frozen cycle %0d/%0d at active_cyc=%0d (was %0h now %0h)",
                        label, s + 1, freeze_len, active_cyc, pre_act, act_out);
            end
            checks = checks + 1;
            if (psum_out !== pre_psum) begin
              errs_this_pass = errs_this_pass + 1;
              errors = errors + 1;
              $display("FAIL FREEZE [%s]: psum_out changed during frozen cycle %0d/%0d at active_cyc=%0d (was %0h now %0h)",
                        label, s + 1, freeze_len, active_cyc, pre_psum, psum_out);
            end
          end
          array_en = 1;
        end

        for (kk = 0; kk < 4; kk = kk + 1) begin
          mrow = active_cyc - kk;
          if (mrow >= 0 && mrow < case_M)
            act_in[kk] = A_case[mrow][kk];
          else
            act_in[kk] = 8'h00;
        end
        psum_in  = '0;
        array_en = 1;

        step(); // active edge
        active_cyc = active_cyc + 1;

        for (jcol = 0; jcol < 4; jcol = jcol + 1) begin
          mrow = active_cyc - jcol - 4;
          if (mrow >= 0 && mrow < case_M) begin
            exp_val = ref_c_elem(W_case, A_case, mrow, jcol, mode_unsigned);
            checks  = checks + 1;
            if (psum_out[jcol] !== exp_val) begin
              errs_this_pass = errs_this_pass + 1;
              errors = errors + 1;
              $display("FAIL [%s]: active_cyc=%0d psum_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        label, active_cyc, jcol, mrow, jcol, exp_val, psum_out[jcol]);
            end
          end
        end
      end
    end
  endtask

  initial begin
    errors    = 0;
    checks    = 0;
    cases_run = 0;

    run_case("identity");
    run_case("all_ones");
    run_case("random_signed");
    run_case("random_unsigned");

    // ==== Task 013 Part B: verification-debt retrofit -- all 64 crv_*
    // cases from task 006 Part A, same hand-skewed methodology as above.
    // These files' recorded M/K/N is irrelevant here: A/W are always a
    // full 4x4 (task 006 Part A wrote them that way unconditionally),
    // and run_case() above already generalizes correctly to whatever
    // case_M each case's own _meta.txt reports (cyc_max and the m-range
    // check are both derived from case_M, not hardcoded to 4) -- it was
    // written generally even though only ever exercised with case_M==4
    // until now. This closes plan.md's "identity-weight test only... no
    // randomized weight/activation matrices" verification-debt note. ====
    begin : crv_sweep
      int ci;
      string crv_name;
      for (ci = 0; ci < 64; ci = ci + 1) begin
        crv_name = $sformatf("crv_%04d", ci);
        run_case(crv_name);
      end
    end

    $display("----------------------------------------");
    $display("ran %0d case(s), checked %0d values total", cases_run, checks);
    if (errors == 0)
      $display("ALL CHECKS PASSED");
    else
      $display("%0d FAILURE(S) (checks=%0d)", errors, checks);
    $display("----------------------------------------");

    // ==== Task 020, Part A: extreme/structural directed cases. Not
    // re-proving task 013's already-solid single-pass coverage -- these
    // target extreme magnitudes, per-PE wiring isolation, and freeze
    // *position* exhaustively on one dataset, none of which the existing
    // 64-crv_*-case run was built to target. Generated directly here in
    // SV, no other file touched. ====
    begin : part_a
      int errs;
      int mm, kk, jj, kpos, jpos, fp, freeze_upper;

      // ---- A1: maximum-magnitude, both modes. All-0xFF weight x
      // all-0xFF activation: signed is small (-1*-1, repeated), unsigned
      // is 255*255*4=260,100 per element -- well inside the 32-bit
      // accumulator on paper, worth confirming the wiring actually
      // carries it correctly end to end, not just checking it doesn't
      // overflow analytically. ----
      case_M = 4;
      for (mm = 0; mm < 4; mm = mm + 1)
        for (kk = 0; kk < 4; kk = kk + 1) begin
          A_case[mm][kk] = 8'hFF;
          W_case[mm][kk] = 8'hFF;
        end

      mode_unsigned = 1'b0;
      $display("---- Part A1: max-magnitude, SIGNED ----");
      reset_dut();
      run_pass("maxmag-signed", 1'b0, 0, 0, errs);

      mode_unsigned = 1'b1;
      $display("---- Part A1: max-magnitude, UNSIGNED ----");
      reset_dut();
      run_pass("maxmag-unsigned", 1'b0, 0, 0, errs);

      // ---- A2: walking-one weight matrix. A single weight[k][j]=1 at
      // each of the 16 positions in turn (rest zero), paired with
      // distinct nonzero activations per row (A[m][k]=16*m+k+1, all
      // different, per the task's own formula) -- isolates each of the
      // grid's internal PE-to-PE wiring paths individually, more
      // precisely than cross_terms needed to (task 004 only had to rule
      // out row/column swaps in the skew/de-skew banks). Doubles as the
      // explicit reference-model sanity check called for above: each of
      // these 16 sub-cases has a trivially hand-verifiable expected
      // pattern (C[m][j] = A[m][kpos] when j==jpos, else 0). ----
      mode_unsigned = 1'b0;
      case_M = 4;
      for (kpos = 0; kpos < 4; kpos = kpos + 1) begin
        for (jpos = 0; jpos < 4; jpos = jpos + 1) begin
          for (kk = 0; kk < 4; kk = kk + 1)
            for (jj = 0; jj < 4; jj = jj + 1)
              W_case[kk][jj] = (kk == kpos && jj == jpos) ? 8'h01 : 8'h00;
          for (mm = 0; mm < 4; mm = mm + 1)
            for (kk = 0; kk < 4; kk = kk + 1)
              A_case[mm][kk] = 8'(16 * mm + kk + 1);

          $display("---- Part A2: walking-one weight[%0d][%0d] ----", kpos, jpos);
          reset_dut();
          run_pass($sformatf("walking-one[%0d][%0d]", kpos, jpos), 1'b0, 0, 0, errs);
        end
      end

      // ---- A3: exhaustive freeze-point sweep on cross_terms (task
      // 004's non-trivial dataset), one 1-cycle freeze per active_cyc
      // from 0 through (M-1)+7 inclusive -- M+7 = 11 sub-cases for M=4,
      // matching CLAUDE.md's own "total cycles for a pass of M rows =
      // M+7" figure exactly (this is the full entry-through-drain span:
      // the very last check, m=M-1/j=3, lands at active_cyc=(M-1)+7).
      // Reuses task 005's active_cyc bookkeeping convention directly,
      // via the same run_pass() task Part B below also uses -- no
      // freeze-aware cycle tracking reinvented here. Checked against the
      // inline reference model (ref_c_elem), not cross_terms_c.hex, for
      // the same independent-derivation reason as A1/A2 -- only
      // cross_terms_a.hex/_w.hex (inputs) are read from disk. ----
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
          $display("---- Part A3: cross_terms freeze at active_cyc=%0d ----", fp);
          reset_dut();
          run_pass($sformatf("freeze-sweep[fp=%0d]", fp), 1'b1, fp, 1, errs);
        end
      end

      $display("----------------------------------------");
      if (errors == 0)
        $display("Part A (max-magnitude x2, walking-one x16, freeze-point-sweep x11): ALL PASSED, checked=%0d total so far", checks);
      else
        $display("Part A: %0d FAILURE(S) SO FAR (checks=%0d)", errors, checks);
      $display("----------------------------------------");
    end

    // ==== Task 020, Part B: long adversarial multi-pass sequences --
    // the core of this task. Not re-testing task 013's operand coverage;
    // the specific thing this is trying to break is whether a fresh
    // pass's weight load, starting immediately after the previous pass's
    // own drain with zero added idle gap and NO reset between passes,
    // ever leaks state from one pass into the next -- the grid-level
    // analogue of task 011's "two ops back to back" and task 012's "64
    // CRV cases chained," but in isolation and with far more randomized
    // freeze timing and data than either of those attempted. ====
    begin : part_b
      localparam int NUM_SEQ = 20;

      logic [31:0] master_rng, rng, seq_seed;
      int seq_idx, pass_idx, num_passes, total_passes;
      int mm, kk, jj;
      int freeze_at, freeze_len, active_cyc_max_this_pass;
      bit do_freeze;
      int errs;
      int checks_before_partb;

      master_rng = 32'h5eed0014; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("Grid adversarial multi-pass master seed = 32'h%08h", master_rng);
      total_passes        = 0;
      checks_before_partb = checks;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_seed   = master_rng;
        rng        = seq_seed;
        $display("Grid adversarial sequence %0d: seed = 32'h%08h", seq_idx, seq_seed);

        rng = xorshift32(rng);
        num_passes = 15 + (rng % 11); // 15..25 passes per sequence -- comfortably clears the >=200-total-passes floor

        reset_dut(); // ONE reset for the whole sequence -- every pass after the first gets no reset and no idle gap

        for (pass_idx = 0; pass_idx < num_passes; pass_idx = pass_idx + 1) begin
          case_M = 4;
          rng = xorshift32(rng);
          mode_unsigned = rng[0];

          for (mm = 0; mm < 4; mm = mm + 1)
            for (kk = 0; kk < 4; kk = kk + 1)
              A_case[mm][kk] = biased_byte(rng);
          for (kk = 0; kk < 4; kk = kk + 1)
            for (jj = 0; jj < 4; jj = jj + 1)
              W_case[kk][jj] = biased_byte(rng);

          active_cyc_max_this_pass = (case_M - 1) + 6;
          rng = xorshift32(rng);
          do_freeze = (rng[3:0] != 4'd0); // ~15/16 chance of a freeze this pass -- "not every pass needs one" is the rare exception, not the common case
          freeze_at  = 0;
          freeze_len = 0;
          if (do_freeze) begin
            rng = xorshift32(rng);
            freeze_at = rng % (active_cyc_max_this_pass + 1); // random point within this pass's own active window
            rng = xorshift32(rng);
            freeze_len = rng % 16; // 0..15 cycles, per the task's own spec -- 0 here still counts as "not every pass gets a visible freeze"
          end

          run_pass($sformatf("seq%0d/pass%0d", seq_idx, pass_idx), do_freeze, freeze_at, freeze_len, errs);
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
      $display("ALL TASK 013 + TASK 020 GRID CHECKS PASSED (identity/all_ones/random x2 + 64 crv_* cases + Part A extreme/structural cases + Part B adversarial multi-pass sequences), checked=%0d total", checks);
    else
      $display("%0d TOTAL FAILURE(S) ACROSS ALL GRID CHECKS (checks=%0d)", errors, checks);
    $display("----------------------------------------");

    $finish;
  end

endmodule
