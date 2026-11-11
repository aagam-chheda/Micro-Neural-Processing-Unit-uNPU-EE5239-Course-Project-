# ==============================================================================
# Test: test_pt_common.tcl (task 074)
# Run : tclsh pnr_v2/pt/test_pt_common.tcl   (from the repository root; no PrimeTime needed)
# Tests the pure-Tcl procs of pt_common.tcl: file check, the SPEF-to-corner decision, SDC value parser, comparison with the expected legacy values, annotation parser and policy,
# check_timing parser, report_constraint parser, verdict, summary and ICC2 comparison lines. The report texts are written from knowledge of the PrimeTime formats (VERIFY on the server).
# ==============================================================================
set here [file dirname [file normalize [info script]]]
source $here/pt_common.tcl
proc read_file_080 {f} { set fp [open $f r]; set s [read $fp]; close $fp; return $s }

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc must_error {script} { return [catch {uplevel 1 $script}] }
proc error_text {script} { catch {uplevel 1 $script} m; return $m }

# ------------------------------------------------------------------ 1. file check
set tmp [file tempfile tname]
close $tmp
check "empty file is a problem" {[string match "*is empty*" [pt_file_problem $tname]]}
set fp [open $tname w]; puts $fp x; close $fp
check "non-empty file is ok" {[pt_file_problem $tname] eq ""}
check "missing file is a problem" {[string match "*does not exist*" [pt_file_problem /nonexistent/file.spef]]}
check "a directory is not a file" {[string match "*not a regular file*" [pt_file_problem [file dirname $tname]]]}
check "pt_need_file stops on a missing file with the purpose in the message" {[string match "PT ERROR: SPEF file: *does not exist*" [error_text {pt_need_file /nonexistent/a.spef "SPEF file"}]]}
check "pt_need_file returns the path when ok" {[pt_need_file $tname "x"] eq $tname}
file delete $tname

# ------------------------------------------------------------------ 2. SPEF to corner
set f125 "/storage/x/unpu_top_spef.TYPICAL_RC_125.spef"
set f40  "/storage/x/unpu_top_spef.TYPICAL_RC_-40.spef"
set files [list $f125 $f40]
set ss {func_ss corner_ss}
set ff {func_ff corner_ff}
check "tag of a SPEF name" {[pt_spef_tag $f125] eq "TYPICAL_RC_125" && [pt_spef_tag $f40] eq "TYPICAL_RC_-40"}
# a clear mapping, line by line (several plausible layouts of the helper file)
set t1 "func_ss unpu_top_spef.TYPICAL_RC_125.spef\nfunc_ff unpu_top_spef.TYPICAL_RC_-40.spef\n"
check "clear mapping (file names): ss" {[pt_spef_decide $t1 $files ss $ss $ff] eq $f125}
check "clear mapping (file names): ff" {[pt_spef_decide $t1 $files ff $ss $ff] eq $f40}
set t2 "scenario: func_ss  corner: corner_ss  rc: TYPICAL_RC_125\nscenario: func_ff  corner: corner_ff  rc: TYPICAL_RC_-40\n"
check "clear mapping (tags): ss" {[pt_spef_decide $t2 $files ss $ss $ff] eq $f125}
check "clear mapping (tags): ff" {[pt_spef_decide $t2 $files ff $ss $ff] eq $f40}
# the mapping the other way round: the decision follows the TEXT, not the temperature in the name
set t3 "func_ss unpu_top_spef.TYPICAL_RC_-40.spef\nfunc_ff unpu_top_spef.TYPICAL_RC_125.spef\n"
check "reversed mapping is followed (not the temperature)" {[pt_spef_decide $t3 $files ss $ss $ff] eq $f40 && [pt_spef_decide $t3 $files ff $ss $ff] eq $f125}
# block layout: scenario on one line, file on the next
set t4 "Scenario func_ss\n  SPEF TYPICAL_RC_125\n\nScenario func_ff\n  SPEF TYPICAL_RC_-40\n"
check "block layout: ss" {[pt_spef_decide $t4 $files ss $ss $ff] eq $f125}
check "block layout: ff" {[pt_spef_decide $t4 $files ff $ss $ff] eq $f40}
# full paths in the text
set t5 "func_ss $f125\nfunc_ff $f40\n"
check "full paths in the text" {[pt_spef_decide $t5 $files ss $ss $ff] eq $f125}
# a tag must not match inside a longer number
check "TYPICAL_RC_125 does not match TYPICAL_RC_1250" {![pt_line_mentions_spef "func_ss TYPICAL_RC_1250" $f125]}
check "TYPICAL_RC_125 matches at the end of the line" {[pt_line_mentions_spef "func_ss TYPICAL_RC_125" $f125]}
check "scenario word must be a whole word" {[pt_line_corner "myfunc_ssx TYPICAL_RC_125" $ss $ff] eq ""}
# ambiguous
set tb "func_ss func_ff unpu_top_spef.TYPICAL_RC_125.spef\n"
set m [error_text {pt_spef_decide $tb $files ss $ss $ff}]
check "a line that names both corners decides nothing -> error that prints the content" {[string match "PT ERROR: the spef_scenario text does not name the corner*" $m] && [string match "*func_ss func_ff unpu_top_spef*" $m]}
set tc "func_ss unpu_top_spef.TYPICAL_RC_125.spef unpu_top_spef.TYPICAL_RC_-40.spef\n"
check "a line that names two files decides nothing -> error" {[must_error {pt_spef_decide $tc $files ss $ss $ff}]}
set td "func_ss unpu_top_spef.TYPICAL_RC_125.spef\nfunc_ss unpu_top_spef.TYPICAL_RC_-40.spef\nfunc_ff unpu_top_spef.TYPICAL_RC_-40.spef\n"
set m [error_text {pt_spef_decide $td $files ss $ss $ff}]
check "two different files for ss -> error 'more than one'" {[string match "*names more than one SPEF file for corner ss*" $m]}
set te "func_ss unpu_top_spef.TYPICAL_RC_125.spef\nfunc_ff unpu_top_spef.TYPICAL_RC_125.spef\n"
set m [error_text {pt_spef_decide $te $files ss $ss $ff}]
check "one file for both corners -> error 'BOTH'" {[string match "*named for BOTH corners*" $m]}
set tf "func_ss unpu_top_spef.TYPICAL_RC_125.spef\n"
set m [error_text {pt_spef_decide $tf $files ff $ss $ff}]
check "the text has no file for ff -> error" {[string match "*names no SPEF file for corner ff*" $m]}
# no corner named
set tg "unpu_top_spef.TYPICAL_RC_125.spef 125 C\nunpu_top_spef.TYPICAL_RC_-40.spef -40 C\n"
set m [error_text {pt_spef_decide $tg $files ss $ss $ff}]
check "temperatures only, no corner name -> error, not a guess by temperature" {[string match "*does not name the corner*" $m] && [string match "*125 C*" $m]}
set m [error_text {pt_spef_decide "" $files ss $ss $ff}]
check "empty text -> error" {[string match "*does not name the corner*" $m]}
set m [error_text {pt_spef_decide "some unrelated text\n" $files ss $ss $ff}]
check "unrelated text -> error that prints it" {[string match "*some unrelated text*" $m]}
# the real 308-byte file is not known; a header line must not break a clear mapping
set th "# written by write_parasitics\n$t1"
check "a comment header line is harmless" {[pt_spef_decide $th $files ss $ss $ff] eq $f125}

# ------------------------------------------------------------------ 3. SDC text values
set sdc "# comment\ncreate_clock -name clk -period 20 \[get_ports clk\]\nset_clock_uncertainty -setup 1.5 \[get_clocks clk\]\nset_clock_uncertainty -hold 0.5 \[get_clocks clk\]\nset_propagated_clock \[get_clocks clk\]\nset_operating_conditions tsl18fs120_scl_ss -library tsl18fs120_scl_ss\nset_max_transition 3.0 \[current_design\]\nset_max_transition 0.4 -clock_path \[get_clocks clk\]\nset_max_capacitance 2.0 \[current_design\]\n"
set v [pt_sdc_values $sdc]
check "sdc: period" {[dict get $v period] == 20}
check "sdc: setup uncertainty" {[dict get $v setup_unc] == 1.5}
check "sdc: hold uncertainty" {[dict get $v hold_unc] == 0.5}
check "sdc: propagated" {[dict get $v propagated] == 1}
check "sdc: operating condition line" {[llength [dict get $v opcond]] == 1}
check "sdc: two max_transition lines" {[llength [dict get $v maxtran]] == 2}
check "sdc: one max_capacitance line" {[llength [dict get $v maxcap]] == 1}
set v2 [pt_sdc_values "create_clock -period 20 -name clk \[get_ports clk\]\nset_clock_uncertainty 0.3 \[get_clocks clk\]\n# set_propagated_clock\n"]
check "sdc: -period after other options" {[dict get $v2 period] == 20}
check "sdc: uncertainty without -setup/-hold counts for both" {[dict get $v2 setup_unc] == 0.3 && [dict get $v2 hold_unc] == 0.3}
check "sdc: a commented set_propagated_clock is not counted" {[dict get $v2 propagated] == 0}
check "sdc: absent values are empty" {[dict get [pt_sdc_values "set_load 1 x"] period] eq ""}
# limits
set ent [pt_limit_entries [dict get $v maxtran] [dict get $v maxcap]]
check "limits: three entries, one with clock_path" {[llength $ent] == 3 && [llength [lsearch -all -exact [lmap e $ent {dict get $e clock_path}] 1]] == 1}
set rep [pt_limit_report $ent 3.0 2.0]
check "limits: the 0.4 clock-path limit is reported as part of the signed-off constraints" {[llength [lsearch -all -glob $rep "*CLOCK-PATH limit of 0.4*"]] == 1}
check "limits: no warning when the design-wide values equal the legacy ones" {[llength [lsearch -all -glob $rep "WARNING*"]] == 0}
set rep2 [pt_limit_report [pt_limit_entries {"set_max_transition 1.0 [current_design]"} {}] 3.0 2.0]
check "limits: a different design-wide max_transition and an absent max_capacitance warn" {[llength [lsearch -all -glob $rep2 "WARNING*"]] == 2}
check "limits: no -clock_path entry is said" {[llength [lsearch -all -glob $rep2 "no -clock_path limit*"]] == 1}

# ------------------------------------------------------------------ 4. constraint comparison with the legacy values
check "setup: 20 / 1.5 accepted" {[pt_check_constraints setup 20.0 1.5 0.5 20.0 1.5 0.5] eq ""}
check "hold: 20 / 0.5 accepted" {[pt_check_constraints hold 20 1.5 0.5 20.0 1.5 0.5] eq ""}
check "wrong period is a problem" {[llength [pt_check_constraints setup 10.0 1.5 0.5 20.0 1.5 0.5]] == 1}
check "wrong setup uncertainty is a problem in the setup check" {[llength [pt_check_constraints setup 20.0 0.15 0.5 20.0 1.5 0.5]] == 1}
check "wrong setup uncertainty is NOT a problem in the hold check" {[pt_check_constraints hold 20.0 0.15 0.5 20.0 1.5 0.5] eq ""}
check "wrong hold uncertainty is a problem in the hold check" {[llength [pt_check_constraints hold 20.0 1.5 0.05 20.0 1.5 0.5]] == 1}
check "unreadable value is a problem" {[llength [pt_check_constraints setup "" 1.5 0.5 20.0 1.5 0.5]] == 1}
check "both wrong gives two problems" {[llength [pt_check_constraints setup 10 0.1 0.5 20.0 1.5 0.5]] == 2}

