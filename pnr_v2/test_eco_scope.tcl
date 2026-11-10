# ==============================================================================
# Test: test_eco_scope.tcl (tasks 092, 093)
# Run : tclsh pnr_v2/test_eco_scope.tcl   (no PrimeTime / ICC2 needed)
# Tests the reg2out scope of the PrimeTime hold ECO: UNPU_ECO_SCOPE, the target selection on sample violation rows (the 7 register-to-output endpoints of the route checkpoint), the release of the
# nets that a flop drives into the read mux (mock of the PrimeTime commands), the cone check on a sample change file, the class of each insertion, the count file, and the apply script's tagged
# input folder and the protection of the earlybuf_* cells.
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
foreach n {079 092 093} {
    set b [string first "# ---- BEGIN PURE TCL $n ----" $apply]; set e [string first "# ---- END PURE TCL $n ----" $apply]
    if {$b < 0 || $e < $b} { puts "FAIL pure block $n not found"; exit 1 }
    eval [string range $apply $b $e]
}

# ---- 1. the scope variable ----
check "scope: unset -> in2reg, source default" {[pt_eco_scope_resolve {}] eq "in2reg default"}
check "scope: reg2out from the environment" {[pt_eco_scope_resolve {reg2out}] eq "reg2out {environment UNPU_ECO_SCOPE}"}
check "scope: in2reg from the environment" {[pt_eco_scope_resolve {in2reg}] eq "in2reg {environment UNPU_ECO_SCOPE}"}
foreach bad {"" "Reg2out" "reg2reg" "all" "in2out"} { check "scope rejected: '$bad'" {[string match "PT ERROR: UNPU_ECO_SCOPE=*" [errmsg {pt_eco_scope_resolve [list $bad]}]]} }

# ---- 2. targets on sample rows ----
proc row {ep sp spk epk slack} { return [dict create endpoint $ep startpoint $sp sp_kind $spk ep_kind $epk slack $slack group clk] }
set rows {}
foreach {ep sl} {{prdata[27]} -0.0238 {prdata[9]} -0.0069 {prdata[17]} -0.0053 {prdata[21]} -0.0029 {prdata[12]} -0.0003 {prdata[3]} -0.0002 {prdata[30]} -0.0001} {
    lappend rows [row $ep u_csr/dest_c_reg_reg_5_/CK pin port $sl]   ;# placeholders: kinds as pt_collect_violations writes them (startpoint a pin, endpoint a port)
}
lappend rows [row u_dma/stage_reg_1__14_/D dma_rdata\[14\] port pin -0.0100]   ;# an input-to-register row
lappend rows [row u_csr/x_reg/D u_csr/y_reg/CK pin pin -0.0050]                ;# register to register
lappend rows [row prdata\[5\] paddr\[3\] port port -0.0010]                       ;# input to output (not a register start)
check "reg2out: the 7 register-to-output endpoints, no other" {[llength [pt_eco_targets reg2out $rows]] == 7 && [lsort [lmap r [pt_eco_targets reg2out $rows] {dict get $r endpoint}]] eq [lsort {{prdata[27]} {prdata[9]} {prdata[17]} {prdata[21]} {prdata[12]} {prdata[3]} {prdata[30]}}]}
check "in2reg: only the port-fed register endpoint (the reg2out rows are excluded)" {[llength [pt_eco_targets in2reg $rows]] == 1 && [dict get [lindex [pt_eco_targets in2reg $rows] 0] endpoint] eq "u_dma/stage_reg_1__14_/D"}
check "reg2out: an input-to-output row is not a target" {[lsearch -exact [lmap r [pt_eco_targets reg2out $rows] {dict get $r endpoint}] prdata\[5\]] < 0}
check "reg2out: a register-to-register row is not a target" {[lsearch -exact [lmap r [pt_eco_targets reg2out $rows] {dict get $r endpoint}] u_csr/x_reg/D] < 0}
check "unreadable kinds belong to no scope" {[llength [pt_eco_targets reg2out [list [row a b "" port -1]]]] == 0 && [llength [pt_eco_targets in2reg [list [row a b port "" -1]]]] == 0}
check "target line: endpoint, startpoint, slack" {[lindex [pt_eco_target_lines [list [lindex $rows 0]]] 0] eq "prdata\[27\] <- u_csr/dest_c_reg_reg_5_/CK (slack -0.0238)"}

