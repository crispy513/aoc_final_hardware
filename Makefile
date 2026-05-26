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
.PHONY: synthesize_PE synthesize_PE_ori spyglass pt wave

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

synthesize_PE: $(syn_dir) $(bld_dir)
	cp script/synopsys_dc.setup $(bld_dir)/.synopsys_dc.setup; \
	cd $(bld_dir); \
	dc_shell -no_home_init -f ../script/synthesis_PE.tcl

synthesize_PE_ori: $(syn_dir) $(bld_dir)
	cp script/synopsys_dc.setup $(bld_dir)/.synopsys_dc.setup; \
	cd $(bld_dir); \
	dc_shell -no_home_init -f ../script/synthesis_PE_ori.tcl

synthesize_PE_array: $(syn_dir) $(bld_dir)
	cp script/synopsys_dc.setup $(bld_dir)/.synopsys_dc.setup; \
	cd $(bld_dir); \
	dc_shell -no_home_init -f ../script/synthesis_PE_array.tcl
spyglass: $(bld_dir)
	@cd $(bld_dir); \
	spyglass &

pt: $(bld_dir)
	cp script/synopsys_pt.setup $(bld_dir)/.synopsys_pt.setup; \
	cd $(bld_dir); \
	pt_shell $(GUI_MODE) -f ../script/pt.tcl

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