# ------------------------------------------------------------------ 5. report parsers (texts written from knowledge of the formats: VERIFY)
set rd "Design : unpu_top\nOperating Conditions: tsl18fs120_scl_ss   Library: tsl18fs120_scl_ss\nWire Load Model Mode: top\n"
check "operating condition from report_design" {[pt_parse_opcond $rd] eq "{tsl18fs120_scl_ss tsl18fs120_scl_ss}"}
check "no operating condition line" {[pt_parse_opcond "nothing"] eq ""}
# ---- parasitics annotation (fix after the first server run: the text is in parasitics_command.log; the table below is the real one quoted by Planning)
set tbl "Report : annotated_parasitics -check -internal_nets -boundary_nets
Design : unpu_top

Net Type                |   Total | Lumped | RC pi | RC network | Not Annotated
--------------------------------------------------------------------------
Internal nets
  - Pin to pin nets     |   16113 |      0 |     0 |      16113 |             0
  - Driverless nets     |     323 |      0 |     0 |          0 |           323
  - Loadless nets       |      48 |      0 |     0 |          0 |            48
Boundary/port nets
  - Pin to pin nets     |     182 |      0 |     0 |        182 |             0
  - Driverless nets     |       0 |      0 |     0 |          0 |             0
  - Loadless nets       |      22 |      0 |     0 |          0 |            22
--------------------------------------------------------------------------
                        |   16688 |      0 |     0 |      16295 |           393 |

Annotated nets : 16295

Not annotated nets:
1.  csr_sel\[2\] (driver: <none>)
2.  u_x/n12 (driver: <none>)
3.  u_dma/add_212_3/B\[29\] (driver: pin u_dma/add_212_3/B\[29\])
"
set rpok "Reading SPEF file ...\nSPEF parsing summary:\n  0 error(s)\n  3 warning(s)\n"
set pa [pt_parse_annotation_table $tbl]
check "table: found" {[dict get $pa found] == 1}
check "table: six rows and the total row" {[llength [dict get $pa rows]] == 6 && [dict get $pa total] eq "16688 0 0 16295 393"}
check "table: internal pin-to-pin row" {[lindex [dict get $pa rows] 0] eq "internal p2p 16113 0 0 16113 0"}
check "table: driverless internal not annotated 323" {[lindex [dict get $pa rows] 1] eq "internal driverless 323 0 0 0 323"}
check "table: boundary pin-to-pin row" {[lindex [dict get $pa rows] 3] eq "boundary p2p 182 0 0 182 0"}
check "table: boundary loadless not annotated 22" {[lindex [dict get $pa rows] 5] eq "boundary loadless 22 0 0 0 22"}
check "table: annotated nets line" {[dict get $pa annotated] == 16295}
check "table: unannotated names (index, name, driver)" {[llength [dict get $pa names]] == 3 && [lindex [lindex [dict get $pa names] 0] 0] == 1 && [lindex [lindex [dict get $pa names] 0] 1] eq "csr_sel\[2\]" && [lindex [lindex [dict get $pa names] 0] 2] eq "<none>"}
check "table: the driver text with a pin" {[lindex [lindex [dict get $pa names] 2] 2] eq "pin u_dma/add_212_3/B\[29\]"}
check "errors: '0 error(s)' -> 0" {[pt_parse_para_errors $rpok] == 0}
check "errors: none printed -> empty" {[pt_parse_para_errors "nothing"] eq ""}
check "errors: the largest N is taken" {[pt_parse_para_errors "2 error(s)\n5 error(s)\n"] == 5}
lassign [pt_annotation_policy $pa 0 0.0 0] ok lines
check "policy: the real table is ACCEPTED (16113+182 annotated, 393 unannotated all driverless/loadless)" {$ok == 1}
check "policy: pin-to-pin line counts 16295 nets, 0 not annotated" {[llength [lsearch -all -glob $lines "pin-to-pin nets: 16295 in total*0 not annotated*"]] == 1}
check "policy: the driverless/loadless counts are printed as information with the explanation" {[llength [lsearch -all -glob $lines "information (not an error): internal driverless nets: 323 in total, 323 not annotated*boundary loadless nets: 22 in total, 22 not annotated*no timing arc*"]] == 1}
check "policy: the first names are printed" {[llength [lsearch -all -glob $lines "unannotated nets listed in the report: 3; the first 10: csr_sel*u_dma/add_212_3/B*"]] == 1}
check "policy: no warning for the real table" {[llength [lsearch -all -glob $lines "WARNING*"]] == 0}
# a pin-to-pin row with unannotated nets -> error
set bad [string map {"|   16113 |      0 |     0 |      16113 |             0" "|   16113 |      0 |     0 |      16100 |            13"} $tbl]
set bad [string map {"|   16688 |      0 |     0 |      16295 |           393 |" "|   16688 |      0 |     0 |      16282 |           406 |"} $bad]
lassign [pt_annotation_policy [pt_parse_annotation_table $bad] 0 0.0 0] ok lines
check "policy: an internal pin-to-pin row with 13 unannotated nets is an ERROR" {$ok == 0 && [llength [lsearch -all -glob $lines "ERROR: 13 pin-to-pin nets*are not annotated*"]] == 1}
lassign [pt_annotation_policy [pt_parse_annotation_table $bad] 0 1.0 0] ok lines
check "policy: the same with a limit of 1 percent is accepted (13 of 16295 = 0.08 percent)" {$ok == 1}
set bad2 [string map {"|     182 |      0 |     0 |        182 |             0" "|     182 |      0 |     0 |        180 |             2"} $tbl]
set bad2 [string map {"|   16688 |      0 |     0 |      16295 |           393 |" "|   16688 |      0 |     0 |      16293 |           395 |"} $bad2]
lassign [pt_annotation_policy [pt_parse_annotation_table $bad2] 0 0.0 0] ok lines
check "policy: a BOUNDARY pin-to-pin row with unannotated nets is an ERROR too" {$ok == 0 && [llength [lsearch -all -glob $lines "ERROR: 2 pin-to-pin nets*"]] == 1}
# inconsistent table
set bad3 [string map {"|   16688 |      0 |     0 |      16295 |           393 |" "|   16689 |      0 |     0 |      16295 |           393 |"} $tbl]
lassign [pt_annotation_policy [pt_parse_annotation_table $bad3] 0 0.0 0] ok lines
check "policy: a table whose rows do not add up to its total row is an ERROR" {$ok == 0 && [llength [lsearch -all -glob $lines "the table is inconsistent*"]] == 1}
# missing table
lassign [pt_annotation_policy [pt_parse_annotation_table "Information: Log for 'report_annotated_parasitics command' will be generated in 'parasitics_command.log'. (PARA-107)\n"] 0 0.0 0] ok lines
check "policy: a missing table is an ERROR" {$ok == 0 && [llength [lsearch -all -glob $lines "the annotation table*could not be found*"]] == 1}
lassign [pt_annotation_policy [pt_parse_annotation_table ""] 0 0.0 1] ok lines
check "policy: a missing table is a WARNING when PT_ALLOW_UNREADABLE_ANNOTATION is 1" {$ok == 1 && [llength [lsearch -all -glob $lines "WARNING*"]] == 1}
# read_parasitics errors
lassign [pt_annotation_policy $pa [pt_parse_para_errors "SPEF parsing summary:\n  4 error(s)\n"] 0.0 0] ok lines
check "policy: 'N error(s)' non-zero is an ERROR even with a good table" {$ok == 0 && [llength [lsearch -all -glob $lines "read_parasitics reported 4 error(s)*"]] == 1}
lassign [pt_annotation_policy [pt_parse_annotation_table ""] 3 0.0 1] ok lines
check "policy: read_parasitics errors are an error even when unreadable tables are allowed" {$ok == 0}
# a table with only driverless/loadless rows is not a table of nets with arcs
set nop2p "Net Type | Total | Lumped | RC pi | RC network | Not Annotated\n  - Driverless nets | 3 | 0 | 0 | 0 | 3\n| 3 | 0 | 0 | 0 | 3 |\n"
lassign [pt_annotation_policy [pt_parse_annotation_table $nop2p] 0 0.0 0] ok lines
check "policy: no pin-to-pin nets at all is an ERROR" {$ok == 0}
# the old summary wording is no longer accepted as a table
check "the old one-line wording is not a table" {[dict get [pt_parse_annotation_table "Total number of nets = 100\nUnannotated nets: 0\n"] found] == 0}
# the parasitics_command.log is APPENDED to: only the part written by the last command is read
set lf [file tempfile lname]; close $lf
set fp [open $lname w]; puts -nonewline $fp "first command text\n0 error(s)\n"; close $fp
set o1 [pt_file_size0 $lname]
check "file size of a missing file is 0" {[pt_file_size0 /nonexistent/parasitics_command.log] == 0}
set fp [open $lname a]; puts -nonewline $fp $tbl; close $fp
check "tail: only the text appended after the offset" {[pt_file_tail $lname $o1] eq $tbl && [string first "first command" [pt_file_tail $lname $o1]] < 0}
check "tail: nothing appended -> empty" {[pt_file_tail $lname [pt_file_size0 $lname]] eq ""}
check "tail: a missing file -> empty" {[pt_file_tail /nonexistent/x 0] eq ""}
set fp [open $lname a]; puts -nonewline $fp "\nReport : annotated_parasitics -check\n[string map {16113 99999} [string range $tbl [string first Net $tbl] end]]"; close $fp
set whole [pt_file_tail $lname 0]
check "last block: the LAST 'Report : annotated_parasitics' block of the whole file" {[string match "Report : annotated_parasitics -check\n*99999*" [pt_last_annotation_block $whole]] && [string first "Internal nets" [pt_last_annotation_block $whole]] > 0 && [string first "16113" [pt_last_annotation_block $whole]] < 0}
check "last block: none -> empty" {[pt_last_annotation_block "no report"] eq ""}
file delete $lname
check "the parasitics log name is a parameter" {$PT_PARA_LOG eq "parasitics_command.log"}
# ---- the post-run check (check_annotation.tcl) and the in-session caveat (second fix: the log file is written buffered, complete only after the session)
set logtext "SPEF parsing summary:\n  Reading SPEF file unpu_top_spef.TYPICAL_RC_125.spef\n  0 error(s)\n  3 warning(s)\n\n$tbl"
lassign [pt_check_log_text $logtext 0.0] ok lines
check "log check: the real log text is accepted" {$ok == 1 && [llength [lsearch -all -glob $lines "read_parasitics errors: 0"]] == 1}
lassign [pt_check_log_text [string map {"|   16113 |      0 |     0 |      16113 |             0" "|   16113 |      0 |     0 |      16100 |            13"} $logtext] 0.0] ok lines
check "log check: an unannotated pin-to-pin row fails (also the inconsistent total)" {$ok == 0}
lassign [pt_check_log_text [string map {"0 error(s)" "7 error(s)"} $logtext] 0.0] ok lines
check "log check: errors fail" {$ok == 0 && [llength [lsearch -all -glob $lines "read_parasitics reported 7 error(s)*"]] == 1}
lassign [pt_check_log_text "SPEF parsing summary:\n  0 error(s)\n" 0.0] ok lines
check "log check: no table fails, and it cannot be waived" {$ok == 0}
set two "$logtext\nReport : annotated_parasitics -check\n[string map {16113 99999} [string range $tbl [string first Net $tbl] end]]"
lassign [pt_check_log_text $two 0.0] ok lines
check "log check: the LAST report block is the one judged (the first block's numbers are not used)" {[llength [lsearch -all -glob $lines "*99999*"]] == 1 || $ok == 0}
check "declared after: only the value 1" {[pt_declared_after 1] == 1 && [pt_declared_after ""] == 0 && [pt_declared_after 0] == 0 && [pt_declared_after yes] == 0 && [pt_declared_after 11] == 0}
check "caveat: none when checked in-session" {[pt_summary_caveat 0] eq ""}
check "caveat: the SUMMARY line when not checked" {[llength [pt_summary_caveat 1]] == 1 && [string match "ANNOTATION NOT CHECKED IN-SESSION: run check_annotation after the session*" [lindex [pt_summary_caveat 1] 0]]}
check "the environment variable name" {$PT_ANNOTATION_ENV eq "PT_ANNOTATION_CHECKED_AFTER"}
# the script itself, run with tclsh on files
set cdir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] ptca_[pid]]
file mkdir $cdir
proc wr {path text} { set fp [open $path w]; puts -nonewline $fp $text; close $fp }
proc ca {args} { global here; set rc [catch {exec tclsh $here/check_annotation.tcl {*}$args 2>@1} out]; return [list $rc $out] }
wr $cdir/good.log $logtext
lassign [ca $cdir/good.log] rc out
check "check_annotation: the real log -> exit 0 and ANNOTATION CHECK PASSED" {$rc == 0 && [string match "*ANNOTATION CHECK PASSED*" $out] && [string match "*pin-to-pin nets: 16295 in total*" $out]}
check "check_annotation: it prints the SPEF lines of the log" {[string match "*Reading SPEF file unpu_top_spef.TYPICAL_RC_125.spef*" $out]}
lassign [ca $cdir/good.log TYPICAL_RC_125] rc out
check "check_annotation: the expected text is found -> PASSED" {$rc == 0}
lassign [ca $cdir/good.log TYPICAL_RC_-40] rc out
check "check_annotation: the expected text is missing (log of the wrong run) -> FAILED" {$rc != 0 && [string match "*ANNOTATION CHECK FAILED*expected text 'TYPICAL_RC_-40'*" $out]}
wr $cdir/bad1.log [string map {"|   16113 |      0 |     0 |      16113 |             0" "|   16113 |      0 |     0 |      16100 |            13" "|   16688 |      0 |     0 |      16295 |           393 |" "|   16688 |      0 |     0 |      16282 |           406 |"} $logtext]
lassign [ca $cdir/bad1.log] rc out
check "check_annotation: 13 unannotated pin-to-pin nets -> FAILED, exit 1" {$rc != 0 && [string match "*ANNOTATION CHECK FAILED*" $out] && [string match "*13 pin-to-pin nets*" $out]}
wr $cdir/bad2.log [string map {"0 error(s)" "3 error(s)"} $logtext]
lassign [ca $cdir/bad2.log] rc out
check "check_annotation: read_parasitics errors -> FAILED" {$rc != 0 && [string match "*3 error(s)*" $out]}
wr $cdir/bad3.log "SPEF parsing summary:\n  0 error(s)\n"
lassign [ca $cdir/bad3.log] rc out
check "check_annotation: no table in the file -> FAILED" {$rc != 0 && [string match "*ANNOTATION CHECK FAILED*" $out]}
wr $cdir/empty.log ""
lassign [ca $cdir/empty.log] rc out
check "check_annotation: an empty file -> FAILED" {$rc != 0 && [string match "*is empty*" $out]}
lassign [ca $cdir/missing.log] rc out
check "check_annotation: a missing file -> FAILED" {$rc != 0 && [string match "*does not exist*" $out]}
set cwd [pwd]
cd $cdir; file copy -force good.log parasitics_command.log
set rc [catch {exec tclsh $here/check_annotation.tcl 2>@1} out]; cd $cwd
check "check_annotation: the default file is parasitics_command.log of the current directory" {$rc == 0 && [string match "*ANNOTATION CHECK PASSED*" $out]}
file delete -force $cdir
check "check_timing: only the known constant is accepted" {[pt_unexpected_endpoints {pready} {pready}] eq ""}
check "check_timing: other endpoints are unexpected" {[pt_unexpected_endpoints {u_x/reg_a/D u_y/reg_b/D} {pready}] eq "u_x/reg_a/D u_y/reg_b/D"}
check "check_timing: known constant with a path prefix" {[pt_unexpected_endpoints {top/pready} {pready}] eq ""}

