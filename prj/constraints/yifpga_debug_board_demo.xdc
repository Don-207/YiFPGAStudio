## YiFPGA Debug M5 board-demo constraints.
## Pin and IOSTANDARD values are mapped from the vendor pin.xdc.

create_clock -period 10.000 -name sys_clk_p -waveform {0.000 5.000} [get_ports clk_p]

## Vendor pin.xdc provides sys_clk_p on J23 and DIFF_HSTL_I_12 for both
## sys_clk_p/sys_clk_n. Vivado package data reports J23's DIFF_PAIR_PIN as J24.
set_property PACKAGE_PIN J23 [get_ports clk_p]
set_property PACKAGE_PIN J24 [get_ports clk_n]
set_property IOSTANDARD DIFF_HSTL_I_12 [get_ports clk_p]
set_property IOSTANDARD DIFF_HSTL_I_12 [get_ports clk_n]

set_property PACKAGE_PIN L23 [get_ports reset_n]
set_property IOSTANDARD LVCMOS18 [get_ports reset_n]

set_property PACKAGE_PIN N22 [get_ports demo_trigger]
set_property IOSTANDARD LVCMOS18 [get_ports demo_trigger]

set_property PACKAGE_PIN F15 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_tx]

set_property PACKAGE_PIN B16 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_rx]

set_property PACKAGE_PIN G26 [get_ports led0]
set_property IOSTANDARD LVCMOS18 [get_ports led0]

set_property PACKAGE_PIN G25 [get_ports led1]
set_property IOSTANDARD LVCMOS18 [get_ports led1]

create_debug_core u_ila_monitor ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_monitor]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_monitor]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_monitor]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_monitor]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_monitor]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_monitor]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_monitor]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_monitor]
set_property port_width 1 [get_debug_ports u_ila_monitor/clk]
connect_debug_port u_ila_monitor/clk [get_nets [list clk_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_monitor/probe0]
set_property port_width 64 [get_debug_ports u_ila_monitor/probe0]
connect_debug_port u_ila_monitor/probe0 [get_nets [list {u_debug_top/monitor_ila_probe[0]} {u_debug_top/monitor_ila_probe[1]} {u_debug_top/monitor_ila_probe[2]} {u_debug_top/monitor_ila_probe[3]} {u_debug_top/monitor_ila_probe[4]} {u_debug_top/monitor_ila_probe[5]} {u_debug_top/monitor_ila_probe[6]} {u_debug_top/monitor_ila_probe[7]} {u_debug_top/monitor_ila_probe[8]} {u_debug_top/monitor_ila_probe[9]} {u_debug_top/monitor_ila_probe[10]} {u_debug_top/monitor_ila_probe[11]} {u_debug_top/monitor_ila_probe[12]} {u_debug_top/monitor_ila_probe[13]} {u_debug_top/monitor_ila_probe[14]} {u_debug_top/monitor_ila_probe[15]} {u_debug_top/monitor_ila_probe[16]} {u_debug_top/monitor_ila_probe[17]} {u_debug_top/monitor_ila_probe[18]} {u_debug_top/monitor_ila_probe[19]} {u_debug_top/monitor_ila_probe[20]} {u_debug_top/monitor_ila_probe[21]} {u_debug_top/monitor_ila_probe[22]} {u_debug_top/monitor_ila_probe[23]} {u_debug_top/monitor_ila_probe[24]} {u_debug_top/monitor_ila_probe[25]} {u_debug_top/monitor_ila_probe[26]} {u_debug_top/monitor_ila_probe[27]} {u_debug_top/monitor_ila_probe[28]} {u_debug_top/monitor_ila_probe[29]} {u_debug_top/monitor_ila_probe[30]} {u_debug_top/monitor_ila_probe[31]} {u_debug_top/monitor_ila_probe[32]} {u_debug_top/monitor_ila_probe[33]} {u_debug_top/monitor_ila_probe[34]} {u_debug_top/monitor_ila_probe[35]} {u_debug_top/monitor_ila_probe[36]} {u_debug_top/monitor_ila_probe[37]} {u_debug_top/monitor_ila_probe[38]} {u_debug_top/monitor_ila_probe[39]} {u_debug_top/monitor_ila_probe[40]} {u_debug_top/monitor_ila_probe[41]} {u_debug_top/monitor_ila_probe[42]} {u_debug_top/monitor_ila_probe[43]} {u_debug_top/monitor_ila_probe[44]} {u_debug_top/monitor_ila_probe[45]} {u_debug_top/monitor_ila_probe[46]} {u_debug_top/monitor_ila_probe[47]} {u_debug_top/monitor_ila_probe[48]} {u_debug_top/monitor_ila_probe[49]} {u_debug_top/monitor_ila_probe[50]} {u_debug_top/monitor_ila_probe[51]} {u_debug_top/monitor_ila_probe[52]} {u_debug_top/monitor_ila_probe[53]} {u_debug_top/monitor_ila_probe[54]} {u_debug_top/monitor_ila_probe[55]} {u_debug_top/monitor_ila_probe[56]} {u_debug_top/monitor_ila_probe[57]} {u_debug_top/monitor_ila_probe[58]} {u_debug_top/monitor_ila_probe[59]} {u_debug_top/monitor_ila_probe[60]} {u_debug_top/monitor_ila_probe[61]} {u_debug_top/monitor_ila_probe[62]} {u_debug_top/monitor_ila_probe[63]}]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_BUFG]
