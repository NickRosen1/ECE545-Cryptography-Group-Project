# SPDX-License-Identifier: GPL-3.0-only
# Apply the core-area settings in an already-open Vivado project.
set timing_xdc [file normalize [file join [file dirname [info script]] \
    ../SystemVerilogHardware/constraints/core_area.xdc]]
if {![llength [get_files -quiet $timing_xdc]]} {
    add_files -fileset constrs_1 -norecurse $timing_xdc
}
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
    -value {-mode out_of_context} -objects [get_runs synth_1]
set_property -name {STEPS.INIT_DESIGN.ARGS.MORE OPTIONS} \
    -value {-mode out_of_context} -objects [get_runs impl_1]

# These AEAD compatibility inputs intentionally have no fanout. Keep their
# diagnostics visible and leave all other unconnected ports at warning severity.
set_msg_config -id {Synth 8-7129} -regexp -string \
    {{.*Port (bdi_pad_loc\[[0-3]\]|bdi_size\[[0-2]\]|hash_in) in module crypto_core_2pass_sv is either unconnected or has no load.*}} \
    -new_severity INFO
