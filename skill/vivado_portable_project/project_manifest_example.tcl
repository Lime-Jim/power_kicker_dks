# Example from power_kicker_dks. Lines after '# 修改此处' must be adapted to your project.
# Canonical active sources. Legacy ROMs/UART command parser remain on disk only.
set pk_project_dir [file dirname [file normalize [info script]]]
# 修改此处 ↓
set pk_project_name power-kicker-fast-feedback-v1
# 修改此处 ↓
set pk_rtl_names {
    ad9122_config ad9516_config ad9643_config control key_filter capture_phase_status
    pd_adc_capture pd_pid_feedback pid_core_signed reset_sync
    spi_config spi_config8 spi_config8r spi_config_top
    spi_master spi_master8 spi_st spi_st8
    test_ad9122 test_ad9643 top_test uart_rx uart_tx
    uart_power_kick_params top_power_kicker
}
set pk_design_files {}
foreach name $pk_rtl_names {
    lappend pk_design_files [file join $pk_project_dir $pk_project_name.srcs sources_1 new $name.v]
}
# 修改此处 ↓
set pk_ip_files [list \
    [file join $pk_project_dir $pk_project_name.srcs sources_1 ip clk_wiz_1.xcix] \
    [file join $pk_project_dir $pk_project_name.srcs sources_1 ip ila_1.xcix] \
    [file join $pk_project_dir $pk_project_name.srcs sources_1 ip ila_adc.xcix] \
    [file join $pk_project_dir $pk_project_name.srcs sources_1 ip ila_capture.xcix] \
    [file join $pk_project_dir $pk_project_name.srcs sources_1 ip vio_0 vio_0.xci] \
    [file join $pk_project_dir $pk_project_name.srcs sources_1 ip vio_pid vio_pid.xci]]
# 修改此处 ↓
set pk_xdc [file join $pk_project_dir $pk_project_name.srcs constrs_1 new kicker.xdc]
# 修改此处 ↓
set pk_timing_entry [file join $pk_project_dir constraints load_external_timing.tcl]
# 修改此处 ↓
set pk_sim_top [file join $pk_project_dir tests tb_control_regression.sv]
# 修改此处 ↓
set pk_aux_files [list [file join $pk_project_dir constraints adc_dac_io_timing.tcl]]

proc pk_assert_project_inputs {} {
    global pk_design_files pk_ip_files pk_xdc pk_sim_top pk_project_dir pk_project_name pk_aux_files pk_timing_entry
    foreach path [concat $pk_design_files $pk_ip_files $pk_aux_files [list $pk_xdc $pk_sim_top $pk_timing_entry]] {
        if {![file isfile $path]} { error "Required source is missing: $path" }
    }
    set fd [open [file join $pk_project_dir $pk_project_name.xpr] r]
    set xml [read $fd]
    close $fd
    foreach path [concat $pk_design_files $pk_ip_files [list $pk_xdc $pk_sim_top $pk_timing_entry]] {
        set relative [string range $path [expr {[string length $pk_project_dir] + 1}] end]
        set portable [string map [list "$pk_project_name.srcs/" {$PSRCDIR/}] $relative]
        if {$portable eq $relative} { set portable "\$PPRDIR/$relative" }
        if {[string first "<File Path=\"$portable\"" $xml] < 0} {
            error "Canonical source not referenced by XPR: $portable. Run recreate_project.tcl."
        }
    }
    # Check file references, not Vivado's harmless historical Project Path field.
    foreach {whole path} [regexp -all -inline {<File Path="([^"]+)"} $xml] {
        if {[string match {*../*} $path] || [string match {*$PGENDIR*} $path] ||
            [string match {*/synth/*.v} $path] || [string match {*/hdl/*.v} $path]} {
            error "Stale/generated source reference in XPR: $path. Run recreate_project.tcl with the GUI project closed."
        }
        if {![string match {$PSRCDIR/*} $path] && ![string match {$PPRDIR/*} $path]} {
            error "Non-portable source reference in XPR: $path"
        }
    }
    if {[string first XSimWcfgFile $xml] >= 0} {
        error "Unexpected waveform configuration reference in XPR"
    }
# 修改此处 ↓
    foreach name {Triangle_rom sin_rom square_rom ila_0} {
        if {[regexp "<FileSet Name=\"$name\"" $xml]} {
            error "Inactive legacy IP is back in the project: $name"
        }
    }
    puts "PROJECT_INPUTS=PASS (portable sources, no legacy/generated duplicates)"
}

proc pk_configure_project {} {
    global pk_timing_entry
    set_property top top_power_kicker [get_filesets sources_1]
    set_property top_auto_set false [get_filesets sim_1]
    set_property top tb_control_regression [get_filesets sim_1]
    set_property xsim.simulate.runtime all [get_filesets sim_1]
    set timing_file [get_files $pk_timing_entry]
    set_property FILE_TYPE Tcl $timing_file
    set_property USED_IN_SYNTHESIS false $timing_file
    set_property USED_IN_SIMULATION false $timing_file
    set_property USED_IN_IMPLEMENTATION true $timing_file
    set_property PROCESSING_ORDER LATE $timing_file
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
}

