# Build a bitstream after adding the M23 Logic Analyzer RTL sources.
#
# Usage:
#   vivado -mode batch -source prj/scripts/build_yifpga_la_m23_bitstream.tcl
#
# Notes:
#   M23 delivers the reusable LA RTL core and adapter. The LA core is not wired
#   into yifpga_debug_board_demo until M25, so this script keeps the existing
#   board demo as the implementation top while making the LA sources visible to
#   the Vivado compile flow.

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug_dir [file join $repo_root rtl yifpga_debug]
set rtl_board_dir [file join $repo_root rtl board]
set xdc_file [file join $repo_root prj constraints yifpga_debug_board_demo.xdc]
set impl_dir [file join $repo_root prj YiFPGAStudio.runs impl_1]
set bit_file [file join $impl_dir yifpga_debug_board_demo_m23.bit]
set timing_file [file join $impl_dir yifpga_debug_board_demo_m23_timing_summary_routed.rpt]
set route_file [file join $impl_dir yifpga_debug_board_demo_m23_route_status.rpt]
set drc_file [file join $impl_dir yifpga_debug_board_demo_m23_drc_routed.rpt]
set util_file [file join $impl_dir yifpga_debug_board_demo_m23_utilization_routed.rpt]
set top_name yifpga_debug_board_demo
set part_name xcku5p-ffvb676-2-i

file mkdir $impl_dir

read_verilog [list \
    [file join $rtl_debug_dir yifpga_debug_pkg.vh] \
    [file join $rtl_debug_dir yifpga_trace_pkg.vh] \
    [file join $rtl_debug_dir yifpga_monitor_pkg.vh] \
    [file join $rtl_debug_dir yifpga_profiler_pkg.vh] \
    [file join $rtl_debug_dir yifpga_la_pkg.vh] \
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
    [file join $rtl_debug_dir yifpga_la_probe_pack.v] \
    [file join $rtl_debug_dir yifpga_la_trigger.v] \
    [file join $rtl_debug_dir yifpga_la_core.v] \
    [file join $rtl_debug_dir yifpga_la_adapter.v] \
    [file join $rtl_debug_dir yifpga_debug_core.v] \
    [file join $rtl_debug_dir yifpga_debug_top.v] \
    [file join $rtl_board_dir yifpga_debug_board_demo.v] \
]
read_xdc $xdc_file

puts "INFO: Synthesizing $top_name for $part_name"
synth_design -top $top_name -part $part_name

puts "INFO: Running implementation"
opt_design
place_design
route_design

puts "INFO: Writing implementation reports"
report_route_status -file $route_file
report_timing_summary -max_paths 10 -warn_on_violation -file $timing_file
report_drc -file $drc_file
report_utilization -hierarchical -file $util_file

puts "INFO: Writing bitstream to $bit_file"
write_bitstream -force $bit_file

if {![file exists $bit_file]} {
    error "Bitstream not generated: $bit_file"
}

puts "PASS: Built YiFPGA M23-compatible board demo bitstream: $bit_file"
puts "PASS: Wrote timing report: $timing_file"
puts "PASS: Wrote route report: $route_file"
puts "PASS: Wrote DRC report: $drc_file"
puts "PASS: Wrote utilization report: $util_file"
