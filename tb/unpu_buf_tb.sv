// Integration test for unpu_wbuf + unpu_actbuf, driving the real
// skew -> grid -> de-skew datapath (same chaining style as
// tb/unpu_skew_tb.sv / tb/unpu_seq_tb.sv). This testbench plays the role
// unpu_seq will eventually play -- driving load_start/load_row/swap by
// hand -- since task 007 doesn't touch unpu_seq (it doesn't know these
// buffers' load/swap protocol yet).
//
// The property this file exists to prove is double buffering itself: a
// background unpu_wbuf/unpu_actbuf load into the INACTIVE banks must run
// to completion, and swap must be able to fire, while the grid is
// mid-compute against the ACTIVE banks with array_en high throughout.
// The concurrent-load tests below use `fork...join` specifically so the
// compute-and-check branch and the background-load branch run as truly
// independent processes advancing on the same clock -- a sequential
// load-then-compute test would pass even with a broken single-bank
// implementation that just happens to work when nothing overlaps.
//
// Test vectors come from the golden model (model/golden.c, task 006 Part
// A) -- no new golden-model work for this task, per the task file.
//
// Simulated with Verilator (--binary --timing) -- iverilog is still not
// installed in this environment (no root to apt-get install it); see
// docs/planning/plan.md's "Tooling note" for the open, non-blocking
// decision on standardizing across the project.
`timescale 1ns/1ps

module unpu_buf_tb;

  logic clk;
  logic rst_n;
  logic array_en;
  logic grid_mode_unsigned;

  // ---- unpu_wbuf ----
  logic                  w_load_start;
  logic [2:0]            w_load_k, w_load_n;
  logic [3:0][7:0]       w_load_row;
  logic                  w_load_busy, w_load_done;
  logic                  w_swap;
  logic [3:0][3:0]       w_weight_load;
  logic [3:0][3:0][7:0]  w_weight_in;

  // ---- unpu_actbuf ----
  logic                  a_load_start;
  logic [2:0]            a_load_m, a_load_k;
  logic [3:0][7:0]       a_load_row;
  logic                  a_load_busy, a_load_done;
  logic                  a_swap;
  logic [1:0]            a_rd_row;
  logic [3:0][7:0]       a_rd_data;

  // ---- Datapath chain ----
  logic [3:0][7:0]  skew_a_raw;
  logic [3:0][7:0]  skew_act_out;
  logic [3:0][31:0] grid_psum_in; // tied 0, no accumulation across passes
  logic [3:0][7:0]  grid_act_out; // unused
  logic [3:0][31:0] grid_psum_out;
  logic [3:0][31:0] deskew_c_out;

  assign grid_psum_in = '0;

  // Compute-side mux: while streaming a matmul, feed actbuf's live
  // (combinational) read of the ACTIVE bank; otherwise 0. Mirrors
  // unpu_seq's own `a_raw <= cycle<m_lat ? a_src[cycle] : '0` mux, here
  // reading through unpu_actbuf instead of a direct a_src array.
  logic use_actbuf;
  assign skew_a_raw = use_actbuf ? a_rd_data : '0;

  unpu_wbuf u_wbuf (
    .clk         (clk),
    .rst_n       (rst_n),
    .array_en    (array_en),
    .load_start  (w_load_start),
    .load_k      (w_load_k),
    .load_n      (w_load_n),
    .load_row    (w_load_row),
    .load_busy   (w_load_busy),
    .load_done   (w_load_done),
    .swap        (w_swap),
    .weight_load (w_weight_load),
    .weight_in   (w_weight_in)
  );

  unpu_actbuf u_actbuf (
    .clk        (clk),
    .rst_n      (rst_n),
    .array_en   (array_en),
    .load_start (a_load_start),
    .load_m     (a_load_m),
    .load_k     (a_load_k),
    .load_row   (a_load_row),
    .load_busy  (a_load_busy),
    .load_done  (a_load_done),
    .swap       (a_swap),
    .rd_row     (a_rd_row),
    .rd_data    (a_rd_data)
  );

  unpu_skew u_skew (
    .clk      (clk),
    .rst_n    (rst_n),
    .array_en (array_en),
    .a_raw    (skew_a_raw),
    .act_out  (skew_act_out)
  );

  unpu_grid u_grid (
    .clk           (clk),
    .rst_n         (rst_n),
    .array_en      (array_en),
    .mode_unsigned (grid_mode_unsigned),
    .weight_load   (w_weight_load),
    .weight_in     (w_weight_in),
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
    #1;
  endtask

  int errors;
  int checks;

  task automatic do_reset;
    begin
      rst_n              = 0;
      array_en           = 0;
      grid_mode_unsigned = 1'b0;
      w_load_start = 0; w_load_k = 0; w_load_n = 0; w_load_row = '0; w_swap = 0;
      a_load_start = 0; a_load_m = 0; a_load_k = 0; a_load_row = '0; a_swap = 0;
      a_rd_row = 0;
      use_actbuf = 1'b0;
      step();
      step();
      rst_n    = 1;
      array_en = 1;
      step();
    end
  endtask

  // ---- Vector loading: reads <name>_{a,w,c}.hex into caller-provided
  // arrays. Pure file I/O, zero sim-time -- safe to call synchronously
  // before a fork, no race with a concurrently-running compute branch. ----
  task automatic load_case_files(input string name,
                                  output logic [7:0]  a_arr [0:3][0:3],
                                  output logic [7:0]  w_arr [0:3][0:3],
                                  output logic [31:0] c_arr [0:3][0:3]);
    begin
      $readmemh({"model/vectors/", name, "_a.hex"}, a_arr);
      $readmemh({"model/vectors/", name, "_w.hex"}, w_arr);
      $readmemh({"model/vectors/", name, "_c.hex"}, c_arr);
    end
  endtask

  // ---- Drives the 4-cycle hardware load of both buffers from the given
  // A/W arrays -- wbuf in reverse row order (3,2,1,0), actbuf in natural
  // order (0,1,2,3), same cycle indices for both. Does NOT swap. ----
  task automatic drive_load_pair(input logic [7:0] a_arr [0:3][0:3],
                                  input logic [7:0] w_arr [0:3][0:3],
                                  input int drv_m, input int drv_k, input int drv_n);
    int i;
    begin
      w_load_k = drv_k[2:0];
      w_load_n = drv_n[2:0];
      a_load_m = drv_m[2:0];
      a_load_k = drv_k[2:0];

      for (i = 0; i < 4; i = i + 1) begin
        w_load_start = (i == 0);
        a_load_start = (i == 0);
        w_load_row[0] = w_arr[3 - i][0]; w_load_row[1] = w_arr[3 - i][1];
        w_load_row[2] = w_arr[3 - i][2]; w_load_row[3] = w_arr[3 - i][3];
        a_load_row[0] = a_arr[i][0]; a_load_row[1] = a_arr[i][1];
        a_load_row[2] = a_arr[i][2]; a_load_row[3] = a_arr[i][3];
        step();
      end
      w_load_start = 0;
      a_load_start = 0;

      checks = checks + 1;
      if (w_load_done !== 1'b1 || a_load_done !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL: load_done not pulsing after 4th row (w=%0b a=%0b)", w_load_done, a_load_done);
      end
    end
  endtask

  task automatic swap_both;
    begin
      w_swap = 1;
      a_swap = 1;
      step();
      w_swap = 0;
      a_swap = 0;
    end
  endtask

  // ---- Runs one matmul against whichever bank is currently ACTIVE and
  // checks deskew_c_out against c_arr over the true drv_m x drv_n
  // submatrix. Loop structure/cycle-index convention matches
  // tb/unpu_skew_tb.sv exactly (cyc=0 is the first injection edge,
  // checks fire at m=cyc-6 after step()) -- proven correct there, only
  // the activation source changed (actbuf's live read instead of a
  // direct a_src array). ----
  task automatic run_compute_and_check(input string name,
                                        input logic [31:0] c_arr [0:3][0:3],
                                        input int drv_m, input int drv_n,
                                        input bit drv_mode_u);
    int cyc, cyc_max, m, j;
    begin
      grid_mode_unsigned = drv_mode_u;
      cyc_max = (drv_m - 1) + 6 + 2;
      for (cyc = 0; cyc <= cyc_max; cyc = cyc + 1) begin
        use_actbuf = (cyc < drv_m);
        a_rd_row   = cyc[1:0];
        step();

        m = cyc - 6;
        if (m >= 0 && m < drv_m) begin
          for (j = 0; j < drv_n; j = j + 1) begin
            checks = checks + 1;
            if (deskew_c_out[j] !== c_arr[m][j]) begin
              errors = errors + 1;
              $display("FAIL [%s]: cycle=%0d c_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        name, cyc, j, m, j, c_arr[m][j], deskew_c_out[j]);
            end else begin
              $display("PASS [%s]: cycle=%0d c_out[%0d] (C[%0d][%0d]) = %0d",
                        name, cyc, j, m, j, deskew_c_out[j]);
            end
          end
        end
      end
      use_actbuf = 1'b0;
    end
  endtask

  // Convenience: load, whitebox-check (optional), swap -- used to
  // establish the very first active case with no concurrency involved.
  logic [7:0]  a_tmp [0:3][0:3];
  logic [7:0]  w_tmp [0:3][0:3];
  logic [31:0] c_tmp [0:3][0:3];

  task automatic load_and_swap(input string name, input int drv_m, input int drv_k, input int drv_n,
                                output logic [31:0] c_out_arr [0:3][0:3]);
    begin
      load_case_files(name, a_tmp, w_tmp, c_tmp);
      drive_load_pair(a_tmp, w_tmp, drv_m, drv_k, drv_n);
      c_out_arr = c_tmp;
      swap_both();
    end
  endtask

  logic [31:0] c_cur [0:3][0:3];

  // ==== CRV bookkeeping ====
  int i, r, c;
  int meta_m, meta_k, meta_n;
  int fd, scan_rc;
  string mode_str;
  string crv_name;

  logic [7:0]  crv_a [0:63][0:3][0:3];
  logic [7:0]  crv_w [0:63][0:3][0:3];
  logic [31:0] crv_c [0:63][0:3][0:3];
  int          crv_m_arr [0:63];
  int          crv_k_arr [0:63];
  int          crv_n_arr [0:63];
  bit          crv_mode_arr [0:63];

  int m_cur, n_cur;
  bit mode_cur;
  int m_ld, k_ld, n_ld;
  bit mode_ld;
  int delay_cyc;
  int compute_len;
  logic [31:0] swap_seed;

  initial begin
    errors = 0;
    checks = 0;

    // ==== Directed: cross_terms through both buffers, plus the
    // whitebox settling assertion (required, in addition to the
    // end-to-end check below). At this point active_sel is still at its
    // reset default (0, bank_a active), so the bank that JUST got loaded
    // is bank_b -- checked directly against W_case[row][col] per the
    // task's own indexing (stage[col][row]). ====
    do_reset();
    load_case_files("cross_terms", a_tmp, w_tmp, c_tmp);
    drive_load_pair(a_tmp, w_tmp, 4, 4, 4);

    for (r = 0; r < 4; r = r + 1) begin
      for (c = 0; c < 4; c = c + 1) begin
        checks = checks + 1;
        if (u_wbuf.bank_b[c][r] !== w_tmp[r][c]) begin
          errors = errors + 1;
          $display("FAIL [whitebox cross_terms]: stage[%0d][%0d]=%0d expected W[%0d][%0d]=%0d",
                    c, r, u_wbuf.bank_b[c][r], r, c, w_tmp[r][c]);
        end
      end
    end
    $display("whitebox settling check: stage[col][row] == W[row][col] for all 16 positions checked");

    c_cur = c_tmp;
    swap_both();
    run_compute_and_check("cross_terms", c_cur, 4, 4, 1'b0);

    // ==== Directed: K/N/M masking through both buffers ====
    load_and_swap("seq_k1", 4, 1, 4, c_cur);
    run_compute_and_check("seq_k1", c_cur, 4, 4, 1'b0);

    load_and_swap("seq_n1", 4, 4, 1, c_cur);
    run_compute_and_check("seq_n1", c_cur, 4, 1, 1'b0);

    load_and_swap("seq_mixed", 3, 2, 3, c_cur);
    run_compute_and_check("seq_mixed", c_cur, 3, 3, 1'b0);

    // ==== Directed: concurrent-load-during-compute -- the double-
    // buffering property itself. Bank A (cross_terms) active; while its
    // matmul streams, a background load of a DIFFERENT case
    // (seq_mixed) runs into the inactive banks, array_en=1 throughout.
    // (a) the in-flight matmul must still produce cross_terms_c.hex
    // exactly; (b) only after that, swap and confirm the new banks
    // (seq_mixed) took effect. ====
    load_and_swap("cross_terms", 4, 4, 4, c_cur);

    load_case_files("seq_mixed", a_tmp, w_tmp, c_tmp);
    fork
      run_compute_and_check("cross_terms (concurrent load in flight)", c_cur, 4, 4, 1'b0);
      begin
        repeat (2) step(); // early/mid within cross_terms's 11-cycle compute window
        drive_load_pair(a_tmp, w_tmp, 3, 2, 3);
      end
    join

    c_cur = c_tmp;
    swap_both();
    run_compute_and_check("seq_mixed (post-concurrent-load swap)", c_cur, 3, 3, 1'b0);

    // ==== CRV: chain all 64 crv_* cases back-to-back. Case i's
    // background load runs concurrently with case i-1's compute, with
    // the load-start point randomized (early/mid/late) relative to
    // case i-1's compute-stream length. Reads ALL case files up front
    // (pure, zero-sim-time I/O) so the fork's two branches never race on
    // shared file-scratch storage -- each branch only ever touches
    // crv_*[i]/crv_*[i-1]'s own slot. ====
    swap_seed = 32'h5eed0006; // reused from task 006; only used here to pick swap timing, independent of golden.c's own draw
    $display("CRV swap-timing seed = 32'h%08h (reusing task 006's base seed)", swap_seed);

    for (i = 0; i < 64; i = i + 1) begin
      crv_name = $sformatf("crv_%04d", i);
      fd = $fopen({"model/vectors/", crv_name, "_meta.txt"}, "r");
      if (fd == 0)
        $fatal(1, "could not open model/vectors/%s_meta.txt -- run model/golden first", crv_name);
      scan_rc = $fscanf(fd, "M=%d\nMODE=%s\nK=%d\nN=%d\n", meta_m, mode_str, meta_k, meta_n);
      $fclose(fd);
      if (scan_rc != 4)
        $fatal(1, "could not parse model/vectors/%s_meta.txt (got %0d fields)", crv_name, scan_rc);

      // $readmemh needs a plain variable target, not a computed slice of
      // a larger array -- route through the a_tmp/w_tmp/c_tmp scratch
      // (already used by load_case_files) and copy into this index.
      $readmemh({"model/vectors/", crv_name, "_a.hex"}, a_tmp);
      $readmemh({"model/vectors/", crv_name, "_w.hex"}, w_tmp);
      $readmemh({"model/vectors/", crv_name, "_c.hex"}, c_tmp);
      crv_a[i] = a_tmp;
      crv_w[i] = w_tmp;
      crv_c[i] = c_tmp;
      crv_m_arr[i]    = meta_m;
      crv_k_arr[i]    = meta_k;
      crv_n_arr[i]    = meta_n;
      crv_mode_arr[i] = (mode_str == "UNSIGNED");
    end

    // Establish case 0 as the baseline active case (no concurrency).
    load_and_swap("crv_0000", crv_m_arr[0], crv_k_arr[0], crv_n_arr[0], c_cur);
    m_cur = crv_m_arr[0]; n_cur = crv_n_arr[0]; mode_cur = crv_mode_arr[0];

    for (i = 1; i < 64; i = i + 1) begin
      m_ld = crv_m_arr[i]; k_ld = crv_k_arr[i]; n_ld = crv_n_arr[i]; mode_ld = crv_mode_arr[i];
      compute_len  = m_cur + 7;
      swap_seed    = swap_seed ^ (swap_seed << 13);
      swap_seed    = swap_seed ^ (swap_seed >> 17);
      swap_seed    = swap_seed ^ (swap_seed << 5);
      delay_cyc    = swap_seed % compute_len; // early/mid/late within [0, compute_len-1]

      fork
        run_compute_and_check($sformatf("crv_%04d (chained)", i - 1), c_cur, m_cur, n_cur, mode_cur);
        begin
          repeat (delay_cyc) step();
          drive_load_pair(crv_a[i], crv_w[i], m_ld, k_ld, n_ld);
        end
      join

      c_cur    = crv_c[i];
      m_cur    = m_ld;
      n_cur    = n_ld;
      mode_cur = mode_ld;
      swap_both();
    end

    // Final case (63) was loaded+swapped in but not yet computed/checked.
    run_compute_and_check("crv_0063 (final)", c_cur, m_cur, n_cur, mode_cur);

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
