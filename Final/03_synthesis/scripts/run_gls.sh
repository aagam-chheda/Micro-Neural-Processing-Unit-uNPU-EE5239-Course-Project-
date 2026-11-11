#!/usr/bin/env bash
# Gate-level simulation of a synthesised clean-name netlist with Xcelium (task 059; replaces the hand-typed xrun lines of syn/RUNBOOK.md step 6).
#
# Usage (from the repo root; works from csh too: `bash scripts/run_gls.sh syn16 sdf`):
#   bash scripts/run_gls.sh <syn16|syn18|syn20> [sdf|nosdf]        (default: sdf)
#   csh, all three profiles in one line (csh has no one-line foreach):
#     bash scripts/run_gls.sh syn16 sdf ; bash scripts/run_gls.sh syn18 sdf ; bash scripts/run_gls.sh syn20 sdf
#
# What it runs: the testbench tb/unpu_top_tb.sv (DUT instance `dut`) against syn/out/<profile>/unpu_top_cn.dc.v and the SCL simulation model.
#   - THE CELL MODELS HAVE ZERO DELAY. tsl18fs120_scl.v has every specparam = 0 (checked by the user on the server, task 059): without an SDF
#     the run is a ZERO-DELAY gate simulation, whatever the testbench clock is. Cell and wire delays exist in a simulation only through an SDF.
#   - mode `sdf` (default): the SDF written by the DC script (syn/out/<profile>/unpu_top_cn.sdf) is back-annotated onto the instance
#     unpu_top_tb.dut through an sdf command file. The clock is the real 20 ns (GLS_CLK_HALF_NS=10): the PE path is 14.7 ns at syn16, so the
#     clock matters once delays exist. Pre-layout SDF: cell delays and DC's wire-load-model net delays, no extracted wires.
#   - mode `nosdf`: zero-delay gate simulation (no SDF, same clock define). Use it to separate a netlist/simulation problem from a delay problem.
# Outputs: syn/out/gls_sdf_<profile>.log (sdf) or syn/out/gls_<profile>.log (nosdf) and, for sdf, syn/out/gls_sdf_<profile>.cmd; NOTHING is
# written into syn/out/<profile>/ (the DC output check wants exactly the 15 files there).
#
# Verdict (printed, and the exit status): PASS only if the log has "ALL CHECKS PASSED", no FAIL line, no *E,/*F, and exactly EXPECT_CHECKS
# (343,341: the number of checks of this testbench, equal in the RTL run) "checked N value(s)/assertion(s) total". The first 5 FAIL lines are printed.
#
# Environment: GLS_MODEL (cell model file; default is the kit path below), GLS_CLK_HALF_NS (default 10), XRUN_FLAGS (extra xrun flags, word-split).
# VERIFY (xrun/Xcelium options not read from a usage text here): -define NAME=value, -sdf_cmd_file with `SDF_FILE = "..", SCOPE = ..;` (an
# uncompiled SDF is compiled by the elaborator; the alternative is `xmsdfc` + COMPILED_SDF_FILE), -sdf_verbose, and that -notimingchecks does not
# switch off SDF delay annotation (it disables the $setup/$hold/$recovery/$width checks that the models DO contain, with real numbers, e.g. dfcrq1 tsu_d_h_cp=0.14; those checks would turn flop outputs to X through the models' notifier). Each of them is printed in the log header.
# Exit status: 0 = PASS, 1 = FAIL, 2 = usage / environment problem.

set -u

# ---- parameters, each with its source ----
GLS_MODEL_DEFAULT=/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v   # single combined model file (handoff 18.7)
EXPECT_CHECKS=343341        # checks of tb/unpu_top_tb.sv, handoff 18.7/18.8, equal in the RTL run (Verilator and Xcelium)
DUT_SCOPE=unpu_top_tb.dut   # tb/unpu_top_tb.sv line `unpu_top dut (`
VALID="syn16 syn18 syn20"

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "run_gls.sh: cannot cd to the repo root" >&2; exit 2; }

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 2; fi
P="$1"; MODE="${2:-sdf}"
ok=0; for v in $VALID; do [ "$P" = "$v" ] && ok=1; done
[ "$ok" -eq 1 ] || { echo "run_gls.sh: unknown profile '$P' (valid: $VALID)" >&2; exit 2; }
case "$MODE" in sdf|nosdf) ;; *) echo "run_gls.sh: mode must be sdf or nosdf, not '$MODE'" >&2; exit 2 ;; esac

