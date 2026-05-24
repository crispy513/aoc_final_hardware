Project := eyeriss_pipeline
ROOT_DIR := $(CURDIR)

VC := vcs
DEBUG_VIEW := nWave

TB_DIR := testbench
TOP_TB_FILE := $(ROOT_DIR)/$(TB_DIR)/tb_top_with_glb.sv
ENCODER_TB_FILE := $(ROOT_DIR)/$(TB_DIR)/tb_sparse_encoder.sv
DECODER_TB_FILE := $(ROOT_DIR)/$(TB_DIR)/tb_sparse_decoder.sv
NOC_TB_FILE := $(ROOT_DIR)/$(TB_DIR)/tb_noc.sv
RSLT_DIR := simulation
VECTOR ?=

ifeq ($(strip $(VECTOR)),)
INPUT_FILE := $(TB_DIR)/input.txt
GOLDEN_FILE := $(TB_DIR)/golden.txt
else
INPUT_FILE := $(TB_DIR)/$(VECTOR)_input.txt
GOLDEN_FILE := $(TB_DIR)/$(VECTOR)_golden.txt
endif

TOP_RUN_ARGS := +INPUT_FILE=$(INPUT_FILE) +GOLDEN_FILE=$(GOLDEN_FILE)

INC_DIRS := .
MACROS :=
WAVE ?= fsdb

ifeq ($(DUMP), 1)
ifeq ($(WAVE), fsdb)
MACROS += FSDB
else
MACROS += WV_NORMAL
endif
endif

MACROS_FLAG := $(addprefix +define+, $(MACROS))
INC_DIR_FLAG := $(addprefix +incdir+$(ROOT_DIR)/, $(INC_DIRS))
VCSFLAGS := -R -sverilog -debug_access+all -debug_region+cell -full64 $(INC_DIR_FLAG) $(MACROS_FLAG)

.PHONY: all check_vectors vcs top encoder decoder noc standalone wave clean help

all: vcs

$(RSLT_DIR):
	@mkdir -p $(RSLT_DIR)

check_vectors:
	@test -f $(INPUT_FILE) || (echo "Missing $(INPUT_FILE). Please provide it before top simulation."; exit 1)
	@test -f $(GOLDEN_FILE) || (echo "Missing $(GOLDEN_FILE). Please provide it before top simulation."; exit 1)

vcs top: check_vectors $(RSLT_DIR)
	@$(VC) $(VCSFLAGS) -o $(RSLT_DIR)/simv_top $(TOP_TB_FILE) $(TOP_RUN_ARGS)

encoder: $(RSLT_DIR)
	@$(VC) $(VCSFLAGS) -o $(RSLT_DIR)/simv_encoder $(ENCODER_TB_FILE)

decoder: $(RSLT_DIR)
	@$(VC) $(VCSFLAGS) -o $(RSLT_DIR)/simv_decoder $(DECODER_TB_FILE)

noc: $(RSLT_DIR)
	@$(VC) $(VCSFLAGS) -o $(RSLT_DIR)/simv_noc $(NOC_TB_FILE)

standalone: encoder decoder noc

wave: $(RSLT_DIR)
	@$(DEBUG_VIEW) &

clean:
	@rm -rf $(RSLT_DIR)
	@rm -f $(TB_DIR)/*.vcd
	@rm -f $(RSLT_DIR)/*.fsdb
	@rm -rf csrc simv simv.daidir ucli.key novas.* verdiLog

help:
	@echo "Targets:"
	@echo "  make / make vcs      Run top-level testbench with VCS"
	@echo "  make top VECTOR=simple  Run the hand-checkable top-level vector"
	@echo "  make encoder         Run SparseEncoder standalone testbench"
	@echo "  make decoder         Run SparseDecoder standalone testbench"
	@echo "  make noc             Run NoC GIN/GON standalone testbench"
	@echo "  make standalone      Run encoder, decoder, and noc tests"
	@echo "  make <target> DUMP=1  Run target and dump FSDB waveform"
	@echo "  make <target> DUMP=1 WAVE=vcd  Run target and dump VCD waveform"
	@echo "  make wave            Open nWave"
	@echo "  make clean           Remove simulation outputs"
