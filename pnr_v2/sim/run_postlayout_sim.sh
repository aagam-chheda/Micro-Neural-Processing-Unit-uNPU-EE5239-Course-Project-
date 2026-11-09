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
#   - an SDF annotation message exists (otherwise nothing proves that the SDF was applied; SDFNEP / SDFNCAP warning lines do not count as annotation evidence);
#   - SDF messages by id: SDFNCAP is INFORMATION (counted, first 3 printed); SDFNEP is accepted ONLY as the bounded, documented class `IOPATH (posedge|negedge X) Y` on a cell type of
#     SDFNEP_ALLOWED_CELLS (run A3, user decision 2026-11-09; README "Known limitation: SDFNEP"), the PASS then carries a caveat in its verdict word; any other SDFNEP, SDFIRE, SDFCNC,
#     any other SDF warning id or a not-found line is a FAIL;
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
# Cell types whose SDFNEP "non-existent path (IOPATH (posedge|negedge X) Y)" warnings are ACCEPTED (documented bounded limitation): run A3, 2026-11-09, user approval (option 1).
# Cause: the library model declares these paths without an edge qualifier, ICC2 writes edge-specific IOPATH entries, Xcelium does not match them and the arc keeps the model's zero delay.
# Families: 2-input multiplexers (mx02*, mi02*), half adder (ah01*), full adder (ad01*), XOR/XNOR (xr02*, xn02*). Only the drive strengths seen in run A3 are listed; another cell type
# (even of these families) is a FAIL until it is added here knowingly.
SDFNEP_ALLOWED_CELLS="mx02d0 mx02d1 mi02d0 mi02d1 ah01d1 ad01d0 xr02d1 xn02d1"

