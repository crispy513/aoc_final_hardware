#=====================================================================
# Debug current directory
#=====================================================================
puts "Current working directory = [pwd]"

#=====================================================================
# Read in RTL modules
#=====================================================================
set search_path "$search_path .. ../src "

set rtl_files [list \
    ../src/PE_array/PE_LEE.sv \
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

compile -gate_clock
compile -incremental -only_hold_time

#=====================================================================
# Create output directory
#=====================================================================
file mkdir ../syn

#=====================================================================
# Create Report
#=====================================================================
report_timing -path full -delay max -nworst 1 -max_paths 1 \
    -significant_digits 4 -sort_by group > ../syn/PE_LEE_timing_max_rpt.txt

report_timing -path full -delay min -nworst 1 -max_paths 1 \
    -significant_digits 4 -sort_by group > ../syn/PE_LEE_timing_min_rpt.txt

report_area -nosplit > ../syn/PE_LEE_area_rpt.txt

report_power -analysis_effort low > ../syn/PE_LEE_power_rpt.txt

#=====================================================================
# Save synthesized file
#=====================================================================
write -hierarchy -format verilog -output ../syn/PE_LEE_syn.v
write_sdf -version 3.0 -context verilog ../syn/PE_LEE_syn.sdf
write_sdc ../syn/PE_LEE_syn.sdc