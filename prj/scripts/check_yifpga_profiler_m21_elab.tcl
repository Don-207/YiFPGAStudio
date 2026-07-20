# Lightweight M21 Profiler board demo elaboration check.
# Usage:
#   vivado -mode batch -source prj/scripts/check_yifpga_profiler_m21_elab.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug_dir [file join $repo_root rtl yifpga_debug]
set rtl_board_dir [file join $repo_root rtl board]
set rtl_vendor_dir [file join $repo_root rtl vendor xilinx]

cd $repo_root
read_verilog [concat \
    [lsort [glob -nocomplain [file join $rtl_debug_dir *.vh]]] \
    [lsort [glob -nocomplain [file join $rtl_debug_dir *.v]]] \
    [list [file join $rtl_board_dir yifpga_debug_board_demo.v]]]
read_verilog -sv [concat \
    [lsort [glob -nocomplain [file join $rtl_debug_dir *.sv]]] \
    [lsort [glob -nocomplain [file join $rtl_vendor_dir *.sv]]]]

synth_design -rtl -name yifpga_profiler_m21_rtl -top yifpga_debug_board_demo -part xcku5p-ffvb676-2-i

puts "PASS: YiFPGA Profiler M21 board demo Vivado RTL elaboration completed"
