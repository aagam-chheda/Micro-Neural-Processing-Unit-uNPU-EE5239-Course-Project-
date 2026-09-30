# =============================================================================
# dc_setup.tcl -- Design Compiler library setup and don't-use cells (task 035)
#
# Sourced by syn/dc_run.tcl. Sets the target/link library to the SCL 180 nm
# FS120 4M1L standard cells, ss corner only, and marks the don't-use cells.
#
# Corner: only ss (process 1.2, 125 C, 1.62 V) is loaded. There is no typical
# library. The ff library is for hold and belongs to PrimeTime, not DC
# (docs/session-handoff.md section 18.2). No operating condition is set here:
# the library's own default is used, and report_lib prints which.
#
# NEVER point this at $FOUNDRY, $STDCELL or anything under
# /home/Cadence_tools/FOUNDRY: that is a generic TSMC-style 0.18 um kit, not
# the SCL process (docs/session-handoff.md section 18.4).
# =============================================================================

# Loud stop: prints a line starting "Error:" (so scripts/dc_summary.sh counts
# it) and exits non-zero. dc_shell -f otherwise stays at its prompt.
proc unpu_die {msg} {
  puts "Error: \[unpu\] $msg"
  exit 1
}

# ---- Kit location: default from the handoff, override from the environment --
set SCL_KIT_ROOT "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180"
if {[info exists ::env(SCL_KIT_ROOT)] && $::env(SCL_KIT_ROOT) ne ""} {
  set SCL_KIT_ROOT $::env(SCL_KIT_ROOT)
}

# Library name as it appears inside the .db, and its file. The directory really
# is spelled 4M1IL (with an I); elsewhere in the kit it is 4M1L.
set SCL_LIB_NAME "tsl18fs120_scl_ss"
set SCL_TARGET_DB [file join $SCL_KIT_ROOT stdcell fs120 4M1IL liberty lib_flow_ss ${SCL_LIB_NAME}.db]

# ---- Don't-use cells ---------------------------------------------------------
# Source: doc/std_cell_guidelines.pdf in the SCL kit (docs/session-handoff.md
# section 18.3). This is the ONE list: scripts/dc_summary.sh reads it from this
# line, so keep it on a single line in this exact form.
set DONT_USE_PATTERNS {slnht* skbrb* slbhb* slnhn* slnln* mx08d*}

# ---- Library file must exist; no fallback of any kind ------------------------
if {![file exists $SCL_TARGET_DB]} {
  unpu_die "target library not found: $SCL_TARGET_DB (SCL_KIT_ROOT=$SCL_KIT_ROOT); no fallback is attempted"
}
puts "Info: \[unpu\] SCL_KIT_ROOT   = $SCL_KIT_ROOT"
puts "Info: \[unpu\] target library = $SCL_TARGET_DB"

set_app_var target_library $SCL_TARGET_DB
set_app_var link_library   [list * $SCL_TARGET_DB]

# Load the library so its cells can be counted and marked.
read_db $SCL_TARGET_DB
if {[sizeof_collection [get_libs -quiet $SCL_LIB_NAME]] == 0} {
  unpu_die "library $SCL_LIB_NAME not loaded after read_db $SCL_TARGET_DB (library name differs from expected?)"
}

# Library on record in the log: units, default operating condition, cell count.
report_lib $SCL_LIB_NAME

# ---- Apply don't-use per pattern, count matches, warn on zero ----------------
foreach pat $DONT_USE_PATTERNS {
  set n [sizeof_collection [get_lib_cells -quiet ${SCL_LIB_NAME}/$pat]]
  if {$n == 0} {
    puts "Warning: \[unpu\] dont-use pattern '$pat' matched 0 library cells in $SCL_LIB_NAME (wrong name, or wrong library?)"
  } else {
    puts "Info: \[unpu\] dont-use pattern '$pat' matched $n library cell(s) in $SCL_LIB_NAME"
    set_dont_use ${SCL_LIB_NAME}/$pat
  }
}