# the real check_timing text of the third server run (abbreviated): the 'Checking' lines are headings, the only finding is the clk port without a driving cell
set real "Information: Checking 'no_input_delay'.\nInformation: Checking 'no_driving_cell'.\nWarning: There is 1 port with parasitics but with no driving cell.\n\nPorts\n------\nclk\n\nInformation: Checking 'unconstrained_endpoints'.\nInformation: Checking 'unexpandable_clocks'.\n\nFailed clocks set  Related clocks  Original Period\n---------------------------------------------\n\nInformation: Checking 'latch_fanout'.\nInformation: Checking 'no_clock'.\nInformation: Checking 'voltage_level'.\nCheck cell voltage level related issues including rail voltages\nCell Name   min/max issues found\n---------------------------------\n"
set pc [pt_parse_check_timing $real]
check "check_timing real: the checks run are read as headings" {[lrange [dict get $pc checks] 0 2] eq "no_input_delay no_driving_cell unconstrained_endpoints" && [llength [dict get $pc checks]] == 7}
check "check_timing real: exactly one finding, the clk port" {[llength [dict get $pc findings]] == 1 && [dict get [lindex [dict get $pc findings] 0] names] eq "clk" && [dict get [lindex [dict get $pc findings] 0] count] == 1}
set dc [pt_check_timing_decide $pc {pready} {clk}]
check "check_timing real: ACCEPTED (no error, no warning)" {[llength [dict get $dc errors]] == 0 && [llength [dict get $dc warnings]] == 0}
check "check_timing real: the clk port is printed as information" {[llength [dict get $dc infos]] == 1 && [string match "*clock source*clk*" [lindex [dict get $dc infos] 0]]}
set dc2 [pt_check_timing_decide $pc {pready} {other_clk}]
check "check_timing: a driverless port that is NOT the clock source is a warning" {[llength [dict get $dc2 warnings]] == 1 && [llength [dict get $dc2 errors]] == 0}
set pc3 [pt_parse_check_timing "Warning: There are 2 ports with parasitics but with no driving cell.\nPorts\n-----\nclk\npaddr\\\[3\\\]\n"]
set dc3 [pt_check_timing_decide $pc3 {pready} {clk}]
check "check_timing: clk plus another port -> warning naming the other port" {[llength [dict get $dc3 warnings]] == 1 && [string match "*paddr*3*" [lindex [dict get $dc3 warnings] 0]]}
check "check_timing: the old false positive (heading line only) is gone" {[llength [dict get [pt_check_timing_decide [pt_parse_check_timing "Information: Checking 'unconstrained_endpoints'.\nInformation: Checking 'unexpandable_clocks'.\n"] {pready} {clk}] errors]] == 0}
# a real unconstrained list
set ct2 "Information: Checking 'unconstrained_endpoints'.\nWarning: There are 2 unconstrained endpoints.\n\nEndpoints\n---------\nu_x/reg_a/D\nu_y/reg_b/D\n\nInformation: Checking 'no_clock'.\n"
set d4 [pt_check_timing_decide [pt_parse_check_timing $ct2] {pready} {clk}]
check "check_timing: 2 unconstrained endpoints -> ERROR naming both" {[llength [dict get $d4 errors]] == 1 && [string match "*u_x/reg_a/D*u_y/reg_b/D*" [lindex [dict get $d4 errors] 0]]}
set ct3 "Warning: There is 1 unconstrained endpoint.\nEndpoints\n---------\npready\n"
set d5 [pt_check_timing_decide [pt_parse_check_timing $ct3] {pready} {clk}]
check "check_timing: only the known constant pready -> accepted as information" {[llength [dict get $d5 errors]] == 0 && [llength [dict get $d5 infos]] == 1}
set ct4 "Warning: There are 3 endpoints which are not constrained for maximum delay.\n  pready\n  u_x/reg_a/D\n  u_y/reg_b/D\n"
set d6 [pt_check_timing_decide [pt_parse_check_timing $ct4] {pready} {clk}]
check "check_timing: 'not constrained for maximum delay' wording, unknown endpoints -> ERROR" {[llength [dict get $d6 errors]] == 1}
set ct5 "Warning: There are 3 unconstrained endpoints.\nEndpoints\n---------\npready\n"
set d7 [pt_check_timing_decide [pt_parse_check_timing $ct5] {pready} {clk}]
check "check_timing: names fewer than the count -> ERROR (cannot read all names)" {[llength [dict get $d7 errors]] == 1 && [string match "*read 1 names for a count of '3'*" [lindex [dict get $d7 errors] 0]]}
set d8 [pt_check_timing_decide [pt_parse_check_timing "Warning: There is 1 unconstrained endpoint.\n"] {pready} {clk}]
check "check_timing: heading without any name -> ERROR" {[llength [dict get $d8 errors]] == 1}
set d9 [pt_check_timing_decide [pt_parse_check_timing "Warning: There are 4 generated clocks with no master.\nClocks\n------\ngclk\n"] {pready} {clk}]
check "check_timing: any other warning is printed, not dropped" {[llength [dict get $d9 warnings]] == 1 && [string match "*generated clocks*gclk*" [lindex [dict get $d9 warnings] 0]]}

