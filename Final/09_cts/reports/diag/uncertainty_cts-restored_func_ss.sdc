################################################################################
#
# Design name:  unpu_top_portbuf
#
# Created by icc2 write_sdc on Tue Nov 10 19:56:48 2026
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

set_clock_uncertainty -setup 1.5 [get_clocks {clk}]
set_clock_uncertainty -hold 0.5 [get_clocks {clk}]
