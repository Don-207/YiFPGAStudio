# Build the KU5P PCIe Gen3 x8 Vivado project.
#
# Usage:
#   vivado -mode batch -source prj/build.tcl
#   vivado -mode batch -source prj/build.tcl -tclargs synth_only

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set proj_name  ku5p_pcie_gen3x8
set xpr_file   [file join $repo_dir build $proj_name ${proj_name}.xpr]
set synth_only [expr {[lsearch -exact $argv synth_only] >= 0}]

if {![file exists $xpr_file]} {
    source [file join $script_dir create_project.tcl]
} else {
    open_project $xpr_file
}

foreach run [get_runs -quiet *_synth_1] {
    if {$run ne "synth_1"} {
        reset_run $run
    }
}
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "INFO: synth_1 status: $synth_status"
if {[string first "Complete" $synth_status] < 0} {
    error "Synthesis did not complete successfully"
}

if {$synth_only} {
    puts "INFO: Stopping after synthesis because synth_only was requested"
    return
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: impl_1 status: $impl_status"
if {[string first "Complete" $impl_status] < 0} {
    error "Implementation did not complete successfully"
}

puts "INFO: Bitstream directory: [file join [get_property DIRECTORY [current_project]] ${proj_name}.runs impl_1]"
