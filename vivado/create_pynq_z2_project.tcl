# Vivado GUI entry point for the PYNQ-Z2 accelerator project.
#
# In Vivado 2024.1, start with no project open and enter:
#   cd {C:/path/to/CNN_YOLO_AI_accelerator}
#   source ./vivado/create_pynq_z2_project.tcl
#
# The script packages the checked-in RTL, creates and validates the block
# design, generates the HDL wrapper, and leaves the project open.  Generate
# the bitstream from Flow Navigator after CNN_GUI: PASS is printed.

set script_path [string map {\\ /} [info script]]
set script_dir [file dirname $script_path]
set repo_root [file dirname $script_dir]
set build_root [file join $repo_root build vivado]
set project_dir [file join $build_root pynq_z2_cnn_gui]
set ip_repo_dir [file join $build_root ip_repo]
set package_tcl [file join $script_dir package_ip.tcl]
set bd_tcl [file join $script_dir bd pynq_z2_cnn_bd.tcl]

if {[string first "2024.1" [version -short]] < 0} {
    error "This project requires Vivado 2024.1; found [version -short]"
}
if {[llength [get_projects -quiet]] != 0} {
    error "Close the current Vivado project, then source this script again"
}
if {![file exists $package_tcl] || ![file exists $bd_tcl]} {
    error "Required repository Tcl files are missing under $script_dir"
}

puts "CNN_GUI: packaging accelerator IP from checked-in RTL"
source $package_tcl

# package_ip.tcl is also a standalone entry point and uses ordinary Tcl
# variables.  Restore this script's paths after the source command returns.
set script_path [string map {\\ /} [info script]]
set script_dir [file dirname $script_path]
set repo_root [file dirname $script_dir]
set build_root [file join $repo_root build vivado]
set project_dir [file join $build_root pynq_z2_cnn_gui]
set ip_repo_dir [file join $build_root ip_repo]
set bd_tcl [file join $script_dir bd pynq_z2_cnn_bd.tcl]

# This directory is generated output. Re-running the script intentionally
# recreates only this exact GUI project directory.
file delete -force $project_dir
file mkdir $project_dir

create_project -force pynq_z2_cnn_gui $project_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

cd $project_dir
source $bd_tcl
validate_bd_design
save_bd_design

set bd_file [get_files -quiet pynqz2.bd]
if {$bd_file eq ""} {
    error "Recreated project does not contain pynqz2.bd"
}

set_property synth_checkpoint_mode None $bd_file
generate_target all $bd_file
make_wrapper -files $bd_file -top

set wrapper_file [file join $project_dir pynq_z2_cnn_gui.gen sources_1 bd pynqz2 hdl pynqz2_wrapper.v]
if {![file exists $wrapper_file]} {
    error "Generated HDL wrapper not found: $wrapper_file"
}

add_files -norecurse [list $wrapper_file]
set_property top pynqz2_wrapper [current_fileset]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
update_compile_order -fileset sources_1
save_bd_design
open_bd_design $bd_file
cd $repo_root

puts "CNN_GUI: PASS project=[get_property DIRECTORY [current_project]]"
puts "CNN_GUI: Block Design pynqz2 is open and validated"
puts "CNN_GUI: Next click Flow Navigator > Generate Bitstream"
puts "CNN_GUI: After bitstream completion, source ./vivado/export_pynq_jupyter_package.tcl"
