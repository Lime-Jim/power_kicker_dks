# Source-synchronous DDR I/O model. All times are ns.
# Loading defines procedures only; load_external_timing.tcl calls apply.
namespace eval ::power_kicker_io {
    variable script_dir [file dirname [file normalize [info script]]]
    variable profile {}
    variable profile_path {}
    variable status PROVISIONAL_NOT_LOADED
    variable reasons {}
}

proc ::power_kicker_io::load_profile {} {
    variable script_dir
    variable profile
    variable profile_path
    variable status
    variable reasons
    set profile {}
    set reasons {}
    set profile_path [file join $script_dir board_timing.tcl]
    if {[info exists ::env(POWER_KICKER_BOARD_TIMING)] &&
        $::env(POWER_KICKER_BOARD_TIMING) ne {}} {
        set profile_path [file normalize $::env(POWER_KICKER_BOARD_TIMING)]
    }
    if {![file isfile $profile_path]} {
        set status PROVISIONAL_MISSING_BOARD_PROFILE
        set reasons [list "Missing board timing profile: $profile_path"]
        return 0
    }
    uplevel #0 [list source $profile_path]
    return [validate_profile]
}

proc ::power_kicker_io::validate_profile {} {
    variable profile
    variable status
    variable reasons
    set reasons {}
    set required {
        schema_version validated board_revision evidence
        adc_reg16 adc_reg17 dac_reg16 adc_period_ns dac_period_ns
        adc_data_lead_min_ns adc_data_lead_max_ns
        adc_board_skew_min_ns adc_board_skew_max_ns adc_margin_ns
        dac_board_skew_min_ns dac_board_skew_max_ns dac_margin_ns
    }
    foreach key $required {
        if {![dict exists $profile $key] || [dict get $profile $key] eq {}} {
            lappend reasons "Unspecified timing field: $key"
        }
    }
    if {[llength $reasons]} {
        set status PROVISIONAL_INCOMPLETE_BOARD_PROFILE
        return 0
    }
    foreach key {
        schema_version validated adc_reg16 adc_reg17 dac_reg16
    } {
        if {![string is integer -strict [dict get $profile $key]]} {
            error "Board timing field $key must be an integer"
        }
    }
    if {[dict get $profile schema_version] != 1} {
        error "Unsupported board timing profile schema"
    }
    # These values match the committed SPI tables. Re-review the model whenever
    # those tables change; a different phase setting must not silently pass.
    foreach {key expected} {adc_reg16 0 adc_reg17 133 dac_reg16 0} {
        if {[dict get $profile $key] != $expected} {
            error "Timing profile $key does not match the current SPI configuration ($expected)"
        }
    }
    foreach key {
        adc_period_ns dac_period_ns adc_data_lead_min_ns adc_data_lead_max_ns
        adc_board_skew_min_ns adc_board_skew_max_ns adc_margin_ns
        dac_board_skew_min_ns dac_board_skew_max_ns dac_margin_ns
    } {
        set value [dict get $profile $key]
        if {![string is double -strict $value] ||
            [catch {expr {abs(double($value)) < 1.0e6}} finite] || !$finite} {
            error "Board timing field $key must be a finite time in ns"
        }
    }
    foreach {key expected} {adc_period_ns 4.0 dac_period_ns 2.0} {
        if {abs([dict get $profile $key] - $expected) > 0.000001} {
            error "$key must match the current XDC clock period ($expected ns)"
        }
    }
    foreach {low high} {
        adc_data_lead_min_ns adc_data_lead_max_ns
        adc_board_skew_min_ns adc_board_skew_max_ns
        dac_board_skew_min_ns dac_board_skew_max_ns
    } {
        if {[dict get $profile $low] > [dict get $profile $high]} {
            error "Board timing range is reversed: $low > $high"
        }
    }
    foreach key {adc_margin_ns dac_margin_ns} {
        if {[dict get $profile $key] < 0} {
            error "$key must be nonnegative"
        }
    }
    # Evaluate even an unvalidated complete profile to reject impossible eyes.
    calculate_delays
    if {[dict get $profile validated] != 1} {
        set status PROVISIONAL_UNVALIDATED_BOARD_PROFILE
        set reasons [list {Board profile has not been validated against the actual hardware}]
        return 0
    }
    set status PROFILE_VALIDATED_AWAITING_STA
    return 1
}

