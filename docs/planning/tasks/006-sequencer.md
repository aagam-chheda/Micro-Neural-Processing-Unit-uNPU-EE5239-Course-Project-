# Task 006 — Sequencer FSM

## Goal

Build `unpu_seq`, the main control FSM that drives a full weight-load →
input-load → compute → readback → writeback pass over the (already
verified) skew → grid → de-skew datapath, for any legal M, N, K (each
1–4), and prove it against the golden model plus the CLAUDE.md timing
contract — directed cases at the shape boundaries, plus CRV.

This task has two parts: a small, backward-compatible extension to the
golden model (new shapes + CRV case generation), then the `unpu_seq` RTL
and its testbench.

## Two resolutions from the user, binding for this task

1. **`LATCH_CFG` and `ERROR` stay in the FSM**, beyond the PM's own 7-state
   sketch (`docs/pm/sequencer-fsm.txt`). This is additive, not a fork — it
   doesn't touch any interface, and `error`/`error_code` exist so a later
   task can wire them into `npu_status` (step 12+). Not blocking on PM
   confirmation; the user will mention it to the PM in passing, as an FYI,
   not a pending question. Build both states as specified below.

2. **The one-cycle-early trap gets a specific check, not just a general
   timing-contract check.** The injection condition (which row of `A` to
   present) and the COMPUTE-exit condition (when to stop) must read the
   *same* registered counter — not two independently incremented ones.
   Both a code-level requirement and a black-box differential test for
   this are specified below; do not skip either.

## A correction to the PM's sketch, found while writing this task

The PM's own FSM sketch (`docs/pm/sequencer-fsm.txt`) says COMPUTE "stop[s]
after `M+K+N-2` cycles." `docs/session-handoff.md` §13 verified this
formula against the passing `cross_terms` case (M=K=N=4): both the
formula and the timing contract give cycle index 10. **That agreement is
coincidental to K=N=4 and does not generalize.** Do not implement
`M+K+N-2` literally — it will pass the full-4×4 regression case and then
silently under-count (stop compute too early, dropping rows) for every
K<4 or N<4 case this task is required to cover.

Why: the skew bank's depths are 0/1/2/3 **by physical row position**
(`unpu_skew.sv`, rows 0–3), and the de-skew bank's depths are 3/2/1/0 **by
physical column position** (`unpu_deskew.sv`, columns 0–3) — both fixed at
hardware-build time, not parameterized by runtime K or N. That is exactly
what `docs/session-handoff.md` §6 already states: sub-4 K/N causes "no
change to the timing contract or skew/de-skew depths." So the pipeline
latency from presenting row `m` of `A` to that row's `C[m][*]` becoming
valid at de-skew is **always** `m+7` — the CLAUDE.md contract, literally,
independent of K and N. `M+K+N-2` only equals `(M-1)+7` when `K+N=8`, i.e.
only at the full 4×4 case.

**Use this instead**, derived directly from the CLAUDE.md contract, no PM
re-confirmation needed (this is an implementation-correctness derivation
from already-answered facts, not a new open question): a single registered
cycle counter, call it `cycle`, reset to 0 on entering COMPUTE, incrementing
once per clock while in COMPUTE:

- inject row `m = cycle` of `A` into `a_raw` while `cycle < dim_m`
- capture `c_dst[cycle-7] <= c_in` (the currently-streaming row from
  de-skew) whenever `cycle >= 7`
- leave COMPUTE (→ READ_OUTPUT) the cycle `cycle == dim_m + 6` is reached
  (that capture also happens that same cycle — it's row `dim_m-1`, the last
  one)

This makes COMPUTE last exactly `dim_m + 7` cycles (`cycle` takes values
`0` through `dim_m+6` inclusive), matching the contract's literal "total
cycles for a pass of M rows: `M+7`" line, and — critically — **it does not
depend on K or N at all**. That independence is exactly what task 006's
acceptance tests below check for directly.

## The timing contract (CLAUDE.md, quoted)

```
A[m][k] enters west edge of row k     at cycle  m + k
A[m][k] arrives at PE(k,j)            at cycle  m + k + j
C[m][j] leaves south edge of column j at cycle  m + j + 4
whole row C[m][*] valid after de-skew at cycle  m + 7
total cycles for a pass of M rows              M + 7
```

## Part A — golden model extension

### Files

Edit `model/golden.c` only. Do not touch `rtl/`, `tb/`, or anything else in
this part.

### Why new cases are needed

Every existing case (`identity`, `all_ones`, `cross_terms`,
`random_signed`, `random_unsigned`) is full 4×4 — M=4, and `K`/`J` are the
file's fixed `#define`s of 4. None of them exercise K<4 or N<4, which is
exactly what `unpu_seq` needs to get right (zero-padding, and the
K/N-independent COMPUTE-length property above).

