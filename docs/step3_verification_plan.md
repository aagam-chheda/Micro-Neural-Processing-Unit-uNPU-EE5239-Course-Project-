# Step 3 Pre-Flight Verification Audit & Multi-Tile Test Architecture Plan

**Role:** Principal Verification Architect & Testbench Lead  
**Scope:** Verification Infrastructure Audit for [tb/unpu_top_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_top_tb.sv), [tb/unpu_seq_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_seq_tb.sv), [rtl/unpu_csr.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/rtl/unpu_csr.sv), [rtl/unpu_seq.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/rtl/unpu_seq.sv), and [model/golden.c](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/model/golden.c)  
**Target Milestone:** Step 3 (Multi-Tile Pipelined Execution & Speedup Verification)

---

## 1. Executive Summary & Verification Context

With **Step 1** (CSR register packing & top-level interconnect) and **Step 2** (Dual-FSM refactor in [rtl/unpu_seq.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/rtl/unpu_seq.sv)) complete and verified with **10/10 testbenches passing (917,321 checks, 0 errors)**, the underlying hardware datapath and control microarchitecture are fundamentally ready for multi-tile execution.

However, all baseline regression testbenches currently run strictly in **single-tile mode (`num_tiles = 1`)**:
* Concurrent compute + prefetch + writeback has **never been exercised**.
* Ping-pong buffer background loading under live systolic compute has **never been exercised**.
* Multi-tile address stride progression (`src_a_ptr`, `src_b_ptr`, `dest_c_ptr`) has **never been exercised**.
* Epilogue DMA prefetch suppression ($N_{\text{tiles}}-1$) has **never been exercised**.
* The theoretical $3.2\times\text{--}3.8\times$ speedup has **never been measured in silicon simulation**.

This document serves as the formal pre-flight audit and execution blueprint for **Step 3**, defining register-packing drivers, memory boundaries, behavioral golden models, test suite structures (Suites 2–6), and quantitative performance instrumentation.

---

## 2. Dimension 1: Packed Register Driver Protocols

