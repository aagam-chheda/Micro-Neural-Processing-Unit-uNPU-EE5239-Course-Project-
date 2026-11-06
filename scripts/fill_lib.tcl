source scripts/00_vars.tcl
create_workspace -flow frame -technology $TF scl_fill
read_lef pnr/feedth.lef
check_workspace
commit_workspace -output pnr/scl_fill.ndm
exit
