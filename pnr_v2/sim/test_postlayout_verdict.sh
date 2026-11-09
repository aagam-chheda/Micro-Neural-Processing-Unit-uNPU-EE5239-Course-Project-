#!/usr/bin/env bash
# Test of the verdict logic of pnr_v2/sim/run_postlayout_sim.sh (task 075) on SAMPLE log texts, plus the dry-run output and the usage errors.
# It proves nothing about Xcelium: the message wordings in the samples are written from knowledge of Xcelium (VERIFY on the server).
# Run: bash pnr_v2/sim/test_postlayout_verdict.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/run_postlayout_sim.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
npass=0; nfail=0
ok()  { npass=$((npass+1)); }
bad() { nfail=$((nfail+1)); echo "FAIL: $1"; }
chk() { if [ "$2" = 1 ]; then ok; else bad "$1"; fi; }

ANN='ncsim: SDF annotation of unpu_top_ss.sdf onto unpu_top_tb.dut
SDF statistics: 187654 delays annotated, 0 not annotated
'
GOODBODY='xcelium 22.09
'"$ANN"'checked 343341 value(s)/assertion(s) total
ALL CHECKS PASSED
Simulation complete via $finish(1) at time 138350796 NS + 0
'
mklog() { printf '%s' "$1" > "$T/$2.log"; }
# judge <name> <mode>  -> sets rc and out
judge() { out=$(judge_log "$T/$1.log" "$2" "${3:-}" 2>&1); rc=$?; }

# 1. PASS in checks and in nochecks mode
mklog "$GOODBODY" good
judge good checks;   chk "good log passes in checks mode" $([ $rc -eq 0 ] && echo 1 || echo 0)
judge good nochecks; chk "the same good log passes in nochecks mode" $([ $rc -eq 0 ] && echo 1 || echo 0)
chk "the verdict prints the simulated end time" $(echo "$out" | grep -q 'simulated end: at time 138350796 NS' && echo 1 || echo 0)
chk "the verdict prints the annotation lines" $(echo "$out" | grep -q '187654 delays annotated' && echo 1 || echo 0)
chk "nochecks mode says violations are not judged" $(echo "$out" | grep -q 'not judged in nochecks mode' && echo 1 || echo 0)

# 2. FAIL by a missing ALL CHECKS PASSED
mklog "$ANN"'checked 343341 value(s)/assertion(s) total
' nopass
judge nopass checks; chk "missing ALL CHECKS PASSED is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'no ALL CHECKS PASSED line' && echo 1 || echo 0)

# 3. wrong check counts
mklog "$ANN"'checked 343340 value(s)/assertion(s) total
ALL CHECKS PASSED
' c340
judge c340 checks; chk "343340 checks is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'checks reported 343340, expected 343341' && echo 1 || echo 0)
mklog "$ANN"'checked 343342 value(s)/assertion(s) total
ALL CHECKS PASSED
' c342
judge c342 checks; chk "343342 checks is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
mklog "$ANN"'ALL CHECKS PASSED
' cnone
judge cnone checks; chk "no 'checked N' line is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'checks reported none' && echo 1 || echo 0)

# 4. *E, and *F, lines
mklog "$GOODBODY"'xmelab: *E,CUVMUR: instance of module unresolved
' errE
judge errE checks; chk "an *E, line is FAIL even with ALL CHECKS PASSED" $([ $rc -eq 1 ] && echo "$out" | grep -q '1 \*E,/\*F, lines' && echo 1 || echo 0)
mklog "$GOODBODY"'xmsim: *F,INTERR: INTERNAL EXCEPTION
' errF
judge errF nochecks; chk "an *F, line is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)

# 5. FAIL lines of the testbench
mklog "$ANN"'FAIL [x]: mem C[0][0]=1 expected 2
FAIL [y]: b
checked 343341 value(s)/assertion(s) total
ALL CHECKS PASSED
' failx
judge failx checks; chk "FAIL lines are FAIL and are printed" $([ $rc -eq 1 ] && echo "$out" | grep -q 'FAIL \[x\]: mem C' && echo "$out" | grep -q '2 lines with FAIL' && echo 1 || echo 0)
mklog "$ANN"'checked 343341 value(s)/assertion(s) total
2 FAILURE(S) (checks=343341)
' failure
judge failure checks; chk "'N FAILURE(S)' line is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)

# 6. setup/hold violations in checks mode
VIOL='Warning! Timing violation: $hold( posedge CP:12345 ps, negedge D:12400 ps, 140 ps ) unpu_top_tb.dut.u_csr.src_a_reg_reg_1_
Timing violation in unpu_top_tb.dut.u_grid.pe $setup( D, posedge CP, 0.14 ) at 5000000 ps
'
mklog "$GOODBODY$VIOL" viol
judge viol checks;   chk "timing violations in checks mode are FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'timing-check violations (checks mode): 2' && echo "$out" | grep -q '2 timing-check violations' && echo 1 || echo 0)
chk "the violation lines (instance) are printed" $(echo "$out" | grep -q 'u_csr.src_a_reg_reg_1_' && echo 1 || echo 0)
judge viol nochecks; chk "the same text is not judged as violations in nochecks mode (the checks are off there)" $([ $rc -eq 0 ] && echo 1 || echo 0)
mklog "$GOODBODY"'*W,TCHKVIO: Timing check violation $width( negedge CP, 0.2 ) in unpu_top_tb.dut.x
' viol2
judge viol2 checks; chk "a *W,TCHKVIO line is a violation in checks mode" $([ $rc -eq 1 ] && echo 1 || echo 0)
# the SDF annotation statistics mention SETUPHOLD but are not violations
mklog "$GOODBODY"'SDF annotation: 1200 SETUPHOLD timing checks annotated
' notviol
judge notviol checks; chk "an annotation line that mentions SETUPHOLD is not a violation" $([ $rc -eq 0 ] && echo 1 || echo 0)

