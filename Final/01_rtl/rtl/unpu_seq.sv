// Main sequencer FSM for the uNPU 4x4 systolic array. Task 011 revision:
// orchestrates the REAL unpu_dma/unpu_wbuf/unpu_actbuf (tasks 007-008)
// instead of task 006's direct-forced a_src/w_src stand-in. Weight/
// activation data now flows unpu_dma -> unpu_wbuf/unpu_actbuf ->
// unpu_grid/unpu_skew directly; this module only sequences that flow
// (job dispatch + swap timing) and reads the result stream (rd_row
// selects which activation row is being presented; c_in is still the
// captured output stream, unchanged in spirit from task 006).
//
// Still control-only: does NOT instantiate unpu_dma/unpu_wbuf/
// unpu_actbuf/unpu_skew/unpu_grid/unpu_deskew itself -- that is
// unpu_top's job (step 14/task 012). This module's testbench wires it to
// the real modules directly.
//
// Eleven states: IDLE, LATCH_CFG, W_FETCH, W_SWAP, A_FETCH, A_SWAP,
// COMPUTE, READ_OUTPUT, WRITE_OUTPUT, DONE, ERROR. LOAD_WEIGHTS/
// LOAD_INPUT (task 006) are gone, replaced by the four new dispatch/swap
// states -- the timing contract itself (COMPUTE's stop condition, the
// LATCH_CFG legality check, ERROR, DONE's pulse) is untouched; this is
// an orchestration change around the compute core, not a change to it.
//
// job_kind encoding verified directly against rtl/unpu_dma.sv (task
// 008), not re-derived from memory: JOB_FETCH_A=2'd0, JOB_FETCH_W=2'd1,
// JOB_WRITE_C=2'd2.
//
// ---- Why a single array_en spanning the whole op (including
// arbitrarily long DMA waits) is still correct ----
// unpu_pe.sv's psum_out <= psum_in + product is a pure per-cycle
// function of that cycle's psum_in and product, not a self-referential
// accumulator -- nothing about a PE's own previous psum_out feeds into
// its next value. Row 0's psum_in is permanently tied to 0, so row 0's
// psum_out is fully overwritten (not accumulated) every cycle regardless
// of what garbage flowed through during a DMA wait; every row downstream
// only ever reflects the row above it last cycle plus this cycle's own
// product, so there is no cross-cycle memory beyond one register stage
// anywhere in the chain. COMPUTE only starts trusting/capturing c_in at
// cycle>=7 -- exactly the pipeline's own depth -- so any activity during
// the preceding W_FETCH/W_SWAP/A_FETCH/A_SWAP states has fully drained
// and been overwritten by real data before a single value is captured.
// array_en spans W_FETCH through WRITE_OUTPUT, same footprint as task
// 006's original LOAD_WEIGHTS-through-WRITE_OUTPUT span -- not split
// into a separate buffer-enable/compute-enable, since there is nothing
// for a split to protect against.
//
// ---- Known trap: the "already issued" flag ----
// W_FETCH/A_FETCH/WRITE_OUTPUT each pulse job_start exactly once on
// entry, then hold it low for the rest of the (possibly long, arbiter-
// contended) wait for job_done -- the same "did I already act on this
// edge" bug class that hit task 007 (stale bank-select) and task 010
// (an extra testbench step()), this time in the RTL itself. job_issued
// is cleared whenever `state` is NOT one of the three dispatch states
// (so it's always 0 going into a fresh visit) and set the cycle
// job_start fires; job_start itself is `state==<dispatch state> &&
// !job_issued`, a pure combinational read of job_issued's CURRENT value
// -- no risk of it lagging the state it gates.
//
// ---- Deviation from the task file, flagged for Planning ----
// docs/planning/tasks/011-seq-revision.md's COMPUTE description gives
// rd_row as a REGISTERED update ("rd_row <= (cycle < m_lat) ?
// cycle[1:0] : rd_row"). Implemented literally, this reads `cycle`
// pre-edge (the value going INTO the same edge that also advances
// `cycle` itself), so rd_row would present row (cycle-1) during cycle N,
// one full cycle behind what the timing contract needs -- exactly the
// kind of one-cycle lag task 006's own a_raw avoided by being pure
// combinational (`assign a_raw = ... a_src[cycle] ...`, no register
// stage between the cycle counter and the value it selects). unpu_actbuf
// adds zero latency of its own (task 007: "a plain combinational read of
// the active bank, no clock involved"), so rd_row needs the exact same
// combinational treatment a_raw had for the injection timing to still
// hold. Implemented as `assign rd_row = ...` below instead of a
// registered update -- flagged here rather than silently deviating
// without a note, per the task file's own instruction to stop and flag
// a hole in a timing argument rather than route around it.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006-010 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
module unpu_seq (
  input  logic                  clk,
  input  logic                  rst_n,          // async, active-low (matches every other module in this array)

  input  logic                  start,          // 1-cycle pulse; sampled only while FSM is in IDLE or ERROR, ignored otherwise
  input  logic [2:0]            dim_m,          // legal range 1-4
  input  logic [2:0]            dim_n,          // legal range 1-4
  input  logic [2:0]            dim_k,          // legal range 1-4
  input  logic                  mode_unsigned,  // latched alongside dims in LATCH_CFG
  input  logic [31:0]           src_a,          // from unpu_csr, latched in LATCH_CFG alongside dims
  input  logic [31:0]           src_b,
  input  logic [31:0]           dest_c,

  output logic [3:0][3:0][31:0] c_dst,          // c_dst[m][j]; rows captured as they become valid; wired to unpu_dma.c_src at unpu_top
  output logic                  done,           // 1-cycle pulse
  output logic                  busy,           // 1 whenever FSM is not IDLE and not ERROR
  output logic                  error,          // latched; cleared only by the next start
  output logic [2:0]            error_code,     // meaningful only while error=1; 3'd1 = illegal dim_m/dim_n/dim_k, others reserved

  output logic                  array_en,           // -> unpu_skew/unpu_grid/unpu_deskew/unpu_wbuf/unpu_actbuf .array_en
  output logic                  mode_unsigned_o,    // -> unpu_grid.mode_unsigned (latched copy, not the raw input)

  // DMA job dispatch -- replaces task 006's a_src/w_src/weight_load/weight_in
  output logic                  job_start,          // 1-cycle pulse, exactly once per dispatch-state visit
  output logic [1:0]            job_kind,           // 2'd0=FETCH_A, 2'd1=FETCH_W, 2'd2=WRITE_C -- matches rtl/unpu_dma.sv exactly
  output logic [31:0]           job_base_addr,
  output logic [2:0]            job_m,              // driven every job regardless of kind -- unpu_dma's BUF_LOAD phase needs the full triple even for a single-tensor fetch
  output logic [2:0]            job_n,
  output logic [2:0]            job_k,
  input  logic                  job_done,

  output logic                  w_swap,             // -> unpu_wbuf.swap
  output logic                  a_swap,             // -> unpu_actbuf.swap

  output logic [1:0]            rd_row,             // -> unpu_actbuf.rd_row (replaces task 006's a_raw)
  input  logic [3:0][31:0]      c_in                // <- unpu_deskew.c_out, fed back for capture
);

  localparam logic [1:0] JOB_FETCH_A = 2'd0;
  localparam logic [1:0] JOB_FETCH_W = 2'd1;
  localparam logic [1:0] JOB_WRITE_C = 2'd2;

  typedef enum logic [3:0] {
    IDLE,
    LATCH_CFG,
    W_FETCH,
    W_SWAP,
    A_FETCH,
    A_SWAP,
    COMPUTE,
    READ_OUTPUT,
    WRITE_OUTPUT,
    DONE,
    ERROR
  } seq_state_e;

  seq_state_e state, state_n;

  // Shadow-latched config: a caller changing dim_*/mode_unsigned/src_*
  // mid-run cannot corrupt an in-flight op (notebook §7.1's config-
  // legality/shadow-copy rationale). k_lat/n_lat have no reader within
  // this module beyond feeding job_k/job_n -- see the assigns below.
  logic [2:0]  m_lat, k_lat, n_lat;
  logic        mode_lat;
  logic [31:0] src_a_lat, src_b_lat, dest_c_lat;

  // Single registered cycle counter, shared by the injection mux
  // (rd_row) and the COMPUTE-exit check (state_n) -- the one-cycle-early
  // trap requirement from task 006, unchanged. 4 bits: the exit value is
  // m_lat+6, which reaches 10 at m_lat==4.
  logic [3:0] cycle;

  // "Already issued" flag for the three job-dispatch states -- see the
  // known-trap header comment.
  logic job_issued;

  logic dim_illegal;
  assign dim_illegal = (dim_m == 3'd0) || (dim_m > 3'd4) ||
                        (dim_n == 3'd0) || (dim_n > 3'd4) ||
                        (dim_k == 3'd0) || (dim_k > 3'd4);

  logic is_dispatch_state;
  assign is_dispatch_state = (state == W_FETCH) || (state == A_FETCH) || (state == WRITE_OUTPUT);

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
      LATCH_CFG:    state_n = dim_illegal ? ERROR : W_FETCH;
      W_FETCH:      if (job_issued && job_done) state_n = W_SWAP;
      W_SWAP:       state_n = A_FETCH;
      A_FETCH:      if (job_issued && job_done) state_n = A_SWAP;
      A_SWAP:       state_n = COMPUTE;
      COMPUTE:      if (cycle == m_lat + 4'd6) state_n = READ_OUTPUT;
      READ_OUTPUT:  state_n = WRITE_OUTPUT;
      WRITE_OUTPUT: if (job_issued && job_done) state_n = DONE;
      DONE:         state_n = IDLE;
      ERROR:        if (start) state_n = LATCH_CFG;
      default:      state_n = IDLE;
    endcase
  end

  // ---- job_issued: cleared whenever NOT in a dispatch state (so a
  // fresh visit always starts at 0), set the cycle job_start fires. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      job_issued <= 1'b0;
    else if (!is_dispatch_state)
      job_issued <= 1'b0;
    else if (!job_issued)
      job_issued <= 1'b1;
    // else: already issued this visit -- hold.
  end

  // ---- Moore outputs: pure combinational functions of `state` (see
  // task 006's header rationale, unchanged reasoning: re-registering
  // these would read the OLD state on the same edge state itself
  // updates). ----
  always_comb begin
    array_en = 1'b0;
    busy     = 1'b0;
    done     = 1'b0;
    error    = 1'b0;
    w_swap   = 1'b0;
    a_swap   = 1'b0;
    case (state)
      LATCH_CFG: begin
        busy = 1'b1; // config-check only, doesn't need the datapath live
      end
      W_FETCH: begin
        array_en = 1'b1;
        busy     = 1'b1;
      end
      W_SWAP: begin
        array_en = 1'b1;
        busy     = 1'b1;
        w_swap   = 1'b1; // pulse exactly this one cycle
      end
      A_FETCH: begin
        array_en = 1'b1;
        busy     = 1'b1;
      end
      A_SWAP: begin
        array_en = 1'b1;
        busy     = 1'b1;
        a_swap   = 1'b1; // pulse exactly this one cycle
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
      default: ; // IDLE
    endcase
  end

  assign mode_unsigned_o = mode_lat;

  // ---- job_start: pulses exactly once per dispatch-state visit (see
  // known-trap header comment) -- pure combinational read of the CURRENT
  // job_issued, not a registered/lagged copy. ----
  assign job_start = is_dispatch_state && !job_issued;

  // ---- job_kind/job_base_addr: which tensor/direction for whichever
  // dispatch state is current; harmless don't-care in every other state
  // since job_start=0 there and unpu_dma only samples at its own
  // job_start. job_m/job_n/job_k are driven unconditionally from the
  // latches -- unpu_dma holds them steady across the whole job
  // regardless of what unpu_seq does meanwhile. ----
  assign job_kind = (state == W_FETCH)      ? JOB_FETCH_W :
                     (state == A_FETCH)      ? JOB_FETCH_A :
                     (state == WRITE_OUTPUT) ? JOB_WRITE_C :
                                                JOB_FETCH_A;
  assign job_base_addr = (state == W_FETCH)      ? src_b_lat :
                          (state == A_FETCH)      ? src_a_lat :
                          (state == WRITE_OUTPUT) ? dest_c_lat :
                                                     32'd0;
  assign job_m = m_lat;
  assign job_n = n_lat;
  assign job_k = k_lat;

  // ---- rd_row: injection mux for unpu_actbuf, pure combinational from
  // the CURRENT cycle register -- see the file header's "Deviation from
  // the task file" note for why this must not be registered. ----
  assign rd_row = (state == COMPUTE && cycle < {1'b0, m_lat}) ? cycle[1:0] : 2'd0;

  // ---- Shadow-latched config + error_code: registered, updated only on
  // the LATCH_CFG cycle. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_lat      <= 3'd0;
      k_lat      <= 3'd0;
      n_lat      <= 3'd0;
      mode_lat   <= 1'b0;
      src_a_lat  <= 32'd0;
      src_b_lat  <= 32'd0;
      dest_c_lat <= 32'd0;
      error_code <= 3'd0;
    end else if (state == LATCH_CFG) begin
      if (dim_illegal) begin
        error_code <= 3'd1;
      end else begin
        m_lat      <= dim_m;
        k_lat      <= dim_k;
        n_lat      <= dim_n;
        mode_lat   <= mode_unsigned;
        src_a_lat  <= src_a;
        src_b_lat  <= src_b;
        dest_c_lat <= dest_c;
      end
    end
  end

  // ---- COMPUTE cycle counter: single register, shared by rd_row's mux
  // above and the exit check in state_n above. Forced to 0 throughout
  // A_SWAP so it reads 0 the instant COMPUTE begins (no extra-cycle lag
  // from a one-shot "reset on transition" pulse) -- same fix pattern
  // task 006 used for LOAD_INPUT. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cycle <= 4'd0;
    else if (state == A_SWAP)
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
