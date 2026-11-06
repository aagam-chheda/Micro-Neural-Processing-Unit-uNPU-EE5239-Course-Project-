// =============================================================================
// unpu_ext2_tb -- externally written stress testbench, adapted to unpu_top
//
// PROVENANCE. Originally written by a peer for a DiP-array (diagonal-input,
// permuted-weight systolic array) implementation of the same course project
// (source: temp/tb2.txt, modules behavioral_sram + tb_unpu_top, 986 lines).
// Adapted for this design in this repository (task 032). It was written
// independently of this repo's testbenches and of model/golden.c, and that
// independence is the point of running it: the peer's own approach is kept --
// an in-testbench software reference model (C = A @ W), a behavioural SRAM
// with three back-pressure modes, a bus protocol checker, and the peer's own
// directed corner cases plus a randomized regression. Nothing here reads
// model/vectors.
//
// SRAM MODEL: behavioral_sram is FOLDED IN as a local model in this file
// (the same shape tb/unpu_top_tb.sv uses), not a second module and not a
// separate file, so the "one module per file" rule holds and
// scripts/run_xrun.sh needs no extra source.
//
// ---------------------------------------------------------------------------
// PER-TEST DISPOSITION (every original test is adapted, replaced or dropped)
//   orig 1  reset behaviour            ADAPTED  test_reset_state: all eight
//                                      registers and npu_status read 0
//   orig 2  APB register map           ADAPTED  test_apb_register_map: five
//                                      peer registers -> our eight; MATRIX_CFG
//                                      -> dim_m/dim_n/dim_k (bits[2:0] only);
//                                      out-of-range read: peer expected
//                                      32'hDEAD_BEEF, THIS design returns 0 for
//                                      unmapped offsets (unpu_csr read mux
//                                      default) and ignores writes to them, so
//                                      that is what is tested
//   orig 3  invalid rows/cols config   ADAPTED  test_invalid_config: dim_m,
//                                      dim_n, dim_k each 0, 5, 7 -> ERROR,
//                                      error_code 1, sticky, no DMA activity;
//                                      the peer cleared it with a soft-reset
//                                      pulse, this design has none, so the
//                                      clearing path tested is "the next legal
//                                      START from the ERROR state" (rtl/
//                                      unpu_seq.sv)
//   orig 4  extreme-value corners      ADAPTED  test_extreme_corners, every
//                                      round in BOTH modes; plus ADDED signed
//                                      corners (test_signed_corners, see below)
//   orig 5  rows x cols factorisations REPLACED test_mnk_sweep: the peer's
//                                      1x16..16x1 is a shape of its own DMA.
//                                      Here the legal shape space is dim_m,
//                                      dim_n, dim_k in 1..4: ALL 64 combinations
//                                      x both modes, every one with output
//                                      lane / row masking (sentinel region)
//   orig 6  overlapping/adjacent regs  ADAPTED  test_overlap_addresses: W, A
//                                      and C regions directly adjacent
//   orig 7  soft_reset mid-transfer    REPLACED test_reset_abort: there is no
//                                      soft reset in npu_ctrl (bit0 START, bit1
//                                      SIGNED only). Equivalent for this design:
//                                      rst_n asserted mid-load, then check idle
//                                      state, no bus activity, registers reset,
//                                      and a clean round afterwards
//   orig 8  redundant START when busy  ADAPTED  test_start_while_busy (the
//                                      redundant START carries the OPPOSITE
//                                      SIGNED bit and a different src_a; the
//                                      window is proven to be hit, and no
//                                      second op may follow)
//   orig 9  back-to-back rounds        ADAPTED  test_back_to_back, both modes
//   orig 10 standalone unpu_dma        DROPPED  the peer instantiated ITS unpu_dma
//           watchdog timeout           (start/cfg_rows/cu_* ports, TIMEOUT_
//                                      CYCLES); this repo's unpu_dma has a
//                                      different (job_*) interface and NEITHER
//                                      unpu_dma NOR any other module has a
//                                      timeout or watchdog (grep of rtl/ for
//                                      timeout/watchdog is empty). The check
//                                      cannot exist for this design.
//                                      REPLACED (equivalent observable) by
//                                      test_stuck_sram: with the SRAM never
//                                      ready the block must hold quietly (no
//                                      ERROR, no DONE, no accepted beat, request
//                                      stays asserted), and complete correctly
//                                      when ready comes back
//   orig 11 randomized regression      ADAPTED  test_random_regression, 60
//                                      iterations x both modes; addresses swept
//                                      across the WHOLE model window, distinct
//                                      and in range by construction
//   -       protocol checker           KEPT     dma_addr/dma_wdata/dma_wstrb
//                                      stable while dma_valid && !dma_ready
//   -       global watchdog            KEPT     now also a counted FAIL
//
// ---------------------------------------------------------------------------
// WHAT WAS CHANGED FOR THIS DESIGN
//  * unpu_top has no parameters and no dma_rvalid. Registers, job shape and
//    STATUS layout as in unpu_ext1_tb.sv's header (src_a 0x00, src_b 0x04,
//    dest_c 0x08, dim_m 0x0C, dim_n 0x10, dim_k 0x14, npu_ctrl 0x18,
//    npu_status 0x1C; STATUS bit0 DONE, bit1 ERROR, [4:2] error_code; no BUSY
//    bit; npu_ctrl bit1 = SIGNED). W is K rows at src_b, A is M rows at src_a
//    (one row per word, byte i = element i), C is M x N words at dest_c +
//    16*m + 4*j. C[m][j] = sum_{k<K} A[m][k] * W[k][j].
//  * Reference model: the peer's unsigned 4x4 multiply, extended to (a) M/N/K
//    from 1..4, (b) unsigned AND signed interpretation, (c) a 32-bit
//    accumulator, and (d) computed from the words actually READ BACK OUT OF
//    SRAM after they were written, never from the constants that were packed.
//    Every matrix round is run in BOTH modes (each mode is its own named round).
//  * Every round also checks: STATUS[1:0] == DONE only after DONE (error_code
//    bits [4:2] are ignored when ERROR=0: unpu_seq documents error_code as
//    meaningful only while error=1, and it holds its last value); the whole
//    4x4 C region against sentinel fill (the M x N result words equal the
//    reference, every word outside it is untouched); and the DMA bus itself
//    (below).
//  * BUS/ADDRESS CHECK. Every accepted DMA beat is logged and compared with
//    the sequence rtl/unpu_dma.sv documents: W rows src_b+4k (k<K), A rows
//    src_a+4m (m<M), then C at dest+16m+4j with wstrb 4'hF and the reference
//    value as wdata -- count, order, address, strobe. That is stronger than
//    the required first/last beat of each stream (both are included). It
//    does pin the fetch order (W first) that the RTL documents.
//  * SRAM MODEL HONESTY (task 030). The peer's model masked any 32-bit
//    address into a 64 KiB window, and its random test swept the full 32-bit
//    space, so two streams that landed 32 KiB apart could alias. Here the
//    model has a 2 MiB window (MEM_ADDR_BITS = 19, same as unpu_top_tb.sv);
//    any DMA beat above it is a counted FAIL (window monitor, no wraparound is
//    declared anywhere in this file); any TB-side index goes through the
//    bounds-checked mem_ix(). The random sweep keeps its intent -- spread
//    across the address space, edges included -- but picks 64-byte slots so
//    src and dst are DISTINCT AND IN RANGE BY CONSTRUCTION (slot 0 and the
//    last slot are forced into iterations 0 and 1). The full 32-bit space
//    (the DUT's high address bits) is not covered here; unpu_top_tb's
//    wraparound cases and the dma/seq high-bit mutations own that.
//  * Back-pressure modes are kept: 0 always ready, 1 random Bernoulli
//    (65%), 2 periodic (1 cycle in 3 low). ADDED mode 3 = never ready, used
//    only by test_stuck_sram.
//  * PORTABLE RANDOMNESS (task 030 item 3). $urandom/$urandom_range are
//    simulator-defined. Replaced by the xorshift32 draw_mod() idiom of
//    unpu_stall_tb.sv; both seeds are printed at startup. No expression
//    contains two draw calls (argument-evaluation order is not portable).
//  * Declaration order: everything is declared before use; audited.
//  * Drive idiom: step() (posedge then #1) like tb/unpu_top_tb.sv.
//  * Ending: unambiguous ALL TESTS PASSED / FAILED line plus a total check
//    count; "PASS : name" lines never contain the word FAIL.
//
// ADDED (not in the original): signed corner cases. The peer's file is
// unsigned-only. test_signed_corners runs, in both modes, every ordered pair
// of constant matrices from {0x80 (-128), 0x7F (+127), 0xFF (-1)} for W and
// A (nine pairs, including 0x7F x 0x80 and 0x7F x 0xFF), plus two mixed
// 0x80/0x7F/0xFF lane patterns. The peer's 0x80/0x7F/0xFF boundary values in
// the checkerboard test and in the biased random bytes are kept, and now also
// run signed.
//
// Simulated with Verilator (--binary --timing); intended also for Xcelium
// (scripts/run_xrun.sh ext2).
// =============================================================================
`timescale 1ns / 1ps

module unpu_ext2_tb;

  // ------------------------------------------------------------------
  // Parameters / knobs
  // ------------------------------------------------------------------
  localparam int CLK_PERIOD          = 10;                 // 100 MHz
  localparam int NUM_RANDOM_TESTS    = 60;                 // raise for a longer regression
  localparam int POLL_MAX            = 20000;              // TB-side bound on STATUS polls per round
  localparam int STUCK_HOLD_CYCLES   = 1000;               // never-ready hold in test_stuck_sram
  localparam int GLOBAL_WATCHDOG_NS  = 50_000_000;         // whole-sim safety net
  localparam int READY_PCT           = 65;                 // stall mode 1

  localparam logic [31:0] SEED_MAIN  = 32'h5EED_E200;      // operands / addresses / modes
  localparam logic [31:0] SEED_SRAM  = 32'h5EED_E201;      // SRAM ready draws (stall mode 1)

  // Model SRAM window: 2^19 words = 2 MiB, DUT-facing decode takes exactly
  // MEM_ADDR_BITS address bits (same as tb/unpu_top_tb.sv).
  localparam int MEM_ADDR_BITS = 19;
  localparam int MEM_WORDS     = 1 << MEM_ADDR_BITS;
  localparam int SLOT_BYTES    = 64;                       // one C region (4 x 16 B); >= the 32 B of inputs
  localparam int N_SLOTS       = (1 << (MEM_ADDR_BITS + 2)) / SLOT_BYTES;

  localparam logic [31:0] CSR_BASE     = 32'h4000_0000;
  localparam logic [31:0] OFF_SRC_A    = 32'h00;
  localparam logic [31:0] OFF_SRC_B    = 32'h04;
  localparam logic [31:0] OFF_DEST_C   = 32'h08;
  localparam logic [31:0] OFF_DIM_M    = 32'h0C;
  localparam logic [31:0] OFF_DIM_N    = 32'h10;
  localparam logic [31:0] OFF_DIM_K    = 32'h14;
  localparam logic [31:0] OFF_NPU_CTRL = 32'h18;           // bit0 START (W1P), bit1 SIGNED
  localparam logic [31:0] OFF_NPU_STAT = 32'h1C;           // bit0 DONE, bit1 ERROR, [4:2] error_code

  // ------------------------------------------------------------------
  // Bookkeeping (declared early)
  // ------------------------------------------------------------------
  int checks      = 0;   // every elementary comparison
  int fail_count  = 0;   // every failed comparison / protocol violation
  int rounds_run  = 0;   // named test rounds started
  int rounds_pass = 0;   // named test rounds finished with no new failure
  int round_serial = 0;  // sentinel diversifier, one per prepared round

  logic [31:0] g_rng;    // operands / addresses / modes (xorshift32)

  // ------------------------------------------------------------------
  // Clock / reset
  // ------------------------------------------------------------------
  logic clk = 0;
  logic rst_n = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  // ------------------------------------------------------------------
  // DUT ports
  // ------------------------------------------------------------------
  logic        psel, penable, pwrite;
  logic [31:0] paddr, pwdata;
  logic [31:0] prdata;
  logic        pready;

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

  // ------------------------------------------------------------------
  // Portable PRNG (xorshift32), the unpu_stall_tb.sv idiom.
  // ------------------------------------------------------------------
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

  // Advances g_rng; result in 0..n-1. Never call twice in one expression.
  function automatic int unsigned draw_mod(input int unsigned n);
    begin
      g_rng = xorshift32(g_rng);
      draw_mod = g_rng % n;
    end
  endfunction

  // ------------------------------------------------------------------
  // Behavioural native-SRAM model (folded in from the peer's
  // behavioral_sram). Registered read address => fixed 1-cycle read
  // latency (data valid the cycle AFTER the accepted read beat; unpu_dma
  // samples in its D_ACK state, one cycle after accept). Writes commit on
  // the accept edge, byte-strobed. Word-addressed array, window checked.
  //   stall mode 0 = always ready
  //              1 = random Bernoulli ready (READY_PCT %)
  //              2 = periodic (ready low 1 cycle in 3)
  //              3 = never ready (test_stuck_sram only)
  // ------------------------------------------------------------------
  logic [31:0] mem [0:MEM_WORDS-1];
  logic [1:0]  sram_stall_mode;
  logic [31:0] sram_rng;
  logic [1:0]  burst_cnt;
  logic        ready_r;
  logic [MEM_ADDR_BITS-1:0] raddr_d;

  assign dma_ready = ready_r;
  assign dma_rdata = mem[raddr_d];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ready_r   <= 1'b1;
      burst_cnt <= 2'd0;
      sram_rng  <= SEED_SRAM;
      raddr_d   <= '0;
    end else begin
      sram_rng <= xorshift32(sram_rng);
      if (dma_valid && dma_ready && dma_wstrb == 4'b0000)
        raddr_d <= dma_addr[MEM_ADDR_BITS+1:2];   // registered read address: 1-cycle latency
      case (sram_stall_mode)
        2'd0: ready_r <= 1'b1;
        2'd1: ready_r <= ((xorshift32(sram_rng) % 32'd100) < 32'(READY_PCT));
        2'd2: begin
          burst_cnt <= (burst_cnt == 2'd2) ? 2'd0 : (burst_cnt + 2'd1);
          ready_r   <= (burst_cnt != 2'd2);
        end
        default: ready_r <= 1'b0;
      endcase
    end
  end

  always @(posedge clk) begin
    if (dma_valid && dma_ready && dma_wstrb != 4'b0000) begin
      if (dma_wstrb[0]) mem[dma_addr[MEM_ADDR_BITS+1:2]][7:0]   <= dma_wdata[7:0];
      if (dma_wstrb[1]) mem[dma_addr[MEM_ADDR_BITS+1:2]][15:8]  <= dma_wdata[15:8];
      if (dma_wstrb[2]) mem[dma_addr[MEM_ADDR_BITS+1:2]][23:16] <= dma_wdata[23:16];
      if (dma_wstrb[3]) mem[dma_addr[MEM_ADDR_BITS+1:2]][31:24] <= dma_wdata[31:24];
    end
  end

  // ---- Model-SRAM bounds discipline (task 030): a TB-side index outside
  // the window is a counted FAIL, never a wrapped or dropped access. Not
  // itself counted in `checks` (a guard on the test's own addressing). ----
  function automatic int mem_ix(input logic [31:0] byte_addr, input int word_off, input string who);
    logic [31:0] idx;
    begin
      idx = (byte_addr >> 2) + 32'(word_off);
      if (idx >= 32'(MEM_WORDS)) begin
        fail_count = fail_count + 1;
        $display("FAIL [mem bounds]: %s: byte_addr=0x%08h word_off=%0d -> word index %0d >= MEM_WORDS=%0d (out-of-range model-SRAM access)", who, byte_addr, word_off, idx, MEM_WORDS);
        mem_ix = 0;
      end else begin
        mem_ix = int'(idx);
      end
    end
  endfunction

  // ---- Window monitor: a DMA beat whose address has bits above the decode
  // would alias silently in the model. No test in this file declares
  // wraparound, so every such beat is a FAIL. Gated by rst_n: until the first
  // clock edge under reset the DUT's flops hold simulator-chosen power-up
  // values (found with Verilator's randomized initial state), and a beat
  // "seen" in that state is not a DUT beat. ----
  always @(posedge clk) begin
    if (rst_n && dma_valid && dma_ready && (dma_addr >> (MEM_ADDR_BITS + 2)) != 32'd0) begin
      fail_count = fail_count + 1;
      $display("FAIL [mem window]: DMA beat at addr 0x%08h is outside the %0d-word model SRAM window (aliasing would be silent)", dma_addr, MEM_WORDS);
    end
  end

  // ---- Protocol checker (peer's): dma_addr/dma_wdata/dma_wstrb stable
  // while dma_valid is asserted and dma_ready is low. ----
  logic [31:0] prev_addr, prev_wdata;
  logic [3:0]  prev_wstrb;
  logic        prev_valid_pending;

  always @(posedge clk) begin
    if (!rst_n) begin
      prev_valid_pending <= 1'b0;
    end else begin
      if (prev_valid_pending) begin
        if (dma_addr !== prev_addr || dma_wdata !== prev_wdata || dma_wstrb !== prev_wstrb) begin
          $display("[%0t] FAIL [PROTOCOL VIOLATION]: dma bus changed while valid&&!ready", $time);
          fail_count = fail_count + 1;
        end
      end
      prev_valid_pending <= dma_valid && !dma_ready;
      prev_addr          <= dma_addr;
      prev_wdata         <= dma_wdata;
      prev_wstrb         <= dma_wstrb;
    end
  end

  // ---- Accepted-beat log, cleared by prepare_round(). blog_n keeps counting
  // past the array so an overrun is visible instead of truncated. ----
  localparam int LOG_MAX = 64;
  logic [31:0] blog_addr  [0:LOG_MAX-1];
  logic [31:0] blog_wdata [0:LOG_MAX-1];
  logic [3:0]  blog_wstrb [0:LOG_MAX-1];
  int          blog_n;

  always @(posedge clk) begin
    if (rst_n && dma_valid && dma_ready) begin
      if (blog_n < LOG_MAX) begin
        blog_addr[blog_n]  = dma_addr;
        blog_wdata[blog_n] = dma_wdata;
        blog_wstrb[blog_n] = dma_wstrb;
      end
      blog_n = blog_n + 1;
    end
  end

  // ------------------------------------------------------------------
  // Global safety net
  // ------------------------------------------------------------------
  initial begin
    #(GLOBAL_WATCHDOG_NS);
    fail_count = fail_count + 1;
    $display("[%0t] FAIL: global simulation watchdog expired -- forcing $finish", $time);
    $display("checked %0d check(s) (INCOMPLETE -- GLOBAL WATCHDOG FIRED)", checks);
    $display("TESTS FAILED: %0d failure(s)", fail_count);
    $finish;
  end

  // ------------------------------------------------------------------
  // Shared operand/result matrices (row-major, index = row*4+col).
  // tb_W[k*4+j] is W[k][j]; tb_A[m*4+k] is A[m][k]; tb_C_golden[m*4+j].
  // ------------------------------------------------------------------
  logic [7:0]  tb_W [0:15];
  logic [7:0]  tb_A [0:15];
  logic [31:0] tb_C_golden [0:15];
  logic [31:0] round_sent  [0:15];

  // ------------------------------------------------------------------
  // APB bus-functional model (tb/unpu_top_tb.sv idiom)
  // ------------------------------------------------------------------
  task automatic apb_write(input logic [31:0] a, input logic [31:0] d);
    begin
      paddr = a; pwdata = d; pwrite = 1'b1; psel = 1'b1; penable = 1'b0;
      step(); // SETUP
      penable = 1'b1;
      step(); // ACCESS -- commits
      psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [31:0] a, output logic [31:0] d);
    begin
      paddr = a; pwrite = 1'b0; psel = 1'b1; penable = 1'b0;
      step(); // SETUP
      penable = 1'b1;
      step(); // ACCESS -- prdata valid
      d = prdata;
      psel = 1'b0; penable = 1'b0;
    end
  endtask

  task automatic apb_start(input bit is_signed);
    begin
      apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, is_signed, 1'b1});   // START | SIGNED?
    end
  endtask

  // Named-check helper for status/register compares.
  task automatic check_eq32(input string what, input logic [31:0] got, input logic [31:0] exp);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        fail_count = fail_count + 1;
        $display("FAIL [%s]: got 0x%08h expected 0x%08h", what, got, exp);
      end
    end
  endtask

  task automatic check_true(input string what, input bit cond);
    begin
      checks = checks + 1;
      if (!cond) begin
        fail_count = fail_count + 1;
        $display("FAIL [%s]", what);
      end
    end
  endtask

  // ------------------------------------------------------------------
  // Randomization / operand helpers (all through g_rng)
  // ------------------------------------------------------------------

  // Extreme-biased random byte (peer's distribution): 55% from
  // {00,01,7F,80,FE,FF,55}, else uniform.
  function automatic logic [7:0] rand_byte_biased();
    int unsigned pick, sel;
    logic [7:0] ev;
    begin
      pick = draw_mod(100);
      if (pick < 55) begin
        sel = draw_mod(7);
        case (sel)
          0: ev = 8'h00;
          1: ev = 8'h01;
          2: ev = 8'h7F;
          3: ev = 8'h80;
          4: ev = 8'hFE;
          5: ev = 8'hFF;
          default: ev = 8'h55;
        endcase
        rand_byte_biased = ev;
      end else begin
        rand_byte_biased = 8'(draw_mod(256));
      end
    end
  endfunction

  task automatic fill_W_const(input logic [7:0] val);
    int i; begin for (i = 0; i < 16; i = i + 1) tb_W[i] = val; end
  endtask
  task automatic fill_A_const(input logic [7:0] val);
    int i; begin for (i = 0; i < 16; i = i + 1) tb_A[i] = val; end
  endtask

  task automatic fill_W_random(input bit biased);
    int i;
    begin
      for (i = 0; i < 16; i = i + 1)
        tb_W[i] = biased ? rand_byte_biased() : 8'(draw_mod(256));
    end
  endtask
  task automatic fill_A_random(input bit biased);
    int i;
    begin
      for (i = 0; i < 16; i = i + 1)
        tb_A[i] = biased ? rand_byte_biased() : 8'(draw_mod(256));
    end
  endtask

  task automatic fill_W_identity();
    int i, j;
    begin
      for (i = 0; i < 4; i = i + 1)
        for (j = 0; j < 4; j = j + 1)
          tb_W[i*4+j] = (i == j) ? 8'd1 : 8'd0;
    end
  endtask
  task automatic fill_A_identity();
    int i, j;
    begin
      for (i = 0; i < 4; i = i + 1)
        for (j = 0; j < 4; j = j + 1)
          tb_A[i*4+j] = (i == j) ? 8'd1 : 8'd0;
    end
  endtask

  // The peer's boundary-value pattern (same for W and A).
  task automatic fill_W_pattern_edges();
    begin
      tb_W[0]=8'h00;  tb_W[1]=8'hFF;  tb_W[2]=8'h00;  tb_W[3]=8'hFF;
      tb_W[4]=8'hFF;  tb_W[5]=8'h7F;  tb_W[6]=8'h80;  tb_W[7]=8'h00;
      tb_W[8]=8'h01;  tb_W[9]=8'hFE;  tb_W[10]=8'h01; tb_W[11]=8'hFE;
      tb_W[12]=8'hFF; tb_W[13]=8'h00; tb_W[14]=8'hFF; tb_W[15]=8'h00;
    end
  endtask
  task automatic fill_A_pattern_edges();
    begin
      tb_A[0]=8'h00;  tb_A[1]=8'hFF;  tb_A[2]=8'h00;  tb_A[3]=8'hFF;
      tb_A[4]=8'hFF;  tb_A[5]=8'h7F;  tb_A[6]=8'h80;  tb_A[7]=8'h00;
      tb_A[8]=8'h01;  tb_A[9]=8'hFE;  tb_A[10]=8'h01; tb_A[11]=8'hFE;
      tb_A[12]=8'hFF; tb_A[13]=8'h00; tb_A[14]=8'hFF; tb_A[15]=8'h00;
    end
  endtask

  // ------------------------------------------------------------------
  // Reference model. mac_term: one product in the selected interpretation,
  // 32 bits wide. golden_from_sram: C[m][j] = sum_{k<K} A[m][k]*W[k][j]
  // with A[m][k] = byte k of the word at src_a+4m and W[k][j] = byte j of
  // the word at src_b+4k, read back OUT OF SRAM, 32-bit accumulate.
  // ------------------------------------------------------------------
  function automatic int signed to_signed8(input logic [7:0] v);
    if (v[7]) return int'(v) - 256;
    else      return int'(v);
  endfunction

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

  task automatic golden_from_sram(input logic [31:0] src_a, input logic [31:0] src_b,
                                  input int m, input int k, input int n, input bit is_signed);
    int mi, j, kk;
    logic [31:0] acc, aw, ww;
    begin
      for (mi = 0; mi < 16; mi = mi + 1) tb_C_golden[mi] = 32'd0;
      for (mi = 0; mi < m; mi = mi + 1)
        for (j = 0; j < n; j = j + 1) begin
          acc = 32'd0;
          for (kk = 0; kk < k; kk = kk + 1) begin
            aw = mem[mem_ix(src_a, mi, "golden: A row")];
            ww = mem[mem_ix(src_b, kk, "golden: W row")];
            acc = acc + mac_term(aw[8*kk +: 8], ww[8*j +: 8], is_signed);
          end
          tb_C_golden[mi*4 + j] = acc;
        end
    end
  endtask

  // Write W (K rows at src_b) and A (M rows at src_a) from tb_W / tb_A into
  // the model SRAM, one row per word, byte i = element i. Bytes of a row
  // beyond K (A) / N (W) are the tb arrays' own values: real data in lanes
  // the DUT must ignore.
  task automatic load_operands_to_sram(input logic [31:0] src_a, input logic [31:0] src_b,
                                       input int m, input int k);
    int t;
    begin
      for (t = 0; t < k; t = t + 1)
        mem[mem_ix(src_b, t, "load W")] = {tb_W[t*4+3], tb_W[t*4+2], tb_W[t*4+1], tb_W[t*4+0]};
      for (t = 0; t < m; t = t + 1)
        mem[mem_ix(src_a, t, "load A")] = {tb_A[t*4+3], tb_A[t*4+2], tb_A[t*4+1], tb_A[t*4+0]};
    end
  endtask

  function automatic logic [31:0] sentinel(input int serial, input int idx);
    sentinel = xorshift32(32'hC0DE_0000 ^ (32'(serial) * 32'd16) ^ 32'(idx));
  endfunction

  // ------------------------------------------------------------------
  // Round machinery, split so special tests can interpose:
  //   prepare_round  operands -> SRAM, golden, sentinel fill, log clear
  //   program_and_start
  //   finish_round   wait, status, results, sentinels, bus check
  // ------------------------------------------------------------------
  task automatic prepare_round(input logic [31:0] src_a, input logic [31:0] src_b, input logic [31:0] dst,
                               input int m, input int k, input int n, input bit is_signed,
                               input logic [1:0] stall_mode);
    int t;
    logic [31:0] sent;
    begin
      sram_stall_mode = stall_mode;
      load_operands_to_sram(src_a, src_b, m, k);
      golden_from_sram(src_a, src_b, m, k, n, is_signed);
      round_serial = round_serial + 1;
      for (t = 0; t < 16; t = t + 1) begin
        sent = sentinel(round_serial, t);
        if ((t / 4) < m && (t % 4) < n && sent === tb_C_golden[t]) sent = ~sent;   // never equal to the answer
        round_sent[t] = sent;
        mem[mem_ix(dst, t, "sentinel fill")] = sent;
      end
      blog_n = 0;
    end
  endtask

  task automatic program_and_start(input logic [31:0] src_a, input logic [31:0] src_b, input logic [31:0] dst,
                                   input int m, input int k, input int n, input bit is_signed);
    begin
      apb_write(CSR_BASE + OFF_SRC_A,  src_a);
      apb_write(CSR_BASE + OFF_SRC_B,  src_b);
      apb_write(CSR_BASE + OFF_DEST_C, dst);
      apb_write(CSR_BASE + OFF_DIM_M,  {29'd0, 3'(m)});
      apb_write(CSR_BASE + OFF_DIM_N,  {29'd0, 3'(n)});
      apb_write(CSR_BASE + OFF_DIM_K,  {29'd0, 3'(k)});
      apb_start(is_signed);
    end
  endtask

  // result: 0 = DONE, 1 = ERROR, 2 = TB poll bound hit
  task automatic wait_for_completion(input int max_polls, output int result);
    logic [31:0] status;
    int i;
    begin
      result = 2;
      for (i = 0; i < max_polls; i = i + 1) begin
        apb_read(CSR_BASE + OFF_NPU_STAT, status);
        if (status[0]) begin result = 0; break; end
        if (status[1]) begin result = 1; break; end
      end
    end
  endtask

  task automatic check_bus_sequence(input string name, input logic [31:0] src_a, input logic [31:0] src_b,
                                    input logic [31:0] dst, input int m, input int k, input int n);
    int i, mi, j, idx;
    logic [31:0] exp_addr;
    begin
      check_true({name, " : DMA beat count == K + M + M*N"}, blog_n == k + m + m * n);
      if (blog_n == k + m + m * n) begin
        for (i = 0; i < k; i = i + 1) begin
          checks = checks + 1;
          if (blog_addr[i] !== src_b + 32'(4 * i) || blog_wstrb[i] !== 4'h0) begin
            fail_count = fail_count + 1;
            $display("FAIL [%s]: W fetch beat %0d addr=0x%08h wstrb=%h expected addr=0x%08h wstrb=0",
                     name, i, blog_addr[i], blog_wstrb[i], src_b + 32'(4 * i));
          end
        end
        for (i = 0; i < m; i = i + 1) begin
          checks = checks + 1;
          if (blog_addr[k + i] !== src_a + 32'(4 * i) || blog_wstrb[k + i] !== 4'h0) begin
            fail_count = fail_count + 1;
            $display("FAIL [%s]: A fetch beat %0d addr=0x%08h wstrb=%h expected addr=0x%08h wstrb=0",
                     name, i, blog_addr[k + i], blog_wstrb[k + i], src_a + 32'(4 * i));
          end
        end
        for (mi = 0; mi < m; mi = mi + 1)
          for (j = 0; j < n; j = j + 1) begin
            idx = k + m + mi * n + j;
            exp_addr = dst + 32'(16 * mi) + 32'(4 * j);
            checks = checks + 1;
            if (blog_addr[idx] !== exp_addr || blog_wstrb[idx] !== 4'hF) begin
              fail_count = fail_count + 1;
              $display("FAIL [%s]: C write beat [%0d][%0d] addr=0x%08h wstrb=%h expected addr=0x%08h wstrb=f",
                       name, mi, j, blog_addr[idx], blog_wstrb[idx], exp_addr);
            end
            checks = checks + 1;
            if (blog_wdata[idx] !== tb_C_golden[mi*4 + j]) begin
              fail_count = fail_count + 1;
              $display("FAIL [%s]: C write beat [%0d][%0d] wdata=%0d expected %0d",
                       name, mi, j, blog_wdata[idx], tb_C_golden[mi*4 + j]);
            end
          end
      end
    end
  endtask

  // Everything after START: wait for DONE, then status, results, sentinels
  // and the bus sequence. Prints one PASS line if nothing new failed.
  task automatic finish_round(input string name, input logic [31:0] src_a, input logic [31:0] src_b,
                              input logic [31:0] dst, input int m, input int k, input int n,
                              input bit is_signed);
    int poll_res;
    int t, f0;
    logic [31:0] status;
    logic [31:0] got;
    begin
      f0 = fail_count;
      rounds_run = rounds_run + 1;
      wait_for_completion(POLL_MAX, poll_res);
      if (poll_res == 2) begin
        check_true({name, " : TB poll timeout waiting for done/error"}, 1'b0);
      end else if (poll_res == 1) begin
        check_true({name, " : DUT reported ERROR on a valid config"}, 1'b0);
      end else begin
        apb_read(CSR_BASE + OFF_NPU_STAT, status);
        // DONE=1 and ERROR=0. status[4:2] (error_code) is NOT compared:
        // rtl/unpu_seq.sv documents error_code as "meaningful only while
        // error=1", and it keeps its last value (1 after an illegal-config op)
        // until reset, so a legal op that follows an illegal one legitimately
        // reads 0x5 here. Reported to Planning as an observation.
        check_eq32({name, " : npu_status[1:0] after DONE (DONE=1, ERROR=0)"}, {30'd0, status[1:0]}, 32'h0000_0001);

        for (t = 0; t < 16; t = t + 1) begin
          got = mem[mem_ix(dst, t, "result read")];
          checks = checks + 1;
          if ((t / 4) < m && (t % 4) < n) begin
            if (got !== tb_C_golden[t]) begin
              fail_count = fail_count + 1;
              $display("FAIL [%s]: C[%0d][%0d] expected=%0d (0x%08h) got=%0d (0x%08h)",
                       name, t / 4, t % 4, tb_C_golden[t], tb_C_golden[t], got, got);
            end
          end else begin
            if (got !== round_sent[t]) begin
              fail_count = fail_count + 1;
              $display("FAIL [%s]: word outside the %0dx%0d result at C[%0d][%0d] was touched: got 0x%08h, sentinel 0x%08h",
                       name, m, n, t / 4, t % 4, got, round_sent[t]);
            end
          end
        end

        check_bus_sequence(name, src_a, src_b, dst, m, k, n);
      end
      if (fail_count == f0) begin
        rounds_pass = rounds_pass + 1;
        $display("PASS : %s", name);
      end
    end
  endtask

  task automatic run_matmul_round(input string name, input logic [31:0] src_a, input logic [31:0] src_b,
                                  input logic [31:0] dst, input int m, input int k, input int n,
                                  input bit is_signed, input logic [1:0] stall_mode);
    begin
      prepare_round(src_a, src_b, dst, m, k, n, is_signed, stall_mode);
      program_and_start(src_a, src_b, dst, m, k, n, is_signed);
      finish_round(name, src_a, src_b, dst, m, k, n, is_signed);
    end
  endtask

  // 4x4x4 round on the current tb_W/tb_A in BOTH modes (unsigned then signed).
  // src_b = src, src_a = src + 16 (the peer's one 8-word region: 4 W rows,
  // then 4 A rows).
  task automatic run_both_modes(input string name, input logic [31:0] src, input logic [31:0] dst,
                                input logic [1:0] stall_mode);
    begin
      run_matmul_round({name, " [unsigned]"}, src + 32'd16, src, dst, 4, 4, 4, 1'b0, stall_mode);
      run_matmul_round({name, " [signed]"},   src + 32'd16, src, dst, 4, 4, 4, 1'b1, stall_mode);
    end
  endtask

  // ==================================================================
  // TEST 1: reset behaviour (orig 1)
  // ==================================================================
  task automatic test_reset_state();
    logic [31:0] v;
    begin
      apb_read(CSR_BASE + OFF_NPU_STAT, v);
      check_eq32("reset: npu_status is idle (done=error=code=0)", v, 32'h0);
      apb_read(CSR_BASE + OFF_SRC_A, v);    check_eq32("reset: src_a reads 0", v, 32'h0);
      apb_read(CSR_BASE + OFF_SRC_B, v);    check_eq32("reset: src_b reads 0", v, 32'h0);
      apb_read(CSR_BASE + OFF_DEST_C, v);   check_eq32("reset: dest_c reads 0", v, 32'h0);
      apb_read(CSR_BASE + OFF_DIM_M, v);    check_eq32("reset: dim_m reads 0", v, 32'h0);
      apb_read(CSR_BASE + OFF_DIM_N, v);    check_eq32("reset: dim_n reads 0", v, 32'h0);
      apb_read(CSR_BASE + OFF_DIM_K, v);    check_eq32("reset: dim_k reads 0", v, 32'h0);
      apb_read(CSR_BASE + OFF_NPU_CTRL, v); check_eq32("reset: npu_ctrl reads 0", v, 32'h0);
      check_true("reset: no DMA request while idle", dma_valid === 1'b0);
    end
  endtask

  // ==================================================================
  // TEST 2: APB register map (orig 2); out-of-range reads return 0 here
  // ==================================================================
  task automatic test_apb_register_map();
    logic [31:0] v;
    begin
      apb_write(CSR_BASE + OFF_SRC_A, 32'hA5A5_A5A0);
      apb_read (CSR_BASE + OFF_SRC_A, v);   check_eq32("apb: src_a write/readback", v, 32'hA5A5_A5A0);
      apb_write(CSR_BASE + OFF_SRC_B, 32'h5A5A_5A50);
      apb_read (CSR_BASE + OFF_SRC_B, v);   check_eq32("apb: src_b write/readback", v, 32'h5A5A_5A50);
      apb_write(CSR_BASE + OFF_DEST_C, 32'h1234_5670);
      apb_read (CSR_BASE + OFF_DEST_C, v);  check_eq32("apb: dest_c write/readback", v, 32'h1234_5670);

      apb_write(CSR_BASE + OFF_DIM_M, 32'd4);
      apb_read (CSR_BASE + OFF_DIM_M, v);   check_eq32("apb: dim_m write/readback", v, 32'd4);
      apb_write(CSR_BASE + OFF_DIM_N, 32'd3);
      apb_read (CSR_BASE + OFF_DIM_N, v);   check_eq32("apb: dim_n write/readback", v, 32'd3);
      apb_write(CSR_BASE + OFF_DIM_K, 32'd2);
      apb_read (CSR_BASE + OFF_DIM_K, v);   check_eq32("apb: dim_k write/readback", v, 32'd2);

      // dim_* keep bits [2:0] only (unpu_csr): upper bits of the written word are dropped
      apb_write(CSR_BASE + OFF_DIM_M, 32'hFFFF_FFFD);
      apb_read (CSR_BASE + OFF_DIM_M, v);   check_eq32("apb: dim_m keeps only bits[2:0]", v, 32'd5);
      apb_write(CSR_BASE + OFF_DIM_N, 32'hFFFF_FFFE);
      apb_read (CSR_BASE + OFF_DIM_N, v);   check_eq32("apb: dim_n keeps only bits[2:0]", v, 32'd6);
      apb_write(CSR_BASE + OFF_DIM_K, 32'hFFFF_FFFF);
      apb_read (CSR_BASE + OFF_DIM_K, v);   check_eq32("apb: dim_k keeps only bits[2:0]", v, 32'd7);
      // leave legal values behind
      apb_write(CSR_BASE + OFF_DIM_M, 32'd4);
      apb_write(CSR_BASE + OFF_DIM_N, 32'd4);
      apb_write(CSR_BASE + OFF_DIM_K, 32'd4);

      // npu_ctrl: bit1 SIGNED stored, bit0 START never stored (reads 0). No
      // bit0 write here: that would start an op.
      apb_write(CSR_BASE + OFF_NPU_CTRL, 32'hFFFF_FFFE);
      apb_read (CSR_BASE + OFF_NPU_CTRL, v); check_eq32("apb: npu_ctrl SIGNED reads back, bit0 reads 0", v, 32'h0000_0002);
      apb_write(CSR_BASE + OFF_NPU_CTRL, 32'h0000_0000);
      apb_read (CSR_BASE + OFF_NPU_CTRL, v); check_eq32("apb: npu_ctrl cleared", v, 32'h0000_0000);

      // npu_status is read-only: a write has no effect
      apb_write(CSR_BASE + OFF_NPU_STAT, 32'hFFFF_FFFF);
      apb_read (CSR_BASE + OFF_NPU_STAT, v); check_eq32("apb: write to read-only npu_status ignored", v, 32'h0);

      // Unmapped offsets (sel 8..1023): the peer expected 32'hDEAD_BEEF; this
      // design reads 0 and ignores writes there.
      apb_read(CSR_BASE + 32'h20, v);  check_eq32("apb: unmapped read (first, 0x20) returns 0", v, 32'h0);
      apb_read(CSR_BASE + 32'h40, v);  check_eq32("apb: unmapped read (0x40) returns 0", v, 32'h0);
      apb_read(CSR_BASE + 32'hFC, v);  check_eq32("apb: far unmapped read (0xFC) returns 0", v, 32'h0);
      apb_read(CSR_BASE + 32'hFFC, v); check_eq32("apb: last unmapped read (0xFFC) returns 0", v, 32'h0);
      apb_write(CSR_BASE + 32'h20,  32'hFFFF_FFFF);
      apb_write(CSR_BASE + 32'hFFC, 32'hFFFF_FFFF);
      apb_read(CSR_BASE + 32'h20, v);  check_eq32("apb: write to unmapped 0x20 had no effect", v, 32'h0);
      apb_read(CSR_BASE + 32'hFFC, v); check_eq32("apb: write to unmapped 0xFFC had no effect", v, 32'h0);
      apb_read(CSR_BASE + OFF_SRC_A, v);  check_eq32("apb: unmapped writes left src_a intact", v, 32'hA5A5_A5A0);
      apb_read(CSR_BASE + OFF_SRC_B, v);  check_eq32("apb: unmapped writes left src_b intact", v, 32'h5A5A_5A50);
      apb_read(CSR_BASE + OFF_DEST_C, v); check_eq32("apb: unmapped writes left dest_c intact", v, 32'h1234_5670);
      apb_read(CSR_BASE + OFF_NPU_STAT, v); check_eq32("apb: unmapped writes left npu_status idle", v, 32'h0);
      check_true("apb: register-map tests started no DMA activity", dma_valid === 1'b0);
    end
  endtask

  // ==================================================================
  // TEST 3: illegal config (orig 3) -> ERROR; cleared by the next legal START
  // ==================================================================
  task automatic test_invalid_config();
    logic [31:0] status;
    int poll_res;
    int which, vi, dm, dn, dk, bad_val, f0;
    string nm;
    begin
      for (which = 0; which < 3; which = which + 1) begin
        for (vi = 0; vi < 3; vi = vi + 1) begin
          case (vi)
            0: bad_val = 0;
            1: bad_val = 5;
            default: bad_val = 7;
          endcase
          dm = (which == 0) ? bad_val : 2;
          dn = (which == 1) ? bad_val : 2;
          dk = (which == 2) ? bad_val : 2;
          nm = $sformatf("invalid_cfg %s=%0d", (which == 0) ? "dim_m" : (which == 1) ? "dim_n" : "dim_k", bad_val);
          f0 = fail_count;
          rounds_run = rounds_run + 1;

          blog_n = 0;
          sram_stall_mode = 2'd0;
          apb_write(CSR_BASE + OFF_SRC_A,  32'h0000_0100);
          apb_write(CSR_BASE + OFF_SRC_B,  32'h0000_0200);
          apb_write(CSR_BASE + OFF_DEST_C, 32'h0000_0300);
          apb_write(CSR_BASE + OFF_DIM_M,  32'(dm));
          apb_write(CSR_BASE + OFF_DIM_N,  32'(dn));
          apb_write(CSR_BASE + OFF_DIM_K,  32'(dk));
          apb_start(1'b0);
          wait_for_completion(1000, poll_res);
          apb_read(CSR_BASE + OFF_NPU_STAT, status);
          check_true({nm, " : reported ERROR (not DONE, no timeout)"}, poll_res == 1);
          check_eq32({nm, " : npu_status = ERROR + error_code 1"}, status, 32'h0000_0006);
          repeat (20) step();
          apb_read(CSR_BASE + OFF_NPU_STAT, status);
          check_eq32({nm, " : ERROR is sticky"}, status, 32'h0000_0006);
          check_true({nm, " : no DMA beat accepted"}, blog_n == 0);
          check_true({nm, " : no DMA request pending"}, dma_valid === 1'b0);
          if (fail_count == f0) begin
            rounds_pass = rounds_pass + 1;
            $display("PASS : %s", nm);
          end

          // the next legal START from the ERROR state must work and clear ERROR
          fill_W_random(1);
          fill_A_random(1);
          run_matmul_round({nm, " -> legal recovery round"}, 32'h0000_0410, 32'h0000_0400, 32'h0000_0500,
                           2, 2, 2, 1'b0, 2'd0);
        end
      end
    end
  endtask

  // ==================================================================
  // TEST 4: directed extreme-value corners (orig 4), every round both modes
  // ==================================================================
  task automatic test_extreme_corners();
    begin
      fill_W_const(8'hFF);
      fill_A_const(8'hFF);
      run_both_modes("extreme: W=0xFF A=0xFF (max accumulation)",           32'h0000_1000, 32'h0000_1100, 2'd0);
      run_both_modes("extreme: W=0xFF A=0xFF, random-stall SRAM",           32'h0000_1000, 32'h0000_1100, 2'd1);
      run_both_modes("extreme: W=0xFF A=0xFF, burst-stall SRAM",            32'h0000_1000, 32'h0000_1100, 2'd2);

      fill_W_const(8'h00);
      fill_A_const(8'h00);
      run_both_modes("extreme: W=0x00 A=0x00",                              32'h0000_1200, 32'h0000_1300, 2'd0);

      fill_W_const(8'h00);
      fill_A_const(8'hFF);
      run_both_modes("extreme: W=0x00 A=0xFF",                              32'h0000_1400, 32'h0000_1500, 2'd1);

      fill_W_identity();
      fill_A_const(8'hFF);
      run_both_modes("extreme: identity(W) A=0xFF (pass-through check)",    32'h0000_1600, 32'h0000_1700, 2'd0);

      fill_W_const(8'hFF);
      fill_A_identity();
      run_both_modes("extreme: W=0xFF identity(A)",                         32'h0000_1800, 32'h0000_1900, 2'd2);

      fill_W_pattern_edges();
      fill_A_pattern_edges();
      run_both_modes("extreme: boundary-value checkerboard both operands",  32'h0000_1A00, 32'h0000_1B00, 2'd1);

      fill_W_const(8'h00);
      fill_A_const(8'h00);
      tb_W[0] = 8'hFF; tb_A[0] = 8'hFF; // W[0][0], A[0][0]
      run_both_modes("extreme: single hot element W[0][0]=A[0][0]=0xFF",    32'h0000_1C00, 32'h0000_1D00, 2'd0);

      fill_W_const(8'h00);
      fill_A_const(8'h00);
      tb_W[15] = 8'hFF; tb_A[15] = 8'hFF; // W[3][3], A[3][3]
      run_both_modes("extreme: single hot element W[3][3]=A[3][3]=0xFF (last PE)", 32'h0000_1E00, 32'h0000_1F00, 2'd0);
    end
  endtask

  // ==================================================================
  // ADDED: signed corner cases (the peer's file is unsigned-only)
  // ==================================================================
  function automatic logic [7:0] signed_corner(input int idx);
    case (idx)
      0: signed_corner = 8'h80;   // -128
      1: signed_corner = 8'h7F;   // +127
      default: signed_corner = 8'hFF;   // -1
    endcase
  endfunction

  task automatic test_signed_corners();
    int wi, ai, i;
    begin
      for (wi = 0; wi < 3; wi = wi + 1)
        for (ai = 0; ai < 3; ai = ai + 1) begin
          fill_W_const(signed_corner(wi));
          fill_A_const(signed_corner(ai));
          run_both_modes($sformatf("signed corner: W=0x%02h A=0x%02h", signed_corner(wi), signed_corner(ai)),
                         32'h0000_4000, 32'h0000_4100, 2'((wi + ai) % 3));
        end
      // mixed lane patterns of the three corner values
      for (i = 0; i < 16; i = i + 1) begin
        tb_W[i] = signed_corner((i * 5 + 1) % 3);
        tb_A[i] = signed_corner((i * 7 + 2) % 3);
      end
      run_both_modes("signed corner: mixed 0x80/0x7F/0xFF lanes (pattern 1)", 32'h0000_4200, 32'h0000_4300, 2'd1);
      for (i = 0; i < 16; i = i + 1) begin
        tb_W[i] = (i % 2 == 0) ? 8'h80 : 8'h7F;
        tb_A[i] = ((i / 4) % 2 == 0) ? 8'h7F : 8'h80;
      end
      run_both_modes("signed corner: mixed 0x80/0x7F lanes (pattern 2)",      32'h0000_4400, 32'h0000_4500, 2'd2);
    end
  endtask

  // ==================================================================
  // TEST 5: every legal (dim_m, dim_k, dim_n) in 1..4 (replaces orig 5)
  // ==================================================================
  task automatic test_mnk_sweep();
    int m, k, n, idx;
    begin
      idx = 0;
      for (m = 1; m <= 4; m = m + 1)
        for (k = 1; k <= 4; k = k + 1)
          for (n = 1; n <= 4; n = n + 1) begin
            fill_W_random(1);
            fill_A_random(1);
            run_matmul_round($sformatf("mnk M=%0d K=%0d N=%0d [unsigned]", m, k, n),
                             32'h0000_0710, 32'h0000_0700, 32'h0000_0800, m, k, n, 1'b0, 2'(idx % 3));
            run_matmul_round($sformatf("mnk M=%0d K=%0d N=%0d [signed]", m, k, n),
                             32'h0000_0710, 32'h0000_0700, 32'h0000_0800, m, k, n, 1'b1, 2'(idx % 3));
            idx = idx + 1;
          end
    end
  endtask

  // ==================================================================
  // TEST 6: adjacent regions (orig 6): W, A and C directly one after another
  // ==================================================================
  task automatic test_overlap_addresses();
    begin
      fill_W_random(1);
      fill_A_random(1);
      // W at 0x2000 (16 B), A at 0x2010 (16 B), C at 0x2020 -- no gap
      run_both_modes("overlap: C region immediately follows the W/A load region", 32'h0000_2000, 32'h0000_2020, 2'd0);
    end
  endtask

  // ==================================================================
  // TEST 7: abort mid-transfer (replaces orig 7: no soft reset exists)
  // ==================================================================
  task automatic test_reset_abort();
    logic [31:0] status, v;
    int f0;
    begin
      f0 = fail_count;
      rounds_run = rounds_run + 1;
      fill_W_random(1);
      fill_A_random(1);
      prepare_round(32'h0000_0310, 32'h0000_0300, 32'h0000_0400, 4, 4, 4, 1'b0, 2'd0);
      program_and_start(32'h0000_0310, 32'h0000_0300, 32'h0000_0400, 4, 4, 4, 1'b0);

      // let it run a few cycles into the load phase, then abort with rst_n
      repeat (3) step();
      check_true("reset_abort: op is in flight when rst_n is asserted (request pending or beats taken)",
                 dma_valid === 1'b1 || blog_n > 0);
      rst_n = 1'b0;
      step();
      step();
      rst_n = 1'b1;
      blog_n = 0;

      repeat (5) step();
      apb_read(CSR_BASE + OFF_NPU_STAT, status);
      check_eq32("reset_abort: mid-load abort returns to idle (npu_status 0)", status, 32'h0);
      apb_read(CSR_BASE + OFF_SRC_A, v);  check_eq32("reset_abort: src_a cleared by reset", v, 32'h0);
      apb_read(CSR_BASE + OFF_DIM_M, v);  check_eq32("reset_abort: dim_m cleared by reset", v, 32'h0);
      repeat (60) step();
      check_true("reset_abort: no DMA beat after the abort", blog_n == 0);
      check_true("reset_abort: no DMA request after the abort", dma_valid === 1'b0);
      if (fail_count == f0) begin
        rounds_pass = rounds_pass + 1;
        $display("PASS : reset_abort: mid-load rst_n abort returns to a quiet idle");
      end

      // now a clean round must still work correctly afterwards (registers
      // were cleared, so run_matmul_round reprograms everything)
      run_matmul_round("reset_abort: recovery round is correct", 32'h0000_0310, 32'h0000_0300, 32'h0000_0400,
                       4, 4, 4, 1'b0, 2'd0);
    end
  endtask

  // ==================================================================
  // TEST 8: redundant START while busy must be ignored (orig 8)
  // ==================================================================
  task automatic test_start_while_busy();
    logic [31:0] before_src, status;
    int total_beats, blog_final;
    begin
      fill_W_random(1);
      fill_A_random(1);
      prepare_round(32'h0000_0510, 32'h0000_0500, 32'h0000_0600, 4, 4, 4, 1'b0, 2'd2);   // slow SRAM
      program_and_start(32'h0000_0510, 32'h0000_0500, 32'h0000_0600, 4, 4, 4, 1'b0);

      repeat (4) step();
      apb_read(CSR_BASE + OFF_SRC_A, before_src);
      check_eq32("start_while_busy: src_a register holds the programmed value", before_src, 32'h0000_0510);
      total_beats = 4 + 4 + 16;
      apb_read(CSR_BASE + OFF_NPU_STAT, status);
      check_true("start_while_busy: op is genuinely busy at the redundant START (beats taken, not all, not DONE)",
                 blog_n > 0 && blog_n < total_beats && status[0] === 1'b0);
      // redundant START with a DIFFERENT src_a staged and the OPPOSITE mode:
      // the running op's latched configuration must win
      apb_write(CSR_BASE + OFF_SRC_A, 32'hDEAD_0000);
      apb_start(1'b1);

      finish_round("start_while_busy: redundant START ignored, result still correct",
                   32'h0000_0510, 32'h0000_0500, 32'h0000_0600, 4, 4, 4, 1'b0);

      // an ignored START must not queue a second op
      blog_final = blog_n;
      repeat (200) step();
      apb_read(CSR_BASE + OFF_NPU_STAT, status);
      check_true("start_while_busy: no further DMA beats after DONE", blog_n == blog_final);
      check_eq32("start_while_busy: npu_status[1:0] still DONE only", {30'd0, status[1:0]}, 32'h0000_0001);
      sram_stall_mode = 2'd0;
    end
  endtask

  // ==================================================================
  // TEST 9: back-to-back rounds, no idle gap (orig 9), both modes
  // ==================================================================
  task automatic test_back_to_back();
    int i;
    logic [1:0] sm;
    begin
      for (i = 0; i < 5; i = i + 1) begin
        fill_W_random(1);
        fill_A_random(1);
        sm = 2'(draw_mod(3));
        run_both_modes($sformatf("back_to_back round %0d", i), 32'h0000_3000, 32'h0000_3100, sm);
      end
    end
  endtask

  // ==================================================================
  // TEST 10: stuck SRAM (replaces orig 10: this design has no watchdog)
  // ==================================================================
  task automatic test_stuck_sram();
    logic [31:0] status;
    int f0;
    begin
      f0 = fail_count;
      rounds_run = rounds_run + 1;
      fill_W_random(1);
      fill_A_random(1);
      prepare_round(32'h0000_0910, 32'h0000_0900, 32'h0000_0A00, 4, 4, 4, 1'b1, 2'd3);   // never ready
      program_and_start(32'h0000_0910, 32'h0000_0900, 32'h0000_0A00, 4, 4, 4, 1'b1);

      repeat (STUCK_HOLD_CYCLES / 2) step();
      apb_read(CSR_BASE + OFF_NPU_STAT, status);
      check_eq32("stuck_sram: mid-hold npu_status[1:0] (no DONE, no ERROR)", {30'd0, status[1:0]}, 32'h0);
      repeat (STUCK_HOLD_CYCLES / 2) step();
      apb_read(CSR_BASE + OFF_NPU_STAT, status);
      check_eq32("stuck_sram: end-of-hold npu_status[1:0] (no DONE, no ERROR)", {30'd0, status[1:0]}, 32'h0);
      check_true("stuck_sram: request still asserted after the hold", dma_valid === 1'b1);
      check_true("stuck_sram: no beat accepted while the SRAM is never ready", blog_n == 0);
      if (fail_count == f0) begin
        rounds_pass = rounds_pass + 1;
        $display("PASS : stuck_sram: block holds quietly with the SRAM never ready");
      end
      // (the resume-and-complete half is its own round, below)
      sram_stall_mode = 2'd0;
      finish_round("stuck_sram: completes correctly once ready returns [signed]",
                   32'h0000_0910, 32'h0000_0900, 32'h0000_0A00, 4, 4, 4, 1'b1);
    end
  endtask

  // ==================================================================
  // TEST 11: randomized regression (orig 11)
  // ==================================================================
  task automatic test_random_regression();
    int i;
    int unsigned slot_s, slot_d;
    logic [31:0] src_b_a, src_a_a, dst_a;
    logic [1:0]  sm;
    begin
      for (i = 0; i < NUM_RANDOM_TESTS; i = i + 1) begin
        fill_W_random(1);
        fill_A_random(1);

        // 64-byte slots across the whole window: src region (32 B) and dst
        // region (64 B) each sit inside their own slot, and the two slots are
        // DISTINCT and IN RANGE BY CONSTRUCTION. Iterations 0 and 1 pin the
        // two window edges.
        if (i == 0) begin
          slot_s = 0;
          slot_d = N_SLOTS - 1;
        end else if (i == 1) begin
          slot_s = N_SLOTS - 1;
          slot_d = 0;
        end else begin
          slot_s = draw_mod(N_SLOTS);
          slot_d = draw_mod(N_SLOTS - 1);
          if (slot_d >= slot_s) slot_d = slot_d + 1;
        end
        src_b_a = 32'(slot_s) * 32'(SLOT_BYTES);
        src_a_a = src_b_a + 32'd16;
        dst_a   = 32'(slot_d) * 32'(SLOT_BYTES);
        sm = 2'(draw_mod(3));

        check_true($sformatf("random[%0d] slots distinct (construction)", i), slot_s != slot_d);
        run_both_modes($sformatf("random[%0d] src=0x%08h dst=0x%08h mode=%0d", i, src_b_a, dst_a, sm),
                       src_b_a, dst_a, sm);
      end
    end
  endtask

  // ==================================================================
  // Main sequence
  // ==================================================================
  initial begin
    psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
    sram_stall_mode = 2'd0;
    blog_n = 0;
    g_rng = SEED_MAIN;

    $display("=================================================================");
    $display(" UNPU external stress testbench (ext2) starting");
    $display(" seeds: SEED_MAIN=0x%08h (operands/addresses/modes) SEED_SRAM=0x%08h (stall mode 1)", SEED_MAIN, SEED_SRAM);
    $display(" model SRAM window: %0d words (%0d KiB); %0d random-sweep slots of %0d bytes",
             MEM_WORDS, MEM_WORDS * 4 / 1024, N_SLOTS, SLOT_BYTES);
    $display("=================================================================");

    rst_n = 0;
    repeat (5) @(posedge clk);
    #1;
    rst_n = 1;
    repeat (5) step();

    test_reset_state();
    test_apb_register_map();
    $display("sections 1-2 (reset, register map): checks=%0d", checks);
    test_invalid_config();
    $display("section 3 (illegal config + recovery): checks=%0d", checks);
    test_extreme_corners();
    $display("section 4 (extreme corners, both modes): checks=%0d", checks);
    test_signed_corners();
    $display("section 4b (added signed corners): checks=%0d", checks);
    test_mnk_sweep();
    $display("section 5 (full M/N/K sweep, both modes): checks=%0d", checks);
    test_overlap_addresses();
    test_reset_abort();
    test_start_while_busy();
    $display("sections 6-8 (adjacent regions, reset abort, start while busy): checks=%0d", checks);
    test_back_to_back();
    test_stuck_sram();
    $display("sections 9-10 (back-to-back, stuck SRAM): checks=%0d", checks);
    test_random_regression();
    $display("section 11 (random regression): checks=%0d", checks);

    $display("=================================================================");
    $display(" TEST SUMMARY");
    $display("   rounds: %0d run, %0d passed", rounds_run, rounds_pass);
    $display("checked %0d value(s)/assertion(s) total", checks);
    if (fail_count == 0)
      $display("ALL TESTS PASSED");
    else
      $display("TESTS FAILED: %0d failure(s)", fail_count);
    $display("=================================================================");
    $finish;
  end

endmodule
