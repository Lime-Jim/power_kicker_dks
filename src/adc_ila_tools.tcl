# Source in Vivado Hardware Manager after loading the matching BIT and LTX.
# Sourcing only defines commands: it does not program the FPGA or change VIO.
proc pk_adc_ila {} {
    set device [current_hw_device]
    if {[llength $device] != 1} { error "Select one programmed hardware device first." }
    set candidates [get_hw_ilas -quiet -of_objects $device -filter {CELL_NAME =~ "*u_ila_adc*"}]
    if {[llength $candidates] != 1} {
        error "Expected one ADC ILA, found [llength $candidates]. Load the matching ADC BIT/LTX and refresh the device."
    }
    return [lindex $candidates 0]
}

proc pk_adc_capture {{csv_path {}}} {
    set ila [pk_adc_ila]
    set_property CONTROL.CAPTURE_MODE ALWAYS $ila
    set_property CONTROL.DATA_DEPTH 8192 $ila
    set_property CONTROL.TRIGGER_POSITION 0 $ila
    run_hw_ila -trigger_now $ila
    wait_on_hw_ila -timeout 0.5 $ila
    set data [upload_hw_ila_data $ila]
    if {[llength $data] != 1} { error "ADC capture did not return one data buffer." }
    display_hw_ila_data $data
    if {$csv_path ne {}} {
        # Do not overwrite an earlier measurement.
        write_hw_ila_data -csv_file $csv_path $data
    }
    puts "ADC capture: probe0=A raw14, probe1=B raw14 (PID input), probe2=decimated B signed16."
    puts "For numeric values, set waveform Radix to Signed Decimal."
    return $data
}

puts "ADC ILA helpers loaded. Run: pk_adc_capture ; optional CSV: pk_adc_capture {D:/measurements/adc_001.csv}"
