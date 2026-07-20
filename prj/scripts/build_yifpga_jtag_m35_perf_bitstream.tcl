# Build the M35 sustained-JTAG performance image (JTAG source only; UART unchanged).
set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug_dir [file join $repo_root rtl yifpga_debug]
set rtl_vendor_dir [file join $repo_root rtl vendor xilinx]
set rtl_board_dir [file join $repo_root rtl board]
set out_dir [file join $repo_root prj YiFPGAStudio.runs m35_perf]
set bit_file [file join $out_dir yifpga_debug_board_demo_m35_perf.bit]
set part_name xcku5p-ffvb676-2-i
file mkdir $out_dir

read_verilog [concat \
    [lsort [glob -nocomplain [file join $rtl_debug_dir *.vh]]] \
    [lsort [glob -nocomplain [file join $rtl_debug_dir *.v]]] \
    [list [file join $rtl_board_dir yifpga_debug_board_demo.v]]]
read_verilog -sv [concat \
    [lsort [glob -nocomplain [file join $rtl_debug_dir *.sv]]] \
    [lsort [glob -nocomplain [file join $rtl_vendor_dir *.sv]]]]
read_xdc [file join $repo_root prj constraints yifpga_debug_board_demo.xdc]

puts "INFO: Synthesizing M35 performance image"
synth_design -top yifpga_debug_board_demo -part $part_name \
    -generic JTAG_PERF_MODE=1 -generic JTAG_PERF_BYTE_INTERVAL_TICKS=50
opt_design
place_design
route_design

report_route_status -file [file join $out_dir route_status.rpt]
report_timing_summary -max_paths 10 -warn_on_violation -file [file join $out_dir timing_summary.rpt]
report_drc -file [file join $out_dir drc.rpt]
report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
write_bitstream -force $bit_file
if {![file exists $bit_file]} { error "Bitstream not generated: $bit_file" }
puts "PASS: Built M35 JTAG performance bitstream: $bit_file"
