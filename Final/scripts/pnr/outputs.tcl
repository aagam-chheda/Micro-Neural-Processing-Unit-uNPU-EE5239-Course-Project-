# =============================================================================
# outputs.tcl -- script 8 of the back-end re-run: netlists, LEF, parasitics, delays, constraints, GDS, and checks of each file
#
# Runs in icc2_shell (U-2022.12-SP3). Plan: docs/planning/backend-rerun-plan.md stage E2; commands that worked in the first run:
# docs/session-handoff.md 18.23 (every write command and the traps), 18.24 (why write_gds -units 1000: Calibre's rule precision),
# 18.25 / 18.26 (the LEF with two MACROs: create_frame leaves one frame per block, so write_lef ALWAYS gets -design).
# No option beyond those of 18.23 is used on the write commands.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1
#   icc2_shell -file $UNPU_REPO/pnr/outputs.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/outputs.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Input: the library $LIB_DIR/$LIB_NAME with the FILLED block $BLK_FINAL (fill.tcl). Every file comes from that block only.
# Output, in $OUT_DIR, with the prefix OUT_PREFIX (unpu_top):
#   <p>_sim.v  <p>_lvs.v  <p>.lef  <p>_ss.spef.* <p>_ff.spef.*  <p>_ss.sdf <p>_ff.sdf  <p>_ss.sdc <p>_ff.sdc  <p>.gds
# and $LOG_DIR/manifest_outputs.txt (size and SHA-256 of every file, the real SPEF names, GDS-017 count). Reports: $RPT_DIR.
#
# No file is overwritten: if a target exists the script stops and names it, unless UNPU_OUTPUTS_OVERWRITE is 1 (then every such
# file is deleted first, with a Warning, so that a stale file can never pass the checks of a failed write).
# UNPU_GDS_LAYER_MAP replaces the kit layer map with a corrected copy (Warning; the path is in the manifest).
#
# Every file is then CHECKED from the outside (pure-Tcl checkers in common.tcl): a wrong file is found here, not in Calibre or in
# the top-level team's tools. The layer and datatype of the GDS pin labels are NOT checked here: Calibre LVS will tell.
#
# No checkpoint block is saved: the block is not modified (create_frame adds a frame view; that view is not saved either, so the
# next run starts from the same final block). The script ends with close_blocks -force and no save.
# Rerun: nothing but files is written, so the script can be run again as it is after UNPU_OUTPUTS_OVERWRITE=1.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

# ---- 1. start ----------------------------------------------------------------
unpu_require_tool_version $ICC2_VERSION            ;# sh_product_version (confirmed, VERIFY_STATUS.md)
unpu_require_syn_profile
set UNPU_CHECK_CONTINUE 1
set lib_path $LIB_DIR/$LIB_NAME
if {![file exists $lib_path]} {
  unpu_die "design library not found: $lib_path. [unpu_prev_msg fill $BLK_FINAL]"
}
# the layer map and the standard-cell GDS are inputs of write_gds: their SHA-256 goes into the manifest (and a missing one stops here)
unpu_stage_begin outputs run [list $lib_path $GDS_LAYER_MAP $STD_GDS]
unpu_derive_die check          ;# the die from the synthesis area of UNPU_SYN_PROFILE (task 054); the floorplan record must name the same profile and die
if {$UNPU_CHECK_FAILED > 0} { unpu_die "the floorplan record does not match this run (UNPU_SYN_PROFILE / die): see the CHECK line above; nothing is done" }
unpu_open_stage $lib_path $LIB_NAME $BLK_FINAL fill
unpu_result outputs syn_profile $SYN_PROFILE
unpu_netlist_expect          ;# NETLIST_MODULES, NETLIST_LEAF_CELLS computed from the netlist file the layout started from
# the stage profile of the block we opened must be PROFILE_OUTPUTS (`route`): read back and CHECKED, not re-read (task 053)
unpu_check_profile_state $PROFILE_OUTPUTS

