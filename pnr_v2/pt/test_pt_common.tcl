# ==============================================================================
# Test: test_pt_common.tcl (task 074)
# Run : tclsh pnr_v2/pt/test_pt_common.tcl   (from the repository root; no PrimeTime needed)
# Tests the pure-Tcl procs of pt_common.tcl: file check, the SPEF-to-corner decision, SDC value parser, comparison with the expected legacy values, annotation parser and policy,
# check_timing parser, report_constraint parser, verdict, summary and ICC2 comparison lines. The report texts are written from knowledge of the PrimeTime formats (VERIFY on the server).
# ==============================================================================
set here [file dirname [file normalize [info script]]]
source $here/pt_common.tcl

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
set ct "Warning: There are 3 endpoints which are not constrained for maximum delay.\n  pready\n  u_x/reg_a/D\n  u_y/reg_b/D\n\nInformation: next section\n"
lassign [pt_parse_unconstrained $ct] head names
check "check_timing: heading and names" {$head == 1 && $names eq "pready u_x/reg_a/D u_y/reg_b/D"}
check "check_timing: only the known constant is accepted" {[pt_unexpected_endpoints {pready} {pready}] eq ""}
check "check_timing: other endpoints are unexpected" {[pt_unexpected_endpoints $names {pready}] eq "u_x/reg_a/D u_y/reg_b/D"}
check "check_timing: known constant with a path prefix" {[pt_unexpected_endpoints {top/pready} {pready}] eq ""}
lassign [pt_parse_unconstrained "Information: Checking 'no_clock'.\nInformation: Checking 'unconstrained_endpoints'.\n"] head names
check "check_timing: no problem text -> no names" {$names eq ""}
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
check "ICC2 figures at the top" {$PT_ICC2_SETUP_WNS == 0.0143 && $PT_ICC2_HOLD_WNS == -0.0004}
check "expected legacy values at the top" {$PT_EXPECT_PERIOD == 20.0 && $PT_EXPECT_SETUP_UNC == 1.5 && $PT_EXPECT_HOLD_UNC == 0.5}
check "SI is off by default" {$PT_SI_ENABLE == 0}
check "the override is empty by default" {$PT_SPEF_OVERRIDE(ss) eq "" && $PT_SPEF_OVERRIDE(ff) eq ""}
check "unannotated limit is 0 by default" {$PT_MAX_UNANNOTATED_PCT == 0.0 && $PT_ALLOW_UNREADABLE_ANNOTATION == 0}
check "the netlist is the one without PG pins" {[string match "*unpu_top_pnr_sim.v" $PT_NETLIST]}
check "libraries are the ss and ff db files named in build_ndm_std.tcl" {[string match "*lib_flow_ss/tsl18fs120_scl_ss.db" $PT_CORNER(ss,db)] && [string match "*lib_flow_ff/tsl18fs120_scl_ff.db" $PT_CORNER(ff,db)]}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
