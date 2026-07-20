# Capture the M36 monitor ILA from one exact cable target suffix.
if {$argc != 2} { error "Pass exact target suffix and output CSV name" }
set target_selector [lindex $argv 0]
set output_name [lindex $argv 1]
if {[file tail $output_name] ne $output_name} { error "Output must be a plain file name" }
set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set out_dir [file join $repo_root prj YiFPGAStudio.runs m36_ila]
set ltx_file [file join $out_dir yifpga_debug_board_demo_m36_ila.ltx]
set output_file [file join $out_dir $output_name]
if {![file exists $ltx_file]} { error "M36 LTX not found: $ltx_file" }

open_hw_manager
connect_hw_server
set targets {}
foreach candidate [get_hw_targets -quiet] {
    set name [get_property NAME $candidate]
    if {$name eq $target_selector || [string match "*/$target_selector" $name]} {
        lappend targets $candidate
    }
}
if {[llength $targets] != 1} {
    error "Expected exactly one target '$target_selector', found [llength $targets]"
}
open_hw_target [lindex $targets 0]
set devices [get_hw_devices]
if {[llength $devices] != 1} { error "Expected one FPGA, found [llength $devices]" }
set device [lindex $devices 0]
current_hw_device $device
set_property PROBES.FILE $ltx_file $device
refresh_hw_device $device
set ilas [get_hw_ilas -quiet]
if {[llength $ilas] != 1} { error "Expected one ILA, found [llength $ilas]" }
set ila [lindex $ilas 0]
set probes [get_hw_probes -of_objects $ila]
if {[llength $probes] != 1} { error "Expected one 64-bit probe port" }
# uart_rx (bit 50) is high while idle, providing a deterministic immediate capture.
set compare "eq64'b"
for {set bit 63} {$bit >= 0} {incr bit -1} {
    append compare [expr {$bit == 50 ? "1" : "X"}]
}
set_property TRIGGER_COMPARE_VALUE $compare [lindex $probes 0]
set_property CONTROL.TRIGGER_POSITION 512 $ila
run_hw_ila $ila
wait_on_hw_ila $ila
set data [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file $output_file $data
if {![file exists $output_file] || [file size $output_file] == 0} {
    error "ILA CSV was not generated"
}
puts "PASS: M36 ILA captured from $device to $output_file"
close_hw_manager
