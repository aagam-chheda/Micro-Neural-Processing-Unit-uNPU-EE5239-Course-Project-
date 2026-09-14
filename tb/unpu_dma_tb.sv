// Integration test for unpu_dma, driving real unpu_actbuf/unpu_wbuf
// instances (task 007) against a small behavioral SRAM model (test
// infrastructure only, not part of the macro -- the real arbiter is
// still unowned, handoff §7 item 2). Covers plan.md steps 10 (DMA
// master) and 11 (randomized back-pressure) together, per the task file.
//
// Address convention under test (Planning's choice, not yet firmware-
// confirmed -- handoff §7 item 5 is still open, see rtl/unpu_dma.sv's
// header comment for the full rationale): A/W fetch one 32-bit word per
// row (addr = base + row*4); C writeback uses a fixed 16-byte row stride
// (addr = dest_C + m*16 + j*4) but only writes the real N columns per
// row.
//
// Loop-structure note: every "wait for job_done" loop below is a
// bounded `for` with an explicit generous cycle cap and a "did we
// actually see it" flag, not an open-ended `while (job_done !== 1)`.
// An open-ended while loop of that shape, built while smoke-testing
// unpu_dma in isolation, hung indefinitely under this Verilator version's
// --timing scheduler for reasons not fully root-caused (a fixed-count
// `for` loop driving the exact same DUT completed correctly and matched
// a cycle-by-cycle trace of the real FSM) -- avoided here rather than
// chased further, since it's a testbench-authoring hazard, not evidence
// of an RTL bug (confirmed independently via the trace).
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006/007 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
`timescale 1ns/1ps

module unpu_dma_tb;

  logic clk;
  logic rst_n;
  logic array_en;

  // ---- unpu_dma <-> bus ----
  logic [31:0] dma_addr, dma_wdata, dma_rdata;
  logic [3:0]  dma_wstrb;
  logic        dma_valid, dma_ready;

  // ---- unpu_dma job control ----
  logic        job_start;
  logic [1:0]  job_kind;
  logic [31:0] job_base_addr;
  logic [2:0]  job_m, job_n, job_k;
  logic        job_busy, job_done;

  // ---- unpu_dma <-> unpu_actbuf/unpu_wbuf ----
  logic                 a_load_start;
  logic [2:0]           a_load_m, a_load_k;
  logic [3:0][7:0]      a_load_row;
  logic                 w_load_start;
  logic [2:0]           w_load_k, w_load_n;
  logic [3:0][7:0]      w_load_row;
  logic [3:0][3:0][31:0] c_src;

  // ---- unpu_actbuf/unpu_wbuf extra ports ----
  logic       a_swap, w_swap;
  logic       a_load_busy, a_load_done, w_load_busy, w_load_done;
  logic [1:0] a_rd_row;
  logic [3:0][7:0] a_rd_data;
  logic [3:0][3:0]       w_weight_load;
  logic [3:0][3:0][7:0]  w_weight_in;

  localparam logic [1:0] JOB_FETCH_A = 2'd0;
  localparam logic [1:0] JOB_FETCH_W = 2'd1;
  localparam logic [1:0] JOB_WRITE_C = 2'd2;

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
    .c_src         (c_src)
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

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  // ---- Behavioral SRAM model: word-addressable, combinational read
  // (dma_rdata valid the same cycle as valid&ready, per the native
  // interface convention), writes committed on valid&ready&wstrb==F.
  // dma_ready is held low for a randomized 0-5 cycle delay before
  // granting every beat (step 11's back-pressure requirement), using a
  // same-cycle-lookahead draw so a delay of 0 can still grant on the very
  // first cycle a request appears -- same idiom as unpu_wbuf's
  // effective_sel (task 007). force_stall lets the directed
  // held-back-pressure test override the model with a longer, fixed
  // stall on demand. ----
  localparam int MEM_WORDS = 8192;
  logic [31:0] mem [0:MEM_WORDS-1];
  assign dma_rdata = mem[dma_addr[14:2]]; // 13-bit word index, covers MEM_WORDS=8192

  always_ff @(posedge clk) begin
    if (dma_valid && dma_ready && dma_wstrb == 4'hF)
      mem[dma_addr[14:2]] <= dma_wdata;
  end

  logic [31:0] bp_rng;
  logic [2:0]  bp_delay_reg;
  logic        bp_have_delay;
  logic [2:0]  bp_delay_eff;
  logic        force_stall;

  function automatic logic [31:0] xorshift32(logic [31:0] x);
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    return x;
  endfunction

  assign bp_delay_eff = bp_have_delay ? bp_delay_reg : (bp_rng[2:0] < 3'd6 ? bp_rng[2:0] : 3'd5);
  assign dma_ready     = force_stall ? 1'b0 : (dma_valid && (bp_delay_eff == 3'd0));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bp_rng        <= 32'h5eed0008;
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

  int errors;
  int checks;

  task automatic do_reset;
    begin
      rst_n         = 0;
      array_en      = 0;
      job_start     = 0; job_kind = 0; job_base_addr = 0; job_m = 0; job_n = 0; job_k = 0;
      c_src         = '0;
      a_swap        = 0;
      w_swap        = 0;
      a_rd_row      = 0;
      force_stall   = 0;
      step();
      step();
      rst_n    = 1;
      array_en = 1;
      step();
    end
  endtask

  // ---- Loads <name>_{a,w,c}.hex (4x4-shaped, task 006 Part A format)
  // and packs A/W rows into mem at the given byte base addresses, one
  // 32-bit word per row (byte i = column i, little-endian). C is left
  // for the writeback tests to read back and check, not preloaded. ----
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

  // Runs one DMA job to completion (bounded loop -- see file header).
  // Returns nothing; caller checks state/memory afterward.
  task automatic run_job(input string label, input logic [1:0] kind,
                          input logic [31:0] base, input int m, input int k, input int n);
    int cyc;
    bit seen_done;
    begin
      job_kind      = kind;
      job_base_addr = base;
      job_m         = m[2:0];
      job_k         = k[2:0];
      job_n         = n[2:0];
      job_start     = 1;
      step();
      job_start = 0;

      seen_done = 1'b0;
      for (cyc = 0; cyc < 300; cyc = cyc + 1) begin
        step();
        if (job_done) begin
          seen_done = 1'b1;
          step(); // let D_FIN -> D_IDLE settle before returning -- job_start
                  // is only sampled in D_IDLE, so a caller pulsing it one
                  // cycle too early (still in D_FIN) would be silently
                  // ignored and the FSM would never leave D_IDLE afterward.
          break;
        end
      end
      checks = checks + 1;
      if (!seen_done) begin
        errors = errors + 1;
        $display("FAIL [%s]: job_done never observed within 300 cycles", label);
      end
    end
  endtask

  // Checks unpu_actbuf's ACTIVE bank against a_case over the true drv_m x
  // drv_k submatrix, via its rd_row/rd_data read port.
  task automatic check_actbuf(input string label, input int drv_m, input int drv_k);
    int m, k;
    begin
      for (m = 0; m < drv_m; m = m + 1) begin
        a_rd_row = m[1:0];
        #1;
        for (k = 0; k < drv_k; k = k + 1) begin
          checks = checks + 1;
          if (a_rd_data[k] !== a_case[m][k]) begin
            errors = errors + 1;
            $display("FAIL [%s]: actbuf active[%0d][%0d]=%0d expected %0d", label, m, k, a_rd_data[k], a_case[m][k]);
          end
        end
      end
    end
  endtask

  // Whitebox check of unpu_wbuf's just-loaded (still INACTIVE) bank,
  // same technique as tb/unpu_buf_tb.sv's task 007 check -- valid only
  // right after a load, before the matching swap.
  task automatic check_wbuf_whitebox(input string label, input logic inactive_is_b);
    int r, c;
    begin
      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
          checks = checks + 1;
          if (inactive_is_b) begin
            if (u_wbuf.bank_b[c][r] !== w_case[r][c]) begin
              errors = errors + 1;
              $display("FAIL [%s]: wbuf stage[%0d][%0d]=%0d expected W[%0d][%0d]=%0d", label, c, r, u_wbuf.bank_b[c][r], r, c, w_case[r][c]);
            end
          end else begin
            if (u_wbuf.bank_a[c][r] !== w_case[r][c]) begin
              errors = errors + 1;
              $display("FAIL [%s]: wbuf stage[%0d][%0d]=%0d expected W[%0d][%0d]=%0d", label, c, r, u_wbuf.bank_a[c][r], r, c, w_case[r][c]);
            end
          end
        end
      end
    end
  endtask

  task automatic swap_both;
    begin
      a_swap = 1;
      w_swap = 1;
      step();
      a_swap = 0;
      w_swap = 0;
    end
  endtask

  // Issues a WRITE_C job from c_case's known values and checks mem at the
  // expected m*16+j*4 offsets over the true drv_m x drv_n submatrix.
  task automatic writeback_and_check(input string label, input logic [31:0] base,
                                      input int drv_m, input int drv_n);
    int m, j;
    begin
      c_src = '0;
      for (m = 0; m < drv_m; m = m + 1)
        for (j = 0; j < drv_n; j = j + 1)
          c_src[m][j] = c_case[m][j];

      run_job(label, JOB_WRITE_C, base, drv_m, 4, drv_n);

      for (m = 0; m < drv_m; m = m + 1) begin
        for (j = 0; j < drv_n; j = j + 1) begin
          checks = checks + 1;
          if (mem[(base >> 2) + m * 4 + j] !== c_case[m][j]) begin
            errors = errors + 1;
            $display("FAIL [%s]: mem C[%0d][%0d]=%0d expected %0d", label, m, j, mem[(base >> 2) + m * 4 + j], c_case[m][j]);
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
  logic [31:0] addr_rng;
  logic [31:0] base_a, base_w, base_c;

  initial begin
    errors = 0;
    checks = 0;
    addr_rng = 32'h5eed0008;
    $display("DMA testbench seed = 32'h%08h (back-pressure model + CRV base-address jitter)", addr_rng);

    // ==== Directed: cross_terms fetch A + fetch W, whitebox + active-bank
    // checks, then swap and confirm. ====
    do_reset();
    preload_case("cross_terms", 32'h0000_1000, 32'h0000_1100);
    run_job("cross_terms FETCH_A", JOB_FETCH_A, 32'h0000_1000, 4, 4, 4);
    run_job("cross_terms FETCH_W", JOB_FETCH_W, 32'h0000_1100, 4, 4, 4);
    check_wbuf_whitebox("cross_terms FETCH_W whitebox", 1'b1); // bank_b is inactive at reset default

    swap_both();
    check_actbuf("cross_terms post-swap actbuf", 4, 4);

    // ==== Directed: writeback C for cross_terms ====
    writeback_and_check("cross_terms WRITE_C", 32'h0000_1200, 4, 4);

    // ==== Directed: seq_k1/seq_n1/seq_mixed through fetch+writeback,
    // proving K/N-aware addressing (beat counts from real K/M only;
    // writeback row stride/beat count from real N). ====
    do_reset();
    preload_case("seq_k1", 32'h0000_2000, 32'h0000_2100);
    run_job("seq_k1 FETCH_A", JOB_FETCH_A, 32'h0000_2000, 4, 1, 4);
    run_job("seq_k1 FETCH_W", JOB_FETCH_W, 32'h0000_2100, 4, 1, 4);
    swap_both();
    check_actbuf("seq_k1 post-swap actbuf", 4, 1);
    writeback_and_check("seq_k1 WRITE_C", 32'h0000_2200, 4, 4);

    do_reset();
    preload_case("seq_n1", 32'h0000_3000, 32'h0000_3100);
    run_job("seq_n1 FETCH_A", JOB_FETCH_A, 32'h0000_3000, 4, 4, 1);
    run_job("seq_n1 FETCH_W", JOB_FETCH_W, 32'h0000_3100, 4, 4, 1);
    swap_both();
    check_actbuf("seq_n1 post-swap actbuf", 4, 4);
    writeback_and_check("seq_n1 WRITE_C", 32'h0000_3200, 4, 1);

    do_reset();
    preload_case("seq_mixed", 32'h0000_4000, 32'h0000_4100);
    run_job("seq_mixed FETCH_A", JOB_FETCH_A, 32'h0000_4000, 3, 2, 3);
    run_job("seq_mixed FETCH_W", JOB_FETCH_W, 32'h0000_4100, 3, 2, 3);
    swap_both();
    check_actbuf("seq_mixed post-swap actbuf", 3, 2);
    writeback_and_check("seq_mixed WRITE_C", 32'h0000_4200, 3, 3);

    // ==== Directed: held-back-pressure -- force dma_ready low for a
    // fixed multi-cycle stretch mid-job (fetch and writeback), confirm
    // dma_addr/dma_valid/dma_wdata hold exactly stable, job still
    // completes correctly once ready returns. ====
    do_reset();
    preload_case("cross_terms", 32'h0000_5000, 32'h0000_5100);

    begin : held_bp_fetch
      logic [31:0] addr_snap;
      logic wdata_snap_valid;
      int stall_i;
      // force_stall asserted BEFORE job_start, so the random back-
      // pressure model can never sneak in a grant before the directed
      // stall takes hold -- asserting it only after a fixed number of
      // step()s would race the model's own (possibly zero-cycle) delay
      // for beat 0, which is exactly what happened the first time this
      // test was written: the model granted beat 0 immediately, so by
      // the time force_stall was set the DUT had already moved on to
      // beat 1's D_REQ.
      force_stall = 1;
      job_kind = JOB_FETCH_A; job_base_addr = 32'h0000_5000; job_m = 3'd4; job_k = 3'd4; job_n = 3'd4;
      job_start = 1;
      step();
      job_start = 0;
      // Now in D_REQ for beat 0, dma_ready held low by force_stall.
      // Hold the bus stalled for 8 cycles (longer than the model's own
      // max 5-cycle random delay would have been, so this is a
      // deliberate directed stall, not just an observation of the model).
      addr_snap = dma_addr;
      for (stall_i = 0; stall_i < 8; stall_i = stall_i + 1) begin
        checks = checks + 1;
        if (dma_addr !== addr_snap || dma_valid !== 1'b1) begin
          errors = errors + 1;
          $display("FAIL [held-back-pressure fetch]: addr/valid drifted during stall (cyc %0d): addr=%0h valid=%0b", stall_i, dma_addr, dma_valid);
        end
        step();
      end
      force_stall = 0;
    end
    // Drain the rest of the job to completion (bounded wait).
    begin : held_bp_fetch_drain
      int cyc2;
      bit seen;
      seen = 1'b0;
      for (cyc2 = 0; cyc2 < 300; cyc2 = cyc2 + 1) begin
        step();
        if (job_done) begin
          seen = 1'b1;
          step(); // let D_FIN -> D_IDLE settle (see run_job's comment)
          break;
        end
      end
      checks = checks + 1;
      if (!seen) begin
        errors = errors + 1;
        $display("FAIL [held-back-pressure fetch]: job never completed after stall released");
      end
    end
    swap_both();
    check_actbuf("held-back-pressure fetch post-swap", 4, 4);

    // Same held-back-pressure directed check during a writeback.
    begin : held_bp_write
      logic [31:0] addr_snap;
      int stall_i;
      c_src = '0;
      for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1)
          c_src[r][c] = c_case[r][c];
      force_stall = 1; // before job_start -- see held_bp_fetch's comment
      job_kind = JOB_WRITE_C; job_base_addr = 32'h0000_5200; job_m = 3'd4; job_k = 3'd4; job_n = 3'd4;
      job_start = 1;
      step();
      job_start = 0;
      addr_snap = dma_addr;
      for (stall_i = 0; stall_i < 8; stall_i = stall_i + 1) begin
        checks = checks + 1;
        if (dma_addr !== addr_snap || dma_valid !== 1'b1 || dma_wdata !== c_case[0][0]) begin
          errors = errors + 1;
          $display("FAIL [held-back-pressure write]: addr/valid/wdata drifted during stall (cyc %0d)", stall_i);
        end
        step();
      end
      force_stall = 0;
    end
    begin : held_bp_write_drain
      int cyc2;
      bit seen;
      seen = 1'b0;
      for (cyc2 = 0; cyc2 < 300; cyc2 = cyc2 + 1) begin
        step();
        if (job_done) begin
          seen = 1'b1;
          step(); // let D_FIN -> D_IDLE settle (see run_job's comment)
          break;
        end
      end
      checks = checks + 1;
      if (!seen) begin
        errors = errors + 1;
        $display("FAIL [held-back-pressure write]: job never completed after stall released");
      end
    end
    for (r = 0; r < 4; r = r + 1) begin
      for (c = 0; c < 4; c = c + 1) begin
        checks = checks + 1;
        if (mem[(32'h0000_5200 >> 2) + r * 4 + c] !== c_case[r][c]) begin
          errors = errors + 1;
          $display("FAIL [held-back-pressure write]: mem C[%0d][%0d] mismatch after stall", r, c);
        end
      end
    end

    // ==== CRV: all 64 crv_* cases, randomized per-beat back-pressure
    // (the model above already draws this every beat unconditionally)
    // and randomized (jittered) base addresses so no two cases share a
    // job_base_addr. ====
    for (i = 0; i < 64; i = i + 1) begin
      crv_name = $sformatf("crv_%04d", i);
      fd = $fopen({"model/vectors/", crv_name, "_meta.txt"}, "r");
      if (fd == 0)
        $fatal(1, "could not open model/vectors/%s_meta.txt -- run model/golden first", crv_name);
      scan_rc = $fscanf(fd, "M=%d\nMODE=%s\nK=%d\nN=%d\n", meta_m, mode_str, meta_k, meta_n);
      $fclose(fd);
      if (scan_rc != 4)
        $fatal(1, "could not parse model/vectors/%s_meta.txt (got %0d fields)", crv_name, scan_rc);

      addr_rng = xorshift32(addr_rng);
      base_a = 32'h0001_0000 + (32'(i) * 32'd1024) + ({26'd0, addr_rng[5:0]} * 32'd4);
      addr_rng = xorshift32(addr_rng);
      base_w = 32'h0001_0000 + (32'(i) * 32'd1024) + 32'd256 + ({26'd0, addr_rng[5:0]} * 32'd4);
      addr_rng = xorshift32(addr_rng);
      base_c = 32'h0001_0000 + (32'(i) * 32'd1024) + 32'd512 + ({26'd0, addr_rng[5:0]} * 32'd4);

      do_reset();
      preload_case(crv_name, base_a, base_w);
      run_job({crv_name, " FETCH_A"}, JOB_FETCH_A, base_a, meta_m, meta_k, meta_n);
      run_job({crv_name, " FETCH_W"}, JOB_FETCH_W, base_w, meta_m, meta_k, meta_n);
      swap_both();
      check_actbuf({crv_name, " post-swap actbuf"}, meta_m, meta_k);
      writeback_and_check({crv_name, " WRITE_C"}, base_c, meta_m, meta_n);
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
