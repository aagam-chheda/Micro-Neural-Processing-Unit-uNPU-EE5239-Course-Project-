// CSR / register file for the uNPU. Pure control-plane storage and
// semantics -- word select in, word data in/out, plus the special
// behaviors (write-1-to-pulse START, read-only STATUS). Knows nothing
// about bus protocol; the native slave FSM that decodes real bus
// transactions into this module's simple select/write/read port is a
// separate task (step 13) -- deliberately split, same "three small
// machines, individually provable" reasoning the notebook gives
// (docs/unpu-notebook.html §07) for keeping FSMs small.
//
// Register map: 8-register list is PM-directed (handoff §6/§12); the
// specific offset assignment below is Planning's proposed layout
// (docs/planning/unpu-architecture.html §3), not yet PM-confirmed --
// built against it per docs/planning/tasks/009-csr.md, same provisional
// footing the plan has operated under since task 006.
//
//   sel | name       | access | contents
//   0   | src_a      | R/W    | pointer to A, SRAM
//   1   | src_b      | R/W    | pointer to B, SRAM
//   2   | dest_c     | R/W    | pointer to C, SRAM
//   3   | dim_m      | R/W    | bits[2:0] only
//   4   | dim_n      | R/W    | bits[2:0] only
//   5   | dim_k      | R/W    | bits[2:0] only
//   6   | npu_ctrl   | R/W    | bit0 START (W1P, reads 0) . bit1 SIGNED
//   7   | npu_status | RO     | bit0 DONE . bit1 ERROR . bits[4:2] error_code
//
// dim_m/dim_n/dim_k legality (1-4) is NOT validated here -- unpu_seq's
// LATCH_CFG already does that (task 006); this module stores whatever is
// written, verbatim.
//
// Polarity (Planning's call, flag back if wrong): the architecture doc
// labels npu_ctrl bit1 "SIGNED mode" with no stated polarity. Read
// literally -- bit1=1 means "operating in signed mode" -- this is the
// INVERSE of unpu_pe's mode_unsigned convention (0=signed, 1=unsigned).
// So mode_unsigned = ~ctrl_signed_reg. The register itself stores bit1
// exactly as written (uninverted); only the derived mode_unsigned OUTPUT
// is inverted -- getting this backwards would silently run every matmul
// in the wrong sign interpretation, and nothing in a naive round-trip
// test would catch it (only a check of the OUTPUT polarity would).
//
// npu_status.DONE is sticky (latched, cleared only by the next
// start_pulse), not a pulse-through -- unpu_seq.done is only a 1-cycle
// pulse (task 006), and firmware needs to poll npu_status at its own
// pace, potentially many cycles later. Priority on coincidence (can't
// happen in real operation, defined anyway for determinism): a new
// start_pulse clears DONE before done_i could set it.
//
// npu_status.ERROR/error_code are pure combinational passthroughs of
// error_i/error_code_i -- unpu_seq already latches error itself (task
// 006: "latched; cleared only by the next start"), so no second latch
// here.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006-008 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
module unpu_csr (
  input  logic         clk,
  input  logic         rst_n,          // async, active-low

  // Register-level R/W port -- bus-protocol-agnostic. sel is a WORD
  // offset within the full 4 KB register window (1024 words); this
  // module implements "unmapped reads as zero, writes ignored" itself
  // (docs/unpu-notebook.html §05 B1) rather than leaving it to step 13.
  input  logic [9:0]   csr_sel,
  input  logic [31:0]  csr_wdata,
  input  logic         csr_wen,        // 1-cycle pulse: commit csr_wdata to csr_sel's register this cycle
  output logic [31:0]  csr_rdata,      // combinational read of csr_sel, no read-enable needed (reads never stall)

  // Consumer-facing outputs -- latched register contents, for unpu_seq /
  // unpu_dma to read directly once step 14 wires this in
  output logic [31:0]  src_a,
  output logic [31:0]  src_b,
  output logic [31:0]  dest_c,
  output logic [2:0]   dim_m,
  output logic [2:0]   dim_n,
  output logic [2:0]   dim_k,
  output logic         mode_unsigned,  // = ~npu_ctrl[1] -- see polarity note above
  output logic         start_pulse,    // 1-cycle pulse, registered one cycle after a qualifying START write -> unpu_seq.start

  // Status inputs -- from unpu_seq
  input  logic         done_i,         // 1-cycle pulse from unpu_seq.done; latches npu_status.DONE
  input  logic         error_i,        // level, already latched upstream by unpu_seq (task 006) -- pass through, don't re-latch
  input  logic [2:0]   error_code_i    // from unpu_seq.error_code, pass through alongside error_i
);

  localparam logic [9:0] SEL_SRC_A    = 10'd0;
  localparam logic [9:0] SEL_SRC_B    = 10'd1;
  localparam logic [9:0] SEL_DEST_C   = 10'd2;
  localparam logic [9:0] SEL_DIM_M    = 10'd3;
  localparam logic [9:0] SEL_DIM_N    = 10'd4;
  localparam logic [9:0] SEL_DIM_K    = 10'd5;
  localparam logic [9:0] SEL_NPU_CTRL = 10'd6;
  localparam logic [9:0] SEL_NPU_STAT = 10'd7;

  logic [31:0] src_a_reg, src_b_reg, dest_c_reg;
  logic [2:0]  dim_m_reg, dim_n_reg, dim_k_reg;
  logic        ctrl_signed_reg; // npu_ctrl bit1, stored uninverted -- see polarity note
  logic        status_done_reg;

  // ---- Writes: bit0 of npu_ctrl (START) is consumed by start_pulse
  // below, never stored here -- it always reads back 0. npu_status
  // (SEL_NPU_STAT) and every unmapped sel (8-1023) fall through to
  // default: csr_wen is accepted but has no effect on any real
  // register, per spec. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      src_a_reg       <= 32'd0;
      src_b_reg       <= 32'd0;
      dest_c_reg      <= 32'd0;
      dim_m_reg       <= 3'd0;
      dim_n_reg       <= 3'd0;
      dim_k_reg       <= 3'd0;
      ctrl_signed_reg <= 1'b0;
    end else if (csr_wen) begin
      case (csr_sel)
        SEL_SRC_A:    src_a_reg       <= csr_wdata;
        SEL_SRC_B:    src_b_reg       <= csr_wdata;
        SEL_DEST_C:   dest_c_reg      <= csr_wdata;
        SEL_DIM_M:    dim_m_reg       <= csr_wdata[2:0];
        SEL_DIM_N:    dim_n_reg       <= csr_wdata[2:0];
        SEL_DIM_K:    dim_k_reg       <= csr_wdata[2:0];
        SEL_NPU_CTRL: ctrl_signed_reg <= csr_wdata[1];
        default:      ; // npu_status (RO) and unmapped: accepted, no effect
      endcase
    end
  end

  assign src_a         = src_a_reg;
  assign src_b         = src_b_reg;
  assign dest_c        = dest_c_reg;
  assign dim_m         = dim_m_reg;
  assign dim_n         = dim_n_reg;
  assign dim_k         = dim_k_reg;
  assign mode_unsigned = ~ctrl_signed_reg;

  // ---- start_pulse: registered one cycle after a qualifying write --
  // clean synchronous handoff, matches the Moore-output discipline used
  // throughout this design (notebook §07.1, unpu_seq, task 006). ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      start_pulse <= 1'b0;
    else
      start_pulse <= csr_wen && (csr_sel == SEL_NPU_CTRL) && csr_wdata[0];
  end

  // ---- npu_status.DONE: sticky, start-clear priority over done_i. ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      status_done_reg <= 1'b0;
    else if (start_pulse)
      status_done_reg <= 1'b0;
    else if (done_i)
      status_done_reg <= 1'b1;
  end

  // ---- Read mux: unmapped sel (8-1023) reads 0 via default. ----
  always_comb begin
    case (csr_sel)
      SEL_SRC_A:    csr_rdata = src_a_reg;
      SEL_SRC_B:    csr_rdata = src_b_reg;
      SEL_DEST_C:   csr_rdata = dest_c_reg;
      SEL_DIM_M:    csr_rdata = {29'd0, dim_m_reg};
      SEL_DIM_N:    csr_rdata = {29'd0, dim_n_reg};
      SEL_DIM_K:    csr_rdata = {29'd0, dim_k_reg};
      SEL_NPU_CTRL: csr_rdata = {30'd0, ctrl_signed_reg, 1'b0}; // bit0 always reads 0
      SEL_NPU_STAT: csr_rdata = {27'd0, error_code_i, error_i, status_done_reg};
      default:      csr_rdata = 32'd0;
    endcase
  end

endmodule