# ---- 3. the nets that a flop drives into the read mux are released (mock of the PrimeTime commands) ----
proc foreach_in_collection {v coll body} { upvar 1 $v x; foreach i $coll { set x $i; uplevel 1 $body } }
proc sizeof_collection {c} { return [llength $c] }
proc get_object_name {x} { return $x }
proc append_to_collection {var item} { upvar 1 $var v; lappend v $item }
set NETDRV [dict create n_qn {u_csr/dest_c_reg_reg_5_/QN} n_mid {u_csr/U10/ZN} n_port {} n_nodrv {} n_apb {u_apb/U5/Z}]
proc get_nets {args} { return n_port }          ;# the nets of the cone ports
proc pt_cone_net_pins {net dir} { global NETDRV; return [dict get $NETDRV $net] }
set cone [dict create cells {u_csr/U10 u_apb/U5} ports_c {prdata[3]} nets_c {n_qn n_mid n_port n_nodrv n_apb} nets {n_qn n_mid n_port n_nodrv n_apb}]
set new [pt_cone_nets_reg2out $cone]
check "net release: the flop-driven net (QN into the read mux) is released" {[lsearch -exact [dict get $new nets_c] n_qn] < 0}
check "net release: a net driven by a cone cell stays protected" {[lsearch -exact [dict get $new nets_c] n_mid] >= 0 && [lsearch -exact [dict get $new nets_c] n_apb] >= 0}
check "net release: a net on a cone port stays protected" {[lsearch -exact [dict get $new nets_c] n_port] >= 0}
check "net release: a net with no known driver stays protected (the safe direction)" {[lsearch -exact [dict get $new nets_c] n_nodrv] >= 0}
check "net release: the name list follows the collection" {[dict get $new nets] eq [lsort -unique [dict get $new nets_c]] && [llength [dict get $new nets_c]] == 4}
check "net release: the cone cells are unchanged" {[dict get $new cells] eq {u_csr/U10 u_apb/U5}}
check "net release: pure rule" {[pt_cone_net_keep {u_csr/dest_reg} {u_csr/U10}] == 0 && [pt_cone_net_keep {u_csr/U10} {u_csr/U10}] == 1 && [pt_cone_net_keep {} {u_csr/U10}] == 1 && [pt_cone_net_keep {u_csr/dest_reg u_csr/U10} {u_csr/U10}] == 1}
check "net release: everything released -> error" {[string match "PT ERROR: reg2out: every cone net was released*" [errmsg {pt_cone_nets_reg2out [dict create cells {x} ports_c {} nets_c {n_qn} nets {n_qn}]}]]}

# ---- 4. the cone check on a sample change file ----
set chg "current_instance {u_csr}\ninsert_buffer \[get_pins {dest_c_reg_reg_5_/QN}\] dl01d1 -new_net_names {net_PTECO_HOLD_NET1} -new_cell_names {U_PTECO_HOLD_BUF1}\ninsert_buffer \[get_pins {src_a_reg_reg_9_/QN}\] dl01d1 -new_net_names {net_PTECO_HOLD_NET2} -new_cell_names {U_PTECO_HOLD_BUF2}\ncurrent_instance\n"
set pr [eco079_parse $chg]
check "sample file parses: 2 insertions" {[llength [dict get $pr errors]] == 0 && [llength [dict get $pr cmds]] == 2}
set conecells {u_csr/U10 u_csr/ctmTdsLR_7 u_apb/U5}
check "change on a flop QN pin outside the cone: clean" {[llength [pt_cone_hits [dict get $pr cmds] $conecells {prdata[3]}]] == 0}
set bad "current_instance {u_csr}\ninsert_buffer \[get_pins {ctmTdsLR_7/Z}\] dl01d1 -new_net_names {a} -new_cell_names {b}\ninsert_buffer \[get_pins {U10/ZN}\] dl01d1 -new_net_names {c} -new_cell_names {d}\ncurrent_instance\ninsert_buffer \[get_ports {prdata\[3\]}\] dl01d1 -new_net_names {e} -new_cell_names {f}\nsize_cell {u_csr/U10} {oai222d2}\n"
set prb [eco079_parse $bad]
set hits [pt_cone_hits [dict get $prb cmds] $conecells {prdata[3]}]
check "changes on the buffer ctmTdsLR_*, on the read-mux cell pin, on the cone port and a resize of a cone cell: all 4 reported" {[llength [dict get $prb errors]] == 0 && [llength $hits] == 4}
check "hit texts name the objects" {[has [join [lmap h $hits {string cat [dict get $h what] " " [dict get $h name]}]] ctmTdsLR_7] && [has [join [lmap h $hits {string cat [dict get $h what] " " [dict get $h name]}]] {prdata[3]}]}

# ---- 5. the class of each insertion ----
check "class: flop output pin outside the cone is the expected form" {[pt_eco_classify_insert pin 0 1 1] eq "flop_output" && [string match "*expected form*" [pt_eco_class_text flop_output]]}
check "class: a pin of a cone cell is cone, whatever else" {[pt_eco_classify_insert pin 1 1 1] eq "cone" && [pt_eco_classify_insert pin 1 0 0] eq "cone"}
check "class: a port" {[pt_eco_classify_insert port 0 "" ""] eq "port"}
check "class: flop input / combinational outside the cone / unreadable" {[pt_eco_classify_insert pin 0 1 0] eq "flop_input" && [pt_eco_classify_insert pin 0 0 1] eq "other" && [pt_eco_classify_insert pin 0 "" 1] eq "unknown" && [pt_eco_classify_insert pin 0 1 ""] eq "unknown"}
check "class texts exist for all classes" {[llength [lsearch -all -inline -not -glob [lmap c {flop_output flop_input cone port other unknown} {pt_eco_class_text $c}] "class unknown*"]] == 5}

