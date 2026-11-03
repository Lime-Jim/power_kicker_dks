set vio [get_hw_vios -of_objects [get_hw_devices xcau15p_0] -filter {CELL_NAME=~"u_vio_control"}]
if {[llength $vio] == 0} {
    error "Cannot find u_vio_control. Make sure the device is programmed and Hardware Manager is connected."
}

set control_probes [list \
    vio_auto_sweep_enable \
    vio_auto_sweep_freq_Hz \
    vio_kick_base_mV \
    vio_kick_min_mV \
    vio_kick_fall_ns \
    vio_kick_rise_ns \
    vio_sweep_start_mV \
    vio_sweep_final_mV \
    vio_sweep_trigger_mV \
    vio_sweep_scan_us \
]

foreach probe_name $control_probes {
    set probe [get_hw_probes -quiet $probe_name -of_objects $vio]
    if {[llength $probe] > 0} {
        set_property OUTPUT_VALUE_RADIX UNSIGNED $probe
    } else {
        puts "WARNING: Missing probe $probe_name"
    }
}

refresh_hw_vio $vio
puts "u_vio_control probes are now shown as unsigned decimal."
