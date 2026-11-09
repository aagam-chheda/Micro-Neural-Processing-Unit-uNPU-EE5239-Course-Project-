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

# 8. SDF instance-not-found warnings (an SDFNEP that is NOT of the accepted IOPATH edge form is still a FAIL)
mklog "$GOODBODY"'xmelab: *W,SDFNEP: unable to find the instance u_grid/g_row_0__g_col_0__pe/U1 in the SDF scope
xmelab: *W,SDFNEP: unable to find the instance u_csr/U7 in the SDF scope
' sdfnf
judge sdfnf checks; chk "SDFNEP instance-not-found lines are FAIL, counted" $([ $rc -eq 1 ] && echo "$out" | grep -q '2 SDFNEP warnings outside the accepted class' && echo "$out" | grep -qE '^ +2 \*W,SDFNEP' && echo 1 || echo 0)
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

# 8b. the real compile error of the first server run: the SDF header said OVI 2.1 but the file had REMOVAL entries
mklog "$GOODBODY"'xmsdfc: *E,SDFIRE: pnr_icc2/outputs/unpu_top_ss.sdf, line 872: Syntax Error: REMOVAL keyword is only allowed in SDFVERSION of 3.0 or later
xmelab: *W,SDFCNC: Cannot compile SDF file - skipping annotation
' sdfc
judge sdfc nochecks
chk "SDFIRE/SDFCNC lines are FAIL even with ALL CHECKS PASSED and 343341 checks" $([ $rc -eq 1 ] && echo 1 || echo 0)
chk "the verdict prints the two real lines" $(echo "$out" | grep -q 'Syntax Error: REMOVAL keyword is only allowed' && echo "$out" | grep -q 'Cannot compile SDF file - skipping annotation' && echo 1 || echo 0)
chk "the verdict says the run had zero delays" $(echo "$out" | grep -q 'ran with zero delays' && echo 1 || echo 0)
chk "the reasons carry the hint: check the SDFVERSION (needs 3.0 if it has REMOVAL/RECOVERY entries) and regenerate with pv.tcl" $(echo "$out" | grep -q 'the SDF could not be compiled: check the SDFVERSION (needs 3.0 if it has REMOVAL/RECOVERY entries) and regenerate with pv.tcl' && echo 1 || echo 0)
judge sdfc checks; chk "the same in checks mode is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
judge good nochecks; chk "a good log has no compile-error block and no hint" $([ $rc -eq 0 ] && ! echo "$out" | grep -q 'SDF compile errors' && ! echo "$out" | grep -q 'could not be compiled' && echo 1 || echo 0)
# the SDF info block: version line and REMOVAL/RECOVERY counts, with a warning for OVI 2.1 + REMOVAL
printf '(DELAYFILE\n(SDFVERSION "OVI 2.1")\n(DESIGN "unpu_top")\n(DIVIDER /)\n(CELL (INSTANCE u1) (TIMINGCHECK (REMOVAL RN (posedge CP) (0:0:0)) (RECOVERY RN (posedge CP) (0:0:0))))\n' > "$T/ovi.sdf"
info=$(sdf_info "$T/ovi.sdf" 2>&1)
chk "sdf_info prints the SDFVERSION line and the REMOVAL + RECOVERY count" $(echo "$info" | grep -q 'SDF version line: (SDFVERSION "OVI 2.1"); REMOVAL + RECOVERY entries: 2' && echo 1 || echo 0)
chk "sdf_info warns about OVI 2.1 with REMOVAL entries" $(echo "$info" | grep -q 'WARNING: the header is not SDFVERSION "3.0" but the file has 2 REMOVAL/RECOVERY entries' && echo 1 || echo 0)
printf '(DELAYFILE\n(SDFVERSION "3.0")\n(DESIGN "unpu_top")\n(CELL (INSTANCE u1) (TIMINGCHECK (REMOVAL RN (posedge CP) (0:0:0))))\n' > "$T/v3.sdf"
info=$(sdf_info "$T/v3.sdf" 2>&1)
chk "sdf_info: no warning for a 3.0 file" $(echo "$info" | grep -q 'SDF version line: (SDFVERSION "3.0")' && ! echo "$info" | grep -q WARNING && echo 1 || echo 0)

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

