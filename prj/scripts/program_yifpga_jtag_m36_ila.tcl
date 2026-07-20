# Program the M36 JTAG+ILA image; an exact cable target filter is mandatory.
set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
if {$argc < 1 || $argc > 2} {
    error "Pass exact target and optional 'perf' or 'jtag_only' mode"
}
set mode [expr {$argc == 2 ? [lindex $argv 1] : "normal"}]
if {$mode eq "perf"} {
    set out_dir [file join $repo_root prj YiFPGAStudio.runs m36_perf_ila]
    set stem yifpga_debug_board_demo_m36_perf_ila
} elseif {$mode eq "normal"} {
    set out_dir [file join $repo_root prj YiFPGAStudio.runs m36_ila]
    set stem yifpga_debug_board_demo_m36_ila
} elseif {$mode eq "jtag_only"} {
    set out_dir [file join $repo_root prj YiFPGAStudio.runs m36_jtag_only_ila]
    set stem yifpga_debug_board_demo_m36_jtag_only_ila
} else { error "Unknown M36 program mode: $mode" }
set bit_file [file join $out_dir ${stem}.bit]
set ltx_file [file join $out_dir ${stem}.ltx]
foreach artifact [list $bit_file $ltx_file] {
    if {![file exists $artifact]} { error "M36 artifact not found: $artifact" }
}
set target_filter [lindex $argv 0]
open_hw_manager
connect_hw_server
set targets {}
foreach candidate [get_hw_targets -quiet] {
    set candidate_name [get_property NAME $candidate]
    if {$candidate_name eq $target_filter ||
        [string match "*/$target_filter" $candidate_name]} {
        lappend targets $candidate
    }
}
if {[llength $targets] != 1} {
    error "Expected exactly one target matching '$target_filter', found [llength $targets]: $targets"
}
open_hw_target [lindex $targets 0]
set devices [get_hw_devices]
if {[llength $devices] != 1} { error "Expected one FPGA, found [llength $devices]: $devices" }
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bit_file $device
set_property PROBES.FILE $ltx_file $device
program_hw_devices $device
refresh_hw_device $device
if {[llength [get_hw_ilas -quiet]] != 1} {
    error "M36 programmed image did not enumerate exactly one ILA"
}
puts "PASS: Programmed M36 JTAG+ILA image on $device; ILA enumerated"
