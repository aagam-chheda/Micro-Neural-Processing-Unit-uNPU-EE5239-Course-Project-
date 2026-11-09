#!/usr/bin/env bash
# Post-layout simulation with the SDF (task 075): the SAME testbench tb/unpu_top_tb.sv against the post-layout netlist written by pv.tcl, with the SDF of one corner.
#
# Usage (from anywhere; the script changes to the repo root itself, because the testbench opens model/vectors/ by a relative path):
#   bash pnr_v2/sim/run_postlayout_sim.sh <ss|ff> <checks|nochecks>
#   DRY_RUN=1 bash pnr_v2/sim/run_postlayout_sim.sh ss nochecks     # prints the SDF command file and the xrun line, runs nothing
# The server login shell is csh, so call it with `bash` as above.
#
# Run matrix (README): A = ss nochecks (primary functional proof), B = ss checks, C = ff nochecks, D = ff checks.
#   nochecks adds -notimingchecks (the flag of the gate-level run that passed, handoff 18.7): the delays of the SDF are applied, the $setup/$hold/$width checks are off.
#   checks   leaves the timing checks ON: a violation turns the flop output to X through the notifier of the cell model.
#
# Inputs (pnr_icc2/outputs/, written by pv.tcl): unpu_top_pnr_sim.v, unpu_top_ss.sdf, unpu_top_ff.sdf. Cell model: the one combined file of the kit (handoff 18.7).
# Outputs (pnr_icc2/sim/, created here, never inside the tracked tree): pl_<corner>_<mode>.log (xrun -l), .console, .sdfcmd (the SDF command file), _annotate.log (written by Xcelium).
#
# Verdict (judge_log below): from the LOG, never from xrun's exit code (the testbench ends in $finish, so xrun exits 0 even when checks failed). PASS only if ALL of:
#   - the line `ALL CHECKS PASSED`;  - exactly EXPECT_CHECKS in `checked N value(s)/assertion(s) total`;  - no line with FAIL;  - no `*E,` / `*F,` line;
#   - an SDF annotation message exists (otherwise nothing proves that the SDF was applied) and there is no SDF warning of the not-found class (any is a FAIL, the classes are counted and printed);
#   - in `checks` mode no timing-check violation message (counted, the first 10 printed).
#   A missing or empty log is a FAIL. The first 5 FAIL or violation lines, the simulated end time and the wall-clock time are printed.
# Exit status: 0 = PASS, 1 = FAIL, 2 = usage / environment problem (nothing was judged).
#
# VERIFY (Xcelium syntax not read from a usage text here; each is printed in the log header, the README table says what to look at): the SDF command file statement
# (SDF_FILE, SCOPE, MTM_CONTROL, SCALE_FACTORS, SCALE_TYPE, LOG_FILE), -sdf_cmd_file, -sdf_verbose, the wording of the annotation / not-found / violation messages, and the end-time line.

set -u

# ---- parameters, each with its source ----
EXPECT_CHECKS=343341                 # checks of tb/unpu_top_tb.sv: docs/session-handoff.md 18.7 (equal in the RTL run and in the zero-delay gate-level run)
DUT_SCOPE=unpu_top_tb.dut            # tb/unpu_top_tb.sv: instance `dut` of module unpu_top inside unpu_top_tb
GLS_CLK_HALF_NS=10                   # 20 ns clock (handoff 18.7; the testbench drives the stimulus 2 ns after each edge)
MODEL_DEFAULT=/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v   # one combined model file (handoff 18.7); do not also pass the per-cell files
OUT_DIR_DEFAULT=pnr_icc2/outputs     # written by pnr_v2/pv.tcl; relative to the repo root (the repo is cloned in the server folder, pnr_v2/README.md)
SIM_DIR_DEFAULT=pnr_icc2/sim

