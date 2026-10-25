# ==============================================================================
# File: Makefile
# Description: Multi-tool verification & synthesis Makefile for macOS environment.
# Tools supported: Icarus Verilog (iverilog/vvp), Verilator, Yosys, GTKWave.
# ==============================================================================

SHELL := /bin/bash
export PATH := /opt/homebrew/bin:$(PATH)

IVERILOG ?= $(shell which iverilog 2>/dev/null || echo /opt/homebrew/bin/iverilog)
VVP      ?= $(shell which vvp 2>/dev/null || echo /opt/homebrew/bin/vvp)
YOSYS    ?= $(shell which yosys 2>/dev/null || echo /opt/homebrew/bin/yosys)
GTKWAVE  ?= $(shell which gtkwave 2>/dev/null || echo /opt/homebrew/bin/gtkwave)

# Directories
RTL_DIR  = ../rtl
CORE_DIR = $(RTL_DIR)/core
BUS_DIR  = $(RTL_DIR)/bus
CACHE_DIR= $(RTL_DIR)/cache
TB_DIR   = ../tb
PROG_DIR = $(TB_DIR)/programs

# Source File Lists
PKG_SRCS = $(CORE_DIR)/rv32i_types_pkg.sv

RTL_SRCS = \
	$(CORE_DIR)/branch_predictor.sv \
	$(CORE_DIR)/stage_if.sv \
	$(CORE_DIR)/pipe_reg_if_id.sv \
	$(CORE_DIR)/stage_id.sv \
	$(CORE_DIR)/pipe_reg_id_ex.sv \
	$(CORE_DIR)/stage_ex.sv \
	$(CORE_DIR)/hazard_unit.sv \
	$(CORE_DIR)/pipe_reg_ex_mem.sv \
	$(CORE_DIR)/stage_mem.sv \
	$(CORE_DIR)/pipe_reg_mem_wb.sv \
	$(CORE_DIR)/stage_wb.sv \
	$(BUS_DIR)/axi4_lite_master.sv \
	$(CACHE_DIR)/l1_dcache.sv \
	$(CORE_DIR)/rv32i_core.sv

TB_SRCS = $(TB_DIR)/tb_rv32i_top.sv

ALL_SRCS = $(PKG_SRCS) $(RTL_SRCS) $(TB_SRCS)

# Targets
SIM_BIN     = sim_rv32i.vvp
VCD_FILE    = rv32i_trace.vcd
SYNTH_NET   = rv32i_core_synth.v

.PHONY: all sim iverilog verilator synth wave clean help

all: sim

help:
	@echo "=================================================================="
	@echo "  RV32I 5-Stage Core Open-Source Build System                    "
	@echo "=================================================================="
	@echo "  make sim        : Compile and run simulation with Icarus Verilog"
	@echo "  make synth      : Synthesize RV32I core with Yosys              "
	@echo "  make wave       : View VCD waveforms in GTKWave (macOS)         "
	@echo "  make clean      : Remove simulation binaries, waveforms & logs  "
	@echo "=================================================================="

# ------------------------------------------------------------------------------
# Icarus Verilog Simulation
# ------------------------------------------------------------------------------
$(SIM_BIN): $(ALL_SRCS)
	@echo "==> Compiling SystemVerilog design with Icarus Verilog..."
	$(IVERILOG) -g2012 -Wall -I $(CORE_DIR) -I $(TB_DIR) -s tb_rv32i_top -o $(SIM_BIN) $(ALL_SRCS)

sim: $(SIM_BIN)
	@echo "==> Executing simulation with VVP..."
	$(VVP) $(SIM_BIN)

iverilog: sim

# ------------------------------------------------------------------------------
# Yosys Synthesis
# ------------------------------------------------------------------------------
synth:
	@echo "==> Running Yosys open-source synthesis..."
	$(YOSYS) -s synth.ys > yosys_synth.log 2>&1
	@echo "==> Synthesis Complete. Log saved to sim/yosys_synth.log"
	@grep -A 25 "=== rv32i_core ===" yosys_synth.log || tail -n 35 yosys_synth.log

# ------------------------------------------------------------------------------
# GTKWave Waveform Viewer (macOS compatible)
# ------------------------------------------------------------------------------
wave:
	@if [ -f "$(VCD_FILE)" ]; then \
		echo "==> Opening $(VCD_FILE) in GTKWave..."; \
		$(GTKWAVE) $(VCD_FILE) & \
	else \
		echo "ERROR: Waveform file $(VCD_FILE) not found. Run 'make sim' first."; \
	fi

# ------------------------------------------------------------------------------
# Clean
# ------------------------------------------------------------------------------
clean:
	@echo "==> Cleaning generated simulation & synthesis files..."
	rm -rf $(SIM_BIN) $(VCD_FILE) rv32i_trace_verilator.vcd $(SYNTH_NET) yosys_synth.log
