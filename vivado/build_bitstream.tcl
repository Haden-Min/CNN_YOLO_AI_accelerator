# Rebuild the complete PYNQ-Z2 accelerator project and generate .bit/.hwh.
# Vivado 2024.1 is required because the checked-in block-design Tcl was
# generated and validated with that release.

set script_path [string map {\\ /} [info script]]
set script_dir [file dirname $script_path]
set repo_root [file dirname $script_dir]
set build_root [file join $repo_root build vivado]
set project_dir [file join $build_root pynq_z2_cnn_project]
set artifact_dir [file join $build_root artifacts]
set ip_repo_dir [file join $build_root ip_repo]
set bd_tcl [file join $script_dir bd pynq_z2_cnn_bd.tcl]
set package_tcl [file join $script_dir package_ip.tcl]

if {[string first "2024.1" [version -short]] < 0} {
    error "This reproducible build requires Vivado 2024.1; found [version -short]"
}
if {![file exists $bd_tcl]} {
    error "Block-design Tcl not found: $bd_tcl"
}

# Always repackage from the checked-in RTL so stale generated IP cannot leak
# into a new build.
source $package_tcl

# package_ip.tcl is intentionally runnable as a standalone script and uses
# ordinary Tcl variables. Restore this build script's paths after it returns.
set script_path [string map {\\ /} [info script]]
set script_dir [file dirname $script_path]
set repo_root [file dirname $script_dir]
set build_root [file join $repo_root build vivado]
set project_dir [file join $build_root pynq_z2_cnn_project]
set artifact_dir [file join $build_root artifacts]
set ip_repo_dir [file join $build_root ip_repo]
set bd_tcl [file join $script_dir bd pynq_z2_cnn_bd.tcl]

file delete -force $project_dir
file mkdir $project_dir
file mkdir $artifact_dir

create_project -force pynq_z2_cnn $project_dir -part xc7z020clg400-1
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
    error "Recreated design does not contain pynqz2.bd"
}

# Use global synthesis so the entire build stays in this Vivado process. This
# avoids Windows Script Host/rundef.js policy differences between team PCs.
set_property synth_checkpoint_mode None $bd_file
generate_target all $bd_file
make_wrapper -files $bd_file -top
set wrapper_file [file join $project_dir pynq_z2_cnn.gen sources_1 bd pynqz2 hdl pynqz2_wrapper.v]
if {![file exists $wrapper_file]} {
    error "Generated HDL wrapper not found: $wrapper_file"
}
add_files -norecurse [list $wrapper_file]
set_property top pynqz2_wrapper [current_fileset]
update_compile_order -fileset sources_1

set timing_report [file join $artifact_dir timing_summary.rpt]
set utilization_report [file join $artifact_dir utilization.rpt]
set drc_report [file join $artifact_dir drc.rpt]
synth_design -top pynqz2_wrapper -part xc7z020clg400-1 -flatten_hierarchy rebuilt
write_checkpoint -force [file join $artifact_dir post_synth.dcp]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $artifact_dir routed.dcp]

report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 10 -input_pins -file $timing_report
report_utilization -hierarchical -file $utilization_report
report_drc -file $drc_report

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set wns [expr {$setup_path eq "" ? 0.0 : [get_property SLACK $setup_path]}]
set whs [expr {$hold_path eq "" ? 0.0 : [get_property SLACK $hold_path]}]
puts "CNN_BUILD: timing WNS=$wns ns WHS=$whs ns"
if {$wns eq "" || [expr {double($wns)}] < 0.0} {
    error "Final implementation does not meet setup timing: WNS=$wns ns"
}
if {$whs ne "" && [expr {double($whs)}] < 0.0} {
    error "Final implementation does not meet hold timing: WHS=$whs ns"
}

set hwh_source [file join $project_dir pynq_z2_cnn.gen sources_1 bd pynqz2 hw_handoff pynqz2.hwh]
if {![file exists $hwh_source]} {
    error "Generated HWH not found: $hwh_source"
}

write_bitstream -force [file join $artifact_dir pynq_z2_cnn.bit]
file copy -force $hwh_source [file join $artifact_dir pynq_z2_cnn.hwh]

puts "CNN_BUILD: PASS bitstream=[file join $artifact_dir pynq_z2_cnn.bit]"
puts "CNN_BUILD: PASS handoff=[file join $artifact_dir pynq_z2_cnn.hwh]"
puts "CNN_BUILD: timing_report=$timing_report"
puts "CNN_BUILD: utilization_report=$utilization_report"
puts "CNN_BUILD: drc_report=$drc_report"
close_project
