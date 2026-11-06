set KIT /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180
set SC  $KIT/stdcell/fs120/4M1IL
set TF  $KIT/digital_pnr_kit/snps/non_rh/4M1L/SCL_4LM.tf

create_workspace -flow normal -technology $TF scl_fs120
read_db [list $SC/liberty/lib_flow_ss/tsl18fs120_scl_ss.db \
              $SC/liberty/lib_flow_ff/tsl18fs120_scl_ff.db]
read_lef $SC/lef/scl18fs120_std.lef
check_workspace
commit_workspace -output pnr/scl_fs120.ndm
exit
