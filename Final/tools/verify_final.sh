#!/usr/bin/env bash
# Task 099: verify Final/ against its INDEX.md and the log files it cites. PASS/FAIL per check; exit 1 if any check fails.
#   bash Final/tools/verify_final.sh                 all checks (the tool-free script tests take about a minute)
#   VERIFY_SKIP_TESTS=1 bash Final/tools/verify_final.sh   skips only check 12 (printed as SKIP, never silently)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="$(dirname "$HERE")"
REPO="$(dirname "$F")"
LIMIT_FILE=$((50*1024*1024)); LIMIT_GZ=$((20*1024*1024)); LIMIT_TOTAL=$((400*1024*1024))
npass=0; nfail=0
ok()  { printf 'PASS  %s\n' "$1"; npass=$((npass+1)); }
bad() { printf 'FAIL  %s\n' "$1"; nfail=$((nfail+1)); }
note(){ printf '      %s\n' "$1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

[ -f "$F/INDEX.md" ] || { echo "FAIL  INDEX.md missing in $F"; exit 1; }

# ---- parse the file table of INDEX.md: path<TAB>size<TAB>sha<TAB>osha
awk -F'|' '/<!-- FILES-BEGIN -->/{f=1;next} /<!-- FILES-END -->/{f=0} f && $2 ~ /^ `/ {
  gsub(/^ *`|` *$/,"",$2); for(i=3;i<=5;i++){gsub(/[ `]/,"",$i)} print $2"\t"$3"\t"$4"\t"$5 }' "$F/INDEX.md" > "$TMP/index.tsv"
n_index=$(wc -l < "$TMP/index.tsv")

# 1. every indexed file exists with the indexed size and sha256 (compressed ones: sha256 of the stored file AND of the decompressed original)
miss=0; badsize=0; badsha=0; badosha=0
while IFS=$'\t' read -r p size sha osha; do
  fp="$F/$p"
  if [ ! -f "$fp" ]; then miss=$((miss+1)); [ $miss -le 3 ] && note "missing: $p"; continue; fi
  [ "$(stat -c%s "$fp")" = "$size" ] || { badsize=$((badsize+1)); [ $badsize -le 3 ] && note "size differs: $p"; }
  [ "$(sha256sum "$fp" | cut -d' ' -f1)" = "$sha" ] || { badsha=$((badsha+1)); [ $badsha -le 3 ] && note "sha256 differs: $p"; }
  if [ -n "$osha" ]; then
    [ "$(gzip -dc "$fp" | sha256sum | cut -d' ' -f1)" = "$osha" ] || { badosha=$((badosha+1)); [ $badosha -le 3 ] && note "sha256 of the decompressed original differs: $p"; }
  fi
done < "$TMP/index.tsv"
if [ "$n_index" -gt 0 ] && [ $miss -eq 0 ] && [ $badsize -eq 0 ] && [ $badsha -eq 0 ] && [ $badosha -eq 0 ]; then
  ok "1  INDEX.md: all $n_index files exist, size and sha256 equal (originals of $(awk -F'\t' '$4!=""' "$TMP/index.tsv" | wc -l) compressed files too)"
else bad "1  INDEX.md vs files: $n_index rows, missing $miss, size $badsize, sha256 $badsha, original sha256 $badosha"; fi

# 2. INDEX.md lists every file (nothing in the folder is missing from the table)
(cd "$F" && find . -type f ! -path './INDEX.md' ! -path './tools/verify_final.sh' ! -path './tools/build_final.py' ! -path './tools/stages.py' ! -path './tools/report_src/*' ! -path '*/__pycache__/*' | sed 's|^\./||' | sort) > "$TMP/onDisk.txt"
cut -f1 "$TMP/index.tsv" | sort > "$TMP/inIndex.txt"
if diff -q "$TMP/onDisk.txt" "$TMP/inIndex.txt" > /dev/null; then ok "2  INDEX.md lists every file of the folder and nothing else"
else bad "2  files not in the table / rows without file: $(comm -23 "$TMP/onDisk.txt" "$TMP/inIndex.txt" | wc -l) / $(comm -13 "$TMP/onDisk.txt" "$TMP/inIndex.txt" | wc -l)"; comm -23 "$TMP/onDisk.txt" "$TMP/inIndex.txt" | head -3 | sed 's/^/      not indexed: /'; fi

# 3. size limits
big=$(find "$F" -type f -size +"${LIMIT_FILE}"c | wc -l)
unz=$(find "$F" -type f -size +"${LIMIT_GZ}"c ! -name '*.gz' | wc -l)
total=$(find "$F" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')
if [ "$big" -eq 0 ] && [ "$unz" -eq 0 ] && [ "$total" -le "$LIMIT_TOTAL" ]; then
  ok "3  size: no file over 50 MB, no uncompressed file over 20 MB, total $((total/1048576)) MB (limit 400 MB)"
else bad "3  size: files over 50 MB $big, uncompressed over 20 MB $unz, total $((total/1048576)) MB"; fi

# 4. nothing confidential by name; no _local_only; no deck name outside a path
conf=$(find "$F" \( -iname '*DRC_TS18SL*' -o -iname '*ANTENNA_TS18SL*' -o -iname '*LVS_TS18SL*' -o -iname '*tsl18fs120*' -o -iname '*scl18fs120*' \
  -o -name '*.ndm' -o -name '*.ndm.*' -o -name '*.dlib' -o -name '*.dlib.*' -o -name '*.gds' -o -name '*.gds.gz' -o -name '*.def' -o -name '*.def.gz' -o -name '*.lib' -o -name '*.db' -o -name '*.tf' -o -name '*.svf' \
  -o -name scr -o -name blocks -o -name svdb -o -name _local_only -o -name 'icv_run_*' -o -name 'outputs_*' -o -name 'bak_*' -o -name '*cshrc*' \) | grep -v '/__pycache__' | wc -l)
deckish=$(grep -rIcE '^[[:space:]]*(LAYER MAP|DRC CHECK MAP|#IFDEF|#ENDIF|[A-Za-z0-9_.]+ *\{ *@)' "$F" --exclude-dir=tools 2>/dev/null | awk -F: '$NF>5' | wc -l)
if [ "$conf" -eq 0 ]; then ok "4a no kit/deck/NDM/database/GDS/checkpoint/tool-setup file name in the tree"; else bad "4a $conf file names on the deny-list"; find "$F" \( -name '*.ndm' -o -name '*.dlib*' -o -name '*.gds*' -o -name scr -o -name blocks -o -name 'outputs_*' \) | head -3 | sed 's/^/      /'; fi
if [ "$deckish" -eq 0 ]; then ok "4b no file looks like SVRF deck content (the deck NAMES occur only in our own prose, ctrl files and in INCLUDE path lines of logs)"; else bad "4b $deckish files look like rule-deck content"; fi

# 4c. no GDS and no DEF anywhere in git (tracked or staged): the GDS contains the foundry library polygons, the DEF the technology via definitions; the repository is public
if git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1; then
  gtr=$(git -C "$REPO" ls-files --cached | grep -iE '\.(gds|def)(\.gz)?$' | wc -l)
  [ "$gtr" -eq 0 ] && ok "4c no .gds / .def (or .gz of them) is tracked or staged in git (repository-wide)" || bad "4c $gtr GDS/DEF files tracked or staged in git"
else bad "4c not a git repository: tracked-GDS check impossible"; fi

# 5. "Not in Final": none of the listed material is inside Final (by path and by sha256)
awk -F'|' '/^## 7\. Not in Final/{f=1;next} /^## 8\./{f=0} f && $2 ~ /^ `/ {for(i=2;i<=4;i++){gsub(/^ +| +$/,"",$i)}; gsub(/`/,"",$2); gsub(/`/,"",$4); print $2"\t"$3"\t"$4}' "$F/INDEX.md" > "$TMP/notin.tsv"
n_notin=$(wc -l < "$TMP/notin.tsv")
awk -F'\t' '$2>1048576 {print $3}' "$TMP/notin.tsv" | sort -u > "$TMP/notin_sha.txt"
( cut -f3 "$TMP/index.tsv"; cut -f4 "$TMP/index.tsv" ) | grep -v '^$' | sort -u > "$TMP/in_sha.txt"
coll=$(comm -12 "$TMP/notin_sha.txt" "$TMP/in_sha.txt" | wc -l)
need=0; for w in unpu_top_routed.gds unpu_top.def pnr_icc2/blocks/ scl180_std.ndm outputs_run3_final; do grep -q "$w" "$TMP/notin.tsv" || { need=$((need+1)); note "Not in Final lacks an entry for $w"; }; done
if [ "$n_notin" -gt 0 ] && [ "$coll" -eq 0 ] && [ "$need" -eq 0 ]; then ok "5  Not in Final: $n_notin listed items (name, size, sha256); none of their >1 MB sha256 occurs in the tree"
else bad "5  Not in Final: $n_notin items listed, $coll sha256 values also occur inside Final, $need required entries missing"; fi

# 6. git does not ignore any file of Final (the stage logs must be able to enter git)
if git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1; then
  ign=$(cd "$REPO" && find Final -type f ! -path '*/__pycache__/*' | git check-ignore --stdin 2>/dev/null | wc -l)
  if [ "$ign" -eq 0 ]; then ok "6  git: no file of Final/ is ignored (logs, reports and outputs can be committed)"; else bad "6  git ignores $ign files of Final/"; (cd "$REPO" && find Final -type f | git check-ignore --stdin | head -3 | sed 's/^/      /'); fi
else bad "6  $REPO is not a git repository: ignore check impossible"; fi

# 7. the key numbers: each keys.tsv row is re-read from its file; the value must be in the cited line, at the recorded line number, in the stage README and (results) in INDEX.md
nk=0; kbad=0
while IFS=$'\t' read -r id stage file pattern nth value line; do
  case "$id" in '#'*|'') continue;; esac
  nk=$((nk+1))
  fp="$F/$file"
  if [ ! -f "$fp" ]; then kbad=$((kbad+1)); note "key $id: $file missing"; continue; fi
  hit=$(grep -nE -- "$pattern" "$fp" | sed -n "${nth}p")
  ln=${hit%%:*}; txt=${hit#*:}
  if [ -z "$hit" ] || [ "$ln" != "$line" ] || ! printf '%s' "$txt" | grep -qF -- "$value"; then kbad=$((kbad+1)); note "key $id: '$value' not at $file:$line (found: ${hit:0:100})"; continue; fi
  grep -qF -- "\`$value\`" "$F/$stage/README.md" || { kbad=$((kbad+1)); note "key $id: value $value not in $stage/README.md"; continue; }
  grep -qF -- "$value" "$F/INDEX.md" || { kbad=$((kbad+1)); note "key $id: value $value not in INDEX.md"; }
done < "$F/tools/keys.tsv"
if [ "$nk" -gt 0 ] && [ "$kbad" -eq 0 ]; then ok "7  key numbers: $nk values equal the cited log lines and appear in the stage READMEs and INDEX.md"; else bad "7  key numbers: $kbad of $nk wrong"; fi

# 8. independent re-counts (not taken from a log line that states them)
lefv=$(awk -F'\t' '$1=="lef_pins"{print $6}' "$F/tools/keys.tsv")
lefn=$(grep -cE '^[[:space:]]*PIN ' "$F/12_fill_and_export/outputs/unpu_top.lef" 2>/dev/null)
macros=$(grep -cE '^MACRO ' "$F/12_fill_and_export/outputs/unpu_top.lef" 2>/dev/null)
if [ -n "$lefv" ] && [ "$lefn" = "$lefv" ] && [ "$macros" = 1 ]; then ok "8a LEF: one MACRO, $lefn PIN entries counted in the file = $lefv stated by the pv log"; else bad "8a LEF: counted PIN $lefn / MACRO $macros, log says $lefv"; fi
for r in A B C D; do
  c=$(grep -c '^=== PASS' "$F/15_post_layout_sim/sim/run${r}_console.txt" 2>/dev/null); fl=$(grep -c '^=== FAIL' "$F/15_post_layout_sim/sim/run${r}_console.txt" 2>/dev/null)
  [ "$c" = 1 ] && [ "$fl" = 0 ] || simbad=1
done
[ "${simbad:-0}" = 0 ] && ok "8b post-layout runs A-D: exactly one '=== PASS' line each, no '=== FAIL'" || bad "8b post-layout run console verdict lines"
zs=$(awk -F'\t' '$1=="drc_results"||$1=="ant_results"{s+=$6} END{print s+0}' "$F/tools/keys.tsv")
[ "$zs" = 0 ] && ok "8c Calibre final4 DRC + antenna results total 0 (from keys.tsv)" || bad "8c Calibre final4 results total $zs"

# 9. every stage README has the five parts
miss5=0
for d in "$F"/[0-1][0-9]_*; do
  for n in 1 2 3 4 5; do grep -q "^## $n\. " "$d/README.md" 2>/dev/null || { miss5=$((miss5+1)); note "$(basename "$d")/README.md lacks part $n"; }; done
done
nst=$(ls -d "$F"/[0-1][0-9]_* | wc -l)
[ "$miss5" -eq 0 ] && [ "$nst" -eq 16 ] && ok "9  16 stage folders, each README.md has the five parts" || bad "9  stage folders $nst (expected 16), missing README parts $miss5"

# 10. scripts/MANIFEST.md: every sha256 equals the file
mm=0; mn=0
while IFS= read -r l; do
  p=$(printf '%s' "$l" | awk -F'|' '{gsub(/^ *`|` *$/,"",$2); print $2}'); s=$(printf '%s' "$l" | awk -F'|' '{gsub(/[ `]/,"",$4); print $4}')
  mn=$((mn+1)); [ "$(sha256sum "$F/scripts/$p" 2>/dev/null | cut -d' ' -f1)" = "$s" ] || { mm=$((mm+1)); note "MANIFEST sha256 differs: $p"; }
done < <(grep -E '^\| `' "$F/scripts/MANIFEST.md")
nsc=$(find "$F/scripts" -type f ! -path "$F/scripts/MANIFEST.md" ! -path "$F/scripts/README.md" | wc -l)
[ "$mm" -eq 0 ] && [ "$mn" -eq "$nsc" ] && ok "10 scripts/MANIFEST.md: $mn rows = $nsc script files, sha256 all equal" || bad "10 MANIFEST: rows $mn, files $nsc, sha256 differences $mm"

# 11. docs/INDEX.md covers every document
nd=$(find "$F/docs" -type f ! -name INDEX.md | wc -l); ni=$(grep -cE '^\| `' "$F/docs/INDEX.md")
[ "$nd" = "$ni" ] && ok "11 docs/INDEX.md: $ni rows = $nd documents" || bad "11 docs/INDEX.md: $ni rows, $nd documents"

# 12. the tool-free tests run from a COPY of scripts/ in a temporary place (the run-root bootstrap must work when the folder is moved)
if [ "${VERIFY_SKIP_TESTS:-0}" = 1 ]; then printf 'SKIP  12 script tests (VERIFY_SKIP_TESTS=1, explicit)\n'
else
  C="$TMP/copy"; mkdir -p "$C"; cp -r "$F/scripts" "$C/"; terr=0; tn=0; tsum=0
  if ! command -v tclsh > /dev/null || ! command -v gcc > /dev/null; then bad "12 tclsh or gcc not found: the script tests cannot run"
  else
    (cd "$C/scripts" && gcc -std=c99 -Wall -Wextra -o model/golden model/golden.c && ./model/golden > "$TMP/golden.out" 2>&1) || { terr=$((terr+1)); note "golden model did not build/run"; }
    for t in pt/test_pt_common.tcl test_pt_eco_apply.tcl test_eco_scope.tcl test_drc_eco.tcl test_sdc_limits.tcl test_run_root.tcl test_si_eco.tcl test_timing_closure.tcl test_opt_uncertainty.tcl test_clock_latency.tcl test_pv_checkpoint.tcl test_pv_lef_check.tcl test_pv_sdf_check.tcl test_port_buffers_early.tcl test_antenna_port_buffers.tcl test_antenna_clk_root.tcl test_diag_io_latency.tcl test_diag_io_whatif.tcl; do
      tn=$((tn+1)); out=$(cd "$C/scripts/pnr_v2/$(dirname "$t")" && timeout 300 tclsh "$(basename "$t")" 2>&1); rc=$?
      res=$(printf '%s\n' "$out" | grep -E '^RESULT: [0-9]+ passed, [0-9]+ failed' | tail -1)
      if [ $rc -ne 0 ] || ! printf '%s' "$res" | grep -q ' 0 failed'; then terr=$((terr+1)); note "$t: rc=$rc ${res:-no RESULT line}"; else tsum=$((tsum + $(printf '%s' "$res" | awk '{print $2}'))); fi
    done
    for t in sim/test_postlayout_verdict.sh; do
      tn=$((tn+1)); out=$(cd "$C/scripts/pnr_v2/$(dirname "$t")" && timeout 600 bash "$(basename "$t")" 2>&1); rc=$?
      res=$(printf '%s\n' "$out" | grep -E '^RESULT: [0-9]+ passed, [0-9]+ failed' | tail -1)
      if [ $rc -ne 0 ] || ! printf '%s' "$res" | grep -q ' 0 failed'; then terr=$((terr+1)); note "$t: rc=$rc ${res:-no RESULT line}"; else tsum=$((tsum + $(printf '%s' "$res" | awk '{print $2}'))); fi
    done
    tn=$((tn+1)); out=$(cd "$C/scripts" && timeout 300 bash scripts/test_syn_compare.sh 2>&1); rc=$?
    if [ $rc -ne 0 ] || ! printf '%s' "$out" | grep -q 'ALL TESTS PASSED'; then terr=$((terr+1)); note "scripts/test_syn_compare.sh rc=$rc"; fi
    [ "$terr" -eq 0 ] && ok "12 script tests from a temporary copy of scripts/: $tn suites, $tsum numbered tests passed, 0 failed (+ test_syn_compare: ALL TESTS PASSED)" || bad "12 script tests: $terr of $tn suites failed"
  fi
fi

# 13. the report documents: tokens resolved from the logs (an unresolved token is a FAIL), every key used by a template appears with its value, section 14 and the [unverified] marks are present
rep_bad=0; rep_n=0
for t in "$F"/tools/report_src/*.md; do
  [ -f "$t" ] || continue
  b=$(basename "$t"); r="$F/16_docs_and_report/$b"; d="$F/docs/report/$b"; rep_n=$((rep_n+1))
  [ -s "$r" ] || { rep_bad=$((rep_bad+1)); note "$b: no rendered copy in 16_docs_and_report"; continue; }
  cmp -s "$r" "$d" || { rep_bad=$((rep_bad+1)); note "$b: docs/report copy differs"; }
  if grep -q '@@' "$r"; then rep_bad=$((rep_bad+1)); note "$b: an unresolved @@token@@ is left"; fi
  while IFS=$'\t' read -r id stage file pattern nth value line; do
    case "$id" in '#'*|'') continue;; esac
    if grep -q "@@${id}@@" "$t"; then grep -qF -- "$value" "$r" || { rep_bad=$((rep_bad+1)); note "$b: value of $id ($value) missing in the rendered report"; }; fi
  done < "$F/tools/keys.tsv"
done
if [ -s "$F/16_docs_and_report/01_project_report.md" ]; then
  grep -q '^## 14\. Limitations' "$F/16_docs_and_report/01_project_report.md" || { rep_bad=$((rep_bad+1)); note "01_project_report.md lacks section 14"; }
  [ "$(grep -c '\[unverified' "$F/16_docs_and_report/01_project_report.md")" -ge 3 ] || { rep_bad=$((rep_bad+1)); note "01_project_report.md has fewer than 3 [unverified] marks"; }
else rep_bad=$((rep_bad+1)); note "01_project_report.md missing"; fi
[ "$rep_bad" -eq 0 ] && [ "$rep_n" -ge 1 ] && ok "13 report documents: $rep_n template(s) rendered, no unresolved token, every cited key value present, section 14 and [unverified] marks present" || bad "13 report documents: $rep_bad problems ($rep_n templates)"

# 14. numbers cited in the report documents 02 and 03 (tables of 02 section 2 and 03 part B): each claim of report_src/claims.tsv must occur in the document and every key value it names must be contained in it
cl_bad=0; cl_n=0
while IFS=$'\t' read -r cfile needle spec; do
  case "$cfile" in '#'*|'') continue;; esac
  cl_n=$((cl_n+1)); doc="$F/$cfile"
  [ -f "$doc" ] || { cl_bad=$((cl_bad+1)); note "claim $cl_n: $cfile missing"; continue; }
  sed 's/−/-/g' "$doc" > "$TMP/doc.norm"
  n2=$(printf '%s' "$needle" | sed 's/−/-/g')
  grep -qF -- "$n2" "$TMP/doc.norm" || { cl_bad=$((cl_bad+1)); note "claim $cl_n: text not found in $(basename "$cfile"): ${n2:0:70}"; continue; }
  nn=$(printf '%s' "$n2" | sed 's/,//g; s/ //g')
  IFS=, read -ra items <<< "$spec"
  for item in "${items[@]}"; do
    id=${item%%:*}; tr=""; case "$item" in *:*) tr=${item#*:};; esac
    val=$(awk -F'\t' -v id="$id" '$1==id{print $6}' "$F/tools/keys.tsv")
    if [ -z "$val" ]; then cl_bad=$((cl_bad+1)); note "claim $cl_n: unknown key $id"; continue; fi
    case "$tr" in
      round0) vv=$(awk -v x="$val" 'BEGIN{printf "%.0f", x}');;
      pct2)   vv=$(awk -v x="$val" 'BEGIN{printf "%.2f", x*100}');;
      zero)   [ "$val" = 0 ] || { cl_bad=$((cl_bad+1)); note "claim $cl_n: $id is $val, the document says 0"; }; continue;;
      *)      vv=${val#+};;
    esac
    printf '%s' "$nn" | grep -qF -- "$vv" || { cl_bad=$((cl_bad+1)); note "claim $cl_n: $id = $val ($vv) is not in: ${n2:0:80}"; }
  done
done < "$F/tools/report_src/claims.tsv"
[ "$cl_n" -gt 0 ] && [ "$cl_bad" -eq 0 ] && ok "14 cited numbers: $cl_n claims of documents 02 and 03 found in the documents and equal to the key values read from the logs" || bad "14 cited numbers: $cl_bad problems in $cl_n claims"

# 15. facts cited in 02 / 03 that are counted independently of keys.tsv
f_bad=0
lefc=$(awk '/^  PIN /{p=1;lay=""} p && /LAYER /{lay=$2} /^  END /{if(p)c[lay]++; p=0} END{print c["M3"]+0, c["M2"]+0}' "$F/12_fill_and_export/outputs/unpu_top.lef")
[ "$lefc" = "102 102" ] || { f_bad=$((f_bad+1)); note "pins by layer in the LEF (M3 M2): $lefc, documents say 102 / 102"; }
net="$F/12_fill_and_export/outputs/unpu_top_pnr_pg.v.gz"
eb=$(gzip -dc "$net" | grep -cE '^[[:space:]]*[A-Za-z0-9_]+ earlybuf_[^ ]* \(')
ab=$(gzip -dc "$net" | grep -cE '^[[:space:]]*[A-Za-z0-9_]+ antbuf_[^ ]* \(')
hb=$(gzip -dc "$net" | grep -cE '^[[:space:]]*[A-Za-z0-9_]+ U_PTECO_HOLD_BUF[0-9]+ \(')
rs=$(cat "$F"/11_eco_and_antenna/reports/data_limit_eco_9_resizes__run3_final/pt_eco_drc_changes.txt "$F"/11_eco_and_antenna/reports/si_round_probes__si_before_si/pt_eco_setup_changes.txt | grep -cE '^[[:space:]]+[0-9]+\. size_cell')
[ "$eb $ab $hb $rs" = "54 1 11 10" ] || { f_bad=$((f_bad+1)); note "ECO cells (early, antenna, hold, resizes): $eb $ab $hb $rs, documents say 54 1 11 10"; }
grep -q -- '-0.2423' "$F/docs/docs/planning/restart-plan-2026-11-10.md" && grep -q -- '-0.3468' "$F/docs/docs/planning/restart-plan-2026-11-10.md" && grep -q '263 endpoints' "$F/docs/docs/planning/restart-plan-2026-11-10.md" || { f_bad=$((f_bad+1)); note "run-1 sign-off numbers (-0.2423, -0.3468, 263 endpoints) not in the restart plan"; }
grep -q '55 -> 50 -> 46 -> 1 -> 0' "$F/docs/docs/session-handoff.md" || { f_bad=$((f_bad+1)); note "run-1 antenna sequence 55 -> 50 -> 46 -> 1 -> 0 not in the handoff"; }
grep -q -- '-0.5899' "$F/docs/docs/planning/progress-log-2026-11-09.md" || { f_bad=$((f_bad+1)); note "-0.5899 not in progress-log-2026-11-09.md"; }
ar="$F/13_signoff_calibre/reports/all_runs.md"
for rr in "route1:10" "route2:4" "route3:0" "final3:3" "final4:0"; do
  run=${rr%%:*}; want=${rr##*:}
  got=$(awk -F'|' -v r="$run" '{gsub(/ /,"",$2); if($2==r){split($7,a," "); print a[1]}}' "$ar")
  [ "$got" = "$want" ] || { f_bad=$((f_bad+1)); note "Calibre antenna results of $run: $got, documents say $want"; }
done
grep -qE '52,656' "$F/docs/docs/planning/progress-log-2026-11-10.md" && awk -v a="$(awk -F'\t' '$1=="sdf_edge"{print $6}' "$F/tools/keys.tsv")" -v b="$(awk -F'\t' '$1=="sdf_cond"{print $6}' "$F/tools/keys.tsv")" 'BEGIN{p=100*(a+b)/52656; exit !(p>42.75 && p<42.85)}' || { f_bad=$((f_bad+1)); note "42.8 percent of 52,656 does not follow from the SDF class counts"; }
sz=$(grep -m1 -E '^[[:space:]]*SIZE ' "$F/12_fill_and_export/outputs/unpu_top.lef" | awk '{print $2" "$4}')
[ "$sz" = "885.6 885.6" ] || { f_bad=$((f_bad+1)); note "LEF size $sz"; }
[ "$f_bad" -eq 0 ] && ok "15 independent counts: 102 + 102 pins on M3 / M2 in the LEF, ECO cells 54 / 1 / 11 / 10 from the netlist and the change lists, run-1 numbers in the records, Calibre antenna 10 / 4 / 0 / 3 / 0, 42.8 percent of 52,656" || bad "15 independent counts: $f_bad problems"

# 16. approximate figures cited in documents 02 and 03 ("more than 80 key numbers", "about 1,200 files", "about 89 MB", "140 files in the deliverable zip")
a_bad=0
nkeys=$(grep -vc '^#' "$F/tools/keys.tsv")
[ "$nkeys" -gt 80 ] || { a_bad=$((a_bad+1)); note "keys.tsv has $nkeys key values, the documents say more than 80"; }
grep -q 'more than 80 key numbers' "$F/16_docs_and_report/02_what_we_did_differently.md" || { a_bad=$((a_bad+1)); note "02 does not say 'more than 80 key numbers'"; }
nf=$(find "$F" -type f ! -path '*/__pycache__/*' | wc -l); mb=$(du -sm "$F" | cut -f1)
[ "$nf" -ge 1140 ] && [ "$nf" -le 1260 ] || { a_bad=$((a_bad+1)); note "Final has $nf files, 03 says about 1,200"; }
[ "$mb" -ge 86 ] && [ "$mb" -le 92 ] || { a_bad=$((a_bad+1)); note "Final is $mb MB, 03 says about 89 MB"; }
grep -q 'about 1,200 files' "$F/16_docs_and_report/03_explanation_and_viva_notes.md" && grep -q '140 files in the deliverable zip' "$F/16_docs_and_report/03_explanation_and_viva_notes.md" || { a_bad=$((a_bad+1)); note "03 Records row not as expected"; }
if [ -f "$HOME/uNPU_deliverables_2026-11-11.zip" ] && command -v python3 > /dev/null; then
  zf=$(python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(len([i for i in z.infolist() if not i.is_dir()]))" "$HOME/uNPU_deliverables_2026-11-11.zip")
  [ "$zf" = 140 ] || { a_bad=$((a_bad+1)); note "the zip holds $zf files, 03 says 140"; }
else note "(zip ~/uNPU_deliverables_2026-11-11.zip not present: its file count was not checked)"; fi
[ "$a_bad" -eq 0 ] && ok "16 approximate figures: $nkeys key values (> 80), $nf files and $mb MB in Final/ (about 1,200 / about 89), zip file count as stated" || bad "16 approximate figures: $a_bad problems"

echo
echo "verify_final.sh: $npass PASS, $nfail FAIL"
[ "$nfail" -eq 0 ] || exit 1
exit 0
