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

  // ---- Task 023 Part C: a SEPARATE, wider back-pressure model for
  // extreme-stall testing (50-100 cycles/beat) -- bp_delay_reg above is
  // only 3 bits (0-5 cycle range, task 008's original moderate-stress
  // model) and structurally can't represent this range; rather than
  // widen it (touching Parts A/B/D/E's already-relied-upon
  // infrastructure), this is an entirely separate mechanism, OFF by
  // default (bp_mode_extreme==0 keeps dma_ready driven by the original
  // model exactly as before -- the only line touched from the original
  // is dma_ready's own assign, now a mux). ----
  logic        bp_mode_extreme;
  logic [31:0] bp_ext_rng;
  logic [6:0]  bp_ext_delay_reg;
  logic        bp_ext_have_delay;
  logic [6:0]  bp_ext_delay_eff;

  assign bp_ext_delay_eff = bp_ext_have_delay ? bp_ext_delay_reg : (7'd50 + (bp_ext_rng[6:0] % 7'd51)); // 50-100
  assign dma_ready = dma_valid && (bp_mode_extreme ? (bp_ext_delay_eff == 7'd0) : (bp_delay_eff == 3'd0));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bp_ext_rng        <= 32'h5eed0019;
      bp_ext_delay_reg  <= 7'd0;
      bp_ext_have_delay <= 1'b0;
    end else if (!bp_mode_extreme || !dma_valid) begin
      bp_ext_have_delay <= 1'b0;
    end else if (!bp_ext_have_delay) begin
      bp_ext_have_delay <= 1'b1;
      bp_ext_delay_reg  <= (bp_ext_delay_eff == 7'd0) ? 7'd0 : (bp_ext_delay_eff - 7'd1);
      bp_ext_rng        <= xorshift32(bp_ext_rng);
    end else if (bp_ext_delay_reg != 7'd0) begin
      bp_ext_delay_reg <= bp_ext_delay_reg - 7'd1;
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
      bp_mode_extreme = 1'b0;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  // ==== Task 023: independent reference model + shared helpers for
  // Parts B-E. ref_c_elem carries no persistent state between calls --
  // every call recomputes its one C[m][j] from scratch off the A/W
  // snapshots and the actual dim_k passed in, same stateless discipline
  // tasks 020-022 used on this project, ruling out the class of bug task
  // 019's first-draft PE reference model had. Unlike the grid/skew
  // versions, this one takes dim_k as an explicit parameter (not fixed
  // at 4) since Part E's ops have genuinely variable K, not always a
  // full 4x4 block. ====
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

  // ~1/8 chance of a boundary extreme, same discipline tasks 019-022
  // used, built on top of this file's own already-existing xorshift32
  // (reused, not redefined).
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

  task automatic step_and_count;
    begin
      step();
      if (job_start) job_start_count = job_start_count + 1;
    end
  endtask

  // Task 023 Part D: like run_op(), but also derives the number of
  // wall-clock cycles unpu_seq spends specifically in COMPUTE, using
  // only externally-observable signals (a_swap, job_start) -- no
  // hierarchical access to unpu_seq's internal cycle/state registers, so
  // this is a genuinely independent measurement, not a check of the
  // RTL's own cycle register against itself.
  //
  // Derivation (fixed FSM topology, independent of DMA back-pressure and
  // of dim_k/dim_n -- that independence is exactly what's under test):
  // a_swap pulses for exactly A_SWAP's one cycle, immediately before
  // COMPUTE begins (cycle==0 the very next edge). job_start's THIRD
  // pulse (after W_FETCH's and A_FETCH's) fires on WRITE_OUTPUT's first
  // cycle, exactly 2 cycles after COMPUTE's last cycle (COMPUTE ->
  // READ_OUTPUT (1 cycle, unconditional) -> WRITE_OUTPUT (job_start
  // pulses immediately on entry)). So if a_swap is observed at wall-
  // clock step t_aswap and the 3rd job_start at step t_third, COMPUTE
  // occupied exactly (t_third - t_aswap - 2) wall-clock cycles -- must
  // equal dim_m+7 by the timing contract, regardless of dim_k/dim_n
  // (which only affect how long the surrounding DMA waits take, not
  // this count).
  task automatic run_op_timed(input string label, input int drv_m, input int drv_k, input int drv_n,
                               input bit drv_mode_u, input logic [31:0] a_addr, input logic [31:0] b_addr,
                               input logic [31:0] c_addr, output bit ok, output int compute_span);
    int cyc;
    bit seen;
    int t, t_aswap, t_third_job_start, job_start_seen;
    begin
      dim_m = drv_m[2:0]; dim_k = drv_k[2:0]; dim_n = drv_n[2:0]; mode_unsigned = drv_mode_u;
      src_a = a_addr; src_b = b_addr; dest_c = c_addr;
      t = 0; t_aswap = -1; t_third_job_start = -1; job_start_seen = 0;

      start = 1;
      step(); t = t + 1;
      start = 0;
      if (a_swap && t_aswap < 0) t_aswap = t;
      if (job_start) begin
        job_start_seen = job_start_seen + 1;
        if (job_start_seen == 3 && t_third_job_start < 0) t_third_job_start = t;
      end

      seen = 1'b0;
      for (cyc = 0; cyc < 4000; cyc = cyc + 1) begin
        step(); t = t + 1;
        if (a_swap && t_aswap < 0) t_aswap = t;
        if (job_start) begin
          job_start_seen = job_start_seen + 1;
          if (job_start_seen == 3 && t_third_job_start < 0) t_third_job_start = t;
        end
        if (done) begin
          seen = 1'b1;
          step(); t = t + 1;
          break;
        end
      end

      ok = seen;
      checks = checks + 1;
      if (!seen) begin
        errors = errors + 1;
        $display("FAIL [%s]: done never observed within 4000 cycles", label);
        compute_span = -1;
      end else begin
        checks = checks + 1;
        if (job_start_seen !== 3) begin
          errors = errors + 1;
          $display("FAIL [%s]: expected exactly 3 job_start pulses, got %0d -- cannot trust the compute-span measurement", label, job_start_seen);
          compute_span = -1;
        end else if (t_aswap < 0 || t_third_job_start < 0) begin
          errors = errors + 1;
          $display("FAIL [%s]: could not locate a_swap and/or the 3rd job_start pulse (t_aswap=%0d t_third_job_start=%0d)", label, t_aswap, t_third_job_start);
          compute_span = -1;
        end else begin
          compute_span = t_third_job_start - t_aswap - 2;
        end
      end
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

  // ==== Task 023 Part B helpers (module scope -- SystemVerilog tasks
  // can't be declared nested inside a procedural begin/end block). ====
  localparam int ST_W_FETCH = 0, ST_W_SWAP = 1, ST_A_FETCH = 2, ST_A_SWAP = 3,
                 ST_COMPUTE = 4, ST_READ_OUTPUT = 5, ST_WRITE_OUTPUT = 6;

  // Runs one op with dim_m=4 fixed, injecting exactly one stray start
  // pulse while the FSM is in the chosen state (identified via this
  // file's own already-trusted Moore outputs -- w_swap/a_swap/job_start
  // -- not hierarchical access), then lets the op run to completion
  // normally.
  task automatic run_op_stray_start(input string lbl, input logic [31:0] a_addr, input logic [31:0] b_addr,
                                     input logic [31:0] c_addr, input int target_state, output bit ok);
    int cyc;
    bit seen, found_aswap;
    int cyc_in_compute;
    begin
      dim_m = 3'd4; dim_k = 3'd4; dim_n = 3'd4; mode_unsigned = 1'b0;
      src_a = a_addr; src_b = b_addr; dest_c = c_addr;
      job_start_count = 0;

      start = 1; step_and_count(); start = 0; // -> LATCH_CFG
      step_and_count(); // -> W_FETCH (job_start's 1st pulse fires this edge)

      if (target_state == ST_W_FETCH) begin start = 1; step_and_count(); start = 0; end

      found_aswap = 1'b0;
      for (cyc = 0; cyc < 2000 && !found_aswap; cyc = cyc + 1) begin
        step_and_count();
        if (w_swap && target_state == ST_W_SWAP) begin
          start = 1; step_and_count(); start = 0;
        end
        if (job_start && job_start_count == 2 && target_state == ST_A_FETCH) begin
          start = 1; step_and_count(); start = 0;
        end
        if (a_swap) begin
          if (target_state == ST_A_SWAP) begin
            start = 1; step_and_count(); start = 0;
          end
          found_aswap = 1'b1;
        end
      end
      if (!found_aswap) begin
        errors = errors + 1;
        checks = checks + 1;
        $display("FAIL [%s]: a_swap never observed within 2000 cycles -- op appears stuck before COMPUTE", lbl);
      end

      step_and_count(); // -> COMPUTE, cycle==0
      cyc_in_compute = 0;
      if (target_state == ST_COMPUTE) begin
        repeat (3) begin step_and_count(); cyc_in_compute = cyc_in_compute + 1; end
        start = 1; step_and_count(); start = 0;
      end
      repeat (10 - cyc_in_compute) step_and_count(); // finish COMPUTE (dim_m=4 -> cycle 0..10)
      step_and_count(); // exit edge -> READ_OUTPUT

      if (target_state == ST_READ_OUTPUT) begin start = 1; step_and_count(); start = 0; end
      step_and_count(); // -> WRITE_OUTPUT (job_start's 3rd pulse fires this edge)

      if (target_state == ST_WRITE_OUTPUT) begin start = 1; step_and_count(); start = 0; end

      seen = 1'b0;
      for (cyc = 0; cyc < 4000; cyc = cyc + 1) begin
        step_and_count();
        if (done) begin
          seen = 1'b1;
          step_and_count();
          break;
        end
      end
      ok = seen;
      checks = checks + 1;
      if (!seen) begin
        errors = errors + 1;
        $display("FAIL [%s]: done never observed within 4000 cycles after stray-start injection", lbl);
      end
      checks = checks + 1;
      if (job_start_count !== 3) begin
        errors = errors + 1;
        $display("FAIL [%s]: expected exactly 3 job_start pulses despite stray start injection, got %0d (restart or corruption suspected)", lbl, job_start_count);
      end else begin
        $display("PASS [%s]: op completed with exactly 3 job_start pulses despite stray start during target state", lbl);
      end
    end
  endtask

  // Same shape, but the stray start lands at a random wall-clock cycle
  // within the op (as long as busy is high), across several long back-
  // to-back sequences -- not just the seven directed placements above.
  task automatic run_op_stray_start_random(input string lbl, input logic [31:0] a_addr, input logic [31:0] b_addr,
                                            input logic [31:0] c_addr, input int inject_at_cycle, output bit ok);
    int cyc;
    bit seen, injected;
    begin
      dim_m = 3'd4; dim_k = 3'd4; dim_n = 3'd4; mode_unsigned = 1'b0;
      src_a = a_addr; src_b = b_addr; dest_c = c_addr;
      job_start_count = 0;
      injected = 1'b0;

      start = 1; step_and_count(); start = 0;

      seen = 1'b0;
      for (cyc = 0; cyc < 4000; cyc = cyc + 1) begin
        if (!injected && cyc == inject_at_cycle && busy) begin
          start = 1; step_and_count(); start = 0;
          injected = 1'b1;
        end
        step_and_count();
        if (done) begin
          seen = 1'b1;
          step_and_count();
          break;
        end
      end
      ok = seen;
      checks = checks + 1;
      if (!seen) begin
        errors = errors + 1;
        $display("FAIL [%s]: done never observed within 4000 cycles (random stray-start at cyc=%0d)", lbl, inject_at_cycle);
      end
      checks = checks + 1;
      if (job_start_count !== 3) begin
        errors = errors + 1;
        $display("FAIL [%s]: expected exactly 3 job_start pulses, got %0d (random stray-start at cyc=%0d)", lbl, job_start_count, inject_at_cycle);
      end
      checks = checks + 1;
      if (!injected) begin
        errors = errors + 1;
        $display("FAIL [%s]: never found a busy cycle to inject the stray start at cyc=%0d", lbl, inject_at_cycle);
      end else begin
        $display("PASS [%s]: op completed with exactly 3 job_start pulses despite a random-timed stray start (cyc=%0d)", lbl, inject_at_cycle);
      end
    end
  endtask

  // ==== Task 023 Part E helpers: synthetic (not golden.c-vector-file)
  // per-op data generation direct into the model SRAM, plus a checker
  // against ref_c_elem -- no corresponding golden.c vector file exists
  // for arbitrary random (M,K,N)/data combinations, so this is the only
  // way to check a randomly-shaped op's result. Same task 006 Part A
  // packing convention preload_case() already uses (full 4x4 grid
  // stored per row, unused cells zero) -- unpu_dma only ever fetches the
  // drv_m/drv_k/drv_n-sized real subset. ====
  logic [7:0] e_a_case [0:3][0:3];
  logic [7:0] e_w_case [0:3][0:3];

  task automatic gen_and_load_op(input logic [31:0] base_a_i, input logic [31:0] base_w_i,
                                  input int drv_m, input int drv_k, ref logic [31:0] rng);
    int rr, cc;
    begin
      e_a_case = '{default: 8'h00};
      e_w_case = '{default: 8'h00};
      for (rr = 0; rr < drv_m; rr = rr + 1)
        for (cc = 0; cc < drv_k; cc = cc + 1)
          e_a_case[rr][cc] = biased_byte(rng);
      for (rr = 0; rr < drv_k; rr = rr + 1)
        for (cc = 0; cc < 4; cc = cc + 1) // full width generated; only the first drv_n columns are ever fetched/used
          e_w_case[rr][cc] = biased_byte(rng);

      for (rr = 0; rr < 4; rr = rr + 1) begin
        mem[(base_a_i >> 2) + rr] = {e_a_case[rr][3], e_a_case[rr][2], e_a_case[rr][1], e_a_case[rr][0]};
        mem[(base_w_i >> 2) + rr] = {e_w_case[rr][3], e_w_case[rr][2], e_w_case[rr][1], e_w_case[rr][0]};
      end
    end
  endtask

  task automatic check_writeback_ref(input string lbl, input logic [31:0] c_addr_i, input int drv_m,
                                      input int drv_n, input int drv_k, input bit drv_mode_u);
    int mm, jj;
    logic [31:0] exp_val;
    begin
      for (mm = 0; mm < drv_m; mm = mm + 1) begin
        for (jj = 0; jj < drv_n; jj = jj + 1) begin
          exp_val = ref_c_elem(e_w_case, e_a_case, mm, jj, drv_k, drv_mode_u);
          checks = checks + 1;
          if (mem[(c_addr_i >> 2) + mm * 4 + jj] !== exp_val) begin
            errors = errors + 1;
            $display("FAIL [%s]: mem C[%0d][%0d]=%0d expected %0d", lbl, mm, jj, mem[(c_addr_i >> 2) + mm * 4 + jj], exp_val);
          end
        end
      end
    end
  endtask

  // Drives one op that's either deliberately illegal (checked against
  // error=1/error_code=1, chain continues into whatever op comes next --
  // ERROR samples start just like IDLE does) or legal (run to done,
  // caller checks the result separately via check_writeback_ref()).
  task automatic run_op_maybe_illegal(input string lbl, input int drv_m, input int drv_k, input int drv_n,
                                       input bit drv_mode_u, input logic [31:0] a_addr, input logic [31:0] b_addr,
                                       input logic [31:0] c_addr, input bit expect_illegal, output bit ok);
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

      if (expect_illegal) begin
        step(); // LATCH_CFG -> ERROR
        checks = checks + 1;
        if (error !== 1'b1 || error_code !== 3'd1) begin
          errors = errors + 1;
          $display("FAIL [%s]: expected illegal-config error=1 error_code=1 (dim_m=%0d dim_n=%0d dim_k=%0d), got error=%0b error_code=%0d",
                    lbl, drv_m, drv_n, drv_k, error, error_code);
        end
        ok = 1'b1;
      end else begin
        seen = 1'b0;
        for (cyc = 0; cyc < 4000; cyc = cyc + 1) begin
          step();
          if (job_start) job_start_count = job_start_count + 1;
          if (done) begin
            seen = 1'b1;
            step();
            break;
          end
        end
        ok = seen;
        checks = checks + 1;
        if (!seen) begin
          errors = errors + 1;
          $display("FAIL [%s]: done never observed within 4000 cycles", lbl);
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

    // ==== Task 023, Part A: exhaustive illegal-config sweep + rapid-
    // fire consecutive errors. error_code==3'd1 is the ONLY error code
    // this RTL defines (unpu_seq.sv's own header: "3'd1 = illegal
    // dim_m/dim_n/dim_k, others reserved") -- checked against that fixed
    // protocol constant, not a value derived from a first run. ====
    begin : part_a
      int dim_idx, val_idx;
      int illegal_vals [0:3];
      int boundary_vals [0:1];
      int dm2, dn2, dk2;

      illegal_vals[0] = 0; illegal_vals[1] = 5; illegal_vals[2] = 6; illegal_vals[3] = 7;
      boundary_vals[0] = 1; boundary_vals[1] = 4;

      // ---- Exhaustive illegal-value sweep: each dim independently,
      // all four illegal values, other two dims legal. ----
      for (dim_idx = 0; dim_idx < 3; dim_idx = dim_idx + 1) begin
        for (val_idx = 0; val_idx < 4; val_idx = val_idx + 1) begin
          dm2 = 4; dn2 = 4; dk2 = 4;
          case (dim_idx)
            0: dm2 = illegal_vals[val_idx];
            1: dn2 = illegal_vals[val_idx];
            default: dk2 = illegal_vals[val_idx];
          endcase
          do_reset();
          dim_m = dm2[2:0]; dim_n = dn2[2:0]; dim_k = dk2[2:0]; mode_unsigned = 1'b0;
          src_a = 0; src_b = 0; dest_c = 0;
          start = 1; step(); start = 0;
          step(); // LATCH_CFG -> ERROR
          checks = checks + 1;
          if (error !== 1'b1 || error_code !== 3'd1) begin
            errors = errors + 1;
            $display("FAIL [illegal dim_idx=%0d val=%0d]: dim_m=%0d dim_n=%0d dim_k=%0d expected error=1 error_code=1, got error=%0b error_code=%0d",
                      dim_idx, illegal_vals[val_idx], dm2, dn2, dk2, error, error_code);
          end else begin
            $display("PASS [illegal dim_idx=%0d val=%0d]: dim_m=%0d dim_n=%0d dim_k=%0d error=1 error_code=1", dim_idx, illegal_vals[val_idx], dm2, dn2, dk2);
          end
        end
      end

      // ---- Exact boundary confirmation: 1 and 4 are LEGAL for each dim
      // independently (0 and 5 already confirmed illegal above). ----
      for (dim_idx = 0; dim_idx < 3; dim_idx = dim_idx + 1) begin
        for (val_idx = 0; val_idx < 2; val_idx = val_idx + 1) begin
          dm2 = 4; dn2 = 4; dk2 = 4;
          case (dim_idx)
            0: dm2 = boundary_vals[val_idx];
            1: dn2 = boundary_vals[val_idx];
            default: dk2 = boundary_vals[val_idx];
          endcase
          do_reset();
          dim_m = dm2[2:0]; dim_n = dn2[2:0]; dim_k = dk2[2:0]; mode_unsigned = 1'b0;
          src_a = 0; src_b = 0; dest_c = 0;
          start = 1; step(); start = 0;
          step(); // LATCH_CFG -> W_FETCH (legal) or ERROR
          checks = checks + 1;
          if (error !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL [boundary-legal dim_idx=%0d val=%0d]: dim_m=%0d dim_n=%0d dim_k=%0d expected error=0 (legal), got error=1 error_code=%0d",
                      dim_idx, boundary_vals[val_idx], dm2, dn2, dk2, error_code);
          end else begin
            $display("PASS [boundary-legal dim_idx=%0d val=%0d]: dim_m=%0d dim_n=%0d dim_k=%0d accepted, no error", dim_idx, boundary_vals[val_idx], dm2, dn2, dk2);
          end
        end
      end

      // ---- Multi-dim illegal combinations. ----
      begin : multi_illegal
        int mm_arr [0:2];
        int nn_arr [0:2];
        int kk_arr [0:2];
        mm_arr[0] = 0; nn_arr[0] = 0; kk_arr[0] = 4; // dim_m, dim_n illegal
        mm_arr[1] = 7; nn_arr[1] = 4; kk_arr[1] = 6; // dim_m, dim_k illegal
        mm_arr[2] = 0; nn_arr[2] = 5; kk_arr[2] = 7; // all three illegal
        for (val_idx = 0; val_idx < 3; val_idx = val_idx + 1) begin
          do_reset();
          dim_m = mm_arr[val_idx][2:0]; dim_n = nn_arr[val_idx][2:0]; dim_k = kk_arr[val_idx][2:0]; mode_unsigned = 1'b0;
          src_a = 0; src_b = 0; dest_c = 0;
          start = 1; step(); start = 0;
          step();
          checks = checks + 1;
          if (error !== 1'b1 || error_code !== 3'd1) begin
            errors = errors + 1;
            $display("FAIL [multi-illegal #%0d]: dim_m=%0d dim_n=%0d dim_k=%0d expected error=1 error_code=1, got error=%0b error_code=%0d",
                      val_idx, mm_arr[val_idx], nn_arr[val_idx], kk_arr[val_idx], error, error_code);
          end else begin
            $display("PASS [multi-illegal #%0d]: dim_m=%0d dim_n=%0d dim_k=%0d error=1 error_code=1", val_idx, mm_arr[val_idx], nn_arr[val_idx], kk_arr[val_idx]);
          end
        end
      end

      // ---- Rapid-fire consecutive errors: >=30 illegal start attempts
      // in a row, ONE reset only (before the whole run), no legal op in
      // between -- confirms the FSM cycles ERROR->LATCH_CFG->ERROR
      // cleanly on every start pulse without ever hanging.
      //
      // Honest limitation, not silently glossed over: this RTL defines
      // exactly ONE error code (3'd1). A "stuck at the last value"
      // bug and "correctly re-latches every time" are indistinguishable
      // by output alone when every attempt targets the same code -- what
      // this loop DOES prove is that error stays 1 and error_code stays
      // the only defined value on every one of 30+ consecutive attempts
      // with no hang and no drop to error=0 unexpectedly; it cannot,
      // with this RTL's single-error-code design, additionally prove
      // "not a stale value from several attempts back" in a way that a
      // second, different code value could. ----
      begin : rapid_fire
        localparam int NUM_RAPID = 32;
        int ridx;
        logic [31:0] rng;
        int rm, rn, rk;

        rng = 32'h5eed0017; // per-task seed convention (0x5eed0000 + task number, hex)
        $display("Part A rapid-fire seed = 32'h%08h", rng);

        do_reset();
        for (ridx = 0; ridx < NUM_RAPID; ridx = ridx + 1) begin
          rng = xorshift32(rng);
          rm = 1 + (rng % 4);
          rng = xorshift32(rng);
          rn = 1 + (rng % 4);
          rng = xorshift32(rng);
          rk = 1 + (rng % 4);
          rng = xorshift32(rng);
          case (rng[1:0])
            2'd0: rm = illegal_vals[rng[3:2]];
            2'd1: rn = illegal_vals[rng[3:2]];
            2'd2: rk = illegal_vals[rng[3:2]];
            default: begin
              rm = illegal_vals[rng[3:2]];
              rn = illegal_vals[rng[5:4]];
            end
          endcase
          rng = xorshift32(rng);

          dim_m = rm[2:0]; dim_n = rn[2:0]; dim_k = rk[2:0]; mode_unsigned = rng[0];
          src_a = 0; src_b = 0; dest_c = 0;
          start = 1; step(); start = 0;
          step();
          checks = checks + 1;
          if (error !== 1'b1 || error_code !== 3'd1) begin
            errors = errors + 1;
            $display("FAIL [rapid-fire #%0d]: dim_m=%0d dim_n=%0d dim_k=%0d expected error=1 error_code=1, got error=%0b error_code=%0d",
                      ridx, rm, rn, rk, error, error_code);
          end
        end
        $display("Part A rapid-fire: %0d consecutive illegal start attempts, no legal op in between, FSM never stuck", NUM_RAPID);
      end

      $display("----------------------------------------");
      if (errors == 0)
        $display("Part A (exhaustive illegal sweep + boundary-legal + multi-illegal + rapid-fire): ALL PASSED, checks=%0d so far", checks);
      else
        $display("Part A: %0d FAILURE(S) SO FAR (checks=%0d)", errors, checks);
      $display("----------------------------------------");
    end

    // ==== Task 023, Part B: stray start-pulse immunity. Proves "start
    // sampled only in IDLE/ERROR" by the op's own outcome (exactly 3
    // job_start pulses, correct C result), not by trusting the state-
    // machine's documented design. All ops here use dim_m=4 (COMPUTE's
    // 11-cycle span, independently confirmed by Part D) so there's room
    // to inject partway through it, not just at entry. ====
    begin : part_b
      begin : directed_placements
        int st;
        string state_names [0:6];
        bit ok2;
        state_names[0] = "W_FETCH";      state_names[1] = "W_SWAP";       state_names[2] = "A_FETCH";
        state_names[3] = "A_SWAP";       state_names[4] = "COMPUTE";      state_names[5] = "READ_OUTPUT";
        state_names[6] = "WRITE_OUTPUT";

        for (st = 0; st < 7; st = st + 1) begin
          do_reset();
          preload_case("cross_terms", 32'h0001_0000, 32'h0001_0100);
          run_op_stray_start($sformatf("stray-start during %s", state_names[st]), 32'h0001_0000, 32'h0001_0100, 32'h0001_0200, st, ok2);
          check_writeback($sformatf("stray-start during %s", state_names[st]), 32'h0001_0200, 4, 4);
        end
      end

      begin : random_placements
        localparam int NUM_RANDOM_STRAY = 10;
        logic [31:0] rng;
        int ri, inj_cyc;
        bit ok2;

        rng = 32'h5eed0018; // per-task seed convention
        $display("Part B random stray-start seed = 32'h%08h", rng);

        do_reset();
        for (ri = 0; ri < NUM_RANDOM_STRAY; ri = ri + 1) begin
          rng = xorshift32(rng);
          inj_cyc = rng % 30;
          preload_case("cross_terms", 32'h0001_0000, 32'h0001_0100);
          run_op_stray_start_random($sformatf("random-stray#%0d(inj_cyc=%0d)", ri, inj_cyc), 32'h0001_0000, 32'h0001_0100, 32'h0001_0200, inj_cyc, ok2);
          check_writeback($sformatf("random-stray#%0d", ri), 32'h0001_0200, 4, 4);
        end
      end

      $display("----------------------------------------");
      if (errors == 0)
        $display("Part B (7 directed stray-start placements + 10 random-timed) ALL PASSED, checks=%0d so far", checks);
      else
        $display("Part B: FAILURE(S) present, checks=%0d so far", checks);
      $display("----------------------------------------");
    end

    // ==== Task 023, Part C: extreme DMA back-pressure (50-100
    // cycles/beat, via the separate bp_mode_extreme model above) across
    // >=10 full ops. Re-proves task 011's exactly-3-job_start-pulses
    // invariant under genuinely extreme stalling, not just the moderate
    // 0-5-cycle range every other part of this file exercises. ====
    begin : part_c
      localparam int NUM_EXTREME_OPS = 10;
      int opi;
      bit ok2;

      do_reset();
      bp_mode_extreme = 1'b1;
      $display("Part C: switching to extreme DMA back-pressure (50-100 cycles/beat) for %0d ops", NUM_EXTREME_OPS);

      for (opi = 0; opi < NUM_EXTREME_OPS; opi = opi + 1) begin
        preload_case("cross_terms", 32'h0002_0000, 32'h0002_0100);
        run_op($sformatf("extreme-backpressure#%0d", opi), 4, 4, 4, 1'b0, 32'h0002_0000, 32'h0002_0100, 32'h0002_0200, ok2);
        check_writeback($sformatf("extreme-backpressure#%0d", opi), 32'h0002_0200, 4, 4);
        checks = checks + 1;
        if (job_start_count !== 3) begin
          errors = errors + 1;
          $display("FAIL [extreme-backpressure#%0d]: expected exactly 3 job_start pulses under extreme back-pressure, got %0d", opi, job_start_count);
        end else begin
          $display("PASS [extreme-backpressure#%0d]: op completed, exactly 3 job_start pulses, under 50-100-cycle/beat back-pressure", opi);
        end
      end

      bp_mode_extreme = 1'b0; // restore normal back-pressure for everything after Part C
      $display("----------------------------------------");
      if (errors == 0)
        $display("Part C (%0d ops under extreme back-pressure): ALL PASSED, checks=%0d so far", NUM_EXTREME_OPS, checks);
      else
        $display("Part C: FAILURE(S) present, checks=%0d so far", checks);
      $display("----------------------------------------");
    end

    // ==== Task 023, Part D: exhaustive (dim_k, dim_n)-independence of
    // the COMPUTE stop condition -- the sharpest test this module gets.
    // Getting this wrong is exactly the bug class this project already
    // caught once (the PM sketch's M+K+N-2 formula, corrected in task
    // 006). Task 006/011 only ever differential-checked 2 pairs; this
    // pushes to 6+ pairs per dim_m, all four dim_m values, using
    // run_op_timed()'s independent (non-hierarchical) cycle-span
    // measurement derived above. ====
    begin : part_d
      int dm, pair_i, dk, dn;
      bit ok2;
      int span;
      int pk [0:5];
      int pn [0:5];
      int total_triples;

      pk[0] = 1; pn[0] = 1;
      pk[1] = 4; pn[1] = 4;
      pk[2] = 1; pn[2] = 4;
      pk[3] = 4; pn[3] = 1;
      pk[4] = 2; pn[4] = 3;
      pk[5] = 3; pn[5] = 2;

      total_triples = 0;
      do_reset();
      preload_case("cross_terms", 32'h0003_0000, 32'h0003_0100);

      for (dm = 1; dm <= 4; dm = dm + 1) begin
        for (pair_i = 0; pair_i < 6; pair_i = pair_i + 1) begin
          dk = pk[pair_i];
          dn = pn[pair_i];
          run_op_timed($sformatf("partD dim_m=%0d dim_k=%0d dim_n=%0d", dm, dk, dn), dm, dk, dn, 1'b0,
                       32'h0003_0000, 32'h0003_0100, 32'h0003_0200, ok2, span);
          checks = checks + 1;
          if (span !== dm + 7) begin
            errors = errors + 1;
            $display("FAIL [partD dim_m=%0d dim_k=%0d dim_n=%0d]: COMPUTE span=%0d expected=%0d (dim_m+7)", dm, dk, dn, span, dm + 7);
          end else begin
            $display("PASS [partD dim_m=%0d dim_k=%0d dim_n=%0d]: COMPUTE span=%0d (dim_m+7), independent of dim_k/dim_n", dm, dk, dn, span);
          end
          total_triples = total_triples + 1;
        end
      end

      $display("----------------------------------------");
      if (errors == 0)
        $display("Part D: %0d (dim_m,dim_k,dim_n) triples checked (4 dim_m values x 6 pairs each), COMPUTE span == dim_m+7 every time, checks=%0d so far", total_triples, checks);
      else
        $display("Part D: FAILURE(S) present, checks=%0d so far", checks);
      $display("----------------------------------------");
    end

    // ==== Task 023, Part E: long adversarial multi-op chains -- one
    // reset per sequence, zero idle gap between ops, ~13% of ops
    // deliberately illegal and interspersed (not run as a separate
    // batch). The specific thing this is trying to break: does an
    // illegal op ever corrupt or delay the NEXT op in the chain -- error
    // recovery was only ever tested once, in isolation, before this
    // (task 006), and never injected into a long back-to-back chain
    // (task 011 never tried it either). ====
    begin : part_e
      localparam int NUM_SEQ = 20;
      logic [31:0] master_rng, rng, seq_seed;
      int seq_idx, op_idx, num_ops, total_ops, total_illegal_ops;
      int this_M, this_K, this_N;
      bit this_mode, is_illegal;
      logic [31:0] eaddr_a, eaddr_w, eaddr_c;
      bit ok2;
      int illeg_vals_e [0:3];
      int badval;

      illeg_vals_e[0] = 0; illeg_vals_e[1] = 5; illeg_vals_e[2] = 6; illeg_vals_e[3] = 7;

      // Fixed, reused address band -- safe because every op freshly
      // writes its own data immediately before running, and is checked
      // immediately after, before the next op's write -- no staleness
      // window exists for a reused address to mask.
      eaddr_a = 32'h0003_8000;
      eaddr_w = 32'h0003_8100;
      eaddr_c = 32'h0003_8200;

      master_rng = 32'h5eed001a; // per-task seed convention
      $display("Part E master seed = 32'h%08h", master_rng);
      total_ops = 0;
      total_illegal_ops = 0;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_seed   = master_rng;
        rng        = seq_seed;
        $display("Part E sequence %0d: seed = 32'h%08h", seq_idx, seq_seed);

        rng = xorshift32(rng);
        num_ops = 100 + (rng % 101); // 100..200 ops per sequence

        do_reset(); // ONE reset per sequence -- every op after the first gets no reset and no idle gap

        for (op_idx = 0; op_idx < num_ops; op_idx = op_idx + 1) begin
          rng = xorshift32(rng);
          is_illegal = (rng % 100) < 13; // ~13%, within the requested 10-15% band

          rng = xorshift32(rng);
          this_M = 1 + (rng % 4);
          rng = xorshift32(rng);
          this_K = 1 + (rng % 4);
          rng = xorshift32(rng);
          this_N = 1 + (rng % 4);
          rng = xorshift32(rng);
          this_mode = rng[0];

          if (is_illegal) begin
            rng = xorshift32(rng);
            badval = illeg_vals_e[rng[1:0]];
            rng = xorshift32(rng);
            case (rng[1:0])
              2'd0: this_M = badval;
              2'd1: this_N = badval;
              default: this_K = badval;
            endcase

            run_op_maybe_illegal($sformatf("seq%0d/op%0d(illegal,M=%0d,K=%0d,N=%0d)", seq_idx, op_idx, this_M, this_K, this_N),
                                  this_M, this_K, this_N, this_mode, eaddr_a, eaddr_w, eaddr_c, 1'b1, ok2);
            total_illegal_ops = total_illegal_ops + 1;
          end else begin
            gen_and_load_op(eaddr_a, eaddr_w, this_M, this_K, rng);
            run_op_maybe_illegal($sformatf("seq%0d/op%0d(M=%0d,K=%0d,N=%0d)", seq_idx, op_idx, this_M, this_K, this_N),
                                  this_M, this_K, this_N, this_mode, eaddr_a, eaddr_w, eaddr_c, 1'b0, ok2);
            check_writeback_ref($sformatf("seq%0d/op%0d", seq_idx, op_idx), eaddr_c, this_M, this_N, this_K, this_mode);
          end
          total_ops = total_ops + 1;
        end
      end

      $display("----------------------------------------");
      $display("Part E: %0d sequences, %0d total ops (%0d illegal, ~%0d%% of total), checks so far=%0d", NUM_SEQ, total_ops, total_illegal_ops, (total_illegal_ops * 100) / total_ops, checks);
      if (errors == 0)
        $display("Part E: ALL PASSED");
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
