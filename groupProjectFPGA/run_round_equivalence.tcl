# SPDX-License-Identifier: GPL-3.0-only
# Source this file from the Tcl Console of the open groupProjectFPGA project.
set repo_dir [file normalize [file join [file dirname [info script]] ..]]
foreach {fileset relative_path} {
    sources_1 hardware/isap_lwc/src_rtl/v1/design_pkg.vhd
    sim_1     hardware/isap_lwc/src_rtl/LWC_config_32.vhd
    sim_1     hardware/LWC_rtl/NIST_LWAPI_pkg.vhd
    sim_1     hardware/isap_lwc/src_rtl/v1/CryptoCore.vhd
    sim_1     SystemVerilogHardware/tb/asconp_vhdl_ref.vhd
} {
    set path [file join $repo_dir $relative_path]
    if {[lsearch -exact [get_files -of_objects [get_filesets $fileset]] $path] < 0} {
        add_files -norecurse -fileset $fileset $path
    }
    set_property file_type {VHDL 2008} [get_files $path]
    set_property library xil_defaultlib [get_files $path]
}

set_property top tb_asconp_equiv [get_filesets sim_1]
update_compile_order -fileset sim_1
if {[current_sim -quiet] ne ""} { close_sim }
launch_simulation -simset sim_1 -mode behavioral
run all
