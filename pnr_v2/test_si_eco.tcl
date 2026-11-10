# ==============================================================================
# Test: test_si_eco.tcl (task 098)  -- the SI-on ECO round: pure parts
# Run : tclsh pnr_v2/test_si_eco.tcl   (no PrimeTime / ICC2 needed)
# ==============================================================================
set here [file dirname [file normalize [info script]]]
proc read_file {p} { set fp [open $p r]; set t [read $fp]; close $fp; return $t }
set nfail 0; set npass 0
proc check {name cond} {
    global nfail npass
    if {[uplevel 1 [list expr $cond]]} { incr npass } else { incr nfail; puts "FAIL $name   ($cond)" }
}
proc has {text lit} { return [expr {[string first $lit $text] >= 0}] }
proc errmsg {script} { if {[catch {uplevel 1 $script} m]} { return $m }; return "" }

source $here/pt/pt_common.tcl
set apply [read_file $here/pt_eco_apply.tcl]
foreach n {079 092 093 095} {
    set b [string first "# ---- BEGIN PURE TCL $n ----" $apply]; set e [string first "# ---- END PURE TCL $n ----" $apply]
    eval [string range $apply $b $e]
}
set common [read_file $here/pt/pt_common.tcl]

# ---- 1. the SI folder of the change files ----
check "SI folder: SI off keeps pt and pt_<tag>" {[eco098_pt_dir /p "" 0] eq "/p/pt" && [eco098_pt_dir /p route3 0] eq "/p/pt_route3"}
check "SI folder: SI on -> pt_si and pt_<tag>_si" {[eco098_pt_dir /p "" 1] eq "/p/pt_si" && [eco098_pt_dir /p route3 1] eq "/p/pt_route3_si"}
check "SI folder: the apply and the probes agree (pt_tag_paths gives the same folder name)" {[file tail [eco098_pt_dir /r route3 1]] eq [file tail [lindex [pt_tag_paths /r route3 1] 1]] && [file tail [eco098_pt_dir /r "" 1]] eq [file tail [lindex [pt_tag_paths /r "" 1] 1]]}
foreach bad {2 on "" -1} { check "SI folder: UNPU_PT_SI='$bad' is an ERROR 098" {[string match "ERROR 098: UNPU_PT_SI=*" [errmsg {eco098_pt_dir /p "" $bad}]]} }
check "kinds: setup has its own change, count and class files and no second setup file" {[eco095_kind_files setup /p 1] eq "main /p/pt_eco_setup_changes_icc2.tcl setup {} count /p/pt_eco_setup_expected_count.txt classes /p/pt_eco_setup_pin_classes.txt"}
check "kinds: hold with SI off still reads the optional setup file (task 079 behaviour)" {[dict get [eco095_kind_files hold /p 0] setup] eq "/p/pt_eco_setup_changes_icc2.tcl" && [dict get [eco095_kind_files hold /p] setup] eq "/p/pt_eco_setup_changes_icc2.tcl"}
check "kinds: hold with SI on does NOT read the setup file (one kind per call)" {[dict get [eco095_kind_files hold /p 1] setup] eq ""}
check "kinds: drc unchanged" {[eco095_kind_files drc /p] eq "main /p/pt_eco_drc_changes_icc2.tcl setup {} count /p/pt_eco_drc_expected_count.txt classes /p/pt_eco_drc_pin_classes.txt"}
check "kinds: the error text names setup" {[has [errmsg {eco095_kind_files nope /p}] "hold (the default), drc or setup"]}

# ---- 2. the setup change file with size_cell lines ----
set sf "current_instance {u_csr}\nsize_cell {U77} oai222d2\ncurrent_instance\nsize_cell {u_apb/U46} an03d1\nsize_cell \[get_cells {u_seq/U10}\] nd02d2\n"
set pr [eco079_parse $sf]
set cmds [dict get $pr cmds]
check "setup change file: 3 size_cell, no errors, hierarchy applied" {[llength [dict get $pr errors]] == 0 && [llength $cmds] == 3 && [lmap c $cmds {dict get $c type}] eq "size_cell size_cell size_cell" && [dict get [lindex $cmds 0] full_inst] eq "u_csr/U77" && [dict get [lindex $cmds 1] full_inst] eq "u_apb/U46" && [dict get [lindex $cmds 2] ref] eq "nd02d2"}
set ei [eco098_earlier_instances [list $sf "current_instance {u_dma}\ninsert_buffer \[get_pins {U1/Z}\] buffd3 -new_net_names {n1} -new_cell_names {B1}\n"]]
check "earlier-round instances: size_cell instances and inserted cells, sorted unique" {$ei eq "u_apb/U46 u_csr/U77 u_dma/B1 u_seq/U10"}

