proc compare_one_bit {width bit value} {
    set bits ""
    for {set i [expr {$width - 1}]} {$i >= 0} {incr i -1} {
        if {$i == $bit} {
            append bits $value
        } else {
            append bits X
        }
    }
    return "eq${width}'b${bits}"
}

open_hw_manager
connect_hw_server

set target [lindex [get_hw_targets] 0]
open_hw_target $target
set device [lindex [get_hw_devices] 0]

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir .. ..]]
set ltx_file [file join $repo_dir prj YiFPGAStudio.runs impl_1 yifpga_debug_board_demo_ila.ltx]
set trigger_bit 50
set trigger_value 0
set out_name monitor_uart_rx_ila.csv

if {[llength $argv] >= 1} {
    set trigger_bit [lindex $argv 0]
}
if {[llength $argv] >= 2} {
    set trigger_value [lindex $argv 1]
}
if {[llength $argv] >= 3} {
    set out_name [lindex $argv 2]
}

set out_file [file join $repo_dir prj YiFPGAStudio.runs impl_1 $out_name]

set_property PROBES.FILE $ltx_file $device
refresh_hw_device $device

set ila [lindex [get_hw_ilas] 0]
set probe [lindex [get_hw_probes -of_objects $ila] 0]

# Bit map highlights:
#   50 uart_rx, 51 monitor_byte_valid, 52 monitor_uart_frame_error
set_property TRIGGER_COMPARE_VALUE [compare_one_bit 64 $trigger_bit $trigger_value] $probe
set_property CONTROL.TRIGGER_POSITION 256 $ila

puts "INFO: Arming ILA $ila, trigger bit${trigger_bit}==$trigger_value"
run_hw_ila $ila
wait_on_hw_ila $ila
puts "INFO: ILA triggered, uploading data"

set data [upload_hw_ila_data $ila]
write_hw_ila_data -force -csv_file $out_file $data
puts "PASS: Wrote $out_file"

close_hw_manager
