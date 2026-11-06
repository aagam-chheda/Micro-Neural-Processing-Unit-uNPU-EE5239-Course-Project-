#!/usr/bin/env bash
# Compare the Design Compiler runs of the stage profiles syn20 / syn18 / syn16 (task 052).
#
# Usage (from the repo root; bash, also from a csh login shell):
#   bash scripts/syn_compare.sh                      # syn20 syn18 syn16
#   bash scripts/syn_compare.sh syn20 syn16          # just these
#   SYN_OUT=~/server_pull/syn bash scripts/syn_compare.sh
#
# Reads $SYN_OUT/<profile>/ (default <repo>/syn/out), the folder written by constraints/pm_dc_script_unpu.tcl (task 051):
#   unpu_top.profile unpu_top.area unpu_top.power unpu_top.timing unpu_top.timing_top5 unpu_top.constraint unpu_top.qor
#   unpu_top.check_timing unpu_top.check_design unpu_top.dc.v unpu_top.sdc unpu_top_cn.dc.v unpu_top_cn.sdc unpu_top_cn.ddc
# and, if you copied it there, dc.log (the log of the run; optional: without it the log checks are skipped and SAID so).
# Every file starts with the one-line profile header the script wrote ("# stage profile <name>: ..."); a file whose header
# names another profile is reported as WRONG PROFILE (a folder copied into the wrong place).
#
# Per profile it prints: the profile line; the worst setup slack per path group and overall (unpu_top.timing_top5 and
# unpu_top.timing); the number of reported paths with a negative slack (in unpu_top.timing_top5); the violated constraints
# (unpu_top.constraint; max_area is EXPECTED: the PM's set_max_area 0); cell area, total area, cell count, flops (2465 expected
# while the RTL is unchanged: a different number is FLAGGED), buf/inv area; dynamic power and leakage; the number of check_timing
# warnings and check_design errors; any line containing "latch" in the reports and the log; the instances of both netlists
# whose reference matches a don't-use pattern (the single list in syn/dc_setup.tcl; expected 0).
# A missing file is MISSING and an unreadable layout is UNPARSED; neither is ever treated as OK.
#
# Verdicts:
#   syn20          PASS only if worst setup slack >= 0, no violated constraint except max_area, no latch, no don't-use hit; else FAIL.
#   syn18, syn16   MET (worst slack >= 0) or "NOT MET (ideal target, instructor)"; never FAIL: the guidance says "ideally
#                  also at 16-18 ns". UNKNOWN if their files are missing or unreadable.
#   The recommendation (rule of task 052, A3): the TIGHTEST profile that is MET at its own period: syn16 if its worst setup
#   slack >= 0, else syn18 if >= 0, else syn20 (which must PASS). A MET profile that has a violated constraint other than
#   max_area, a latch line or a don't-use hit is INELIGIBLE (the reason is printed). If syn20 does not PASS, none qualifies. The script only
#   recommends; the user may override in writing.
#
# Exit status: 0 only if syn20 was asked for AND PASSES AND nothing is MISSING / UNPARSED / WRONG PROFILE / FLAGGED (flops) for
# the profiles asked; 1 otherwise; 2 for a usage problem.
#
# ASSUMPTION (task 052): the layouts of unpu_top.timing_top5, .constraint, .qor, .check_timing, .check_design and .profile have no real
# example yet. They are parsed as the DC commands print them (the round-3 reports of docs/planning/synthesis-reports/ are real
# examples of .area, .power, .timing and the constraint report) preceded by the profile header line. The parsers are strict: an
# expected field that is not found is UNPARSED.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${SYN_OUT:-$ROOT/syn/out}"
SETUP="${SYN_SETUP:-$ROOT/syn/dc_setup.tcl}"
EXPECT_FLOPS=2465
REQUIRED=(unpu_top.profile unpu_top.area unpu_top.power unpu_top.timing unpu_top.timing_top5 unpu_top.constraint unpu_top.qor
          unpu_top.check_timing unpu_top.check_design unpu_top.dc.v unpu_top.sdc unpu_top_cn.dc.v unpu_top_cn.sdc unpu_top_cn.ddc)