`matmul()` itself does **not** need to change. It already takes runtime
`M`; feed it `A`/`W` arrays that are zero-padded outside the true
`M×K`/`K×N` submatrix (rows/columns beyond the real K or N set to 0) and it
produces the right answer for free — a zero weight nulls the product
regardless of the paired activation, same reasoning as the existing "no
change to skew/de-skew depths" argument above. So this part is new case
data plus new case-generation calls, not new arithmetic.

### New directed cases

Add these, same `generate_case`-style flow, same self-check-before-write
discipline (if a self-check fails, exit nonzero, write nothing — matching
every existing case):

- `seq_m1` — M=1, K=4, N=4
- `seq_k1` — M=4, K=1, N=4 (only row 0 of `W` nonzero; zero the rest of `W`
  **and** the corresponding columns of `A` for clarity, even though the
  zero weight alone already nulls those products)
- `seq_n1` — M=4, K=4, N=1 (only column 0 of `W` nonzero, rest zeroed)
- `seq_mixed` — M=3, K=2, N=3 (the non-square, non-multiple-of-4-in-every-
  dimension case; plan.md step 8 asks for this explicitly)

Pick your own small, distinct, nonzero values for each (avoid all-ones/
identity-style patterns — this task isn't re-testing wiring, `cross_terms`
already covers that). These four don't need a hand-computed table; `matmul()`
is already a validated oracle (proven by `identity`/`all_ones`/`cross_terms`'s
hand-checks) — self-check by calling `matmul()` and trusting it directly,
same precedent as the existing `random_signed`/`random_unsigned` cases.

### Meta-file format — append, don't reorder (compatibility requirement)

