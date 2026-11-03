# Read-only design verification after moving the project; Vivado may normalize
# its XPR metadata on close. No synthesis, implementation, or board programming.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir project_manifest.tcl]
pk_assert_project_inputs
open_project [file join $script_dir $pk_project_name.xpr]
if {[get_property TOP [get_filesets sources_1]] ne {top_power_kicker}} {error {Wrong synthesis top}}
if {[get_property TOP [get_filesets sim_1]] ne {tb_control_regression}} {error {Wrong simulation top}}
if {[lsort [get_ips]] ne [lsort {clk_wiz_1 ila_1 vio_0 vio_pid}]} {error {Unexpected active IP set}}
set timing_file [get_files $pk_timing_entry]
if {[string toupper [get_property FILE_TYPE $timing_file]] ne {TCL} ||
    [get_property USED_IN_SYNTHESIS $timing_file] ||
    ![get_property USED_IN_IMPLEMENTATION $timing_file] ||
    [get_property PROCESSING_ORDER $timing_file] ne {LATE}} {
    error {Incorrect external timing constraint entry properties}
}
foreach name {synth_1 impl_1} {
    set status [get_property STATUS [get_runs $name]]
    puts "DELIVERY_RUN=$name STATUS=$status PROGRESS=[get_property PROGRESS [get_runs $name]] REFRESH=[get_property NEEDS_REFRESH [get_runs $name]]"
    if {![string match {*Complete*} $status]} {error "Incomplete delivered run: $name"}
    if {[get_property NEEDS_REFRESH [get_runs $name]]} {error "Delivered run marked stale: $name"}
}
open_run impl_1
if {[llength [get_clocks -quiet dac_dci_forwarded]] != 1} {error {DCI clock did not survive project relocation}}
set latches [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]
if {[llength $latches]} {error "Unexpected latches after relocation: $latches"}
foreach type {max min} {
    set path [get_timing_paths -delay_type $type -max_paths 1]
    set slack [get_property SLACK $path]
    puts "DELIVERY_${type}_SLACK=$slack"
    if {$slack < 0} {error "Negative delivered timing: $type"}
}
close_design
close_project
pk_assert_project_inputs
puts {DELIVERY_OPEN=PASS}
