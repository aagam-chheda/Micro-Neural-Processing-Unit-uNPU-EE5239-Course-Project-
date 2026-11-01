# =============================================================================
# common.tcl -- shared procedures of the back-end (place and route) stage scripts
#
# Pure Tcl at source time: no Synopsys command runs when this file is sourced, so
# plain tclsh can source it (pnr/test_common.tcl does). Procedures that call tool
# commands are only DEFINED here; every tool command that is not shown in
# docs/session-handoff.md carries a "VERIFY" comment.
#
# Message format (all stage scripts), one line each:
#   Info: [unpu] <text>
#   Warning: [unpu] <text>
#   Error: [unpu] <text>                      (then exit 1)
#   Info: [unpu] RESULT <stage> <key> = <value>   (numbers a summary script can grep)
#   Info: [unpu] CHECK <stage> <name> PASS|FAIL <detail>
# =============================================================================

if {[info script] eq ""} {
  puts "Error: \[unpu\] cannot determine the location of common.tcl (info script is empty)"
  exit 1
}
set UNPU_PNR_DIR [file dirname [file normalize [info script]]]

# ---- messages ----------------------------------------------------------------
proc unpu_info {msg} { puts "Info: \[unpu\] $msg" }
proc unpu_warn {msg} { puts "Warning: \[unpu\] $msg" }
proc unpu_die  {msg} { puts "Error: \[unpu\] $msg"; exit 1 }
proc unpu_result {stage key value} { puts "Info: \[unpu\] RESULT $stage $key = $value" }

# ---- files and directories ---------------------------------------------------
# ---- kit files are read-only --------------------------------------------------
# Every procedure that writes or removes a path calls this first: a path under SCL_KIT_ROOT stops the script.
proc unpu_no_kit_write {path} {
  global SCL_KIT_ROOT
  if {![info exists SCL_KIT_ROOT] || $SCL_KIT_ROOT eq ""} return
  set k [file normalize $SCL_KIT_ROOT]
  set p [file normalize $path]
  if {$p eq $k || [string first "$k/" $p] == 0} {
    unpu_die "refusing to write or remove $path: it is under SCL_KIT_ROOT ($SCL_KIT_ROOT); kit files are read-only"
  }
}

proc unpu_need_file {path what} {
  if {![file exists $path]} { unpu_die "$what not found: $path" }
  if {![file isdirectory $path] && ![file readable $path]} { unpu_die "$what is not readable: $path" }
  return $path
}
proc unpu_ensure_dir {path} {
  unpu_no_kit_write $path
  if {[file exists $path] && ![file isdirectory $path]} { unpu_die "$path exists and is not a directory" }
  if {![file isdirectory $path]} {
    if {[catch {file mkdir $path} msg]} { unpu_die "cannot create directory $path: $msg" }
  }
  if {![file isdirectory $path]} { unpu_die "directory $path was not created" }
  return $path
}
# total size in bytes of a file, or of everything below a directory (pure Tcl)
proc unpu_path_size {path} {
  if {![file exists $path]} { return -1 }
  if {![file isdirectory $path]} { return [file size $path] }
  set total 0
  foreach f [glob -nocomplain -types f -directory $path * .*] { incr total [file size $f] }
  foreach d [glob -nocomplain -types d -directory $path *] {
    if {[file tail $d] eq "." || [file tail $d] eq ".."} continue
    set s [unpu_path_size $d]
    if {$s > 0} { incr total $s }
  }
  return $total
}

# ---- identification for the run manifest -------------------------------------
# SHA-256 of a file through an external tool. No silent fallback to a different
# algorithm: if neither tool exists, say so and stop (a manifest without checksums
# would look complete and not be).
proc unpu_sha256 {file} {
  unpu_need_file $file "file to checksum"
  if {![catch {exec sha256sum $file} out]} { return [lindex $out 0] }
  if {![catch {exec shasum -a 256 $file} out2]} { return [lindex $out2 0] }
  unpu_die "cannot compute a SHA-256 of $file: neither sha256sum nor shasum worked ($out | $out2)"
}
proc unpu_git_rev {} {
  global REPO_ROOT
  if {[catch {exec git -C $REPO_ROOT rev-parse --short HEAD} rev]} {
    unpu_warn "git revision unavailable ($rev); recorded as unknown"
    return unknown
  }
  set rev [string trim $rev]
  # uncommitted changes in pnr/ (the scripts of the flow) make the revision untrustworthy
  if {[catch {exec git -C $REPO_ROOT status --porcelain -- pnr} st]} {
    unpu_warn "git status failed ($st); revision recorded without the dirty test"
    return $rev
  }
  if {[string trim $st] ne ""} { append rev +dirty }
  return $rev
}
# Version string of the running Synopsys shell, "" if it cannot be read.
# Confirmed by the help probes of both shells (task 047, version.txt): sh_product_version is a Tcl variable AND readable by
# get_app_var and printvar, value U-2022.12-SP3. The last probe (release string in the path of the executable) is a fallback.
proc unpu_tool_version {} {
  if {[info exists ::sh_product_version] && $::sh_product_version ne ""} { return $::sh_product_version }
  if {[llength [info commands get_app_var]]} {
    if {![catch {get_app_var sh_product_version} v] && $v ne ""} { return $v }   ;# confirmed (get_app_var sh_product_version, version.txt)
  }
  if {[regexp {[A-Z]-[0-9]{4}\.[0-9]{2}(-SP[0-9]+)?} [info nameofexecutable] v]} { return $v }
  return ""
}
# Die unless the shell is the expected release. A readable but different version, or an unreadable
# version, stops the script; UNPU_SKIP_VERSION_CHECK=1 continues with a loud warning (use it only
# after reading the banner yourself).
set UNPU_VERSION_CHECK_SKIPPED 0
set UNPU_VERSION_FOUND not_checked
proc unpu_require_tool_version {expected} {
  global UNPU_VERSION_CHECK_SKIPPED UNPU_VERSION_FOUND
  set found [unpu_tool_version]
  set UNPU_VERSION_FOUND [expr {$found eq "" ? "unreadable" : $found}]
  if {$found eq $expected} {
    unpu_info "tool version $found matches the expected $expected"
    return $found
  }
  set skip [expr {[info exists ::env(UNPU_SKIP_VERSION_CHECK)] && $::env(UNPU_SKIP_VERSION_CHECK) eq "1"}]
  if {$found eq ""} {
    set why "the tool version could not be read"
  } else {
    set why "found version '$found', expected '$expected'"
  }
  if {$skip} {
    set UNPU_VERSION_CHECK_SKIPPED 1
    unpu_warn "$why; continuing because UNPU_SKIP_VERSION_CHECK=1 (read the shell banner yourself)"
    return $found
  }
  unpu_die "$why. Use the shell of release $expected (full path, see params.tcl ICC2_LM_SHELL); to continue anyway after reading the banner, setenv UNPU_SKIP_VERSION_CHECK 1"
}

# Run manifest: date, user, host, script, git revision, tool version, every parameter of
# params.tcl, checksum of each input/output file. Nothing hand-typed.
# dir defaults to LOG_DIR; the shared (NDM) stage passes NDM_DIR.
proc unpu_manifest {stage files {dir ""}} {
  global LOG_DIR UNPU_PARAM_NAMES UNPU_VERSION_CHECK_SKIPPED UNPU_VERSION_FOUND
  if {$dir eq ""} { set dir $LOG_DIR }
  unpu_ensure_dir $dir
  set path [file join $dir manifest_${stage}.txt]
  unpu_no_kit_write $path
  set user unknown
  if {[info exists ::env(USER)]} { set user $::env(USER) }
  if {[catch {open $path w} fh]} { unpu_die "cannot write manifest $path: $fh" }
  puts $fh "stage        = $stage"
  puts $fh "date         = [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
  puts $fh "user         = $user"
  puts $fh "host         = [info hostname]"
  puts $fh "script       = [info script]"
  puts $fh "git_rev      = [unpu_git_rev]"
  puts $fh "tool_version = [unpu_tool_version]"
  puts $fh "tcl_version  = [info patchlevel]"
  puts $fh "version_check_skipped = $UNPU_VERSION_CHECK_SKIPPED"
  puts $fh "version_found = $UNPU_VERSION_FOUND"
  puts $fh "--- parameters (params.tcl) ---"
  foreach n $UNPU_PARAM_NAMES { puts $fh "$n = [set ::$n]" }
  puts $fh "--- files (sha256) ---"
  foreach f $files {
    if {![file exists $f]} {
      close $fh
      unpu_die "manifest $stage: listed file does not exist: $f"
    }
    if {[file isdirectory $f]} {
      puts $fh "[format %-64s directory] $f"
    } else {
      puts $fh "[unpu_sha256 $f]  $f"
    }
  }
  close $fh
  unpu_info "manifest written: $path"
  return $path
}

# ---- LEF handling (pure Tcl) -------------------------------------------------
proc unpu_count_lef_macros {lef} {
  unpu_need_file $lef "LEF file"
  set fh [open $lef r]
  set n 0
  while {[gets $fh line] >= 0} { if {[regexp {^\s*MACRO\s+\S+} $line]} { incr n } }
  close $fh
  return $n
}
# Writes outfile = LEF header (everything before the first MACRO), then each requested MACRO
# block (MACRO <name> ... END <name>), then END LIBRARY. Dies unless every requested name is
# found exactly once and every block is closed. Returns the number of blocks written.
proc unpu_extract_lef_macros {lef names outfile} {
  unpu_need_file $lef "LEF file"
  set fh [open $lef r]
  set lines {}
  while {[gets $fh line] >= 0} { lappend lines $line }
  close $fh
  # pass 1: header end, and the line index of every MACRO line by name
  set header_end -1
  array set start {}
  array set count {}
  set i 0
  foreach line $lines {
    if {[regexp {^\s*MACRO\s+(\S+)\s*$} $line -> nm]} {
      if {$header_end < 0} { set header_end $i }
      if {![info exists count($nm)]} { set count($nm) 0 }
      incr count($nm)
      set start($nm) $i
    }
    incr i
  }
  if {$header_end < 0} { unpu_die "no MACRO found in $lef" }
  foreach nm $names {
    set c 0
    if {[info exists count($nm)]} { set c $count($nm) }
    if {$c == 0} { unpu_die "MACRO $nm not found in $lef" }
    if {$c > 1}  { unpu_die "MACRO $nm is defined $c times in $lef (must be exactly once)" }
  }
  # pass 2: write
  unpu_no_kit_write $outfile
  if {[catch {open $outfile w} out]} { unpu_die "cannot write $outfile: $out" }
  for {set k 0} {$k < $header_end} {incr k} { puts $out [lindex $lines $k] }
  set written 0
  foreach nm $names {
    set closed 0
    for {set k $start($nm)} {$k < [llength $lines]} {incr k} {
      set line [lindex $lines $k]
      puts $out $line
      if {[regexp {^\s*END\s+(\S+)\s*$} $line -> endnm] && $endnm eq $nm} { set closed 1; break }
    }
    if {!$closed} { close $out; unpu_die "MACRO $nm in $lef is not closed by END $nm" }
    incr written
  }
  puts $out "END LIBRARY"
  close $out
  return $written
}

# ---- checks ------------------------------------------------------------------
# unpu_check_pass stage name cond detail : prints PASS or FAIL; a FAIL stops the script unless
# UNPU_CHECK_CONTINUE is 1 (a checking script sets it so that every verdict is printed, then
# calls unpu_checks_finish, which exits non-zero if anything failed).
set UNPU_CHECK_CONTINUE 0
set UNPU_CHECK_FAILED 0
set UNPU_CHECK_TOTAL 0
proc unpu_check_pass {stage name cond detail} {
  global UNPU_CHECK_CONTINUE UNPU_CHECK_FAILED UNPU_CHECK_TOTAL
  incr UNPU_CHECK_TOTAL
  if {![string is boolean -strict $cond]} {
    unpu_die "check $stage/$name: condition '$cond' is not a boolean (internal script error)"
  }
  if {[string is true -strict $cond]} {
    puts "Info: \[unpu\] CHECK $stage $name PASS $detail"
    return 1
  }
  puts "Error: \[unpu\] CHECK $stage $name FAIL $detail"
  incr UNPU_CHECK_FAILED
  if {!$UNPU_CHECK_CONTINUE} { exit 1 }
  return 0
}
proc unpu_checks_finish {stage} {
  global UNPU_CHECK_FAILED UNPU_CHECK_TOTAL
  unpu_result $stage checks_total $UNPU_CHECK_TOTAL
  unpu_result $stage checks_failed $UNPU_CHECK_FAILED
  if {$UNPU_CHECK_FAILED > 0} { unpu_die "$stage: $UNPU_CHECK_FAILED of $UNPU_CHECK_TOTAL check(s) FAILED" }
  unpu_info "$stage: all $UNPU_CHECK_TOTAL check(s) passed"
}

