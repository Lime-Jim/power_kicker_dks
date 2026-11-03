# Integration smoke test reproducing generated implementation-run semantics.
# Uses the project's existing synthesis checkpoint and OOC IP; no P&R, XPR save,
# board profile generation, or hardware programming.
set ::power_kicker_loader_test_root [file normalize [file join [file dirname [info script]] ..]]
set ::power_kicker_loader_test_dcp [file join $::power_kicker_loader_test_root \
    power-kicker-fast-feedback-v1.runs synth_1 top_power_kicker.dcp]
if {![file isfile $::power_kicker_loader_test_dcp]} {error {Synthesis checkpoint required}}
create_project -in_memory -part xcau15p-ffvb676-2-i
set_property design_mode GateLvl [current_fileset]
add_files -quiet $::power_kicker_loader_test_dcp
foreach name {vio_0 clk_wiz_1 ila_1 vio_pid} {
    read_ip -quiet [file join $::power_kicker_loader_test_root \
        power-kicker-fast-feedback-v1.srcs sources_1 ip $name ${name}.xci]
}
read_xdc [file join $::power_kicker_loader_test_root \
    power-kicker-fast-feedback-v1.srcs constrs_1 new kicker.xdc]
set ::power_kicker_loader_test_entry [file join $::power_kicker_loader_test_root \
    constraints load_external_timing.tcl]
read_xdc -unmanaged $::power_kicker_loader_test_entry
set_property PROCESSING_ORDER LATE [get_files $::power_kicker_loader_test_entry]
link_design -top top_power_kicker -part xcau15p-ffvb676-2-i
if {[llength [get_clocks -quiet dac_dci_forwarded]] != 1} {
    error {Loader failed to create DAC forwarded clock in actual constraints-set context}
}
if {[get_property PERIOD [get_clocks dac_dci_forwarded]] != 2.0} {
    error {DAC forwarded-clock period is incorrect}
}
if {[llength [info commands ::power_kicker_io::apply]] != 1} {
    error {External timing library was not loaded}
}
set expected_dir [file normalize [file join $::power_kicker_loader_test_root constraints]]
if {[file normalize $::power_kicker_io::script_dir] ne $expected_dir} {
    error "Loader resolved wrong profile directory: $::power_kicker_io::script_dir"
}
puts "CONSTRAINT_LOADER_STATUS=$::power_kicker_io::status"
report_clocks
puts {PASS: check_constraint_loader_vivado (registered unmanaged Tcl + link_design)}
close_project
exit
