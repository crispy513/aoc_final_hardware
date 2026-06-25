#=====================================================================
# Generic Synopsys Design Compiler synthesis script
#
# Required from Makefile/environment:
#   SYN_TOP : top module name
#   SYN_SRC : RTL source files separated by spaces
# Optional:
#   SYN_OUT : output/report prefix. Default = SYN_TOP
#
# Example:
#   make synthesize SYN_TOP=PPU SYN_SRC=src/PPU/PPU.sv
#=====================================================================

#=====================================================================
# Debug current directory
#=====================================================================
puts "Current working directory = [pwd]"

#=====================================================================
# Read synthesis variables from environment
#=====================================================================
if {![info exists ::env(SYN_TOP)] || $::env(SYN_TOP) eq ""} {
    echo "ERROR: SYN_TOP is not set. Example: make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv"
    exit 1
}

if {![info exists ::env(SYN_SRC)] || $::env(SYN_SRC) eq ""} {
    echo "ERROR: SYN_SRC is not set. Example: make synthesize SYN_TOP=PE SYN_SRC=src/PE_array/PE.sv"
    exit 1
}

set TOP_MODULE $::env(SYN_TOP)
set OUT_NAME   $TOP_MODULE
if {[info exists ::env(SYN_OUT)] && $::env(SYN_OUT) ne ""} {
    set OUT_NAME $::env(SYN_OUT)
}

# SYN_SRC is passed as a space-separated string by Makefile.
# The script is executed inside build/, so paths like src/xxx.sv are
# automatically converted to ../src/xxx.sv.
set rtl_files [list]
foreach f [split $::env(SYN_SRC)] {
    if {$f eq ""} {
        continue
    }

    if {[file exists $f]} {
        lappend rtl_files $f
    } elseif {[file exists ../$f]} {
        lappend rtl_files ../$f
    } else {
        echo "ERROR: RTL file not found: $f"
        echo "       Tried: $f and ../$f"
        exit 1
    }
}

puts "Top module  = $TOP_MODULE"
puts "Output name = $OUT_NAME"
puts "RTL files   = $rtl_files"

#=====================================================================
# Read in RTL modules
#=====================================================================
set search_path "$search_path ..  ../src/PE_array ../src/PE_array/GIN ../src/PE_array/GON"

analyze -format sverilog $rtl_files

#=====================================================================
# Set top module
#=====================================================================
elaborate $TOP_MODULE
current_design $TOP_MODULE
link

#=====================================================================
# Set Design Environment
#=====================================================================
set_host_options -max_core 8

source ../script/DC.sdc

check_design

#=====================================================================
# Synthesis
#=====================================================================
uniquify

set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

set_max_area 0

compile
compile -incremental -only_hold_time

#=====================================================================
# Create output directory
#=====================================================================
file mkdir ../syn

#=====================================================================
# Create Report
#=====================================================================


report_timing -path full -delay min -nworst 50 -max_paths 50 -significant_digits 4 -sort_by group > ../syn/${OUT_NAME}_timing_min_50_rpt.txt

report_timing -path full -delay max -nworst 50 -max_paths 50 -significant_digits 4 -sort_by group > ../syn/${OUT_NAME}_timing_max_50_rpt.txt

set_false_path -from [get_ports rst]

report_timing -path full -delay max -nworst 50 -max_paths 50 -significant_digits 4 -sort_by group > ../syn/${OUT_NAME}_timing_max_no_rst_rpt.txt

report_timing -path full -delay max \
    -through [get_pins -hier *GIN*/*] \
    -nworst 20 -max_paths 20 -significant_digits 4 \
    > ../syn/${OUT_NAME}_timing_GIN_rpt.txt

report_timing -path full -delay max \
    -through [get_pins -hier *GON*/*] \
    -nworst 20 -max_paths 20 -significant_digits 4 \
    > ../syn/${OUT_NAME}_timing_GON_rpt.txt

report_area -nosplit > ../syn/${OUT_NAME}_area_rpt.txt

report_power -analysis_effort low > ../syn/${OUT_NAME}_power_rpt.txt

#=====================================================================
# Save synthesized file
#=====================================================================
write -hierarchy -format verilog -output ../syn/${OUT_NAME}_syn.v
write_sdf -version 3.0 -context verilog ../syn/${OUT_NAME}_syn.sdf
write_sdc ../syn/${OUT_NAME}_syn.sdc
puts "Synthesis done. Outputs are under ../syn with prefix: $OUT_NAME"