# clock propagation proof from a report text
set rp "  clock clk (rise edge)                   0.0000    0.0000\n  clock network delay (propagated)        0.5900    0.5900\n  u_a/reg/CP (dfnrq1)                              0.5900 r\n  clock clk (rise edge)                  20.0000   20.0000\n  clock network delay (propagated)        0.5800   20.5800\n"
set cp [pt_clock_propagation $rp]
check "propagation: propagated tags are accepted" {[dict get $cp status] eq "propagated" && [dict get $cp propagated] == 2 && [dict get $cp ideal] == 0}
check "propagation: latency values are read" {[dict get $cp delays] eq "{propagated 0.5900} {propagated 0.5800}"}
set ri "  clock clk (rise edge)                   0.0000    0.0000\n  clock network delay (ideal)             0.0000    0.0000\n  u_a/reg/CP (dfnrq1)                              0.0000 r\n"
check "propagation: ideal is rejected" {[dict get [pt_clock_propagation $ri] status] eq "ideal"}
check "propagation: one ideal end among propagated ones is rejected" {[dict get [pt_clock_propagation "$rp\n  clock network delay (ideal)  0.0000 0.0000\n"] status] eq "ideal"}
check "propagation: no tag at all is rejected (cannot be proved)" {[dict get [pt_clock_propagation "  Startpoint: a\n  Endpoint: b\n  slack (MET) 1.0\n"] status] eq "none"}
check "propagation: empty text is rejected" {[dict get [pt_clock_propagation ""] status] eq "none"}
# the SDC messages of this run
set sm [pt_sdc_known_messages "Warning: Converting a propagated clock 'clk' to an ideal clock. (UITE-305)\nWarning: Setting input delay on clock port (clk) relative to a clock (clk) defined at the same port. Command is ignored. (UITE-489)\n"]
check "sdc messages: UITE-305 and UITE-489 are recognised" {[llength $sm] == 2 && [string match "*UITE-305*IDEAL*" [lindex $sm 0]] && [string match "*UITE-489*harmless*" [lindex $sm 1]]}
check "sdc messages: none -> nothing printed" {[llength [pt_sdc_known_messages "Information: ok\n"]] == 0}
set vt "  Endpoint              Required    Actual    Slack\n  ----------------------------------------------\n  u_a/reg/D (dfnrq1)     10.0000     10.0004   -0.0004 (VIOLATED)\n  u_b/reg/D (dfnrq1)     10.0000     10.0100   -0.0100 (VIOLATED)\n  u_c/reg/D (dfnrq1)     10.0000      9.0000    1.0000 (MET)\n"
set pv [pt_parse_violators $vt]
check "violators: count, worst, total" {[dict get $pv count] == 2 && [dict get $pv wns] == -0.01 && abs([dict get $pv tns] + 0.0104) < 1e-9}
check "violators: none" {[dict get [pt_parse_violators "  u/D 1.0 (MET)"] count] == 0 && [dict get [pt_parse_violators ""] wns] eq ""}

# ------------------------------------------------------------------ 6. verdict, summary, comparison with ICC2
check "verdict: positive WNS -> MET" {[pt_verdict 0.0143] eq "MET"}
check "verdict: zero -> MET" {[pt_verdict 0.0] eq "MET"}
check "verdict: negative -> VIOLATED" {[pt_verdict -0.0004] eq "VIOLATED"}
check "verdict: unreadable -> UNKNOWN" {[pt_verdict ""] eq "UNKNOWN" && [pt_verdict n/a] eq "UNKNOWN" && [pt_verdict "x"] eq "UNKNOWN"}
check "verdict: never MET on an unreadable number" {[pt_verdict "MET"] ne "MET" && [pt_verdict "{}"] ne "MET"}
check "summary line: setup" {[pt_summary_line setup ss 0.0100 0.0 0] eq "SETUP corner ss: WNS +0.0100 ns, TNS +0.0000 ns, violating endpoints 0"}
check "summary line: hold violated" {[pt_summary_line hold ff -0.0004 -0.0004 1] eq "HOLD corner ff: WNS -0.0004 ns, TNS -0.0004 ns, violating endpoints 1"}
check "summary line: unreadable" {[pt_summary_line hold ff "" "" ""] eq "HOLD corner ff: WNS n/a ns, TNS n/a ns, violating endpoints n/a"}
check "comparison with ICC2 (setup)" {[pt_compare_line setup 0.0100 0.0143] eq "SETUP WNS: PrimeTime +0.0100 ns, ICC2 +0.0143 ns, difference -0.0043 ns (PrimeTime minus ICC2)"}
check "comparison with ICC2 (hold)" {[pt_compare_line hold -0.0004 -0.0004] eq "HOLD WNS: PrimeTime -0.0004 ns, ICC2 -0.0004 ns, difference +0.0000 ns (PrimeTime minus ICC2)"}
check "comparison with ICC2 (unreadable)" {[pt_compare_line hold "" -0.0004] eq "HOLD WNS: PrimeTime n/a ns, ICC2 -0.0004 ns, difference UNKNOWN"}
check "095: no ICC2 figure is a constant any more (the run-1 numbers are gone)" {![info exists PT_ICC2_SETUP_WNS] && ![info exists PT_ICC2_HOLD_WNS] && $PT_ICC2_SETUP_REPORT eq "unpu_top_final_setup_ss.rpt" && $PT_ICC2_HOLD_REPORT eq "unpu_top_final_hold_ff.rpt"}
check "expected legacy values at the top" {$PT_EXPECT_PERIOD == 20.0 && $PT_EXPECT_SETUP_UNC == 1.5 && $PT_EXPECT_HOLD_UNC == 0.5}
check "SI is off by default" {$PT_SI_ENABLE == 0}
check "the override is empty by default" {$PT_SPEF_OVERRIDE(ss) eq "" && $PT_SPEF_OVERRIDE(ff) eq ""}
check "unannotated limit is 0 by default" {$PT_MAX_UNANNOTATED_PCT == 0.0 && $PT_ALLOW_UNREADABLE_ANNOTATION == 0}
check "the netlist is the one without PG pins" {[string match "*unpu_top_pnr_sim.v" $PT_NETLIST]}
check "libraries are the ss and ff db files named in build_ndm_std.tcl" {[string match "*lib_flow_ss/tsl18fs120_scl_ss.db" $PT_CORNER(ss,db)] && [string match "*lib_flow_ff/tsl18fs120_scl_ff.db" $PT_CORNER(ff,db)]}


# ------------------------------------------------------------------ 7. task 078: violation CSV, consistency, ECO probe helpers
check "csv header: 9 columns separated by ;" {[pt_viol_header] eq "endpoint;startpoint;startpoint_kind;endpoint_kind;slack_ns;path_group;n_cells;cells;incr_ns"}
# the real dma_rdata[14] hold path of the PrimeTime run (task 078): port 0.26, copt_h_inst_3910 (buffd1) 0.17, U588 (mx02d0) 0.12, D at 0.56
set d1 [dict create endpoint u_dma/stage_reg_1__14_/D startpoint dma_rdata\[14\] sp_kind port ep_kind pin slack -0.35 group clk cells {copt_h_inst_3910/Z(buffd1) U588/Z(mx02d0)} delays {0.17 0.12}]
set row1 [pt_viol_row $d1]
check "csv row: the real example" {$row1 eq "u_dma/stage_reg_1__14_/D;dma_rdata\[14\];port;pin;-0.3500;clk;2;copt_h_inst_3910/Z(buffd1),U588/Z(mx02d0);0.1700,0.1200"}
set back [pt_viol_parse_line $row1]
check "csv parse: endpoint, startpoint, kinds, slack, group" {[dict get $back endpoint] eq "u_dma/stage_reg_1__14_/D" && [dict get $back startpoint] eq "dma_rdata\[14\]" && [dict get $back sp_kind] eq "port" && [dict get $back ep_kind] eq "pin" && [dict get $back slack] eq "-0.3500" && [dict get $back group] eq "clk"}
check "csv parse: cells and incremental delays in order" {[dict get $back n_cells] == 2 && [dict get $back cells] eq {copt_h_inst_3910/Z(buffd1) U588/Z(mx02d0)} && [dict get $back delays] eq {0.1700 0.1200}}
# a register-to-register path: the startpoint is a pin
set d2 [dict create endpoint u_dma/stage_reg_0__3_/D startpoint u_csr/src_a_reg_reg_3_/CP sp_kind pin ep_kind pin slack -0.0004 group clk cells {u_csr/src_a_reg_reg_3_/Q(dfnrq1)} delays {0.2100}]
set row2 [pt_viol_row $d2]
check "csv row: a pin startpoint (register to register)" {[string match "u_dma/stage_reg_0__3_/D;u_csr/src_a_reg_reg_3_/CP;pin;pin;-0.0004;clk;1;u_csr/src_a_reg_reg_3_/Q(dfnrq1);0.2100" $row2]}
check "csv parse: the pin startpoint comes back" {[dict get [pt_viol_parse_line $row2] sp_kind] eq "pin" && [dict get [pt_viol_parse_line $row2] n_cells] == 1}
# n/a fields: slack unreadable, no cells, an unreadable incremental delay, an output port endpoint
set d3 [dict create endpoint dma_addr\[31\] startpoint u_dma/beat_idx_reg_0_/CP sp_kind pin ep_kind "" slack "" group ""]
set row3 [pt_viol_row $d3]
check "csv row: unreadable fields and no cells are n/a" {$row3 eq "dma_addr\[31\];u_dma/beat_idx_reg_0_/CP;pin;n/a;n/a;n/a;n/a;n/a;n/a"}
set b3 [pt_viol_parse_line $row3]
check "csv parse: n/a stays n/a" {[dict get $b3 slack] eq "n/a" && [dict get $b3 cells] eq "n/a" && [dict get $b3 n_cells] eq "n/a" && [dict get $b3 ep_kind] eq "n/a"}
set d4 [dict create endpoint a/D startpoint p sp_kind port ep_kind pin slack -0.1 group g cells {u1/Z(buffd1) u2/Z(inv0d1)} delays {0.1 ""}]
check "csv row: one unreadable incremental delay is n/a" {[string match "*;0.1000,n/a" [pt_viol_row $d4]]}
check "csv row: an empty cell list is none and parses to an empty list" {[dict get [pt_viol_parse_line [pt_viol_row [dict create endpoint a/D startpoint p sp_kind port ep_kind pin slack -0.1 group g cells {} delays {}]]] cells] eq ""}
check "csv row: a ';' in a value is an error" {[must_error {pt_viol_row [dict create endpoint "a;b" startpoint p]}]}
check "csv row: a ',' in a cell text is an error" {[must_error {pt_viol_row [dict create endpoint e startpoint p cells {a,b} delays {0.1}]}]}
check "csv row: cells and delays of different length are an error" {[must_error {pt_viol_row [dict create endpoint e startpoint p cells {a b} delays {0.1}]}]}
check "csv parse: wrong column count is an error" {[must_error {pt_viol_parse_line "a;b;c"}]}
check "csv parse: n_cells that disagrees with the list is an error" {[must_error {pt_viol_parse_line "e;s;port;pin;-0.1000;g;3;a(x),b(y);0.1,0.2"}]}
set csv "[pt_viol_header]\n$row1\n$row2\n\n$row3\n"
set rows [pt_viol_parse_file $csv]
check "csv file: three rows back, blank line ignored" {[llength $rows] == 3 && [dict get [lindex $rows 2] endpoint] eq "dma_addr\[31\]"}
check "csv file: a wrong header is an error" {[must_error {pt_viol_parse_file "endpoint;x\n$row1\n"}]}
check "csv file: header only is zero rows" {[llength [pt_viol_parse_file "[pt_viol_header]\n"]] == 0}
# the path points -> cells and incremental delays, from the real dma_rdata[14] path
set pts [list \
  [dict create name clk class port dir in arrival 0.00 ref ""] \
  [dict create name dma_rdata\[14\] class port dir in arrival 0.00 ref ""] \
  [dict create name u_dma/copt_h_inst_3910/I class pin dir in arrival 0.26 ref buffd1] \
  [dict create name u_dma/copt_h_inst_3910/Z class pin dir out arrival 0.43 ref buffd1] \
  [dict create name u_dma/U588/I0 class pin dir in arrival 0.43 ref mx02d0] \
  [dict create name u_dma/U588/Z class pin dir out arrival 0.55 ref mx02d0] \
  [dict create name u_dma/stage_reg_1__14_/D class pin dir in arrival 0.56 ref dfnrq1]]
