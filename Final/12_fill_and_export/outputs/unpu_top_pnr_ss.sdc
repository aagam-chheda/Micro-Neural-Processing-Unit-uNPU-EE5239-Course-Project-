################################################################################
#
# Design name:  unpu_top_filled
#
# Created by icc2 write_sdc on Wed Nov 11 03:49:20 2026
#
################################################################################

set sdc_version 2.1
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current uA

################################################################################
#
# Units
# time_unit               : 1e-09
# resistance_unit         : 1000
# capacitive_load_unit    : 1e-12
# voltage_unit            : 1
# current_unit            : 1e-06
# power_unit              : 1e-12
################################################################################


# Mode: mode_func
# Corner: corner_ss
# Scenario: func_ss

# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 318; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/pnr_v2/placement.tcl, line \
#   77; /storage/EE5239G1/aagams_workspace2/unpu_run3/pnr_v2/cts.tcl, line 200
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
set_propagated_clock [get_clocks {clk}]
set_load -pin_load 0.2 [get_ports {rst_n}]
set_load -pin_load 0.2 [get_ports {paddr[31]}]
set_load -pin_load 0.2 [get_ports {paddr[30]}]
set_load -pin_load 0.2 [get_ports {paddr[29]}]
set_load -pin_load 0.2 [get_ports {paddr[28]}]
set_load -pin_load 0.2 [get_ports {paddr[27]}]
set_load -pin_load 0.2 [get_ports {paddr[26]}]
set_load -pin_load 0.2 [get_ports {paddr[25]}]
set_load -pin_load 0.2 [get_ports {paddr[24]}]
set_load -pin_load 0.2 [get_ports {paddr[23]}]
set_load -pin_load 0.2 [get_ports {paddr[22]}]
set_load -pin_load 0.2 [get_ports {paddr[21]}]
set_load -pin_load 0.2 [get_ports {paddr[20]}]
set_load -pin_load 0.2 [get_ports {paddr[19]}]
set_load -pin_load 0.2 [get_ports {paddr[18]}]
set_load -pin_load 0.2 [get_ports {paddr[17]}]
set_load -pin_load 0.2 [get_ports {paddr[16]}]
set_load -pin_load 0.2 [get_ports {paddr[15]}]
set_load -pin_load 0.2 [get_ports {paddr[14]}]
set_load -pin_load 0.2 [get_ports {paddr[13]}]
set_load -pin_load 0.2 [get_ports {paddr[12]}]
set_load -pin_load 0.2 [get_ports {paddr[11]}]
set_load -pin_load 0.2 [get_ports {paddr[10]}]
set_load -pin_load 0.2 [get_ports {paddr[9]}]
set_load -pin_load 0.2 [get_ports {paddr[8]}]
set_load -pin_load 0.2 [get_ports {paddr[7]}]
set_load -pin_load 0.2 [get_ports {paddr[6]}]
set_load -pin_load 0.2 [get_ports {paddr[5]}]
set_load -pin_load 0.2 [get_ports {paddr[4]}]
set_load -pin_load 0.2 [get_ports {paddr[3]}]
set_load -pin_load 0.2 [get_ports {paddr[2]}]
set_load -pin_load 0.2 [get_ports {paddr[1]}]
set_load -pin_load 0.2 [get_ports {paddr[0]}]
set_load -pin_load 0.2 [get_ports {pwdata[31]}]
set_load -pin_load 0.2 [get_ports {pwdata[30]}]
set_load -pin_load 0.2 [get_ports {pwdata[29]}]
set_load -pin_load 0.2 [get_ports {pwdata[28]}]
set_load -pin_load 0.2 [get_ports {pwdata[27]}]
set_load -pin_load 0.2 [get_ports {pwdata[26]}]
set_load -pin_load 0.2 [get_ports {pwdata[25]}]
set_load -pin_load 0.2 [get_ports {pwdata[24]}]
set_load -pin_load 0.2 [get_ports {pwdata[23]}]
set_load -pin_load 0.2 [get_ports {pwdata[22]}]
set_load -pin_load 0.2 [get_ports {pwdata[21]}]
set_load -pin_load 0.2 [get_ports {pwdata[20]}]
set_load -pin_load 0.2 [get_ports {pwdata[19]}]
set_load -pin_load 0.2 [get_ports {pwdata[18]}]
set_load -pin_load 0.2 [get_ports {pwdata[17]}]
set_load -pin_load 0.2 [get_ports {pwdata[16]}]
set_load -pin_load 0.2 [get_ports {pwdata[15]}]
set_load -pin_load 0.2 [get_ports {pwdata[14]}]
set_load -pin_load 0.2 [get_ports {pwdata[13]}]
set_load -pin_load 0.2 [get_ports {pwdata[12]}]
set_load -pin_load 0.2 [get_ports {pwdata[11]}]
set_load -pin_load 0.2 [get_ports {pwdata[10]}]
set_load -pin_load 0.2 [get_ports {pwdata[9]}]
set_load -pin_load 0.2 [get_ports {pwdata[8]}]
set_load -pin_load 0.2 [get_ports {pwdata[7]}]
set_load -pin_load 0.2 [get_ports {pwdata[6]}]
set_load -pin_load 0.2 [get_ports {pwdata[5]}]
set_load -pin_load 0.2 [get_ports {pwdata[4]}]
set_load -pin_load 0.2 [get_ports {pwdata[3]}]
set_load -pin_load 0.2 [get_ports {pwdata[2]}]
set_load -pin_load 0.2 [get_ports {pwdata[1]}]
set_load -pin_load 0.2 [get_ports {pwdata[0]}]
set_load -pin_load 0.2 [get_ports {pwrite}]
set_load -pin_load 0.2 [get_ports {psel}]
set_load -pin_load 0.2 [get_ports {penable}]
set_load -pin_load 1 [get_ports {prdata[31]}]
set_load -pin_load 1 [get_ports {prdata[30]}]
set_load -pin_load 1 [get_ports {prdata[29]}]
set_load -pin_load 1 [get_ports {prdata[28]}]
set_load -pin_load 1 [get_ports {prdata[27]}]
set_load -pin_load 1 [get_ports {prdata[26]}]
set_load -pin_load 1 [get_ports {prdata[25]}]
set_load -pin_load 1 [get_ports {prdata[24]}]
set_load -pin_load 1 [get_ports {prdata[23]}]
set_load -pin_load 1 [get_ports {prdata[22]}]
set_load -pin_load 1 [get_ports {prdata[21]}]
set_load -pin_load 1 [get_ports {prdata[20]}]
set_load -pin_load 1 [get_ports {prdata[19]}]
set_load -pin_load 1 [get_ports {prdata[18]}]
set_load -pin_load 1 [get_ports {prdata[17]}]
set_load -pin_load 1 [get_ports {prdata[16]}]
set_load -pin_load 1 [get_ports {prdata[15]}]
set_load -pin_load 1 [get_ports {prdata[14]}]
set_load -pin_load 1 [get_ports {prdata[13]}]
set_load -pin_load 1 [get_ports {prdata[12]}]
set_load -pin_load 1 [get_ports {prdata[11]}]
set_load -pin_load 1 [get_ports {prdata[10]}]
set_load -pin_load 1 [get_ports {prdata[9]}]
set_load -pin_load 1 [get_ports {prdata[8]}]
set_load -pin_load 1 [get_ports {prdata[7]}]
set_load -pin_load 1 [get_ports {prdata[6]}]
set_load -pin_load 1 [get_ports {prdata[5]}]
set_load -pin_load 1 [get_ports {prdata[4]}]
set_load -pin_load 1 [get_ports {prdata[3]}]
set_load -pin_load 1 [get_ports {prdata[2]}]
set_load -pin_load 1 [get_ports {prdata[1]}]
set_load -pin_load 1 [get_ports {prdata[0]}]
set_load -pin_load 1 [get_ports {pready}]
set_load -pin_load 1 [get_ports {dma_addr[31]}]
set_load -pin_load 1 [get_ports {dma_addr[30]}]
set_load -pin_load 1 [get_ports {dma_addr[29]}]
set_load -pin_load 1 [get_ports {dma_addr[28]}]
set_load -pin_load 1 [get_ports {dma_addr[27]}]
set_load -pin_load 1 [get_ports {dma_addr[26]}]
set_load -pin_load 1 [get_ports {dma_addr[25]}]
set_load -pin_load 1 [get_ports {dma_addr[24]}]
set_load -pin_load 1 [get_ports {dma_addr[23]}]
set_load -pin_load 1 [get_ports {dma_addr[22]}]
set_load -pin_load 1 [get_ports {dma_addr[21]}]
set_load -pin_load 1 [get_ports {dma_addr[20]}]
set_load -pin_load 1 [get_ports {dma_addr[19]}]
set_load -pin_load 1 [get_ports {dma_addr[18]}]
set_load -pin_load 1 [get_ports {dma_addr[17]}]
set_load -pin_load 1 [get_ports {dma_addr[16]}]
set_load -pin_load 1 [get_ports {dma_addr[15]}]
set_load -pin_load 1 [get_ports {dma_addr[14]}]
set_load -pin_load 1 [get_ports {dma_addr[13]}]
set_load -pin_load 1 [get_ports {dma_addr[12]}]
set_load -pin_load 1 [get_ports {dma_addr[11]}]
set_load -pin_load 1 [get_ports {dma_addr[10]}]
set_load -pin_load 1 [get_ports {dma_addr[9]}]
set_load -pin_load 1 [get_ports {dma_addr[8]}]
set_load -pin_load 1 [get_ports {dma_addr[7]}]
set_load -pin_load 1 [get_ports {dma_addr[6]}]
set_load -pin_load 1 [get_ports {dma_addr[5]}]
set_load -pin_load 1 [get_ports {dma_addr[4]}]
set_load -pin_load 1 [get_ports {dma_addr[3]}]
set_load -pin_load 1 [get_ports {dma_addr[2]}]
set_load -pin_load 1 [get_ports {dma_addr[1]}]
set_load -pin_load 1 [get_ports {dma_addr[0]}]
set_load -pin_load 1 [get_ports {dma_wdata[31]}]
set_load -pin_load 1 [get_ports {dma_wdata[30]}]
set_load -pin_load 1 [get_ports {dma_wdata[29]}]
set_load -pin_load 1 [get_ports {dma_wdata[28]}]
set_load -pin_load 1 [get_ports {dma_wdata[27]}]
set_load -pin_load 1 [get_ports {dma_wdata[26]}]
set_load -pin_load 1 [get_ports {dma_wdata[25]}]
set_load -pin_load 1 [get_ports {dma_wdata[24]}]
set_load -pin_load 1 [get_ports {dma_wdata[23]}]
set_load -pin_load 1 [get_ports {dma_wdata[22]}]
set_load -pin_load 1 [get_ports {dma_wdata[21]}]
set_load -pin_load 1 [get_ports {dma_wdata[20]}]
set_load -pin_load 1 [get_ports {dma_wdata[19]}]
set_load -pin_load 1 [get_ports {dma_wdata[18]}]
set_load -pin_load 1 [get_ports {dma_wdata[17]}]
set_load -pin_load 1 [get_ports {dma_wdata[16]}]
set_load -pin_load 1 [get_ports {dma_wdata[15]}]
set_load -pin_load 1 [get_ports {dma_wdata[14]}]
set_load -pin_load 1 [get_ports {dma_wdata[13]}]
set_load -pin_load 1 [get_ports {dma_wdata[12]}]
set_load -pin_load 1 [get_ports {dma_wdata[11]}]
set_load -pin_load 1 [get_ports {dma_wdata[10]}]
set_load -pin_load 1 [get_ports {dma_wdata[9]}]
set_load -pin_load 1 [get_ports {dma_wdata[8]}]
set_load -pin_load 1 [get_ports {dma_wdata[7]}]
set_load -pin_load 1 [get_ports {dma_wdata[6]}]
set_load -pin_load 1 [get_ports {dma_wdata[5]}]
set_load -pin_load 1 [get_ports {dma_wdata[4]}]
set_load -pin_load 1 [get_ports {dma_wdata[3]}]
set_load -pin_load 1 [get_ports {dma_wdata[2]}]
set_load -pin_load 1 [get_ports {dma_wdata[1]}]
set_load -pin_load 1 [get_ports {dma_wdata[0]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[31]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[30]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[29]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[28]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[27]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[26]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[25]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[24]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[23]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[22]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[21]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[20]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[19]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[18]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[17]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[16]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[15]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[14]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[13]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[12]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[11]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[10]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[9]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[8]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[7]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[6]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[5]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[4]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[3]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[2]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[1]}]
set_load -pin_load 0.2 [get_ports {dma_rdata[0]}]
set_load -pin_load 1 [get_ports {dma_wstrb[3]}]
set_load -pin_load 1 [get_ports {dma_wstrb[2]}]
set_load -pin_load 1 [get_ports {dma_wstrb[1]}]
set_load -pin_load 1 [get_ports {dma_wstrb[0]}]
set_load -pin_load 1 [get_ports {dma_valid}]
set_load -pin_load 0.2 [get_ports {dma_ready}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 9
set_operating_conditions -library tsl18fs120_scl_ss -analysis_type \
    on_chip_variation tsl18fs120_scl_ss
# Warning: Libcell power domain derates are skipped!

set_clock_uncertainty -setup 1.5 [get_clocks {clk}]
set_clock_uncertainty -hold 0.5 [get_clocks {clk}]
set_clock_transition 0.6 [get_clocks {clk}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 14
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {rst_n}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 15
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 16
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 17
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 18
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 19
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 20
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 21
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 22
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 23
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 24
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 25
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 26
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 27
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 28
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 29
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 30
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 31
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 32
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 33
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 34
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 35
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 36
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 37
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 38
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 39
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 40
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 41
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 42
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 43
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 44
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 45
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 46
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {paddr[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 47
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 48
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 49
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 50
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 51
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 52
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 53
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 54
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 55
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 56
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 57
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 58
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 59
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 60
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 61
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 62
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 63
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 64
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 65
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 66
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 67
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 68
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 69
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 70
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 71
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 72
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 73
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 74
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 75
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 76
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 77
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 78
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwdata[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 79
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {pwrite}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 80
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {psel}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 81
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {penable}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 82
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 83
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 84
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 85
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 86
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 87
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 88
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 89
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 90
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 91
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 92
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 93
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 94
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 95
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 96
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 97
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 98
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 99
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 100
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 101
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 102
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 103
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 104
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 105
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 106
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 107
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 108
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 109
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 110
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 111
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 112
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 113
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_rdata[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 114
set_driving_cell -lib_cell buffd1 -pin Z -library \
    tsl18fs120_scl_ss.db:tsl18fs120_scl_ss [get_ports {dma_ready}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 325
set_input_delay -clock [get_clocks {clk}] 0 [get_ports {clk}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 326; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 327
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {rst_n}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {rst_n}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 328; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 329
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[31]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 330; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 331
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[30]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 332; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 333
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[29]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 334; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 335
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[28]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 336; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 337
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[27]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 338; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 339
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[26]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 340; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 341
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[25]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 342; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 343
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[24]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 344; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 345
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[23]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 346; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 347
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[22]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 348; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 349
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[21]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 350; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 351
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[20]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 352; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 353
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[19]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 354; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 355
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[18]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 356; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 357
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[17]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 358; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 359
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[16]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 360; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 361
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[15]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 362; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 363
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[14]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 364; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 365
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[13]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 366; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 367
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[12]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 368; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 369
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[11]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 370; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 371
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[10]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 372; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 373
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[9]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 374; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 375
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[8]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 376; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 377
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[7]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 378; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 379
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[6]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 380; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 381
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[5]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 382; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 383
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[4]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 384; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 385
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[3]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 386; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 387
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[2]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 388; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 389
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[1]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 390; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 391
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {paddr[0]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {paddr[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 392; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 393
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[31]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 394; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 395
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[30]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 396; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 397
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[29]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 398; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 399
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[28]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 400; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 401
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[27]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 402; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 403
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[26]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 404; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 405
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[25]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 406; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 407
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[24]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 408; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 409
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[23]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 410; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 411
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[22]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 412; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 413
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[21]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 414; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 415
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[20]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 416; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 417
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[19]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 418; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 419
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[18]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 420; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 421
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[17]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 422; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 423
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[16]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 424; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 425
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[15]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 426; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 427
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[14]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 428; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 429
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[13]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 430; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 431
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[12]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 432; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 433
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[11]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 434; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 435
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[10]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 436; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 437
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[9]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 438; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 439
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[8]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 440; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 441
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[7]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 442; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 443
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[6]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 444; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 445
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[5]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 446; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 447
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[4]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 448; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 449
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[3]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 450; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 451
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[2]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 452; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 453
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[1]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 454; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 455
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwdata[0]}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwdata[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 456; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 457
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {pwrite}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {pwrite}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 458; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 459
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {psel}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {psel}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 460; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 461
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {penable}]
set_input_delay -clock [get_clocks {clk}] -max 7 [get_ports {penable}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 528; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 529
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[31]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 530; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 531
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[30]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 532; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 533
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[29]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 534; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 535
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[28]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 536; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 537
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[27]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 538; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 539
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[26]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 540; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 541
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[25]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 542; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 543
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[24]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 544; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 545
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[23]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 546; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 547
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[22]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 548; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 549
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[21]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 550; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 551
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[20]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 552; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 553
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[19]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 554; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 555
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[18]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 556; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 557
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[17]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 558; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 559
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[16]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 560; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 561
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[15]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 562; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 563
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[14]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 564; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 565
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[13]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 566; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 567
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[12]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 568; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 569
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[11]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 570; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 571
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[10]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 572; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 573
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[9]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 574; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 575
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[8]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 576; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 577
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[7]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 578; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 579
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[6]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 580; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 581
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[5]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 582; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 583
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[4]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 584; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 585
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[3]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 586; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 587
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[2]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 588; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 589
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[1]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 590; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 591
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {prdata[0]}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {prdata[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 592; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 593
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {pready}]
set_output_delay -clock [get_clocks {clk}] -max 7 [get_ports {pready}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 594; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 595
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[31]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 596; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 597
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[30]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 598; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 599
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[29]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 600; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 601
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[28]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 602; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 603
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[27]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 604; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 605
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[26]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 606; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 607
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[25]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 608; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 609
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[24]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 610; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 611
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[23]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 612; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 613
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[22]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 614; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 615
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[21]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 616; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 617
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[20]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 618; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 619
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[19]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 620; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 621
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[18]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 622; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 623
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[17]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 624; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 625
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[16]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 626; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 627
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[15]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 628; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 629
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[14]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 630; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 631
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[13]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 632; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 633
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[12]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 634; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 635
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[11]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 636; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 637
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[10]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 638; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 639
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[9]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 640; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 641
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[8]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 642; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 643
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[7]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 644; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 645
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[6]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 646; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 647
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[5]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 648; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 649
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[4]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 650; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 651
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[3]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 652; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 653
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[2]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 654; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 655
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[1]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 656; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 657
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_addr[0]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_addr[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 658; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 659
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[31]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 660; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 661
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[30]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 662; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 663
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[29]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 664; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 665
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[28]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 666; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 667
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[27]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 668; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 669
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[26]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 670; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 671
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[25]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 672; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 673
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[24]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 674; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 675
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[23]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 676; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 677
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[22]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 678; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 679
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[21]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 680; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 681
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[20]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 682; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 683
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[19]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 684; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 685
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[18]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 686; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 687
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[17]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 688; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 689
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[16]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 690; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 691
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[15]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 692; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 693
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[14]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 694; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 695
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[13]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 696; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 697
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[12]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 698; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 699
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[11]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 700; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 701
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[10]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 702; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 703
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[9]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 704; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 705
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[8]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 706; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 707
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[7]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 708; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 709
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[6]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 710; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 711
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[5]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 712; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 713
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[4]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 714; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 715
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[3]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 716; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 717
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[2]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 718; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 719
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[1]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 720; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 721
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wdata[0]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wdata[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 462; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 463
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[31]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[31]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 464; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 465
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[30]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[30]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 466; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 467
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[29]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[29]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 468; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 469
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[28]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[28]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 470; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 471
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[27]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[27]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 472; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 473
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[26]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[26]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 474; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 475
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[25]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[25]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 476; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 477
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[24]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[24]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 478; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 479
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[23]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[23]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 480; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 481
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[22]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[22]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 482; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 483
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[21]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[21]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 484; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 485
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[20]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[20]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 486; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 487
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[19]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[19]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 488; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 489
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[18]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[18]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 490; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 491
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[17]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[17]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 492; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 493
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[16]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[16]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 494; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 495
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[15]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[15]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 496; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 497
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[14]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[14]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 498; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 499
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[13]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[13]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 500; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 501
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[12]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[12]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 502; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 503
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[11]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[11]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 504; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 505
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[10]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[10]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 506; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 507
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[9]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[9]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 508; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 509
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[8]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[8]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 510; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 511
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[7]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[7]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 512; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 513
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[6]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[6]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 514; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 515
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[5]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[5]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 516; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 517
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[4]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[4]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 518; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 519
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[3]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 520; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 521
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[2]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 522; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 523
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[1]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 524; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 525
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_rdata[0]}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_rdata[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 722; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 723
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wstrb[3]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wstrb[3]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 724; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 725
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wstrb[2]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wstrb[2]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 726; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 727
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wstrb[1]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wstrb[1]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 728; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 729
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_wstrb[0]}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_wstrb[0]}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 730; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 731
set_output_delay -clock [get_clocks {clk}] -min -0.5 [get_ports {dma_valid}]
set_output_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_valid}]
# /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 526; \
#   /storage/EE5239G1/aagams_workspace2/unpu_run3/syn/out/legacy/unpu_top_cn.sdc, \
#   line 527
set_input_delay -clock [get_clocks {clk}] -min 0 [get_ports {dma_ready}]
set_input_delay -clock [get_clocks {clk}] -max 8 [get_ports {dma_ready}]
set_max_transition 3 [current_design]
set_max_capacitance 2 [current_design]
