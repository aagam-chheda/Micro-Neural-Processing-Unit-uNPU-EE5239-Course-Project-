# =============================================================================
# ndm_fill_probe.tcl -- EXPLORATORY probe (task 056): why does get_lib_cells find 0 of the 3 filler cells in the
# second NDM workspace? Builds the second workspace in several variants, in a SCRATCH directory, and prints everything
# that answers the question, so that ONE server run is enough. It never touches the real ndm/ directory.
#
# Runs in the library manager of the SAME release as icc2_shell (like ndm_file_gen.tcl):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_PROBE_DIR <a NEW directory, e.g. $UNPU_WORK/ndm_probe1>      # must not exist yet (or be empty); not the real ndm/
#   /home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell -file $UNPU_REPO/pnr/ndm_fill_probe.tcl -output_log_file $UNPU_WORK/ndm_fill_probe.log
#
# Variants (each in its own sub-directory of UNPU_PROBE_DIR, so the committed .ndm files do not collide):
#   lefLib      create_workspace -flow physical_only -technology TF WS ; read_lef LEF           (the form that ran in pnr_run2)
#   lefInto     create_workspace -flow physical_only -technology TF WS ; read_lef -library WS LEF
#   noTech      create_workspace -flow physical_only WS ; read_lef LEF
#   noTechInto  create_workspace -flow physical_only WS ; read_lef -library WS LEF
#   useTechLib  create_workspace -flow physical_only -use_technology_lib <main workspace name> WS ; read_lef LEF
#               (probe only; the technology library name is a GUESS: the name of the main workspace; an error here is a result)
# Per variant it prints, after create_workspace and after read_lef: report_workspace (plain, -details, -panes, -changes, and -lib_group for
# the names it guesses), get_workspaces, current_workspace, get_libs, current_lib; every get_lib_cells form of NDM_FILL_FIND_FORMS plus
# extra ones, with the object names found and their design_type; then it types what the first exact form lists, runs check_workspace (plain and
# -details physical_only_cells), commit_workspace, and lists the .ndm files that appeared. A summary table closes the log
# (also written to UNPU_PROBE_DIR/summary.txt).
#
# VERIFY (not in a usage text yet): get_libs, current_lib, current_workspace, get_workspaces, report_lib_cells, get_attribute. Every one of
# them is called inside catch: an error is printed as a RESULT, never hidden and never fatal.
# Optional: UNPU_PROBE_VARIANTS="lefInto noTech" runs only those.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
source [file join $here ndm_fill_common.tcl]
unpu_load_params

unpu_require_tool_version $ICC2_VERSION
unpu_need_file $TECH_FILE "technology file"
unpu_need_file $LEF_STD   "standard-cell LEF"

# ---- the scratch directory ---------------------------------------------------
if {![info exists ::env(UNPU_PROBE_DIR)] || $::env(UNPU_PROBE_DIR) eq ""} {
  unpu_die "UNPU_PROBE_DIR is not set. It must name a NEW directory for this probe (not the real ndm/ directory). csh: setenv UNPU_PROBE_DIR \$UNPU_WORK/ndm_probe1"
}
set PROBE_DIR [file normalize $::env(UNPU_PROBE_DIR)]
unpu_no_kit_write $PROBE_DIR/x
set real_ndm [file normalize $NDM_DIR]
if {$PROBE_DIR eq $real_ndm || [string first "$real_ndm/" $PROBE_DIR] == 0 || [string first "$PROBE_DIR/" $real_ndm] == 0} {
  unpu_die "UNPU_PROBE_DIR=$PROBE_DIR is the real NDM directory or contains/is inside it ($real_ndm). Use a separate directory."
}
if {[file exists $PROBE_DIR]} {
  if {![file isdirectory $PROBE_DIR]} { unpu_die "UNPU_PROBE_DIR=$PROBE_DIR exists and is not a directory" }
  if {[llength [glob -nocomplain -directory $PROBE_DIR *]] > 0} { unpu_die "UNPU_PROBE_DIR=$PROBE_DIR is not empty. Use a new directory (nothing is overwritten)." }
}
file mkdir $PROBE_DIR
unpu_info "probe directory: $PROBE_DIR (the real ndm directory $real_ndm is not touched)"

set feedth_lef $PROBE_DIR/feedth.lef
set nfill_lef [unpu_extract_lef_macros $LEF_STD $FILLER_CELLS $feedth_lef]
unpu_check_pass ndm_fill_probe feedth_lef [expr {$nfill_lef == [llength $FILLER_CELLS]}] "$nfill_lef MACROs written to $feedth_lef"