# ---- pure-Tcl helpers for the setup stages (testable with made-up text) -------

# The NDM list written by ndm_file_gen.tcl: one absolute path per line, in reference-library order.
# Dies on a missing file, an empty file, or a listed NDM that does not exist.
proc unpu_read_ndm_manifest {path} {
  unpu_need_file $path "NDM manifest (run ndm_file_gen.tcl first)"
  set fh [open $path r]
  set list {}
  while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} continue
    if {![file exists $line]} { close $fh; unpu_die "NDM listed in $path does not exist: $line" }
    lappend list $line
  }
  close $fh
  if {[llength $list] == 0} { unpu_die "$path lists no NDM" }
  return $list
}

# Tool message ids (e.g. SDC-3, UIC-034, TLUP-011) found in captured text, sorted, unique.
# prefix "" = any id, or e.g. SDC to keep only SDC-<number>.
proc unpu_message_ids {text {prefix ""}} {
  set ids {}
  foreach {all pre num} [regexp -all -inline -- {\m([A-Z]{2,6})-([0-9]{1,4})\M} $text] {
    if {$prefix ne "" && $pre ne $prefix} continue
    lappend ids ${pre}-${num}
  }
  return [lsort -unique $ids]
}
# lines of text that contain a match of the regular expression
proc unpu_lines_matching {text re} {
  set out {}
  foreach l [split $text "\n"] { if {[regexp -- $re $l]} { lappend out [string trim $l] } }
  return $out
}
# ids in `found` that are not in `expected`
proc unpu_ids_unexpected {found expected} {
  set bad {}
  foreach i $found { if {[lsearch -exact $expected $i] < 0} { lappend bad $i } }
  return $bad
}
proc unpu_text_has {text phrase} { return [expr {[string first $phrase $text] >= 0}] }
# lines that mention unresolved references (wording not known from the handoff: 'unresolved', 'unable to resolve'; VERIFY), except the zero-count forms ("no unresolved", "0 unresolved")
proc unpu_unresolved_lines {text} {
  set out {}
  foreach l [split $text "\n"] {
    if {![regexp -nocase {unresolved|unable to resolve|cannot resolve} $l]} continue
    if {[regexp -nocase {\m(no|0|zero)\s+unresolved} $l]} continue
    lappend out [string trim $l]
  }
  return $out
}
# report_ref_libs text: is the library `name` listed as open? The real report (server run, task 047) has a flag column:
#   *+  scl18fs120 <path> <location>        with the legend  "*" = Library currently open, "+" = Library has technology information
# so a line whose flags (before the name) contain * is open. A line that says "open" in words is also accepted; "not open",
# "closed", "unopened" and "fail" never are. \m..\M are word boundaries, and _ is a word character, so scl18fs120 does not
# match scl18fs120_fillf. The name must be the first word after the flags (a path that contains the name does not count).
proc unpu_reflib_open {text name} {
  set nre [string map {. \\.} $name]
  foreach l [split $text "\n"] {
    if {![regexp "\\m${nre}\\M" $l]} continue
    if {[regexp -nocase {not\s+open|closed|unopened|fail} $l]} continue
    if {[regexp "^\\s*(\[*+\]*\\*\[*+\]*)\\s+${nre}\\M" $l]} { return 1 }
    if {[regexp -nocase {\mopen} $l]} { return 1 }
  }
  return 0
}
# report_corners text: does the region of `corner` hold the expected voltage and temperature numbers?
# The region starts at a line whose first word is the corner name (optionally after "Corner"/"Corner:") and
# runs to the line before the first line that starts another listed corner or to the end. The check is
# "the expected numbers appear among the numbers of the region"; a corner that cannot be found, or a region
# without the numbers (for example 1.8 V where 1.62 V is expected), is reported. The format of
# report_corners is NOT known from the handoff (VERIFY): when this cannot find the corner it says so.
# Returns {ok|fail detail}.
proc unpu_corner_has_point {text corner others volt temp} {
  set lines [split $text "\n"]
  set start -1
  set i 0
  foreach l $lines {
    if {[regexp "^\\s*(Corner\\s*:?\\s*)?[string map {. \\.} $corner]\\M" $l]} { set start $i; break }
    incr i
  }
  if {$start < 0} { return [list fail "corner '$corner' not found in the report text"] }
  set region {}
  for {set j $start} {$j < [llength $lines]} {incr j} {
    set l [lindex $lines $j]
    if {$j > $start} {
      set stop 0
      foreach o $others { if {[regexp "^\\s*(Corner\\s*:?\\s*)?[string map {. \\.} $o]\\M" $l]} { set stop 1 } }
      if {$stop} break
    }
    lappend region $l
  }
  # numbers = whitespace/punctuation-separated tokens that are numbers, optionally with a trailing unit letter
  # (V, C); digits inside names such as tsl18fs120_scl_ss are NOT numbers
  set nums {}
  foreach tok [regexp -all -inline -- {[^\s,;:()=\[\]/]+} [join $region " "]] {
    regsub -- {[VvCc]$} $tok {} tok2
    if {[string is double -strict $tok2]} { lappend nums $tok2 }
  }
  set hv 0; set ht 0
  foreach n $nums { if {abs($n - $volt) < 1e-6} { set hv 1 }; if {abs($n - $temp) < 1e-6} { set ht 1 } }
  if {$hv && $ht} { return [list ok "corner '$corner': found $volt V and $temp C"] }
  set miss {}
  if {!$hv} { lappend miss "${volt} V" }
  if {!$ht} { lappend miss "${temp} C" }
  return [list fail "corner '$corner': [join $miss { and }] not found; numbers in its region: [join $nums { }]"]
}
# "{0.0 0.0} {868.0 868.0}" (the boundary_bbox attribute) or any text with four numbers -> {llx lly urx ury},
# or {} if there are not exactly four numbers.
proc unpu_parse_bbox {text} {
  set nums {}
  foreach tok [regexp -all -inline -- {[^\s,;(){}\[\]]+} $text] { if {[string is double -strict $tok]} { lappend nums $tok } }
  if {[llength $nums] != 4} { return {} }
  return $nums
}
# report_design -floorplan text -> {ok chip core util detail} or {fail detail}.
# Tolerant: a line holding the words "chip area" / "core area" / "utilization" gives its first number after
# the label (commas in numbers and a trailing %, um2 or um^2 are accepted); if that line has no number the next
# non-empty line is used. Strict: a missing chip or core area is a failure that quotes the text seen (first 12
# lines). Utilization is optional (util = "" when absent). The layout of the real report is NOT known from the
# handoff (VERIFY): 18.14 only quotes "chip area 686,909.44", "core 650,280.96 um2", "core utilisation 66.00%".
proc unpu_parse_floorplan_areas {text} {
  set lines [split $text "\n"]
  set found(chip) ""; set found(core) ""; set found(util) ""
  foreach {key re} {chip {(?i)chip\s*area} core {(?i)core\s*area} util {(?i)utili[sz]ation}} {
    for {set i 0} {$i < [llength $lines]} {incr i} {
      set l [lindex $lines $i]
      if {![regexp -indices -- $re $l m]} continue
      if {$key ne "util" && [regexp -nocase -- {utili[sz]ation} $l]} continue   ;# "core area utilization" is not the core area
      set rest [string range $l [expr {[lindex $m 1] + 1}] end]
      set v [unpu_first_number $rest]
      if {$v eq ""} {
        for {set j [expr {$i + 1}]} {$j < [llength $lines]} {incr j} {
          if {[string trim [lindex $lines $j]] eq ""} continue
          set v [unpu_first_number [lindex $lines $j]]
          break
        }
      }
      if {$v ne ""} { set found($key) $v; break }
    }
  }
  if {$found(chip) eq "" || $found(core) eq ""} {
    set seen [join [lrange $lines 0 11] " | "]
    set miss {}
    if {$found(chip) eq ""} { lappend miss "chip area" }
    if {$found(core) eq ""} { lappend miss "core area" }
    return [list fail "not found in the report text: [join $miss { and }]. Text seen (first lines): $seen"]
  }
  return [list ok $found(chip) $found(core) $found(util) "chip area $found(chip), core area $found(core), utilization '$found(util)'"]
}
# first number in a string; tokens are split at whitespace and = : ( ) ; commas inside a number are removed
# (668,469.76 -> 668469.76); a trailing % is dropped; tokens such as um2 or um^2 are not numbers.
proc unpu_first_number {s} {
  foreach tok [regexp -all -inline -- {[^\s=:()]+} $s] {
    regsub -- {%$} $tok {} tok
    set tok [string map {, {}} $tok]
    if {[string is double -strict $tok]} { return $tok }
  }
  return ""
}

# ---- power stage helpers (task 041): command strings, summaries, terminal/stripe boxes -----------

# The five power-grid commands of handoff 18.15 as Tcl lists, built from the parameters:
#   create_pg_std_cell_conn_pattern std_rail -layers {M1} -rail_width 0.74
#   create_pg_mesh_pattern top_mesh -layers {{{vertical_layer: TOP_M} {width: 2.24} {pitch: 112} {spacing: interleaving}}}
#   set_pg_strategy s_rail -core -pattern {{name: std_rail} {nets: {VDD VSS}}}
#   set_pg_strategy s_mesh -core -pattern {{name: top_mesh} {nets: {VDD VSS}}}
#   compile_pg -strategies {s_rail s_mesh}
proc unpu_pg_commands {rail_pat mesh_pat strat_rail strat_mesh rail_layer rail_w stripe_layer stripe_w pitch spacing net_p net_g} {
  set mesh_one [list "vertical_layer: $stripe_layer" "width: $stripe_w" "pitch: $pitch" "spacing: $spacing"]
  set nets "\{$net_p $net_g\}"
  return [list \
    [list create_pg_std_cell_conn_pattern $rail_pat -layers [list $rail_layer] -rail_width $rail_w] \
    [list create_pg_mesh_pattern $mesh_pat -layers [list $mesh_one]] \
    [list set_pg_strategy $strat_rail -core -pattern [list "name: $rail_pat" "nets: $nets"]] \
    [list set_pg_strategy $strat_mesh -core -pattern [list "name: $mesh_pat" "nets: $nets"]] \
    [list compile_pg -strategies [list $strat_rail $strat_mesh]]]
}

