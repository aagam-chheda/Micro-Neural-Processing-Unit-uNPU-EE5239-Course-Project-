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

    $finish;
  end

endmodule
