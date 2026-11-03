# Pure Tcl regression. Hardware Manager operations are replaced by in-memory
# stubs; this test cannot connect, program hardware, or write saved parameters.
set test_dir [file dirname [info script]]
set project_dir [file dirname $test_dir]
set checks 0
set hw_calls 0
set commits {}
set vios {}
array set hw {}
array set vio_probes {}

proc check {condition label} {
    global checks
    incr checks
    if {![uplevel 1 [list expr $condition]]} { error "FAIL: $label" }
}
proc expect_error {body label} {
    check {[catch {uplevel 1 $body}]} $label
}
proc add_vio {vio cell} {
    lappend ::vios $vio
    set ::hw($vio,CELL_NAME) $cell
    set ::vio_probes($vio) {}
}
proc add_probe {vio id name value {radix UNSIGNED}} {
    lappend ::vio_probes($vio) $id
    set ::hw($id,NAME) $name
    set ::hw($id,OUTPUT_VALUE) $value
    set ::hw($id,OUTPUT_VALUE_RADIX) $radix
}
proc get_hw_vios {args} { return $::vios }
proc get_hw_devices {args} { return device0 }
proc get_hw_probes {args} {
    set index [lsearch -exact $args -of_objects]
    if {$index < 0} { error "Mock requires explicit VIO scope" }
    set vio [lindex $args [expr {$index+1}]]
    if {![info exists ::vio_probes($vio)]} { return {} }
    return $::vio_probes($vio)
}
proc get_property {property object} {
    if {![info exists ::hw($object,$property)]} { error "Unknown mock property $object/$property" }
    return $::hw($object,$property)
}
proc set_property {property value objects} {
    foreach object $objects { set ::hw($object,$property) $value }
}
proc refresh_hw_vio {args} {}
proc commit_hw_vio {probes} { lappend ::commits $probes }
proc open_hw_manager {args} { incr ::hw_calls; error "Hardware access forbidden in test" }
proc connect_hw_server {args} { incr ::hw_calls; error "Hardware access forbidden in test" }
proc program_hw_devices {args} { incr ::hw_calls; error "Hardware access forbidden in test" }

set ::power_kicking_vio_autosave_no_autostart 1
source [file join $project_dir open_vio_with_last_parameters.tcl]
check {$hw_calls == 0} "loading helpers with no-autostart must not access hardware"
rename _pk_prepare_hw _pk_real_prepare_hw
proc _pk_prepare_hw {} {}

check {[_pk_normalize_probe_value vio_pid_kp 65535] == -1} "legacy unsigned minus one"
check {[_pk_normalize_probe_value vio_pid_ki 65280] == -256} "legacy unsigned negative gain"
check {[_pk_normalize_probe_value vio_pid_target_mV 32768] == -32768} "legacy signed minimum"
check {[_pk_normalize_probe_value vio_pid_target_mV -32768] == -32768} "signed minimum unchanged"
check {[_pk_normalize_probe_value vio_pid_kd -256] == -256} "signed negative unchanged"
check {[_pk_normalize_probe_value vio_pid_kp 32767] == 32767} "signed maximum unchanged"
check {[_pk_normalize_probe_value vio_pid_kp FF00 HEX] == -256} "hex signed capture"
check {[_pk_normalize_probe_value vio_pid_kp 0xFFFF] == -1} "explicit hex prefix"
check {[_pk_normalize_probe_value vio_pid_kp 1111111111111111 BINARY] == -1} "binary signed capture"
check {[_pk_normalize_probe_value vio_pid_confirm_samples 08] == 8} "decimal leading zero is not octal"
check {[_pk_normalize_probe_value vio_sweep_scan_us 4294967295] == 4294967295} "32-bit unsigned sweep duration"
check {[_pk_normalize_probe_value vio_pid_corr_limit 65535] == 65535} "unsigned probe does not become negative"
expect_error {_pk_normalize_probe_value vio_pid_kp 65536} "reject signed positive overflow"
expect_error {_pk_normalize_probe_value vio_pid_kp -32769} "reject signed negative overflow"
expect_error {_pk_normalize_probe_value vio_pid_window_mV -1} "reject negative unsigned value"
expect_error {_pk_normalize_probe_value vio_pid_kp {1+2}} "integer parser cannot evaluate expressions"

