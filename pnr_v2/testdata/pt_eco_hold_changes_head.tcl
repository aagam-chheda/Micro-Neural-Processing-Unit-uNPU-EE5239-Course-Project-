# RECONSTRUCTED test data (task 079): the real change file is on the server only. These lines are assembled from the excerpts quoted in docs/planning/tasks/079-apply-pt-eco-in-icc2.md
# (the three insert_buffer lines of the excerpt, the u_dma / u_csr pins of the .txt example). Replace with `head -20 pt_eco_hold_changes_icc2.tcl` of the real file when it is copied back.
current_instance
current_instance {u_apb}
insert_buffer [get_pins {U46/Z}] dl02d1 -new_net_names {net_PTECO_HOLD_NET1} -new_cell_names {U_PTECO_HOLD_BUF1}
current_instance
insert_buffer [get_pins {U61/Z}] dl01d2 -new_net_names {net_PTECO_HOLD_NET2} -new_cell_names {U_PTECO_HOLD_BUF2}
current_instance
current_instance {u_dma}
insert_buffer [get_pins {copt_h_inst_3080/Z}] dl02d1 -new_net_names {net_PTECO_HOLD_NET3} -new_cell_names {U_PTECO_HOLD_BUF3}
insert_buffer [get_pins {U_PTECO_HOLD_BUF3/Z}] dl01d1 -new_net_names {net_PTECO_HOLD_NET4} -new_cell_names {U_PTECO_HOLD_BUF4}
current_instance
current_instance {u_csr}
insert_buffer [get_pins {dest_c_reg_reg_2_/D}] buffd1 -new_net_names {net_PTECO_HOLD_NET5} -new_cell_names {U_PTECO_HOLD_BUF5}
insert_buffer [get_pins {U81/ZN}] dl01d1 -new_net_names {net_PTECO_HOLD_NET6} -new_cell_names {U_PTECO_HOLD_BUF6}
current_instance
