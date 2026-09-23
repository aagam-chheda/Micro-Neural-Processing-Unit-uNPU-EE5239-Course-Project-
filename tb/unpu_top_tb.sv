// CPU's-eye-view integration test for unpu_top. Drives the DUT through
// its two ports -- APB (paddr/pwdata/pwrite/psel/penable/prdata/pready,
// task 018) and native (dma_*) -- no hierarchical whitebox access to
// check intermediate state, unlike some earlier testbenches that used it
// for specific settling checks. That's the actual point of this test:
// proving the block works exactly the way a real CPU (or the SPI debug
// backdoor) would see it. Task 018 reverts the CPU<->NPU register port
// from native (task 010/012) back to APB, per the user/PM/SoC-top team's
// decision, and fully retires task 017's provisional npu_enable/
// npu_start_req protocol -- APB's own psel/penable handshake already
// covers what those signals were approximating, so the four directed
// cases task 017 added for them are gone too, not carried forward.
//
// CSR offsets and the SIGNED-bit polarity come straight from task 009's
// file (docs/planning/tasks/009-csr.md): src_A=0x00, src_B=0x04,
// dest_C=0x08, dim_M=0x0C, dim_N=0x10, dim_K=0x14, npu_ctrl=0x18 (bit0
// START, bit1 SIGNED), npu_status=0x1C (bit0 DONE, bit1 ERROR, bits[4:2]
// error_code). bit1=1 means SIGNED, so unpu_csr's mode_unsigned output
// is the INVERSE of what gets written -- getting this backwards here
// would be a whole-system repeat of the bug task 009's own directed test
// already exists to catch one layer down.
//
// Addresses are the full 32'h4000_0000-relative absolute address, not
// the bare offset -- exercising unpu_apb's own documented assumption
// (task 018, carried over from task 010's native slave: address already
// window-filtered) with a realistic address.
//
// Loop-structure note (tasks 008/011's lesson, carried forward): every
// "wait for done" loop is a bounded `for` with an explicit cap.
//
// Simulated with Verilator (--binary --timing), consistent with every
// task since 006.
`timescale 1ns/1ps

module unpu_top_tb;

  logic clk, rst_n;

  logic [31:0] paddr, pwdata, prdata;
  logic        pwrite, psel, penable, pready;

  logic [31:0] dma_addr, dma_wdata, dma_rdata;
  logic [3:0]  dma_wstrb;
  logic        dma_valid, dma_ready;

  unpu_top dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .paddr     (paddr),
    .pwdata    (pwdata),
    .pwrite    (pwrite),
    .psel      (psel),
    .penable   (penable),
    .prdata    (prdata),
    .pready    (pready),
    .dma_addr  (dma_addr),
    .dma_wdata (dma_wdata),
    .dma_rdata (dma_rdata),
    .dma_wstrb (dma_wstrb),
    .dma_valid (dma_valid),
    .dma_ready (dma_ready)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  // ---- Behavioral SRAM model on the dma_* port, same design as tasks
  // 008/011: word-addressable, combinational read, randomized 0-5 cycle
  // per-beat back-pressure via a same-cycle-lookahead draw. ----
  //
  // Size: MEM_WORDS = 2**MEM_ADDR_BITS words (2 MiB). The CRV loop places
  // case i at 0x10_0000 + i*4096 (top end ~0x13F240), which needs 21 address
  // bits; the original 2**18-word / [19:2] model only reached 0xF_FFFF, so
  // those TB-side writes were out of range (task 030: Verilator silently
  // wrapped the index, a 4-state simulator drops the write and the DUT reads
  // x). The DUT-facing decode takes exactly MEM_ADDR_BITS address bits, so
  // it cannot go out of range. Two rules keep aliasing deliberate only:
  //   * TB-side computed indexes go through mem_ix() (bounds-checked), or,
  //     for the address-wraparound tests where aliasing is intended,
  //     through wrap_ix() (the same decode the DUT-facing assign uses);
  //   * the window monitor reports any DMA beat whose address has bits
  //     ABOVE the decode set unless the test declared wrap_expected. ----
  localparam int MEM_ADDR_BITS = 19;
  localparam int MEM_WORDS     = 1 << MEM_ADDR_BITS;
  logic [31:0] mem [0:MEM_WORDS-1];
  assign dma_rdata = mem[dma_addr[MEM_ADDR_BITS+1:2]];

  always_ff @(posedge clk) begin
    if (dma_valid && dma_ready && dma_wstrb == 4'hF)
      mem[dma_addr[MEM_ADDR_BITS+1:2]] <= dma_wdata;
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
      bp_rng        <= 32'h5eed000c;
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

  // ---- CSR window offsets (task 009), and the CPU-visible base
  // address for this macro. ----
  localparam logic [31:0] CSR_BASE     = 32'h4000_0000;
  localparam logic [31:0] OFF_SRC_A    = 32'h00;
  localparam logic [31:0] OFF_SRC_B    = 32'h04;
  localparam logic [31:0] OFF_DEST_C   = 32'h08;
  localparam logic [31:0] OFF_DIM_M    = 32'h0C;
  localparam logic [31:0] OFF_DIM_N    = 32'h10;
  localparam logic [31:0] OFF_DIM_K    = 32'h14;
  localparam logic [31:0] OFF_NPU_CTRL = 32'h18;
  localparam logic [31:0] OFF_NPU_STAT = 32'h1C;

  int errors, checks;

  // ---- Model-SRAM bounds discipline (task 030). mem_ix() turns a
  // byte-address + word-offset into a mem[] index and FAILS LOUDLY if it is
  // out of range, instead of leaving the outcome to whatever the simulator
  // does with an out-of-range array write (Verilator: wraps; Xcelium: drops
  // the write and reads back x). Returns 0 after reporting so the run
  // continues, but errors is already incremented. Not counted in `checks`:
  // it is a guard on the test's own addressing, not a DUT check. ----
  function automatic int mem_ix(input logic [31:0] byte_addr, input int word_off, input string who);
    logic [31:0] idx;
    begin
      idx = (byte_addr >> 2) + 32'(word_off);
      if (idx >= 32'(MEM_WORDS)) begin
        errors = errors + 1;
        $display("FAIL [mem bounds]: %s: byte_addr=0x%08h word_off=%0d -> word index %0d >= MEM_WORDS=%0d (out-of-range model-SRAM access)", who, byte_addr, word_off, idx, MEM_WORDS);
        mem_ix = 0;
      end else begin
        mem_ix = int'(idx);
      end
    end
  endfunction

  // Explicit, INTENDED aliasing for the address-wraparound tests: the word
  // index is the low MEM_ADDR_BITS of the (already 32-bit-wrapped) byte
  // address -- exactly the decode the DUT-facing assign applies, so the TB
  // and the model agree by construction rather than by accident.
  function automatic int wrap_ix(input logic [31:0] byte_addr);
    wrap_ix = int'(byte_addr[MEM_ADDR_BITS+1:2]);
  endfunction

  // Set by a test that DELIBERATELY drives addresses past the SRAM window
  // (32-bit wraparound cases); the window monitor then allows aliasing.
  logic wrap_expected;
  initial wrap_expected = 1'b0;

  always @(posedge clk) begin
    if (dma_valid && dma_ready && (dma_addr >> (MEM_ADDR_BITS + 2)) != 32'd0 && !wrap_expected) begin
      errors = errors + 1;
      $display("FAIL [mem window]: DMA beat at addr 0x%08h is outside the %0d-word model SRAM window but no wraparound was declared (aliasing would be silent)", dma_addr, MEM_WORDS);
    end
  end

  // Back-pressure overrides. Declared here, ahead of do_reset (their first
  // use), because IEEE 1800 requires declaration before use (Xcelium:
  // *E,UNDIDN). Semantics are described with the extreme-stall model below.
  logic        bp_mode_extreme; // 1 = wide 50-100 cycle/beat model instead of 0-5
  logic        force_stall;     // 1 = hold the current beat stalled indefinitely

  task automatic do_reset;
    begin
      rst_n = 0;
      paddr = 0; pwdata = 0; pwrite = 0; psel = 0; penable = 0;
      bp_rng = 32'h5eed000c;
      bp_mode_extreme = 1'b0;
      force_stall = 1'b0;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  // Drives one full APB transaction: SETUP (psel=1, penable=0) for one
  // cycle, then ACCESS (psel=1, penable=1) for one cycle -- the ACCESS
  // cycle is where a write actually commits and where prdata reflects
  // the read (task 018; see tb/unpu_apb_tb.sv for the unit-level version
  // of this same mechanics, including the directed test that a SETUP-
  // phase write must not commit).
  task automatic apb_write(input logic [31:0] addr, input logic [31:0] wdata);
    begin
      paddr = addr; pwdata = wdata; pwrite = 1'b1; psel = 1'b1; penable = 1'b0;
      step(); // SETUP
      penable = 1'b1;
      step(); // ACCESS -- commits
      psel = 1'b0; penable = 1'b0;
    end
  endtask

  task automatic apb_read(input logic [31:0] addr, output logic [31:0] rdata);
    begin
      paddr = addr; pwrite = 1'b0; psel = 1'b1; penable = 1'b0;
      step(); // SETUP
      penable = 1'b1;
      step(); // ACCESS -- prdata valid
      rdata = prdata;
      psel = 1'b0; penable = 1'b0;
    end
  endtask

  // ---- Loads <name>_{a,w,c}.hex (4x4-shaped, task 006 Part A format)
  // and packs A/W rows into the model SRAM at the given byte base
  // addresses -- identical convention to tb/unpu_dma_tb.sv (task 008). ----
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
        mem[mem_ix(base_a, r, "preload_case A")] = {a_case[r][3], a_case[r][2], a_case[r][1], a_case[r][0]};
        mem[mem_ix(base_w, r, "preload_case W")] = {w_case[r][3], w_case[r][2], w_case[r][1], w_case[r][0]};
      end
    end
  endtask

  // Drives one full op as real firmware would: write src_A/src_B/
  // dest_C/dim_M/dim_N/dim_K, then npu_ctrl LAST with START+SIGNED,
  // then poll npu_status (APB reads) until DONE, optionally with idle
  // gaps between polls (sparse CPU-side pacing). Every register access
  // is a full APB SETUP->ACCESS sequence (task 018).
  task automatic run_case_via_cpu(input string label, input logic [31:0] base_a, input logic [31:0] base_w,
                                   input logic [31:0] base_c, input int drv_m, input int drv_k, input int drv_n,
                                   input bit ctrl_signed_bit, input bit sparse_poll, output bit ok);
    logic [31:0] rdata;
    int poll_i, idle_i;
    begin
      apb_write(CSR_BASE + OFF_SRC_A,  base_a);
      apb_write(CSR_BASE + OFF_SRC_B,  base_w);
      apb_write(CSR_BASE + OFF_DEST_C, base_c);
      apb_write(CSR_BASE + OFF_DIM_M,  {29'd0, drv_m[2:0]});
      apb_write(CSR_BASE + OFF_DIM_N,  {29'd0, drv_n[2:0]});
      apb_write(CSR_BASE + OFF_DIM_K,  {29'd0, drv_k[2:0]});
      apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, ctrl_signed_bit, 1'b1}); // bit0=START, bit1=SIGNED

      ok = 1'b0;
      for (poll_i = 0; poll_i < 4000; poll_i = poll_i + 1) begin
        if (sparse_poll) begin
          for (idle_i = 0; idle_i < 3; idle_i = idle_i + 1)
            step();
        end
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
        if (rdata[0] == 1'b1) begin
          ok = 1'b1;
          break;
        end
      end
      checks = checks + 1;
      if (!ok) begin
        errors = errors + 1;
        $display("FAIL [%s]: npu_status DONE never observed within poll bound", label);
      end
    end
  endtask

  task automatic check_writeback(input string label, input logic [31:0] base_c, input int drv_m, input int drv_n);
    int m, j;
    begin
      for (m = 0; m < drv_m; m = m + 1) begin
        for (j = 0; j < drv_n; j = j + 1) begin
          checks = checks + 1;
          if (mem[mem_ix(base_c, m * 4 + j, "check_writeback")] !== c_case[m][j]) begin
            errors = errors + 1;
            $display("FAIL [%s]: mem C[%0d][%0d]=%0d expected %0d", label, m, j, mem[mem_ix(base_c, m * 4 + j, "check_writeback")], c_case[m][j]);
          end
        end
      end
    end
  endtask

  // ==== Task 028 (final, module 10): independent reference model +
  // shared adversarial helpers, combining every technique the campaign
  // built. ref_c_elem carries no persistent state between calls -- every
  // call recomputes its one C[m][j] from scratch off the A/W snapshots
  // and the actual dim_k passed in, same stateless discipline modules
  // 2-5/7 used, ruling out the class of bug task 019's first-draft PE
  // reference model had. ====
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

  // ~1/8 chance of a boundary extreme, same discipline every prior
  // module used.
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

  // ---- A SEPARATE, wider back-pressure model for extreme-stall testing
  // (50-200 cycles/beat), same additive approach tasks 023/025 used --
  // OFF by default (bp_mode_extreme==0 keeps dma_ready driven by the
  // original 0-5-cycle model exactly as before; force_stall (below) is a
  // third, independent override for holding a single beat indefinitely
  // on demand, used by Part A's mid-flight-polling case). ----
  logic [31:0] bp_ext_rng;
  logic [6:0]  bp_ext_delay_reg;
  logic        bp_ext_have_delay;
  logic [6:0]  bp_ext_delay_eff;

  assign bp_ext_delay_eff = bp_ext_have_delay ? bp_ext_delay_reg : (7'd50 + (bp_ext_rng[6:0] % 7'd51)); // 50-100
  assign dma_ready = force_stall ? 1'b0 :
                      dma_valid && (bp_mode_extreme ? (bp_ext_delay_eff == 7'd0) : (bp_delay_eff == 3'd0));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bp_ext_rng        <= 32'h5eed001c;
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

  // Same-shape APB write, but holds SETUP for setup_len cycles with
  // changing garbage paddr/pwdata first, committing only the final,
  // real (addr,wdata) pair -- module 9's Part A3 pattern, reused here to
  // mix adversarial pacing into a real op's own register-write sequence.
  task automatic apb_write_long_setup(input logic [31:0] addr, input logic [31:0] wdata, input int setup_len);
    int si;
    logic [31:0] rng_local;
    begin
      psel = 1'b1; penable = 1'b0; pwrite = 1'b1;
      rng_local = 32'hBADD_CAFE ^ addr;
      for (si = 0; si < setup_len; si = si + 1) begin
        rng_local = xorshift32(rng_local);
        paddr  = rng_local;
        pwdata = rng_local ^ 32'hFFFF_0000;
        step();
      end
      paddr  = addr;
      pwdata = wdata;
      step(); // one more SETUP cycle holding the real, final values
      penable = 1'b1;
      step(); // ACCESS -- commits
      psel = 1'b0; penable = 1'b0;
    end
  endtask

  // ---- Wraparound-aware preload/check: mirrors preload_case()/
  // check_writeback()'s own job exactly, but computes each word's real
  // 32-bit byte address via plain logic[31:0] arithmetic (which wraps at
  // 32 bits exactly like the DUT's own address registers do) and indexes
  // mem[] via wrap_ix() (that address's low MEM_ADDR_BITS slice) -- the SAME decode convention
  // dma_rdata's own assign already applies -- rather than preload_case's
  // plain (base>>2)+offset pointer arithmetic, which is only valid when
  // nothing wraps and would index far out of mem[]'s bounds otherwise. ----
  task automatic preload_case_wrap(input string name, input logic [31:0] base_a, input logic [31:0] base_w);
    int rr;
    logic [31:0] byte_addr;
    begin
      $readmemh({"model/vectors/", name, "_a.hex"}, a_case);
      $readmemh({"model/vectors/", name, "_w.hex"}, w_case);
      $readmemh({"model/vectors/", name, "_c.hex"}, c_case);
      for (rr = 0; rr < 4; rr = rr + 1) begin
        byte_addr = base_a + (32'(rr) * 32'd4);
        mem[wrap_ix(byte_addr)] = {a_case[rr][3], a_case[rr][2], a_case[rr][1], a_case[rr][0]};
        byte_addr = base_w + (32'(rr) * 32'd4);
        mem[wrap_ix(byte_addr)] = {w_case[rr][3], w_case[rr][2], w_case[rr][1], w_case[rr][0]};
      end
    end
  endtask

  // ==== Task 028 Part B helpers: synthetic per-op data generation +
  // checking (no golden.c vector file exists for arbitrary random
  // shapes), supporting both safe and wraparound-decoded addressing. ====
  logic [7:0] b_a_case [0:3][0:3];
  logic [7:0] b_w_case [0:3][0:3];

  task automatic gen_and_load_op_b(input logic [31:0] base_a, input logic [31:0] base_w, input bit use_wrap, ref logic [31:0] rng);
    int rr, cc;
    logic [31:0] byte_addr;
    begin
      for (rr = 0; rr < 4; rr = rr + 1)
        for (cc = 0; cc < 4; cc = cc + 1) begin
          b_a_case[rr][cc] = biased_byte(rng);
          b_w_case[rr][cc] = biased_byte(rng);
        end
      for (rr = 0; rr < 4; rr = rr + 1) begin
        if (use_wrap) begin
          byte_addr = base_a + (32'(rr) * 32'd4);
          mem[wrap_ix(byte_addr)] = {b_a_case[rr][3], b_a_case[rr][2], b_a_case[rr][1], b_a_case[rr][0]};
          byte_addr = base_w + (32'(rr) * 32'd4);
          mem[wrap_ix(byte_addr)] = {b_w_case[rr][3], b_w_case[rr][2], b_w_case[rr][1], b_w_case[rr][0]};
        end else begin
          mem[mem_ix(base_a, rr, "gen_and_load_op_b A")] = {b_a_case[rr][3], b_a_case[rr][2], b_a_case[rr][1], b_a_case[rr][0]};
          mem[mem_ix(base_w, rr, "gen_and_load_op_b W")] = {b_w_case[rr][3], b_w_case[rr][2], b_w_case[rr][1], b_w_case[rr][0]};
        end
      end
    end
  endtask

  task automatic check_op_b(input string label, input logic [31:0] base_c, input bit use_wrap,
                             input int drv_m, input int drv_n, input int drv_k, input bit mode_uns);
    int mm, jj;
    logic [31:0] byte_addr, exp_val, got_val;
    begin
      for (mm = 0; mm < drv_m; mm = mm + 1) begin
        for (jj = 0; jj < drv_n; jj = jj + 1) begin
          exp_val = ref_c_elem(b_w_case, b_a_case, mm, jj, drv_k, mode_uns);
          checks  = checks + 1;
          if (use_wrap) begin
            byte_addr = base_c + (32'(mm) * 32'd16) + (32'(jj) * 32'd4);
            got_val = mem[wrap_ix(byte_addr)];
          end else begin
            got_val = mem[mem_ix(base_c, mm * 4 + jj, "check_op_b")];
          end
          if (got_val !== exp_val) begin
            errors = errors + 1;
            $display("FAIL [%s]: C[%0d][%0d]=%0d expected %0d", label, mm, jj, got_val, exp_val);
          end
        end
      end
    end
  endtask

  // Drives one full legal op: 7-register config (optionally mixing
  // long-SETUP for src_A and npu_ctrl with zero-gap for the rest),
  // START, then polls npu_status (optionally sparse) until DONE.
  task automatic run_op_b(input string label, input logic [31:0] base_a, input logic [31:0] base_w, input logic [31:0] base_c,
                           input int drv_m, input int drv_k, input int drv_n, input bit drv_signed_bit,
                           input bit use_long_setup, input int setup_len_a, input int setup_len_ctrl,
                           input bit sparse_poll, output bit ok);
    int poll_i, idle_i;
    logic [31:0] rdata_b;
    begin
      if (use_long_setup)
        apb_write_long_setup(CSR_BASE + OFF_SRC_A, base_a, setup_len_a);
      else
        apb_write(CSR_BASE + OFF_SRC_A, base_a);
      apb_write(CSR_BASE + OFF_SRC_B,  base_w);
      apb_write(CSR_BASE + OFF_DEST_C, base_c);
      apb_write(CSR_BASE + OFF_DIM_M,  {29'd0, drv_m[2:0]});
      apb_write(CSR_BASE + OFF_DIM_N,  {29'd0, drv_n[2:0]});
      apb_write(CSR_BASE + OFF_DIM_K,  {29'd0, drv_k[2:0]});
      if (use_long_setup)
        apb_write_long_setup(CSR_BASE + OFF_NPU_CTRL, {30'd0, drv_signed_bit, 1'b1}, setup_len_ctrl);
      else
        apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, drv_signed_bit, 1'b1}); // bit0=START, bit1=SIGNED

      ok = 1'b0;
      for (poll_i = 0; poll_i < 6000; poll_i = poll_i + 1) begin
        if (sparse_poll) begin
          for (idle_i = 0; idle_i < 3; idle_i = idle_i + 1)
            step();
        end
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata_b);
        if (rdata_b[0] == 1'b1) begin
          ok = 1'b1;
          break;
        end
      end
      checks = checks + 1;
      if (!ok) begin
        errors = errors + 1;
        $display("FAIL [%s]: npu_status DONE never observed within poll bound", label);
      end
    end
  endtask

  // Drives one deliberately illegal op: 7-register config with one
  // dimension forced illegal, START, confirms ERROR + error_code==1.
  task automatic run_op_illegal_b(input string label, input int drv_m, input int drv_k, input int drv_n,
                                   input bit drv_signed_bit, output bit ok);
    int ii2;
    logic [31:0] rdata_b;
    begin
      apb_write(CSR_BASE + OFF_SRC_A,  32'd0);
      apb_write(CSR_BASE + OFF_SRC_B,  32'd0);
      apb_write(CSR_BASE + OFF_DEST_C, 32'd0);
      apb_write(CSR_BASE + OFF_DIM_M,  {29'd0, drv_m[2:0]});
      apb_write(CSR_BASE + OFF_DIM_N,  {29'd0, drv_n[2:0]});
      apb_write(CSR_BASE + OFF_DIM_K,  {29'd0, drv_k[2:0]});
      apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, drv_signed_bit, 1'b1});

      ok = 1'b0;
      for (ii2 = 0; ii2 < 100; ii2 = ii2 + 1) begin
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata_b);
        if (rdata_b[1] == 1'b1) begin
          ok = 1'b1;
          break;
        end
        step();
      end
      checks = checks + 1;
      if (!ok) begin
        errors = errors + 1;
        $display("FAIL [%s]: npu_status ERROR bit never observed", label);
      end else begin
        checks = checks + 1;
        if (rdata_b[4:2] !== 3'd1) begin
          errors = errors + 1;
          $display("FAIL [%s]: npu_status error_code=%0d expected 1", label, rdata_b[4:2]);
        end
      end
    end
  endtask

  task automatic check_writeback_wrap(input string label, input logic [31:0] base_c, input int drv_m, input int drv_n);
    int mm, jj;
    logic [31:0] byte_addr;
    begin
      for (mm = 0; mm < drv_m; mm = mm + 1) begin
        for (jj = 0; jj < drv_n; jj = jj + 1) begin
          byte_addr = base_c + (32'(mm) * 32'd16) + (32'(jj) * 32'd4);
          checks = checks + 1;
          if (mem[wrap_ix(byte_addr)] !== c_case[mm][jj]) begin
            errors = errors + 1;
            $display("FAIL [%s]: mem[wrapped addr=%0h idx=%0h] C[%0d][%0d]=%0d expected %0d",
                      label, byte_addr, wrap_ix(byte_addr), mm, jj, mem[wrap_ix(byte_addr)], c_case[mm][jj]);
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
  logic [31:0] rdata;
  bit ok, ctrl_signed_bit, sparse;

  initial begin
    errors = 0;
    checks = 0;

    // ==== Directed: cross_terms end to end, APB-port-only path ====
    do_reset();
    preload_case("cross_terms", 32'h0000_1000, 32'h0000_1100);
    run_case_via_cpu("cross_terms", 32'h0000_1000, 32'h0000_1100, 32'h0000_1200, 4, 4, 4, 1'b1, 1'b0, ok);
    check_writeback("cross_terms", 32'h0000_1200, 4, 4);

    // ==== Directed: seq_m1/seq_k1/seq_n1/seq_mixed ====
    do_reset();
    preload_case("seq_m1", 32'h0000_2000, 32'h0000_2100);
    run_case_via_cpu("seq_m1", 32'h0000_2000, 32'h0000_2100, 32'h0000_2200, 1, 4, 4, 1'b1, 1'b0, ok);
    check_writeback("seq_m1", 32'h0000_2200, 1, 4);

    do_reset();
    preload_case("seq_k1", 32'h0000_3000, 32'h0000_3100);
    run_case_via_cpu("seq_k1", 32'h0000_3000, 32'h0000_3100, 32'h0000_3200, 4, 1, 4, 1'b1, 1'b0, ok);
    check_writeback("seq_k1", 32'h0000_3200, 4, 4);

    do_reset();
    preload_case("seq_n1", 32'h0000_4000, 32'h0000_4100);
    run_case_via_cpu("seq_n1", 32'h0000_4000, 32'h0000_4100, 32'h0000_4200, 4, 4, 1, 1'b1, 1'b0, ok);
    check_writeback("seq_n1", 32'h0000_4200, 4, 1);

    // seq_mixed doubles as the sparse-CPU-side-polling directed case --
    // deliberate idle gaps between npu_status reads.
    do_reset();
    preload_case("seq_mixed", 32'h0000_5000, 32'h0000_5100);
    run_case_via_cpu("seq_mixed (sparse polling)", 32'h0000_5000, 32'h0000_5100, 32'h0000_5200, 3, 2, 3, 1'b1, 1'b1, ok);
    check_writeback("seq_mixed (sparse polling)", 32'h0000_5200, 3, 3);

    // ==== Directed: illegal config through the real register path ====
    do_reset();
    apb_write(CSR_BASE + OFF_SRC_A,  32'd0);
    apb_write(CSR_BASE + OFF_SRC_B,  32'd0);
    apb_write(CSR_BASE + OFF_DEST_C, 32'd0);
    apb_write(CSR_BASE + OFF_DIM_M,  32'd0); // illegal
    apb_write(CSR_BASE + OFF_DIM_N,  32'd4);
    apb_write(CSR_BASE + OFF_DIM_K,  32'd4);
    apb_write(CSR_BASE + OFF_NPU_CTRL, 32'h1); // START

    ok = 1'b0;
    for (i = 0; i < 20; i = i + 1) begin
      apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
      if (rdata[1] == 1'b1) begin
        ok = 1'b1;
        break;
      end
      step();
    end
    checks = checks + 1;
    if (!ok) begin
      errors = errors + 1;
      $display("FAIL [illegal dim_M=0]: npu_status ERROR bit never observed");
    end else begin
      checks = checks + 1;
      if (rdata[4:2] !== 3'd1) begin
        errors = errors + 1;
        $display("FAIL [illegal dim_M=0]: npu_status error_code=%0d expected 1", rdata[4:2]);
      end else begin
        $display("PASS [illegal dim_M=0]: npu_status ERROR=1, error_code=1, read back over APB");
      end
    end

    // Legal case immediately after, no reset -- confirms recovery.
    preload_case("cross_terms", 32'h0000_9000, 32'h0000_9100);
    run_case_via_cpu("post-error recovery: cross_terms", 32'h0000_9000, 32'h0000_9100, 32'h0000_9200, 4, 4, 4, 1'b1, 1'b0, ok);
    check_writeback("post-error recovery: cross_terms", 32'h0000_9200, 4, 4);

    // ==== CRV: all 64 crv_* cases, back to back, no reset between
    // them, through unpu_top's APB and dma_* ports only. ====
    do_reset();
    $display("CRV: running all 64 crv_* cases through unpu_top's APB port, back-pressure seed 32'h5eed000c");

    for (i = 0; i < 64; i = i + 1) begin
      crv_name = $sformatf("crv_%04d", i);
      fd = $fopen({"model/vectors/", crv_name, "_meta.txt"}, "r");
      if (fd == 0)
        $fatal(1, "could not open model/vectors/%s_meta.txt -- run model/golden first", crv_name);
      scan_rc = $fscanf(fd, "M=%d\nMODE=%s\nK=%d\nN=%d\n", meta_m, mode_str, meta_k, meta_n);
      $fclose(fd);
      if (scan_rc != 4)
        $fatal(1, "could not parse model/vectors/%s_meta.txt (got %0d fields)", crv_name, scan_rc);

      // Per-case address band (not reused across cases -- stale SRAM
      // content masking a real addressing bug is exactly the false
      // pass to avoid).
      base_a = 32'h0010_0000 + (32'(i) * 32'd4096);
      base_w = base_a + 32'd256;
      base_c = base_a + 32'd512;

      ctrl_signed_bit = (mode_str == "SIGNED") ? 1'b1 : 1'b0; // bit1=1 means SIGNED (polarity, task 009)
      sparse          = bp_rng[3]; // random subset gets sparse CPU-side polling pacing

      preload_case(crv_name, base_a, base_w);
      run_case_via_cpu(crv_name, base_a, base_w, base_c, meta_m, meta_k, meta_n, ctrl_signed_bit, sparse, ok);
      check_writeback(crv_name, base_c, meta_m, meta_n);
    end

    $display("CRV: 64 cases completed");

    // ==== Task 028, Part A1: address wraparound WITH real data
    // correctness. Module 7 (task 025) could only prove the DMA address
    // sequence itself wraps correctly -- its isolated model SRAM
    // couldn't represent content at a wrapped address coherently. Here,
    // with the real end-to-end datapath live, preload_case_wrap()/
    // check_writeback_wrap() use the exact same wrap_ix() decode convention
    // this file's own dma_rdata assign already applies, so this proves
    // the ACTUAL COMPUTED C values land correctly at wherever the
    // wraparound resolves to -- not just that addressing survives. ====
    begin : part_a1
      logic [31:0] wbase_a, wbase_w, wbase_c;
      do_reset();
      // base_a: row 0 at 0xFFFFFFFC, rows 1-3 wrap to 0x00000000/4/8.
      // base_w: same wraparound shape. base_c: M=N=4 writeback's max
      // offset is 3*16+3*4=60 bytes, so starting 32 bytes from the top
      // wraps partway through row 2.
      wbase_a = 32'hFFFF_FFFC;
      wbase_w = 32'hFFFF_FFE0;
      wbase_c = 32'hFFFF_FFE0;
      preload_case_wrap("cross_terms", wbase_a, wbase_w);
      wrap_expected = 1'b1; // intended aliasing: addresses wrap past 32'hFFFF_FFFF
      run_case_via_cpu("wraparound-with-data", wbase_a, wbase_w, wbase_c, 4, 4, 4, 1'b1, 1'b0, ok);
      wrap_expected = 1'b0;
      check_writeback_wrap("wraparound-with-data", wbase_c, 4, 4);
      $display("Part A1: address wraparound with real end-to-end data correctness (base_a/base_w/base_c all near 32'hFFFF_FFFF), checks=%0d so far", checks);
    end

    // ==== Task 028, Part A2: mid-flight register write during an active
    // op -- structurally impossible to test below the full-system level
    // (needs CSR, APB, DMA, and the sequencer all live simultaneously).
    // Starts a real op, injects config writes with DIFFERENT values
    // while it's still running (LATCH_CFG's shadow copy should protect
    // it), confirms the first op completes correctly, THEN starts a
    // second op and confirms it picks up exactly the values written
    // during the first op's run -- proving the shadow copy protects the
    // CURRENT op without silently discarding the NEXT one's config. ====
    begin : part_a2
      bit ok2a;
      logic [31:0] c_case_op1 [0:3][0:3]; // snapshot -- c_case is a shared scratch buffer that the second preload_case() call below overwrites
      int m2, j2;
      do_reset();
      preload_case("cross_terms", 32'h0004_0000, 32'h0004_0100);
      c_case_op1 = c_case; // snapshot cross_terms's own expected C before it gets clobbered
      apb_write(CSR_BASE + OFF_SRC_A,  32'h0004_0000);
      apb_write(CSR_BASE + OFF_SRC_B,  32'h0004_0100);
      apb_write(CSR_BASE + OFF_DEST_C, 32'h0004_0200);
      apb_write(CSR_BASE + OFF_DIM_M,  32'd4);
      apb_write(CSR_BASE + OFF_DIM_N,  32'd4);
      apb_write(CSR_BASE + OFF_DIM_K,  32'd4);
      apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, 1'b1, 1'b1}); // START+SIGNED

      repeat (20) step(); // well before DONE -- mid-fetch, genuinely in flight

      // Inject config writes with DIFFERENT values while the first op
      // is still running -- these are what the SECOND op (below) should
      // end up using.
      preload_case("seq_mixed", 32'h0004_1000, 32'h0004_1100);
      apb_write(CSR_BASE + OFF_SRC_A,  32'h0004_1000);
      apb_write(CSR_BASE + OFF_SRC_B,  32'h0004_1100);
      apb_write(CSR_BASE + OFF_DEST_C, 32'h0004_1200);
      apb_write(CSR_BASE + OFF_DIM_M,  32'd3);
      apb_write(CSR_BASE + OFF_DIM_N,  32'd3);
      apb_write(CSR_BASE + OFF_DIM_K,  32'd2);
      // Deliberately no npu_ctrl write here -- that would be a mid-
      // flight START, a different (also-interesting, but not this)
      // scenario; this case is about config writes landing mid-flight.

      ok2a = 1'b0;
      for (i = 0; i < 4000; i = i + 1) begin
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
        if (rdata[0] == 1'b1) begin
          ok2a = 1'b1;
          break;
        end
      end
      checks = checks + 1;
      if (!ok2a) begin
        errors = errors + 1;
        $display("FAIL [mid-flight-write]: first op (cross_terms) never completed after mid-flight config writes");
      end
      for (m2 = 0; m2 < 4; m2 = m2 + 1) begin
        for (j2 = 0; j2 < 4; j2 = j2 + 1) begin
          checks = checks + 1;
          if (mem[mem_ix(32'h0004_0200, m2 * 4 + j2, "mid-flight-write readback")] !== c_case_op1[m2][j2]) begin
            errors = errors + 1;
            $display("FAIL [mid-flight-write: first op unaffected]: mem C[%0d][%0d]=%0d expected %0d", m2, j2, mem[mem_ix(32'h0004_0200, m2 * 4 + j2, "mid-flight-write readback")], c_case_op1[m2][j2]);
          end
        end
      end

      // Second op: START now, using exactly the config written mid-
      // flight above -- confirms it was captured, not discarded.
      apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, 1'b1, 1'b1}); // START+SIGNED
      ok2a = 1'b0;
      for (i = 0; i < 4000; i = i + 1) begin
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
        if (rdata[0] == 1'b1) begin
          ok2a = 1'b1;
          break;
        end
      end
      checks = checks + 1;
      if (!ok2a) begin
        errors = errors + 1;
        $display("FAIL [mid-flight-write]: second op never completed");
      end
      check_writeback("mid-flight-write: second op correctly picks up mid-flight-written config (seq_mixed, M=3/K=2/N=3)", 32'h0004_1200, 3, 3);
      $display("Part A2: mid-flight register write during an active op -- first op unaffected, second op correctly picked up the mid-flight config, checks=%0d so far", checks);
    end

    // ==== Task 028, Part A3: mid-flight status polling during active
    // DMA beats. force_stall holds a real beat stalled indefinitely on
    // demand; while it's stalled, rapid npu_status reads are interleaved
    // -- confirms polling never disturbs the stalled operation itself,
    // and DONE eventually reads correctly once it actually completes.
    // Also structurally impossible below the full-system level: needs
    // CSR, APB, DMA, and the sequencer all live at once. ====
    begin : part_a3
      bit ok3a;
      int pi;
      do_reset();
      preload_case("cross_terms", 32'h0005_0000, 32'h0005_0100);
      force_stall = 1'b1; // before any register writes -- the very first DMA beat will stall the instant it's dispatched
      apb_write(CSR_BASE + OFF_SRC_A,  32'h0005_0000);
      apb_write(CSR_BASE + OFF_SRC_B,  32'h0005_0100);
      apb_write(CSR_BASE + OFF_DEST_C, 32'h0005_0200);
      apb_write(CSR_BASE + OFF_DIM_M,  32'd4);
      apb_write(CSR_BASE + OFF_DIM_N,  32'd4);
      apb_write(CSR_BASE + OFF_DIM_K,  32'd4);
      apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, 1'b1, 1'b1}); // START+SIGNED -- dispatches W_FETCH's first beat, which immediately stalls (force_stall=1)

      for (pi = 0; pi < 30; pi = pi + 1) begin
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
        checks = checks + 1;
        if (rdata[0] !== 1'b0) begin
          errors = errors + 1;
          $display("FAIL [mid-flight-polling]: npu_status DONE read as 1 at poll #%0d while the op is genuinely still stalled mid-beat", pi);
        end
      end

      force_stall = 1'b0; // release -- normal 0-5-cycle back-pressure resumes from here

      ok3a = 1'b0;
      for (i = 0; i < 4000; i = i + 1) begin
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
        if (rdata[0] == 1'b1) begin
          ok3a = 1'b1;
          break;
        end
      end
      checks = checks + 1;
      if (!ok3a) begin
        errors = errors + 1;
        $display("FAIL [mid-flight-polling]: op never completed after the stall was released");
      end
      check_writeback("mid-flight-polling: op completes correctly despite 30 interleaved status polls during a genuine mid-beat stall", 32'h0005_0200, 4, 4);
      $display("Part A3: mid-flight status polling during a genuinely stalled DMA beat never disturbed the operation, checks=%0d so far", checks);
    end

    // ==== Task 028, Part A4: maximum-speed config write -- a full
    // 7-register config sequence as zero-gap back-to-back APB
    // transactions (apb_write()'s own trailing psel=0/penable=0 and the
    // next call's leading psel=1 land in the same zero-simulation-time
    // window, module 9's own finding), repeated across several ops. ====
    begin : part_a4
      do_reset();
      preload_case("cross_terms", 32'h0006_0000, 32'h0006_0100);
      run_case_via_cpu("max-speed-config #0", 32'h0006_0000, 32'h0006_0100, 32'h0006_0200, 4, 4, 4, 1'b1, 1'b0, ok);
      check_writeback("max-speed-config #0", 32'h0006_0200, 4, 4);

      preload_case("seq_k1", 32'h0006_1000, 32'h0006_1100);
      run_case_via_cpu("max-speed-config #1", 32'h0006_1000, 32'h0006_1100, 32'h0006_1200, 4, 1, 4, 1'b1, 1'b0, ok);
      check_writeback("max-speed-config #1", 32'h0006_1200, 4, 4);

      preload_case("seq_n1", 32'h0006_2000, 32'h0006_2100);
      run_case_via_cpu("max-speed-config #2", 32'h0006_2000, 32'h0006_2100, 32'h0006_2200, 4, 4, 1, 1'b1, 1'b0, ok);
      check_writeback("max-speed-config #2", 32'h0006_2200, 4, 1);

      preload_case("seq_mixed", 32'h0006_3000, 32'h0006_3100);
      run_case_via_cpu("max-speed-config #3", 32'h0006_3000, 32'h0006_3100, 32'h0006_3200, 3, 2, 3, 1'b1, 1'b0, ok);
      check_writeback("max-speed-config #3", 32'h0006_3200, 3, 3);

      $display("Part A4: 4 ops, each with a full 7-register config sequence at zero-gap maximum APB rate, checks=%0d so far", checks);
    end

    // ==== Task 028, Part A5: combined extreme APB pacing through a real
    // op -- long-SETUP phases (module 9's pattern) mixed with zero-gap
    // writes within the SAME op's register-write sequence. ====
    begin : part_a5
      do_reset();
      preload_case("cross_terms", 32'h0007_0000, 32'h0007_0100);
      apb_write_long_setup(CSR_BASE + OFF_SRC_A,  32'h0007_0000, 30);
      apb_write(CSR_BASE + OFF_SRC_B,  32'h0007_0100); // zero-gap normal
      apb_write_long_setup(CSR_BASE + OFF_DEST_C, 32'h0007_0200, 25);
      apb_write(CSR_BASE + OFF_DIM_M,  32'd4);
      apb_write_long_setup(CSR_BASE + OFF_DIM_N,  32'd4, 15);
      apb_write(CSR_BASE + OFF_DIM_K,  32'd4);
      apb_write_long_setup(CSR_BASE + OFF_NPU_CTRL, {30'd0, 1'b1, 1'b1}, 20); // START+SIGNED, also via long-SETUP

      ok = 1'b0;
      for (i = 0; i < 4000; i = i + 1) begin
        apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
        if (rdata[0] == 1'b1) begin
          ok = 1'b1;
          break;
        end
      end
      checks = checks + 1;
      if (!ok) begin
        errors = errors + 1;
        $display("FAIL [combined-pacing]: op never completed");
      end
      check_writeback("combined-pacing: cross_terms configured via a mix of long-SETUP and zero-gap APB writes", 32'h0007_0200, 4, 4);
      $display("Part A5: combined extreme APB pacing (long-SETUP + zero-gap mixed within one op's config sequence), checks=%0d so far", checks);
    end

    // ==== Task 028, Part B: the maximal adversarial long-chain campaign.
    // >=30 independently-seeded sequences, each >=15 back-to-back ops,
    // zero reset between ops within a sequence. Every op combines: random
    // legal M/N/K/mode with random addresses (occasionally wraparound),
    // extreme-biased A/W data, ~10-15% deliberately illegal ops mixed in,
    // extreme DMA back-pressure (moderate + 50-100-cycle extreme mixed),
    // extreme APB pacing (zero-gap + long-SETUP + sparse polling mixed).
    // Fixed address bands are reused across ops relying on the
    // write-then-check-immediately discipline: each op's data is written
    // and checked before the next op reuses the same band. ====
    begin : part_b
      localparam int NUM_SEQ = 30;
      int seq_idx, op_idx, num_ops;
      logic [31:0] master_rng, seq_rng;
      int roll;
      bit use_wrap_b, use_bp_extreme_b, use_long_setup_b, sparse_poll_b, signed_bit_b;
      int drv_m_b, drv_k_b, drv_n_b, setup_len_a_b, setup_len_ctrl_b;
      logic [31:0] base_a_b, base_w_b, base_c_b;
      bit ok_b;
      int illeg_vals_b [0:3];
      int illeg_dim_b, illeg_val_b;
      int total_ops_b, total_illegal_b, total_wrap_b, total_bpext_b;

      illeg_vals_b[0] = 0;
      illeg_vals_b[1] = 5;
      illeg_vals_b[2] = 6;
      illeg_vals_b[3] = 7;

      master_rng = 32'h5eed011c;
      total_ops_b = 0;
      total_illegal_b = 0;
      total_wrap_b = 0;
      total_bpext_b = 0;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_rng = master_rng ^ (32'h9e3779b9 * (seq_idx + 1));
        do_reset();
        bp_mode_extreme = 1'b0;

        seq_rng = xorshift32(seq_rng);
        num_ops = 15 + (seq_rng % 3586); // 15..3600, scaled up so Part B's combined-adversarial total is the largest in the campaign

        for (op_idx = 0; op_idx < num_ops; op_idx = op_idx + 1) begin
          total_ops_b = total_ops_b + 1;

          seq_rng = xorshift32(seq_rng);
          roll = seq_rng % 100;

          seq_rng = xorshift32(seq_rng);
          use_bp_extreme_b = (seq_rng % 4) == 0; // ~25%
          bp_mode_extreme = use_bp_extreme_b;
          if (use_bp_extreme_b) total_bpext_b = total_bpext_b + 1;

          if (roll < 12) begin
            // ~12%: deliberately illegal op
            total_illegal_b = total_illegal_b + 1;
            seq_rng = xorshift32(seq_rng);
            illeg_dim_b = seq_rng % 3; // which of M/K/N goes illegal
            seq_rng = xorshift32(seq_rng);
            illeg_val_b = illeg_vals_b[seq_rng % 4];
            seq_rng = xorshift32(seq_rng);
            signed_bit_b = seq_rng[0];

            drv_m_b = 1 + (seq_rng % 4);
            seq_rng = xorshift32(seq_rng);
            drv_k_b = 1 + (seq_rng % 4);
            seq_rng = xorshift32(seq_rng);
            drv_n_b = 1 + (seq_rng % 4);

            case (illeg_dim_b)
              0: drv_m_b = illeg_val_b;
              1: drv_k_b = illeg_val_b;
              default: drv_n_b = illeg_val_b;
            endcase

            run_op_illegal_b($sformatf("partB seq=%0d op=%0d illegal(dim=%0d val=%0d)", seq_idx, op_idx, illeg_dim_b, illeg_val_b),
                              drv_m_b, drv_k_b, drv_n_b, signed_bit_b, ok_b);
          end else begin
            // legal op
            seq_rng = xorshift32(seq_rng);
            drv_m_b = 1 + (seq_rng % 4);
            seq_rng = xorshift32(seq_rng);
            drv_k_b = 1 + (seq_rng % 4);
            seq_rng = xorshift32(seq_rng);
            drv_n_b = 1 + (seq_rng % 4);
            seq_rng = xorshift32(seq_rng);
            signed_bit_b = seq_rng[0];

            seq_rng = xorshift32(seq_rng);
            use_wrap_b = (seq_rng % 16) == 0; // ~1/16
            seq_rng = xorshift32(seq_rng);
            use_long_setup_b = (seq_rng % 8) == 0; // ~1/8
            seq_rng = xorshift32(seq_rng);
            sparse_poll_b = (seq_rng % 4) == 0; // ~1/4

            if (use_wrap_b) begin
              total_wrap_b = total_wrap_b + 1;
              base_a_b = 32'hFFFF_FFFC;
              base_w_b = 32'hFFFF_FFE0;
              base_c_b = 32'hFFFF_FFE0;
            end else begin
              base_a_b = 32'h0008_0000;
              base_w_b = 32'h0008_0100;
              base_c_b = 32'h0008_0200;
            end

            setup_len_a_b    = 5 + (seq_rng % 20);
            seq_rng = xorshift32(seq_rng);
            setup_len_ctrl_b = 5 + (seq_rng % 20);

            gen_and_load_op_b(base_a_b, base_w_b, use_wrap_b, seq_rng);

            wrap_expected = use_wrap_b; // intended aliasing only for the wraparound ops
            run_op_b($sformatf("partB seq=%0d op=%0d legal(M=%0d K=%0d N=%0d wrap=%0b bpext=%0b longsetup=%0b sparse=%0b)",
                                seq_idx, op_idx, drv_m_b, drv_k_b, drv_n_b, use_wrap_b, use_bp_extreme_b, use_long_setup_b, sparse_poll_b),
                      base_a_b, base_w_b, base_c_b, drv_m_b, drv_k_b, drv_n_b, signed_bit_b,
                      use_long_setup_b, setup_len_a_b, setup_len_ctrl_b, sparse_poll_b, ok_b);
            wrap_expected = 1'b0;

            if (ok_b)
              check_op_b($sformatf("partB seq=%0d op=%0d legal", seq_idx, op_idx),
                         base_c_b, use_wrap_b, drv_m_b, drv_n_b, drv_k_b, ~signed_bit_b);
          end
        end
      end

      bp_mode_extreme = 1'b0;
      $display("Part B: %0d sequences, %0d total ops (%0d illegal, %0d wraparound, %0d under extreme back-pressure), checks=%0d so far",
                NUM_SEQ, total_ops_b, total_illegal_b, total_wrap_b, total_bpext_b, checks);
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
