#!/usr/bin/env bash
# Script para compilar y correr el testbench de alu_top_fsm con Icarus Verilog.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
OUTPUT="${BUILD_DIR}/tb_alu_top_fsm.vvp"

mkdir -p "${BUILD_DIR}"

IVERILOG_BIN="${IVERILOG:-iverilog}"
VVP_BIN="${VVP:-vvp}"

echo "[INFO] Compilando testbench alu_top_fsm..."
"${IVERILOG_BIN}" -g2012 -I "${REPO_ROOT}/src/rtl" \
  -o "${OUTPUT}" \
  "${REPO_ROOT}/src/rtl/alu_pkg.v" \
  "${REPO_ROOT}/src/rtl/arithmetic_unit.v" \
  "${REPO_ROOT}/src/rtl/logical_unit.v" \
  "${REPO_ROOT}/src/rtl/shifter_unit.v" \
  "${REPO_ROOT}/src/rtl/alu.v" \
  "${REPO_ROOT}/src/rtl/alu_register_bank.v" \
  "${REPO_ROOT}/src/rtl/alu_top.v" \
  "${REPO_ROOT}/src/rtl/sync_fifo.sv" \
  "${REPO_ROOT}/src/rtl/uart_packet_decoder.sv" \
  "${REPO_ROOT}/src/rtl/alu_top_fsm.v" \
  "${REPO_ROOT}/src/sim/sv/tb_alu_top_fsm.sv"

echo "[INFO] Ejecutando simulación..."
"${VVP_BIN}" "${OUTPUT}"

echo "[INFO] Simulación completada."
