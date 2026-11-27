# SPDX-License-Identifier: GPL-3.0-only
# create_project.tcl - Create a clean Vivado GUI project for the optimized core.
#
# In Vivado: Tools > Run Tcl Script... and pick this file, or
#   vivado -mode batch -source OptimizedHardware/vivado/create_project.tcl
# then open OptimizedHardware/vivado/isap_opt/isap_opt.xpr
#
# Unlike groupProjectFPGA, this project contains only ONE definition of each
# module (no original CryptoCore.vhd next to the binding), so simulation and
# synthesis cannot pick up the wrong CryptoCore_2pass.
# Top = crypto_core_2pass_opt, out of context, clock-only constraint.
set here [file dirname [file normalize [info script]]]
set opt  [file dirname $here]
set repo [file dirname $opt]
set proj [file join $here isap_opt]

create_project -force isap_opt $proj -part xc7a12tcsg325-3
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    [file join $opt rtl asconp.sv] \
    [file join $opt rtl crypto_core_2pass_opt.sv]]
set_property file_type SystemVerilog [get_files *.sv]
set_property top crypto_core_2pass_opt [current_fileset]

add_files -fileset constrs_1 -norecurse [file join $here core_clock.xdc]
set_property used_in_synthesis true  [get_files core_clock.xdc]
set_property used_in_implementation true [get_files core_clock.xdc]

set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property -name {STEPS.INIT_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]

puts "Created $proj/isap_opt.xpr. Run Implementation, then Report Utilization and Report Timing Summary."
close_project