set P $OUT_PREFIX
array set F [list sim $OUT_DIR/${P}_sim.v lvs $OUT_DIR/${P}_lvs.v lef $OUT_DIR/${P}.lef gds $OUT_DIR/${P}.gds \
    sdf_ss $OUT_DIR/${P}_ss.sdf sdf_ff $OUT_DIR/${P}_ff.sdf sdc_ss $OUT_DIR/${P}_ss.sdc sdc_ff $OUT_DIR/${P}_ff.sdc]
set spef_base(ss) $OUT_DIR/${P}_ss.spef
set spef_base(ff) $OUT_DIR/${P}_ff.spef
# files that exist already: the targets and everything the tool adds to the SPEF names (write_parasitics adds a suffix)
set existing {}
foreach k [array names F] { if {[file exists $F($k)]} { lappend existing $F($k) } }
foreach c {ss ff} { foreach f [glob -nocomplain -directory $OUT_DIR [file tail $spef_base($c)]*] { lappend existing $f } }
set existing [lsort -unique $existing]
if {[llength $existing] > 0} {
  if {$OUTPUTS_OVERWRITE ne "1"} {
    unpu_die "output file(s) exist already: [join $existing {, }]. Nothing is overwritten; move them, use a new UNPU_RUN_TAG, or setenv UNPU_OUTPUTS_OVERWRITE 1"
  }
  foreach f $existing {
    unpu_warn "UNPU_OUTPUTS_OVERWRITE=1: deleting and rewriting $f"
    unpu_no_kit_write $f
    file delete -force $f
  }
}

# the port names of the block (the 204 signals; VDD/VSS are PG pins, not ports). VERIFY: get_ports, get_object_name
set ports {}
foreach_in_collection p [get_ports] { lappend ports [get_object_name $p] }
unpu_check_pass outputs ports_read [expr {[llength $ports] == $EXPECT_PORTS}] "[llength $ports] top-level ports read from the block, $EXPECT_PORTS expected (EXPECT_PORTS)"
# Power terminals per net: power.tcl made one terminal per TOP_M stripe, and the LEF power pin has one rectangle per terminal. (A count of
# stripe SHAPES would be wrong here: power.tcl creates its extension rectangles with shape_use stripe too, so that query counts both.)
foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
  if {[catch {sizeof_collection [get_terminals -quiet -of_objects [get_nets $n]]} c]} { set c unavailable }
  set nstripe($n) $c
  unpu_result outputs power_terminals_$n $c
}
proc oc_ls {} { global OUT_DIR; return [glob -nocomplain -tails -directory $OUT_DIR *] }

# ---- 2. netlists (18.23): -include and -exclude cannot be combined (CMD-001) ---------------------------------------
# simulation netlist: no power pins, no cell stubs
unpu_run_logged [list write_verilog -hierarchy all -exclude {all_physical_cells leaf_module_declarations pg_netlist pg_objects supply_statements} $F(sim)] {Error Warning}
# LVS netlist: .VDD/.VSS on the instances
unpu_run_logged [list write_verilog -hierarchy all -include {pg_netlist} $F(lvs)] {Error Warning}

# ---- 3. LEF (18.23, 18.25/18.26): the frame view first; ALWAYS with -design (a stale frame of an older block gives two MACROs) ----
unpu_run_logged [list create_frame -block_all true] {Error Warning FRAM-}
unpu_run_logged [list write_lef -design $BLK_FINAL -include cell $F(lef)] {Error Warning LEFW-}

# ---- 4. parasitics, delays, constraints for BOTH corners (18.23) ---------------------------------------------------
# write_parasitics adds a suffix (.typ_125.spef) and helper files: the real names are found by listing the directory
foreach {c corner} [list ss $CORNER_SETUP ff $CORNER_HOLD] {
  set before [oc_ls]
  unpu_run_logged [list write_parasitics -corner $corner -output $spef_base($c)] {Error Warning}
  set new($c) [unpu_new_files $before [oc_ls] [file tail $spef_base($c)]]
  unpu_result outputs spef_files_$c [join $new($c) " "]
}
unpu_run_logged [list write_sdf -corner $CORNER_SETUP $F(sdf_ss)] {Error Warning}
unpu_run_logged [list write_sdf -corner $CORNER_HOLD $F(sdf_ff)] {Error Warning}
# the "Multiply cell derates are skipped" warnings are benign and are printed by the logged run
unpu_run_logged [list write_sdc -scenario $SCEN_SETUP -output $F(sdc_ss)] {Error Warning derate}
unpu_run_logged [list write_sdc -scenario $SCEN_HOLD -output $F(sdc_ff)] {Error Warning derate}

