# Maintainer utility: extend the official Xilinx PYNQ-Z2 Vivado 2024.1 PS
# design, then export a self-contained block-design Tcl for this repository.
#
# Prerequisites:
#   1. Run vivado/package_ip.tcl.
#   2. Set PYNQ_BASE_TCL to the official Xilinx PYNQ pynqz2.tcl path.
#      https://github.com/Xilinx/PYNQ/blob/master/boards/Pynq-Z2/
#      petalinux_bsp/hardware_project/pynqz2.tcl

if {![info exists ::env(PYNQ_BASE_TCL)]} {
    error "PYNQ_BASE_TCL must point to the official Xilinx PYNQ pynqz2.tcl"
}

set script_path [string map {\\ /} [info script]]
set script_dir [file dirname $script_path]
set repo_root [file dirname $script_dir]
set build_root [file join $repo_root build vivado]
set reference_dir [file join $build_root reference_project]
set ip_repo_dir [file join $build_root ip_repo]
set exported_bd_tcl [file join $script_dir bd pynq_z2_cnn_bd.tcl]
set base_tcl [string map {\\ /} $::env(PYNQ_BASE_TCL)]

if {![file exists $base_tcl]} {
    error "Official PYNQ-Z2 base Tcl not found: $base_tcl"
}
if {![file exists [file join $ip_repo_dir cnn_tile_accel_1_0 component.xml]]} {
    error "Packaged accelerator IP not found; run vivado/package_ip.tcl first"
}

file delete -force $reference_dir
file mkdir $reference_dir
file mkdir [file dirname $exported_bd_tcl]
cd $reference_dir

source $base_tcl
current_bd_design pynqz2

set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

set ps7 [get_bd_cells ps7]
set rst0 [get_bd_cells rst_ps7_0_fclk0]
set irq_concat [get_bd_cells xlconcat_0]

# Remove the three unused clock/reset domains from the official base project.
# Keeping them creates extra timing clocks and constraint warnings after the
# unused reset IP is optimized away.
foreach net_name {ps7_FCLK_CLK1 ps7_FCLK_CLK2 ps7_FCLK_CLK3} {
    set unused_net [get_bd_nets -quiet $net_name]
    if {$unused_net ne ""} {
        delete_bd_objs $unused_net
    }
}
foreach cell_name {rst_ps7_0_fclk1 rst_ps7_0_fclk2 rst_ps7_0_fclk3} {
    set unused_cell [get_bd_cells -quiet $cell_name]
    if {$unused_cell ne ""} {
        delete_bd_objs $unused_cell
    }
}

# Enable only the interfaces and one clock used by this accelerator system.
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_EN_CLK1_PORT {0} \
    CONFIG.PCW_EN_CLK2_PORT {0} \
    CONFIG.PCW_EN_CLK3_PORT {0} \
    CONFIG.PCW_FPGA_FCLK1_ENABLE {0} \
    CONFIG.PCW_FPGA_FCLK2_ENABLE {0} \
    CONFIG.PCW_FPGA_FCLK3_ENABLE {0} \
] $ps7
set_property PFM.CLOCK { FCLK_CLK0 {id "0" is_default "true" proc_sys_reset "rst_ps7_0_fclk0" status "fixed"} } $ps7

set control_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_control]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $control_smc

set ddr_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_ddr]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $ddr_smc

set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_sg_length_width {23} \
] $dma

set accel_vlnv haden-min.github.io:cnn:cnn_tile_accel:1.0
if {[get_ipdefs -all $accel_vlnv] eq ""} {
    error "Packaged accelerator IP is missing from the catalog: $accel_vlnv"
}
set accel [create_bd_cell -type ip -vlnv $accel_vlnv cnn_accel_0]

# PS control path: M_AXI_GP0 -> DMA AXI-Lite and accelerator AXI-Lite.
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_smc_control/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_control/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_smc_control/M01_AXI] [get_bd_intf_pins cnn_accel_0/S_AXI]

# DMA memory path: both DMA masters -> SmartConnect -> PS DDR HP0.
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins axi_smc_ddr/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins axi_smc_ddr/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_ddr/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]

# Stream loop through the accelerator.
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins cnn_accel_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins cnn_accel_0/M_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# One 100 MHz clock domain.
connect_bd_net [get_bd_pins ps7/FCLK_CLK0] \
    [get_bd_pins ps7/M_AXI_GP0_ACLK] \
    [get_bd_pins ps7/S_AXI_HP0_ACLK] \
    [get_bd_pins axi_smc_control/aclk] \
    [get_bd_pins axi_smc_ddr/aclk] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
    [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] \
    [get_bd_pins cnn_accel_0/aclk]

connect_bd_net [get_bd_pins rst_ps7_0_fclk0/peripheral_aresetn] \
    [get_bd_pins axi_smc_control/aresetn] \
    [get_bd_pins axi_smc_ddr/aresetn] \
    [get_bd_pins axi_dma_0/axi_resetn] \
    [get_bd_pins cnn_accel_0/aresetn]

# Three level-high interrupts share the PS IRQ_F2P port.
set_property CONFIG.NUM_PORTS {3} $irq_concat
connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins cnn_accel_0/irq] [get_bd_pins xlconcat_0/In2]

# Stable software-visible control addresses.
assign_bd_address -offset 0x40400000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs axi_dma_0/S_AXI_LITE/Reg]
assign_bd_address -offset 0x43C00000 -range 0x00010000 \
    -target_address_space [get_bd_addr_spaces ps7/Data] \
    [get_bd_addr_segs cnn_accel_0/S_AXI/reg0]

# Give both DMA channels the PS DDR address segment.
assign_bd_address -target_address_space [get_bd_addr_spaces axi_dma_0/Data_MM2S] \
    [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM]
assign_bd_address -target_address_space [get_bd_addr_spaces axi_dma_0/Data_S2MM] \
    [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM]

validate_bd_design
save_bd_design
write_bd_tcl -force $exported_bd_tcl

puts "CNN_BUILD: exported self-contained block design to $exported_bd_tcl"
close_project
