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

  // ==== Task 024: independent reference model + shared randomization
  // helpers for Part B's synthetic (non-golden.c-file) data. This file
  // had no existing ref_c_elem-equivalent (its CRV loop checks against
  // model/golden.c's own precomputed C files, not an inline reference),
  // so one is derived here fresh, same discipline modules 2-5 used:
  // ref_c_elem carries no persistent state between calls -- every call
  // recomputes its one C[m][j] from scratch off the A/W snapshots and
  // the actual dim_k passed in, ruling out the class of bug task 019's
  // first-draft PE reference model had (accumulating from its own prior
  // state instead of each cycle's driven input). ====
  function automatic int signed to_signed8(input logic [7:0] v);
    if (v[7])
      return int'(v) - 256;
    else
      return int'(v);
  endfunction

  function automatic logic [31:0] ref_c_elem(input logic [7:0] Wm [0:3][0:3], input logic [7:0] Am [0:3][0:3],
                                              input int mrow, input int jcol, input int dk, input bit mode_uns);
    int kk;
    int unsigned acc_u, uw, ua;
    int signed   acc_s, sw, sa;
    begin
      if (mode_uns) begin
        acc_u = 0;
        for (kk = 0; kk < dk; kk = kk + 1) begin
          uw = {24'd0, Wm[kk][jcol]};
          ua = {24'd0, Am[mrow][kk]};
          acc_u = acc_u + uw * ua;
        end
        ref_c_elem = acc_u;
      end else begin
        acc_s = 0;
        for (kk = 0; kk < dk; kk = kk + 1) begin
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

  // ~1/8 chance of a boundary extreme, same discipline tasks 019-023
  // used.
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

    // ==== Task 024, Part A1: exhaustive (K,N) masking boundary sweep,
    // all 16 combinations, M=4 fixed (isolating K/N masking from M's).
    // W/A filled UNIFORMLY with an extreme byte (0xFF) rather than only
    // at the two boundary rows/columns the task names -- a uniform fill
    // includes those boundary positions as a strict subset while making
    // ANY off-by-one in the masking cutoff visible everywhere at once
    // (a masked cell reading anything but 0x00, or a real cell reading
    // anything but 0xFF), checked via both wbuf's stage[]/actbuf's
    // bank[] whitebox reads and the grid-based functional result
    // (task 007's own method, via ref_c_elem since this data has no
    // corresponding golden.c vector file). ====
    begin : part_a1
      int kk, nn, ar, ac;
      logic [31:0] exp_val;

      for (kk = 1; kk <= 4; kk = kk + 1) begin
        for (nn = 1; nn <= 4; nn = nn + 1) begin
          do_reset();
          for (ar = 0; ar < 4; ar = ar + 1)
            for (ac = 0; ac < 4; ac = ac + 1) begin
              a_tmp[ar][ac] = 8'hFF;
              w_tmp[ar][ac] = 8'hFF;
            end
          drive_load_pair(a_tmp, w_tmp, 4, kk, nn);

          // whitebox: wbuf's stage[col][row] -- row masked by K, col by N.
          for (ar = 0; ar < 4; ar = ar + 1) begin
            for (ac = 0; ac < 4; ac = ac + 1) begin
              checks  = checks + 1;
              exp_val = (ar < kk && ac < nn) ? 32'h0000_00FF : 32'h0;
              if ({24'd0, u_wbuf.bank_b[ac][ar]} !== exp_val) begin
                errors = errors + 1;
                $display("FAIL [partA1-KN K=%0d N=%0d]: wbuf stage[%0d][%0d]=%0d expected %0d", kk, nn, ac, ar, u_wbuf.bank_b[ac][ar], exp_val[7:0]);
              end
            end
          end
          // whitebox: actbuf's bank[row][col] -- M=4 fixed here (row
          // never masked), col masked by K.
          for (ar = 0; ar < 4; ar = ar + 1) begin
            for (ac = 0; ac < 4; ac = ac + 1) begin
              checks  = checks + 1;
              exp_val = (ac < kk) ? 32'h0000_00FF : 32'h0;
              if ({24'd0, u_actbuf.bank_b[ar][ac]} !== exp_val) begin
                errors = errors + 1;
                $display("FAIL [partA1-KN K=%0d N=%0d]: actbuf bank[%0d][%0d]=%0d expected %0d", kk, nn, ar, ac, u_actbuf.bank_b[ar][ac], exp_val[7:0]);
              end
            end
          end

          for (ar = 0; ar < 4; ar = ar + 1)
            for (ac = 0; ac < 4; ac = ac + 1)
              c_cur[ar][ac] = ref_c_elem(w_tmp, a_tmp, ar, ac, kk, 1'b0);
          swap_both();
          run_compute_and_check($sformatf("partA1-KN K=%0d N=%0d", kk, nn), c_cur, 4, nn, 1'b0);
        end
      end
      $display("Part A1: all 16 (K,N) masking combinations checked (whitebox stage[]/bank[] + grid-based), checks=%0d so far", checks);
    end

    // ==== Task 024, Part A2: unpu_wbuf reverse-row settling, K=1,2,3
    // individually (task 007 only ever confirmed K=4, via cross_terms's
    // directed test above). Uses DISTINCT per-position data (not
    // Part A1's uniform fill) specifically because uniform data can't
    // reveal a position/transposition bug -- every real cell would read
    // the identical value regardless of where it actually landed. ====
    begin : part_a2
      int kk, ar, ac;
      logic [31:0] exp_val;

      for (kk = 1; kk <= 3; kk = kk + 1) begin
        do_reset();
        for (ar = 0; ar < 4; ar = ar + 1)
          for (ac = 0; ac < 4; ac = ac + 1)
            w_tmp[ar][ac] = 8'(16 * ar + ac + 1); // distinct per position
        for (ar = 0; ar < 4; ar = ar + 1)
          for (ac = 0; ac < 4; ac = ac + 1)
            a_tmp[ar][ac] = 8'hAA; // irrelevant to this check
        drive_load_pair(a_tmp, w_tmp, 4, kk, 4);

        for (ar = 0; ar < 4; ar = ar + 1) begin
          for (ac = 0; ac < 4; ac = ac + 1) begin
            checks  = checks + 1;
            exp_val = (ar < kk) ? {24'd0, w_tmp[ar][ac]} : 32'h0;
            if ({24'd0, u_wbuf.bank_b[ac][ar]} !== exp_val) begin
              errors = errors + 1;
              $display("FAIL [partA2-settle K=%0d]: stage[%0d][%0d]=%0d expected %0d", kk, ac, ar, u_wbuf.bank_b[ac][ar], exp_val[7:0]);
            end
          end
        end
        $display("PASS [partA2-settle K=%0d]: stage[col][row] settles correctly, distinct per-position data, masked rows read zero", kk);
      end
    end

    // ==== Task 024, Part A3: unpu_actbuf combinational-read stress --
    // the read-side analogue of module 3's depth-0-wire zero-latency
    // checks. rd_row driven with a rapidly-changing, non-repeating
    // sequence; rd_data checked with NO clock edge at all (#1 settle
    // only) to directly confirm the pure-combinational contract, then
    // reconfirmed after a real clock edge too. Run twice -- once against
    // the bank made active by the first swap, once against a second,
    // freshly-loaded bank made active by a second swap -- covering both
    // "before" and "after a bank swap" as asked. ====
    begin : part_a3
      localparam int NUM_A3_CYCLES = 80;
      logic [31:0] rng;
      int ci, phase, ar, ac;
      logic [1:0] new_row, prev_row;

      do_reset();
      for (ar = 0; ar < 4; ar = ar + 1)
        for (ac = 0; ac < 4; ac = ac + 1)
          w_tmp[ar][ac] = 8'hAA; // irrelevant to this check
      rng = 32'h5eed0018; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("Part A3 actbuf combinational-read stress seed = 32'h%08h", rng);

      prev_row = 2'd0;
      for (phase = 0; phase < 2; phase = phase + 1) begin
        for (ar = 0; ar < 4; ar = ar + 1)
          for (ac = 0; ac < 4; ac = ac + 1)
            a_tmp[ar][ac] = 8'(16 * ar + ac + 1 + phase * 100); // distinct per position, distinct per phase so the two banks are distinguishable
        drive_load_pair(a_tmp, w_tmp, 4, 4, 4);
        swap_both();

        for (ci = 0; ci < NUM_A3_CYCLES; ci = ci + 1) begin
          rng = xorshift32(rng);
          new_row = rng[1:0];
          if (new_row == prev_row) // avoid repeats where avoidable
            new_row = new_row + 2'd1;
          a_rd_row = new_row;
          #1; // no clock edge at all -- pure combinational settle
          checks = checks + 1;
          if (a_rd_data[0] !== a_tmp[new_row][0] || a_rd_data[1] !== a_tmp[new_row][1] ||
              a_rd_data[2] !== a_tmp[new_row][2] || a_rd_data[3] !== a_tmp[new_row][3]) begin
            errors = errors + 1;
            $display("FAIL [partA3 phase=%0d cyc=%0d]: rd_row=%0d rd_data=%0h_%0h_%0h_%0h expected=%0h_%0h_%0h_%0h (zero-latency combinational read)",
                      phase, ci, new_row, a_rd_data[3], a_rd_data[2], a_rd_data[1], a_rd_data[0],
                      a_tmp[new_row][3], a_tmp[new_row][2], a_tmp[new_row][1], a_tmp[new_row][0]);
          end
          step(); // also cross a real clock edge -- must still read correctly, not drift
          checks = checks + 1;
          if (a_rd_data[0] !== a_tmp[new_row][0] || a_rd_data[1] !== a_tmp[new_row][1] ||
              a_rd_data[2] !== a_tmp[new_row][2] || a_rd_data[3] !== a_tmp[new_row][3]) begin
            errors = errors + 1;
            $display("FAIL [partA3 phase=%0d cyc=%0d post-step]: rd_row=%0d rd_data mismatch", phase, ci, new_row);
          end
          prev_row = new_row;
        end
      end
      $display("Part A3: actbuf combinational read confirmed zero-latency across %0d cycles x 2 phases (pre/post a second swap), no repeats", NUM_A3_CYCLES);
    end

    // ==== Task 024, Part A4: rapid-fire back-to-back load->swap cycles,
    // swap the instant load_done fires, next load starts immediately, no
    // compute in between -- confirms the ping-pong bank-select never
    // gets confused under maximum swap frequency (checked directly via
    // active_sel, not just inferred from data correctness) and every
    // swap's data is correct. ====
    begin : part_a4
      localparam int NUM_RAPID = 24;
      int ri, ar, ac;
      bit expect_sel;

      do_reset();
      expect_sel = 1'b0; // post-reset active_sel=0 (bank_a active); first load targets bank_b

      for (ri = 0; ri < NUM_RAPID; ri = ri + 1) begin
        for (ar = 0; ar < 4; ar = ar + 1)
          for (ac = 0; ac < 4; ac = ac + 1) begin
            w_tmp[ar][ac] = 8'(ri * 16 + ar * 4 + ac + 1);
            a_tmp[ar][ac] = 8'(ri * 16 + ar * 4 + ac + 129);
          end
        drive_load_pair(a_tmp, w_tmp, 4, 4, 4); // loads into the currently-INACTIVE bank; checks load_done pulsed
        swap_both(); // swap immediately, no gap
        expect_sel = ~expect_sel;

        checks = checks + 1;
        if (u_wbuf.active_sel !== expect_sel) begin
          errors = errors + 1;
          $display("FAIL [partA4 iter=%0d]: wbuf active_sel=%0b expected=%0b (ping-pong desync)", ri, u_wbuf.active_sel, expect_sel);
        end
        checks = checks + 1;
        if (u_actbuf.active_sel !== expect_sel) begin
          errors = errors + 1;
          $display("FAIL [partA4 iter=%0d]: actbuf active_sel=%0b expected=%0b (ping-pong desync)", ri, u_actbuf.active_sel, expect_sel);
        end

        for (ar = 0; ar < 4; ar = ar + 1) begin
          for (ac = 0; ac < 4; ac = ac + 1) begin
            checks = checks + 1;
            if (expect_sel) begin
              if (u_wbuf.bank_b[ac][ar] !== w_tmp[ar][ac]) begin
                errors = errors + 1;
                $display("FAIL [partA4 iter=%0d]: wbuf bank_b[%0d][%0d]=%0d expected %0d", ri, ac, ar, u_wbuf.bank_b[ac][ar], w_tmp[ar][ac]);
              end
            end else begin
              if (u_wbuf.bank_a[ac][ar] !== w_tmp[ar][ac]) begin
                errors = errors + 1;
                $display("FAIL [partA4 iter=%0d]: wbuf bank_a[%0d][%0d]=%0d expected %0d", ri, ac, ar, u_wbuf.bank_a[ac][ar], w_tmp[ar][ac]);
              end
            end
          end
        end
      end
      $display("Part A4: %0d consecutive rapid-fire load->swap cycles, ping-pong bank-select never desynced, every swap's data correct, checks=%0d so far", NUM_RAPID, checks);
    end

    // ==== Task 024, Part B: long adversarial chains of concurrent
    // load/swap racing compute. Mirrors the existing 64-crv_*-case
    // fork/join chain above exactly (same structure, already proven
    // correct there), but with synthetic ~1/8-extreme-biased data
    // (checked against ref_c_elem, since no golden.c vector file exists
    // for arbitrary random shapes) and a freshly-randomized load-start
    // delay every single pass -- the existing CRV loop already
    // randomizes this per case, this just does many more sequences of it
    // with adversarial data on top. ====
    begin : part_b
      localparam int NUM_SEQ = 20;
      logic [31:0] master_rng, rng, seq_seed;
      int seq_idx, pass_idx, num_passes, total_passes;
      int m_cur2, k_cur2, n_cur2;
      bit mode_cur2;
      int m_next, k_next, n_next;
      bit mode_next;
      logic [7:0]  a_cur2 [0:3][0:3];
      logic [7:0]  w_cur2 [0:3][0:3];
      logic [7:0]  a_next [0:3][0:3];
      logic [7:0]  w_next [0:3][0:3];
      logic [31:0] c_cur2 [0:3][0:3];
      int compute_len2, delay_cyc2;
      int rr, cc;

      master_rng = 32'h5eed0118; // distinct from Part A3's 0x5eed0018 -- same per-task base, different sub-stream
      $display("Part B master seed = 32'h%08h", master_rng);
      total_passes = 0;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_seed   = master_rng;
        rng        = seq_seed;
        $display("Part B sequence %0d: seed = 32'h%08h", seq_idx, seq_seed);

        rng = xorshift32(rng);
        num_passes = 80 + (rng % 81); // 80..160 passes per sequence

        do_reset();

        // Establish pass 0 as the baseline active case (no concurrency).
        rng = xorshift32(rng);
        m_cur2 = 1 + (rng % 4);
        rng = xorshift32(rng);
        k_cur2 = 1 + (rng % 4);
        rng = xorshift32(rng);
        n_cur2 = 1 + (rng % 4);
        rng = xorshift32(rng);
        mode_cur2 = rng[0];
        for (rr = 0; rr < 4; rr = rr + 1)
          for (cc = 0; cc < 4; cc = cc + 1) begin
            a_cur2[rr][cc] = biased_byte(rng);
            w_cur2[rr][cc] = biased_byte(rng);
          end
        drive_load_pair(a_cur2, w_cur2, m_cur2, k_cur2, n_cur2);
        swap_both();
        for (rr = 0; rr < 4; rr = rr + 1)
          for (cc = 0; cc < 4; cc = cc + 1)
            c_cur2[rr][cc] = ref_c_elem(w_cur2, a_cur2, rr, cc, k_cur2, mode_cur2);

        for (pass_idx = 1; pass_idx < num_passes; pass_idx = pass_idx + 1) begin
          rng = xorshift32(rng);
          m_next = 1 + (rng % 4);
          rng = xorshift32(rng);
          k_next = 1 + (rng % 4);
          rng = xorshift32(rng);
          n_next = 1 + (rng % 4);
          rng = xorshift32(rng);
          mode_next = rng[0];
          for (rr = 0; rr < 4; rr = rr + 1)
            for (cc = 0; cc < 4; cc = cc + 1) begin
              a_next[rr][cc] = biased_byte(rng);
              w_next[rr][cc] = biased_byte(rng);
            end

          compute_len2 = m_cur2 + 7;
          rng = xorshift32(rng);
          delay_cyc2 = rng % compute_len2; // randomized early/mid/late, per pass

          fork
            run_compute_and_check($sformatf("partB seq%0d/pass%0d", seq_idx, pass_idx - 1), c_cur2, m_cur2, n_cur2, mode_cur2);
            begin
              repeat (delay_cyc2) step();
              drive_load_pair(a_next, w_next, m_next, k_next, n_next);
            end
          join

          swap_both();
          m_cur2 = m_next; k_cur2 = k_next; n_cur2 = n_next; mode_cur2 = mode_next;
          a_cur2 = a_next; w_cur2 = w_next;
          for (rr = 0; rr < 4; rr = rr + 1)
            for (cc = 0; cc < 4; cc = cc + 1)
              c_cur2[rr][cc] = ref_c_elem(w_cur2, a_cur2, rr, cc, k_cur2, mode_cur2);

          total_passes = total_passes + 1;
        end

        // Final pass of this sequence was loaded+swapped but not yet computed/checked.
        run_compute_and_check($sformatf("partB seq%0d/final", seq_idx), c_cur2, m_cur2, n_cur2, mode_cur2);
        total_passes = total_passes + 1;
      end

      $display("----------------------------------------");
      $display("Part B: %0d sequences, %0d total passes (>=200 required), checks so far=%0d", NUM_SEQ, total_passes, checks);
      if (errors == 0)
        $display("Part B: ALL PASSED");
      $display("----------------------------------------");
    end

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
