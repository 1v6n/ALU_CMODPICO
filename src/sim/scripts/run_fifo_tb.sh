#!/usr/bin/env bash
# Script para compilar y ejecutar el testbench del FIFO con Icarus Verilog.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build"
OUTPUT="${BUILD_DIR}/tb_sync_fifo.vvp"

mkdir -p "${BUILD_DIR}"

IVERILOG_BIN="${IVERILOG:-iverilog}"
VVP_BIN="${VVP:-vvp}"

echo "[INFO] Compilando testbench sync_fifo..."
"${IVERILOG_BIN}" -g2012 \
    -o "${OUTPUT}" \
    "${REPO_ROOT}/src/rtl/sync_fifo.sv" \
    "${REPO_ROOT}/src/sim/sv/tb_sync_fifo.sv"

echo "[INFO] Ejecutando simulación..."
"${VVP_BIN}" "${OUTPUT}"

echo "[INFO] Simulación finalizada."
