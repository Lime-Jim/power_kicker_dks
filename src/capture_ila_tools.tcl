# Hardware Manager helpers. Sourcing does not program hardware or change VIO outputs.
proc pk_capture_ila {} {
    set device [current_hw_device]
    if {[llength $device] != 1} { error "Select one programmed device first." }
    set ilas [get_hw_ilas -quiet -of_objects $device -filter {CELL_NAME =~ "*u_ila_capture"}]
    if {[llength $ilas] != 1} { error "Load matching capture-state BIT/LTX and refresh the device; expected one u_ila_capture." }
    return [lindex $ilas 0]
}
proc pk_capture_read {{csv_path {}}} {
    set ila [pk_capture_ila]
    wait_on_hw_ila -timeout 0.5 $ila
    set data [upload_hw_ila_data $ila]
    if {[llength $data] != 1} { error "Expected one captured data buffer." }
    display_hw_ila_data $data
    if {$csv_path ne {}} { write_hw_ila_data -csv_file $csv_path $data }
    return $data
}
proc pk_capture_now {{csv_path {}}} {
    set ila [pk_capture_ila]
    set_property CONTROL.DATA_DEPTH 8192 $ila
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    run_hw_ila -trigger_now $ila
    return [pk_capture_read $csv_path]
}
proc pk_capture_status {} {
    set vios [get_hw_vios -quiet -of_objects [current_hw_device] -filter {CELL_NAME =~ "*u_vio_pid"}]
    if {[llength $vios] != 1} { error "Expected one PID VIO on the current device." }
    set vio [lindex $vios 0]
    set selected {}
    foreach signal {w_capture_phase w_captured_seen} {
        set found {}
        foreach probe [get_hw_probes -quiet -of_objects $vio] {
            set name [get_property NAME $probe]
            if {$name eq $signal || [string match "*/$signal" $name]} { lappend found $probe }
        }
        if {[llength $found] != 1} { error "Missing/ambiguous status probe $signal; check LTX." }
        set_property INPUT_VALUE_RADIX UNSIGNED $found
        lappend selected [lindex $found 0]
    }
    refresh_hw_vio $vio
    set phase [get_property INPUT_VALUE [lindex $selected 0]]
    set seen [get_property INPUT_VALUE [lindex $selected 1]]
    if {![string is integer -strict $phase] || $phase < 0 || $phase > 3} {
        error "Unexpected phase value: $phase"
    }
    puts "phase=$phase ([lindex {IDLE SCAN CAPTURE PID_FEEDBACK} $phase]); captured_seen=$seen"
    return [dict create phase $phase captured_seen $seen]
}
puts "Capture helpers loaded: pk_capture_status, pk_capture_now, pk_capture_read. Phase: 0 IDLE, 1 SCAN, 2 CAPTURE, 3 PID_FEEDBACK."
