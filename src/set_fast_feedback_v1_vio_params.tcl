# Fast-feedback v1 runtime VIO parameters.
# Source this after programming the fast-feedback v1 bitstream and opening Hardware Manager.
#
# Important units:
# - vio_kick_rise_ns uses ns.
# - vio_kick_fall_ns uses ns.
# - vio_sweep_scan_us remains us.
#
# This script intentionally changes only vio_pid_confirm_samples.
# It does not modify VIO IP, probe order, probe width, RTL, XDC, or XCI.

set fast_feedback_v1_confirm_samples 1

proc ffv1_find_pid_confirm_probe {} {
    set semantic_candidates {}
    set numbered_candidates {}
    foreach vio [get_hw_vios -quiet] {
        set cell [get_property CELL_NAME $vio]
        set is_pid [expr {$cell eq "u_vio_pid" || [string match "*/u_vio_pid" $cell]}]
        set probes [get_hw_probes -quiet -of_objects $vio]
        foreach probe $probes {
            set probe_name [get_property NAME $probe]
            if {$probe_name eq "vio_pid_confirm_samples" ||
                [string match "*/vio_pid_confirm_samples" $probe_name]} {
                lappend semantic_candidates $probe
            } elseif {$is_pid && ($probe_name eq "probe_out7" ||
                      [string match "*/probe_out7" $probe_name])} {
                lappend numbered_candidates $probe
            }
        }
    }
    set candidates $semantic_candidates
    if {[llength $candidates] == 0} { set candidates $numbered_candidates }
    if {[llength $candidates] > 1} { error "Multiple PID confirm probes found; select one hardware target first." }
    return [lindex $candidates 0]
}

set confirm_probe [ffv1_find_pid_confirm_probe]
if {$confirm_probe eq ""} {
    error "Cannot find vio_pid_confirm_samples or probe_out7 in an identified u_vio_pid core. Refresh Hardware Manager with matching bitstream/LTX files."
}

puts "Setting fast-feedback v1 confirm samples:"
puts "  probe = $confirm_probe"
puts "  value = $fast_feedback_v1_confirm_samples"

set_property OUTPUT_VALUE_RADIX UNSIGNED $confirm_probe
catch {set_property DISPLAY_RADIX UNSIGNED $confirm_probe}
set_property OUTPUT_VALUE $fast_feedback_v1_confirm_samples $confirm_probe
commit_hw_vio [list $confirm_probe]

puts "fast_feedback_v1: vio_pid_confirm_samples committed as 1."