add_vio control top/u_vio_control
add_vio pid top/u_vio_pid
add_probe control control/7 probe_out7 1500
foreach name $pid_probe_order { add_probe pid pid/$name top/$name 0 }
add_probe pid pid/locked top/vio_pid_locked 0
set ::power_kicking_vio_restore_had_errors 0
_pk_restore_values pid {vio_pid_target_mV vio_pid_kp vio_pid_ki vio_pid_kd vio_pid_window_mV} \
    {vio_pid_target_mV -2 vio_pid_kp 65280 vio_pid_ki 65535 vio_pid_kd -3 vio_pid_window_mV 10} PID
check {$hw(pid/vio_pid_target_mV,OUTPUT_VALUE) == -2} "restore negative target"
check {$hw(pid/vio_pid_kp,OUTPUT_VALUE) == -256} "restore legacy unsigned gain as signed decimal"
check {$hw(pid/vio_pid_ki,OUTPUT_VALUE) == -1} "restore unsigned minus one"
check {$hw(pid/vio_pid_kd,OUTPUT_VALUE) == -3} "restore negative derivative gain"
check {$hw(pid/vio_pid_kp,OUTPUT_VALUE_RADIX) eq "SIGNED"} "signed restore radix"
check {$hw(pid/vio_pid_window_mV,OUTPUT_VALUE_RADIX) eq "UNSIGNED"} "unsigned restore radix"
check {$power_kicking_vio_restore_had_errors == 0} "valid restore reports success"
set commit_count [llength $commits]
_pk_restore_values pid {missing_probe} {missing_probe 1} PID
check {$power_kicking_vio_restore_had_errors == 1 && [llength $commits] == $commit_count} "missing restore probe is flagged and not committed"
set ::power_kicking_vio_restore_had_errors 0
_pk_check_expected_probes pid {vio_pid_kp absent_probe} PID
check {$power_kicking_vio_restore_had_errors == 1} "missing expected probe is flagged"
set ::power_kicking_vio_restore_had_errors 0
_pk_restore_values pid {vio_pid_kp} {vio_pid_kp 65536} PID
check {$power_kicking_vio_restore_had_errors == 1 && $hw(pid/vio_pid_kp,OUTPUT_VALUE) == -256} "invalid restore cannot replace last valid value"

set hw(pid/vio_pid_target_mV,OUTPUT_VALUE) FFFE
set hw(pid/vio_pid_target_mV,OUTPUT_VALUE_RADIX) HEX
set hw(pid/vio_pid_kp,OUTPUT_VALUE) 65535
set hw(pid/vio_pid_kp,OUTPUT_VALUE_RADIX) UNSIGNED
set hw(pid/vio_pid_ki,OUTPUT_VALUE) 1111111100000000
set hw(pid/vio_pid_ki,OUTPUT_VALUE_RADIX) BINARY
set collected [_pk_collect_values pid {vio_pid_target_mV vio_pid_kp vio_pid_ki}]
_pk_restore_values pid {vio_pid_start_delay_ns} {} PID
check {$hw(pid/vio_pid_start_delay_ns,OUTPUT_VALUE) == 200} "old saved PID values use independent 200 ns default"
_pk_restore_values pid {vio_pid_start_delay_ns} {vio_pid_start_delay_ns 4294967295} PID
check {$hw(pid/vio_pid_start_delay_ns,OUTPUT_VALUE) == 4294967295} "full unsigned 32-bit delay survives restore"
check {[_pk_collect_values pid {vio_pid_start_delay_ns}] eq {vio_pid_start_delay_ns 4294967295}} "delay survives save collection"
expect_error {_pk_normalize_probe_value vio_pid_start_delay_ns -1} "negative delay rejected"
expect_error {_pk_normalize_probe_value vio_pid_start_delay_ns 4294967296} "overflow delay rejected"
_pk_restore_values pid {vio_pid_require_window} {} PID
check {$hw(pid/vio_pid_require_window,OUTPUT_VALUE) == 1} "old saves require PD window by default"
_pk_restore_values pid {vio_pid_require_window} {vio_pid_require_window 0} PID
check {[_pk_collect_values pid {vio_pid_require_window}] eq {vio_pid_require_window 0}} "bypass survives restore and save collection"
expect_error {_pk_normalize_probe_value vio_pid_require_window 2} "non-boolean window mode rejected"
expect_error {_pk_normalize_probe_value vio_pid_require_window -1} "negative window mode rejected"
check {$collected eq {vio_pid_target_mV -2 vio_pid_kp -1 vio_pid_ki -256}} "save normalizes each current display radix to decimal"
expect_error {_pk_collect_values pid {vio_pid_kp nonexistent}} "incomplete save refuses to discard previous values"
check {[_pk_get_probe pid vio_pid_k] eq ""} "semantic lookup rejects partial name"

