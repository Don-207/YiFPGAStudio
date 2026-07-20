open_hw_manager
connect_hw_server

set target [lindex [get_hw_targets] 0]
open_hw_target $target
set device [lindex [get_hw_devices] 0]

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. ..]]
set ltx_file [file join $repo_dir prj YiFPGAStudio.runs impl_1 yifpga_debug_board_demo_ila.ltx]
set_property PROBES.FILE $ltx_file $device
refresh_hw_device $device

set ila [lindex [get_hw_ilas] 0]
puts "ILA=$ila"
puts "PROBES:"
foreach probe [get_hw_probes -of_objects $ila] {
    puts "  [get_property NAME $probe]"
    report_property $probe
}

close_hw_manager
