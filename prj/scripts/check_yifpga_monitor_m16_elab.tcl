# Lightweight M16 Monitor board demo elaboration check.
# Usage:
#   vivado -mode batch -source prj/scripts/check_yifpga_monitor_m16_elab.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug_dir [file join $repo_root rtl yifpga_debug]
set rtl_board_dir [file join $repo_root rtl board]
set constraints_dir [file join $repo_root prj constraints]

cd $repo_root
read_verilog [list \
    [file join $rtl_debug_dir yifpga_debug_pkg.vh] \
    [file join $rtl_debug_dir yifpga_trace_pkg.vh] \
    [file join $rtl_debug_dir yifpga_monitor_pkg.vh] \
    [file join $rtl_debug_dir yifpga_debug_timestamp.v] \
    [file join $rtl_debug_dir yifpga_debug_ring_buffer.v] \
    [file join $rtl_debug_dir yifpga_debug_packetizer.v] \
    [file join $rtl_debug_dir yifpga_debug_uart_tx.v] \
    [file join $rtl_debug_dir yifpga_debug_uart_rx.v] \
    [file join $rtl_debug_dir yifpga_debug_command_parser.v] \
    [file join $rtl_debug_dir yifpga_trace_adapter.v] \
    [file join $rtl_debug_dir yifpga_trace_dma_probe.v] \
    [file join $rtl_debug_dir yifpga_trace_frame_probe.v] \
    [file join $rtl_debug_dir yifpga_trace_fifo_probe.v] \
    [file join $rtl_debug_dir yifpga_trace_irq_probe.v] \
    [file join $rtl_debug_dir yifpga_monitor_reg_bank.v] \
    [file join $rtl_debug_dir yifpga_monitor_core.v] \
    [file join $rtl_debug_dir yifpga_monitor_adapter.v] \
    [file join $rtl_debug_dir yifpga_debug_core.v] \
    [file join $rtl_debug_dir yifpga_debug_top.v] \
    [file join $rtl_board_dir yifpga_debug_board_demo.v] \
]
read_xdc [file join $constraints_dir yifpga_debug_board_demo.xdc]

synth_design -rtl -name yifpga_monitor_m16_rtl -top yifpga_debug_board_demo -part xcku5p-ffvb676-2-i

puts "PASS: YiFPGA Monitor M16 board demo Vivado RTL elaboration completed"
