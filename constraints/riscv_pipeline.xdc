
#  Clock Constraints
create_clock -period 10.000 [get_ports clk]   ;# 100 MHz system clock
# Input/Output Delays (optional, if external interfaces exist)
# set_input_delay 2.0 -clock [get_clocks clk] [get_ports data_in]
# set_output_delay 2.0 -clock [get_clocks clk] [get_ports data_out]

# False Paths (debug signals are not timing-critical)
set_false_path -to   [get_ports -filter {NAME =~ "dbg_*"}]
set_false_path -from [get_ports -filter {NAME =~ "dbg_*"}]

# Multicycle Paths (only if branch resolves in MEM stage)

# set_multicycle_path 2 -from [get_registers -hier -filter {NAME =~ "*id_ex*"}] \
#                         -to   [get_registers -hier -filter {NAME =~ "*ex_mem*"}]

# Register Retiming & Optimization
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]
# set_property ALLOW_DUPLICATE_REG true [get_nets /uut/some_high_fanout_net]
