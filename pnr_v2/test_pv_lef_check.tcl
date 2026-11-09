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


# 9. task 073 fix: the real header of the file written by write_lef has an INDENTED property definition "  MACRO expanded_util REAL ;"
#    between PROPERTYDEFINITIONS and END PROPERTYDEFINITIONS; it is not a macro. A MACRO entry starts at column 0 with "MACRO <name>" and nothing else but trailing spaces.
set realhdr "VERSION 5.8 ;\nBUSBITCHARS \"\[\]\" ;\nDIVIDERCHAR \"/\" ;\n\nPROPERTYDEFINITIONS\n  MACRO expanded_util REAL ;\nEND PROPERTYDEFINITIONS\n\n"
set realmac "MACRO unpu_top\n  CLASS BLOCK ;\n  ORIGIN 0 0 ;\n  SIZE 885.6 BY 885.6 ;\n  SYMMETRY X Y ;\n"
for {set i 0} {$i < 204} {incr i} { append realmac "  PIN sig$i\n    DIRECTION INPUT ;\n    USE SIGNAL ;\n  END sig$i\n" }
append realmac "  PIN VDD\n    DIRECTION INOUT ;\n    USE POWER ;\n  END VDD\n  PIN VSS\n    DIRECTION INOUT ;\n    USE GROUND ;\n  END VSS\n  OBS\n    LAYER M1 ;\n      RECT 0 0 885.6 885.6 ;\n  END\nEND unpu_top\n\nEND LIBRARY\n"
set real "${realhdr}${realmac}"
check "real header: the property definition is not a macro" {[pv_lef_macros $real] eq "unpu_top"}
check "real header + macro (204 signal + 2 power pins, 885.6 x 885.6) is accepted" {[pv_lef_check $real unpu_top 206 885.6 885.6] eq ""}
check "real header: one END unpu_top" {[pv_lef_end_count $real unpu_top] == 1}
check "real header: the property line is outside the macro block" {[string first "expanded_util" [pv_lef_block $real unpu_top]] < 0}
check "trailing spaces after the macro name are allowed" {[pv_lef_macros "MACRO unpu_top   \nEND unpu_top\n"] eq "unpu_top"}
check "tab after the keyword is allowed" {[pv_lef_macros "MACRO\tunpu_top\nEND unpu_top\n"] eq "unpu_top"}
check "an indented MACRO line is not a macro" {[pv_lef_macros "  MACRO unpu_top\nEND unpu_top\n"] eq ""}
check "a column-0 'MACRO x REAL ;' line is not a macro (more than the name on the line)" {[pv_lef_macros "MACRO expanded_util REAL ;\n"] eq ""}
check "MACRO lines inside PROPERTYDEFINITIONS are ignored even at column 0" {[pv_lef_macros "PROPERTYDEFINITIONS\nMACRO inside\nEND PROPERTYDEFINITIONS\nMACRO real\nEND real\n"] eq "real"}
check "after END PROPERTYDEFINITIONS macros count again" {[pv_lef_macros "PROPERTYDEFINITIONS\n  MACRO a REAL ;\nEND PROPERTYDEFINITIONS\nMACRO b\nEND b\nMACRO c\nEND c\n"] eq "b c"}
# the old bad cases, now with the real header in front
set bad2 $realhdr
foreach n $names { append bad2 [make_macro $n 2 1.12 5.6] }
append bad2 "END LIBRARY\n"
check "122 library macros without unpu_top are still rejected (with the real header)" {[llength [pv_lef_macros $bad2]] == 122 && [string match "*holds 0 'MACRO unpu_top' entries*122 MACRO entries in total*" [lindex [pv_lef_check $bad2 unpu_top 206 885.6 885.6] 0]]}
set two2 "${realhdr}${realmac}${realmac}"
set pr [pv_lef_check $two2 unpu_top 206 885.6 885.6]
check "two real unpu_top macros are still rejected" {[llength $pr] >= 1 && [string match "*holds 2 'MACRO unpu_top' entries, 1 expected*" [lindex $pr 0]]}
set lib2 "${realhdr}${realmac}MACRO inv0d4\n  SIZE 1.12 BY 5.6 ;\nEND inv0d4\n"
set pr [pv_lef_check $lib2 unpu_top 206 885.6 885.6]
check "a library macro at column 0 next to unpu_top is still rejected" {[llength $pr] == 1 && [string match "*2 MACRO entries, 1 expected (extra: inv0d4)*" [lindex $pr 0]]}
set pr [pv_lef_check "${realhdr}[make_macro unpu_top 200 885.6 885.6]" unpu_top 206 885.6 885.6]
check "wrong PIN count is still rejected with the real header" {[llength $pr] == 1 && [string match "*202 PIN entries, 206 expected*" [lindex $pr 0]]}
set pr [pv_lef_check "${realhdr}[make_macro unpu_top 204 817.6 817.6]" unpu_top 206 885.6 885.6]
check "wrong SIZE is still rejected with the real header" {[llength $pr] == 1 && [string match "*SIZE is 817.6 x 817.6*" [lindex $pr 0]]}
# the rename helper counts the same way
set filled2 "${realhdr}[make_macro unpu_top_filled 204 885.6 885.6]END LIBRARY\n"
lassign [pv_lef_rename $filled2 unpu_top_filled unpu_top] ren n
check "rename with the real header changes exactly the MACRO line and the END line" {$n == 2}
check "rename leaves the property definition alone" {[string first "  MACRO expanded_util REAL ;" $ren] >= 0}
check "renamed file is accepted" {[pv_lef_check $ren unpu_top 206 885.6 885.6] eq ""}
check "renaming the name of the property definition is an error (it is not a macro)" {[catch {pv_lef_rename $real expanded_util other}]}
check "rename counts the same macro lines as the check (macro_lines)" {[llength [pv_lef_macro_lines $filled2]] == 1 && [lindex [lindex [pv_lef_macro_lines $filled2] 0] 1] eq "unpu_top_filled"}
check "rename keeps the length difference exactly the name difference" {[string length $ren] == [string length $filled2] - 2 * [string length _filled]}

puts "RESULT: $npass passed, $nfail failed"
if {$nfail > 0} { exit 1 }
exit 0
