# =============================================================================
# test_common.tcl -- local tests of pnr/params.tcl and pnr/common.tcl (plain tclsh)
#
#   UNPU_TEST_TMP=<scratch dir> tclsh pnr/test_common.tcl
#
# Needs no Synopsys tool and no server file. Fixtures are made in a temporary directory
# (UNPU_TEST_TMP, else TMPDIR, else /tmp -- never inside the repo) and removed at the end.
# unpu_die exits, so every dying case runs in a child tclsh. Exit code 1 if any test FAILS.
# =============================================================================

set here [file dirname [file normalize [info script]]]
set tclsh [info nameofexecutable]

set tmp_base /tmp
if {[info exists ::env(TMPDIR)] && $::env(TMPDIR) ne ""} { set tmp_base $::env(TMPDIR) }
if {[info exists ::env(UNPU_TEST_TMP)] && $::env(UNPU_TEST_TMP) ne ""} { set tmp_base $::env(UNPU_TEST_TMP) }
set tmp [file join $tmp_base unpu_pnr_test_[pid]]
file mkdir $tmp

set npass 0
set nfail 0
proc t_check {name cond {detail ""}} {
  global npass nfail
  if {[string is true -strict $cond]} { incr npass; puts "PASS: $name" } \
  else { incr nfail; puts "FAIL: $name $detail" }
}
# ordered literal-substring match: parts separated by * must appear in this order (no glob/bracket surprises)
proc t_has {text pattern} {
  set pos 0
  foreach part [split $pattern *] {
    if {$part eq ""} continue
    set i [string first $part $text $pos]
    if {$i < 0} { return 0 }
    set pos [expr {$i + [string length $part]}]
  }
  return 1
}
# run a child tclsh on a script text with extra environment; returns {exit_code output}
proc t_child {script envlist} {
  global tclsh tmp
  set f [file join $tmp child_[incr ::t_n].tcl]
  set fh [open $f w]; puts $fh $script; close $fh
  array set save {}
  foreach {k v} $envlist { if {[info exists ::env($k)]} { set save($k) $::env($k) }; set ::env($k) $v }
  set code 0
  if {[catch {exec $tclsh $f 2>@1} out opts]} {
    set ec [lindex [dict get $opts -errorcode] 0]
    if {$ec eq "CHILDSTATUS"} { set code [lindex [dict get $opts -errorcode] 2] } else { set code -1 }
  }
  foreach {k v} $envlist { if {[info exists save($k)]} { set ::env($k) $save($k) } else { unset ::env($k) } }
  return [list $code $out]
}
set t_n 0

# ---- 1. defaults: sourcing params.tcl, derived floorplan values -----------------
foreach v {UNPU_DIE_SIZE UNPU_NDM_MODE UNPU_RUN_TAG UNPU_HOLD_UNCERT UNPU_NETLIST UNPU_SDC} { catch {unset ::env($v)} }
source [file join $here common.tcl]
set code [catch {source [file join $here params.tcl]} msg]
t_check "params.tcl sources under plain tclsh" [expr {$code == 0}] $msg
t_check "default core side 856.8" [expr {abs($CORE_SIDE - 856.8) < 1e-9}] "got $CORE_SIDE"
t_check "default rows 153" [expr {$FP_ROWS == 153}] "got $FP_ROWS"
t_check "default die/site 1550" [expr {$FP_SITES_ACROSS == 1550}] "got $FP_SITES_ACROSS"
t_check "default core area = side^2" [expr {abs($CORE_AREA - 734106.24) < 1e-6}] "got $CORE_AREA"
t_check "boundary is {{5.6 5.6} {862.4 862.4}}" [expr {$FP_BOUNDARY eq "{5.6 5.6} {862.4 862.4}"}] "got $FP_BOUNDARY"
t_check "REPO_ROOT is the parent of pnr/" [expr {$REPO_ROOT eq [file dirname $here]}] $REPO_ROOT
t_check "NDM_MODE default single" [expr {$NDM_MODE eq "single"}]
t_check "directory layout derived" [expr {$LOG_DIR eq "$UNPU_WORK/$UNPU_RUN_TAG/logs" && $NDM_DIR eq "$UNPU_WORK/ndm"}]
t_check "kit path uses 4M1IL for stdcell and 4M1L for pnr kit" \
    [expr {[string match */stdcell/fs120/4M1IL/lef/scl18fs120_std.lef $LEF_STD] && [string match */snps/non_rh/4M1L/SCL_4LM.tf $TECH_FILE]}]
t_check "UNPU_PARAM_NAMES is computed and holds the parameters" \
    [expr {[lsearch -exact $UNPU_PARAM_NAMES DIE_SIZE] >= 0 && [lsearch -exact $UNPU_PARAM_NAMES ANT_RATIO] >= 0 && [lsearch -exact $UNPU_PARAM_NAMES _p_before] < 0}]
t_check "DONT_USE_PATTERNS is the dc_setup.tcl list" [expr {$DONT_USE_PATTERNS eq "slnht* skbrb* slbhb* slnhn* slnln* mx08d*"}]

