// Main sequencer FSM for the uNPU 4x4 systolic array. Drives one full
// weight-load -> input-load -> compute -> readback -> writeback pass over
// the (already verified) skew -> grid -> de-skew datapath, for any legal
// M/N/K each 1-4 (handoff §6, §12: M/N/K each <=4, no tiling needed).
//
// Control-only: does NOT instantiate unpu_skew/unpu_grid/unpu_deskew
// itself -- that is unpu_top's job (step 14). This module's testbench
// wires it to those three directly.
//
// Nine states, one beyond the PM's own 7-state sketch
// (docs/pm/sequencer-fsm.txt): LATCH_CFG and ERROR are additive, per the
// user's resolution #1 in docs/planning/tasks/006-sequencer.md -- neither
// touches any interface, and error/error_code exist so a later task
// (step 12+) can wire them into npu_status.
//
// COMPUTE-length derivation (task 006, correcting the PM's own sketch):
// the PM's sketch says COMPUTE "stops after M+K+N-2 cycles." That formula
// only agrees with the timing contract's M+7 when K+N==8, i.e. only at the
// full 4x4 case -- it silently under-counts (stops too early, dropping
// rows) for every K<4 or N<4 shape this module must handle. The skew bank
// depths (0/1/2/3 by physical row) and de-skew bank depths (3/2/1/0 by
// physical column) are fixed at hardware-build time, not parameterized by
// runtime K/N (handoff §6: "no change to the timing contract or
// skew/de-skew depths" for sub-4 K/N) -- so the true pipeline latency from
// presenting row m of A to C[m][*] becoming valid at de-skew is always
// m+7 (CLAUDE.md), independent of K and N. COMPUTE below uses a single
// registered cycle counter for both the injection mux and the exit check
// (the "one-cycle-early trap" the task calls out) so this holds by
// construction, not by coincidence.
//
// Output architecture: array_en/weight_load/busy/done/error/mode_unsigned_o
// are pure Moore outputs, combinational functions of the registered `state`
// (plus the shadow-latched config/error_code registers) -- NOT re-registered
// in the same always_ff that advances `state`. Re-registering them would
// read the OLD `state` on the same edge that `state` itself updates, so
// e.g. weight_load would visibly pulse one cycle after array_en=1 first
// shows on `state`, not on the same cycle -- silently violating the
// LOAD_WEIGHTS known trap ("assert array_en=1 on the exact cycle
// weight_load pulses, not before or after") and delaying `done` by a
// cycle relative to the state that's supposed to produce it. Tying them
// combinationally to `state` makes them change atomically with it instead.
//
// Simulated with Verilator (--binary --timing) -- iverilog is not
// installed in this environment (no root to apt-get install it); prior
// module headers in this repo claim Icarus, which is stale/inaccurate for
// this environment as of this task. Flagged to Planning separately;
// nothing in this file depends on simulator choice (synthesisable subset
// throughout, per CLAUDE.md).
module unpu_seq (
  input  logic                  clk,
  input  logic                  rst_n,          // async, active-low (matches every other module in this array)

  input  logic                  start,          // 1-cycle pulse; sampled only while FSM is in IDLE or ERROR, ignored otherwise
  input  logic [2:0]            dim_m,          // legal range 1-4
  input  logic [2:0]            dim_n,          // legal range 1-4
  input  logic [2:0]            dim_k,          // legal range 1-4
  input  logic                  mode_unsigned,  // latched alongside dims in LATCH_CFG

  // Direct-forced source matrices. unpu_wbuf/unpu_actbuf (step 9) and
  // unpu_dma (step 10) don't exist yet, so this task presents the full
  // matrix up front -- same "direct forcing" pattern tasks 003-005 used
  // for weights. Caller (the testbench, for this task) must zero-pad
  // a_src/w_src outside the true dim_m x dim_k / dim_k x dim_n submatrix --
  // unpu_seq always loads/presents the full 4x4 and trusts that padding.
  input  logic [3:0][3:0][7:0]  a_src,          // a_src[m][k]
  input  logic [3:0][3:0][7:0]  w_src,          // w_src[k][j]

  output logic [3:0][3:0][31:0] c_dst,          // c_dst[m][j]; rows captured as they become valid, fully valid at done
  output logic                  done,           // 1-cycle pulse
  output logic                  busy,           // 1 whenever FSM is not IDLE and not ERROR
  output logic                  error,          // latched; cleared only by the next start
  output logic [2:0]            error_code,     // meaningful only while error=1; 3'd1 = illegal dim_m/dim_n/dim_k, others reserved

  // Datapath control -- wire directly to unpu_skew / unpu_grid /
  // unpu_deskew in the testbench.
  output logic                  array_en,           // -> unpu_skew.array_en, unpu_grid.array_en, unpu_deskew.array_en
  output logic                  mode_unsigned_o,    // -> unpu_grid.mode_unsigned (latched copy, not the raw input)
  output logic [3:0][3:0]       weight_load,        // -> unpu_grid.weight_load
  output logic [3:0][3:0][7:0]  weight_in,          // -> unpu_grid.weight_in
  output logic [3:0][7:0]       a_raw,              // -> unpu_skew.a_raw
  input  logic [3:0][31:0]      c_in                // <- unpu_deskew.c_out, fed back for capture
);

  typedef enum logic [3:0] {
    IDLE,
    LATCH_CFG,
    LOAD_WEIGHTS,
    LOAD_INPUT,
    COMPUTE,
    READ_OUTPUT,
    WRITE_OUTPUT,
    DONE,
    ERROR
  } seq_state_e;

  seq_state_e state, state_n;

  // Shadow-latched config: a caller changing dim_*/mode_unsigned mid-run
  // cannot corrupt an in-flight op (notebook §7.1's config-legality/
  // shadow-copy rationale). k_lat/n_lat are latched per the FSM spec but
  // have no reader within this module yet -- unpu_seq validates dim_k/
  // dim_n and trusts the caller's a_src/w_src zero-padding, it doesn't
  // need K/N itself for anything in this task's scope. They exist for a
  // later consumer (e.g. npu_status/readback, step 12+), not dead code.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [2:0] m_lat, k_lat, n_lat;
  /* verilator lint_on UNUSEDSIGNAL */
  logic       mode_lat;

  // Single registered cycle counter, shared by the injection mux (a_raw)
  // and the COMPUTE-exit check (state_n) -- the one-cycle-early trap
  // requirement: both must read this exact same register. 4 bits, not 3:
  // the exit value is m_lat+6, which reaches 10 at m_lat==4 and would
  // silently wrap in a 3-bit counter (max 7).
  logic [3:0] cycle;

  logic dim_illegal;
  assign dim_illegal = (dim_m == 3'd0) || (dim_m > 3'd4) ||
                        (dim_n == 3'd0) || (dim_n > 3'd4) ||
                        (dim_k == 3'd0) || (dim_k > 3'd4);

  // ---- State register ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= IDLE;
    else
      state <= state_n;
  end

  // ---- Next-state logic ----
  always_comb begin
    state_n = state;
    case (state)
      IDLE:         if (start) state_n = LATCH_CFG;
      LATCH_CFG:    state_n = dim_illegal ? ERROR : LOAD_WEIGHTS;
      LOAD_WEIGHTS: state_n = LOAD_INPUT;
      LOAD_INPUT:   state_n = COMPUTE;
      COMPUTE:      if (cycle == m_lat + 4'd6) state_n = READ_OUTPUT;
      READ_OUTPUT:  state_n = WRITE_OUTPUT;
      WRITE_OUTPUT: state_n = DONE;
      DONE:         state_n = IDLE;
      ERROR:        if (start) state_n = LATCH_CFG;
      default:      state_n = IDLE;
    endcase
  end

  // ---- Moore outputs: pure combinational functions of `state` (see
  // header comment for why these are not re-registered). ----
  always_comb begin
    array_en    = 1'b0;
    weight_load = '0;
    busy        = 1'b0;
    done        = 1'b0;
    error       = 1'b0;
    case (state)
      LOAD_WEIGHTS: begin
        array_en    = 1'b1;
        weight_load = '1; // pulse all 16 PEs simultaneously; array_en=1 same cycle (known trap)
        busy        = 1'b1;
      end
      LOAD_INPUT: begin
        array_en = 1'b1;
        busy     = 1'b1;
      end
      COMPUTE: begin
        array_en = 1'b1;
        busy     = 1'b1;
      end
      READ_OUTPUT: begin
        array_en = 1'b1;
        busy     = 1'b1;
      end
      WRITE_OUTPUT: begin
        array_en = 1'b1;
        busy     = 1'b1;
      end
      DONE: begin
        busy = 1'b1; // "busy: 1 whenever FSM is not IDLE and not ERROR" -- DONE qualifies
        done = 1'b1; // exactly this one cycle; state auto-advances to IDLE next
      end
      ERROR: begin
        error = 1'b1; // holds while parked here; drops the instant `start` moves state_n to LATCH_CFG
      end
      LATCH_CFG: begin
        busy = 1'b1; // config-check only, doesn't need the datapath live
      end
      default: ; // IDLE
    endcase
  end

  assign mode_unsigned_o = mode_lat;
  assign weight_in       = w_src; // direct-forced every cycle; unpu_pe only latches when weight_load & array_en both 1
  assign a_raw           = (state == COMPUTE && cycle < {1'b0, m_lat}) ? a_src[cycle] : '0;

  // ---- Shadow-latched config + error_code: registered, updated only on
  // the LATCH_CFG cycle. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_lat      <= 3'd0;
      k_lat      <= 3'd0;
      n_lat      <= 3'd0;
      mode_lat   <= 1'b0;
      error_code <= 3'd0;
    end else if (state == LATCH_CFG) begin
      if (dim_illegal) begin
        error_code <= 3'd1;
      end else begin
        m_lat    <= dim_m;
        k_lat    <= dim_k;
        n_lat    <= dim_n;
        mode_lat <= mode_unsigned;
      end
    end
  end

  // ---- COMPUTE cycle counter: single register, shared by a_raw's mux
  // above and the exit check in state_n above. Forced to 0 throughout
  // LOAD_INPUT so it reads 0 the instant COMPUTE begins (no extra-cycle
  // lag from a one-shot "reset on transition" pulse). ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cycle <= 4'd0;
    else if (state == LOAD_INPUT)
      cycle <= 4'd0;
    else if (state == COMPUTE && cycle != m_lat + 4'd6)
      cycle <= cycle + 4'd1;
  end

  // ---- Output capture: c_dst[cycle-7] <= c_in whenever cycle>=7, i.e.
  // once per COMPUTE cycle from cycle==7 (row 0's result) through
  // cycle==m_lat+6 (row m_lat-1's result, the same cycle COMPUTE exits). ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      c_dst <= '0;
    else if (state == COMPUTE && cycle >= 4'd7)
      c_dst[cycle - 4'd7] <= c_in;
  end

endmodule
