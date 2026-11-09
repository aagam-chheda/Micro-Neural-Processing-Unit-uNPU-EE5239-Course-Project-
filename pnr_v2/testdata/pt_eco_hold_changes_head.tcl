###############################################################################
# Change list, formatted for IC Compiler
#
#
#
###############################################################################
current_instance
current_instance {u_apb}
insert_buffer [get_pins {U46/Z}] dl02d1 -new_net_names {net_PTECO_HOLD_NET1} -new_cell_names {U_PTECO_HOLD_BUF1}
current_instance
insert_buffer [get_pins {U61/Z}] dl01d2 -new_net_names {net_PTECO_HOLD_NET2} -new_cell_names {U_PTECO_HOLD_BUF2}
current_instance
current_instance {u_apb}
insert_buffer [get_pins {U29/Z}] dl01d1 -new_net_names {net_PTECO_HOLD_NET3} -new_cell_names {U_PTECO_HOLD_BUF3}
current_instance
insert_buffer [get_ports {dma_rdata[14]}] dl01d1 -new_net_names {net_PTECO_HOLD_NET4} -new_cell_names {U_PTECO_HOLD_BUF4}
insert_buffer [get_ports {dma_rdata[22]}] dl01d1 -new_net_names {net_PTECO_HOLD_NET5} -new_cell_names {U_PTECO_HOLD_BUF5}
current_instance
current_instance {u_dma}
insert_buffer [get_pins {copt_h_inst_3077/Z}] dl02d1 -new_net_names {net_PTECO_HOLD_NET6} -new_cell_names {U_PTECO_HOLD_BUF6}