# 7. empty and missing logs
: > "$T/empty.log"
judge empty checks; chk "an empty log is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'is empty' && echo 1 || echo 0)
out=$(judge_log "$T/missing.log" checks 2>&1); rc=$?; chk "a missing log is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'does not exist' && echo 1 || echo 0)

# 8. SDF instance-not-found warnings
mklog "$GOODBODY"'xmelab: *W,SDFNEP: unable to find the instance u_grid/g_row_0__g_col_0__pe/U1 in the SDF scope
xmelab: *W,SDFNEP: unable to find the instance u_csr/U7 in the SDF scope
' sdfnf
judge sdfnf checks; chk "SDF not-found warnings are FAIL, counted by message id" $([ $rc -eq 1 ] && echo "$out" | grep -q '2 SDF not-found warnings' && echo "$out" | grep -qE '^ +2 \*W,SDFNEP' && echo 1 || echo 0)
mklog "$GOODBODY"'SDF: instance u_x/U1 not found in the design
' sdfnf2
judge sdfnf2 nochecks; chk "a plain 'not found' SDF line is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
# the separate annotation log is read too
mklog "$GOODBODY" withann
printf 'SDF annotation log\n  cell u_a/U9 not found in the design\n  0 delays annotated\n' > "$T/ann.log"
judge withann checks "$T/ann.log"; chk "a not-found line in the annotation log is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
mklog "$GOODBODY" withann2
printf 'SDF annotation log\n  187654 delays annotated\n' > "$T/ann2.log"
judge withann2 checks "$T/ann2.log"; chk "a clean annotation log passes" $([ $rc -eq 0 ] && echo 1 || echo 0)

# 9. no annotation message at all: nothing proves the SDF was applied
mklog 'checked 343341 value(s)/assertion(s) total
ALL CHECKS PASSED
' noann
judge noann checks; chk "no SDF annotation message is FAIL (a silent run would be a zero-delay run)" $([ $rc -eq 1 ] && echo "$out" | grep -q 'no SDF annotation message' && echo 1 || echo 0)

# 10. dry run and usage (from a temporary copy of the repo layout is not needed: the dry run only prints)
d=$(DRY_RUN=1 bash "$HERE/run_postlayout_sim.sh" ss nochecks 2>&1); rc=$?
chk "dry run ss nochecks: exit 0" $([ $rc -eq 0 ] && echo 1 || echo 0)
chk "dry run ss: MTM_CONTROL MAXIMUM, scope unpu_top_tb.dut, SDF_FILE of ss" $(echo "$d" | grep -q 'MTM_CONTROL = "MAXIMUM"' && echo "$d" | grep -q 'SCOPE = unpu_top_tb.dut' && echo "$d" | grep -q 'SDF_FILE = "pnr_icc2/outputs/unpu_top_ss.sdf"' && echo 1 || echo 0)
chk "dry run nochecks: -notimingchecks is in the xrun line" $(echo "$d" | grep -q '^ *xrun .*-notimingchecks' && echo 1 || echo 0)
d=$(DRY_RUN=1 bash "$HERE/run_postlayout_sim.sh" ff checks 2>&1)
chk "dry run ff checks: MINIMUM, no -notimingchecks, the ff SDF, xmlibdirname pl_ff_checks" $(echo "$d" | grep -q 'MTM_CONTROL = "MINIMUM"' && ! echo "$d" | grep -q -- '-notimingchecks' && echo "$d" | grep -q 'unpu_top_ff.sdf' && echo "$d" | grep -q -- '-xmlibdirname xrun_out/pl_ff_checks' && echo 1 || echo 0)
chk "dry run: the passed flags of handoff 18.7 are in the line" $(echo "$d" | grep -q -- '-sv -64bit -access +r -timescale 1ns/1ps -top unpu_top_tb -define GLS_CLK_HALF_NS=10' && echo 1 || echo 0)
chk "dry run: the log goes under pnr_icc2/sim/" $(echo "$d" | grep -q -- '-l pnr_icc2/sim/pl_ff_checks.log' && echo 1 || echo 0)
chk "dry run: the model is the one combined file" $(echo "$d" | grep -q 'vcs_sim_model/tsl18fs120_scl.v' && echo 1 || echo 0)
chk "dry run: nothing was created" $([ ! -e "$HERE/../../pnr_icc2/sim" ] && echo 1 || echo 0)
out=$(bash "$HERE/run_postlayout_sim.sh" xx checks 2>&1); rc=$?; chk "bad corner: exit 2" $([ $rc -eq 2 ] && echo 1 || echo 0)
out=$(bash "$HERE/run_postlayout_sim.sh" ss foo 2>&1); rc=$?; chk "bad mode: exit 2" $([ $rc -eq 2 ] && echo 1 || echo 0)
out=$(bash "$HERE/run_postlayout_sim.sh" 2>&1); rc=$?; chk "no argument: exit 2 and usage text" $([ $rc -eq 2 ] && echo "$out" | grep -q 'Usage' && echo 1 || echo 0)
out=$(bash "$HERE/run_postlayout_sim.sh" ss checks 2>&1); rc=$?; chk "missing inputs (no DRY_RUN): exit 2" $([ $rc -eq 2 ] && echo "$out" | grep -q 'missing or empty' && echo 1 || echo 0)

echo "RESULT: $npass passed, $nfail failed"
[ "$nfail" -eq 0 ]
