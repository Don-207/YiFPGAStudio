# Rebuild the YiFPGA Debug board demo with an ILA on monitor RX path.
# Usage:
#   vivado -mode batch -source prj/scripts/build_yifpga_debug_board_demo_ila.tcl
#
# monitor_ila_probe bit map:
#   62 busy
#   61 monitor_msg_ready
#   60 monitor_msg_valid
#   59 monitor_resp_ready
#   58 monitor_resp_valid
#   57 monitor_req_ready
#   56 monitor_req_valid
#   55 monitor_unsupported_error
#   54 monitor_bad_len_error
#   53 monitor_checksum_error
#   52 monitor_uart_frame_error
#   51 monitor_byte_valid
#   50 uart_rx
#   49:47 monitor_parser_state
#   46:39 monitor_msg_type
#   38:31 monitor_resp_status
#   30:23 monitor_req_width
#   22:15 monitor_byte_data
#   14 monitor_req_write
#   13:6 monitor_req_seq[7:0]
#   5:0 buffer_used[5:0]

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug_dir [file join $repo_root rtl yifpga_debug]
set rtl_board_dir [file join $repo_root rtl board]
set xdc_file [file join $repo_root prj constraints yifpga_debug_board_demo.xdc]
set impl_dir [file join $repo_root prj YiFPGAStudio.runs impl_1]
set bit_file [file join $impl_dir yifpga_debug_board_demo_ila.bit]
set ltx_file [file join $impl_dir yifpga_debug_board_demo_ila.ltx]

file mkdir $impl_dir

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
read_xdc $xdc_file

synth_design -top yifpga_debug_board_demo -part xcku5p-ffvb676-2-i

set ila_clk [get_nets -hier -filter {NAME == u_debug_top/monitor_ila_clk}]
if {[llength $ila_clk] != 1} {
    puts "ERROR: Expected one monitor_ila_clk net, found [llength $ila_clk]."
    foreach net $ila_clk {
        puts "  $net"
    }
    error "monitor_ila_clk net mismatch"
}

set all_probe_nets [get_nets -hier -filter {NAME =~ *monitor_ila_probe*}]
set ila_probe {}
for {set bit 0} {$bit < 64} {incr bit} {
    set expected [format {u_debug_top/monitor_ila_probe[%d]} $bit]
    set matches {}
    foreach net $all_probe_nets {
        if {[get_property NAME $net] eq $expected} {
            lappend matches $net
        }
    }
    if {[llength $matches] != 1} {
        puts "ERROR: Expected one net named $expected, found [llength $matches]."
        puts "Available monitor_ila_probe nets:"
        foreach net $all_probe_nets {
            puts "  [get_property NAME $net]"
        }
        error "monitor_ila_probe bit $bit net mismatch"
    }
    lappend ila_probe [lindex $matches 0]
}

create_debug_core u_ila_monitor ila
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_monitor]
connect_debug_port u_ila_monitor/clk $ila_clk
set_property port_width 64 [get_debug_ports u_ila_monitor/probe0]
connect_debug_port u_ila_monitor/probe0 $ila_probe

opt_design
place_design
route_design
write_debug_probes -force $ltx_file
write_bitstream -force $bit_file

if {![file exists $bit_file]} {
    error "Bitstream not generated: $bit_file"
}
if {![file exists $ltx_file]} {
    error "Debug probes not generated: $ltx_file"
}

puts "PASS: Rebuilt YiFPGA Debug board demo ILA bitstream: $bit_file"
puts "PASS: Wrote ILA probes: $ltx_file"
