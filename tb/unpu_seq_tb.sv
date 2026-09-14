// Full-stack integration test for the revised unpu_seq (task 011):
// unpu_seq + unpu_dma + unpu_wbuf + unpu_actbuf + unpu_skew + unpu_grid +
// unpu_deskew + a behavioral SRAM model (same design as task 008's,
// including randomized per-beat back-pressure). The new FSM states only
// mean something wired to what they orchestrate, so this is
// deliberately a bigger lift than task 006's original testbench -- the
// point of this task is proving the orchestration works end to end
// (DMA fetch -> buffer swap -> compute -> DMA writeback), not
// re-proving the compute core (already proven in tasks 003-006).
//
// unpu_seq is driven directly with start/dim_*/mode_unsigned/src_a/
// src_b/dest_c -- no CSR/native-slave yet (that's task 012/step 14).
//
// Test vectors come from the golden model (model/golden.c, task 006 Part
// A) -- no new golden-model work for this task.
//
// Loop-structure note (task 008's lesson, carried forward): every "wait
// for done" loop is a bounded `for` with an explicit cap, and takes one
// extra settle cycle after observing `done` before the caller may issue
// the next `start` -- DONE only transitions to IDLE the cycle AFTER
// done=1 is observed, and start is sampled only in IDLE/ERROR, so
// issuing it one cycle early (still in DONE) would be silently dropped,
// looking exactly like a hang. This is the same bug class task 008 hit
// with unpu_dma's D_FIN -> D_IDLE settle.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006-010 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
`timescale 1ns/1ps

module unpu_seq_tb;

  logic clk, rst_n;

  // ---- unpu_seq ----
  logic                  start;
  logic [2:0]            dim_m, dim_n, dim_k;
  logic                  mode_unsigned;
  logic [31:0]           src_a, src_b, dest_c;
  logic [3:0][3:0][31:0] c_dst;
  logic                  done, busy, error;
  logic [2:0]            error_code;
  logic                  array_en;
  logic                  mode_unsigned_o;
  logic                  job_start;
  logic [1:0]            job_kind;
  logic [31:0]           job_base_addr;
  logic [2:0]            job_m, job_n, job_k;
  logic                  job_done;
  logic                  w_swap, a_swap;
  logic [1:0]            rd_row;
  logic [3:0][31:0]      c_in;

  // ---- unpu_dma ----
  logic [31:0] dma_addr, dma_wdata, dma_rdata;
  logic [3:0]  dma_wstrb;
  logic        dma_valid, dma_ready;
  logic        job_busy; // unused by unpu_seq, just needs a net
  logic                 a_load_start;
  logic [2:0]           a_load_m, a_load_k;
  logic [3:0][7:0]      a_load_row;
  logic                 w_load_start;
  logic [2:0]           w_load_k, w_load_n;
  logic [3:0][7:0]      w_load_row;

  // ---- unpu_wbuf / unpu_actbuf extra ----
  logic                  a_load_busy, a_load_done, w_load_busy, w_load_done;
  logic [3:0][7:0]       a_rd_data;
  logic [3:0][3:0]       w_weight_load;
  logic [3:0][3:0][7:0]  w_weight_in;

  // ---- datapath chain ----
  logic [3:0][7:0]  skew_act_out;
  logic [3:0][31:0] grid_psum_in;
  logic [3:0][7:0]  grid_act_out;
  logic [3:0][31:0] grid_psum_out;
  logic [3:0][31:0] deskew_c_out;

  assign grid_psum_in = '0;
  assign c_in          = deskew_c_out;

  localparam logic [1:0] JOB_FETCH_A = 2'd0;
  localparam logic [1:0] JOB_FETCH_W = 2'd1;
  localparam logic [1:0] JOB_WRITE_C = 2'd2;

  unpu_seq u_seq (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (start),
    .dim_m           (dim_m),
    .dim_n           (dim_n),
    .dim_k           (dim_k),
    .mode_unsigned   (mode_unsigned),
    .src_a           (src_a),
    .src_b           (src_b),
    .dest_c          (dest_c),
    .c_dst           (c_dst),
    .done            (done),
    .busy            (busy),
    .error           (error),
    .error_code      (error_code),
    .array_en        (array_en),
    .mode_unsigned_o (mode_unsigned_o),
    .job_start       (job_start),
    .job_kind        (job_kind),
    .job_base_addr   (job_base_addr),
    .job_m           (job_m),
    .job_n           (job_n),
    .job_k           (job_k),
    .job_done        (job_done),
    .w_swap          (w_swap),
    .a_swap          (a_swap),
    .rd_row          (rd_row),
    .c_in            (c_in)
  );

  unpu_dma u_dma (
    .clk           (clk),
    .rst_n         (rst_n),
    .dma_addr      (dma_addr),
    .dma_wdata     (dma_wdata),
    .dma_rdata     (dma_rdata),
    .dma_wstrb     (dma_wstrb),
    .dma_valid     (dma_valid),
    .dma_ready     (dma_ready),
    .job_start     (job_start),
    .job_kind      (job_kind),
    .job_base_addr (job_base_addr),
    .job_m         (job_m),
    .job_n         (job_n),
    .job_k         (job_k),
    .job_busy      (job_busy),
    .job_done      (job_done),
    .a_load_start  (a_load_start),
    .a_load_m      (a_load_m),
    .a_load_k      (a_load_k),
    .a_load_row    (a_load_row),
    .w_load_start  (w_load_start),
    .w_load_k      (w_load_k),
    .w_load_n      (w_load_n),
    .w_load_row    (w_load_row),
    .c_src         (c_dst)
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
    .rd_row     (rd_row),
    .rd_data    (a_rd_data)
  );

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

  unpu_skew u_skew (
    .clk      (clk),
    .rst_n    (rst_n),
    .array_en (array_en),
    .a_raw    (a_rd_data),
    .act_out  (skew_act_out)
  );

  unpu_grid u_grid (
    .clk           (clk),
    .rst_n         (rst_n),
    .array_en      (array_en),
    .mode_unsigned (mode_unsigned_o),
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

  // ---- Behavioral SRAM model, same design as task 008's: word-
  // addressable, combinational read, randomized 0-5 cycle per-beat
  // back-pressure via a same-cycle-lookahead draw (unpu_wbuf's
  // effective_sel idiom, task 007) so a delay of 0 can still grant on
  // the very first cycle a request appears. ----
  localparam int MEM_WORDS = 65536;
  logic [31:0] mem [0:MEM_WORDS-1];
  assign dma_rdata = mem[dma_addr[17:2]]; // 16-bit word index, covers MEM_WORDS=65536

  always_ff @(posedge clk) begin
    if (dma_valid && dma_ready && dma_wstrb == 4'hF)
      mem[dma_addr[17:2]] <= dma_wdata;
  end

  logic [31:0] bp_rng;
  logic [2:0]  bp_delay_reg;
  logic        bp_have_delay;
  logic [2:0]  bp_delay_eff;

  function automatic logic [31:0] xorshift32(logic [31:0] x);
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    return x;
  endfunction

  assign bp_delay_eff = bp_have_delay ? bp_delay_reg : (bp_rng[2:0] < 3'd6 ? bp_rng[2:0] : 3'd5);
  assign dma_ready     = dma_valid && (bp_delay_eff == 3'd0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bp_rng        <= 32'h5eed000b;
      bp_delay_reg  <= 3'd0;
      bp_have_delay <= 1'b0;
    end else if (!dma_valid) begin
      bp_have_delay <= 1'b0;
    end else if (!bp_have_delay) begin
      bp_have_delay <= 1'b1;
      bp_delay_reg  <= (bp_delay_eff == 3'd0) ? 3'd0 : (bp_delay_eff - 3'd1);
      bp_rng        <= xorshift32(bp_rng);
    end else if (bp_delay_reg != 3'd0) begin
      bp_delay_reg <= bp_delay_reg - 3'd1;
    end
  end

  int errors, checks;

  task automatic do_reset;
    int i;
    begin
      rst_n = 0;
      start = 0; dim_m = 0; dim_n = 0; dim_k = 0; mode_unsigned = 0;
      src_a = 0; src_b = 0; dest_c = 0;
      bp_rng = 32'h5eed000b;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  // ---- Loads <name>_{a,w,c}.hex (4x4-shaped, task 006 Part A format)
  // and packs A/W rows into mem at the given byte base addresses --
  // identical convention to tb/unpu_dma_tb.sv (task 008). ----
  logic [7:0]  a_case [0:3][0:3];
  logic [7:0]  w_case [0:3][0:3];
  logic [31:0] c_case [0:3][0:3];

  task automatic preload_case(input string name, input logic [31:0] base_a, input logic [31:0] base_w);
    int r;
    begin
      $readmemh({"model/vectors/", name, "_a.hex"}, a_case);
      $readmemh({"model/vectors/", name, "_w.hex"}, w_case);
      $readmemh({"model/vectors/", name, "_c.hex"}, c_case);
      for (r = 0; r < 4; r = r + 1) begin
        mem[(base_a >> 2) + r] = {a_case[r][3], a_case[r][2], a_case[r][1], a_case[r][0]};
        mem[(base_w >> 2) + r] = {w_case[r][3], w_case[r][2], w_case[r][1], w_case[r][0]};
      end
    end
  endtask

  // Runs one full op through unpu_seq (start -> ... -> done), bounded,
  // taking one extra settle cycle past `done` before returning so a
  // caller can immediately issue the next `start` without it being
  // dropped (DONE -> IDLE settle, see file header).
  int job_start_count;

  task automatic run_op(input string label, input int drv_m, input int drv_k, input int drv_n,
                         input bit drv_mode_u, input logic [31:0] a_addr, input logic [31:0] b_addr,
                         input logic [31:0] c_addr, output bit ok);
    int cyc;
    bit seen;
    begin
      dim_m = drv_m[2:0]; dim_k = drv_k[2:0]; dim_n = drv_n[2:0]; mode_unsigned = drv_mode_u;
      src_a = a_addr; src_b = b_addr; dest_c = c_addr;
      job_start_count = 0;
      start = 1;
      step();
      start = 0;
      if (job_start) job_start_count = job_start_count + 1;

      seen = 1'b0;
      for (cyc = 0; cyc < 4000; cyc = cyc + 1) begin
        step();
        if (job_start) job_start_count = job_start_count + 1;
        if (done) begin
          seen = 1'b1;
          step(); // let DONE -> IDLE settle before the caller issues another start
          break;
        end
      end
      ok = seen;
      checks = checks + 1;
      if (!seen) begin
        errors = errors + 1;
        $display("FAIL [%s]: done never observed within 4000 cycles", label);
      end
    end
  endtask

  task automatic check_writeback(input string label, input logic [31:0] c_addr, input int drv_m, input int drv_n);
    int m, j;
    begin
      for (m = 0; m < drv_m; m = m + 1) begin
        for (j = 0; j < drv_n; j = j + 1) begin
          checks = checks + 1;
          if (mem[(c_addr >> 2) + m * 4 + j] !== c_case[m][j]) begin
            errors = errors + 1;
            $display("FAIL [%s]: mem C[%0d][%0d]=%0d expected %0d", label, m, j, mem[(c_addr >> 2) + m * 4 + j], c_case[m][j]);
          end
        end
      end
    end
  endtask

  int i, r, c;
  int meta_m, meta_k, meta_n;
  int fd, scan_rc;
  string mode_str;
  string crv_name;
  logic [31:0] base_a, base_w, base_c;
  bit ok;

  initial begin
    errors = 0;
    checks = 0;

    // ==== Directed: cross_terms end to end -- the primary regression
    // anchor (DMA fetch -> buffer swap -> compute -> DMA writeback, for
    // the first time all wired together for real). ====
    do_reset();
    preload_case("cross_terms", 32'h0000_1000, 32'h0000_1100);
    run_op("cross_terms", 4, 4, 4, 1'b0, 32'h0000_1000, 32'h0000_1100, 32'h0000_1200, ok);
    check_writeback("cross_terms", 32'h0000_1200, 4, 4);

    // ---- job_start re-pulse boundary (known trap): exactly 3 pulses
    // per op (one each for W_FETCH/A_FETCH/WRITE_OUTPUT), even with the
    // back-pressure model's randomized multi-cycle waits already active
    // above. ----
    checks = checks + 1;
    if (job_start_count !== 3) begin
      errors = errors + 1;
      $display("FAIL [job_start boundary]: expected exactly 3 pulses (W_FETCH/A_FETCH/WRITE_OUTPUT), got %0d", job_start_count);
    end else begin
      $display("PASS [job_start boundary]: exactly 3 job_start pulses observed for one op");
    end

    // ==== Directed: seq_m1/seq_k1/seq_n1/seq_mixed end to end ====
    do_reset();
    preload_case("seq_m1", 32'h0000_2000, 32'h0000_2100);
    run_op("seq_m1", 1, 4, 4, 1'b0, 32'h0000_2000, 32'h0000_2100, 32'h0000_2200, ok);
    check_writeback("seq_m1", 32'h0000_2200, 1, 4);

    do_reset();
    preload_case("seq_k1", 32'h0000_3000, 32'h0000_3100);
    run_op("seq_k1", 4, 1, 4, 1'b0, 32'h0000_3000, 32'h0000_3100, 32'h0000_3200, ok);
    check_writeback("seq_k1", 32'h0000_3200, 4, 4);

    do_reset();
    preload_case("seq_n1", 32'h0000_4000, 32'h0000_4100);
    run_op("seq_n1", 4, 4, 1, 1'b0, 32'h0000_4000, 32'h0000_4100, 32'h0000_4200, ok);
    check_writeback("seq_n1", 32'h0000_4200, 4, 1);

    do_reset();
    preload_case("seq_mixed", 32'h0000_5000, 32'h0000_5100);
    run_op("seq_mixed", 3, 2, 3, 1'b0, 32'h0000_5000, 32'h0000_5100, 32'h0000_5200, ok);
    check_writeback("seq_mixed", 32'h0000_5200, 3, 3);

    // ==== Directed: two ops back to back, no reset -- the direct test
    // of the array_en/psum-safety argument (file header). ====
    do_reset();
    preload_case("cross_terms", 32'h0000_6000, 32'h0000_6100);
    run_op("back-to-back: cross_terms", 4, 4, 4, 1'b0, 32'h0000_6000, 32'h0000_6100, 32'h0000_6200, ok);
    check_writeback("back-to-back: cross_terms", 32'h0000_6200, 4, 4);

    preload_case("seq_mixed", 32'h0000_7000, 32'h0000_7100); // no do_reset() -- second op immediately after the first
    run_op("back-to-back: seq_mixed", 3, 2, 3, 1'b0, 32'h0000_7000, 32'h0000_7100, 32'h0000_7200, ok);
    check_writeback("back-to-back: seq_mixed", 32'h0000_7200, 3, 3);

    // ==== Directed: illegal-config / error-recovery (task 006's own
    // case, re-confirmed with the new states downstream unaffected). ====
    do_reset();
    dim_m = 3'd0; dim_k = 3'd4; dim_n = 3'd4; mode_unsigned = 1'b0;
    src_a = 0; src_b = 0; dest_c = 0;
    start = 1; step(); start = 0;
    step(); // LATCH_CFG -> ERROR (illegal)
    checks = checks + 1;
    if (error !== 1'b1 || error_code !== 3'd1) begin
      errors = errors + 1;
      $display("FAIL [illegal dim_m=0]: expected error=1 error_code=1, got error=%0b error_code=%0d", error, error_code);
    end else begin
      $display("PASS [illegal dim_m=0]: error=1 error_code=1");
    end
    // Legal start afterward, no reset -- confirms recovery.
    preload_case("cross_terms", 32'h0000_8000, 32'h0000_8100);
    run_op("post-error recovery: cross_terms", 4, 4, 4, 1'b0, 32'h0000_8000, 32'h0000_8100, 32'h0000_8200, ok);
    check_writeback("post-error recovery: cross_terms", 32'h0000_8200, 4, 4);

    // ==== CRV: all 64 crv_* cases, run back to back (no reset between
    // them), model SRAM's randomized per-beat back-pressure enabled
    // throughout (already the model's normal behavior, not toggled). ====
    do_reset();
    $display("CRV: running all 64 crv_* cases through unpu_seq end to end, back-pressure seed 32'h5eed000b");

    for (i = 0; i < 64; i = i + 1) begin
      crv_name = $sformatf("crv_%04d", i);
      fd = $fopen({"model/vectors/", crv_name, "_meta.txt"}, "r");
      if (fd == 0)
        $fatal(1, "could not open model/vectors/%s_meta.txt -- run model/golden first", crv_name);
      scan_rc = $fscanf(fd, "M=%d\nMODE=%s\nK=%d\nN=%d\n", meta_m, mode_str, meta_k, meta_n);
      $fclose(fd);
      if (scan_rc != 4)
        $fatal(1, "could not parse model/vectors/%s_meta.txt (got %0d fields)", crv_name, scan_rc);

      // Per-case address band, well separated (1024 words = 4KB apart),
      // same convention as tb/unpu_dma_tb.sv (task 008).
      base_a = 32'h0010_0000 + (32'(i) * 32'd4096);
      base_w = base_a + 32'd256;
      base_c = base_a + 32'd512;

      preload_case(crv_name, base_a, base_w);
      run_op(crv_name, meta_m, meta_k, meta_n, (mode_str == "UNSIGNED"), base_a, base_w, base_c, ok);
      check_writeback(crv_name, base_c, meta_m, meta_n);
    end

    $display("CRV: 64 cases completed");

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