source [file join $project_dir set_pid_vio_decimal_only.tcl]
foreach name {vio_pid_target_mV vio_pid_kp vio_pid_ki vio_pid_kd} {
    check {$hw(pid/$name,OUTPUT_VALUE_RADIX) eq "SIGNED"} "decimal helper uses signed radix for $name"
}
foreach name {vio_pid_feedback_enable vio_pid_window_mV vio_pid_clear vio_pid_confirm_samples vio_pid_corr_limit} {
    check {$hw(pid/$name,OUTPUT_VALUE_RADIX) eq "UNSIGNED"} "decimal helper uses unsigned radix for $name"
}
check {$hw(control/7,OUTPUT_VALUE) == 1500} "decimal helper does not change control VIO"

# Generic probe_out7 is allowed only inside an explicitly identified PID core.
set vio_probes(pid) {}
add_probe pid pid/7 probe_out7 3
source [file join $project_dir set_fast_feedback_v1_vio_params.tcl]
check {$hw(pid/7,OUTPUT_VALUE) == 1} "confirm fallback writes identified PID probe 7"
check {$hw(control/7,OUTPUT_VALUE) == 1500} "confirm fallback never writes control probe 7"
set vios {control}
check {[ffv1_find_pid_confirm_probe] eq ""} "control probe 7 alone is not a PID confirm probe"
check {[_pk_find_vio u_vio_pid *control* {vio_pid_kp}] eq ""} "hardware numbering fallback cannot select wrong VIO"
expect_error {pk_pid_decimal_only} "decimal helper refuses unrecognized core"
set vios {control pid}
set hw(pid,CELL_NAME) top/u_vio_pid_old
check {[ffv1_find_pid_confirm_probe] eq ""} "similar but nonmatching PID cell cannot use numbered fallback"
set vio_probes(pid) {}
add_probe pid pid/semantic top/vio_pid_confirm_samples 3
check {[ffv1_find_pid_confirm_probe] eq "pid/semantic"} "exact semantic confirm probe is allowed without recognized cell"
set hw(pid/semantic,NAME) top/vio_pid_confirm_samples_backup
check {[ffv1_find_pid_confirm_probe] eq ""} "confirm semantic lookup rejects suffix contamination"
set hw(pid/semantic,NAME) top/vio_pid_confirm_samples
add_vio second unknown
add_probe second second/semantic vio_pid_confirm_samples 3
expect_error {ffv1_find_pid_confirm_probe} "ambiguous semantic confirm probes require explicit target"

# Missing hardware must leave existing saved files untouched. The helper returns
# before any output file is opened; guard open so accidental writes fail the test.
rename open test_real_open
proc open {path args} {
    if {[llength $args] && [lindex $args 0] ne "r"} { error "Saved-file writes forbidden in helper regression" }
    return [test_real_open $path {*}$args]
}
set vios {}
pk_save_current_vio_parameters 1
check {$hw_calls == 0} "entire regression makes no hardware calls"
puts "PASS: test_vio_helpers checks=$checks"
