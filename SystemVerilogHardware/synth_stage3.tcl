# SPDX-License-Identifier: GPL-3.0-only
# Matched wrapper synthesis, added 2026-11-10. See ../LICENSE.txt.
# Arguments: design (reference/systemverilog), period in ns, report directory.
set design [lindex $argv 0]
set period [lindex $argv 1]
set reports [file normalize [lindex $argv 2]]
set portroot [file dirname [file normalize [info script]]]
set repo [file dirname $portroot]
set lwc [file join $repo hardware isap_lwc]
set shared [file join $repo hardware LWC_rtl]
set part xc7a12tcsg325-3
if {$design ni {reference systemverilog}} {error "Invalid design $design"}
if {![string is double -strict $period] || $period <= 0} {error "Invalid period"}
file mkdir $reports
set_param general.maxThreads 2
if {[llength [get_parts -quiet $part]] != 1} {error "Device support missing: $part"}
create_project -in_memory -part $part
set_property target_language VHDL [current_project]
read_vhdl -vhdl2008 [list [file join $lwc src_rtl v1 design_pkg.vhd]]
read_vhdl -vhdl2008 [list [file join $lwc src_rtl LWC_config_32.vhd]]
read_vhdl -vhdl2008 [list [file join $shared NIST_LWAPI_pkg.vhd]]
if {$design eq "reference"} {
    read_vhdl -vhdl2008 [list [file join $lwc src_rtl v1 CryptoCore.vhd]]
} else {
    read_verilog -sv [list [file join $portroot rtl asconp.sv] [file join $portroot rtl crypto_core_2pass.sv]]
    read_vhdl -vhdl2008 [list [file join $portroot rtl crypto_core_2pass_binding.vhd]]
}
foreach name {key_piso FIFO data_sipo data_piso PreProcessor PostProcessor LWC_2pass} {
    read_vhdl -vhdl2008 [list [file join $shared $name.vhd]]
}
set xdc [open constraints.xdc w]
puts $xdc "create_clock -name clk -period $period \[get_ports clk\]"
puts $xdc {set_input_delay -clock clk 0.0 [get_ports -filter {DIRECTION == IN && NAME != clk}]}
puts $xdc {set_output_delay -clock clk 0.0 [all_outputs]}
close $xdc
read_xdc constraints.xdc
synth_design -top LWC_2pass -part $part -flatten_hierarchy rebuilt -mode out_of_context
report_utilization -file [file join $reports utilization.rpt]
report_utilization -hierarchical -file [file join $reports hierarchy.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $reports post_synth_timing.rpt]
report_timing -delay_type max -max_paths 10 -file [file join $reports post_synth_paths.rpt]
report_drc -file [file join $reports post_synth_drc.rpt]
set tf [open [file join $reports post_synth_timing.rpt] r]
set timing_text [read $tf]
close $tf
if {![regexp {checking no_input_delay \(0\)} $timing_text] || ![regexp {checking no_output_delay \(0\)} $timing_text]} {
    error "I/O constraints were not applied to all data ports"
}
set latches [get_cells -hierarchical -filter {REF_NAME =~ LD*}]
set blackboxes [get_cells -hierarchical -filter {IS_BLACKBOX == 1}]
set worst [get_timing_paths -delay_type max -max_paths 1]
set f [open [file join $reports synthesis_summary.txt] w]
puts $f "tool=[version -short]"
puts $f "design=$design"
puts $f "top=LWC_2pass"
puts $f "part=$part"
puts $f "clock_period_ns=$period"
puts $f "input_output_delay_ns=0.0"
puts $f "flow=post-synthesis,out_of_context,flatten_hierarchy_rebuilt"
puts $f "external_payload_fifo=excluded"
puts $f "internal_header_fifo=included"
puts $f "latches=[llength $latches]"
puts $f "blackboxes=[llength $blackboxes]"
if {[llength $worst]} {puts $f "worst_setup_slack_ns=[get_property SLACK $worst]"}
close $f
file copy -force constraints.xdc [file join $reports constraints.xdc]
write_checkpoint -force post_synth.dcp
set lf [open [file join $reports latches.txt] w]
foreach cell $latches {puts $lf $cell}
close $lf
if {[llength $blackboxes]} {error "Unexpected blackboxes"}
if {$design eq "systemverilog" && [llength $latches]} {error "Unexpected latches in SV port"}
if {$design eq "reference" && [llength $latches] != 320} {error "Reference latch count changed; review"}
if {[llength $latches]} {puts "STAGE3_REFERENCE_WARNING: 320 upstream absorption latches; see Stage 3 report"}
puts "STAGE3_SYNTHESIS_COMPLETE $design"