# ------------------------------------------------------------------------------------------------------------------------
# The verdict. judge_log <log> <checks|nochecks> [annotation_log]  -> prints the evidence, returns 0 (PASS) or 1 (FAIL)
# ------------------------------------------------------------------------------------------------------------------------
judge_log() {
  local log="$1" mode="$2" annlog="${3:-}"
  local why=() n_fail n_err n_pass checked n_ann n_sdfwarn n_viol endt
  if [ ! -e "$log" ]; then echo "--- FAIL: the log $log does not exist"; return 1; fi
  if [ ! -s "$log" ]; then echo "--- FAIL: the log $log is empty"; return 1; fi
  n_fail=$(grep -c 'FAIL' "$log")
  n_err=$(grep -cE '\*[EF],' "$log")
  n_pass=$(grep -c 'ALL CHECKS PASSED' "$log")
  checked=$(grep -oE 'checked [0-9]+ value' "$log" | tail -n1 | grep -oE '[0-9]+')
  endt=$(grep -oE 'at time [0-9]+ [A-Za-z]+' "$log" | tail -n1)
  echo "--- first 5 FAIL lines:"
  grep -m5 -n 'FAIL' "$log" | sed 's/^/    /'
  echo "--- first 5 *E,/*F, lines:"
  grep -m5 -nE '\*[EF],' "$log" | sed 's/^/    /'
  # ---- SDF annotation evidence (log and the separate annotation log) ----
  local anntext
  anntext=$( { grep -iE 'annotat' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -iE 'annotat' "$annlog"; } 2>/dev/null )
  n_ann=$(printf '%s' "$anntext" | grep -c . )
  echo "--- SDF annotation lines (Xcelium's own counts; $n_ann lines; the annotated number must be large, 'unannotated'/'not annotated' counts are printed as they are):"
  printf '%s\n' "$anntext" | head -n 12 | sed 's/^/    /'
  # SDF warnings of the not-found class: *W,SDF... messages, and any SDF line that says not found / unmatched / cannot find
  local sdftext
  sdftext=$( { grep -E '\*W,SDF' "$log"; grep -iE 'sdf.*(not found|unmatched|cannot find|no such|could not)' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -iE '(\*W,SDF|not found|unmatched|cannot find|no such instance)' "$annlog"; } 2>/dev/null | sort -u )
  n_sdfwarn=$(printf '%s' "$sdftext" | grep -c . )
  echo "--- SDF warnings (not-found class): $n_sdfwarn; by message id:"
  printf '%s\n' "$sdftext" | grep -oE '\*W,SDF[A-Z]*' | sort | uniq -c | sed 's/^/    /'
  printf '%s\n' "$sdftext" | head -n 5 | sed 's/^/    /'
  # ---- timing-check violations (checks mode only) ----
  n_viol=0
  if [ "$mode" = checks ]; then
    local viol
    viol=$(grep -iE 'violation|\*W,TCHKVIO|\$(setup|hold|recovery|removal|width|period|setuphold|recrem|skew)[ (]' "$log" | grep -viE 'annotat|^ *SDF' )
    n_viol=$(printf '%s' "$viol" | grep -c . )
    echo "--- timing-check violations (checks mode): $n_viol; the first 10 (time and instance are in the line):"
    printf '%s\n' "$viol" | head -n 10 | sed 's/^/    /'
  else
    echo "--- timing-check violations: not judged in nochecks mode (-notimingchecks switches the checks off)"
  fi
  echo "--- FAIL lines: $n_fail; *E/*F lines: $n_err; 'ALL CHECKS PASSED' lines: $n_pass; checks reported: ${checked:-none} (expected $EXPECT_CHECKS); SDF annotation lines: $n_ann; SDF not-found warnings: $n_sdfwarn; violations: $n_viol; simulated end: ${endt:-not found in the log}"
  [ "$n_pass" -ge 1 ] || why+=("no ALL CHECKS PASSED line")
  [ "${checked:-0}" = "$EXPECT_CHECKS" ] || why+=("checks reported ${checked:-none}, expected $EXPECT_CHECKS")
  [ "$n_fail" -eq 0 ] || why+=("$n_fail lines with FAIL")
  [ "$n_err" -eq 0 ] || why+=("$n_err *E,/*F, lines")
  [ "$n_ann" -ge 1 ] || why+=("no SDF annotation message in the log: nothing proves that the SDF was applied")
  [ "$n_sdfwarn" -eq 0 ] || why+=("$n_sdfwarn SDF not-found warnings")
  [ "$n_viol" -eq 0 ] || why+=("$n_viol timing-check violations")
  if [ "${#why[@]}" -eq 0 ]; then return 0; fi
  printf -- '--- reasons: %s\n' "$(IFS=';'; echo "${why[*]}")"
  return 1
}

