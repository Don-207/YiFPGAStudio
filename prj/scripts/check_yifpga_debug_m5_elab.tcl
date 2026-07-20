# Lightweight M5 project elaboration check.
# Usage:
#   vivado -mode batch -source prj/scripts/check_yifpga_debug_m5_elab.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]

open_project [file join $repo_root prj YiFPGAStudio.xpr]
update_compile_order -fileset sources_1
synth_design -rtl -name yifpga_debug_m5_rtl -top yifpga_debug_board_demo -part xcku5p-ffvb676-2-i

puts "PASS: YiFPGA Debug M5 Vivado RTL elaboration completed"
