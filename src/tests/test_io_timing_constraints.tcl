# Pure Tcl regression of equations and coverage; synthetic values below are
# TEST FIXTURES, never a board profile and never evidence of hardware timing.
source [file join [file dirname [info script]] .. constraints adc_dac_io_timing.tcl]
proc check {condition message} {
    if {![uplevel 1 [list expr $condition]]} {error "FAIL: $message"}
}
proc close_to {actual expected} {
    check {abs($actual - $expected) < 1.0e-9} "Expected $expected, got $actual"
}
set had_profile_env [info exists ::env(POWER_KICKER_BOARD_TIMING)]
if {$had_profile_env} {set saved_profile_env $::env(POWER_KICKER_BOARD_TIMING)}
set ::env(POWER_KICKER_BOARD_TIMING) [file join [file dirname [info script]] \
    __intentionally_missing_board_profile_for_test__.tcl]
check {![file exists $::env(POWER_KICKER_BOARD_TIMING)]} {Missing-profile fixture must not exist}
check {![::power_kicker_io::load_profile]} {Absent board profile must be provisional}
check {[catch {::power_kicker_io::require_validated_profile}]} {Signoff must reject an absent board profile}
if {$had_profile_env} {
    set ::env(POWER_KICKER_BOARD_TIMING) $saved_profile_env
} else {unset ::env(POWER_KICKER_BOARD_TIMING)}
set fixture [dict create schema_version 1 validated 1 board_revision UNIT_TEST_ONLY \
    evidence {Synthetic test values; NOT board evidence} \
    adc_reg16 0 adc_reg17 133 dac_reg16 0 adc_period_ns 4.0 dac_period_ns 2.0 \
    adc_data_lead_min_ns 1.0 adc_data_lead_max_ns 1.6 \
    adc_board_skew_min_ns -0.05 adc_board_skew_max_ns 0.05 adc_margin_ns 0.05 \
    dac_board_skew_min_ns -0.05 dac_board_skew_max_ns 0.05 dac_margin_ns 0.05]
set ::power_kicker_io::profile $fixture
check {[::power_kicker_io::validate_profile]} {Complete profile must validate}
set delays [::power_kicker_io::calculate_delays]
foreach {key value} {adc_min 0.3 adc_max 1.1 dac_min 0.25 dac_max 1.05} {
    close_to [dict get $delays $key] $value
}
# Derived DAC bounds use the SAME launch edge: upper skew=-tS, lower=tH-UI.
# Zero board skew/margin therefore permits -0.35 <= FPGA data-DCI <= +0.05.
foreach key {dac_board_skew_min_ns dac_board_skew_max_ns dac_margin_ns} {
    dict set ::power_kicker_io::profile $key 0
}
set delays [::power_kicker_io::calculate_delays]
close_to [expr {1.0 - [dict get $delays dac_max]}] 0.05
close_to [expr {-[dict get $delays dac_min]}] -0.35
foreach {field value} {
    schema_version 2 adc_reg16 128 adc_reg17 0 dac_reg16 1
    adc_period_ns 5 dac_period_ns 4 adc_margin_ns -0.1
    adc_data_lead_max_ns 2.1 dac_margin_ns 0.3
} {
    set ::power_kicker_io::profile $fixture
    dict set ::power_kicker_io::profile $field $value
    check {[catch {::power_kicker_io::validate_profile}]} "Invalid $field must fail"
}
set ::power_kicker_io::profile $fixture
dict set ::power_kicker_io::profile validated 0
check {![::power_kicker_io::validate_profile]} {Unvalidated profile must be provisional}
dict unset ::power_kicker_io::profile adc_board_skew_min_ns
check {![::power_kicker_io::validate_profile]} {Missing value must remain provisional}
# Mock Vivado commands to verify both differential buses and all four DDR
# min/max/rising/falling constraints. Actual Vivado STA remains a separate gate.
set commands {}
proc get_pins {args} {return u_hw/u_dac/u_dac_dci_oddr/C}
proc get_ports {patterns} {
    set result {}
    foreach pattern $patterns {
        if {[string match adc_data* $pattern]} {
            for {set i 0} {$i < 14} {incr i} {lappend result ${pattern}_$i}
        } elseif {[string match dac_data* $pattern]} {
            for {set i 0} {$i < 16} {incr i} {lappend result ${pattern}_$i}
        } else {lappend result $pattern}
    }
    return $result
}
proc get_clocks {name} {return $name}
proc get_property {property object} {
    if {$object eq {adc_clk_p}} {return 4.0}
    return 2.0
}
foreach command {create_generated_clock set_input_delay set_output_delay} {
    proc $command {args} "lappend ::commands \[linsert \$args 0 $command\]"
}
rename ::power_kicker_io::load_profile ::power_kicker_io::load_profile_real
proc ::power_kicker_io::load_profile {} {
    variable profile
    set profile $::fixture
    return [validate_profile]
}
::power_kicker_io::apply
check {[llength $commands] == 9} {Expected one clock and eight delay constraints}
set inputs 0
set outputs 0
set falling 0
foreach command $commands {
    if {[lindex $command 0] eq {set_input_delay}} {
        incr inputs
        check {[llength [lindex $command end]] == 28} {ADC differential coverage}
    }
    if {[lindex $command 0] eq {set_output_delay}} {
        incr outputs
        check {[llength [lindex $command end]] == 34} {DAC data plus FRAME coverage}
    }
    if {{-clock_fall} in $command} {
        incr falling
        check {{-add_delay} in $command} {Falling edge must preserve rising constraints}
    }
}
check {$inputs == 4 && $outputs == 4 && $falling == 4} {DDR min/max coverage}
check {$::power_kicker_io::status eq {CONSTRAINED_AWAITING_STA}} {No false signoff status}
puts {PASS: test_io_timing_constraints (missing-profile gate, equations, validation, DDR coverage)}
