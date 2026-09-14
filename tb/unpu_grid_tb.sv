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

    $finish;
  end

endmodule
