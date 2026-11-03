set script_dir [file dirname [info script]]
set last_value_file [file join $script_dir last_vio_parameters_v2.tcl]
set legacy_last_value_file [file join $script_dir last_vio_parameters.tcl]
set default_bit_file [file normalize [file join $script_dir power-kicker-fast-feedback-v1.runs impl_1 top_power_kicker.bit]]
set default_ltx_file [file normalize [file join $script_dir power-kicker-fast-feedback-v1.runs impl_1 top_power_kicker.ltx]]

set default_control_values {vio_auto_sweep_enable 0 vio_auto_sweep_freq_Hz 50 vio_kick_base_mV 1000 vio_kick_min_mV 500 vio_kick_fall_ns 10000 vio_kick_rise_ns 100 vio_sweep_start_mV 0 vio_sweep_final_mV 1500 vio_sweep_trigger_mV 1500 vio_sweep_scan_us 10000}
set default_pid_values {vio_pid_feedback_enable 0 vio_pid_target_mV 133 vio_pid_window_mV 10 vio_pid_ki 8 vio_pid_kd 0 vio_pid_kp 256 vio_pid_clear 0 vio_pid_confirm_samples 1 vio_pid_corr_limit 1000 vio_pid_start_delay_ns 200 vio_pid_require_window 1}

