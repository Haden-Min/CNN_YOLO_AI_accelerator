# Package top_single_conv_tile_axi as a reusable Vivado IP.
# Run from the repository root with Vivado 2024.1:
#   vivado -mode batch -source vivado/package_ip.tcl

set script_path [string map {\\ /} [info script]]
set script_dir [file dirname $script_path]
set repo_root  [file dirname $script_dir]
set build_root [file join $repo_root build vivado]
set project_dir [file join $build_root ip_packaging_project]
set ip_repo_dir [file join $build_root ip_repo]
set ip_root [file join $ip_repo_dir cnn_tile_accel_1_0]

puts "CNN_BUILD: script_path=$script_path"
puts "CNN_BUILD: script_dir=$script_dir"
puts "CNN_BUILD: repo_root=$repo_root"
puts "CNN_BUILD: build_root=$build_root"

file mkdir $build_root
file mkdir $ip_repo_dir

create_project -force cnn_tile_accel_pkg $project_dir -part xc7z020clg400-1

set filelist [file join $repo_root rtl filelists current tile_conv_rtl.f]
set file_handle [open $filelist r]
set rtl_files {}
while {[gets $file_handle line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
        continue
    }
    lappend rtl_files [file join $repo_root {*}[file split $line]]
}
close $file_handle

# The canonical filelist stops at top_single_conv_tile_axi. Add the optional
# fixed-parameter IP Integrator shell only for this packaging flow.
lappend rtl_files [file join $repo_root rtl active integration cnn_tile_accel_ip.v]

add_files -norecurse $rtl_files
update_compile_order -fileset sources_1
set_property source_mgmt_mode None [current_project]
set_property top cnn_tile_accel_ip [current_fileset]

ipx::package_project \
    -root_dir $ip_root \
    -vendor haden-min.github.io \
    -library cnn \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]
set_property name cnn_tile_accel $core
set_property version 1.0 $core
set_property display_name {CNN 28x28 Serial-IC Tile Accelerator} $core
set_property description {INT8 valid 3x3 tile convolution with AXI-Lite control and AXI4-Stream data} $core
set_property vendor_display_name {CNN YOLO AI Accelerator} $core
set_property company_url {https://github.com/Haden-Min/CNN_YOLO_AI_accelerator} $core

# Re-run interface inference after setting the stable core metadata.
ipx::infer_bus_interfaces $core

foreach {old_name new_name} {
    s_axi  S_AXI
    s_axis S_AXIS
    m_axis M_AXIS
} {
    set bus_if [ipx::get_bus_interfaces $old_name -of_objects $core]
    if {$bus_if eq ""} {
        error "IP packaging failed: interface '$old_name' was not inferred"
    }
    set_property name $new_name $bus_if
}

set clk_if [ipx::get_bus_interfaces aclk -of_objects $core]
if {$clk_if eq ""} {
    error "IP packaging failed: aclk interface was not inferred"
}
set clk_param [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clk_if]
if {$clk_param eq ""} {
    set clk_param [ipx::add_bus_parameter ASSOCIATED_BUSIF $clk_if]
}
set_property value {S_AXI:S_AXIS:M_AXIS} $clk_param

set reset_param [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clk_if]
if {$reset_param eq ""} {
    set reset_param [ipx::add_bus_parameter ASSOCIATED_RESET $clk_if]
}
set_property value {aresetn} $reset_param

set freq_param [ipx::get_bus_parameters FREQ_HZ -of_objects $clk_if]
if {$freq_param eq ""} {
    set freq_param [ipx::add_bus_parameter FREQ_HZ $clk_if]
}
set_property value {100000000} $freq_param

set reset_if [ipx::get_bus_interfaces aresetn -of_objects $core]
if {$reset_if eq ""} {
    error "IP packaging failed: aresetn interface was not inferred"
}
set polarity_param [ipx::get_bus_parameters POLARITY -of_objects $reset_if]
if {$polarity_param eq ""} {
    set polarity_param [ipx::add_bus_parameter POLARITY $reset_if]
}
set_property value {ACTIVE_LOW} $polarity_param

foreach required_if {S_AXI S_AXIS M_AXIS aclk aresetn irq} {
    if {[ipx::get_bus_interfaces $required_if -of_objects $core] eq ""} {
        error "IP packaging failed: required interface '$required_if' is missing"
    }
}

ipx::check_integrity -quiet $core
ipx::save_core $core
close_project

puts "CNN_BUILD: packaged IP at $ip_root"