# the order of the rule: tightest first
ORDER=(syn16 syn18 syn20)
VALID="syn20 syn18 syn16"

if [ "$#" -gt 0 ]; then PROFILES=("$@"); else PROFILES=(syn20 syn18 syn16); fi
for p in "${PROFILES[@]}"; do
  case " $VALID " in *" $p "*) ;; *) echo "usage: bash scripts/syn_compare.sh [syn20] [syn18] [syn16]  (got '$p')" >&2; exit 2 ;; esac
done

declare -A INELIG PERIOD SLACK NEG5 VIOLS CELLAREA TOTAREA NCELLS FLOPS BUFINV DYN LEAK CTWARN CDERR LATCH DNU NMISS NUNP NFLAG VERDICT DETAIL
declare -A GROUPS_TXT
attention_total=0

num() { awk -v x="$1" 'BEGIN { if (x ~ /^[-+]?[0-9]+(\.[0-9]+)?$/) exit 0; exit 1 }'; }
lt0() { awk -v x="$1" 'BEGIN { exit (x + 0 < 0) ? 0 : 1 }'; }

analyse() {
  local P="$1" D="$OUT/$P" f path
  local nmiss=0 nunp=0 nflag=0 detail=""
  echo
  echo "================================================================ $P  ($D)"
  if [ ! -d "$D" ]; then
    echo "MISSING: directory $D"; NMISS[$P]=1; NUNP[$P]=0; NFLAG[$P]=0; SLACK[$P]="n/a"; VERDICT[$P]="MISSING"; return
  fi
  # ---- required files, and the profile header of each text file ----
  for f in "${REQUIRED[@]}"; do
    path="$D/$f"
    if [ ! -f "$path" ]; then echo "MISSING: $path"; nmiss=$((nmiss + 1)); continue; fi
    case "$f" in
      *.dc.v|*.sdc|*.ddc) ;;   # netlists, SDC, ddc: no header
      *)
        first="$(head -n 1 "$path")"
        case "$first" in
          "# stage profile $P:"*) ;;
          "# stage profile "*) echo "WRONG PROFILE: $path says '${first:0:60}...' (folder is $P)"; nunp=$((nunp + 1)) ;;
          *) echo "UNPARSED: $path has no profile header line as its first line"; nunp=$((nunp + 1)) ;;
        esac ;;
    esac
  done
  # ---- the profile line ----
  echo
  echo "-- profile"
  local pf="$D/unpu_top.profile" period="n/a"
  if [ -f "$pf" ]; then
    head -n 1 "$pf" | sed 's/^/  /'
    period="$(head -n 1 "$pf" | sed -nE 's/^# stage profile [a-z0-9]+: period ([0-9.]+) ns, setup uncertainty ([0-9.]+) ns, hold uncertainty ([0-9.]+) ns;.*$/\1/p')"
    if [ -z "$period" ]; then echo "  UNPARSED: the profile line has not the expected layout"; nunp=$((nunp + 1)); period="n/a"; fi
  fi
  PERIOD[$P]="$period"

  # ---- worst setup slack (timing_top5 and timing) ----
  echo
  echo "-- setup slack (unpu_top.timing_top5 and unpu_top.timing)"
  local all_sl="" neg5=0 ok=1
  for f in unpu_top.timing_top5 unpu_top.timing; do
    path="$D/$f"; [ -f "$path" ] || { ok=0; continue; }
    local parsed
    parsed="$(awk '
      /^ *Path Group:/ { g = $3 }
      /^ *slack \(/    { v = $NF; if (v !~ /^[-+]?[0-9]+(\.[0-9]+)?$/) { print "BAD " $0; next } print ((g == "") ? "(none)" : g) " " v }
      ' "$path")"
    if [ -z "$parsed" ]; then echo "  UNPARSED: no slack line in $f"; nunp=$((nunp + 1)); ok=0; continue; fi
    if echo "$parsed" | grep -q '^BAD '; then echo "  UNPARSED: a slack line of $f has no number: $(echo "$parsed" | grep -m1 '^BAD ')"; nunp=$((nunp + 1)); ok=0; continue; fi
    all_sl="$all_sl"$'\n'"$parsed"
    [ "$f" = unpu_top.timing_top5 ] && neg5=$(echo "$parsed" | awk '$2 + 0 < 0 { n++ } END { print n + 0 }')
  done
  all_sl="$(echo "$all_sl" | sed '/^$/d')"
  local worst="n/a"
  if [ -n "$all_sl" ]; then
    local pergroup
    pergroup="$(echo "$all_sl" | awk '{ if (!($1 in w) || $2 + 0 < w[$1] + 0) w[$1] = $2 } END { for (k in w) printf "%s %s\n", k, w[k] }' | sort)"
    echo "$pergroup" | while read -r g s; do echo "  group $g : worst slack $s"; done
    worst="$(echo "$all_sl" | awk 'NR == 1 || $2 + 0 < m + 0 { m = $2 } END { print m }')"
    echo "  worst overall: $worst ns;  reported paths with a negative slack (timing_top5): $neg5"
    GROUPS_TXT[$P]="$(echo "$pergroup" | tr '\n' ';')"
  fi
  SLACK[$P]="$worst"; NEG5[$P]="$neg5"

  # ---- violated constraints ----
  echo
  echo "-- violated constraints (unpu_top.constraint; max_area is expected: set_max_area 0)"
  local viols="n/a"
  path="$D/unpu_top.constraint"
  if [ -f "$path" ]; then
    if ! grep -q 'Report : constraint' "$path"; then
      echo "  UNPARSED: no 'Report : constraint' line"; nunp=$((nunp + 1))
    else
      local nv names
      nv=$(grep -c '(VIOLATED)' "$path")
      names="$(grep -E '^   [a-z_]+(/[a-z]+)?( \(.*\))?[[:space:]]*$' "$path" | sed -E 's/^   //; s/[[:space:]]+$//' | sort -u | tr '\n' ',' | sed 's/,$//')"
      if [ "$nv" -gt 0 ] && [ -z "$names" ]; then
        echo "  UNPARSED: $nv VIOLATED line(s) but no constraint name found"; nunp=$((nunp + 1))
      else
        viols="$names"; [ -z "$viols" ] && viols="(none)"
        echo "  violated: $viols  ($nv VIOLATED line(s))"
      fi
    fi
  fi
  VIOLS[$P]="$viols"

  # ---- area ----
  echo
  echo "-- area (unpu_top.area)"
  path="$D/unpu_top.area"
  local cellarea="n/a" totarea="n/a" ncells="n/a" flops="n/a" bufinv="n/a"
  if [ -f "$path" ]; then
    getn() { sed -nE "s|^$1[[:space:]]+([0-9.]+)[[:space:]]*\$|\\1|p" "$path" | head -n 1; }
    cellarea=$(getn "Total cell area:"); totarea=$(getn "Total area:"); ncells=$(getn "Number of cells:")
    flops=$(getn "Number of sequential cells:"); bufinv=$(getn "Buf/Inv area:")
    for pair in "Total cell area:$cellarea" "Total area:$totarea" "Number of cells:$ncells" "Number of sequential cells:$flops" "Buf/Inv area:$bufinv"; do
      if [ -z "${pair#*:}" ] || ! num "${pair##*:}"; then echo "  UNPARSED: '${pair%%:*}' not found or not a number"; nunp=$((nunp + 1)); fi
    done
    echo "  cells $ncells, flops $flops, total cell area $cellarea um2, total area $totarea um2, buf/inv area $bufinv um2"
    if [ "$flops" != "$EXPECT_FLOPS" ]; then echo "  FLAG: flops = $flops, expected $EXPECT_FLOPS (the RTL is unchanged)"; nflag=$((nflag + 1)); fi
  fi
  CELLAREA[$P]="${cellarea:-n/a}"; TOTAREA[$P]="${totarea:-n/a}"; NCELLS[$P]="${ncells:-n/a}"; FLOPS[$P]="${flops:-n/a}"; BUFINV[$P]="${bufinv:-n/a}"

  # ---- power ----
  echo
  echo "-- power (unpu_top.power)"
  local dyn="n/a" leak="n/a"
  path="$D/unpu_top.power"
  if [ -f "$path" ]; then
    dyn="$(sed -nE 's/^Total Dynamic Power[[:space:]]+=[[:space:]]+([0-9.]+ [munp]?W).*$/\1/p' "$path" | head -n 1)"
    leak="$(sed -nE 's/^Cell Leakage Power[[:space:]]+=[[:space:]]+([0-9.]+ [munp]?W).*$/\1/p' "$path" | head -n 1)"
    [ -n "$dyn" ] || { echo "  UNPARSED: no 'Total Dynamic Power' line"; nunp=$((nunp + 1)); dyn="n/a"; }
    [ -n "$leak" ] || { echo "  UNPARSED: no 'Cell Leakage Power' line"; nunp=$((nunp + 1)); leak="n/a"; }
    echo "  dynamic $dyn, leakage $leak"
  fi
  DYN[$P]="$dyn"; LEAK[$P]="$leak"

  # ---- check_timing, check_design ----
  echo
  echo "-- check_timing / check_design"
  local ctw="n/a" cde="n/a"
  if [ -f "$D/unpu_top.check_timing" ]; then
    ctw=$(grep -c '^Warning:' "$D/unpu_top.check_timing")
    echo "  check_timing warnings: $ctw"
    grep -m5 '^Warning:' "$D/unpu_top.check_timing" | sed 's/^/    /'
  fi
  if [ -f "$D/unpu_top.check_design" ]; then
    cde=$(grep -c '^Error:' "$D/unpu_top.check_design")
    echo "  check_design errors: $cde"
    grep -m5 '^Error:' "$D/unpu_top.check_design" | sed 's/^/    /'
    local other
    other="$(grep '^Warning:' "$D/unpu_top.check_design" | grep -vE '\((LINT-28|LINT-32|LINT-33)\)' | head -n 5)"
    [ -n "$other" ] && { echo "  check_design warnings other than the benign LINT-28/32/33 of handoff 18.8 (first 5):"; echo "$other" | sed 's/^/    /'; }
  fi
  CTWARN[$P]="$ctw"; CDERR[$P]="$cde"

  # ---- latch ----
  echo
  echo "-- lines containing 'latch' (reports and dc.log)"
  local nl=0
  for f in unpu_top.area unpu_top.power unpu_top.timing unpu_top.timing_top5 unpu_top.constraint unpu_top.qor unpu_top.check_timing unpu_top.check_design dc.log; do
    [ -f "$D/$f" ] || continue
    local hits; hits="$(grep -in 'latch' "$D/$f")"
    if [ -n "$hits" ]; then echo "$hits" | sed "s/^/  $f: /"; nl=$((nl + $(echo "$hits" | wc -l))); fi
  done
  if [ ! -f "$D/dc.log" ]; then echo "  (no dc.log in this folder: the log was NOT checked for latch or Error: lines)"; fi
  [ "$nl" -eq 0 ] && echo "  (none)"
  LATCH[$P]="$nl"
  if [ -f "$D/dc.log" ]; then
    local nerr; nerr=$(grep -c '^Error:' "$D/dc.log")
    echo "  dc.log Error: lines = $nerr"
    [ "$nerr" -gt 0 ] && { echo "  FLAG: Error: lines in dc.log"; nflag=$((nflag + 1)); }
  fi

  # ---- don't-use cells in both netlists ----
  echo
  echo "-- don't-use cell instances (patterns of syn/dc_setup.tcl)"
  local dnu=0
  if [ ! -f "$SETUP" ]; then echo "MISSING: $SETUP"; nmiss=$((nmiss + 1)); dnu="n/a"; else
    local pats; pats=$(sed -nE 's/^set DONT_USE_PATTERNS \{([^}]*)\}.*$/\1/p' "$SETUP")
    if [ -z "$pats" ]; then echo "  UNPARSED: DONT_USE_PATTERNS not found in $SETUP"; nunp=$((nunp + 1)); dnu="n/a"; else
      echo "  patterns: $pats"
      for net in unpu_top.dc.v unpu_top_cn.dc.v; do
        [ -f "$D/$net" ] || continue
        for p2 in $pats; do
          local re="${p2//\*/[A-Za-z0-9_]*}" m
          m=$(grep -nE "^[[:space:]]*$re[[:space:]]+[^[:space:]]+[[:space:]]*\(" "$D/$net")
          if [ -n "$m" ]; then echo "$m" | sed "s/^/  HIT($p2) $net: /"; dnu=$((dnu + $(echo "$m" | wc -l))); fi
        done
      done
      echo "  don't-use instances found: $dnu (expected 0)"
    fi
  fi
  DNU[$P]="$dnu"

  # ---- verdict of this profile ----
  NMISS[$P]=$nmiss; NUNP[$P]=$nunp; NFLAG[$P]=$nflag
  local reasons=""
  if [ "$nmiss" -gt 0 ] || [ "$nunp" -gt 0 ]; then
    VERDICT[$P]="UNKNOWN"; DETAIL[$P]="$nmiss missing, $nunp unreadable"
    [ "$P" = syn20 ] && { VERDICT[$P]="FAIL"; DETAIL[$P]="cannot be judged: $nmiss missing, $nunp unreadable/wrong profile"; }
    return
  fi
  if [ "$P" = syn20 ]; then
    num "$worst" && lt0 "$worst" && reasons="$reasons worst setup slack $worst < 0;"
    local extra; extra="$(echo "$viols" | tr ',' '\n' | grep -v '^max_area$' | grep -v '^(none)$' | tr '\n' ' ')"
    [ -n "$extra" ] && reasons="$reasons violated constraint(s) other than max_area: $extra;"
    [ "$nl" -gt 0 ] && reasons="$reasons $nl latch line(s);"
    [ "$dnu" != "0" ] && reasons="$reasons $dnu don't-use instance(s);"
    if [ -z "$reasons" ]; then VERDICT[$P]="PASS"; DETAIL[$P]="worst setup slack $worst ns"; else VERDICT[$P]="FAIL"; DETAIL[$P]="$reasons"; fi
  else
    if num "$worst" && ! lt0 "$worst"; then VERDICT[$P]="MET"; DETAIL[$P]="worst setup slack $worst ns at its own period ($period ns)"
    else VERDICT[$P]="NOT MET"; DETAIL[$P]="(ideal target, instructor) worst setup slack $worst ns at $period ns"; fi
    # A tighter profile that is MET on slack but has another finding is INELIGIBLE for the recommendation (task 052 follow-up).
    local extra2; extra2="$(echo "$viols" | tr ',' '\n' | grep -v '^max_area$' | grep -v '^(none)$' | tr '\n' ' ')"
    [ -n "$extra2" ] && reasons="$reasons violated constraint(s) other than max_area: $extra2;"
    [ "$nl" -gt 0 ] && reasons="$reasons $nl latch line(s);"
    [ "$dnu" != "0" ] && reasons="$reasons $dnu don't-use instance(s);"
    INELIG[$P]="$reasons"
  fi
}

