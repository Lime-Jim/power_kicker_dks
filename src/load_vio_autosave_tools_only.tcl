# Load VIO restore/autosave helper procedures without immediately connecting hardware.
# Use this when you want the commands available but do not want Vivado to block on hw_server.
set ::power_kicking_vio_autosave_no_autostart 1
source [file join [file dirname [info script]] open_vio_with_last_parameters.tcl]
puts "VIO autosave tools loaded without autostart."
puts "After programming the FPGA, run:"
puts "  pk_restore_last_vio_parameters"
puts "  pk_save_current_vio_parameters"
puts "  pk_autosave_status"