# ---- 2. other die sizes: old run accepted, 868.3 rejected, bad mode rejected -----
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs \"DIE=\$DIE_SIZE ROWS=\$FP_ROWS\"" {UNPU_DIE_SIZE 817.6}] c o
t_check "die 817.6 (the first run) passes: 144 rows" [expr {$c == 0 && [t_has $o "ROWS=144"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]" {UNPU_DIE_SIZE 868.3}] c o
t_check "die 868.3 is rejected with a message" [expr {$c == 1 && [t_has $o "Error: \[unpu\]*not an integer"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]" {UNPU_DIE_SIZE abc}] c o
t_check "die 'abc' is rejected" [expr {$c == 1 && [t_has $o "Error: \[unpu\]*DIE_SIZE"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]" {UNPU_NDM_MODE three}] c o
t_check "UNPU_NDM_MODE=three is rejected" [expr {$c == 1 && [t_has $o "Error: \[unpu\]*UNPU_NDM_MODE*single or two"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs MODE=\$NDM_MODE" {UNPU_NDM_MODE two}] c o
t_check "UNPU_NDM_MODE=two is accepted" [expr {$c == 0 && [t_has $o "MODE=two"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]" {UNPU_RUN_TAG a/b}] c o
t_check "UNPU_RUN_TAG with a slash is rejected" [expr {$c == 1}] "exit $c: $o"


# ---- 2b. item 5: hold uncertainty, core offset on the grid, boundary rounding, experiment warnings ----
set pre "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\n"
lassign [t_child "${pre}puts \"H=\$HOLD_UNCERT\"" {UNPU_HOLD_UNCERT -0.1}] c o
t_check "UNPU_HOLD_UNCERT=-0.1 is rejected" [expr {$c == 1 && [t_has $o "Error: \[unpu\]*HOLD_UNCERT*>= 0"]}] "exit $c: $o"
lassign [t_child "$pre" {UNPU_HOLD_UNCERT abc}] c o
t_check "UNPU_HOLD_UNCERT=abc is rejected" [expr {$c == 1 && [t_has $o "HOLD_UNCERT='abc'"]}] "exit $c: $o"
lassign [t_child "${pre}puts \"H=\$HOLD_UNCERT\"" {UNPU_HOLD_UNCERT 0.2}] c o
t_check "UNPU_HOLD_UNCERT=0.2 is accepted and a Warning marks the experiment" [expr {$c == 0 && [t_has $o "H=0.2"] && [t_has $o "Warning: \[unpu\] HOLD_UNCERT = 0.2 differs from the plan default 0.5"]}] "exit $c: $o"
lassign [t_child "$pre" {UNPU_DIE_SIZE 817.6}] c o
t_check "UNPU_DIE_SIZE=817.6 prints the experiment Warning" [expr {$c == 0 && [t_has $o "Warning: \[unpu\] DIE_SIZE = 817.6 differs from the plan default 868.0"]}] "exit $c: $o"
lassign [t_child "$pre" {}] c o
t_check "no experiment Warning with the defaults" [expr {$c == 0 && [string first "differs from the plan default" $o] < 0}] "exit $c: $o"
lassign [t_child "${pre}puts \[unpu_floorplan_check 868.0 2.8 5.6 0.56 1e-6\]" {}] c o
t_check "core offset that is not a whole number of rows is rejected" [expr {$c == 1 && [t_has $o "CORE_OFFSET / ROW_HEIGHT"]}] "exit $c: $o"
lassign [t_child "${pre}puts \[unpu_floorplan_check 105.0 5.0 5.0 0.6 1e-6\]" {}] c o
t_check "core offset that is not a whole number of sites is rejected" [expr {$c == 1 && [t_has $o "CORE_OFFSET / SITE_WIDTH"]}] "exit $c: $o"
t_check "unpu_floorplan_check accepts the plan numbers" [expr {[unpu_floorplan_check 868.0 5.6 5.6 0.56 1e-6] eq "856.8 153 1550 734106.24"}] [unpu_floorplan_check 868.0 5.6 5.6 0.56 1e-6]
t_check "unpu_round4 removes a floating-point tail" [expr {[unpu_round4 0.30000000000000004] eq "0.3" && [unpu_round4 [expr {817.6 - 5.6}]] eq "812.0"}] "[unpu_round4 0.30000000000000004] [unpu_round4 [expr {817.6 - 5.6}]]"
lassign [t_child "${pre}puts \"B=\$FP_BOUNDARY\"" {UNPU_DIE_SIZE 817.6}] c o
t_check "boundary for die 817.6 carries no floating-point tail" [expr {$c == 0 && [t_has $o "B={5.6 5.6} {812.0 812.0}"]}] "exit $c: $o"

# ---- item 6: exact block-name matching ----------------------------------------
t_check "block match: lib:name.design" [unpu_block_name_matches unpu2_lib:placed.design placed]
t_check "block match: lib:name" [unpu_block_name_matches unpu2_lib:placed placed]
t_check "block match: bare name" [unpu_block_name_matches placed placed]
t_check "block match rejects a longer name (placed2)" [expr {![unpu_block_name_matches unpu2_lib:placed2.design placed]}]
t_check "block match rejects a prefix-extended name (xplaced)" [expr {![unpu_block_name_matches unpu2_lib:xplaced placed]}]
t_check "block match rejects a name followed by more text (.design.bak)" [expr {![unpu_block_name_matches unpu2_lib:placed.design.bak placed]}]
t_check "block match rejects an empty current block" [expr {![unpu_block_name_matches "" placed]}]
t_check "block match: fp is not matched by fp_old" [expr {![unpu_block_name_matches lib:fp_old.design fp]}]

# ---- item 8: a failing command prints what it had printed ----------------------
lassign [t_child "source [list [file join $here common.tcl]]\nproc redirect {args} { set ::UNPU_CAP \"PARTIAL-OUTPUT-LINE\\n\"; error boom }\nunpu_run_logged {fake_cmd} {}\nputs NOT_REACHED" {}] c o
t_check "failed command: captured text is printed before the Error" [expr {$c == 1 && [t_has $o "PARTIAL-OUTPUT-LINE*Error: \[unpu\] command failed: fake_cmd"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nproc redirect {args} { set ::UNPU_CAP \"Workspace check succeeded!\\n\" }\nunpu_run_logged {fake_cmd} {}\nputs \"OK=\$UNPU_CAP_OK\"" {}] c o
t_check "capture flag is set when redirect works" [expr {$c == 0 && [t_has $o "OK=1"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nproc fake_cmd {} {}\nunpu_run_logged {fake_cmd} {}\nputs \"OK=\$UNPU_CAP_OK\"" {}] c o
t_check "no capture flag and a Warning when redirect is unavailable" [expr {$c == 0 && [t_has $o "OK=0"] && [t_has $o "Warning: \[unpu\] redirect is not available"]}] "exit $c: $o"

# ---- task 039: shared helpers and new parameters ---------------------------------
t_check "new parameters present with the handoff values" [expr {$EXPECT_LEAF_CELLS == 12487 && $SCEN_SETUP eq "default" && $SCEN_HOLD eq "ff_hold" && $CORNER_SETUP eq "default" && $CORNER_HOLD eq "ff" && $MODE_NAME eq "default" && $PARA_TECH_NAME eq "typ" && $EXPECT_SDC_IGNORED eq "SDC-3 SDC-4" && $EXPECT_CHECK_TIMING_WARNINGS == 1 && $EXPECT_SS_VOLT == 1.62 && $EXPECT_SS_TEMP == 125 && $EXPECT_FF_VOLT == 1.98 && $EXPECT_FF_TEMP == -40}]
t_check "new parameters are in the computed manifest list" [expr {[lsearch -exact $UNPU_PARAM_NAMES EXPECT_LEAF_CELLS] >= 0 && [lsearch -exact $UNPU_PARAM_NAMES SCEN_HOLD] >= 0 && [lsearch -exact $UNPU_PARAM_NAMES EXPECT_FF_TEMP] >= 0}]

# unpu_read_ndm_manifest
set n1 [file join $tmp ndm_a.ndm]; set n2 [file join $tmp ndm_b.ndm]; file mkdir $n1 $n2
set mgood [file join $tmp man_good.txt]; set fh [open $mgood w]; puts $fh "$n1\n\n$n2\n"; close $fh
t_check "unpu_read_ndm_manifest returns the listed NDMs in order" [expr {[unpu_read_ndm_manifest $mgood] eq [list $n1 $n2]}]
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_read_ndm_manifest [list [file join $tmp nosuch_manifest.txt]]" {}] c o
t_check "manifest reader: missing file dies" [expr {$c == 1 && [t_has $o "NDM manifest*not found"]}] "exit $c: $o"
set mempty [file join $tmp man_empty.txt]; set fh [open $mempty w]; puts $fh "\n  \n"; close $fh
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_read_ndm_manifest [list $mempty]" {}] c o
t_check "manifest reader: empty file dies" [expr {$c == 1 && [t_has $o "lists no NDM"]}] "exit $c: $o"
set mbad [file join $tmp man_bad.txt]; set fh [open $mbad w]; puts $fh "$n1\n[file join $tmp gone.ndm]"; close $fh
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_read_ndm_manifest [list $mbad]" {}] c o
t_check "manifest reader: a listed NDM that does not exist dies" [expr {$c == 1 && [t_has $o "does not exist*gone.ndm"]}] "exit $c: $o"

# message ids
set sdc_txt "Info: loaded SDC 2.1\nWarning: SDC-3: set_wire_load_model not supported by icc2\nWarning: SDC-4: set_max_area not supported\nWarning: UIC-034: Redefining clock 'clk'\nWarning: TLUP-011: layer ignored\nWarning: SDC-3: again"
t_check "message ids: SDC only, sorted, unique" [expr {[unpu_message_ids $sdc_txt SDC] eq "SDC-3 SDC-4"}] [unpu_message_ids $sdc_txt SDC]
t_check "message ids: any prefix" [expr {[unpu_message_ids $sdc_txt] eq "SDC-3 SDC-4 TLUP-011 UIC-034"}] [unpu_message_ids $sdc_txt]
t_check "message ids: 'SDC 2.1' is not an id" [expr {[unpu_message_ids "loaded as SDC 2.1" SDC] eq ""}]
t_check "lines matching an SDC id" [expr {[llength [unpu_lines_matching $sdc_txt {SDC-[0-9]+}]] == 3}]
t_check "unexpected ids: none when equal" [expr {[unpu_ids_unexpected {SDC-3 SDC-4} {SDC-3 SDC-4}] eq ""}]
t_check "unexpected ids: an extra id is named" [expr {[unpu_ids_unexpected {SDC-3 SDC-4 SDC-9} {SDC-3 SDC-4}] eq "SDC-9"}]
t_check "unexpected ids: fewer than expected is not unexpected" [expr {[unpu_ids_unexpected {SDC-3} {SDC-3 SDC-4}] eq ""}]

# link_block output
set link_ok "Information: Linking design 'unpu_top'\nDesign 'unpu_top' was successfully linked.\nInformation: 0 unresolved cells"
set link_bad "Linking design 'unpu_top'\nWarning: Unable to resolve reference 'foo' in 'unpu_top'.\nError: unresolved references remain\nDesign 'unpu_top' was not linked."
t_check "text with the success phrase" [unpu_text_has $link_ok "successfully linked"]
t_check "text without the success phrase" [expr {![unpu_text_has $link_bad "successfully linked"]}]
t_check "zero-count 'unresolved' wording is not a problem" [expr {[unpu_unresolved_lines $link_ok] eq ""}] [unpu_unresolved_lines $link_ok]
t_check "unresolved references are found (both wordings)" [expr {[llength [unpu_unresolved_lines $link_bad]] == 2}] [unpu_unresolved_lines $link_bad]

# report_ref_libs
set rrl "Library        Status\n  scl18fs120_fillf   open, has technology information\n  scl18fs120    (open, has technology information)\n  other  not open"
t_check "reflib open: scl18fs120 listed and open" [unpu_reflib_open $rrl scl18fs120]
t_check "reflib open: scl18fs120_fillf listed and open" [unpu_reflib_open $rrl scl18fs120_fillf]
t_check "reflib open: 'other' is not open" [expr {![unpu_reflib_open $rrl other]}]
t_check "reflib open: scl18fs120 is not confused with scl18fs120_fillf" [expr {![unpu_reflib_open "  scl18fs120_fillf   open" scl18fs120]}]
t_check "reflib open: a library that is absent" [expr {![unpu_reflib_open $rrl nosuchlib]}]

# report_corners, two layouts
set rc_table "Corner   Process Voltage Temperature OpCond\ndefault  1.2     1.62    125         tsl18fs120_scl_ss\nff       0.8     1.98    -40         tsl18fs120_scl_ff"
set rc_block "Corner default:\n  Operating condition: tsl18fs120_scl_ss\n  Process: 1.2\n  Voltage: 1.62\n  Temperature: 125.00\nCorner ff:\n  Operating condition: tsl18fs120_scl_ff\n  Process: 0.8\n  Voltage: 1.98\n  Temperature: -40.00"
foreach {lay txt} [list table $rc_table block $rc_block] {
  t_check "corners ($lay layout): ss corner has 1.62 V / 125 C" [expr {[lindex [unpu_corner_has_point $txt default {ff} 1.62 125] 0] eq "ok"}] [unpu_corner_has_point $txt default {ff} 1.62 125]
  t_check "corners ($lay layout): ff corner has 1.98 V / -40 C" [expr {[lindex [unpu_corner_has_point $txt ff {default} 1.98 -40] 0] eq "ok"}] [unpu_corner_has_point $txt ff {default} 1.98 -40]
}
set rc_wrong [string map {1.62 1.8} $rc_table]
t_check "corners: 1.8 V at the first corner fails" [expr {[lindex [unpu_corner_has_point $rc_wrong default {ff} 1.62 125] 0] eq "fail" && [t_has [lindex [unpu_corner_has_point $rc_wrong default {ff} 1.62 125] 1] "1.62 V not found"]}] [unpu_corner_has_point $rc_wrong default {ff} 1.62 125]
t_check "corners: ff corner not touched by an ss error" [expr {[lindex [unpu_corner_has_point $rc_wrong ff {default} 1.98 -40] 0] eq "ok"}]
set rc_swapped "Corner   Process Voltage Temperature\ndefault  0.8     1.98    -40\nff       1.2     1.62    125"
t_check "corners: swapped corners fail" [expr {[lindex [unpu_corner_has_point $rc_swapped default {ff} 1.62 125] 0] eq "fail"}]
t_check "corners: temperature 40 is not -40" [expr {[lindex [unpu_corner_has_point "ff 0.8 1.98 40" ff {default} 1.98 -40] 0] eq "fail"}]
t_check "corners: a corner that is not in the text is reported" [expr {[lindex [unpu_corner_has_point $rc_table nosuch {ff} 1.62 125] 0] eq "fail" && [t_has [lindex [unpu_corner_has_point $rc_table nosuch {ff} 1.62 125] 1] "not found in the report"]}]

t_check "corners: digits inside names (tsl18fs120_scl_ss) are not numbers" [expr {[lindex [unpu_corner_has_point "default 1.2 1.8 tsl18fs120_scl_ss 125" default {} 1.62 120] 0] eq "fail"}] [unpu_corner_has_point "default 1.2 1.8 tsl18fs120_scl_ss 125" default {} 1.62 120]
t_check "corners: values with unit letters (1.62V, 125C) are read" [expr {[lindex [unpu_corner_has_point "Corner default: 1.62V / 125C" default {} 1.62 125] 0] eq "ok"}]
t_check "unresolved: 'Unable to resolve reference' is found" [expr {[llength [unpu_unresolved_lines "Warning: Unable to resolve reference 'foo' in 'unpu_top'."]] == 1}]
t_check "corner name with a dot is matched literally" [expr {[lindex [unpu_corner_has_point "ff.1 1.98 -40\nffx1 9 9" ff.1 {} 1.98 -40] 0] eq "ok" && [lindex [unpu_corner_has_point "ffx1 1.98 -40" ff.1 {} 1.98 -40] 0] eq "fail"}]
t_check "reflib name with a dot is matched literally" [expr {[unpu_reflib_open "lib.v1 open" lib.v1] && ![unpu_reflib_open "libxv1 open" lib.v1]}]

# check_timing and slack parsing
set ct1 "Information: Checking unconstrained_endpoints...\nWarning: There is 1 unconstrained port 'pready' (case constant)\n"
set ct2 "Warning: a\nwarning: b\n  Warning: c\nInformation: d"
t_check "check_timing: one warning line" [expr {[llength [unpu_warning_lines $ct1]] == 1}]
t_check "check_timing: three warning lines (case-insensitive)" [expr {[llength [unpu_warning_lines $ct2]] == 3}]
t_check "slack parse: MET value" [expr {[unpu_parse_slack "  slack (MET)                 0.82\n"] eq "0.82"}]
t_check "slack parse: VIOLATED value" [expr {[unpu_parse_slack "  slack (VIOLATED)           -0.50\n"] eq "-0.50"}]
t_check "slack parse: nothing found" [expr {[unpu_parse_slack "no paths"] eq ""}]

# ---- task 040: floorplan parsers and parameters ---------------------------------
t_check "parameters: EXPECT_DONT_USE_COUNT 18, EXPECT_DONT_USE_MATCHED 15, SITE_NAME unit, mx08d* may be empty" [expr {$EXPECT_DONT_USE_COUNT == 18 && $EXPECT_DONT_USE_MATCHED == 15 && $SITE_NAME eq "unit" && $DONT_USE_EXPECT_EMPTY eq "mx08d*" && $EXPECT_DONT_USE_COUNT == $EXPECT_DONT_USE_MATCHED + [llength $LIB_DONT_USE_CELLS]}]
t_check "no EXPECT_CHIP_AREA parameter (derived from DIE_SIZE)" [expr {![info exists EXPECT_CHIP_AREA]}]
t_check "bbox parse: attribute form" [expr {[unpu_parse_bbox "{0.0 0.0} {868.0 868.0}"] eq "0.0 0.0 868.0 868.0"}]
t_check "bbox parse: three numbers is not a bbox" [expr {[unpu_parse_bbox "{0 0} {868.0}"] eq ""}]
t_check "bbox parse: junk" [expr {[unpu_parse_bbox "none"] eq ""}]
set fa1 "Report : design\n  Chip area:                668,469.76 um2\n  Number of rows:           144\n  Core area:                650280.96\n  Core utilization:         66.00%"
set fa2 "Floorplan summary\n  Chip area (um^2)   = 753424.00\n  Core area (um^2)   = 734,106.24\n  Core Utilization = 58.46 %"
set fa3 "Chip area\n   668469.76\nCore area\n   650280.96\n"
lassign [unpu_parse_floorplan_areas $fa1] st chip core util d
t_check "floorplan areas, layout 1 (first run numbers 668,469.76 / 650,280.96 / 66.00%)" [expr {$st eq "ok" && $chip == 668469.76 && $core == 650280.96 && $util == 66.00}] "$st $chip $core $util"
lassign [unpu_parse_floorplan_areas $fa2] st chip core util d
t_check "floorplan areas, layout 2 (plan numbers 753,424 / 734,106.24 / 58.46%)" [expr {$st eq "ok" && $chip == 753424.0 && $core == 734106.24 && $util == 58.46}] "$st $chip $core $util"
lassign [unpu_parse_floorplan_areas $fa3] st chip core util d
t_check "floorplan areas, value on the next line, no utilization" [expr {$st eq "ok" && $chip == 668469.76 && $core == 650280.96 && $util eq ""}] "$st $chip $core '$util'"
set fa4 "Chip area: 753424.00\nCore area utilization: 58.46%\nCore area: 734106.24"
lassign [unpu_parse_floorplan_areas $fa4] st chip core util d
t_check "floorplan areas: 'core area utilization' is not taken as the core area" [expr {$st eq "ok" && $core == 734106.24 && $util == 58.46}] "$st $core $util"
t_check "floorplan areas: absent numbers fail and quote the text" [expr {[lindex [unpu_parse_floorplan_areas "Report : design\nNumber of rows: 153\nno areas here"] 0] eq "fail" && [t_has [lindex [unpu_parse_floorplan_areas "Report : design\nNumber of rows: 153\nno areas here"] 1] "chip area and core area*Text seen*Number of rows"]}]
t_check "floorplan areas: only the chip area present fails naming the core area" [expr {[lindex [unpu_parse_floorplan_areas "Chip area: 1.0"] 0] eq "fail" && [t_has [lindex [unpu_parse_floorplan_areas "Chip area: 1.0"] 1] "core area"]}]
t_check "floorplan areas: empty text fails" [expr {[lindex [unpu_parse_floorplan_areas ""] 0] eq "fail"}]
# wrong numbers parse fine (the script compares them): the 828.8 mistake of the first attempt
lassign [unpu_parse_floorplan_areas "Chip area: 686,909.44\nCore area: 650280.96"] st chip core util d
t_check "floorplan areas: the 18.14 mistake (686,909.44) parses and differs from 817.6^2" [expr {$st eq "ok" && abs($chip - 817.6*817.6) > 1}] "$st $chip"
t_check "first number: commas, percent, units" [expr {[unpu_first_number " = 1,234.50 um2"] eq "1234.50" && [unpu_first_number ": 66.00%"] eq "66.00" && [unpu_first_number "um^2 only"] eq ""}]

# ---- task 041: power helpers ----------------------------------------------------------
t_check "power parameters present" [expr {$PG_NET_POWER eq "VDD" && $PG_NET_GROUND eq "VSS" && $PG_PATTERN_RAIL eq "std_rail" && $PG_PATTERN_MESH eq "top_mesh" && $PG_STRAT_RAIL eq "s_rail" && $PG_STRAT_MESH eq "s_mesh" && $PG_SPACING eq "interleaving" && $PG_PIN_BOTTOM_Y == 0 && $PG_TOLERANCE > 0}]
set pgc [unpu_pg_commands $PG_PATTERN_RAIL $PG_PATTERN_MESH $PG_STRAT_RAIL $PG_STRAT_MESH $PG_RAIL_LAYER $PG_RAIL_WIDTH $PG_STRIPE_LAYER $PG_STRIPE_WIDTH $PG_STRIPE_PITCH $PG_SPACING $PG_NET_POWER $PG_NET_GROUND]
t_check "pg command 1 = handoff 18.15 (std cell rail pattern)" [expr {[lindex $pgc 0] eq {create_pg_std_cell_conn_pattern std_rail -layers M1 -rail_width 0.74}}] [lindex $pgc 0]
t_check "pg command 2 = handoff 18.15 (mesh pattern)" [expr {[lindex [lindex $pgc 1] 0] eq "create_pg_mesh_pattern" && [lindex [lindex $pgc 1] 1] eq "top_mesh" && [lindex [lindex $pgc 1] 2] eq "-layers" && [lindex [lindex $pgc 1] 3] eq {{{vertical_layer: TOP_M} {width: 2.24} {pitch: 112} {spacing: interleaving}}}}] [lindex $pgc 1]
t_check "pg command 2 value: a list of ONE layer item that holds four fields" [expr {[llength [lindex [lindex $pgc 1] 3]] == 1 && [llength [lindex [lindex [lindex $pgc 1] 3] 0]] == 4}]
t_check "pg commands 3 and 4 = handoff 18.15 (strategies)" [expr {[lindex $pgc 2] eq {set_pg_strategy s_rail -core -pattern {{name: std_rail} {nets: {VDD VSS}}}} && [lindex $pgc 3] eq {set_pg_strategy s_mesh -core -pattern {{name: top_mesh} {nets: {VDD VSS}}}}}] "[lindex $pgc 2] | [lindex $pgc 3]"
t_check "pg command 5 = compile_pg -strategies {s_rail s_mesh}" [expr {[lindex $pgc 4] eq {compile_pg -strategies {s_rail s_mesh}}}] [lindex $pgc 4]
t_check "pg commands follow the parameters (width 3.0 changes command 2)" [expr {[string first "width: 3.0" [lindex $pgc 1]] < 0 && [string first "width: 3.0" [lindex [unpu_pg_commands a b c d M1 0.74 TOP_M 3.0 112 interleaving VDD VSS] 1]] > 0}]
t_check "int tokens: commas" [expr {[unpu_int_token 12,487] == 12487 && [unpu_int_token 1.5] eq "" && [unpu_int_token abc] eq ""}]
t_check "ints in a line" [expr {[unpu_ints_in "VDD: 12,487 pins, 3 nets"] eq "12487 3"}] [unpu_ints_in "VDD: 12,487 pins, 3 nets"]
# connect_pg_net
set cp1 "Information: Connecting power and ground nets\n P/G pin count\n   Net    Pins\n   VDD    12,487\n   VSS    12,487\n"
set cp2 "Connected 12487 pins to net VDD (tie 0)\nConnected 12487 pins to net VSS (tie 0)\n"
set cp3 "Connecting done.\n  VDD connected\n"
t_check "connect_pg_net, table layout" [expr {[unpu_parse_connect_pg $cp1 {VDD VSS}] eq "VDD 12487 VSS 12487"}] [unpu_parse_connect_pg $cp1 {VDD VSS}]
t_check "connect_pg_net, sentence layout" [expr {[unpu_parse_connect_pg $cp2 {VDD VSS}] eq "VDD 12487 VSS 12487"}] [unpu_parse_connect_pg $cp2 {VDD VSS}]
t_check "connect_pg_net, a net without a number: not parsed" [expr {[unpu_parse_connect_pg $cp3 {VDD VSS}] eq "not parsed"}]
t_check "connect_pg_net, empty text: not parsed" [expr {[unpu_parse_connect_pg "" {VDD VSS}] eq "not parsed"}]
t_check "connect_pg_net, different counts are returned as they are" [expr {[unpu_parse_connect_pg "VDD 12000\nVSS 12487" {VDD VSS}] eq "VDD 12000 VSS 12487"}]
# check_pg_drc
t_check "pg_drc: 'No errors found'" [expr {[unpu_parse_pg_drc "Running check_pg_drc ...\nNo errors found.\n"] == 0}]
t_check "pg_drc: 'Total errors: 0'" [expr {[unpu_parse_pg_drc "Total errors: 0"] == 0}]
t_check "pg_drc: 'Found 3 DRC errors'" [expr {[unpu_parse_pg_drc "Found 3 DRC errors"] == 3}]
t_check "pg_drc: '0 violations'" [expr {[unpu_parse_pg_drc "check_pg_drc: 0 violations"] == 0}]
t_check "pg_drc: unrecognised text is not parsed" [expr {[unpu_parse_pg_drc "Done.\nSee the report."] eq "not parsed"}]
# check_pg_connectivity
set pc1 "Number of floating wires: 0\nNumber of floating vias: 0\nNumber of floating terminals: 0\nNumber of floating standard cells: 12487"
set pc2 "No floating wires.\nNo floating vias\nfloating terminals = 0\nFloating cells: VDD 12,487 VSS 12,487"
set pc3 "Number of floating wires: 2\nNumber of floating vias: 0"
array set a1 [unpu_parse_pg_connectivity $pc1]
t_check "pg_connectivity, numbered layout" [expr {$a1(wires) == 0 && $a1(vias) == 0 && $a1(terminals) == 0 && $a1(cells) == 12487}] [array get a1]
array set a2 [unpu_parse_pg_connectivity $pc2]
t_check "pg_connectivity, 'No floating ...' layout and per-net cells" [expr {$a2(wires) == 0 && $a2(vias) == 0 && $a2(terminals) == 0 && $a2(cells) == 12487}] [array get a2]
array set a3 [unpu_parse_pg_connectivity $pc3]
t_check "pg_connectivity: floating wires counted, absent categories absent" [expr {$a3(wires) == 2 && ![info exists a3(terminals)] && ![info exists a3(cells)]}] [array get a3]
# terminal boxes against stripe boxes (18.21 numbers: VSS at 60.48, VDD at 116.48, width 2.24)
set st {{VSS 60.48 5.6 62.72 812.0} {VDD 116.48 5.6 118.72 812.0} {VSS 172.48 5.6 174.72 812.0}}
set tm {{VSS 60.48 0.0 62.72 6.0} {VDD 116.48 0.0 118.72 6.0} {VSS 172.48 0.0 174.72 6.0}}
set r [unpu_terminals_vs_stripes $tm $st 817.6 0.0 0.001]
t_check "terminals vs stripes: all good" [expr {[join $r ""] eq ""}] $r
set tm_dup [concat $tm [list {VSS 60.48 0.0 62.72 6.0}]]
set r [unpu_terminals_vs_stripes $tm_dup $st 817.6 0.0 0.001]
t_check "terminals vs stripes: the 18.21 duplicate (VSS 8 terminals for 7 stripes) is found by count and duplicate" [expr {[llength [lindex $r 0]] == 1 && [llength [lindex $r 2]] == 1 && [t_has [lindex [lindex $r 0] 0] "net VSS: 3 terminal(s) for 2 stripe(s)"]}] $r
set r [unpu_terminals_vs_stripes [lrange $tm 0 1] $st 817.6 0.0 0.001]
t_check "terminals vs stripes: a missing terminal is found by count and x range" [expr {[llength [lindex $r 0]] == 1 && [llength [lindex $r 1]] == 1 && [t_has [lindex [lindex $r 1] 0] "172.48"]}] $r
set tm_x [lreplace $tm 1 1 {VDD 116.50 0.0 118.74 6.0}]
set r [unpu_terminals_vs_stripes $tm_x $st 817.6 0.0 0.001]
t_check "terminals vs stripes: a wrong x range is found" [expr {[llength [lindex $r 1]] == 1 && [t_has [lindex [lindex $r 1] 0] "116.48"]}] $r
set tm_y [lreplace $tm 2 2 {VSS 172.48 0.5 174.72 6.0}]
set r [unpu_terminals_vs_stripes $tm_y $st 817.6 0.0 0.001]
t_check "terminals vs stripes: a terminal not starting at y = 0 is found" [expr {[llength [lindex $r 3]] == 1}] $r
set tm_o [lreplace $tm 0 0 {VSS 60.48 -1.0 62.72 6.0}]
set r [unpu_terminals_vs_stripes $tm_o $st 817.6 0.0 0.001]
t_check "terminals vs stripes: a terminal outside the die is found" [expr {[llength [lindex $r 4]] == 1 && [llength [lindex $r 3]] == 1}] $r
set tm_net [lreplace $tm 0 0 {VDD 60.48 0.0 62.72 6.0}]
set r [unpu_terminals_vs_stripes $tm_net $st 817.6 0.0 0.001]
t_check "terminals vs stripes: a terminal on the wrong net is found" [expr {[llength [lindex $r 0]] >= 1 && [llength [lindex $r 1]] >= 1}] $r
t_check "box entry: rounds to 4 decimals" [expr {[unpu_box_entry VSS "{60.48000001 0.0} {62.72 6.0}"] eq "VSS 60.48 0.0 62.72 6.0"}] [unpu_box_entry VSS "{60.48000001 0.0} {62.72 6.0}"]
t_check "box entry: not four numbers gives empty" [expr {[unpu_box_entry VSS "{1 2} {3}"] eq ""}]

# ---- task 042: command-usage probe helpers ----------------------------------------------
set usage_txt "Usage: place_pins   \[-self\]\n                  \[-ports port_list\]\n   -self (Boolean)\n"
set err_txt "Error: unknown command 'frobnicate_all' (CMD-005)\n"
set wild_txt "place_pins\nset_block_pin_constraints\nset_individual_pin_constraints\nreport_pin_placement\n"
t_check "classify: a usage text is FOUND" [expr {[lindex [unpu_classify_help $usage_txt] 0] eq "FOUND"}]
t_check "classify: a help *pin* listing is FOUND" [expr {[lindex [unpu_classify_help $wild_txt] 0] eq "FOUND"}]
t_check "classify: empty text is NOT_FOUND" [expr {[lindex [unpu_classify_help ""] 0] eq "NOT_FOUND" && [lindex [unpu_classify_help "  \n"] 0] eq "NOT_FOUND"}]
t_check "classify: 'Error: unknown command' is NOT_FOUND" [expr {[lindex [unpu_classify_help $err_txt] 0] eq "NOT_FOUND"}]
t_check "classify: 'Error: no commands match' is NOT_FOUND" [expr {[lindex [unpu_classify_help "Error: no commands match 'zz*' (CMD-010)"] 0] eq "NOT_FOUND"}]
t_check "classify: 'no app options match' is NOT_FOUND" [expr {[lindex [unpu_classify_help "Error: no app options match 'zz.*'"] 0] eq "NOT_FOUND"}]
t_check "classify: another Error line is ERROR" [expr {[lindex [unpu_classify_help "Error: license checkout failed (LIC-1)\n"] 0] eq "ERROR"}]
t_check "classify: usage text plus a Tcl error is still FOUND" [expr {[lindex [unpu_classify_help $usage_txt "extra"] 0] eq "FOUND"}]
t_check "classify: empty text and 'invalid command name' is NOT_FOUND" [expr {[lindex [unpu_classify_help "" {invalid command name "foo"}] 0] eq "NOT_FOUND"}]
t_check "classify: empty text and another Tcl error is ERROR with the message" [expr {[lindex [unpu_classify_help "" "wrong # args: should be x"] 0] eq "ERROR" && [t_has [lindex [unpu_classify_help "" "wrong # args: should be x"] 1] "wrong # args"]}]
t_check "classify: the detail of NOT_FOUND quotes the first line" [expr {[t_has [lindex [unpu_classify_help $err_txt] 1] "unknown command 'frobnicate_all'"]}]
t_check "file name: * becomes X" [expr {[unpu_probe_filename *pin*] eq "XpinX" && [unpu_probe_filename *write_*] eq "Xwrite_X"}]
t_check "file name: dots kept, other characters replaced" [expr {[unpu_probe_filename place.*] eq "place.X" && [unpu_probe_filename "a/b c?"] eq "a_b_c_" && [unpu_probe_filename route.detail.*] eq "route.detail.X"}]
proc pn_files {l} { set o {}; foreach p $l { lappend o [unpu_probe_filename $p] }; return $o }
t_check "file names of the wildcard list are distinct" [expr {[llength [lsort -unique [pn_files $PROBE_WILDCARDS_ICC2]]] == [llength $PROBE_WILDCARDS_ICC2]}]
foreach lst {PROBE_COMMANDS_ICC2 PROBE_WILDCARDS_ICC2 PROBE_APPOPT_PATTERNS_ICC2 PROBE_COMMANDS_LM PROBE_WILDCARDS_LM} {
  upvar 0 $lst L
  t_check "$lst has no duplicates ([llength $L] entries)" [expr {[llength $L] == [llength [lsort -unique $L]] && [llength $L] > 0}]
}
set core {place_pins set_block_pin_constraints set_individual_pin_constraints create_placement place_opt clock_opt route_auto route_opt define_antenna_rule create_stdcell_fillers write_gds create_frame}
set miss {}; foreach c $core { if {[lsearch -exact $PROBE_COMMANDS_ICC2 $c] < 0} { lappend miss $c } }
t_check "icc2 list holds the core set" [expr {[llength $miss] == 0}] "missing: $miss"
set verify_cmds {get_libs get_object_name get_nets get_pins get_ports get_cells get_scenarios set_app_var get_app_var printvar current_scenario get_timing_paths get_site_rows get_site_defs get_blocks create_terminal get_terminals get_shapes}
set miss {}; foreach c $verify_cmds { if {[lsearch -exact $PROBE_COMMANDS_ICC2 $c] < 0} { lappend miss $c } }
t_check "icc2 list holds the commands used with VERIFY in the earlier scripts" [expr {[llength $miss] == 0}] "missing: $miss"
set miss {}; foreach c {create_workspace read_lef read_db check_workspace commit_workspace set_attribute get_lib_cells foreach_in_collection get_object_name redirect} { if {[lsearch -exact $PROBE_COMMANDS_LM $c] < 0} { lappend miss $c } }
t_check "lm list holds the commands of ndm_file_gen.tcl" [expr {[llength $miss] == 0}] "missing: $miss"
t_check "help_probe.tcl probes only help: no create_lib/open_lib/read_* call in the two probe scripts" [expr {![regexp {create_lib|open_lib|read_verilog|read_lef|create_workspace} [string map {# {}} [exec grep -v {^#} [file join $here help_probe.tcl] [file join $here help_probe_lm.tcl]]]]}]
# summary
set recs {{FOUND command place_pins /x/place_pins.txt} {NOT_FOUND command nosuch {NOT_FOUND (empty output)}} {ERROR wildcard *pin* boom} {FOUND appopt place.* /x/a.txt}}
lassign [unpu_probe_summary $recs] sl sf sn se st snames
t_check "summary: counts and names" [expr {$sf == 2 && $sn == 1 && $se == 1 && $st == 4 && $snames eq "command:nosuch" && [llength $sl] == 4}] "$sf $sn $se $st $snames"
t_check "summary: one line per record with status first" [expr {[string match "FOUND *" [lindex $sl 0]] && [string match "NOT_FOUND *" [lindex $sl 1]]}]

# ---- task 043: CTS parsers and parameters ------------------------------------------------
t_check "CTS parameters" [expr {$CTS_BUILD_TO eq "build_clock" && $CTS_OPT_FROM eq "route_clock" && $CTS_OPT_TO eq "final_opto" && $FLW_INCOMPLETE_ID eq "FLW-8004" && $EXPECT_CTS_LEVELS == 3 && $EXPECT_CTS_REPEATERS == 53 && $EXPECT_CTS_EXCLUDED == 12 && $TIMING_MAX_PATHS > 2219}]
# check_legality
t_check "legality: 'TOTAL 0 Violations'" [expr {[unpu_parse_legality "Legality check\n  TOTAL 0 Violations\n  (104 cell types)"] == 0}]
t_check "legality: nonzero count with a comma" [expr {[unpu_parse_legality "Total 1,204 violations found"] == 1204}]
t_check "legality: per-category zeros without a total are not parsed" [expr {[unpu_parse_legality "Overlap: 0\nOff-site: 0"] eq "not parsed"}]
# FLW ids
set flw_txt "Information: FLW-8000 stage route_clock\nInformation: FLW-8001 done\nWarning: FLW-8004: Incomplete clock_opt / final_opto\nWarning: FLW-8004: Incomplete again, see FLW-8000\nWarning: ZRT-309 other"
t_check "FLW counting: every occurrence, sorted" [expr {[unpu_count_ids $flw_txt FLW] eq "FLW-8000 2 FLW-8001 1 FLW-8004 2"}] [unpu_count_ids $flw_txt FLW]
t_check "FLW counting: none" [expr {[unpu_count_ids "no messages" FLW] eq ""}]
t_check "FLW counting: other prefixes are ignored" [expr {[unpu_count_ids "ZRT-309 ZRT-309" FLW] eq ""}]
# clock QoR, two layouts, the 18.17 numbers
set cq_a "Clock QoR summary\n  Number of sinks:   2,465\n  Number of levels:  3\n  Clock repeaters:   53\nCorner default\n  Max latency (ns):  1.21\n  Global skew (ns):  0.95\nCorner ff\n  Max latency (ns):  0.49\n  Global skew (ns):  0.36"
set cq_b "Clock: clk\n Sinks            2465\n Levels           3\n Repeater count   53\n Corner: default  latency 1.21  skew 0.95\n Corner: ff       latency 0.49  skew 0.36"
foreach {lay txt} [list A $cq_a B $cq_b] {
  set r [unpu_parse_clock_qor $txt {default ff}]
  array unset qq; array set qq [lrange $r 1 end]
  t_check "clock QoR layout $lay: 18.17 numbers" [expr {[lindex $r 0] eq "ok" && $qq(sinks) == 2465 && $qq(levels) == 3 && $qq(repeaters) == 53 && $qq(latency_default) == 1.21 && $qq(skew_default) == 0.95 && $qq(latency_ff) == 0.49 && $qq(skew_ff) == 0.36}] $r
}
t_check "clock QoR: no sinks number fails and quotes the text" [expr {[lindex [unpu_parse_clock_qor "Report\nnothing useful" {default ff}] 0] eq "fail" && [t_has [lindex [unpu_parse_clock_qor "Report\nnothing useful" {default ff}] 1] "Text seen*Report"]}]
set r [unpu_parse_clock_qor "Sinks: 2464\nCorner default\n Max latency 1.0" {default ff}]
array unset qq; array set qq [lrange $r 1 end]
t_check "clock QoR: wrong sinks value is returned as it is; absent items are empty" [expr {$qq(sinks) == 2464 && $qq(levels) eq "" && $qq(latency_ff) eq "" && $qq(latency_default) == 1.0}] $r
# report_timing paths
set rt "  Startpoint: u_wbuf/bank_b_reg_0__3__1_ (rising edge-triggered flip-flop clocked by clk)\n  Endpoint: u_wbuf/bank_b_reg_0__3__1_ (rising edge-triggered flip-flop clocked by clk)\n  Path Group: clk\n  clock uncertainty   -0.50\n  slack (VIOLATED)   -0.0125\n\n  Startpoint: pwdata\[1\] (input port)\n  Endpoint: u_csr/src_a_reg_reg_1_ (rising edge)\n  Path Group: in2reg\n  slack (VIOLATED)   -0.0060\n\n  Startpoint: a\n  Endpoint: b\n  Path Group: clk\n  slack (MET)   0.0100\n"
set pp [unpu_parse_report_timing_paths $rt]
t_check "report_timing paths: three paths with groups and slacks" [expr {[llength $pp] == 3 && [lindex [lindex $pp 0] 2] == -0.0125 && [lindex [lindex $pp 1] 3] eq "in2reg" && [lindex [lindex $pp 2] 2] == 0.01 && [lindex [lindex $pp 0] 1] eq "u_wbuf/bank_b_reg_0__3__1_"}] $pp
t_check "report_timing paths: violations by group" [expr {[unpu_violations_by_group $pp] eq "2 clk 1 in2reg 1"}] [unpu_violations_by_group $pp]
t_check "report_timing paths: no paths" [expr {[unpu_parse_report_timing_paths "No paths."] eq "" && [unpu_violations_by_group {}] eq "0"}]
set we [unpu_worst_endpoints $pp 2]
t_check "worst endpoints: lowest slack first, limited to n" [expr {[llength $we] == 2 && [t_has [lindex $we 0] "-0.0125 ns*u_wbuf/bank_b_reg_0__3__1_"] && [t_has [lindex $we 1] "-0.0060 ns*u_csr/src_a_reg_reg_1_"]}] $we
t_check "worst endpoints: fewer paths than n" [expr {[llength [unpu_worst_endpoints [lrange $pp 0 0] 10]] == 1}]
# constraint reports
t_check "violations: rows with (VIOLATED) are counted" [expr {[unpu_parse_violations "a (VIOLATED)\nb (VIOLATED)\nc (MET)"] == 2}]
t_check "violations: 'no violations' is zero" [expr {[unpu_parse_violations "Information: no violations"] == 0 && [unpu_parse_violations "Total: 0 violations"] == 0}]
t_check "violations: empty or unrecognised text is unavailable, never zero" [expr {[unpu_parse_violations ""] eq "unavailable" && [unpu_parse_violations "Report : constraint\nmax_transition"] eq "unavailable"}]
# clock uncertainty read back
t_check "clock uncertainty: value with a sign" [expr {[unpu_parse_clock_uncertainty "  clock uncertainty   -0.20   0.80"] == 0.20 && [unpu_parse_clock_uncertainty "clock uncertainty 0.50"] == 0.50}]
t_check "clock uncertainty: absent" [expr {[unpu_parse_clock_uncertainty "nothing"] eq ""}]
# generic number finder
set fn [unpu_find_numbers "Total cell area: 484,572.00\nNumber of instances: 14,309\nCore utilization 74.50 %" {area {(?i)cell\s*area} inst {(?i)instances} util {(?i)utili[sz]ation} bufs {(?i)buffers?}}]
t_check "find numbers: values and an absent label" [expr {$fn eq "area 484572.00 inst 14309 util 74.50 bufs {}"}] $fn

# ---- task 044: routing parsers, block-name override, stage rules ---------------------------------------
set cr_txt "Running check_routes ...\n\nVerify Summary:\n  Total number of nets = 13,999, of which 0 are not extracted\n  Total number of open nets = 0, of which 0 are frozen\n  Total number of excluded ports/nets (tie to rail): not checked\n  Total number of DRCs = 0\n  Total number of antenna violations = 0\n  Tie to rail: not checked\n"
array set crr [unpu_parse_check_routes $cr_txt]
t_check "check_routes summary: the first run's lines (18.20)" [expr {$crr(nets) == 13999 && $crr(not_extracted) == 0 && $crr(open_nets) == 0 && $crr(frozen) == 0 && $crr(drcs) == 0 && $crr(antenna) == 0 && [llength $crr(tie_lines)] == 2}] [array get crr]
array unset crr; array set crr [unpu_parse_check_routes [string map {"open nets = 0" "open nets = 1" "DRCs = 0" "DRCs = 2" "violations = 0" "violations = 3"} $cr_txt]]
t_check "check_routes summary: open nets 1, DRCs 2, antenna violations 3 are read" [expr {$crr(open_nets) == 1 && $crr(drcs) == 2 && $crr(antenna) == 3}] [array get crr]
array unset crr; array set crr [unpu_parse_check_routes "Report done.\nTotal number of nets = 10\nTotal number of DRCs = 0"]
t_check "check_routes summary: strict - a nets line without 'of which ... not extracted' and absent fields are 'not parsed'" [expr {$crr(open_nets) eq "not parsed" && $crr(antenna) eq "not parsed" && $crr(nets) eq "not parsed" && $crr(not_extracted) eq "not parsed" && $crr(drcs) == 0}] [array get crr]
array unset crr; array set crr [unpu_parse_check_routes ""]
t_check "check_routes summary: empty text is 'not parsed' everywhere" [expr {$crr(nets) eq "not parsed" && $crr(drcs) eq "not parsed"}]
array set lv1 [unpu_parse_check_lvs "LVS check\n  Shorts: 0\n  Opens: 0\n  Floating routes: 0 (14,008 nets)"]
t_check "check_lvs, 'name: n' layout" [expr {$lv1(shorts) == 0 && $lv1(opens) == 0 && $lv1(floating) == 0}] [array get lv1]
array set lv2 [unpu_parse_check_lvs "Found 2 shorts\nFound 0 opens\nNo floating routes found"]
t_check "check_lvs, 'n name' layout with a short and 'No floating routes'" [expr {$lv2(shorts) == 2 && $lv2(opens) == 0 && $lv2(floating) == 0}] [array get lv2]
array set lv3 [unpu_parse_check_lvs "check_lvs done"]
t_check "check_lvs: nothing recognised is 'not parsed'" [expr {$lv3(shorts) eq "not parsed" && $lv3(opens) eq "not parsed" && $lv3(floating) eq "not parsed"}]
set ra_txt "Route summary\n  Total wire length = 792,524.31 um\n  Layer M1 16,927\n  Layer M2 323,338\n  Layer M3 368,389\n  Layer TOP_M 81,399\n  Total number of contacts = 103,651\n  Layer V2 49,073\n  Layer V3 49,523\n  Layer TOP_V 5,055\n  Total number of open nets = 0 of 13,997\nDR iteration 0: 4 violations\nDR iteration 1: 0 violations\nFinish DR since reached 0 DRC\n"
array set rs [unpu_parse_route_summary $ra_txt {M1 M2 M3 TOP_M} {V2 V3 TOP_V}]
t_check "route summary: the 18.20 numbers (wire per layer, contacts per via layer, open nets, finish line)" [expr {$rs(wire_total) == 792524.31 && $rs(wire_M1) == 16927 && $rs(wire_M2) == 323338 && $rs(wire_M3) == 368389 && $rs(wire_TOP_M) == 81399 && $rs(contacts_total) == 103651 && $rs(via_V2) == 49073 && $rs(via_V3) == 49523 && $rs(via_TOP_V) == 5055 && $rs(open_nets) == 0 && $rs(finished_dr) == 1}] [array get rs]
array unset rs; array set rs [unpu_parse_route_summary "nothing here" {M1 M2} {V2}]
t_check "route summary: nothing found gives empty values" [expr {$rs(wire_total) eq "" && $rs(wire_M1) eq "" && $rs(via_V2) eq "" && $rs(finished_dr) == 0}]
t_check "DR iterations: violations per iteration" [expr {[unpu_parse_dr_iterations $ra_txt] eq "{0 4} {1 0}"}] [unpu_parse_dr_iterations $ra_txt]
t_check "DR iterations: none" [expr {[unpu_parse_dr_iterations "no iteration lines"] eq ""}]
set z_txt "Warning: ZRT-311: Skipping antenna analysis for net paddr\[4\] because there is not enough gate area information\nWarning: ZRT-311: Skipping antenna analysis for net pwdata\[7\] ... not enough gate area information\nWarning: ZRT-311: Skipping antenna analysis for net paddr\[4\] (again)\nInfo: ZRT-309 other"
t_check "ZRT-311: net names, sorted and unique" [expr {[lindex [unpu_zrt311_nets $z_txt] 0] eq "paddr\[4\]" && [lindex [unpu_zrt311_nets $z_txt] 1] eq "pwdata\[7\]" && [llength [unpu_zrt311_nets $z_txt]] == 2}] [unpu_zrt311_nets $z_txt]
t_check "ZRT-309 and ZRT-311 counting (every occurrence)" [expr {[unpu_count_ids $z_txt ZRT] eq "ZRT-309 1 ZRT-311 3"}] [unpu_count_ids $z_txt ZRT]
set opt_txt "Information: OPT-209: unreasonable large hold violation(s)\nInformation: OPT-209: unreasonable large hold violation(s)\nInformation: OPT-100 other"
t_check "OPT-209 counted twice" [expr {[unpu_count_ids $opt_txt OPT] eq "OPT-100 1 OPT-209 2"}] [unpu_count_ids $opt_txt OPT]
# the hold switch rule
t_check "hold decision: zero violations pass (switch or not)" [expr {[unpu_hold_decision 0 0] eq "pass" && [unpu_hold_decision 0 1] eq "pass"}]
t_check "hold decision: violations fail without the switch" [expr {[unpu_hold_decision 6 0] eq "fail"}]
t_check "hold decision: violations are accepted only with the switch" [expr {[unpu_hold_decision 6 1] eq "accepted"}]

# router antenna switch (task 044 follow-up): decision on the value of route.detail.antenna
foreach {val st} {true on True on 1 on on on yes on false off False off 0 off off off no off "" unknown maybe unknown auto unknown "{true}" on " false " off} {
  t_check "option state: '$val' is $st" [expr {[unpu_option_state $val] eq $st}] [unpu_option_state $val]
}
set rep "Name                                 Type     Default  Value\n------------------------------------------------\nroute.detail.antenna                 boolean  true     false\nroute.detail.antenna_fixing_preference string (none) hole"
t_check "report parse: Default and Value columns that disagree are ambiguous, not guessed" [expr {[unpu_app_option_from_report $rep route.detail.antenna] eq ""}] [unpu_app_option_from_report $rep route.detail.antenna]
t_check "report parse: Default and Value columns that agree give the value" [expr {[unpu_app_option_from_report "route.detail.antenna boolean false false" route.detail.antenna] eq "false"}]
set rep2 "route.detail.antenna  false"
t_check "report parse: two-column layout" [expr {[unpu_app_option_from_report $rep2 route.detail.antenna] eq "false"}]
t_check "report parse: option not listed gives empty" [expr {[unpu_app_option_from_report $rep2 route.detail.other] eq ""}]
t_check "report parse: the longer name does not match the shorter one" [expr {[unpu_app_option_from_report "route.detail.antenna_fixing_preference string hole" route.detail.antenna] eq ""}]
t_check "report parse: no boolean word gives empty" [expr {[unpu_app_option_from_report "route.detail.antenna  string abc" route.detail.antenna] eq ""}]
lassign [unpu_antenna_switch_message route.detail.antenna true] st msg
t_check "antenna switch true: state on, no alarm text" [expr {$st eq "on" && [string first "!!!" $msg] < 0}] $msg
lassign [unpu_antenna_switch_message route.detail.antenna false] st msg
t_check "antenna switch false: state off, loud text says the router will NOT fix antennas" [expr {$st eq "off" && [string first "!!!" $msg] >= 0 && [string first "will NOT fix antenna" $msg] >= 0}] $msg
lassign [unpu_antenna_switch_message route.detail.antenna ""] st msg
t_check "antenna switch unreadable: state unknown, loud text" [expr {$st eq "unknown" && [string first "!!!" $msg] >= 0 && [string first "could not be read" $msg] >= 0}] $msg
t_check "ROUTE_ANTENNA_ENABLE_OPTION is route.detail.antenna" [expr {$ROUTE_ANTENNA_ENABLE_OPTION eq "route.detail.antenna"}]

# ---- fill stage (task 045) ---------------------------------------------------------------------------------
# create_stdcell_fillers output: the three lines of the first run (18.22)
set ftxt "Info: 3 filler cell types\n  Option: ... 4159 of regular filler feedth9 inserted\n  ... 7451 of regular filler feedth3 inserted\n  ... 10902 of regular filler feedth inserted\nInfo: done"
set fc [unpu_parse_fillers $ftxt]
t_check "fillers: counts per cell in the order printed" [expr {$fc eq "feedth9 4159 feedth3 7451 feedth 10902"}] $fc
t_check "fillers: total is 22,512 (18.22)" [expr {[unpu_filler_total $fc] == 22512}] [unpu_filler_total $fc]
t_check "fillers: a library prefix and a thousands comma are accepted" [expr {[unpu_parse_fillers "10,902 of regular filler scl18fs120_fillf/feedth inserted"] eq "feedth 10902"}] [unpu_parse_fillers "10,902 of regular filler scl18fs120_fillf/feedth inserted"]
t_check "fillers: the same cell printed twice is summed" [expr {[unpu_parse_fillers "5 of regular filler feedth inserted\n7 of regular filler feedth inserted"] eq "feedth 12"}]
t_check "fillers: no matching line gives an empty list and total 0" [expr {[unpu_parse_fillers "nothing inserted"] eq "" && [unpu_filler_total {}] == 0}]
# connect_pg_net: previous/current table and the pins sentence (18.22: VDD 12041/34553, VSS 12041/34553, 45,024 pins)
set cpg "Power net VDD   12041/34553\nPower net VSS   12041/34553\nconnections of 45,024 power/ground pin(s) are created or changed."
array set ch [unpu_parse_connect_pg_change $cpg {VDD VSS}]
t_check "connect_pg change: pins 45024, VDD 12041 -> 34553, VSS the same" [expr {$ch(pins) == 45024 && $ch(VDD_previous) == 12041 && $ch(VDD_current) == 34553 && $ch(VSS_previous) == 12041 && $ch(VSS_current) == 34553}] [array get ch]
array unset ch
array set ch [unpu_parse_connect_pg_change "Power net VDD   12041 34553\nPower net VSS   12,041 34,553\nconnections of 45024 power/ground pins are created or changed" {VDD VSS}]
t_check "connect_pg change: a space instead of the slash, commas, 'pins'" [expr {$ch(pins) == 45024 && $ch(VDD_current) == 34553 && $ch(VSS_previous) == 12041}] [array get ch]
array unset ch
array set ch [unpu_parse_connect_pg_change "Power net VDD   12041/34553" {VDD VSS}]
t_check "connect_pg change: a missing net and a missing pins line are 'not parsed'" [expr {$ch(pins) eq "not parsed" && $ch(VSS_previous) eq "not parsed" && $ch(VSS_current) eq "not parsed" && $ch(VDD_current) == 34553}] [array get ch]
t_check "connect_pg (existing parser) now reads previous/current: the larger count" [expr {[unpu_parse_connect_pg "VDD 12041/34553\nVSS 12041/34553" {VDD VSS}] eq "VDD 34553 VSS 34553"}] [unpu_parse_connect_pg "VDD 12041/34553\nVSS 12041/34553" {VDD VSS}]
# free sites and coverage: first-run numbers and the new die
set fs [unpu_free_sites 144 1440 428,609.66 0.56 5.6]
t_check "free sites, first run: 207,360 total, 136,674 used, 70,686 free" [expr {$fs eq "207360 136674 70686"}] $fs
set fs2 [unpu_free_sites 153 1530 512434.94 0.56 5.6]
t_check "free sites, new die: 153 x 1,530 = 234,090 total" [expr {[lindex $fs2 0] == 234090}] $fs2
t_check "free sites: unreadable area is 'not parsed'" [expr {[unpu_free_sites 153 1530 unavailable 0.56 5.6] eq "not parsed" && [unpu_free_sites 153 1530 "" 0.56 5.6] eq "not parsed"}]
set cov [unpu_filler_coverage "feedth9 4159 feedth3 7451 feedth 10902" {feedth 1 feedth3 3 feedth9 9} 70686 2]
t_check "coverage, first run: 9 x 4159 + 3 x 7451 + 10902 = 70,686, difference 0, ok" [expr {$cov eq "1 70686 70686 0 {}"}] $cov
set cov [unpu_filler_coverage "feedth9 4159 feedth3 7451 feedth 10952" {feedth 1 feedth3 3 feedth9 9} 70686 2]
t_check "coverage: 50 sites too many is not ok" [expr {[lindex $cov 0] == 0 && [lindex $cov 3] == 50}] $cov
t_check "coverage: 2 sites off is within the tolerance, 3 is not" [expr {[lindex [unpu_filler_coverage "feedth 70688" {feedth 1} 70686 2] 0] == 1 && [lindex [unpu_filler_coverage "feedth 70689" {feedth 1} 70686 2] 0] == 0}]
set cov [unpu_filler_coverage "feedth9 4159 feedth7 10 feedth 10902" {feedth 1 feedth3 3 feedth9 9} 70686 2]
t_check "coverage: a cell with no known width is listed and not ok" [expr {[lindex $cov 0] == 0 && [lindex $cov 4] eq "feedth7"}] $cov
set cov [unpu_filler_coverage "feedth9 4159 feedth 10902" {feedth 1 feedth3 3 feedth9 9} 70686 2]
t_check "coverage: a missing cell type (no feedth3) leaves the sites uncovered" [expr {[lindex $cov 0] == 0 && [lindex $cov 3] == -22353}] $cov
t_check "geometry of the default die: 153 rows, 1,530 sites per row" [expr {$FP_ROWS == 153 && int(round($CORE_SIDE / $SITE_WIDTH)) == 1530}] "$FP_ROWS $CORE_SIDE $SITE_WIDTH"
t_check "FILLER_SITES covers exactly FILLER_CELLS" [expr {[lsort [dict keys $FILLER_SITES]] eq [lsort $FILLER_CELLS]}]
# fillers with violations (remove_stdcell_fillers_with_violation -check_only true)
t_check "filler violations: 'no filler cell with violation' is 0" [expr {[unpu_parse_filler_violations "Info: no filler cell with violation was found"] == 0}]
t_check "filler violations: '3 filler cell(s) with violations' is 3" [expr {[unpu_parse_filler_violations "Info: 3 filler cell(s) with violations were found; see x.rpt"] == 3}]
t_check "filler violations: an unrelated text is 'not parsed'" [expr {[unpu_parse_filler_violations "Done."] eq "not parsed" && [unpu_parse_filler_violations ""] eq "not parsed"}]
# the hold rule of the filled block: 0 passes, a sub-picosecond residual is accepted, larger fails, unreadable fails
t_check "fill hold: 0 violating endpoints pass" [expr {[unpu_fill_hold_decision 0 0.01 0.001 10] eq "pass"}]
t_check "fill hold: 1 endpoint at -0.0004 ns (0.4 ps) is accepted" [expr {[unpu_fill_hold_decision 1 -0.0004 0.001 10] eq "accepted"}]
t_check "fill hold: the first run's -0.0006 ns residual is accepted" [expr {[unpu_fill_hold_decision 1 -0.0006 0.001 10] eq "accepted"}]
t_check "fill hold: exactly -0.001 ns is accepted (not worse than the tolerance)" [expr {[unpu_fill_hold_decision 1 -0.001 0.001 10] eq "accepted"}]
t_check "fill hold: -0.005 ns (5 ps) fails" [expr {[unpu_fill_hold_decision 1 -0.005 0.001 10] eq "fail"}]
t_check "fill hold: 10 endpoints at -0.0004 ns are accepted, 11 fail (FILL_HOLD_MAX_ENDPOINTS 10)" [expr {[unpu_fill_hold_decision 10 -0.0004 0.001 10] eq "accepted" && [unpu_fill_hold_decision 11 -0.0004 0.001 10] eq "fail" && $FILL_HOLD_MAX_ENDPOINTS == 10}]
t_check "fill hold: many endpoints with a tiny worst slack do not hide behind it" [expr {[unpu_fill_hold_decision 400 -0.0001 0.001 10] eq "fail"}]
t_check "fill hold: an unavailable count fails" [expr {[unpu_fill_hold_decision unavailable -0.0004 0.001 10] eq "fail"}]
t_check "fill hold: an unreadable slack with violations fails" [expr {[unpu_fill_hold_decision 2 unavailable 0.001 10] eq "fail" && [unpu_fill_hold_decision 2 "" 0.001 10] eq "fail"}]
t_check "fill hold: tolerance and decision date are parameters (0.001 ns)" [expr {$FILL_HOLD_TOLERANCE_NS == 0.001 && $FILL_COVERAGE_TOL_SITES == 2 && $FILL_ECO eq "0"}] "$FILL_HOLD_TOLERANCE_NS $FILL_COVERAGE_TOL_SITES $FILL_ECO"
t_check "hold endpoint lines for the manifest" [expr {[unpu_hold_endpoint_lines {a b}] eq "{hold_endpoint_1 = a} {hold_endpoint_2 = b}"}] [unpu_hold_endpoint_lines {a b}]
# ---- output-file checkers (task 046) ------------------------------------------------------------------------
# Verilog: module definitions (endmodule and comments do not count), the header block name, library cell types
set vtxt "// Block Name: final\nmodule unpu_top (a, b);\n  input a;\n  wire n1;\n  ad01d0 U1 ( .A(a), .CO(n1) );\n  sub u_sub ( .x(n1) );\n  \\ff\\/q U2 ( .A(a) );\nendmodule\nmodule sub (x);\n  inv0d1 U3 ( .I(x) );\n  ad01d0 U4 ( .A(x) );\nendmodule\n// module commented ( \n"
t_check "verilog: two module definitions, endmodule and comments not counted" [expr {[unpu_verilog_modules $vtxt] eq "unpu_top sub"}] [unpu_verilog_modules $vtxt]
t_check "verilog: header block name" [expr {[unpu_verilog_block_name $vtxt] eq "final" && [unpu_verilog_block_name "module x();"] eq ""}]
t_check "verilog: library cell types are the instantiated types that are not modules" [expr {[unpu_verilog_cell_types $vtxt] eq [list {\ff\/q} ad01d0 inv0d1]}] [unpu_verilog_cell_types $vtxt]
t_check "verilog: .VDD( / .VSS( connection pattern" [expr {[regexp -- {\.(VDD|VSS)\s*\(} "U1 ( .A(a), .VDD(VDD) )"] && ![regexp -- {\.(VDD|VSS)\s*\(} "U1 ( .A(a), .VDDQ(x) )"]}]
# LEF: one macro (good), two macros (the 18.25 case), the 163-byte shell (18.23)
set lef_good "VERSION 5.8 ;\nMACRO unpu_top\n  CLASS BLOCK ;\n  SIZE 868 BY 868 ;\n  PIN a\n    DIRECTION INPUT ;\n    PORT\n      LAYER M3 ;\n        RECT 0 10 0.5 10.5 ;\n    END\n  END a\n  PIN VDD\n    DIRECTION INPUT ;\n    USE POWER ;\n    PORT\n      LAYER TOP_M ;\n        RECT 116.48 0 118.72 6 ;\n        RECT 228.48 0 230.72 6 ;\n    END\n  END VDD\n  PIN VSS\n    USE GROUND ;\n    PORT\n      LAYER TOP_M ;\n        RECT 60.48 2 62.72 6 ;\n    END\n  END VSS\n  OBS\n    LAYER M1 ;\n      RECT 0 0 868 868 ;\n  END\nEND unpu_top\nEND LIBRARY\n"
array set lg [unpu_parse_lef $lef_good]
t_check "lef: one macro, size, three pins in order" [expr {$lg(macros) eq "unpu_top" && $lg(size) eq "868 868" && $lg(pins) eq "a VDD VSS"}] [array get lg]
t_check "lef: rectangles of VDD on TOP_M are 2, starting at y 0; the OBS rectangle is not a pin rectangle" [expr {[llength [unpu_lef_pin_rects [array get lg] VDD TOP_M]] == 2 && [lindex [lindex [unpu_lef_pin_rects [array get lg] VDD TOP_M] 0] 1] == 0 && [llength [unpu_lef_pin_rects [array get lg] a M1]] == 0 && [llength [unpu_lef_pin_rects [array get lg] VSS TOP_M]] == 1}]
t_check "lef: USE is read per pin" [expr {[dict get $lg(use) VDD] eq "POWER" && [dict get $lg(use) VSS] eq "GROUND"}]
array set lt [unpu_parse_lef "$lef_good\nMACRO unpu_top\n  SIZE 868 BY 868 ;\nEND unpu_top\n"]
t_check "lef: two MACRO unpu_top entries are seen (the stale-frame case of 18.25)" [expr {$lt(macros) eq "unpu_top unpu_top"}] $lt(macros)
set shell "VERSION 5.8 ;\nBUSBITCHARS \"\[\]\" ;\nDIVIDERCHAR \"/\" ;\nEND LIBRARY\n"
array set ls [unpu_parse_lef $shell]
t_check "lef: the empty shell has no macro, no size, no pin ([string length $shell] bytes here, 163 in 18.23)" [expr {$ls(macros) eq "" && $ls(size) eq "" && $ls(pins) eq ""}] [array get ls]
array set lb [unpu_parse_lef "MACRO m\n PIN paddr\[3\]\n  PORT\n   LAYER M3 ;\n   RECT 1 2 3 4 ;\n  END\n END paddr\[3\]\n PIN b\n  PORT\n   LAYER M3 ;\n   RECT 5 6 7 8 ;\n  END\n END b\nEND m"]
t_check "lef: a bus pin name with brackets closes at its END line (the next pin keeps its own rectangle)" [expr {$lb(pins) eq [list "paddr\[3\]" b] && [unpu_lef_pin_rects [array get lb] "paddr\[3\]" M3] eq "{1 2 3 4}" && [unpu_lef_pin_rects [array get lb] b M3] eq "{5 6 7 8}"}] [array get lb]
# SPEF / SDF heads
t_check "spef head: *SPEF first, *DESIGN names the design" [expr {[unpu_check_spef_head "*SPEF \"IEEE 1481-1998\"\n*DESIGN \"unpu_top\"\n*DATE x" unpu_top] eq "1 {*SPEF \"IEEE 1481-1998\"} unpu_top"}] [unpu_check_spef_head "*SPEF \"IEEE 1481-1998\"\n*DESIGN \"unpu_top\"\n" unpu_top]
t_check "spef head: another design name fails, no *SPEF fails" [expr {[lindex [unpu_check_spef_head "*SPEF x\n*DESIGN \"other\"\n" unpu_top] 0] == 0 && [lindex [unpu_check_spef_head "garbage\n*DESIGN \"unpu_top\"\n" unpu_top] 0] == 0 && [lindex [unpu_check_spef_head "" unpu_top] 0] == 0}]
t_check "sdf head: (DELAYFILE and (DESIGN \"unpu_top\")" [expr {[unpu_check_sdf_head "(DELAYFILE\n(SDFVERSION \"3.0\")\n(DESIGN \"unpu_top\")\n" unpu_top] && ![unpu_check_sdf_head "(DELAYFILE\n(DESIGN \"x\")\n" unpu_top] && ![unpu_check_sdf_head "(DESIGN \"unpu_top\")" unpu_top]}]
# SDC uncertainty
set sdc "create_clock -name clk -period 20 \[get_ports clk\]\nset_clock_uncertainty -setup 0.8 \[get_clocks clk\]\nset_clock_uncertainty -hold 0.5 \[get_clocks clk\]\nset_clock_uncertainty -from a -to b -hold 9 \[get_clocks clk\]\n"
array set sd [unpu_parse_sdc $sdc]
t_check "sdc: setup 0.8, hold 0.5, one clock; the -from/-to line is ignored" [expr {$sd(setup) == 0.8 && $sd(hold) == 0.5 && $sd(clocks) == 1}] [array get sd]
array set sd [unpu_parse_sdc "set_clock_uncertainty 0.3 \[get_clocks clk\]"]
t_check "sdc: an uncertainty without -setup/-hold sets both" [expr {$sd(setup) == 0.3 && $sd(hold) == 0.3 && $sd(clocks) == 0}] [array get sd]
array set sd [unpu_parse_sdc "set_clock_latency 1 x"]
t_check "sdc: no uncertainty gives empty values" [expr {$sd(setup) eq "" && $sd(hold) eq ""}]
t_check "new files of a write command: those added whose name starts with the prefix" [expr {[unpu_new_files {a.v unpu_top_ss.spef.old} {a.v unpu_top_ss.spef.old unpu_top_ss.spef.typ_125.spef unpu_top_ss.spef_scenario other.txt} unpu_top_ss.spef] eq "unpu_top_ss.spef.typ_125.spef unpu_top_ss.spef_scenario"}]
# GDSII: a tiny stream written by the test (HEADER BGNLIB LIBNAME UNITS BGNSTR STRNAME TEXT STRING ENDEL ENDSTR ... ENDLIB)
proc g_rec {rt dt data} { return [binary format SccA* [expr {4 + [string length $data]}] $rt $dt $data] }
proc g_str {s} { if {[string length $s] % 2} { append s "\x00" }; return $s }
proc g_real {v} {
  if {$v == 0} { return [binary format c8 {0 0 0 0 0 0 0 0}] }
  set sign 0; if {$v < 0} { set sign 128; set v [expr {-$v}] }
  set e 0
  while {$v >= 1.0} { set v [expr {$v / 16.0}]; incr e }
  while {$v < 0.0625} { set v [expr {$v * 16.0}]; incr e -1 }
  set m [expr {wide(round($v * 72057594037927936.0))}]
  set bytes [list [expr {$sign | ($e + 64)}]]
  for {set k 6} {$k >= 0} {incr k -1} { lappend bytes [expr {($m >> (8*$k)) & 255}] }
  return [binary format c8 $bytes]
}
proc g_stream {units_dbu structs texts {end 1} {pad 0}} {
  set s [g_rec 0 2 [binary format S 600]]
  append s [g_rec 1 2 [binary format S12 {0 0 0 0 0 0 0 0 0 0 0 0}]]
  append s [g_rec 2 6 [g_str TESTLIB]]
  append s [g_rec 3 5 "[g_real [expr {1.0/$units_dbu}]][g_real [expr {1e-6/$units_dbu}]]"]
  foreach st $structs {
    append s [g_rec 5 2 [binary format S12 {0 0 0 0 0 0 0 0 0 0 0 0}]]
    append s [g_rec 6 6 [g_str $st]]
    if {$st eq "unpu_top"} {
      foreach tx $texts { append s [g_rec 12 0 ""] [g_rec 13 2 [binary format S 5]] [g_rec 22 2 [binary format S 0]] [g_rec 16 3 [binary format I2 {0 0}]] [g_rec 25 6 [g_str $tx]] [g_rec 17 0 ""] }
      append s [g_rec 10 0 ""] [g_rec 18 6 [g_str ad01d0]] [g_rec 16 3 [binary format I2 {0 0}]] [g_rec 17 0 ""]
    }
    append s [g_rec 7 0 ""]
  }
  if {$end} { append s [g_rec 4 0 ""] }
  if {$pad} { append s [string repeat "\x00" $pad] }
  return $s
}
proc g_bytes {r} { binary scan $r cu8 b; return $b }
t_check "gds real8 round trip: 1e-3, 1e-9 and 1" [expr {abs([unpu_gds_real8 [g_bytes [g_real 1e-3]]] - 1e-3) < 1e-15 && abs([unpu_gds_real8 [g_bytes [g_real 1e-9]]] - 1e-9) < 1e-21 && [unpu_gds_real8 [g_bytes [g_real 1.0]]] == 1.0}]
t_check "gds real8: the known encoding of 1.0 is 41 10 00 00 00 00 00 00" [expr {[g_bytes [g_real 1.0]] eq "65 16 0 0 0 0 0 0"}] [g_bytes [g_real 1.0]]
set gd [g_stream 1000 {unpu_top ad01d0} {paddr[0] paddr[1] VDD VSS}]
array set gs [unpu_gds_scan $gd]
t_check "gds scan: well formed, 'HEADER' first (0002), ENDLIB seen" [expr {$gs(ok) && $gs(first) eq "0002" && $gs(endlib) == 1}] [array get gs]
t_check "gds scan: structure names, referenced structure, text strings" [expr {$gs(strnames) eq "unpu_top ad01d0" && $gs(snames) eq "ad01d0" && $gs(texts) eq [list "paddr\[0\]" "paddr\[1\]" VDD VSS]}] [array get gs]
lassign [unpu_gds_units_check $gs(units) 1000 1e-6] uok dbu dbm um
t_check "gds units: -units 1000 -> 1000 db units per user unit, 1e-9 m database unit, user unit 1 um" [expr {$uok && abs($dbu - 1000) < 1e-3 && abs($dbm - 1e-9) < 1e-15 && abs($um - 1e-6) < 1e-12}] "$uok $dbu $dbm $um"
array set g2 [unpu_gds_scan [g_stream 10000 {unpu_top} {VDD}]]
t_check "gds units: a stream with 10000 db units per um (the default of 18.24) fails the -units 1000 check" [expr {[lindex [unpu_gds_units_check $g2(units) 1000 1e-6] 0] == 0 && abs([lindex [unpu_gds_units_check $g2(units) 1000 1e-6] 1] - 10000) < 1e-2}]
t_check "gds units: no UNITS record fails" [expr {[lindex [unpu_gds_units_check {} 1000 1e-6] 0] == 0}]
set cnt [unpu_gds_label_counts $gs(texts) {paddr[0] paddr[1] paddr[2] VDD VSS}]
t_check "gds labels: counts per name, a missing label is found" [expr {$cnt eq [list "paddr\[0\]" 1 "paddr\[1\]" 1 "paddr\[2\]" 0 VDD 1 VSS 1] && [unpu_zero_counts $cnt] eq [list "paddr\[2\]"]}] $cnt
t_check "gds labels: a repeated label is counted twice" [expr {[unpu_gds_label_counts {VDD VDD x} {VDD}] eq "VDD 2"}]
array set g3 [unpu_gds_scan [g_stream 1000 {unpu_top} {VDD} 1 6]]
t_check "gds scan: zero padding after ENDLIB is accepted" [expr {$g3(ok)}] [array get g3]
array set g4 [unpu_gds_scan [g_stream 1000 {unpu_top} {VDD} 0 0]]
t_check "gds scan: a stream without ENDLIB is seen (endlib 0)" [expr {$g4(endlib) == 0}]
array set g5 [unpu_gds_scan [string range [g_stream 1000 {unpu_top} {VDD}] 0 end-7]]
t_check "gds scan: a truncated stream is not ok" [expr {!$g5(ok) && [string length $g5(error)] > 0}] $g5(error)
array set g6 [unpu_gds_scan "not a gds file at all"]
t_check "gds scan: text that is not GDSII is not ok (first record is not 0002)" [expr {$g6(first) ne "0002"}] [array get g6]
array set g7 [unpu_gds_scan ""]
t_check "gds scan: an empty file is not ok" [expr {!$g7(ok)}]
set gtmp [file join $tmp g.gds]
set fh [open $gtmp w]; fconfigure $fh -translation binary; puts -nonewline $fh $gd; close $fh
t_check "file reader: the binary file reads back byte for byte, the head reader cuts it" [expr {[unpu_read_text $gtmp] eq $gd && [string length [unpu_read_head $gtmp 10]] == 10}]
t_check "file reader: a missing file is an error" [expr {[catch {unpu_read_text [file join $tmp nosuch]}]}]
# parameters of the outputs stage
t_check "outputs parameters: prefix, module count, min sizes, overwrite default" [expr {$OUT_PREFIX eq "unpu_top" && $EXPECT_NETLIST_MODULES == 76 && $OUTPUTS_OVERWRITE eq "0" && [dict get $OUT_MIN_BYTES lef] > 163 && $GDS_LAYER_MAP eq $GDS_LAYER_MAP_KIT}]
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs OW=\$OUTPUTS_OVERWRITE" {UNPU_OUTPUTS_OVERWRITE 1}] c o
t_check "UNPU_OUTPUTS_OVERWRITE=1 is accepted with a Warning" [expr {$c == 0 && [t_has $o "OW=1"] && [t_has $o "Warning: \[unpu\]*UNPU_OUTPUTS_OVERWRITE=1"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs NOT_REACHED" {UNPU_OUTPUTS_OVERWRITE 2}] c o
t_check "UNPU_OUTPUTS_OVERWRITE=2 is rejected" [expr {$c == 1 && [t_has $o "must be 0 or 1"]}] "exit $c: $o"
set mapf [file join $tmp custom.map]; set fh [open $mapf w]; puts $fh "x"; close $fh
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs MAP=\$GDS_LAYER_MAP" [list UNPU_GDS_LAYER_MAP $mapf]] c o
t_check "UNPU_GDS_LAYER_MAP replaces the kit map with a Warning" [expr {$c == 0 && [t_has $o "MAP=$mapf"] && [t_has $o "Warning: \[unpu\]*layer map overridden"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs NOT_REACHED" [list UNPU_GDS_LAYER_MAP [file join $tmp nosuch.map]]] c o
t_check "UNPU_GDS_LAYER_MAP to a missing file is rejected" [expr {$c == 1 && [t_has $o "does not exist"]}] "exit $c: $o"
# UNPU_FILL_ECO: 0|1 only, a Warning for 1
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs ECO=\$FILL_ECO" {UNPU_FILL_ECO 1}] c o
t_check "UNPU_FILL_ECO=1 is accepted with a Warning" [expr {$c == 0 && [t_has $o "ECO=1"] && [t_has $o "Warning: \[unpu\]*UNPU_FILL_ECO=1"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nputs NOT_REACHED" {UNPU_FILL_ECO 2}] c o
t_check "UNPU_FILL_ECO=2 is rejected" [expr {$c == 1 && [t_has $o "UNPU_FILL_ECO='2' must be 0 or 1"]}] "exit $c: $o"
t_check "hold decision: an unavailable count is never accepted" [expr {[unpu_hold_decision unavailable 1] eq "fail" && [unpu_hold_decision unavailable 0] eq "fail"}]
t_check "ROUTE_ACCEPT_HOLD defaults to 0" [expr {$ROUTE_ACCEPT_HOLD eq "0"}]
lassign [t_child "$pre" {UNPU_ROUTE_ACCEPT_HOLD 1}] c o
t_check "UNPU_ROUTE_ACCEPT_HOLD=1 is accepted and a Warning is printed at source time" [expr {$c == 0 && [t_has $o "Warning: \[unpu\] UNPU_ROUTE_ACCEPT_HOLD=1"]}] "exit $c: $o"
lassign [t_child "$pre" {UNPU_ROUTE_ACCEPT_HOLD yes}] c o
t_check "UNPU_ROUTE_ACCEPT_HOLD=yes is rejected" [expr {$c == 1 && [t_has $o "must be 0 or 1"]}] "exit $c: $o"
# BLK_* override
t_check "BLK_ROUTE_AUTO default" [expr {$BLK_ROUTE_AUTO eq "routeauto" && $BLK_CLKOPT eq "clkopt" && $BLK_ROUTED eq "routed"}]
lassign [t_child "${pre}puts \"B=\$BLK_CLKOPT R=\$BLK_ROUTED\"" {UNPU_BLK_CLKOPT clkopt_h02}] c o
t_check "UNPU_BLK_CLKOPT=clkopt_h02 overrides with a Warning and the other names stay" [expr {$c == 0 && [t_has $o "B=clkopt_h02 R=routed"] && [t_has $o "Warning: \[unpu\] checkpoint block BLK_CLKOPT = clkopt_h02 overrides the default clkopt"]}] "exit $c: $o"
lassign [t_child "$pre" {UNPU_BLK_ROUTE_AUTO ra2}] c o
t_check "UNPU_BLK_ROUTE_AUTO is an override too" [expr {$c == 0 && [t_has $o "BLK_ROUTE_AUTO = ra2"]}] "exit $c: $o"
lassign [t_child "$pre" {UNPU_BLK_CTS bad-name}] c o
t_check "an override with a bad name is rejected" [expr {$c == 1 && [t_has $o "Error: \[unpu\] UNPU_BLK_CTS='bad-name' may contain only letters, digits and _"]}] "exit $c: $o"
lassign [t_child "$pre" {UNPU_BLK_FP a/b}] c o
t_check "an override with a slash is rejected" [expr {$c == 1}] "exit $c: $o"
lassign [t_child "${pre}puts \"N=\[lsearch -exact \$UNPU_PARAM_NAMES BLK_CLKOPT\]\"" {UNPU_BLK_CLKOPT x1}] c o
t_check "the overridden names are in the computed manifest list" [expr {$c == 0 && ![t_has $o "N=-1"]}] "exit $c: $o"
# CTS stage rule
lassign [unpu_cts_stage_plan all placed cts clkopt] mn mh ob
t_check "cts stage all: cts and clkopt must not exist, placed is opened" [expr {$mn eq "cts clkopt" && $mh eq "" && $ob eq "placed"}] "$mn | $mh | $ob"
lassign [unpu_cts_stage_plan tree placed cts clkopt] mn mh ob
t_check "cts stage tree: only cts must not exist, placed is opened" [expr {$mn eq "cts" && $mh eq "" && $ob eq "placed"}] "$mn | $mh | $ob"
lassign [unpu_cts_stage_plan hold placed cts clkopt] mn mh ob
t_check "cts stage hold: clkopt must not exist, cts must exist and is opened" [expr {$mn eq "clkopt" && $mh eq "cts" && $ob eq "cts"}] "$mn | $mh | $ob"
lassign [unpu_cts_stage_plan hold placed cts clkopt_h02] mn mh ob
t_check "cts stage hold with another clkopt name" [expr {$mn eq "clkopt_h02" && $ob eq "cts"}] "$mn | $ob"
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_cts_stage_plan bogus a b c" {}] c o
t_check "cts stage: an unknown value dies" [expr {$c == 1 && [t_has $o "not all, tree or hold"]}] "exit $c: $o"
t_check "CTS_STAGE defaults to all" [expr {$CTS_STAGE eq "all"}]
lassign [t_child "${pre}puts \"S=\$CTS_STAGE\"" {UNPU_CTS_STAGE hold}] c o
t_check "UNPU_CTS_STAGE=hold is accepted" [expr {$c == 0 && [t_has $o "S=hold"]}] "exit $c: $o"
lassign [t_child "$pre" {UNPU_CTS_STAGE both}] c o
t_check "UNPU_CTS_STAGE=both is rejected" [expr {$c == 1 && [t_has $o "must be all, tree or hold"]}] "exit $c: $o"
t_check "CTS_STAGE is in the manifest parameter list" [expr {[lsearch -exact $UNPU_PARAM_NAMES CTS_STAGE] >= 0 && [lsearch -exact $UNPU_PARAM_NAMES ROUTE_ACCEPT_HOLD] >= 0}]
# manifest append
set mdir [file join $tmp mapp]
file mkdir $mdir
unpu_manifest_append teststage {"hold_accepted = 1" "hold_endpoint_1 = x"} $mdir
unpu_manifest_append teststage {"more = 2"} $mdir
set fh [open [file join $mdir manifest_teststage.txt] r]; set mt2 [read $fh]; close $fh
t_check "manifest append: lines are appended in order" [expr {$mt2 eq "hold_accepted = 1\nhold_endpoint_1 = x\nmore = 2\n"}] $mt2

# ---- 3. unpu_result format ------------------------------------------------------
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_result st key {a b}" {}] c o
t_check "unpu_result prints exactly 'Info: \[unpu\] RESULT st key = a b'" [expr {[string trim $o] eq "Info: \[unpu\] RESULT st key = a b"}] "got: $o"

# ---- 4. LEF extraction ----------------------------------------------------------
set lef [file join $tmp fake.lef]
set fh [open $lef w]
puts $fh "VERSION 5.8 ;"
puts $fh "SITE CoreSite\n  SIZE 0.56 BY 5.6 ;\nEND CoreSite"
foreach m {alpha feedth feedth3 beta feedth9} {
  puts $fh "MACRO $m\n  CLASS CORE ;\n  SIZE 1 BY 5.6 ;\n  PIN I\n    DIRECTION INPUT ;\n  END I\n  OBS\n  END\nEND $m"
}
puts $fh "END LIBRARY"
close $fh
t_check "count of MACROs in the fake LEF" [expr {[unpu_count_lef_macros $lef] == 5}]
set out [file join $tmp feedth.lef]
set n [unpu_extract_lef_macros $lef {feedth feedth3 feedth9} $out]
t_check "extract returns 3" [expr {$n == 3}] "got $n"
set fh [open $out r]; set txt [read $fh]; close $fh
t_check "header kept (VERSION and SITE before the first MACRO)" [expr {[string first "VERSION 5.8" $txt] == 0 && [string first "SITE CoreSite" $txt] > 0 && [string first "SITE CoreSite" $txt] < [string first "MACRO" $txt]}]
t_check "exactly the three requested MACROs" [expr {[llength [regexp -all -inline -line {^MACRO \S+$} $txt]] == 3 && [string first "MACRO alpha" $txt] < 0 && [string first "MACRO beta" $txt] < 0}]
t_check "each block closed, in the requested order" [expr {[string first "MACRO feedth\n" $txt] < [string first "MACRO feedth3\n" $txt] && [string first "MACRO feedth3\n" $txt] < [string first "MACRO feedth9\n" $txt] && [string first "END feedth9" $txt] > 0}]
t_check "ends with END LIBRARY" [expr {[string match "*END LIBRARY\n" $txt]}]
t_check "MACRO feedth is not confused with feedth3 (prefix)" [expr {[llength [regexp -all -inline -line {^END feedth$} $txt]] == 1}]
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_extract_lef_macros [list $lef] {feedth nosuch} [list [file join $tmp x.lef]]" {}] c o
t_check "a missing macro name dies with a message" [expr {$c == 1 && [t_has $o "Error: \[unpu\]*MACRO nosuch not found"]}] "exit $c: $o"
set dup [file join $tmp dup.lef]
set fh [open $dup w]; puts $fh "VERSION 5.8 ;\nMACRO a\nEND a\nMACRO a\nEND a\nEND LIBRARY"; close $fh
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_extract_lef_macros [list $dup] {a} [list [file join $tmp x.lef]]" {}] c o
t_check "a duplicated macro dies with a message" [expr {$c == 1 && [t_has $o "defined 2 times"]}] "exit $c: $o"
set unc [file join $tmp unclosed.lef]
set fh [open $unc w]; puts $fh "VERSION 5.8 ;\nMACRO a\n  PIN I\n  END I\nEND LIBRARY"; close $fh
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_extract_lef_macros [list $unc] {a} [list [file join $tmp x.lef]]" {}] c o
t_check "a MACRO without its END dies" [expr {$c == 1 && [t_has $o "not closed"]}] "exit $c: $o"

# ---- 5. helpers -----------------------------------------------------------------
t_check "unpu_ensure_dir creates nested directories" [expr {[unpu_ensure_dir [file join $tmp a b c]] eq [file join $tmp a b c] && [file isdirectory [file join $tmp a b c]]}]
t_check "unpu_path_size sums files below a directory" [expr {[unpu_path_size $tmp] > 0 && [unpu_path_size [file join $tmp nosuch]] == -1}]
set sf [file join $tmp sum.txt]
set fh [open $sf w]; puts -nonewline $fh "abc"; close $fh
t_check "unpu_sha256 of 'abc'" [expr {[unpu_sha256 $sf] eq "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}]
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_need_file [list [file join $tmp nosuch.db]] {ss .db}" {}] c o
t_check "unpu_need_file dies naming what is missing" [expr {$c == 1 && [t_has $o "Error: \[unpu\]*ss .db not found"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_check_pass st nm 1 {fine}\nunpu_check_pass st nm2 0 {broken}\nputs NOT_REACHED" {}] c o
t_check "unpu_check_pass: PASS printed, FAIL dies" [expr {$c == 1 && [t_has $o "CHECK st nm PASS fine"] && [t_has $o "CHECK st nm2 FAIL broken"] && [string first NOT_REACHED $o] < 0}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nset UNPU_CHECK_CONTINUE 1\nunpu_check_pass st a 0 x\nunpu_check_pass st b 1 y\nunpu_checks_finish st" {}] c o
t_check "continue mode: all verdicts printed, exit 1 at the end" [expr {$c == 1 && [t_has $o "CHECK st b PASS y"] && [t_has $o "RESULT st checks_failed = 1"]}] "exit $c: $o"


# kit files are read-only: writes under SCL_KIT_ROOT are refused
set kit [file join $tmp fakekit]
file mkdir $kit
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nunpu_ensure_dir [list [file join $kit newdir]]" [list SCL_KIT_ROOT $kit]] c o
t_check "unpu_ensure_dir under SCL_KIT_ROOT is refused" [expr {$c == 1 && [t_has $o "refusing to write or remove*under SCL_KIT_ROOT"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nunpu_extract_lef_macros [list $lef] {feedth} [list [file join $kit out.lef]]" [list SCL_KIT_ROOT $kit]] c o
t_check "LEF extraction into SCL_KIT_ROOT is refused" [expr {$c == 1 && [t_has $o "refusing to write or remove"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_load_params" [list SCL_KIT_ROOT $kit UNPU_WORK [file join $kit work]]] c o
t_check "UNPU_WORK inside SCL_KIT_ROOT is refused" [expr {$c == 1 && [t_has $o "refusing to write or remove"]}] "exit $c: $o"

# manifest: parameters come from params.tcl, checksums from the files
set LOG_DIR [file join $tmp logs]
set mf [unpu_manifest teststage [list $sf] $LOG_DIR]
set fh [open $mf r]; set mtxt [read $fh]; close $fh
t_check "manifest lists a parameter by name" [expr {[string first "DIE_SIZE = 868.0" $mtxt] >= 0 && [string first "ANT_RATIO = 300" $mtxt] >= 0}]
t_check "manifest holds the checksum of the file" [expr {[string first "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  $sf" $mtxt] >= 0}]
t_check "manifest holds date, host, git revision" [expr {[string first "date         = 20" $mtxt] >= 0 && [string first "host         = " $mtxt] >= 0 && [string first "git_rev      = " $mtxt] >= 0}]
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nunpu_manifest bad [list [file join $tmp nosuch.txt]] [list [file join $tmp logs2]]" {}] c o
t_check "manifest dies if a listed file is missing" [expr {$c == 1 && [t_has $o "listed file does not exist"]}] "exit $c: $o"

# version check: found / mismatch / unreadable / skip
lassign [t_child "source [list [file join $here common.tcl]]\nset ::sh_product_version U-2022.12-SP3\nunpu_require_tool_version U-2022.12-SP3\nputs OK" {}] c o
t_check "version match passes" [expr {$c == 0 && [t_has $o "OK"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nset ::sh_product_version V-2023.12-SP4\nunpu_require_tool_version U-2022.12-SP3\nputs NOT_REACHED" {}] c o
t_check "version mismatch dies naming what was found" [expr {$c == 1 && [t_has $o "found version 'V-2023.12-SP4', expected 'U-2022.12-SP3'"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_require_tool_version U-2022.12-SP3\nputs NOT_REACHED" {}] c o
t_check "unreadable version dies" [expr {$c == 1 && [t_has $o "could not be read"]}] "exit $c: $o"
lassign [t_child "source [list [file join $here common.tcl]]\nunpu_require_tool_version U-2022.12-SP3\nputs CONTINUED" {UNPU_SKIP_VERSION_CHECK 1}] c o
t_check "UNPU_SKIP_VERSION_CHECK=1 continues with a Warning" [expr {$c == 0 && [t_has $o "Warning: \[unpu\]*UNPU_SKIP_VERSION_CHECK"] && [t_has $o "CONTINUED"]}] "exit $c: $o"

# item 7: a skipped version check is recorded in the manifest
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nunpu_require_tool_version U-2022.12-SP3\nputs \[unpu_manifest vs {} [list [file join $tmp mvs]]\]" {UNPU_SKIP_VERSION_CHECK 1}] c o
set mp [file join $tmp mvs manifest_vs.txt]
set fh [open $mp r]; set mt [read $fh]; close $fh
t_check "manifest records version_check_skipped = 1 and version_found = unreadable" [expr {[string first "version_check_skipped = 1" $mt] >= 0 && [string first "version_found = unreadable" $mt] >= 0}] $mt
lassign [t_child "source [list [file join $here common.tcl]]\nsource [list [file join $here params.tcl]]\nset ::sh_product_version V-2023.12-SP4\nunpu_require_tool_version U-2022.12-SP3\nunpu_manifest vs2 {} [list [file join $tmp mvs]]" {UNPU_SKIP_VERSION_CHECK 1}] c o
set fh [open [file join $tmp mvs manifest_vs2.txt] r]; set mt [read $fh]; close $fh
t_check "manifest records the version that was found when the check is skipped" [expr {[string first "version_check_skipped = 1" $mt] >= 0 && [string first "version_found = V-2023.12-SP4" $mt] >= 0}] $mt
t_check "manifest of a normal run says version_check_skipped = 0" [expr {[string first "version_check_skipped = 0" [read [open $mf r]]] >= 0}]

# ---- result --------------------------------------------------------------------
file delete -force $tmp
puts "----------------------------------------"
puts "test_common: $npass passed, $nfail failed"
if {$nfail > 0} { puts "TESTS FAILED"; exit 1 }
puts "ALL TESTS PASSED"
exit 0
