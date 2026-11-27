# SPDX-License-Identifier: GPL-3.0-only
# build.tcl - Synthesize, place and route one design out of context on the
# Artix-7 xc7a12tcsg325-3 and record area and timing.
#
# Run from anywhere:
#   vivado -mode batch -source OptimizedHardware/vivado/build.tcl -tclargs <design> <top> [period_ns]
#
#   <design> : opt          OptimizedHardware/rtl (current optimized core)
#              baseline     SystemVerilogHardware/rtl (partner's straight port)
#              reference    the ISAP team's original VHDL core (includes Ascon-Hash)
#              it<N>_...    a saved snapshot in OptimizedHardware/iterations/
#   <top>    : core         the CryptoCore alone (area of the ISAP datapath)
#              wrapper      LWC_2pass: core + NIST LWC API wrapper (as published)
#   period   : clock period in ns (default 10.0 = 100 MHz)
#
# Timing constraints: only the clock. Core ports connect to other on-chip
# logic, so their timing belongs to the level above; setting them to zero
# delay (as the old core_area.xdc did) creates false hold violations on
# port-to-register paths. All register-to-register paths are fully timed.
# For the 'wrapper' top every core port is internal and therefore timed too.
#
# Results: OptimizedHardware/vivado/results/<design>_<top>/ and one line
# appended to OptimizedHardware/vivado/results/summary.csv
#
# Exits with an error if the routed design misses timing (WNS < 0 or WHS < 0).

# Remember where this script lives while it is being sourced: [info script]
# is empty when build_one is later typed at the Tcl prompt.
set ::ISAP_VIVADO_DIR [file dirname [file normalize [info script]]]

proc build_one {design top {period 10.0}} {
    set here $::ISAP_VIVADO_DIR
    set opt  [file dirname $here]
    set repo [file dirname $opt]
    set lwc  [file join $repo hardware isap_lwc]
    set shared [file join $repo hardware LWC_rtl]
    set part xc7a12tcsg325-3
    set out [file join $here results "${design}_${top}"]
    file mkdir $out

    create_project -in_memory -part $part
    set_property target_language VHDL [current_project]

    # packages needed by any VHDL in the build
    read_vhdl -vhdl2008 [list [file join $lwc src_rtl v1 design_pkg.vhd] \
                             [file join $lwc src_rtl LWC_config_32.vhd] \
                             [file join $shared NIST_LWAPI_pkg.vhd]]

    # the core under test
    switch -glob -- $design {
        reference {
            read_vhdl -vhdl2008 [file join $lwc src_rtl v1 CryptoCore.vhd]
            set core_top CryptoCore_2pass
        }
        baseline {
            set sv [file join $repo SystemVerilogHardware rtl]
            read_verilog -sv [list [file join $sv asconp.sv] [file join $sv crypto_core_2pass.sv]]
            read_vhdl -vhdl2008 [file join $sv crypto_core_2pass_binding.vhd]
            set core_top crypto_core_2pass_sv
        }
        opt {
            read_verilog -sv [list [file join $opt rtl asconp.sv] [file join $opt rtl crypto_core_2pass_opt.sv]]
            read_vhdl -vhdl2008 [file join $opt rtl crypto_core_2pass_binding_opt.vhd]
            set core_top crypto_core_2pass_opt
        }
        it* {
            set snap [file join $opt iterations $design crypto_core_2pass_opt.sv]
            if {![file exists $snap]} { error "No snapshot $snap" }
            read_verilog -sv [list [file join $opt rtl asconp.sv] $snap]
            read_vhdl -vhdl2008 [file join $opt rtl crypto_core_2pass_binding_opt.vhd]
            set core_top crypto_core_2pass_opt
        }
        default { error "Unknown design '$design'" }
    }

    if {$top eq "wrapper"} {
        foreach name {key_piso FIFO data_sipo data_piso PreProcessor PostProcessor LWC_2pass} {
            read_vhdl -vhdl2008 [file join $shared $name.vhd]
        }
        set synth_top LWC_2pass
    } elseif {$top eq "core"} {
        set synth_top $core_top
    } else {
        error "Unknown top '$top' (use core or wrapper)"
    }

    set xdc [file join $out clock.xdc]
    set f [open $xdc w]
    puts $f "create_clock -name clk -period $period \[get_ports clk\]"
    close $f
    read_xdc -mode out_of_context $xdc

    synth_design -top $synth_top -part $part -mode out_of_context -flatten_hierarchy rebuilt
    report_utilization -file [file join $out utilization_synth.rpt]
    opt_design
    place_design
    phys_opt_design
    route_design

    report_utilization -file [file join $out utilization_routed.rpt]
    report_utilization -hierarchical -file [file join $out utilization_hier.rpt]
    report_timing_summary -max_paths 10 -file [file join $out timing_summary.rpt]
    report_timing -delay_type max -max_paths 5 -path_type full -file [file join $out critical_paths.rpt]
    write_checkpoint -force [file join $out routed.dcp]

    # ---- extract the numbers -------------------------------------------------
    set util [report_utilization -return_string]
    proc grab {text row} {
        if {[regexp "\\|\\s*$row\\s*\\|\\s*(\\d+)" $text -> n]} { return $n }
        return "NA"
    }
    set luts   [grab $util {Slice LUTs\*?}]
    set ffs    [grab $util {Slice Registers}]
    set slices [grab $util {Slice}]
    set latch  [grab $util {Register as Latch}]
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
    if {$wns eq ""} { set wns "NA" }
    if {$whs eq ""} { set whs "NA" }
    if {$wns ne "NA"} {
        set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
    } else { set fmax "NA" }

    set line "$design,$top,$luts,$ffs,$slices,$latch,$period,$wns,$whs,$fmax,[version -short]"
    set f [open [file join $out summary.txt] w]
    puts $f "design=$design top=$top LUTs=$luts FFs=$ffs slices=$slices latches=$latch"
    puts $f "period=${period}ns WNS=${wns}ns WHS=${whs}ns Fmax=${fmax}MHz"
    close $f
    puts "RESULT $line"
    # Excel locks an open .csv on Windows; don't lose the build over it.
    set csv [file join $here results summary.csv]
    if {[catch {
        set new [expr {![file exists $csv]}]
        set f [open $csv a]
        if {$new} { puts $f "design,top,LUTs,FFs,slices,latches,period_ns,WNS_ns,WHS_ns,Fmax_MHz,vivado" }
        puts $f $line
        close $f
    } err]} {
        puts "NOTE: could not add this line to summary.csv ($err). Close the file if it is"
        puts "      open in Excel, then run collect_results.tcl to rebuild the table."
    }
    close_project

    if {$wns ne "NA" && $wns < 0} { error "$design/$top MISSES SETUP TIMING (WNS=$wns ns)" }
    if {$whs ne "NA" && $whs < 0} { error "$design/$top MISSES HOLD TIMING (WHS=$whs ns)" }
}

if {[info exists argv] && [llength $argv] >= 2 && [info script] ne "" && ![info exists ::BUILD_LIBRARY_ONLY]} {
    set period 10.0
    if {[llength $argv] >= 3} { set period [lindex $argv 2] }
    build_one [lindex $argv 0] [lindex $argv 1] $period
}
