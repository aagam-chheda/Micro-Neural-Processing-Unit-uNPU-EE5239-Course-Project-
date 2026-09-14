// DMA master for the uNPU 4x4 systolic array. Moves A/W tensors from
// shared SRAM into unpu_actbuf/unpu_wbuf (task 007), and streams C back
// out to SRAM. One job at a time (fetch A, fetch W, or writeback C),
// dispatched by job_start -- unpu_seq doesn't drive this yet (step 14).
//
// Native memory-interface convention (handoff §4/§5): wstrb==0 is a read,
// dma_rdata is valid the same cycle as valid&ready, and -- the trap this
// project's notebook calls "the classic DMA bug... wrong in a way no
// waveform makes obvious" -- the address only ever advances on a cycle
// where dma_valid and dma_ready are BOTH high. That property falls out
// structurally here: beat_idx/cur_m/cur_j only change in D_ACK, which is
// only entered from D_REQ once dma_ready was observed high; D_REQ itself
// holds dma_addr/dma_wdata/dma_wstrb perfectly stable for as long as
// dma_ready stays low, since none of the registers those outputs are
// combinationally derived from change while parked in D_REQ.
//
// Per-beat core is the notebook's own 4-state handshake (D_IDLE/D_REQ/
// D_ACK/D_FIN), quoted in docs/planning/tasks/008-dma.md -- the
// deliberately un-collapsed version (handoff §6: "build the 4-state DMA
// FSM first, optimise later"). BUF_LOAD is the one addition this task
// needs: unpu_actbuf/unpu_wbuf's load ports (task 007) expect a clean,
// gap-free 4-cycle burst once load_start fires, with no stall/
// backpressure handshake of their own -- so a fetch first drains all of
// its beats into the 4-entry `stage` array (absorbing whatever arbiter
// back-pressure D_REQ/D_ACK see), then BUF_LOAD burns exactly 4 clean
// cycles draining `stage` into the buffer's load port, decoupled from the
// bus entirely.
//
// Addressing convention (Planning's choice, not yet firmware-confirmed --
// handoff §7 item 5 is still open; docs/planning/tasks/008-dma.md has the
// full rationale): A/W fetch one 32-bit word per row always
// (addr = base + row*4, row count = M for A, K for W, real K/N only
// changes what the buffers DO with each word's bytes, task 007). C
// writeback uses a fixed 16-byte row stride (addr = dest_C + m*16 + j*4)
// but only ever writes the real N words per row -- hence the explicit
// cur_m/cur_j counters below rather than one flat running address.
// Byte order within a word: word[8*i +: 8] is row/column-element i (byte
// 0 = bits [7:0]) -- a plain packed-array bit-compatible assignment from
// a 32-bit `stage` entry to a `[3:0][7:0]` load_row port produces exactly
// this ordering with no unpack function needed.
//
// Known trap (carried forward from task 007's unpu_wbuf lesson): every
// BUF_LOAD-cycle output (a_load_start/a_load_row/w_load_start/w_load_row)
// is a pure combinational function of the CURRENT `ld_cnt`/`row_idx`, not
// a separately-registered copy that would lag behind by a cycle -- same
// class of bug as unpu_wbuf's weight_in-vs-active_sel mismatch on the
// swap cycle, avoided here by never introducing an intermediate register
// between ld_cnt and what it drives.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006/007 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
module unpu_dma (
  input  logic                  clk,
  input  logic                  rst_n,

  // Native master port to (arbitrated, shared) SRAM
  output logic [31:0]           dma_addr,
  output logic [31:0]           dma_wdata,
  input  logic [31:0]           dma_rdata,
  output logic [3:0]            dma_wstrb,      // 4'h0 = read; 4'hF = write (no partial writes in this design)
  output logic                  dma_valid,
  input  logic                  dma_ready,

  // Job control -- one job at a time, latched (shadow copy) at job_start
  input  logic                  job_start,        // 1-cycle pulse; sampled only in D_IDLE
  input  logic [1:0]            job_kind,         // 2'd0 = fetch A, 2'd1 = fetch W, 2'd2 = writeback C
  input  logic [31:0]           job_base_addr,    // src_A / src_B / dest_C
  input  logic [2:0]            job_m,            // 1-4
  input  logic [2:0]            job_n,            // 1-4
  input  logic [2:0]            job_k,            // 1-4
  output logic                  job_busy,
  output logic                  job_done,         // 1-cycle pulse

  // Fetch-A output -- wire straight into unpu_actbuf's load port
  output logic                  a_load_start,
  output logic [2:0]            a_load_m,
  output logic [2:0]            a_load_k,
  output logic [3:0][7:0]       a_load_row,

  // Fetch-W output -- wire straight into unpu_wbuf's load port
  output logic                  w_load_start,
  output logic [2:0]            w_load_k,
  output logic [2:0]            w_load_n,
  output logic [3:0][7:0]       w_load_row,

  // Writeback-C source -- shaped exactly like unpu_seq's c_dst. Purely
  // combinational read from DMA's side.
  input  logic [3:0][3:0][31:0] c_src
);

  localparam logic [1:0] JOB_FETCH_A = 2'd0;
  localparam logic [1:0] JOB_FETCH_W = 2'd1;
  localparam logic [1:0] JOB_WRITE_C = 2'd2;

  typedef enum logic [2:0] { D_IDLE, D_REQ, D_ACK, BUF_LOAD, D_FIN } dma_state_e;
  dma_state_e state;

  // Shadow-latched job parameters.
  logic [1:0]  kind_lat;
  logic [31:0] base_lat;
  logic [2:0]  m_lat, n_lat, k_lat;

  // Per-beat progress (D_REQ/D_ACK) and writeback row/column position.
  logic [4:0] beat_idx;
  logic [2:0] cur_m, cur_j;

  // 4-entry fetch staging array -- absorbs arbiter back-pressure across
  // D_REQ/D_ACK so BUF_LOAD's drain into unpu_actbuf/unpu_wbuf is clean
  // and gap-free.
  logic [31:0] stage [0:3];

  // BUF_LOAD's own 4-cycle counter.
  logic [1:0] ld_cnt;

  logic [4:0] total_beats;
  assign total_beats = (kind_lat == JOB_FETCH_A) ? {2'b00, m_lat} :
                        (kind_lat == JOB_FETCH_W) ? {2'b00, k_lat} :
                        (5'(m_lat) * 5'(n_lat)); // JOB_WRITE_C: up to 4*4=16

  // ---- Sequential: state, latches, counters, staging capture. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= D_IDLE;
      kind_lat <= 2'd0;
      base_lat <= 32'd0;
      m_lat    <= 3'd0;
      n_lat    <= 3'd0;
      k_lat    <= 3'd0;
      beat_idx <= 5'd0;
      cur_m    <= 3'd0;
      cur_j    <= 3'd0;
      ld_cnt   <= 2'd0;
      stage[0] <= 32'd0;
      stage[1] <= 32'd0;
      stage[2] <= 32'd0;
      stage[3] <= 32'd0;
    end else begin
      case (state)
        D_IDLE: begin
          if (job_start) begin
            kind_lat <= job_kind;
            base_lat <= job_base_addr;
            m_lat    <= job_m;
            n_lat    <= job_n;
            k_lat    <= job_k;
            beat_idx <= 5'd0;
            cur_m    <= 3'd0;
            cur_j    <= 3'd0;
            state    <= D_REQ;
          end
        end

        D_REQ: begin
          if (dma_ready)
            state <= D_ACK;
          // else: dma_addr/dma_wdata/dma_wstrb are combinational functions
          // of registers that don't change here, so everything holds
          // stable automatically -- stay in D_REQ.
        end

        D_ACK: begin
          if (kind_lat != JOB_WRITE_C)
            stage[beat_idx[1:0]] <= dma_rdata;

          if (beat_idx == total_beats - 5'd1) begin
            if (kind_lat == JOB_WRITE_C) begin
              state <= D_FIN;
            end else begin
              state  <= BUF_LOAD;
              ld_cnt <= 2'd0;
            end
          end else begin
            beat_idx <= beat_idx + 5'd1;
            if (kind_lat == JOB_WRITE_C) begin
              if (cur_j == n_lat - 3'd1) begin
                cur_j <= 3'd0;
                cur_m <= cur_m + 3'd1;
              end else begin
                cur_j <= cur_j + 3'd1;
              end
            end
            state <= D_REQ;
          end
        end

        BUF_LOAD: begin
          if (ld_cnt == 2'd3)
            state <= D_FIN;
          else
            ld_cnt <= ld_cnt + 2'd1;
        end

        D_FIN: begin
          state <= D_IDLE;
        end

        default: state <= D_IDLE;
      endcase
    end
  end

  // ---- Combinational: bus-facing outputs. dma_addr/dma_wdata/dma_wstrb
  // read only kind_lat/base_lat/cur_m/cur_j/beat_idx, none of which
  // change while parked in D_REQ -- so "hold everything stable while
  // dma_ready is low" falls out for free. ----
  assign job_busy  = (state != D_IDLE);
  assign job_done  = (state == D_FIN);
  assign dma_valid = (state == D_REQ);
  assign dma_wstrb = (state == D_REQ && kind_lat == JOB_WRITE_C) ? 4'hF : 4'h0;
  assign dma_wdata = (kind_lat == JOB_WRITE_C) ? c_src[cur_m][cur_j] : 32'd0;
  assign dma_addr  = (kind_lat == JOB_WRITE_C)
                      ? (base_lat + (32'(cur_m) * 32'd16) + (32'(cur_j) * 32'd4))
                      : (base_lat + (32'(beat_idx) * 32'd4));

  // ---- Combinational: BUF_LOAD drain into unpu_actbuf/unpu_wbuf. Every
  // output here is a direct function of the CURRENT ld_cnt/row_idx (see
  // header comment's known-trap note) -- ld_cnt is reset to 0 on the same
  // edge state becomes BUF_LOAD (both NBAs commit together), so it reads
  // correctly from the very first BUF_LOAD cycle, same fix pattern as
  // unpu_seq's cycle counter reading 0 the instant COMPUTE begins. ----
  assign a_load_start = (state == BUF_LOAD) && (kind_lat == JOB_FETCH_A) && (ld_cnt == 2'd0);
  assign a_load_m     = m_lat;
  assign a_load_k     = k_lat;
  assign a_load_row   = (4'(ld_cnt) < 4'(m_lat)) ? stage[ld_cnt] : '0;

  logic [2:0] row_idx;
  assign row_idx       = 3'd3 - {1'b0, ld_cnt}; // reverse order for unpu_wbuf: ld_cnt 0->row3 ... 3->row0
  assign w_load_start = (state == BUF_LOAD) && (kind_lat == JOB_FETCH_W) && (ld_cnt == 2'd0);
  assign w_load_k     = k_lat;
  assign w_load_n     = n_lat;
  assign w_load_row   = (4'(row_idx) < 4'(k_lat)) ? stage[row_idx[1:0]] : '0;

endmodule
