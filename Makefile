# ---- tools -------------------------------------------------------------------
VERILATOR ?= verilator
CC        ?= gcc
VFLAGS    ?= --binary --timing -Wno-fatal -Wno-PINMISSING -Wno-TIMESCALEMOD -j 0

RTL  := $(wildcard rtl/*.sv)
TBS  := $(notdir $(basename $(wildcard tb/*_tb.sv)))

.PHONY: all test vectors lint clean $(TBS)

all: test

# ---- golden model and reference vectors --------------------------------------
model/golden: model/golden.c
	$(CC) -std=c99 -Wall -Wextra -o $@ $<

model/vectors/.stamp: model/golden
	./model/golden > /dev/null && touch $@

vectors: model/vectors/.stamp

# ---- one testbench:  make unpu_csr_tb ----------------------------------------
$(TBS): %: model/vectors/.stamp
	$(VERILATOR) $(VFLAGS) --top-module $@ --Mdir obj_dir/$@ $(RTL) tb/$@.sv
	./obj_dir/$@/V$@

# ---- the whole regression ----------------------------------------------------
test: $(TBS)

# ---- whole-design lint -------------------------------------------------------
lint:
	$(VERILATOR) --lint-only -Wall -Wno-GENUNNAMED -Wno-PINMISSING -Wno-TIMESCALEMOD --top-module unpu_top $(RTL)

clean:
	rm -rf obj_dir verilator_out model/golden model/golden.exe model/vectors/.stamp