# ---- helpers -----------------------------------------------------------------
# run a script, print it, its return code and everything it printed
proc pr {title script} {
  lassign [ndm_cap $script] rc text
  puts ""
  puts "#### $title"
  puts "#### script: $script"
  puts "#### rc=$rc"
  puts -nonewline $text
  if {$text ne "" && ![string match *\n $text]} { puts "" }
  return [list $rc $text]
}
# a form's objects: count, names, design_type of each
proc pr_form {form} {
  lassign [ndm_form_names $form] ok names
  if {!$ok} { puts "#### form '$form': ERROR $names"; return [list $form error 0 {}] }
  set types {}
  if {[llength $names]} {
    catch {
      foreach_in_collection c [uplevel #0 $form] {
        if {[catch {get_attribute $c design_type} v]} { set v "(get_attribute error: $v)" }
        lappend types "[get_object_name $c]=$v"
      }
    }
  }
  puts "#### form '$form': [llength $names] object(s): $names"
  if {[llength $types]} { puts "####   design_type: $types" }
  return [list $form ok [llength $names] $names]
}
proc dump_state {tag ws} {
  global NDM_FILL_FIND_FORMS
  puts ""
  puts "######## STATE $tag ########"
  pr "$tag report_workspace" {report_workspace}
  pr "$tag report_workspace -details" {report_workspace -details}
  pr "$tag report_workspace -panes" {report_workspace -panes}
  pr "$tag report_workspace -changes" {report_workspace -changes}
  foreach lg [list $ws feedth] { pr "$tag report_workspace -lib_group $lg" [list report_workspace -lib_group $lg -details] }
  pr "$tag get_workspaces" {foreach_in_collection w [get_workspaces] { puts [get_object_name $w] }}
  pr "$tag current_workspace" {current_workspace}
  pr "$tag current_lib" {current_lib}
  pr "$tag get_libs" {foreach_in_collection l [get_libs *] { puts [get_object_name $l] }}
  set results {}
  foreach form [concat [unpu_fill_find_forms $NDM_FILL_FIND_FORMS $ws] {{get_lib_cells -quiet *feedth*} {get_lib_cells -regexp {feedth}} {get_lib_cells -quiet feedth/*} {get_lib_cells -quiet feedth/feedth*} {get_lib_cells -quiet feedth/feedth} {get_lib_cells -quiet feedth/feedth/*}}] {
    lappend results [pr_form $form]
  }
  pr "$tag report_lib_cells" {report_lib_cells}
  return $results
}

# ---- the variants --------------------------------------------------------------
set variants [unpu_fill_variant_names]
lappend variants useTechLib
if {[info exists ::env(UNPU_PROBE_VARIANTS)] && $::env(UNPU_PROBE_VARIANTS) ne ""} { set variants $::env(UNPU_PROBE_VARIANTS) }
set SUMMARY {}
foreach variant $variants {
  set ws $NDM_WS_FILL
  set vdir $PROBE_DIR/$variant
  file mkdir $vdir
  cd $vdir
  puts ""
  puts "################################################################################"
  puts "######## VARIANT $variant   (directory $vdir)"
  puts "################################################################################"
  if {$variant eq "useTechLib"} {
    set cmds [list [list create_workspace -flow physical_only -use_technology_lib $NDM_WS_MAIN $ws] [list read_lef $feedth_lef]]
  } else {
    set cmds [unpu_fill_variant_cmds $variant $ws $TECH_FILE $feedth_lef]
  }
  set rec [dict create variant $variant create ? read ? forms_exact {} typed 0 check ? commit ? ndm {}]
  # create_workspace
  lassign [pr "$variant create" [lindex $cmds 0]] rc text
  dict set rec create [expr {$rc ? "ERROR" : "ok"}]
  if {$rc} {
    dict set rec read skipped
    lappend SUMMARY $rec
    pr "$variant remove_workspace" {remove_workspace}
    continue
  }
  dump_state "$variant after-create" $ws
  # read_lef
  lassign [pr "$variant read_lef" [lindex $cmds 1]] rc text
  dict set rec read [expr {$rc ? "ERROR" : "ok"}]
  set results [dump_state "$variant after-read_lef" $ws]
  # which forms list exactly the fillers
  set exact {}
  foreach r $results {
    lassign $r form st n names
    if {$st eq "ok"} { lassign [unpu_fill_match $names $FILLER_CELLS] m d; if {$m} { lappend exact $form } }
  }
  dict set rec forms_exact $exact
  puts ""
  puts "#### $variant: forms that list exactly the fillers: [expr {[llength $exact] ? $exact : {NONE}}]"
  if {[llength $exact]} {
    lassign [ndm_type_by_form [lindex $exact 0]] n bad
    dict set rec typed $n
    puts "#### $variant: design_type filler set on $n cell(s); read-back differences: [expr {[llength $bad] ? $bad : {none}}]"
  }
  # check_workspace
  lassign [pr "$variant check_workspace" {check_workspace}] rc text
  dict set rec check [expr {(!$rc && [unpu_workspace_check_ok $text]) ? "succeeded" : "NOT-succeeded"}]
  pr "$variant check_workspace -details physical_only_cells" {check_workspace -details physical_only_cells}
  # commit
  set before [glob -nocomplain -directory $vdir *.ndm]
  lassign [pr "$variant commit_workspace" {commit_workspace}] rc text
  dict set rec commit [expr {$rc ? "ERROR" : "ok"}]
  set after [glob -nocomplain -directory $vdir *.ndm]
  set new {}
  foreach f $after { if {[lsearch -exact $before $f] < 0} { lappend new "[file tail $f] ([unpu_path_size $f] bytes)" } }
  dict set rec ndm $new
  puts "#### $variant: .ndm files in $vdir after commit_workspace: [expr {[llength $new] ? $new : {NONE}}]"
  puts "#### $variant: all files in $vdir: [lsort [glob -nocomplain -tails -directory $vdir *]]"
  if {$rc} { pr "$variant remove_workspace" {remove_workspace} }
  lappend SUMMARY $rec
}

# ---- summary -------------------------------------------------------------------
set lines {}
lappend lines "variant        create  read  typed  check          commit  ndm                                forms listing EXACTLY the 3 fillers"
foreach r $SUMMARY {
  lappend lines [format "%-14s %-7s %-5s %-6s %-14s %-7s %-34s %s" [dict get $r variant] [dict get $r create] [dict get $r read] [dict get $r typed] [dict get $r check] [dict get $r commit] [join [dict get $r ndm] {,}] [expr {[llength [dict get $r forms_exact]] ? [join [dict get $r forms_exact] { | }] : {NONE}}]]
}
puts ""
puts "######## SUMMARY ########"
foreach l $lines { puts $l }
set fh [open $PROBE_DIR/summary.txt w]
foreach l $lines { puts $fh $l }
close $fh
unpu_info "summary written to $PROBE_DIR/summary.txt; send this log and that file to Planning"
exit 0