# ------------------------------------------------------------------------------------------------------------------------
# The SDF command file text. sdf_cmd_text <sdf_path> <annotation_log> <ss|ff>
# MTM_CONTROL: the corner's value. ss -> MAXIMUM (the slow corner, setup), ff -> MINIMUM (the fast corner, hold). If the SDF triples are all equal the choice changes nothing
# (the header check below prints whether they differ).
# ------------------------------------------------------------------------------------------------------------------------
sdf_cmd_text() {
  local sdf="$1" annlog="$2" corner="$3" mtm
  case "$corner" in ss) mtm=MAXIMUM ;; ff) mtm=MINIMUM ;; esac
  printf 'SDF_FILE = "%s",\n  SCOPE = %s,\n  MTM_CONTROL = "%s",\n  SCALE_FACTORS = "1.0:1.0:1.0",\n  SCALE_TYPE = "FROM_MTM",\n  LOG_FILE = "%s";\n' "$sdf" "$DUT_SCOPE" "$mtm" "$annlog"
}

# header and counts of an SDF file (read at run time; nothing is assumed)
sdf_info() {
  local f="$1"
  echo "=== SDF $f: [$(ls -l "$f" | awk '{print $5}') bytes]"
  head -n 40 "$f" | grep -E '^\s*\((SDFVERSION|DESIGN|DATE|VENDOR|PROGRAM|VERSION|DIVIDER|VOLTAGE|PROCESS|TEMPERATURE|TIMESCALE)' | sed 's/^/    /'
  echo "    counts: IOPATH $(grep -c 'IOPATH' "$f"), INTERCONNECT $(grep -c 'INTERCONNECT' "$f"), SETUPHOLD $(grep -c 'SETUPHOLD' "$f"), SETUP $(grep -cE '\(SETUP ' "$f"), HOLD $(grep -cE '\(HOLD ' "$f"), RECOVERY $(grep -c 'RECOVERY' "$f"), REMOVAL $(grep -c 'REMOVAL' "$f"), WIDTH $(grep -c 'WIDTH' "$f")"
  echo "    first INSTANCE lines:"; grep -m3 -E '^\s*\(INSTANCE' "$f" | sed 's/^/        /'
  # do the min:typ:max triples differ? look at the first 5000 triples
  grep -m5000 -oE '\(-?[0-9.]*:-?[0-9.]*:-?[0-9.]*\)' "$f" | awk -F'[(:)]' 'BEGIN{n=0;d=0} {n++; if ($2!=$4) d++} END{printf "    triples sampled: %d, with min != max: %d (%s)\n", n, d, (n==0 ? "no triples found" : (d==0 ? "all equal: the delay selection changes nothing" : "they differ: MTM_CONTROL matters"))}'
}

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." || { echo "run_postlayout_sim.sh: cannot cd to the repo root" >&2; return 2; }
  if [ "$#" -ne 2 ]; then usage; return 2; fi
  local corner="$1" mode="$2"
  case "$corner" in ss|ff) ;; *) echo "run_postlayout_sim.sh: corner must be ss or ff, not '$corner'" >&2; return 2 ;; esac
  case "$mode" in checks|nochecks) ;; *) echo "run_postlayout_sim.sh: mode must be checks or nochecks, not '$mode'" >&2; return 2 ;; esac
  local dry="${DRY_RUN:-0}"
  local OUT="${PL_OUT_DIR:-$OUT_DIR_DEFAULT}" SIM="${PL_SIM_DIR:-$SIM_DIR_DEFAULT}" MODEL="${GLS_MODEL:-$MODEL_DEFAULT}"
  local NET="$OUT/unpu_top_pnr_sim.v" SDF="$OUT/unpu_top_$corner.sdf" TB=tb/unpu_top_tb.sv
  local TAG="pl_${corner}_${mode}" LOG="$SIM/pl_${corner}_${mode}.log" CMD="$SIM/pl_${corner}_${mode}.sdfcmd" ANN="$SIM/pl_${corner}_${mode}_annotate.log" XM="xrun_out/pl_${corner}_${mode}"
  local flags=(-sv -64bit -access +r -timescale 1ns/1ps -top unpu_top_tb -define "GLS_CLK_HALF_NS=$GLS_CLK_HALF_NS")
  [ "$mode" = nochecks ] && flags+=(-notimingchecks)
  flags+=(-sdf_cmd_file "$CMD" -sdf_verbose -xmlibdirname "$XM")
  local XRUN_LINE="xrun ${flags[*]} $NET $MODEL $TB -l $LOG ${XRUN_FLAGS:-}"

  # ---- inputs ----
  local bad=0 f
  for f in "$NET" "$SDF" "$MODEL" "$TB"; do
    if [ ! -s "$f" ]; then
      if [ "$dry" = 1 ]; then echo "DRY RUN note: $f is missing or empty here (the real run would stop with exit 2)"; else echo "run_postlayout_sim.sh: input $f missing or empty" >&2; bad=1; fi
    fi
  done
  if [ ! -d model/vectors ] || [ -z "$(ls -A model/vectors 2>/dev/null)" ]; then
    if [ "$dry" = 1 ]; then echo "DRY RUN note: model/vectors/ is missing or empty here (the real run would stop)"; else
      echo "run_postlayout_sim.sh: model/vectors/ is missing or empty (the testbench opens it by a relative path): gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden" >&2; bad=1; fi
  fi
  if [ "$dry" != 1 ] && ! command -v xrun >/dev/null 2>&1; then echo "run_postlayout_sim.sh: 'xrun' not found in PATH -- source ~/cad_cshrc first" >&2; bad=1; fi
  [ "$bad" -eq 0 ] || return 2

  echo "=== post-layout simulation: corner $corner, mode $mode, clock half period ${GLS_CLK_HALF_NS} ns (20 ns clock), expected checks $EXPECT_CHECKS"
  if [ "$dry" = 1 ]; then
    echo "=== DRY RUN: nothing is written or run"
    echo "=== SDF command file (would be $CMD):"
    sdf_cmd_text "$SDF" "$ANN" "$corner" | sed 's/^/    /'
    echo "=== xrun line:"
    echo "    $XRUN_LINE"
    [ -s "$SDF" ] && sdf_info "$SDF"
    return 0
  fi
  mkdir -p "$SIM" xrun_out || { echo "run_postlayout_sim.sh: cannot create $SIM or xrun_out" >&2; return 2; }
  echo "=== tool: $(xrun -version 2>&1 | head -n 2 | tr '\n' ' ')"
  sdf_info "$SDF"
  sdf_cmd_text "$SDF" "$ANN" "$corner" > "$CMD" || { echo "run_postlayout_sim.sh: cannot write $CMD" >&2; return 2; }
  echo "=== SDF command file $CMD:"; sed 's/^/    /' "$CMD"
  echo "=== VERIFY: the SDF command file statement, -sdf_cmd_file and -sdf_verbose are Xcelium syntax not read from a usage text here (README table)"
  echo "=== command: $XRUN_LINE"
  rm -f "$LOG" "$ANN"
  local t0=$SECONDS
  # shellcheck disable=SC2086  # XRUN_FLAGS is deliberately word-split
  xrun "${flags[@]}" "$NET" "$MODEL" "$TB" -l "$LOG" ${XRUN_FLAGS:-} >"${LOG%.log}.console" 2>&1
  local rc=$? el=$((SECONDS - t0))
  echo "=== xrun exit code $rc (informational: the verdict is judged from the log); wall-clock time $((el/60)) min $((el%60)) s"
  judge_log "$LOG" "$mode" "$ANN"
  local v=$?
  if [ "$v" -eq 0 ]; then echo "=== PASS: post-layout $corner $mode (wall-clock $((el/60)) min $((el%60)) s)"; return 0; fi
  echo "=== FAIL: post-layout $corner $mode (log $LOG, console ${LOG%.log}.console, annotation log $ANN)"
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; exit $?; fi
