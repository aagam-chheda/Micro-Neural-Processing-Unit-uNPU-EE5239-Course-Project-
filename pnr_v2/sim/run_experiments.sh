#!/usr/bin/env bash
# The two simulation experiments of task 094 in ONE command (README "Experiments that remove the causes"):
#   eqeq    nep_cond: `===` -> `==` in the COND lines of a COPY of the SDF (ss and ff), run A and C (nochecks) on the copies
#   negtchk nl1_neg / net_remrec: `-define neg_tchk` (+ the simulator option, if this xrun lists it), run B and D (checks)
# Usage (from anywhere; csh needs `bash`):
#   bash pnr_v2/sim/run_experiments.sh |& tee pnr_icc2/sim/experiments_console.txt          # both, about 25 minutes
#   bash pnr_v2/sim/run_experiments.sh eqeq                                                   # only experiment 2 (about 10 minutes)
#   bash pnr_v2/sim/run_experiments.sh negtchk                                                # only experiment 1 (about 15 minutes + licence wait)
# At the end it prints ONE summary block (also written to pnr_icc2/sim/experiments_summary.txt): paste that block, nothing else.
# Nothing original is changed: the SDF copies go to pnr_icc2/sdf_experiment/ (the originals are checksummed before and after), the logs get the labels eqeq / negtchk, the standard logs are not touched.
# Environment (all optional): LICENSE_RETRIES (default 6), LICENSE_WAIT_S (default 600), NEG_TCHK_OPT (the simulator option, default: auto from `xrun -helpall`), DRY_RUN=1 (prints the commands, runs no simulation),
#   PL_OUT_DIR / PL_SIM_DIR / EXP_DIR (folders; default pnr_icc2/outputs, pnr_icc2/sim, pnr_icc2/sdf_experiment, relative to the repo root).
# Exit status: 0 = finished (the verdict words of the runs are FAIL by design when a cause is removed: read the summary), 2 = a precondition failed (nothing was run).
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || { echo "run_experiments.sh: cannot cd to the repo root" >&2; exit 2; }
WHAT="${1:-all}"
case "$WHAT" in all|eqeq|negtchk) ;; *) echo "run_experiments.sh: argument must be all, eqeq or negtchk, not '$WHAT'" >&2; exit 2 ;; esac
OUT="${PL_OUT_DIR:-pnr_icc2/outputs}"; SIM="${PL_SIM_DIR:-pnr_icc2/sim}"; EXPD="${EXP_DIR:-pnr_icc2/sdf_experiment}"
RET="${LICENSE_RETRIES:-6}"; WAIT="${LICENSE_WAIT_S:-600}"
RUN="bash pnr_v2/sim/run_postlayout_sim.sh"
SUM="$SIM/experiments_summary.txt"
mkdir -p "$SIM" "$EXPD" || { echo "run_experiments.sh: cannot create $SIM / $EXPD" >&2; exit 2; }
: > "$SUM"
say() { echo "$*" | tee -a "$SUM"; }

# ---- 1. preconditions and the SDF copies ----
declare -A CK0
for c in ss ff; do
  f="$OUT/unpu_top_$c.sdf"
  [ -s "$f" ] || { echo "run_experiments.sh: $f missing or empty" >&2; exit 2; }
  CK0[$c]=$(cksum < "$f")
done
if [ "$WHAT" != negtchk ]; then
  echo "=== experiment 2 (nep_cond): SDF copies with === -> == in the COND lines, in $EXPD"
  for c in ss ff; do
    f="$OUT/unpu_top_$c.sdf"; g="$EXPD/unpu_top_${c}_eqeq.sdf"
    n_orig=$(grep -c '===' "$f"); n_cond=$(grep -c '(COND' "$f"); n_nocond=$(grep '===' "$f" | grep -vc '(COND')
    if [ "$n_nocond" -ne 0 ]; then echo "run_experiments.sh: $n_nocond lines with === are not COND lines in $f: the sed would change more than the COND arcs; stop" >&2; exit 2; fi
    sed '/(COND/ s/===/==/g' "$f" > "$g" || { echo "run_experiments.sh: sed failed for $f" >&2; exit 2; }
    n_copy=$(grep -c '===' "$g"); n_diff=$(diff "$f" "$g" | grep -c '^<')
    echo "    $c: lines with === in the original $n_orig (COND lines $n_cond), in the copy $n_copy, lines that differ $n_diff"
    if [ "$n_copy" -ne 0 ] || [ "$n_diff" -ne "$n_orig" ]; then echo "run_experiments.sh: the copy $g is not what the sed should make (expected 0 === and $n_orig differing lines); stop" >&2; exit 2; fi
  done
fi

