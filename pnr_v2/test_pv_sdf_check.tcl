# ==============================================================================
# Test: test_pv_sdf_check.tcl (task 076)
# Run : tclsh pnr_v2/test_pv_sdf_check.tcl   (from the repository root; no ICC2 needed)
# Tests (1) the pure-Tcl SDF version check of pnr_v2/pv.tcl (between "BEGIN PURE TCL 076" and "END PURE TCL 076") and (2) the block of pv.tcl that rewrites and checks the SDFVERSION of the two
# SDF files, run on small sample files in a temporary directory (it uses only exec head / grep / sed).
# ==============================================================================
set here [file dirname [file normalize [info script]]]
set fp [open $here/pv.tcl r]; set src [read $fp]; close $fp
set b [string first "# ---- BEGIN PURE TCL 076 ----" $src]
set e [string first "# ---- END PURE TCL 076 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]
# the block that edits and checks the files
set b2 [string first "    set pv_sdf_problems {}" $src]
set e2 [string first "    foreach pv_pr \$pv_sdf_problems" $src]
if {$b2 < 0 || $e2 < 0 || $e2 <= $b2} { puts "FAIL cannot find the SDF block in pv.tcl"; exit 1 }
set e2 [string first "\n" $src $e2]
set blockcode [string range $src $b2 $e2]

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}

# ------------------------------------------------------------------ pure part
set h21 "(DELAYFILE\n(SDFVERSION \"OVI 2.1\")\n(DESIGN \"unpu_top\")\n(DIVIDER /)\n"
set h30 "(DELAYFILE\n(SDFVERSION \"3.0\")\n(DESIGN \"unpu_top\")\n"
check "versions: OVI 2.1" {[pv_sdf_versions $h21] eq "{OVI 2.1}"}
check "versions: 3.0" {[pv_sdf_versions $h30] eq "3.0"}
check "versions: spaces inside the parentheses" {[pv_sdf_versions "( SDFVERSION  \"3.0\" )"] eq "3.0"}
check "versions: none" {[pv_sdf_versions "(DELAYFILE\n(DESIGN \"x\")\n"] eq ""}
check "problem: 3.0 is accepted" {[pv_sdf_version_problem $h30] eq ""}
check "problem: OVI 2.1 is rejected with the value" {[pv_sdf_version_problem $h21] eq "SDFVERSION is \"OVI 2.1\", 3.0 required"}
check "problem: 2.1 is rejected" {[pv_sdf_version_problem "(SDFVERSION \"2.1\")"] ne ""}
check "problem: no SDFVERSION line is rejected" {[string match "no (SDFVERSION*" [pv_sdf_version_problem "(DELAYFILE)"]]}
check "problem: two SDFVERSION lines are rejected" {[string match "2 SDFVERSION lines*" [pv_sdf_version_problem "(SDFVERSION \"3.0\")\n(SDFVERSION \"3.0\")"]]}
check "problem: 3.0.1 is not 3.0" {[pv_sdf_version_problem "(SDFVERSION \"3.0.1\")"] ne ""}

# ------------------------------------------------------------------ the block on sample files
set tmp [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] ptsdf_[pid]]
file mkdir $tmp
proc wr {path text} { set fp [open $path w]; puts -nonewline $fp $text; close $fp }
proc rd {path} { set fp [open $path r]; set t [read $fp]; close $fp; return $t }
set body "(CELL (CELLTYPE \"dfcrq1\") (INSTANCE u1)\n (DELAY (ABSOLUTE (IOPATH CP Q (0.1:0.2:0.3) (0.1:0.2:0.3))))\n (TIMINGCHECK (REMOVAL RN (posedge CP) (0.0:0.1:0.2)) (RECOVERY RN (posedge CP) (0.3:0.4:0.5)) (SETUP D (posedge CP) (0.1:0.1:0.1)))\n)\n"
set OUT_DIR $tmp
set DESIGN_NAME unpu_top
# the real case: OVI 2.1 header and REMOVAL / RECOVERY entries in both files
wr $tmp/unpu_top_ss.sdf "${h21}${body}"
wr $tmp/unpu_top_ff.sdf "${h21}${body}${body}"
set out ""
set code "proc pv_run {} { global OUT_DIR DESIGN_NAME pv_sdf_problems\n$blockcode\n}"
eval $code
set pv_sdf_problems {}
set out [pv_run]
check "block: both files are rewritten to 3.0" {[pv_sdf_version_problem [rd $tmp/unpu_top_ss.sdf]] eq "" && [pv_sdf_version_problem [rd $tmp/unpu_top_ff.sdf]] eq ""}
check "block: the entries are untouched (REMOVAL and RECOVERY still there)" {[regexp -all {REMOVAL} [rd $tmp/unpu_top_ss.sdf]] == 1 && [regexp -all {RECOVERY} [rd $tmp/unpu_top_ff.sdf]] == 2}
check "block: the body is byte for byte the same except the version text" {[string length [rd $tmp/unpu_top_ss.sdf]] == [string length "${h21}${body}"] - [string length "OVI 2.1"] + [string length "3.0"]}
check "block: no problem reported" {$pv_sdf_problems eq ""}
# a file that is already 3.0 is not touched
wr $tmp/unpu_top_ss.sdf "${h30}${body}"
wr $tmp/unpu_top_ff.sdf "${h30}${body}"
set before [rd $tmp/unpu_top_ss.sdf]
set pv_sdf_problems {}
pv_run
check "block: a 3.0 file is left as it is and passes" {[rd $tmp/unpu_top_ss.sdf] eq $before && $pv_sdf_problems eq ""}
# only the first lines are edited: a later (SDFVERSION "x") text deep in the file stays
set deep "${h21}"
for {set i 0} {$i < 100} {incr i} { append deep "(* filler line $i *)\n" }
append deep "(SDFVERSION \"OVI 2.1\") (* not the header *)\n"
wr $tmp/unpu_top_ss.sdf $deep
wr $tmp/unpu_top_ff.sdf "${h21}${body}"
set pv_sdf_problems {}
pv_run
check "block: only the header lines (first 60) are rewritten" {[regexp -all {OVI 2.1} [rd $tmp/unpu_top_ss.sdf]] == 1 && [pv_sdf_version_problem [string range [rd $tmp/unpu_top_ss.sdf] 0 200]] eq ""}
# no SDFVERSION line at all -> the block cannot make it 3.0 -> problem
wr $tmp/unpu_top_ss.sdf "(DELAYFILE\n(DESIGN \"x\")\n${body}"
wr $tmp/unpu_top_ff.sdf "${h30}${body}"
set pv_sdf_problems {}
pv_run
check "block: a file without an SDFVERSION line is a problem" {[llength $pv_sdf_problems] == 1 && [string match "*unpu_top_ss.sdf: no (SDFVERSION*" [lindex $pv_sdf_problems 0]]}
# missing and empty files
file delete $tmp/unpu_top_ss.sdf
wr $tmp/unpu_top_ff.sdf ""
set pv_sdf_problems {}
pv_run
check "block: a missing file and an empty file are problems" {[llength $pv_sdf_problems] == 2 && [string match "*does not exist or is empty*" [lindex $pv_sdf_problems 0]] && [string match "*does not exist or is empty*" [lindex $pv_sdf_problems 1]]}
file delete -force $tmp

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
