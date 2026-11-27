# Out-of-context core constraint: 100 MHz clock only.
# The core's ports connect to other on-chip logic (the LWC wrapper), so their
# timing is checked at that level (build.tcl ... wrapper). The previous
# core_area.xdc forced zero input/output delays, which produced false hold
# violations (-0.379 ns) on paths straight from input ports to registers.
create_clock -name clk -period 10.000 [get_ports clk]