echo "== syn_compare: $OUT   profiles: ${PROFILES[*]}"
for P in "${PROFILES[@]}"; do analyse "$P"; done

# ---- side-by-side table ----
echo
echo "================================================================ comparison"
printf "%-26s" "item"; for P in "${PROFILES[@]}"; do printf "%18s" "$P"; done; echo
row() { local label="$1" var="$2"; printf "%-26s" "$label"; for P in "${PROFILES[@]}"; do eval "v=\${$var[\$P]:-n/a}"; printf "%18s" "$v"; done; echo; }
row "period (ns)" PERIOD
row "worst setup slack (ns)" SLACK
row "paths < 0 (top5)" NEG5
row "total cell area (um2)" CELLAREA
row "total area (um2)" TOTAREA
row "cells" NCELLS
row "flops (expect $EXPECT_FLOPS)" FLOPS
row "buf/inv area (um2)" BUFINV
row "dynamic power" DYN
row "leakage" LEAK
row "check_timing warnings" CTWARN
row "check_design errors" CDERR
row "violated constraints" VIOLS
row "latch lines" LATCH
row "don't-use hits" DNU

# ---- verdicts ----
echo
echo "================================================================ verdicts"
exit_code=0
syn20_asked=0; syn20_pass=0
for P in "${PROFILES[@]}"; do
  v="${VERDICT[$P]:-UNKNOWN}"
  case "$P" in
    syn20) syn20_asked=1; [ "$v" = PASS ] && syn20_pass=1; echo "$P: $v  (${DETAIL[$P]:-})" ;;
    *)     echo "$P: $v  (${DETAIL[$P]:-})" ;;
  esac
  [ "${NMISS[$P]:-1}" -gt 0 ] && exit_code=1
  [ "${NUNP[$P]:-0}" -gt 0 ] && exit_code=1
  [ "${NFLAG[$P]:-0}" -gt 0 ] && exit_code=1
