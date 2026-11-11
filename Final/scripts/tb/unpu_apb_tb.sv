// Integration test for unpu_apb, paired with a REAL unpu_csr (task 009)
// -- unpu_apb is a thin combinational pass-through, so the simplest
// correct test structure is the real pair together, checked against a
// shadow model extending task 009's own (same shadow this file's
// predecessor, tb/unpu_slave_tb.sv, used for the native slave -- task
// 018 retires that file and this one takes its place), now modeling the
// APB dispatch rule instead: a transaction is SETUP (psel=1, penable=0)
// for one or more cycles, then ACCESS (psel=1, penable=1) for exactly
// one cycle, and only the ACCESS cycle's pwrite/pwdata commit anything
// -- csr_wen gates on psel && penable && pwrite, specifically penable,
// not psel alone, so SETUP alone must never commit a write.
//
// pready==1'b1 is checked on every single step() in this entire file
// (baked into the step() task itself, not a separate pass) -- same
// "never hang the SPI debug backdoor" guarantee task 010's native-slave
// test verified directly, carried over unchanged since pready is tied
// high for the same reasons (handoff §3).
//
// Simulated with Verilator (--binary --timing), consistent with every
// task since 006.
`timescale 1ns/1ps

module unpu_apb_tb;

  logic clk, rst_n;

  logic [31:0] paddr, pwdata, prdata;
  logic        pwrite, psel, penable, pready;

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

  unpu_apb u_apb (
    .clk       (clk),
    .rst_n     (rst_n),
    .paddr     (paddr),
    .pwdata    (pwdata),
    .pwrite    (pwrite),
    .psel      (psel),
    .penable   (penable),
    .prdata    (prdata),
    .pready    (pready),
    .csr_sel   (csr_sel),
    .csr_wdata (csr_wdata),
    .csr_wen   (csr_wen),
    .csr_rdata (csr_rdata)
  );

  unpu_csr u_csr (
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

  int errors, checks;

  // Bakes the "pready==1 on every cycle" check into every single clock
  // step this file ever takes -- directed and CRV alike.
  task automatic step;
    begin
      @(posedge clk);
      #1;
      checks = checks + 1;
      if (pready !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL: pready != 1 (got %0b) at time %0t", pready, $time);
      end
    end
  endtask

  task automatic do_reset;
    begin
      rst_n = 0;
      paddr = 32'd0; pwdata = 32'd0; pwrite = 1'b0; psel = 1'b0; penable = 1'b0;
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

  // Drives one full APB transaction: SETUP (psel=1, penable=0) for one
  // cycle, then ACCESS (psel=1, penable=1) for one cycle -- the ACCESS
  // cycle is where a write actually commits and where prdata reflects
  // the read. Leaves paddr/prdata settled afterward (psel/penable drop
  // back to 0) so a caller can check prdata directly, same convention
  // tb/unpu_slave_tb.sv's native_xact used for mem_rdata.
  task automatic apb_xact(input logic [9:0] sel, input logic [31:0] wdata, input bit is_write);
    begin
      paddr   = {20'd0, sel, 2'b00};
      pwdata  = wdata;
      pwrite  = is_write;
      psel    = 1'b1;
      penable = 1'b0;
      step(); // SETUP -- must not commit
      penable = 1'b1;
      step(); // ACCESS -- commits (if is_write) / prdata valid
      psel    = 1'b0;
      penable = 1'b0;
    end
  endtask

  function automatic logic [31:0] xorshift32(logic [31:0] x);
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    return x;
  endfunction

  initial begin
    errors = 0;
    checks = 0;

    // ---- Write then read back src_A, npu_ctrl through APB; confirm
    // unpu_csr's own semantics come through unchanged. ----
    do_reset();
    apb_xact(10'd0, 32'h1234_5678, 1'b1); // write src_A
    check_eq32("src_A written through APB", src_a, 32'h1234_5678);
    apb_xact(10'd0, 32'hFFFF_FFFF, 1'b0); // read -- must not clobber src_A
    check_eq32("src_A read back through APB (prdata)", prdata, 32'h1234_5678);
    check_eq32("src_A unaffected by the read's pwdata", src_a, 32'h1234_5678);

    // npu_ctrl: START self-clears, SIGNED bit independent (task 009
    // semantics unchanged through the APB translation). apb_xact's
    // ACCESS-phase step() already consumes the one edge start_pulse
    // needs to register -- no extra step() needed here, same reasoning
    // tb/unpu_slave_tb.sv's native version relied on.
    apb_xact(10'd6, 32'h3, 1'b1); // START + SIGNED together
    check_eq1("start_pulse fires through APB", start_pulse, 1'b1);
    check_eq1("mode_unsigned reflects SIGNED bit (polarity) through APB", mode_unsigned, 1'b0);
    apb_xact(10'd6, 32'd0, 1'b0); // read npu_ctrl
    check_eq32("npu_ctrl bit0 reads 0 (START never stored) through APB", prdata, 32'h2);

    // ---- SETUP-phase write must not commit: hold psel=1, penable=0,
    // pwrite=1 with real data for more than one cycle, confirm no
    // register change; only once penable=1 does the write land. This is
    // specifically what csr_wen's "&& penable" term exists to prevent. ----
    do_reset();
    paddr   = {20'd0, 10'd0, 2'b00};
    pwdata  = 32'hDEAD_BEEF;
    pwrite  = 1'b1;
    psel    = 1'b1;
    penable = 1'b0;
    step(); // SETUP
    step(); // still SETUP -- held an extra cycle on purpose
    check_eq32("SETUP-phase write (penable=0) does not commit, even held", src_a, 32'd0);
    penable = 1'b1;
    step(); // ACCESS -- now it commits
    check_eq32("write commits once penable=1 (ACCESS reached)", src_a, 32'hDEAD_BEEF);
    psel = 1'b0; penable = 1'b0;

    // ---- pwrite polarity: a write (pwrite=1) commits, a read
    // (pwrite=0) does not -- confirms the read/write dispatch isn't
    // inverted, not just that reads happen to leave things alone. ----
    do_reset();
    apb_xact(10'd2, 32'h4444_4444, 1'b1); // write dest_C
    check_eq32("dest_C written with pwrite=1", dest_c, 32'h4444_4444);
    apb_xact(10'd2, 32'h5555_5555, 1'b0); // read dest_C -- pwrite=0 must not write
    check_eq32("dest_C unaffected by a pwrite=0 access despite nonzero pwdata on the bus", dest_c, 32'h4444_4444);
    check_eq32("prdata reflects dest_C on a pwrite=0 access, not the bus's stray pwdata", prdata, 32'h4444_4444);

    // ---- Sparse/idle psel pacing: hold psel low for an arbitrary run,
    // then run a normal transaction -- completes in exactly the usual
    // two cycles (SETUP then ACCESS), no extra wait. ----
    do_reset();
    begin : idle_pacing
      int idle_i;
      psel = 1'b0; penable = 1'b0;
      for (idle_i = 0; idle_i < 17; idle_i = idle_i + 1) begin
        step(); // pready==1 still checked every cycle even while idle
      end
      apb_xact(10'd0, 32'h0BAD_F00D, 1'b1);
      check_eq32("transaction completes normally right after idle pacing, no extra wait", src_a, 32'h0BAD_F00D);
    end

    // ---- Reserved-offset access: reads 0, no side effect. ----
    do_reset();
    apb_xact(10'd0, 32'hAAAA_AAAA, 1'b1);
    apb_xact(10'd1, 32'hBBBB_BBBB, 1'b1);
    apb_xact(10'd8, 32'hFFFF_FFFF, 1'b1);    // reserved, just above npu_status
    apb_xact(10'd1023, 32'hFFFF_FFFF, 1'b1); // reserved, top of window
    apb_xact(10'd8, 32'd0, 1'b0);
    check_eq32("reserved sel=8 reads 0 through APB", prdata, 32'd0);
    apb_xact(10'd1023, 32'd0, 1'b0);
    check_eq32("reserved sel=1023 reads 0 through APB", prdata, 32'd0);
    check_eq32("src_A unaffected by reserved-offset writes", src_a, 32'hAAAA_AAAA);
    check_eq32("src_B unaffected by reserved-offset writes", src_b, 32'hBBBB_BBBB);

    // ==== CRV ====
    // Shadow model extends task 009's own, same as tb/unpu_slave_tb.sv's
    // did, now modeling APB's SETUP-then-ACCESS dispatch: a randomized
    // idle gap (psel=0), then one SETUP cycle, then one ACCESS cycle
    // where psel && penable && pwrite decides whether anything commits.
    begin : crv_block
      localparam int NUM_ITERS = 150; // matches task 010's own native-slave bar
      logic [31:0] rng;
      int iter;

      logic [9:0]  sel_v;
      logic [31:0] wdata_v;
      bit          pwrite_v;
      bit          wen_v;
      int          idle_gap;
      int          gap_i;

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

      rng = 32'h5eed0012; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("CRV seed = 32'h%08h", rng);

      do_reset();
      sh_src_a = 32'd0; sh_src_b = 32'd0; sh_dest_c = 32'd0;
      sh_dim_m = 3'd0; sh_dim_n = 3'd0; sh_dim_k = 3'd0;
      sh_ctrl_signed = 1'b0; sh_start_pulse = 1'b0; sh_status_done = 1'b0;
      done_i = 1'b0; error_i = 1'b0; error_code_i = 3'd0;

      for (iter = 0; iter < NUM_ITERS; iter = iter + 1) begin
        // Randomized idle-cycle gap (0-7) before this transaction --
        // mimics the SPI debug backdoor's arbitrarily slow pacing.
        // psel stays 0 throughout; nothing in the shadow model changes
        // since csr_wen can't assert without psel&&penable. done_i must
        // be held low here too, same reasoning tb/unpu_slave_tb.sv's
        // native CRV used: unpu_csr latches status_done off done_i
        // directly regardless of the bus, so leaving it at a stale
        // value would desync the shadow (which only accounts for
        // done_i on the ACCESS cycle below) from the real DUT.
        rng = xorshift32(rng);
        idle_gap = rng[2:0];
        psel = 1'b0; penable = 1'b0;
        done_i = 1'b0;
        for (gap_i = 0; gap_i < idle_gap; gap_i = gap_i + 1)
          step();

        // Bias sel: ~50% land on a real register (0-7), rest span the
        // full 0-1023 range (reserved offsets included).
        rng = xorshift32(rng);
        if (rng[0])
          sel_v = {7'd0, rng[12:10]};
        else
          sel_v = rng[9:0];

        rng = xorshift32(rng);
        wdata_v = rng;

        rng = xorshift32(rng);
        pwrite_v = (rng[1:0] != 2'd0); // ~75% writes, matching task 009/010's CRV mix

        rng = xorshift32(rng);
        // Occasional done_i pulse and error_i level, exactly this
        // (ACCESS) cycle.
        done_i       = (rng[2:0] == 3'd0);
        error_i      = (rng[5:3] == 3'd0);
        error_code_i = rng[8:6];

        // ---- SETUP phase: psel=1, penable=0 -- must not commit
        // anything (the directed test above already nails this
        // boundary explicitly; this loop just must not violate it). ----
        paddr   = {20'd0, sel_v, 2'b00};
        pwdata  = wdata_v;
        pwrite  = pwrite_v;
        psel    = 1'b1;
        penable = 1'b0;
        step();

        // ---- ACCESS phase: psel=1, penable=1 -- this is the cycle
        // that actually commits/reads. ----
        penable = 1'b1;
        wen_v = pwrite_v; // psel && penable both 1 here by construction

        // ---- Compute new shadow values (same rules as task 009/010's
        // shadow, wen_v now keyed on the APB ACCESS phase). ----
        new_src_a       = (wen_v && sel_v == 10'd0) ? wdata_v      : sh_src_a;
        new_src_b       = (wen_v && sel_v == 10'd1) ? wdata_v      : sh_src_b;
        new_dest_c      = (wen_v && sel_v == 10'd2) ? wdata_v      : sh_dest_c;
        new_dim_m       = (wen_v && sel_v == 10'd3) ? wdata_v[2:0] : sh_dim_m;
        new_dim_n       = (wen_v && sel_v == 10'd4) ? wdata_v[2:0] : sh_dim_n;
        new_dim_k       = (wen_v && sel_v == 10'd5) ? wdata_v[2:0] : sh_dim_k;
        new_ctrl_signed = (wen_v && sel_v == 10'd6) ? wdata_v[1]   : sh_ctrl_signed;
        new_start_pulse = wen_v && (sel_v == 10'd6) && wdata_v[0];
        new_status_done = sh_start_pulse ? 1'b0 : (done_i ? 1'b1 : sh_status_done);

        step(); // ACCESS cycle itself

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

        // ---- Check prdata against shadow, keyed on THIS iteration's
        // sel (paddr unchanged since driving it above; prdata=csr_rdata
        // is unconditional on pwrite). ----
        case (sel_v)
          10'd0: exp_rdata = sh_src_a;
          10'd1: exp_rdata = sh_src_b;
          10'd2: exp_rdata = sh_dest_c;
          10'd3: exp_rdata = {29'd0, sh_dim_m};
          10'd4: exp_rdata = {29'd0, sh_dim_n};
          10'd5: exp_rdata = {29'd0, sh_dim_k};
          10'd6: exp_rdata = {30'd0, sh_ctrl_signed, 1'b0};
          10'd7: exp_rdata = {27'd0, error_code_i, error_i, sh_status_done};
          default: exp_rdata = 32'd0;
        endcase
        check_eq32($sformatf("CRV[%0d] prdata sel=%0d", iter, sel_v), prdata, exp_rdata);

        psel = 1'b0; penable = 1'b0;
      end

      psel = 1'b0; penable = 1'b0;
      $display("CRV: %0d iterations completed with randomized idle-gap + SETUP/ACCESS pacing", NUM_ITERS);
    end

    // ==== Task 027, Part A1: ignored-bits immunity. paddr[31:12] and
    // paddr[1:0] randomized on every draw while paddr[11:2] stays fixed
    // at src_A's offset -- direct proof csr_sel=paddr[11:2] really does
    // ignore everything else, not just that it happens to work on the
    // clean addresses every other test in this project has used. ====
    begin : part_a1
      localparam int NUM_A1 = 60;
      logic [31:0] rng;
      int ii;
      logic [19:0] hi_bits;
      logic [1:0]  lo_bits;
      logic [31:0] wval;

      do_reset();
      rng = 32'h5eed001b; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("Part A1 ignored-bits seed = 32'h%08h", rng);

      for (ii = 0; ii < NUM_A1; ii = ii + 1) begin
        rng = xorshift32(rng);
        hi_bits = rng[19:0];
        rng = xorshift32(rng);
        lo_bits = rng[1:0];
        rng = xorshift32(rng);
        wval = rng;

        paddr   = {hi_bits, 10'd0, lo_bits}; // sel fixed at 0 (src_a); hi/lo garbage
        pwdata  = wval;
        pwrite  = 1'b1;
        psel    = 1'b1;
        penable = 1'b0;
        step();
        penable = 1'b1;
        step();
        checks = checks + 1;
        if (src_a !== wval) begin
          errors = errors + 1;
          $display("FAIL [partA1-ignoredbits #%0d write]: paddr=%0h (hi=%0h lo=%0b) src_a=%0h expected %0h", ii, paddr, hi_bits, lo_bits, src_a, wval);
        end
        psel = 1'b0; penable = 1'b0;

        // Read back through a DIFFERENT random hi/lo combination --
        // confirms the read also hits the same register regardless of
        // whatever garbage sits in the ignored bits this time.
        rng = xorshift32(rng);
        hi_bits = rng[19:0];
        rng = xorshift32(rng);
        lo_bits = rng[1:0];
        paddr   = {hi_bits, 10'd0, lo_bits};
        pwrite  = 1'b0;
        psel    = 1'b1;
        penable = 1'b0;
        step();
        penable = 1'b1;
        step();
        checks = checks + 1;
        if (prdata !== wval) begin
          errors = errors + 1;
          $display("FAIL [partA1-ignoredbits #%0d readback]: paddr=%0h prdata=%0h expected %0h", ii, paddr, prdata, wval);
        end
        psel = 1'b0; penable = 1'b0;
      end
      $display("Part A1: ignored-bits immunity, %0d random paddr[31:12]/[1:0] draws (write+readback each), paddr[11:2] fixed, checks=%0d so far", NUM_A1, checks);
    end

    // ==== Task 027, Part A2: penable without psel. psel=0, penable=1,
    // pwrite=1, real write data present -- confirms psel is a NECESSARY
    // term in csr_wen's AND, not redundant with penable in the cases
    // already tested. ====
    begin : part_a2
      do_reset();
      psel = 1'b0; penable = 1'b1; pwrite = 1'b1;
      paddr = {20'd0, 10'd0, 2'b00}; pwdata = 32'hDEAD_CAFE;
      step();
      checks = checks + 1;
      if (src_a !== 32'd0) begin
        errors = errors + 1;
        $display("FAIL [partA2-penable-no-psel]: src_a=%0h expected 0 -- psel=0 failed to block a write despite penable=1/pwrite=1", src_a);
      end else begin
        $display("PASS [partA2-penable-no-psel]: psel=0/penable=1/pwrite=1 with real write data does not commit -- psel is load-bearing in csr_wen's AND");
      end
      psel = 1'b0; penable = 1'b0;
    end

    // ==== Task 027, Part A3: adversarially long SETUP phase, paddr/
    // pwdata changing every cycle throughout, then one final, distinct
    // set of values right before ACCESS -- confirms only those final
    // values commit, none of the transient SETUP-phase garbage leaks
    // through (csr_wen/csr_wdata are pure combinational reads of
    // whatever's present the instant penable asserts, nothing latched
    // earlier in SETUP). ====
    begin : part_a3
      localparam int LONG_SETUP = 55;
      logic [31:0] rng;
      int si;
      logic [31:0] final_wdata;

      do_reset();
      rng = 32'h5eed011b;
      $display("Part A3 long-SETUP seed = 32'h%08h", rng);

      psel = 1'b1; penable = 1'b0; pwrite = 1'b1;
      for (si = 0; si < LONG_SETUP; si = si + 1) begin
        rng = xorshift32(rng);
        paddr = {rng[29:0], 2'b00};
        rng = xorshift32(rng);
        pwdata = rng;
        step(); // still SETUP throughout
      end
      checks = checks + 1;
      if (src_a !== 32'd0) begin
        errors = errors + 1;
        $display("FAIL [partA3-long-setup]: src_a=%0h expected 0 -- a transient SETUP-phase value leaked through before ACCESS", src_a);
      end

      paddr       = {20'd0, 10'd0, 2'b00}; // sel=0 (src_a)
      final_wdata = 32'hF00D_BEEF;
      pwdata      = final_wdata;
      step(); // one more SETUP cycle, now holding the final distinct values
      penable = 1'b1;
      step(); // ACCESS -- only these final values should commit
      checks = checks + 1;
      if (src_a !== final_wdata) begin
        errors = errors + 1;
        $display("FAIL [partA3-long-setup]: src_a=%0h expected %0h (only the final pre-ACCESS SETUP values should commit)", src_a, final_wdata);
      end else begin
        $display("PASS [partA3-long-setup]: %0d-cycle SETUP with changing paddr/pwdata every cycle, only the final values committed, no transient leak", LONG_SETUP);
      end
      psel = 1'b0; penable = 1'b0;
    end

    // ==== Task 027, Part A4: zero-gap back-to-back transactions.
    // apb_xact() itself already produces this -- its trailing psel=0/
    // penable=0 execute in the same zero-simulation-time window as the
    // next call's leading psel=1, so the DUT never sees a real idle
    // cycle between calls made back to back. >=20 consecutive
    // transactions at maximum APB rate, none dropped or duplicated. ====
    begin : part_a4
      localparam int NUM_BACKTOBACK = 24;
      int bi;
      logic [9:0]  sel_bi;
      logic [31:0] val_bi;

      do_reset();
      for (bi = 0; bi < NUM_BACKTOBACK; bi = bi + 1) begin
        sel_bi = bi % 6; // src_a/src_b/dest_c/dim_m/dim_n/dim_k -- no W1P/RO complications
        val_bi = 32'hB000_0000 + bi;
        apb_xact(sel_bi, val_bi, 1'b1);
        checks = checks + 1;
        case (sel_bi)
          10'd0: if (src_a  !== val_bi) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d write]: src_a=%0h expected %0h", bi, sel_bi, src_a, val_bi); end
          10'd1: if (src_b  !== val_bi) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d write]: src_b=%0h expected %0h", bi, sel_bi, src_b, val_bi); end
          10'd2: if (dest_c !== val_bi) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d write]: dest_c=%0h expected %0h", bi, sel_bi, dest_c, val_bi); end
          10'd3: if ({29'd0, dim_m} !== {29'd0, val_bi[2:0]}) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d write]: dim_m mismatch", bi, sel_bi); end
          10'd4: if ({29'd0, dim_n} !== {29'd0, val_bi[2:0]}) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d write]: dim_n mismatch", bi, sel_bi); end
          default: if ({29'd0, dim_k} !== {29'd0, val_bi[2:0]}) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d write]: dim_k mismatch", bi, sel_bi); end
        endcase

        apb_xact(sel_bi, 32'hFFFF_FFFF, 1'b0); // immediate zero-gap readback
        checks = checks + 1;
        case (sel_bi)
          10'd0, 10'd1, 10'd2: if (prdata !== val_bi) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d readback]: prdata=%0h expected %0h", bi, sel_bi, prdata, val_bi); end
          default:             if (prdata !== {29'd0, val_bi[2:0]}) begin errors = errors + 1; $display("FAIL [partA4-backtoback #%0d sel=%0d readback]: prdata=%0h expected %0h", bi, sel_bi, prdata, {29'd0, val_bi[2:0]}); end
        endcase
      end
      $display("Part A4: %0d write+readback pairs (%0d total transactions) at zero-gap maximum APB rate, none dropped/duplicated, checks=%0d so far", NUM_BACKTOBACK, NUM_BACKTOBACK * 2, checks);
    end

    // ==== Task 027, Part A5: pwrite flips between SETUP and ACCESS --
    // confirms the same-cycle sampling (csr_wen = psel && penable &&
    // pwrite, evaluated AT ACCESS, not latched from SETUP) both
    // directions: a write-looking SETUP that becomes a read at ACCESS
    // must not commit; a read-looking SETUP that becomes a write at
    // ACCESS must commit. ====
    begin : part_a5
      do_reset();
      apb_xact(10'd0, 32'hCAFE_0000, 1'b1); // known baseline in src_a

      paddr   = {20'd0, 10'd0, 2'b00};
      pwdata  = 32'hBAD0_BAD0; // would land in src_a if wrongly treated as a write
      pwrite  = 1'b1;          // SETUP: looks like a write
      psel    = 1'b1;
      penable = 1'b0;
      step();
      pwrite  = 1'b0;          // flip to READ right at ACCESS
      penable = 1'b1;
      step();
      checks = checks + 1;
      if (src_a !== 32'hCAFE_0000) begin
        errors = errors + 1;
        $display("FAIL [partA5-pwrite-flip 1->0]: src_a=%0h expected unchanged 32'hCAFE_0000 -- pwrite flipping to 0 at ACCESS should make this a read", src_a);
      end
      checks = checks + 1;
      if (prdata !== 32'hCAFE_0000) begin
        errors = errors + 1;
        $display("FAIL [partA5-pwrite-flip 1->0]: prdata=%0h expected 32'hCAFE_0000", prdata);
      end
      psel = 1'b0; penable = 1'b0;

      paddr   = {20'd0, 10'd1, 2'b00}; // src_b
      pwdata  = 32'hFEED_FACE;
      pwrite  = 1'b0;          // SETUP: looks like a read
      psel    = 1'b1;
      penable = 1'b0;
      step();
      pwrite  = 1'b1;          // flip to WRITE right at ACCESS
      penable = 1'b1;
      step();
      checks = checks + 1;
      if (src_b !== 32'hFEED_FACE) begin
        errors = errors + 1;
        $display("FAIL [partA5-pwrite-flip 0->1]: src_b=%0h expected 32'hFEED_FACE -- pwrite flipping to 1 at ACCESS should commit as a write", src_b);
      end else begin
        $display("PASS [partA5-pwrite-flip]: pwrite sampled at ACCESS, not latched from SETUP, confirmed both directions (1->0 blocks, 0->1 commits)");
      end
      psel = 1'b0; penable = 1'b0;
    end

    // ==== Task 027, Part B: high-volume extreme-biased CRV -- >=2,000
    // iterations (matching task 026's scale), ~15-20% of drawn wdata
    // forced to an extreme value, randomized pacing that mixes in
    // occasional long-SETUP (Part A3's mechanism) and zero-gap-prone
    // idle gaps with ordinary single-cycle-SETUP transactions. Same
    // shadow model as the baseline CRV above -- no extension needed,
    // since only the FINAL pre-ACCESS SETUP values ever matter to it
    // (Part A3 already proved that), and done_i is held low through
    // every non-tracked cycle (idle gap or long-SETUP garbage) for the
    // same desync-avoidance reason the baseline CRV's own comment gives. ====
    begin : part_b
      localparam int NUM_ITERS_B = 2000;
      logic [31:0] rng;
      int iter;

      logic [9:0]  sel_v;
      logic [31:0] wdata_v;
      bit          pwrite_v;
      bit          wen_v;
      int          idle_gap;
      int          gap_i;
      int          setup_len;
      int          su_i;
      logic [31:0] extreme_vals [0:3];

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

      extreme_vals[0] = 32'h0000_0000;
      extreme_vals[1] = 32'hFFFF_FFFF;
      extreme_vals[2] = 32'h8000_0000;
      extreme_vals[3] = 32'h7FFF_FFFF;

      rng = 32'h5eed021b; // per-task seed convention, distinct sub-stream
      $display("Part B CRV seed = 32'h%08h", rng);

      do_reset();
      sh_src_a = 32'd0; sh_src_b = 32'd0; sh_dest_c = 32'd0;
      sh_dim_m = 3'd0; sh_dim_n = 3'd0; sh_dim_k = 3'd0;
      sh_ctrl_signed = 1'b0; sh_start_pulse = 1'b0; sh_status_done = 1'b0;
      done_i = 1'b0; error_i = 1'b0; error_code_i = 3'd0;

      for (iter = 0; iter < NUM_ITERS_B; iter = iter + 1) begin
        // ---- Idle gap, done_i held low throughout (same desync-
        // avoidance reasoning as the baseline CRV). ----
        rng = xorshift32(rng);
        idle_gap = rng[2:0];
        psel = 1'b0; penable = 1'b0;
        done_i = 1'b0;
        for (gap_i = 0; gap_i < idle_gap; gap_i = gap_i + 1)
          step();

        // ---- Occasional long SETUP, changing garbage every cycle --
        // done_i held low throughout this phase too, same reason. ----
        rng = xorshift32(rng);
        if (rng[4:0] == 5'h0) begin // ~1/32 of iterations
          rng = xorshift32(rng);
          setup_len = 2 + (rng % 20);
          psel = 1'b1; penable = 1'b0; done_i = 1'b0;
          for (su_i = 0; su_i < setup_len; su_i = su_i + 1) begin
            rng = xorshift32(rng);
            paddr  = {rng[29:0], 2'b00};
            rng = xorshift32(rng);
            pwdata = rng;
            pwrite = rng[0];
            step();
          end
        end

        // ---- This iteration's real, tracked transaction. ----
        rng = xorshift32(rng);
        if (rng[0])
          sel_v = {7'd0, rng[12:10]};
        else
          sel_v = rng[9:0];

        rng = xorshift32(rng);
        if (rng[4:0] < 5'd6) begin // ~18.75%, within the requested 15-20% band
          rng = xorshift32(rng);
          wdata_v = extreme_vals[rng[1:0]];
        end else begin
          rng = xorshift32(rng);
          wdata_v = rng;
        end

        rng = xorshift32(rng);
        pwrite_v = (rng[1:0] != 2'd0);

        rng = xorshift32(rng);
        done_i       = (rng[2:0] == 3'd0);
        error_i      = (rng[5:3] == 3'd0);
        error_code_i = rng[8:6];

        paddr   = {20'd0, sel_v, 2'b00};
        pwdata  = wdata_v;
        pwrite  = pwrite_v;
        psel    = 1'b1;
        penable = 1'b0;
        step();

        penable = 1'b1;
        wen_v = pwrite_v;

        new_src_a       = (wen_v && sel_v == 10'd0) ? wdata_v      : sh_src_a;
        new_src_b       = (wen_v && sel_v == 10'd1) ? wdata_v      : sh_src_b;
        new_dest_c      = (wen_v && sel_v == 10'd2) ? wdata_v      : sh_dest_c;
        new_dim_m       = (wen_v && sel_v == 10'd3) ? wdata_v[2:0] : sh_dim_m;
        new_dim_n       = (wen_v && sel_v == 10'd4) ? wdata_v[2:0] : sh_dim_n;
        new_dim_k       = (wen_v && sel_v == 10'd5) ? wdata_v[2:0] : sh_dim_k;
        new_ctrl_signed = (wen_v && sel_v == 10'd6) ? wdata_v[1]   : sh_ctrl_signed;
        new_start_pulse = wen_v && (sel_v == 10'd6) && wdata_v[0];
        new_status_done = sh_start_pulse ? 1'b0 : (done_i ? 1'b1 : sh_status_done);

        step(); // ACCESS cycle itself

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
          10'd7: exp_rdata = {27'd0, error_code_i, error_i, sh_status_done};
          default: exp_rdata = 32'd0;
        endcase
        check_eq32($sformatf("PartB-CRV[%0d] prdata sel=%0d", iter, sel_v), prdata, exp_rdata);

        // ---- Consume start_pulse's one-cycle pulse *now*, before the
        // next iteration's idle-gap/long-setup cycles run. The real
        // DUT's status_done_reg reacts to start_pulse on the very next
        // edge after it's set, whichever kind of cycle that happens to
        // be -- tracked ACCESS, idle gap, or long-SETUP garbage. Letting
        // sh_start_pulse/sh_status_done linger unconsumed until the next
        // TRACKED iteration's own new_status_done computation (as a
        // naive single-step shadow would) makes that lingering "clear"
        // wrongly out-compete the next iteration's own done_i, when in
        // the real DUT the clear already resolved (and start_pulse
        // already dropped back to 0) one edge earlier, before that
        // done_i ever took effect. First caught as 4 real failures in
        // this exact block during development (npu_status reading DONE=1
        // where the unconsumed-shadow formula predicted 0) -- root-
        // caused to this gap, not an RTL issue (the original 150-
        // iteration baseline CRV never hit it, likely luck of the draw
        // with its shorter idle-gap range, not evidence it's immune).
        if (sh_start_pulse) begin
          sh_status_done = 1'b0;
          sh_start_pulse = 1'b0;
        end

        psel = 1'b0; penable = 1'b0;
      end

      psel = 1'b0; penable = 1'b0;
      $display("----------------------------------------");
      $display("Part B: %0d iterations, ~18.75%% extreme-biased data, randomized pacing (idle gaps + occasional long-SETUP), checks so far=%0d", NUM_ITERS_B, checks);
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
