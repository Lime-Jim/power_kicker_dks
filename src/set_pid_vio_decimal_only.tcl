# Change display radix only; do not commit values or program the device.
proc pk_pid_decimal_only {} {
    set signed_probes {vio_pid_target_mV vio_pid_kp vio_pid_ki vio_pid_kd}
    set unsigned_probes {vio_pid_feedback_enable vio_pid_window_mV vio_pid_clear vio_pid_confirm_samples vio_pid_corr_limit vio_pid_start_delay_ns vio_pid_require_window}
    set candidates {}
    foreach vio [get_hw_vios -quiet] {
        set cell [get_property CELL_NAME $vio]
        if {$cell eq "u_vio_pid" || [string match "*/u_vio_pid" $cell]} {
            lappend candidates $vio
        }
    }
    if {[llength $candidates] == 0} {
        # A semantic PID probe is safe if an old LTX lacks the cell name.
        foreach vio [get_hw_vios -quiet] {
            foreach probe [get_hw_probes -quiet -of_objects $vio] {
                set name [get_property NAME $probe]
                if {$name eq "vio_pid_target_mV" || [string match "*/vio_pid_target_mV" $name]} {
                    lappend candidates $vio
                    break
                }
            }
        }
    }
    if {[llength $candidates] != 1} {
        error "Expected one identifiable u_vio_pid core; found [llength $candidates]. Connect and load matching bitstream/LTX files."
    }
    set vio [lindex $candidates 0]
    foreach probe_name [concat $signed_probes $unsigned_probes] {
        set found 0
        foreach probe [get_hw_probes -quiet -of_objects $vio] {
            set name [get_property NAME $probe]
            if {$name eq $probe_name || [string match "*/$probe_name" $name]} {
                set radix [expr {$probe_name in $signed_probes ? "SIGNED" : "UNSIGNED"}]
                set_property OUTPUT_VALUE_RADIX $radix $probe
                catch {set_property DISPLAY_RADIX $radix $probe}
                set found 1
                break
            }
        }
        if {!$found} { puts "WARNING: Missing PID output probe $probe_name" }
    }
    refresh_hw_vio $vio
    puts "u_vio_pid is decimal: target/Kp/Ki/Kd signed; enables/window/count/limit unsigned."
}

pk_pid_decimal_only
