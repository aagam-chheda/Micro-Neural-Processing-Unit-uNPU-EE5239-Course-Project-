// =============================================================================
// unpu_ext1_tb -- externally written single-case smoke test, adapted to unpu_top
//
// PROVENANCE. Originally written by a peer for a DiP-array (diagonal-input,
// permuted-weight systolic array) implementation of the same course project
// (source: temp/tb1.txt, module tb_unpu_top, 252 lines). Adapted for this
// design in this repository (task 032). The peer's testbench was written
// independently of this repo's testbenches and of model/golden.c; that
// independence is the point of running it, so the peer's own approach is
// kept: an in-testbench software reference model, computed from the operands
// as they sit in SRAM, on the peer's own test data (W and A both 1..16,
// row-major). It does not read anything under model/vectors.
//
// WHAT THE ORIGINAL DID (one test): load a 4x4 W and a 4x4 A (both 1..16)
// into a behavioural SRAM, program the DMA, START, poll STATUS for done or
// error, and compare the 16 output words with A @ W.
//
// WHAT WAS CHANGED FOR THIS DESIGN
//  * unpu_top has no parameters (TIMEOUT_CYCLES dropped) and no dma_rvalid
//    port. The peer's SRAM model drove dma_rvalid; here it is gone. The
//    peer's registered 1-cycle-latency read (dma_rdata_r loaded on the
//    accepted read beat) is KEPT: unpu_dma samples dma_rdata one cycle after
//    the accepted beat (state D_ACK), which is exactly when that data is valid.
//  * Register map: eight registers (src_a 0x00, src_b 0x04, dest_c 0x08,
//    dim_m 0x0C, dim_n 0x10, dim_k 0x14, npu_ctrl 0x18, npu_status 0x1C; from
//    rtl/unpu_csr.sv SEL_*). The peer's CTRL/STATUS/DMA_SRC/DMA_DST/MATRIX
//    words do not exist.
//  * Job shape: separate src_b (W, K words, one row per word), src_a (A, M
//    words) and dest_c (C, row stride 16 bytes). The peer's one-region "4 W
//    words then 4 A words" is laid out as W at 0x000, A at 0x010 (adjacent),
//    C at 0x100. Byte order inside a word is little-endian (byte i = element
//    i, rtl/unpu_dma.sv header); the peer's word was {col0,col1,col2,col3}
//    (MSB-first) for its own array.
//  * STATUS: bit0 DONE, bit1 ERROR, bits[4:2] error_code (there is no BUSY
//    bit). The peer polled STATUS[0]/[2]; here DONE=[0] and ERROR=[1].
//  * Arithmetic: this design has a signed/unsigned mode (npu_ctrl bit1 =
//    SIGNED; bit1=0 is unsigned) and a 32-bit accumulator. The peer's golden
//    model was unsigned only; it is extended to both modes and the whole
//    test runs TWICE, once per mode, with the same operands (1..16 is
//    identical in both interpretations, so both must give the same words).
//    Because the second pass reuses the same output region, the region is
//    pre-filled with a sentinel before every pass, so stale data from the
//    previous pass cannot satisfy the compare.
//  * Declaration order: the peer used dma_rdata_r (its line 102) before its
//    declaration (line 112), which a standards-strict simulator rejects
//    (Xcelium *E,UNDIDN). Declared first here. Nothing else in the file uses
//    a name ahead of its declaration.
//  * SRAM model honesty (task 030): the peer's model indexed mem[dma_addr
//    [11:2]] and would silently alias any address >= 4 KiB. Here every
//    DMA beat above the window is a counted FAIL (window monitor), and every
//    TB-side index goes through the bounds-checked mem_ix().
//  * Step/drive idiom: driven with step() (posedge, then #1) like
//    tb/unpu_top_tb.sv, instead of blocking assignments at the clock edge.
//  * Golden model: computed from the words actually read back out of SRAM
//    (not from the constants that were packed), by the documented layout.
//  * Ending: the peer's $finish-on-failure paths are now counted failures,
//    and the run always ends in an unambiguous ALL TESTS PASSED / FAILED
//    line plus a "checked N" total, so scripts/run_xrun.sh can judge it.
//
// WHAT WAS DROPPED
//  * The peer's "NOTE ON SIMULATORS" (Icarus X readback in its own unpu_cu)
//    is about its implementation and its simulator, not this repo's.
//  * The peer's rows/cols MATRIX word and its "rows==4, cols==4" setup: this
//    design takes dim_m/dim_n/dim_k, all programmed to 4 here.
//  * No randomness is used in this file, so there is no seed to print.
//
// Simulated with Verilator (--binary --timing); intended also for Xcelium
// (scripts/run_xrun.sh ext1).
// =============================================================================
`timescale 1ns / 1ps

module unpu_ext1_tb;

  localparam int N = 4;

  // ---- clock/reset ----
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;   // 100 MHz

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  // ---- bookkeeping (declared before first use) ----
  int pass_count = 0;
  int fail_count = 0;

  // ---- APB ----
  logic        psel, penable, pwrite;
  logic [31:0] paddr, pwdata, prdata;
  logic        pready;

  // CSR byte offsets (rtl/unpu_csr.sv: sel = paddr[11:2])
  localparam logic [31:0] A_SRC_A  = 32'h00;
  localparam logic [31:0] A_SRC_B  = 32'h04;
  localparam logic [31:0] A_DST    = 32'h08;
  localparam logic [31:0] A_DIM_M  = 32'h0C;
  localparam logic [31:0] A_DIM_N  = 32'h10;
  localparam logic [31:0] A_DIM_K  = 32'h14;
  localparam logic [31:0] A_CTRL   = 32'h18;   // bit0 START (W1P), bit1 SIGNED
  localparam logic [31:0] A_STATUS = 32'h1C;   // bit0 DONE, bit1 ERROR, [4:2] error_code

  // ---- native SRAM master (from unpu_top) ----
  logic [31:0] dma_addr, dma_wdata, dma_rdata;
  logic [3:0]  dma_wstrb;
  logic        dma_valid, dma_ready;

  unpu_top dut (
    .clk(clk), .rst_n(rst_n),
    .psel(psel), .penable(penable), .pwrite(pwrite),
    .paddr(paddr), .pwdata(pwdata), .prdata(prdata), .pready(pready),
    .dma_addr(dma_addr), .dma_wdata(dma_wdata), .dma_rdata(dma_rdata),
    .dma_wstrb(dma_wstrb), .dma_valid(dma_valid), .dma_ready(dma_ready)
  );

  // -------------------------------------------------------------------
  // Behavioural single-port SRAM model, 4 KiB window (1024 words):
  // registered 1-cycle read latency (dma_rdata_r loaded on the accepted read
  // beat), same-cycle write, dma_ready always high. dma_rdata_r is declared
  // BEFORE the always_ff that uses it (the peer's file had these two the
  // other way round).
  // -------------------------------------------------------------------
  localparam int MEM_ADDR_BITS = 10;
  localparam int MEM_WORDS     = 1 << MEM_ADDR_BITS;
  logic [31:0] mem [0:MEM_WORDS-1];
  logic [31:0] dma_rdata_r;

  assign dma_ready = 1'b1;   // always accept the address phase
  assign dma_rdata = dma_rdata_r;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      dma_rdata_r <= 32'd0;
    end else begin
      if (dma_valid && dma_ready && (dma_wstrb == 4'b0000))
        dma_rdata_r <= mem[dma_addr[MEM_ADDR_BITS+1:2]];
      if (dma_valid && dma_ready && (dma_wstrb == 4'b1111))
        mem[dma_addr[MEM_ADDR_BITS+1:2]] <= dma_wdata;
    end
  end

  // Bounds discipline (task 030): a TB-side index out of the window is a
  // counted FAIL, never a wrapped or dropped access.
  function automatic int mem_ix(input logic [31:0] byte_addr, input int word_off, input string who);
    logic [31:0] idx;
    begin
      idx = (byte_addr >> 2) + 32'(word_off);
      if (idx >= 32'(MEM_WORDS)) begin
        fail_count = fail_count + 1;
        $display("FAIL [mem bounds]: %s: byte_addr=0x%08h word_off=%0d -> word index %0d >= MEM_WORDS=%0d", who, byte_addr, word_off, idx, MEM_WORDS);
        mem_ix = 0;
      end else begin
        mem_ix = int'(idx);
      end
    end
  endfunction

  // Window monitor: any DMA beat whose address has bits above the decode set
  // would alias silently in the model above, so it is reported instead.
  // Gated by rst_n: until the first clock edge under reset the DUT's flops
  // hold simulator-chosen power-up values (found with Verilator's randomized
  // initial state), and a beat "seen" in that state is not a DUT beat.
  always @(posedge clk) begin
    if (rst_n && dma_valid && dma_ready && (dma_addr >> (MEM_ADDR_BITS + 2)) != 32'd0) begin
      fail_count = fail_count + 1;
      $display("FAIL [mem window]: DMA beat at addr 0x%08h is outside the %0d-word model SRAM window (aliasing would be silent)", dma_addr, MEM_WORDS);
    end
  end

  // -------------------------------------------------------------------
  // APB helper tasks (tb/unpu_top_tb.sv idiom: SETUP then ACCESS, driven
  // after step(), prdata sampled after the ACCESS edge)
  // -------------------------------------------------------------------
  task automatic apb_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      paddr = addr; pwdata = data; pwrite = 1'b1; psel = 1'b1; penable = 1'b0;
      step(); // SETUP
      penable = 1'b1;
      step(); // ACCESS -- commits
      psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [31:0] addr, output logic [31:0] data);
    begin
      paddr = addr; pwrite = 1'b0; psel = 1'b1; penable = 1'b0;
      step(); // SETUP
      penable = 1'b1;
      step(); // ACCESS -- prdata valid
      data = prdata;
      psel = 1'b0; penable = 1'b0;
    end
  endtask

  // -------------------------------------------------------------------
  // Test data: weight and activation matrices, both filled 1..16
  // row-major (matrix[row][col]), and the reference result
  // -------------------------------------------------------------------
  logic [7:0]  W [0:N-1][0:N-1];
  logic [7:0]  A [0:N-1][0:N-1];
  logic [31:0] expected [0:N-1][0:N-1];

  // Layout: W (dim_k = 4 rows) at SRC_B, A (dim_m = 4 rows) directly after it
  // at SRC_A, C at DST_ADDR (row stride 16 bytes).
  localparam logic [31:0] SRC_B    = 32'h000;
  localparam logic [31:0] SRC_A    = 32'h010;
  localparam logic [31:0] DST_ADDR = 32'h100;   // word offset 64

  integer r, c, k, m;
  logic [31:0] rd;
  logic [31:0] got;
  logic [31:0] w_word, a_word;
  int poll_i;
  int mode_i;

  function automatic int signed to_signed8(input logic [7:0] v);
    if (v[7]) return int'(v) - 256;
    else      return int'(v);
  endfunction

  // One MAC term in the selected interpretation, 32 bits wide.
  function automatic logic [31:0] mac_term(input logic [7:0] a, input logic [7:0] w, input bit is_signed);
    int signed sa, sw;
    int unsigned ua, uw;
    begin
      if (is_signed) begin
        sa = to_signed8(a);
        sw = to_signed8(w);
        mac_term = 32'(sa * sw);
      end else begin
        ua = {24'd0, a};
        uw = {24'd0, w};
        mac_term = 32'(ua * uw);
      end
    end
  endfunction

  // Reference model: expected[k][c] = sum_m A[k][m] * W[m][c], computed from
  // the words actually sitting in SRAM (byte i of a word = element i), in the
  // requested interpretation, with a 32-bit accumulator.
  task automatic compute_expected(input bit is_signed);
    int kk, cc, mm;
    logic [31:0] acc;
    logic [31:0] aw, ww;
    begin
      for (kk = 0; kk < N; kk = kk + 1)
        for (cc = 0; cc < N; cc = cc + 1) begin
          acc = 32'd0;
          for (mm = 0; mm < N; mm = mm + 1) begin
            aw = mem[mem_ix(SRC_A, kk, "expected: A row")];
            ww = mem[mem_ix(SRC_B, mm, "expected: W row")];
            acc = acc + mac_term(aw[8*mm +: 8], ww[8*cc +: 8], is_signed);
          end
          expected[kk][cc] = acc;
        end
    end
  endtask

  function automatic logic [31:0] sentinel(input int idx);
    sentinel = 32'hDEAD_C0DE ^ (32'(idx) * 32'h0101_0101);
  endfunction

  // One full START -> DONE pass in the given interpretation.
  task automatic run_pass(input bit is_signed);
    begin
      // sentinel-fill the whole 4x4 result region (stride 16 bytes), so a
      // result left over from the previous pass cannot satisfy the compare
      compute_expected(is_signed);
      for (r = 0; r < N; r = r + 1)
        for (c = 0; c < N; c = c + 1) begin
          w_word = sentinel(r * N + c);
          if (w_word === expected[r][c]) w_word = ~w_word;   // never equal to the answer
          mem[mem_ix(DST_ADDR, r * 4 + c, "sentinel fill")] = w_word;
        end

      apb_write(A_SRC_A, SRC_A);
      apb_write(A_SRC_B, SRC_B);
      apb_write(A_DST,   DST_ADDR);
      apb_write(A_DIM_M, 32'd4);
      apb_write(A_DIM_N, 32'd4);
      apb_write(A_DIM_K, 32'd4);
      apb_write(A_CTRL,  {30'd0, is_signed, 1'b1});   // START | SIGNED?

      // ---- poll STATUS until done or error ----
      rd = 32'h0;
      for (poll_i = 0; poll_i < 500; poll_i = poll_i + 1) begin
        apb_read(A_STATUS, rd);
        if (rd[0] || rd[1]) break;
        step();
        step();
      end

      if (rd[1]) begin
        fail_count = fail_count + 1;
        $display("FAIL: NPU reported ERROR (status=0x%08h), %s mode", rd, is_signed ? "signed" : "unsigned");
      end else if (!rd[0]) begin
        fail_count = fail_count + 1;
        $display("FAIL: timed out waiting for DONE (status=0x%08h), %s mode", rd, is_signed ? "signed" : "unsigned");
      end else begin
        $display("NPU reported DONE (status=0x%08h), %s mode", rd, is_signed ? "signed" : "unsigned");
        if (rd === 32'h0000_0001) pass_count = pass_count + 1;
        else begin
          fail_count = fail_count + 1;
          $display("FAIL: status after DONE is 0x%08h, expected exactly 0x00000001 (DONE only)", rd);
        end

        // ---- check the 16 output words against the reference model ----
        for (r = 0; r < N; r = r + 1) begin
          for (c = 0; c < N; c = c + 1) begin
            got = mem[mem_ix(DST_ADDR, r * 4 + c, "result read")];
            if (got === expected[r][c]) begin
              pass_count = pass_count + 1;
            end else begin
              fail_count = fail_count + 1;
              $display("FAIL: MISMATCH out[%0d][%0d]: got=%0d expected=%0d (word %0d) %s mode",
                       r, c, got, expected[r][c], (DST_ADDR >> 2) + r * 4 + c, is_signed ? "signed" : "unsigned");
            end
          end
        end
      end
    end
  endtask

  initial begin
    psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;

    // ---- build W and A, both = [[1..4],[5..8],[9..12],[13..16]] ----
    for (r = 0; r < N; r = r + 1)
      for (c = 0; c < N; c = c + 1) begin
        W[r][c] = 8'(r * N + c + 1);   // 1..16
        A[r][c] = 8'(r * N + c + 1);   // 1..16
      end

    // ---- pack into SRAM: one row per word, byte i = element i ----
    for (r = 0; r < N; r = r + 1) begin
      mem[mem_ix(SRC_B, r, "pack W")] = {W[r][3], W[r][2], W[r][1], W[r][0]};
      mem[mem_ix(SRC_A, r, "pack A")] = {A[r][3], A[r][2], A[r][1], A[r][0]};
    end

    $display("Weight matrix W:");
    for (r = 0; r < N; r = r + 1)
      $display("  %0d %0d %0d %0d", W[r][0], W[r][1], W[r][2], W[r][3]);
    $display("Activation matrix A:");
    for (r = 0; r < N; r = r + 1)
      $display("  %0d %0d %0d %0d", A[r][0], A[r][1], A[r][2], A[r][3]);
    $display("No random stimulus in this testbench (no seed).");

    // ---- reset ----
    rst_n = 0;
    repeat (5) @(posedge clk);
    #1;
    rst_n = 1;
    repeat (3) step();

    for (mode_i = 0; mode_i < 2; mode_i = mode_i + 1)
      run_pass(mode_i == 1);

    $display("---------------------------------------------");
    $display("checked %0d status/output-word check(s) total", pass_count + fail_count);
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TESTS FAILED: %0d failure(s)", fail_count);
    $display("---------------------------------------------");
    $finish;
  end

  // ---- watchdog ----
  initial begin
    #100000;
    fail_count = fail_count + 1;
    $display("FAIL: global simulation timeout");
    $display("TESTS FAILED: %0d failure(s)", fail_count);
    $finish;
  end

endmodule
