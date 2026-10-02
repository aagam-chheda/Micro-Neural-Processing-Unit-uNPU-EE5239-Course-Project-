// Main sequencer FSM for the uNPU 4x4 systolic array.
// Step 2 Refactor: Concurrent Dual-FSM Architecture (CE and DE) with
// Fork-Join barrier synchronization, dual-buffered ping-pong output staging
// (c_dst_bank[0:1]), autonomous address accumulators, zero-bubble
// lookahead bypass, and unified start qualification.
//
// Documented and formally verified in docs/pipelining_spec.md (Version 1.1.1).
//
// Architecture Overview:
// 1. Compute Engine (CE) FSM (ce_state):
//    CE_IDLE -> CE_LATCH_CFG -> CE_PROLOGUE_WAIT -> CE_COMPUTE -> CE_WAIT_BARRIER
//    Orchestrates activation injection (rd_row), systolic execution cycles
//    (cycle: 0 .. M+6), deskew output capture into c_dst_bank[c_bank_comp],
//    and array gating (array_en).
//
// 2. DMA Engine (DE) FSM (de_state):
//    DE_IDLE -> DE_PROLOGUE_W -> DE_PROLOGUE_SWAP_W -> DE_PROLOGUE_A ->
//    DE_PROLOGUE_WAIT -> DE_STEADY_WRITE_C -> DE_STEADY_FETCH_W ->
//    DE_STEADY_FETCH_A -> DE_DRAIN_WRITE_C -> DE_WAIT_BARRIER
//    Orchestrates serialized DMA memory transfers (JOB_WRITE_C, JOB_FETCH_W,
//    JOB_FETCH_A) over the single shared DMA master port.
//
// 3. Synchronization Barrier (can_advance):
//    can_advance = ce_done && de_done
//    Synchronizes CE and DE at tile boundaries. On barrier assertion:
//    - Pulses w_swap and a_swap with array_en=1
//    - Toggles output ping-pong banks (c_bank_comp, c_bank_dma)
//    - Advances autonomous address pointers (src_a_ptr, src_b_ptr)
//    - Increments tile_idx counter
//
// 4. Unified Start Qualification & Single-Tile Backward Compatibility:
//    start_valid gates start on both CE and DE being quiescent (IDLE or ERROR).
//    Stray start pulses during active writeback drain (DE_DRAIN_WRITE_C) are
//    strictly ignored, preserving output memory contents and bank pointers.
//    Cold-start prologue decouples w_swap (in DE_PROLOGUE_SWAP_W) and a_swap
//    (at the prologue barrier), maintaining 100% compliance with legacy testbenches.
module unpu_seq (
  input  logic                  clk,
  input  logic                  rst_n,          // async, active-low

  input  logic                  start,          // 1-cycle pulse; sampled only in IDLE/ERROR
  input  logic [2:0]            dim_m,          // legal range 1-4
  input  logic [2:0]            dim_n,          // legal range 1-4
  input  logic [2:0]            dim_k,          // legal range 1-4
  input  logic                  mode_unsigned,  // latched alongside dims in LATCH_CFG
  input  logic [31:0]           src_a,          // from unpu_csr, latched in LATCH_CFG
  input  logic [31:0]           src_b,
  input  logic [31:0]           dest_c,

  // Multi-tile streaming control from unpu_csr (Section 5.1/5.2)
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [15:0]           num_tiles = 16'd1, // total tiles to compute (N_tiles >= 1)
  input  logic [31:0]           stride_a  = 32'd0, // byte stride for tensor A base pointer
  input  logic [31:0]           stride_b  = 32'd0, // byte stride for tensor B base pointer
  input  logic [31:0]           stride_c  = 32'd0, // byte stride for tensor C base pointer
  /* verilator lint_on UNUSEDSIGNAL */

  output logic [3:0][3:0][31:0] c_dst,          // c_dst[m][j]; wired to unpu_dma.c_src
  output logic                  done,           // 1-cycle pulse
  output logic                  busy,           // 1 whenever FSM is active
  output logic                  error,          // latched; cleared only by next valid start
  output logic [2:0]            error_code,     // 3'd1 = illegal dimensions or num_tiles=0

  output logic                  array_en,       // -> unpu_skew/unpu_grid/unpu_deskew/unpu_wbuf/unpu_actbuf
  output logic                  mode_unsigned_o,// -> unpu_grid.mode_unsigned (latched copy)

  // DMA job dispatch -> unpu_dma
  output logic                  job_start,      // 1-cycle pulse per dispatch-state visit
  output logic [1:0]            job_kind,       // 2'd0=FETCH_A, 2'd1=FETCH_W, 2'd2=WRITE_C
  output logic [31:0]           job_base_addr,
  output logic [2:0]            job_m,
  output logic [2:0]            job_n,
  output logic [2:0]            job_k,
  input  logic                  job_done,

  output logic                  w_swap,         // -> unpu_wbuf.swap
  output logic                  a_swap,         // -> unpu_actbuf.swap

  output logic [1:0]            rd_row,         // -> unpu_actbuf.rd_row
  input  logic [3:0][31:0]      c_in            // <- unpu_deskew.c_out
);

  localparam logic [1:0] JOB_FETCH_A = 2'd0;
  localparam logic [1:0] JOB_FETCH_W = 2'd1;
  localparam logic [1:0] JOB_WRITE_C = 2'd2;

  // =========================================================================
  // 1. Dual-FSM State Type Definitions
  // =========================================================================
  typedef enum logic [2:0] {
    CE_IDLE          = 3'd0,
    CE_LATCH_CFG     = 3'd1,
    CE_PROLOGUE_WAIT = 3'd2,
    CE_COMPUTE       = 3'd3,
    CE_WAIT_BARRIER  = 3'd4,
    CE_ERROR         = 3'd5
  } ce_state_e;

  typedef enum logic [3:0] {
    DE_IDLE             = 4'd0,
    DE_PROLOGUE_W       = 4'd1,
    DE_PROLOGUE_SWAP_W  = 4'd2, // Cold-start 1-cycle weight swap
    DE_PROLOGUE_A       = 4'd3,
    DE_PROLOGUE_WAIT    = 4'd4,
    DE_STEADY_WRITE_C   = 4'd5,
    DE_STEADY_FETCH_W   = 4'd6,
    DE_STEADY_FETCH_A   = 4'd7,
    DE_DRAIN_WRITE_C    = 4'd8,
    DE_WAIT_BARRIER     = 4'd9,
    DE_ERROR            = 4'd10
  } de_state_e;

  ce_state_e ce_state, ce_state_n;
  de_state_e de_state, de_state_n;

  // =========================================================================
  // 2. Unified Start Qualification
  // =========================================================================
  // A start pulse is only legal when both engines are completely quiescent
  // (IDLE or ERROR). Stray start pulses while DE is draining writeback are
  // ignored to prevent output buffer and pointer corruption.
  wire start_valid = start &&
                     (ce_state == CE_IDLE || ce_state == CE_ERROR) &&
                     (de_state == DE_IDLE || de_state == DE_ERROR);

  // =========================================================================
  // 3. Configuration & Shadow Latches
  // =========================================================================
  logic [2:0]  m_lat, k_lat, n_lat;
  logic        mode_lat;
  logic [31:0] src_a_lat, src_b_lat, dest_c_lat;
  logic [15:0] num_tiles_lat;
  logic [31:0] stride_a_lat, stride_b_lat, stride_c_lat;

  logic dim_illegal;
  assign dim_illegal = (dim_m == 3'd0) || (dim_m > 3'd4) ||
                       (dim_n == 3'd0) || (dim_n > 3'd4) ||
                       (dim_k == 3'd0) || (dim_k > 3'd4) ||
                       (num_tiles == 16'd0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_lat          <= 3'd0;
      k_lat          <= 3'd0;
      n_lat          <= 3'd0;
      mode_lat       <= 1'b0;
      src_a_lat      <= 32'd0;
      src_b_lat      <= 32'd0;
      dest_c_lat     <= 32'd0;
      num_tiles_lat  <= 16'd1;
      stride_a_lat   <= 32'd0;
      stride_b_lat   <= 32'd0;
      stride_c_lat   <= 32'd0;
    end else if (ce_state == CE_LATCH_CFG && !dim_illegal) begin
      m_lat          <= dim_m;
      k_lat          <= dim_k;
      n_lat          <= dim_n;
      mode_lat       <= mode_unsigned;
      src_a_lat      <= src_a;
      src_b_lat      <= src_b;
      dest_c_lat     <= dest_c;
      num_tiles_lat  <= num_tiles;
      stride_a_lat   <= stride_a;
      stride_b_lat   <= stride_b;
      stride_c_lat   <= stride_c;
    end
  end

  assign mode_unsigned_o = mode_lat;

  // =========================================================================
  // 4. Tile Index & Termination Detection
  // =========================================================================
  logic [15:0] tile_idx;
  logic        is_last_tile;
  assign is_last_tile = (tile_idx == num_tiles_lat - 16'd1);

  // =========================================================================
  // 5. Address Pointers & Effective Stride Arithmetic
  // =========================================================================
  logic [31:0] eff_stride_a, eff_stride_b, eff_stride_c;
  // Default dense strides: A = M * 4 bytes, B = K * 4 bytes, C = M * 16 bytes
  assign eff_stride_a = (stride_a_lat != 32'd0) ? stride_a_lat : {27'd0, m_lat, 2'b00};
  assign eff_stride_b = (stride_b_lat != 32'd0) ? stride_b_lat : {27'd0, k_lat, 2'b00};
  assign eff_stride_c = (stride_c_lat != 32'd0) ? stride_c_lat : {25'd0, m_lat, 4'b0000};

  logic [31:0] src_a_ptr;
  logic [31:0] src_b_ptr;
  logic [31:0] dest_c_ptr;

  logic can_advance;
  logic job_issued;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      src_a_ptr  <= 32'd0;
      src_b_ptr  <= 32'd0;
      dest_c_ptr <= 32'd0;
      tile_idx   <= 16'd0;
    end else if (ce_state == CE_LATCH_CFG) begin
      src_a_ptr  <= src_a;
      src_b_ptr  <= src_b;
      dest_c_ptr <= dest_c;
      tile_idx   <= 16'd0;
    end else begin
      // Input prefetch pointers advance on every tile swap (can_advance)
      if (can_advance) begin
        src_a_ptr <= src_a_ptr + eff_stride_a;
        src_b_ptr <= src_b_ptr + eff_stride_b;
      end
      // Output writeback pointer advances ONLY on actual completion of JOB_WRITE_C
      if (de_state inside {DE_STEADY_WRITE_C, DE_DRAIN_WRITE_C} && job_issued && job_done) begin
        dest_c_ptr <= dest_c_ptr + eff_stride_c;
      end
      // Tile index counter increments strictly when retiring a compute tile
      if (can_advance && (ce_state == CE_COMPUTE || ce_state == CE_WAIT_BARRIER)) begin
        tile_idx <= tile_idx + 16'd1;
      end
    end
  end

  // =========================================================================
  // 6. Dual Ping-Pong Output Buffer (c_dst_bank[0:1])
  // =========================================================================
  logic [3:0][3:0][31:0] c_dst_bank [0:1];
  logic                  c_bank_comp; // Bank populated by systolic compute
  logic                  c_bank_dma;  // Bank read by DMA writeback to SRAM

  assign c_dst = c_dst_bank[c_bank_dma];

  logic [3:0] cycle;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      c_dst_bank[0] <= '0;
      c_dst_bank[1] <= '0;
    end else if (ce_state == CE_COMPUTE && array_en && cycle >= 4'd7) begin
      c_dst_bank[c_bank_comp][cycle - 4'd7] <= c_in;
    end
  end

  // Output bank pointer toggle across barrier:
  // Gated on (ce_state == CE_COMPUTE || ce_state == CE_WAIT_BARRIER) so that
  // the Prologue barrier does not advance bank pointers. Tile 0 always
  // captures into c_dst_bank[0] (c_bank_comp=0).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      c_bank_comp <= 1'b0;
      c_bank_dma  <= 1'b1;
    end else if (ce_state == CE_LATCH_CFG) begin
      c_bank_comp <= 1'b0;
      c_bank_dma  <= 1'b1;
    end else if (can_advance && (ce_state == CE_COMPUTE || ce_state == CE_WAIT_BARRIER)) begin
      c_bank_comp <= ~c_bank_comp;
      c_bank_dma  <= ~c_bank_dma;
    end
  end

  // =========================================================================
  // 7. Synchronization Barrier & Fork-Join Handshake
  // =========================================================================
  logic ce_done;
  logic de_done;

  assign ce_done = (ce_state == CE_PROLOGUE_WAIT) ||
                   (ce_state == CE_WAIT_BARRIER);

  assign de_done = (de_state == DE_WAIT_BARRIER) ||
                   (de_state == DE_STEADY_FETCH_A && job_issued && job_done) ||
                   (de_state == DE_PROLOGUE_WAIT);

  assign can_advance = ce_done && de_done;

  // Swap output continuous assignments:
  // w_swap fires in DE_PROLOGUE_SWAP_W during cold-start, and on can_advance in steady-state.
  // a_swap fires strictly at tile barriers (can_advance).
  assign w_swap = (de_state == DE_PROLOGUE_SWAP_W) ||
                  (can_advance && (ce_state != CE_PROLOGUE_WAIT));
  assign a_swap = can_advance;

  // =========================================================================
  // 8. Compute Engine (CE) FSM
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      ce_state <= CE_IDLE;
    else
      ce_state <= ce_state_n;
  end

  always_comb begin
    ce_state_n = ce_state;
    case (ce_state)
      CE_IDLE: begin
        if (start_valid)
          ce_state_n = CE_LATCH_CFG;
      end

      CE_LATCH_CFG: begin
        if (dim_illegal)
          ce_state_n = CE_ERROR;
        else
          ce_state_n = CE_PROLOGUE_WAIT;
      end

      CE_PROLOGUE_WAIT: begin
        if (can_advance)
          ce_state_n = CE_COMPUTE;
      end

      CE_COMPUTE: begin
        if (cycle == m_lat + 4'd6)
          ce_state_n = CE_WAIT_BARRIER;
      end

      CE_WAIT_BARRIER: begin
        if (can_advance) begin
          if (is_last_tile)
            ce_state_n = CE_IDLE;
          else
            ce_state_n = CE_COMPUTE;
        end
      end

      CE_ERROR: begin
        if (start_valid)
          ce_state_n = CE_LATCH_CFG;
      end

      default: ce_state_n = CE_IDLE;
    endcase
  end

  // CE Cycle Counter (0 .. M+6)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cycle <= 4'd0;
    else if (can_advance)
      cycle <= 4'd0;
    else if (ce_state == CE_COMPUTE) begin
      if (cycle != m_lat + 4'd6)
        cycle <= cycle + 4'd1;
    end else
      cycle <= 4'd0;
  end

  // Combinational activation injection mux
  assign rd_row = (ce_state == CE_COMPUTE && cycle < {1'b0, m_lat}) ? cycle[1:0] : 2'd0;

  // =========================================================================
  // 9. DMA Engine (DE) FSM
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      de_state <= DE_IDLE;
    else
      de_state <= de_state_n;
  end

  always_comb begin
    de_state_n = de_state;
    case (de_state)
      DE_IDLE: begin
        if (ce_state == CE_LATCH_CFG) begin
          if (dim_illegal)
            de_state_n = DE_ERROR;
          else
            de_state_n = DE_PROLOGUE_W;
        end
      end

      DE_PROLOGUE_W: begin
        if (job_issued && job_done)
          de_state_n = DE_PROLOGUE_SWAP_W;
      end

      DE_PROLOGUE_SWAP_W: begin
        de_state_n = DE_PROLOGUE_A;
      end

      DE_PROLOGUE_A: begin
        if (job_issued && job_done)
          de_state_n = DE_PROLOGUE_WAIT;
      end

      DE_PROLOGUE_WAIT: begin
        if (can_advance) begin
          if (is_last_tile)
            de_state_n = DE_WAIT_BARRIER;
          else
            de_state_n = DE_STEADY_FETCH_W;
        end
      end

      DE_STEADY_WRITE_C: begin
        if (job_issued && job_done) begin
          if (is_last_tile)
            de_state_n = DE_WAIT_BARRIER;
          else
            de_state_n = DE_STEADY_FETCH_W;
        end
      end

      DE_STEADY_FETCH_W: begin
        if (job_issued && job_done)
          de_state_n = DE_STEADY_FETCH_A;
      end

      DE_STEADY_FETCH_A: begin
        if (job_issued && job_done) begin
          if (can_advance)
            de_state_n = is_last_tile ? DE_DRAIN_WRITE_C : DE_STEADY_WRITE_C;
          else
            de_state_n = DE_WAIT_BARRIER;
        end
      end

      DE_WAIT_BARRIER: begin
        if (can_advance)
          de_state_n = is_last_tile ? DE_DRAIN_WRITE_C : DE_STEADY_WRITE_C;
      end

      DE_DRAIN_WRITE_C: begin
        if (job_issued && job_done)
          de_state_n = DE_IDLE;
      end

      DE_ERROR: begin
        if (start_valid)
          de_state_n = DE_IDLE;
      end

      default: de_state_n = DE_IDLE;
    endcase
  end

  // =========================================================================
  // 10. DMA Job Dispatch Logic
  // =========================================================================
  logic is_dispatch_state;
  assign is_dispatch_state = (de_state == DE_PROLOGUE_W)     ||
                             (de_state == DE_PROLOGUE_A)     ||
                             (de_state == DE_STEADY_WRITE_C) ||
                             (de_state == DE_STEADY_FETCH_W) ||
                             (de_state == DE_STEADY_FETCH_A) ||
                             (de_state == DE_DRAIN_WRITE_C);

  // Single-pulse job_start tracking across back-to-back dispatch states
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      job_issued <= 1'b0;
    else if (de_state != de_state_n)
      job_issued <= 1'b0;
    else if (is_dispatch_state && !job_issued)
      job_issued <= 1'b1;
  end

  assign job_start = is_dispatch_state && !job_issued;

  assign job_kind = (de_state == DE_PROLOGUE_W)     ? JOB_FETCH_W :
                    (de_state == DE_PROLOGUE_A)     ? JOB_FETCH_A :
                    (de_state == DE_STEADY_WRITE_C) ? JOB_WRITE_C :
                    (de_state == DE_STEADY_FETCH_W) ? JOB_FETCH_W :
                    (de_state == DE_STEADY_FETCH_A) ? JOB_FETCH_A :
                    (de_state == DE_DRAIN_WRITE_C)  ? JOB_WRITE_C :
                                                      JOB_FETCH_A;

  assign job_base_addr = (de_state == DE_PROLOGUE_W)     ? src_b_lat  :
                         (de_state == DE_PROLOGUE_A)     ? src_a_lat  :
                         (de_state == DE_STEADY_WRITE_C) ? dest_c_ptr :
                         (de_state == DE_STEADY_FETCH_W) ? src_b_ptr  :
                         (de_state == DE_STEADY_FETCH_A) ? src_a_ptr  :
                         (de_state == DE_DRAIN_WRITE_C)  ? dest_c_ptr :
                                                           32'd0;

  assign job_m = m_lat;
  assign job_n = n_lat;
  assign job_k = k_lat;

  // =========================================================================
  // 11. Datapath Control & Clock Gating (array_en)
  // =========================================================================
  // array_en gates systolic PE registers, skew/deskew networks, and buffer
  // shifting. Must be 1'b1 during compute, swap, and buffer loading.
  assign array_en = (ce_state == CE_COMPUTE) ||
                    can_advance ||
                    (de_state == DE_PROLOGUE_W) ||
                    (de_state == DE_PROLOGUE_SWAP_W) ||
                    (de_state == DE_PROLOGUE_A) ||
                    (de_state == DE_STEADY_FETCH_W) ||
                    (de_state == DE_STEADY_FETCH_A);

  // =========================================================================
  // 12. Top-Level Status Outputs (busy, done, error, error_code)
  // =========================================================================
  // 1-cycle completion pulse upon retiring the final drain writeback
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      done <= 1'b0;
    else
      done <= (de_state == DE_DRAIN_WRITE_C && job_issued && job_done);
  end

  // busy: 1 whenever FSM is active (including done pulse)
  assign busy = (ce_state != CE_IDLE && ce_state != CE_ERROR) ||
                (de_state != DE_IDLE && de_state != DE_ERROR) ||
                done;

  // Latched error and error_code
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      error      <= 1'b0;
      error_code <= 3'd0;
    end else if (start_valid) begin
      error      <= 1'b0;
      error_code <= 3'd0;
    end else if (ce_state == CE_LATCH_CFG && dim_illegal) begin
      error      <= 1'b1;
      error_code <= 3'd1;
    end
  end

endmodule
