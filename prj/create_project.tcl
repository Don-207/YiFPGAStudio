# Recreate the YiFPGA Studio Vivado project from repository sources.
# This only creates project metadata; it does not launch synthesis or implementation.
#
# Usage:
#   vivado -mode batch -source prj/create_project.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set project_dir [file join $script_dir YiFPGAStudio.generated]
set project_name YiFPGAStudio
set part_name xcku5p-ffvb676-2-i

create_project $project_name $project_dir -part $part_name -force

set rtl_debug [file join $repo_root rtl yifpga_debug]
set rtl_vendor [file join $repo_root rtl vendor xilinx]
set design_sources [concat \
    [lsort [glob -nocomplain [file join $rtl_debug *.vh]]] \
    [lsort [glob -nocomplain [file join $rtl_debug *.v]]] \
    [lsort [glob -nocomplain [file join $rtl_debug *.sv]]] \
    [lsort [glob -nocomplain [file join $rtl_vendor *.sv]]] \
    [list [file join $repo_root rtl board yifpga_debug_board_demo.v]]]

foreach source_file $design_sources {
    if {![file exists $source_file]} {
        error "Missing design source: $source_file"
    }
}
add_files -norecurse -fileset sources_1 $design_sources
set_property include_dirs [list $rtl_debug] [get_filesets sources_1]
set_property top yifpga_debug_board_demo [get_filesets sources_1]

set constraint_file [file join $script_dir constraints yifpga_debug_board_demo.xdc]
if {![file exists $constraint_file]} {
    error "Missing constraints: $constraint_file"
}
add_files -norecurse -fileset constrs_1 $constraint_file
set_property target_constrs_file $constraint_file [get_filesets constrs_1]

update_compile_order -fileset sources_1
puts "PASS: Created portable YiFPGA Studio project: [get_property DIRECTORY [current_project]]"
