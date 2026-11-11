#!/usr/bin/env bash
# Self-test of scripts/run_gls.sh (task 059) with a STUB xrun: proves the argument handling, the file names, the verdict logic. It proves
# nothing about Xcelium. Run from anywhere: bash scripts/test_run_gls.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; mkdir -p "$T/bin"; trap 'rm -rf "$T"' EXIT
npass=0; nfail=0
ok()  { npass=$((npass+1)); }
bad() { nfail=$((nfail+1)); echo "FAIL: $1"; }
chk() { if [ "$2" = 1 ]; then ok; else bad "$1"; fi; }

mk() {  # fresh tree
  rm -rf "$T/r"; mkdir -p "$T/r/scripts" "$T/r/tb" "$T/r/model/vectors" "$T/r/syn/out/syn16" "$T/r/syn/out/syn20" "$T/bin" "$T/m"
  cp "$HERE/run_gls.sh" "$T/r/scripts/"; echo "module unpu_top_tb; endmodule" > "$T/r/tb/unpu_top_tb.sv"; echo 1 > "$T/r/model/vectors/a.hex"
  for p in syn16 syn20; do echo "module unpu_top; endmodule" > "$T/r/syn/out/$p/unpu_top_cn.dc.v"; echo "(DELAYFILE)" > "$T/r/syn/out/$p/unpu_top_cn.sdf"; done
  echo "module m; endmodule" > "$T/m/model.v"
}
# stub xrun: writes the log named after -l, with the content of $STUB_LOG_BODY; records its arguments in $T/args
cat > "$T/bin/xrun" <<'EOS'
#!/usr/bin/env bash
echo "$@" > "$STUB_ARGS"
while [ $# -gt 0 ]; do [ "$1" = "-l" ] && { shift; LOGF="$1"; }; shift; done
printf '%b' "$STUB_LOG_BODY" > "$LOGF"
exit 0
EOS
chmod +x "$T/bin/xrun"
export STUB_ARGS="$T/args"
GOOD='SDF annotation: 12345 delays annotated\nchecked 343341 value(s)/assertion(s) total\nALL CHECKS PASSED\n'
run() { ( cd "$T/r" && PATH="$T/bin:$PATH" GLS_MODEL="$T/m/model.v" bash scripts/run_gls.sh "$@" ) ; }

mk; export STUB_LOG_BODY="$GOOD"
out=$(run syn16 sdf 2>&1); rc=$?
chk "sdf pass: exit 0" $([ $rc -eq 0 ] && echo 1 || echo 0)
chk "sdf pass: says PASS" $(echo "$out" | grep -q '=== PASS: syn16 (sdf)' && echo 1 || echo 0)
chk "sdf: log is syn/out/gls_sdf_syn16.log" $([ -s "$T/r/syn/out/gls_sdf_syn16.log" ] && echo 1 || echo 0)
chk "sdf: command file has SDF_FILE of the profile and SCOPE unpu_top_tb.dut" $(grep -q 'SDF_FILE = "syn/out/syn16/unpu_top_cn.sdf"' "$T/r/syn/out/gls_sdf_syn16.cmd" && grep -q 'SCOPE = unpu_top_tb.dut' "$T/r/syn/out/gls_sdf_syn16.cmd" && echo 1 || echo 0)
a=$(cat "$T/args")
chk "sdf: xrun gets -define GLS_CLK_HALF_NS=10, -sdf_cmd_file, -notimingchecks, the netlist, the model, the tb" $(echo "$a" | grep -q -- '-define GLS_CLK_HALF_NS=10' && echo "$a" | grep -q -- '-sdf_cmd_file syn/out/gls_sdf_syn16.cmd' && echo "$a" | grep -q -- '-notimingchecks' && echo "$a" | grep -q 'syn/out/syn16/unpu_top_cn.dc.v' && echo "$a" | grep -q "$T/m/model.v" && echo "$a" | grep -q 'tb/unpu_top_tb.sv' && echo 1 || echo 0)
chk "nothing new inside syn/out/syn16/ (still the 2 files made by the test)" $([ "$(ls "$T/r/syn/out/syn16" | wc -l)" -eq 2 ] && echo 1 || echo 0)

mk; out=$(run syn20 nosdf 2>&1); rc=$?
chk "nosdf pass: exit 0, log syn/out/gls_syn20.log, no sdf args, no cmd file" $([ $rc -eq 0 ] && [ -s "$T/r/syn/out/gls_syn20.log" ] && ! grep -q -- '-sdf_cmd_file' "$T/args" && [ ! -e "$T/r/syn/out/gls_sdf_syn20.cmd" ] && echo 1 || echo 0)

mk; GLS_CLK_HALF_NS=5 out=$( cd "$T/r" && GLS_CLK_HALF_NS=5 PATH="$T/bin:$PATH" GLS_MODEL="$T/m/model.v" bash scripts/run_gls.sh syn16 nosdf 2>&1 ); chk "GLS_CLK_HALF_NS=5 is passed on" $(grep -q -- '-define GLS_CLK_HALF_NS=5' "$T/args" && echo 1 || echo 0)

mk; export STUB_LOG_BODY='FAIL [x]: a\nFAIL [x]: b\nchecked 343341 value(s)/assertion(s) total\nALL CHECKS PASSED\n'; out=$(run syn16 sdf 2>&1); rc=$?
chk "a FAIL line makes the verdict FAIL (even with ALL CHECKS PASSED) and prints it" $([ $rc -eq 1 ] && echo "$out" | grep -q 'FAIL \[x\]: a' && echo "$out" | grep -q '=== FAIL: syn16 (sdf)' && echo 1 || echo 0)
mk; export STUB_LOG_BODY='checked 343340 value(s)/assertion(s) total\nALL CHECKS PASSED\n'; out=$(run syn16 sdf 2>&1); rc=$?
chk "a different check count is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
mk; export STUB_LOG_BODY='checked 343341 value(s)/assertion(s) total\n'; out=$(run syn16 sdf 2>&1); rc=$?
chk "no ALL CHECKS PASSED line (interrupted run) is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
mk; export STUB_LOG_BODY='*E,SOMETHING\nchecked 343341 value(s)/assertion(s) total\nALL CHECKS PASSED\n'; out=$(run syn16 sdf 2>&1); rc=$?
chk "an *E line is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)
mk; export STUB_LOG_BODY=''; out=$(run syn16 sdf 2>&1); rc=$?
chk "an empty log is FAIL" $([ $rc -eq 1 ] && echo 1 || echo 0)

export STUB_LOG_BODY="$GOOD"
mk; out=$(run syn17 sdf 2>&1); chk "unknown profile: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)
mk; out=$(run syn16 foo 2>&1); chk "unknown mode: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)
mk; out=$(run 2>&1); chk "no argument: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)
mk; rm "$T/r/syn/out/syn16/unpu_top_cn.sdf"; out=$(run syn16 sdf 2>&1); rc=$?; chk "missing SDF in sdf mode: exit 2 naming the file" $([ $rc -eq 2 ] && echo "$out" | grep -q 'unpu_top_cn.sdf' && echo 1 || echo 0)
mk; rm "$T/r/syn/out/syn16/unpu_top_cn.sdf"; out=$(run syn16 nosdf 2>&1); chk "missing SDF is fine in nosdf mode" $([ $? -eq 0 ] && echo 1 || echo 0)
mk; rm "$T/r/syn/out/syn16/unpu_top_cn.dc.v"; out=$(run syn16 sdf 2>&1); chk "missing netlist: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)
mk; out=$( cd "$T/r" && PATH="$T/bin:$PATH" GLS_MODEL="$T/m/none.v" bash scripts/run_gls.sh syn16 sdf 2>&1 ); chk "missing model file: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)
mk; rm -rf "$T/r/model/vectors"; out=$(run syn16 sdf 2>&1); chk "missing vectors: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)
mk; out=$( cd "$T/r" && PATH="/usr/bin:/bin" GLS_MODEL="$T/m/model.v" bash scripts/run_gls.sh syn16 sdf 2>&1 ); chk "no xrun in PATH: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)
mk; out=$( cd "$T/r" && GLS_CLK_HALF_NS=abc PATH="$T/bin:$PATH" GLS_MODEL="$T/m/model.v" bash scripts/run_gls.sh syn16 sdf 2>&1 ); chk "bad GLS_CLK_HALF_NS: exit 2" $([ $? -eq 2 ] && echo 1 || echo 0)

echo "test_run_gls: $npass passed, $nfail failed"
[ "$nfail" -eq 0 ] && { echo "ALL TESTS PASSED"; exit 0; }
echo "TESTS FAILED"; exit 1