# ---- 6. the count file ----
set cft [pt_eco_expected_text 7 "Final ECO Summary" /x/pt_route/pt_eco_hold_changes_icc2.tcl reg2out]
lassign [eco079_expect_decide 1 $cft 112 EXPECT_HOLD_CMDS] n src warn
check "count file with a scope line: the apply parser still reads commands 7" {$n == 7 && $warn eq "" && [string match "*\nscope reg2out\n*" $cft]}
check "count file without a scope: as before" {![string match "*scope*" [pt_eco_expected_text 112 s /x/f.tcl]] && [pt_eco_expected_text 112 s /x/f.tcl] eq [pt_eco_expected_text 112 s /x/f.tcl ""]}

# ---- 7. the probe source ----
set pb [read_file $here/pt/pt_eco_probe.tcl]
check "probe reads UNPU_ECO_SCOPE once, through the validator, before the session is prepared" {[regexp -all {::env\(UNPU_ECO_SCOPE\)} $pb] == 2 && [string first "pt_eco_scope_resolve" $pb] < [string first "pt_prepare_session hold" $pb]}
check "probe prints the scope with its source and the folders" {[has $pb {>>> 092 ECO scope $eco_scope ($eco_scope_src); input folder $PT_OUT_DIR, change files and reports in $PT_RPT_DIR}]}
check "probe lists the targets and their count" {[has $pb {>>> 092 scope $eco_scope: [llength $eco_targets] of $n_before hold violators are targets}] && [has $pb {>>> 092   target: $l}]}
check "the net release runs only in reg2out and before the protection" {[regexp {if \{\$eco_scope eq "reg2out"\} \{[^\n]*\n[^\n]*\n[^\n]*pt_cone_nets_reg2out} $pb] && [string first "pt_cone_nets_reg2out" $pb] < [string first "pt_cone_protect \$cone" $pb]}
check "the cone cells stay protected and the AFTER check of the change file is still there (pin level since 093)" {[has $pb {pt_cone_hits_pin [dict get $chk cmds] $eco_clsd $cone_cells}] && [has $pb {pt_eco_result_line touches}] && [has $pb {pt_cone_protect $cone}]}
check "every insertion is printed with pin, net, driver and class; classes summed" {[has $pb {>>> 093 insertion [dict get $c idx]: pin [dict get $c full_pin]}] && [has $pb {>>> 093 insertions by class}]}
check "remaining targets after the ECO are printed" {[has $pb {remaining after the ECO}] && [has $pb {remaining target: $l}]}
set lit_cf "\$countfile\x7d\] \$eco_scope\]"
check "the count file carries the scope" {[has $pb $lit_cf]}
check "all outputs go to PT_RPT_DIR (the tag folder): no literal pt/ or outputs/ path" {![regexp {pnr_icc2/(pt|outputs)\y} [join [lmap l [split $pb "\n"] {expr {[string match "#*" [string trim $l]] ? "" : $l}}] "\n"]]}
check "the hold margin is still the parameter PT_ECO_HOLD_MARGIN (0.05)" {[has $pb {-hold_margin $PT_ECO_HOLD_MARGIN}] && $PT_ECO_HOLD_MARGIN == 0.05}
check "banner names the scope" {[has $pb {scope $eco_scope)}]}
check "the protection of the cone is still on by default" {$PT_CONE_PROTECT == 1 && $PT_CONE_PROTECT_NETS == 1}

