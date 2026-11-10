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
# Exit status: 0 = PASS, 1 = FAIL, 2 = usage / environment problem (nothing was judged): a bad argument, an invalid SDF_ACCEPT, or a run that died on the licence only (*F,NOLICN as the only *E/*F line).
# Task 094 (run 3): environment variables, all optional.
#   SDF_ACCEPT="nep_cond nl1_neg net_remrec"  the SDF warning classes THE USER has approved (default none): README "Task 094". Printed at the start and in the verdict words.
#   LICENSE_RETRIES=<n> LICENSE_WAIT_S=<s>    after a licence-only death, wait and run again up to n times (default 0 = no retry, 600 s); each failed attempt's log is kept as .attemptN.log.
#   The verdict reads the SDF of the run (JUDGE_SDF, set here) to count the unmatched entries TRUE, because Xcelium prints at most 500 lines per message id, and checks the counts against Xcelium's own "Annotation completed with N Errors and M Warnings".
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
# Task 094 (run 3, final layout): the classes of SDF warnings that are NOT accepted by default. Each is accepted only if the USER approves it by naming it in the environment variable SDF_ACCEPT
# (space or comma separated), for example `env SDF_ACCEPT="nep_cond nl1_neg net_remrec" bash pnr_v2/sim/run_postlayout_sim.sh ss checks`; the verdict words then say exactly what was accepted. README "Task 094".
SDF_APPROVABLE="nep_cond nl1_neg net_remrec"
# nep_cond: *W,SDFNEP on a COND-form arc (COND B===1'b0 && CI===1'b0 (IOPATH A S)): the model's path conditions are written `(CI == 1'b0) && (B == 1'b0)`. Cells with COND arcs in the run-3 SDF: full adders and a 3-input XOR.
SDFNEP_COND_CELLS="ad01d0 ad01d1 ad01d4 xr03d1"
# nl1_neg / net_remrec: the reset flops, whose models have `$recovery (posedge CDN, ...)` and `$hold (posedge CP, posedge CDN, th_cp_cdn_l)` only (no $removal, no negedge recovery) and no negative-limit support
# without `neg_tchk`. Cells of the run-3 SDF that carry REMOVAL/RECOVERY entries.
SDFCHK_CELLS="dfcrn1 dfcrn2 dfcrq2 decrq1"

