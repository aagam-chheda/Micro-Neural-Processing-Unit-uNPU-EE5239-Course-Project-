# =============================================================================
# ndm_fill_common.tcl -- TOOL procedures shared by ndm_fill_probe.tcl and ndm_file_gen.tcl (task 056).
# Source it after common.tcl, inside icc2_lm_shell. Defines procedures only; runs nothing.
# Every library-manager command used here is from the usage files in help_lm (create_workspace, read_lef, report_workspace,
# get_lib_cells, remove_workspace, check_workspace, commit_workspace, set_attribute, foreach_in_collection, get_object_name,
# sizeof_collection, redirect) except: get_libs, get_attribute (VERIFY: synonym list / ICC2 common; no usage text read yet).
# =============================================================================

# Run a script, capture everything it prints. Returns {rc text}; never stops the shell. rc 0 = no Tcl error.
proc ndm_cap {script} {
  set ::NDM_CAP ""
  set rc 0
  if {[llength [info commands redirect]]} {
    set rc [catch {redirect -variable ::NDM_CAP [list uplevel #0 $script]} msg]
    if {$rc} { return [list 1 "$::NDM_CAP\n$msg"] }
    return [list 0 $::NDM_CAP]
  }
  set rc [catch {uplevel #0 $script} msg]
  return [list $rc $msg]
}

# Names of the objects a form lists (full names). Error text if the form fails: returns {ok names-or-message}.
proc ndm_form_names {form} {
  set names {}
  if {[catch {
    set coll [uplevel #0 $form]
    if {$coll ne ""} {
      foreach_in_collection c $coll { lappend names [get_object_name $c] }
    }
  } msg]} { return [list 0 $msg] }
  return [list 1 $names]
}

# The first form (of NDM_FILL_FIND_FORMS, %WS% replaced) that lists exactly the filler cells. Returns {form detail} or {"" report}.
# Every form tried is printed with its count.
proc ndm_find_fillers {ws} {
  global NDM_FILL_FIND_FORMS FILLER_CELLS
  set report {}
  foreach form [unpu_fill_find_forms $NDM_FILL_FIND_FORMS $ws] {
    lassign [ndm_form_names $form] ok names
    if {!$ok} {
      unpu_info "find form '$form': error: $names"
      lappend report "'$form': error: $names"
      continue
    }
    lassign [unpu_fill_match $names $FILLER_CELLS] m detail
    unpu_info "find form '$form': [llength $names] object(s); exact match [expr {$m ? {yes} : {no}}]: $detail"
    if {$m} { return [list $form $detail] }
    lappend report "'$form': $detail"
  }
  return [list "" [join $report "; "]]
}

# Type the cells listed by `form` as design_type filler and read the value back. Returns {n bad}.
proc ndm_type_by_form {form} {
  set n 0
  set bad {}
  set readable 1
  foreach_in_collection c [uplevel #0 $form] {
    set nm [get_object_name $c]
    set_attribute $c design_type filler
    incr n
    if {[catch {get_attribute $c design_type} v]} {
      if {$readable} { unpu_warn "get_attribute design_type could not be read back ($v): the typing is NOT verified (VERIFY)" }
      set readable 0
    } elseif {$v ne "filler"} {
      lappend bad "$nm=$v"
    }
  }
  return [list $n $bad]
}

# Remove the current workspace (after a failed variant). Never stops the shell; says what happened.
proc ndm_discard_ws {} {
  lassign [ndm_cap remove_workspace] rc text
  unpu_info "remove_workspace: [expr {$rc ? {error} : {ok}}] [string trim $text]"
  return [expr {!$rc}]
}

# One variant: build the workspace, read the LEF, find and type the fillers, check_workspace.
# Returns {ok message}; on ok=0 the caller discards the workspace. Nothing here stops the shell.
proc ndm_try_fill_variant {variant ws tf lef} {
  global FILLER_CELLS
  set cmds [unpu_fill_variant_cmds $variant $ws $tf $lef]
  foreach c $cmds {
    unpu_info "variant $variant: $c"
    lassign [ndm_cap $c] rc text
    puts -nonewline $text
    if {$text ne "" && ![string match *\n $text]} { puts "" }
    if {$rc} { return [list 0 "command failed: $c"] }
  }
  lassign [ndm_find_fillers $ws] form detail
  if {$form eq ""} { return [list 0 "no get_lib_cells form lists exactly the [llength $FILLER_CELLS] fillers: $detail"] }
  lassign [ndm_type_by_form $form] n bad
  unpu_info "variant $variant: design_type filler set on $n cell(s) found by '$form'"
  lassign [ndm_form_names $form] ok1 names1
  if {!$ok1 || $n != [llength $names1] || $n < [llength $FILLER_CELLS]} { return [list 0 "typed $n objects, the form lists [llength $names1] (at least [llength $FILLER_CELLS] expected)"] }
  if {[llength $bad]} { return [list 0 "design_type read back differs from filler: $bad"] }
  lassign [ndm_cap check_workspace] rc text
  puts -nonewline $text
  if {$text ne "" && ![string match *\n $text]} { puts "" }
  if {$rc} { return [list 0 "check_workspace failed"] }
  if {![unpu_workspace_check_ok $text]} { return [list 0 "check_workspace did not print 'Workspace check succeeded!'"] }
  unpu_info "variant $variant: check_workspace reported success"
  return [list 1 "variant $variant, cells found by '$form'"]
}