# ------------------------------------------------------------------------------------------------------------------------
# The verdict. judge_log <log> <checks|nochecks> [annotation_log]  -> prints the evidence, returns 0 (PASS) or 1 (FAIL).
# Sets the global JUDGE_CAVEAT: empty for a clean PASS, the full "PASS (with the documented SDF limitation: ...)" text when the bounded SDFNEP acceptance was used.
# ------------------------------------------------------------------------------------------------------------------------
judge_log() {
  local log="$1" mode="$2" annlog="${3:-}"
  local why=() n_fail n_err n_pass checked n_ann n_sdfwarn n_viol endt
  JUDGE_CAVEAT=""
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
  anntext=$( { grep -iE 'annotat' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -iE 'annotat' "$annlog"; } 2>/dev/null | grep -vE '\*[WEF],(SDFNEP|SDFNCAP)' )
  n_ann=$(printf '%s' "$anntext" | grep -c . )
  echo "--- SDF annotation lines (Xcelium's own counts; SDFNEP/SDFNCAP warning lines are not counted as evidence; $n_ann lines; the annotated number must be large, 'unannotated'/'not annotated' counts are printed as they are):"
  printf '%s\n' "$anntext" | head -n 12 | sed 's/^/    /'
  # ---- SDF messages by id (log and annotation log, duplicates removed, log order kept) ----
  local sdfall
  sdfall=$( { grep -E '\*[WEF],SDF' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -E '\*[WEF],SDF' "$annlog"; } 2>/dev/null | awk '!s[$0]++' )
  echo "--- SDF messages by id (all of them, before classification):"
  printf '%s\n' "$sdfall" | grep -oE '\*[WEF],SDF[A-Z]*' | sort | uniq -c | sed 's/^/    /'
  # SDFNCAP: information (the port annotation still occurs)
  local ncap_txt n_ncap
  ncap_txt=$(printf '%s\n' "$sdfall" | grep -E '\*[WEF],SDFNCAP')
  n_ncap=$(printf '%s' "$ncap_txt" | grep -c . )
  echo "--- *W,SDFNCAP (INFORMATION, not a failure: the interconnect source is separated by a unidirectional continuous assign; the port annotation still occurs): $n_ncap; the first 3:"
  printf '%s\n' "$ncap_txt" | head -n 3 | sed 's/^/    /'
  # SDFNEP: accepted only in the bounded class
  local nep_txt n_nep_ok=0 n_nep_bad=0 nep_ok_rec="" nep_bad_txt="" line cell
  local nep_re='non-existent path \(IOPATH \((posedge|negedge) ([A-Za-z0-9_]+)\) ([A-Za-z0-9_]+)\) of instance ([^ ]+) of module ([A-Za-z0-9_]+)'
  nep_txt=$(printf '%s\n' "$sdfall" | grep -E '\*[WEF],SDFNEP')
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [[ $line =~ $nep_re ]]; then
      cell="${BASH_REMATCH[5]}"
      case " $SDFNEP_ALLOWED_CELLS " in
        *" $cell "*) n_nep_ok=$((n_nep_ok+1)); nep_ok_rec+="$cell"$'\t'"(${BASH_REMATCH[1]} ${BASH_REMATCH[2]}) ${BASH_REMATCH[3]}"$'\n' ;;
        *) n_nep_bad=$((n_nep_bad+1)); nep_bad_txt+="[cell type $cell is not in the allowed list] $line"$'\n' ;;
      esac
    else
      n_nep_bad=$((n_nep_bad+1)); nep_bad_txt+="[not of the form IOPATH (posedge|negedge X) Y] $line"$'\n'
    fi
  done <<< "$nep_txt"
  local nep_cap
  nep_cap=$(grep -E 'MXWARN.*SDFNEP' "$log")
  echo "--- *W,SDFNEP: total $((n_nep_ok + n_nep_bad)); in the accepted class (IOPATH edge form on a cell of: $SDFNEP_ALLOWED_CELLS): $n_nep_ok; outside it: $n_nep_bad"
  if [ "$n_nep_ok" -gt 0 ]; then
    echo "    count per cell type:"; printf '%s' "$nep_ok_rec" | cut -f1 | sort | uniq -c | sort -rn | sed 's/^/        /'
    echo "    count per arc form:";  printf '%s' "$nep_ok_rec" | cut -f2 | sort | uniq -c | sort -rn | sed 's/^/        /'
  fi
  if [ -n "$nep_cap" ]; then
    echo "    NOTE: the message cap of 1000 was reached: the real count is higher (the count above is a lower bound; the rule is applied to the printed lines):"
    printf '%s\n' "$nep_cap" | head -n 2 | sed 's/^/        /'
  fi
  if [ "$n_nep_bad" -gt 0 ]; then
    echo "    SDFNEP outside the accepted class, the first 5:"
    printf '%s' "$nep_bad_txt" | head -n 5 | sed 's/^/        /'
  fi
  # a cap on any other SDF message id hides the rest of that class
  local cap_other
  cap_other=$(grep -E 'MXWARN.*SDF' "$log" | grep -vE "'(SDFNEP|SDFNCAP)'")
  # any other SDF id (SDFINF, ...) and the not-found text forms
  local other_ids other_txt n_other sdftext n_sdfwarn
  other_txt=$(printf '%s\n' "$sdfall" | grep -vE '\*[WEF],(SDFNCAP|SDFNEP|SDFIRE|SDFCNC)' | grep .)
  n_other=$(printf '%s' "$other_txt" | grep -c . )
  sdftext=$( { grep -iE 'sdf.*(not found|unmatched|cannot find|no such|could not)' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -iE '(not found|unmatched|cannot find|no such instance)' "$annlog"; } 2>/dev/null | grep -vE '\*[WEF],(SDFNCAP|SDFNEP)' | awk '!s[$0]++' )
  n_sdfwarn=$(printf '%s' "$sdftext" | grep -c . )
  echo "--- SDF warnings of unknown id: $n_other; not-found / unmatched text lines: $n_sdfwarn; the first 5 of both:"
  { printf '%s\n' "$other_txt"; printf '%s\n' "$sdftext"; } | grep . | head -n 5 | sed 's/^/    /'
  # ---- SDF compile errors (xmsdfc *E,SDFIRE syntax error, xmelab *W,SDFCNC "Cannot compile SDF file - skipping annotation"): the run is then a ZERO-DELAY run ----
  local n_sdfc sdfctext
  sdfctext=$(grep -E 'SDFIRE|SDFCNC' "$log")
  n_sdfc=$(printf '%s' "$sdfctext" | grep -c . )
  if [ "$n_sdfc" -gt 0 ]; then
    echo "--- SDF compile errors (SDFIRE / SDFCNC): $n_sdfc; the SDF was NOT annotated, the simulation ran with zero delays:"
    printf '%s\n' "$sdfctext" | head -n 5 | sed 's/^/    /'
  fi
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
  echo "--- FAIL lines: $n_fail; *E/*F lines: $n_err; 'ALL CHECKS PASSED' lines: $n_pass; checks reported: ${checked:-none} (expected $EXPECT_CHECKS); SDF annotation lines: $n_ann; SDFNCAP (info): $n_ncap; SDFNEP accepted/outside: $n_nep_ok/$n_nep_bad; other-id SDF warnings: $n_other; SDF not-found text lines: $n_sdfwarn; violations: $n_viol; simulated end: ${endt:-not found in the log}"
  [ "$n_pass" -ge 1 ] || why+=("no ALL CHECKS PASSED line")
  [ "${checked:-0}" = "$EXPECT_CHECKS" ] || why+=("checks reported ${checked:-none}, expected $EXPECT_CHECKS")
  [ "$n_fail" -eq 0 ] || why+=("$n_fail lines with FAIL")
  [ "$n_err" -eq 0 ] || why+=("$n_err *E,/*F, lines")
  [ "$n_ann" -ge 1 ] || why+=("no SDF annotation message in the log: nothing proves that the SDF was applied")
  [ "$n_sdfwarn" -eq 0 ] || why+=("$n_sdfwarn SDF not-found warnings")
  [ "$n_nep_bad" -eq 0 ] || why+=("$n_nep_bad SDFNEP warnings outside the accepted class (IOPATH edge form on a cell of the allowed list)")
  [ "$n_other" -eq 0 ] || why+=("$n_other SDF warnings of an id that is not accepted (only SDFNCAP and the bounded SDFNEP class are)")
  [ -z "$cap_other" ] || why+=("the message cap was reached for an SDF message id other than SDFNEP/SDFNCAP: the rest of that class is hidden")
  [ "$n_viol" -eq 0 ] || why+=("$n_viol timing-check violations")
  [ "$n_sdfc" -eq 0 ] || why+=("the SDF could not be compiled: check the SDFVERSION (needs 3.0 if it has REMOVAL/RECOVERY entries) and regenerate with pv.tcl")
  JUDGE_CAVEAT=""
  if [ "${#why[@]}" -eq 0 ]; then
    if [ "$n_nep_ok" -gt 0 ]; then
      JUDGE_CAVEAT="PASS (with the documented SDF limitation: $n_nep_ok SDFNEP warnings on mux-select, XOR/XNOR and adder-sum arcs ran at zero delay; the simulation is slightly optimistic on those arcs; timing sign-off is PrimeTime)"
      echo "--- $JUDGE_CAVEAT"
    fi
    return 0
  fi
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
  local ver nrem
  ver=$(head -n 40 "$f" | grep -oE '\(SDFVERSION[^)]*\)' | head -n1)
  nrem=$(( $(grep -c 'REMOVAL' "$f") + $(grep -c 'RECOVERY' "$f") ))
  echo "    SDF version line: ${ver:-none found}; REMOVAL + RECOVERY entries: $nrem"
  case "$ver" in
    *'"3.0"'*) ;;
    *) if [ "$nrem" -gt 0 ]; then echo "    WARNING: the header is not SDFVERSION \"3.0\" but the file has $nrem REMOVAL/RECOVERY entries (SDF 3.0 only): Xcelium stops with *E,SDFIRE and skips the SDF (*W,SDFCNC). Regenerate with pv.tcl (it writes 3.0 since task 076) or run the sed of the README known-problem note."; fi ;;
  esac
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
  if [ "$v" -eq 0 ]; then echo "=== ${JUDGE_CAVEAT:-PASS}: post-layout $corner $mode (wall-clock $((el/60)) min $((el%60)) s)"; return 0; fi
  echo "=== FAIL: post-layout $corner $mode (log $LOG, console ${LOG%.log}.console, annotation log $ANN)"
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; exit $?; fi
