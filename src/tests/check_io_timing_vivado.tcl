# Diagnostic only: apply SYNTHETIC parameters to a read-only routed checkpoint.
# Does not save a design or create a board profile. A failing slack is expected
# to be possible; this test checks the model/edge relationship, not board signoff.
if {[llength $argv] != 1} {error {Usage: check_io_timing_vivado.tcl routed_checkpoint.dcp}}
set ::power_kicker_io_diagnostic_root [file normalize [file join [file dirname [info script]] ..]]
puts "IO_DIAG_ROOT=$::power_kicker_io_diagnostic_root"
open_checkpoint [lindex $argv 0]
source [file join $::power_kicker_io_diagnostic_root constraints adc_dac_io_timing.tcl]
rename ::power_kicker_io::load_profile ::power_kicker_io::load_profile_real
proc ::power_kicker_io::load_profile {} {
    variable profile
    set profile [dict create schema_version 1 validated 1 board_revision SYNTHETIC_STA_TEST \
        evidence {Synthetic test only; NOT board evidence} \
        adc_reg16 0 adc_reg17 133 dac_reg16 0 adc_period_ns 4.0 dac_period_ns 2.0 \
        adc_data_lead_min_ns 1.0 adc_data_lead_max_ns 1.6 \
        adc_board_skew_min_ns 0 adc_board_skew_max_ns 0 adc_margin_ns 0 \
        dac_board_skew_min_ns 0 dac_board_skew_max_ns 0 dac_margin_ns 0]
    return [validate_profile]
}
::power_kicker_io::apply
puts {DIAGNOSTIC ONLY: synthetic zero PCB skew/uncertainty, not hardware signoff}
report_clocks
foreach kind {max min} {
    puts "ADC_$kind"
    report_timing -from [get_ports {adc_data_p1[*]}] -delay_type $kind \
        -path_type full_clock_expanded -max_paths 2 -nworst 2
    puts "DAC_$kind"
    report_timing -to [get_ports {dac_data_p[*] dac_frame_p}] -delay_type $kind \
        -path_type full_clock_expanded -max_paths 4 -nworst 4
    set paths [get_timing_paths -to [get_ports {dac_data_p[*]}] \
        -delay_type $kind -max_paths 1]
    if {[llength $paths] != 1} {error "No DAC $kind timing path"}
    set requirement [get_property REQUIREMENT $paths]
    set expected [expr {$kind eq {max} ? 1.0 : 0.0}]
    if {abs($requirement - $expected) > 0.000001} {
        error "Unexpected DAC $kind clock-edge requirement: $requirement, expected $expected"
    }
}
set ::power_kicker_io_diagnostic_reports [file join $::power_kicker_io_diagnostic_root \
    verification io_timing_synthetic_sta]
::power_kicker_io::audit_routed_profile $::power_kicker_io_diagnostic_reports 0
set fd [open [file join $::power_kicker_io_diagnostic_reports adc_dac_io_coverage.csv] r]
set coverage [read $fd]
close $fd
if {[regexp {MISSING_PATH|DELAY_MISMATCH|EDGE_MISMATCH} $coverage]} {
    error {Synthetic constraint coverage/model mismatch; inspect CSV}
}
puts {PASS: Vivado accepted DDR constraints and expected edge relationships}
close_design
exit
