// Stall test: proves dropping array_en mid-stream freezes the skew bank,
// all 16 PEs, and the de-skew bank on the same clock edge, and that
// resuming afterward is bit-identical to an unstalled run. Reuses the
// cross_terms vectors and skew -> unpu_grid -> unpu_deskew chain built in
// task 004 (tb/unpu_skew_tb.sv) unchanged.
//
// Bookkeeping: driven and checked against an active-cycle counter
// (active_cyc), not raw simulation/wall-clock cycles -- a stall pauses
// the clock the timing contract is measured against, not the clock
// itself. active_cyc increments once per edge on which array_en was 1
// during that edge; it does not advance on edges where the array was
// frozen. See CLAUDE.md for the underlying timing contract this still
// must satisfy once active_cyc is substituted for wall-clock cycles.
//
// Simulated with Icarus Verilog (iverilog/vvp) -- Xcelium not available in
// this environment, same as unpu_pe_tb.sv/unpu_grid_tb.sv/unpu_skew_tb.sv.
`timescale 1ns/1ps

module unpu_stall_tb;

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
  int frozen_checks;
  int g_seed;

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

  // Case storage, M<=4 (matches cross_terms).
  logic [7:0]  A_case [0:3][0:3];
  logic [7:0]  W_case [0:3][0:3];
  logic [31:0] C_case [0:3][0:3];

  int m, j, s, m_drv;
  int case_M;
  int fd, scan_rc;
  string mode_str;
  int active_cyc;
  int stall_len;

  // ---- Freeze-check snapshot storage: the 44 probed registers (depth-0
  // wire paths -- unpu_skew's act_out[0], unpu_deskew's c_out[3] -- are
  // not registers and are excluded, per docs/planning/tasks/005-stall.md). ----
  logic [7:0]  prev_row1_q, prev_row2_q1, prev_row2_q2;
  logic [7:0]  prev_row3_q1, prev_row3_q2, prev_row3_q3;
  logic [31:0] prev_col2_q1, prev_col1_q1, prev_col1_q2;
  logic [31:0] prev_col0_q1, prev_col0_q2, prev_col0_q3;
  logic [7:0]  prev_pe_act  [0:3][0:3];
  logic [31:0] prev_pe_psum [0:3][0:3];
  int prev_active_cyc;

  task automatic capture_snapshot;
    begin
      prev_row1_q  = u_skew.row1_q;
      prev_row2_q1 = u_skew.row2_q1;
      prev_row2_q2 = u_skew.row2_q2;
      prev_row3_q1 = u_skew.row3_q1;
      prev_row3_q2 = u_skew.row3_q2;
      prev_row3_q3 = u_skew.row3_q3;

      prev_col2_q1 = u_deskew.col2_q1;
      prev_col1_q1 = u_deskew.col1_q1;
      prev_col1_q2 = u_deskew.col1_q2;
      prev_col0_q1 = u_deskew.col0_q1;
      prev_col0_q2 = u_deskew.col0_q2;
      prev_col0_q3 = u_deskew.col0_q3;

      // Grid: unrolled per-PE with literal indices (rather than a
      // variable-indexed loop into the g_row/g_col generate-block
      // instance array) -- same simulator-portability call made
      // elsewhere in this repo for hierarchical/array access.
      prev_pe_act[0][0] = u_grid.g_row[0].g_col[0].pe.act_out; prev_pe_psum[0][0] = u_grid.g_row[0].g_col[0].pe.psum_out;
      prev_pe_act[0][1] = u_grid.g_row[0].g_col[1].pe.act_out; prev_pe_psum[0][1] = u_grid.g_row[0].g_col[1].pe.psum_out;
      prev_pe_act[0][2] = u_grid.g_row[0].g_col[2].pe.act_out; prev_pe_psum[0][2] = u_grid.g_row[0].g_col[2].pe.psum_out;
      prev_pe_act[0][3] = u_grid.g_row[0].g_col[3].pe.act_out; prev_pe_psum[0][3] = u_grid.g_row[0].g_col[3].pe.psum_out;
      prev_pe_act[1][0] = u_grid.g_row[1].g_col[0].pe.act_out; prev_pe_psum[1][0] = u_grid.g_row[1].g_col[0].pe.psum_out;
      prev_pe_act[1][1] = u_grid.g_row[1].g_col[1].pe.act_out; prev_pe_psum[1][1] = u_grid.g_row[1].g_col[1].pe.psum_out;
      prev_pe_act[1][2] = u_grid.g_row[1].g_col[2].pe.act_out; prev_pe_psum[1][2] = u_grid.g_row[1].g_col[2].pe.psum_out;
      prev_pe_act[1][3] = u_grid.g_row[1].g_col[3].pe.act_out; prev_pe_psum[1][3] = u_grid.g_row[1].g_col[3].pe.psum_out;
      prev_pe_act[2][0] = u_grid.g_row[2].g_col[0].pe.act_out; prev_pe_psum[2][0] = u_grid.g_row[2].g_col[0].pe.psum_out;
      prev_pe_act[2][1] = u_grid.g_row[2].g_col[1].pe.act_out; prev_pe_psum[2][1] = u_grid.g_row[2].g_col[1].pe.psum_out;
      prev_pe_act[2][2] = u_grid.g_row[2].g_col[2].pe.act_out; prev_pe_psum[2][2] = u_grid.g_row[2].g_col[2].pe.psum_out;
      prev_pe_act[2][3] = u_grid.g_row[2].g_col[3].pe.act_out; prev_pe_psum[2][3] = u_grid.g_row[2].g_col[3].pe.psum_out;
      prev_pe_act[3][0] = u_grid.g_row[3].g_col[0].pe.act_out; prev_pe_psum[3][0] = u_grid.g_row[3].g_col[0].pe.psum_out;
      prev_pe_act[3][1] = u_grid.g_row[3].g_col[1].pe.act_out; prev_pe_psum[3][1] = u_grid.g_row[3].g_col[1].pe.psum_out;
      prev_pe_act[3][2] = u_grid.g_row[3].g_col[2].pe.act_out; prev_pe_psum[3][2] = u_grid.g_row[3].g_col[2].pe.psum_out;
      prev_pe_act[3][3] = u_grid.g_row[3].g_col[3].pe.act_out; prev_pe_psum[3][3] = u_grid.g_row[3].g_col[3].pe.psum_out;

      prev_active_cyc = active_cyc;
    end
  endtask

  task automatic check_frozen(input string ctx);
    begin
      if (u_skew.row1_q !== prev_row1_q) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row1_q changed (was %0h now %0h)", ctx, prev_row1_q, u_skew.row1_q); end else frozen_checks++;
      if (u_skew.row2_q1 !== prev_row2_q1) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row2_q1 changed", ctx); end else frozen_checks++;
      if (u_skew.row2_q2 !== prev_row2_q2) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row2_q2 changed", ctx); end else frozen_checks++;
      if (u_skew.row3_q1 !== prev_row3_q1) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row3_q1 changed", ctx); end else frozen_checks++;
      if (u_skew.row3_q2 !== prev_row3_q2) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row3_q2 changed", ctx); end else frozen_checks++;
      if (u_skew.row3_q3 !== prev_row3_q3) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row3_q3 changed", ctx); end else frozen_checks++;

      if (u_deskew.col2_q1 !== prev_col2_q1) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col2_q1 changed", ctx); end else frozen_checks++;
      if (u_deskew.col1_q1 !== prev_col1_q1) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col1_q1 changed", ctx); end else frozen_checks++;
      if (u_deskew.col1_q2 !== prev_col1_q2) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col1_q2 changed", ctx); end else frozen_checks++;
      if (u_deskew.col0_q1 !== prev_col0_q1) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col0_q1 changed", ctx); end else frozen_checks++;
      if (u_deskew.col0_q2 !== prev_col0_q2) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col0_q2 changed", ctx); end else frozen_checks++;
      if (u_deskew.col0_q3 !== prev_col0_q3) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col0_q3 changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[0].g_col[0].pe.act_out !== prev_pe_act[0][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[0].pe.psum_out !== prev_pe_psum[0][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[1].pe.act_out !== prev_pe_act[0][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[1].pe.psum_out !== prev_pe_psum[0][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[2].pe.act_out !== prev_pe_act[0][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[2].pe.psum_out !== prev_pe_psum[0][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[3].pe.act_out !== prev_pe_act[0][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[3].pe.psum_out !== prev_pe_psum[0][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][3].psum_out changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[1].g_col[0].pe.act_out !== prev_pe_act[1][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[0].pe.psum_out !== prev_pe_psum[1][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[1].pe.act_out !== prev_pe_act[1][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[1].pe.psum_out !== prev_pe_psum[1][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[2].pe.act_out !== prev_pe_act[1][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[2].pe.psum_out !== prev_pe_psum[1][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[3].pe.act_out !== prev_pe_act[1][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[3].pe.psum_out !== prev_pe_psum[1][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][3].psum_out changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[2].g_col[0].pe.act_out !== prev_pe_act[2][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[0].pe.psum_out !== prev_pe_psum[2][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[1].pe.act_out !== prev_pe_act[2][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[1].pe.psum_out !== prev_pe_psum[2][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[2].pe.act_out !== prev_pe_act[2][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[2].pe.psum_out !== prev_pe_psum[2][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[3].pe.act_out !== prev_pe_act[2][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[3].pe.psum_out !== prev_pe_psum[2][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][3].psum_out changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[3].g_col[0].pe.act_out !== prev_pe_act[3][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[0].pe.psum_out !== prev_pe_psum[3][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[1].pe.act_out !== prev_pe_act[3][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[1].pe.psum_out !== prev_pe_psum[3][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[2].pe.act_out !== prev_pe_act[3][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[2].pe.psum_out !== prev_pe_psum[3][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[3].pe.act_out !== prev_pe_act[3][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[3].pe.psum_out !== prev_pe_psum[3][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][3].psum_out changed", ctx); end else frozen_checks++;

      if (active_cyc !== prev_active_cyc) begin
        errors++;
        $display("FAIL FREEZE [%s]: active_cyc advanced during stall (was %0d now %0d)", ctx, prev_active_cyc, active_cyc);
      end else begin
        frozen_checks++;
      end
    end
  endtask

  // Runs one full pass of 'name' (reset -> preload -> compute), optionally
  // inserting one randomised stall of 1-5 cycles at active_cyc ==
  // trigger_active_cyc. Checks c_out against C_case[m][*] at
  // active_cyc == m+7 regardless (contract line 4, substituting
  // active_cyc for wall-clock cycle per the bookkeeping rule above).
  task automatic run_case(input string name, input string run_label,
                           input bit do_stall, input int trigger_active_cyc);
    string path;
    int active_cyc_max;
    begin
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

      $display("==== run '%s' (%s)%s ====", name, run_label,
                do_stall ? $sformatf(" stall trigger active_cyc=%0d", trigger_active_cyc) : "");

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

      // ---- Preload weights, direct per-PE forcing (unrolled, same
      // convention as tb/unpu_skew_tb.sv). ----
      array_en = 1;
      weight_in[0][0] = W_case[0][0]; weight_in[0][1] = W_case[0][1]; weight_in[0][2] = W_case[0][2]; weight_in[0][3] = W_case[0][3];
      weight_in[1][0] = W_case[1][0]; weight_in[1][1] = W_case[1][1]; weight_in[1][2] = W_case[1][2]; weight_in[1][3] = W_case[1][3];
      weight_in[2][0] = W_case[2][0]; weight_in[2][1] = W_case[2][1]; weight_in[2][2] = W_case[2][2]; weight_in[2][3] = W_case[2][3];
      weight_in[3][0] = W_case[3][0]; weight_in[3][1] = W_case[3][1]; weight_in[3][2] = W_case[3][2]; weight_in[3][3] = W_case[3][3];
      weight_load = '1; // pulse all 16 PEs simultaneously
      a_raw = '0;
      step();
      weight_load = '0;

      // ---- Compute pass, indexed by active_cyc (see header comment). ----
      active_cyc = 0;
      active_cyc_max = (case_M - 1) + 7 + 2; // margin past last readout

      while (active_cyc <= active_cyc_max) begin
        // Present A[m] while active_cyc == m; hold the last row once
        // active_cyc >= case_M.
        m_drv = (active_cyc < case_M) ? active_cyc : (case_M - 1);
        a_raw[0] = A_case[m_drv][0];
        a_raw[1] = A_case[m_drv][1];
        a_raw[2] = A_case[m_drv][2];
        a_raw[3] = A_case[m_drv][3];

        if (do_stall && active_cyc == trigger_active_cyc) begin
          stall_len = 1 + ($unsigned($random(g_seed)) % 5); // 1-5 cycles
          $display("  stalling %0d cycle(s) at active_cyc=%0d (run=%s)",
                    stall_len, active_cyc, run_label);
          for (s = 0; s < stall_len; s = s + 1) begin
            capture_snapshot();
            array_en = 0;
            a_raw    = {4{8'hA5}}; // don't-care garbage; DUT must ignore it
            step();
            check_frozen($sformatf("%s stall cyc %0d/%0d", run_label, s + 1, stall_len));
          end
          array_en = 1;
          // Restore the scheduled a_raw before resuming the real edge below.
          a_raw[0] = A_case[m_drv][0];
          a_raw[1] = A_case[m_drv][1];
          a_raw[2] = A_case[m_drv][2];
          a_raw[3] = A_case[m_drv][3];
        end

        array_en = 1;
        step(); // active edge -- array_en was 1, so active_cyc advances
        active_cyc = active_cyc + 1;

        m = active_cyc - 7;
        if (m >= 0 && m < case_M) begin
          for (j = 0; j < 4; j = j + 1) begin
            checks = checks + 1;
            if (c_out[j] !== C_case[m][j]) begin
              errors = errors + 1;
              $display("FAIL [%s/%s]: active_cyc=%0d c_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        name, run_label, active_cyc, j, m, j, C_case[m][j], c_out[j]);
            end else begin
              $display("PASS [%s/%s]: active_cyc=%0d c_out[%0d] (C[%0d][%0d]) = %0d",
                        name, run_label, active_cyc, j, m, j, c_out[j]);
            end
          end
        end
      end
    end
  endtask

  initial begin
    errors        = 0;
    checks        = 0;
    frozen_checks = 0;
    g_seed        = 32'h5EED_0005;
    $display("stall RNG seed = 32'h%08h", g_seed);

    // Baseline: no stall, re-confirms task 004's result and this tb's own
    // active_cyc bookkeeping before it's trusted for the stalled runs.
    run_case("cross_terms", "baseline", 1'b0, 0);

    // (a) Early: skew bank still filling (before active_cyc reaches 7).
    run_case("cross_terms", "early", 1'b1, 1);

    // (b) Mid: all four rows driven (m=3 enters at active_cyc==3) but none
    // has exited yet (earliest exit is active_cyc==7) -- multiple rows in
    // flight through the grid simultaneously.
    run_case("cross_terms", "mid", 1'b1, 5);

    // (c) Late: de-skew bank draining -- m=0's result is already out
    // (active_cyc==7) but m=3's (active_cyc==10) is not yet.
    run_case("cross_terms", "late", 1'b1, 8);

    $display("----------------------------------------");
    $display("checked %0d C-value(s), %0d frozen-register check(s) total", checks, frozen_checks);
    if (errors == 0 && checks == 64)
      $display("ALL CHECKS PASSED");
    else
      $display("%0d FAILURE(S) (checks=%0d, expected 64)", errors, checks);
    $display("----------------------------------------");

    $finish;
  end

endmodule