# "12,487" -> 12487; "" if not an integer
proc unpu_int_token {tok} {
  set tok [string map {, {}} $tok]
  if {[regexp -- {^[0-9]+$} $tok]} { return [scan $tok %d] }
  return ""
}
# all integers (commas allowed) on a line, tokens split at whitespace and : = ( ) ;
proc unpu_ints_in {line} {
  set out {}
  foreach tok [regexp -all -inline -- {[^\s:=();,]+(?:,[0-9]{3})*} $line] {
    set v [unpu_int_token $tok]
    if {$v ne ""} { lappend out $v }
  }
  return $out
}
# connect_pg_net summary -> list {net count ...} for the requested nets, or "not parsed".
# Accepts any line that holds the net name as a whole word and at least one integer; the count is the LARGEST
# integer on the first such line (so a small id on the line does not win). The real table layout is not known
# (VERIFY); a net without a number makes the whole result "not parsed" so the script falls back to counting.
proc unpu_parse_connect_pg {text nets} {
  set out {}
  foreach n $nets {
    set cnt ""
    foreach l [split $text "\n"] {
      if {![regexp -- "\\m[string map {. \\.} $n]\\M" $l]} continue
      set ints [unpu_ints_in [string map {/ { }} $l]]      ;# "previous/current" (18.22: VDD 12041/34553) holds two integers
      if {[llength $ints] == 0} continue
      set cnt [lindex [lsort -integer -decreasing $ints] 0]
      break
    }
    if {$cnt eq ""} { return "not parsed" }
    lappend out $n $cnt
  }
  return $out
}
# check_pg_drc summary -> number of errors, or "not parsed". Accepts "no errors" / "0 errors", a line holding
# "error(s)" or "violation(s)" with a number ("Total errors: 3", "Found 3 DRC errors"), nothing else.
proc unpu_parse_pg_drc {text} {
  foreach l [split $text "\n"] {
    if {[regexp -nocase -- {\mno\s+(drc\s+)?(error|violation)} $l]} { return 0 }
    if {![regexp -nocase -- {error|violation} $l]} continue
    if {[regexp -nocase -- {^\s*(info|warning)\M.*\mno\M} $l]} continue
    set ints [unpu_ints_in $l]
    if {[llength $ints] > 0} { return [lindex $ints 0] }
  }
  return "not parsed"
}
# check_pg_connectivity summary -> {wires N vias N terminals N cells N} for the categories found; a category
# that is not found is absent from the result. "no floating wires" counts as 0; the cells value is the largest
# integer on the line (per-net lists such as "VDD 12487 VSS 12487" give 12487).
proc unpu_parse_pg_connectivity {text} {
  set res {}
  foreach {key re} {wires {(?i)floating\s+(wire|route|shape)} vias {(?i)floating\s+via} terminals {(?i)floating\s+terminal} cells {(?i)floating\s+(std\s*|standard\s*)?cell}} {
    foreach l [split $text "\n"] {
      if {![regexp -- $re $l]} continue
      if {[regexp -nocase -- {\mno\s+floating} $l]} { lappend res $key 0; break }
      set ints [unpu_ints_in $l]
      if {[llength $ints] == 0} continue
      lappend res $key [lindex [lsort -integer -decreasing $ints] 0]
      break
    }
  }
  return $res
}
# Terminal boxes against stripe boxes. Both are lists of {net llx lly urx ury}. die = die side (um),
# bottom_y = y of the bottom boundary, tol = tolerance. Returns a list of five problem lists, in this order:
#   count      terminals per net differ from stripes per net
#   xrange     a stripe has no terminal with the same net and x range
#   duplicate  two terminals share the same net and x range
#   lowesty    a terminal does not start at bottom_y
#   outside    a terminal is outside [0, die] in x or y
proc unpu_terminals_vs_stripes {terms stripes die bottom_y tol} {
  set count {}; set xr {}; set dup {}; set low {}; set outside {}
  array set ns {}; array set nt {}
  foreach s $stripes { set n [lindex $s 0]; if {![info exists ns($n)]} { set ns($n) 0 }; incr ns($n) }
  foreach t $terms   { set n [lindex $t 0]; if {![info exists nt($n)]} { set nt($n) 0 }; incr nt($n) }
  foreach n [lsort -unique [concat [array names ns] [array names nt]]] {
    set a [expr {[info exists ns($n)] ? $ns($n) : 0}]; set b [expr {[info exists nt($n)] ? $nt($n) : 0}]
    if {$a != $b} { lappend count "net $n: $b terminal(s) for $a stripe(s)" }
  }
  foreach s $stripes {
    lassign $s n sx0 sy0 sx1 sy1
    set hits 0
    foreach t $terms {
      lassign $t tn tx0 ty0 tx1 ty1
      if {$tn eq $n && abs($tx0 - $sx0) <= $tol && abs($tx1 - $sx1) <= $tol} { incr hits }
    }
    if {$hits == 0} { lappend xr "stripe $n x $sx0..$sx1 has no terminal with that x range" }
  }
  set i 0
  foreach t $terms {
    lassign $t tn tx0 ty0 tx1 ty1
    set j 0
    foreach u $terms {
      if {$j > $i} {
        lassign $u un ux0 uy0 ux1 uy1
        if {$un eq $tn && abs($ux0 - $tx0) <= $tol && abs($ux1 - $tx1) <= $tol} { lappend dup "net $tn: two terminals at x $tx0..$tx1" }
      }
      incr j
    }
    if {abs($ty0 - $bottom_y) > $tol} { lappend low "terminal $tn x $tx0..$tx1 starts at y $ty0, expected $bottom_y" }
    if {$tx0 < -$tol || $ty0 < -$tol || $tx1 > $die + $tol || $ty1 > $die + $tol} { lappend outside "terminal $tn x $tx0..$tx1 y $ty0..$ty1 is outside the die 0..$die" }
    incr i
  }
  return [list $count $xr $dup $low $outside]
}
# "{60.48 0.0} {62.72 6.0}" plus a net name -> {net 60.48 0.0 62.72 6.0} rounded to 4 decimals, or {} if not 4 numbers
proc unpu_box_entry {net bbox_text} {
  set b [unpu_parse_bbox $bbox_text]
  if {[llength $b] != 4} { return {} }
  set out [list $net]
  foreach v $b { lappend out [unpu_round4 $v] }
  return $out
}

# ---- command-usage probe helpers (task 042) -----------------------------------------------------
# Classify what a probe captured: text = what the command printed, err = the Tcl error message (or "").
# Returns {FOUND|NOT_FOUND|ERROR detail}. Text first: a usage text counts as FOUND even if the command also
# raised an error (some shells return an error code after printing -help); an empty text is judged by the error.
proc unpu_classify_help {text {err ""}} {
  set nf {unknown command|invalid command name|no commands? match|no app options? match|no (matching )?(commands|app options|options) |no such command|command not found|ambiguous command}
  set t [string trim $text]
  if {$t ne ""} {
    if {[regexp -nocase -- $nf $t]} { return [list NOT_FOUND [lindex [split $t "\n"] 0]] }
    if {[regexp -line -- {^\s*Error:} $t] && ![regexp -nocase -- {usage} $t]} {
      regexp -line -- {^\s*Error:.*$} $t first
      return [list ERROR [string trim $first]]
    }
    return [list FOUND "[llength [split $t "\n"]] line(s)"]
  }
  if {$err ne ""} {
    if {[regexp -nocase -- $nf $err]} { return [list NOT_FOUND $err] }
    return [list ERROR $err]
  }
  return [list NOT_FOUND "empty output"]
}
# a pattern or name as a file-name part: * -> X, anything outside letters digits _ . - -> _
proc unpu_probe_filename {name} {
  return [regsub -all -- {[^A-Za-z0-9_.-]} [string map {* X} $name] _]
}
# summary of probe records, each {STATUS kind name detail}: returns {lines found not_found error total not_found_names}
proc unpu_probe_summary {records} {
  set lines {}; set f 0; set n 0; set e 0; set nfn {}
  foreach r $records {
    lassign $r st kind name detail
    lappend lines [format "%-9s %-8s %-40s %s" $st $kind $name $detail]
    switch -- $st { FOUND { incr f } NOT_FOUND { incr n; lappend nfn "$kind:$name" } default { incr e } }
  }
  return [list $lines $f $n $e [llength $records] $nfn]
}

# ---- CTS stage helpers (task 043): parsers for texts whose layout is not known (VERIFY) -------------------

# {key regex ...} spec -> {key value ...}: the first number after the label on the first line matching the regex
# (the next non-empty line if the label line has none); value "" when not found.
proc unpu_find_numbers {text spec} {
  set lines [split $text "\n"]
  set out {}
  foreach {key re} $spec {
    set val ""
    for {set i 0} {$i < [llength $lines] && $val eq ""} {incr i} {
      set l [lindex $lines $i]
      if {![regexp -indices -- $re $l m]} continue
      set val [unpu_first_number [string range $l [expr {[lindex $m 1] + 1}] end]]
    }
    lappend out $key $val
  }
  return $out
}
# check_legality summary -> number of violations, or "not parsed". Accepts "TOTAL 0 Violations" (the 18.16/18.18 text)
# and "Total N violations" in any case; otherwise "not parsed".
proc unpu_parse_legality {text} {
  foreach l [split $text "\n"] {
    if {[regexp -nocase -- {\mtotal\s+([0-9][0-9,]*)\s+violations?} $l -> n]} { return [string map {, {}} $n] }
  }
  return "not parsed"
}
# occurrences of message ids with a prefix: {id count id count ...}, ids sorted (every occurrence counts, not every line)
proc unpu_count_ids {text prefix} {
  array set c {}
  foreach {all pre num} [regexp -all -inline -- {\m([A-Z]{2,6})-([0-9]{1,5})\M} $text] {
    if {$pre ne $prefix} continue
    set id ${pre}-${num}
    if {![info exists c($id)]} { set c($id) 0 }
    incr c($id)
  }
  set out {}
  foreach id [lsort [array names c]] { lappend out $id $c($id) }
  return $out
}
# report_clock_qor -type summary text -> {ok sinks S levels L repeaters R latency_<corner> x skew_<corner> y ...}
# or {fail detail}. Sinks are required; levels, repeaters and the per-corner latency and skew are optional (""
# when not found). A corner's region starts at a line that begins with (Corner)? <name> and ends before the first
# line that starts another listed corner. 18.17 quotes: 2,465 sinks, 3 levels, 53 clock repeaters, corner default
# max latency 1.21 ns / global skew 0.95 ns, corner ff 0.49 / 0.36. Layout NOT known (VERIFY).
proc unpu_parse_clock_qor {text corners} {
  array set g [unpu_find_numbers $text {sinks {(?i)sinks?} levels {(?i)levels?} repeaters {(?i)(clock\s+)?repeaters?}}]
  if {$g(sinks) eq ""} {
    return [list fail "no clock sinks number found in the report text. Text seen (first lines): [join [lrange [split $text "\n"] 0 11] { | }]"]
  }
  set out [list ok sinks $g(sinks) levels $g(levels) repeaters $g(repeaters)]
  set lines [split $text "\n"]
  foreach c $corners {
    set others {}; foreach o $corners { if {$o ne $c} { lappend others $o } }
    set start -1
    for {set i 0} {$i < [llength $lines]} {incr i} {
      if {[regexp -- "^\\s*(Corner\\s*:?\\s*)?[string map {. \\.} $c]\\M" [lindex $lines $i]]} { set start $i; break }
    }
    set region {}
    if {$start >= 0} {
      for {set j $start} {$j < [llength $lines]} {incr j} {
        set l [lindex $lines $j]
        if {$j > $start} {
          set stop 0
          foreach o $others { if {[regexp -- "^\\s*(Corner\\s*:?\\s*)?[string map {. \\.} $o]\\M" $l]} { set stop 1 } }
          if {$stop} break
        }
        lappend region $l
      }
    }
    array unset r
    array set r [unpu_find_numbers [join $region "\n"] {latency {(?i)(max(imum)?\s*)?latency} skew {(?i)(global\s*)?skew}}]
    lappend out latency_$c $r(latency) skew_$c $r(skew)
  }
  return $out
}
# report_timing text -> list of {startpoint endpoint slack group} (slack numeric; "" when absent), one per path
proc unpu_parse_report_timing_paths {text} {
  set paths {}
  set cur {}
  set group ""
  foreach l [split $text "\n"] {
    if {[regexp -- {^\s*Startpoint:\s*(\S+)} $l -> sp]} {
      set cur [list $sp "" "" $group]
    } elseif {[regexp -- {^\s*Endpoint:\s*(\S+)} $l -> ep] && $cur ne ""} {
      set cur [lreplace $cur 1 1 $ep]
    } elseif {[regexp -- {^\s*Path Group:\s*(\S+)} $l -> grp]} {
      set group $grp
      if {$cur ne ""} { set cur [lreplace $cur 3 3 $grp] }
    } elseif {[regexp -- {slack\s*\(([A-Za-z ]+)\)\s+(-?[0-9]+(?:\.[0-9]+)?)} $l -> st v] && $cur ne ""} {
      set cur [lreplace $cur 2 2 $v]
      lappend paths $cur
      set cur {}
    }
  }
  return $paths
}
# the n worst entries (lowest slack first) of {start end slack group} as text lines "slack  end  (from start)"
proc unpu_worst_endpoints {paths n} {
  set rows {}
  foreach p $paths { if {[lindex $p 2] ne ""} { lappend rows [list [lindex $p 2] [lindex $p 1] [lindex $p 0] [lindex $p 3]] } }
  set rows [lsort -real -index 0 $rows]
  set out {}
  foreach r [lrange $rows 0 [expr {$n - 1}]] { lappend out [format "%s ns  %s  (from %s, group %s)" [lindex $r 0] [lindex $r 1] [lindex $r 2] [lindex $r 3]] }
  return $out
}
# number of violating paths (slack < 0) in parsed paths, in total and per group: {total group n group n ...}
proc unpu_violations_by_group {paths} {
  array set c {}
  set total 0
  foreach p $paths {
    set s [lindex $p 2]
    if {$s eq "" || $s >= 0} continue
    incr total
    set g [lindex $p 3]; if {$g eq ""} { set g unknown }
    if {![info exists c($g)]} { set c($g) 0 }
    incr c($g)
  }
  set out [list $total]
  foreach g [lsort [array names c]] { lappend out $g $c($g) }
  return $out
}
# a constraint report (report_constraint -all_violators ...): the number of "(VIOLATED)" rows, 0 if the text says
# there are no violations, else "unavailable" (an empty or unrecognised text is never counted as zero)
proc unpu_parse_violations {text} {
  set n 0
  foreach l [split $text "\n"] { if {[regexp -nocase -- {\(violated\)} $l]} { incr n } }
  if {$n > 0} { return $n }
  if {[regexp -nocase -- {no\s+(\w+\s+)?violat|\m0\s+violat|no violating} $text]} { return 0 }
  return "unavailable"
}
# first "clock uncertainty" value of a report_timing text (absolute value), or ""
proc unpu_parse_clock_uncertainty {text} {
  foreach l [split $text "\n"] {
    if {[regexp -nocase -- {clock\s+uncertainty} $l]} {
      set v [unpu_first_number [regsub -nocase -- {.*clock\s+uncertainty} $l {}]]
      if {$v ne ""} { return [expr {abs($v)}] }
    }
  }
  return ""
}