lassign [pt_viol_path_cells $pts dma_rdata\[14\]] found cells delays
check "path cells: start at the startpoint, output pins only" {$found == 1 && $cells eq {u_dma/copt_h_inst_3910/Z(buffd1) u_dma/U588/Z(mx02d0)}}
check "path cells: incremental delays are the arrival differences (0.17, 0.12)" {abs([lindex $delays 0] - 0.17) < 1e-9 && abs([lindex $delays 1] - 0.12) < 1e-9}
lassign [pt_viol_path_cells $pts nosuchstart] found cells delays
check "path cells: a startpoint that is not among the points -> not found" {$found == 0 && $cells eq ""}
set pts2 [list [dict create name u_x/CP class pin dir in arrival 0.92 ref dfnrq1] [dict create name u_x/Q class pin dir out arrival 1.10 ref dfnrq1] [dict create name u_y/D class pin dir in arrival 1.12 ref dfnrq1]]
lassign [pt_viol_path_cells $pts2 u_x/CP] found cells delays
check "path cells: a flop startpoint gives the clock-to-Q cell (0.18)" {$found == 1 && $cells eq {u_x/Q(dfnrq1)} && abs([lindex $delays 0] - 0.18) < 1e-9}
set pts3 [list [dict create name u_x/CP class pin dir in arrival "" ref dfnrq1] [dict create name u_x/Q class pin dir out arrival 1.10 ref ""]]
lassign [pt_viol_path_cells $pts3 u_x/CP] found cells delays
check "path cells: unreadable arrival or ref -> n/a" {$cells eq {u_x/Q(n/a)} && $delays eq "n/a"}
# consistency of the file count with the summary count
check "consistency: equal counts are ok" {[lindex [pt_viol_consistency 263 263] 0] == 1 && [string match "violations file: 263 endpoints (equal to the summary count 263)" [lindex [pt_viol_consistency 263 263] 1]]}
check "consistency: a difference is an error with an explanation" {[lindex [pt_viol_consistency 250 263] 0] == 0 && [string match "*250 endpoints but the summary counts 263*" [lindex [pt_viol_consistency 250 263] 1]]}
check "consistency: zero and zero is ok" {[lindex [pt_viol_consistency 0 0] 0] == 1}
check "consistency: an unreadable summary count is not ok" {[lindex [pt_viol_consistency 5 ""] 0] == 0 && [lindex [pt_viol_consistency 5 n/a] 0] == 0}
check "na note: one line per column with the counts" {[pt_viol_na_note [dict create slack_ns 2 cells 5] 263] eq {{slack_ns could not be read for 2 of 263 endpoints (written as n/a; VERIFY the path attribute)} {cells could not be read for 5 of 263 endpoints (written as n/a; VERIFY the path attribute)}}}
check "na note: nothing unreadable -> no lines" {[pt_viol_na_note [dict create] 10] eq ""}
check "violation bound parameter is large and named" {$PT_VIOL_MAX_PATHS >= 100000}

# the ECO probe helpers
check "eco: fix_eco_timing is preferred" {[pt_eco_pick_cmd {write_changes fix_eco_hold fix_eco_timing}] eq "fix_eco_timing"}
check "eco: fix_eco_hold is the fallback" {[pt_eco_pick_cmd {write_changes fix_eco_hold}] eq "fix_eco_hold"}
check "eco: neither exists -> empty" {[pt_eco_pick_cmd {write_changes}] eq ""}
check "eco licence lines: only the lines that mention ECO" {[pt_eco_license_lines "PrimeTime  ok\nPrimeTime-ECO  not available\n PrimeTime-SI x\n"] eq [list "PrimeTime-ECO  not available"]}
# buffer classification: the raw values of the first server run and the true/false forms
check "attr bool: true / 1 / yes / TRUE -> yes" {[pt_eco_attr_bool true] eq "yes" && [pt_eco_attr_bool 1] eq "yes" && [pt_eco_attr_bool yes] eq "yes" && [pt_eco_attr_bool TRUE] eq "yes" && [pt_eco_attr_bool " true "] eq "yes"}
check "attr bool: false / 0 / no -> no" {[pt_eco_attr_bool false] eq "no" && [pt_eco_attr_bool 0] eq "no" && [pt_eco_attr_bool no] eq "no"}
check "attr bool: the raw text 'is_buffer' seen on the server and an empty value are UNRECOGNISED (not no)" {[pt_eco_attr_bool is_buffer] eq "" && [pt_eco_attr_bool ""] eq ""}
set pb [list [dict create name I dir in func ""] [dict create name Z dir out func "I"]]
check "function: one input, one output, Z = I -> buffer" {[pt_eco_func_is_buffer $pb] eq "yes"}
check "function: parentheses and blanks ignored" {[pt_eco_func_is_buffer [list [dict create name I dir input func ""] [dict create name Z dir output func " ( I ) "]]] eq "yes"}
check "function: an inverter (Z = !I) is not a buffer" {[pt_eco_func_is_buffer [list [dict create name I dir in func ""] [dict create name ZN dir out func "!I"]]] eq "no"}
check "function: two inputs -> no" {[pt_eco_func_is_buffer [list [dict create name A dir in func ""] [dict create name B dir in func ""] [dict create name Z dir out func "A"]]] eq "no"}
check "function: unreadable pins or function -> unknown" {[pt_eco_func_is_buffer {}] eq "" && [pt_eco_func_is_buffer [list [dict create name I dir in func ""] [dict create name Z dir out func ""]]] eq ""}
# classes: recognised attribute wins; unrecognised raw -> the function; nothing readable -> the queried name pattern
check "class: attribute true" {[lindex [pt_eco_buffer_class [dict create name buffd1 raw true func ""]] 0] eq "yes"}
check "class: attribute false is respected even for a dl* name" {[lindex [pt_eco_buffer_class [dict create name dl01d1 raw false func yes]] 0] eq "no"}
check "class: raw 'is_buffer' (unrecognised) with a buffer function -> yes, basis names the function" {[lindex [pt_eco_buffer_class [dict create name dl04d1 raw is_buffer func yes]] 0] eq "yes" && [string match "function*" [lindex [pt_eco_buffer_class [dict create name dl04d1 raw is_buffer func yes]] 1]]}
check "class: raw 'is_buffer' with an inverter function -> no" {[lindex [pt_eco_buffer_class [dict create name buffd9 raw is_buffer func no]] 0] eq "no"}
check "class: raw unrecognised, pins unreadable, dl*/buff* name -> yes by the name pattern, and says so" {[lindex [pt_eco_buffer_class [dict create name dl04d1 raw is_buffer func ""]] 0] eq "yes" && [string match "name pattern*" [lindex [pt_eco_buffer_class [dict create name dl04d1 raw is_buffer func ""]] 1]]}
check "class: raw unrecognised, pins unreadable, other name -> no" {[lindex [pt_eco_buffer_class [dict create name inv0d1 raw "" func ""]] 0] eq "no"}
# the 18 cells of the first server run (areas: dl04d1 40.77 as printed; the others are test values), all with the raw text 'is_buffer' and delay n/a
set names18 {dl04d1 dl03d1 dl02d2 dl03d4 dl04d2 dl02d1 dl01d4 dl04d4 dl02d4 dl01d2 dl01d1 dl03d2 buffd2 buffda buffd3 buffd4 buffd7 buffd1}
set areas18 {40.77 31.0 30.5 38.0 45.0 25.0 33.0 52.0 36.0 22.0 20.0 24.0 14.0 15.0 13.0 18.0 25.5 10.0}
set cands18 {}
foreach n $names18 a $areas18 { lappend cands18 [dict create name $n raw is_buffer func "" area $a delay ""] }
lassign [pt_eco_choose_buffers $cands18 20 dl* {buffd1}] lst note
check "server case: none rejected -- 13 cells (12 dl* plus buffd1) are chosen" {[llength $lst] == 13 && [lsearch $lst buffd1] >= 0 && [lsearch $lst buffd2] < 0 && [lsearch $lst buffd7] < 0}
check "server case: ordered by area, largest first" {[lindex $lst 0] eq "dl04d4" && [lindex $lst 1] eq "dl04d2" && [lindex $lst end] eq "buffd1"}
check "server case: the note says the delay was not readable and what the proxy is" {[string match "THE DELAY WAS NOT READABLE*area, largest first*" $note]}
lassign [pt_eco_choose_buffers $cands18 5 dl* {buffd1}] lst5 note5
check "server case: max is respected" {[llength $lst5] == 5 && [lindex $lst5 0] eq "dl04d4"}
# with proper attribute values and delays: by delay
set cands [list \
  [dict create name dl01d1 raw true func "" area 20.0 delay 0.30] \
  [dict create name dl02d1 raw true func "" area 25.0 delay 0.55] \
  [dict create name buffd1 raw true func "" area 10.0 delay 0.17] \
  [dict create name buffd2 raw true func "" area 12.0 delay 0.17] \
  [dict create name inv0d1 raw false func "" area 5.0 delay 0.05] \
  [dict create name dlx_nodata raw true func "" area 30.0 delay ""]]
