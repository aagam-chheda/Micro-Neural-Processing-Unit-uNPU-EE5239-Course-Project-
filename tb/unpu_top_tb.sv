// CPU's-eye-view integration test for unpu_top. Drives the DUT through
// its two native ports (mem_* and dma_*) plus, as of task 017, the two
// interim npu_enable/npu_start_req pins -- no hierarchical whitebox
// access to check intermediate state, unlike some earlier testbenches
// that used it for specific settling checks, with one deliberate
// exception (task 017's edge-timing check, `dut.u_seq.busy`; see that
// test's own comment for why). That's the actual point of this test
// otherwise: proving the block works exactly the way a real CPU (or the
// SPI debug backdoor) would see it.
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
// the bare offset -- exercising unpu_slave's own documented assumption
// (task 010: address already window-filtered) with a realistic address.
//
// Loop-structure note (tasks 008/011's lesson, carried forward): every
// "wait for done" loop is a bounded `for` with an explicit cap.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006-011 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
`timescale 1ns/1ps

module unpu_top_tb;

  logic clk, rst_n;

  logic [31:0] mem_addr, mem_wdata, mem_rdata;
  logic [3:0]  mem_wstrb;
  logic        mem_valid, mem_ready;

  logic [31:0] dma_addr, dma_wdata, dma_rdata;
  logic [3:0]  dma_wstrb;
  logic        dma_valid, dma_ready;

  // Interim, provisional protocol (task 017) -- see rtl/unpu_top.sv's
  // header for what these are and why they're provisional.
  logic        npu_enable, npu_start_req;

  unpu_top dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .mem_addr      (mem_addr),
    .mem_wdata     (mem_wdata),
    .mem_wstrb     (mem_wstrb),
    .mem_valid     (mem_valid),
    .mem_rdata     (mem_rdata),
    .mem_ready     (mem_ready),
    .dma_addr      (dma_addr),
    .dma_wdata     (dma_wdata),
    .dma_rdata     (dma_rdata),
    .dma_wstrb     (dma_wstrb),
    .dma_valid     (dma_valid),
    .dma_ready     (dma_ready),
    .npu_enable    (npu_enable),
    .npu_start_req (npu_start_req)
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
  localparam int MEM_WORDS = 1 << 18; // 256K words, generous per-case address bands
  logic [31:0] mem [0:MEM_WORDS-1];
  assign dma_rdata = mem[dma_addr[19:2]];

  always_ff @(posedge clk) begin
    if (dma_valid && dma_ready && dma_wstrb == 4'hF)
      mem[dma_addr[19:2]] <= dma_wdata;
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

  task automatic do_reset;
    begin
      rst_n = 0;
      mem_addr = 0; mem_wdata = 0; mem_wstrb = 0; mem_valid = 0;
      // npu_enable defaults asserted -- every existing case's register
      // traffic runs with it held high for the whole case (task 017);
      // the two cases that need it deasserted set it to 0 explicitly and
      // don't rely on this default.
      npu_enable = 1'b1;
      npu_start_req = 1'b0;
      bp_rng = 32'h5eed000c;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  task automatic native_write(input logic [31:0] addr, input logic [31:0] wdata);
    begin
      mem_addr = addr; mem_wdata = wdata; mem_wstrb = 4'hF; mem_valid = 1'b1;
      step();
      mem_valid = 1'b0; mem_wstrb = 4'h0;
    end
  endtask

  task automatic native_read(input logic [31:0] addr, output logic [31:0] rdata);
    begin
      mem_addr = addr; mem_wstrb = 4'h0; mem_valid = 1'b1;
      step();
      rdata = mem_rdata;
      mem_valid = 1'b0;
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
        mem[(base_a >> 2) + r] = {a_case[r][3], a_case[r][2], a_case[r][1], a_case[r][0]};
        mem[(base_w >> 2) + r] = {w_case[r][3], w_case[r][2], w_case[r][1], w_case[r][0]};
      end
    end
  endtask

  // Drives one full op as real firmware would: write src_A/src_B/
  // dest_C/dim_M/dim_N/dim_K, then npu_ctrl LAST with START+SIGNED,
  // then poll npu_status (native reads) until DONE, optionally with
  // idle gaps between polls (sparse CPU-side pacing).
  task automatic run_case_via_cpu(input string label, input logic [31:0] base_a, input logic [31:0] base_w,
                                   input logic [31:0] base_c, input int drv_m, input int drv_k, input int drv_n,
                                   input bit ctrl_signed_bit, input bit sparse_poll, output bit ok);
    logic [31:0] rdata;
    int poll_i, idle_i;
    begin
      native_write(CSR_BASE + OFF_SRC_A,  base_a);
      native_write(CSR_BASE + OFF_SRC_B,  base_w);
      native_write(CSR_BASE + OFF_DEST_C, base_c);
      native_write(CSR_BASE + OFF_DIM_M,  {29'd0, drv_m[2:0]});
      native_write(CSR_BASE + OFF_DIM_N,  {29'd0, drv_n[2:0]});
      native_write(CSR_BASE + OFF_DIM_K,  {29'd0, drv_k[2:0]});
      native_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, ctrl_signed_bit, 1'b1}); // bit0=START, bit1=SIGNED

      ok = 1'b0;
      for (poll_i = 0; poll_i < 4000; poll_i = poll_i + 1) begin
        if (sparse_poll) begin
          for (idle_i = 0; idle_i < 3; idle_i = idle_i + 1)
            step();
        end
        native_read(CSR_BASE + OFF_NPU_STAT, rdata);
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

  // Drives one full op like run_case_via_cpu, but triggers START via a
  // rising edge on npu_start_req instead of npu_ctrl bit0 (task 017's
  // second, independent trigger path). npu_ctrl is still written, for
  // the SIGNED bit only (bit0=0 -- no register-write START this way).
  task automatic run_case_via_start_req(input string label, input logic [31:0] base_a, input logic [31:0] base_w,
                                         input logic [31:0] base_c, input int drv_m, input int drv_k, input int drv_n,
                                         input bit ctrl_signed_bit, output bit ok);
    logic [31:0] rdata;
    int poll_i;
    begin
      native_write(CSR_BASE + OFF_SRC_A,  base_a);
      native_write(CSR_BASE + OFF_SRC_B,  base_w);
      native_write(CSR_BASE + OFF_DEST_C, base_c);
      native_write(CSR_BASE + OFF_DIM_M,  {29'd0, drv_m[2:0]});
      native_write(CSR_BASE + OFF_DIM_N,  {29'd0, drv_n[2:0]});
      native_write(CSR_BASE + OFF_DIM_K,  {29'd0, drv_k[2:0]});
      native_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, ctrl_signed_bit, 1'b0}); // bit0=0 (no register-write START), bit1=SIGNED

      npu_start_req = 1'b1;
      step();
      npu_start_req = 1'b0;

      ok = 1'b0;
      for (poll_i = 0; poll_i < 4000; poll_i = poll_i + 1) begin
        native_read(CSR_BASE + OFF_NPU_STAT, rdata);
        if (rdata[0] == 1'b1) begin
          ok = 1'b1;
          break;
        end
      end
      checks = checks + 1;
      if (!ok) begin
        errors = errors + 1;
        $display("FAIL [%s]: npu_status DONE never observed within poll bound (npu_start_req trigger)", label);
      end
    end
  endtask

  task automatic check_writeback(input string label, input logic [31:0] base_c, input int drv_m, input int drv_n);
    int m, j;
    begin
      for (m = 0; m < drv_m; m = m + 1) begin
        for (j = 0; j < drv_n; j = j + 1) begin
          checks = checks + 1;
          if (mem[(base_c >> 2) + m * 4 + j] !== c_case[m][j]) begin
            errors = errors + 1;
            $display("FAIL [%s]: mem C[%0d][%0d]=%0d expected %0d", label, m, j, mem[(base_c >> 2) + m * 4 + j], c_case[m][j]);
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

    // ==== Directed: cross_terms end to end, native-port-only path ====
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
    native_write(CSR_BASE + OFF_SRC_A,  32'd0);
    native_write(CSR_BASE + OFF_SRC_B,  32'd0);
    native_write(CSR_BASE + OFF_DEST_C, 32'd0);
    native_write(CSR_BASE + OFF_DIM_M,  32'd0); // illegal
    native_write(CSR_BASE + OFF_DIM_N,  32'd4);
    native_write(CSR_BASE + OFF_DIM_K,  32'd4);
    native_write(CSR_BASE + OFF_NPU_CTRL, 32'h1); // START

    ok = 1'b0;
    for (i = 0; i < 20; i = i + 1) begin
      native_read(CSR_BASE + OFF_NPU_STAT, rdata);
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
        $display("PASS [illegal dim_M=0]: npu_status ERROR=1, error_code=1, read back over the native port");
      end
    end

    // Legal case immediately after, no reset -- confirms recovery.
    preload_case("cross_terms", 32'h0000_9000, 32'h0000_9100);
    run_case_via_cpu("post-error recovery: cross_terms", 32'h0000_9000, 32'h0000_9100, 32'h0000_9200, 4, 4, 4, 1'b1, 1'b0, ok);
    check_writeback("post-error recovery: cross_terms", 32'h0000_9200, 4, 4);

    // ==== New (task 017): npu_enable=0 blocks register access -- the
    // write is silently dropped (matches the already-tested unmapped-
    // offset behavior, task 010) and the bus never hangs (mem_ready
    // stays 1). ====
    do_reset();
    npu_enable = 1'b0;
    mem_addr = CSR_BASE + OFF_DIM_M; mem_wdata = 32'd3; mem_wstrb = 4'hF; mem_valid = 1'b1;
    step();
    checks = checks + 1;
    if (mem_ready !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL [enable=0 blocks write]: mem_ready not 1 while npu_enable=0 (bus would hang)");
    end
    mem_valid = 1'b0; mem_wstrb = 4'h0;
    npu_enable = 1'b1;
    native_read(CSR_BASE + OFF_DIM_M, rdata);
    checks = checks + 1;
    if (rdata[2:0] !== 3'd0) begin
      errors = errors + 1;
      $display("FAIL [enable=0 blocks write]: dim_M read back %0d, expected 0 (reset value -- write should have been blocked)", rdata[2:0]);
    end else begin
      $display("PASS [enable=0 blocks write]: register write while npu_enable=0 had no effect, mem_ready stayed 1");
    end

    // ==== New (task 017): npu_start_req triggers a real matmul, same
    // cross_terms case as the anchor directed test above, but START
    // comes from a rising edge on npu_start_req instead of a npu_ctrl
    // bit-0 write. ====
    do_reset();
    preload_case("cross_terms", 32'h0000_6000, 32'h0000_6100);
    run_case_via_start_req("cross_terms via npu_start_req", 32'h0000_6000, 32'h0000_6100, 32'h0000_6200, 4, 4, 4, 1'b1, ok);
    check_writeback("cross_terms via npu_start_req", 32'h0000_6200, 4, 4);

    // ==== New (task 017): edge-timing check -- u_seq.busy (leaving
    // IDLE) must assert exactly one cycle after npu_start_req's rising
    // edge, not the same cycle, not two cycles later (known trap, same
    // class as task 007/010/011's staging bugs -- see rtl/unpu_top.sv's
    // comment on start_req_pulse). This is the one deliberate exception
    // to this file's black-box-only policy (see header comment): the
    // signal under test, start_req_pulse/seq_start, is transient -- it
    // settles (and, in the correct design, is already extinguished) by
    // the same clock edge that produces it, so it cannot be caught
    // through the #1-settled mem_*/dma_* interface this file otherwise
    // uses exclusively. unpu_seq's own registered busy output is the
    // smallest whitebox probe that can still nail the exact cycle. ====
    do_reset();
    checks = checks + 1;
    if (dut.u_seq.busy !== 1'b0) begin
      errors = errors + 1;
      $display("FAIL [edge-timing]: u_seq.busy not 0 before any npu_start_req activity");
    end
    npu_start_req = 1'b1;
    step(); // the cycle immediately after npu_start_req's rising edge
    checks = checks + 1;
    if (dut.u_seq.busy !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL [edge-timing]: u_seq.busy not asserted exactly one cycle after npu_start_req's rising edge (got %b)", dut.u_seq.busy);
    end else begin
      $display("PASS [edge-timing]: u_seq.busy asserted exactly one cycle after npu_start_req's rising edge");
    end
    npu_start_req = 1'b0;

    // ==== New (task 017): npu_start_req without npu_enable produces no
    // start -- proves the "&& npu_enable" term in start_req_pulse is
    // actually doing something, not just present in the RTL. ====
    do_reset();
    npu_enable = 1'b0;
    npu_start_req = 1'b1;
    step();
    npu_start_req = 1'b0;
    step();
    checks = checks + 1;
    if (dut.u_seq.busy !== 1'b0) begin
      errors = errors + 1;
      $display("FAIL [start_req without enable]: u_seq.busy asserted despite npu_enable=0");
    end else begin
      $display("PASS [start_req without enable]: npu_start_req rising edge produced no start while npu_enable=0");
    end
    npu_enable = 1'b1;

    // ==== CRV: all 64 crv_* cases, back to back, no reset between
    // them, through unpu_top's native ports only. ====
    do_reset();
    $display("CRV: running all 64 crv_* cases through unpu_top's native ports, back-pressure seed 32'h5eed000c");

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
