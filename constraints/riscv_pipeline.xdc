# ============================================================================
# Clock Constraints
# ============================================================================
# Define primary system clock at 100 MHz (10 ns period)
create_clock -period 10.000 [get_ports clk]

# ============================================================================
# Input/Output Delays (if external interfaces exist)
# Adjust these if you connect to external devices
# ============================================================================
# Example (commented out):
# set_input_delay 2.0 -clock [get_clocks clk] [get_ports data_in]
# set_output_delay 2.0 -clock [get_clocks clk] [get_ports data_out]

# ============================================================================
# False Paths (debug signals are not timing-critical)
# Use -filter to select debug ports by name pattern
# ============================================================================
# Mark all debug ports (names starting with dbg_) as false paths
set_false_path -to [get_ports -filter {NAME =~ "dbg_*"}]
set_false_path -from [get_ports -filter {NAME =~ "dbg_*"}]

# If you prefer to list specific ports, use:
# set_false_path -to [get_ports dbg_if_id_PC dbg_if_id_instruction dbg_stall dbg_flush]

# ============================================================================
# Multicycle Paths
# ============================================================================
# NOTE: Set multicycle paths only if your RTL actually requires them.
# In the provided RTL branch resolves in EX stage. If branch resolves in EX,
# you typically do NOT need a 2-cycle multicycle path for id_ex -> ex_mem.
# If you intentionally resolve branch in MEM, set 2 cycles and reference registers.

# Example: If branch resolves in MEM and you want to allow 2 cycles between
# ID/EX registers and EX/MEM registers, use get_registers with a name filter:
# (Adjust the NAME filters to match the synthesized register names in your design.)
# set_multicycle_path 2 -from [get_registers -hierarchical -filter {NAME =~ "*id_ex*"}] \
#                         -to   [get_registers -hierarchical -filter {NAME =~ "*ex_mem*"}]

# For the current EX-stage branch resolution (recommended), remove the above.
# If you still want to explicitly set a 1-cycle path (default), you can omit set_multicycle_path.

# ============================================================================
# Register Retiming & Optimization
# ============================================================================
# Enable Vivado retiming to balance registers automatically
set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true [get_runs synth_1]

# Optional: allow register duplication for specific high-fanout nets only.
# Example (apply to a named net only):
# set_property ALLOW_DUPLICATE_REG true [get_nets /uut/some_high_fanout_net]

# ============================================================================
# Notes and guidance
# ============================================================================
# 1) If you change where branch is resolved (EX vs MEM), update multicycle paths accordingly.
# 2) Use -filter patterns that match actual port/register names in the implemented netlist.
# 3) Keep debug ports false-pathed to avoid timing pressure from non-critical outputs.
# 4) If you need help mapping synthesized register names for multicycle paths, run
#    synthesis once and inspect the implemented netlist/register names, then update filters.