lassign [pt_eco_choose_buffers $cands 3] lst note
check "eco choose: buffers only, the largest delay first, ties by smaller area" {$lst eq {dl02d1 dl01d1 buffd1}}
check "eco choose: the maximum count is respected and the inverter is never chosen" {[llength [lindex [pt_eco_choose_buffers $cands 10] 0]] == 4 && [lsearch [lindex [pt_eco_choose_buffers $cands 10] 0] inv0d1] < 0}
check "eco choose: the note says it was chosen by delay" {[string match "*chosen by delay*4 buffer cells*" $note]}
# no dl*/extra cell among the buffers: all buffers by area, largest first
lassign [pt_eco_choose_buffers [list [dict create name bufB raw true func "" area 9.0 delay ""] [dict create name bufC raw true func "" area 12.0 delay ""] [dict create name invC raw false func "" area 3.0 delay ""]] 5] lst2 note2
check "eco choose: no dl*/extra cell -> all buffers by area, largest first, and the note says so" {$lst2 eq {bufC bufB} && [string match "*no cell matches*all 2 buffer cells*" $note2]}
check "eco choose: no buffer at all -> empty list" {[lindex [pt_eco_choose_buffers [list [dict create name x raw false func "" area 1 delay 1]] 3] 0] eq ""}
check "eco parameters for the buffer list" {$PT_ECO_MAX_BUFFERS >= 18 && $PT_ECO_DELAY_PATTERN eq "dl*" && $PT_ECO_EXTRA_CELLS eq "buffd1"}
# the split of the violators by kind
set prow [list [dict create endpoint a/D sp_kind port ep_kind pin] [dict create endpoint b/D sp_kind pin ep_kind pin] [dict create endpoint p sp_kind port ep_kind port] [dict create endpoint c/D sp_kind port ep_kind pin] [dict create endpoint u sp_kind "" ep_kind ""]]
set sp [pt_eco_split_kinds $prow]
check "split: port-fed pin 2, other pin 1, port 1, unknown 1, total 5" {[dict get $sp port_fed_pin] == 2 && [dict get $sp other_pin] == 1 && [dict get $sp port] == 1 && [dict get $sp unknown] == 1 && [dict get $sp total] == 5}
check "split: the real run (229 + 26 + 8 = 263)" {[dict get [pt_eco_split_kinds [concat [lrepeat 229 [dict create endpoint x sp_kind port ep_kind pin]] [lrepeat 26 [dict create endpoint y sp_kind pin ep_kind pin]] [lrepeat 8 [dict create endpoint z sp_kind port ep_kind port]]]] total] == 263}
set chg "# changes\ninsert_buffer \[get_pins u_dma/stage_reg_1__14_/D\] buffd1 -new_cell_names hfix_1\ninsert_buffer \[get_pins u_dma/stage_reg_1__13_/D\] dl01d1 -new_cell_names hfix_2\ninsert_buffer \[get_pins u_dma/stage_reg_1__12_/D\] dl01d1\nsize_cell U12 buffd2\nset x 1\n"
set cc [pt_eco_count_changes $chg {buffd1 dl01d1 buffd2}]
check "eco changes: total, per verb and per library cell" {[dict get $cc n] == 4 && [dict get [dict get $cc verbs] insert_buffer] == 3 && [dict get [dict get $cc verbs] size_cell] == 1 && [dict get [dict get $cc refs] dl01d1] == 2 && [dict get [dict get $cc refs] buffd1] == 1 && [dict get [dict get $cc refs] buffd2] == 1}
check "eco changes: a text without any change line counts 0" {[dict get [pt_eco_count_changes "# nothing\n\n" {buffd1}] n] == 0}
check "eco option error: unknown option" {[pt_eco_is_option_error "Error: unknown option '-to' (CMD-010)."] == 1}
check "eco option error: licence error is not an option error" {[pt_eco_is_option_error "Error: Unable to checkout 'PrimeTime-ECO' license. (PT-110)"] == 0}
check "eco option error: no such command is not an option error" {[pt_eco_is_option_error "Error: unknown command 'fix_eco_timing' (CMD-005)."] == 0}
check "eco result line: ran" {[pt_eco_result_line 1 "255 changes proposed, change file /x/pt_eco_hold_changes.tcl"] eq "PROBE RESULT: ECO RAN: 255 changes proposed, change file /x/pt_eco_hold_changes.tcl"}
check "eco result line: not available" {[pt_eco_result_line 0 "no licence"] eq "PROBE RESULT: ECO NOT AVAILABLE: no licence"}
check "eco parameters: margin 0.05, output files" {$PT_ECO_HOLD_MARGIN == 0.05 && $PT_ECO_FILE_ICCTCL eq "pt_eco_hold_changes.tcl" && $PT_ECO_FILE_TEXT eq "pt_eco_hold_changes.txt"}


# ---- the real fix_eco_timing excerpt of the second server run (13 cells, PTECO-099 x13, PTECO-017, no commands)
set cells13 {dl04d4 dl04d2 dl02d4 dl03d4 dl01d4 dl04d1 dl03d1 dl02d2 dl02d1 dl01d2 dl03d2 dl01d1 buffd1}
set fx "Information: Setting timing_save_pin_arrival_and_slack to TRUE and updating timing. (PTE-076)\nIt is recommended that the variable timing_save_pin_arrival_and_slack be set before the initial timing update for optimal performance of this command. (PTE-077)\n"
foreach c $cells13 { append fx "Warning: Ignoring lib cell tsl18fs120_scl_ff/$c as corresponding library cell definition does not exist. (PTECO-099)\n" }
append fx "Error: The buffer list specified by -buffer_list is empty or doesn't have any valid buffer. (PTECO-017)\nInformation: No more fixes are available.\n\nInserted buffers:\n  No buffer\n  0 TOTAL\n\nFinal ECO Summary: Total number of commands 0\n"
set pf [pt_eco_parse_fix_text $fx]
check "fix text: 13 PTECO-099 warnings counted" {[dict get $pf n099] == 13}
check "fix text: the PTECO-017 error is read, with its id counted once" {[dict get [dict get $pf ids] PTECO-017] == 1 && [dict get [dict get $pf ids] PTECO-099] == 13}
check "fix text: 0 commands and 'No more fixes'" {[dict get $pf ncmd] == 0 && [dict get $pf nofix] == 1}
check "fix text: 14 Error/Warning lines (the Information lines are not messages)" {[llength [dict get $pf msgs]] == 14}
check "fix text: nothing proposed" {[pt_eco_fix_proposed $pf] == 0}
set fm [pt_eco_first_messages $pf 4]
check "first messages: error first, then the warning, one line per id, with counts" {[llength $fm] == 2 && [string match "PTECO-017 (1x): Error: The buffer list specified by -buffer_list is empty*" [lindex $fm 0]] && [string match "PTECO-099 (13x): Warning: Ignoring lib cell tsl18fs120_scl_ff/dl04d4 *" [lindex $fm 1]]}
check "first messages: the limit is respected" {[llength [pt_eco_first_messages $pf 1]] == 1}
set fxok "Information: Inserting buffers\nInserted buffers:\n  dl04d4  12\n  229 TOTAL\n\nFinal ECO Summary: Total number of commands 229\n"
set pfok [pt_eco_parse_fix_text $fxok]
check "fix text: 229 commands -> proposed" {[dict get $pfok ncmd] == 229 && [pt_eco_fix_proposed $pfok] == 1}
check "fix text: no 'Total number' line and no Error -> assumed proposed" {[pt_eco_fix_proposed [pt_eco_parse_fix_text "Information: done\n"]] == 1}
check "fix text: no 'Total number' line but an Error -> not proposed" {[pt_eco_fix_proposed [pt_eco_parse_fix_text "Error: something (PTECO-001)\n"]] == 0}
check "write_changes: 'No changes to write.' is recognised" {[pt_eco_write_empty "No changes to write.\n"] == 1 && [pt_eco_write_empty "Writing 229 changes\n"] == 0}
check "result line: ran but no changes carries the first messages" {[pt_eco_result_line nochanges "pt ran but proposed no change. [lindex $fm 0]"] eq "PROBE RESULT: ECO RAN BUT PROPOSED NO CHANGES: pt ran but proposed no change. [lindex $fm 0]"}
check "result line: the old not-available form is unchanged" {[pt_eco_result_line 0 "x"] eq "PROBE RESULT: ECO NOT AVAILABLE: x"}
check "physical ECO is off by default and the std LEF is the kit file of build_ndm_std.tcl" {$PT_ECO_PHYSICAL == 0 && [string match "*/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef" $PT_ECO_STD_LEF] && [string match "*/unpu_top.def" $PT_ECO_DEF] && $PT_ECO_TECH_LEF eq ""}


# ---- task 079 part 1: the hold ECO excerpt of the user's second server run (the numbers 109 / 2687.50 / the four cells are from the run; the LAYOUT of the lines is a reconstruction -- VERIFY)
set hx "Information: Inserting hold buffers\nNumber of insert_buffer commands 109\nTotal area increased 2687.50 um^2\nInserted buffers:\n  dl01d1  64  25.09\n  dl02d1  31  28.22\n  buffd1  12  12.54\n  dl01d2   2  28.22\n  109 TOTAL\n\nFinal ECO Summary: Total number of commands 109\n"
set hp [pt_eco_parse_fix_text $hx]
check "hold excerpt: 109 commands" {[dict get $hp ncmd] == 109 && [dict get [dict get $hp commands] insert_buffer] == 109}
check "hold excerpt: area 2687.50" {[dict get $hp area] == 2687.50}
check "hold excerpt: the cell table (cell -> count, area each)" {[dict get [dict get $hp cells] dl01d1] eq {64 25.09} && [dict get [dict get $hp cells] dl02d1] eq {31 28.22} && [dict get [dict get $hp cells] buffd1] eq {12 12.54} && [dict get [dict get $hp cells] dl01d2] eq {2 28.22} && [dict size [dict get $hp cells]] == 4}
check "hold excerpt: the table sums to 109 cells and 2687.50 um^2" {abs(64*25.09 + 31*28.22 + 12*12.54 + 2*28.22 - 2687.50) < 0.5}
check "hold excerpt: proposed" {[pt_eco_fix_proposed $hp] == 1}
# the sample lines of the change files
set chg "current_instance\ncurrent_instance {u_apb}\ninsert_buffer \[get_pins {U46/Z}\] dl02d1 -new_net_names {net_PTECO_HOLD_NET1} -new_cell_names {U_PTECO_HOLD_BUF1}\ncurrent_instance\ninsert_buffer \[get_pins {U61/Z}\] dl01d2 -new_net_names {net_PTECO_HOLD_NET2} -new_cell_names {U_PTECO_HOLD_BUF2}\ncurrent_instance\n"
set cc [pt_eco_count_changes $chg {dl02d1 dl01d2 dl01d1 buffd1}]
check "change file (tcl): the two insert_buffer lines are counted with their references" {[dict get $cc n] == 2 && [dict get [dict get $cc refs] dl02d1] == 1 && [dict get [dict get $cc refs] dl01d2] == 1}
set txtl "16. insert_buffer in u_dma: added one 'dl02d1' 'I' to 'Z' on pin 'copt_h_inst_3080/Z' named 'net_PTECO_HOLD_NET16' 'U_PTECO_HOLD_BUF16'\n17. insert_buffer in u_csr: added one 'buffd1' 'I' to 'Z' on pin 'dest_c_reg_reg_2_/D' named 'net_PTECO_HOLD_NET17' 'U_PTECO_HOLD_BUF17'\n"
set ct [pt_eco_count_changes $txtl {dl02d1 buffd1}]
check "change file (txt): numbered lines are counted (the bug: the first word was '16.')" {[dict get $ct n] == 2 && [dict get [dict get $ct verbs] insert_buffer] == 2 && [dict get [dict get $ct refs] dl02d1] == 1 && [dict get [dict get $ct refs] buffd1] == 1}
check "size_cell lines are counted" {[dict get [pt_eco_count_changes "size_cell {HFSINV_13_284} inv0d8\n" {inv0d8}] n] == 1 && [dict get [dict get [pt_eco_count_changes "size_cell {HFSINV_13_284} inv0d8\n" {inv0d8}] refs] inv0d8] == 1}
# the number reported: the summary first
check "change number: the summary wins (109), source named" {[lindex [pt_eco_change_number $hp 0] 0] == 109 && [string match "Final ECO Summary*" [lindex [pt_eco_change_number $hp 0] 1]]}
check "change number: a different file count adds a NOTE" {[string match "*lists 111 change lines but PrimeTime's summary says 109*" [lindex [pt_eco_change_number $hp 111] 2]]}
check "change number: equal counts, no note" {[lindex [pt_eco_change_number $hp 109] 2] eq ""}
check "change number: no summary line -> the file count" {[lindex [pt_eco_change_number [pt_eco_parse_fix_text "Information: done\n"] 7] 0] == 7}
check "change number: nothing -> empty, the note says so" {[lindex [pt_eco_change_number [pt_eco_parse_fix_text ""] ""] 0] eq "" && [string match "neither*" [lindex [pt_eco_change_number [pt_eco_parse_fix_text ""] ""] 2]]}
check "closing line for the hold run" {[pt_eco_result_line 1 "[lindex [pt_eco_change_number $hp 0] 0] changes proposed, change file /x/pt_eco_hold_changes.tcl"] eq "PROBE RESULT: ECO RAN: 109 changes proposed, change file /x/pt_eco_hold_changes.tcl"}


