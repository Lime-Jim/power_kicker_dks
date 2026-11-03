set script_dir [file dirname [file normalize [info script]]]
open_project [file join $script_dir power-kicker-fast-feedback-v1.xpr]
set rtl [file join $script_dir power-kicker-fast-feedback-v1.srcs sources_1 new capture_phase_status.v]
if {![llength [get_files -quiet $rtl]]} { add_files -norecurse $rtl }
if {![llength [get_ips -quiet ila_capture]]} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
        -module_name ila_capture -dir [file join $script_dir power-kicker-fast-feedback-v1.srcs sources_1 ip]
}
set ila [get_ips ila_capture]
set widths {2 3 16 1 16 16 16 1 1 1 1 1 1 1 1 16 16 1 1 1 1 1 1}
set props [list CONFIG.C_NUM_OF_PROBES [llength $widths] CONFIG.C_DATA_DEPTH 8192 \
    CONFIG.C_INPUT_PIPE_STAGES 1 CONFIG.C_ADV_TRIGGER false]
set i 0
foreach width $widths { lappend props CONFIG.C_PROBE${i}_WIDTH $width; incr i }
set_property -dict $props $ila
set vio [get_ips vio_pid]
set_property -dict [list CONFIG.C_NUM_PROBE_IN 10 CONFIG.C_PROBE_IN8_WIDTH 2 \
    CONFIG.C_PROBE_IN9_WIDTH 1] $vio
generate_target all [list $ila $vio]
update_compile_order -fileset sources_1
puts "CAPTURE_DEBUG_IP=PASS (23 ILA probes; VIO input8 phase2, input9 history1)"
close_project
file copy -force [file join $script_dir power-kicker-fast-feedback-v1.xpr] \
    [file join $script_dir project_template.xml]
source [file join $script_dir project_manifest.tcl]
pk_assert_project_inputs
