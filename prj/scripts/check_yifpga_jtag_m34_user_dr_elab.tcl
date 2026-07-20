set root_dir [file normalize [file join [file dirname [info script]] ../..]]
set part_name xcku5p-ffvb676-2-i

read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_ring_buffer.sv]
read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_mailbox.sv]
read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_transport.sv]
read_verilog -sv [file join $root_dir rtl/yifpga_debug/yifpga_jtag_user_dr.sv]
read_verilog -sv [file join $root_dir rtl/vendor/xilinx/yifpga_jtag_bscan_xilinx.sv]
read_verilog -sv [file join $root_dir rtl/vendor/xilinx/yifpga_jtag_transport_xilinx.sv]

synth_design -name yifpga_jtag_m34_user_dr_synth \
    -top yifpga_jtag_transport_xilinx -part $part_name

if {[llength [get_cells -hier -filter {REF_NAME == BSCANE2}]] != 1} {
    error "M34 USER-DR gate requires exactly one BSCANE2 instance"
}
if {[llength [get_cells -hier -filter {REF_NAME =~ yifpga_jtag_user_dr*}]] != 1} {
    error "M34 USER-DR command engine was not preserved in hierarchy"
}
if {[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]] < 1} {
    error "M34 ring buffer did not infer block RAM"
}
puts "M34 BSCANE2 USER-DR RTL elaboration completed"