# 11. the bounded SDF acceptance (task 077; run A3, 2026-11-09, user approval): exact lines of the real run on top of a good log
NCAP='xmelab: *W,SDFNCAP (unpu_top_ss.sdf,1234): The interconnect source unpu_top_tb.dut.n1 is separated by a unidirectional continuous assign from the destination unpu_top_tb.dut.u_a.U1.A. The port annotation will still occur.
'
NEP1='xmelab: *W,SDFNEP (unpu_top_ss.sdf,31510): Unable to annotate to non-existent path (IOPATH (posedge A) S) of instance unpu_top_tb.dut.u_dma.add_212_3.U3 of module ah01d1 <unpu_top_ss.sdf, line 31510>.
'
NEP2='xmelab: *W,SDFNEP (unpu_top_ss.sdf,40001): Unable to annotate to non-existent path (IOPATH (negedge S) Z) of instance unpu_top_tb.dut.u_grid.U77 of module mx02d0 <unpu_top_ss.sdf, line 40001>.
xmelab: *W,SDFNEP (unpu_top_ss.sdf,40002): Unable to annotate to non-existent path (IOPATH (posedge S) Z) of instance unpu_top_tb.dut.u_grid.U78 of module mx02d0 <unpu_top_ss.sdf, line 40002>.
'
CAVEAT_RE='PASS \(with the documented SDF limitation: 3 SDFNEP warnings on mux-select, XOR/XNOR and adder-sum arcs ran at zero delay; the simulation is slightly optimistic on those arcs; timing sign-off is PrimeTime\)'
mklog "$GOODBODY$NCAP$NEP1$NEP2" lim
judge lim nochecks
chk "SDFNCAP + SDFNEP (ah01d1, mx02d0) on a good log: PASS" $([ $rc -eq 0 ] && echo 1 || echo 0)
chk "the verdict word carries the documented limitation with the count" $(echo "$out" | grep -qE -- "^--- $CAVEAT_RE" && echo 1 || echo 0)
chk "table: count per cell type" $(echo "$out" | grep -qE '^ +2 mx02d0' && echo "$out" | grep -qE '^ +1 ah01d1' && echo 1 || echo 0)
chk "table: count per arc form" $(echo "$out" | grep -qE '^ +1 \(posedge A\) S' && echo "$out" | grep -qE '^ +1 \(negedge S\) Z' && echo "$out" | grep -qE '^ +1 \(posedge S\) Z' && echo 1 || echo 0)
chk "table: totals (3 accepted, 0 outside)" $(echo "$out" | grep -q 'SDFNEP: total 3; in the accepted class .*: 3; outside it: 0' && echo 1 || echo 0)
chk "SDFNCAP is information with its own id line" $(echo "$out" | grep -q 'SDFNCAP (INFORMATION, not a failure.*): 1; the first 3' && echo "$out" | grep -qE '^ +1 \*W,SDFNCAP' && echo "$out" | grep -q 'port annotation will still occur' && echo 1 || echo 0)
chk "no cap note without the MXWARN line" $(! echo "$out" | grep -q 'message cap of 1000' && echo 1 || echo 0)
judge lim checks; chk "the same in checks mode is PASS with the caveat (no violation lines)" $([ $rc -eq 0 ] && echo "$out" | grep -qE -- "^--- $CAVEAT_RE" && echo 1 || echo 0)
# the caveat is exported to main through JUDGE_CAVEAT (not in a subshell here)
judge_log "$T/lim.log" nochecks >/dev/null 2>&1; chk "JUDGE_CAVEAT is set for the limited PASS" $(echo "$JUDGE_CAVEAT" | grep -q '^PASS (with the documented SDF limitation: 3 SDFNEP' && echo 1 || echo 0)
judge_log "$T/good.log" nochecks >/dev/null 2>&1; chk "JUDGE_CAVEAT is empty for a clean PASS" $([ -z "$JUDGE_CAVEAT" ] && echo 1 || echo 0)
judge good nochecks; chk "a clean PASS does not print the limitation" $(! echo "$out" | grep -q 'documented SDF limitation' && echo 1 || echo 0)
# the cap line
CAP="xmelab: *W,MXWARN: Reached maximum warning limit for 'SDFNEP'(1000)
"
mklog "$GOODBODY$NCAP$NEP1$CAP" limcap
judge limcap nochecks; chk "the MXWARN cap line prints the NOTE and still PASSES with the caveat" $([ $rc -eq 0 ] && echo "$out" | grep -q 'NOTE: the message cap of 1000 was reached: the real count is higher' && echo 1 || echo 0)
chk "the cap NOTE does not appear for the SDFNEP-less log" $(! judge_log "$T/good.log" nochecks 2>&1 | grep -q 'message cap' && echo 1 || echo 0)
# a cell type not in the list
NEPBAD='xmelab: *W,SDFNEP (unpu_top_ss.sdf,50000): Unable to annotate to non-existent path (IOPATH (posedge A) Z) of instance unpu_top_tb.dut.u_x.U9 of module nd02d1 <unpu_top_ss.sdf, line 50000>.
'
mklog "$GOODBODY$NCAP$NEP1$NEP2$NEPBAD" limbad
judge limbad nochecks; chk "an SDFNEP on a cell type outside the list is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'cell type nd02d1 is not in the allowed list' && echo "$out" | grep -q '1 SDFNEP warnings outside the accepted class' && echo 1 || echo 0)
chk "no limited-PASS word on a FAIL" $(! echo "$out" | grep -q '^--- PASS (with' && echo 1 || echo 0)
# a non-IOPATH form
NEPFORM='xmelab: *W,SDFNEP (unpu_top_ss.sdf,50001): Unable to annotate to non-existent path (SETUPHOLD (posedge D) (posedge CP)) of instance unpu_top_tb.dut.u_x.U9 of module mx02d0 <unpu_top_ss.sdf, line 50001>.
'
mklog "$GOODBODY$NCAP$NEP1$NEPFORM" limform
judge limform nochecks; chk "an SDFNEP that is not an IOPATH edge form is FAIL even on an allowed cell" $([ $rc -eq 1 ] && echo "$out" | grep -q 'not of the form IOPATH' && echo 1 || echo 0)
NEPNOEDGE='xmelab: *W,SDFNEP (unpu_top_ss.sdf,50002): Unable to annotate to non-existent path (IOPATH A S) of instance unpu_top_tb.dut.u_x.U9 of module ah01d1 <unpu_top_ss.sdf, line 50002>.
'
mklog "$GOODBODY$NEPNOEDGE" limnoedge
judge limnoedge nochecks; chk "an IOPATH without an edge qualifier is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
# another SDF id
mklog "$GOODBODY$NCAP$NEP1"'xmelab: *W,SDFINF: something else about the SDF
' limid
judge limid nochecks; chk "an unknown SDF id (*W,SDFINF) is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q '1 SDF warnings of an id that is not accepted' && echo "$out" | grep -q 'SDFINF' && echo 1 || echo 0)
# SDFCNC / SDFIRE together with an otherwise accepted log
mklog "$GOODBODY$NCAP$NEP1"'xmelab: *W,SDFCNC: Cannot compile SDF file - skipping annotation
' limcnc
judge limcnc nochecks; chk "SDFCNC is FAIL even next to the accepted class" $([ $rc -eq 1 ] && echo "$out" | grep -q 'could not be compiled' && echo 1 || echo 0)
# no annotation message at all, with the accepted warnings present: the warning lines are not annotation evidence
mklog 'checked 343341 value(s)/assertion(s) total
ALL CHECKS PASSED
'"$NCAP$NEP1" limnoann
judge limnoann nochecks; chk "no annotation message (only the SDFNCAP/SDFNEP lines mention annotate) is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'no SDF annotation message' && echo 1 || echo 0)
# only SDFNCAP
mklog "$GOODBODY$NCAP" ncaponly
judge ncaponly nochecks; chk "only SDFNCAP: PASS" $([ $rc -eq 0 ] && echo 1 || echo 0)
chk "only SDFNCAP: the information line is printed and there is NO limitation caveat" $(echo "$out" | grep -q 'SDFNCAP (INFORMATION' && ! echo "$out" | grep -q 'documented SDF limitation' && echo 1 || echo 0)
judge_log "$T/ncaponly.log" nochecks >/dev/null 2>&1; chk "only SDFNCAP: JUDGE_CAVEAT empty" $([ -z "$JUDGE_CAVEAT" ] && echo 1 || echo 0)
# a cap on another SDF id hides the rest of that class
mklog "$GOODBODY$NCAP$NEP1"$'xmelab: *W,MXWARN: Reached maximum warning limit for \'SDFXYZ\'(1000)\n' limcap2
judge limcap2 nochecks; chk "a cap on another SDF id is FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'message cap was reached for an SDF message id other than' && echo 1 || echo 0)
# other failures still fail next to the accepted class
mklog "$GOODBODY$NCAP$NEP1"'xmelab: *E,CUVMUR: instance unresolved
' limerr
judge limerr nochecks; chk "an *E, line next to the accepted class is still FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
mklog "$ANN$NCAP$NEP1"'checked 343340 value(s)/assertion(s) total
ALL CHECKS PASSED
' limcnt
judge limcnt nochecks; chk "a wrong check count next to the accepted class is still FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
chk "the allowed cell list is the one approved in run A3" $([ "$SDFNEP_ALLOWED_CELLS" = "mx02d0 mx02d1 mi02d0 mi02d1 ah01d1 ad01d0 xr02d1 xn02d1" ] && echo 1 || echo 0)

echo "RESULT: $npass passed, $nfail failed"
[ "$nfail" -eq 0 ]
