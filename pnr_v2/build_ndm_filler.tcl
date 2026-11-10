# ==============================================================================
# File: <RUN_DIR>/pnr_v2/build_ndm_filler.tcl   ;# 063 E1: new path
# Tool: Synopsys IC Compiler II Library Manager (icc2_lm_shell)
# Process: SCL 180nm (4M1IL) - Physical-Only Filler/Spacer Library
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Path Definitions
# ------------------------------------------------------------------------------
set KIT_DIR        "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180"

# Tech File & Interconnect Parasitics
set TECH_FILE      "${KIT_DIR}/digital_pnr_kit/snps/non_rh/4M1L/SCL_4LM.tf"
set TLUP_FILE      "${KIT_DIR}/digital_pnr_kit/snps/non_rh/4M1L/SCL_TLUPLUS_4M1L_TYP.tlup"
set TLUP_MAP       "${KIT_DIR}/digital_pnr_kit/snps/non_rh/4M1L/SCL_TLUPLUS_4M1L.map"

# Original Standard Cell Physical LEF
set CELL_LEF       "${KIT_DIR}/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"

# Output Configuration
set WORKSPACE_NAME "scl180_filler_workspace"
set UNPU_ERR ""   ;# 082: the run root is derived from where this script lives (pnr_v2/run_root.tcl), never typed: one clone = one run
if {[info script] eq "" || [catch {source [file join [file dirname [file normalize [info script]]] run_root.tcl]} UNPU_ERR]} { error "ERROR 082: cannot load run_root.tcl from the folder of this script ('[info script]'): [expr {$UNPU_ERR ne {} ? $UNPU_ERR : {the script was pasted into the shell: use source <file> or -f <file>}}]" }
set RUN_ROOT [unpu_run_init [info script]]   ;# 082: prints ">>> RUN ROOT: <path>" and a WARNING if the current directory is in another clone
set OUT_NDM_DIR    "${RUN_ROOT}/pnr_icc2"   ;# 063 E3: output directory
set OUT_NDM        "${OUT_NDM_DIR}/scl180_filler.ndm"

file mkdir $OUT_NDM_DIR

puts "\n=================================================================="
puts "  CREATING PHYSICAL-ONLY FILLER NDM LIBRARY FROM ORIGINAL LEF"
puts "==================================================================\n"

# ------------------------------------------------------------------------------
# 2. Create Workspace with Physical-Only Flow
# ------------------------------------------------------------------------------
create_workspace ${WORKSPACE_NAME} \
    -flow physical_only \
    -technology ${TECH_FILE}

# ------------------------------------------------------------------------------
# 3. Read Parasitic Interconnect Tech (TLUPlus)
# ------------------------------------------------------------------------------
puts "Reading TLUPlus models and Layer Map..."
read_parasitic_tech \
    -tlup ${TLUP_FILE} \
    -layermap ${TLUP_MAP} \
    -name typ_rc

# ------------------------------------------------------------------------------
# 4. Read Original Standard Cell LEF
# ------------------------------------------------------------------------------
puts "Reading Original LEF: ${CELL_LEF}"
read_lef ${CELL_LEF}

# ------------------------------------------------------------------------------
# 5. Validation & Library Build
# ------------------------------------------------------------------------------
puts "Validating workspace integrity..."
check_workspace

puts "Committing physical-only workspace to NDM: ${OUT_NDM}"
commit_workspace -output ${OUT_NDM} -force

puts "\n=================================================================="
puts "  FILLER NDM GENERATED SUCCESSFULLY: ${OUT_NDM}"
puts "==================================================================\n"

exit