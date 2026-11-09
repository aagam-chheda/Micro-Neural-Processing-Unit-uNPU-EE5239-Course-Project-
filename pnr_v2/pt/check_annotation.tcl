# ==============================================================================
# Script: check_annotation.tcl   (task 074 fix: post-run annotation check)
# Use   : tclsh ../../pnr_v2/pt/check_annotation.tcl [parasitics_command.log [expected_text]]      (run from pnr_icc2/pt, AFTER the pt_shell session has ended)
# Why   : PrimeTime writes parasitics_command.log buffered and completes it only at the end of the session; when the annotation table is not in the session text the sign-off script cannot
#         check it in-session. This script applies the SAME parser and policy (pt_common.tcl: pt_check_log_text, PT_MAX_UNANNOTATED_PCT) to the finished file. It cannot be waived
#         (PT_ALLOW_UNREADABLE_ANNOTATION does not apply here): a missing table or a missing file is a FAILURE.
# Args  : the log (default parasitics_command.log in the current directory); optional expected_text, a string that must occur in the file (for example the tag of the SPEF of the corner,
#         TYPICAL_RC_125 for ss), because each pt_shell run recreates the file: copy it after each run (README) and check each copy.
# Output: ANNOTATION CHECK PASSED (exit 0) or ANNOTATION CHECK FAILED (exit 1).
# ==============================================================================
set CA_DIR [file dirname [file normalize [info script]]]
source ${CA_DIR}/pt_common.tcl

proc ca_main {argv} {
    global PT_PARA_LOG PT_MAX_UNANNOTATED_PCT
    set log [expr {[llength $argv] >= 1 ? [lindex $argv 0] : $PT_PARA_LOG}]
    set expect [expr {[llength $argv] >= 2 ? [lindex $argv 1] : {}}]
    puts ">>> 074 check_annotation: file $log, maximum unannotated pin-to-pin nets $PT_MAX_UNANNOTATED_PCT percent, expected text '$expect'"
    set p [pt_file_problem $log]
    if {$p ne ""} { puts "ANNOTATION CHECK FAILED: $p"; return 1 }
    set fp [open $log r]
    set text [read $fp]
    close $fp
    puts ">>> 074 [string length $text] bytes read"
    foreach l [split $text "\n"] { if {[regexp -nocase {\.spef|reading|spef file} $l]} { puts ">>> 074 log line: $l" } }
    if {$expect ne "" && [string first $expect $text] < 0} {
        puts "ANNOTATION CHECK FAILED: the expected text '$expect' does not occur in $log (is this the log of the right pt_shell run?)"
        return 1
    }
    lassign [pt_check_log_text $text $PT_MAX_UNANNOTATED_PCT] ok lines
    foreach l $lines { puts ">>> 074 ANNOTATION: $l" }
    if {$ok} { puts "ANNOTATION CHECK PASSED"; return 0 }
    puts "ANNOTATION CHECK FAILED"
    return 1
}
exit [ca_main $argv]