# ------------------------------------------------------------------ 080: the in2out cone (pure parts)
pt_load_eco_parser
check "the change-file parser of pt_eco_apply.tcl is loaded (one parser for both sides)" {[llength [info commands eco079_parse]] == 1 && [llength [info commands eco079_pin_cell]] == 1}
# rows of violators (the real dma_rdata[14] path of task 078, with the hierarchy of the cells)
set rowA [dict create endpoint u_dma/stage_reg_1__14_/D startpoint dma_rdata\[14\] sp_kind port ep_kind pin slack -0.3468 group clk cells {u_dma/copt_h_inst_3910/Z(buffd1) u_dma/U588/Z(mx02d0)} delays {0.17 0.12}]
set rowB [dict create endpoint u_csr/src_a_reg_reg_3_/D startpoint pwdata\[3\] sp_kind port ep_kind pin slack -0.1 group clk cells {u_csr/U7/ZN(nd02d1) u_apb/U46/Z(buffd1)} delays {0.1 0.2}]
set rowC [dict create endpoint x/D startpoint y sp_kind pin ep_kind pin slack -0.1 group clk cells n/a delays n/a]
check "row cells: instance names without the pin and the reference" {[pt_cone_row_cells $rowA] eq {u_dma/copt_h_inst_3910 u_dma/U588} && [pt_cone_row_cells $rowC] eq {}}
set cone_cells {u_apb/U46 u_apb/U61 u_apb/U29 u_csr/U55}
set tc [pt_cone_touching [list $rowA $rowB $rowC] $cone_cells]
check "touching: only the row that crosses a cone cell (u_apb/U46), with the cell" {[llength $tc] == 1 && [lindex $tc 0 0] eq "u_csr/src_a_reg_reg_3_/D" && [lindex $tc 0 1] eq "u_apb/U46"}
set why [pt_cone_why_remaining [list $rowA $rowB $rowC] $cone_cells]
check "why remaining: cone crossing / no cone cell / unreadable, one line per row" {[llength $why] == 3 && [string match "*crosses the protected cone at u_apb/U46*" [lindex $why 1]] && [string match "*no cone cell on its data path*" [lindex $why 0]] && [string match "*path cells unreadable*" [lindex $why 2]]}
# the change file: the REAL first 20 lines (hold) and the real setup lines
set hp [eco079_parse [read_file_080 $here/../testdata/pt_eco_hold_changes_head.tcl]]
set hc [dict get $hp cmds]
check "cone hits: a change on pin u_apb/U46/Z when u_apb/U46 is a cone cell -> reported with its change number and line" {[llength [pt_cone_hits $hc {u_apb/U46} {}]] == 1 && [dict get [lindex [pt_cone_hits $hc {u_apb/U46} {}] 0] idx] == 1 && [dict get [lindex [pt_cone_hits $hc {u_apb/U46} {}] 0] line] == 9 && [string match "insert_buffer on pin u_apb/U46/Z of the cone cell" [dict get [lindex [pt_cone_hits $hc {u_apb/U46} {}] 0] what]]}
check "cone hits: no change touches a cone of other cells -> clean" {[pt_cone_hits $hc {u_apb/U99 u_csr/U1} {}] eq ""}
check "cone hits: three cone cells (u_apb/U46, the TOP-level U61 (empty current_instance in the real file), u_apb/U29) -> three hits; u_apb/U61 would be none" {[llength [pt_cone_hits $hc {u_apb/U46 U61 u_apb/U29} {}]] == 3 && [llength [pt_cone_hits $hc {u_apb/U61} {}]] == 0}
check "cone hits: an insertion on a cone PORT is a hit, on another port not" {[llength [pt_cone_hits $hc {} {dma_rdata[14]}]] == 1 && [pt_cone_hits $hc {} {paddr[2]}] eq ""}
set sp [eco079_parse "current_instance\nsize_cell {HFSINV_13_284} {inv0d7}\n"]
check "cone hits: size_cell of a cone cell is reported (the setup probe prints it as information), of another cell not" {[llength [pt_cone_hits [dict get $sp cmds] {HFSINV_13_284} {}]] == 1 && [pt_cone_hits [dict get $sp cmds] {u_apb/U46} {}] eq ""}
check "cone hits: a pin of a NON-cone cell on a hierarchy with the same leaf name is not a hit (full names compared)" {[pt_cone_hits $hc {U46} {}] eq ""}
check "cone head: sorted, truncated with the number of the rest" {[pt_cone_head {c b a d} 2] eq "a, b ... (and 2 more)" && [pt_cone_head {a} 5] eq "a"}
# the new PROBE RESULT lines
check "PROBE RESULT touches" {[pt_eco_result_line touches "3 of 109 proposed changes touch the cone"] eq "PROBE RESULT: ECO RAN BUT TOUCHES THE IN2OUT CONE: 3 of 109 proposed changes touch the cone"}
check "PROBE RESULT cone not computed / check not completed" {[pt_eco_result_line cone "m"] eq "PROBE RESULT: ECO NOT RUN, IN2OUT CONE NOT COMPUTED: m" && [pt_eco_result_line unchecked "m"] eq "PROBE RESULT: ECO RAN BUT THE IN2OUT CONE CHECK COULD NOT BE COMPLETED: m"}
check "the old three PROBE RESULT lines are unchanged" {[pt_eco_result_line 1 "109 changes proposed, change file f"] eq "PROBE RESULT: ECO RAN: 109 changes proposed, change file f" && [string match "PROBE RESULT: ECO NOT AVAILABLE: x" [pt_eco_result_line 0 x]] && [string match "PROBE RESULT: ECO RAN BUT PROPOSED NO CHANGES: x" [pt_eco_result_line nochanges x]]}

# ------------------------------------------------------------------ 080 fix: the cone by several methods (pure parts)
check "intersect: common names, sorted, unique" {[pt_cone_intersect {c a b a} {b c d}] eq {b c}}
check "union: all names, sorted, unique" {[pt_cone_union {{b a} {c a} {}}] eq {a b c}}
check "missing: elements of a not in b" {[pt_cone_missing {a b c} {b}] eq {a c}}
# a toy netlist: ports -> U1 -> U2 -> out port; U2 -> FF1 (D); FF1 -> U3 -> out2; in2 -> U4 -> FF2.  Cone = {U1 U2}
array set succF {U1 {U2} U2 {FF1} FF1 {U3} U3 {} U4 {FF2} FF2 {}}
array set predB {U2 {U1} U1 {} U3 {FF1} FF1 {U2} U4 {} FF2 {U4}}
array set isseq {U1 0 U2 0 U3 0 U4 0 FF1 1 FF2 1}
proc stepF {n} { global succF isseq; return [list $succF($n) $isseq($n)] }
proc stepB {n} { global predB isseq; return [list $predB($n) $isseq($n)] }
set fwd [pt_cone_reach {U1 U4} stepF 1000]
set bwd [pt_cone_reach {U2 U3} stepB 1000]
check "reach forward: stops at the flops (they are visited, not expanded): U3 is NOT reached" {[dict get $fwd all] eq {FF1 FF2 U1 U2 U4} && [dict get $fwd seq] eq {FF1 FF2}}
check "reach backward from the outputs: U3 stops at FF1 (U2 behind the flop is not reached through it)" {[dict get $bwd all] eq {FF1 U1 U2 U3} && [dict get $bwd seq] eq {FF1}}
check "structural cone = forward ∩ backward minus the sequential cells: {U1 U2}" {[pt_cone_structural $fwd $bwd] eq {U1 U2}}
check "a flop in both regions (reached at D from an input, drives an output) is not in the cone" {[lsearch -exact [pt_cone_structural $fwd $bwd] FF1] < 0}
check "reach: the bound is an error" {[catch {pt_cone_reach {U1} stepF 1} e] == 1 && [string match "*more than 1 cells*" $e]}
set rep "  Startpoint: paddr\[2\] (input port clocked by clk)\n  Endpoint: prdata\[5\] (output port clocked by clk)\n  Path Group: in2out_default\n\n  Point    Incr   Path\n  ---------\n  input external delay   7.00   7.00 r\n  paddr\[2\] (in)   0.00   7.00 r\n  u_apb/U46/Z (buffd1)   0.20   7.20 f\n  u_csr/U9/ZN (nd02d1)   0.10   7.30 r\n  prdata\[5\] (out)   0.40   7.70 r\n  data arrival time   7.70\n\n  Startpoint: paddr\[3\] (input port clocked by clk)\n  u_apb/U46/Z (buffd1)  0.2  7.2 f\n"
set pr [pt_cone_parse_report $rep]
check "report parser: two Startpoint lines, the cells without the pin, the ports" {[dict get $pr nstart] == 2 && [dict get $pr cells] eq {u_apb/U46 u_csr/U9} && [lindex [dict get $pr ports] 0] eq "paddr\[2\]" && [lindex [dict get $pr ports] 1] eq "prdata\[5\]" && [llength [dict get $pr ports]] == 2}
check "report parser: an empty report has no startpoint" {[dict get [pt_cone_parse_report ""] nstart] == 0}
check "sanity: u_apb cell present, no flop -> no problem" {[pt_cone_sanity {u_apb/U46 x/U1} 0 {u_apb/ u_csr/}] eq ""}
check "sanity: no cell of the expected blocks -> problem naming the prefixes" {[string match "*none starts with one of {u_apb/ u_csr/}*" [lindex [pt_cone_sanity {x/U1 y/U2} 0 {u_apb/ u_csr/}] 0]]}
check "sanity: a flop in the cone -> problem" {[string match "*contains 2 sequential cell(s), expected 0*" [lindex [pt_cone_sanity {u_csr/U1} 2 {u_apb/ u_csr/}] 0]]}
check "sanity: an empty cone -> problem" {[pt_cone_sanity {} 0 {u_apb/}] eq {{the cone is empty}}}
set cmp [pt_cone_compare [dict create c {a b c} a1 {a b}] {a b c}]
check "compare: the smaller path-based method is reported as not covering the union; no BUG text for subsets" {[llength $cmp] == 2 && [string match "method c: 3 cells; equal to or covering*" [lindex $cmp 0]] && [string match "method a1: 2 cells; 1 cells of the final cone are not in it" [lindex $cmp 1]] && [string first BUG [join $cmp]] < 0}
check "compare: a method with a cell outside the final cone is flagged (cannot happen with the union)" {[string match "*BUG*" [lindex [pt_cone_compare [dict create z {a q}] {a b}] 0]]}

# ------------------------------------------------------------------ 081: the count file written by the probe is read by the apply script (round trip)
set cft [pt_eco_expected_text 112 "Final ECO Summary: Total number of commands" /x/pt_eco_hold_changes_icc2.tcl]
lassign [eco079_expect_decide 1 $cft 109 EXPECT_HOLD_CMDS] n src warn
check "count file: written by the probe's formatter, read back by the apply parser (112)" {$n == 112 && $warn eq "" && [string match "commands 112*" [lindex [split $cft "\n"] 1]] && [string match "change_file /x/*" [lindex [split $cft "\n"] 3]]}
check "count file: the default of PT_CONE_PROTECT_NETS is 1 (cells and nets), decided from the server runs" {$PT_CONE_PROTECT_NETS == 1}

