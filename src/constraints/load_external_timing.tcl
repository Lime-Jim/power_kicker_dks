# Add to constrs_1 with FILE_TYPE=Tcl, USED_IN_SYNTHESIS=false,
# USED_IN_IMPLEMENTATION=true, PROCESSING_ORDER=LATE. Vivado sources Tcl
# constraint files after managed XDC (including the clock-wizard IP clocks).
namespace eval ::power_kicker_constraint_loader {
    # Unmanaged constraint evaluation happens inside the implementation driver:
    # [info script] can name .runs/impl_1/top_power_kicker.tcl, NOT this file.
    # The registry is authoritative in both generated run scripts and open_run.
    set files [get_files -all -quiet *load_external_timing.tcl]
    if {[llength $files] != 1} {
        error "Expected one registered external-timing loader, got: $files"
    }
    set directory [file dirname [get_property NAME $files]]
    set library [file join $directory adc_dac_io_timing.tcl]
    if {![file isfile $library]} {error "Missing external-timing library: $library"}
    source $library
    # Pin the profile location to the same registry path even if Vivado changes
    # the source evaluator's [info script] behavior in a different run context.
    set ::power_kicker_io::script_dir $directory
    ::power_kicker_io::apply
    set logic_clocks [get_clocks -quiet -include_generated_clocks clk_out1_clk_wiz_1]
    set dac_clocks [get_clocks -quiet -include_generated_clocks fpga_clk_p]
    set adc_clocks [get_clocks -quiet -include_generated_clocks adc_clk_p]
    if {[llength $logic_clocks] == 0 || [llength $dac_clocks] == 0 ||
        [llength $adc_clocks] == 0} {
        error {Missing logic/ADC/DAC clock when loading external timing constraints}
    }
    set_clock_groups -name power_kicker_async_domains -asynchronous \
        -group $logic_clocks -group $dac_clocks -group $adc_clocks
    puts "INFO: POWER_KICKER_CONSTRAINT_LOADER=$library"
    unset files directory library logic_clocks dac_clocks adc_clocks
}
