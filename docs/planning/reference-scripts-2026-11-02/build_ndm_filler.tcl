# ==============================================================================
# File: build_ndm_filler.tcl
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
set OUT_NDM_DIR    "/storage/EE5239G2/RFID_v2/pnr_icc2"
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