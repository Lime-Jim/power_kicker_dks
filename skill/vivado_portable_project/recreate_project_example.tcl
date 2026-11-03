# Metadata-only recovery. Close the project in the GUI before running in batch.
# IMPORTANT: never use create_project -force here: Vivado deletes same-name
# .srcs directories in a populated project. Only replace the backed-up XPR.
source [file join [file dirname [file normalize [info script]]] project_manifest.tcl]
if {[llength [get_projects -quiet]]} { error "Close the current project first" }
foreach path [concat $pk_design_files $pk_ip_files $pk_aux_files [list $pk_xdc $pk_sim_top $pk_timing_entry]] {
    if {![file isfile $path]} { error "Required source is missing: $path" }
}
set template [file join $pk_project_dir project_template.xml]
if {![file isfile $template]} { error "Canonical XPR template not found: $template" }
set xpr [file join $pk_project_dir $pk_project_name.xpr]
set backup {}
if {[file exists $xpr]} {
    set backup "$xpr.before_recreate_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]"
    file copy $xpr $backup
    puts "XPR_BACKUP=$backup"
}
if {[catch {
    file copy -force $template $xpr
    pk_assert_project_inputs
    open_project $xpr
    pk_configure_project
    puts "RECREATED_IPS=[get_ips]"
    close_project
    pk_assert_project_inputs
} problem options]} {
    catch {close_project}
    if {$backup ne {}} { file copy -force $backup $xpr }
    return -options $options $problem
}
puts "RECREATE_PROJECT=PASS (XPR metadata only; source directories preserved)"