# ---- 2. the simulator option for experiment 1 ----
NEGOPT=""
if [ "$WHAT" != eqeq ]; then
  if [ -n "${NEG_TCHK_OPT+x}" ]; then NEGOPT="$NEG_TCHK_OPT"; NEGSRC="NEG_TCHK_OPT"
  elif [ "${DRY_RUN:-0}" = 1 ]; then NEGOPT="-neg_tchk"; NEGSRC="dry run default"
  elif command -v xrun >/dev/null 2>&1; then
    HLP=$(xrun -helpall 2>&1 | grep -i 'neg' | head -n 20)
    echo "=== xrun options that mention neg:"; echo "$HLP" | sed 's/^/    /'
    if echo "$HLP" | grep -qi -- '-neg_tchk'; then NEGOPT="-neg_tchk"; NEGSRC="listed by xrun -helpall"; else NEGOPT=""; NEGSRC="NOT listed by xrun -helpall: the define alone is used"; fi
  else echo "run_experiments.sh: 'xrun' not found in PATH -- source ~/cad_cshrc first" >&2; exit 2; fi
  echo "=== experiment 1 (nl1_neg / net_remrec): XRUN_FLAGS = -define neg_tchk $NEGOPT  (option source: $NEGSRC)"
fi

# ---- 3. the runs (a FAIL verdict is expected when a cause is removed: the script goes on) ----
if [ "$WHAT" != negtchk ]; then
  for r in "ss nochecks A" "ff nochecks C"; do
    set -- $r
    env PL_SDF="$EXPD/unpu_top_${1}_eqeq.sdf" PL_LABEL=eqeq LICENSE_RETRIES="$RET" LICENSE_WAIT_S="$WAIT" $RUN "$1" "$2" 2>&1 | tee "$SIM/run${3}_eqeq_console.txt" | grep -E '^===|^--- (PASS|reasons)'
  done
fi
if [ "$WHAT" != eqeq ]; then
  for r in "ss checks B" "ff checks D"; do
    set -- $r
    env PL_LABEL=negtchk XRUN_FLAGS="-define neg_tchk $NEGOPT" LICENSE_RETRIES="$RET" LICENSE_WAIT_S="$WAIT" $RUN "$1" "$2" 2>&1 | tee "$SIM/run${3}_negtchk_console.txt" | grep -E '^===|^--- (PASS|reasons)'
  done
fi

# ---- 4. the checksum of the originals and the summary ----
say ""
say "################ EXPERIMENT SUMMARY (paste this block) ################"
for c in ss ff; do
  now=$(cksum < "$OUT/unpu_top_$c.sdf")
  say "original $OUT/unpu_top_$c.sdf unchanged: $([ "$now" = "${CK0[$c]}" ] && echo YES || echo NO-CHANGED-STOP)"
done
fact() {   # fact <log> -> one line of numbers
  local l="$1"
  [ -s "$l" ] || { echo "log missing or empty"; return; }
  local w; w=$(grep -m1 'Annotation completed' "$l" | sed -E 's/.*completed with ([0-9]+) Errors? and ([0-9]+) Warnings?.*/errors \1, warnings \2/')
  local pd; pd=$(grep -m1 'No. of Pathdelays' "$l" | sed -E 's/.*Annotated = ([0-9.]+%).*/\1/')
  echo "$w; pathdelays annotated ${pd:-n/a}; ALL CHECKS PASSED $(grep -c 'ALL CHECKS PASSED' "$l"); $(grep -oE 'checked [0-9]+ value' "$l" | tail -n1 | sed 's/ value//'); FAIL lines $(grep -c FAIL "$l"); *E/*F $(grep -cE '\*[EF],' "$l"); SDFNEP-COND $(grep -c 'SDFNEP.*COND' "$l"); SDFNL1 $(grep -c 'SDFNL1' "$l"); SDFNET $(grep -c 'SDFNET' "$l"); violation lines $(grep -ciE 'timing violation|TCHKVIO' "$l"); NOLICN $(grep -c NOLICN "$l")"
}
warn_of() { grep -m1 'Annotation completed' "$1" 2>/dev/null | sed -E 's/.*and ([0-9]+) Warnings?.*/\1/'; }   # the TRUE warning total of a log ("" when absent)
# the baseline of a corner = the warnings of the DEFAULT nochecks run (SDFNEP only: the same SDFNEP warnings appear in the checks runs); read from the standard log, never typed
base_of() { local f="$SIM/pl_${1}_nochecks.log"; [ -s "$f" ] && warn_of "$f"; }
if [ "$WHAT" != negtchk ]; then
  say "--- experiment 2 (=== -> ==):"
  for c in ss ff; do m=nochecks; say "    $c $m: $(fact "$SIM/pl_${c}_${m}_eqeq.log")"; done
  Bss=$(base_of ss); ncond=$(grep -c '(COND' "$OUT/unpu_top_ss.sdf"); Wss=$(warn_of "$SIM/pl_ss_nochecks_eqeq.log")
  say "    reference (the default nochecks run $SIM/pl_ss_nochecks.log): warnings ${Bss:-NOT AVAILABLE}; COND entries in the SDF $ncond"
  a=$(fact "$SIM/pl_ss_nochecks_eqeq.log")
  if [ -z "${Bss:-}" ] || [ -z "${Wss:-}" ]; then say "    READING: the default nochecks log or the experiment log has no 'Annotation completed' line: cannot compare, send this block to Planning"
  elif [ "$Wss" -eq $((Bss - ncond)) ] && echo "$a" | grep -q 'SDFNEP-COND 0;' && echo "$a" | grep -q 'ALL CHECKS PASSED 1;'; then
    say "    READING: the === was the cause: warnings fell from $Bss to $Wss (= minus the $ncond COND entries), no COND warning left, the run passes -> nep_cond needs NO approval"
  elif [ "$Wss" -eq "$Bss" ] && echo "$a" | grep -q 'ALL CHECKS PASSED 1;'; then say "    READING: unchanged ($Wss warnings, the same as the default run) and the run passes: the === was NOT the cause; nep_cond stays an approval question (a documented limitation)"
  elif echo "$a" | grep -q 'ALL CHECKS PASSED 0;'; then say "    READING: the run did not pass: send the log to Planning (a real race or an environment problem)"
  else say "    READING: another number (default $Bss, experiment $Wss): send this block to Planning"; fi
