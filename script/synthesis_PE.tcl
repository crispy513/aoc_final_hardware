#=====================================================================
# Debug current directory
#=====================================================================
puts "Current working directory = [pwd]"

#=====================================================================
# Read in RTL modules
#=====================================================================
set search_path "$search_path .. ../src ../src/PE_array"

set rtl_files [list \
    ../src/PE_array/PE.sv \
]

analyze -format sverilog $rtl_files

#=====================================================================
# SET top module
#=====================================================================
elaborate PE
current_design PE
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
report_timing -path full -delay max -nworst 1 -max_paths 1 \
    -significant_digits 4 -sort_by group > ../syn/PE_timing_max_rpt.txt

report_timing -path full -delay min -nworst 1 -max_paths 1 \
    -significant_digits 4 -sort_by group > ../syn/PE_timing_min_rpt.txt

report_area -nosplit > ../syn/PE_area_rpt.txt

report_power -analysis_effort low > ../syn/PE_power_rpt.txt

#=====================================================================
# Save synthesized file
#=====================================================================
write -hierarchy -format verilog -output ../syn/PE_syn.v
write_sdf -version 3.0 -context verilog ../syn/PE_syn.sdf