set control_probe_order [list \
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

set pid_probe_order [list \
    vio_pid_feedback_enable \
    vio_pid_target_mV \
    vio_pid_window_mV \
    vio_pid_ki \
    vio_pid_kd \
    vio_pid_kp \
    vio_pid_clear \
    vio_pid_confirm_samples \
    vio_pid_corr_limit \
    vio_pid_start_delay_ns \
    vio_pid_require_window \
]

set pid_status_probe_order [list \
    vio_pid_locked \
]

# Saved files use canonical decimal integers. Older unsigned decimal encodings
# of signed 16-bit probes (e.g. 65535 for -1) remain accepted on restore.
proc _pk_probe_is_signed {probe_name} {
    return [expr {$probe_name in {vio_pid_target_mV vio_pid_kp vio_pid_ki vio_pid_kd}}]
}

proc _pk_parse_integer {value {radix DECIMAL}} {
    set value [string trim $value]
    set radix [string toupper $radix]
    if {[regexp {^[+-]?[0-9]+$} $value] && $radix in {DECIMAL SIGNED UNSIGNED}} {
        set sign 1
        if {[string index $value 0] eq "-"} { set sign -1 }
        set value [string trimleft $value +-]
        set number 0
        foreach digit [split $value {}] { set number [expr {$number * 10 + $digit}] }
        return [expr {$sign * $number}]
    }
    if {$radix in {HEX HEXADECIMAL} || [regexp -nocase {^0x} $value]} {
        regsub -nocase {^0x} $value {} value
        if {![regexp {^[0-9a-fA-F]+$} $value]} { error "Invalid hexadecimal VIO value: $value" }
        set number 0
        foreach digit [split [string tolower $value] {}] {
            set number [expr {$number * 16 + [string first $digit 0123456789abcdef]}]
        }
        return $number
    }
    if {$radix in {BIN BINARY}} {
        regsub -nocase {^0b} $value {} value
        if {![regexp {^[01]+$} $value]} { error "Invalid binary VIO value: $value" }
        set number 0
        foreach bit [split $value {}] { set number [expr {$number * 2 + $bit}] }
        return $number
    }
    error "Invalid $radix VIO integer: $value"
}

proc _pk_normalize_probe_value {probe_name value {radix DECIMAL}} {
    set number [_pk_parse_integer $value $radix]
    if {[_pk_probe_is_signed $probe_name]} {
        if {$number < -32768 || $number > 65535} { error "$probe_name is outside signed 16-bit range: $value" }
        if {$number > 32767} { set number [expr {$number - 65536}] }
    } elseif {$number < 0} {
        error "$probe_name is unsigned: $value"
    }
    if {$probe_name eq "vio_pid_start_delay_ns" && $number > 4294967295} {
        error "$probe_name is outside unsigned 32-bit range: $value"
    }
    if {$probe_name eq "vio_pid_require_window" && $number > 1} {
        error "$probe_name must be 0 or 1: $value"
    }
    return $number
}

proc _pk_probe_name_matches {actual expected} {
    return [expr {$actual eq $expected || [string match "*/$expected" $actual]}]
}

proc _pk_prepare_hw {} {
    global default_ltx_file
    catch {open_hw_manager}
    if {[llength [get_hw_servers -quiet]] == 0} {
        catch {connect_hw_server -url 127.0.0.1:3121 -cs_url TCP:127.0.0.1:3042}
    }
    set open_targets [get_hw_targets -quiet -filter {IS_OPEN==1}]
    if {[llength $open_targets] == 0} {
        set targets [get_hw_targets -quiet]
        if {[llength $targets] != 0} {
            catch {open_hw_target [lindex $targets 0]}
        }
    }
    foreach dev [get_hw_devices -quiet] {
        if {[file exists $default_ltx_file]} {
            catch {set_property PROBES.FILE $default_ltx_file $dev}
        }
        catch {refresh_hw_device $dev}
    }
}

proc pk_program_device {{bit_file ""} {ltx_file ""}} {
    global default_bit_file default_ltx_file
    _pk_prepare_hw
    if {$bit_file eq ""} {
        set bit_file $default_bit_file
    }
    if {$ltx_file eq ""} {
        set ltx_file $default_ltx_file
    }
    if {![file exists $bit_file]} {
        puts "ERROR: Bit file not found: $bit_file"
        return
    }
    if {![file exists $ltx_file]} {
        puts "WARNING: LTX probes file not found: $ltx_file"
    }
    set devices [get_hw_devices -quiet]
    if {[llength $devices] == 0} {
        puts "ERROR: No hardware device found. Connect target first."
        return
    }
    set dev [lindex $devices 0]
    set_property PROGRAM.FILE $bit_file $dev
    if {[file exists $ltx_file]} {
        set_property PROBES.FILE $ltx_file $dev
    }
    program_hw_devices $dev
    refresh_hw_device $dev
    puts "Programmed $dev"
    puts "BIT: $bit_file"
    if {[file exists $ltx_file]} {
        puts "LTX: $ltx_file"
    }
    pk_restore_last_vio_parameters
}

proc _pk_probe_exists {vio probe_name} {
    return [expr {[_pk_get_probe $vio $probe_name] ne ""}]
}

proc _pk_find_vio {cell_name fallback_pattern {probe_names {}}} {
    foreach vio [get_hw_vios -quiet] {
        set cell [get_property CELL_NAME $vio]
        if {[_pk_probe_name_matches $cell $cell_name]} { return $vio }
    }
    if {[llength $probe_names] != 0} {
        set best_vio ""
        set best_count 0
        foreach vio [get_hw_vios -quiet] {
            set count 0
            foreach probe_name $probe_names {
                if {[_pk_probe_exists $vio $probe_name]} {
                    incr count
                }
            }
            if {$count > $best_count} {
                set best_count $count
                set best_vio $vio
            }
            if {$count == [llength $probe_names]} {
                return $vio
            }
        }
        if {$best_count > 0} {
            return $best_vio
        }
    }
    # Hardware Manager hw_vio_N numbering is not a stable core identity.
    # Keep fallback_pattern in the procedure signature for existing callers,
    # but never select an unrecognized core just because its number matches.
    return ""
}

proc _pk_get_probe {vio probe_name} {
    if {$vio eq ""} {
        return ""
    }
    foreach probe [get_hw_probes -quiet -of_objects $vio] {
        if {[_pk_probe_name_matches [get_property NAME $probe] $probe_name]} {
            return $probe
        }
    }
    return ""
}

proc _pk_set_decimal_radix {vio probe_names} {
    foreach probe_name $probe_names {
        set probe [_pk_get_probe $vio $probe_name]
        if {$probe ne ""} {
            set radix [expr {[_pk_probe_is_signed $probe_name] ? "SIGNED" : "UNSIGNED"}]
            if {$probe_name eq "vio_pid_locked"} {
                catch {set_property INPUT_VALUE_RADIX UNSIGNED $probe}
            } else {
                set_property OUTPUT_VALUE_RADIX $radix $probe
            }
            catch {set_property DISPLAY_RADIX $radix $probe}
        }
    }
}

proc _pk_check_expected_probes {vio probe_names label} {
    global power_kicking_vio_restore_had_errors
    if {$vio eq ""} {
        return
    }
    set missing {}
    foreach probe_name $probe_names {
        if {![_pk_probe_exists $vio $probe_name]} {
            lappend missing $probe_name
        }
    }
    if {[llength $missing] != 0} {
        set power_kicking_vio_restore_had_errors 1
        puts "ERROR: $label VIO is missing expected probes: $missing"
        puts "ERROR: The programmed bitstream and/or probes .ltx file is old or mismatched."
        puts "ERROR: Build with build_fast_feedback_v1.tcl, then program with matching top_power_kicker.bit and top_power_kicker.ltx files."
    }
}

proc _pk_restore_values {vio probe_names value_list label} {
    global power_kicking_vio_restore_had_errors
    catch {array unset saved_values}
    array set saved_values $value_list
    if {$label eq "PID" && ![info exists saved_values(vio_pid_require_window)]} {
        # Preserve the legacy PD qualification for older parameter files.
        set saved_values(vio_pid_require_window) 1
    }
    if {$label eq "PID" && ![info exists saved_values(vio_pid_start_delay_ns)]} {
        # Old save files predate the independent delay. Use a fixed default;
        # never derive PID timing from the current kick fall setting.
        set saved_values(vio_pid_start_delay_ns) 200
    }
    if {$label eq "control" && ![info exists saved_values(vio_kick_fall_ns)] && [info exists saved_values(vio_kick_fall_us)]} {
        set saved_values(vio_kick_fall_ns) [expr {$saved_values(vio_kick_fall_us) * 1000}]
    }
    if {$label eq "control" && ![info exists saved_values(vio_kick_rise_ns)] && [info exists saved_values(vio_kick_rise_us)]} {
        set saved_values(vio_kick_rise_ns) $saved_values(vio_kick_rise_us)
    }
    set probes_to_commit {}
    foreach probe_name $probe_names {
        if {![info exists saved_values($probe_name)]} {
            continue
        }
        set probe [_pk_get_probe $vio $probe_name]
        if {$probe eq ""} {
            puts "WARNING: Missing $label probe $probe_name"
            set power_kicking_vio_restore_had_errors 1
            continue
        }
        set radix [expr {[_pk_probe_is_signed $probe_name] ? "SIGNED" : "UNSIGNED"}]
        if {[catch {
            set value [_pk_normalize_probe_value $probe_name $saved_values($probe_name)]
            set_property OUTPUT_VALUE_RADIX $radix $probe
            set_property OUTPUT_VALUE $value $probe
        } err]} {
            set power_kicking_vio_restore_had_errors 1
            puts "WARNING: Could not restore $label probe $probe_name = $saved_values($probe_name). $err"
            puts "WARNING: Check the value and VIO width/order. Rebuild with build_fast_feedback_v1.tcl and load the matching bitstream/LTX if needed."
            continue
        }
        lappend probes_to_commit $probe
    }
    if {[llength $probes_to_commit] != 0} {
        commit_hw_vio $probes_to_commit
        catch {refresh_hw_vio $vio}
    }
}

proc pk_restore_last_vio_parameters {} {
    global last_value_file control_probe_order pid_probe_order pid_status_probe_order default_control_values default_pid_values power_kicking_vio_restore_had_errors power_kicking_vio_missing
    set power_kicking_vio_restore_had_errors 0
    set power_kicking_vio_missing 0
    _pk_prepare_hw
    set control_vio [_pk_find_vio u_vio_control *hw_vio_2* $control_probe_order]
    set pid_vio [_pk_find_vio u_vio_pid *hw_vio_1* $pid_probe_order]

    if {$control_vio eq ""} {
        puts "WARNING: Control VIO was not found. Open Hardware Manager, connect target, and program the FPGA first."
        set power_kicking_vio_restore_had_errors 1
        set power_kicking_vio_missing 1
    }
    if {$pid_vio eq ""} {
        puts "WARNING: PID VIO was not found. Open Hardware Manager, connect target, and program the FPGA first."
        set power_kicking_vio_restore_had_errors 1
        set power_kicking_vio_missing 1
    }

    _pk_set_decimal_radix $control_vio $control_probe_order
    _pk_set_decimal_radix $pid_vio $pid_probe_order
    _pk_set_decimal_radix $pid_vio $pid_status_probe_order
    _pk_check_expected_probes $control_vio $control_probe_order control
    _pk_check_expected_probes $pid_vio $pid_probe_order PID
    _pk_check_expected_probes $pid_vio $pid_status_probe_order "PID status"

    if {![file exists $last_value_file]} {
        puts "No saved VIO parameter file yet. Current values were left unchanged."
        return
    }

    set saved_control_values {}
    set saved_pid_values {}
    source $last_value_file

    if {[llength $saved_control_values] == 0} {
        set saved_control_values $default_control_values
    }
    if {[llength $saved_pid_values] == 0} {
        set saved_pid_values $default_pid_values
    }

    if {$control_vio ne "" && [llength $saved_control_values] != 0} {
        _pk_restore_values $control_vio $control_probe_order $saved_control_values control
    }
    if {$pid_vio ne "" && [llength $saved_pid_values] != 0} {
        _pk_restore_values $pid_vio $pid_probe_order $saved_pid_values PID
    }
    if {!$power_kicking_vio_missing} {
        puts "Restored last saved VIO parameters from $last_value_file"
    } else {
        puts "Saved VIO parameter file was found at $last_value_file, but no VIO was available to restore yet."
    }
}

proc _pk_collect_values {vio probe_names} {
    set values {}
    foreach probe_name $probe_names {
        set probe [_pk_get_probe $vio $probe_name]
        if {$probe eq ""} {
            error "Cannot save parameters: missing VIO output $probe_name; existing saved files are unchanged."
        }
        set value [_pk_normalize_probe_value $probe_name \
            [get_property OUTPUT_VALUE $probe] [get_property OUTPUT_VALUE_RADIX $probe]]
        lappend values $probe_name $value
    }
    return $values
}

proc pk_save_current_vio_parameters {{quiet 0}} {
    global last_value_file legacy_last_value_file control_probe_order pid_probe_order
    _pk_prepare_hw
    set control_vio [_pk_find_vio u_vio_control *hw_vio_2* $control_probe_order]
    set pid_vio [_pk_find_vio u_vio_pid *hw_vio_1* $pid_probe_order]

    if {$control_vio eq "" || $pid_vio eq ""} {
        if {!$quiet} {
            puts "Both control and PID VIOs are required to save. Existing saved parameters were left unchanged."
        }
        return
    }
    if {[catch {
        set control_values [_pk_collect_values $control_vio $control_probe_order]
        set pid_values [_pk_collect_values $pid_vio $pid_probe_order]
    } err]} {
        if {!$quiet} { puts "WARNING: $err" }
        return
    }

    set f [open $last_value_file w]
    puts $f "# Auto-saved VIO parameters. Do not edit while Vivado is using it."
    puts $f "set saved_control_values [list $control_values]"
    puts $f "set saved_pid_values [list $pid_values]"
    close $f

    set f [open $legacy_last_value_file w]
    puts $f "# Compatibility copy of last_vio_parameters_v2.tcl."
    puts $f "# Auto-saved VIO parameters. Do not edit while Vivado is using it."
    puts $f "set saved_control_values [list $control_values]"
    puts $f "set saved_pid_values [list $pid_values]"
    close $f

    if {!$quiet} {
        puts "Saved current VIO parameters to $last_value_file"
    }
}

proc _pk_file_mtime_text {path} {
    if {![file exists $path]} {
        return "missing"
    }
    return [clock format [file mtime $path] -format "%Y-%m-%d %H:%M:%S"]
}

proc pk_autosave_status {} {
    global last_value_file legacy_last_value_file default_bit_file default_ltx_file
    set enabled [expr {[info exists ::power_kicking_vio_autosave_enabled] ? $::power_kicking_vio_autosave_enabled : 0}]
    set started [expr {[info exists ::power_kicking_vio_autosave_started] ? $::power_kicking_vio_autosave_started : 0}]
    puts "VIO auto-save enabled=$enabled started=$started"
    puts "Default bit file: $default_bit_file"
    puts "Default ltx file: $default_ltx_file"
    puts "Current save file: $last_value_file"
    puts "Current save file mtime: [_pk_file_mtime_text $last_value_file]"
    puts "Legacy save file: $legacy_last_value_file"
    puts "Legacy save file mtime: [_pk_file_mtime_text $legacy_last_value_file]"
}

proc pk_list_vio_probes {} {
    global control_probe_order pid_probe_order pid_status_probe_order
    _pk_prepare_hw
    set control_vio [_pk_find_vio u_vio_control *hw_vio_2* $control_probe_order]
    set pid_vio [_pk_find_vio u_vio_pid *hw_vio_1* $pid_probe_order]

    foreach pair [list [list control $control_vio] [list PID $pid_vio]] {
        set label [lindex $pair 0]
        set vio [lindex $pair 1]
        puts "---- $label VIO: $vio ----"
        if {$vio eq ""} {
            puts "not found"
            continue
        }
        foreach probe [get_hw_probes -quiet -of_objects $vio] {
            set name [get_property NAME $probe]
            set out_value ""
            set in_value ""
            catch {set out_value [get_property OUTPUT_VALUE $probe]}
            catch {set in_value [get_property INPUT_VALUE $probe]}
            if {$out_value ne ""} {
                puts "OUT  $name = $out_value"
            } elseif {$in_value ne ""} {
                puts "IN   $name = $in_value"
            } else {
                puts "     $name"
            }
        }
    }
    puts "Expected PID status input probes: $pid_status_probe_order"
    puts "Note: vio_pid_locked is a read-only VIO input probe, not a writable output parameter."
}

proc pk_hw_debug {} {
    global default_bit_file default_ltx_file
    catch {open_hw_manager}
    catch {connect_hw_server -url 127.0.0.1:3121 -cs_url TCP:127.0.0.1:3042}
    puts "---- HW servers ----"
    set servers [get_hw_servers -quiet]
    if {[llength $servers] == 0} {
        puts "none"
    } else {
        foreach server $servers { puts $server }
    }

    puts "---- HW targets ----"
    set targets [get_hw_targets -quiet]
    if {[llength $targets] == 0} {
        puts "none"
    } else {
        foreach target $targets {
            set is_open ""
            catch {set is_open [get_property IS_OPEN $target]}
            puts "$target IS_OPEN=$is_open"
        }
    }

    puts "---- HW devices ----"
    set devices [get_hw_devices -quiet]
    if {[llength $devices] == 0} {
        puts "none"
    } else {
        foreach dev $devices {
            puts $dev
            catch {puts "  PROGRAM.FILE=[get_property PROGRAM.FILE $dev]"}
            catch {puts "  PROBES.FILE=[get_property PROBES.FILE $dev]"}
        }
    }

    puts "---- HW VIOs ----"
    set vios [get_hw_vios -quiet]
    if {[llength $vios] == 0} {
        puts "none"
    } else {
        foreach vio $vios {
            set cell ""
            catch {set cell [get_property CELL_NAME $vio]}
            puts "$vio CELL_NAME=$cell"
        }
    }

    puts "---- Default files ----"
    puts "BIT exists=[file exists $default_bit_file] $default_bit_file"
    puts "LTX exists=[file exists $default_ltx_file] $default_ltx_file"
    puts "If HW VIOs is none, run pk_program_device, then pk_hw_debug again."
}

proc _pk_autosave_loop {interval_ms} {
    if {[info exists ::power_kicking_vio_autosave_enabled] && $::power_kicking_vio_autosave_enabled} {
        catch {pk_save_current_vio_parameters 1}
        after $interval_ms [list _pk_autosave_loop $interval_ms]
    }
}

if {[info exists ::power_kicking_vio_autosave_no_autostart] && $::power_kicking_vio_autosave_no_autostart} {
    puts "VIO auto-save autostart skipped by ::power_kicking_vio_autosave_no_autostart."
} else {
    pk_restore_last_vio_parameters
    if {[info exists ::power_kicking_vio_restore_had_errors] && $::power_kicking_vio_restore_had_errors} {
        set ::power_kicking_vio_autosave_enabled 0
        catch {unset ::power_kicking_vio_autosave_started}
        puts "VIO auto-save was NOT started because restore found missing or width-mismatched probes."
        if {[info exists ::power_kicking_vio_missing] && $::power_kicking_vio_missing} {
            puts "Open Hardware Manager, connect target, program the FPGA if needed, then run autosave again."
        } else {
            puts "Rebuild with build_fast_feedback_v1.tcl, program the matching bitstream/LTX, then source this script again."
        }
    } elseif {![info exists ::power_kicking_vio_autosave_started]} {
        set ::power_kicking_vio_autosave_enabled 1
        set ::power_kicking_vio_autosave_started 1
        after 180000 [list _pk_autosave_loop 180000]
        puts "VIO auto-save is running every 3 minutes. Use pk_save_current_vio_parameters to save immediately."
        puts "Use pk_autosave_status to check whether the save file timestamp is moving."
        puts "Use pk_list_vio_probes to list current VIO input/output probes."
        puts "Use pk_hw_debug to diagnose hardware target/device/VIO visibility."
    } elseif {![info exists ::power_kicking_vio_autosave_enabled] || !$::power_kicking_vio_autosave_enabled} {
        set ::power_kicking_vio_autosave_enabled 1
        after 180000 [list _pk_autosave_loop 180000]
        puts "VIO auto-save was restarted every 3 minutes. Use pk_save_current_vio_parameters to save immediately."
        puts "Use pk_autosave_status to check whether the save file timestamp is moving."
        puts "Use pk_list_vio_probes to list current VIO input/output probes."
        puts "Use pk_hw_debug to diagnose hardware target/device/VIO visibility."
    } else {
        puts "VIO auto-save was already running."
        puts "Use pk_autosave_status to check whether the save file timestamp is moving."
        puts "Use pk_list_vio_probes to list current VIO input/output probes."
        puts "Use pk_hw_debug to diagnose hardware target/device/VIO visibility."
    }
}
