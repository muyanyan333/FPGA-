create_clock -name clk -period 20 [get_ports {clk}]
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {gesture_rx}]
