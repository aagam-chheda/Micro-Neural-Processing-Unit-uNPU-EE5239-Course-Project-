// APB slave for the uNPU CSR window. Turns CPU-facing (and SPI-debug-
// backdoor-facing) APB transactions into the register-level
// csr_sel/csr_wdata/csr_wen/csr_rdata port unpu_csr already exposes (task
// 009). This is plan.md step 13's "APB slave FSM," restored -- task 010's
// native slave (mem_*, PicoRV32 convention) is retired: the user, the PM,
// and the SoC-top team met and decided the CPU<->NPU register interface
// reverts to APB (docs/session-handoff.md), superseding Q7's earlier
// "native for both ports" answer for this half only. The DMA<->SRAM
// master port (unpu_dma) is unaffected and stays native.
//
// This also fully retires task 017's provisional npu_enable/
// npu_start_req protocol -- APB's own psel/penable handshake already
// provides everything those signals were approximating: psel is target
// identification (what npu_enable stood in for), penable qualifies real
// access from setup, and START stays a register write over the bus like
// it always was, so npu_start_req isn't replaced by anything, it's gone.
//
// Despite the "FSM" name carried over from the plan, this collapses to
// pure combinational glue -- no sequential logic at all, same finding as
// the native slave it replaces and for the same reason: unpu_csr already
// reads/writes in a single cycle, and pready is tied high -- "a
// configuration register has no reason to stall a CPU," and separately,
// the master might be the SPI debug backdoor, which must never hang
// (handoff §3). Trust the master to sequence SETUP (psel=1, penable=0)
// before ACCESS (psel=1, penable=1), standard APB discipline; this slave
// doesn't independently track which phase it's in, it just reacts
// combinationally to whatever's presented.
//
// Two assumptions baked in, flagged so they're easy to revisit rather
// than buried (both carried over unchanged from the native slave, task
// 010, and before that the notebook's original APB sketch, notebook
// §05 B1):
// 1. Address decode assumes paddr is already known to be in our window
//    whenever psel is asserted -- csr_sel is just paddr[11:2] (the word
//    offset within the 4 KB window), never checking the 0x4000_ prefix.
//    The notebook's original sketch said "decode paddr[7:2]," sized for
//    the old 5-register design's smaller window -- csr_sel is 10 bits
//    now (the actual 4 KB window, 1024 words), so paddr[11:2] is what
//    matches what's already built. Re-confirmed by the PM's own answer
//    on this exact point (docs/session-handoff.md §16): an external
//    decoder asserts our psel specifically -- that decoder's job (and
//    APB's own convention) is exactly "generate a peripheral-specific
//    select."
// 2. Every write is a full-word write, no PSTRB (byte-lane strobes) and
//    no partial-byte merge -- same simplification unpu_dma (task 008)
//    and the old native slave (task 010) both already made: every
//    register here is a firmware-facing 32-bit value a `sw` will target,
//    so byte-merge logic has no case to serve.
//
// No PSLVERR: every transaction returns success, matching the "never
// stall, never error, a stray pointer shouldn't hang the SoC" philosophy
// already built into unpu_csr's unmapped-offset handling.
//
// csr_wen gates on psel && penable && pwrite -- specifically penable, not
// psel alone. Gating on psel alone would commit a write during SETUP,
// before the master has necessarily settled pwdata/paddr for this
// transaction; only once penable is also asserted has the master reached
// ACCESS. tb/unpu_apb_tb.sv has a directed test for exactly this
// boundary.
//
// Simulated with Verilator (--binary --timing), consistent with every
// task since 006.
module unpu_apb (
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic         clk,    // unused -- this module is pure combinational glue (see header); kept for interface consistency with every other module in this design
  input  logic         rst_n,  // unused, same reason
  /* verilator lint_on UNUSEDSIGNAL */

  // APB slave port
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0]  paddr,  // only [11:2] used -- see assumption 1 above ([31:12] window-prefix bits, [1:0] sub-word byte bits, both intentionally ignored)
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [31:0]  pwdata,
  input  logic         pwrite,   // 1 = write, 0 = read
  input  logic         psel,
  input  logic         penable,
  output logic [31:0]  prdata,
  output logic         pready,

  // Register-level port -- straight into unpu_csr, no protocol here
  output logic [9:0]   csr_sel,
  output logic [31:0]  csr_wdata,
  output logic         csr_wen,
  input  logic [31:0]  csr_rdata
);

  assign pready    = 1'b1;
  assign csr_sel   = paddr[11:2];
  assign csr_wdata = pwdata;
  assign csr_wen   = psel && penable && pwrite;
  assign prdata    = csr_rdata;

endmodule
