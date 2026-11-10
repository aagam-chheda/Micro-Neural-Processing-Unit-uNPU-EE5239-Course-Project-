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

# ======================================================================================================================
# 12. Task 094 (run 3, final layout): COND-form SDFNEP, SDFNL1 / SDFNET with source-context lines, the violation count, the true counts from the SDF, NOLICN, SDF_ACCEPT, the retry loop
# ======================================================================================================================
# a fake cell model: the module dfcrn2 starts at line 11670 (the lines 11679..11681 of the real model are three checks of dfcrn2); a second module below it
{ for i in $(seq 1 11669); do echo "// pad"; done; echo "module dfcrn2 (D,CP,CDN,QN);"; for i in $(seq 1 20); do echo "// body"; done; echo "endmodule"; echo "module other (A,Z);"; for i in $(seq 1 20); do echo "// body"; done; echo "endmodule"; } > "$T/model.v"
CTX=' $hold  (posedge CP &&& (CDN==1'"'"'b1),posedge D &&& (CDN==1'"'"'b1),th_cp_d_l,notifier);
     |
'
nl1() { printf '%sxmelab: *W,SDFNL1 (%s,%s|5): Attempt to annotate a negative value to a 1 limit timing check in instance (unpu_top_tb.dut.u_seq.cycle_reg_1_), setting to 0 <\n' "$CTX" "$T/model.v" "$1"; }
NL1="$(nl1 11681)"$'\n'"$(nl1 11680)"$'\n'"$(nl1 11679)"$'\n'   # command substitution strips the last newline: put it back
NET1='xmelab: *W,SDFNET: Unable to annotate to non-existent timing check (REMOVAL (posedge CDN) (posedge CP) (0.43)) of instance unpu_top_tb.dut.u_seq.cycle_reg_1_ of module dfcrn2 <./pnr_icc2/outputs/unpu_top_ss.sdf, line 6634>.
xmelab: *W,SDFNET: Unable to annotate to non-existent timing check (REMOVAL (negedge CDN) (posedge CP) (0)) of instance unpu_top_tb.dut.u_seq.cycle_reg_1_ of module dfcrn2 <./pnr_icc2/outputs/unpu_top_ss.sdf, line 6635>.
xmelab: *W,SDFNET: Unable to annotate to non-existent timing check (RECOVERY (negedge CDN) (posedge CP) (0)) of instance unpu_top_tb.dut.u_seq.cycle_reg_1_ of module dfcrn2 <./pnr_icc2/outputs/unpu_top_ss.sdf, line 6637>.
'
COND1='xmelab: *W,SDFNEP: Unable to annotate to non-existent path (COND ((B===0)&&(CI===0)) (IOPATH A S)) of instance unpu_top_tb.dut.u_dma.mult_117_U4 of module ad01d0 <./pnr_icc2/outputs/unpu_top_ss.sdf, line 31439>.
xmelab: *W,SDFNEP: Unable to annotate to non-existent path (COND ((B===0)&&(CI===1)) (IOPATH A S)) of instance unpu_top_tb.dut.u_dma.mult_117_U4 of module ad01d0 <./pnr_icc2/outputs/unpu_top_ss.sdf, line 31440>.
'
STATS='	Annotation completed with 0 Errors and 9 Warnings
	SDF statistics:
		 No. of Pathdelays = 63337   	 No. of Disabled Pathdelays = 0        Annotated = 47.56% (30122/63337)
		 No. of Tchecks    = 25065   	 No. of Disabled Tchecks    = 0        Annotated = 60.66% (15205/25065)
