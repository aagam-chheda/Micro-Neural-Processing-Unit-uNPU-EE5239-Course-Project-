# 00_vars.tcl  -- shared paths and names, sourced by every stage script.
# Edit ONLY this file if a path on the server is different.

set KIT  /storage/PDK_iitg/SCLPDK_V3.0_KIT/scl180
set PNR  $KIT/digital_pnr_kit/snps/non_rh/4M1L        ;# ICC2 kit: tech file + TLUPlus
set SC   $KIT/stdcell/fs120/4M1IL                     ;# std-cell views (lef, liberty, gds)

set TF        $PNR/SCL_4LM.tf
set TLU_TYP   $PNR/SCL_TLUPLUS_4M1L_TYP.tlup
set TLU_MAP   $PNR/SCL_TLUPLUS_4M1L.map
set DB_SS     $SC/liberty/lib_flow_ss/tsl18fs120_scl_ss.db
set DB_FF     $SC/liberty/lib_flow_ff/tsl18fs120_scl_ff.db
set STD_LEF   $SC/lef/scl18fs120_std.lef

# Find these two once with:  find $KIT -iname "*.gds*" ; find $KIT -iname "*gds*map*"
set STD_GDS   CHANGE_ME_std_cells.gds
set GDS_MAP   CHANGE_ME_gds_layer.map

set NETLIST   syn/out/unpu_top_cn.dc.v
set SDC       constraints/pm_unpu_top.sdc
set TOP       unpu_top
set REF_NDM   pnr/scl_fs120.ndm
set DLIB      pnr/unpu_lib
set RPT       pnr/rpt
set OUT       pnr/out
file mkdir $RPT $OUT

# Die size = dummy LEF size (contract with the top-level team). Do not change.
set DIE_W 820.4
set DIE_H 823.2
set CORE_OFFSET 20

# Metal layer names, read from the tech file so nothing is guessed.
# Works only after a library is open (stage scripts call it after open_lib/create_lib).
proc get_metals {} {
    set ml [get_object_name [get_layers -filter "layer_type==interconnect"]]
    puts "INFO metal layers from tech file: $ml   (expect 4 names, bottom first)"
    return $ml
}
