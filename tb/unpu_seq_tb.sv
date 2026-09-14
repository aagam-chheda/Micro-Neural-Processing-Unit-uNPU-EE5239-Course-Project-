// End-to-end sequencer test for unpu_seq, driving the real
// skew -> grid -> de-skew datapath (same chaining style as
// tb/unpu_skew_tb.sv / tb/unpu_stall_tb.sv) through a full
// weight-load -> input-load -> compute -> readback -> writeback pass, for
// any legal M/N/K each 1-4 (task 006).
//
// Test vectors come from the golden model (model/golden.c, task 006 Part
// A): model/vectors/<case>_{a,w,c}.hex + <case>_meta.txt. Run
// `model/golden` from the repo root before this testbench to (re)generate
// them -- this tb does not regenerate them itself.
//
// For the directed cases (cross_terms/seq_m1/seq_k1/seq_n1/seq_mixed),
// dim_m/dim_n/dim_k/mode_unsigned are driven from explicit,
// test-writer-supplied values, not parsed back out of each case's
// _meta.txt -- the shape of each directed case is already known by name.
// The CRV batch (crv_0000..crv_0063) is the one place this tb parses
// _meta.txt directly, since 64 cases' shapes are golden.c's own random
// draws, not something this file can know in advance.
//
// Simulated with Verilator (--binary --timing) -- iverilog is not
// installed in this environment (no root to apt-get install it); prior
// testbench headers in this repo claim Icarus, which is stale/inaccurate
// for this environment as of this task. Flagged to Planning separately.
`timescale 1ns/1ps

module unpu_seq_tb;

  logic clk;
  logic rst_n;

  logic                  start;
  logic [2:0]            dim_m, dim_n, dim_k;
  logic                  mode_unsigned;
  logic [3:0][3:0][7:0]  a_src;
  logic [3:0][3:0][7:0]  w_src;
  logic [3:0][3:0][31:0] c_dst;
  logic                  done, busy, error;
  logic [2:0]            error_code;

  logic                  array_en;
  logic                  mode_unsigned_o;
  logic [3:0][3:0]       weight_load;
  logic [3:0][3:0][7:0]  weight_in;
  logic [3:0][7:0]       a_raw;
  logic [3:0][31:0]      c_in;

  // Datapath chain, wired the same way as tb/unpu_skew_tb.sv /
  // tb/unpu_stall_tb.sv: unpu_skew -> unpu_grid -> unpu_deskew.
  logic [3:0][7:0]  skew_act_out;
  logic [3:0][31:0] grid_psum_in;   // north edge, tied 0 for the whole run -- no accumulation across passes
  logic [3:0][7:0]  grid_act_out;   // east edge, unused
  logic [3:0][31:0] grid_psum_out;
  logic [3:0][31:0] deskew_c_out;

  assign grid_psum_in = '0;
  assign c_in          = deskew_c_out;

  unpu_seq u_seq (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (start),
    .dim_m           (dim_m),
    .dim_n           (dim_n),
    .dim_k           (dim_k),
    .mode_unsigned   (mode_unsigned),
    .a_src           (a_src),
    .w_src           (w_src),
    .c_dst           (c_dst),
    .done            (done),
    .busy            (busy),
    .error           (error),
    .error_code      (error_code),
    .array_en        (array_en),
    .mode_unsigned_o (mode_unsigned_o),
    .weight_load     (weight_load),
    .weight_in       (weight_in),
    .a_raw           (a_raw),
    .c_in            (c_in)
  );

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
    .mode_unsigned (mode_unsigned_o),
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
    .c_out    (deskew_c_out)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1; // allow NBAs to settle before checking
  endtask

  int errors;
  int checks;

  // Case storage: always 4x4 for A/W (task 006 Part A's fixed 16-byte
  // format), C sized 4x4 too (unused rows/cols beyond the true M/N are
  // simply never read).
  logic [7:0]  A_case [0:3][0:3];
  logic [7:0]  W_case [0:3][0:3];
  logic [31:0] C_case [0:3][0:3];

  task automatic do_reset;
    begin
      rst_n         = 0;
      start         = 0;
      dim_m         = 3'd0;
      dim_n         = 3'd0;
      dim_k         = 3'd0;
      mode_unsigned = 1'b0;
      a_src         = '0;
      w_src         = '0;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  // Loads <name>_{a,w,c}.hex into A_case/W_case/C_case and drives
  // a_src/w_src from them. Unrolled per-element (rather than a
  // variable-indexed loop) -- same simulator-portability convention as
  // tb/unpu_skew_tb.sv/tb/unpu_grid_tb.sv (a non-constant [r][c] index
  // pair as an lvalue into a 3-level packed array is rejected by some
  // simulators).
  task automatic load_case(input string name);
    begin
      $readmemh({"model/vectors/", name, "_a.hex"}, A_case);
      $readmemh({"model/vectors/", name, "_w.hex"}, W_case);
      $readmemh({"model/vectors/", name, "_c.hex"}, C_case);

      a_src[0][0] = A_case[0][0]; a_src[0][1] = A_case[0][1]; a_src[0][2] = A_case[0][2]; a_src[0][3] = A_case[0][3];
      a_src[1][0] = A_case[1][0]; a_src[1][1] = A_case[1][1]; a_src[1][2] = A_case[1][2]; a_src[1][3] = A_case[1][3];
      a_src[2][0] = A_case[2][0]; a_src[2][1] = A_case[2][1]; a_src[2][2] = A_case[2][2]; a_src[2][3] = A_case[2][3];
      a_src[3][0] = A_case[3][0]; a_src[3][1] = A_case[3][1]; a_src[3][2] = A_case[3][2]; a_src[3][3] = A_case[3][3];

      w_src[0][0] = W_case[0][0]; w_src[0][1] = W_case[0][1]; w_src[0][2] = W_case[0][2]; w_src[0][3] = W_case[0][3];
      w_src[1][0] = W_case[1][0]; w_src[1][1] = W_case[1][1]; w_src[1][2] = W_case[1][2]; w_src[1][3] = W_case[1][3];
      w_src[2][0] = W_case[2][0]; w_src[2][1] = W_case[2][1]; w_src[2][2] = W_case[2][2]; w_src[2][3] = W_case[2][3];
      w_src[3][0] = W_case[3][0]; w_src[3][1] = W_case[3][1]; w_src[3][2] = W_case[3][2]; w_src[3][3] = W_case[3][3];
    end
  endtask

  // Pulses start (assumes dim_*/mode_unsigned and a_src/w_src are already
  // driven) and runs to completion, counting:
  //  - total_cycles: edges from the start-pulse edge through the edge
  //    `done` is observed high, inclusive -- used for the one-cycle-early
  //    differential check (same dim_m, different dim_k/dim_n must give
  //    the same total_cycles).
  //  - compute_cycles: edges where `state` reads COMPUTE, post-edge --
  //    equals exactly dim_m+7 by construction (see rtl/unpu_seq.sv's
  //    header comment); checked directly against dim_m+7 by the caller.
  // Does NOT reset and does NOT load vectors -- callers that want a clean
  // run call do_reset()/load_case() first; the illegal-config/recovery
  // test deliberately does not, to prove recovery works without one.
  task automatic pulse_start_and_run(output int total_cycles, output int compute_cycles);
    begin
      start = 1;
      step();
      start = 0;
      total_cycles   = 1;
      compute_cycles = (u_seq.state === u_seq.COMPUTE) ? 1 : 0;

      while (done !== 1'b1) begin
        step();
        total_cycles = total_cycles + 1;
        if (u_seq.state === u_seq.COMPUTE)
          compute_cycles = compute_cycles + 1;
      end
    end
  endtask

  // Checks c_dst[m][j] against C_case[m][j] over the true drv_m x drv_n
  // submatrix (C_case may hold stale/undefined data beyond that from a
  // previous, larger case -- never read here).
  task automatic check_result(input string name, input int drv_m, input int drv_n);
    int m, j;
    begin
      for (m = 0; m < drv_m; m = m + 1) begin
        for (j = 0; j < drv_n; j = j + 1) begin
          checks = checks + 1;
          if (c_dst[m][j] !== C_case[m][j]) begin
            errors = errors + 1;
            $display("FAIL [%s]: c_dst[%0d][%0d] exp=%0d got=%0d", name, m, j, C_case[m][j], c_dst[m][j]);
          end else begin
            $display("PASS [%s]: c_dst[%0d][%0d] = %0d", name, m, j, c_dst[m][j]);
          end
        end
      end
    end
  endtask

  // Full convenience path: reset, load, drive shape, run, check. Used for
  // every case that doesn't need the illegal-config/recovery test's
  // no-reset-in-between behavior.
  task automatic run_case(input string name, input int drv_m, input int drv_k,
                           input int drv_n, input bit drv_mode_u,
                           output int total_cycles, output int compute_cycles);
    begin
      do_reset();
      load_case(name);
      dim_m         = drv_m[2:0];
      dim_k         = drv_k[2:0];
      dim_n         = drv_n[2:0];
      mode_unsigned = drv_mode_u;

      pulse_start_and_run(total_cycles, compute_cycles);
      check_result(name, drv_m, drv_n);
    end
  endtask

  int total_cyc, compute_cyc;
  int total_cyc_b, compute_cyc_b;

  // ---- CRV bookkeeping: record (dim_m, dim_k, dim_n, total_cycles) per
  // case so the K/N-independence property can be checked opportunistically
  // across any pair sharing the same dim_m. ----
  int crv_m   [0:63];
  int crv_k   [0:63];
  int crv_n   [0:63];
  int crv_tot [0:63];
  int crv_comp[0:63];

  int i, j2, pairs_checked;
  int fd, scan_rc;
  int meta_m, meta_k, meta_n;
  string mode_str;
  string crv_name;

  initial begin
    errors = 0;
    checks = 0;

    // ==== Directed: regression anchor ====
    run_case("cross_terms", 4, 4, 4, 1'b0, total_cyc, compute_cyc);
    if (compute_cyc !== (4 + 7)) begin
      errors = errors + 1;
      $display("FAIL [cross_terms]: compute_cyc=%0d expected %0d (dim_m+7)", compute_cyc, 4 + 7);
    end else begin
      checks = checks + 1;
      $display("PASS [cross_terms]: compute_cyc=%0d == dim_m+7", compute_cyc);
    end

    // ==== Directed: sub-4 shape boundaries ====
    run_case("seq_m1", 1, 4, 4, 1'b0, total_cyc, compute_cyc);
    if (compute_cyc !== (1 + 7)) begin
      errors = errors + 1;
      $display("FAIL [seq_m1]: compute_cyc=%0d expected %0d (dim_m+7)", compute_cyc, 1 + 7);
    end else begin
      checks = checks + 1;
      $display("PASS [seq_m1]: compute_cyc=%0d == dim_m+7", compute_cyc);
    end

    run_case("seq_k1", 4, 1, 4, 1'b0, total_cyc, compute_cyc);
    run_case("seq_n1", 4, 4, 1, 1'b0, total_cyc, compute_cyc);
    run_case("seq_mixed", 3, 2, 3, 1'b0, total_cyc, compute_cyc);

    // COMPUTE-length check for dim_m=1 and dim_m=4 is already asserted
    // above, inline with the seq_m1/cross_terms runs (compute_cyc ==
    // dim_m+7 in each case) -- that's the same check the acceptance
    // criterion asks for, just run where the case is already loaded
    // rather than repeated as a separate pass.

    // ==== One-cycle-early differential check (required): same dim_m
    // (4), two different (dim_k, dim_n) pairs -- total elapsed
    // start->done cycle count must be identical. This is what catches
    // the M+K+N-2 bug class -- a wrong implementation passes cross_terms
    // (K=N=4) and only fails here (K=N=1). ====
    run_case("cross_terms", 4, 4, 4, 1'b0, total_cyc, compute_cyc);
    run_case("seq_k1",      4, 1, 1, 1'b0, total_cyc_b, compute_cyc_b);
    checks = checks + 1;
    if (total_cyc !== total_cyc_b) begin
      errors = errors + 1;
      $display("FAIL [one-cycle-early diff]: dim_m=4 total_cycles differ across (K=4,N=4)=%0d vs (K=1,N=1)=%0d -- M+K+N-2 regression",
                total_cyc, total_cyc_b);
    end else begin
      $display("PASS [one-cycle-early diff]: dim_m=4 total_cycles identical across (K=4,N=4) and (K=1,N=1): %0d", total_cyc);
    end
    checks = checks + 1;
    if (compute_cyc !== compute_cyc_b || compute_cyc !== (4 + 7)) begin
      errors = errors + 1;
      $display("FAIL [one-cycle-early diff]: compute_cyc mismatch (K=4,N=4)=%0d vs (K=1,N=1)=%0d, expected both %0d",
                compute_cyc, compute_cyc_b, 4 + 7);
    end else begin
      $display("PASS [one-cycle-early diff]: compute_cyc identical and == dim_m+7 across both (K,N) pairs: %0d", compute_cyc);
    end

    // ==== Illegal-config + recovery, no reset between attempts from the
    // second onward -- proves the ERROR state's own start-triggered
    // recovery path, not just "a fresh reset always works." Covers three
    // distinct fields (dim_m, dim_k, dim_n) across the illegal set. ====

    // (a) dim_m = 0 -- fresh reset, first illegal probe.
    do_reset();
    dim_m = 3'd0; dim_k = 3'd4; dim_n = 3'd4; mode_unsigned = 1'b0;
    a_src = '0; w_src = '0;
    start = 1; step(); start = 0;
    step(); // LATCH_CFG -> ERROR (illegal)
    checks = checks + 1;
    if (error !== 1'b1 || error_code !== 3'd1) begin
      errors = errors + 1;
      $display("FAIL [illegal dim_m=0]: expected error=1 error_code=1, got error=%0b error_code=%0d", error, error_code);
    end else begin
      $display("PASS [illegal dim_m=0]: error=1 error_code=1");
    end

    begin : no_done_check_a
      bit saw_done;
      saw_done = 1'b0;
      for (i = 0; i < 20; i = i + 1) begin
        if (done) saw_done = 1'b1;
        step();
      end
      checks = checks + 1;
      if (saw_done) begin
        errors = errors + 1;
        $display("FAIL [illegal dim_m=0]: done pulsed while parked in ERROR");
      end else begin
        $display("PASS [illegal dim_m=0]: done never pulsed while parked in ERROR (20 cycles)");
      end
    end

    // (b) dim_k = 0 -- fresh reset, second field.
    do_reset();
    dim_m = 3'd4; dim_k = 3'd0; dim_n = 3'd4; mode_unsigned = 1'b0;
    a_src = '0; w_src = '0;
    start = 1; step(); start = 0;
    step();
    checks = checks + 1;
    if (error !== 1'b1 || error_code !== 3'd1) begin
      errors = errors + 1;
      $display("FAIL [illegal dim_k=0]: expected error=1 error_code=1, got error=%0b error_code=%0d", error, error_code);
    end else begin
      $display("PASS [illegal dim_k=0]: error=1 error_code=1");
    end

    // (c) dim_n = 5 -- deliberately NO reset here: FSM is still parked in
    // ERROR from (b). A fresh illegal 'start' re-attempts LATCH_CFG (per
    // the ERROR state's own spec) and lands back in ERROR.
    dim_m = 3'd4; dim_k = 3'd4; dim_n = 3'd5; mode_unsigned = 1'b0;
    start = 1; step(); start = 0;
    step();
    checks = checks + 1;
    if (error !== 1'b1 || error_code !== 3'd1) begin
      errors = errors + 1;
      $display("FAIL [illegal dim_n=5]: expected error=1 error_code=1, got error=%0b error_code=%0d", error, error_code);
    end else begin
      $display("PASS [illegal dim_n=5]: error=1 error_code=1 (re-entered ERROR from ERROR, no reset)");
    end

    // Recovery: a LEGAL start, still with NO reset since (b) -- proves
    // the FSM is not stuck in ERROR.
    load_case("cross_terms");
    dim_m = 3'd4; dim_k = 3'd4; dim_n = 3'd4; mode_unsigned = 1'b0;
    pulse_start_and_run(total_cyc, compute_cyc);
    check_result("cross_terms (post-error recovery, no reset)", 4, 4);
    checks = checks + 1;
    if (compute_cyc !== (4 + 7)) begin
      errors = errors + 1;
      $display("FAIL [post-error recovery]: compute_cyc=%0d expected %0d", compute_cyc, 4 + 7);
    end else begin
      $display("PASS [post-error recovery]: FSM recovered from ERROR without reset, ran to completion correctly");
    end

    // ==== CRV: all 64 crv_* cases from model/golden.c, shapes parsed
    // from each case's own _meta.txt (the one place this tb parses shape
    // rather than hard-coding it -- see file header comment). ====
    $display("CRV base seed = 32'h5eed0006 (see model/golden.c)");

    for (i = 0; i < 64; i = i + 1) begin
      crv_name = $sformatf("crv_%04d", i);

      fd = $fopen({"model/vectors/", crv_name, "_meta.txt"}, "r");
      if (fd == 0)
        $fatal(1, "could not open model/vectors/%s_meta.txt -- run model/golden first", crv_name);
      scan_rc = $fscanf(fd, "M=%d\nMODE=%s\nK=%d\nN=%d\n", meta_m, mode_str, meta_k, meta_n);
      $fclose(fd);
      if (scan_rc != 4)
        $fatal(1, "could not parse model/vectors/%s_meta.txt (got %0d fields)", crv_name, scan_rc);

      run_case(crv_name, meta_m, meta_k, meta_n, (mode_str == "UNSIGNED"), total_cyc, compute_cyc);

      checks = checks + 1;
      if (compute_cyc !== (meta_m + 7)) begin
        errors = errors + 1;
        $display("FAIL [%s]: compute_cyc=%0d expected %0d (dim_m+7)", crv_name, compute_cyc, meta_m + 7);
      end else begin
        $display("PASS [%s]: M=%0d K=%0d N=%0d MODE=%s compute_cyc==dim_m+7", crv_name, meta_m, meta_k, meta_n, mode_str);
      end

      crv_m[i]    = meta_m;
      crv_k[i]    = meta_k;
      crv_n[i]    = meta_n;
      crv_tot[i]  = total_cyc;
      crv_comp[i] = compute_cyc;
    end

    // Opportunistic K/N-independence check across the CRV batch: any pair
    // sharing dim_m but differing in (dim_k, dim_n) must have identical
    // total_cycles. Not forced -- just checked wherever it naturally
    // occurs among the 64 draws.
    pairs_checked = 0;
    for (i = 0; i < 64; i = i + 1) begin
      for (j2 = i + 1; j2 < 64; j2 = j2 + 1) begin
        if (crv_m[i] == crv_m[j2] &&
            (crv_k[i] != crv_k[j2] || crv_n[i] != crv_n[j2])) begin
          pairs_checked = pairs_checked + 1;
          checks = checks + 1;
          if (crv_tot[i] !== crv_tot[j2]) begin
            errors = errors + 1;
            $display("FAIL [CRV K/N-independence]: crv_%04d (M=%0d,K=%0d,N=%0d,tot=%0d) vs crv_%04d (M=%0d,K=%0d,N=%0d,tot=%0d) -- same M, different total_cycles",
                      i, crv_m[i], crv_k[i], crv_n[i], crv_tot[i],
                      j2, crv_m[j2], crv_k[j2], crv_n[j2], crv_tot[j2]);
          end
        end
      end
    end
    $display("CRV K/N-independence: %0d comparable pair(s) found and checked", pairs_checked);

    $display("----------------------------------------");
    $display("checked %0d value(s)/assertion(s) total", checks);
    if (errors == 0)
      $display("ALL CHECKS PASSED");
    else
      $display("%0d FAILURE(S) (checks=%0d)", errors, checks);
    $display("----------------------------------------");

    $finish;
  end

endmodule