done
[ "$syn20_asked" -eq 1 ] && [ "$syn20_pass" -eq 1 ] || exit_code=1

# ---- recommendation (rule A3) ----
echo
rec=""
if [ "$syn20_asked" -eq 0 ]; then
  echo "RECOMMENDATION: none. syn20 was not asked for and it must PASS (the mandatory profile)."
elif [ "$syn20_pass" -ne 1 ]; then
  echo "RECOMMENDATION: none qualifies. syn20 does not PASS."
else
  for P in "${ORDER[@]}"; do
    case " ${PROFILES[*]} " in *" $P "*) ;; *) continue ;; esac
    v="${VERDICT[$P]:-UNKNOWN}"
    if [ "$P" = syn20 ] && [ "$v" = PASS ]; then rec="$P"; break; fi
    if [ "$v" = MET ] && [ -n "${INELIG[$P]:-}" ]; then echo "$P: MET on slack but INELIGIBLE for the recommendation:${INELIG[$P]}"; continue; fi
    if [ "$v" = MET ] && [ "${NFLAG[$P]:-0}" -eq 0 ]; then rec="$P"; break; fi
    if [ "$v" = MET ]; then echo "$P: MET on slack but INELIGIBLE for the recommendation: flagged (flop count or dc.log Error: lines)"; fi
  done
  if [ -n "$rec" ]; then
    echo "RECOMMENDATION: take the netlist of $rec  (the tightest profile that is met at its own period: ${DETAIL[$rec]})"
    echo "  files: $OUT/$rec/unpu_top_cn.dc.v (the clean-name netlist that goes to the layout flow)"
    echo "  the user may override this rule in writing; the script only recommends"
  else
    echo "RECOMMENDATION: none qualifies."
  fi
fi

echo
if [ "$exit_code" -eq 0 ]; then echo "== syn_compare: syn20 PASSES and nothing is missing, unreadable or flagged"; else echo "== syn_compare: NEEDS ATTENTION (syn20 not passing or not asked for, or MISSING / UNPARSED / WRONG PROFILE / FLAG lines above)"; fi
exit $exit_code
