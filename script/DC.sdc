
#=====================================================================
# Setting Clock freq & some parameter
#=====================================================================

set clk_period 2.0
set input_max   [expr {double(round(1000*$clk_period * 0.6))/1000}]
set input_min   [expr {double(round(1000*$clk_period * 0.0))/1000}]
set output_max  [expr {double(round(1000*$clk_period * 0.1))/1000}]
set output_min  [expr {double(round(1000*$clk_period * 0.0))/1000}]


#=====================================================================
# Setting Clock Constraints
#=====================================================================

# 500 MHz clock, duty cycle 50%
create_clock -name clk -period $clk_period \
    -waveform [list 0.0 [expr {$clk_period / 2.0}]] \
    [get_ports clk]
# clock transition = 0.05 ns
set_clock_transition 0.05 [get_clocks clk]

# clock generator -> clock pad = 0.13 ns
set_clock_latency -source 0.13 [get_clocks clk]

# clock pad -> FF = 0.12 ns
set_clock_latency 0.12 [get_clocks clk]

# clock skew = 0.1 ns
set_clock_uncertainty -setup 0.10 [get_clocks clk]
set_clock_uncertainty -hold  0.10 [get_clocks clk]

set_dont_touch_network [get_ports clk]
set_dont_touch_network [get_clocks clk]
set_ideal_network      [get_ports clk]
set_ideal_network      [get_clocks clk]

# ask DC to consider hold fixing
set_fix_hold [get_clocks clk]


#=====================================================================
# Setting Timing Constraints
#=====================================================================

# all input ports except clock
set input_ports_no_clk [remove_from_collection [all_inputs] [get_ports clk]]

# input transition = 0.05 ns
set_input_transition 0.05 $input_ports_no_clk

# input delay
set_input_delay  -clock [get_clocks clk] -max $input_max  $input_ports_no_clk
set_input_delay  -clock [get_clocks clk] -min $input_min  $input_ports_no_clk

# output delay
set_output_delay -clock [get_clocks clk] -max $output_max [all_outputs]
set_output_delay -clock [get_clocks clk] -min $output_min [all_outputs]

# output load 這裡講義沒有寫
set_load 0.05 [all_outputs]


#=====================================================================
# Setting Design Environment
#=====================================================================

set_operating_conditions -min_library N16ADFP_StdCellff0p88vm40c -min ff0p88vm40c \
                         -max_library N16ADFP_StdCellss0p72v125c -max ss0p72v125c

set_wire_load_model -name ZeroWireload -library N16ADFP_StdCellss0p72v125c


#=====================================================================
# Setting DRC Constraints
#=====================================================================

# force area optimization
set_max_area 0

# DRC constraints
set_max_fanout      10  [all_inputs]
set_max_transition  0.5 [all_inputs]
set_max_capacitance 0.1 [all_inputs]


#=====================================================================
# Naming Rule
#=====================================================================

set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true

change_names -hierarchy -rule verilog

define_name_rules name_rule -allowed "A-Z a-z 0-9 _"   -max_length 255 -type cell
define_name_rules name_rule -allowed "A-Z a-z 0-9 _[]" -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive

change_names -hierarchy -rules name_rule