# ---- 8. the apply script ----
check "apply: no tag -> pnr_icc2/pt" {[eco092_pt_dir /r/pnr_icc2 ""] eq "/r/pnr_icc2/pt"}
check "apply: tag route -> pnr_icc2/pt_route" {[eco092_pt_dir /r/pnr_icc2 route] eq "/r/pnr_icc2/pt_route"}
foreach bad [list "a b" "../x" "a-b" [string repeat a 33]] { check "apply: tag rejected '$bad'" {[string match "ERROR 092: UNPU_PT_TAG=*" [errmsg {eco092_pt_dir /r/pnr_icc2 $bad}]]} }
check "apply: the PrimeTime and the ICC2 side use the same folder for a tag" {[lindex [pt_tag_paths /r route] 1] eq [eco092_pt_dir /r/pnr_icc2 route]}
check "protect: nothing to protect -> not ok (wrong block)" {[lindex [eco092_protect_decide 0 0] 0] == 0}
check "protect: run 3 form (54 earlybuf, no antbuf) ok" {[lindex [eco092_protect_decide 0 54] 0] == 1 && [string match "0 antbuf_* and 54 earlybuf_* cells are protected" [lindex [eco092_protect_decide 0 54] 1]]}
check "protect: run 1 form (15 antbuf) ok and both ok" {[lindex [eco092_protect_decide 15 0] 0] == 1 && [lindex [eco092_protect_decide 15 54] 0] == 1}
check "count: unchanged -> no problem; changed -> sentence with both numbers" {[eco092_count_problem earlybuf_* 54 54] eq "" && [string match "earlybuf_* count 54 before the ECO, 53 after it" [eco092_count_problem earlybuf_* 54 53]]}
check "apply source: UNPU_PT_TAG read, folder via eco092_pt_dir, missing folder is an ERROR 092" {[has $apply {info exists ::env(UNPU_PT_TAG)}] && [has $apply {set PT_DIR      [eco092_pt_dir $PNR_DIR $PT_TAG]}] && [has $apply {ERROR 092: UNPU_PT_TAG=$PT_TAG but the folder}]}
check "apply source: every input file is under PT_DIR" {[has $apply {set ECO_HOLD_FILE   "${PT_DIR}/}] && [has $apply {set ECO_SETUP_FILE  "${PT_DIR}/}] && [has $apply {set ECO_COUNT_FILE  "${PT_DIR}/}]}
check "apply source: the earlybuf_* cells are found, protected (snapshot) and counted before and after" {[has $apply {get_cells -quiet ${EARLY_PREFIX}_*}] && [has $apply {set ea_names [concat $ea_names $ea_early]}] && [has $apply {eco092_count_problem}] && [has $apply {${EARLY_PREFIX}_* count: $ea_nearly1 (before the ECO $ea_nearly)}]}
check "apply source: the typed 15 is gone" {![string match "*EXPECT_ANTBUF*" [join [lmap l [split $apply "\n"] {expr {[string match "*The old EXPECT_ANTBUF*" $l] ? "" : $l}}] "\n"]]}
check "apply source: the gates are unchanged (in2out and whole-design setup, tolerance GATE_TOL_SETUP)" {[has $apply {eco079_gate_check $glabel $gb $ga $gtol}] && [has $apply {set GATE_TOL_SETUP  0.005}] && [has $apply {the in2out group}]}
check "apply source: the block is still saved over unpu_top_route only after the checks (the user copies the library first)" {[string first "save_block -force -as \${DESIGN_NAME}_route" $apply] > [string first "NOTHING SAVED" $apply]}

# ---- 9. task 093: the cone check at PIN level ----
# mock of the PrimeTime commands used by pt_eco_insert_facts_pin. The 9 pins are the real ones of run 3 (checkpoint route3); the NET names are placeholders (the log of the server run has them), the drivers follow the
# pattern of the log: the QN pin of a u_csr flop (dest_c_reg_reg_*, src_a_reg_reg_*, src_b_reg_reg_*), a sequential cell.
set real9 {{u_csr/U77/A2 dest_c_reg_reg_5_} {u_csr/U77/C2 src_a_reg_reg_9_} {u_csr/U77/B2 src_b_reg_reg_9_} {u_csr/U9/B2 dest_c_reg_reg_13_} {u_csr/U74/C2 src_a_reg_reg_23_} {u_csr/U361/B2 src_b_reg_reg_23_} {u_csr/U79/B2 dest_c_reg_reg_21_} {u_csr/U72/C2 src_a_reg_reg_17_} {u_csr/U398/A2 src_b_reg_reg_27_}}
array set PINNET {}; array set PINDIR {}; array set CELLSEQ {}
set NETDRV [dict create]
set mux_cells {}
set bn 0
foreach pr $real9 {
    lassign $pr pin flop
    incr bn
    set net "u_csr/qn_$flop"                                  ;# the ORIGINAL net (before the ECO): driven by the QN pin of a u_csr flop
    set bufc "u_csr/U_PTECO_HOLD_BUF$bn"; set newnet "u_csr/net_PTECO_HOLD_NET$bn"
    set PINNET($pin) $newnet; set PINDIR($pin) in             ;# AFTER the ECO the load pin sees the new net, driven by the new buffer
    dict set NETDRV $newnet [list "$bufc/Z"]
    set CELLSEQ($bufc) false
    set PINNET($bufc/I) $net; set PINDIR($bufc/I) in; set PINDIR($bufc/Z) out; set PINNET($bufc/Z) $newnet   ;# the buffer's input pin sits on the original net
    dict set NETDRV $net [list "u_csr/$flop/QN"]
    set CELLSEQ(u_csr/$flop) true
    set cell [eco079_pin_cell $pin]; set CELLSEQ($cell) false
    lappend mux_cells $cell
}
set mux_cells [lsort -unique $mux_cells]
# a kept cone net (driven by the decode cell U50, a cone cell), a pin on it, a driver pin, a combinational driver of a released net
set PINNET(u_csr/U77/A1) u_csr/n_dec;   set PINDIR(u_csr/U77/A1) in;  dict set NETDRV u_csr/n_dec {u_csr/U50/ZN}; set CELLSEQ(u_csr/U50) false
set PINNET(u_csr/U77/ZN) u_csr/n_rd;    set PINDIR(u_csr/U77/ZN) out; dict set NETDRV u_csr/n_rd {u_csr/U77/ZN}
set PINNET(u_csr/U9/A2)  u_csr/n_comb;  set PINDIR(u_csr/U9/A2) in;   dict set NETDRV u_csr/n_comb {u_csr/U33/ZN}; set CELLSEQ(u_csr/U33) false
set PINNET(u_csr/U9/C2)  u_csr/n_nodrv; set PINDIR(u_csr/U9/C2) in;   dict set NETDRV u_csr/n_nodrv {}
set PINNET(u_csr/U9/C1)  u_csr/n_unk;   set PINDIR(u_csr/U9/C1) in;   dict set NETDRV u_csr/n_unk {u_csr/Ux/Z}      ;# the driver's is_sequential is unreadable (no entry in CELLSEQ)
set PINNET(u_csr/U9/B1)  u_csr/n_far;   set PINDIR(u_csr/U9/B1) in;   dict set NETDRV u_csr/n_far {u_csr/dest_c_reg_reg_5_/QN}   ;# a net that is in neither list
set PINNET(u_csr/dest_c_reg_reg_5_/QN) u_csr/qn_dest_c_reg_reg_5_; set PINDIR(u_csr/dest_c_reg_reg_5_/QN) out    ;# a flop output pin outside the cone (the 092 form)
set CELLSEQ(u_csr/Ux) maybe
set cone_cells [concat $mux_cells {u_csr/U50 u_csr/U33 u_csr/Ux}]
proc get_pins {args} {
    global PINDIR
    if {[lindex $args 0] eq "-quiet" && [lindex $args 1] eq "-of_objects"} {   ;# the input pin of a (buffer) cell
        set c [lindex $args 2]
        return [expr {[info exists PINDIR($c/I)] ? [list $c/I] : {}}]
    }
    set p [lindex $args end]; return [expr {[info exists PINDIR($p)] ? [list $p] : {}}]
}
proc get_cells {args} {
    if {[lindex $args 0] eq "-quiet" && [lindex $args 1] eq "-of_objects"} { return [list [eco079_pin_cell [lindex $args 2]]] }
    global CELLSEQ; set c [lindex $args end]; return [expr {[info exists CELLSEQ($c)] ? [list $c] : {}}]
}
proc get_nets {args} { global PINNET; set p [lindex $args end]; return [expr {[info exists PINNET($p)] ? [list $PINNET($p)] : {}}] }
proc get_attribute {obj attr} {
    global PINDIR CELLSEQ
    if {$attr eq "direction"} { return $PINDIR($obj) }
    if {$attr eq "is_sequential"} { return $CELLSEQ($obj) }
    error "mock: attribute $attr"
}
catch {unset pt_cone_h}; catch {unset pt_cone_seqc}
set kept_nets {u_csr/n_dec u_csr/n_rd u_csr/n_comb_kept}
set rel_nets [lmap pr $real9 {string cat u_csr/qn_ [lindex $pr 1]}]
lappend rel_nets u_csr/n_comb u_csr/n_nodrv u_csr/n_unk u_csr/qn_dest_c_reg_reg_5_
set cone93 [dict create cells $cone_cells ports {prdata[3]} nets $kept_nets released [lsort -unique $rel_nets]]
proc cls_of {objkind pin {newcell ""}} {
    global cone93
    set fx [pt_eco_insert_facts_pin $objkind $pin $cone93 $newcell]
    return [pt_eco_pin_class $objkind [dict get $fx in_cone] [dict get $fx dir] [dict get $fx state] [dict get $fx drv_seq] [dict get $fx is_seq] [dict get $fx is_out]]
}
check "net state: kept / released / none / unreadable" {[pt_pin_net_state a {a b} {c}] eq "kept" && [pt_pin_net_state c {a b} {c}] eq "released" && [pt_pin_net_state z {a b} {c}] eq "none" && [pt_pin_net_state "" {a} {c}] eq ""}
check "net state: a net in both lists is kept (the safe direction)" {[pt_pin_net_state a {a} {a}] eq "kept"}
# the 9 real pins
set table {}
set counts [dict create load_flop 0 load_comb 0 flop_output 0 flop_input 0 other 0 port 0 cone_net 0 cone_driver 0 cone_port 0 unknown 0]
set chg9 "current_instance {u_csr}\n"
set k 0
foreach pr $real9 {
    lassign $pr pin flop
    incr k
    set rel [string range $pin [expr {[string length u_csr/] }] end]
    append chg9 "insert_buffer \[get_pins {$rel}\] buffd1 -new_net_names {net_PTECO_HOLD_NET$k} -new_cell_names {U_PTECO_HOLD_BUF$k}\n"
}
append chg9 "current_instance\n"
set p9 [eco079_parse $chg9]
check "the 9 real pins parse as 9 insertions" {[llength [dict get $p9 errors]] == 0 && [llength [dict get $p9 cmds]] == 9 && [dict get [lindex [dict get $p9 cmds] 0] full_pin] eq "u_csr/U77/A2"}
set clsd [dict create]
set rows9 {}
foreach c [dict get $p9 cmds] {
    set fx [pt_eco_insert_facts_pin [dict get $c objkind] [dict get $c full_pin] $cone93 [dict get $c cell]]
    set cls [pt_eco_pin_class [dict get $c objkind] [dict get $fx in_cone] [dict get $fx dir] [dict get $fx state] [dict get $fx drv_seq] [dict get $fx is_seq] [dict get $fx is_out]]
    dict set clsd [dict get $c idx] $cls
    dict incr counts $cls
    lappend rows9 [pt_eco_class_row [dict get $c idx] [dict get $c full_pin] [dict get $c ref] $cls [dict get $fx net] [dict get $fx drivers]]
    lappend table "[dict get $c full_pin] | orig net [dict get $fx net] | orig driver [join [dict get $fx drivers] ,] | after ECO [dict get $fx new_net] ([dict get $fx new_driver]) | $cls"
}
check "all 9 real pins are in the cone cells (the old cell-level check called all 9 a hit)" {[llength [pt_cone_hits [dict get $p9 cmds] $cone_cells {prdata[3]}]] == 9}
check "all 9 real pins are class load_flop" {[dict get $counts load_flop] == 9 && [llength [lsort -unique [dict values $clsd]]] == 1}
check "the pin-level check finds no hit for the 9" {[llength [pt_cone_hits_pin [dict get $p9 cmds] $clsd $cone_cells]] == 0}
check "class summary for 9 of load_flop" {[pt_eco_class_summary $counts] eq "9 load pin on a flop-driven net (safe: starts at a flop)"}
set resline [pt_eco_result_line 1 "9 changes proposed, change file /x/pt_route3/pt_eco_hold_changes.tcl (none touches the in2out cone). Pin classes: [pt_eco_class_summary $counts]"]
check "PROBE RESULT line: ECO RAN: 9 changes proposed, then the class summary" {[string match "PROBE RESULT: ECO RAN: 9 changes proposed, change file * Pin classes: 9 load pin on a flop-driven net (safe: starts at a flop)" $resline]}
# violations and the defences
check "a pin on a KEPT cone net is cone_net (violation)" {[cls_of pin u_csr/U77/A1] eq "cone_net" && [pt_eco_class_violation cone_net]}
check "a driver pin of a cone cell is cone_driver (violation)" {[cls_of pin u_csr/U77/ZN] eq "cone_driver" && [pt_eco_class_violation cone_driver]}
check "a load pin on a released net with a combinational driver outside the cone: load_comb, not a violation, with its own text" {[cls_of pin u_csr/U9/A2] eq "load_comb" && ![pt_eco_class_violation load_comb] && [has [pt_eco_class_text093 load_comb] "read it"]}
check "an unreadable pin (not found) in a cone cell is unknown (violation)" {[cls_of pin u_csr/U77/B1] eq "unknown" && [pt_eco_class_violation unknown]}
check "a released net with no driver is unknown" {[cls_of pin u_csr/U9/C2] eq "unknown"}
check "a released net whose driver's is_sequential is unreadable is unknown" {[cls_of pin u_csr/U9/C1] eq "unknown"}
check "a net in neither list is unknown, not safe" {[cls_of pin u_csr/U9/B1] eq "unknown"}
check "the 092 expected form is unchanged: a flop QN pin outside the cone is flop_output" {[cls_of pin u_csr/dest_c_reg_reg_5_/QN] eq "flop_output"}
check "a cone port is cone_port (violation), another port is port" {[cls_of port {prdata[3]}] eq "cone_port" && [cls_of port {prdata[4]}] eq "port" && [pt_eco_class_violation cone_port] && ![pt_eco_class_violation port]}
check "violation set: cone_net cone_driver cone_port cone_resize unknown only" {[lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize unknown} {pt_eco_class_violation $c}] eq {0 0 0 0 0 0 1 1 1 1 1}}
check "the apply script's violation list equals the probe's" {[lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize unknown} {eco093_violation $c}] eq [lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize unknown} {pt_eco_class_violation $c}]}
check "every class has a text" {[llength [lsearch -all -inline -glob [lmap c {load_flop load_comb flop_output flop_input other port cone_net cone_driver cone_port cone_resize unknown} {pt_eco_class_text093 $c}] "class unknown*"]] == 1}
# a mixed change file: violations are reported with the idx, the pin and the class
set mix "current_instance {u_csr}\ninsert_buffer \[get_pins {U77/A2}\] buffd1 -new_net_names {net_PTECO_HOLD_NET1} -new_cell_names {U_PTECO_HOLD_BUF1}\ninsert_buffer \[get_pins {U77/A1}\] buffd1 -new_net_names {c} -new_cell_names {d}\ninsert_buffer \[get_pins {U77/ZN}\] buffd1 -new_net_names {e} -new_cell_names {f}\nsize_cell {U77} {oai222d2}\ncurrent_instance\ninsert_buffer \[get_ports {prdata\[3\]}\] buffd1 -new_net_names {g} -new_cell_names {h}\n"
set pm [eco079_parse $mix]
set cm [dict create]
foreach c [dict get $pm cmds] { if {[dict get $c type] eq "insert_buffer"} { dict set cm [dict get $c idx] [cls_of [dict get $c objkind] [dict get $c full_pin] [dict get $c cell]] } }
set mh [pt_cone_hits_pin [dict get $pm cmds] $cm $cone_cells]
check "mixed file: A2 clean; A1 (kept net), ZN (driver), the resize of U77 and the cone port are 4 hits" {[llength [dict get $pm errors]] == 0 && [llength $mh] == 4 && [lsort -integer [lmap h $mh {dict get $h idx}]] eq {2 3 4 5}}
check "hit texts carry the pin and the class" {[has [dict get [lindex $mh 0] what] "u_csr/U77/A1"] && [has [dict get [lindex $mh 0] what] "VIOLATION"] && [dict get [lindex $mh 0] name] eq "u_csr/U77"}
check "an insertion without a class is a violation (no silent pass)" {[llength [pt_cone_hits_pin [dict get $p9 cmds] [dict create] $cone_cells]] == 9}
# the net release stores the released names; in2reg (no release) keeps every cone-cell pin a violation
check "pt_cone_nets_reg2out records the released nets (section 3 result)" {[dict exists $new released] && [dict get $new released] eq {n_qn}}
set cone_in2reg [dict create cells $cone_cells ports {prdata[3]} nets [concat $kept_nets $rel_nets]]
set fx0 [pt_eco_insert_facts_pin pin u_csr/U77/A2 $cone_in2reg u_csr/U_PTECO_HOLD_BUF1]
check "in2reg (nothing released): the same pin is on a kept net -> cone_net, as the cell-level check said" {[dict get $fx0 state] eq "kept" && [pt_eco_pin_class pin 1 [dict get $fx0 dir] [dict get $fx0 state] [dict get $fx0 drv_seq] "" ""] eq "cone_net"}

