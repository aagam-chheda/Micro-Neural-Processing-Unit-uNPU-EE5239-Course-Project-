################################################################################
#
# Design name:  unpu_top_filled
#
# Created by icc2 write_sdc on Wed Nov 11 03:49:19 2026
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
# Corner: corner_ff
# Scenario: func_ff

set_propagated_clock [get_clocks {clk}]