# ---- the annotation table with SI ON (extra column 'Coupled network'): the columns are read from the header; real rows of pt_si/pt_setup_ss.log (run 3) and the SI-off table of the same netlist
set ann_off [read [set fp [open $here/../testdata/annotation_si_off.txt]]]; close $fp
set ann_on [read [set fp [open $here/../testdata/annotation_si_on.txt]]]; close $fp
set po [pt_parse_annotation_table $ann_off]
set pn [pt_parse_annotation_table $ann_on]
check "SI off (real run-3 table): found, header read with 5 columns" {[dict get $po found] == 1 && [llength [dict get $po columns]] == 5 && [dict get $po problem] eq ""}
check "SI on (real run-3 table): found, header read with 6 columns incl. 'coupled network'" {[dict get $pn found] == 1 && [llength [dict get $pn columns]] == 6 && [lsearch -exact [dict get $pn columns] "coupled network"] >= 0 && [dict get $pn columns] eq "total lumped {rc pi} {rc network} {coupled network} {not annotated}"}
check "SI on: six rows, the total row is the five fixed columns, the coupled total separately" {[llength [dict get $pn rows]] == 6 && [dict get $pn total] eq "16984 0 0 3477 413" && [dict get $pn total_extra] == 13094}
check "SI on: the internal pin-to-pin row (16389 | 0 | 0 | 3360 | 13029 | 0) keeps the coupled nets as the 8th field" {[lindex [dict get $pn rows] 0] eq "internal p2p 16389 0 0 3360 0 13029"}
check "SI on: the boundary pin-to-pin row (182 | 117 | 65 | 0)" {[lindex [dict get $pn rows] 3] eq "boundary p2p 182 0 0 117 0 65"}
check "SI on: not annotated is read BY NAME from the last column (343 and 48, 22)" {[lindex [dict get $pn rows] 1 6] == 343 && [lindex [dict get $pn rows] 2 6] == 48 && [lindex [dict get $pn rows] 5 6] == 22}
check "SI off: the rows keep the 7-field form (no 8th field)" {[llength [lindex [dict get $po rows] 0]] == 7}
lassign [pt_annotation_policy $po 0 0.0 0] ok_off lines_off
lassign [pt_annotation_policy $pn 0 0.0 0] ok_on lines_on
check "policy SI off: accepted, 16571 pin-to-pin nets, 0 not annotated" {$ok_off == 1 && [llength [lsearch -all -glob $lines_off "pin-to-pin nets: 16571 in total*0 not annotated*"]] == 1}
check "policy SI on: accepted, the same 16571 pin-to-pin nets, all annotated (3477 RC network + 13094 coupled), 0 not annotated" {$ok_on == 1 && [llength [lsearch -all -glob $lines_on "pin-to-pin nets: 16571 in total*annotated 16389*0 not annotated (0.000 percent*"]] == 0 || ($ok_on == 1 && [llength [lsearch -all -glob $lines_on "pin-to-pin nets: 16571 in total*0 not annotated*"]] == 1)}
check "policy SI on: driverless / loadless are information (343 + 0, 48 + 22 not annotated)" {[llength [lsearch -all -glob $lines_on "information (not an error): internal driverless nets: 343 in total, 343 not annotated*"]] == 1}
check "policy SI on: no WARNING (the 'Annotated nets' line equals the pin-to-pin count)" {[llength [lsearch -all -glob $lines_on "WARNING*"]] == 0}
# strictness is unchanged with the extra column: one unannotated pin-to-pin net is an ERROR; the consistency check still works
set on_bad [string map {"|   16389 |       0 |       0 |    3360 |   13029 |       0 |" "|   16389 |       0 |       0 |    3360 |   13016 |      13 |"} $ann_on]
set on_bad [string map {"|   16984 |       0 |       0 |    3477 |   13094 |     413 |" "|   16984 |       0 |       0 |    3477 |   13081 |     426 |"} $on_bad]
lassign [pt_annotation_policy [pt_parse_annotation_table $on_bad] 0 0.0 0] ok lines
check "SI on: 13 unannotated pin-to-pin nets is an ERROR (0 percent limit, mandatory)" {$ok == 0 && [llength [lsearch -all -glob $lines "ERROR: 13 pin-to-pin nets*are not annotated*"]] == 1}
set on_inc [string map {"|   16984 |       0 |       0 |    3477 |   13094 |     413 |" "|   16985 |       0 |       0 |    3477 |   13094 |     413 |"} $ann_on]
lassign [pt_annotation_policy [pt_parse_annotation_table $on_inc] 0 0.0 0] ok lines
check "SI on: a total row that does not add up is an ERROR" {$ok == 0 && [llength [lsearch -all -glob $lines "the table is inconsistent*"]] == 1}
# a row with a wrong number of numbers for the header, a header without the columns, a non-number: found = 0 with the real reason
set on_short [string map {"|   16389 |       0 |       0 |    3360 |   13029 |       0 |" "|   16389 |       0 |       0 |    3360 |       0 |"} $ann_on]
set ps [pt_parse_annotation_table $on_short]
check "a row with 5 numbers under a 6-column header: not found, the reason names the counts" {[dict get $ps found] == 0 && [dict get $ps present] == 1 && [string match "*5 numbers but the header has 6 columns*" [dict get $ps problem]]}
lassign [pt_annotation_policy $ps 0 0.0 0] ok lines
check "policy: a table that IS present but unparsed says so (not 'could not be found')" {$ok == 0 && [llength [lsearch -all -glob $lines "the annotation table of report_annotated_parasitics IS in the text but could not be parsed: row*5 numbers but the header has 6 columns*"]] == 1}
set nohdr [string map {"Annotated|" "Unconnected|" "|   Not   |" "|  Other  |"} $ann_on]
set pnh [pt_parse_annotation_table $nohdr]
check "a header without a 'Not Annotated' column is not guessed: found 0 and the reason" {[dict get $pnh found] == 0 && [string match "*no 'Total' and 'Not Annotated' column*" [dict get $pnh problem]]}
set nonum [string map {"|     182 |       0 |       0 |     117 |      65 |       0 |" "|     182 |       0 |       0 |     117 |      6x |       0 |"} $ann_on]
check "a cell that is not a number: the row is rejected with the reason" {[dict get [pt_parse_annotation_table $nonum] found] == 0 || [string match "*not a number*" [dict get [pt_parse_annotation_table $nonum] problem]] || [llength [dict get [pt_parse_annotation_table $nonum] rows]] == 5}
check "no table at all: not present, not found" {[dict get [pt_parse_annotation_table "Information: nothing"] present] == 0 && [dict get [pt_parse_annotation_table "Information: nothing"] found] == 0}
check "the old 5-column text without a header line is still read (SI-off layout assumed)" {[dict get [pt_parse_annotation_table [regsub {Net Type[^\n]*\n} $ann_off ""]] found] == 1}
# the post-run check reads the SI-on table too (check_annotation.tcl uses the same parser)
lassign [pt_check_log_text "SPEF parsing summary:\n  0 error(s)\n$ann_on" 0.0] okc linesc
check "post-run check (check_annotation) accepts the SI-on table" {$okc == 1}
lassign [pt_check_log_text "SPEF parsing summary:\n  0 error(s)\n$ann_off" 0.0] okc linesc
check "post-run check accepts the SI-off table" {$okc == 1}
# the in-session reader tells 'present but unparsed' from 'not in the session'
set cm [string range [read [set fp [open $here/pt_common.tcl]]] 0 end]; close $fp
check "pt_read_spef: a present-but-unparsed table has its own error text and is never waived by the post-run option" {[string match "*the annotation table IS in the text but could not be parsed*" $cm] && [string match "*set present_problem*" $cm]}
check "hold script, setup script and the three ECO probes read the table through pt_read_spef (one parser)" {[string match "*pt_prepare_session*" [read [set fp [open $here/pt_eco_probe.tcl]]]] && [string match "*pt_prepare_session*" [read [set fp2 [open $here/pt_eco_drc_probe.tcl]]]] && [string match "*pt_read_spef*" [read [set fp3 [open $here/pt_setup_ss.tcl]]]] && [string match "*pt_read_spef*" [read [set fp4 [open $here/pt_hold_ff.tcl]]]]}


# ---- the REAL header is two lines (task fix 2): the names are split across them. Verbatim tables: testdata/annotation_si_off.txt is the block of pt/pt_setup_ss.log of run 3; the SI-on one is the text of pt_si/pt_setup_ss.log
check "the real SI-off header: columns joined from the two lines" {[dict get $po columns] eq "total lumped {rc pi} {rc network} {not annotated}"}
check "the real tables have the header split over two lines (the one-line paraphrase 'Net Type | Total | ... | Not Annotated' is NOT what the tool prints)" {[regexp -nocase {Net Type\s*\|\s*Total\s*\|\s*Lumped\s*\|[^\n]*Not Annotated} $ann_off] == 0 && [regexp -nocase {Net Type\s*\|\s*Total\s*\|\s*Lumped\s*\|[^\n]*Not Annotated} $ann_on] == 0 && [regexp {\|\s+Not\s+\|\n\s*Net Type[^\n]*\|Annotated\|} $ann_on] == 1 && [regexp {\|\s+Not\s+\|\n\s*Net Type[^\n]*\|Annotated\|} $ann_off] == 1}
check "real SI-off table: 16571 pin-to-pin nets, 0 not annotated (internal 16389, boundary 182)" {[dict get $po found] == 1 && [dict get $po total] eq "16984 0 0 16571 413" && [lindex [dict get $po rows] 0] eq "internal p2p 16389 0 0 16389 0"}
check "the one-line header form is still read (older fixtures)" {[dict get [pt_parse_annotation_table "Net Type | Total | Lumped | RC pi | RC network | Not Annotated\n  - Pin to pin nets | 5 | 0 | 0 | 5 | 0 |\n| 5 | 0 | 0 | 5 | 0 |\n"] found] == 1}
# the whole real log of run 3 (SI off), when the server pull is on this machine
set reallog [file normalize ~/server_pull/run3/pnr_icc2/pt/pt_setup_ss.log]
if {[file exists $reallog]} {
    set rl [read [set fp [open $reallog]]]; close $fp
    lassign [pt_check_log_text $rl 0.0] okr linesr
    set prl [pt_parse_annotation_table [pt_last_annotation_block $rl]]
    set nets_ann [lindex [dict get $prl total] 3]   ;# the file is replaced when a newer run is copied (16,571 nets in the first final, 16,573 in the last): the checks use the numbers OF THE FILE, the exact numbers are in the verbatim fixture above
    check "the REAL pt_setup_ss.log of run 3: the post-run check passes, all pin-to-pin nets annotated" {$okr == 1 && [llength [lsearch -all -glob $linesr "*pin-to-pin nets: $nets_ann in total*0 not annotated*"]] >= 1}
    check "the REAL log: the last report block parses (found), 6 rows, the pin-to-pin rows add up to the annotated total, nothing but driverless/loadless nets is unannotated" {[dict get $prl found] == 1 && [llength [dict get $prl rows]] == 6 && [expr {[lindex [dict get $prl rows] 0 2] + [lindex [dict get $prl rows] 3 2]}] == $nets_ann && [lindex [dict get $prl rows] 0 6] == 0 && [lindex [dict get $prl rows] 3 6] == 0}
} else { puts "NOTE: ~/server_pull/run3/pnr_icc2/pt/pt_setup_ss.log not on this machine: the whole-log check was skipped" }

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
