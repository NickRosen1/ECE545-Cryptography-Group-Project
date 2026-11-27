# SPDX-License-Identifier: GPL-3.0-only
# collect_results.tcl - Rebuild the results table from the reports that
# build.tcl leaves in vivado/results/<design>_<top>/, without re-running
# anything. Use it if summary.csv is missing lines (for example because it
# was open in Excel, which locks the file on Windows).
#
# In the Vivado Tcl Shell (or any tclsh), from the repository root:
#   source OptimizedHardware/vivado/collect_results.tcl
# Writes OptimizedHardware/vivado/results/summary_collected.csv and prints it.

namespace eval collect {
    proc slurp {path} {
        set f [open $path r]; set t [read $f]; close $f; return $t
    }
    proc util_row {text row} {
        if {[regexp -line "^\\|\\s*${row}\\s*\\|\\s*(\\d+)\\s*\\|" $text -> n]} { return $n }
        return "NA"
    }
    # First data line under the "WNS(ns) ... WHS(ns)" header of the
    # Design Timing Summary: columns are WNS TNS ... WHS ...
    proc timing {text} {
        set lines [split $text "\n"]
        for {set i 0} {$i < [llength $lines]} {incr i} {
            if {[regexp {^\s*WNS\(ns\)\s+TNS\(ns\)} [lindex $lines $i]]} {
                set nums [regexp -all -inline {\S+} [lindex $lines [expr {$i + 2}]]]
                if {[llength $nums] >= 5} { return [list [lindex $nums 0] [lindex $nums 4]] }
            }
        }
        return {NA NA}
    }
    proc run {} {
        set here [file dirname [file normalize [info script]]]
        set res [file join $here results]
        set out [file join $res summary_collected.csv]
        set rows [list "design,top,LUTs,FFs,slices,latches,period_ns,WNS_ns,WHS_ns,Fmax_MHz"]
        foreach dir [lsort [glob -nocomplain -type d [file join $res *]]] {
            set name [file tail $dir]
            if {![regexp {^(.+)_(core|wrapper)$} $name -> design top]} { continue }
            set u [file join $dir utilization_routed.rpt]
            set t [file join $dir timing_summary.rpt]
            if {![file exists $u] || ![file exists $t]} {
                puts "skipping $name (no routed reports: build did not finish)"
                continue
            }
            set ut [slurp $u]
            set luts   [util_row $ut {Slice LUTs\*?}]
            set ffs    [util_row $ut {Slice Registers}]
            set slices [util_row $ut {Slice}]
            set latch  [util_row $ut {Register as Latch}]
            lassign [timing [slurp $t]] wns whs
            set period 10.0
            set x [file join $dir clock.xdc]
            if {[file exists $x] && [regexp {\-period\s+([0-9.]+)} [slurp $x] -> p]} { set period $p }
            if {[string is double -strict $wns]} {
                set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
            } else { set fmax NA }
            lappend rows "$design,$top,$luts,$ffs,$slices,$latch,$period,$wns,$whs,$fmax"
        }
        if {[catch {
            set f [open $out w]; puts $f [join $rows "\n"]; close $f
        } err]} {
            puts "Could not write $out ($err). Is it open in Excel? Table below:"
        } else {
            puts "Wrote $out"
        }
        puts [join $rows "\n"]
    }
}
collect::run