# ---- 5. GDS (18.23, 18.24): -units 1000 is Calibre's rule precision; the kit map gives GDS-017 for its T lines ----------
if {$GDS_LAYER_MAP ne $GDS_LAYER_MAP_KIT} { unpu_warn "the GDS layer map used is NOT the kit map: $GDS_LAYER_MAP" }
unpu_result outputs gds_layer_map $GDS_LAYER_MAP
set gtext [unpu_run_logged [list write_gds -design $BLK_FINAL -units $GDS_UNITS -layer_map_format icc_default -layer_map $GDS_LAYER_MAP -merge_files $STD_GDS -output_pin all $F(gds)] {Error GDS-}]
array set gid [unpu_count_ids $gtext GDS]
set g017 [expr {[info exists gid(GDS-017)] ? $gid(GDS-017) : 0}]
unpu_result outputs gds_017_count $g017
foreach id [lsort [array names gid]] {
  if {$id ne "GDS-017"} { unpu_warn "write_gds printed $id $gid($id) time(s); only GDS-017 (layer map syntax of the T lines, file still written) is known from 18.23" }
}
if {$g017 > 0} { unpu_info "GDS-017 appears $g017 time(s): the kit layer map's T text lines are rejected, the file is still written (18.23); the layer of the pin labels is for Calibre LVS to tell" }

