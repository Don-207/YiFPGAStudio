# M34 discovery helpers. Board-specific mailbox shifts live behind these procs so
# deployments can adapt the USER-chain operation without changing Python.
proc ofjt_discover {} {
    open_hw_manager
    connect_hw_server -allow_non_jtag
    set rows {}
    foreach target [get_hw_targets] {
        current_hw_target $target
        open_hw_target
        foreach device [get_hw_devices] {
            set cable [get_property PARAM.FREQUENCY $target]
            if {$cable eq ""} { set cable [get_property NAME $target] }
            set target_name [get_property NAME $target]
            set device_name [get_property NAME $device]
            # The M34 board-validation image uses USER2.
            lappend rows [list $cable $target_name $device_name 2 0x4d340001]
        }
    }
    return $rows
}

proc ofjt_select {cable target_name device_name user_chain expected_build} {
    set matches [get_hw_devices -quiet -filter "NAME == $device_name"]
    if {[llength $matches] != 1} { error "device identity did not match exactly once" }
    current_hw_device [lindex $matches 0]
    set ::ofjt_user_chain $user_chain
    set ::ofjt_expected_build $expected_build
}
