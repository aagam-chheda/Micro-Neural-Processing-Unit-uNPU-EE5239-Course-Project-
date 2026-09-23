#!/usr/bin/env bash
# Run the uNPU testbenches under Cadence Xcelium (xrun) and report per-TB
# PASS/FAIL with the self-reported check counts.
#
# Usage (from the repo root; the server login shell may be csh -- this is
# bash and simply inherits the Cadence environment it exports):
#
#   bash scripts/run_xrun.sh                # all ten testbenches
#   bash scripts/run_xrun.sh dma seq top    # just these
#
# Environment:
#   XRUN_FLAGS   extra flags appended to every xrun invocation (e.g. a
#                license-queue option). Word-split on purpose.
#
# PASS/FAIL is decided from each testbench's LOG, never from xrun's exit
# code: the testbenches end in $finish, so xrun exits 0 even when checks
# failed. A testbench FAILS if its log has any of
#   *E, / *F,        Xcelium compile/elaboration/runtime error or fatal
#   FAIL             any TB failure line (also matches FAILURE(S))
#   $fatal           a testbench $fatal message
# or if the testbench's own final ALL-PASSED line is absent. A missing or
# empty log is a FAIL too (nothing fails silently).
#
# Outputs (all under xrun_out/, which is gitignored): <tb>.log (xrun -l),
# <tb>.console (raw xrun stdout/stderr) and the <tb>/ xmlib directory.
#
# Exit status: 0 = every requested TB passed, 1 = at least one failed,
# 2 = usage / environment problem (nothing was judged).

set -u

ALL_TBS=(pe grid skew stall buf dma csr seq apb top)

# The one line each TB prints only when it finished with errors == 0. Kept
# in step with the tb/*.sv sources; the simple TBs share "ALL CHECKS PASSED".
pass_regex() {
  case "$1" in
    pe)    echo '^ALL TASK 013 \+ TASK 019 PE CHECKS PASSED' ;;
    grid)  echo '^ALL TASK 013 \+ TASK 020 GRID CHECKS PASSED' ;;
    skew)  echo '^ALL TASK 013 \+ TASK 021 SKEW/DESKEW CHECKS PASSED' ;;
    stall) echo '^ALL TASK 005/013 \+ TASK 022 STALL CHECKS PASSED' ;;
    *)     echo '^ALL CHECKS PASSED' ;;
  esac
}

# The self-reported count line(s) for the summary table.
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

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  echo "Testbench names: ${ALL_TBS[*]}"
}

# Always work from the repo root, wherever the script was invoked from: the
# TBs open model/vectors/... by relative path.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "cannot cd to repo root" >&2; exit 2; }

for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
  esac
done

if [ "$#" -gt 0 ]; then
  TBS=("$@")
else
  TBS=("${ALL_TBS[@]}")
fi

for t in "${TBS[@]}"; do
  ok=0
  for k in "${ALL_TBS[@]}"; do [ "$t" = "$k" ] && ok=1; done
  if [ "$ok" -ne 1 ]; then
    echo "run_xrun.sh: unknown testbench '$t' (valid: ${ALL_TBS[*]})" >&2
    exit 2
  fi
done

if ! command -v xrun >/dev/null 2>&1; then
  echo "run_xrun.sh: 'xrun' not found in PATH -- source the Cadence Xcelium environment first" >&2
  exit 2
fi
if [ ! -d model/vectors ] || [ -z "$(ls -A model/vectors 2>/dev/null)" ]; then
  echo "run_xrun.sh: model/vectors/ is missing or empty -- generate the golden vectors from the repo root first:" >&2
  echo "    gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden" >&2
  exit 2
fi

RTL=(rtl/*.sv)
if [ ! -e "${RTL[0]}" ]; then
  echo "run_xrun.sh: no rtl/*.sv found (run from the repo checkout)" >&2
  exit 2
fi

mkdir -p xrun_out || { echo "run_xrun.sh: cannot create xrun_out/" >&2; exit 2; }

declare -a ROW_NAME ROW_STATUS ROW_DETAIL
any_fail=0

for t in "${TBS[@]}"; do
  top="unpu_${t}_tb"
  log="xrun_out/${t}.log"
  console="xrun_out/${t}.console"
  rm -rf "xrun_out/${t}" "$log" "$console"

  echo "=== ${top}: running xrun ..."
  # shellcheck disable=SC2086  # XRUN_FLAGS is deliberately word-split
  xrun -sv -64bit -access +r -timescale 1ns/1ps \
       -top "$top" -xmlibdirname "xrun_out/${t}" -l "$log" \
       ${XRUN_FLAGS:-} "${RTL[@]}" "tb/${top}.sv" >"$console" 2>&1
  xrun_rc=$?

  status=PASS
  reasons=()
  n_warn=0

  if [ ! -s "$log" ]; then
    status=FAIL
    reasons+=("no log produced (see ${console})")
  else
    n_err=$(grep -cE '\*[EF],' "$log")
    n_fail=$(grep -c 'FAIL' "$log")
    n_fatal=$(grep -cF '$fatal' "$log")
    if [ "$n_err" -gt 0 ];   then status=FAIL; reasons+=("${n_err} *E,/*F, line(s)"); fi
    if [ "$n_fail" -gt 0 ];  then status=FAIL; reasons+=("${n_fail} FAIL line(s)"); fi
    if [ "$n_fatal" -gt 0 ]; then status=FAIL; reasons+=("\$fatal in log"); fi
    if ! grep -qE "$(pass_regex "$t")" "$log"; then
      status=FAIL
      reasons+=("final ALL-PASSED line absent (did not finish, or compile stopped it)")
    fi
    n_warn=$(grep -cE '\*W,' "$log")
  fi

  if [ "$status" = FAIL ]; then
    any_fail=1
    echo "--- ${top}: FAIL: ${reasons[*]}"
    if [ -s "$log" ]; then
      echo "--- first offending log lines (${log}):"
      grep -nE '\*[EF],|FAIL|\$fatal' "$log" | head -n 8 | sed 's/^/    /'
    fi
  else
    echo "--- ${top}: PASS"
  fi

  detail=""
  if [ -s "$log" ]; then
    detail=$(count_lines "$t" "$log" | sed 's/^/      /')
    detail="${detail}"$'\n'"      (xrun exit code ${xrun_rc} -- informational only; *W, warnings: ${n_warn})"
  else
    detail="      (xrun exit code ${xrun_rc}; no log)"
  fi

  ROW_NAME+=("$t")
  ROW_STATUS+=("$status")
  ROW_DETAIL+=("$detail")
done

echo
echo "================ Xcelium summary ================"
for i in "${!ROW_NAME[@]}"; do
  printf '%-6s %s\n' "${ROW_NAME[$i]}" "${ROW_STATUS[$i]}"
  printf '%s\n' "${ROW_DETAIL[$i]}"
done
echo "================================================="
if [ "$any_fail" -eq 0 ]; then
  echo "ALL ${#TBS[@]} TESTBENCH(ES) PASSED"
  exit 0
fi
echo "AT LEAST ONE TESTBENCH FAILED (see FAIL rows above)"
exit 1
