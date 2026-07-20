open_hw_manager
connect_hw_server

set targets [get_hw_targets]
puts "HW_TARGETS:"
foreach target $targets {
    puts "  $target"
}

if {[llength $targets] == 0} {
    error "No hardware targets found."
}

set target [lindex $targets 0]
open_hw_target $target

set devices [get_hw_devices]
puts "HW_DEVICES:"
foreach device $devices {
    puts "  $device"
}

if {[llength $devices] == 0} {
    error "No hardware devices found."
}

set device [lindex $devices 0]
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. ..]]
set ltx_file [file join $repo_dir prj YiFPGAStudio.runs impl_1 yifpga_debug_board_demo_ila.ltx]
if {[file exists $ltx_file]} {
    puts "INFO: Probes file: $ltx_file"
    set_property PROBES.FILE $ltx_file $device
} else {
    puts "INFO: Probes file not found: $ltx_file"
}
refresh_hw_device $device

set cores [get_hw_ilas -quiet]
puts "HW_ILAS:"
if {[llength $cores] == 0} {
    puts "  <none>"
} else {
    foreach core $cores {
        puts "  $core"
    }
}

close_hw_manager