# ------------------------------------------------------------------------------------------------------------------------
# Helpers of the verdict (task 094)
# ------------------------------------------------------------------------------------------------------------------------
# Xcelium prints, for a warning with a source location, the SOURCE LINE and a caret line (`     |`) BEFORE the message. Those source lines are model code ($hold (...), assign ...), not events. strip_context removes every
# line that is directly followed by a caret-only line, and the caret line itself. (Run 3: the old pattern counted 500 `$hold`/`$recovery` source lines as "500 timing-check violations" in checks mode.)
strip_context() {
  awk '{ if (held) { if ($0 ~ /^[ \t]*\|[ \t]*$/) { held = 0; next } print prev } prev = $0; held = 1 } END { if (held) print prev }' "$1"
}
# SDF_ACCEPT: the classes of SDF warnings that the USER has approved (README "Task 094"): a space or comma separated list of SDF_APPROVABLE. Empty (the default) approves nothing new. Prints the problem, or nothing.
sdf_accept_problem() {
  local t
  for t in ${1//,/ }; do
    case " $SDF_APPROVABLE " in *" $t "*) ;; *) echo "SDF_ACCEPT contains '$t', which is not an approvable class (known: $SDF_APPROVABLE)"; return 0 ;; esac
  done
  return 0
}
# the classes counted in the SDF for the reconciliation. sdf_expect <sdf> <ss|ff|"">  -> lines `class<TAB>cell<TAB>count`:
#   edge  IOPATH entries with an edge qualifier (posedge|negedge X)        -- unmatched (SDFNEP) on the cells of SDFNEP_ALLOWED_CELLS; on flops (CP -> Q) they match and give no warning
#   cond  IOPATH entries in a COND wrapper                                 -- unmatched (SDFNEP) on every cell
#   net   REMOVAL entries and RECOVERY entries with (negedge data)         -- non-existent timing check in the model (SDFNET)
#   nl1   SETUP / HOLD / RECOVERY(posedge) entries with a strictly negative value -- clamped to 0 (SDFNL1); the value read is the one of MTM_CONTROL (ss: MAXIMUM = 3rd field, ff: MINIMUM = 1st)
sdf_expect() {
  awk -v corner="$2" '
    BEGIN { fld = (corner == "ff") ? 1 : 3 }
    /\(CELLTYPE/ { if (match($0, /"[^"]+"/)) cell = substr($0, RSTART + 1, RLENGTH - 2); next }
    /IOPATH/ {
      if ($0 ~ /^[ \t]*\(COND/) c = "cond"; else if ($0 ~ /\(IOPATH[ \t]+\((posedge|negedge)[ \t]/) c = "edge"; else c = "plain"
      n[c "\t" cell]++; next
    }
    /^[ \t]*\((SETUP|HOLD|RECOVERY|REMOVAL)[ \t]/ {
      if ($0 ~ /^[ \t]*\(REMOVAL[ \t]/) { n["net\t" cell]++; next }
      if ($0 ~ /^[ \t]*\(RECOVERY[ \t]+\(negedge/) { n["net\t" cell]++; next }
      if (match($0, /\(-?[0-9.]*:[-0-9.]*:[-0-9.]*\)[ \t]*\)[ \t]*$/)) {
        t = substr($0, RSTART + 1, RLENGTH - 2); sub(/\).*$/, "", t); k = split(t, a, ":")
        v = a[fld]; if (v == "") v = (fld == 1 ? a[3] : a[1])
        if (v != "" && v + 0 < 0) n["nl1\t" cell]++
      }
    }
    END { for (k in n) print k "\t" n[k] }' "$1"
}
# sum of the counts of one class in the text of sdf_expect; with a cell list (space separated) only those cells, with "!list" all cells NOT in the list
exp_sum() {
  local text="$1" cls="$2" cells="${3:-}"
  printf '%s\n' "$text" | awk -F'\t' -v cls="$cls" -v cells="$cells" '
    BEGIN { neg = (substr(cells, 1, 1) == "!"); if (neg) cells = substr(cells, 2); m = split(cells, L, " "); for (i = 1; i <= m; i++) inl[L[i]] = 1 }
    $1 == cls { if (cells == "" || (!neg && ($2 in inl)) || (neg && !($2 in inl))) s += $3 }
    END { print s + 0 }'
}
# the cells (with counts) of one class, for the printed table
exp_cells() {
  printf '%s\n' "$1" | awk -F'\t' -v cls="$2" -v cells="${3:-}" 'BEGIN { m = split(cells, L, " "); for (i = 1; i <= m; i++) inl[L[i]] = 1 } $1 == cls && (cells == "" || ($2 in inl)) { printf "%s%s %d", (n++ ? ", " : ""), $2, $3 }'
}
# the module that contains a line of a model file (awk: the last `module <name>` line at or before it)
model_module_at() { awk -v L="$2" '/^[ \t]*module[ \t]/ { m = $2; sub(/[ (].*$/, "", m) } NR == L { print m; exit }' "$1"; }
# the licence part of the verdict: what the log and the console say about the checkout
licence_report() {
  local log="$1" console="${2:-}"
  echo "--- ENVIRONMENT PROBLEM, nothing about the design was judged: the simulator could not check out a licence (the only *F, line is *F,NOLICN)"
  echo "--- from the log: the checkout attempt and the NOLICN line:"
  awk '/Trying to check out license/ { p = 1 } p { print } /\*F,NOLICN/ { exit }' "$log" | sed 's/^/    /'
  if [ -n "$console" ] && [ -s "$console" ]; then
    echo "--- from the console ($console): the licence feature(s), server and error (counted):"
    grep -E '^(Feature:|Server name:|License path:|FlexNet Licensing error:|license file\(s\):)' "$console" | sort | uniq -c | sort -rn | head -n 12 | sed 's/^/    /'
    grep -m1 -A3 'FlexNet Licensing checkout error' "$console" | sed 's/^/    /'
  else
    echo "--- the console file is not available: paste the lines around \`*F,NOLICN\` and the FlexNet lines (Feature:, License path:, FlexNet Licensing error:) of the console output"
  fi
  echo "--- this is not a FAIL of the design: wait and run the same command again (LICENSE_RETRIES=<n> LICENSE_WAIT_S=<seconds> let the script retry by itself, README \"Task 094\")"
}

# ------------------------------------------------------------------------------------------------------------------------
# The verdict. judge_log <log> <checks|nochecks> [annotation_log]  -> prints the evidence, returns 0 (PASS), 1 (FAIL) or 2 (environment problem: licence only, or an invalid SDF_ACCEPT).
# Optional inputs through variables (set by main): JUDGE_SDF (the SDF of the run: the TRUE counts of the unmatched SDF entries, reconciled with Xcelium's own total), JUDGE_CORNER (ss|ff), JUDGE_CONSOLE (the
# console file of the run), JUDGE_MODEL (the cell model, to attribute a model line to its module). SDF_ACCEPT: the SDF classes the user approved (default: none).
# Sets the global JUDGE_CAVEAT: empty for a clean PASS, the full "PASS (with ...)" text when an SDF limitation was accepted.
# ------------------------------------------------------------------------------------------------------------------------
judge_log() {
  local log="$1" mode="$2" annlog="${3:-}"
  local sdf="${JUDGE_SDF:-}" corner="${JUDGE_CORNER:-}" console="${JUDGE_CONSOLE:-}" model="${JUDGE_MODEL:-}" accept="${SDF_ACCEPT:-}"
  local why=() n_fail n_err n_pass checked n_ann n_viol endt n_nolic
  JUDGE_CAVEAT=""
  if [ ! -e "$log" ]; then echo "--- FAIL: the log $log does not exist"; return 1; fi
  if [ ! -s "$log" ]; then echo "--- FAIL: the log $log is empty"; return 1; fi
  local accprob; accprob=$(sdf_accept_problem "$accept")
  if [ -n "$accprob" ]; then echo "--- ENVIRONMENT PROBLEM: $accprob"; return 2; fi
  n_fail=$(grep -c 'FAIL' "$log")
  n_err=$(grep -cE '\*[EF],' "$log")
  n_pass=$(grep -c 'ALL CHECKS PASSED' "$log")
  checked=$(grep -oE 'checked [0-9]+ value' "$log" | tail -n1 | grep -oE '[0-9]+')
  endt=$(grep -oE 'at time [0-9]+ [A-Za-z]+' "$log" | tail -n1)
  n_nolic=$(grep -c '\*F,NOLICN' "$log")
  # a run that died on the licence only (no check line, no FAIL, no other *E/*F): an environment problem, exit 2, not a FAIL of the design
  if [ "$n_nolic" -gt 0 ] && [ "$n_err" -eq "$n_nolic" ] && [ "$n_pass" -eq 0 ] && [ "$n_fail" -eq 0 ] && [ -z "$checked" ]; then
    licence_report "$log" "$console"
    return 2
  fi
  echo "--- first 5 FAIL lines:"
  grep -m5 -n 'FAIL' "$log" | sed 's/^/    /'
  echo "--- first 5 *E,/*F, lines:"
  grep -m5 -nE '\*[EF],' "$log" | sed 's/^/    /'
  # ---- SDF annotation evidence (log and the separate annotation log) ----
  local anntext
  anntext=$( { grep -iE 'annotat' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -iE 'annotat' "$annlog"; } 2>/dev/null | grep -vE '\*[WEF],(SDFNEP|SDFNCAP|SDFNL1|SDFNET)' )
  n_ann=$(printf '%s' "$anntext" | grep -c . )
  echo "--- SDF annotation lines (Xcelium's own counts; SDF warning lines are not counted as evidence; $n_ann lines; the annotated number must be large, 'unannotated'/'not annotated' counts are printed as they are):"
  printf '%s\n' "$anntext" | head -n 12 | sed 's/^/    /'
  # ---- SDF messages by id (log and annotation log, duplicates removed, log order kept) ----
  local sdfall
  sdfall=$( { grep -E '\*[WEF],SDF' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -E '\*[WEF],SDF' "$annlog"; } 2>/dev/null | awk '!s[$0]++' )
  echo "--- SDF messages by id (all of them, before classification; the lines Xcelium PRINTED: it prints a fixed number per id and then stops, the true counts are below):"
  printf '%s\n' "$sdfall" | grep -oE '\*[WEF],SDF[A-Z0-9]*' | sort | uniq -c | sed 's/^/    /'
  # SDFNCAP: information (the port annotation still occurs)
  local ncap_txt n_ncap
  ncap_txt=$(printf '%s\n' "$sdfall" | grep -E '\*[WEF],SDFNCAP')
  n_ncap=$(printf '%s' "$ncap_txt" | grep -c . )
  echo "--- *W,SDFNCAP (INFORMATION, not a failure: the interconnect source is separated by a unidirectional continuous assign; the port annotation still occurs): $n_ncap; the first 3:"
  printf '%s\n' "$ncap_txt" | head -n 3 | sed 's/^/    /'
  # ---- classify every other printed SDF line ----
  local nep_re='non-existent path \(IOPATH \((posedge|negedge) ([A-Za-z0-9_]+)\) ([A-Za-z0-9_]+)\) of instance ([^ ]+) of module ([A-Za-z0-9_]+)'
  local cond_re='non-existent path \(COND .* \(IOPATH ([A-Za-z0-9_]+) ([A-Za-z0-9_]+)\)\) of instance ([^ ]+) of module ([A-Za-z0-9_]+)'
  local nl1_re='\*W,SDFNL1 \((.*),([0-9]+)\|[0-9]+\): Attempt to annotate a negative value to a 1 limit timing check in instance \(([^)]+)\), setting to 0'
  local net_re='Unable to annotate to non-existent timing check \((REMOVAL|RECOVERY) \((posedge|negedge) ([A-Za-z0-9_]+)\) \((posedge|negedge) ([A-Za-z0-9_]+)\) \(([-0-9.:]+)\)\) of instance ([^ ]+) of module ([A-Za-z0-9_]+)'
  local n_nep_ok=0 n_nep_bad=0 nep_ok_rec="" nep_bad_txt="" line cell mod f ln
  local n_cond_ok=0 n_cond_bad=0 cond_bad_txt="" n_nl1_ok=0 n_nl1_bad=0 nl1_bad_txt="" n_net_ok=0 n_net_bad=0 net_bad_txt=""
  local other_txt="" n_other=0 nl1_lines="" nl1_map=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *'*W,SDFNCAP'*|*'SDFIRE'*|*'SDFCNC'*) continue ;;
      *'*W,SDFNEP'*)
        if [[ $line =~ $nep_re ]]; then
          cell="${BASH_REMATCH[5]}"
          case " $SDFNEP_ALLOWED_CELLS " in
            *" $cell "*) n_nep_ok=$((n_nep_ok+1)); nep_ok_rec+="$cell"$'\t'"(${BASH_REMATCH[1]} ${BASH_REMATCH[2]}) ${BASH_REMATCH[3]}"$'\n' ;;
            *) n_nep_bad=$((n_nep_bad+1)); nep_bad_txt+="[cell type $cell is not in the allowed list] $line"$'\n' ;;
          esac
        elif [[ $line =~ $cond_re ]]; then
          cell="${BASH_REMATCH[4]}"
          case " $SDFNEP_COND_CELLS " in
            *" $cell "*) n_cond_ok=$((n_cond_ok+1)) ;;
            *) n_cond_bad=$((n_cond_bad+1)); cond_bad_txt+="[cell type $cell is not in the COND list] $line"$'\n' ;;
          esac
        else
          n_nep_bad=$((n_nep_bad+1)); nep_bad_txt+="[not of the form IOPATH (posedge|negedge X) Y] $line"$'\n'
        fi ;;
      *'*W,SDFNL1'*)
        if [[ $line =~ $nl1_re ]]; then nl1_lines+="${BASH_REMATCH[1]},${BASH_REMATCH[2]}"$'\n'; else n_nl1_bad=$((n_nl1_bad+1)); nl1_bad_txt+="[not of the form: negative value to a 1 limit timing check] $line"$'\n'; fi ;;
      *'*W,SDFNET'*)
        if [[ $line =~ $net_re ]]; then
          cell="${BASH_REMATCH[8]}"
          if { [ "${BASH_REMATCH[1]}" = REMOVAL ] || [ "${BASH_REMATCH[2]}" = negedge ]; }; then
            case " $SDFCHK_CELLS " in
              *" $cell "*) n_net_ok=$((n_net_ok+1)) ;;
              *) n_net_bad=$((n_net_bad+1)); net_bad_txt+="[cell type $cell is not in the reset-flop list] $line"$'\n' ;;
            esac
          else n_net_bad=$((n_net_bad+1)); net_bad_txt+="[RECOVERY (posedge ...) exists in the model: not the known form] $line"$'\n'; fi
        else n_net_bad=$((n_net_bad+1)); net_bad_txt+="[not of the form: non-existent REMOVAL/RECOVERY timing check] $line"$'\n'; fi ;;
      *) other_txt+="$line"$'\n'; n_other=$((n_other+1)) ;;
    esac
  done <<< "$sdfall"
  # SDFNL1 lines carry the model file and line, not the module: attribute each distinct (file,line) once
  if [ -n "$nl1_lines" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      ln="${f##*,}"; f="${f%,*}"
      mod=""
      if [ -r "$f" ]; then mod=$(model_module_at "$f" "$ln"); elif [ -n "$model" ] && [ -r "$model" ]; then mod=$(model_module_at "$model" "$ln"); fi
      nl1_map+="$f,$ln $mod"$'\n'
    done < <(printf '%s' "$nl1_lines" | sort -u)
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      mod=$(printf '%s' "$nl1_map" | awk -v k="$f" '$1 == k { print $2; exit }')
      case " $SDFCHK_CELLS " in
        *" $mod "*) n_nl1_ok=$((n_nl1_ok+1)) ;;
        *) n_nl1_bad=$((n_nl1_bad+1)); nl1_bad_txt+="[line $f of the model is in module '${mod:-unknown}', not in the reset-flop list] SDFNL1"$'\n' ;;
      esac
    done < <(printf '%s' "$nl1_lines")
  fi
  # ---- the SDF side: the TRUE number of unmatched / clamped entries, reconciled with Xcelium's total ----
  local sdf_exp="" have_sdf=0 e_edge="" e_cond="" e_net="" e_nl1="" ann_line ann_e="" ann_w="" explained="" recon="none" recon_diff=""
  ann_line=$(grep -m1 -E 'Annotation completed with [0-9]+ Errors? and [0-9]+ Warnings?' "$log")
  if [ -n "$ann_line" ]; then
    ann_e=$(printf '%s' "$ann_line" | sed -nE 's/.*completed with ([0-9]+) Error.*/\1/p')
    ann_w=$(printf '%s' "$ann_line" | sed -nE 's/.* and ([0-9]+) Warning.*/\1/p')
  fi
  if [ -n "$sdf" ] && [ -s "$sdf" ]; then
    have_sdf=1
    sdf_exp=$(sdf_expect "$sdf" "$corner")
    e_edge=$(exp_sum "$sdf_exp" edge "$SDFNEP_ALLOWED_CELLS")
    e_cond=$(exp_sum "$sdf_exp" cond)
    e_net=$(exp_sum "$sdf_exp" net)
    e_nl1=$(exp_sum "$sdf_exp" nl1)
    if [ "$mode" = checks ]; then explained=$((e_edge + e_cond + e_net + e_nl1)); else explained=$((e_edge + e_cond)); fi
    if [ -n "$ann_w" ]; then
      recon_diff=$((ann_w - explained))
      if [ "$recon_diff" -eq 0 ]; then recon="ok"; else recon="MISMATCH"; fi
    fi
  fi
  # ---- SDFNEP summary (the 2026-11-09 acceptance: the edge form on the listed cells, unchanged) ----
  local nep_cap
  nep_cap=$(grep -E 'MXWARN.*SDFNEP' "$log")
  echo "--- *W,SDFNEP: total $((n_nep_ok + n_nep_bad + n_cond_ok + n_cond_bad)); in the accepted class (IOPATH edge form on a cell of: $SDFNEP_ALLOWED_CELLS): $n_nep_ok; outside it: $n_nep_bad; COND form (class nep_cond, needs approval): $((n_cond_ok + n_cond_bad)) (printed lines)"
  if [ "$n_nep_ok" -gt 0 ]; then
    echo "    count per cell type:"; printf '%s' "$nep_ok_rec" | cut -f1 | sort | uniq -c | sort -rn | sed 's/^/        /'
    echo "    count per arc form:";  printf '%s' "$nep_ok_rec" | cut -f2 | sort | uniq -c | sort -rn | sed 's/^/        /'
  fi
  if [ -n "$nep_cap" ]; then
    echo "    NOTE: the message cap of 1000 was reached: the real count is higher (the count above is a lower bound; the rule is applied to the printed lines$( [ "$recon" = ok ] && echo "; the true counts below are checked against Xcelium's total" )):"
    printf '%s\n' "$nep_cap" | head -n 2 | sed 's/^/        /'
  fi
  if [ "$n_nep_bad" -gt 0 ]; then
    echo "    SDFNEP outside the accepted class, the first 5:"
    printf '%s' "$nep_bad_txt" | head -n 5 | sed 's/^/        /'
  fi
  # ---- the true counts and the reconciliation ----
  if [ "$have_sdf" -eq 1 ]; then
    echo "--- SDF warning classes, TRUE counts from $sdf (corner ${corner:-?}, mode $mode), checked against Xcelium's own total:"
    printf '    %-12s %-9s %9s  %s\n' class approved entries "cells (entries)"
    printf '    %-12s %-9s %9s  %s\n' nep_edge "always" "$e_edge" "$(exp_cells "$sdf_exp" edge "$SDFNEP_ALLOWED_CELLS")  [the cells of SDFNEP_ALLOWED_CELLS only; edge arcs of flops match]"
    printf '    %-12s %-9s %9s  %s\n' nep_cond "$(case " ${accept//,/ } " in *" nep_cond "*) echo yes;; *) echo NO;; esac)" "$e_cond" "$(exp_cells "$sdf_exp" cond)"
    if [ "$mode" = checks ]; then
      printf '    %-12s %-9s %9s  %s\n' nl1_neg "$(case " ${accept//,/ } " in *" nl1_neg "*) echo yes;; *) echo NO;; esac)" "$e_nl1" "$(exp_cells "$sdf_exp" nl1)"
      printf '    %-12s %-9s %9s  %s\n' net_remrec "$(case " ${accept//,/ } " in *" net_remrec "*) echo yes;; *) echo NO;; esac)" "$e_net" "$(exp_cells "$sdf_exp" net)"
    else echo "    (nl1_neg and net_remrec do not apply: the timing checks are off in this mode)"; fi
    if [ -n "$ann_line" ]; then
      echo "    Xcelium: '$(printf '%s' "$ann_line" | sed 's/^[[:space:]]*//')'; explained by the SDF: $explained; difference: $recon_diff  ->  reconciliation $recon"
    else echo "    NOTE: the log has no 'Annotation completed with N Errors and M Warnings' line: the true counts cannot be checked against Xcelium"; fi
  else
    echo "--- SDF warning classes: the SDF of the run is not available to the verdict (JUDGE_SDF): only the PRINTED lines are classified; the true counts are NOT known"
  fi
  # ---- unknown ids and not-found text ----
  local sdftext n_sdfwarn cap_other
  cap_other=$(grep -E 'MXWARN.*SDF' "$log" | grep -vE "'(SDFNEP|SDFNCAP)'")
  sdftext=$( { grep -iE 'sdf.*(not found|unmatched|cannot find|no such|could not)' "$log"; [ -n "$annlog" ] && [ -s "$annlog" ] && grep -iE '(not found|unmatched|cannot find|no such instance)' "$annlog"; } 2>/dev/null | grep -vE '\*[WEF],(SDFNCAP|SDFNEP|SDFNL1|SDFNET)' | awk '!s[$0]++' )
  n_sdfwarn=$(printf '%s' "$sdftext" | grep -c . )
  echo "--- SDF warnings of unknown id or form: $n_other; not-found / unmatched text lines: $n_sdfwarn; the first 5 of both:"
  { printf '%s' "$other_txt"; printf '%s\n' "$sdftext"; } | grep . | head -n 5 | sed 's/^/    /'
  local bad_form
  bad_form="$(printf '%s%s%s' "$cond_bad_txt" "$nl1_bad_txt" "$net_bad_txt")"
  if [ -n "$bad_form" ]; then echo "--- SDF lines outside the form or the cell list of their class, the first 5:"; printf '%s' "$bad_form" | head -n 5 | sed 's/^/    /'; fi
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
  local tchk_line tchk_total tchk_dis
  tchk_line=$(grep -m1 -E 'No\. of Tchecks +=' "$log")
  tchk_total=$(printf '%s' "$tchk_line" | sed -nE 's/.*No\. of Tchecks += *([0-9]+).*/\1/p')
  tchk_dis=$(printf '%s' "$tchk_line" | sed -nE 's/.*No\. of Disabled Tchecks += *([0-9]+).*/\1/p')
  if [ "$mode" = checks ]; then
    local clean viol_hdr viol_body n_hdr n_body
    clean=$(strip_context "$log")
    viol_hdr=$(printf '%s\n' "$clean" | grep -iE 'timing violation|\*[WE],TCHKVIO')
    viol_body=$(printf '%s\n' "$clean" | grep -iE '\$(setup|hold|recovery|removal|width|period|setuphold|recrem|skew|nochange)[A-Za-z<>]*[[:space:]]*\(.*[0-9][[:space:]]*(fs|ps|ns|us|ms)([^A-Za-z]|$)')
    n_hdr=$(printf '%s' "$viol_hdr" | grep -c . ); n_body=$(printf '%s' "$viol_body" | grep -c . )
    n_viol=$n_hdr; [ "$n_body" -gt "$n_viol" ] && n_viol=$n_body
    echo "--- timing-check violations (checks mode): $n_viol (message lines $n_hdr, check lines with times $n_body; the source-context lines under the warnings are not events); the first 10 (time and instance are in the line):"
    { printf '%s\n' "$viol_hdr"; printf '%s\n' "$viol_body"; } | grep . | awk '!s[$0]++' | head -n 10 | sed 's/^/    /'
    if [ -n "$tchk_line" ]; then
      echo "--- timing checks in this run (Xcelium's statistics): $tchk_total checks, disabled $tchk_dis  [a checks run needs 0 disabled]"
    else
      echo "--- NOTE: the log has no 'No. of Tchecks' statistics line: it cannot be confirmed from the log that the timing checks were enabled"
    fi
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
  [ "$n_other" -eq 0 ] || why+=("$n_other SDF warnings of an id that is not accepted (only SDFNCAP, the bounded SDFNEP class and the approved classes are)")
  [ -n "${ann_e:-}" ] && [ "${ann_e:-0}" -ne 0 ] && why+=("Xcelium's annotation reports $ann_e Errors")
  [ "$n_viol" -eq 0 ] || why+=("$n_viol timing-check violations")
  [ "$n_sdfc" -eq 0 ] || why+=("the SDF could not be compiled: check the SDFVERSION (needs 3.0 if it has REMOVAL/RECOVERY entries) and regenerate with pv.tcl")
  if [ "$mode" = checks ] && [ -n "$tchk_line" ] && [ "${tchk_dis:-0}" -gt 0 ]; then why+=("the timing checks are DISABLED in a checks run ($tchk_dis of $tchk_total)"); fi
  # the reconciliation: every warning Xcelium counted must be explained by a known class
  if [ "$recon" = MISMATCH ]; then why+=("Xcelium counted $ann_w SDF warnings, the SDF explains $explained in the known classes (difference $recon_diff): the hidden part of the cap is NOT classified"); fi
  # a message cap on an id: hidden lines. SDFNL1 / SDFNET are acceptable only when the reconciliation proves the hidden part; any other id is a FAIL as before
  local capid cap_bad=""
  while IFS= read -r capid; do
    [ -n "$capid" ] || continue
    case "$capid" in
      *"'SDFNL1'"*|*"'SDFNET'"*) [ "$recon" = ok ] || cap_bad="$capid" ;;
      *) cap_bad="$capid" ;;
    esac
  done <<< "$cap_other"
  [ -z "$cap_bad" ] || why+=("the message cap was reached for an SDF message id other than SDFNEP/SDFNCAP and the hidden part is not proven by the SDF reconciliation: the rest of that class is hidden")
  # ---- the classes: approval and the cell lists, with the true counts when the SDF is known ----
  local acc_text="" cls approved n_cls cells_out
  acceptwords=" ${accept//,/ } "
  # count of a class: the true count when known (and the reconciliation held), else the printed lines
  local c_edge c_cond c_nl1 c_net
  if [ "$have_sdf" -eq 1 ]; then c_edge=$e_edge; c_cond=$e_cond; c_nl1=$e_nl1; c_net=$e_net; else c_edge=$n_nep_ok; c_cond=$((n_cond_ok + n_cond_bad)); c_nl1=$((n_nl1_ok + n_nl1_bad)); c_net=$((n_net_ok + n_net_bad)); fi
  [ "$mode" = checks ] || { [ "$have_sdf" -eq 1 ] && { c_nl1=0; c_net=0; }; }
  for cls in nep_cond nl1_neg net_remrec; do
    case "$cls" in nep_cond) n_cls=$c_cond ;; nl1_neg) n_cls=$c_nl1 ;; net_remrec) n_cls=$c_net ;; esac
    [ "$n_cls" -gt 0 ] || continue
    case "$acceptwords" in
      *" $cls "*) approved=1 ;;
      *) approved=0 ;;
    esac
    if [ "$approved" -eq 0 ]; then
      why+=("SDF class $cls: $n_cls warning(s)$( [ "$have_sdf" -eq 1 ] || echo ' (printed lines only)' ), NOT approved: classified in the README (task 094), accepted only when the user approves it with SDF_ACCEPT=$cls")
    else
      case "$cls" in
        nep_cond) cells_out=$([ "$have_sdf" -eq 1 ] && exp_sum "$sdf_exp" cond "!$SDFNEP_COND_CELLS" || echo "$n_cond_bad"); [ "$cells_out" -eq 0 ] || why+=("SDF class nep_cond: $cells_out COND-form entries are on cells outside the approved list ($SDFNEP_COND_CELLS)") ;;
        nl1_neg) cells_out=$([ "$have_sdf" -eq 1 ] && exp_sum "$sdf_exp" nl1 "!$SDFCHK_CELLS" || echo "$n_nl1_bad"); [ "$cells_out" -eq 0 ] || why+=("SDF class nl1_neg: $cells_out negative limits are on cells outside the approved list ($SDFCHK_CELLS)") ;;
        net_remrec) cells_out=$([ "$have_sdf" -eq 1 ] && exp_sum "$sdf_exp" net "!$SDFCHK_CELLS" || echo "$n_net_bad"); [ "$cells_out" -eq 0 ] || why+=("SDF class net_remrec: $cells_out REMOVAL/RECOVERY entries are on cells outside the approved list ($SDFCHK_CELLS)") ;;
      esac
      case "$cls" in
        nep_cond) acc_text+="$n_cls SDFNEP COND-form arcs (adder sum on ad01*, xr03d1) ran at zero delay; " ;;
        nl1_neg) acc_text+="$n_cls negative hold/recovery limits of reset flops were clamped to 0 by Xcelium (stricter than the SDF: conservative); " ;;
        net_remrec) acc_text+="$n_cls REMOVAL/RECOVERY(negedge) entries of reset flops were not annotated (the model's own removal limit applies); " ;;
      esac
    fi
  done
  # the bad forms inside an approved class are failures too
  [ "$n_cond_bad" -eq 0 ] || why+=("$n_cond_bad SDFNEP COND-form lines are on a cell outside the list")
  [ "$n_nl1_bad" -eq 0 ] || why+=("$n_nl1_bad SDFNL1 lines outside the known form or the reset-flop list")
  [ "$n_net_bad" -eq 0 ] || why+=("$n_net_bad SDFNET lines outside the known form or the reset-flop list")
  JUDGE_CAVEAT=""
  if [ "${#why[@]}" -eq 0 ]; then
    if [ -n "$acc_text" ]; then
      JUDGE_CAVEAT="PASS (with documented SDF limitations, SDF_ACCEPT='${accept}': ${c_edge} SDFNEP edge-form arcs on mux-select, XOR/XNOR and adder-sum ran at zero delay; ${acc_text}the simulation is optimistic on the zero-delay arcs; timing sign-off is PrimeTime)"
      echo "--- $JUDGE_CAVEAT"
    elif [ "$c_edge" -gt 0 ]; then
      JUDGE_CAVEAT="PASS (with the documented SDF limitation: $c_edge SDFNEP warnings on mux-select, XOR/XNOR and adder-sum arcs ran at zero delay; the simulation is slightly optimistic on those arcs; timing sign-off is PrimeTime)"
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
  # ---- the run, with the optional wait-and-retry for a licence that cannot be checked out (task 094) ----
  local retries="${LICENSE_RETRIES:-0}" wait_s="${LICENSE_WAIT_S:-600}"
  case "$retries" in ''|*[!0-9]*) echo "run_postlayout_sim.sh: LICENSE_RETRIES='$retries' is not a number" >&2; return 2 ;; esac
  case "$wait_s" in ''|*[!0-9]*) echo "run_postlayout_sim.sh: LICENSE_WAIT_S='$wait_s' is not a number of seconds" >&2; return 2 ;; esac
  local accprob; accprob=$(sdf_accept_problem "${SDF_ACCEPT:-}")
  if [ -n "$accprob" ]; then echo "run_postlayout_sim.sh: $accprob" >&2; return 2; fi
  echo "=== SDF classes approved by the user (SDF_ACCEPT): ${SDF_ACCEPT:-none}  [the documented SDFNEP edge-form acceptance of 2026-11-09 is always on]; licence retries: $retries, wait $wait_s s"
  export JUDGE_SDF="$SDF" JUDGE_CORNER="$corner" JUDGE_CONSOLE="${LOG%.log}.console" JUDGE_MODEL="$MODEL"
  local attempt=0 t0 rc el v
  while :; do
    rm -f "$LOG" "$ANN"
    t0=$SECONDS
    # shellcheck disable=SC2086  # XRUN_FLAGS is deliberately word-split
    xrun "${flags[@]}" "$NET" "$MODEL" "$TB" -l "$LOG" ${XRUN_FLAGS:-} >"${LOG%.log}.console" 2>&1
    rc=$?; el=$((SECONDS - t0))
    echo "=== xrun exit code $rc (informational: the verdict is judged from the log); wall-clock time $((el/60)) min $((el%60)) s"
    judge_log "$LOG" "$mode" "$ANN"
    v=$?
    if [ "$v" -eq 2 ] && [ "$attempt" -lt "$retries" ]; then
      attempt=$((attempt+1))
      mv -f "$LOG" "${LOG%.log}.attempt${attempt}.log" 2>/dev/null; mv -f "${LOG%.log}.console" "${LOG%.log}.attempt${attempt}.console" 2>/dev/null
      echo "=== attempt $attempt of $((retries+1)) ended without a verdict (environment problem); its log is kept as ${LOG%.log}.attempt${attempt}.log; waiting $wait_s s, then trying again"
      sleep "$wait_s"
      continue
    fi
    break
  done
  if [ "$v" -eq 0 ]; then echo "=== ${JUDGE_CAVEAT:-PASS}: post-layout $corner $mode (wall-clock $((el/60)) min $((el%60)) s)"; return 0; fi
  if [ "$v" -eq 2 ]; then echo "=== ENVIRONMENT PROBLEM (exit 2), NOT a FAIL of the design: post-layout $corner $mode was not judged after $((attempt+1)) attempt(s) (log $LOG, console ${LOG%.log}.console); run the same command again when the licence server answers"; return 2; fi
  echo "=== FAIL: post-layout $corner $mode (log $LOG, console ${LOG%.log}.console, annotation log $ANN)"
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; exit $?; fi