MODEL="${GLS_MODEL:-$GLS_MODEL_DEFAULT}"
HALF="${GLS_CLK_HALF_NS:-10}"
case "$HALF" in ''|*[!0-9]*) echo "run_gls.sh: GLS_CLK_HALF_NS='$HALF' is not a positive integer" >&2; exit 2 ;; esac
[ "$HALF" -ge 1 ] || { echo "run_gls.sh: GLS_CLK_HALF_NS must be >= 1" >&2; exit 2; }

NET="syn/out/$P/unpu_top_cn.dc.v"
SDF="syn/out/$P/unpu_top_cn.sdf"
[ -s "$NET" ] || { echo "run_gls.sh: netlist $NET missing or empty (run the DC script for $P first)" >&2; exit 2; }
[ -s "$MODEL" ] || { echo "run_gls.sh: cell model $MODEL missing or empty (set GLS_MODEL)" >&2; exit 2; }
[ -s tb/unpu_top_tb.sv ] || { echo "run_gls.sh: tb/unpu_top_tb.sv not found (run from the repo checkout)" >&2; exit 2; }
if [ ! -d model/vectors ] || [ -z "$(ls -A model/vectors 2>/dev/null)" ]; then
  echo "run_gls.sh: model/vectors/ is missing or empty (the testbench opens it by a relative path): gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden" >&2; exit 2
fi
command -v xrun >/dev/null 2>&1 || { echo "run_gls.sh: 'xrun' not found in PATH -- source ~/cad_cshrc first" >&2; exit 2; }

mkdir -p syn/out || { echo "run_gls.sh: cannot create syn/out" >&2; exit 2; }
SDFARGS=()
if [ "$MODE" = sdf ]; then
  [ -s "$SDF" ] || { echo "run_gls.sh: SDF $SDF missing or empty (the DC script writes it since task 059; rerun it for $P)" >&2; exit 2; }
  LOG="syn/out/gls_sdf_$P.log"
  CMD="syn/out/gls_sdf_$P.cmd"
  printf 'SDF_FILE = "%s",\n  SCOPE = %s,\n  LOG_FILE = "syn/out/gls_sdf_%s_annotate.log";\n' "$SDF" "$DUT_SCOPE" "$P" > "$CMD" || { echo "run_gls.sh: cannot write $CMD" >&2; exit 2; }
  SDFARGS=(-sdf_cmd_file "$CMD" -sdf_verbose)
else
  LOG="syn/out/gls_$P.log"
fi
rm -f "$LOG"

echo "=== GLS $P mode $MODE: clock half period ${HALF} ns; log $LOG"
[ "$MODE" = sdf ] && echo "=== sdf command file $CMD:" && sed 's/^/    /' "$CMD"
echo "=== VERIFY: -define, -sdf_cmd_file/SDF_FILE/SCOPE, -sdf_verbose are Xcelium options not read from a usage text here"
# shellcheck disable=SC2086  # XRUN_FLAGS is deliberately word-split
xrun -sv -64bit -access +r -timescale 1ns/1ps -notimingchecks -define GLS_CLK_HALF_NS="$HALF" ${SDFARGS[@]+"${SDFARGS[@]}"} \
     -top unpu_top_tb "$NET" "$MODEL" tb/unpu_top_tb.sv -l "$LOG" ${XRUN_FLAGS:-} >"${LOG%.log}.console" 2>&1
rc=$?

if [ ! -s "$LOG" ]; then echo "--- FAIL: no log produced (xrun exit $rc; see ${LOG%.log}.console)"; exit 1; fi

n_fail=$(grep -c 'FAIL' "$LOG")
n_err=$(grep -cE '\*[EF],' "$LOG")
n_pass=$(grep -c 'ALL CHECKS PASSED' "$LOG")
checked=$(grep -oE 'checked [0-9]+ value' "$LOG" | tail -n1 | grep -oE '[0-9]+')
echo "--- first 5 FAIL lines (grep -m5 -n FAIL):"
grep -m5 -n FAIL "$LOG" | sed 's/^/    /'
if [ "$MODE" = sdf ]; then
  echo "--- SDF annotation lines in the log (the number of annotated delays must be large; zero means nothing was annotated):"
  grep -iE 'sdf|annotat' "$LOG" | head -n 12 | sed 's/^/    /'
fi
echo "--- FAIL lines: $n_fail; *E/*F lines: $n_err; 'ALL CHECKS PASSED' lines: $n_pass; checks reported: ${checked:-none} (expected $EXPECT_CHECKS); xrun exit code $rc (informational)"
if [ "$n_fail" -eq 0 ] && [ "$n_err" -eq 0 ] && [ "$n_pass" -ge 1 ] && [ "${checked:-0}" = "$EXPECT_CHECKS" ]; then
  echo "=== PASS: $P ($MODE)"
  exit 0
fi
echo "=== FAIL: $P ($MODE)"
exit 1
