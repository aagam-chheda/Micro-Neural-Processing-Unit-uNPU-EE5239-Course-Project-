# =============================================================================
# help_probe_lm.tcl -- print the usage of the library-manager commands (icc2_lm_shell of U-2022.12-SP3)
#
# Purpose: as help_probe.tcl, for the shell that builds the NDM (ndm_file_gen.tcl): the usage of
# PROBE_COMMANDS_LM and the commands matching PROBE_WILDCARDS_LM (params.tcl), and how the release string is
# exposed. No application-option probe in this shell.
#
# Run (csh; the FULL path: the bare name finds Fusion Compiler V-2023.12-SP4, handoff 18.10):
#   source ~/cad_cshrc
#   source ~/synopsys_cshrc
#   setenv UNPU_REPO <your clone of the repo>
#   setenv UNPU_WORK <work directory>
#   setenv UNPU_RUN_TAG run1
#   mkdir -p $UNPU_WORK/$UNPU_RUN_TAG/logs
#   /home/Synopsys_tools/icc2/U-2022.12-SP3/bin/icc2_lm_shell -file $UNPU_REPO/pnr/help_probe_lm.tcl \
#       -output_log_file $UNPU_WORK/$UNPU_RUN_TAG/logs/help_probe_lm.log
#   (VERIFY -file / -output_log_file in icc2_lm_shell)
#
# Output, in $RPT_DIR/help_lm/: the same files as help_probe.tcl (version.txt, summary.txt, all_commands.txt,
#   all_wildcards.txt and one file per probe). Never: creates a workspace, reads a LEF or a library, changes any
#   state. Every probe runs; NOT_FOUND is a finding; the script exits 0.
# =============================================================================

set here [file dirname [file normalize [info script]]]
source [file join $here common.tcl]
unpu_load_params

if {[unpu_tool_version] eq ""} {
  unpu_warn "the tool version could not be read by the guess in common.tcl; continuing so that the probe can find out how it is exposed (see version.txt)"
} else {
  unpu_require_tool_version $ICC2_VERSION
}
unpu_stage_begin help_probe_lm run
set dir $RPT_DIR/help_lm
unpu_probe_all icc2_lm $dir $PROBE_COMMANDS_LM $PROBE_WILDCARDS_LM {}
unpu_info "done: see $dir/summary.txt; paste summary.txt, all_commands.txt, all_wildcards.txt and version.txt"
exit 0
