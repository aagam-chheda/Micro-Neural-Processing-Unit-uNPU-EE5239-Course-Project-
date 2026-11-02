# ==============================================================================
# File: /storage/EE5239G1/aagams_workspace2/unpu/pnr_v2/build_ndm_std.tcl   ;# 063 E1: new path
# Tool: Synopsys IC Compiler II Library Manager (icc2_lm_shell)
# Process: SCL 180nm (4M1IL) with Embedded TLUPlus (Standard Cells)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Path Definitions
# ------------------------------------------------------------------------------
set KIT_DIR        "/storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180"

# Tech File & Interconnect Parasitics
set TECH_FILE      "${KIT_DIR}/digital_pnr_kit/snps/non_rh/4M1L/SCL_4LM.tf"
set TLUP_FILE      "${KIT_DIR}/digital_pnr_kit/snps/non_rh/4M1L/SCL_TLUPLUS_4M1L_TYP.tlup"
set TLUP_MAP       "${KIT_DIR}/digital_pnr_kit/snps/non_rh/4M1L/SCL_TLUPLUS_4M1L.map"

# Standard Cell Physical LEF
set CELL_LEF       "${KIT_DIR}/stdcell/fs120/4M1IL/lef/scl18fs120_std.lef"

# Multi-Corner Timing DBs
set TIMING_DBS     [list \
    "${KIT_DIR}/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.db" \
    "${KIT_DIR}/stdcell/fs120/4M1IL/liberty/lib_flow_ff/tsl18fs120_scl_ff.db" \
]

# Output Configuration
set WORKSPACE_NAME "scl180_std_workspace"
set OUT_NDM_DIR    "/storage/EE5239G1/aagams_workspace2/unpu/pnr_icc2"   ;# 063 E3: output directory
set OUT_NDM        "${OUT_NDM_DIR}/scl180_std.ndm"

file mkdir $OUT_NDM_DIR

puts "\n=================================================================="
puts "  CREATING STANDARD NDM WITH TIMING, LEF, AND TLUPLUS PARASITICS"
puts "==================================================================\n"

# ------------------------------------------------------------------------------
# 2. Create Workspace
# ------------------------------------------------------------------------------
create_workspace ${WORKSPACE_NAME} \
    -flow normal \
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
# 4. Ingest Physical LEF & Timing DBs
# ------------------------------------------------------------------------------
puts "Reading Standard Cell LEF: ${CELL_LEF}"
read_lef ${CELL_LEF}

puts "Reading Multi-Corner Timing DBs: ${TIMING_DBS}"
read_db ${TIMING_DBS}

# ------------------------------------------------------------------------------
# 5. Validation & Library Build
# ------------------------------------------------------------------------------
puts "Validating workspace integrity..."
check_workspace

puts "Committing workspace to NDM: ${OUT_NDM}"
commit_workspace -output ${OUT_NDM} -force

puts "\n=================================================================="
puts "  STANDARD NDM GENERATED SUCCESSFULLY: ${OUT_NDM}"
puts "==================================================================\n"

exit