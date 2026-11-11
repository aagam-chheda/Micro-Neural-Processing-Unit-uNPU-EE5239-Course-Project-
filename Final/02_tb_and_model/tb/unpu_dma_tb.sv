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
  //
  // Size: MEM_WORDS = 2**MEM_ADDR_BITS words (128 KiB). The CRV loop uses
  // per-case bases in 0x1_0000..0x1_FF3C, so the decode has to reach bit 16
  // (task 030: the original 8192-word / [14:2] model was smaller than the
  // CRV address band; a 4-state simulator dropped the out-of-range TB writes
  // and the DUT read x, while Verilator silently wrapped the index).
  // The DUT-facing decode below takes exactly MEM_ADDR_BITS address bits, so
  // it cannot go out of range; any beat whose address has bits ABOVE the
  // decode set is reported by the window monitor below unless the test has
  // declared address wraparound (wrap_expected) -- aliasing is only ever
  // allowed on purpose. TB-side computed indexes go through mem_ix().
  localparam int MEM_ADDR_BITS = 15;
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
        mem[mem_ix(base_a, r, "preload_case A")] = {a_case[r][3], a_case[r][2], a_case[r][1], a_case[r][0]};
        mem[mem_ix(base_w, r, "preload_case W")] = {w_case[r][3], w_case[r][2], w_case[r][1], w_case[r][0]};
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
          if (mem[mem_ix(base, m * 4 + j, "writeback_and_check")] !== c_case[m][j]) begin
            errors = errors + 1;
            $display("FAIL [%s]: mem C[%0d][%0d]=%0d expected %0d", label, m, j, mem[mem_ix(base, m * 4 + j, "writeback_and_check")], c_case[m][j]);
          end
        end
      end
    end
  endtask

  // ~1/8 chance of a boundary extreme, same discipline tasks 019-024
  // used, built on this file's own already-existing xorshift32.
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

  // Plain random 32-bit value with an occasional (~1/8) boundary
  // extreme -- used for Part B's WRITE_C payloads, which unpu_dma just
  // moves verbatim and doesn't interpret as INT8 weight/activation data,
  // so this doesn't need biased_byte's per-byte granularity.
  function automatic logic [31:0] biased_word32(ref logic [31:0] rng);
    logic [31:0] r1, r2;
    begin
      rng = xorshift32(rng); r1 = rng;
      if (r1[3:0] < 4'd2) begin
        rng = xorshift32(rng); r2 = rng;
        case (r2[1:0])
          2'd0: biased_word32 = 32'h0000_0000;
          2'd1: biased_word32 = 32'hFFFF_FFFF;
          2'd2: biased_word32 = 32'h8000_0000;
          default: biased_word32 = 32'h7FFF_FFFF;
        endcase
      end else begin
        biased_word32 = r1;
      end
    end
  endfunction

  // Task 025 Part B: like run_job(), but forces dma_ready low for
  // stall_len cycles at beat 0 before letting the job run to completion
  // normally -- a lighter-weight, per-job variant of Part A3's full-job
  // extreme stalling, spot-checking that extreme back-pressure combines
  // correctly with the random-kind-order chain, not just in isolation.
  task automatic run_job_with_stall0(input string label, input logic [1:0] kind, input logic [31:0] base,
                                      input int m, input int k, input int n, input int stall_len);
    int cyc, s;
    bit seen_done;
    begin
      force_stall = 1;
      job_kind = kind; job_base_addr = base; job_m = m[2:0]; job_k = k[2:0]; job_n = n[2:0];
      job_start = 1;
      step();
      job_start = 0;
      for (s = 0; s < stall_len; s = s + 1)
        step();
      force_stall = 0;

      seen_done = 1'b0;
      for (cyc = 0; cyc < 400; cyc = cyc + 1) begin
        step();
        if (job_done) begin
          seen_done = 1'b1;
          step();
          break;
        end
      end
      checks = checks + 1;
      if (!seen_done) begin
        errors = errors + 1;
        $display("FAIL [%s]: job_done never observed within 400 cycles (extended beat-0 stall=%0d)", label, stall_len);
      end
    end
  endtask

  // ==== Task 025 Part A helpers: exact beat-count + exact address-
  // sequence checks, independent of memory content (the behavioral SRAM
  // model above only ever decodes dma_addr[14:2] -- 15 bits -- so it
  // cannot represent a genuinely-wrapped 32-bit address's content
  // coherently; the DUT's own dma_addr output is checked directly
  // against a plain 32-bit-unsigned-arithmetic reference instead, which
  // wraps the exact same way a real address register would). ====

  // Runs a FETCH job (A or W), counting actual beats (valid&&ready
  // cycles) and checking each beat's dma_addr against base+beat*4 --
  // computed as plain logic[31:0] arithmetic, which wraps at 32 bits
  // exactly like the DUT's own registers would.
  task automatic run_fetch_check_addr(input string label, input logic [1:0] kind, input logic [31:0] base,
                                       input int rows, output int actual_beats);
    int cyc;
    bit seen_done;
    int beat_seen;
    logic [31:0] exp_addr;
    begin
      job_kind = kind; job_base_addr = base; job_m = rows[2:0]; job_k = rows[2:0]; job_n = rows[2:0];
      job_start = 1;
      step();
      job_start = 0;
      beat_seen = 0;
      seen_done = 1'b0;
      for (cyc = 0; cyc < 300; cyc = cyc + 1) begin
        if (dma_valid && dma_ready) begin
          exp_addr = base + (32'(beat_seen) * 32'd4);
          checks  = checks + 1;
          if (dma_addr !== exp_addr) begin
            errors = errors + 1;
            $display("FAIL [%s]: beat %0d addr=%0h expected=%0h", label, beat_seen, dma_addr, exp_addr);
          end
          beat_seen = beat_seen + 1;
        end
        step();
        if (job_done) begin
          seen_done = 1'b1;
          step();
          break;
        end
      end
      checks = checks + 1;
      if (!seen_done) begin
        errors = errors + 1;
        $display("FAIL [%s]: job_done never observed within 300 cycles", label);
      end
      checks = checks + 1;
      if (beat_seen !== rows) begin
        errors = errors + 1;
        $display("FAIL [%s]: observed %0d beats, expected exactly %0d", label, beat_seen, rows);
      end
      actual_beats = beat_seen;
    end
  endtask

  // Same shape for WRITE_C, whose address formula is base+m*16+j*4 with
  // m/j advancing per the real drv_m x drv_n submatrix -- computed here
  // independently of the DUT's own cur_m/cur_j registers.
  task automatic run_write_check_addr(input string label, input logic [31:0] base, input int drv_m, input int drv_n,
                                       output int actual_beats);
    int cyc;
    bit seen_done;
    int beat_seen, exp_m, exp_j;
    logic [31:0] exp_addr;
    begin
      job_kind = JOB_WRITE_C; job_base_addr = base; job_m = drv_m[2:0]; job_k = 3'd4; job_n = drv_n[2:0];
      job_start = 1;
      step();
      job_start = 0;
      beat_seen = 0; exp_m = 0; exp_j = 0;
      seen_done = 1'b0;
      for (cyc = 0; cyc < 300; cyc = cyc + 1) begin
        if (dma_valid && dma_ready) begin
          exp_addr = base + (32'(exp_m) * 32'd16) + (32'(exp_j) * 32'd4);
          checks  = checks + 1;
          if (dma_addr !== exp_addr) begin
            errors = errors + 1;
            $display("FAIL [%s]: beat %0d (m=%0d,j=%0d) addr=%0h expected=%0h", label, beat_seen, exp_m, exp_j, dma_addr, exp_addr);
          end
          beat_seen = beat_seen + 1;
          if (exp_j == drv_n - 1) begin
            exp_j = 0;
            exp_m = exp_m + 1;
          end else begin
            exp_j = exp_j + 1;
          end
        end
        step();
        if (job_done) begin
          seen_done = 1'b1;
          step();
          break;
        end
      end
      checks = checks + 1;
      if (!seen_done) begin
        errors = errors + 1;
        $display("FAIL [%s]: job_done never observed within 300 cycles", label);
      end
      checks = checks + 1;
      if (beat_seen !== drv_m * drv_n) begin
        errors = errors + 1;
        $display("FAIL [%s]: observed %0d beats, expected exactly %0d", label, beat_seen, drv_m * drv_n);
      end
      actual_beats = beat_seen;
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
        if (mem[mem_ix(32'h0000_5200, r * 4 + c, "partA0 readback")] !== c_case[r][c]) begin
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

    // ==== Task 025, Part A1: address wraparound. job_base_addr near
    // 32'hFFFF_FFF0, a full 16-beat writeback (M=N=4) so base+m*16+j*4
    // genuinely wraps past 32'hFFFF_FFFF. Checked via run_write_check_addr,
    // which computes its own expected address as plain logic[31:0]
    // arithmetic -- that silently wraps at 32 bits exactly like a real
    // address register, so this is a like-for-like comparison, not an
    // assumption that addresses stay in a comfortable range. Memory
    // content is deliberately not checked here -- the behavioral SRAM
    // model only ever decodes the low MEM_ADDR_BITS of dma_addr and can't represent a
    // wrapped address's content coherently; the address sequence itself
    // is the property under test. ====
    begin : part_a1
      int actual_beats;
      do_reset();
      c_src = '0;
      for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1)
          c_src[r][c] = 32'(r * 4 + c + 1); // distinct per position, irrelevant to the address check itself
      wrap_expected = 1'b1; // intended aliasing: addresses wrap past 32'hFFFF_FFFF, model decodes the low bits
      run_write_check_addr("partA1-wraparound", 32'hFFFF_FFF0, 4, 4, actual_beats);
      wrap_expected = 1'b0;
      $display("Part A1: address-wraparound writeback (base=32'hFFFF_FFF0, M=N=4), %0d beats, all addresses matched 32-bit-wrapping reference, checks=%0d so far", actual_beats, checks);
    end

    // ==== Task 025, Part A2: exhaustive burst-length coverage -- every
    // M for fetch-A, every K for fetch-W, all 16 (M,N) for writeback-C.
    // Exact beat count AND exact address sequence for each, not just
    // whatever mix 64 generically-random crv_* shapes happened to draw. ====
    begin : part_a2
      int mm, kk, nn, actual_beats;

      for (mm = 1; mm <= 4; mm = mm + 1) begin
        do_reset();
        run_fetch_check_addr($sformatf("partA2-fetchA-M%0d", mm), JOB_FETCH_A, 32'h0000_6000, mm, actual_beats);
      end
      for (kk = 1; kk <= 4; kk = kk + 1) begin
        do_reset();
        run_fetch_check_addr($sformatf("partA2-fetchW-K%0d", kk), JOB_FETCH_W, 32'h0000_6100, kk, actual_beats);
      end
      for (mm = 1; mm <= 4; mm = mm + 1) begin
        for (nn = 1; nn <= 4; nn = nn + 1) begin
          do_reset();
          c_src = '0;
          for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
              c_src[r][c] = 32'(r * 4 + c + 1);
          run_write_check_addr($sformatf("partA2-writeC-M%0dN%0d", mm, nn), 32'h0000_6200, mm, nn, actual_beats);
        end
      end
      $display("Part A2: exhaustive burst-length coverage (4 fetch-A + 4 fetch-W + 16 writeback-C = 24 sub-cases), every beat count and address sequence exact, checks=%0d so far", checks);
    end

    // ==== Task 025, Part A3: extreme back-pressure -- a full 16-beat
    // writeback with every single beat individually stalled 50-200
    // cycles (an order of magnitude past the 0-5-cycle range already
    // exercised). force_stall holds dma_ready low directly; the
    // underlying random bp model keeps counting its own (much shorter)
    // delay down to 0 the whole time dma_valid stays high, so it's
    // already stuck at "would grant immediately" well before force_stall
    // is released each beat -- confirmed explicitly below, not assumed. ====
    begin : part_a3
      localparam int NUM_BEATS_C = 16;
      logic [31:0] rng;
      int beat_i, stall_len, s, exp_m, exp_j;
      logic [31:0] addr_snap;

      do_reset();
      c_src = '0;
      for (r = 0; r < 4; r = r + 1)
        for (c = 0; c < 4; c = c + 1)
          c_src[r][c] = 32'(r * 4 + c + 1);

      rng = 32'h5eed0119; // per-task seed convention (0x5eed0000 + task number, hex, distinct sub-stream)
      $display("Part A3 extreme back-pressure seed = 32'h%08h", rng);

      force_stall = 1;
      job_kind = JOB_WRITE_C; job_base_addr = 32'h0000_6300; job_m = 3'd4; job_k = 3'd4; job_n = 3'd4;
      job_start = 1;
      step();
      job_start = 0;

      exp_m = 0; exp_j = 0;
      for (beat_i = 0; beat_i < NUM_BEATS_C; beat_i = beat_i + 1) begin
        rng = xorshift32(rng);
        stall_len = 50 + (rng % 151); // 50..200
        addr_snap = dma_addr;
        for (s = 0; s < stall_len; s = s + 1) begin
          checks = checks + 1;
          if (dma_addr !== addr_snap || dma_valid !== 1'b1 || dma_wdata !== c_src[exp_m][exp_j]) begin
            errors = errors + 1;
            $display("FAIL [partA3 beat=%0d cyc=%0d]: addr/valid/wdata drifted during a %0d-cycle stall", beat_i, s, stall_len);
          end
          step();
        end
        force_stall = 0;
        #1; // let dma_ready's combinational dependency on force_stall settle before checking it
        checks = checks + 1;
        if (!(dma_valid && dma_ready)) begin
          errors = errors + 1;
          $display("FAIL [partA3 beat=%0d]: beat not granted on the cycle after releasing a %0d-cycle stall", beat_i, stall_len);
        end
        step(); // the granted edge -- state moves D_REQ -> D_ACK here (beat consumed)
        force_stall = 1; // re-assert before the next beat's D_REQ is reached
        if (beat_i != NUM_BEATS_C - 1)
          step(); // D_ACK's own cycle (dma_valid=0 for exactly this one cycle) -> D_REQ for the next beat, address now advanced
        if (exp_j == 3) begin
          exp_j = 0;
          exp_m = exp_m + 1;
        end else begin
          exp_j = exp_j + 1;
        end
      end
      force_stall = 0;

      begin : part_a3_drain
        int cyc2;
        bit seen;
        seen = 1'b0;
        for (cyc2 = 0; cyc2 < 300; cyc2 = cyc2 + 1) begin
          step();
          if (job_done) begin
            seen = 1'b1;
            step();
            break;
          end
        end
        checks = checks + 1;
        if (!seen) begin
          errors = errors + 1;
          $display("FAIL [partA3]: job never completed after all 16 beats' extreme stalling");
        end
      end

      for (r = 0; r < 4; r = r + 1) begin
        for (c = 0; c < 4; c = c + 1) begin
          checks = checks + 1;
          if (mem[mem_ix(32'h0000_6300, r * 4 + c, "partA3 readback")] !== c_src[r][c]) begin
            errors = errors + 1;
            $display("FAIL [partA3]: mem C[%0d][%0d] mismatch after full-job 50-200-cycle-per-beat stalling", r, c);
          end
        end
      end
      $display("Part A3: full 16-beat writeback, every beat individually stalled 50-200 cycles, zero address/data drift, job completed, correct content, checks=%0d so far", checks);
    end

    // ==== Task 025, Part A4: BUF_LOAD staging correctness across
    // differing burst sizes back to back -- the sharpest structural
    // check here. A K=4 fetch fills all 4 stage[] slots; a K=1 fetch
    // immediately after (no swap between them, so both target the same
    // inactive bank) only writes stage[0] fresh -- stage[1..3] are never
    // touched by this second job and still hold the FIRST job's stale
    // content. Confirms unpu_dma's own masking (not unpu_wbuf's) zeros
    // the unused rows correctly regardless of that stale content, and
    // that row 0 genuinely reflects the fresh fetch, not anything left
    // over. Deliberately constructed exactly, not left to Part B's
    // random ordering to produce reliably. ====
    begin : part_a4
      logic [7:0] fresh_row [0:3];

      do_reset();
      for (r = 0; r < 4; r = r + 1)
        mem[mem_ix(32'h0000_7000, r, "partA4 preload")] = {8'(200 + r * 4 + 3), 8'(200 + r * 4 + 2), 8'(200 + r * 4 + 1), 8'(200 + r * 4 + 0)};
      run_job("partA4 K=4 fetch", JOB_FETCH_W, 32'h0000_7000, 4, 4, 4);
      // No swap -- the just-loaded bank (bank_b, reset default inactive) stays inactive.

      fresh_row[0] = 8'hAB; fresh_row[1] = 8'hCD; fresh_row[2] = 8'hEF; fresh_row[3] = 8'h12;
      mem[mem_ix(32'h0000_7100, 0, "partA4 preload")] = {fresh_row[3], fresh_row[2], fresh_row[1], fresh_row[0]};
      run_job("partA4 K=1 fetch", JOB_FETCH_W, 32'h0000_7100, 4, 1, 4);

      for (c = 0; c < 4; c = c + 1) begin
        checks = checks + 1;
        if (u_wbuf.bank_b[c][0] !== fresh_row[c]) begin
          errors = errors + 1;
          $display("FAIL [partA4-bufload]: bank_b[%0d][0]=%0d expected fresh K=1 row value %0d (stale/leftover data suspected)", c, u_wbuf.bank_b[c][0], fresh_row[c]);
        end
        checks = checks + 1;
        if (u_wbuf.bank_b[c][1] !== 8'h00) begin
          errors = errors + 1;
          $display("FAIL [partA4-bufload]: bank_b[%0d][1]=%0d expected 0 (masked, K=1) -- possible stale leftover from the prior K=4 fetch", c, u_wbuf.bank_b[c][1]);
        end
        checks = checks + 1;
        if (u_wbuf.bank_b[c][2] !== 8'h00) begin
          errors = errors + 1;
          $display("FAIL [partA4-bufload]: bank_b[%0d][2]=%0d expected 0 (masked, K=1) -- possible stale leftover from the prior K=4 fetch", c, u_wbuf.bank_b[c][2]);
        end
        checks = checks + 1;
        if (u_wbuf.bank_b[c][3] !== 8'h00) begin
          errors = errors + 1;
          $display("FAIL [partA4-bufload]: bank_b[%0d][3]=%0d expected 0 (masked, K=1) -- possible stale leftover from the prior K=4 fetch", c, u_wbuf.bank_b[c][3]);
        end
      end
      $display("Part A4: BUF_LOAD staging (K=4 fetch immediately followed by K=1 fetch), stage[0] genuinely fresh, masked rows correctly zero despite stale stage[1..3], checks=%0d so far", checks);
    end

    // ==== Task 025, Part B: long adversarial job chains, random kind
    // order -- fetch-A, fetch-W, and writeback-C interleaved in any
    // order (not the natural fetch-A->fetch-W->writeback-C sequence a
    // real op produces), zero gap between jobs. Never swaps -- bank_b
    // stays the loading target throughout for both buffers, so every
    // fetch job's freshly-loaded data is directly whitebox-checkable
    // against what was just written to mem[] immediately beforehand
    // (task 008's own verification method, generalized off a real
    // shape/address per job instead of a fixed case). Addresses are
    // mostly kept within the behavioral SRAM model's real 32 KB decode
    // window for full content verification; a ~1/16 fraction are drawn
    // near the wraparound boundary instead, for which content can't be
    // checked (the model only ever decodes the low 15 address bits) --
    // those jobs get the same address-sequence-only verification Part A1
    // used. ~1/8 of jobs additionally get an extended, beat-0 stall
    // (Part A3's mechanism, one beat per job here rather than all 16),
    // spot-checking that extreme back-pressure combines correctly with
    // random job ordering, not just in isolation. ====
    begin : part_b
      localparam int NUM_SEQ = 20;
      logic [31:0] master_rng, rng, seq_seed;
      int seq_idx, job_idx, num_jobs, total_jobs;
      int kind_pick;
      logic [1:0] jkind;
      int jm, jk, jn;
      logic [31:0] jbase;
      bit near_wrap, do_extreme_stall;
      int stall_len2;
      int rr, cc, ab;
      logic [7:0]  fetch_data [0:3][0:3];
      logic [31:0] wc_data    [0:3][0:3];
      string jlabel;

      master_rng = 32'h5eed0219; // per-task seed convention, distinct sub-stream
      $display("Part B master seed = 32'h%08h", master_rng);
      total_jobs = 0;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_seed   = master_rng;
        rng        = seq_seed;
        $display("Part B sequence %0d: seed = 32'h%08h", seq_idx, seq_seed);

        rng = xorshift32(rng);
        num_jobs = 40 + (rng % 41); // 40..80 jobs per sequence

        do_reset(); // ONE reset per sequence -- every job after the first gets no reset and no idle gap

        for (job_idx = 0; job_idx < num_jobs; job_idx = job_idx + 1) begin
          rng = xorshift32(rng);
          kind_pick = rng % 3;
          jkind = kind_pick[1:0];
          jlabel = $sformatf("partB seq%0d/job%0d", seq_idx, job_idx);

          rng = xorshift32(rng);
          jm = 1 + (rng % 4);
          rng = xorshift32(rng);
          jk = 1 + (rng % 4);
          rng = xorshift32(rng);
          jn = 1 + (rng % 4);

          rng = xorshift32(rng);
          near_wrap = (rng[3:0] == 4'h0); // ~1/16
          if (near_wrap) begin
            rng = xorshift32(rng);
            jbase = 32'hFFFF_FF00 + {24'd0, rng[7:0]};
          end else begin
            rng = xorshift32(rng);
            jbase = ({20'd0, rng[9:0]} * 32'd16); // spread within the model's real 32 KB window
          end

          rng = xorshift32(rng);
          do_extreme_stall = !near_wrap && (rng[2:0] == 3'h0); // ~1/8 of non-wraparound jobs

          total_jobs = total_jobs + 1;

          if (near_wrap) begin
            // Address-only verification -- same reasoning as Part A1.
            wrap_expected = 1'b1;
            if (jkind == JOB_WRITE_C) begin
              c_src = '0;
              for (rr = 0; rr < 4; rr = rr + 1)
                for (cc = 0; cc < 4; cc = cc + 1)
                  c_src[rr][cc] = biased_word32(rng);
              run_write_check_addr(jlabel, jbase, jm, jn, ab);
            end else begin
              run_fetch_check_addr(jlabel, jkind, jbase, (jkind == JOB_FETCH_A) ? jm : jk, ab);
            end
            wrap_expected = 1'b0;
          end else if (jkind == JOB_FETCH_A) begin
            for (rr = 0; rr < 4; rr = rr + 1)
              for (cc = 0; cc < 4; cc = cc + 1)
                fetch_data[rr][cc] = biased_byte(rng);
            for (rr = 0; rr < 4; rr = rr + 1)
              mem[mem_ix(jbase, rr, "partB fetch preload")] = {fetch_data[rr][3], fetch_data[rr][2], fetch_data[rr][1], fetch_data[rr][0]};

            if (do_extreme_stall) begin
              rng = xorshift32(rng);
              stall_len2 = 20 + (rng % 131); // 20..150
              run_job_with_stall0(jlabel, JOB_FETCH_A, jbase, jm, jk, jn, stall_len2);
            end else begin
              run_job(jlabel, JOB_FETCH_A, jbase, jm, jk, jn);
            end

            for (rr = 0; rr < 4; rr = rr + 1) begin
              for (cc = 0; cc < 4; cc = cc + 1) begin
                checks = checks + 1;
                if (rr < jm && cc < jk) begin
                  if (u_actbuf.bank_b[rr][cc] !== fetch_data[rr][cc]) begin
                    errors = errors + 1;
                    $display("FAIL [%s FETCH_A]: bank_b[%0d][%0d]=%0d expected %0d", jlabel, rr, cc, u_actbuf.bank_b[rr][cc], fetch_data[rr][cc]);
                  end
                end else begin
                  if (u_actbuf.bank_b[rr][cc] !== 8'h00) begin
                    errors = errors + 1;
                    $display("FAIL [%s FETCH_A]: bank_b[%0d][%0d]=%0d expected 0 (M/K-masked)", jlabel, rr, cc, u_actbuf.bank_b[rr][cc]);
                  end
                end
              end
            end
          end else if (jkind == JOB_FETCH_W) begin
            for (rr = 0; rr < 4; rr = rr + 1)
              for (cc = 0; cc < 4; cc = cc + 1)
                fetch_data[rr][cc] = biased_byte(rng);
            for (rr = 0; rr < 4; rr = rr + 1)
              mem[mem_ix(jbase, rr, "partB fetch preload")] = {fetch_data[rr][3], fetch_data[rr][2], fetch_data[rr][1], fetch_data[rr][0]};

            if (do_extreme_stall) begin
              rng = xorshift32(rng);
              stall_len2 = 20 + (rng % 131);
              run_job_with_stall0(jlabel, JOB_FETCH_W, jbase, jm, jk, jn, stall_len2);
            end else begin
              run_job(jlabel, JOB_FETCH_W, jbase, jm, jk, jn);
            end

            for (rr = 0; rr < 4; rr = rr + 1) begin
              for (cc = 0; cc < 4; cc = cc + 1) begin
                checks = checks + 1;
                if (rr < jk && cc < jn) begin
                  if (u_wbuf.bank_b[cc][rr] !== fetch_data[rr][cc]) begin
                    errors = errors + 1;
                    $display("FAIL [%s FETCH_W]: stage[%0d][%0d]=%0d expected %0d", jlabel, cc, rr, u_wbuf.bank_b[cc][rr], fetch_data[rr][cc]);
                  end
                end else begin
                  if (u_wbuf.bank_b[cc][rr] !== 8'h00) begin
                    errors = errors + 1;
                    $display("FAIL [%s FETCH_W]: stage[%0d][%0d]=%0d expected 0 (K/N-masked)", jlabel, cc, rr, u_wbuf.bank_b[cc][rr]);
                  end
                end
              end
            end
          end else begin // JOB_WRITE_C
            c_src = '0;
            for (rr = 0; rr < 4; rr = rr + 1)
              for (cc = 0; cc < 4; cc = cc + 1)
                if (rr < jm && cc < jn)
                  wc_data[rr][cc] = biased_word32(rng);
            for (rr = 0; rr < 4; rr = rr + 1)
              for (cc = 0; cc < 4; cc = cc + 1)
                c_src[rr][cc] = (rr < jm && cc < jn) ? wc_data[rr][cc] : 32'd0;

            if (do_extreme_stall) begin
              rng = xorshift32(rng);
              stall_len2 = 20 + (rng % 131);
              run_job_with_stall0(jlabel, JOB_WRITE_C, jbase, jm, jk, jn, stall_len2);
            end else begin
              run_job(jlabel, JOB_WRITE_C, jbase, jm, jk, jn);
            end

            for (rr = 0; rr < jm; rr = rr + 1) begin
              for (cc = 0; cc < jn; cc = cc + 1) begin
                checks = checks + 1;
                if (mem[mem_ix(jbase, rr * 4 + cc, "partB WRITE_C readback")] !== wc_data[rr][cc]) begin
                  errors = errors + 1;
                  $display("FAIL [%s WRITE_C]: mem C[%0d][%0d]=%0d expected %0d", jlabel, rr, cc, mem[mem_ix(jbase, rr * 4 + cc, "partB WRITE_C readback")], wc_data[rr][cc]);
                end
              end
            end
          end
        end
      end

      $display("----------------------------------------");
      $display("Part B: %0d sequences, %0d total jobs (>=400 required), checks so far=%0d", NUM_SEQ, total_jobs, checks);
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
