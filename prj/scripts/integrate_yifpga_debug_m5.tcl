# YiFPGA Studio M5 board-demo integration script.
# Usage in Vivado Tcl console:
#   source prj/scripts/integrate_yifpga_debug_m5.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set project_file [file join $repo_root prj YiFPGAStudio.xpr]

if {[llength [get_projects -quiet]] == 0} {
    open_project $project_file
}

proc add_file_if_missing {fileset file_path} {
    if {[llength [get_files -quiet $file_path]] == 0} {
        add_files -norecurse -fileset $fileset $file_path
    }
}

set rtl_files [list \
    [file join $repo_root rtl yifpga_debug yifpga_debug_pkg.vh] \
    [file join $repo_root rtl yifpga_debug yifpga_trace_pkg.vh] \
    [file join $repo_root rtl yifpga_debug yifpga_monitor_pkg.vh] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_timestamp.v] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_ring_buffer.v] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_packetizer.v] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_uart_tx.v] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_uart_rx.v] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_command_parser.v] \
    [file join $repo_root rtl yifpga_debug yifpga_trace_adapter.v] \
    [file join $repo_root rtl yifpga_debug yifpga_trace_dma_probe.v] \
    [file join $repo_root rtl yifpga_debug yifpga_trace_frame_probe.v] \
    [file join $repo_root rtl yifpga_debug yifpga_trace_fifo_probe.v] \
    [file join $repo_root rtl yifpga_debug yifpga_trace_irq_probe.v] \
    [file join $repo_root rtl yifpga_debug yifpga_monitor_reg_bank.v] \
    [file join $repo_root rtl yifpga_debug yifpga_monitor_core.v] \
    [file join $repo_root rtl yifpga_debug yifpga_monitor_adapter.v] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_core.v] \
    [file join $repo_root rtl yifpga_debug yifpga_debug_top.v] \
    [file join $repo_root rtl board yifpga_debug_board_demo.v] \
]

foreach rtl_file $rtl_files {
    add_file_if_missing sources_1 $rtl_file
}
set_property include_dirs [list [file join $repo_root rtl yifpga_debug]] [current_fileset]
set_property top yifpga_debug_board_demo [current_fileset]

set xdc_file [file join $repo_root prj constraints yifpga_debug_board_demo.xdc]
if {[file exists $xdc_file]} {
    add_file_if_missing constrs_1 $xdc_file
}

update_compile_order -fileset sources_1

puts "YiFPGA Debug M5 demo integrated. Edit prj/constraints/yifpga_debug_board_demo.xdc with the board pinout before implementation/bitstream."
