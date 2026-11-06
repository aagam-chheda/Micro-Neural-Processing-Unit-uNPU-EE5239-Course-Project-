// Top-level integration for the uNPU macro. Pure wiring across ten
// module instances -- no new mechanism here, everything below is
// already built and unit-tested (tasks 001-011). Every port name in this
// file was checked directly against each module's current source (not
// transcribed from the task file's own wiring table) before wiring,
// same discipline as verifying unpu_dma's job_kind encoding in task 011.
//
// Signal path: unpu_apb -> unpu_csr -> unpu_seq -> unpu_dma ->
// unpu_wbuf/unpu_actbuf -> unpu_skew/unpu_grid/unpu_deskew -> back to
// unpu_seq for capture and writeback (unpu_seq.c_dst IS unpu_dma.c_src,
// task 008 built that shape deliberately so no adapter is needed here).
//
// unpu_grid.psum_in (north edge, all 4 columns) ties to 32'h0000_0000
// always -- no accumulate mode exists in this design, matches every
// testbench built so far. unpu_grid.act_out (east edge) is left
// unconnected -- "goes nowhere and will be optimised away" (notebook
// §05 B7), expected; not wired to anything, on purpose.
//
// CPU<->NPU register port is APB (task 018) -- reverted from the native
// (PicoRV32-convention) interface task 010/012 built, per the user/PM/
// SoC-top team's decision (docs/session-handoff.md). This also fully
// retires task 017's provisional npu_enable/npu_start_req protocol:
// APB's own psel/penable handshake already covers what those signals
// were approximating, so nothing replaces them, they're just gone. The
// DMA<->SRAM master port is unaffected and stays native -- that
// decision was specifically about CPU<->NPU communication, matching its
// corresponding module's port exactly (unpu_apb task 018, unpu_dma task
// 008).
//
// Simulated with Verilator (--binary --timing), consistent with every
// task since 006.
module unpu_top (
  input  logic         clk,
  input  logic         rst_n,

  // APB slave port -- CPU (or SPI debug backdoor) facing. Matches
  // unpu_apb's port exactly (task 018).
  input  logic [31:0]  paddr,
  input  logic [31:0]  pwdata,
  input  logic         pwrite,
  input  logic         psel,
  input  logic         penable,
  output logic [31:0]  prdata,
  output logic         pready,

  // Native master port -- SRAM/arbiter facing. Matches unpu_dma's port
  // exactly (task 008).
  output logic [31:0]  dma_addr,
  output logic [31:0]  dma_wdata,
  input  logic [31:0]  dma_rdata,
  output logic [3:0]   dma_wstrb,
  output logic         dma_valid,
  input  logic         dma_ready
);

  // ---- unpu_apb <-> unpu_csr ----
  logic [9:0]  csr_sel;
  logic [31:0] csr_wdata;
  logic        csr_wen;
  logic [31:0] csr_rdata;

  // ---- unpu_csr -> unpu_seq ----
  logic [31:0] src_a, src_b, dest_c;
  logic [2:0]  dim_m, dim_n, dim_k;
  logic        mode_unsigned;
  logic        start_pulse;

  // ---- unpu_seq -> unpu_csr (status) ----
  logic        seq_done, seq_error;
  logic [2:0]  seq_error_code;

  // ---- unpu_seq <-> unpu_dma (job dispatch) ----
  logic        job_start;
  logic [1:0]  job_kind;
  logic [31:0] job_base_addr;
  logic [2:0]  job_m, job_n, job_k;
  logic        job_done;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        job_busy; // unpu_dma output, unused by unpu_seq -- just needs a net
  /* verilator lint_on UNUSEDSIGNAL */

  // ---- unpu_seq -> unpu_wbuf/unpu_actbuf (swap + read select) ----
  logic        w_swap, a_swap;
  logic [1:0]  rd_row;

  // ---- unpu_seq <-> unpu_deskew / unpu_dma (compute result) ----
  logic [3:0][3:0][31:0] c_dst;
  logic [3:0][31:0]      c_in;

  // ---- unpu_seq -> datapath (global enable/mode) ----
  logic array_en;
  logic mode_unsigned_o;

  // ---- unpu_dma -> unpu_actbuf (fetch-A load port) ----
  logic                 a_load_start;
  logic [2:0]           a_load_m, a_load_k;
  logic [3:0][7:0]      a_load_row;

  // ---- unpu_dma -> unpu_wbuf (fetch-W load port) ----
  logic                 w_load_start;
  logic [2:0]           w_load_k, w_load_n;
  logic [3:0][7:0]      w_load_row;

  // ---- unpu_wbuf/unpu_actbuf load-side status (unused upstream, just
  // need nets to connect) ----
  /* verilator lint_off UNUSEDSIGNAL */
  logic w_load_busy, w_load_done;
  logic a_load_busy, a_load_done;
  /* verilator lint_on UNUSEDSIGNAL */

  // ---- unpu_wbuf -> unpu_grid (weight side) ----
  logic [3:0][3:0]      weight_load;
  logic [3:0][3:0][7:0] weight_in;

  // ---- unpu_actbuf -> unpu_skew -> unpu_grid (activation side) ----
  logic [3:0][7:0] a_rd_data;
  logic [3:0][7:0] skew_act_out;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [3:0][7:0] grid_act_out; // east edge, unconnected downstream (notebook §05 B7) -- "goes nowhere and will be optimised away," expected
  /* verilator lint_on UNUSEDSIGNAL */

  // ---- unpu_grid <-> unpu_deskew (partial sums) ----
  logic [3:0][31:0] grid_psum_in;  // north edge, tied 0 (no accumulate mode)
  logic [3:0][31:0] grid_psum_out;
  logic [3:0][31:0] deskew_c_out;

  assign grid_psum_in = '0;
  assign c_in          = deskew_c_out;

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
    .done_i        (seq_done),
    .error_i       (seq_error),
    .error_code_i  (seq_error_code)
  );

  unpu_seq u_seq (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (start_pulse),
    .dim_m           (dim_m),
    .dim_n           (dim_n),
    .dim_k           (dim_k),
    .mode_unsigned   (mode_unsigned),
    .src_a           (src_a),
    .src_b           (src_b),
    .dest_c          (dest_c),
    .c_dst           (c_dst),
    .done            (seq_done),
    /* verilator lint_off PINCONNECTEMPTY */
    .busy            (),          // no top-level consumer; CPU polls npu_status, not this
    /* verilator lint_on PINCONNECTEMPTY */
    .error           (seq_error),
    .error_code      (seq_error_code),
    .array_en        (array_en),
    .mode_unsigned_o (mode_unsigned_o),
    .job_start       (job_start),
    .job_kind        (job_kind),
    .job_base_addr   (job_base_addr),
    .job_m           (job_m),
    .job_n           (job_n),
    .job_k           (job_k),
    .job_done        (job_done),
    .w_swap          (w_swap),
    .a_swap          (a_swap),
    .rd_row          (rd_row),
    .c_in            (c_in)
  );

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
    .c_src         (c_dst)
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
    .weight_load (weight_load),
    .weight_in   (weight_in)
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
    .rd_row     (rd_row),
    .rd_data    (a_rd_data)
  );

  unpu_skew u_skew (
    .clk      (clk),
    .rst_n    (rst_n),
    .array_en (array_en),
    .a_raw    (a_rd_data),
    .act_out  (skew_act_out)
  );

  unpu_grid u_grid (
    .clk           (clk),
    .rst_n         (rst_n),
    .array_en      (array_en),
    .mode_unsigned (mode_unsigned_o),
    .weight_load   (weight_load),
    .weight_in     (weight_in),
    .act_in        (skew_act_out),
    .psum_in       (grid_psum_in),
    .act_out       (grid_act_out), // unconnected downstream, on purpose
    .psum_out      (grid_psum_out)
  );

  unpu_deskew u_deskew (
    .clk      (clk),
    .rst_n    (rst_n),
    .array_en (array_en),
    .psum_in  (grid_psum_out),
    .c_out    (deskew_c_out)
  );

endmodule