'
# 12a. the COND form: a FAIL by default (needs approval), PASS with the approval; the verdict words name it
mklog "$GOODBODY$NCAP$NEP1$COND1" cond
judge cond nochecks
chk "COND-form SDFNEP on ad01d0: FAIL by default, class nep_cond not approved" $([ $rc -eq 1 ] && echo "$out" | grep -q 'SDF class nep_cond: 2 warning(s) (printed lines only), NOT approved' && echo 1 || echo 0)
chk "COND-form lines are counted as their own class, not as 'not of the form IOPATH'" $(echo "$out" | grep -q 'COND form (class nep_cond, needs approval): 2 (printed lines)' && ! echo "$out" | grep -q 'not of the form IOPATH' && echo 1 || echo 0)
out=$(SDF_ACCEPT=nep_cond judge_log "$T/cond.log" nochecks 2>&1); rc=$?
chk "with SDF_ACCEPT=nep_cond: PASS and the verdict words name the class" $([ $rc -eq 0 ] && echo "$out" | grep -q "PASS (with documented SDF limitations, SDF_ACCEPT='nep_cond': 1 SDFNEP edge-form arcs" && echo "$out" | grep -q '2 SDFNEP COND-form arcs' && echo 1 || echo 0)
out=$(SDF_ACCEPT="nep_cond,nl1_neg" judge_log "$T/cond.log" nochecks 2>&1); rc=$?
chk "SDF_ACCEPT also takes commas" $([ $rc -eq 0 ] && echo 1 || echo 0)
NEPCONDBAD='xmelab: *W,SDFNEP: Unable to annotate to non-existent path (COND ((B===0)&&(CI===0)) (IOPATH A S)) of instance unpu_top_tb.dut.u_x.U9 of module nd02d1 <./x.sdf, line 5>.
'
mklog "$GOODBODY$NCAP$NEP1$NEPCONDBAD" condbad
out=$(SDF_ACCEPT=nep_cond judge_log "$T/condbad.log" nochecks 2>&1); rc=$?
chk "an approved class does not cover a COND arc on a cell outside its list (nd02d1): FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'cell type nd02d1 is not in the COND list' && echo 1 || echo 0)
# 12b. SDFNL1 / SDFNET with source-context lines (checks mode): FAIL by default, PASS when all three classes are approved; the context lines are NOT violations
mklog "$GOODBODY$NCAP$NEP1$COND1$NL1$NET1" chk
judge chk checks
chk "checks mode, run-3 shape: the 9 source-context lines are not violations" $(echo "$out" | grep -q 'timing-check violations (checks mode): 0 ' && echo 1 || echo 0)
chk "SDFNL1 and SDFNET are named by class in the reasons (not 'an id that is not accepted')" $([ $rc -eq 1 ] && echo "$out" | grep -q 'SDF class nl1_neg: 3 warning' && echo "$out" | grep -q 'SDF class net_remrec: 3 warning' && ! echo "$out" | grep -q 'of an id that is not accepted' && echo 1 || echo 0)
out=$(SDF_ACCEPT="nep_cond nl1_neg net_remrec" judge_log "$T/chk.log" checks 2>&1); rc=$?
chk "all three classes approved (printed lines only, model attribution of the SDFNL1 lines): PASS" $([ $rc -eq 0 ] && echo "$out" | grep -q 'negative hold/recovery limits of reset flops were clamped to 0' && echo "$out" | grep -q 'REMOVAL/RECOVERY(negedge) entries of reset flops were not annotated' && echo 1 || echo 0)
out=$(SDF_ACCEPT="nep_cond net_remrec" judge_log "$T/chk.log" checks 2>&1); rc=$?
chk "a class that is not approved stays a FAIL even with the others approved" $([ $rc -eq 1 ] && echo "$out" | grep -q 'SDF class nl1_neg' && ! echo "$out" | grep -q 'SDF class net_remrec' && echo 1 || echo 0)
# SDFNL1 whose model line is in another module
mklog "$GOODBODY$NCAP$NEP1$(nl1 11700)"$'\n' nl1other
out=$(SDF_ACCEPT=nl1_neg judge_log "$T/nl1other.log" checks 2>&1); rc=$?
chk "an SDFNL1 whose model line (11700) is in module 'other' (not a reset flop): FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q "module 'other', not in the reset-flop list" && echo 1 || echo 0)
mklog "$GOODBODY$NCAP$NEP1"'xmelab: *W,SDFNL1 (/no/such/model.v,11681|5): Attempt to annotate a negative value to a 1 limit timing check in instance (unpu_top_tb.dut.u_seq.f1), setting to 0 <
' nl1nomodel
out=$(SDF_ACCEPT=nl1_neg judge_log "$T/nl1nomodel.log" checks 2>&1); rc=$?
chk "an SDFNL1 whose model file cannot be read cannot be attributed: FAIL, never a silent pass" $([ $rc -eq 1 ] && echo "$out" | grep -q "module 'unknown'" && echo 1 || echo 0)
out=$(JUDGE_MODEL="$T/model.v" SDF_ACCEPT=nl1_neg judge_log "$T/nl1nomodel.log" checks 2>&1); rc=$?
chk "the same with JUDGE_MODEL pointing at the model: attributed to dfcrn2" $([ $rc -eq 0 ] && echo 1 || echo 0)
# 12c. a REAL violation (invented in the form of the NC-Verilog / Xcelium violation message; VERIFY on the first real one) is found next to the context lines
REALV='Warning!  Timing violation
		$setup( posedge D:5000 ps, posedge CP:5050 ps, 140 ps );