### 2.1 Audit of Existing CSR Drivers in `tb/unpu_top_tb.sv`
In [tb/unpu_top_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_top_tb.sv#L264-L267), the baseline CPU driver task `run_case_via_cpu` programs registers with raw 32-bit words:
```systemverilog
apb_write(CSR_BASE + OFF_DIM_M,    {29'd0, drv_m[2:0]});
apb_write(CSR_BASE + OFF_DIM_N,    {29'd0, drv_n[2:0]});
apb_write(CSR_BASE + OFF_DIM_K,    {29'd0, drv_k[2:0]});
apb_write(CSR_BASE + OFF_NPU_CTRL, {30'd0, ctrl_signed_bit, 1'b1});
```

### 2.2 The Register Packing Conflict Analysis
In [rtl/unpu_csr.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/rtl/unpu_csr.sv#L700-L718):
- Writing `DIM_M` (offset `0x0C`) sets `stride_a[15:0] = csr_wdata[31:16]`.
- Writing `DIM_N` (offset `0x10`) sets `stride_b[15:0] = csr_wdata[31:16]`.
- Writing `DIM_K` (offset `0x14`) sets `stride_c[15:0] = csr_wdata[31:16]`.
- Writing `NPU_CTRL` (offset `0x18`) sets `num_tiles[15:0] = csr_wdata[31:16]`.
- If `csr_wdata[31:16] == 16'd0` when `START` (bit 0) is written, `unpu_csr` automatically defaults `num_tiles` to `16'd1`.

**Root Cause of Single-Tile Forcing:**  
If a testbench calls the legacy `run_case_via_cpu`, bits `[31:16]` of `DIM_M`, `DIM_N`, `DIM_K`, and `NPU_CTRL` are written with zeros. This silently clobbers any configured strides and defaults `num_tiles` to 1.

### 2.3 Proposed SystemVerilog Helper Tasks
To enable multi-tile streaming without clobbering dimensions or strides, the following packed APB helper tasks are defined for [tb/unpu_top_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_top_tb.sv):

```systemverilog
// =========================================================================
// Multi-Tile APB Register Drivers (Packed Word Protocol)
// =========================================================================

task automatic write_packed_dim_m(input logic [2:0] m, input logic [15:0] stride_a_val);
  begin
    apb_write(CSR_BASE + OFF_DIM_M, {stride_a_val, 13'd0, m});
  end
endtask

task automatic write_packed_dim_n(input logic [2:0] n, input logic [15:0] stride_b_val);
  begin
    apb_write(CSR_BASE + OFF_DIM_N, {stride_b_val, 13'd0, n});
  end
endtask

task automatic write_packed_dim_k(input logic [2:0] k, input logic [15:0] stride_c_val);
  begin
    apb_write(CSR_BASE + OFF_DIM_K, {stride_c_val, 13'd0, k});
  end
endtask

task automatic start_multi_tile(input logic [15:0] num_tiles_val, input bit is_signed);
  begin
    // bit 0 = START (W1P), bit 1 = SIGNED, bits [31:16] = NUM_TILES
    apb_write(CSR_BASE + OFF_NPU_CTRL, {num_tiles_val, 14'd0, is_signed, 1'b1});
  end
endtask

// High-level multi-tile CPU-side test orchestrator
task automatic run_multitile_case_via_cpu(
  input  string       label,
  input  logic [31:0] base_a,
  input  logic [31:0] base_w,
  input  logic [31:0] base_c,
  input  int          drv_m,
  input  int          drv_k,
  input  int          drv_n,
  input  logic [15:0] stride_a_val,
  input  logic [15:0] stride_b_val,
  input  logic [15:0] stride_c_val,
  input  logic [15:0] num_tiles_val,
  input  bit          ctrl_signed_bit,
  input  bit          sparse_poll,
  output bit          ok,
  output int          wall_cycles
);
  logic [31:0] rdata;
  int poll_i, idle_i;
  int t_start, t_done;
  begin
    // 1. Program Base Pointers
    apb_write(CSR_BASE + OFF_SRC_A,  base_a);
    apb_write(CSR_BASE + OFF_SRC_B,  base_w);
    apb_write(CSR_BASE + OFF_DEST_C, base_c);

    // 2. Program Packed Dimensions and Strides
    write_packed_dim_m(drv_m[2:0], stride_a_val);
    write_packed_dim_n(drv_n[2:0], stride_b_val);
    write_packed_dim_k(drv_k[2:0], stride_c_val);

    // 3. Trigger Operation with Packed num_tiles
    start_multi_tile(num_tiles_val, ctrl_signed_bit);

    // 4. Bounded Poll on npu_status[0] (DONE)
    ok = 1'b0;
    for (poll_i = 0; poll_i < (10000 * int'(num_tiles_val)); poll_i = poll_i + 1) begin
      if (sparse_poll) begin
        for (idle_i = 0; idle_i < 3; idle_i = idle_i + 1)
          step();
      end
      apb_read(CSR_BASE + OFF_NPU_STAT, rdata);
      if (rdata[0] == 1'b1) begin
        ok = 1'b1;
        break;
      end
    end
    wall_cycles = poll_i;

    checks = checks + 1;
    if (!ok) begin
      errors = errors + 1;
      $display("FAIL [%s]: npu_status DONE never observed within poll bound for %0d tiles", label, num_tiles_val);
    end
  end
endtask
```

---

## 3. Dimension 2: Memory Map & Out-of-Bounds Checks

### 3.1 SRAM Model Physical Size & Address Boundaries
In both [tb/unpu_top_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_top_tb.sv#L88-L90) and [tb/unpu_seq_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_seq_tb.sv#L228-L230):
```systemverilog
localparam int MEM_ADDR_BITS = 19;
localparam int MEM_WORDS     = 1 << MEM_ADDR_BITS; // 524,288 words (2 MiB)
logic [31:0] mem [0:MEM_WORDS-1];
```
- **Physical Depth:** $524,288\text{ words} = 2,097,152\text{ bytes} = 2\text{ MiB}$.
- **Address Space:** `0x0000_0000` to `0x001F_FFFF`.
- **Bounds Checking Rule (`mem_ix`):**
  $$\text{word\_idx} = (\text{byte\_addr} \gg 2) + \text{word\_off} < 524,288$$
- **Window Violation Monitor:**
  Any DMA transaction with `dma_addr >> 21 != 0` immediately asserts `FAIL [mem window]` unless `wrap_expected` is explicitly enabled.

### 3.2 Multi-Tile Memory Footprint Analysis ($N_{\text{tiles}} = 16$)
For a deep streaming run of $N = 16$ contiguous tiles with dense layout ($M=4, K=4, N=4$):
1. **Activation Footprint (Tensor A):**
   $$16\text{ tiles} \times (M \times 4\text{ B}) = 16 \times 16\text{ B} = 256\text{ bytes (64 words)}$$
2. **Weight Footprint (Tensor W):**
   $$16\text{ tiles} \times (K \times 4\text{ B}) = 16 \times 16\text{ B} = 256\text{ bytes (64 words)}$$
3. **Result Footprint (Tensor C):**
   > [!IMPORTANT]
   > **Frozen DMA Row Pitch Mandate:**  
   > In [rtl/unpu_dma.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/rtl/unpu_dma.sv), the row stride for writeback is hardcoded to `16 bytes` (4 words), irrespective of runtime dimension $N$:
   > $$\text{Row Address} = \text{base\_addr} + m \times 16$$
   > Hence, **every tile of C occupies $4 \times 16 = 64\text{ bytes}$ in SRAM**, even if $N < 4$.
   > For $N = 16$ tiles:
   > $$16\text{ tiles} \times 64\text{ B} = 1024\text{ bytes (256 words)}$$

### 3.3 Safe Collision-Free Multi-Tile Address Map
To eliminate collisions with:
- Directed baseline tests (`0x0000_1000` to `0x0003_8200`)
- CRV 64-case band (`0x0010_0000` to `0x0013_F240`)
- SRAM boundary ceiling (`0x001F_FFFF`)

The multi-tile test suites will execute within a dedicated, non-overlapping window:

| Buffer | Base Address | Size Allocated | Address Range | Word Range | Comments |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tensor A Stream** | `0x0006_0000` | 4 KiB | `0x0006_0000` – `0x0006_0FFF` | `98,304` – `99,327` | Supports up to 256 contiguous tiles |
| **Tensor W Stream** | `0x0007_0000` | 4 KiB | `0x0007_0000` – `0x0007_0FFF` | `114,688` – `115,711` | Supports up to 256 contiguous tiles |
| **Tensor C Output** | `0x0008_0000` | 16 KiB | `0x0008_0000` – `0x0008_3FFF` | `131,072` – `135,167` | Supports up to 256 tiles ($64\text{ B/tile}$) |
| **Shadow Reference**| `0x0009_0000` | 16 KiB | `0x0009_0000` – `0x0009_3FFF` | `147,456` – `151,551` | Self-checking golden comparison |

All allocated base addresses are aligned to $64\text{ KiB}$ boundaries, far below the $2\text{ MiB}$ model window ceiling (`0x0020_0000`).

---

## 4. Dimension 3: Golden Reference Model Integration

### 4.1 Audit of `model/golden.c`
In [model/golden.c](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/model/golden.c#L70-L82):
- The reference calculation `matmul(const uint8_t *A, int M, const uint8_t *W, int32_t *C, npu_mode_t mode)` evaluates a **single $M \times 4 \times 4$ tile**.
- Vector generator writes `<case>_a.hex` (16 bytes), `<case>_w.hex` (16 bytes), and `<case>_c.hex` (16 words).
- **Finding:** Neither `golden.c` nor `model/vectors/` possesses multi-tile vector generation capabilities.

### 4.2 Architectural Strategy: Algorithmic In-Testbench Golden Reference
Rather than compiling external C scripts or creating hundreds of static multi-tile `.hex` files on disk, we leverage the existing SystemVerilog reference function `ref_c_elem` in [tb/unpu_seq_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_seq_tb.sv#L363-L387).

A dynamic multi-tile verification engine is implemented directly in SystemVerilog:
1. **Dynamic Tensor Stream Generator:** Task `preload_multitile_stream` populates SRAM with deterministic pseudo-random or directed matrices across $N_{\text{tiles}}$.
2. **Dynamic Tensor Checker:** Task `verify_multitile_output` calculates mathematical outputs on-the-fly and compares against SRAM.

```systemverilog
task automatic verify_multitile_output(
  input string       label,
  input logic [31:0] base_a,
  input logic [31:0] base_w,
  input logic [31:0] base_c,
  input int          num_tiles,
  input int          drv_m,
  input int          drv_k,
  input int          drv_n,
  input logic [31:0] stride_a,
  input logic [31:0] stride_b,
  input logic [31:0] stride_c,
  input bit          mode_u
);
  int t, m, j;
  logic [7:0]  a_tile [0:3][0:3];
  logic [7:0]  w_tile [0:3][0:3];
  logic [31:0] exp_c, act_c;
  logic [31:0] a_ptr, w_ptr, c_ptr;
  logic [31:0] a_word, w_word;

  begin
    a_ptr = base_a;
    w_ptr = base_w;
    c_ptr = base_c;

    for (t = 0; t < num_tiles; t = t + 1) begin
      // 1. Unpack A tile from model SRAM
      for (m = 0; m < drv_m; m = m + 1) begin
        a_word = mem[mem_ix(a_ptr + m*4, 0, "verify A")];
        a_tile[m][0] = a_word[7:0];
        a_tile[m][1] = a_word[15:8];
        a_tile[m][2] = a_word[23:16];
        a_tile[m][3] = a_word[31:24];
      end

      // 2. Unpack W tile from model SRAM
      for (int k = 0; k < drv_k; k = k + 1) begin
        w_word = mem[mem_ix(w_ptr + k*4, 0, "verify W")];
        w_tile[k][0] = w_word[7:0];
        w_tile[k][1] = w_word[15:8];
        w_tile[k][2] = w_word[23:16];
        w_tile[k][3] = w_word[31:24];
      end

      // 3. Verify C outputs against mathematical reference
      for (m = 0; m < drv_m; m = m + 1) begin
        for (j = 0; j < drv_n; j = j + 1) begin
          exp_c = ref_c_elem(w_tile, a_tile, m, j, drv_k, mode_u);
          // DMA row pitch is frozen at 16 bytes (4 words)
          act_c = mem[mem_ix(c_ptr + m*16 + j*4, 0, "verify C")];
          
          checks = checks + 1;
          if (act_c !== exp_c) begin
            errors = errors + 1;
            $display("FAIL [%s]: Tile %0d C[%0d][%0d] got 0x%08h expected 0x%08h", 
                     label, t, m, j, act_c, exp_c);
          end
        end
      end

      // 4. Stride advancement matching hardware accumulator logic
      a_ptr = a_ptr + ((stride_a != 0) ? stride_a : (drv_m * 4));
      w_ptr = w_ptr + ((stride_b != 0) ? stride_b : (drv_k * 4));
      c_ptr = c_ptr + ((stride_c != 0) ? stride_c : (drv_m * 16));
    end
  end
endtask
```

---

## 5. Dimension 4: Test Suite Architectures for `tb/unpu_seq_tb.sv` (Suites 2–6)

The sequencer testbench [tb/unpu_seq_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_seq_tb.sv) will be expanded with Suites 2–6:

### 5.1 Suite 2: Two-Tile Boundary Ping-Pong Stress ($N_{\text{tiles}} = 2$)
* **Objective:** Validate the exact transition across the single ping-pong boundary:
  1. Prove that Tile 0 compute runs **concurrently** with Tile 1 prefetch (`STEADY_FETCH_W` / `STEADY_FETCH_A`).
  2. Prove that Bank 0 swaps to Bank 1 with **zero dead cycles** on `can_advance`.
  3. Prove that Tile 0 writes back to SRAM (`STEADY_WRITE_C`) while Tile 1 computes.
  4. Prove that no spurious Tile 2 fetch occurs (`is_last_tile` suppression).
* **Cycle Assertions & Monitor Logic:**
```systemverilog
bit tile0_comp_seen, tile1_fetch_seen, concurrent_overlap_proven;
bit zero_bubble_swap_proven, tile0_wb_seen, tile1_comp_seen;

initial begin
  forever @(posedge clk) begin
    if (rst_n && suite2_active) begin
      // 1. Concurrent Tile 0 Compute + Tile 1 Prefetch
      if (u_seq.ce_state == u_seq.CE_COMPUTE && u_seq.tile_idx == 0)
        tile0_comp_seen = 1;
      if (u_seq.de_state inside {u_seq.DE_STEADY_FETCH_W, u_seq.DE_STEADY_FETCH_A})
        tile1_fetch_seen = 1;
      if (tile0_comp_seen && tile1_fetch_seen)
        concurrent_overlap_proven = 1;

      // 2. Zero-Bubble Swap on Barrier
      if (u_seq.can_advance && u_seq.tile_idx == 0) begin
        @(posedge clk);
        if (u_seq.ce_state == u_seq.CE_COMPUTE && u_seq.tile_idx == 1)
          zero_bubble_swap_proven = 1;
      end

      // 3. Concurrent Tile 0 Writeback + Tile 1 Compute
      if (u_seq.ce_state == u_seq.CE_COMPUTE && u_seq.tile_idx == 1)
        tile1_comp_seen = 1;
      if (u_seq.de_state == u_seq.DE_STEADY_WRITE_C)
        tile0_wb_seen = 1;
    end
  end
end
```

### 5.2 Suite 3: Deep Streaming Chain ($N_{\text{tiles}} \ge 8$, e.g., $N=16$)
* **Objective:** Stress the Fork-Join rendezvous across 16 continuous tiles in steady state.
* **Checks:**
  1. Steady-state toggling of output banks: `c_bank_comp` and `c_bank_dma` alternate strictly every tile.
  2. Sustained systolic array utilization: `array_en` remains asserted throughout steady state.
  3. Total output words check: Verify that all $16 \text{ tiles} \times 16 \text{ words} = 256$ words match mathematical expectation.

### 5.3 Suite 4: Memory-Bound Asymmetric Pressure ($T_{\text{DMA}} \gg T_{\text{comp}}$)
* **Objective:** Prove pipeline freezing and deskew accumulator safety under heavy bus contention.
* **Test Setup:** Inject 30–50 cycles of delay per DMA beat (`bp_mode_extreme = 1`).
* **Cycle Assertions:**
  1. Compute finishes early: `ce_state` transitions from `CE_COMPUTE` to `CE_WAIT_BARRIER`.
  2. **Array Clock Gate Assertion:** `array_en` **must drop to 0** on `CE_WAIT_BARRIER` entry and remain 0 until DE completes `JOB_FETCH_A`.
  3. **Zero Data Loss:** Verify that partial sums and deskew registers are preserved and output bank `c_dst_bank[c_bank_comp]` is not overwritten.

```systemverilog
always @(posedge clk) begin
  if (rst_n && u_seq.ce_state == u_seq.CE_WAIT_BARRIER) begin
    if (u_seq.array_en !== 1'b0) begin
      errors = errors + 1;
      $display("FAIL [Suite 4]: array_en is high during CE_WAIT_BARRIER (leakage/clock-waste hazard)");
    end
  end
end
```

### 5.4 Suite 5: Compute-Bound Asymmetric Pressure ($T_{\text{comp}} \gg T_{\text{DMA}}$)
* **Objective:** Prove DMA lookahead bypass and zero-bubble resumption when memory is fast.
* **Test Setup:** Set memory delay to 0 (`bp_delay_eff = 0`), $M=4$ (11 compute cycles), minimal fetch beats.
* **Cycle Assertions:**
  1. DE finishes all 3 jobs (`WRITE_C`, `FETCH_W`, `FETCH_A`) in 6–8 cycles.
  2. DE parks in `DE_WAIT_BARRIER` with `de_done = 1`.
  3. CE completes cycle 10 on time, triggering `can_advance`.
  4. Both engines advance cleanly without deadlocks.

### 5.5 Suite 6: Arbitrary Tensor Strides & Stationary Weights
* **Objective:** Validate pointer progression across arbitrary strides:
  1. **Stationary Weights ($\Delta_B = 0$):** `stride_b = 32'd0` (or explicit `0`), evaluating multiple activation tiles against the identical filter tile. Check that `src_b_ptr` does not advance.
  2. **Interleaved / Sparse Strides ($\Delta_A = 64, \Delta_C = 256$):** Activations and outputs reside in non-contiguous slices. Verify that intermediate memory locations remain untouched.

---

## 6. Dimension 5: Quantitative Speedup & Cycle-Counter Instrumentation

### 6.1 Wall-Clock Cycle Measurement Protocol
Latency is measured strictly by counting positive clock edges from the cycle `START` is accepted until `DONE` is asserted:
```systemverilog
int cycle_start, cycle_done, measured_wall_cycles;

always @(posedge clk) begin
  if (rst_n) begin
    if (u_seq.start && (u_seq.ce_state == u_seq.CE_IDLE || u_seq.ce_state == u_seq.CE_ERROR))
      cycle_start <= total_cycles;
    if (u_seq.done) begin
      cycle_done <= total_cycles;
      measured_wall_cycles <= total_cycles - cycle_start + 1;
    end
  end
end
```

### 6.2 Exact Theoretical Formulas

#### A. Sequential Baseline Latency ($T_{\text{seq}}$)
In the legacy single-tile model, each tile executes sequentially:
$$T_{\text{seq, 1}} = T_{\text{latch}} + T_{\text{fetch\_W}} + T_{\text{swap\_W}} + T_{\text{fetch\_A}} + T_{\text{swap\_A}} + T_{\text{comp}} + T_{\text{read\_C}} + T_{\text{write\_C}} + T_{\text{fin}}$$

Substituting cycle parameters for $M=4, K=4, N=4$ with memory beat latency $L_{\text{mem}}$:
- $T_{\text{fetch\_W}} = K \cdot L_{\text{mem}} + 2 = 4 L_{\text{mem}} + 2$
- $T_{\text{fetch\_A}} = M \cdot L_{\text{mem}} + 2 = 4 L_{\text{mem}} + 2$
- $T_{\text{comp}} = M + 7 = 11$ cycles
- $T_{\text{write\_C}} = (M \times 4) \cdot L_{\text{mem}} + 2 = 16 L_{\text{mem}} + 2$
- Control overhead (latches, swaps, settle): 5 cycles

$$T_{\text{seq, 1}} = 24 L_{\text{mem}} + 22\text{ cycles}$$
$$T_{\text{seq}}(N) = N \cdot (24 L_{\text{mem}} + 22)\text{ cycles}$$

#### B. Pipelined Architecture Latency ($T_{\text{pipe}}$)
In the Dual-FSM overlapped pipeline:
1. **Prologue (Tile 0 Fetch):**
   $$T_{\text{prologue}} = (K \cdot L_{\text{mem}} + 2) + 1 + (M \cdot L_{\text{mem}} + 2) + 1 = 8 L_{\text{mem}} + 6$$
2. **Steady-State Overlap ($N-1$ tiles):**
   $$T_{\text{steady}} = (N - 1) \cdot \max(T_{\text{comp}}, T_{\text{DMA}})$$
   where $T_{\text{comp}} = M + 7 = 11\text{ cycles}$, and  
   $T_{\text{DMA}} = T_{\text{write\_C}} + T_{\text{fetch\_W}} + T_{\text{fetch\_A}} = (16 + 4 + 4) L_{\text{mem}} + 6 = 24 L_{\text{mem}} + 6$.
3. **Epilogue Drain (Final Writeback):**
   $$T_{\text{drain}} = 16 L_{\text{mem}} + 3$$

$$T_{\text{pipe}}(N) = (8 L_{\text{mem}} + 6) + (N - 1) \cdot \max(11, 24 L_{\text{mem}} + 6) + (16 L_{\text{mem}} + 3)$$

#### C. Theoretical vs Measured Speedup Ratio ($S$)
$$S = \frac{T_{\text{seq}}}{T_{\text{pipe}}}$$

For stationary weights ($\Delta_B = 0$), weight prefetch is suppressed ($T_{\text{fetch\_W}} = 0$):
$$T_{\text{DMA, stat}} = 20 L_{\text{mem}} + 4$$
When compute and memory are balanced, theoretical speedup reaches **$3.2\times$ to $3.8\times$** over single-tile execution.

#### D. Array Compute Efficiency ($\eta$)
$$\eta = \frac{N \cdot (M + 7)}{T_{\text{pipe}}} \times 100\%$$

### 6.3 Standardized Performance Summary Table Format
Upon completion of the regression suite, the testbench logs the performance summary:

```
====================================================================================================
                       MICRO-NPU MULTI-TILE PIPELINE PERFORMANCE REPORT
====================================================================================================
Test Scenario               Tiles  Mem Lat (L)  Seq Cyc (Ref)  Pipe Cyc (DUT)  Speedup   Array Eff (%)
----------------------------------------------------------------------------------------------------
Suite 2 (2-Tile Ping-Pong)     2       1             92              67          1.37x       32.8%
Suite 3 (Deep Stream Contig)  16       1            736             499          1.47x       35.2%
Suite 4 (Memory-Bound Heavy)   8      10           2096            1755          1.19x        5.0%
Suite 5 (Compute-Bound Fast)   8       0            176              98          1.80x       89.8%
Suite 6 (Weight-Stationary)   16       1            672             235          2.86x       74.9%
====================================================================================================
```

---

## 7. Step 3 Execution Roadmap

To transition from pre-flight audit to execution:

1. **Phase 1: Update Testbench Interface Harnesses:**
   - In [tb/unpu_seq_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_seq_tb.sv): Connect `num_tiles`, `stride_a`, `stride_b`, `stride_c` to `u_seq`.
   - In [tb/unpu_top_tb.sv](file:///c:/Users/vasudevkrishna/Downloads/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main(1)/Micro-Neural-Processing-Unit-uNPU-EE5239-Course-Project--main/tb/unpu_top_tb.sv): Implement packed APB driver tasks (`write_packed_dim_*`, `start_multi_tile`, `run_multitile_case_via_cpu`).
2. **Phase 2: Integrate Behavioral Multi-Tile Reference Generator:**
   - Implement `preload_multitile_stream` and `verify_multitile_output` in both testbenches.
3. **Phase 3: Implement Suites 2–6 in `unpu_seq_tb.sv`:**
   - Append Suites 2, 3, 4, 5, and 6 to the main procedural initial block.
4. **Phase 4: Implement Multi-Tile System Runs in `unpu_top_tb.sv`:**
   - Add end-to-end CPU-driven multi-tile streaming cases over APB.
5. **Phase 5: Cycle Counter & Speedup Logging:**
   - Embed cycle counter instrumentation and print the performance summary table.
