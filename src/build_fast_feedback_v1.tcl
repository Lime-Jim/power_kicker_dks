set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir project_manifest.tcl]
pk_assert_project_inputs
set require_signoff [expr {[lsearch -exact $argv --signoff] >= 0}]
set implementation_only [expr {[lsearch -exact $argv --implementation-only] >= 0}]
set routed_only [expr {[lsearch -exact $argv --routed-only] >= 0}]
if {$require_signoff} {
    source [file join $script_dir constraints adc_dac_io_timing.tcl]
    ::power_kicker_io::require_validated_profile
}
set xpr [file join $script_dir power-kicker-fast-feedback-v1.xpr]
if {![file exists $xpr]} {
    error "Experiment project not found: $xpr"
}

open_project $xpr
puts "PROJECT=[current_project]"
puts "PART=[get_property PART [current_project]]"
set_property top top_power_kicker [current_fileset]
pk_configure_project
puts "TOP=[get_property top [current_fileset]]"
puts "IPS=[get_ips]"

update_compile_order -fileset sources_1
report_ip_status
generate_target all [get_ips]
foreach ip [get_ips] {
    set ip_file [get_files [get_property IP_FILE $ip]]
    if {[get_property GENERATE_SYNTH_CHECKPOINT $ip_file] &&
        [llength [get_runs -quiet ${ip}_synth_1]] == 0} {
        create_ip_run $ip_file
    }
}

if {$implementation_only || $routed_only} {
    if {![string match {*Complete*} [get_property STATUS [get_runs synth_1]]] ||
        [get_property NEEDS_REFRESH [get_runs synth_1]]} {
        error "Cannot reuse synthesis: incomplete or stale. Run a full build."
    }
    puts "SYNTH_REUSE=PASS (completed, not stale)"
} else {
    reset_run synth_1
    launch_runs synth_1 -jobs 1
    wait_on_run synth_1
}
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
puts "SYNTH_PROGRESS=[get_property PROGRESS [get_runs synth_1]]"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed: $synth_status"
}

if {$routed_only} {
    if {![string match {*route_design Complete*} [get_property STATUS [get_runs impl_1]]] ||
        [get_property NEEDS_REFRESH [get_runs impl_1]]} {
        error "Cannot reuse routing: incomplete or stale. Run a full build."
    }
    puts "ROUTE_REUSE=PASS (completed, not stale)"
} else {
    reset_run impl_1
    launch_runs impl_1 -to_step route_design -jobs 1
    wait_on_run impl_1
}
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
puts "IMPL_PROGRESS=[get_property PROGRESS [get_runs impl_1]]"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation failed: $impl_status"
}

open_run impl_1
# Debug trigger comparators contain very short paths. Repair hold physically,
# with all original timing constraints intact, then route any modified nets.
phys_opt_design -aggressive_hold_fix
route_design
set report_dir [file join $script_dir verification implementation]
file mkdir $report_dir
source [file join $script_dir constraints adc_dac_io_timing.tcl]
set io_status [::power_kicker_io::audit_routed_profile $report_dir $require_signoff]
puts "ADC_DAC_IO_STATUS=$io_status"
if {$io_status eq {IO_STA_FAILED}} {
    error "A supplied board profile failed I/O timing or coverage; see $report_dir"
}
if {[llength [get_clocks -quiet dac_dci_forwarded]] != 1} {
    error "Forwarded DCI clock missing: external Tcl constraints did not load"
}
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report_dir timing_summary.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]
report_methodology -file [file join $report_dir methodology.rpt]
report_drc -file [file join $report_dir drc.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
set latch_cells [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]
puts "LATCH_COUNT=[llength $latch_cells]"
if {[llength $latch_cells]} { error "Unexpected inferred latches: $latch_cells" }
foreach delay_type {max min} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1 -nworst 1]
    if {![llength $paths]} { error "No $delay_type timing paths found" }
    set slack [get_property SLACK [lindex $paths 0]]
    puts "WORST_${delay_type}_SLACK=$slack"
    if {$slack < 0.0} { error "Routed $delay_type timing failed: $slack ns; see $report_dir" }
}
puts "INTERNAL_TIMING=PASS; consult TIMING_CONSTRAINTS.md for external I/O status"
# The managed write_bitstream step reopens this checkpoint. Persist the exact
# physically repaired and verified design before handing it back to the run.
write_checkpoint -force [file join $script_dir power-kicker-fast-feedback-v1.runs impl_1 top_power_kicker_routed.dcp]
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*write_bitstream Complete*" $impl_status]} {
    error "Bitstream generation failed: $impl_status"
}
puts "IMPL_STATUS=$impl_status"

set bit_candidates [glob -nocomplain [file join $script_dir power-kicker-fast-feedback-v1.runs impl_1 *.bit]]
puts "BIT_CANDIDATES=$bit_candidates"

close_project
pk_assert_project_inputs