`write_meta` currently writes exactly:
```
M=<int>
MODE=<SIGNED|UNSIGNED>
```
`tb/unpu_stall_tb.sv` parses this with `$fscanf(fd, "M=%d\nMODE=%s\n", ...)`
and stops reading there — it never looks past line 2. **Extend `write_meta`
to append two more lines after `MODE=`, not before it:**
```
M=<int>
MODE=<SIGNED|UNSIGNED>
K=<int>
N=<int>
```
Update every existing call site (`identity`, `all_ones`, `cross_terms`,
`random_signed`, `random_unsigned`) to pass `K=4, N=4` (the file's existing
`K`/`J` macros). Because the new lines are appended after, not inserted
before, `MODE=`, `unpu_stall_tb.sv`'s existing parse is untouched and keeps
working on the regenerated files — verify this by re-running
`unpu_stall_tb` after this change and confirming it still passes (same
`cross_terms`, unrelated to this task's own RTL). This is the reason the
format changes this way instead of adding a second parser/writer function.

### CRV case generation

Add a case-generation pass producing at least 64 pseudo-random cases,
`crv_0000` .. `crv_0063` (zero-padded index, four digits), each:

- one running `xorshift32` state seeded from `32'h5eed0006` (continuing the
  project's per-task seed convention — task 005 used `32'h5eed0005`)
- draws `M`, `K`, `N` independently, each uniform in `1..4`
- draws `MODE` (signed/unsigned) per iteration too — not required by the
  plan.md CRV spec for this step, but cheap extra coverage of
  `mode_unsigned`'s latch/passthrough path, unique to this module
- fills `A`/`W` with full 0x00–0xFF-range random bytes, zero-padded outside
  the true `M×K`/`K×N` submatrix, same convention as the directed cases
  above
- self-checks via `matmul()` (already-trusted oracle, no hand-derived
  table — same precedent as `random_signed`/`random_unsigned`)
- writes `crv_<idx>_{a,w,c}.hex` + `crv_<idx>_meta.txt` (new 4-line format)

Print the base seed once (`$5eed0006` style, matching task 005's
`$display` convention) before generating the batch, and a final count
summary line after.

### Acceptance (Part A)

- `model/golden.c` still compiles clean (`gcc -std=c99 -Wall -Wextra`).
- All five existing cases plus `seq_m1`/`seq_k1`/`seq_n1`/`seq_mixed` plus
  64 `crv_*` cases self-check clean and get written.
- Re-running the tool is deterministic — identical files byte-for-byte
  across runs (same seeds).
- `tb/unpu_stall_tb.sv` still passes unmodified against the regenerated
  `cross_terms_meta.txt` (proves the append-only format change is safe).

## Part B — `unpu_seq` RTL and testbench

### Files

- Create `rtl/unpu_seq.sv`
- Create `tb/unpu_seq_tb.sv`

Do not modify `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`, or
`rtl/unpu_deskew.sv` — all four are frozen from prior tasks.

### Interface

`unpu_seq` is control-only — it does **not** instantiate `unpu_skew`/
`unpu_grid`/`unpu_deskew` itself (that's `unpu_top`'s job, step 14). This
task's testbench wires it to those three directly, the same way
`tb/unpu_skew_tb.sv` and `tb/unpu_stall_tb.sv` already do.

```systemverilog
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
```

`unpu_grid`'s `psum_in` (north edge) is tied to 0 by the testbench for the
whole run, same as `tb/unpu_stall_tb.sv` — no accumulation across passes,
out of scope.

### FSM states

Nine states, `enum` per CLAUDE.md's synthesisable-subset rule:
`IDLE`, `LATCH_CFG`, `LOAD_WEIGHTS`, `LOAD_INPUT`, `COMPUTE`,
`READ_OUTPUT`, `WRITE_OUTPUT`, `DONE`, `ERROR`.

1. **`IDLE`** — `array_en=0`. On `start`: → `LATCH_CFG`.
2. **`LATCH_CFG`** — check `dim_m`, `dim_n`, `dim_k` are each in `1..4`. If
   any is out of range: latch `error<=1`, `error_code<=3'd1` → `ERROR`.
   Otherwise latch `m_lat<=dim_m`, `k_lat<=dim_k`, `n_lat<=dim_n`,
   `mode_lat<=mode_unsigned` (a shadow copy, so a caller changing `dim_*`
   mid-run can't corrupt an in-flight op — this is the "config
   legality/shadow-copy" rationale the plan referenced from notebook §7.1)
   → `LOAD_WEIGHTS`.
3. **`LOAD_WEIGHTS`** — `array_en=1`. Pulse `weight_load[row][col]=1` for
   all 16 `(row,col)` simultaneously for exactly one cycle, `weight_in =
   w_src` (direct forcing over the whole 4×4 grid every run — the
   shift-down, double-buffered network is `unpu_wbuf`, step 9, out of
   scope here; this is deliberately 1 cycle, not the eventual 4-cycle
   hidden swap). **Known trap:** `unpu_pe.sv`'s weight latch only fires
   when `array_en` and `weight_load` are both 1 on the same cycle
   (`else if (array_en) begin if (weight_load) weight_reg <= weight_in;
   ... end`) — assert `array_en=1` on the exact cycle `weight_load` pulses,
   not before or after. → `LOAD_INPUT`.
4. **`LOAD_INPUT`** — `array_en=1`, no datapath action this task (input is
   already fully present in `a_src`; this state exists for FSM-shape
   parity with the PM's sketch and becomes load-bearing once
   `unpu_actbuf`/`unpu_dma` exist and input must actually stream in before
   compute can start). Reset `cycle<=0` on the transition out. → `COMPUTE`.
5. **`COMPUTE`** — `array_en=1`. Single registered counter `cycle`,
   incrementing once per clock, starting at 0:
   - `a_raw <= (cycle < m_lat) ? a_src[cycle] : '0`
   - `if (cycle >= 7) c_dst[cycle-7] <= c_in`
   - `if (cycle == m_lat + 6) → READ_OUTPUT` (same cycle also does the
     `cycle>=7` capture above, for row `m_lat-1`)
   - else `cycle <= cycle + 1`, stay in `COMPUTE`

   **This is the one-cycle-early-trap requirement (user's resolution #2):**
   the injection mux (`cycle < m_lat`) and the exit check
   (`cycle == m_lat + 6`) must read the exact same `cycle` register. Do not
   implement this as an injection index that free-runs independently of a
   separate down-counter or done-flag used only for the exit transition —
   see "Acceptance (Part B)" below for the specific test that catches this
   if done wrong.
6. **`READ_OUTPUT`** — `array_en=1`, one cycle, no datapath action in this
   task (real read-side backpressure/timing is a DMA-era concern, step 10;
   this state exists for the same FSM-shape-parity reason as
   `LOAD_INPUT`). → `WRITE_OUTPUT`.
7. **`WRITE_OUTPUT`** — `array_en=1`, one cycle, no datapath action in this
   task (no DMA yet to burst `c_dst` out to SRAM — that's step 10).
   → `DONE`.
8. **`DONE`** — `array_en=0`. `done=1` for exactly this one cycle.
   → `IDLE` automatically the next cycle (no separate ack needed).
9. **`ERROR`** — `array_en=0`. `error` and `error_code` hold. On `start`:
   re-attempt `LATCH_CFG` (this also clears `error` optimistically — it's
   re-set immediately if the new config is still illegal).

Reset (`rst_n=0`, async): state → `IDLE`, `cycle<=0`, `done<=0`,
`busy<=0`, `error<=0`, `error_code<=0`, `c_dst<='0`.

### Testbench (`tb/unpu_seq_tb.sv`)

Instantiate `unpu_seq` + `unpu_skew` + `unpu_grid` + `unpu_deskew`, wired
as the port table above specifies (`unpu_seq`'s `array_en`/`weight_load`/
`weight_in`/`a_raw` outputs drive the datapath modules' matching inputs;
`unpu_deskew.c_out` feeds back into `unpu_seq.c_in`; `unpu_grid.psum_in`
tied to 0). Load each case's `a_src`/`w_src` from its `_a.hex`/`_w.hex`
(these are already 4×4-shaped and zero-padded per Part A), drive
`dim_m`/`dim_n`/`dim_k`/`mode_unsigned` from the case's known shape (pass
these as explicit test-writer-supplied values per case — don't parse them
back out of `_meta.txt`'s new `K=`/`N=` lines; you already know what shape
each case is since you're the one selecting which case to run), pulse
`start`, wait for `done`, check `c_dst[m][j]` for `m < dim_m, j < dim_n`
against the case's `_c.hex`.

### Acceptance (Part B)

**Directed:**
- `cross_terms` (M=K=N=4) passes — regression anchor, reuses the existing
  oracle.
- `seq_m1`, `seq_k1`, `seq_n1`, `seq_mixed` each pass, checked over their
  true `M×N` submatrix.
- Illegal-config case: at least one of `dim_m=0`, `dim_m=5`, `dim_k=0`,
  `dim_n=5` (cover more than one field across the directed set) → confirm
  `error=1`, `error_code==3'd1`, `done` never pulses, and a legal `start`
  immediately afterward runs and completes correctly (FSM doesn't get
  stuck in `ERROR`).
- **COMPUTE-length check:** for at least `dim_m=1` and `dim_m=4`, count
  clock edges from entering `COMPUTE` (first cycle `cycle==0` is visible)
  to the edge that transitions to `READ_OUTPUT`; assert it equals exactly
  `dim_m + 7`, matching the contract's "total cycles for a pass of M rows:
  `M+7`" line literally.
- **The one-cycle-early differential check (user's resolution #2, required,
  not optional):** run the same `dim_m` (e.g. 4) through at least two
  different `(dim_k, dim_n)` pairs (e.g. `K=4,N=4` and `K=1,N=1`) and
  assert the total elapsed cycle count from `start` to `done` is
  **identical** across both. This is what actually catches the `M+K+N-2`
  bug class from the correction above — a wrong implementation would pass
  the `M=K=N=4` regression case and only fail here.

**Plus CRV**, per the methodology in `docs/planning/plan.md`: run all 64
`crv_*` cases generated in Part A through `unpu_seq`, checking `c_dst`
against each case's `_c.hex` over its true `M×N` submatrix, self-checked,
with the seed printed once at the top of the run. Within this same loop,
extend the K/N-independence check above: for any two `crv_*` cases that
happen to share the same `dim_m` but different `(dim_k, dim_n)`, assert
matching total start→done cycle counts (opportunistic — don't force extra
iterations just to guarantee pairs exist, but log a count of how many
comparable pairs were found and checked).

- Regression: `unpu_pe_tb`, `unpu_grid_tb`, `unpu_skew_tb`, `unpu_stall_tb`
  still pass unchanged (confirms `unpu_pe.sv`/`unpu_grid.sv`/
  `unpu_skew.sv`/`unpu_deskew.sv` untouched and the Part A meta-format
  change didn't break `unpu_stall_tb`'s parser).
- Simulate clean (Icarus/Verilator — note which, same convention as prior
  tasks). File headers note simulator used.

## Out of scope

- No `unpu_wbuf`/`unpu_actbuf` (step 9) — weights and activations are
  still direct-forced from `a_src`/`w_src`, not a shift-down network.
- No `unpu_dma` (step 10) — no SRAM bursting; `READ_OUTPUT`/`WRITE_OUTPUT`
  are structural placeholders in this task.
- No CSR/`npu_status` wiring (step 12+) — `error`/`error_code` are plain
  outputs; mapping them into the register map is a later task, per the
  user's resolution #1 above.
- No `array_en` external-stall testing here — that property was already
  proven at the skew/grid/de-skew level in step 7 (`tb/unpu_stall_tb.sv`);
  this task doesn't need to re-prove it, though `unpu_seq`'s own
  `array_en` output should still gate correctly per the FSM description
  above.
- Don't touch `rtl/unpu_pe.sv`, `rtl/unpu_grid.sv`, `rtl/unpu_skew.sv`,
  `rtl/unpu_deskew.sv`, or `tb/unpu_stall_tb.sv`.
