# Run with Vivado in batch; edits only the project beside this script.
# Configure independent delay on output 9 and window requirement on output 10.
set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir power-kicker-fast-feedback-v1.xpr]
set ip [get_ips vio_pid]
if {[get_property CONFIG.C_NUM_PROBE_OUT $ip] < 11} {
    set_property CONFIG.C_NUM_PROBE_OUT 11 $ip
}
set_property -dict [list CONFIG.C_PROBE_OUT9_WIDTH 32 CONFIG.C_PROBE_OUT9_INIT_VAL 0x000000C8 \
    CONFIG.C_PROBE_OUT10_WIDTH 1 CONFIG.C_PROBE_OUT10_INIT_VAL 0x1] $ip
generate_target all $ip
puts "PID_DELAY_VIO=PASS width=[get_property CONFIG.C_PROBE_OUT9_WIDTH $ip] default_ns=200"
puts "PID_WINDOW_VIO=PASS width=[get_property CONFIG.C_PROBE_OUT10_WIDTH $ip] require_window_default=1"
close_project