fi
if [ "$WHAT" != eqeq ]; then
  say "--- experiment 1 (neg_tchk, option '${NEGOPT:-none}'):"
  for c in ss ff; do m=checks; say "    $c $m: $(fact "$SIM/pl_${c}_${m}_negtchk.log")"; done
  Bss=$(base_of ss); Bff=$(base_of ff); Wss=$(warn_of "$SIM/pl_ss_checks_negtchk.log"); Wff=$(warn_of "$SIM/pl_ff_checks_negtchk.log")
  Dss=$(warn_of "$SIM/pl_ss_checks.log"); Dff=$(warn_of "$SIM/pl_ff_checks.log")
  say "    reference (the default runs): nochecks warnings ss ${Bss:-n/a} / ff ${Bff:-n/a} (SDFNEP only); default checks warnings ss ${Dss:-n/a} / ff ${Dff:-n/a}. The printed SDFNL1 / SDFNET counts are capped at 500: the TRUE counts are the warning totals"
  b=$(fact "$SIM/pl_ss_checks_negtchk.log"); d=$(fact "$SIM/pl_ff_checks_negtchk.log")
  if echo "$b$d" | grep -qE 'violation lines [1-9]'; then say "    READING: TIMING-CHECK VIOLATIONS appeared with the real limits: a REAL finding, send this block and the logs to Planning BEFORE any approval"
  elif echo "$b$d" | grep -q 'NOLICN [1-9]'; then say "    READING: a run died on the licence: run again later"
  elif [ -z "${Wss:-}" ] || [ -z "${Wff:-}" ]; then say "    READING: a checks log has no 'Annotation completed' line: cannot compare, send this block to Planning"
  elif echo "$b" | grep -q 'SDFNL1 0;' && echo "$d" | grep -q 'SDFNL1 0;' && echo "$b$d" | grep -q 'ALL CHECKS PASSED 1;' && ! echo "$b$d" | grep -q 'ALL CHECKS PASSED 0;'; then
    if [ -z "${Bss:-}" ] || [ -z "${Bff:-}" ]; then say "    READING: neg_tchk removed nl1_neg (SDFNL1 0) and the checks pass; the remaining net_remrec count cannot be computed (no default nochecks log for the baseline): total warnings ss $Wss / ff $Wff"
    else
      Nss=$((Wss - Bss)); Nff=$((Wff - Bff))
      if [ "$Nss" -le 0 ] && [ "$Nff" -le 0 ]; then say "    READING: both classes are gone and the checks pass -> nl1_neg and net_remrec need NO approval"
      else say "    READING: neg_tchk removed nl1_neg (SDFNL1 0); net_remrec reduced to $Nss (ss) / $Nff (ff) removal/recovery warnings (= total $Wss / $Wff minus the nochecks baseline $Bss / $Bff); the checks pass with 0 violations; the verdict of this run says FAIL (reconciliation: Xcelium counted FEWER warnings than the SDF predicts) only because the prediction still counts the removed class"; fi
    fi
  elif echo "$b" | grep -qE 'SDFNL1 [1-9]'; then say "    READING: the messages remain: the define / option had no effect; nothing learned, the approval question stays"
  else say "    READING: another outcome: send this block to Planning"; fi
fi
say "################ END OF SUMMARY ################"
echo "(also in $SUM)"
