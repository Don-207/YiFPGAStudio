# Lightweight M13 UART RX and command parser elaboration check.
# Usage:
#   vivado -mode batch -source prj/scripts/check_yifpga_monitor_m13_elab.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug_dir [file join $repo_root rtl yifpga_debug]

cd $repo_root
read_verilog [list \
    [file join $rtl_debug_dir yifpga_debug_pkg.vh] \
    [file join $rtl_debug_dir yifpga_monitor_pkg.vh] \
    [file join $rtl_debug_dir yifpga_debug_uart_rx.v] \
    [file join $rtl_debug_dir yifpga_debug_command_parser.v] \
]

synth_design -rtl -name yifpga_monitor_m13_rtl -top yifpga_debug_command_parser -part xcku5p-ffvb676-2-i

puts "PASS: YiFPGA Monitor M13 UART RX command parser Vivado RTL elaboration completed"
