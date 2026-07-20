# Program the current YiFPGA Debug board demo bitstream over JTAG.
# Usage (target filter is mandatory):
#   vivado -mode batch -source prj/scripts/program_yifpga_debug_board_demo.tcl -tclargs *210308A1*

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set bit_file [file join $repo_root prj YiFPGAStudio.runs impl_1 yifpga_debug_board_demo.bit]

if {![file exists $bit_file]} {
    error "Bitstream not found: $bit_file"
}

if {$argc != 1} {
    error "Pass exactly one JTAG target filter in -tclargs; refusing to guess a connected target"
}
set target_filter [lindex $argv 0]

open_hw_manager
connect_hw_server
set targets [get_hw_targets -quiet -filter "NAME =~ $target_filter"]
if {[llength $targets] != 1} {
    error "Expected exactly one JTAG target matching '$target_filter', found [llength $targets]: $targets"
}
open_hw_target [lindex $targets 0]

set devices [get_hw_devices]
if {[llength $devices] != 1} {
    error "Expected exactly one FPGA device on the selected target, found [llength $devices]: $devices"
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

puts "PASS: Programmed $device with $bit_file"