# ---- routing stage helpers (task 044): parsers for texts whose layout is not fully known (VERIFY) -------------

# check_routes "Verify Summary" -> {nets N not_extracted M open_nets O frozen F drcs D antenna A tie_lines {...}}.
# Strict: every field comes from a line in the form printed in the first run (18.20/18.25/18.26):
#   Total number of nets = 13999, of which 0 are not extracted
#   Total number of open nets = 0, of which 0 are frozen
#   Total number of DRCs = 0
#   Total number of antenna violations = 0
# and the "tie to rail ... not checked" lines (kept as text). A field not found is "not parsed".
proc unpu_parse_check_routes {text} {
  array set r {nets "not parsed" not_extracted "not parsed" open_nets "not parsed" frozen "not parsed" drcs "not parsed" antenna "not parsed"}
  set tie {}
  foreach l [split $text "\n"] {
    if {[regexp -nocase -- {Total number of nets\s*=\s*([0-9,]+)\s*,\s*of which\s*([0-9,]+)\s*are not extracted} $l -> a b]} { set r(nets) [string map {, {}} $a]; set r(not_extracted) [string map {, {}} $b] }
    if {[regexp -nocase -- {Total number of open nets\s*=\s*([0-9,]+)\s*,\s*of which\s*([0-9,]+)\s*are frozen} $l -> a b]} { set r(open_nets) [string map {, {}} $a]; set r(frozen) [string map {, {}} $b] }
    if {[regexp -nocase -- {Total number of DRCs\s*=\s*([0-9,]+)} $l -> a]} { set r(drcs) [string map {, {}} $a] }
    if {[regexp -nocase -- {Total number of antenna violations\s*=\s*([0-9,]+)} $l -> a]} { set r(antenna) [string map {, {}} $a] }
    if {[regexp -nocase -- {tie\s*(to|-)?\s*rail} $l] && [regexp -nocase -- {not checked} $l]} { lappend tie [string trim $l] }
  }
  return [list nets $r(nets) not_extracted $r(not_extracted) open_nets $r(open_nets) frozen $r(frozen) drcs $r(drcs) antenna $r(antenna) tie_lines $tie]
}
# check_lvs summary -> {shorts N opens N floating N} ("not parsed" per field). Accepts "N shorts" and "shorts = N" /
# "Short: N" forms; a line saying "no shorts" counts as 0. VERIFY: 18.20 gives the three numbers, not the layout.
proc unpu_parse_check_lvs {text} {
  set out {}
  foreach {key re} {shorts {shorts?|short\s*circuits?} opens {opens?\M|open\s*nets?} floating {floating\s*routes?}} {
    set val "not parsed"
    foreach l [split $text "\n"] {
      if {![regexp -nocase -- "\\m($re)" $l]} continue
      if {$key eq "opens" && [regexp -nocase -- {open nets|frozen} $l] && ![regexp -nocase -- {\m0\s+opens?|\mno\s+opens?|opens?\s*[:=]} $l]} continue
      if {[regexp -nocase -- "\\mno\\s+(\\w+\\s+)?($re)" $l]} { set val 0; break }
      if {[regexp -nocase -- "(\[0-9,\]+)\\s+($re)" $l -> n]} { set val [string map {, {}} $n]; break }
      if {[regexp -nocase -- "($re)\[^0-9\]*?(\[0-9,\]+)" $l -> w n]} { set val [string map {, {}} $n]; break }
    }
    lappend out $key $val
  }
  return $out
}
# route_auto / route_opt summary -> {wire_total X wire_<L> v ... contacts_total N via_<L> v ... open_nets N finished_dr 0|1}
# Layer sections: lines after one containing "wire length" belong to the wire section until a line with "contact" or
# "via" starts the via section. All values "" when not found. 18.20 quotes: wire length 792,524 um (M1 16,927; M2 323,338;
# M3 368,389; TOP_M 81,399); contacts 103,651 (V2 49,073; V3 49,523; TOP_V 5,055); 0 open nets of 13,997.
proc unpu_parse_route_summary {text wire_layers via_layers} {
  array set r {wire_total "" contacts_total "" open_nets ""}
  foreach l $wire_layers { set r(wire_$l) "" }
  foreach l $via_layers  { set r(via_$l) "" }
  set sect none
  foreach l [split $text "\n"] {
    if {[regexp -nocase -- {total\s+wire\s*length} $l]} { set r(wire_total) [unpu_first_number [regsub -nocase -- {.*wire\s*length} $l {}]]; set sect wire; continue }
    if {[regexp -nocase -- {wire\s*length} $l] && $sect eq "none"} { set sect wire }
    if {[regexp -nocase -- {total\s+(number\s+of\s+)?(contacts?|vias?)} $l]} { set r(contacts_total) [unpu_first_number [regsub -nocase -- {.*(contacts?|vias?)} $l {}]]; set sect via; continue }
    if {[regexp -nocase -- {contacts?|\mvias?\M} $l] && $sect eq "wire"} { set sect via }
    if {[regexp -nocase -- {open\s+nets?} $l] && $r(open_nets) eq ""} { set r(open_nets) [unpu_first_number [regsub -nocase -- {.*open\s+nets?} $l {}]] }
    foreach lay $wire_layers {
      if {$sect eq "wire" && $r(wire_$lay) eq "" && [regexp -- "^\\s*(Layer\\s+)?[string map {. \\.} $lay]\\M" $l]} { set r(wire_$lay) [unpu_first_number [regsub -- "^\\s*(Layer\\s+)?[string map {. \\.} $lay]" $l {}]] }
    }
    foreach lay $via_layers {
      if {$sect eq "via" && $r(via_$lay) eq "" && [regexp -- "^\\s*(Layer\\s+)?[string map {. \\.} $lay]\\M" $l]} { set r(via_$lay) [unpu_first_number [regsub -- "^\\s*(Layer\\s+)?[string map {. \\.} $lay]" $l {}]] }
    }
  }
  set out [list wire_total $r(wire_total)]
  foreach lay $wire_layers { lappend out wire_$lay $r(wire_$lay) }
  lappend out contacts_total $r(contacts_total)
  foreach lay $via_layers { lappend out via_$lay $r(via_$lay) }
  lappend out open_nets $r(open_nets) finished_dr [expr {[regexp -nocase -- {Finish DR since reached 0 DRC} $text] ? 1 : 0}]
  return $out
}
# detail-route iteration lines -> list of {iteration violations}: lines holding "iteration N" and a number followed by
# violations/DRCs/drc (first such pair on the line). Layout NOT known (VERIFY).
proc unpu_parse_dr_iterations {text} {
  set out {}
  foreach l [split $text "\n"] {
    if {![regexp -nocase -- {iteration\s*:?\s*([0-9]+)} $l -> it]} continue
    if {[regexp -nocase -- {([0-9]+)\s*(violations?|DRCs?|drc)} $l -> v]} { lappend out [list $it $v] } elseif {[regexp -nocase -- {(violations?|DRCs?)\s*[:=]?\s*([0-9]+)} $l -> w v]} { lappend out [list $it $v] }
  }
  return $out
}
# ZRT-311 lines ("Skipping antenna analysis for net X ... not enough gate area information") -> sorted unique net names
proc unpu_zrt311_nets {text} {
  set nets {}
  foreach l [split $text "\n"] {
    if {[string first ZRT-311 $l] < 0} continue
    if {[regexp -- {net\s+'?([^\s',]+)'?} $l -> n]} { lappend nets $n }
  }
  return [lsort -unique $nets]
}
# the lines of a manifest file are appended (hold_accepted etc.)
proc unpu_manifest_append {stage lines {dir ""}} {
  global LOG_DIR
  if {$dir eq ""} { set dir $LOG_DIR }
  set path [file join $dir manifest_${stage}.txt]
  unpu_no_kit_write $path
  if {[catch {open $path a} fh]} { unpu_die "cannot append to manifest $path: $fh" }
  foreach l $lines { puts $fh $l }
  close $fh
}
# pure rule of the hold switch: decides what route.tcl does with the hold check.
# violations = count or "unavailable"; accept = "0"/"1". Returns pass | fail | accepted.
# A residual is accepted only when the count is KNOWN (> 0) and the switch is 1; an unavailable count never is.
proc unpu_hold_decision {violations accept} {
  if {$violations eq "unavailable"} { return fail }
  if {$violations == 0} { return pass }
  if {$accept eq "1"} { return accepted }
  return fail
}
# state of a boolean application option from its value text: on (true/1/on/yes), off (false/0/off/no), unknown (anything else,
# including an empty string). Case-insensitive, surrounding spaces and braces ignored. Pure rule, used by route.tcl.
proc unpu_option_state {value} {
  set v [string tolower [string trim $value " \t\r\n{}"]]
  if {[lsearch -exact {true 1 on yes} $v] >= 0} { return on }
  if {[lsearch -exact {false 0 off no} $v] >= 0} { return off }
  return unknown
}
# the value of an application option from the text of report_app_options / get_app_options: the line whose first word is the
# option name; the value is the boolean word (true false on off yes no 0 1) found after the name. If the line holds boolean
# words that DISAGREE (for example a Default column and a Value column), the value is ambiguous and "" is returned: the column
# layout is otherwise not known, so no column is guessed. "" also when the option is not listed or has no boolean word.
proc unpu_app_option_from_report {text name} {
  foreach l [split $text "\n"] {
    set w [regexp -all -inline -- {\S+} $l]
    if {[llength $w] < 2 || [lindex $w 0] ne $name} continue
    # The real report_app_options row (server run, task 047) is: name type Value User-value User-default System-default scope status
    # source, with -- for an empty column, e.g.  route.detail.antenna  bool  --  --  --  true  block  normal  --
    # The effective value is the first column of Value, User-value, User-default, System-default that is not --.
    if {[llength $w] >= 6 && [lindex $w 1] eq "bool"} {
      foreach x [lrange $w 2 5] { if {$x ne "--"} { return $x } }
      return ""
    }
    set found {}
    foreach x [lrange $w 1 end] { if {[unpu_option_state $x] ne "unknown"} { lappend found $x } }
    if {[llength $found] == 0} { return "" }
    set states {}
    foreach x $found { lappend states [unpu_option_state $x] }
    if {[llength [lsort -unique $states]] > 1} { return "" }
    return [lindex $found 0]
  }
  return ""
}
# what route.tcl says about the router's antenna switch: returns {state message}; state on = silent Info, anything else is the
# text of a loud Warning (the router only fixes antennas if the option is on)
proc unpu_antenna_switch_message {name value} {
  set s [unpu_option_state $value]
  if {$s eq "on"} { return [list on "$name = $value: the detail router fixes antenna violations"] }
  if {$s eq "off"} { return [list off "!!! $name = '$value' (OFF): the router will NOT fix antenna violations, whatever define_antenna_rule says. Routing goes on; decide before the next run whether this is intended !!!"] }
  return [list unknown "!!! $name could not be read as true/false (value '$value'): it is unknown whether the router fixes antenna violations. Read the printed options above !!!"]
}
# manifest lines "hold_endpoint_<i> = <endpoint text>" for a list of worst endpoints (route.tcl and fill.tcl)
proc unpu_hold_endpoint_lines {lines} {
  set out {}
  set i 0
  foreach l $lines { incr i; lappend out "hold_endpoint_$i = $l" }
  return $out
}
# check_workspace output: 1 when it holds the success line "Workspace check succeeded!" (real text, server run of task 047)
proc unpu_workspace_check_ok {text} { return [expr {[string first "Workspace check succeeded" $text] >= 0}] }
# number of physical designs the workspace skipped: "Information: Skipped 6 physical designs (LM-052)" -> 6, "" when absent
proc unpu_workspace_skipped {text} {
  if {[regexp -- {Skipped\s+([0-9]+)\s+physical designs?\s+\(LM-052\)} $text -> n]} { return $n }
  return ""
}
# ---- fill stage helpers (task 045) -------------------------------------------------------------------------
# connect_pg_net -automatic summary (extends unpu_parse_connect_pg, which returns only the largest count per net):
# {pins N <net>_previous P <net>_current C ...}; every field "not parsed" when absent. The table of 18.22 has a line per net
# "Power net VDD   12041/34553" (previous/current; a space instead of the slash is accepted) and the sentence
# "connections of 45,024 power/ground pin(s) are created or changed". Layout VERIFY (the 18.22 numbers, not the text, are known).
proc unpu_parse_connect_pg_change {text nets} {
  set pins "not parsed"
  foreach l [split $text "\n"] {
    if {[regexp -nocase -- {connections?\s+of\s+([0-9][0-9,]*)\s+power/ground\s+pins?} $l -> n]} { set pins [string map {, {}} $n]; break }
  }
  set out [list pins $pins]
  foreach n $nets {
    set prev "not parsed"; set cur "not parsed"
    foreach l [split $text "\n"] {
      if {![regexp -- "\\m[string map {. \\.} $n]\\M" $l]} continue
      set ints [unpu_ints_in [string map {/ { }} $l]]
      if {[llength $ints] >= 2} { set prev [lindex $ints end-1]; set cur [lindex $ints end]; break }
    }
    lappend out ${n}_previous $prev ${n}_current $cur
  }
  return $out
}
# create_stdcell_fillers output -> {cell count ...} in the order printed, cell names without a library prefix. Accepts the
# line of the first run: "... 4159 of regular filler feedth9 inserted" (any words between "of" and "filler", at most three).
# The same cell printed twice is summed. Nothing found gives an empty list.
proc unpu_parse_fillers {text} {
  array set c {}
  set order {}
  foreach l [split $text "\n"] {
    if {[regexp -nocase -- {\m([0-9][0-9,]*)\s+of\s+(?:\S+\s+){0,3}?filler\s+(\S+)\s+inserted} $l -> n cell]} {
      set cell [lindex [split $cell /] end]
      set n [string map {, {}} $n]
      if {![info exists c($cell)]} { set c($cell) 0; lappend order $cell }
      incr c($cell) $n
    }
  }
  set out {}
  foreach cell $order { lappend out $cell $c($cell) }
  return $out
}
# total of a {cell count ...} list
proc unpu_filler_total {counts} {
  set s 0
  foreach {cell n} $counts { incr s $n }
  return $s
}
# Sites in the rows, sites taken by the standard cells and the free ones: {total used free}.
# total = rows * sites_per_row; used = cell_area / (site_w * row_h) rounded to a whole site; free = total - used.
# 18.22: cell area 428,609.66 um2 / (0.56 * 5.6) = 136,674 sites; 144 rows * 1,440 = 207,360; free 70,686.
# A cell area that is not a number gives "not parsed" (the caller then has no check, only the printed arithmetic).
proc unpu_free_sites {rows sites_per_row cell_area site_w row_h} {
  set area [string map {, {}} $cell_area]
  if {![string is double -strict $area]} { return "not parsed" }
  set total [expr {$rows * $sites_per_row}]
  set used [expr {int(round($area / ($site_w * $row_h)))}]
  return [list $total $used [expr {$total - $used}]]
}
# Filler coverage: counts {cell n ...}, sitemap {cell sites ...} (feedth 1 feedth3 3 feedth9 9), free sites, tolerance in sites.
# Returns {ok covered free diff unknown}: covered = sum n * sites; diff = covered - free; ok = |diff| <= tol and no cell without an
# entry in sitemap (unknown lists those cells; an unknown cell makes ok 0 because its width is not known).
proc unpu_filler_coverage {counts sitemap free tol} {
  array set sm $sitemap
  set covered 0; set unknown {}
  foreach {cell n} $counts {
    if {[info exists sm($cell)]} { incr covered [expr {$n * $sm($cell)}] } else { lappend unknown $cell }
  }
  set diff [expr {$covered - $free}]
  set ok [expr {abs($diff) <= $tol && [llength $unknown] == 0}]
  return [list $ok $covered $free $diff $unknown]
}
# remove_stdcell_fillers_with_violation -check_only true output -> number of fillers with violations, or "not parsed".
# Accepts a sentence that says there is no violation ("no filler ... violation") as 0, or a line that holds "filler" and
# "violation" and an integer (the first integer is taken). Text layout VERIFY (18.22 names the report file, not the text).
proc unpu_parse_filler_violations {text} {
  foreach l [split $text "\n"] {
    if {![regexp -nocase -- {filler} $l] || ![regexp -nocase -- {violation} $l]} continue
    if {[regexp -nocase -- {\m(no|0|zero)\M\s+(\S+\s+){0,4}violation|\mno\s+filler} $l]} { return 0 }
    set ints [unpu_ints_in $l]
    if {[llength $ints] > 0} { return [lindex $ints 0] }
  }
  return "not parsed"
}
# The hold rule of the filled block (decision of 2026-10-29, handoff 18.22 option A): violations = count or "unavailable",
# worst = worst hold slack in ns or "unavailable", tol = FILL_HOLD_TOLERANCE_NS (> 0), maxn = FILL_HOLD_MAX_ENDPOINTS.
#   0 violating endpoints                                  -> pass
#   1..maxn endpoints, worst slack numeric and >= -tol     -> accepted (a sub-picosecond residual; PrimeTime decides)
#   anything worse, more than maxn endpoints, or a count/slack that could not be read -> fail
# (the 2026-10-29 decision accepted ONE path; a widespread degradation must not hide behind a small worst slack)
proc unpu_fill_hold_decision {violations worst tol maxn} {
  if {$violations eq "unavailable" || ![string is integer -strict $violations]} { return fail }
  if {$violations == 0} { return pass }
  if {$worst eq "unavailable" || ![string is double -strict $worst]} { return fail }
  if {$violations <= $maxn && $worst >= -$tol} { return accepted }
  return fail
}
# ---- output-file checkers (task 046): pure Tcl, run on the files outputs.tcl wrote ------------------------------
# whole file as text (binary translation: no newline or encoding change), "" and an error text for a missing file
proc unpu_read_text {file} {
  if {[catch {set fh [open $file r]} m]} { return -code error "cannot open $file: $m" }
  fconfigure $fh -translation binary
  set d [read $fh]; close $fh
  return $d
}
# the first n bytes of a file (SPEF/SDF headers: the files are tens of MB)
proc unpu_read_head {file n} {
  if {[catch {set fh [open $file r]} m]} { return -code error "cannot open $file: $m" }
  fconfigure $fh -translation binary
  set d [read $fh $n]; close $fh
  return $d
}
# names of the modules DEFINED in a Verilog text, in order: lines that start (after blanks) with the word "module"
# (endmodule does not match; // comment lines are skipped). The name ends at a blank, "(", "#" or ";".
proc unpu_verilog_modules {text} {
  set out {}
  foreach l [split $text "\n"] {
    if {[regexp -- {^\s*module\s+(\\?[^\s(#;]+)} $l -> n]} { lappend out $n }
  }
  return $out
}
# the "Block Name: <name>" header comment of a netlist written by write_verilog (18.23), "" if there is none
proc unpu_verilog_block_name {text} {
  if {[regexp -nocase -- {Block Name:\s*(\S+)} $text -> n]} { return $n }
  return ""
}
# cell types instantiated in a netlist that are NOT modules defined in it (= library cells), sorted. An instance is a line that
# starts with <type> <name> ( ; declaration keywords are skipped. VERIFY against the real netlist (the layout is the usual one).
proc unpu_verilog_cell_types {text} {
  set mods [unpu_verilog_modules $text]
  array set ismod {}
  foreach m $mods { set ismod($m) 1 }
  set kw {module endmodule input output inout wire reg assign supply0 supply1 parameter localparam tri wand wor integer function endfunction task endtask always initial generate endgenerate defparam}
  array set iskw {}
  foreach k $kw { set iskw($k) 1 }
  array set seen {}
  foreach l [split $text "\n"] {
    if {[regexp -- {^\s*(\\?[A-Za-z_][^\s(#;]*)\s+(\\?[^\s(;]+)\s*\(} $l -> ty nm]} {
      if {[info exists iskw($ty)] || [info exists ismod($ty)]} continue
      set seen($ty) 1
    }
  }
  return [lsort [array names seen]]
}
# LEF text -> dict: macros (names of the lines "MACRO <name>"), size {w h} or "", pins (names of PIN entries of the macros, in
# order), rects (dict pin -> list of {layer llx lly urx ury}), use (dict pin -> USE word). OBS blocks are skipped.
proc unpu_parse_lef {text} {
  set macros {}; set size ""; set pins {}; set rects [dict create]; set use [dict create]
  set pin ""; set layer ""; set inobs 0
  foreach raw [split $text "\n"] {
    set l [string trim $raw]
    if {$l eq ""} continue
    if {[regexp -- {^MACRO\s+(\S+)} $l -> m]} { lappend macros $m; continue }
    if {[regexp -- {^SIZE\s+(\S+)\s+BY\s+(\S+)} $l -> w h]} { set size [list $w $h]; continue }
    if {[regexp -- {^OBS\M} $l]} { set inobs 1; set pin ""; continue }
    if {$inobs} { if {$l eq "END"} { set inobs 0 }; continue }
    if {[regexp -- {^PIN\s+(\S+)} $l -> p]} { set pin $p; lappend pins $p; dict set rects $p {}; set layer ""; continue }
    if {$pin ne ""} {
      if {[regexp -- "^END\\s+[string map {[ \\[ ] \\] . \\. * \\* + \\+ ? \\?} $pin]\\s*\$" $l]} { set pin ""; continue }
      if {[regexp -- {^USE\s+(\S+)} $l -> u]} { dict set use $pin $u; continue }
      if {[regexp -- {^LAYER\s+(\S+)} $l -> ly]} { set layer $ly; continue }
      if {[regexp -- {^RECT\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $l -> a b c d]} {
        dict lappend rects $pin [list $layer $a $b $c $d]
      }
    }
  }
  return [dict create macros $macros size $size pins $pins rects $rects use $use]
}
# rectangles of a pin on a layer from the dict of unpu_parse_lef: {{llx lly urx ury} ...}
proc unpu_lef_pin_rects {lef pin layer} {
  set out {}
  set r [dict get $lef rects]
  if {![dict exists $r $pin]} { return {} }
  foreach e [dict get $r $pin] { if {[lindex $e 0] eq $layer} { lappend out [lrange $e 1 4] } }
  return $out
}
# SPEF head: {ok magic design}; ok when the first non-blank line starts *SPEF and "*DESIGN" names the design
proc unpu_check_spef_head {head design} {
  set magic ""; set d ""
  foreach l [split $head "\n"] {
    set s [string trim $l]
    if {$s eq ""} continue
    if {$magic eq ""} { set magic $s }
    if {[regexp -- {^\*DESIGN\s+"?([^"\s]+)"?} $s -> n]} { set d $n; break }
  }
  return [list [expr {[string match {\*SPEF*} $magic] && $d eq $design}] $magic $d]
}
# SDF head: 1 when it holds (DELAYFILE and (DESIGN "<design>")
proc unpu_check_sdf_head {head design} {
  return [expr {[string first "(DELAYFILE" $head] >= 0 && [regexp -- "\\(DESIGN\\s+\"[string map {. \\.} $design]\"\\s*\\)" $head]}]
}
# SDC text -> {setup <ns or ""> hold <ns or "">, from the set_clock_uncertainty lines without -from/-to. A line with no -setup/-hold
# sets both. clocks <number of create_clock lines>. VERIFY the layout write_sdc prints.
proc unpu_parse_sdc {text} {
  set setup ""; set hold ""; set clocks 0
  foreach l [split $text "\n"] {
    set w [regexp -all -inline -- {\S+} $l]
    if {[llength $w] == 0} continue
    if {[lindex $w 0] eq "create_clock"} { incr clocks; continue }
    if {[lindex $w 0] ne "set_clock_uncertainty"} continue
    if {[lsearch -exact $w -from] >= 0 || [lsearch -exact $w -to] >= 0} continue
    set val ""
    foreach x [lrange $w 1 end] { if {[string is double -strict $x]} { set val $x; break } }
    if {$val eq ""} continue
    set hs [expr {[lsearch -exact $w -hold] >= 0}]; set ss [expr {[lsearch -exact $w -setup] >= 0}]
    if {$hs || (!$hs && !$ss)} { set hold $val }
    if {$ss || (!$hs && !$ss)} { set setup $val }
  }
  return [list setup $setup hold $hold clocks $clocks]
}
# GDSII real8 from 8 byte values (0..255): excess-64 base-16 exponent, 56-bit fraction
proc unpu_gds_real8 {b} {
  set b0 [lindex $b 0]
  set sign [expr {($b0 & 0x80) ? -1.0 : 1.0}]
  set e [expr {($b0 & 0x7f) - 64}]
  set m 0.0
  foreach x [lrange $b 1 7] { set m [expr {$m * 256.0 + $x}] }
  return [expr {$sign * $m / 72057594037927936.0 * pow(16.0, $e)}]
}
# GDSII stream scan (binary string). Returns a dict: ok (1 when the stream is well formed to its end), error (text), first
# (first record type byte pair "0002" for HEADER), records, units {db_in_user db_in_m} or "", strnames (STRNAME records, in order),
# snames (SNAME records: referenced structures), texts (STRING records: the text strings of TEXT elements), endlib (0|1).
# Padding with zero bytes after ENDLIB is accepted. Layer and datatype of the texts are NOT read here: they are for Calibre LVS.
proc unpu_gds_scan {data} {
  set n [string length $data]
  set pos 0; set rec 0; set first ""; set units ""; set err ""; set endlib 0
  set strnames {}; set snames {}; set texts {}
  while {$pos + 4 <= $n} {
    binary scan $data "@$pos Su cu cu" len rt dt
    if {$len == 0} {
      # zero padding after ENDLIB is legal; anything else is not
      if {$endlib && [string trim [string range $data $pos end] "\x00"] eq ""} { set pos $n; break }
      set err "record of length 0 at byte $pos"; break
    }
    if {$len < 4 || ($len % 2) != 0} { set err "bad record length $len at byte $pos"; break }
    if {$pos + $len > $n} { set err "record at byte $pos (length $len) runs past the end of the file"; break }
    incr rec
    if {$rec == 1} { set first [format %02x%02x $rt $dt] }
    switch -- $rt {
      3  { if {$len >= 20} { binary scan $data "@[expr {$pos+4}] cu8 cu8" a b; set units [list [unpu_gds_real8 $a] [unpu_gds_real8 $b]] } }
      4  { set endlib 1 }
      6  { lappend strnames [string trimright [string range $data [expr {$pos+4}] [expr {$pos+$len-1}]] "\x00"] }
      18 { lappend snames [string trimright [string range $data [expr {$pos+4}] [expr {$pos+$len-1}]] "\x00"] }
      25 { lappend texts [string trimright [string range $data [expr {$pos+4}] [expr {$pos+$len-1}]] "\x00"] }
    }
    incr pos $len
  }
  if {$err eq "" && $pos < $n} { set err "$pos of $n bytes read; trailing bytes after the last record" }
  if {$err eq "" && $rec == 0} { set err "no records" }
  return [dict create ok [expr {$err eq ""}] error $err first $first records $rec units $units strnames $strnames snames $snames texts $texts endlib $endlib]
}
# GDSII units check: UNITS holds {db size in user units, db size in metres}. With database units per user unit = want_dbu
# (write_gds -units): first ~ 1/want_dbu, second ~ 1e-6/want_dbu; the user unit in metres is second / first (1e-6 = 1 um). Returns {ok db_per_user db_m user_unit_m}.
# rel = relative tolerance (the reals are stored in base 16 and are not exact).
proc unpu_gds_units_check {units want_dbu rel} {
  if {[llength $units] != 2} { return [list 0 "" "" ""] }
  lassign $units a b
  set dbu [expr {1.0 / $a}]
  set user_m [expr {$b / $a}]
  set ok [expr {abs($dbu - $want_dbu) <= $rel * $want_dbu && abs($user_m - 1e-6) <= $rel * 1e-6}]
  return [list $ok $dbu $b $user_m]
}
# count of each name of a list among the text strings: {name count ...} in the order of names
proc unpu_gds_label_counts {texts names} {
  array set c {}
  foreach s $texts { if {[info exists c($s)]} { incr c($s) } else { set c($s) 1 } }
  set out {}
  foreach n $names { lappend out $n [expr {[info exists c($n)] ? $c($n) : 0}] }
  return $out
}
# names of {name count ...} whose count is 0
proc unpu_zero_counts {counts} {
  set out {}
  foreach {n c} $counts { if {$c == 0} { lappend out $n } }
  return $out
}
# the real names a write command added to a directory: files in `after` that are not in `before` or whose name matches a
# prefix, sorted. Both are lists of file tails.
proc unpu_new_files {before after prefix} {
  array set b {}
  foreach f $before { set b($f) 1 }
  set out {}
  foreach f $after { if {![info exists b($f)] && [string first $prefix $f] == 0} { lappend out $f } }
  return [lsort $out]
}
# ---- pin placement helpers (task 048): pure Tcl on pin records -----------------------------------------------------
# A pin record is {port edge coord width length layer llx lly urx ury}:
#   edge   right | top | left | bottom (the one die edge the box touches), corner (it touches two), none (it touches none)
#   coord  centre of the box ALONG the edge (y on the right/left edges, x on the top/bottom edges), um
#   width  extent ALONG the edge, length extent ACROSS the edge (into the die), um
# "touches the edge" = the box reaches the die boundary within the tolerance (urx >= die on the right edge, ury >= die on the top,
# llx <= 0 on the left, lly <= 0 on the bottom); a pin centred on the edge line also touches it. The die is square, 0..die.
proc unpu_box_edges {box die tol} {
  lassign $box llx lly urx ury
  set e {}
  if {$llx <= $tol} { lappend e left }
  if {$urx >= $die - $tol} { lappend e right }
  if {$lly <= $tol} { lappend e bottom }
  if {$ury >= $die - $tol} { lappend e top }
  return $e
}
proc unpu_pin_record {port box layer die tol} {
  lassign $box llx lly urx ury
  set es [unpu_box_edges $box $die $tol]
  set edge [expr {[llength $es] == 0 ? "none" : [llength $es] > 1 ? "corner" : [lindex $es 0]}]
  if {$edge eq "left" || $edge eq "right"} {
    set coord [expr {($lly + $ury) / 2.0}]; set w [expr {$ury - $lly}]; set l [expr {$urx - $llx}]
  } else {
    set coord [expr {($llx + $urx) / 2.0}]; set w [expr {$urx - $llx}]; set l [expr {$ury - $lly}]
  }
  return [list $port $edge [unpu_round4 $coord] [unpu_round4 $w] [unpu_round4 $l] $layer $llx $lly $urx $ury]
}
# the records whose port is in `ports`
proc unpu_pins_of {records ports} {
  array set want {}
  foreach p $ports { set want($p) 1 }
  set out {}
  foreach r $records { if {[info exists want([lindex $r 0])]} { lappend out $r } }
  return $out
}
# ports (names) matching one of the patterns; a pattern is a name, or a name with [*] for a bus bit: paddr[*] -> paddr[<digits>]
proc unpu_port_matches {name patterns} {
  foreach p $patterns {
    if {[string first {[*]} $p] >= 0} {
      set re "^[string map {. \\.} [string map [list {[*]} @@BIT@@] $p]]\$"
      set re [string map [list @@BIT@@ {\[[0-9]+\]}] $re]
      if {[regexp -- $re $name]} { return 1 }
    } elseif {$p eq $name} { return 1 }
  }
  return 0
}
proc unpu_split_ports {names patterns} {
  set in {}; set out {}
  foreach n $names { if {[unpu_port_matches $n $patterns]} { lappend in $n } else { lappend out $n } }
  return [list $in $out]
}
# {edge count ...} for the records, edges in the order right top left bottom corner none (only those with a count)
proc unpu_pin_edge_counts {records} {
  array set c {}
  foreach r $records { set e [lindex $r 1]; if {![info exists c($e)]} { set c($e) 0 }; incr c($e) }
  set out {}
  foreach e {right top left bottom corner none} { if {[info exists c($e)]} { lappend out $e $c($e) } }
  return $out
}
# the edge most pins of a group landed on ("" for an empty group)
proc unpu_pin_dominant_edge {records} {
  set best ""; set bn 0
  foreach {e n} [unpu_pin_edge_counts $records] { if {$n > $bn} { set best $e; set bn $n } }
  return $best
}
# records of a group that are NOT on `edge`
proc unpu_pins_off_edge {records edge} {
  set out {}
  foreach r $records { if {[lindex $r 1] ne $edge} { lappend out $r } }
  return $out
}
# gaps between neighbouring pins (centre to centre) on one edge: {n min max} or {n "" ""} with fewer than two pins
proc unpu_pin_gaps {records edge} {
  set cs {}
  foreach r $records { if {[lindex $r 1] eq $edge} { lappend cs [lindex $r 2] } }
  set cs [lsort -real $cs]
  if {[llength $cs] < 2} { return [list [llength $cs] "" ""] }
  set mn ""; set mx ""
  for {set i 1} {$i < [llength $cs]} {incr i} {
    set g [expr {[lindex $cs $i] - [lindex $cs $i-1]}]
    if {$mn eq "" || $g < $mn} { set mn $g }
    if {$mx eq "" || $g > $mx} { set mx $g }
  }
  return [list [llength $cs] $mn $mx]
}
# pairs of ports on the same edge whose centre distance is below `pitch - tol`: {{portA portB gap} ...}
proc unpu_pin_close_pairs {records pitch tol} {
  set out {}
  foreach edge {right top left bottom} {
    set rs {}
    foreach r $records { if {[lindex $r 1] eq $edge} { lappend rs $r } }
    set rs [lsort -real -index 2 $rs]
    for {set i 1} {$i < [llength $rs]} {incr i} {
      set a [lindex $rs $i-1]; set b [lindex $rs $i]
      set g [expr {[lindex $b 2] - [lindex $a 2]}]
      if {$g < $pitch - $tol} { lappend out [list [lindex $a 0] [lindex $b 0] $g] }
    }
  }
  return $out
}
# do two boxes {llx lly urx ury} overlap by more than tol in both directions?
proc unpu_boxes_overlap {a b tol} {
  lassign $a ax0 ay0 ax1 ay1
  lassign $b bx0 by0 bx1 by1
  return [expr {min($ax1,$bx1) - max($ax0,$bx0) > $tol && min($ay1,$by1) - max($ay0,$by0) > $tol}]
}
# pins that overlap each other (any edge): {{portA portB} ...}
proc unpu_pin_overlaps {records tol} {
  set out {}
  set n [llength $records]
  for {set i 0} {$i < $n} {incr i} {
    set a [lindex $records $i]
    for {set j [expr {$i+1}]} {$j < $n} {incr j} {
      set b [lindex $records $j]
      if {[unpu_boxes_overlap [lrange $a 6 9] [lrange $b 6 9] $tol]} { lappend out [list [lindex $a 0] [lindex $b 0]] }
    }
  }
  return $out
}
# signal pins that overlap a power terminal box: {{port net} ...}; powerboxes = {{net llx lly urx ury} ...}
proc unpu_pin_power_overlaps {records powerboxes tol} {
  set out {}
  foreach r $records {
    foreach pb $powerboxes {
      if {[unpu_boxes_overlap [lrange $r 6 9] [lrange $pb 1 4] $tol]} { lappend out [list [lindex $r 0] [lindex $pb 0]]; break }
    }
  }
  return $out
}
# pins within `keepout` of a corner along their edge (the extent of the box counts): {port ...}
proc unpu_pin_corner_pins {records die keepout} {
  set out {}
  foreach r $records {
    set e [lindex $r 1]
    if {$e eq "corner"} { lappend out [lindex $r 0]; continue }
    if {$e eq "none"} continue
    set c [lindex $r 2]; set hw [expr {[lindex $r 3] / 2.0}]
    if {$c - $hw < $keepout || $c + $hw > $die - $keepout} { lappend out [lindex $r 0] }
  }
  return $out
}
# pins whose width or length differs from the wanted ones: {{port width length} ...}
proc unpu_pin_bad_size {records width length tol} {
  set out {}
  foreach r $records {
    if {abs([lindex $r 3] - $width) > $tol || abs([lindex $r 4] - $length) > $tol} { lappend out [list [lindex $r 0] [lindex $r 3] [lindex $r 4]] }
  }
  return $out
}
# ports that have more than one record
proc unpu_pin_duplicates {records} {
  array set c {}
  foreach r $records { set p [lindex $r 0]; if {![info exists c($p)]} { set c($p) 0 }; incr c($p) }
  set out {}
  foreach p [lsort [array names c]] { if {$c($p) > 1} { lappend out $p } }
  return $out
}
# the text of the "wrong edge" diagnosis. rside/tside = the side numbers used for the right and the top group; redge/tedge = the edge
# most pins of each group landed on. The mapping learned from this run (a side number -> the edge it gave) is printed, and the
# numbers to try are suggested. Returns "" when both groups are where they should be.
proc unpu_pin_side_diagnosis {rside tside redge tedge} {
  if {$redge eq "right" && $tedge eq "top"} { return "" }
  set txt "the right (APB) group, side number $rside, landed on the $redge edge (expected right); the top (DMA) group, side number $tside, landed on the $tedge edge (expected top)."
  if {$redge eq "top" && $tedge eq "right"} {
    append txt " The groups are swapped: set UNPU_PIN_SIDE_RIGHT=$tside and UNPU_PIN_SIDE_TOP=$rside and run again."
  } else {
    append txt " What this run showed: side $rside = $redge edge, side $tside = $tedge edge. The side number of the right edge and of the top edge is unknown: try the numbers 1 to 4 that are not yet explained (UNPU_PIN_SIDE_RIGHT, UNPU_PIN_SIDE_TOP) and run again; the guess was clockwise from the left edge: 1 left, 2 top, 3 right, 4 bottom."
  }
  return $txt
}
# the order report: one line per pin "port edge coordinate layer", sorted by edge (right, top, left, bottom) and coordinate
proc unpu_pin_order_lines {records} {
  set out {}
  foreach e {right top left bottom corner none} {
    set rs {}
    foreach r $records { if {[lindex $r 1] eq $e} { lappend rs $r } }
    foreach r [lsort -real -index 2 $rs] { lappend out [format "%-22s %-7s %10.3f  %s" [lindex $r 0] [lindex $r 1] [lindex $r 2] [lindex $r 5]] }
  }
  return $out
}
# per-bus summary: for each bus (name[<bit>]) the bit numbers in coordinate order on each edge; scalars are listed with their position
proc unpu_pin_bus_summary {records} {
  array set bus {}
  set scalars {}
  foreach e {right top left bottom} {
    set rs {}
    foreach r $records { if {[lindex $r 1] eq $e} { lappend rs $r } }
    foreach r [lsort -real -index 2 $rs] {
      if {[regexp -- {^(.+)\[([0-9]+)\]$} [lindex $r 0] -> b bit]} { lappend bus($b,$e) $bit } else { lappend scalars "[lindex $r 0] [lindex $r 1] [format %.3f [lindex $r 2]]" }
    }
  }
  set out {}
  foreach k [lsort [array names bus]] { lassign [split $k ,] b e; lappend out "$b ($e): [join $bus($k) { }]" }
  foreach s $scalars { lappend out "scalar $s" }
  return $out
}
# ---- placement stage helpers (task 049) ---------------------------------------------------------------------------
# Power terminals of the block (shared by pin_place.tcl and placement.tcl): {names boxes}; a box is {net llx lly urx ury}.
# VERIFY (as power.tcl): get_terminals -of_objects <net>, get_attribute <terminal> bbox
proc unpu_power_terminals {} {
  global PG_NET_POWER PG_NET_GROUND
  set names {}; set boxes {}
  foreach n [list $PG_NET_POWER $PG_NET_GROUND] {
    foreach_in_collection t [get_terminals -quiet -of_objects [get_nets $n]] {
      lappend names [get_object_name $t]
      set e [unpu_box_entry $n [get_attribute $t bbox]]
      if {$e ne ""} { lappend boxes $e }
    }
  }
  return [list $names $boxes]
}
# place_opt -list_only text: {found missing} of the expected stage names; found = the expected names that appear as whole words,
# in the order of `expected`. The usage text of the tool lists them as "[ initial_place initial_drc initial_opto final_place final_opto ]".
proc unpu_stages_in_text {text expected} {
  set found {}; set missing {}
  foreach s $expected { if {[regexp "\\m$s\\M" $text]} { lappend found $s } else { lappend missing $s } }
  return [list $found $missing]
}
# half-perimeter of a list of points {x y ...} pairs given as boxes {llx lly urx ury}: the boxes' centres are the points.
# Returns the HPWL in um, or "unavailable" for an empty list.
proc unpu_hpwl_of_boxes {boxes} {
  if {[llength $boxes] == 0} { return unavailable }
  set xs {}; set ys {}
  foreach b $boxes { lassign $b x0 y0 x1 y1; lappend xs [expr {($x0+$x1)/2.0}]; lappend ys [expr {($y0+$y1)/2.0}] }
  set xs [lsort -real $xs]; set ys [lsort -real $ys]
  return [expr {([lindex $xs end] - [lindex $xs 0]) + ([lindex $ys end] - [lindex $ys 0])}]
}
# HPWL from a net bbox attribute text ("{llx lly} {urx ury}"): width + height, or "unavailable"
proc unpu_hpwl_of_bbox {text} {
  set b [unpu_parse_bbox $text]
  if {[llength $b] != 4} { return unavailable }
  return [expr {([lindex $b 2] - [lindex $b 0]) + ([lindex $b 3] - [lindex $b 1])}]
}
# Estimated antenna ratio of a single-layer run: 2 * HPWL * detour * weight / gate_area (the Calibre deck rule AN.MTL.1.MT is
# perimeter * 0.84 / gate area, handoff 18.27; the perimeter of a wire of length L is about 2L). "unavailable" without a positive
# gate area or a numeric HPWL.
proc unpu_antenna_estimate {hpwl detour weight gate_area} {
  if {![string is double -strict $hpwl] || ![string is double -strict $gate_area] || $gate_area <= 0} { return unavailable }
  return [expr {2.0 * $hpwl * $detour * $weight / $gate_area}]
}
# 1 when the estimate is a number above the limit, 0 when it is not, "unknown" when it is unavailable
proc unpu_antenna_flag {estimate limit} {
  if {![string is double -strict $estimate]} { return unknown }
  return [expr {$estimate > $limit ? 1 : 0}]
}
# port report rows {port net loads hpwl gate_area gate_source ratio flag method}: sorted by ratio, worst first, unavailable last
proc unpu_port_report_sort {rows} {
  set num {}; set na {}
  foreach r $rows { if {[string is double -strict [lindex $r 6]]} { lappend num $r } else { lappend na $r } }
  return [concat [lsort -real -decreasing -index 6 $num] [lsort -index 0 $na]]
}
# the CSV text of the rows (header + one line per row); fields are written as they are, ratios and lengths with 3 decimals
proc unpu_port_report_csv {rows} {
  set out [list "port,net,loads,hpwl_um,gate_area_um2,gate_area_source,estimated_ratio,flag,hpwl_method"]
  foreach r [unpu_port_report_sort $rows] {
    lassign $r port net loads hpwl gate src ratio flag method
    foreach v {hpwl gate ratio} { if {[string is double -strict [set $v]]} { set $v [format %.3f [set $v]] } }
    set fl [expr {$flag eq "1" ? "FLAG" : $flag eq "0" ? "ok" : "unknown"}]
    lappend out [join [list [string map {, _} $port] [string map {, _} $net] $loads $hpwl $gate $src $ratio $fl $method] ,]
  }
  return $out
}
# summary of the rows: {flagged longest_hpwl longest_port long_count unknown_count}; long = hpwl above `long_um`
proc unpu_port_report_summary {rows long_um} {
  set flagged 0; set lh -1; set lp ""; set long 0; set unk 0
  foreach r $rows {
    lassign $r port net loads hpwl gate src ratio flag method
    if {$flag eq "1"} { incr flagged }
    if {![string is double -strict $hpwl]} { incr unk; continue }
    if {$hpwl > $lh} { set lh $hpwl; set lp $port }
    if {$hpwl > $long_um} { incr long }
  }
  return [list $flagged [expr {$lh < 0 ? "n/a" : $lh}] $lp $long $unk]
}
# cts.tcl stage rule: the guards of each mode as a list of "must_not_exist" blocks and "must_exist" blocks, and the block opened
proc unpu_cts_stage_plan {stage placed cts clkopt} {
  switch -- $stage {
    all  { return [list [list $cts $clkopt] {} $placed] }
    tree { return [list [list $cts] {} $placed] }
    hold { return [list [list $clkopt] [list $cts] $cts] }
    default { unpu_die "CTS stage '$stage' is not all, tree or hold" }
  }
}

# number of lines that start with Warning (case-insensitive) in the text of a check
proc unpu_warning_lines {text} { return [unpu_lines_matching $text {(?i)^\s*warning}] }
# first slack value in a report_timing text ("slack (MET)    0.82")
proc unpu_parse_slack {text} {
  if {[regexp {slack\s*\([A-Za-z ]+\)\s+(-?[0-9]+(?:\.[0-9]+)?)} $text -> v]} { return $v }
  return ""
}

# ---- parameters and stages (tool procedures: defined, not run) ---------------
proc unpu_load_params {} {
  global UNPU_PNR_DIR UNPU_PARAM_NAMES
  if {[info exists UNPU_PARAM_NAMES]} { return }
  uplevel #0 [list source [file join $UNPU_PNR_DIR params.tcl]]   ;# global scope, so the variables are global
  if {![info exists UNPU_PARAM_NAMES]} { unpu_die "params.tcl did not define UNPU_PARAM_NAMES" }
  global UNPU_WORK
  unpu_no_kit_write $UNPU_WORK/x   ;# the work directory must not be inside the kit
}

# unpu_stage_begin stage ?scope? ?files?
#   scope run (default): create RUN_DIR/{logs,out,rpt,calibre}; manifest in LOG_DIR
#   scope shared:        create UNPU_WORK and NDM_DIR only; manifest in NDM_DIR
# Loads params.tcl, makes the shell stop on error, writes the manifest of the stage.
proc unpu_stage_begin {stage {scope run} {files {}}} {
  global UNPU_WORK NDM_DIR RUN_DIR LOG_DIR OUT_DIR RPT_DIR CALIBRE_DIR UNPU_STAGE
  unpu_load_params
  set UNPU_STAGE $stage
  unpu_info "stage $stage begins (scope $scope)"
  # VERIFY (server): sh_continue_on_error exists in icc2_shell / icc2_lm_shell (it does in dc_shell,
  # syn/dc_run.tcl). If it does not, the failure is a Warning, not silence: die/exit still stop on
  # our own checks.
  if {[llength [info commands set_app_var]]} {
    if {[catch {set_app_var sh_continue_on_error false} msg]} {
      unpu_warn "could not set sh_continue_on_error false: $msg"
    }
  } else {
    unpu_warn "set_app_var is not available in this shell; sh_continue_on_error not set"
  }
  if {$scope eq "shared"} {
    unpu_ensure_dir $UNPU_WORK
    unpu_ensure_dir $NDM_DIR
    unpu_manifest $stage $files $NDM_DIR
  } elseif {$scope eq "run"} {
    unpu_ensure_dir $UNPU_WORK
    foreach d [list $RUN_DIR $LOG_DIR $OUT_DIR $RPT_DIR $CALIBRE_DIR] { unpu_ensure_dir $d }
    unpu_manifest $stage $files $LOG_DIR
  } else {
    unpu_die "unpu_stage_begin: scope '$scope' must be run or shared"
  }
}

# Exact block-name match: the current-block string may be "<lib>:<name>" or "<lib>:<name>.design"
# (or just "<name>"); it must NOT match any string that merely contains the name.
proc unpu_block_name_matches {cur name} {
  if {$cur eq "" || $name eq ""} { return 0 }
  if {[string match *.design $cur]} { set cur [string range $cur 0 end-7] }
  set tail [lindex [split $cur :] end]
  return [expr {$tail eq $name}]
}
# Name of the block that is current in the shell, "" if none.
# VERIFY (server): current_block returns the block object; its name via get_object_name.
proc unpu_current_block_name {} {
  if {[catch {current_block} b] || $b eq ""} { return "" }
  if {[catch {get_object_name $b} n]} { return "" }
  return $n
}
# Open the design library at lib_dir and the block lib_name:block.
# VERIFY (server): open_lib <path>, open_block <lib>:<block> (handoff 18.12 shows unpu_lib:unpu_top.design).
proc unpu_open_stage {lib_dir lib_name block} {
  unpu_need_file $lib_dir "design library"
  if {[catch {open_lib $lib_dir} msg]} { unpu_die "open_lib $lib_dir failed: $msg" }
  if {[catch {open_block ${lib_name}:${block}} msg]} { unpu_die "open_block ${lib_name}:${block} failed: $msg" }
  set cur [unpu_current_block_name]
  # the name may carry a label suffix (.design) or a library prefix
  if {![unpu_block_name_matches $cur $block]} {
    unpu_die "after open_block ${lib_name}:${block} the current block is '$cur' (expected exactly :${block} or :${block}.design)"
  }
  unpu_info "opened ${lib_name}:${block} (current block '$cur')"
}
# Save the current block under a new name and make the new block current. save_block -as keeps the
# old in-memory name; closing and reopening is what makes the new block current, and the old block
# on disk stays untouched (the pattern that worked in the first run).
# VERIFY (server): save_block -as, close_blocks -force, open_block with this argument form.
proc unpu_checkpoint {new_name} {
  global LIB_NAME
  if {[catch {save_block -as $new_name} msg]} { unpu_die "save_block -as $new_name failed: $msg" }
  if {[catch {close_blocks -force} msg]} { unpu_die "close_blocks -force failed: $msg" }
  if {[catch {open_block ${LIB_NAME}:${new_name}} msg]} { unpu_die "open_block ${LIB_NAME}:${new_name} failed: $msg" }
  set cur [unpu_current_block_name]
  if {![unpu_block_name_matches $cur $new_name]} {
    unpu_die "after checkpoint the current block is '$cur', expected exactly :${new_name} or :${new_name}.design"
  }
  # VERIFY (server): save_lib with the new block open persists the library (18.22: the reference
  # list did not persist until the library was saved)
  if {[catch {save_lib} msg]} { unpu_die "save_lib after checkpoint $new_name failed: $msg" }
  unpu_info "checkpoint $new_name saved and reopened (current block '$cur')"
}

# Run a tool command in global scope and keep its printed output, so messages that mention given
# words can be echoed as separate lines (the benign TECH-001/LEFR-064/FRAM-066 are printed, never
# suppressed). Returns the captured text. VERIFY (server): `redirect -variable` captures the messages
# of the command; if it does not, the messages are still in the shell log and the Warning says so.
set UNPU_CAP ""
set UNPU_CAP_OK 0
proc unpu_run_logged {cmd {words {}}} {
  set ::UNPU_CAP ""
  set ::UNPU_CAP_OK 0
  if {[llength [info commands redirect]]} {
    set ::UNPU_CAP_OK 1
    if {[catch {redirect -variable ::UNPU_CAP [list uplevel #0 $cmd]} msg]} {
      # print what the command had printed before it failed, then stop
      if {$::UNPU_CAP ne ""} { puts "Info: \[unpu\] output captured before the failure of '$cmd':"; puts -nonewline $::UNPU_CAP; if {![string match *\n $::UNPU_CAP]} { puts "" } }
      unpu_die "command failed: $cmd :: $msg"
    }
    if {$::UNPU_CAP ne ""} { puts -nonewline $::UNPU_CAP; if {![string match *\n $::UNPU_CAP]} { puts "" } }
    foreach line [split $::UNPU_CAP "\n"] {
      foreach w $words {
        if {[string first $w $line] >= 0} { unpu_info "MSG-MENTIONING-$w: [string trim $line]"; break }
      }
    }
  } else {
    unpu_warn "redirect is not available; running without message capture: $cmd"
    if {[catch {uplevel #0 $cmd} msg]} { unpu_die "command failed: $cmd :: $msg" }
  }
  return $::UNPU_CAP
}


# ---- command-usage probe: tool procedures (defined, not run); they only READ tool help --------------------
# Run one probe: build the Tcl script text with `script`, capture its output to `file` by redirect -file,
# classify it; returns a record {STATUS kind name detail}. Never raises.
proc unpu_probe_capture {kind name script file} {
  catch {file delete $file}
  # catch returns 1 on a Tcl error (err = message) and 0 on success (the result is not an error)
  if {![catch {redirect -file $file [list uplevel #0 $script]} err]} { set err "" }
  set text ""
  if {[file exists $file]} { set fh [open $file r]; set text [read $fh]; close $fh }
  return [list $text $err]
}
# commands: <cmd> -help, else help <cmd>
proc unpu_probe_command {cmd dir} {
  set file [file join $dir [unpu_probe_filename $cmd].txt]
  lassign [unpu_probe_capture command $cmd [list $cmd -help] $file] text err
  lassign [unpu_classify_help $text $err] st detail
  if {$st ne "FOUND"} {
    set first_st $st; set first_detail $detail
    lassign [unpu_probe_capture command $cmd [list help $cmd] $file] text2 err2
    lassign [unpu_classify_help $text2 $err2] st2 detail2
    if {$st2 eq "FOUND"} { set st FOUND; set detail "via help $cmd: $detail2"; set text $text2 } else {
      set detail "$first_st ($first_detail); help $cmd: $st2 ($detail2)"
    }
  }
  return [list [list $st command $cmd [expr {$st eq "FOUND" ? [file tail $file] : $detail}]] $text]
}
proc unpu_probe_wildcard {pat dir} {
  set file [file join $dir wild_[unpu_probe_filename $pat].txt]
  lassign [unpu_probe_capture wildcard $pat [list help $pat] $file] text err
  lassign [unpu_classify_help $text $err] st detail
  return [list [list $st wildcard $pat [expr {$st eq "FOUND" ? [file tail $file] : $detail}]] $text]
}
# app options: report_app_options <pattern>, else get_app_options <pattern> (VERIFY which exists)
proc unpu_probe_appopt {pat dir} {
  set file [file join $dir appopt_[unpu_probe_filename $pat].txt]
  lassign [unpu_probe_capture appopt $pat [list report_app_options $pat] $file] text err
  lassign [unpu_classify_help $text $err] st detail
  set via report_app_options
  if {$st ne "FOUND"} {
    lassign [unpu_probe_capture appopt $pat "puts \[get_app_options [list $pat]\]" $file] t3 e3
    lassign [unpu_classify_help $t3 $e3] st3 d3
    if {$st3 eq "FOUND"} { set st FOUND; set text $t3; set via get_app_options; set detail $d3 } else { set detail "report_app_options: $detail; get_app_options: $d3" }
  }
  return [list [list $st appopt $pat [expr {$st eq "FOUND" ? "[file tail $file] (via $via)" : $detail}]] $text]
}
proc unpu_pv_try {label script} {
  if {[catch {uplevel #0 $script} r]} { return "$label = ERROR: $r" }
  return "$label = $r"
}
# how the release string is exposed: every probe in a catch, results written to version.txt and returned
proc unpu_probe_version {dir} {
  set lines {}
  lappend lines [unpu_pv_try "sh_product_version (puts \$sh_product_version)" {set ::sh_product_version}]
  lappend lines [unpu_pv_try "sh_product_version (get_app_var)" {get_app_var sh_product_version}]
  set tmp [file join $dir version_printvar.tmp]
  if {[catch {redirect -file $tmp {printvar sh_product_version}} r]} { lappend lines "sh_product_version (printvar) = ERROR: $r" } else {
    set fh [open $tmp r]; lappend lines "sh_product_version (printvar) = [string trim [read $fh]]"; close $fh
  }
  catch {file delete $tmp}
  lappend lines "info patchlevel = [info patchlevel]"
  lappend lines "info nameofexecutable = [info nameofexecutable]"
  lappend lines "tcl_version = $::tcl_version"
  lappend lines [unpu_pv_try "sh_enable_page_mode (before)" {get_app_var sh_enable_page_mode}]
  lappend lines "unpu_tool_version (common.tcl, the current guess) = [unpu_tool_version]"
  return $lines
}
# the shared body of both probe scripts: writes <dir>/{version.txt,summary.txt,all_commands.txt,...}
# kinds: dict-like lists commands, wildcards, appopts (appopts may be empty)
proc unpu_probe_all {shell dir commands wildcards appopts} {
  unpu_ensure_dir $dir
  unpu_no_kit_write $dir/x
  # switch the pager off in this throwaway shell (VERIFY: sh_enable_page_mode exists)
  if {[catch {set_app_var sh_enable_page_mode false} m]} { unpu_warn "sh_enable_page_mode could not be set ($m); output goes to files, so no pager should be involved" }
  set vlines [unpu_probe_version $dir]
  set fh [open $dir/version.txt w]; foreach l $vlines { puts $fh $l; unpu_info "version probe: $l" }; close $fh
  set records {}
  set allc [open $dir/all_commands.txt w]
  foreach c $commands {
    lassign [unpu_probe_command $c $dir] rec text
    lappend records $rec
    puts $allc "===== $c ====="
    puts $allc [expr {[string trim $text] eq "" ? "(no output; [lindex $rec 0]: [lindex $rec 3])" : [string trimright $text "\n"]}]
    puts $allc ""
    if {[lindex $rec 0] ne "FOUND"} { unpu_warn "command $c: [lindex $rec 0] ([lindex $rec 3])" }
  }
  close $allc
  set allw [open $dir/all_wildcards.txt w]
  foreach w $wildcards {
    lassign [unpu_probe_wildcard $w $dir] rec text
    lappend records $rec
    puts $allw "===== help $w ====="
    puts $allw [expr {[string trim $text] eq "" ? "(no output; [lindex $rec 0]: [lindex $rec 3])" : [string trimright $text "\n"]}]
    puts $allw ""
    if {[lindex $rec 0] ne "FOUND"} { unpu_warn "wildcard $w: [lindex $rec 0] ([lindex $rec 3])" }
  }
  close $allw
  if {[llength $appopts] > 0} {
    set alla [open $dir/all_appopts.txt w]
    foreach a $appopts {
      lassign [unpu_probe_appopt $a $dir] rec text
      lappend records $rec
      puts $alla "===== report_app_options $a ====="
      puts $alla [expr {[string trim $text] eq "" ? "(no output; [lindex $rec 0]: [lindex $rec 3])" : [string trimright $text "\n"]}]
      puts $alla ""
      if {[lindex $rec 0] ne "FOUND"} { unpu_warn "app options $a: [lindex $rec 0] ([lindex $rec 3])" }
    }
    close $alla
  }
  lassign [unpu_probe_summary $records] lines nf nn ne total nfn
  set fh [open $dir/summary.txt w]
  puts $fh "shell: $shell"
  foreach l $lines { puts $fh $l }
  puts $fh "TOTAL $total  FOUND $nf  NOT_FOUND $nn  ERROR $ne"
  puts $fh "NOT_FOUND: $nfn"
  close $fh
  unpu_result help_probe $shell:probes $total
  unpu_result help_probe $shell:found $nf
  unpu_result help_probe $shell:not_found $nn
  unpu_result help_probe $shell:error $ne
  unpu_result help_probe $shell:not_found_names [join $nfn " "]
  unpu_result help_probe $shell:expected_probes [expr {[llength $commands] + [llength $wildcards] + [llength $appopts]}]
  unpu_result help_probe $shell:output_dir $dir
  return $total
}


# ---- shared by cts.tcl and route.tcl (moved from cts.tcl, task 044) ------------------------------------------
# VERIFY: current_scenario <name> (see design_setup.tcl)
proc unpu_scenario {name} { unpu_run_logged [list current_scenario $name] {} }
# a report command to $RPT_DIR/<prefix>_<name>.rpt (redirect -file), read back, printed, returned as text
proc unpu_report {prefix name cmd} {
  global RPT_DIR
  set f [file join $RPT_DIR ${prefix}_${name}.rpt]
  unpu_no_kit_write $f
  if {[catch {redirect -file $f [list uplevel #0 $cmd]} msg]} { unpu_die "report '$cmd' failed: $msg" }
  if {![file exists $f]} { unpu_die "report '$cmd' did not write $f" }
  set fh [open $f r]; set text [read $fh]; close $fh
  unpu_info "--- $cmd -> $f ---"
  puts -nonewline $text
  if {![string match *\n $text]} { puts "" }
  return $text
}
# report_timing in a scenario; returns the parsed paths {start end slack group}, or "unavailable" if the command failed
# or its text holds an Error line. VERIFY: report_timing -delay_type -slack_lesser_than -max_paths -nosplit
proc unpu_paths {prefix scenario delay name extra} {
  global RPT_DIR
  unpu_scenario $scenario
  set f [file join $RPT_DIR ${prefix}_${name}.rpt]
  if {[catch {redirect -file $f [list uplevel #0 [concat [list report_timing -delay_type $delay] $extra [list -nosplit]]]} msg]} {
    unpu_warn "report_timing ($scenario, $delay, $extra) failed: $msg"
    return unavailable
  }
  set fh [open $f r]; set text [read $fh]; close $fh
  if {[regexp -line -- {^\s*Error:} $text]} {
    unpu_warn "report_timing ($scenario, $delay, $extra) printed an Error: [lindex [regexp -line -inline -- {^\s*Error:.*$} $text] 0]"
    return unavailable
  }
  return [unpu_parse_report_timing_paths $text]
}
# worst slack and violating endpoints of a scenario: {worst total {group n ...} paths}; "unavailable" where it could not be read
proc unpu_timing_summary {prefix scenario delay tag} {
  global TIMING_MAX_PATHS
  set worst_paths [unpu_paths $prefix $scenario $delay ${tag}_worst [list -max_paths 1]]
  set viol_paths  [unpu_paths $prefix $scenario $delay ${tag}_violating [list -slack_lesser_than 0 -max_paths $TIMING_MAX_PATHS]]
  set worst unavailable
  if {$worst_paths ne "unavailable" && [llength $worst_paths] > 0} { set worst [lindex [lindex $worst_paths 0] 2] }
  if {$viol_paths eq "unavailable"} { return [list $worst unavailable {} {}] }
  set vg [unpu_violations_by_group $viol_paths]
  return [list $worst [lindex $vg 0] [lrange $vg 1 end] $viol_paths]
}
# max_transition / max_capacitance violation count from report_constraint, or "unavailable" (VERIFY the options)
proc unpu_constraint_count {prefix kind opt} {
  global RPT_DIR
  set f [file join $RPT_DIR ${prefix}_${kind}.rpt]
  if {[catch {redirect -file $f [list uplevel #0 [list report_constraint -all_violators $opt]]} msg]} {
    unpu_warn "report_constraint -all_violators $opt failed: $msg"
    return unavailable
  }
  set fh [open $f r]; set rtxt [read $fh]; close $fh
  return [unpu_parse_violations $rtxt]
}
