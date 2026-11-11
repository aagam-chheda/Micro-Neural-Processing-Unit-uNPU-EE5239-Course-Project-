// Stall test: proves dropping array_en mid-stream freezes the skew bank,
// all 16 PEs, and the de-skew bank on the same clock edge, and that
// resuming afterward is bit-identical to an unstalled run. Reuses the
// cross_terms vectors and skew -> unpu_grid -> unpu_deskew chain built in
// task 004 (tb/unpu_skew_tb.sv) unchanged.
//
// Bookkeeping: driven and checked against an active-cycle counter
// (active_cyc), not raw simulation/wall-clock cycles -- a stall pauses
// the clock the timing contract is measured against, not the clock
// itself. active_cyc increments once per edge on which array_en was 1
// during that edge; it does not advance on edges where the array was
// frozen. See CLAUDE.md for the underlying timing contract this still
// must satisfy once active_cyc is substituted for wall-clock cycles.
//
// Simulated with Icarus Verilog (iverilog/vvp) -- Xcelium not available in
// this environment, same as unpu_pe_tb.sv/unpu_grid_tb.sv/unpu_skew_tb.sv.
//
// Task 013 (verification-debt retrofit): this module was already closest
// to the CRV bar (randomized stall duration/placement existed since task
// 005) -- the remaining gap was scope: only cross_terms as the data/
// shape source. Extended below to run the same baseline+early/mid/late
// pattern across all 64 crv_* cases from task 006 Part A, with the
// early/mid/late trigger points clamped per case's own active_cyc_max
// (derived from that case's real M) so they stay valid for M<4 cases too
// -- in practice the clamp rarely engages, since even the smallest
// active_cyc_max (M=1) comfortably exceeds all three trigger values.
// Simulated with Verilator for this addition -- see tb/unpu_pe_tb.sv's
// header for why the Icarus line above is stale.
`timescale 1ns/1ps

module unpu_stall_tb;

  logic clk;
  logic rst_n;
  logic array_en;
  logic mode_unsigned;

  // unpu_skew <-> unpu_grid
  logic [3:0][7:0] a_raw;
  logic [3:0][7:0] skew_act_out;

  // unpu_grid itself
  logic [3:0][3:0]      weight_load;
  logic [3:0][3:0][7:0] weight_in;
  logic [3:0][31:0]     grid_psum_in;   // north edge, unused: tied 0 for the whole run
  logic [3:0][7:0]      grid_act_out;   // east edge, unused by this tb
  logic [3:0][31:0]     grid_psum_out;

  // unpu_grid -> unpu_deskew
  logic [3:0][31:0] c_out;

  int errors;
  int checks;
  int frozen_checks;
  // Single seeded stream for baseline, crv and Part A draws. This used to be $random(g_seed)
  // (task 030): $random's algorithm is implementation-defined -- Verilator
  // implements its own (VL_RANDOM_SEEDED_II reseeds an internal xoshiro
  // generator), Xcelium another -- so the same seed gave different stall
  // lengths per simulator and frozen_checks differed (Verilator 250,245 vs
  // Xcelium 252,225, a whole 44 stall cycles x 45 registers). Now drawn from
  // this file's own xorshift32(), like Part B and every other campaign TB.
  logic [31:0] g_rng;

  unpu_skew u_skew (
    .clk      (clk),
    .rst_n    (rst_n),
    .array_en (array_en),
    .a_raw    (a_raw),
    .act_out  (skew_act_out)
  );

  unpu_grid u_grid (
    .clk           (clk),
    .rst_n         (rst_n),
    .array_en      (array_en),
    .mode_unsigned (mode_unsigned),
    .weight_load   (weight_load),
    .weight_in     (weight_in),
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
    .c_out    (c_out)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  task automatic step;
    @(posedge clk);
    #1; // allow NBAs to settle before checking
  endtask

  // Case storage, M<=4 (matches cross_terms).
  logic [7:0]  A_case [0:3][0:3];
  logic [7:0]  W_case [0:3][0:3];
  logic [31:0] C_case [0:3][0:3];

  int m, j, s, m_drv;
  int case_M;
  int fd, scan_rc;
  string mode_str;
  int active_cyc;
  int stall_len;

  // ---- Freeze-check snapshot storage: the 44 probed registers (depth-0
  // wire paths -- unpu_skew's act_out[0], unpu_deskew's c_out[3] -- are
  // not registers and are excluded, per docs/planning/tasks/005-stall.md). ----
  logic [7:0]  prev_row1_q, prev_row2_q1, prev_row2_q2;
  logic [7:0]  prev_row3_q1, prev_row3_q2, prev_row3_q3;
  logic [31:0] prev_col2_q1, prev_col1_q1, prev_col1_q2;
  logic [31:0] prev_col0_q1, prev_col0_q2, prev_col0_q3;
  logic [7:0]  prev_pe_act  [0:3][0:3];
  logic [31:0] prev_pe_psum [0:3][0:3];
  int prev_active_cyc;

  task automatic capture_snapshot;
    begin
      prev_row1_q  = u_skew.row1_q;
      prev_row2_q1 = u_skew.row2_q1;
      prev_row2_q2 = u_skew.row2_q2;
      prev_row3_q1 = u_skew.row3_q1;
      prev_row3_q2 = u_skew.row3_q2;
      prev_row3_q3 = u_skew.row3_q3;

      prev_col2_q1 = u_deskew.col2_q1;
      prev_col1_q1 = u_deskew.col1_q1;
      prev_col1_q2 = u_deskew.col1_q2;
      prev_col0_q1 = u_deskew.col0_q1;
      prev_col0_q2 = u_deskew.col0_q2;
      prev_col0_q3 = u_deskew.col0_q3;

      // Grid: unrolled per-PE with literal indices (rather than a
      // variable-indexed loop into the g_row/g_col generate-block
      // instance array) -- same simulator-portability call made
      // elsewhere in this repo for hierarchical/array access.
      prev_pe_act[0][0] = u_grid.g_row[0].g_col[0].pe.act_out; prev_pe_psum[0][0] = u_grid.g_row[0].g_col[0].pe.psum_out;
      prev_pe_act[0][1] = u_grid.g_row[0].g_col[1].pe.act_out; prev_pe_psum[0][1] = u_grid.g_row[0].g_col[1].pe.psum_out;
      prev_pe_act[0][2] = u_grid.g_row[0].g_col[2].pe.act_out; prev_pe_psum[0][2] = u_grid.g_row[0].g_col[2].pe.psum_out;
      prev_pe_act[0][3] = u_grid.g_row[0].g_col[3].pe.act_out; prev_pe_psum[0][3] = u_grid.g_row[0].g_col[3].pe.psum_out;
      prev_pe_act[1][0] = u_grid.g_row[1].g_col[0].pe.act_out; prev_pe_psum[1][0] = u_grid.g_row[1].g_col[0].pe.psum_out;
      prev_pe_act[1][1] = u_grid.g_row[1].g_col[1].pe.act_out; prev_pe_psum[1][1] = u_grid.g_row[1].g_col[1].pe.psum_out;
      prev_pe_act[1][2] = u_grid.g_row[1].g_col[2].pe.act_out; prev_pe_psum[1][2] = u_grid.g_row[1].g_col[2].pe.psum_out;
      prev_pe_act[1][3] = u_grid.g_row[1].g_col[3].pe.act_out; prev_pe_psum[1][3] = u_grid.g_row[1].g_col[3].pe.psum_out;
      prev_pe_act[2][0] = u_grid.g_row[2].g_col[0].pe.act_out; prev_pe_psum[2][0] = u_grid.g_row[2].g_col[0].pe.psum_out;
      prev_pe_act[2][1] = u_grid.g_row[2].g_col[1].pe.act_out; prev_pe_psum[2][1] = u_grid.g_row[2].g_col[1].pe.psum_out;
      prev_pe_act[2][2] = u_grid.g_row[2].g_col[2].pe.act_out; prev_pe_psum[2][2] = u_grid.g_row[2].g_col[2].pe.psum_out;
      prev_pe_act[2][3] = u_grid.g_row[2].g_col[3].pe.act_out; prev_pe_psum[2][3] = u_grid.g_row[2].g_col[3].pe.psum_out;
      prev_pe_act[3][0] = u_grid.g_row[3].g_col[0].pe.act_out; prev_pe_psum[3][0] = u_grid.g_row[3].g_col[0].pe.psum_out;
      prev_pe_act[3][1] = u_grid.g_row[3].g_col[1].pe.act_out; prev_pe_psum[3][1] = u_grid.g_row[3].g_col[1].pe.psum_out;
      prev_pe_act[3][2] = u_grid.g_row[3].g_col[2].pe.act_out; prev_pe_psum[3][2] = u_grid.g_row[3].g_col[2].pe.psum_out;
      prev_pe_act[3][3] = u_grid.g_row[3].g_col[3].pe.act_out; prev_pe_psum[3][3] = u_grid.g_row[3].g_col[3].pe.psum_out;

      prev_active_cyc = active_cyc;
    end
  endtask

  task automatic check_frozen(input string ctx);
    begin
      if (u_skew.row1_q !== prev_row1_q) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row1_q changed (was %0h now %0h)", ctx, prev_row1_q, u_skew.row1_q); end else frozen_checks++;
      if (u_skew.row2_q1 !== prev_row2_q1) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row2_q1 changed", ctx); end else frozen_checks++;
      if (u_skew.row2_q2 !== prev_row2_q2) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row2_q2 changed", ctx); end else frozen_checks++;
      if (u_skew.row3_q1 !== prev_row3_q1) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row3_q1 changed", ctx); end else frozen_checks++;
      if (u_skew.row3_q2 !== prev_row3_q2) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row3_q2 changed", ctx); end else frozen_checks++;
      if (u_skew.row3_q3 !== prev_row3_q3) begin errors++; $display("FAIL FREEZE [%s]: u_skew.row3_q3 changed", ctx); end else frozen_checks++;

      if (u_deskew.col2_q1 !== prev_col2_q1) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col2_q1 changed", ctx); end else frozen_checks++;
      if (u_deskew.col1_q1 !== prev_col1_q1) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col1_q1 changed", ctx); end else frozen_checks++;
      if (u_deskew.col1_q2 !== prev_col1_q2) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col1_q2 changed", ctx); end else frozen_checks++;
      if (u_deskew.col0_q1 !== prev_col0_q1) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col0_q1 changed", ctx); end else frozen_checks++;
      if (u_deskew.col0_q2 !== prev_col0_q2) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col0_q2 changed", ctx); end else frozen_checks++;
      if (u_deskew.col0_q3 !== prev_col0_q3) begin errors++; $display("FAIL FREEZE [%s]: u_deskew.col0_q3 changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[0].g_col[0].pe.act_out !== prev_pe_act[0][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[0].pe.psum_out !== prev_pe_psum[0][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[1].pe.act_out !== prev_pe_act[0][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[1].pe.psum_out !== prev_pe_psum[0][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[2].pe.act_out !== prev_pe_act[0][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[2].pe.psum_out !== prev_pe_psum[0][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[3].pe.act_out !== prev_pe_act[0][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[0].g_col[3].pe.psum_out !== prev_pe_psum[0][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[0][3].psum_out changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[1].g_col[0].pe.act_out !== prev_pe_act[1][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[0].pe.psum_out !== prev_pe_psum[1][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[1].pe.act_out !== prev_pe_act[1][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[1].pe.psum_out !== prev_pe_psum[1][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[2].pe.act_out !== prev_pe_act[1][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[2].pe.psum_out !== prev_pe_psum[1][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[3].pe.act_out !== prev_pe_act[1][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[1].g_col[3].pe.psum_out !== prev_pe_psum[1][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[1][3].psum_out changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[2].g_col[0].pe.act_out !== prev_pe_act[2][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[0].pe.psum_out !== prev_pe_psum[2][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[1].pe.act_out !== prev_pe_act[2][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[1].pe.psum_out !== prev_pe_psum[2][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[2].pe.act_out !== prev_pe_act[2][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[2].pe.psum_out !== prev_pe_psum[2][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[3].pe.act_out !== prev_pe_act[2][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[2].g_col[3].pe.psum_out !== prev_pe_psum[2][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[2][3].psum_out changed", ctx); end else frozen_checks++;

      if (u_grid.g_row[3].g_col[0].pe.act_out !== prev_pe_act[3][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][0].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[0].pe.psum_out !== prev_pe_psum[3][0]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][0].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[1].pe.act_out !== prev_pe_act[3][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][1].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[1].pe.psum_out !== prev_pe_psum[3][1]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][1].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[2].pe.act_out !== prev_pe_act[3][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][2].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[2].pe.psum_out !== prev_pe_psum[3][2]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][2].psum_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[3].pe.act_out !== prev_pe_act[3][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][3].act_out changed", ctx); end else frozen_checks++;
      if (u_grid.g_row[3].g_col[3].pe.psum_out !== prev_pe_psum[3][3]) begin errors++; $display("FAIL FREEZE [%s]: pe[3][3].psum_out changed", ctx); end else frozen_checks++;

      if (active_cyc !== prev_active_cyc) begin
        errors++;
        $display("FAIL FREEZE [%s]: active_cyc advanced during stall (was %0d now %0d)", ctx, prev_active_cyc, active_cyc);
      end else begin
        frozen_checks++;
      end
    end
  endtask

  // Task 013 Part D: reads just the M= line of a case's _meta.txt,
  // without disturbing run_case()'s own case_M/mode_str/fd/scan_rc
  // state -- used to size each crv_* case's early/mid/late trigger
  // points before calling run_case() for it.
  task automatic peek_case_m(input string name, output int m_out);
    string ppath;
    int pfd, prc;
    string pmode;
    begin
      ppath = {"model/vectors/", name, "_meta.txt"};
      pfd = $fopen(ppath, "r");
      if (pfd == 0)
        $fatal(1, "could not open %s -- run model/golden first", ppath);
      prc = $fscanf(pfd, "M=%d\nMODE=%s\n", m_out, pmode);
      $fclose(pfd);
      if (prc != 2)
        $fatal(1, "could not parse %s (got %0d fields)", ppath, prc);
    end
  endtask

  // ==== Task 022: independent reference model + generalized multi-
  // freeze pass runner, extending this file's existing distinctive job
  // (bit-exact verification of all 44 internal registers through a
  // freeze) into freeze *combinations* task 005/013 and task 021 never
  // tried -- multiple freezes per pass, extreme durations, freezes
  // landing exactly on data-validity boundaries, zero-gap back-to-back
  // freezes, and varying freeze density across many back-to-back passes.
  //
  // ref_c_elem carries no persistent state between calls -- every call
  // recomputes its one C[m][j] from scratch off A_case/W_case snapshots,
  // same stateless discipline tasks 020/021 used, which structurally
  // rules out the class of bug task 019's first-draft PE reference model
  // had (accumulating from its own prior state instead of each cycle's
  // driven input). Used uniformly for both Part A's cross_terms-derived
  // cases and Part B's synthetic per-pass data, rather than switching
  // between this and cross_terms_c.hex, for the same independent-
  // derivation reason tasks 020/021 used it exclusively on this chain. ====
  function automatic int signed to_signed8(input logic [7:0] v);
    if (v[7])
      return int'(v) - 256;
    else
      return int'(v);
  endfunction

  function automatic logic [31:0] ref_c_elem(input logic [7:0] Wm [0:3][0:3], input logic [7:0] Am [0:3][0:3],
                                              input int mrow, input int jcol, input bit mode_uns);
    int kk;
    int unsigned acc_u, uw, ua;
    int signed   acc_s, sw, sa;
    begin
      if (mode_uns) begin
        acc_u = 0;
        for (kk = 0; kk < 4; kk = kk + 1) begin
          uw = {24'd0, Wm[kk][jcol]};
          ua = {24'd0, Am[mrow][kk]};
          acc_u = acc_u + uw * ua;
        end
        ref_c_elem = acc_u;
      end else begin
        acc_s = 0;
        for (kk = 0; kk < 4; kk = kk + 1) begin
          sw = to_signed8(Wm[kk][jcol]);
          sa = to_signed8(Am[mrow][kk]);
          acc_s = acc_s + sw * sa;
        end
        ref_c_elem = acc_s;
      end
    end
  endfunction

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

  // Advances g_rng one xorshift32 step and returns it modulo n. Every
  // `base + draw_mod(n)` stall/freeze length in this file goes through here.
  function automatic int unsigned draw_mod(input int unsigned n);
    begin
      g_rng = xorshift32(g_rng);
      draw_mod = g_rng % n;
    end
  endfunction

  // ~1/8 chance of a boundary extreme, same discipline tasks 019-021
  // used, biased toward the values most likely to expose a wiring/width
  // bug instead of trusting uniform random to find them by chance.
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

  task automatic reset_dut;
    begin
      rst_n        = 0;
      array_en     = 0;
      weight_load  = '0;
      weight_in    = '0;
      a_raw        = '0;
      grid_psum_in = '0;
      step();
      step();
      rst_n = 1;
      step();
    end
  endtask

  localparam int MAX_FREEZES = 8;

  // Preloads weights from the module-level W_case, then runs one full
  // pass over the module-level A_case/case_M/mode_unsigned, injecting up
  // to MAX_FREEZES independent freeze windows (freeze_starts[]/
  // freeze_lens[], only the first num_freezes entries used) -- every
  // held cycle of every one of them checked bit-exact across all 44
  // internal registers via capture_snapshot()/check_frozen() (task 005's
  // own machinery, reused unmodified). Does NOT reset the DUT -- callers
  // running a single isolated pass call reset_dut() first; Part B's
  // back-to-back sequences reset once per sequence and call this
  // repeatedly with no reset and no idle gap between passes, case_M
  // allowed to differ pass to pass.
  //
  // freeze_starts must be strictly increasing: a freeze holds active_cyc
  // still for its whole duration, so the very next active edge after one
  // freeze resumes is enough of a gap for the next freeze's start
  // condition to fire immediately after -- true zero-gap back-to-back
  // freezes fall out of consecutive integers (e.g. 2,3,4,5), not a
  // special case this task needs to know about.
  task automatic run_pass_freezes(input string label, input int num_freezes,
                                   input int freeze_starts [0:MAX_FREEZES-1],
                                   input int freeze_lens   [0:MAX_FREEZES-1],
                                   output int errs_this_pass);
    int active_cyc, active_cyc_max, fi;
    logic [31:0] exp_val;
    begin
      errs_this_pass = 0;

      // ---- Preload weights (unrolled, same convention as run_case()). ----
      array_en = 1;
      weight_in[0][0] = W_case[0][0]; weight_in[0][1] = W_case[0][1]; weight_in[0][2] = W_case[0][2]; weight_in[0][3] = W_case[0][3];
      weight_in[1][0] = W_case[1][0]; weight_in[1][1] = W_case[1][1]; weight_in[1][2] = W_case[1][2]; weight_in[1][3] = W_case[1][3];
      weight_in[2][0] = W_case[2][0]; weight_in[2][1] = W_case[2][1]; weight_in[2][2] = W_case[2][2]; weight_in[2][3] = W_case[2][3];
      weight_in[3][0] = W_case[3][0]; weight_in[3][1] = W_case[3][1]; weight_in[3][2] = W_case[3][2]; weight_in[3][3] = W_case[3][3];
      weight_load = '1;
      a_raw = '0;
      step();
      weight_load = '0;

      active_cyc     = 0;
      active_cyc_max = (case_M - 1) + 7 + 2; // margin past last readout, same as run_case()
      fi = 0;

      while (active_cyc <= active_cyc_max) begin
        m_drv = (active_cyc < case_M) ? active_cyc : (case_M - 1);
        a_raw[0] = A_case[m_drv][0];
        a_raw[1] = A_case[m_drv][1];
        a_raw[2] = A_case[m_drv][2];
        a_raw[3] = A_case[m_drv][3];

        if (fi < num_freezes && active_cyc == freeze_starts[fi]) begin
          for (s = 0; s < freeze_lens[fi]; s = s + 1) begin
            capture_snapshot();
            array_en = 0;
            a_raw    = {4{8'hA5}}; // don't-care garbage; DUT must ignore it while frozen
            step();   // frozen edge -- active_cyc does NOT advance
            check_frozen($sformatf("%s freeze#%0d cyc %0d/%0d @active_cyc=%0d", label, fi, s + 1, freeze_lens[fi], active_cyc));
          end
          array_en = 1;
          a_raw[0] = A_case[m_drv][0];
          a_raw[1] = A_case[m_drv][1];
          a_raw[2] = A_case[m_drv][2];
          a_raw[3] = A_case[m_drv][3];
          fi = fi + 1;
        end

        array_en = 1;
        step(); // active edge
        active_cyc = active_cyc + 1;

        m = active_cyc - 7;
        if (m >= 0 && m < case_M) begin
          for (j = 0; j < 4; j = j + 1) begin
            exp_val = ref_c_elem(W_case, A_case, m, j, mode_unsigned);
            checks  = checks + 1;
            if (c_out[j] !== exp_val) begin
              errs_this_pass = errs_this_pass + 1;
              errors = errors + 1;
              $display("FAIL [%s]: active_cyc=%0d c_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        label, active_cyc, j, m, j, exp_val, c_out[j]);
            end
          end
        end
      end
    end
  endtask

  // Runs one full pass of 'name' (reset -> preload -> compute), optionally
  // inserting one randomised stall of 1-5 cycles at active_cyc ==
  // trigger_active_cyc. Checks c_out against C_case[m][*] at
  // active_cyc == m+7 regardless (contract line 4, substituting
  // active_cyc for wall-clock cycle per the bookkeeping rule above).
  task automatic run_case(input string name, input string run_label,
                           input bit do_stall, input int trigger_active_cyc);
    string path;
    int active_cyc_max;
    begin
      path = {"model/vectors/", name, "_meta.txt"};
      fd = $fopen(path, "r");
      if (fd == 0)
        $fatal(1, "could not open %s -- run model/golden first", path);
      scan_rc = $fscanf(fd, "M=%d\nMODE=%s\n", case_M, mode_str);
      $fclose(fd);
      if (scan_rc != 2)
        $fatal(1, "could not parse %s (got %0d fields)", path, scan_rc);
      if (case_M > 4)
        $fatal(1, "case '%s' has M=%0d, this tb only handles M<=4", name, case_M);

      mode_unsigned = (mode_str == "UNSIGNED") ? 1'b1 : 1'b0;

      $readmemh({"model/vectors/", name, "_a.hex"}, A_case);
      $readmemh({"model/vectors/", name, "_w.hex"}, W_case);
      $readmemh({"model/vectors/", name, "_c.hex"}, C_case);

      $display("==== run '%s' (%s)%s ====", name, run_label,
                do_stall ? $sformatf(" stall trigger active_cyc=%0d", trigger_active_cyc) : "");

      // ---- Reset ----
      rst_n        = 0;
      array_en     = 0;
      weight_load  = '0;
      weight_in    = '0;
      a_raw        = '0;
      grid_psum_in = '0;
      step();
      step();
      rst_n = 1;
      step();

      // ---- Preload weights, direct per-PE forcing (unrolled, same
      // convention as tb/unpu_skew_tb.sv). ----
      array_en = 1;
      weight_in[0][0] = W_case[0][0]; weight_in[0][1] = W_case[0][1]; weight_in[0][2] = W_case[0][2]; weight_in[0][3] = W_case[0][3];
      weight_in[1][0] = W_case[1][0]; weight_in[1][1] = W_case[1][1]; weight_in[1][2] = W_case[1][2]; weight_in[1][3] = W_case[1][3];
      weight_in[2][0] = W_case[2][0]; weight_in[2][1] = W_case[2][1]; weight_in[2][2] = W_case[2][2]; weight_in[2][3] = W_case[2][3];
      weight_in[3][0] = W_case[3][0]; weight_in[3][1] = W_case[3][1]; weight_in[3][2] = W_case[3][2]; weight_in[3][3] = W_case[3][3];
      weight_load = '1; // pulse all 16 PEs simultaneously
      a_raw = '0;
      step();
      weight_load = '0;

      // ---- Compute pass, indexed by active_cyc (see header comment). ----
      active_cyc = 0;
      active_cyc_max = (case_M - 1) + 7 + 2; // margin past last readout

      while (active_cyc <= active_cyc_max) begin
        // Present A[m] while active_cyc == m; hold the last row once
        // active_cyc >= case_M.
        m_drv = (active_cyc < case_M) ? active_cyc : (case_M - 1);
        a_raw[0] = A_case[m_drv][0];
        a_raw[1] = A_case[m_drv][1];
        a_raw[2] = A_case[m_drv][2];
        a_raw[3] = A_case[m_drv][3];

        if (do_stall && active_cyc == trigger_active_cyc) begin
          stall_len = 1 + (draw_mod(5)); // 1-5 cycles
          $display("  stalling %0d cycle(s) at active_cyc=%0d (run=%s)",
                    stall_len, active_cyc, run_label);
          for (s = 0; s < stall_len; s = s + 1) begin
            capture_snapshot();
            array_en = 0;
            a_raw    = {4{8'hA5}}; // don't-care garbage; DUT must ignore it
            step();
            check_frozen($sformatf("%s stall cyc %0d/%0d", run_label, s + 1, stall_len));
          end
          array_en = 1;
          // Restore the scheduled a_raw before resuming the real edge below.
          a_raw[0] = A_case[m_drv][0];
          a_raw[1] = A_case[m_drv][1];
          a_raw[2] = A_case[m_drv][2];
          a_raw[3] = A_case[m_drv][3];
        end

        array_en = 1;
        step(); // active edge -- array_en was 1, so active_cyc advances
        active_cyc = active_cyc + 1;

        m = active_cyc - 7;
        if (m >= 0 && m < case_M) begin
          for (j = 0; j < 4; j = j + 1) begin
            checks = checks + 1;
            if (c_out[j] !== C_case[m][j]) begin
              errors = errors + 1;
              $display("FAIL [%s/%s]: active_cyc=%0d c_out[%0d] (C[%0d][%0d]) exp=%0d got=%0d",
                        name, run_label, active_cyc, j, m, j, C_case[m][j], c_out[j]);
            end else begin
              $display("PASS [%s/%s]: active_cyc=%0d c_out[%0d] (C[%0d][%0d]) = %0d",
                        name, run_label, active_cyc, j, m, j, c_out[j]);
            end
          end
        end
      end
    end
  endtask

  initial begin
    errors        = 0;
    checks        = 0;
    frozen_checks = 0;
    g_rng         = 32'h5EED_0005;
    $display("stall RNG seed = 32'h%08h", g_rng);

    // Baseline: no stall, re-confirms task 004's result and this tb's own
    // active_cyc bookkeeping before it's trusted for the stalled runs.
    run_case("cross_terms", "baseline", 1'b0, 0);

    // (a) Early: skew bank still filling (before active_cyc reaches 7).
    run_case("cross_terms", "early", 1'b1, 1);

    // (b) Mid: all four rows driven (m=3 enters at active_cyc==3) but none
    // has exited yet (earliest exit is active_cyc==7) -- multiple rows in
    // flight through the grid simultaneously.
    run_case("cross_terms", "mid", 1'b1, 5);

    // (c) Late: de-skew bank draining -- m=0's result is already out
    // (active_cyc==7) but m=3's (active_cyc==10) is not yet.
    run_case("cross_terms", "late", 1'b1, 8);

    // ==== Task 013 Part D: verification-debt retrofit -- the same
    // baseline+early/mid/late pattern above, across all 64 crv_* cases
    // (all 64 run, not just the required >=16: this file's simulation
    // time is milliseconds per earlier tasks' runs, so there's no
    // runtime reason to stop short of full coverage). Trigger points are
    // clamped to each case's own active_cyc_max so they stay valid for
    // M<4 cases -- see the file header note. g_rng keeps accumulating
    // from the cross_terms runs above (same single seeded stream for the
    // whole file, printed once at the top), so stall_len draws inside
    // run_case() remain reproducible from that one seed. ====
    begin : crv_stall_sweep
      int ci, this_m, this_max, trig_early, trig_mid, trig_late;
      string crv_name;

      for (ci = 0; ci < 64; ci = ci + 1) begin
        crv_name = $sformatf("crv_%04d", ci);
        peek_case_m(crv_name, this_m);
        this_max = (this_m - 1) + 7 + 2; // matches run_case()'s own active_cyc_max formula

        trig_early = (1 > this_max) ? this_max : 1;
        trig_mid   = (5 > this_max) ? this_max : 5;
        trig_late  = (8 > this_max) ? this_max : 8;

        run_case(crv_name, "baseline", 1'b0, 0);
        run_case(crv_name, "early",    1'b1, trig_early);
        run_case(crv_name, "mid",      1'b1, trig_mid);
        run_case(crv_name, "late",     1'b1, trig_late);
      end
      $display("stall CRV: ran baseline+early/mid/late across all 64 crv_* cases");
    end

    $display("----------------------------------------");
    $display("checked %0d C-value(s), %0d frozen-register check(s) total", checks, frozen_checks);
    if (errors == 0)
      $display("ALL CHECKS PASSED");
    else
      $display("%0d FAILURE(S) (checks=%0d)", errors, checks);
    $display("----------------------------------------");

    // ==== Task 022, Part A: extreme freeze-combination directed cases.
    // Not re-proving task 005/013's baseline (one randomized 1-5-cycle
    // freeze per run) or task 021's exhaustive-position/single-freeze
    // coverage -- these specifically target freeze *combinations*
    // neither tried, still through this file's own 44-register bit-exact
    // lens via run_pass_freezes()/check_frozen(), reused unmodified. ====
    begin : part_a
      int errs;
      int meta_M;
      string meta_mode;
      int mfd, mrc;
      int fstarts [0:MAX_FREEZES-1];
      int flens   [0:MAX_FREEZES-1];
      int bidx;

      mfd = $fopen("model/vectors/cross_terms_meta.txt", "r");
      if (mfd == 0)
        $fatal(1, "could not open model/vectors/cross_terms_meta.txt -- run model/golden first");
      mrc = $fscanf(mfd, "M=%d\nMODE=%s\n", meta_M, meta_mode);
      $fclose(mfd);
      if (mrc != 2)
        $fatal(1, "could not parse model/vectors/cross_terms_meta.txt (got %0d fields)", mrc);

      $readmemh("model/vectors/cross_terms_a.hex", A_case);
      $readmemh("model/vectors/cross_terms_w.hex", W_case);
      case_M        = meta_M;
      mode_unsigned = (meta_mode == "UNSIGNED") ? 1'b1 : 1'b0;

      // ---- A1: multiple freezes in one pass -- three separate freezes
      // at active_cyc 1, 4, and 8, each an independent random 1-10-cycle
      // duration, all 44 registers checked bit-exact through each. ----
      reset_dut();
      fstarts[0] = 1; flens[0] = 1 + (draw_mod(10));
      fstarts[1] = 4; flens[1] = 1 + (draw_mod(10));
      fstarts[2] = 8; flens[2] = 1 + (draw_mod(10));
      $display("---- Part A1: 3 freezes in one pass @active_cyc 1/4/8, durations %0d/%0d/%0d ----", flens[0], flens[1], flens[2]);
      run_pass_freezes("multi-freeze", 3, fstarts, flens, errs);

      // ---- A2: extreme-duration freeze -- 50-100 cycles, well past the
      // 1-5-cycle range used so far, every one of the 44 registers
      // checked bit-exact on every cycle of the hold (not spot-checked),
      // since check_frozen() runs inside the freeze loop every cycle. ----
      reset_dut();
      fstarts[0] = 5; flens[0] = 50 + (draw_mod(51));
      $display("---- Part A2: extreme-duration freeze (%0d cycles) @active_cyc=5 ----", flens[0]);
      run_pass_freezes("extreme-duration", 1, fstarts, flens, errs);

      // ---- A3: freeze exactly on a data-validity boundary -- the two
      // highest-risk moments for an off-by-one in what array_en gates:
      // active_cyc==7 (first C row would normally become valid) and
      // active_cyc==(M-1)+7 (last row's validity cycle). ----
      reset_dut();
      fstarts[0] = 7; flens[0] = 1 + (draw_mod(5));
      $display("---- Part A3a: freeze exactly at active_cyc==7 (first row's validity cycle), duration=%0d ----", flens[0]);
      run_pass_freezes("boundary-freeze-at-7", 1, fstarts, flens, errs);

      reset_dut();
      fstarts[0] = (case_M - 1) + 7; flens[0] = 1 + (draw_mod(5));
      $display("---- Part A3b: freeze exactly at active_cyc==(M-1)+7=%0d (last row's validity cycle), duration=%0d ----", fstarts[0], flens[0]);
      run_pass_freezes("boundary-freeze-at-M-1+7", 1, fstarts, flens, errs);

      // ---- A4: back-to-back freezes with zero gap -- freeze, resume
      // for exactly one cycle, freeze again immediately, repeated 4
      // times (active_cyc 2,3,4,5: consecutive integers, per
      // run_pass_freezes()'s own header note on what "zero gap" reduces
      // to). ----
      reset_dut();
      for (bidx = 0; bidx < 4; bidx = bidx + 1) begin
        fstarts[bidx] = 2 + bidx;
        flens[bidx]   = 2 + (draw_mod(4));
      end
      $display("---- Part A4: 4x zero-gap back-to-back freezes @active_cyc 2/3/4/5, durations %0d/%0d/%0d/%0d ----",
                flens[0], flens[1], flens[2], flens[3]);
      run_pass_freezes("zero-gap-back-to-back", 4, fstarts, flens, errs);

      $display("----------------------------------------");
      if (errors == 0)
        $display("Part A (multi-freeze, extreme-duration, both validity-boundary freezes, zero-gap back-to-back): ALL PASSED, checks=%0d frozen_checks=%0d so far", checks, frozen_checks);
      else
        $display("Part A: %0d FAILURE(S) SO FAR (checks=%0d frozen_checks=%0d)", errors, checks, frozen_checks);
      $display("----------------------------------------");
    end

    // ==== Task 022, Part B: long multi-pass sequences with varying
    // freeze density. The specific thing this pushes hard: does the
    // single global array_en correctly gate every one of the 44
    // registers, every time, under adversarial freeze density (0-4
    // freezes per pass, randomly placed and durationed), across hundreds
    // of back-to-back passes with no reset and no idle gap, without ever
    // once drifting. ====
    begin : part_b
      localparam int NUM_SEQ = 20;

      logic [31:0] master_rng, rng, seq_seed;
      int seq_idx, pass_idx, num_passes, total_passes;
      int mm, kk, jj, this_M;
      int window_max, freeze_count, prev_start, candidate, fi;
      int b_starts [0:MAX_FREEZES-1];
      int b_lens   [0:MAX_FREEZES-1];
      int errs;
      int checks_before_partb, frozen_before_partb;

      master_rng = 32'h5eed0016; // per-task seed convention (0x5eed0000 + task number, hex)
      $display("Stall Part B multi-pass master seed = 32'h%08h", master_rng);
      total_passes         = 0;
      checks_before_partb  = checks;
      frozen_before_partb  = frozen_checks;

      for (seq_idx = 0; seq_idx < NUM_SEQ; seq_idx = seq_idx + 1) begin
        master_rng = xorshift32(master_rng);
        seq_seed   = master_rng;
        rng        = seq_seed;
        $display("Stall Part B sequence %0d: seed = 32'h%08h", seq_idx, seq_seed);

        rng = xorshift32(rng);
        num_passes = 10 + (rng % 11); // 10..20 passes per sequence

        reset_dut(); // ONE reset for the whole sequence -- every pass after the first gets no reset and no idle gap

        for (pass_idx = 0; pass_idx < num_passes; pass_idx = pass_idx + 1) begin
          rng = xorshift32(rng);
          this_M = 1 + (rng % 4);
          case_M = this_M;

          rng = xorshift32(rng);
          mode_unsigned = rng[0];

          for (mm = 0; mm < 4; mm = mm + 1)
            for (kk = 0; kk < 4; kk = kk + 1)
              A_case[mm][kk] = biased_byte(rng);
          for (kk = 0; kk < 4; kk = kk + 1)
            for (jj = 0; jj < 4; jj = jj + 1)
              W_case[kk][jj] = biased_byte(rng);

          // ---- Random freeze density (0-4), independently placed
          // (strictly increasing within this pass's own active window)
          // and durationed (1-20 cycles). ----
          window_max = (case_M - 1) + 7;
          rng = xorshift32(rng);
          freeze_count = rng % 5; // 0..4
          prev_start = -1;
          for (fi = 0; fi < freeze_count; fi = fi + 1) begin
            if (prev_start + 1 > window_max) begin
              freeze_count = fi; // window too small to fit another -- shrink rather than duplicate a start
              break;
            end
            rng = xorshift32(rng);
            candidate = prev_start + 1 + (rng % (window_max - prev_start));
            b_starts[fi] = candidate;
            prev_start   = candidate;
            rng = xorshift32(rng);
            b_lens[fi] = 1 + (rng % 20);
          end

          run_pass_freezes($sformatf("seq%0d/pass%0d(M=%0d,freezes=%0d)", seq_idx, pass_idx, this_M, freeze_count),
                            freeze_count, b_starts, b_lens, errs);
          total_passes = total_passes + 1;
        end
      end

      $display("----------------------------------------");
      $display("Part B: %0d sequences, %0d total passes (>=200 required), %0d C-value check(s) + %0d register-check(s) this part, %0d failures",
                NUM_SEQ, total_passes, (checks - checks_before_partb), (frozen_checks - frozen_before_partb), errors);
      if (errors == 0)
        $display("Part B: ALL PASSED");
      $display("----------------------------------------");
    end

    $display("----------------------------------------");
    if (errors == 0)
      $display("ALL TASK 005/013 + TASK 022 STALL CHECKS PASSED (baseline+early/mid/late + 64 crv_* cases + Part A freeze-combination cases + Part B adversarial multi-pass sequences), checks=%0d frozen_checks=%0d",
                checks, frozen_checks);
    else
      $display("%0d TOTAL FAILURE(S) ACROSS ALL STALL CHECKS (checks=%0d frozen_checks=%0d)", errors, checks, frozen_checks);
    $display("----------------------------------------");

    $finish;
  end

endmodule
