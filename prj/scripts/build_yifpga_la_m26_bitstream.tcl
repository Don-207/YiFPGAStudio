# M26 release bitstream entry point. Reuses the reviewed implementation flow
# and copies the resulting image to an M26-stable release filename.
# Usage: vivado -mode batch -source prj/scripts/build_yifpga_la_m26_bitstream.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
source [file join $script_dir build_yifpga_la_m23_bitstream.tcl]

set generated_bit [file join $repo_root prj YiFPGAStudio.runs impl_1 yifpga_debug_board_demo_m23.bit]
set release_bit [file join $repo_root prj YiFPGAStudio.runs impl_1 yifpga_debug_board_demo_m26.bit]
if {![file exists $generated_bit]} {
    error "M26 source bitstream not found: $generated_bit"
}
file copy -force $generated_bit $release_bit
puts "PASS: Built YiFPGA M26 Logic Analyzer release bitstream: $release_bit"
