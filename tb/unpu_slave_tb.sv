// Integration test for unpu_slave, paired with a REAL unpu_csr (task
// 009) -- unpu_slave is a thin combinational pass-through, so the
// simplest correct test structure is the real pair together, checked
// against a shadow model extending task 009's own, now also modeling the
// native-bus dispatch rule: wstrb==0 -> read, nonzero -> full-word write,
// valid gates everything, ready is always 1 (never stalls, never hangs
// the SPI debug backdoor -- handoff §3).
//
// mem_ready==1'b1 is checked on every single step() in this entire file
// (baked into the step() task itself, not a separate pass) -- this is
// the actual "never hang" guarantee task 010 asks to verify directly,
// not just infer from transactions completing.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006-009 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
`timescale 1ns/1ps

module unpu_slave_tb;

  logic clk, rst_n;

  logic [31:0] mem_addr, mem_wdata, mem_rdata;
  logic [3:0]  mem_wstrb;
  logic        mem_valid, mem_ready;

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

  unpu_slave u_slave (
    .clk       (clk),
    .rst_n     (rst_n),
    .mem_addr  (mem_addr),
    .mem_wdata (mem_wdata),
    .mem_wstrb (mem_wstrb),
    .mem_valid (mem_valid),
    .mem_rdata (mem_rdata),
    .mem_ready (mem_ready),
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

  // Bakes the "mem_ready==1 on every cycle" check into every single
  // clock step this file ever takes -- directed and CRV alike.
  task automatic step;
    begin
      @(posedge clk);
      #1;
      checks = checks + 1;
      if (mem_ready !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL: mem_ready != 1 (got %0b) at time %0t", mem_ready, $time);
      end
    end
  endtask

  task automatic do_reset;
    begin
      rst_n = 0;
      mem_addr = 32'd0; mem_wdata = 32'd0; mem_wstrb = 4'd0; mem_valid = 1'b0;
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

  // Convenience: drives one native transaction (sel encoded as
  // mem_addr[11:2], byte offset bits held 0 -- word-aligned CSR access)
  // for exactly one cycle, then drops mem_valid.
  task automatic native_xact(input logic [9:0] sel, input logic [31:0] wdata, input logic [3:0] wstrb);
    begin
      mem_addr  = {20'd0, sel, 2'b00};
      mem_wdata = wdata;
      mem_wstrb = wstrb;
      mem_valid = 1'b1;
      step();
      mem_valid = 1'b0;
      mem_wstrb = 4'd0;
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

    // ---- Write then read back src_A, npu_ctrl through the native port;
    // confirm unpu_csr's own semantics come through unchanged. ----
    do_reset();
    native_xact(10'd0, 32'h1234_5678, 4'hF); // write src_A
    check_eq32("src_A written through native port", src_a, 32'h1234_5678);
    native_xact(10'd0, 32'hFFFF_FFFF, 4'h0); // read (wstrb=0) -- must not clobber src_A
    check_eq32("src_A read back through native port", mem_rdata, 32'h1234_5678);
    check_eq32("src_A unaffected by the read's mem_wdata", src_a, 32'h1234_5678);

    // npu_ctrl: START self-clears, SIGNED bit independent (task 009
    // semantics unchanged through the native-bus translation).
    // native_xact already consumes the one edge start_pulse needs to
    // register (it fires the write, then drops mem_valid) -- no extra
    // step() needed here, start_pulse is already observable right after.
    native_xact(10'd6, 32'h3, 4'hF); // START + SIGNED together
    check_eq1("start_pulse fires through native port", start_pulse, 1'b1);
    check_eq1("mode_unsigned reflects SIGNED bit (polarity) through native port", mode_unsigned, 1'b0);
    native_xact(10'd6, 32'd0, 4'h0); // read npu_ctrl
    check_eq32("npu_ctrl bit0 reads 0 (START never stored) through native port", mem_rdata, 32'h2);

    // ---- wstrb==0 on an address just written: confirms a read, not a
    // second write. ----
    do_reset();
    native_xact(10'd1, 32'hAAAA_AAAA, 4'hF);
    check_eq32("src_B written", src_b, 32'hAAAA_AAAA);
    native_xact(10'd1, 32'h5555_5555, 4'h0); // wstrb=0 -- must be a read despite nonzero mem_wdata on the bus
    check_eq32("src_B unchanged by a wstrb=0 access", src_b, 32'hAAAA_AAAA);
    check_eq32("mem_rdata reflects the read, not the bus's stray wdata", mem_rdata, 32'hAAAA_AAAA);

    // ---- Any nonzero wstrb commits the FULL word -- no partial-byte
    // merge, try more than one pattern. ----
    do_reset();
    native_xact(10'd2, 32'h1111_1111, 4'hF);
    check_eq32("dest_C full write with wstrb=F", dest_c, 32'h1111_1111);
    native_xact(10'd2, 32'h2222_2222, 4'h1); // a single-byte strobe still commits the FULL word, per assumption 2
    check_eq32("dest_C full write with wstrb=1 (no partial merge)", dest_c, 32'h2222_2222);
    native_xact(10'd2, 32'h3333_3333, 4'h3);
    check_eq32("dest_C full write with wstrb=3 (no partial merge)", dest_c, 32'h3333_3333);

    // ---- mem_valid=0 with mem_wstrb nonzero: no write. ----
    do_reset();
    native_xact(10'd0, 32'hCAFE_0000, 4'hF);
    mem_addr = {20'd0, 10'd0, 2'b00};
    mem_wdata = 32'hDEAD_0000;
    mem_wstrb = 4'hF;
    mem_valid = 1'b0; // valid deasserted -- csr_wen must gate on this, not fire off wstrb alone
    step();
    check_eq32("no write occurs when mem_valid=0 despite nonzero wstrb", src_a, 32'hCAFE_0000);
    mem_wstrb = 4'd0;

    // ---- Sparse/idle pacing: hold mem_valid low for an arbitrary run,
    // then assert -- the very next cycle completes the transaction. ----
    do_reset();
    begin : idle_pacing
      int idle_i;
      mem_valid = 1'b0;
      for (idle_i = 0; idle_i < 17; idle_i = idle_i + 1) begin
        step(); // mem_ready==1 still checked every cycle even while idle
      end
      native_xact(10'd0, 32'h0BAD_F00D, 4'hF);
      check_eq32("transaction completes the very next cycle after idle pacing, no extra wait", src_a, 32'h0BAD_F00D);
    end

    // ---- Reserved-offset access: reads 0, no side effect. ----
    do_reset();
    native_xact(10'd0, 32'hAAAA_AAAA, 4'hF);
    native_xact(10'd1, 32'hBBBB_BBBB, 4'hF);
    native_xact(10'd8, 32'hFFFF_FFFF, 4'hF);    // reserved, just above npu_status
    native_xact(10'd1023, 32'hFFFF_FFFF, 4'hF); // reserved, top of window
    native_xact(10'd8, 32'd0, 4'h0);
    check_eq32("reserved sel=8 reads 0 through native port", mem_rdata, 32'd0);
    native_xact(10'd1023, 32'd0, 4'h0);
    check_eq32("reserved sel=1023 reads 0 through native port", mem_rdata, 32'd0);
    check_eq32("src_A unaffected by reserved-offset writes", src_a, 32'hAAAA_AAAA);
    check_eq32("src_B unaffected by reserved-offset writes", src_b, 32'hBBBB_BBBB);

    // ==== CRV ====
    // Shadow model extends task 009's own: same register-update rules,
    // plus the native-bus dispatch rule (wen = valid && wstrb!=0) and
    // randomized idle-cycle gaps standing in for the SPI backdoor's
    // arbitrary pacing.
    begin : crv_block
      localparam int NUM_ITERS = 150; // well over the required >=64
      logic [31:0] rng;
      int iter;

      logic [9:0]  sel_v;
      logic [31:0] wdata_v;
      logic [3:0]  wstrb_v;
      bit          valid_v;
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

      rng = 32'h5eed000a;
      $display("CRV seed = 32'h%08h", rng);

      do_reset();
      sh_src_a = 32'd0; sh_src_b = 32'd0; sh_dest_c = 32'd0;
      sh_dim_m = 3'd0; sh_dim_n = 3'd0; sh_dim_k = 3'd0;
      sh_ctrl_signed = 1'b0; sh_start_pulse = 1'b0; sh_status_done = 1'b0;
      done_i = 1'b0; error_i = 1'b0; error_code_i = 3'd0;

      for (iter = 0; iter < NUM_ITERS; iter = iter + 1) begin
        // Randomized idle-cycle gap (0-7) before this transaction --
        // mimics the SPI debug backdoor's arbitrarily slow pacing.
        // mem_valid stays 0 throughout; nothing in the shadow model
        // changes since csr_wen can't assert without valid. done_i must
        // be held low here too -- it's the one signal below that isn't
        // gated by mem_valid at all (unpu_csr latches status_done off
        // done_i directly, task 006/009), so leaving it at whatever a
        // previous iteration last drove it to would let status_done
        // change during these un-tracked idle cycles, desyncing the
        // shadow (which only accounts for done_i on the transaction
        // cycle below) from the real DUT.
        rng = xorshift32(rng);
        idle_gap = rng[2:0];
        mem_valid = 1'b0;
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
        wstrb_v = (rng[1:0] != 2'd0) ? 4'hF : 4'h0; // ~75% writes, matching task 009's CRV mix
        valid_v = 1'b1; // this transaction cycle is always the active one; idle gaps above already covered valid=0

        rng = xorshift32(rng);
        // Occasional done_i pulse and error_i level, exactly this cycle.
        done_i       = (rng[2:0] == 3'd0);
        error_i      = (rng[5:3] == 3'd0);
        error_code_i = rng[8:6];

        wen_v = valid_v && (wstrb_v != 4'h0);

        // ---- Compute new shadow values (same rules as task 009's
        // unpu_csr_tb, extended with the native dispatch's wen_v). ----
        new_src_a       = (wen_v && sel_v == 10'd0) ? wdata_v      : sh_src_a;
        new_src_b       = (wen_v && sel_v == 10'd1) ? wdata_v      : sh_src_b;
        new_dest_c      = (wen_v && sel_v == 10'd2) ? wdata_v      : sh_dest_c;
        new_dim_m       = (wen_v && sel_v == 10'd3) ? wdata_v[2:0] : sh_dim_m;
        new_dim_n       = (wen_v && sel_v == 10'd4) ? wdata_v[2:0] : sh_dim_n;
        new_dim_k       = (wen_v && sel_v == 10'd5) ? wdata_v[2:0] : sh_dim_k;
        new_ctrl_signed = (wen_v && sel_v == 10'd6) ? wdata_v[1]   : sh_ctrl_signed;
        new_start_pulse = wen_v && (sel_v == 10'd6) && wdata_v[0];
        new_status_done = sh_start_pulse ? 1'b0 : (done_i ? 1'b1 : sh_status_done);

        // ---- Drive the native port and advance one cycle. ----
        mem_addr  = {20'd0, sel_v, 2'b00};
        mem_wdata = wdata_v;
        mem_wstrb = wstrb_v;
        mem_valid = valid_v;
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

        // ---- Check mem_rdata against shadow, keyed on THIS cycle's
        // sel (mem_addr unchanged since driving it above). ----
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
        check_eq32($sformatf("CRV[%0d] mem_rdata sel=%0d", iter, sel_v), mem_rdata, exp_rdata);
      end

      mem_valid = 1'b0;
      $display("CRV: %0d iterations completed with randomized idle-gap pacing", NUM_ITERS);
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
