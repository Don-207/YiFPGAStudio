# M36 synthesis matrix and JTAG/ILA coexistence static gate.
# This script performs synthesis only. Implementation and bitstream remain
# explicit, separately approved hardware/release operations.
set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set out_root [file join $repo_root prj YiFPGAStudio.runs m36_matrix]
set part_name xcku5p-ffvb676-2-i
file mkdir $out_root

set rtl_debug [file join $repo_root rtl yifpga_debug]
set rtl_vendor [file join $repo_root rtl vendor xilinx]
set board_file [file join $repo_root rtl board yifpga_debug_board_demo.v]
set sources_v [concat [lsort [glob -nocomplain [file join $rtl_debug *.vh]]] \
                      [lsort [glob -nocomplain [file join $rtl_debug *.v]]] \
                      [list $board_file]]
set sources_sv [concat [lsort [glob -nocomplain [file join $rtl_debug *.sv]]] \
                       [lsort [glob -nocomplain [file join $rtl_vendor *.sv]]]]

foreach {name enable_uart enable_jtag perf_mode expected_bscan} {
    uart             1 0 0 0
    jtag             0 1 0 1
    uart_and_jtag    1 1 0 1
    jtag_disabled    1 0 0 0
    jtag_perf        0 1 1 1
} {
    create_project -in_memory -part $part_name m36_$name
    read_verilog $sources_v
    read_verilog -sv $sources_sv
    read_xdc [file join $repo_root prj constraints yifpga_debug_board_demo.xdc]
    synth_design -top yifpga_debug_board_demo -part $part_name \
        -generic ENABLE_UART=$enable_uart -generic ENABLE_JTAG=$enable_jtag \
        -generic JTAG_PERF_MODE=$perf_mode
    set bscan_count [llength [get_cells -hier -filter {REF_NAME == BSCANE2}]]
    if {$bscan_count != $expected_bscan} {
        error "M36 $name: expected $expected_bscan BSCANE2, found $bscan_count"
    }
    set out_dir [file join $out_root $name]
    file mkdir $out_dir
    report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
    report_clock_interaction -file [file join $out_dir clock_interaction.rpt]
    report_cdc -details -file [file join $out_dir cdc.rpt]
    set report [open [file join $out_dir manifest.txt] w]
    puts $report "configuration=$name"
    puts $report "part=$part_name"
    puts $report "enable_uart=$enable_uart"
    puts $report "enable_jtag=$enable_jtag"
    puts $report "jtag_perf_mode=$perf_mode"
    puts $report "user_chain=2"
    puts $report "bscan_count=$bscan_count"
    close $report
    close_project
}
puts "PASS: M36 synthesis matrix and BSCANE2 pruning gate completed"