proc ::power_kicker_io::calculate_delays {} {
    variable profile
    set adc_ui [expr {[dict get $profile adc_period_ns] / 2.0}]
    set dac_ui [expr {[dict get $profile dac_period_ns] / 2.0}]
    # A positive lead means ADC data changes BEFORE its sampling DCO edge.
    # Reference each transition to the preceding opposite DCO edge, so Vivado
    # sees a positive half-cycle launch-to-capture interval on both edges.
    set adc_min [expr {$adc_ui - [dict get $profile adc_data_lead_max_ns] +
        [dict get $profile adc_board_skew_min_ns] - [dict get $profile adc_margin_ns]}]
    set adc_max [expr {$adc_ui - [dict get $profile adc_data_lead_min_ns] +
        [dict get $profile adc_board_skew_max_ns] + [dict get $profile adc_margin_ns]}]
    if {$adc_min <= 0 || $adc_max >= $adc_ui || $adc_min > $adc_max} {
        error "ADC eye crosses its selected DCO edge; review hardware phase/delay (min=$adc_min max=$adc_max UI=$adc_ui)"
    }
    # AD9122 Rev C Table 13, register 0x16 = 0: tS=-0.05, tH=0.65.
    # Data and DCI launch on the SAME ODDR edge. Rebase BOTH output delays by
    # one UI so default opposite-edge DDR STA checks that same-edge word.
    # This avoids granting a spurious extra UI to the new I/Q word.
    set dac_max [expr {$dac_ui - 0.05 + [dict get $profile dac_board_skew_max_ns] +
        [dict get $profile dac_margin_ns]}]
    set dac_min [expr {$dac_ui - 0.65 + [dict get $profile dac_board_skew_min_ns] -
        [dict get $profile dac_margin_ns]}]
    if {$dac_max - $dac_min >= $dac_ui} {
        error "DAC setup/hold, PCB skew and uncertainty leave no valid DDR eye"
    }
    return [dict create adc_min $adc_min adc_max $adc_max \
        dac_min $dac_min dac_max $dac_max]
}

proc ::power_kicker_io::require_validated_profile {} {
    variable status
    variable reasons
    if {![load_profile]} {
        error "External I/O timing signoff blocked: $status; [join $reasons {; }]"
    }
    return $status
}

proc ::power_kicker_io::apply {} {
    variable profile
    variable status
    variable reasons
    # Use the primary source port: ODDRE1 expands into device primitives during
    # implementation, so a hard-coded .../u_dac_dci_oddr/C pin is not portable.
    # divide_by 1 follows the actual source->buffer->ODDR->OBUFDS clock path.
    set dci_source [get_ports fpga_clk_p]
    create_generated_clock -name dac_dci_forwarded -source $dci_source \
        -divide_by 1 [get_ports dac_dci_p]
    if {![load_profile]} {
        puts "WARNING: POWER_KICKER_IO_TIMING=$status; [join $reasons {; }]. Internal build only; ADC/DAC external timing is NOT signed off."
        return
    }
    foreach {name key} {adc_clk_p adc_period_ns fpga_clk_p dac_period_ns} {
        set actual [get_property PERIOD [get_clocks $name]]
        if {abs($actual - [dict get $profile $key]) > 0.000001} {
            error "Timing profile $key disagrees with active clock $name"
        }
    }
    set delays [calculate_delays]
    set adc_ports [get_ports {adc_data_p1[*] adc_data_n1[*]}]
    set dac_ports [get_ports {dac_data_p[*] dac_data_n[*] dac_frame_p dac_frame_n}]
    if {[llength $adc_ports] != 28 || [llength $dac_ports] != 34} {
        error "Unexpected ADC/DAC differential port count; review timing coverage"
    }
    set_input_delay -clock adc_clk_p -max [dict get $delays adc_max] $adc_ports
    set_input_delay -clock adc_clk_p -min [dict get $delays adc_min] $adc_ports
    set_input_delay -clock adc_clk_p -clock_fall -add_delay -max [dict get $delays adc_max] $adc_ports
    set_input_delay -clock adc_clk_p -clock_fall -add_delay -min [dict get $delays adc_min] $adc_ports
    set_output_delay -clock dac_dci_forwarded -max [dict get $delays dac_max] $dac_ports
    set_output_delay -clock dac_dci_forwarded -min [dict get $delays dac_min] $dac_ports
    set_output_delay -clock dac_dci_forwarded -clock_fall -add_delay -max [dict get $delays dac_max] $dac_ports
    set_output_delay -clock dac_dci_forwarded -clock_fall -add_delay -min [dict get $delays dac_min] $dac_ports
    set status CONSTRAINED_AWAITING_STA
    puts "INFO: POWER_KICKER_IO_TIMING=$status; board=[dict get $profile board_revision]; delays(ns)=$delays"
}

