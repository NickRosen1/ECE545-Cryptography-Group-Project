# Use the same 100 MHz clock and port timing budget as the Stage 3 area comparison.
create_clock -name clk -period 10.000 [get_ports clk]
set_input_delay  -clock clk 0.0 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 0.0 [all_outputs]
