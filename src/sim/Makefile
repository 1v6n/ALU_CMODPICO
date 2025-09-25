# @file Makefile
# @brief Script de compilación para simulación Verilator de ALU.
# Este Makefile compila el testbench C++ con el módulo Verilog ALU usando Verilator,
# genera ejecutable, soporta volcado VCD y limpieza. Módulo superior: alu_top.

# @var VERILATOR: Herramienta Verilator para compilación de Verilog a C++
VERILATOR = verilator

# @var VERILATOR_FLAGS: Flags para Verilator (soporte SV, warnings, compilación C++, ejecutable, jobs paralelos, trace VCD)
VERILATOR_FLAGS  = --sv -Wall --cc --exe --build -j --trace

# @var TOP_MODULE: Módulo superior para simulación (debe ser alu_top)
TOP_MODULE = alu_top

# @var VERILOG_SOURCES: Lista de archivos fuente Verilog, incluyendo paquete y sub-módulos
VERILOG_SOURCES = \
	../rtl/alu_pkg.v \
	../rtl/alu_top.v \
	../rtl/alu.v \
	../rtl/arithmetic_unit.v \
	../rtl/logical_unit.v \
	../rtl/shifter_unit.v \
	../rtl/alu_register_bank.v 

# @var CPP_SOURCES: Archivo de testbench en C++
CPP_SOURCES = tb_alu.cpp

# @var TARGET: Nombre del ejecutable generado (V + TOP_MODULE)
TARGET = V$(TOP_MODULE)

# @target all: Compila el proyecto Verilator (objetivo por defecto)
all: obj_dir/$(TARGET)

# @target obj_dir/$(TARGET): Regla implícita para construir el ejecutable
# Verilator maneja la vinculación automáticamente con --build
obj_dir/$(TARGET):
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) \
	  $(VERILOG_SOURCES) $(CPP_SOURCES)

# @target run: Ejecuta la simulación compilada
run: obj_dir/$(TARGET)
	./obj_dir/$(TARGET)

# @target wave: Visualiza formas de onda VCD con GTKWave
wave:
	gtkwave dump.vcd

# @target clean: Limpia archivos generados (obj_dir y VCD)
clean:
	rm -rf obj_dir *.vcd

# @brief Targets falsos (phony) para evitar conflictos con nombres de archivos
.PHONY: all run wave clean