File: /storage/PDK/tsl18fs120_scl.v, line = 11940
Scope: unpu_top_tb.dut.u_seq.cycle_reg_1_
Time: 5050 PS
'
mklog "$GOODBODY$NCAP$NEP1$NL1$REALV" realv
out=$(SDF_ACCEPT=nl1_neg judge_log "$T/realv.log" checks 2>&1); rc=$?
chk "a real violation message is counted once (message and check line are one event) and is a FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'timing-check violations (checks mode): 1 (message lines 1, check lines with times 1' && echo "$out" | grep -q '1 timing-check violations' && echo 1 || echo 0)
chk "the violation lines are printed, the source-context lines are not" $(echo "$out" | grep -q 'Warning!  Timing violation' && echo "$out" | grep -q 'posedge D:5000 ps' && ! echo "$out" | sed -n '/^--- timing-check violations/,/^--- timing checks/p' | grep -q 'notifier' && echo 1 || echo 0)
mklog "$GOODBODY$NCAP$NEP1$NL1" noviol
out=$(SDF_ACCEPT=nl1_neg judge_log "$T/noviol.log" checks 2>&1); rc=$?
chk "a log with the context lines and 0 real violations: PASS" $([ $rc -eq 0 ] && echo 1 || echo 0)
# 12d. the timing checks must really be on in a checks run
mklog "$GOODBODY$NCAP$NEP1"'	No. of Tchecks    = 25065   	 No. of Disabled Tchecks    = 25065    Annotated = 0.00% (0/0)
' tcoff
judge tcoff checks
chk "checks run with all timing checks disabled: FAIL (0 violations would mean nothing)" $([ $rc -eq 1 ] && echo "$out" | grep -q 'timing checks are DISABLED in a checks run (25065 of 25065)' && echo 1 || echo 0)
judge tcoff nochecks
chk "the same statistics in a nochecks run are fine" $([ $rc -eq 0 ] && echo 1 || echo 0)
mklog "$GOODBODY$NCAP$NEP1"'	No. of Tchecks    = 25065   	 No. of Disabled Tchecks    = 0        Annotated = 60.66% (15205/25065)
' tcon
judge tcon checks
chk "checks run with 0 disabled: PASS and the statistics are printed" $([ $rc -eq 0 ] && echo "$out" | grep -q 'timing checks in this run (Xcelium.s statistics): 25065 checks, disabled 0' && echo 1 || echo 0)
judge good checks
chk "no statistics line in a checks log: only a NOTE, not a FAIL" $([ $rc -eq 0 ] && echo "$out" | grep -q "NOTE: the log has no 'No. of Tchecks'" && echo 1 || echo 0)
# 12e. the true counts from the SDF, reconciled with Xcelium's total
cat > "$T/fake.sdf" <<'SDFEOF'
(DELAYFILE
(SDFVERSION "3.0")
(CELL
  (CELLTYPE "mx02d0")
  (INSTANCE u_x/U1 )
  (DELAY
    (ABSOLUTE
    (IOPATH I0 Z (0.3::0.3)(0.4::0.4))
    (IOPATH (posedge S) Z (0.3::0.3)(0.4::0.4))
    (IOPATH (negedge S) Z (0.3::0.3)(0.4::0.4))
    )
  )
)
(CELL
  (CELLTYPE "ad01d0")
  (INSTANCE u_x/U2 )
  (DELAY
    (ABSOLUTE
    (IOPATH A CO (0.42::0.42)(0.57::0.59))
    (COND B===1'b0 && CI===1'b0 (IOPATH A S (0.28::0.28)(0.47::0.48)))
    (COND B===1'b0 && CI===1'b1 (IOPATH A S (0.62::0.64)(0.49::0.49)))
    )
  )
)
(CELL
  (CELLTYPE "dfcrn2")
  (INSTANCE u_seq/f1 )
  (DELAY
    (ABSOLUTE
    (IOPATH (posedge CP) QN (0.59::0.59)(0.63::0.63))
    )
  )
  (TIMINGCHECK
    (HOLD (posedge D)  (posedge CP) (-0.07::-0.07))
    (HOLD (negedge D)  (posedge CP) (-0.00::-0.00))
    (SETUP (posedge D)  (posedge CP) (0.11::0.11))
    (REMOVAL (posedge CDN)  (posedge CP) (0.43::0.43))
    (REMOVAL (negedge CDN)  (posedge CP) (0.00::0.00))
    (RECOVERY (posedge CDN)  (posedge CP) (-0.32::-0.32))
    (RECOVERY (negedge CDN)  (posedge CP) (0.00::0.00))
  )
)
)
SDFEOF
ex=$(sdf_expect "$T/fake.sdf" ss)
chk "sdf_expect: edge 2 on mx02d0 (the flop CP->QN edge is counted by the class but only the allowed cells are summed)" $([ "$(exp_sum "$ex" edge "mx02d0")" = 2 ] && [ "$(exp_sum "$ex" edge "$SDFNEP_ALLOWED_CELLS")" = 2 ] && echo 1 || echo 0)
chk "sdf_expect: cond 2, net 3 (2 REMOVAL + RECOVERY negedge), nl1 2 (-0.07 and -0.32; -0.00 is not negative)" $([ "$(exp_sum "$ex" cond)" = 2 ] && [ "$(exp_sum "$ex" net)" = 3 ] && [ "$(exp_sum "$ex" nl1)" = 2 ] && echo 1 || echo 0)
chk "exp_sum with a '!' list sums the cells NOT in it" $([ "$(exp_sum "$ex" cond '!ad01d0')" = 0 ] && [ "$(exp_sum "$ex" cond '!mx02d0')" = 2 ] && echo 1 || echo 0)
# checks run: 2 edge + 2 cond + 3 net + 2 nl1 = 9 warnings, as in STATS
mklog "$GOODBODY$NCAP$NEP1$COND1$NL1$NET1$STATS" rec
out=$(JUDGE_SDF="$T/fake.sdf" JUDGE_CORNER=ss SDF_ACCEPT="nep_cond nl1_neg net_remrec" judge_log "$T/rec.log" checks 2>&1); rc=$?
chk "reconciliation: 9 warnings of Xcelium = 9 explained by the SDF -> ok, PASS with the TRUE counts in the verdict words" $([ $rc -eq 0 ] && echo "$out" | grep -q 'explained by the SDF: 9; difference: 0  ->  reconciliation ok' && echo "$out" | grep -q "2 SDFNEP edge-form arcs" && echo "$out" | grep -q '2 SDFNEP COND-form arcs' && echo "$out" | grep -q '2 negative hold/recovery' && echo "$out" | grep -q '3 REMOVAL/RECOVERY' && echo 1 || echo 0)
chk "the class table is printed with the cells" $(echo "$out" | grep -q 'nep_cond .*yes .*2  ad01d0 2' && echo "$out" | grep -q 'net_remrec .*yes .*3  dfcrn2 3' && echo 1 || echo 0)
out=$(JUDGE_SDF="$T/fake.sdf" JUDGE_CORNER=ss judge_log "$T/rec.log" checks 2>&1); rc=$?
chk "with the SDF but without approval: FAIL with the TRUE counts in the reasons (no 'printed lines only')" $([ $rc -eq 1 ] && echo "$out" | grep -q 'SDF class nep_cond: 2 warning(s), NOT approved' && ! echo "$out" | grep -q 'printed lines only' && echo 1 || echo 0)
mklog "$GOODBODY$NCAP$NEP1$COND1$NL1$NET1${STATS/9 Warnings/12 Warnings}" recbad
out=$(JUDGE_SDF="$T/fake.sdf" JUDGE_CORNER=ss SDF_ACCEPT="nep_cond nl1_neg net_remrec" judge_log "$T/recbad.log" checks 2>&1); rc=$?
chk "Xcelium counts 12, the SDF explains 9: FAIL, the hidden part is not classified" $([ $rc -eq 1 ] && echo "$out" | grep -q 'Xcelium counted 12 SDF warnings, the SDF explains 9' && echo "$out" | grep -q 'MISMATCH' && echo 1 || echo 0)
mklog "$GOODBODY$NCAP$NEP1$COND1${STATS/9 Warnings/4 Warnings}" recno
out=$(JUDGE_SDF="$T/fake.sdf" JUDGE_CORNER=ss SDF_ACCEPT="nep_cond" judge_log "$T/recno.log" nochecks 2>&1); rc=$?
chk "nochecks: only the SDFNEP classes are expected (2 + 2 = 4 = Xcelium's 4): PASS" $([ $rc -eq 0 ] && echo "$out" | grep -q 'explained by the SDF: 4; difference: 0' && echo "$out" | grep -q 'nl1_neg and net_remrec do not apply' && echo 1 || echo 0)
# the message cap on SDFNL1 / SDFNET: acceptable only when the reconciliation proves the hidden part
CAPS="xmelab: *W,MXWARN: Reached maximum warning limit for 'SDFNL1'(1000).
xmelab: *W,MXWARN: Reached maximum warning limit for 'SDFNET'(1000).
"
mklog "$GOODBODY$NCAP$NEP1$COND1$NL1$NET1$CAPS$STATS" capok
out=$(JUDGE_SDF="$T/fake.sdf" JUDGE_CORNER=ss SDF_ACCEPT="nep_cond nl1_neg net_remrec" judge_log "$T/capok.log" checks 2>&1); rc=$?
chk "cap on SDFNL1/SDFNET with a reconciliation that holds: PASS" $([ $rc -eq 0 ] && echo 1 || echo 0)
out=$(SDF_ACCEPT="nep_cond nl1_neg net_remrec" judge_log "$T/capok.log" checks 2>&1); rc=$?
chk "the same cap WITHOUT the SDF to prove the hidden part: FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'message cap was reached for an SDF message id other than SDFNEP/SDFNCAP and the hidden part is not proven' && echo 1 || echo 0)
mklog "$GOODBODY$NCAP$NEP1$COND1$NL1$NET1${STATS/0 Errors/3 Errors}" errs
out=$(JUDGE_SDF="$T/fake.sdf" JUDGE_CORNER=ss SDF_ACCEPT="nep_cond nl1_neg net_remrec" judge_log "$T/errs.log" checks 2>&1); rc=$?
chk "'Annotation completed with 3 Errors' is a FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q "Xcelium's annotation reports 3 Errors" && echo 1 || echo 0)
# cells outside the approved list, seen in the SDF (an adder cell that is not in SDFNEP_COND_CELLS)
sed 's/"ad01d0"/"ad01d9"/' "$T/fake.sdf" > "$T/fake2.sdf"
out=$(JUDGE_SDF="$T/fake2.sdf" JUDGE_CORNER=ss SDF_ACCEPT="nep_cond nl1_neg net_remrec" judge_log "$T/rec.log" checks 2>&1); rc=$?
chk "an approved class with entries on a cell outside its list (ad01d9 in the SDF) is a FAIL" $([ $rc -eq 1 ] && echo "$out" | grep -q 'SDF class nep_cond: 2 COND-form entries are on cells outside the approved list' && echo 1 || echo 0)
# invalid SDF_ACCEPT
out=$(SDF_ACCEPT="nep_cond everything" judge_log "$T/good.log" nochecks 2>&1); rc=$?
chk "an unknown SDF_ACCEPT word is exit 2 with a text, nothing is judged" $([ $rc -eq 2 ] && echo "$out" | grep -q "SDF_ACCEPT contains 'everything', which is not an approvable class" && echo 1 || echo 0)
chk "the approvable classes and cell lists are the documented ones" $([ "$SDF_APPROVABLE" = "nep_cond nl1_neg net_remrec" ] && [ "$SDFNEP_COND_CELLS" = "ad01d0 ad01d1 ad01d4 xr03d1" ] && [ "$SDFCHK_CELLS" = "dfcrn1 dfcrn2 dfcrq2 decrq1" ] && echo 1 || echo 0)
chk "by default nothing new is accepted (SDF_ACCEPT is not set in the test environment)" $([ -z "${SDF_ACCEPT:-}" ] && echo 1 || echo 0)
# 12f. NOLICN: exit 2 and the licence block; with any other *E/*F it is a plain FAIL
LIC='Writing initial simulation snapshot: worklib.unpu_top_tb:sv

