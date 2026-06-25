######################################################################
# Directory Setting
######################################################################

root_dir := $(PWD)
wv_dir   := waveform
sim_dir  := sim
src_dir  := src
syn_dir  := syn
in_dir   := image
bld_dir  := build

######################################################################
# Source Files for Verilator
######################################################################

SRC1 = $(wildcard ./src/PE_array/PE.sv)
SRC2 = $(wildcard ./src/PE_array/PE_array.sv)
SRC3 = $(wildcard ./src/PPU/PPU.sv)

######################################################################
# Verilator Setting
######################################################################

ifeq ($(VERILATOR_ROOT),)
VERILATOR = verilator
VERILATOR_COVERAGE = verilator_coverage
else
export VERILATOR_ROOT
VERILATOR = $(VERILATOR_ROOT)/bin/verilator
VERILATOR_COVERAGE = $(VERILATOR_ROOT)/bin/verilator_coverage
endif

VERILATOR_FLAGS += --cc --exe
VERILATOR_FLAGS += -I./include
VERILATOR_FLAGS += --build
VERILATOR_FLAGS += --trace-fst
VERILATOR_FLAGS += --trace-max-array 1024
VERILATOR_FLAGS += --debug

CXXFLAGS += -g

# Optional optimization
# VERILATOR_FLAGS += -x-assign fast

# Optional lint warning
# VERILATOR_FLAGS += -Wall
# VERILATOR_FLAGS += -Wall -Wno-lint

LOG_FILE ?= logs/terminal_text.log
POST_PROCESS :=
EXTRA_DEFINES ?=

######################################################################
# Select Verilator Target
######################################################################

ifneq ($(PE),)
VERILATOR_FLAGS += -CFLAGS "-DTB_PE=$(PE) $(EXTRA_DEFINES)"
LOG_FILE = logs/terminal_text_pe$(PE).log
VERILATOR_INPUT = $(SRC1) ./testbench/tb_PE.cpp
TARGET = VPE
POST_PROCESS = @chmod 666 ./testbench/tb_PE.cpp
else ifneq ($(ARRAY),)
VERILATOR_FLAGS += -CFLAGS "-DTBA=$(ARRAY) $(EXTRA_DEFINES)"
LOG_FILE = logs/terminal_text_array$(ARRAY).log
VERILATOR_INPUT = $(SRC2) ./testbench/tb_array.cpp
TARGET = VPE_array
POST_PROCESS = @chmod 666 ./testbench/tb_array.cpp
else ifneq ($(PPU),)
VERILATOR_FLAGS += -CFLAGS "-DTB_PPU=$(PPU) $(EXTRA_DEFINES)"
VERILATOR_INPUT = $(SRC3) ./testbench/tb_PPU.cpp
TARGET = VPPU
LOG_FILE = logs/terminal_text_ppu$(PPU).log
POST_PROCESS = @chmod 666 ./testbench/tb_PPU.cpp
endif

######################################################################
# FSDB / PASS / GUI Setting
######################################################################

FSDB_DEF :=
ifeq ($(WV),1)
FSDB_DEF := FSDB
else ifeq ($(WV),2)
FSDB_DEF := FSDB_ALL
endif

PASS_DEF :=
ifeq ($(PASS),1)
PASS_DEF := PASS_TEST
else
PASS_DEF := NONE
endif

GUI_MODE :=
ifeq ($(GUI),1)
GUI_MODE := -gui
endif

######################################################################
# Default Target
######################################################################

default: all

######################################################################
# Phony Targets
######################################################################

.PHONY: default all clean mostlyclean distclean maintainer-clean
.PHONY: pe_all array_all ppu_all all_classroom
.PHONY: pe_all_classroom array_all_classroom ppu_all_classroom
.PHONY: run format show-config dist maintainer-copy
.PHONY: array% pe% ppu%
.PHONY: array_classroom% pe_classroom% ppu_classroom%
.PHONY: synthesize synthesize_PE synthesize_PE_ori synthesize_PE_array spyglass pt wave

######################################################################
# Folder Creation
######################################################################

$(wv_dir):
	@mkdir -p $(wv_dir)

$(bld_dir):
	@mkdir -p $(bld_dir)

$(syn_dir):
	@mkdir -p $(syn_dir)

######################################################################
# Verilator Group Targets
######################################################################

pe_all: pe0 pe1 pe2
array_all: array0 array1 array2 array3 array4 array5
ppu_all: ppu0 ppu1 ppu2

pe_all_classroom: pe_classroom0 pe_classroom1 pe_classroom2
array_all_classroom: array_classroom0 array_classroom1 array_classroom2 array_classroom3 array_classroom4 array_classroom5
ppu_all_classroom: ppu_classroom0 ppu_classroom1 ppu_classroom2

all: pe_all array_all ppu_all
all_classroom: pe_all_classroom array_all_classroom ppu_all_classroom

######################################################################
# Verilator Run
######################################################################