# the real shape (093 follow-up): the pin sees net_PTECO_HOLD_NET<n> driven by U_PTECO_HOLD_BUF<n>; the class comes from the buffer's input net
set fx1 [pt_eco_insert_facts_pin pin u_csr/U77/A2 $cone93 u_csr/U_PTECO_HOLD_BUF1]
check "facts: original net and driver from the buffer's input pin, the new net and driver kept" {[dict get $fx1 net] eq "u_csr/qn_dest_c_reg_reg_5_" && [dict get $fx1 drivers] eq "u_csr/dest_c_reg_reg_5_/QN" && [dict get $fx1 drv_seq] eq "1" && [dict get $fx1 state] eq "released" && [dict get $fx1 new_net] eq "u_csr/net_PTECO_HOLD_NET1" && [dict get $fx1 new_driver] eq "u_csr/U_PTECO_HOLD_BUF1/Z"}
check "the change file names the buffer: cell and net of insertion 1" {[dict get [lindex [dict get $p9 cmds] 0] cell] eq "u_csr/U_PTECO_HOLD_BUF1" && [dict get [lindex [dict get $p9 cmds] 0] net] eq "u_csr/net_PTECO_HOLD_NET1"}
check "without the buffer name the new net is in neither list: unknown (the bug of the first 093 server run)" {[cls_of pin u_csr/U77/A2] eq "unknown" && [dict get [pt_eco_insert_facts_pin pin u_csr/U77/A2 $cone93] state] eq "none"}
check "the name of ANOTHER buffer does not match: unknown" {[cls_of pin u_csr/U77/A2 u_csr/U_PTECO_HOLD_BUF2] eq "unknown"}
check "the named buffer: load_flop" {[cls_of pin u_csr/U77/A2 u_csr/U_PTECO_HOLD_BUF1] eq "load_flop"}
check "pure: new-buffer driver test" {[pt_eco_new_buf_driver {b1} b1] == 1 && [pt_eco_new_buf_driver {b1} b2] == 0 && [pt_eco_new_buf_driver {} b1] == 0 && [pt_eco_new_buf_driver {b1} ""] == 0 && [pt_eco_new_buf_driver {b1 ""} b1] == 0 && [pt_eco_new_buf_driver {b1 b2} b1] == 0}
# a buffer whose input net cannot be found stays unknown; a buffer on a kept net is a violation; a buffer on a net with a combinational driver is load_comb
set PINNET(u_csr/U_PTECO_HOLD_BUF9/I) u_csr/n_missing; set PINDIR(u_csr/U_PTECO_HOLD_BUF9/I) in; set PINDIR(u_csr/U9/B3) in
set PINNET(u_csr/U9/B3) u_csr/net_PTECO_HOLD_NET9; dict set NETDRV u_csr/net_PTECO_HOLD_NET9 {u_csr/U_PTECO_HOLD_BUF9/Z}; set CELLSEQ(u_csr/U_PTECO_HOLD_BUF9) false
check "a buffer whose input net is in no list: unknown" {[cls_of pin u_csr/U9/B3 u_csr/U_PTECO_HOLD_BUF9] eq "unknown"}
unset PINNET(u_csr/U_PTECO_HOLD_BUF9/I); unset PINDIR(u_csr/U_PTECO_HOLD_BUF9/I)
check "a buffer without a readable input pin / net: unknown, net empty" {[cls_of pin u_csr/U9/B3 u_csr/U_PTECO_HOLD_BUF9] eq "unknown" && [dict get [pt_eco_insert_facts_pin pin u_csr/U9/B3 $cone93 u_csr/U_PTECO_HOLD_BUF9] net] eq ""}
set PINNET(u_csr/U_PTECO_HOLD_BUF9/I) u_csr/n_dec; set PINDIR(u_csr/U_PTECO_HOLD_BUF9/I) in
check "a buffer whose input net is a KEPT cone net: cone_net (violation)" {[cls_of pin u_csr/U9/B3 u_csr/U_PTECO_HOLD_BUF9] eq "cone_net"}
set PINNET(u_csr/U_PTECO_HOLD_BUF9/I) u_csr/n_comb
check "a buffer whose input net is released with a combinational driver: load_comb" {[cls_of pin u_csr/U9/B3 u_csr/U_PTECO_HOLD_BUF9] eq "load_comb"}
set PINNET(u_csr/U_PTECO_HOLD_BUF9/I) u_csr/n_nodrv
check "a buffer whose input net has no driver: unknown" {[cls_of pin u_csr/U9/B3 u_csr/U_PTECO_HOLD_BUF9] eq "unknown"}
# the class file and the apply side
check "class row text" {[lindex $rows9 0] eq "1 u_csr/U77/A2 buffd1 load_flop net=u_csr/qn_dest_c_reg_reg_5_ drivers=u_csr/dest_c_reg_reg_5_/QN"}
check "class row: unreadable net and no drivers are written as ?" {[pt_eco_class_row 3 x/A1 buffd1 unknown "" {}] eq "3 x/A1 buffd1 unknown net=? drivers=?"}
set cls_text "# comment\n[join $rows9 "\n"]\n"
set pc [eco093_parse_classes $cls_text]
check "apply: the class file of the 9 parses" {[llength [dict get $pc errors]] == 0 && [dict size [dict get $pc rows]] == 9}
lassign [eco093_check [dict get $p9 cmds] [dict get $pc rows]] lines probs
check "apply: 9 lines printed, no problem" {[llength $lines] == 9 && [llength $probs] == 0 && [has [lindex $lines 0] "class load_flop; net u_csr/qn_dest_c_reg_reg_5_; driver u_csr/dest_c_reg_reg_5_/QN"]}
set bad_rows [dict get $pc rows]
dict set bad_rows 4 cls cone_net
lassign [eco093_check [dict get $p9 cmds] $bad_rows] l2 p2
check "apply: a violation class in the file stops the apply (a problem is returned)" {[llength $p2] == 1 && [has [lindex $p2 0] "cone_net"] && [has [lindex $l2 3] "(VIOLATION)"]}
set other_rows [dict get $pc rows]
dict set other_rows 2 pin u_csr/U1/A1
lassign [eco093_check [dict get $p9 cmds] $other_rows] l3 p3
check "apply: a line for another pin = the file belongs to another change file" {[llength $p3] == 1 && [has [lindex $p3 0] "another change file"]}
set short_rows [dict get $pc rows]; dict unset short_rows 9
lassign [eco093_check [dict get $p9 cmds] $short_rows] l4 p4
check "apply: a missing line is a problem" {[llength $p4] == 1 && [has [lindex $p4 0] "has no line"]}
set long_rows [dict get $pc rows]; dict set long_rows 10 [dict create pin x/A1 ref buffd1 cls load_flop net n drivers d]
lassign [eco093_check [dict get $p9 cmds] $long_rows] l5 p5
check "apply: a line without a change is a problem" {[llength $p5] == 1 && [has [lindex $p5 0] "no insertion with that number"]}
check "apply: a malformed class file is an error list" {[llength [dict get [eco093_parse_classes "1 only three fields"] errors]] == 1 && [llength [dict get [eco093_parse_classes "$cls_text\n$cls_text"] errors]] == 9}
# source checks
set pb [read_file $here/pt/pt_eco_probe.tcl]
check "probe: the AFTER check is pin level and the cell-level pt_cone_hits is no longer called there" {[has $pb {pt_cone_hits_pin}] && ![has $pb {set hits [pt_cone_hits [dict get $chk cmds]}]}
check "probe: the new buffer name of the change file is handed to the facts; the line shows original and new net" {[has $pb {$cone [dict get $c cell]]}] && [has $pb {original net}] && [has $pb {after the ECO the pin sees}]}
check "probe: the class file is deleted, then written next to the change files (PT_RPT_DIR)" {[has $pb {file delete -force ${PT_RPT_DIR}/pt_eco_hold_pin_classes.txt}] && [has $pb {open ${PT_RPT_DIR}/pt_eco_hold_pin_classes.txt w}]}
check "probe: the result line carries the class summary" {[has $pb {Pin classes: [pt_eco_class_summary $eco_cls]}]}
check "probe: the cone is still protected before fix_eco_timing with the cell-level dont_touch (unchanged)" {[string first "pt_cone_protect \$cone" $pb] < [string first "foreach att {collection bare_names}" $pb] && $PT_CONE_PROTECT == 1}
check "apply: the class file is read from PT_DIR, an ERROR 093 stops it before anything is changed" {[has $apply {set ea_cls_file "${PT_DIR}/pt_eco_hold_pin_classes.txt"}] && [has $apply {ERROR 093: the pin classes of}] && [string first "ERROR 093: the pin classes" $apply] < [string first "2. Pins, references, names" $apply]}
check "apply: the gates of the in2out and setup WNS are still there" {[has $apply {eco079_gate_check $glabel $gb $ga $gtol}]}
set ::tableout [join $table "\n"]

puts "RESULT: $npass passed, $nfail failed"
if {[info exists env(SHOW_TABLE)]} { puts $::tableout }
if {$nfail > 0} { exit 1 }
exit 0