# ---- 6. the files, checked from outside --------------------------------------------------------------------------
# the SPEF files: the main one of each corner is the new file whose name ends in .spef
foreach c {ss ff} {
  set mains {}
  foreach f $new($c) { if {[string match *.spef $f]} { lappend mains $f } }
  unpu_check_pass outputs spef_found_$c [expr {[llength $mains] == 1}] "write_parasitics wrote [llength $new($c)] new file(s) for corner $c: {$new($c)}; exactly one ends in .spef: {$mains}"
  set spef_main($c) [expr {[llength $mains] == 1 ? "$OUT_DIR/[lindex $mains 0]" : ""}]
}
# 6a. existence, size, SHA-256
array set kind {sim verilog lvs verilog lef lef gds gds sdf_ss sdf sdf_ff sdf sdc_ss sdc sdc_ff sdc}
set files {}
foreach k {sim lvs lef sdf_ss sdf_ff sdc_ss sdc_ff gds} { lappend files $k $F($k) $kind($k) }
foreach c {ss ff} { if {$spef_main($c) ne ""} { lappend files spef_$c $spef_main($c) spef } }
set mf {}
array set minb $OUT_MIN_BYTES
array set have {}
foreach {k f ty} $files {
  set sz [expr {[file exists $f] ? [file size $f] : -1}]
  set ok [expr {$sz >= $minb($ty)}]
  set have($k) $ok
  unpu_check_pass outputs file_$k $ok "[file tail $f]: $sz bytes (at least $minb($ty) expected for a $ty file)"
  unpu_result outputs size_$k $sz
  if {$sz > 0} { lappend mf "size $sz  $f" "sha256 [unpu_sha256 $f]  $f" }
}
# 6b. simulation netlist
set pgconn {\.(VDD|VSS)\s*\(}
if {$have(sim)} {
  set txt [unpu_read_text $F(sim)]
  set mods [unpu_verilog_modules $txt]
  unpu_check_pass outputs sim_modules [expr {[llength $mods] == $NETLIST_MODULES}] "[llength $mods] module definitions in [file tail $F(sim)], $NETLIST_MODULES expected"
  unpu_check_pass outputs sim_top [expr {[lsearch -exact $mods $TOP_NAME] >= 0}] "module $TOP_NAME defined in [file tail $F(sim)]"
  unpu_check_pass outputs sim_no_pg [expr {![regexp -- $pgconn $txt]}] "no .VDD( / .VSS( connection in [file tail $F(sim)]"
  unpu_check_pass outputs sim_no_filler [expr {[string first feedth $txt] < 0}] "no 'feedth' in [file tail $F(sim)]"
}
# 6c. LVS netlist
set lvs_cells {}
if {$have(lvs)} {
  set txt [unpu_read_text $F(lvs)]
  set mods [unpu_verilog_modules $txt]
  unpu_check_pass outputs lvs_modules [expr {[llength $mods] == $NETLIST_MODULES}] "[llength $mods] module definitions in [file tail $F(lvs)], $NETLIST_MODULES expected"
  unpu_check_pass outputs lvs_top [expr {[lsearch -exact $mods $TOP_NAME] >= 0}] "module $TOP_NAME defined in [file tail $F(lvs)]"
  unpu_check_pass outputs lvs_pg [expr {[regexp -- "\\.$PG_NET_POWER\\s*\\(" $txt] && [regexp -- "\\.$PG_NET_GROUND\\s*\\(" $txt]}] ".${PG_NET_POWER}( and .${PG_NET_GROUND}( connections present in [file tail $F(lvs)]"
  unpu_check_pass outputs lvs_no_filler [expr {[string first feedth $txt] < 0}] "no 'feedth' in [file tail $F(lvs)] (the fillers are layout-only; Calibre must accept that, 18.23)"
  set hdr [unpu_verilog_block_name $txt]
  unpu_result outputs lvs_header_block $hdr
  unpu_check_pass outputs lvs_header_block [expr {$hdr eq $BLK_FINAL || [string match "*:$BLK_FINAL*" $hdr] || [string match "${BLK_FINAL}.*" $hdr]}] "the header comment of [file tail $F(lvs)] names block '$hdr', expected $BLK_FINAL"
  set lvs_cells [unpu_verilog_cell_types $txt]
  unpu_result outputs lvs_cell_types [llength $lvs_cells]
}
# 6d. LEF: ONE macro, the die size, the pins, the power pin rectangles
if {$have(lef)} {
  array set lef [unpu_parse_lef [unpu_read_text $F(lef)]]
  unpu_check_pass outputs lef_one_macro [expr {$lef(macros) eq [list $TOP_NAME]}] "MACRO lines in [file tail $F(lef)]: {$lef(macros)}, exactly {MACRO $TOP_NAME} expected (two macros = a stale frame, 18.25)"
  set sz_ok 0
  if {[llength $lef(size)] == 2} { lassign $lef(size) w h; set sz_ok [expr {abs($w - $DIE_SIZE) < 1e-3 && abs($h - $DIE_SIZE) < 1e-3}] }
  unpu_check_pass outputs lef_size $sz_ok "SIZE {$lef(size)} in the LEF, $DIE_SIZE BY $DIE_SIZE expected (DIE_SIZE)"
  set want_pins [expr {[llength $ports] + 2}]
  unpu_check_pass outputs lef_pins [expr {[llength $lef(pins)] == $want_pins}] "[llength $lef(pins)] PIN entries, [llength $ports] signal ports + $PG_NET_POWER + $PG_NET_GROUND = $want_pins expected (18.23 had 206)"
  set missing {}
  array set haspin {}
  foreach p $lef(pins) { set haspin($p) 1 }
  foreach p [concat $ports [list $PG_NET_POWER $PG_NET_GROUND]] { if {![info exists haspin($p)]} { lappend missing $p } }
  unpu_check_pass outputs lef_all_ports [expr {[llength $missing] == 0}] "ports without a PIN entry in the LEF: [llength $missing] {[lrange $missing 0 9]}"
  foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
    set rects [unpu_lef_pin_rects [array get lef] $n $PG_STRIPE_LAYER]
    set ys {}
    foreach r $rects { lappend ys [lindex $r 1] }
    set miny [expr {[llength $ys] > 0 ? [lindex [lsort -real $ys] 0] : "none"}]
    unpu_result outputs lef_${n}_rects [llength $rects]
    unpu_check_pass outputs lef_${n}_rects [expr {$nstripe($n) ne "unavailable" && [llength $rects] == $nstripe($n)}] "PIN $n has [llength $rects] rectangle(s) on $PG_STRIPE_LAYER, the block has $nstripe($n) power terminal(s) of $n"
    unpu_check_pass outputs lef_${n}_from_bottom [expr {$miny ne "none" && abs($miny) < 1e-3}] "lowest y of the $PG_STRIPE_LAYER rectangles of PIN $n: $miny (0 expected: the pins start at the bottom edge)"
  }
}
# 6e. SPEF (both corners; only the head is read: the files are tens of MB)
foreach c {ss ff} {
  if {$have(spef_$c)} {
    lassign [unpu_check_spef_head [unpu_read_head $spef_main($c) 65536] $TOP_NAME] ok magic dname
    unpu_check_pass outputs spef_head_$c $ok "[file tail $spef_main($c)]: first line '$magic', *DESIGN '$dname' (*SPEF and $TOP_NAME expected)"
  }
}
# 6f. SDF (both corners)
foreach c {ss ff} {
  if {$have(sdf_$c)} {
    unpu_check_pass outputs sdf_head_$c [unpu_check_sdf_head [unpu_read_head $F(sdf_$c) 65536] $TOP_NAME] "[file tail $F(sdf_$c)] holds (DELAYFILE and (DESIGN \"$TOP_NAME\")"
  }
}
# 6g. SDC (both corners; the hold uncertainty of the ff file is the hold uncertainty of the run). VERIFY the line layout of write_sdc
foreach c {ss ff} {
  if {$have(sdc_$c)} {
    array unset sd; array set sd [unpu_parse_sdc [unpu_read_text $F(sdc_$c)]]
    unpu_result outputs sdc_${c}_uncertainty "setup '$sd(setup)' hold '$sd(hold)' (create_clock lines: $sd(clocks))"
    unpu_check_pass outputs sdc_clock_$c [expr {$sd(clocks) >= 1}] "[file tail $F(sdc_$c)]: $sd(clocks) create_clock line(s) (at least 1 expected)"
    unpu_check_pass outputs sdc_uncertainty_$c [expr {$sd(setup) ne "" || $sd(hold) ne ""}] "[file tail $F(sdc_$c)]: set_clock_uncertainty setup '$sd(setup)', hold '$sd(hold)' (one of them expected)"
    if {$c eq "ff"} {
      unpu_check_pass outputs sdc_hold_uncertainty [expr {$sd(hold) ne "" && abs($sd(hold) - $UNPU_PROFILE_HOLD) < 1e-9}] "hold uncertainty in [file tail $F(sdc_ff)]: '$sd(hold)' ns, profile hold uncertainty $UNPU_PROFILE_HOLD ns"
    }
  }
}
# 6h. GDS: a well-formed stream, units, top structure, a text label for every port, library cell structures
set gds_scan_ok 0
if {$have(gds)} {
  set t0 [clock seconds]
  array set gs [unpu_gds_scan [unpu_read_text $F(gds)]]
  unpu_result outputs gds_scan_seconds [expr {[clock seconds] - $t0}]
  unpu_result outputs gds_records $gs(records)
  unpu_check_pass outputs gds_stream [expr {$gs(ok) && $gs(endlib)}] "GDSII stream: $gs(records) records, ENDLIB seen $gs(endlib), problem: '$gs(error)'"
  unpu_check_pass outputs gds_header [expr {$gs(first) eq "0002"}] "first record of [file tail $F(gds)] is '$gs(first)' (0002 = HEADER expected)"
  lassign [unpu_gds_units_check $gs(units) $GDS_UNITS $GDS_UNITS_REL_TOL] uok dbu dbm um
  unpu_result outputs gds_units "UNITS record {$gs(units)}: $dbu database units per user unit, database unit $dbm m, user unit $um m"
  unpu_check_pass outputs gds_units $uok "UNITS record {$gs(units)} gives $dbu database units per user unit (write_gds -units $GDS_UNITS) and a user unit of $um m (1e-6 = 1 um expected)"
  set top_ok [expr {[lsearch -exact $gs(strnames) $TOP_NAME] >= 0 && [lsearch -exact $gs(snames) $TOP_NAME] < 0}]
  unpu_check_pass outputs gds_top $top_ok "structure $TOP_NAME [expr {[lsearch -exact $gs(strnames) $TOP_NAME] >= 0 ? {is} : {is NOT}}] in the stream and [expr {[lsearch -exact $gs(snames) $TOP_NAME] < 0 ? {is not} : {IS}}] referenced by another structure ([llength $gs(strnames)] structures)"
  # every port and the PG names as TEXT strings (pin labels); the layer and datatype of the labels are NOT checked here (Calibre LVS)
  set names [concat $ports [list $PG_NET_POWER $PG_NET_GROUND]]
  set counts [unpu_gds_label_counts $gs(texts) $names]
  set zero [unpu_zero_counts $counts]
  set fh [open [file join $RPT_DIR outputs_gds_label_counts.txt] w]; foreach {n c} $counts { puts $fh "$c  $n" }; close $fh
  unpu_result outputs gds_text_strings [llength $gs(texts)]
  unpu_result outputs gds_label_counts [join $counts " "]
  set diag ""
  if {[llength $zero] > 0} {
    array set seenbase {}
    set sample {}
    set b0 [lindex [split [lindex $zero 0] {[<(_}] 0]
    foreach s $gs(texts) { if {[string first $b0 $s] == 0 && ![info exists seenbase($s)]} { set seenbase($s) 1; lappend sample $s; if {[llength $sample] >= 8} break } }
    set diag " Text strings that start like the first missing name '[lindex $zero 0]': {$sample}"
  }
  unpu_check_pass outputs gds_labels [expr {[llength $zero] == 0}] "text labels in the stream for [expr {[llength $names] - [llength $zero]}] of [llength $names] names (ports + $PG_NET_POWER/$PG_NET_GROUND; counts in rpt/outputs_gds_label_counts.txt); without a label: [llength $zero] {[lrange $zero 0 9]}.$diag"
  # library cell structures from the merged standard-cell GDS
  set nstruct [llength [lsort -unique $gs(strnames)]]
  unpu_result outputs gds_structures $nstruct
  unpu_check_pass outputs gds_lib_structures [expr {[llength $lvs_cells] > 0 && $nstruct > [llength $lvs_cells]}] "$nstruct distinct structures in the GDS, [llength $lvs_cells] library cell types in [file tail $F(lvs)] (more structures than cell types expected: the standard-cell GDS was merged)"
  array set instruct {}
  foreach s $gs(strnames) { set instruct($s) 1 }
  set nocell {}
  foreach c $lvs_cells { if {![info exists instruct($c)]} { lappend nocell $c } }
  unpu_check_pass outputs gds_cells_present [expr {[llength $lvs_cells] > 0 && [llength $nocell] == 0}] "library cell types of the LVS netlist without a structure in the GDS: [llength $nocell] {[lrange $nocell 0 9]}"
}

# ---- 7. verdict; the manifest; no checkpoint ---------------------------------------------------------------------
# the manifest gets the size and SHA-256 of every file, the real SPEF names and the GDS-017 count (also when a check failed)
lappend mf "spef_files_ss = $new(ss)" "spef_files_ff = $new(ff)" "gds_017_count = $g017" "gds_layer_map = $GDS_LAYER_MAP"
unpu_manifest_append outputs $mf
unpu_checks_finish outputs
# nothing was saved: the block is not modified; close without saving
if {[catch {close_blocks -force} msg]} { unpu_warn "close_blocks -force failed: $msg" }
unpu_info "done: [llength $files] files in $OUT_DIR, all checked from outside. No checkpoint block was saved. Calibre (DRC, antenna, LVS) and PrimeTime come next; the layer of the GDS pin labels is for Calibre LVS to tell."
exit 0
