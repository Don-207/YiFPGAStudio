# Rebuild the YiFPGA Debug board demo bitstream from the current RTL.
# Usage:
#   vivado -mode batch -source prj/scripts/build_yifpga_debug_board_demo.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug_dir [file join $repo_root rtl yifpga_debug]
set rtl_board_dir [file join $repo_root rtl board]
set xdc_file [file join $repo_root prj constraints yifpga_debug_board_demo.xdc]
set impl_dir [file join $repo_root prj YiFPGAStudio.runs impl_1]
set bit_file [file join $impl_dir yifpga_debug_board_demo.bit]

file mkdir $impl_dir

read_verilog [list \
    [file join $rtl_debug_dir yifpga_debug_pkg.vh] \
    [file join $rtl_debug_dir yifpga_trace_pkg.vh] \
    [file join $rtl_debug_dir yifpga_monitor_pkg.vh] \
    [file join $rtl_debug_dir yifpga_profiler_pkg.vh] \
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
    [file join $rtl_debug_dir yifpga_profiler_counter.v] \
    [file join $rtl_debug_dir yifpga_profiler_core.v] \
    [file join $rtl_debug_dir yifpga_profiler_adapter.v] \
    [file join $rtl_debug_dir yifpga_profiler_axis_probe.v] \
    [file join $rtl_debug_dir yifpga_profiler_fifo_probe.v] \
    [file join $rtl_debug_dir yifpga_profiler_frame_probe.v] \
    [file join $rtl_debug_dir yifpga_profiler_latency.v] \
    [file join $rtl_debug_dir yifpga_la_pkg.vh] \
    [file join $rtl_debug_dir yifpga_la_probe_pack.v] \
    [file join $rtl_debug_dir yifpga_la_trigger.v] \
    [file join $rtl_debug_dir yifpga_la_core.v] \
    [file join $rtl_debug_dir yifpga_la_adapter.v] \
    [file join $rtl_debug_dir yifpga_debug_core.v] \
    [file join $rtl_debug_dir yifpga_debug_top.v] \
    [file join $rtl_board_dir yifpga_debug_board_demo.v] \
]
read_verilog -sv [list \
    [file join $rtl_debug_dir yifpga_jtag_ring_buffer.sv] \
    [file join $rtl_debug_dir yifpga_jtag_mailbox.sv] \
    [file join $rtl_debug_dir yifpga_jtag_transport.sv] \
    [file join $rtl_debug_dir yifpga_jtag_user_dr.sv] \
    [file join $repo_root rtl vendor xilinx yifpga_jtag_bscan_xilinx.sv] \
    [file join $repo_root rtl vendor xilinx yifpga_jtag_transport_xilinx.sv] \
]
read_xdc $xdc_file

synth_design -top yifpga_debug_board_demo -part xcku5p-ffvb676-2-i
opt_design
place_design
route_design
write_bitstream -force $bit_file

if {![file exists $bit_file]} {
    error "Bitstream not generated: $bit_file"
}

puts "PASS: Rebuilt YiFPGA Debug board demo bitstream: $bit_file"
