# Program a Xilinx FPGA bitstream through Vivado Hardware Manager.
#
# Usage:
#   vivado -mode batch -source prj/program.tcl
#   vivado -mode batch -source prj/program.tcl -tclargs path/to/top.bit
#   vivado -mode batch -source prj/program.tcl -tclargs path/to/top.bit "*Digilent*" "*xcku5p*"
#
# Arguments:
#   argv[0]  optional bitstream path. If omitted, the newest .bit under build/
#            is used.
#   argv[1]  optional hardware target glob pattern.
#   argv[2]  optional hardware device glob pattern.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]

proc newest_file {pattern} {
    set files [glob -nocomplain $pattern]
    if {[llength $files] == 0} {
        return ""
    }

    set newest [lindex $files 0]
    set newest_mtime [file mtime $newest]
    foreach file $files {
        set mtime [file mtime $file]
        if {$mtime > $newest_mtime} {
            set newest $file
            set newest_mtime $mtime
        }
    }
    return [file normalize $newest]
}

proc select_one {items kind pattern} {
    if {$pattern ne ""} {
        set matches {}
        foreach item $items {
            if {[string match -nocase $pattern $item]} {
                lappend matches $item
            }
        }
    } else {
        set matches $items
    }

    if {[llength $matches] == 1} {
        return [lindex $matches 0]
    }

    puts "ERROR: Expected exactly one $kind, found [llength $matches]."
    if {$pattern ne ""} {
        puts "ERROR: Pattern was: $pattern"
    }
    puts "Available $kind values:"
    foreach item $items {
        puts "  $item"
    }
    error "Select a unique $kind by passing a glob pattern in -tclargs."
}

set bit_file ""
set target_pattern ""
set device_pattern ""

if {[llength $argv] >= 1} {
    set bit_file [file normalize [lindex $argv 0]]
}
if {[llength $argv] >= 2} {
    set target_pattern [lindex $argv 1]
}
if {[llength $argv] >= 3} {
    set device_pattern [lindex $argv 2]
}

if {$bit_file eq ""} {
    set bit_file [newest_file [file join $repo_dir build *.bit]]
}
if {$bit_file eq ""} {
    set bit_file [newest_file [file join $repo_dir build * *.bit]]
}
if {$bit_file eq ""} {
    set bit_file [newest_file [file join $repo_dir build * * *.bit]]
}

if {$bit_file eq "" || ![file exists $bit_file]} {
    error "Bitstream not found. Pass the .bit path as the first -tclargs argument."
}

puts "INFO: Bitstream: $bit_file"

open_hw_manager
connect_hw_server

set targets [get_hw_targets]
if {[llength $targets] == 0} {
    error "No hardware targets found. Check JTAG cable, board power, and hw_server."
}

set target [select_one $targets "hardware target" $target_pattern]
puts "INFO: Opening target: $target"
open_hw_target $target

set devices [get_hw_devices]
if {[llength $devices] == 0} {
    error "No hardware devices found on target $target."
}

set device [select_one $devices "hardware device" $device_pattern]
puts "INFO: Programming device: $device"

set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

puts "INFO: Programming complete."
