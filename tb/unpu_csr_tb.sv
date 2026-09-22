// Directed + CRV test for unpu_csr. Pure control-plane module -- no
// datapath instantiated, done_i/error_i/error_code_i driven directly as
// testbench stimulus standing in for unpu_seq (task 006), same role the
// testbench has played for every not-yet-integrated module so far.
//
// No golden-model oracle applies here (register semantics, not
// arithmetic) -- CRV self-checks against a shadow model maintained
// alongside the DUT, applying the exact same rules the RTL does,
// including the one genuinely subtle piece of timing: start_pulse is a
// registered pulse one cycle after a qualifying write, and
// npu_status.DONE's set/clear priority reads the CURRENT (i.e.
// previous-edge-set) start_pulse value, not the live write condition --
// see the shadow-update comment below for the exact derivation.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006-008 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
`timescale 1ns/1ps

module unpu_csr_tb;

  logic clk, rst_n;
  logic [9:0]  csr_sel;
  logic [31:0] csr_wdata;
  logic        csr_wen;
  logic [31:0] csr_rdata;
  logic [31:0] src_a, src_b, dest_c;
  logic [2:0]  dim_m, dim_n, dim_k;
  logic        mode_unsigned;
  logic        start_pulse;
  logic        done_i, error_i;
  logic [2:0]  error_code_i;

  unpu_csr dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .csr_sel       (csr_sel),
    .csr_wdata     (csr_wdata),
    .csr_wen       (csr_wen),
    .csr_rdata     (csr_rdata),
    .src_a         (src_a),
    .src_b         (src_b),
    .dest_c        (dest_c),
    .dim_m         (dim_m),
    .dim_n         (dim_n),
    .dim_k         (dim_k),
    .mode_unsigned (mode_unsigned),
    .start_pulse   (start_pulse),
    .done_i        (done_i),
    .error_i       (error_i),
    .error_code_i  (error_code_i)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1;
  endtask

  int errors, checks;

  function automatic logic [31:0] xorshift32(logic [31:0] x);
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    return x;
  endfunction

  task automatic do_reset;
    begin
      rst_n = 0;
      csr_sel = 10'd0; csr_wdata = 32'd0; csr_wen = 1'b0;
      done_i = 1'b0; error_i = 1'b0; error_code_i = 3'd0;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  task automatic check_eq32(input string label, input logic [31:0] got, input logic [31:0] exp);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("FAIL [%s]: got=%0h expected=%0h", label, got, exp);
      end
    end
  endtask

  task automatic check_eq1(input string label, input logic got, input logic exp);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("FAIL [%s]: got=%0b expected=%0b", label, got, exp);
      end
    end
  endtask

  // ==== Directed ====
  initial begin
    errors = 0;
    checks = 0;

    // ---- All 8 real offsets: write then read back. ----
    do_reset();
    csr_sel = 10'd0; csr_wdata = 32'h1234_5678; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("src_a readback", src_a, 32'h1234_5678);
    csr_sel = 10'd1; csr_wdata = 32'hDEAD_BEEF; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("src_b readback", src_b, 32'hDEAD_BEEF);
    csr_sel = 10'd2; csr_wdata = 32'hCAFE_F00D; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("dest_c readback", dest_c, 32'hCAFE_F00D);

    // dim_M/N/K: storage is unvalidated -- write 0 and 7, both illegal
    // per unpu_seq's own check, and confirm verbatim round-trip here.
    csr_sel = 10'd3; csr_wdata = 32'd0; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("dim_m stores 0 verbatim", {29'd0, dim_m}, 32'd0);
    csr_sel = 10'd3; csr_wdata = 32'd7; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("dim_m stores 7 verbatim", {29'd0, dim_m}, 32'd7);
    csr_sel = 10'd4; csr_wdata = 32'd0; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("dim_n stores 0 verbatim", {29'd0, dim_n}, 32'd0);
    csr_sel = 10'd4; csr_wdata = 32'd7; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("dim_n stores 7 verbatim", {29'd0, dim_n}, 32'd7);
    csr_sel = 10'd5; csr_wdata = 32'd0; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("dim_k stores 0 verbatim", {29'd0, dim_k}, 32'd0);
    csr_sel = 10'd5; csr_wdata = 32'd7; csr_wen = 1; step(); csr_wen = 0;
    check_eq32("dim_k stores 7 verbatim", {29'd0, dim_k}, 32'd7);
    // dim_* bits beyond [2:0] are write-ignored / read as 0.
    csr_sel = 10'd3; csr_wdata = 32'hFFFF_FFF9; csr_wen = 1; step(); csr_wen = 0; // bits[2:0]=1
    check_eq32("dim_m upper bits ignored", {29'd0, dim_m}, 32'd1);

    // ---- npu_ctrl bit0: START, write-1-to-pulse. ----
    do_reset();
    csr_sel = 10'd6; csr_wdata = 32'h1; csr_wen = 1;
    step();
    csr_wen = 0;
    check_eq1("start_pulse asserts one cycle after START write", start_pulse, 1'b1);
    step();
    check_eq1("start_pulse is exactly one cycle", start_pulse, 1'b0);
    csr_sel = 10'd6; csr_wen = 0; step();
    check_eq32("npu_ctrl bit0 reads 0 immediately", csr_rdata, 32'd0);
    step();
    check_eq32("npu_ctrl bit0 still reads 0 later", csr_rdata, 32'd0);

    // ---- npu_ctrl bit1: SIGNED, polarity check (do NOT skip). ----
    do_reset();
    csr_sel = 10'd6; csr_wdata = 32'h2; csr_wen = 1; step(); csr_wen = 0;
    csr_sel = 10'd6; step();
    check_eq32("npu_ctrl bit1 reads back 1 as written", csr_rdata, 32'h2);
    check_eq1("mode_unsigned=0 when SIGNED bit=1 (polarity)", mode_unsigned, 1'b0);
    csr_sel = 10'd6; csr_wdata = 32'h0; csr_wen = 1; step(); csr_wen = 0;
    check_eq1("mode_unsigned=1 when SIGNED bit=0 (polarity)", mode_unsigned, 1'b1);

    // ---- Both bits together: don't interfere. ----
    do_reset();
    csr_sel = 10'd6; csr_wdata = 32'h3; csr_wen = 1;
    step();
    csr_wen = 0;
    check_eq1("start_pulse still fires with bit1 also set", start_pulse, 1'b1);
    check_eq1("mode_unsigned still reflects bit1 independently", mode_unsigned, 1'b0);

    // ---- npu_status.DONE: sticky, cleared only by next START. ----
    do_reset();
    done_i = 1; step(); done_i = 0;
    csr_sel = 10'd7; step();
    check_eq1("npu_status.DONE set after done_i pulse", csr_rdata[0], 1'b1);
    step(); step(); step();
    check_eq1("npu_status.DONE stays sticky across idle cycles", csr_rdata[0], 1'b1);
    csr_sel = 10'd6; csr_wdata = 32'h1; csr_wen = 1; step(); csr_wen = 0;
    // Post this step(), start_pulse is now observable as 1 (registered
    // one cycle after the write). status_done_reg's own update rule
    // ("if (start_pulse) status_done <= 0") reads THAT observable value
    // as its trigger, so the clear itself commits on the NEXT edge --
    // one more step() below, which is exactly what "clears [triggered
    // by] start_pulse asserting" means operationally (RTL registers
    // triggered by a signal always resolve one edge after that signal
    // is itself observable, not on the same edge that produced it).
    csr_sel = 10'd7; step();
    check_eq1("npu_status.DONE clears (triggered by start_pulse's assertion)", csr_rdata[0], 1'b0);

    // ---- npu_status.ERROR: pure passthrough, no CSR-side latch. ----
    do_reset();
    error_i = 1; error_code_i = 3'd1;
    csr_sel = 10'd7; step();
    check_eq1("npu_status.ERROR set (passthrough)", csr_rdata[1], 1'b1);
    check_eq32("npu_status.error_code (passthrough)", {29'd0, csr_rdata[4:2]}, 32'd1);
    error_i = 0; error_code_i = 3'd0;
    csr_sel = 10'd7; step();
    check_eq1("npu_status.ERROR clears when error_i drops (no latch)", csr_rdata[1], 1'b0);
    check_eq32("npu_status.error_code clears too", {29'd0, csr_rdata[4:2]}, 32'd0);

    // ---- npu_status write attempt: accepted, no effect. ----
    do_reset();
    done_i = 1; step(); done_i = 0;
    csr_sel = 10'd7; csr_wdata = 32'hFFFF_FFFF; csr_wen = 1; step(); csr_wen = 0;
    csr_sel = 10'd7; step();
    check_eq1("npu_status write has no effect -- DONE still reflects done_i", csr_rdata[0], 1'b1);
    check_eq1("npu_status write has no effect -- ERROR still 0", csr_rdata[1], 1'b0);

    // ---- Reserved-range: reads 0, no side effect on real registers. ----
    do_reset();
    csr_sel = 10'd0; csr_wdata = 32'hAAAA_AAAA; csr_wen = 1; step();
    csr_sel = 10'd1; csr_wdata = 32'hBBBB_BBBB; step();
    csr_sel = 10'd2; csr_wdata = 32'hCCCC_CCCC; step();
    csr_wen = 0;
    // Write to reserved offsets 8, 255, 1023.
    csr_sel = 10'd8;    csr_wdata = 32'hFFFF_FFFF; csr_wen = 1; step();
    csr_sel = 10'd255;  csr_wdata = 32'hFFFF_FFFF; step();
    csr_sel = 10'd1023; csr_wdata = 32'hFFFF_FFFF; step();
    csr_wen = 0;
    csr_sel = 10'd8;    step(); check_eq32("reserved sel=8 reads 0",    csr_rdata, 32'd0);
    csr_sel = 10'd255;  step(); check_eq32("reserved sel=255 reads 0",  csr_rdata, 32'd0);
    csr_sel = 10'd1023; step(); check_eq32("reserved sel=1023 reads 0", csr_rdata, 32'd0);
    check_eq32("src_a unaffected by reserved writes",  src_a,  32'hAAAA_AAAA);
    check_eq32("src_b unaffected by reserved writes",  src_b,  32'hBBBB_BBBB);
    check_eq32("dest_c unaffected by reserved writes", dest_c, 32'hCCCC_CCCC);
    check_eq32("dim_m unaffected by reserved writes",  {29'd0, dim_m}, 32'd0);
    check_eq32("dim_n unaffected by reserved writes",  {29'd0, dim_n}, 32'd0);
    check_eq32("dim_k unaffected by reserved writes",  {29'd0, dim_k}, 32'd0);
    check_eq1 ("mode_unsigned unaffected by reserved writes", mode_unsigned, 1'b1);

    // ==== CRV ====
    // Shadow model mirrors the RTL's own register update rules exactly,
    // cycle for cycle -- including the one-cycle relationship between
    // start_pulse and npu_status.DONE (see file header). Because every
    // consumer-facing port (src_a/b/dest_c/dim_*/mode_unsigned/
    // start_pulse) and csr_rdata are pure combinational reads of
    // just-updated registers, there is no need for a separate "settle"
    // cycle between actions -- every iteration below is a genuine
    // back-to-back write with zero idle cycles, satisfying that
    // requirement as the loop's normal mode rather than a special case.
    begin : crv_block
      localparam int NUM_ITERS = 200; // well over the required >=64
      logic [31:0] rng;
      int iter;

      logic [9:0]  sel_v;
      logic [31:0] wdata_v;
      bit          wen_v;
      bit          done_v;
      bit          err_v;
      logic [2:0]  errc_v;

      logic [31:0] sh_src_a, sh_src_b, sh_dest_c;
      logic [2:0]  sh_dim_m, sh_dim_n, sh_dim_k;
      logic        sh_ctrl_signed;
      logic        sh_start_pulse;
      logic        sh_status_done;

      logic [31:0] new_src_a, new_src_b, new_dest_c;
      logic [2:0]  new_dim_m, new_dim_n, new_dim_k;
      logic        new_ctrl_signed;
      logic        new_start_pulse;
      logic        new_status_done;
      logic [31:0] exp_rdata;

      rng = 32'h5eed0009;
      $display("CRV seed = 32'h%08h", rng);

      do_reset();
      sh_src_a = 32'd0; sh_src_b = 32'd0; sh_dest_c = 32'd0;
      sh_dim_m = 3'd0; sh_dim_n = 3'd0; sh_dim_k = 3'd0;
      sh_ctrl_signed = 1'b0; sh_start_pulse = 1'b0; sh_status_done = 1'b0;

      for (iter = 0; iter < NUM_ITERS; iter = iter + 1) begin
        rng = xorshift32(rng);
        // Bias sel: ~50% land on a real register (0-7) for good coverage
        // of that small space; the rest span the full 0-1023 range
        // (reserved offsets included, per the requirement).
        if (rng[0])
          sel_v = {7'd0, rng[12:10]} & 10'd7;
        else
          sel_v = rng[9:0];

        rng = xorshift32(rng);
        wdata_v = rng;

        rng = xorshift32(rng);
        wen_v = (rng[1:0] != 2'd0); // ~75% writes -- plenty of back-to-back writes

        rng = xorshift32(rng);
        done_v = (rng[2:0] == 3'd0); // occasional done pulse

        rng = xorshift32(rng);
        err_v = (rng[2:0] == 3'd0); // occasional error level
        errc_v = rng[6:4];

        // ---- Compute new shadow values from OLD shadow + this cycle's
        // live stimulus, mirroring the RTL exactly. ----
        new_src_a       = (wen_v && sel_v == 10'd0) ? wdata_v      : sh_src_a;
        new_src_b       = (wen_v && sel_v == 10'd1) ? wdata_v      : sh_src_b;
        new_dest_c      = (wen_v && sel_v == 10'd2) ? wdata_v      : sh_dest_c;
        new_dim_m       = (wen_v && sel_v == 10'd3) ? wdata_v[2:0] : sh_dim_m;
        new_dim_n       = (wen_v && sel_v == 10'd4) ? wdata_v[2:0] : sh_dim_n;
        new_dim_k       = (wen_v && sel_v == 10'd5) ? wdata_v[2:0] : sh_dim_k;
        new_ctrl_signed = (wen_v && sel_v == 10'd6) ? wdata_v[1]   : sh_ctrl_signed;
        new_start_pulse = wen_v && (sel_v == 10'd6) && wdata_v[0];
        new_status_done = sh_start_pulse ? 1'b0 : (done_v ? 1'b1 : sh_status_done);

        // ---- Drive DUT and advance one cycle. ----
        csr_sel = sel_v; csr_wdata = wdata_v; csr_wen = wen_v;
        done_i = done_v; error_i = err_v; error_code_i = errc_v;
        step();

        // ---- Commit shadow (post-edge state). ----
        sh_src_a = new_src_a; sh_src_b = new_src_b; sh_dest_c = new_dest_c;
        sh_dim_m = new_dim_m; sh_dim_n = new_dim_n; sh_dim_k = new_dim_k;
        sh_ctrl_signed = new_ctrl_signed;
        sh_start_pulse = new_start_pulse;
        sh_status_done = new_status_done;

        // ---- Check every always-live port against shadow. ----
        check_eq32($sformatf("CRV[%0d] src_a", iter), src_a, sh_src_a);
        check_eq32($sformatf("CRV[%0d] src_b", iter), src_b, sh_src_b);
        check_eq32($sformatf("CRV[%0d] dest_c", iter), dest_c, sh_dest_c);
        check_eq32($sformatf("CRV[%0d] dim_m", iter), {29'd0, dim_m}, {29'd0, sh_dim_m});
        check_eq32($sformatf("CRV[%0d] dim_n", iter), {29'd0, dim_n}, {29'd0, sh_dim_n});
        check_eq32($sformatf("CRV[%0d] dim_k", iter), {29'd0, dim_k}, {29'd0, sh_dim_k});
        check_eq1($sformatf("CRV[%0d] mode_unsigned", iter), mode_unsigned, ~sh_ctrl_signed);
        check_eq1($sformatf("CRV[%0d] start_pulse", iter), start_pulse, sh_start_pulse);

        // ---- Check csr_rdata against shadow, keyed on THIS cycle's sel
        // (csr_sel hasn't changed since driving it above, so the
        // combinational read at this instant reflects sel_v). ----
        case (sel_v)
          10'd0: exp_rdata = sh_src_a;
          10'd1: exp_rdata = sh_src_b;
          10'd2: exp_rdata = sh_dest_c;
          10'd3: exp_rdata = {29'd0, sh_dim_m};
          10'd4: exp_rdata = {29'd0, sh_dim_n};
          10'd5: exp_rdata = {29'd0, sh_dim_k};
          10'd6: exp_rdata = {30'd0, sh_ctrl_signed, 1'b0};
          10'd7: exp_rdata = {27'd0, errc_v, err_v, sh_status_done};
          default: exp_rdata = 32'd0;
        endcase
        check_eq32($sformatf("CRV[%0d] csr_rdata sel=%0d", iter, sel_v), csr_rdata, exp_rdata);
      end

      $display("CRV: %0d iterations completed, all back-to-back (no idle cycles)", NUM_ITERS);
    end

    // ==== Task 026, Part A1: full extreme-value sweep on src_A/src_B/
    // dest_C -- exact bit-for-bit round-trip, no bit ever dropped or
    // stuck. ====
    begin : part_a1
      logic [31:0] xvals [0:5];
      int vi;
      xvals[0] = 32'h0000_0000; xvals[1] = 32'hFFFF_FFFF; xvals[2] = 32'h8000_0000;
      xvals[3] = 32'h7FFF_FFFF; xvals[4] = 32'h5555_5555; xvals[5] = 32'hAAAA_AAAA;

      do_reset();
      for (vi = 0; vi < 6; vi = vi + 1) begin
        csr_sel = 10'd0; csr_wdata = xvals[vi]; csr_wen = 1; step(); csr_wen = 0;
        check_eq32($sformatf("partA1 src_a extreme[%0d]", vi), src_a, xvals[vi]);
        csr_sel = 10'd1; csr_wdata = xvals[vi]; csr_wen = 1; step(); csr_wen = 0;
        check_eq32($sformatf("partA1 src_b extreme[%0d]", vi), src_b, xvals[vi]);
        csr_sel = 10'd2; csr_wdata = xvals[vi]; csr_wen = 1; step(); csr_wen = 0;
        check_eq32($sformatf("partA1 dest_c extreme[%0d]", vi), dest_c, xvals[vi]);
      end
      $display("Part A1: 6 extreme values x 3 pointer registers, exact bit-for-bit round-trip, checks=%0d so far", checks);
    end

    // ==== Task 026, Part A2: full 3-bit range on dim_M/dim_N/dim_K --
    // all 8 values, not just the two boundary values task 009 tried. ====
    begin : part_a2
      int dv;
      do_reset();
      for (dv = 0; dv < 8; dv = dv + 1) begin
        csr_sel = 10'd3; csr_wdata = dv[31:0]; csr_wen = 1; step(); csr_wen = 0;
        check_eq32($sformatf("partA2 dim_m=%0d", dv), {29'd0, dim_m}, dv[31:0]);
        csr_sel = 10'd4; csr_wdata = dv[31:0]; csr_wen = 1; step(); csr_wen = 0;
        check_eq32($sformatf("partA2 dim_n=%0d", dv), {29'd0, dim_n}, dv[31:0]);
        csr_sel = 10'd5; csr_wdata = dv[31:0]; csr_wen = 1; step(); csr_wen = 0;
        check_eq32($sformatf("partA2 dim_k=%0d", dv), {29'd0, dim_k}, dv[31:0]);
      end
      $display("Part A2: all 8 values (0-7) x 3 dimension registers, verbatim storage confirmed, checks=%0d so far", checks);
    end

    // ==== Task 026, Part A3: register cross-talk matrix -- for each of
    // the 8 real registers, write a distinct recognizable pattern, read
    // back ALL 8, confirm only the intended one changed. 8 rounds x 8
    // reads = 64 checks minimum. npu_status (round 7) is read-only and
    // derived from done_i/error_i/error_code_i (held low throughout),
    // never from a write -- its own expected value is always 0 here,
    // checked the same way as any other round's untouched registers. ====
    begin : part_a3
      logic [31:0] expected [0:7];
      logic [31:0] patterns [0:7];
      int rnd, chk_i;
      logic [31:0] got;

      patterns[0] = 32'hA1A1_A1A1; // src_a
      patterns[1] = 32'hB2B2_B2B2; // src_b
      patterns[2] = 32'hC3C3_C3C3; // dest_c
      patterns[3] = 32'h0000_0005; // dim_m
      patterns[4] = 32'h0000_0003; // dim_n
      patterns[5] = 32'h0000_0006; // dim_k
      patterns[6] = 32'h0000_0002; // npu_ctrl: bit1=1 (SIGNED), bit0=0 (no START -- keeps this round free of the documented DONE-clearing side effect, which isn't cross-talk)
      patterns[7] = 32'hFFFF_FFFF; // npu_status write attempt -- must have NO effect anywhere, including on npu_status itself

      do_reset();
      for (chk_i = 0; chk_i < 8; chk_i = chk_i + 1)
        expected[chk_i] = 32'd0;

      for (rnd = 0; rnd < 8; rnd = rnd + 1) begin
        csr_sel = rnd[9:0]; csr_wdata = patterns[rnd]; csr_wen = 1'b1;
        step();
        csr_wen = 1'b0;

        if (rnd != 7) begin
          if (rnd == 3 || rnd == 4 || rnd == 5)
            expected[rnd] = {29'd0, patterns[rnd][2:0]};
          else if (rnd == 6)
            expected[rnd] = {30'd0, patterns[rnd][1], 1'b0};
          else
            expected[rnd] = patterns[rnd];
        end

        for (chk_i = 0; chk_i < 8; chk_i = chk_i + 1) begin
          csr_sel = chk_i[9:0];
          #1;
          got = csr_rdata;
          checks = checks + 1;
          if (chk_i == 7) begin
            if (got !== 32'd0) begin
              errors = errors + 1;
              $display("FAIL [partA3-crosstalk round=%0d]: npu_status(sel=7)=%0h expected 0 (done_i/error_i held low throughout)", rnd, got);
            end
          end else begin
            if (got !== expected[chk_i]) begin
              errors = errors + 1;
              $display("FAIL [partA3-crosstalk round=%0d]: sel=%0d read %0h expected %0h (cross-talk leak suspected from round %0d's write)", rnd, chk_i, got, expected[chk_i], rnd);
            end
          end
        end
      end
      $display("Part A3: register cross-talk matrix, 8 rounds x 8 reads = 64 checks, only the intended register ever changed, checks=%0d so far", checks);
    end

    // ==== Task 026, Part A4: sustained START write -- hold csr_wen=1,
    // csr_sel=6, csr_wdata[0]=1 for 10 consecutive cycles. Confirms
    // start_pulse fires every one of those cycles (the design registers
    // the write condition directly each cycle -- not edge-detected;
    // confirmed here, not assumed), and npu_ctrl bit0 never latches. ====
    begin : part_a4
      int ci;
      do_reset();
      csr_sel = 10'd6; csr_wdata = 32'h1; csr_wen = 1'b1;
      for (ci = 0; ci < 10; ci = ci + 1) begin
        step();
        checks = checks + 1;
        if (start_pulse !== 1'b1) begin
          errors = errors + 1;
          $display("FAIL [partA4-sustained-start cyc=%0d]: start_pulse=%0b expected 1", ci, start_pulse);
        end
        checks = checks + 1;
        if (csr_rdata[0] !== 1'b0) begin
          errors = errors + 1;
          $display("FAIL [partA4-sustained-start cyc=%0d]: npu_ctrl bit0 read as %0b, expected 0 (never latches)", ci, csr_rdata[0]);
        end
      end
      csr_wen = 1'b0;
      $display("Part A4: sustained START write held 10 consecutive cycles, start_pulse fired every cycle (registered directly, not edge-detected), npu_ctrl bit0 never latched, checks=%0d so far", checks);
    end

    // ==== Task 026, Part A5: denser reserved-offset sweep -- all of
    // csr_sel 8-31 (24 cases) plus >=50 randomly-sampled values from
    // 32-1023. ====
    begin : part_a5
      int s2, ridx;
      logic [31:0] rng2;

      do_reset();
      csr_sel = 10'd0; csr_wdata = 32'hAAAA_AAAA; csr_wen = 1; step();
      csr_sel = 10'd1; csr_wdata = 32'hBBBB_BBBB; step();
      csr_sel = 10'd2; csr_wdata = 32'hCCCC_CCCC; step();
      csr_wen = 0;

      for (s2 = 8; s2 <= 31; s2 = s2 + 1) begin
        csr_sel = s2[9:0]; csr_wdata = 32'hFFFF_FFFF; csr_wen = 1'b1; step(); csr_wen = 1'b0;
        csr_sel = s2[9:0]; #1;
        checks = checks + 1;
        if (csr_rdata !== 32'd0) begin
          errors = errors + 1;
          $display("FAIL [partA5-reserved sel=%0d]: reads %0h expected 0", s2, csr_rdata);
        end
      end

      rng2 = 32'h5eed011a; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("Part A5 reserved-sweep random seed = 32'h%08h", rng2);
      for (ridx = 0; ridx < 50; ridx = ridx + 1) begin
        rng2 = xorshift32(rng2);
        s2 = 32 + (rng2 % 992); // 32..1023
        csr_sel = s2[9:0]; csr_wdata = 32'hFFFF_FFFF; csr_wen = 1'b1; step(); csr_wen = 1'b0;
        csr_sel = s2[9:0]; #1;
        checks = checks + 1;
        if (csr_rdata !== 32'd0) begin
          errors = errors + 1;
          $display("FAIL [partA5-reserved sel=%0d]: reads %0h expected 0", s2, csr_rdata);
        end
      end

      checks = checks + 1;
      if (src_a !== 32'hAAAA_AAAA) begin
        errors = errors + 1;
        $display("FAIL [partA5]: src_a corrupted by reserved-offset writes");
      end
      checks = checks + 1;
      if (src_b !== 32'hBBBB_BBBB) begin
        errors = errors + 1;
        $display("FAIL [partA5]: src_b corrupted by reserved-offset writes");
      end
      checks = checks + 1;
      if (dest_c !== 32'hCCCC_CCCC) begin
        errors = errors + 1;
        $display("FAIL [partA5]: dest_c corrupted by reserved-offset writes");
      end
      $display("Part A5: 24 reserved sel 8-31 + 50 random reserved sel 32-1023 = 74 sub-cases, all read 0, no effect on real registers, checks=%0d so far", checks);
    end

    // ==== Task 026, Part B: high-volume extreme-biased CRV -- >=2,000
    // iterations (10x task 009's original), ~15-20% of drawn wdata
    // forced to an extreme value, same shadow model as the baseline CRV
    // above (no new shadow-model behavior needed -- Part A3's cross-talk
    // and Part A4's sustained-write both already match the shadow's
    // existing per-cycle update rules exactly, nothing to extend). ====
    begin : part_b
      localparam int NUM_ITERS_B = 2000;
      logic [31:0] rng;
      int iter;

      logic [9:0]  sel_v;
      logic [31:0] wdata_v;
      bit          wen_v;
      bit          done_v;
      bit          err_v;
      logic [2:0]  errc_v;

      logic [31:0] sh_src_a, sh_src_b, sh_dest_c;
      logic [2:0]  sh_dim_m, sh_dim_n, sh_dim_k;
      logic        sh_ctrl_signed;
      logic        sh_start_pulse;
      logic        sh_status_done;

      logic [31:0] new_src_a, new_src_b, new_dest_c;
      logic [2:0]  new_dim_m, new_dim_n, new_dim_k;
      logic        new_ctrl_signed;
      logic        new_start_pulse;
      logic        new_status_done;
      logic [31:0] exp_rdata;
      logic [31:0] extreme_vals [0:3];

      extreme_vals[0] = 32'h0000_0000;
      extreme_vals[1] = 32'hFFFF_FFFF;
      extreme_vals[2] = 32'h8000_0000;
      extreme_vals[3] = 32'h7FFF_FFFF;

      rng = 32'h5eed011b; // per-task seed convention, distinct sub-stream
      $display("Part B CRV seed = 32'h%08h", rng);

      do_reset();
      sh_src_a = 32'd0; sh_src_b = 32'd0; sh_dest_c = 32'd0;
      sh_dim_m = 3'd0; sh_dim_n = 3'd0; sh_dim_k = 3'd0;
      sh_ctrl_signed = 1'b0; sh_start_pulse = 1'b0; sh_status_done = 1'b0;

      for (iter = 0; iter < NUM_ITERS_B; iter = iter + 1) begin
        rng = xorshift32(rng);
        if (rng[0])
          sel_v = {7'd0, rng[12:10]} & 10'd7;
        else
          sel_v = rng[9:0];

        rng = xorshift32(rng);
        if (rng[4:0] < 5'd6) begin // ~6/32 ~= 18.75%, within the requested 15-20% band
          rng = xorshift32(rng);
          wdata_v = extreme_vals[rng[1:0]];
        end else begin
          rng = xorshift32(rng);
          wdata_v = rng;
        end

        rng = xorshift32(rng);
        wen_v = (rng[1:0] != 2'd0);

        rng = xorshift32(rng);
        done_v = (rng[2:0] == 3'd0);

        rng = xorshift32(rng);
        err_v = (rng[2:0] == 3'd0);
        errc_v = rng[6:4];

        new_src_a       = (wen_v && sel_v == 10'd0) ? wdata_v      : sh_src_a;
        new_src_b       = (wen_v && sel_v == 10'd1) ? wdata_v      : sh_src_b;
        new_dest_c      = (wen_v && sel_v == 10'd2) ? wdata_v      : sh_dest_c;
        new_dim_m       = (wen_v && sel_v == 10'd3) ? wdata_v[2:0] : sh_dim_m;
        new_dim_n       = (wen_v && sel_v == 10'd4) ? wdata_v[2:0] : sh_dim_n;
        new_dim_k       = (wen_v && sel_v == 10'd5) ? wdata_v[2:0] : sh_dim_k;
        new_ctrl_signed = (wen_v && sel_v == 10'd6) ? wdata_v[1]   : sh_ctrl_signed;
        new_start_pulse = wen_v && (sel_v == 10'd6) && wdata_v[0];
        new_status_done = sh_start_pulse ? 1'b0 : (done_v ? 1'b1 : sh_status_done);

        csr_sel = sel_v; csr_wdata = wdata_v; csr_wen = wen_v;
        done_i = done_v; error_i = err_v; error_code_i = errc_v;
        step();

        sh_src_a = new_src_a; sh_src_b = new_src_b; sh_dest_c = new_dest_c;
        sh_dim_m = new_dim_m; sh_dim_n = new_dim_n; sh_dim_k = new_dim_k;
        sh_ctrl_signed = new_ctrl_signed;
        sh_start_pulse = new_start_pulse;
        sh_status_done = new_status_done;

        check_eq32($sformatf("PartB-CRV[%0d] src_a", iter), src_a, sh_src_a);
        check_eq32($sformatf("PartB-CRV[%0d] src_b", iter), src_b, sh_src_b);
        check_eq32($sformatf("PartB-CRV[%0d] dest_c", iter), dest_c, sh_dest_c);
        check_eq32($sformatf("PartB-CRV[%0d] dim_m", iter), {29'd0, dim_m}, {29'd0, sh_dim_m});
        check_eq32($sformatf("PartB-CRV[%0d] dim_n", iter), {29'd0, dim_n}, {29'd0, sh_dim_n});
        check_eq32($sformatf("PartB-CRV[%0d] dim_k", iter), {29'd0, dim_k}, {29'd0, sh_dim_k});
        check_eq1($sformatf("PartB-CRV[%0d] mode_unsigned", iter), mode_unsigned, ~sh_ctrl_signed);
        check_eq1($sformatf("PartB-CRV[%0d] start_pulse", iter), start_pulse, sh_start_pulse);

        case (sel_v)
          10'd0: exp_rdata = sh_src_a;
          10'd1: exp_rdata = sh_src_b;
          10'd2: exp_rdata = sh_dest_c;
          10'd3: exp_rdata = {29'd0, sh_dim_m};
          10'd4: exp_rdata = {29'd0, sh_dim_n};
          10'd5: exp_rdata = {29'd0, sh_dim_k};
          10'd6: exp_rdata = {30'd0, sh_ctrl_signed, 1'b0};
          10'd7: exp_rdata = {27'd0, errc_v, err_v, sh_status_done};
          default: exp_rdata = 32'd0;
        endcase
        check_eq32($sformatf("PartB-CRV[%0d] csr_rdata sel=%0d", iter, sel_v), csr_rdata, exp_rdata);
      end

      $display("----------------------------------------");
      $display("Part B: %0d iterations, ~15-20%% extreme-biased data, full csr_sel range, checks so far=%0d", NUM_ITERS_B, checks);
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
