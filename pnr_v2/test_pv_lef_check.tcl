# ==============================================================================
# Test: test_pv_lef_check.tcl (task 073)
# Run : tclsh pnr_v2/test_pv_lef_check.tcl   (from the repository root; no ICC2 needed)
# Tests the pure-Tcl LEF check of pnr_v2/pv.tcl (between "BEGIN PURE TCL 073" and "END PURE TCL 073") on sample LEF texts:
# one correct macro, the real bad case (122 library macros, no unpu_top), two unpu_top macros, a wrong SIZE, a wrong PIN count, and the rename.
# ==============================================================================
set here [file dirname [file normalize [info script]]]
set fp [open $here/pv.tcl r]
set src [read $fp]
close $fp
set b [string first "# ---- BEGIN PURE TCL 073 ----" $src]
set e [string first "# ---- END PURE TCL 073 ----" $src]
if {$b < 0 || $e < 0 || $e <= $b} { puts "FAIL cannot find the pure Tcl markers"; exit 1 }
eval [string range $src $b $e]

set nfail 0
set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}

# a LEF text with one macro: n signal pins plus VDD VSS, size w x h
proc make_macro {name npins w h} {
    set t "MACRO $name\n  CLASS BLOCK ;\n  ORIGIN 0 0 ;\n  SIZE $w BY $h ;\n  SYMMETRY X Y R90 ;\n"
    for {set i 0} {$i < $npins} {incr i} { append t "  PIN sig$i\n    DIRECTION INPUT ;\n    USE SIGNAL ;\n    PORT\n      LAYER M3 ;\n        RECT 0 0 1 1 ;\n    END\n  END sig$i\n" }
    append t "  PIN VDD\n    DIRECTION INOUT ;\n    USE POWER ;\n    PORT\n      LAYER TOP_M ;\n        RECT 0 0 1 1 ;\n    END\n  END VDD\n"
    append t "  PIN VSS\n    DIRECTION INOUT ;\n    USE GROUND ;\n    PORT\n      LAYER TOP_M ;\n        RECT 0 0 1 1 ;\n    END\n  END VSS\n"
    append t "  OBS\n    LAYER M1 ;\n      RECT 0 0 $w $h ;\n  END\nEND $name\n"
    return $t
}
set hdr "VERSION 5.8 ;\nBUSBITCHARS \"\[\]\" ;\nDIVIDERCHAR \"/\" ;\n"

# 1. the correct file
set good "${hdr}[make_macro unpu_top 204 885.600 885.600]END LIBRARY\n"
check "correct macro is accepted" {[pv_lef_check $good unpu_top 206 885.6 885.6] eq ""}
check "macro names" {[pv_lef_macros $good] eq "unpu_top"}
check "END count" {[pv_lef_end_count $good unpu_top] == 1}
check "tolerance: 0.0005 off is accepted" {[pv_lef_check $good unpu_top 206 885.6005 885.6] eq ""}

# 2. the real bad case of the first server run: 122 library macros, no unpu_top
set bad ""
append bad $hdr
set names [list inv0d4]
for {set i 1} {$i < 121} {incr i} { lappend names cell$i }
lappend names feedth
foreach n $names { append bad [make_macro $n 2 1.12 5.6] }
append bad "END LIBRARY\n"
check "the test file has 122 macros" {[llength [pv_lef_macros $bad]] == 122}
set pr [pv_lef_check $bad unpu_top 206 885.6 885.6]
puts "bad case messages: $pr"
check "122 library macros without unpu_top is rejected" {[llength $pr] >= 2}
check "message says 0 unpu_top macros and names first and last" {[string match "*holds 0 'MACRO unpu_top' entries, 1 expected (122 MACRO entries in total, first 'inv0d4', last 'feedth')*" [lindex $pr 0]]}
check "message says the END line is missing" {[string match "*0 'END unpu_top' lines*" [join $pr " "]]}

# 3. two unpu_top macros
set two "${hdr}[make_macro unpu_top 204 885.6 885.6][make_macro unpu_top 204 885.6 885.6]END LIBRARY\n"
set pr [pv_lef_check $two unpu_top 206 885.6 885.6]
check "two unpu_top macros are rejected" {[llength $pr] >= 1 && [string match "*holds 2 'MACRO unpu_top' entries, 1 expected*" [lindex $pr 0]]}
check "two END lines are reported" {[string match "*2 'END unpu_top' lines*" [join $pr " "]]}

