if {[info exists ::env(TILE_CONV_REPO)]} {
    set repo_dir $::env(TILE_CONV_REPO)
} else {
    set repo_dir [pwd]
}

if {[info exists ::env(TILE_CONV_TOP)]} {
    set top_name $::env(TILE_CONV_TOP)
} else {
    set top_name "top_single_conv_tile_axi"
}

if {[info exists ::env(TILE_CONV_REPORT_NAME)]} {
    set report_name $::env(TILE_CONV_REPORT_NAME)
} else {
    set report_name "tile_conv_ooc"
}

set report_dir [file join $repo_dir "reports" $report_name]
file mkdir $report_dir

set filelist_path [file join $repo_dir "rtl" "filelists" "current" "tile_conv_rtl.f"]
set filelist_handle [open $filelist_path r]
set filelist_text [read $filelist_handle]
close $filelist_handle

foreach source_path [split $filelist_text "\n"] {
    set source_path [string trim $source_path]
    if {$source_path ne ""} {
        set source_file [file join $repo_dir $source_path]
        read_verilog [list $source_file]
    }
}

synth_design -top $top_name \
             -part xc7z020clg400-1 \
             -mode out_of_context \
             -flatten_hierarchy rebuilt

create_clock -name aclk -period 10.000 [get_ports aclk]
set_clock_uncertainty 0.200 [get_clocks aclk]

opt_design
place_design
phys_opt_design
route_design

report_utilization -hierarchical \
                   -file [file join $report_dir "utilization_hierarchical.rpt"]
report_timing_summary -delay_type min_max \
                      -report_unconstrained \
                      -check_timing_verbose \
                      -max_paths 20 \
                      -file [file join $report_dir "timing_summary.rpt"]
report_methodology -file [file join $report_dir "methodology.rpt"]
write_checkpoint -force [file join $report_dir "${top_name}_routed.dcp"]

set timing_paths [get_timing_paths -max_paths 1 -setup]
if {[llength $timing_paths] == 0} {
    puts "TILE_CONV_TIMING: no setup path found"
} else {
    set worst_path [lindex $timing_paths 0]
    puts [format "TILE_CONV_TIMING: WNS=%.3f ns" [get_property SLACK $worst_path]]
}

puts "TILE_CONV_REPORT_DIR: $report_dir"
puts "TILE_CONV_TOP: $top_name"
