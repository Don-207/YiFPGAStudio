# Build the M36 UART+JTAG release image with Vivado ILA coexistence evidence.
set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_debug [file join $repo_root rtl yifpga_debug]
set rtl_vendor [file join $repo_root rtl vendor xilinx]
set part_name xcku5p-ffvb676-2-i
set perf_mode 0
set jtag_only_mode 0
set reuse_synth 0
foreach arg $argv {
    if {$arg eq "perf"} { set perf_mode 1 }
    if {$arg eq "jtag_only"} { set jtag_only_mode 1 }
    if {$arg eq "reuse"} { set reuse_synth 1 }
    if {$arg ne "perf" && $arg ne "jtag_only" && $arg ne "reuse"} {
        error "Unknown M36 build mode: $arg"
    }
}
if {$perf_mode && $jtag_only_mode} { error "perf and jtag_only are mutually exclusive" }
if {$perf_mode} {
    set enable_uart 0
    set build_name m36_perf_ila
    set artifact_stem yifpga_debug_board_demo_m36_perf_ila
} elseif {$jtag_only_mode} {
    set enable_uart 0
    set build_name m36_jtag_only_ila
    set artifact_stem yifpga_debug_board_demo_m36_jtag_only_ila
} else {
    set enable_uart 1
    set build_name m36_ila
    set artifact_stem yifpga_debug_board_demo_m36_ila
}
set out_dir [file join $repo_root prj YiFPGAStudio.runs $build_name]
set bit_file [file join $out_dir ${artifact_stem}.bit]
set ltx_file [file join $out_dir ${artifact_stem}.ltx]
file mkdir $out_dir

read_verilog [concat \
    [lsort [glob -nocomplain [file join $rtl_debug *.vh]]] \
    [lsort [glob -nocomplain [file join $rtl_debug *.v]]] \
    [list [file join $repo_root rtl board yifpga_debug_board_demo.v]]]
read_verilog -sv [concat \
    [lsort [glob -nocomplain [file join $rtl_debug *.sv]]] \
    [lsort [glob -nocomplain [file join $rtl_vendor *.sv]]]]
read_xdc [file join $repo_root prj constraints yifpga_debug_board_demo.xdc]

set synth_dcp [file join $out_dir post_synth.dcp]
if {$reuse_synth && [file exists $synth_dcp]} {
    open_checkpoint $synth_dcp
} else {
    synth_design -top yifpga_debug_board_demo -part $part_name \
        -generic ENABLE_UART=$enable_uart -generic ENABLE_JTAG=1 \
        -generic JTAG_PERF_MODE=$perf_mode
    write_checkpoint -force $synth_dcp
}

set bscan_count [llength [get_cells -hier -filter {REF_NAME == BSCANE2}]]
if {$bscan_count != 1} {
    error "M36 ILA coexistence requires exactly one USER2 BSCANE2, found $bscan_count"
}
set ila_clk [get_nets -hier -filter {NAME =~ *monitor_ila_clk*}]
if {[llength $ila_clk] != 1} {
    error "Expected one monitor_ila_clk net, found [llength $ila_clk]"
}
set all_probe_nets [get_nets -hier -filter {NAME =~ *monitor_ila_probe*}]
set ila_probe {}
for {set bit 0} {$bit < 64} {incr bit} {
    set expected [format {u_debug_top/monitor_ila_probe[%d]} $bit]
    set matches {}
    foreach net $all_probe_nets {
        if {[get_property NAME $net] eq $expected} { lappend matches $net }
    }
    if {[llength $matches] != 1} {
        foreach match $matches { puts "ILA_PROBE_CANDIDATE: [get_property NAME $match]" }
        error "Expected one ILA probe net $expected, found [llength $matches]"
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
report_route_status -file [file join $out_dir route_status.rpt]
report_timing_summary -max_paths 10 -warn_on_violation \
    -file [file join $out_dir timing_summary.rpt]
report_drc -file [file join $out_dir drc.rpt]
report_utilization -hierarchical -file [file join $out_dir utilization.rpt]
report_cdc -details -file [file join $out_dir cdc.rpt]

set timing_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $timing_paths] == 0} { error "No setup timing path found" }
set wns [get_property SLACK [lindex $timing_paths 0]]
if {$wns < 0.0} { error "M36 ILA timing failed: WNS=$wns ns" }
set unrouted [get_nets -hier -quiet -filter {ROUTE_STATUS == UNROUTED}]
if {[llength $unrouted] != 0} {
    error "M36 ILA image contains [llength $unrouted] unrouted nets"
}

write_debug_probes -force $ltx_file
write_bitstream -force $bit_file
foreach artifact [list $bit_file $ltx_file] {
    if {![file exists $artifact]} { error "Missing M36 artifact: $artifact" }
}
set manifest [open [file join $out_dir manifest.txt] w]
puts $manifest "configuration=$build_name"
puts $manifest "part=$part_name"
puts $manifest "enable_uart=$enable_uart"
puts $manifest "enable_jtag=1"
puts $manifest "jtag_perf_mode=$perf_mode"
puts $manifest "jtag_only_mode=$jtag_only_mode"
puts $manifest "user_chain=2"
puts $manifest "bscan_count=$bscan_count"
puts $manifest "ila_count=[llength [get_debug_cores u_ila_monitor]]"
puts $manifest "wns_ns=$wns"
puts $manifest "bitstream=$bit_file"
puts $manifest "probes=$ltx_file"
close $manifest
puts "PASS: Built M36 JTAG+ILA image: $bit_file (WNS=$wns ns)"
