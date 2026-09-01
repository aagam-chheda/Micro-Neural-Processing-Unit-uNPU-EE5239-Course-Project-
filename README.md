# uNPU — Micro Neural Processing Unit

## What is this project?

This is a small hardware chip (called a "module" or "block") whose only job
is to do one thing really fast: **multiply matrices of numbers**, which is
the core math operation neural networks use to make predictions.

Think of it like this: when a neural network recognizes a handwritten digit
or an image, under the hood it's really just doing a huge number of
multiply-and-add operations on grids of numbers. A normal CPU does these
one at a time, which is slow. This chip does *many of them at once, every
single clock tick*, using a special grid-shaped circuit called a
**systolic array**.

## Why is it built this way?

### The big picture: two halves

The chip is split into two halves that work together:

1. **The "control" side** — this is how the main computer (CPU) talks to
   the chip. It's like a small set of switches and dials: "here's your
   data, here's the size of the matrix, now go!"
2. **The "data" side** — this is where the actual number-crunching
   happens. Once the CPU says "go," this side works on its own, pulling
   data from memory and running the calculation.

### The systolic array — the heart of the chip

Imagine a 4x4 grid of tiny calculators (16 total), each one able to
multiply two numbers and add the result to a running total. Data flows
into this grid from the top and left, moves through cell by cell, and
each cell passes its result to its neighbor — a bit like a bucket brigade
passing water buckets down a line.

For this to work correctly, the data can't all enter the grid at the same
time — each row has to be delayed by one extra tick compared to the row
above it, so everything lines up correctly as it flows through. This
staggered entry is called **wavefront alignment**, and a set of small
buffers (FIFOs) are responsible for creating that delay.

The specific strategy used here is called **weight-stationary**: the
"weights" (the numbers the neural network learned during training) get
loaded into the grid once and stay put, while the input data streams
through them. This is efficient when you're reusing the same weights
over and over, which is exactly what happens during real-world use.

### Getting data in and out

A part of the chip called the **DMA engine** (Direct Memory Access) is in
charge of fetching data from memory and sending results back, all on its
own, without needing the CPU to babysit it the whole time.

## The main pieces (sub-modules) of the design

| Piece | What it does, in plain terms |
|---|---|
| **APB Wrapper & Control Registers** | The "front door" — lets the CPU configure and start the chip |
| **DMA Master Engine** | Fetches data from memory automatically |
| **Skewing FIFOs** | Small buffers that delay data just enough so it lines up correctly entering the grid |
| **Processing Element (PE) Core** | One tiny multiply-and-add calculator — the basic building block |
| **2D Systolic Grid** | 16 of those calculators wired together in a 4x4 grid |

## How the CPU actually uses it

The CPU talks to the chip through a handful of registers (like labeled
mailboxes it can write to or read from):

- **NPU_CTRL** — write to this to start the chip, or reset it
- **NPU_STATUS** — read this to check if the chip is done, busy, or hit an error
- **DMA_SRC_ADDR** — tells the chip where in memory to read the input data from
- **DMA_DST_ADDR** — tells the chip where in memory to write the results
- **MATRIX_CFG** — tells the chip the size of the matrix (how many rows and columns)

In short, the CPU sets these values, hits start, and then just waits
(checking NPU_STATUS occasionally) until the chip signals it's done.

## How do we know it actually works? (Testing)

Two simple but clever tests are used to catch two different kinds of bugs:

1. **The Identity Test** — multiply a matrix of increasing numbers by an
   "identity matrix" (a special matrix that, mathematically, doesn't
   change anything it's multiplied by). If the chip's timing and wiring
   are correct, the output should come out *exactly* the same as the
   input. If it doesn't, it means the data isn't lining up correctly as
   it flows through the grid.
2. **The Saturation Test** — multiply the largest possible numbers
   (0xFF, or 255) together, repeatedly. This checks whether the chip's
   internal "running total" registers are big enough to hold the result
   without overflowing (wrapping around and giving a wrong answer).

After these, there's also a full real-world test: running actual
firmware on a companion RISC-V processor to make the chip recognize a
real handwritten digit (from the MNIST dataset), to prove the whole
system works together end to end.

## The physical chip side (not just code)

Once the design works in simulation, it also has to be turned into an
actual physical layout — deciding exactly where every wire and transistor
sits on the silicon. This includes:

**Floorplanning**: Arranging the grid and memory interfaces efficiently on silicon.  
**Power Distribution**: Designing a power grid (PDN) robust enough to feed 16 multipliers firing simultaneously.  
**Routing**: Untangling the massive wire congestion inherent to a highly-connected 2D systolic array.  
**Timing Analysis**: Ensuring electrical signals travel through the multipliers fast enough to hit our target clock speed (which sometimes requires adding pipeline registers to break up long paths). 

## Status

This project is a WIP(work in progress). RTL (the actual digital circuit
design) is being built and tested first; the physical chip layout work
happens after the design is verified to work correctly.
