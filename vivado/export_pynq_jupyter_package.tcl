# Export the generated overlay and board test material for browser upload.
# Run this from the Vivado Tcl Console after Generate Bitstream completes:
#   source ./vivado/export_pynq_jupyter_package.tcl

set script_path [string map {\\ /} [info script]]
set script_dir [file dirname $script_path]
set repo_root [file dirname $script_dir]
set build_root [file join $repo_root build vivado]
set gui_project_dir [file join $build_root pynq_z2_cnn_gui]
set upload_root [file join $repo_root build pynq_upload]
set package_dir [file join $upload_root pynq_z2_cnn]
set zip_path [file join $upload_root pynq_z2_cnn_jupyter.zip]

# Export only the GUI-generated result so an older command-line artifact cannot
# accidentally be uploaded after the block design has changed.
set bit_source [file join $gui_project_dir pynq_z2_cnn_gui.runs impl_1 pynqz2_wrapper.bit]
set hwh_source [file join $gui_project_dir pynq_z2_cnn_gui.gen sources_1 bd pynqz2 hw_handoff pynqz2.hwh]

if {![file exists $bit_source]} {
    error "Bitstream not found. Run Flow Navigator > Generate Bitstream first"
}
if {![file exists $hwh_source]} {
    error "HWH not found. Regenerate the block-design output products first"
}

set notebook_source [file join $repo_root sw pynq pynq_z2_cnn_bringup.ipynb]
set smoke_source [file join $repo_root sw pynq smoke_test_single_conv.py]
set fixture_single [file join $repo_root sw fixture single_conv_tile_28]
set fixture_multi [file join $repo_root sw fixture multi_ic_conv_tile_28]
foreach required [list $notebook_source $smoke_source $fixture_single $fixture_multi] {
    if {![file exists $required]} {
        error "Board test input is missing: $required"
    }
}

# Only generated upload output is replaced.
file delete -force $upload_root
file mkdir $package_dir

file copy -force $bit_source [file join $package_dir pynq_z2_cnn.bit]
file copy -force $hwh_source [file join $package_dir pynq_z2_cnn.hwh]
file copy -force $notebook_source [file join $package_dir pynq_z2_cnn_bringup.ipynb]
file copy -force $smoke_source [file join $package_dir smoke_test_single_conv.py]

# Use the fixed fixture manifest instead of Tcl glob. Some Windows Vivado
# installations mis-normalize long paths containing the directory name
# "Documents" when glob is used.
set fixture_files {
    layer_config.json
    input_int8.hex
    weight_int8.hex
    bias_int32.hex
    expected_acc_int32.hex
}
foreach fixture_pair [list \
    [list $fixture_single single_conv_tile_28] \
    [list $fixture_multi multi_ic_conv_tile_28]] {
    lassign $fixture_pair fixture_source fixture_name
    set fixture_destination [file join $package_dir $fixture_name]
    file mkdir $fixture_destination
    foreach fixture_file $fixture_files {
        file copy -force -- \
            [file join $fixture_source $fixture_file] \
            [file join $fixture_destination $fixture_file]
    }
}

set readme_path [file join $package_dir README_UPLOAD.txt]
set readme_handle [open $readme_path w]
puts $readme_handle "Upload pynq_z2_cnn_jupyter.zip and pynq_z2_cnn_bringup.ipynb to the PYNQ Jupyter home page."
puts $readme_handle "Open the notebook and run every cell from top to bottom."
close $readme_handle

# Keep the notebook outside the archive so the user can open it before the
# first cell extracts the archive.
file copy -force $notebook_source [file join $upload_root pynq_z2_cnn_bringup.ipynb]

set tar_executable [auto_execok tar]
if {$tar_executable eq ""} {
    error "tar executable not found; upload the folder directly from $package_dir"
}
set archive_entries {
    pynq_z2_cnn.bit
    pynq_z2_cnn.hwh
    pynq_z2_cnn_bringup.ipynb
    smoke_test_single_conv.py
    single_conv_tile_28
    multi_ic_conv_tile_28
    README_UPLOAD.txt
}
exec {*}$tar_executable -a -c -f $zip_path -C $package_dir {*}$archive_entries
if {![file exists $zip_path]} {
    error "Failed to create upload archive: $zip_path"
}

puts "CNN_EXPORT: PASS notebook=[file join $upload_root pynq_z2_cnn_bringup.ipynb]"
puts "CNN_EXPORT: PASS archive=$zip_path"
puts "CNN_EXPORT: Upload those two files in the PYNQ Jupyter browser"
