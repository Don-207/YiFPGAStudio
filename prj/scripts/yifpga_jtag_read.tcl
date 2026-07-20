# Persistent M34 worker. These two low-level procs are the sole adaptation point
# for Vivado releases/boards exposing a different USER-chain shift primitive.
source [file join [file dirname [info script]] yifpga_jtag_discover.tcl]

proc ofjt_shift_read {kind length} {
    error "M33 USER-DR command engine is not integrated; Hardware Manager cannot perform a generic raw USER shift (kind=$kind)"
}
proc ofjt_shift_commit {session start length} {
    error "M33 USER-DR command engine is not integrated; commit is unavailable"
}
proc ofjt_reply {args} { puts [join [linsert $args 0 OFJT] "\t"]; flush stdout }

set targets {}
while {[gets stdin line] >= 0} {
    if {$line eq "QUIT"} break
    set fields [split $line "\t"]
    set command [lindex $fields 0]
    if {[catch {
        switch -- $command {
            DISCOVER { set targets [ofjt_discover]; ofjt_reply OK [llength $targets] }
            TARGET {
                set row [lindex $targets [lindex $fields 1]]
                if {[llength $row] != 5} { error "invalid target index" }
                ofjt_reply OK {*}$row
            }
            OPEN { ofjt_select {*}[lrange $fields 1 5]; ofjt_reply OK }
            HEADER { ofjt_reply OK [ofjt_shift_read header 40] }
            READ {
                set result [ofjt_shift_read payload [lindex $fields 1]]
                if {[llength $result] != 3} { error "read adapter must return session start hex" }
                ofjt_reply OK {*}$result
            }
            COMMIT { ofjt_shift_commit {*}[lrange $fields 1 3]; ofjt_reply OK }
            default { error "unknown command" }
        }
    } message]} { ofjt_reply ERR $message }
}
catch {close_hw_manager}