run:
	@echo
	@echo "-- Verilator Start"

	@echo
	@echo "-- VERILATE ----------------"
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_INPUT)

	@echo
	@echo "-- RUN ---------------------"
	@mkdir -p logs
	@mkdir -p wave
	obj_dir/$(TARGET) +trace > $(LOG_FILE)

	$(POST_PROCESS)

	@echo
	@echo "-- DONE --------------------"
	@echo "To see waveforms, open *.fst in a waveform viewer"
	@echo

######################################################################
# Specific Testbench Targets
######################################################################

pe%:
	$(MAKE) run PE=$*

array%:
	$(MAKE) run ARRAY=$*

ppu%:
	$(MAKE) run PPU=$*

######################################################################
# Github Classroom Testbench Targets
######################################################################

pe_classroom%:
	$(MAKE) run PE=$* EXTRA_DEFINES="-DCLASSROOM_MODE=1"

array_classroom%:
	$(MAKE) run ARRAY=$* EXTRA_DEFINES="-DCLASSROOM_MODE=1"

ppu_classroom%:
	$(MAKE) run PPU=$* EXTRA_DEFINES="-DCLASSROOM_MODE=1"

######################################################################
# Format / Config / Release
######################################################################

format:
	clang-format -i testbench/*.cpp testbench/*.h
	@chmod 666 ./testbench/*.cpp
	@chmod 666 ./testbench/*.h

show-config:
	$(VERILATOR) -V

dist:
	$(MAKE) clean
	python release.py
	cd release && zip -r ../aoc2025-lab3.zip .

maintainer-copy::

######################################################################
# Synopsys Design Compiler / PrimeTime / SpyGlass
######################################################################

#======================================================================
# Generic synthesis target
# Usage examples:
#   make synthesize SYN_TOP=PE        SYN_SRC=src/PE_array/PE.sv
#   make synthesize SYN_TOP=PE_origin SYN_SRC=src/PE_array/PE_origin.sv SYN_OUT=PE_ori
#   make synthesize SYN_TOP=PPU       SYN_SRC=src/PPU/PPU.sv
#   make synthesize SYN_TOP=PE_array  SYN_SRC="src/PE_array/PE.sv src/PE_array/PE_array.sv"
#
# SYN_TOP : top module name used by elaborate/current_design
# SYN_SRC : RTL files, separated by spaces
# SYN_OUT : output/report prefix. Default = SYN_TOP
#======================================================================

SYN_TOP ?= PE
SYN_SRC ?= src/PE_array/$(SYN_TOP).sv
SYN_OUT ?= $(SYN_TOP)

# Export these Makefile variables so Tcl can read them through $::env(...)
export SYN_TOP
export SYN_SRC
export SYN_OUT

synthesize: $(syn_dir) $(bld_dir)
	@echo "SYN_TOP = $(SYN_TOP)"
	@echo "SYN_SRC = $(SYN_SRC)"
	@echo "SYN_OUT = $(SYN_OUT)"
	cp script/synopsys_dc.setup $(bld_dir)/.synopsys_dc.setup
	cd $(bld_dir) && dc_shell -no_home_init -f ../script/synthesis.tcl

# Backward-compatible shortcuts
synthesize_PE:
	$(MAKE) synthesize SYN_TOP=PE SYN_SRC="src/PE_array/PE.sv" SYN_OUT=PE

synthesize_PE_ori:
	$(MAKE) synthesize SYN_TOP=PE_ori SYN_SRC="src/PE_array/PE_origin.sv" SYN_OUT=PE_ori

synthesize_PE_array:
	$(MAKE) synthesize \
		SYN_TOP=PE_array \
		SYN_SRC="src/PE_array/GIN/GIN_MulticastController.sv \
src/PE_array/GIN/GIN_Bus.sv \
src/PE_array/GIN/GIN.sv \
src/PE_array/GON/GON_MulticastController.sv \
src/PE_array/GON/GON_Bus_full_throughput_pipeline.sv \
src/PE_array/GON/GON_full_throughput_pipeline.sv \
src/PE_array/PE_LEE.sv \
src/PE_array/PE_array.sv" \
		SYN_OUT=PE_array

synthesize_PE_LEE:
	$(MAKE) synthesize SYN_TOP=PE_LEE SYN_SRC="src/PE_array/PE_LEE.sv" SYN_OUT=PE_LEE

spyglass: $(bld_dir)
	@cd $(bld_dir); \
	spyglass &

pt: $(bld_dir)
	cp script/synopsys_pt.setup $(bld_dir)/.synopsys_pt.setup; \
	pt_shell $(GUI_MODE) -f ./script/pt.tcl

wave:
	@cd $(wv_dir); \
	nWave &

######################################################################
# Clean
######################################################################

clean mostlyclean distclean maintainer-clean::
	-rm -rf obj_dir
	-rm -rf logs
	-rm -rf *.log
	-rm -rf *.dmp
	-rm -rf *.vpd
	-rm -rf coverage.dat
	-rm -rf core
	-rm -rf wave/*.vcd
	-rm -rf wave/*.fst
	-rm -rf wave/*.fsdb
	-rm -rf $(wv_dir)
	-rm -rf $(bld_dir)

######################################################################
# Color Setting
######################################################################

RED    = \033[1;31m
BLUE   = \033[1;34m
NORMAL = \033[0m