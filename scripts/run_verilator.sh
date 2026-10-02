#!/usr/bin/env bash
# Run the uNPU testbenches locally under Verilator and report per-TB
# PASS/FAIL with self-reported check counts.
#
# Usage (from repo root):
#   bash scripts/run_verilator.sh                # all ten testbenches
#   bash scripts/run_verilator.sh csr            # single testbench
#   bash scripts/run_verilator.sh dma seq top    # multiple testbenches

set -u

ALL_TBS=(pe grid skew stall buf dma csr seq apb top)
EXTRA_TBS=(ext1 ext2)

pass_regex() {
  case "$1" in
    pe)    echo '^ALL TASK 013 \+ TASK 019 PE CHECKS PASSED' ;;
    grid)  echo '^ALL TASK 013 \+ TASK 020 GRID CHECKS PASSED' ;;
    skew)  echo '^ALL TASK 013 \+ TASK 021 SKEW/DESKEW CHECKS PASSED' ;;
    stall) echo '^ALL TASK 005/013 \+ TASK 022 STALL CHECKS PASSED' ;;
    ext1|ext2) echo '^ALL TESTS PASSED' ;;
    *)     echo '^ALL CHECKS PASSED' ;;
  esac
}

count_lines() {
  local tb="$1" log="$2"
  case "$tb" in
    pe)
      grep -E '(exhaustive (signed|unsigned) sweep|PE accumulator sweep|PE randomized weight-load timing|PE adversarial long-sequence testing):' "$log" \
        | sed -E 's/, 0 failures.*//; s/, [0-9]+ failures.*//'
      ;;
    grid|skew)
      grep -E "$(pass_regex "$tb")" "$log" | grep -oE 'checked=[0-9]+ total'
      ;;
    stall)
      grep -E "$(pass_regex "$tb")" "$log" | grep -oE 'checks=[0-9]+ frozen_checks=[0-9]+'
      ;;
    *)
      grep -E '^checked [0-9]+ ' "$log"
      ;;
  esac
}

cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "cannot cd to repo root" >&2; exit 2; }

if [ "$#" -gt 0 ]; then
  TBS=("$@")
else
  TBS=("${ALL_TBS[@]}")
fi

if ! command -v verilator >/dev/null 2>&1; then
  echo "run_verilator.sh: 'verilator' not found in PATH" >&2
  exit 2
fi

if [ ! -d model/vectors ] || [ -z "$(ls -A model/vectors 2>/dev/null)" ]; then
  echo "run_verilator.sh: generating reference vectors first..."
  gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden >/dev/null
fi

mkdir -p verilator_out

declare -a ROW_NAME ROW_STATUS ROW_DETAIL
any_fail=0

for t in "${TBS[@]}"; do
  top="unpu_${t}_tb"
  log="verilator_out/${t}.log"
  echo "=== ${top}: building and simulating with Verilator ==="
  
  verilator --binary --timing -Wno-fatal -Wno-PINMISSING -Wno-TIMESCALEMOD -j 0 \
            --top-module "$top" --Mdir "obj_dir/${top}" \
            rtl/*.sv "tb/${top}.sv" >"$log" 2>&1
  compile_rc=$?

  if [ "$compile_rc" -ne 0 ]; then
    echo "--- ${top}: BUILD FAIL"
    ROW_NAME+=("$t")
    ROW_STATUS+=("BUILD_FAIL")
    ROW_DETAIL+=("      (compile failed, see ${log})")
    any_fail=1
    continue
  fi

  "./obj_dir/${top}/V${top}" >>"$log" 2>&1
  sim_rc=$?

  status=PASS
  if [ "$sim_rc" -ne 0 ] || grep -q 'FAIL' "$log" || ! grep -qE "$(pass_regex "$t")" "$log"; then
    status=FAIL
    any_fail=1
    echo "--- ${top}: FAIL"
  else
    echo "--- ${top}: PASS"
  fi

  detail=$(count_lines "$t" "$log" | sed 's/^/      /')
  ROW_NAME+=("$t")
  ROW_STATUS+=("$status")
  ROW_DETAIL+=("$detail")
done

echo
echo "================ Verilator summary ================"
for i in "${!ROW_NAME[@]}"; do
  printf '%-6s %s\n' "${ROW_NAME[$i]}" "${ROW_STATUS[$i]}"
  if [ -n "${ROW_DETAIL[$i]}" ]; then
    printf '%s\n' "${ROW_DETAIL[$i]}"
  fi
done
echo "==================================================="
if [ "$any_fail" -eq 0 ]; then
  echo "ALL ${#TBS[@]} TESTBENCH(ES) PASSED"
  exit 0
fi
echo "AT LEAST ONE TESTBENCH FAILED"
exit 1
