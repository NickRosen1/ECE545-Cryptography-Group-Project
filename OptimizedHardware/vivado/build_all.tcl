# SPDX-License-Identifier: GPL-3.0-only
# build_all.tcl - Build every design the report needs, one after another, and
# collect the numbers in OptimizedHardware/vivado/results/summary.csv.
#
#   vivado -mode batch -source OptimizedHardware/vivado/build_all.tcl
#   vivado -mode batch -source OptimizedHardware/vivado/build_all.tcl -tclargs 8.0   (other period)
#
# Takes roughly 2-5 minutes per design. A design that misses timing is
# reported and the loop continues.
set ::BUILD_LIBRARY_ONLY 1
source [file join [file dirname [file normalize [info script]]] build.tcl]

set period 10.0
if {[info exists argv] && [llength $argv] >= 1} { set period [lindex $argv 0] }

set runs {
    {reference core}
    {baseline core}
    {it1_narrow_counters core}
    {it2_static_y core}
    {it3_shared_absorb core}
    {it4_shared_outputs core}
    {it5_explicit_state_mux core}
    {it6_no_static_y core}
    {it7_with_shared_outputs core}
    {it8_no_static_y_shared_outputs core}
    {opt core}
    {reference wrapper}
    {baseline wrapper}
    {opt wrapper}
}
foreach r $runs {
    lassign $r design top
    if {[catch {build_one $design $top $period} err]} {
        puts "WARNING: $design/$top: $err"
        catch {close_project}
    }
}
puts "\nAll done. See [file join $::ISAP_VIVADO_DIR results summary.csv]"
puts "To build one more design from this prompt:  build_one <design> <core|wrapper> \[period\]"