Trying to check out license...
	Xcelium_Limited_Single_Core 22.00 - Failed
	Xcelium_Single_Core 22.00 - Failed
xmsim: *F,NOLICN: Unable to checkout license for the simulation. '"'"'lic_error LMF-03015'"'"'.
'
mklog "$ANN$LIC" lic
printf 'FlexNet Licensing checkout error: Cannot connect to license server system.\n The license server manager (lmgrd) has not been started yet,\nFeature:       Incisive_HDL_Simulator\nServer name:   10.0.0.1\nLicense path:  5280@10.0.0.1:\nFlexNet Licensing error:-15,570.  System Error: 115 "Operation now in progress"\nFeature:       Incisive_HDL_Simulator\nServer name:   10.0.0.1\nLicense path:  5280@10.0.0.1:\n' > "$T/lic.console"
out=$(JUDGE_CONSOLE="$T/lic.console" judge_log "$T/lic.log" checks 2>&1); rc=$?
chk "NOLICN as the only *F: exit status 2, not 1" $([ $rc -eq 2 ] && echo 1 || echo 0)
chk "the licence block names the problem, prints the checkout lines and the log line" $(echo "$out" | grep -q 'ENVIRONMENT PROBLEM, nothing about the design was judged' && echo "$out" | grep -q 'Xcelium_Limited_Single_Core 22.00 - Failed' && echo "$out" | grep -q '\*F,NOLICN' && echo 1 || echo 0)
chk "the licence block prints the FlexNet feature, server, path and error from the console, counted" $(echo "$out" | grep -qE '2 Feature: +Incisive_HDL_Simulator' && echo "$out" | grep -q 'License path:  5280@10.0.0.1:' && echo "$out" | grep -q 'FlexNet Licensing error:-15,570' && echo "$out" | grep -q 'Cannot connect to license server system' && echo 1 || echo 0)
chk "no design verdict is printed for a licence-only death (no 'reasons:', no violation block)" $(! echo "$out" | grep -q 'reasons:' && ! echo "$out" | grep -q 'timing-check violations' && echo 1 || echo 0)
out=$(judge_log "$T/lic.log" checks 2>&1); rc=$?
chk "without a console file the block says what to paste" $([ $rc -eq 2 ] && echo "$out" | grep -q 'paste the lines around' && echo 1 || echo 0)
mklog "$ANN$LIC"'xmelab: *E,CUVMUR: instance of module unresolved
' licerr
judge licerr checks
chk "NOLICN together with another *E, line is a plain FAIL (exit 1)" $([ $rc -eq 1 ] && echo 1 || echo 0)
mklog "$ANN$LIC"'FAIL [x]: something
' licfail
judge licfail checks
chk "NOLICN together with a FAIL line is a plain FAIL (exit 1)" $([ $rc -eq 1 ] && echo 1 || echo 0)
mklog "$GOODBODY$LIC" licpass
judge licpass checks
chk "NOLICN in a log that also has the check lines is a FAIL, never exit 2" $([ $rc -eq 1 ] && echo 1 || echo 0)
# 12g. main: the retry loop, with a fake xrun that dies on the licence twice and then passes
RT="$T/rt"; mkdir -p "$RT/out"
printf '(DELAYFILE\n(SDFVERSION "3.0")\n)\n' > "$RT/out/unpu_top_ss.sdf"
echo "module x; endmodule" > "$RT/out/unpu_top_pnr_sim.v"; echo "module m; endmodule" > "$RT/model.v"
XCOUNT="$RT/count"; echo 0 > "$XCOUNT"
xrun() {
  local l="" a; local -a args=("$@"); local i
  for ((i=0; i<${#args[@]}; i++)); do [ "${args[$i]}" = "-l" ] && l="${args[$((i+1))]}"; done
  [ -n "$l" ] || { echo "fake xrun"; return 0; }   # `xrun -version` has no -l
  local n; n=$(cat "$XCOUNT"); n=$((n+1)); echo "$n" > "$XCOUNT"
  if [ "$n" -le "${FAKE_FAILS:-2}" ]; then printf 'Trying to check out license...\n\tXcelium_Single_Core 22.00 - Failed\nxmsim: *F,NOLICN: Unable to checkout license\n' > "$l"; return 2; fi
  printf '%sANN\n' "" > /dev/null; printf '%s' "$GOODBODY" > "$l"; return 0
}
REPO="$(cd "$HERE/../.." && pwd)"; HAD_XO=0; [ -d "$REPO/xrun_out" ] && HAD_XO=1
out=$(PL_OUT_DIR="$RT/out" PL_SIM_DIR="$RT/sim" GLS_MODEL="$RT/model.v" LICENSE_RETRIES=3 LICENSE_WAIT_S=0 main ss nochecks 2>&1); rc=$?
chk "retry loop: two licence deaths then a pass -> exit 0 after 3 attempts" $([ $rc -eq 0 ] && [ "$(cat "$XCOUNT")" = 3 ] && echo "$out" | grep -q 'attempt 1 of 4 ended without a verdict' && echo "$out" | grep -q 'attempt 2 of 4' && echo "$out" | grep -qE '^=== PASS: post-layout ss nochecks' && echo 1 || echo 0)
chk "retry loop: the failed attempts' logs are kept" $([ -s "$RT/sim/pl_ss_nochecks.attempt1.log" ] && [ -s "$RT/sim/pl_ss_nochecks.attempt2.log" ] && echo 1 || echo 0)
echo 0 > "$XCOUNT"
out=$(FAKE_FAILS=9 PL_OUT_DIR="$RT/out" PL_SIM_DIR="$RT/sim2" GLS_MODEL="$RT/model.v" LICENSE_RETRIES=1 LICENSE_WAIT_S=0 main ss nochecks 2>&1); rc=$?
chk "retries used up: exit 2 with the environment text, not a FAIL" $([ $rc -eq 2 ] && [ "$(cat "$XCOUNT")" = 2 ] && echo "$out" | grep -q 'ENVIRONMENT PROBLEM (exit 2), NOT a FAIL of the design' && echo 1 || echo 0)
echo 0 > "$XCOUNT"
out=$(FAKE_FAILS=9 PL_OUT_DIR="$RT/out" PL_SIM_DIR="$RT/sim3" GLS_MODEL="$RT/model.v" main ss nochecks 2>&1); rc=$?
chk "default: no retry (one attempt), exit 2" $([ $rc -eq 2 ] && [ "$(cat "$XCOUNT")" = 1 ] && echo 1 || echo 0)
out=$(PL_OUT_DIR="$RT/out" PL_SIM_DIR="$RT/sim4" GLS_MODEL="$RT/model.v" LICENSE_RETRIES=x main ss nochecks 2>&1); rc=$?
chk "LICENSE_RETRIES must be a number: exit 2" $([ $rc -eq 2 ] && echo "$out" | grep -q "LICENSE_RETRIES='x' is not a number" && echo 1 || echo 0)
out=$(PL_OUT_DIR="$RT/out" PL_SIM_DIR="$RT/sim4" GLS_MODEL="$RT/model.v" SDF_ACCEPT=bogus main ss nochecks 2>&1); rc=$?
chk "an invalid SDF_ACCEPT stops main with exit 2 before xrun runs" $([ $rc -eq 2 ] && echo "$out" | grep -q "SDF_ACCEPT contains 'bogus'" && [ "$(cat "$XCOUNT")" = 1 ] && echo 1 || echo 0)
out=$(PL_OUT_DIR="$RT/out" PL_SIM_DIR="$RT/sim5" GLS_MODEL="$RT/model.v" SDF_ACCEPT="nep_cond" FAKE_FAILS=0 main ss nochecks 2>&1); rc=$?
chk "main prints the approved classes at the start" $(echo "$out" | grep -q 'SDF classes approved by the user (SDF_ACCEPT): nep_cond' && echo 1 || echo 0)
unset -f xrun
[ "$HAD_XO" = 0 ] && rmdir "$REPO/xrun_out" 2>/dev/null

echo "RESULT: $npass passed, $nfail failed"
[ "$nfail" -eq 0 ]