# ---- 3. the speed-up check ----
check "faster: an02d4 -> an02d7, buffd1 -> buffd3, oai222d1 -> oai222d2, inv0d0 -> inv0d1" {[pt_ref_faster an02d4 an02d7] && [pt_ref_faster buffd1 buffd3] && [pt_ref_faster oai222d1 oai222d2] && [pt_ref_faster inv0d0 inv0d1]}
check "not faster: a smaller or equal drive, another family, a name without a number" {![pt_ref_faster buffd3 buffd1] && ![pt_ref_faster buffd1 buffd1] && ![pt_ref_faster oai222d2 oai22d4] && ![pt_ref_faster buffd1 buffda] && ![pt_ref_faster buffda buffd3] && ![pt_ref_faster "" buffd3] && ![pt_ref_faster an02d4 nd02d7]}
check "split: prefix and drive" {[pt_ref_split an02d4] eq "an02d 4" && [pt_ref_split dfcrq2] eq "dfcrq 2" && [pt_ref_split buffda] eq ""}
check "speed text names the relation" {[has [pt_ref_speed_text an02d4 an02d7] "larger drive of the same function (faster)"] && [has [pt_ref_speed_text buffd3 buffd1] "NOT a larger drive"] && [has [pt_ref_speed_text "" buffd1] "speed-up not provable"] && [has [pt_ref_speed_text an02d4 nd02d7] "not the same family"]}
check "class: a cone cell to a faster reference is allowed (cone_faster)" {[pt_setup_size_class 1 0 oai222d1 oai222d2] eq "cone_faster" && ![pt_eco_class_violation cone_faster] && ![eco093_violation cone_faster]}
check "class: a cone cell to a slower or incomparable reference is a violation (cone_slower)" {[pt_setup_size_class 1 0 oai222d2 oai222d1] eq "cone_slower" && [pt_setup_size_class 1 0 oai222d2 oai22d2] eq "cone_slower" && [pt_eco_class_violation cone_slower] && [eco093_violation cone_slower]}
check "class: a clock cell is a violation, a cell off the cone is resize_other, unknown stays unknown" {[pt_setup_size_class 0 1 buffd1 buffd3] eq "clock_net" && [pt_setup_size_class 0 0 buffd1 buffd3] eq "resize_other" && [pt_setup_size_class "" 0 a b] eq "unknown" && [pt_setup_size_class 0 "" a b] eq "unknown" && ![pt_eco_class_violation resize_other]}
check "the violation lists of the probe side and the apply side are equal (with cone_slower)" {[lsort [lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize cone_slower cone_faster resize_other clock_net unknown} {expr {[pt_eco_class_violation $c] ? $c : [continue]}}]] eq [lsort [lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize cone_slower cone_faster resize_other clock_net unknown} {expr {[eco093_violation $c] ? $c : [continue]}}]]}
check "class texts exist for the new classes" {[has [pt_eco_class_text093 cone_faster] "FASTER"] && [has [pt_eco_class_text093 cone_slower] "VIOLATION"] && [has [pt_eco_class_text093 resize_other] "outside the cone"]}

# ---- 4. the class file check of the apply (size rows) ----
set rows [dict get [eco093_parse_classes "# c\n1 u_csr/U77 oai222d2 cone_faster net=n77 drivers=?\n2 u_apb/U46 an03d1 resize_other net=n46 drivers=?\n3 u_seq/U10 nd02d2 resize_other net=? drivers=?\n"] rows]
lassign [eco098_check_size $cmds $rows] lines probs
check "size classes: 3 rows for 3 changes, no problem" {[llength $lines] == 3 && [llength $probs] == 0 && [has [lindex $lines 0] "class cone_faster"]}
lassign [eco098_check_size $cmds [dict remove $rows 2]] lines probs
check "size classes: a change without a row is a problem" {[llength $probs] == 1 && [has [lindex $probs 0] "has no line in the class file"]}
set rows_v [dict replace $rows 1 [dict replace [dict get $rows 1] cls cone_slower]]
lassign [eco098_check_size $cmds $rows_v] lines probs
check "size classes: a violation class is a problem" {[llength $probs] == 1 && [has [lindex $lines 0] "(VIOLATION)"] && [has [lindex $probs 0] "cone_slower"]}
set rows_o [dict replace $rows 2 [dict replace [dict get $rows 2] pin u_apb/U99]]
lassign [eco098_check_size $cmds $rows_o] lines probs
check "size classes: a row for another instance means another change file" {[has [lindex $probs 0] "belongs to another change file"]}