# Run after open_run impl_1 / route_design. This audits the constraints already
# in the routed design; it deliberately does NOT call apply or modify timing.
# require_signoff=1 turns provisional/failed coverage/slack into a Tcl error.
proc ::power_kicker_io::audit_routed_profile {report_dir {require_signoff 0}} {
    variable profile
    variable status
    variable reasons
    file mkdir $report_dir
    set summary_path [file join $report_dir adc_dac_io_status.txt]
    if {![load_profile]} {
        set fd [open $summary_path w]
        puts $fd "STATUS=$status"
        puts $fd "DETAIL=[join $reasons {; }]"
        puts $fd {External ADC/DAC timing is not signed off.}
        close $fd
        if {$require_signoff} {
            error "External I/O timing signoff blocked: $status"
        }
        return $status
    }
    set expected [calculate_delays]
    set failures {}
    set count 0
    set csv [open [file join $report_dir adc_dac_io_coverage.csv] w]
    puts $csv {interface,port,analysis,clock_edge,delay_ns,slack_ns,requirement_ns,status}
    # ADC differential timing is represented by the P pin in the DIFFINBUF
    # timing model; both polarities still have input-delay declarations.
    set adc_ports [get_ports {adc_data_p1[*]}]
    set dac_ports [get_ports {dac_data_p[*] dac_data_n[*] dac_frame_p dac_frame_n}]
    if {[llength $adc_ports] != 14 || [llength $dac_ports] != 34} {
        lappend failures {ADC/DAC port inventory does not match expected coverage}
    }
    foreach iface {adc dac} {
        set ports [expr {$iface eq {adc} ? $adc_ports : $dac_ports}]
        foreach port $ports {
            foreach kind {max min} {
                foreach edge {rise fall} {
                    if {$iface eq {adc}} {
                        set paths [get_timing_paths -quiet \
                            -${edge}_from [get_clocks adc_clk_p] -through $port \
                            -delay_type $kind -max_paths 1]
                        set delay_property INPUT_DELAY
                    } else {
                        set paths [get_timing_paths -quiet \
                            -from [get_clocks fpga_clk_p] -through $port \
                            -${edge}_to [get_clocks dac_dci_forwarded] \
                            -delay_type $kind -max_paths 1]
                        set delay_property OUTPUT_DELAY
                    }
                    incr count
                    set row_status PASS
                    if {[llength $paths] != 1} {
                        lappend failures "$iface $port $kind $edge: missing constrained path"
                        puts $csv "$iface,$port,$kind,$edge,,,,MISSING_PATH"
                        continue
                    }
                    set actual_delay [get_property $delay_property $paths]
                    set slack [get_property SLACK $paths]
                    set requirement [get_property REQUIREMENT $paths]
                    # Vivado timing path properties report to ps precision.
                    if {$actual_delay eq {} ||
                        abs($actual_delay - [dict get $expected ${iface}_${kind}]) > 0.0011} {
                        set row_status DELAY_MISMATCH
                        lappend failures "$iface $port $kind $edge: applied delay differs from profile"
                    }
                    if {$slack eq {} || $slack < 0} {
                        set row_status TIMING_FAILED
                        lappend failures "$iface $port $kind $edge: slack=$slack ns"
                    }
                    if {$iface eq {dac}} {
                        set edge_requirement [expr {$kind eq {max} ? 1.0 : 0.0}]
                        if {abs($requirement - $edge_requirement) > 0.0011} {
                            set row_status EDGE_MISMATCH
                            lappend failures "$iface $port $kind $edge: unexpected clock relationship"
                        }
                    }
                    puts $csv "$iface,$port,$kind,$edge,$actual_delay,$slack,$requirement,$row_status"
                }
            }
        }
    }
    close $csv
    foreach kind {max min} {
        report_timing -from $adc_ports -delay_type $kind -max_paths 28 -nworst 2 \
            -path_type full_clock_expanded -file [file join $report_dir adc_io_${kind}.rpt]
        report_timing -to $dac_ports -delay_type $kind -max_paths 68 -nworst 2 \
            -path_type full_clock_expanded -file [file join $report_dir dac_io_${kind}.rpt]
    }
    set status [expr {[llength $failures] ? {IO_STA_FAILED} : {IO_STA_PASSED}}]
    set fd [open $summary_path w]
    puts $fd "STATUS=$status"
    puts $fd "BOARD=[dict get $profile board_revision]"
    puts $fd "EVIDENCE=[dict get $profile evidence]"
    puts $fd "CHECKED_EDGE_PATHS=$count"
    puts $fd "FAILURES=[llength $failures]"
    puts $fd [join $failures \n]
    puts $fd {I/O STA does not replace CDC review or physical board validation.}
    close $fd
    puts "INFO: POWER_KICKER_IO_TIMING=$status; checked=$count; failures=[llength $failures]"
    if {$require_signoff && [llength $failures]} {
        error "ADC/DAC routed timing audit failed; see $summary_path"
    }
    return $status
}
