# uNPU — Questions to settle with the PM

**Project 2 · Micro Neural Processing Unit · Frankenstein 180 nm IP-Validation SoC**

Meeting date: ______________  Attendees: ______________________________

Bring a proposed answer to every question. A meeting where you ask thirteen open
questions goes badly; a meeting where you propose thirteen answers and ask for
approval goes fast.

Questions are ordered by **when they block work**, not by importance.

---

## Ask first — these block RTL on Monday

### Q1. Do we have to handle matrices larger than 4×4?

`MATRIX_CFG` gives 16 bits each to Rows and Columns, far more than a 4×4 array
needs. But every required test is 4×4 and the sample firmware writes
`0x00040004`.

This is the biggest question on the list. Tiling means a much larger sequencer,
K-accumulation storage, and roughly double the verification matrix — 60 to 80
person-hours on a 400-hour budget.

**Our proposal:** 4×4 only for the required deliverables, with tile counters
stubbed in the RTL so we can extend if there is time.

- [ ] Answered — Answer: ______________________________________________
- Blocks: sequencer design, verification plan, the entire schedule buffer

---

### Q2. Signed or unsigned INT8?

The saturation test multiplies `0xFF` by `0xFF`. If the PE treats `0xFF` as
signed −1, that test computes `4` instead of `260,100` — it would pass on a
4-bit accumulator. It passes for entirely the wrong reason.

**Our proposal:** signed by default, since real quantised networks use signed
symmetric weights. Add a mode bit so the saturation test can run in both modes.

- [ ] Answered — Answer: ______________________________________________
- Blocks: PE multiplier RTL (week 1)

---

### Q3. Can we add registers inside our own 4 KB window?

Two gaps in the specified map:

- `MATRIX_CFG` carries Rows and Columns, but a matmul needs three dimensions.
  There is nowhere to put K.
- `DMA_SRC_ADDR` is one pointer for two input tensors, weights and activations.

**Our proposal:** all five specified offsets stay exactly where they are. Add
`ACT_ADDR` at `0x14` and `NPU_CFG2` at `0x18` (K, SIGNED, OUT_INT8). Nothing
outside the macro sees any difference, so we read this as microarchitectural
rather than a memory-map change.

**Fallback if refused:** a fixed `[weights][activations]` block layout, so the
activation base is `SRC + K*N`. It works and costs no registers, but it is much
easier for firmware to get wrong.

- [ ] Answered — Answer: ______________________________________________
- Blocks: CSR file, firmware header (week 1)

---

### Q4. What clock frequency are we constrained to?

Never stated in the brief, but "macro-level STA signoff ensuring all internal
multiplication pipelines meet the target clock frequency constraints" is a
deliverable.

It also decides whether the PE needs two-stage pipelining. That is not a local
change: registering the product forces a matching register on the activation
forwarding path, which changes the skew depths from 0/1/2/3 to 0/2/4/6 and
changes every number in the timing contract.

**Our proposal:** a conservative target for the first pass, revisited only after
the identity test passes on gates. A working slow macro beats a broken fast one.

- [ ] Answered — Answer: ______________________________________________
- Blocks: all back-end work from week 5

---

## Same meeting — the Project 1 interface contract

These need Project 1 in the room, or a written interface document afterwards.
**Get 5, 6 and 7 in writing.** Verbal agreement on bus timing is how two teams
end up each confident they are right while nothing works, in week 7, with no
time to find out which of them moved.

### Q5. How is read versus write encoded on the DMA port?

There is no direction pin in `unpu_top`.

**Our proposal:** `dma_wstrb == 4'b0000` means read, anything else means write.

- [ ] Answered — Answer: ______________________________________________
- Blocks: DMA handshake FSM (week 3)

---

### Q6. When is `dma_rdata` valid?

Same cycle as `dma_valid & dma_ready`, or the cycle after? There is no `rvalid`.
Both teams will assume, and they will assume differently, and every read will be
off by one word.

**Our proposal:** same cycle. If the SRAM needs a cycle, the arbiter holds
`ready` low for it.

- [ ] Answered — Answer: ______________________________________________
- Blocks: DMA handshake FSM (week 3)

---

### Q7. Is the data plane native or AHB?

The top-level block diagram labels it "Native/AHB Data Plane", but the port list
we were given is plain valid/ready with no AHB signals. If Project 1 is building
an AHB fabric, our master needs `HTRANS`, `HSIZE` and the rest — a substantially
different interface.

- [ ] Answered — Answer: ______________________________________________
- Blocks: DMA architecture. Could invalidate week 3 work entirely

---

### Q8. What is the worst-case grant latency from the SRAM arbiter?

