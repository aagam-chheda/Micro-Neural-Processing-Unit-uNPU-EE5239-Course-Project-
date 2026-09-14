// Native slave for the uNPU CSR window. Turns CPU-facing (and SPI-debug-
// backdoor-facing) native memory-bus transactions into the register-level
// csr_sel/csr_wdata/csr_wen/csr_rdata port unpu_csr already exposes (task
// 009). This is plan.md step 13, "native slave FSM (was: APB slave FSM)"
// -- superseded, not renamed: Q7 confirmed the CPU<->NPU interface is
// native (PicoRV32 convention), not APB.
//
// Despite the "FSM" name carried over from the plan, this collapses to
// pure combinational glue -- no sequential logic at all. unpu_csr already
// reads combinationally (csr_rdata valid off csr_sel, no settle cycle)
// and commits a write in one cycle off a single csr_wen pulse; and the
// notebook's own (now-superseded) APB design already decided pready tied
// high -- "a configuration register has no reason to stall a CPU," and
// separately, the master might be the SPI debug backdoor, which must
// never hang (handoff §3). Both reasons carry over unchanged to native.
// Adding states, a hold register, or extra latency here would work
// against that exact "never stall, never hang" property for no benefit
// -- the "FSM" framing is about the job (bus protocol -> register
// access), not a mandate that the RTL have multiple states.
//
// Two assumptions baked in, flagged so they're easy to revisit rather
// than buried:
// 1. Address decode assumes mem_addr is already known to be in our
//    window whenever mem_valid is asserted -- csr_sel is just
//    mem_addr[11:2] (the word offset within the 4 KB window), never
//    checking the 0x4000_ prefix. Mirrors the old APB design's own
//    already-relative "decode paddr[7:2]" from an upstream bridge. If
//    plan.md's still-open address-window question resolves to "check the
//    prefix ourselves," it's a one-line change here, not a restructure.
// 2. Any nonzero mem_wstrb commits the full 32-bit mem_wdata, no
//    partial-byte merge -- same simplification unpu_dma already made
//    (task 008): every register here is a firmware-facing 32-bit value a
//    `sw` will target, so byte-merge logic has no case to serve.
//
// Simulated with Verilator (--binary --timing), consistent with tasks
// 006-009 -- see docs/planning/plan.md's "Tooling note" for the still-
// open, non-blocking decision on standardizing across the project.
module unpu_slave (
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic         clk,    // unused -- this module is pure combinational glue (see header); kept for interface consistency with every other module in this design
  input  logic         rst_n,  // unused, same reason
  /* verilator lint_on UNUSEDSIGNAL */

  // Native slave port. Same PicoRV32-convention signal shapes as
  // unpu_dma's master port (handoff §4/§5): wstrb==0 means read; rdata
  // is valid the same cycle as valid&ready.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0]  mem_addr, // only [11:2] used -- see assumption 1 above ([31:12] window-prefix bits, [1:0] sub-word byte bits, both intentionally ignored)
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [31:0]  mem_wdata,
  input  logic [3:0]   mem_wstrb,
  input  logic         mem_valid,
  output logic [31:0]  mem_rdata,
  output logic         mem_ready,

  // Register-level port -- straight into unpu_csr, no protocol here
  output logic [9:0]   csr_sel,
  output logic [31:0]  csr_wdata,
  output logic         csr_wen,
  input  logic [31:0]  csr_rdata
);

  assign mem_ready = 1'b1;
  assign csr_sel   = mem_addr[11:2];
  assign csr_wdata = mem_wdata;
  assign csr_wen   = mem_valid && (mem_wstrb != 4'h0);
  assign mem_rdata = csr_rdata;

endmodule
