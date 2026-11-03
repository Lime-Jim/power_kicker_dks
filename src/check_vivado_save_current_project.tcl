set script_dir [file dirname [file normalize [info script]]]
set xpr [file join $script_dir power-kicker-fast-feedback-v1.xpr]
if {![file exists $xpr]} {
    error "Project not found: $xpr"
}
open_project $xpr
puts "PROJECT_OPEN_OK=[current_project]"
close_project