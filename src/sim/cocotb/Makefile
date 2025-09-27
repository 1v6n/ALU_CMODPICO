TOPLEVEL_LANG ?= verilog
SIM ?= verilator

RTL_DIR := $(abspath ../../rtl)

VERILOG_SOURCES := \
	$(RTL_DIR)/alu_pkg.v \
	$(RTL_DIR)/alu_register_bank.v \
	$(RTL_DIR)/alu.v \
	$(RTL_DIR)/alu_top.v \
	$(RTL_DIR)/arithmetic_unit.v \
	$(RTL_DIR)/logical_unit.v \
	$(RTL_DIR)/shifter_unit.v

TOPLEVEL := alu_top
MODULE := test_alu

EXTRA_ARGS += --trace
VERILATOR_COMPILE_ARGS += --sv --trace

include $(shell cocotb-config --makefiles)/Makefile.sim
