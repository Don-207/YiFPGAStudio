set root_dir [file normalize [file join [file dirname [info script]] ../..]]
set part_name xcku5p-ffvb676-2-i

read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_transport_router.sv]
read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_ring_buffer.sv]
read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_mailbox.sv]
read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_transport.sv]
read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_user_dr.sv]
read_verilog -sv [file join $root_dir rtl/vendor/xilinx/yifpga_jtag_bscan_xilinx.sv]
read_verilog -sv [file join $root_dir rtl/vendor/xilinx/yifpga_jtag_transport_xilinx.sv]

synth_design -name yifpga_jtag_m33_synth -top yifpga_jtag_transport -part $part_name

# Standalone timing assumptions used by this CDC gate. The clocks are unrelated;
# the periods match the transport regression testbench (100 MHz and ~71.4 MHz).
create_clock -name debug_clk -period 10.000 [get_ports debug_clk]
create_clock -name jtag_clk  -period 14.000 [get_ports jtag_clk]
set_clock_groups -asynchronous \
    -group [get_clocks debug_clk] \
    -group [get_clocks jtag_clk]

if {[llength [get_clocks -quiet debug_clk]] != 1 ||
    [llength [get_clocks -quiet jtag_clk]] != 1} {
    error "M33 CDC gate requires both debug_clk and jtag_clk constraints"
}

set cdc_report [report_cdc -details -return_string]
set cdc_report_path [file join $root_dir prj/yifpga_jtag_m33_cdc.rpt]
set cdc_report_file [open $cdc_report_path w]
puts -nonewline $cdc_report_file $cdc_report
close $cdc_report_file

if {[regexp {CDC-[0-9]+[[:space:]]+Critical} $cdc_report]} {
    error "M33 CDC gate failed: Critical CDC violations found in $cdc_report_path"
}

puts "M33 synthesis and CDC report completed"
