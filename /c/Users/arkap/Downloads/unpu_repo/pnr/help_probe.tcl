# =============================================================================
# help_probe.tcl -- print the usage of the commands the back-end flow uses (icc2_shell)
#
# Purpose: the scripts so far carry VERIFY comments for commands and options that the handoff does not show.
# This probe asks the tool itself: for every command of PROBE_COMMANDS_ICC2 it captures `<cmd> -help` (else
# `help <cmd>`); for every pattern of PROBE_WILDCARDS_ICC2 it captures `help <pattern>` (the commands whose name
# matches); for every pattern of PROBE_APPOPT_PATTERNS_ICC2 it captures `report_app_options <pattern>` (else
# `get_app_options`). It also records how the release string is exposed. Lists: pnr/params.tcl.
#
# Run (csh):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>        # default in pnr/params.tcl
#   setenv UNPU_RUN_TAG run1
#   mkdir -p $UNPU_WORK/$UNPU_RUN_TAG/logs
#   icc2_shell -file $UNPU_REPO/pnr/help_probe.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/help_probe.log
#   (-file / -output_log_file: confirmed on the server, VERIFY_STATUS.md)
#
# Output, in $RPT_DIR/help/: version.txt, summary.txt (one line per probe: STATUS kind name file-or-message, then
#   the totals), all_commands.txt (every command's text, banner "===== <cmd> =====" before each),
#   all_wildcards.txt and all_appopts.txt (the same for the other two kinds; extras beyond the task text), and one
#   file per probe: <cmd>.txt, wild_<pattern>.txt (* written as X), appopt_<pattern>.txt.
# Never: opens a library or a block, reads a design, changes any state of the design (it sets one session
#   variable, sh_enable_page_mode false, in this throwaway shell). Every probe runs; a missing command is the
#   finding, not an error: the script prints a Warning for each NOT_FOUND and exits 0.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

# the release check: if the version cannot be read (that is one of the questions of this probe) it is a
# Warning, not a stop; a version that is readable but wrong still stops the script
if {[unpu_tool_version] eq ""} {
  unpu_warn "the tool version could not be read by the guess in common.tcl; continuing so that the probe can find out how it is exposed (see version.txt)"
} else {
  unpu_require_tool_version $ICC2_VERSION
}
unpu_stage_begin help_probe run
set dir $RPT_DIR/help
unpu_probe_all icc2 $dir $PROBE_COMMANDS_ICC2 $PROBE_WILDCARDS_ICC2 $PROBE_APPOPT_PATTERNS_ICC2
unpu_info "done: see $dir/summary.txt; paste summary.txt, all_commands.txt, all_wildcards.txt, all_appopts.txt and version.txt"
exit 0
