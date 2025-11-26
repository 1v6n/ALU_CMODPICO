#!/usr/bin/env bash
# Script para compilar y ejecutar el testbench del UART packet decoder con Icarus Verilog.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
OUTPUT="${BUILD_DIR}/tb_uart_packet_decoder.vvp"

mkdir -p "${BUILD_DIR}"

IVERILOG_BIN="${IVERILOG:-iverilog}"
VVP_BIN="${VVP:-vvp}"

echo "[INFO] Compilando testbench uart_packet_decoder..."
"${IVERILOG_BIN}" -g2012 -I "${REPO_ROOT}/src/rtl" \
    -o "${OUTPUT}" \
    "${REPO_ROOT}/src/rtl/sync_fifo.sv" \
    "${REPO_ROOT}/src/rtl/uart_packet_decoder.sv" \
    "${REPO_ROOT}/src/rtl/alu_timescale.vh" \
    "${REPO_ROOT}/src/sim/sv/tb_uart_packet_decoder.sv"

echo "[INFO] Ejecutando simulación..."
"${VVP_BIN}" "${OUTPUT}"

echo "[INFO] Simulación finalizada."
