set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir power-kicker-fast-feedback-v1.xpr]
if {![llength [get_ips -quiet ila_adc]]} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
        -module_name ila_adc -dir [file join $script_dir power-kicker-fast-feedback-v1.srcs sources_1 ip]
}
set ip [get_ips ila_adc]
set_property -dict [list CONFIG.C_NUM_OF_PROBES 3 CONFIG.C_PROBE0_WIDTH 14 \
    CONFIG.C_PROBE1_WIDTH 14 CONFIG.C_PROBE2_WIDTH 16 CONFIG.C_DATA_DEPTH 8192 \
    CONFIG.C_INPUT_PIPE_STAGES 1 CONFIG.C_ADV_TRIGGER false] $ip
generate_target all $ip
update_compile_order -fileset sources_1
puts "ADC_ILA=PASS file=[get_property IP_FILE $ip] depth=[get_property CONFIG.C_DATA_DEPTH $ip] widths=14,14,16 pipe=1"
close_project
# Keep project recovery aware of the new IP. File references are portable.
file copy -force [file join $script_dir power-kicker-fast-feedback-v1.xpr] \
                 [file join $script_dir project_template.xml]
source [file join $script_dir project_manifest.tcl]
pk_assert_project_inputs