# 4. one unpu_top plus a library macro
set extra "${hdr}[make_macro unpu_top 204 885.6 885.6][make_macro inv0d4 2 1.12 5.6]END LIBRARY\n"
set pr [pv_lef_check $extra unpu_top 206 885.6 885.6]
check "an extra library macro next to unpu_top is rejected" {[llength $pr] == 1 && [string match "*2 MACRO entries, 1 expected (extra: inv0d4)*" [lindex $pr 0]]}

# 5. wrong size
set wrong "${hdr}[make_macro unpu_top 204 817.6 817.6]END LIBRARY\n"
set pr [pv_lef_check $wrong unpu_top 206 885.6 885.6]
check "wrong SIZE is rejected with both sizes in the message" {[llength $pr] == 1 && [string match "*SIZE is 817.6 x 817.6 um, the die box is 885.600 x 885.600 um*" [lindex $pr 0]]}
set wrong "${hdr}[make_macro unpu_top 204 885.6 885.7]END LIBRARY\n"
check "0.1 um off in one side is rejected" {[llength [pv_lef_check $wrong unpu_top 206 885.6 885.6]] == 1}
check "a looser tolerance accepts it" {[pv_lef_check $wrong unpu_top 206 885.6 885.6 0.2] eq ""}

# 6. wrong pin count
set pins "${hdr}[make_macro unpu_top 200 885.6 885.6]END LIBRARY\n"
set pr [pv_lef_check $pins unpu_top 206 885.6 885.6]
check "202 PIN entries instead of 206 are rejected" {[llength $pr] == 1 && [string match "*macro unpu_top has 202 PIN entries, 206 expected*" [lindex $pr 0]]}
set pins "${hdr}[make_macro unpu_top 205 885.6 885.6]END LIBRARY\n"
check "one PIN too many is rejected" {[llength [pv_lef_check $pins unpu_top 206 885.6 885.6]] == 1}
check "PIN lines of the other macro are not counted" {[pv_lef_check "${hdr}[make_macro unpu_top 204 885.6 885.6]" unpu_top 206 885.6 885.6] eq ""}

# 7. no SIZE, empty text
set nosize [regsub {  SIZE [^\n]*\n} $good ""]
check "a macro without SIZE is rejected" {[string match "*has no SIZE line*" [join [pv_lef_check $nosize unpu_top 206 885.6 885.6] " "]]}
check "empty text is rejected" {[string match "*no MACRO at all*" [lindex [pv_lef_check "" unpu_top 206 885.6 885.6] 0]]}

# 8. rename (the block name is not the cell name)
set filled "${hdr}[make_macro unpu_top_filled 204 885.6 885.6]END LIBRARY\n"
check "before the rename the check fails" {[llength [pv_lef_check $filled unpu_top 206 885.6 885.6]] >= 1}
lassign [pv_lef_rename $filled unpu_top_filled unpu_top] renamed nchg
check "rename changes exactly the MACRO line and the END line" {$nchg == 2}
check "after the rename the check passes" {[pv_lef_check $renamed unpu_top 206 885.6 885.6] eq ""}
check "the pin lines still have their names" {[regexp -all {PIN sig} $renamed] == 204 && [string first "unpu_top_filled" $renamed] < 0}
check "rename keeps the rest of the text byte for byte" {[string length $renamed] == [string length $filled] - 2 * [string length _filled]}
check "rename of an absent macro is an error" {[catch {pv_lef_rename $good nothere unpu_top}]}
check "rename refuses two macros of that name" {[catch {pv_lef_rename "${hdr}[make_macro a 1 1 1][make_macro a 1 1 1]" a b}]}
# a macro whose name only starts like the old one is not renamed
set prefix "${hdr}[make_macro unpu_top_filled 2 1 1][make_macro unpu_top_filled2 2 1 1]"
lassign [pv_lef_rename $prefix unpu_top_filled unpu_top] r2 n2
check "a longer name with the same start is left alone" {$n2 == 2 && [lsort [pv_lef_macros $r2]] eq "unpu_top unpu_top_filled2"}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
