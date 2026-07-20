# Run Vivado builds one stage at a time for easier troubleshooting.
#
# Usage:
#   vivado -mode batch -source prj/build_step.tcl -tclargs synth
#   vivado -mode batch -source prj/build_step.tcl -tclargs opt
#   vivado -mode batch -source prj/build_step.tcl -tclargs place
#   vivado -mode batch -source prj/build_step.tcl -tclargs route
#   vivado -mode batch -source prj/build_step.tcl -tclargs bit
#   vivado -mode batch -source prj/build_step.tcl -tclargs bit reset 8
#
# Arguments:
#   argv[0]  stage: synth, opt, place, route, or bit
#   argv[1]  optional: reset
#   argv[2]  optional: jobs count, default 8

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set proj_name  YiFPGAStudio
set xpr_file   [file join $script_dir YiFPGAStudio.generated ${proj_name}.xpr]

if {[llength $argv] < 1} {
    error "Missing stage. Use one of: synth, opt, place, route, bit."
}

set stage [string tolower [lindex $argv 0]]
set do_reset false
set jobs 8

if {[llength $argv] >= 2} {
    set arg1 [string tolower [lindex $argv 1]]
    if {$arg1 eq "reset"} {
        set do_reset true
    } elseif {[string is integer -strict $arg1]} {
        set jobs $arg1
    } else {
        error "Unknown second argument '$arg1'. Use 'reset' or a jobs count."
    }
}

if {[llength $argv] >= 3} {
    set arg2 [lindex $argv 2]
    if {![string is integer -strict $arg2]} {
        error "Jobs count must be an integer."
    }
    set jobs $arg2
}

array set impl_steps {
    opt   opt_design
    place place_design
    route route_design
    bit   write_bitstream
}

if {![file exists $xpr_file]} {
    source [file join $script_dir create_project.tcl]
} else {
    open_project $xpr_file
}

proc run_and_check {run_name args} {
    set cmd [list launch_runs $run_name]
    foreach arg $args {
        lappend cmd $arg
    }
    puts "INFO: [join $cmd { }]"
    eval $cmd
    wait_on_run $run_name

    set status [get_property STATUS [get_runs $run_name]]
    puts "INFO: $run_name status: $status"
    if {[string first "Complete" $status] < 0} {
        error "$run_name did not complete successfully"
    }
}

if {$stage eq "synth"} {
    if {$do_reset} {
        foreach run [get_runs -quiet *_synth_1] {
            if {$run ne "synth_1"} {
                reset_run $run
            }
        }
        reset_run synth_1
    }
    run_and_check synth_1 -jobs $jobs
    return
}

if {![info exists impl_steps($stage)]} {
    error "Unknown stage '$stage'. Use one of: synth, opt, place, route, bit."
}

set synth_status [get_property STATUS [get_runs synth_1]]
if {[string first "Complete" $synth_status] < 0} {
    puts "INFO: synth_1 is not complete; running synthesis first."
    if {$do_reset} {
        foreach run [get_runs -quiet *_synth_1] {
            if {$run ne "synth_1"} {
                reset_run $run
            }
        }
        reset_run synth_1
    }
    run_and_check synth_1 -jobs $jobs
}

if {$do_reset} {
    reset_run impl_1
}

set step $impl_steps($stage)
run_and_check impl_1 -to_step $step -jobs $jobs

if {$stage eq "bit"} {
    puts "INFO: Bitstream directory: [file join [get_property DIRECTORY [current_project]] ${proj_name}.runs impl_1]"
}