The array consumes exactly one 32-bit word per cycle at full rate, so we want
100% of the SRAM port — while competing with a cacheless PicoRV32 fetching
almost every cycle, plus the SPI controller.

We need an agreed maximum so we can size our DMA timeout above it. Otherwise we
raise ERROR on normal contention.

- [ ] Answered — Answer: ______________________________________________
- Blocks: timeout sizing, ERR_CODE definition (week 3)

---

### Q9. How does the BIST FSM reach our macro?

Project 1's brief says the BIST FSM "runs autonomous diagnostic patterns on the
SRAM and hard macros to verify manufacturing integrity post-fabrication,
completely independent of the software stack."

If that is over APB, we need to agree a self-test register sequence with them and
make sure it leaves no state behind. If it is a dedicated test port, that is pins
we do not currently have.

- [ ] Answered — Answer: ______________________________________________
- Blocks: register map, port list request in Q10

---

## Can wait until week 3

### Q10. Can we add pins?

Specifically `scan_en`, `scan_in`, `scan_out`. DFT is not mentioned anywhere in
the brief and there are no scan ports in the given port list — but a macro that
cannot be scan-tested cannot be tested on a tester, and the BIST FSM implies
somebody expects post-fabrication structural test.

Also worth deciding here: do you want an interrupt output (`npu_irq`), or is the
polling loop in the sample firmware the intended model?

**Timing matters.** Adding pins after the macro is hardened means re-hardening
it. This must close before floorplan, not after.

- [ ] Answered — Answer: ______________________________________________
- Blocks: floorplan (week 5)

---

### Q11. What MNIST network, and does it fit in 32 KB?

A textbook 784→64→10 classifier needs 784 × 64 = 50,176 INT8 weights for the
first layer alone. That is 49 KB. The whole SoC has 32 KB of SRAM, shared with
firmware `.text`, `.data`, stack, and our buffers. **The reference network does
not fit.**

Also unresolved: the uNPU block diagram says "CNN RISC-V Firmware" but the brief
text says only "quantized MNIST digit". A convolution needs an im2col transform
on the CPU, which is real work and real SRAM.

And: is requantisation (INT32 accumulator back to INT8) our hardware's job or the
firmware's? The brief never mentions it. A hardware requantiser is roughly 10% of
our macro area.

**Our proposal:** a shrunk fully-connected net (784→16 fits in 12.5 KB and still
reaches roughly 92%), or a downsampled 14×14 input. Requantisation in firmware
for v1.

- [ ] Answered — Answer: ______________________________________________
- Blocks: firmware, SRAM memory map (week 3)

---

### Q12. Which tools for DRC, LVS, formal equivalence and IR drop?

We have Xcelium, Genus, Tempus and IC Compiler. None of those does DRC or LVS
signoff, and a DRC/LVS-clean GDSII is an explicit deliverable. Nothing for
formal equivalence after synthesis or dynamic IR analysis either.

- [ ] Answered — Answer: ______________________________________________
- Blocks: signoff planning (week 7)

---

### Q13. Output format — raw INT32 or packed INT8?

Changes write-back traffic by 4× and the output buffer size.

**Our proposal:** support both. INT32 for the required identity and saturation
tests, packed INT8 for the MNIST run.

- [ ] Answered — Answer: ______________________________________________
- Blocks: output packer, RTL freeze (week 4)

---

## Summary tracker

| # | Question | Owner | Due | Status |
|---|---|---|---|---|
| 1 | Tiling beyond 4×4 in scope? | | W1 | |
| 2 | Signed or unsigned INT8? | | W1 | |
| 3 | Can we add registers in our window? | | W1 | |
| 4 | Target clock frequency? | | W1 | |
| 5 | Read/write encoding on DMA port | | W1 | |
| 6 | When is `dma_rdata` valid? | | W1 | |
| 7 | Native or AHB data plane? | | W1 | |
| 8 | Worst-case arbiter grant latency | | W3 | |
| 9 | How does BIST reach us? | | W3 | |
| 10 | Can we add scan pins / interrupt? | | W3 | |
| 11 | MNIST network shape and fit | | W3 | |
| 12 | Tools for DRC, LVS, formal, IR | | W3 | |
| 13 | Output format INT32 or INT8? | | W3 | |

---

## After the meeting

1. Record every answer in §14 of the design notebook (decision log), with the
   date and who gave it.
2. Move each answered item out of §13 (open questions) and rewrite it as a
   `[SPEC]` or `[DECIDED]` block in the relevant section.
3. For Q5, Q6 and Q7, produce a one-page shared interface document and get
   Project 1 to sign it. Do not rely on meeting notes.
4. If Q1 comes back as "no tiling", update the §16 hour budget — the schedule
   buffer goes from roughly 4% to 20% and several things become optional rather
   than urgent.