# ---- 5. the result lines and the guards ----
set PT_SI_ENABLE 0
check "result line SI off: unchanged text" {[pt_eco_result_line 1 x] eq "PROBE RESULT: ECO RAN: x"}
set PT_SI_ENABLE 1; set PT_SI_SOURCE env; set PT_SDC_MODE exported; set PT_SDC_SOURCE default
check "result line SI on: carries (SI ON)" {[pt_eco_result_line 1 x] eq "PROBE RESULT (SI ON): ECO RAN: x"}
check "result lines: not closed and needs a decision" {[has [pt_eco_result_line notclosed y] "SIZE-ONLY ECO DOES NOT CLOSE THE VIOLATORS (the user decides): y"] && [has [pt_eco_result_line needsdecision y] "ECO NEEDS A DECISION (nothing is applied): y"]}
check "guard: the hold and setup probes may run with SI on" {[errmsg {pt_probe_si_guard pt_eco_probe.tcl 1}] eq ""}
check "guard: the max-transition probe still refuses SI on" {[string match "PT ERROR: pt_eco_drc_probe.tcl is an ECO probe that runs with SI off*" [errmsg {pt_probe_si_guard pt_eco_drc_probe.tcl}]]}
set PT_SDC_MODE legacy
check "guard: the legacy SDC is refused even with SI allowed" {[string match "PT ERROR: pt_eco_probe.tcl is an ECO probe and runs on the exported SDC*" [errmsg {pt_probe_si_guard pt_eco_probe.tcl 1}]]}
set PT_SDC_MODE exported; set PT_SI_ENABLE 0

# ---- 6. source checks ----
set sp [read_file $here/pt/pt_eco_setup_probe.tcl]
set code [join [regexp -all -inline -line {^[^#]*$} $sp] \n]
check "setup probe: size_cell only (no insert_buffer method, an insertion in the result stops the probe)" {[has $sp {-methods {size_cell}}] && ![has $code {-methods {size_cell insert_buffer}}] && [has $sp needsdecision]}
check "setup probe: the cone is computed but NOT protected; the clock network and the earlier cells are" {[has $sp {pt_in2out_cone}] && ![has $code {pt_cone_protect}] && [has $sp {pt_clock_protect}] && [has $sp {*PTECO_HOLD*}] && [has $sp {earlybuf_*}] && [has $sp {pt_eco_drc_changes_icc2.tcl}]}
check "setup probe: stale count and class files are deleted first, written only when the violators are closed" {[has $sp {file delete -force ${PT_RPT_DIR}/$f}] && [string first {pt_eco_setup_expected_count.txt w} $sp] > [string first "elseif {\$n_after > 0}" $sp] && [string first "pt_eco_setup_pin_classes.txt w" $sp] > [string first "elseif {\$n_after > 0}" $sp]}
check "setup probe: per change cell, old/new reference, speed relation, net, read path, area" {[has $sp {on the read path (in2out cone)}] && [has $sp {pt_ref_speed_text $oldref $new}] && [has $sp {output net}] && [has $sp {area}]}
check "setup probe: SI on and SI off views before and after in the same session" {[has $sp {pt_measure_views BEFORE}] && [has $sp {pt_measure_views AFTER}] && [has $common {si_enable_analysis false}] && [has $common {use the two-run procedure}]}
check "setup probe: the margin option falls back to the form without it" {[has $sp {-setup_margin $PT_ECO_SETUP_MARGIN}] && $PT_ECO_SETUP_MARGIN == 0.02 && [has $sp {size_cell, no margin option}]}
set hp [read_file $here/pt/pt_eco_probe.tcl]
check "hold probe: allowed with SI on; hold margin stays 0.05" {[has $hp {pt_probe_si_guard pt_eco_probe.tcl 1}] && $PT_ECO_HOLD_MARGIN == 0.05}
check "apply source: UNPU_PT_SI read, the folder from eco098_pt_dir, the setup kind is size_cell only and needs the class file" {[has $apply {set PT_SI 0}] && [has $apply {eco098_pt_dir $PNR_DIR $PT_TAG $PT_SI}] && [has $apply {the setup kind is size_cell only}] && [has $apply {for the kind setup it is REQUIRED}] && [has $apply {CHECK size classes}]}
check "apply source: earlier-round cells are protected and may not be targeted; the gates are unchanged" {[has $apply {earlier-round cells from}] && [has $apply {a cell of an earlier round (protected)}] && [has $apply {set ea_names [concat $ea_names $ea_early $ea_holdprev $ea_earlier]}] && [has $apply {set GATE_TOL_SETUP  0.005}]}
check "apply source: the relocation of 097 applies to the setup resizes (same size_cell branch)" {[has $apply {RELOCATE it to the nearest free run}]}

check "apply source: in the SI-on round the marker cells of the first hold ECO are earlier-round cells (protected, not new, must still be there); the drc rule is unchanged" {[has $apply {set ea_si_round [expr {$PT_SI && $ECO_KIND ne "drc"}]}] && [has $apply {CHECK earlier-round cells with the marker}] && [has $apply {earlier-round cells vanished}] && [has $apply {CHECK hold-ECO cells}]}

puts "RESULT: $npass passed, $nfail failed"
exit [expr {$nfail > 0}]
