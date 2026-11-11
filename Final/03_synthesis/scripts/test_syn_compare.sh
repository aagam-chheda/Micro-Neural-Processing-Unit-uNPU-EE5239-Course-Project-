#!/usr/bin/env bash
# Test of scripts/syn_compare.sh (task 052). Builds sample run directories in a temporary folder from the text of the REAL round-3
# reports (docs/planning/synthesis-reports/round3-2026-10-14/, copied below) and checks the verdicts and the exit status.
#
#   bash scripts/test_syn_compare.sh
#
# ASSUMPTION: unpu_top.profile, .timing_top5, .qor, .check_timing, .check_design and the "# stage profile" header line have no real
# example yet. They are written here in the format the DC commands print (the round-3 timing text is a real report_timing; the
# top-5 file repeats its path). If the real layout differs, syn_compare.sh reports UNPARSED and this test is the place to fix it.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/syn_compare.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
npass=0; nfail=0
ok()   { npass=$((npass + 1)); echo "PASS: $1"; }
bad()  { nfail=$((nfail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

# ---- the real round-3 texts -------------------------------------------------------------------------------------
write_area() { cat <<'EOF_AREA'
 
****************************************
Report : area
Design : unpu_top
Version: T-2022.03-SP5
Date   : Wed Oct 14 21:54:02 2026
****************************************

Information: Updating design information... (UID-85)
Warning: Design 'unpu_top' contains 1 high-fanout nets. A fanout number of 1000 will be used for delay calculations involving these nets. (TIM-134)
Library(s) Used:

    tsl18fs120_scl_ss (File: /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db)

Number of ports:                         7452
Number of nets:                         21639
Number of cells:                        12614
Number of combinational cells:          10022
Number of sequential cells:              2465
Number of macros/black boxes:               0
Number of buf/inv:                       2005
Number of references:                      22

Combinational area:             251012.343238
Buf/Inv area:                    19857.169936
Noncombinational area:          178148.899307
Macro/Black Box area:                0.000000
Net Interconnect area:           13134.606586

Total cell area:                429161.242546
Total area:                     442295.849131
1
EOF_AREA
}
write_power() { cat <<'EOF_POWER'
Loading db file '/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db'
Information: Propagating switching activity (low effort zero delay simulation). (PWR-6)
Warning: Design has unannotated primary inputs. (PWR-414)
Warning: Design has unannotated sequential cell outputs. (PWR-415)
 
****************************************
Report : power
        -analysis_effort low
        -verbose
Design : unpu_top
Version: T-2022.03-SP5
Date   : Wed Oct 14 21:54:04 2026
****************************************


Library(s) Used:

    tsl18fs120_scl_ss (File: /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db)


Operating Conditions: tsl18fs120_scl_ss   Library: tsl18fs120_scl_ss
Wire Load Model Mode: top

Design        Wire Load Model            Library
------------------------------------------------
unpu_top               140000            tsl18fs120_scl_ss


Global Operating Voltage = 1.62 
Power-specific unit information :
    Voltage Units = 1V
    Capacitance Units = 1.000000pf
    Time Units = 1ns
    Dynamic Power Units = 1mW    (derived from V,C,T units)
    Leakage Power Units = 1pW


Attributes
----------
i - Including register clock pin internal power


  Cell Internal Power  =   6.0775 mW   (95%)
  Net Switching Power  = 327.2520 uW    (5%)
                         ---------
Total Dynamic Power    =   6.4048 mW  (100%)

Cell Leakage Power     =   5.5654 uW

                 Internal         Switching           Leakage            Total                         Cell
Power Group      Power            Power               Power              Power   (   %    )  Attrs  Count
---------------------------------------------------------------------------------------------------------
io_pad             0.0000            0.0000            0.0000            0.0000  (   0.00%)            0
memory             0.0000            0.0000            0.0000            0.0000  (   0.00%)            0
black_box          0.0000            0.0000            0.0000            0.0000  (   0.00%)            0
clock_network      6.0460            0.0000            0.0000            6.0460  (  94.32%)            0
                                                                                             i
register       1.1679e-02        2.4048e-04        2.0217e+06        1.3988e-02  (   0.22%)            2465
sequential         0.0000            0.0000            0.0000            0.0000  (   0.00%)            0
combinational  1.9731e-02            0.3270        3.5437e+06            0.3503  (   5.46%)            10022
---------------------------------------------------------------------------------------------------------
Total              6.0774 mW         0.3273 mW     5.5654e+06 pW         6.4103 mW
1
EOF_POWER
}
# the real worst-path report; the slack line is replaced by $SLACKLINE
write_timing_body() { cat <<'EOF_TIMING'
 
****************************************
Report : timing
        -path full
        -delay max
        -max_paths 1
Design : unpu_top
Version: T-2022.03-SP5
Date   : Wed Oct 14 21:54:04 2026
****************************************

 # A fanout number of 1000 was used for high fanout net computations.

Operating Conditions: tsl18fs120_scl_ss   Library: tsl18fs120_scl_ss
Wire Load Model Mode: top

  Startpoint: paddr[3] (input port clocked by clk)
  Endpoint: prdata[14] (output port clocked by clk)
  Path Group: clk
  Path Type: max

  Des/Clust/Port     Wire Load Model       Library
  ------------------------------------------------
  unpu_top           140000                tsl18fs120_scl_ss

  Point                                    Incr       Path
  -----------------------------------------------------------
  clock clk (rise edge)                    0.00       0.00
  clock network delay (ideal)              0.00       0.00
  input external delay                     7.00       7.00 r
  paddr[3] (in)                            1.07       8.07 r
  u_apb/paddr[3] (unpu_apb)                0.00       8.07 r
  u_apb/U29/Z (buffd1)                     0.24       8.31 r
  u_apb/csr_sel[1] (unpu_apb)              0.00       8.31 r
  U37/ZN (inv0d1)                          0.09       8.40 f
  U36/ZN (invbd2)                          0.15       8.55 r
  u_csr/csr_sel[1] (unpu_csr)              0.00       8.55 r
  u_csr/U20/ZN (inv0d1)                    0.20       8.75 f
  u_csr/U21/ZN (nr03d1)                    0.56       9.31 r
  u_csr/U13/Z (an02d2)                     0.48       9.79 r
  u_csr/U29/ZN (inv0d1)                    0.39      10.18 f
  u_csr/U396/ZN (oai222d1)                 0.41      10.59 r
  u_csr/csr_rdata[14] (unpu_csr)           0.00      10.59 r
  u_apb/csr_rdata[14] (unpu_apb)           0.00      10.59 r
  u_apb/U31/Z (buffd1)                     0.25      10.84 r
  u_apb/prdata[14] (unpu_apb)              0.00      10.84 r
  U51/Z (buffda)                           0.64      11.48 r
  prdata[14] (out)                         0.01      11.49 r
  data arrival time                                  11.49

  clock clk (rise edge)                   20.00      20.00
  clock network delay (ideal)              0.00      20.00
  clock uncertainty                       -1.50      18.50
  output external delay                   -7.00      11.50
  data required time                                 11.50
  -----------------------------------------------------------
  data required time                                 11.50
  data arrival time                                 -11.49
  -----------------------------------------------------------
  @@SLACKLINE@@


1
EOF_TIMING
}
write_violators() { cat <<'EOF_VIOL'
 
****************************************
Report : constraint
        -all_violators
Design : unpu_top
Version: T-2022.03-SP5
Date   : Wed Oct 14 21:54:40 2026
****************************************


   max_area

                             Required        Actual
   Design                      Area           Area           Slack
   -----------------------------------------------------------------
   unpu_top                     0.00       442295.84      -442295.84
                                                                    (VIOLATED)


1
EOF_VIOL
}

# ---- one sample run directory ------------------------------------------------------------------------------------
# make_run <base> <profile> <period> <worst-slack> [flops] [extra-violator] [dontuse-netlist-line] [latch-line]
make_run() {
  local base="$1" p="$2" T="$3" sl="$4" flops="${5:-2465}" extra="${6:-}" dnu="${7:-}" latch="${8:-}"
  local d="$base/$p"; mkdir -p "$d"
  local hdr="# stage profile $p: period $T ns, setup uncertainty 1.2 ns, hold uncertainty 0.05 ns; written Mon Nov  2 12:00:00 2026"
  echo "$hdr" > "$d/unpu_top.profile"
  local word="MET"; awk -v x="$sl" 'BEGIN { exit (x + 0 < 0) ? 0 : 1 }' && word="VIOLATED"
  local line; line="$(printf 'slack (%s)                                         %s' "$word" "$sl")"
  { echo "$hdr"; write_timing_body | sed "s/@@SLACKLINE@@/$line/"; } > "$d/unpu_top.timing"
  # top-5: the same real path five times, the worst one carries the slack under test, the others are comfortable
  { echo "$hdr"; for i in 1 2 3 4; do write_timing_body | sed "s/@@SLACKLINE@@/slack (MET)                                         1.8$i/"; done; write_timing_body | sed "s/@@SLACKLINE@@/$line/"; } > "$d/unpu_top.timing_top5"
  { echo "$hdr"; write_area | sed -E "s/^(Number of sequential cells:) +[0-9]+/\1 $flops/"; } > "$d/unpu_top.area"
  { echo "$hdr"; write_power; } > "$d/unpu_top.power"
  { echo "$hdr"; write_violators; if [ -n "$extra" ]; then printf '\n   %s\n\n                             Required        Actual\n   Design                      0.00           3.50           -0.50\n                                                                    (VIOLATED)\n' "$extra"; fi; } > "$d/unpu_top.constraint"
  { echo "$hdr"; echo "Information: Updating design information... (UID-85)"; echo " "; echo "Report : qor (stub of the QoR report, content not parsed)"; } > "$d/unpu_top.qor"
  { echo "$hdr"; echo "Information: Updating design information... (UID-85)"; } > "$d/unpu_top.check_timing"
  { echo "$hdr"; echo "Warning: In design 'unpu_top', port 'paddr[0]' is not connected to any nets. (LINT-28)"; echo "Warning: In design 'unpu_top', cell 'x' has constant 'B' bits. (LINT-32)"; echo "Warning: Design has input port(s) tied to 0. (LINT-33)"; } > "$d/unpu_top.check_design"
  [ -n "$latch" ] && echo "$latch" >> "$d/unpu_top.check_design"
  local net="module unpu_top (clk);
  input clk;
  buffd1 U1 ( .I(clk), .Z(n1) );
  dfnrq1 U2 ( .D(n1), .CP(clk), .Q(n2) );
$dnu
endmodule"
  echo "$net" > "$d/unpu_top.dc.v"; echo "$net" > "$d/unpu_top_cn.dc.v"
  echo "set_units -time ns" > "$d/unpu_top.sdc"; echo "set_units -time ns" > "$d/unpu_top_cn.sdc"; echo "ddc" > "$d/unpu_top_cn.ddc"
}
good_set() {  # good_set <base>: syn20 +0.01, syn18 +0.5, syn16 +0.2
  make_run "$1" syn20 20.0 0.01; make_run "$1" syn18 18.0 0.5; make_run "$1" syn16 16.0 0.2
}
run() {  # run <base> [profiles...] -> $OUT_TXT and $RC
  local base="$1"; shift
  OUT_TXT="$(SYN_OUT="$base" bash "$SCRIPT" "$@" 2>&1)"; RC=$?
}
has() { echo "$OUT_TXT" | grep -qF -- "$1"; }

# 1. a good set
B="$TMP/good"; good_set "$B"; run "$B"
[ "$RC" -eq 0 ] && ok "good set: exit 0" || bad "good set: exit $RC" "$(echo "$OUT_TXT" | tail -5)"
has "syn20: PASS" && ok "good set: syn20 PASS" || bad "good set: syn20 PASS"
has "syn18: MET" && has "syn16: MET" && ok "good set: syn18 and syn16 MET" || bad "good set: syn18/syn16 MET"
has "RECOMMENDATION: take the netlist of syn16" && ok "good set: the recommendation is syn16 (tightest that is met)" || bad "good set: recommendation" "$(echo "$OUT_TXT" | grep RECOMM)"
has "violated: max_area" && ok "good set: max_area is listed as the violator" || bad "good set: max_area listed"
has "flops 2465" && ok "good set: 2465 flops read" || bad "good set: flops"
has "dynamic 6.4048 mW, leakage 5.5654 uW" && ok "good set: power read from the real power report" || bad "good set: power"
has "total cell area 429161.242546" && ok "good set: total cell area read from the real area report" || bad "good set: area"
echo
echo "---- the comparison table of the good set (as printed) ----"
echo "$OUT_TXT" | sed -n '/== comparison/,/== verdicts/p' | sed '$d'
echo "-----------------------------------------------------------"

# 2. syn16 with a negative slack: NOT MET, never FAIL, recommendation syn18, exit 0
B="$TMP/s16neg"; good_set "$B"; make_run "$B" syn16 16.0 -0.35; run "$B"
[ "$RC" -eq 0 ] && ok "syn16 negative: exit 0 (syn20 passes)" || bad "syn16 negative: exit $RC"
has "syn16: NOT MET" && ok "syn16 negative: NOT MET" || bad "syn16 negative: NOT MET"
echo "$OUT_TXT" | grep -q "syn16: FAIL" && bad "syn16 negative: must never be FAIL" || ok "syn16 negative: never FAIL"
has "RECOMMENDATION: take the netlist of syn18" && ok "syn16 negative: recommendation falls back to syn18" || bad "syn16 negative: recommendation" "$(echo "$OUT_TXT" | grep RECOMM)"
has "reported paths with a negative slack (timing_top5): 1" && ok "syn16 negative: one reported path below 0 counted" || bad "syn16 negative: path count"

# 2b. syn16 and syn18 both negative: recommendation syn20
B="$TMP/both"; good_set "$B"; make_run "$B" syn16 16.0 -0.35; make_run "$B" syn18 18.0 -0.02; run "$B"
has "RECOMMENDATION: take the netlist of syn20" && ok "syn18 and syn16 negative: recommendation syn20" || bad "recommendation syn20" "$(echo "$OUT_TXT" | grep RECOMM)"

# 3. syn20 with a negative slack: FAIL, exit 1, no recommendation
B="$TMP/s20neg"; good_set "$B"; make_run "$B" syn20 20.0 -0.05; run "$B"
[ "$RC" -eq 1 ] && ok "syn20 negative: exit 1" || bad "syn20 negative: exit $RC"
has "syn20: FAIL" && ok "syn20 negative: FAIL" || bad "syn20 negative: FAIL"
has "RECOMMENDATION: none qualifies" && ok "syn20 negative: none qualifies" || bad "syn20 negative: recommendation"

# 4. a missing file: MISSING, exit 1
B="$TMP/missing"; good_set "$B"; rm "$B/syn18/unpu_top.timing_top5"; run "$B"
[ "$RC" -eq 1 ] && ok "missing file: exit 1" || bad "missing file: exit $RC"
has "MISSING: $B/syn18/unpu_top.timing_top5" && ok "missing file: named as MISSING" || bad "missing file: named"
has "syn18: UNKNOWN" && ok "missing file: syn18 verdict UNKNOWN (never MET)" || bad "missing file: verdict" "$(echo "$OUT_TXT" | grep 'syn18:')"
B="$TMP/missing20"; good_set "$B"; rm "$B/syn20/unpu_top.area"; run "$B"
[ "$RC" -eq 1 ] && has "syn20: FAIL" && ok "missing file of syn20: FAIL, exit 1" || bad "missing file of syn20"

# 5. a violator other than max_area: syn20 FAIL
B="$TMP/viol"; good_set "$B"; make_run "$B" syn20 20.0 0.01 2465 "max_transition"; run "$B"
[ "$RC" -eq 1 ] && has "syn20: FAIL" && has "other than max_area: max_transition" && ok "other violator: syn20 FAIL naming max_transition" || bad "other violator" "$(echo "$OUT_TXT" | grep 'syn20:')"
B="$TMP/viol2"; good_set "$B"; make_run "$B" syn20 20.0 0.01 2465 "max_delay/setup ('clk' group)"; run "$B"
has "max_delay/setup ('clk' group)" && has "syn20: FAIL" && ok "setup violator with a group name is parsed and fails syn20" || bad "setup violator parse" "$(echo "$OUT_TXT" | grep -E 'violated|syn20:')"

# 6. flops 2464: flagged, exit 1
B="$TMP/flops"; good_set "$B"; make_run "$B" syn18 18.0 0.5 2464; run "$B"
[ "$RC" -eq 1 ] && has "FLAG: flops = 2464, expected 2465" && ok "2464 flops: flagged, exit 1" || bad "2464 flops" "$RC"

# 7. a latch line, and a don't-use hit: syn20 FAIL
B="$TMP/latch"; good_set "$B"; make_run "$B" syn20 20.0 0.01 2465 "" "" "Warning: Latch inferred in design 'unpu_top' (HDL-1)"; run "$B"
has "syn20: FAIL" && has "latch line(s)" && ok "latch line: syn20 FAIL" || bad "latch line" "$(echo "$OUT_TXT" | grep -E 'syn20:|latch')"
B="$TMP/dnu"; good_set "$B"; make_run "$B" syn20 20.0 0.01 2465 "" "  slnht01d1 U9 ( .I(n1), .Z(n3) );"; run "$B"
has "HIT(slnht*)" && has "syn20: FAIL" && ok "don't-use instance: found and syn20 FAIL" || bad "don't-use hit" "$(echo "$OUT_TXT" | grep -E 'HIT|syn20:')"

# 8. a wrong-profile folder and an unreadable layout are reported, not skipped
B="$TMP/wrong"; good_set "$B"; sed -i '1s/syn16/syn18/' "$B/syn16/unpu_top.area"; run "$B"
has "WRONG PROFILE" && [ "$RC" -eq 1 ] && ok "a report with another profile's header: WRONG PROFILE, exit 1" || bad "wrong profile"
B="$TMP/unparsed"; good_set "$B"; sed -i '/Total cell area/d' "$B/syn18/unpu_top.area"; run "$B"
has "UNPARSED: 'Total cell area' not found" && [ "$RC" -eq 1 ] && ok "a missing field: UNPARSED, exit 1" || bad "unparsed field" "$(echo "$OUT_TXT" | grep -E 'UNPARSED')"
B="$TMP/nolog"; good_set "$B"; run "$B"
has "no dc.log in this folder" && ok "no dc.log: said, not silently OK" || bad "no dc.log message"
B="$TMP/log"; good_set "$B"; echo "Error: something (X-1)" > "$B/syn20/dc.log"; run "$B"
has "FLAG: Error: lines in dc.log" && [ "$RC" -eq 1 ] && ok "an Error: line in dc.log: flagged, exit 1" || bad "dc.log error"

# 9. only syn20 asked for, and a bad name
B="$TMP/only20"; good_set "$B"; run "$B" syn20
[ "$RC" -eq 0 ] && has "RECOMMENDATION: take the netlist of syn20" && ok "only syn20: exit 0, recommendation syn20" || bad "only syn20" "$RC"
run "$B" syn17; [ "$RC" -eq 2 ] && ok "unknown profile name: usage error, exit 2" || bad "unknown profile name: exit $RC"
B="$TMP/no20"; good_set "$B"; run "$B" syn18 syn16
[ "$RC" -eq 1 ] && has "RECOMMENDATION: none. syn20 was not asked for" && ok "syn20 not asked for: exit 1, no recommendation" || bad "syn20 not asked for" "$RC"

# 10. a MET tighter profile with another finding is INELIGIBLE for the recommendation (task 052 follow-up)
B="$TMP/inel_viol"; good_set "$B"; make_run "$B" syn16 16.0 0.2 2465 "max_transition"; run "$B"
has "syn16: MET" && has "syn16: MET on slack but INELIGIBLE" && has "max_transition" && has "RECOMMENDATION: take the netlist of syn18" && [ "$RC" -eq 0 ] \
  && ok "syn16 MET with a max_transition violator: ineligible, reason printed, recommendation syn18" || bad "ineligible violator" "$(echo "$OUT_TXT" | grep -E 'syn16:|RECOMM')"
B="$TMP/inel_latch"; good_set "$B"; make_run "$B" syn16 16.0 0.2 2465 "" "" "Warning: Latch inferred (HDL-1)"; run "$B"
has "syn16: MET on slack but INELIGIBLE" && has "latch line" && has "RECOMMENDATION: take the netlist of syn18" && ok "syn16 MET with a latch line: ineligible" || bad "ineligible latch" "$(echo "$OUT_TXT" | grep -E 'syn16:|RECOMM')"
B="$TMP/inel_dnu"; good_set "$B"; make_run "$B" syn16 16.0 0.2 2465 "" "  slnht01d1 U9 ( .I(n1), .Z(n3) );"; make_run "$B" syn18 18.0 0.5 2465 "" "  mx08d1 U8 ( .I(n1), .Z(n3) );"; run "$B"
has "syn16: MET on slack but INELIGIBLE" && has "syn18: MET on slack but INELIGIBLE" && has "RECOMMENDATION: take the netlist of syn20" && ok "both tighter profiles with a don't-use hit: ineligible, recommendation syn20" || bad "ineligible dnu" "$(echo "$OUT_TXT" | grep -E 'INELIG|RECOMM')"

echo
echo "test_syn_compare: $npass passed, $nfail failed"
[ "$nfail" -eq 0 ] || { echo "TESTS FAILED"; exit 1; }
echo "ALL TESTS PASSED"
