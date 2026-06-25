set LIB_PATH /usr/cad/process/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/NLDM

set_app_var search_path [list . ./syn ./script $LIB_PATH]

set_app_var target_library [list \
    $LIB_PATH/N16ADFP_StdCellss0p72v125c.db \
]

set_app_var link_library [list \
    * \
    $LIB_PATH/N16ADFP_StdCellss0p72v125c.db \
    $LIB_PATH/N16ADFP_StdCellff0p88vm40c.db \
]
# =========================
# Set power analysis mode
# =========================
set power_enable_analysis TRUE
set power_analysis_mode averaged

# =========================
# Read and Link Design
# =========================
set DESIGN_NAME PE_LEE
read_verilog syn/${DESIGN_NAME}_syn.v
current_design ${DESIGN_NAME}
link

# =========================
# Read .sdf .sdc .spef
# =========================
read_sdf ./syn/${DESIGN_NAME}_syn.sdf
read_sdc -version 2.1  ./syn/${DESIGN_NAME}_syn.sdc
# read_parasitics ../pr/${DESIGN_NAME}_pr.spef

# =========================
# Static Timing Analysis
# =========================
check_timing
update_timing
# setup check
report_timing -path full -delay max -nworst 1 -max_paths 1 -significant_digits 4
# hold check
report_timing -path full -delay min -nworst 1 -max_paths 1 -significant_digits 4

# ===============================
# Specify Switching Activity Data
# ===============================
read_vcd -strip_path TOP/PE ./wave/PE_wave.vcd

# =====================
# Power Analysis
# ====================
check_power
update_power
report_power

