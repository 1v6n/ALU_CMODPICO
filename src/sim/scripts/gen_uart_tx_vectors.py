#!/usr/bin/env python3
"""
@file gen_uart_tx_vectors.py
@brief Genera el include de vectores de prueba para el transmisor UART (uart_tx)

@details Script autónomo que construye un archivo include SystemVerilog con los
datos de prueba necesarios para validar el módulo `uart_tx`. Se inspira en la
filosofía del generador de la ALU: mantener un "modelo dorado" simple y
producir artefactos fáciles de consumir desde el testbench.

Características principales:
- Produce un include (`uart_tx_test_vectors.svh`) con arrays paralelos de datos
    (solo DATA de 8 bits). El testbench calcula el frame esperado internamente.
- Cubre tres modos de paridad: `none`, `even`, `odd`.
- Para cada modo genera 6 casos smoke + 9 casos aleatorios (15 por modo,
    45 totales), con semillas fijas para reproducibilidad.

Estructura del frame (serializado por el DUT/testbench):
- START (0) + DATA[LSB→MSB] + [PARITY] + STOP (1)

Paridad (calculada exclusivamente sobre DATA):
- even → bit de paridad = XOR(DATA)
- odd  → bit de paridad = ~XOR(DATA)
- none → no se agrega bit de paridad

Salida generada:
- Archivo: `src/sim/sv/uart_tx_test_vectors.svh`
- Contenido por modo (`none`, `even`, `odd`):
    - `localparam int NUM_SMOKE_*`, `NUM_RANDOM_*`, `FRAME_BITS_*`
    - `logic [7:0] smoke_data_*[...]` y `random_data_*[...]` inicializados

Suposiciones y alcance:
- DATA es de 8 bits y STOP es 1 bit (alineado al RTL/TB actual).
- El include no contiene frames ni paridad precalculada; eso lo hace el TB.

Uso:
- Ejecutar directamente desde el repositorio del proyecto:
        python src/sim/scripts/gen_uart_tx_vectors.py
    El script creará/actualizará `src/sim/sv/uart_tx_test_vectors.svh`.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import List
import random
import argparse

# --- Parámetros configurables ---
# Cantidad de vectores aleatorios por modo (se suman a los 6 smoke)
NUM_RANDOM_VECTORS = 9

# Ruta de salida del include generado (relativa al directorio de este script)
OUTPUT_PATH = Path(__file__).resolve().parents[1] / "sv" / "uart_tx_test_vectors.svh"

# --- Smoke tests predefinidos (nombre, data) ---
# Casos representativos y fáciles de depurar.
SMOKE_CASES = [
    ("BASIC_1F", 0x1F),
    ("ALL_ZERO", 0x00),
    ("MSB_SET", 0x80),
    ("ALL_ONES", 0xFF),
    ("ALT_55", 0x55),
    ("ALT_AA", 0xAA),
]


@dataclass
class TxVector:
    """Representa un vector de prueba para un modo de paridad.

    Atributos:
    - name: nombre del caso (p. ej., "BASIC_1F", "RND_0").
    - data: valor de datos de 8 bits (0..255).
    - frame: frame serial empaquetado (LSB-first), de 10 o 11 bits según paridad.
             Nota: este campo se utiliza solo para documentación/generación auxiliar;
             el include final exporta únicamente los arrays de `data`.
    """

    name: str
    data: int  # 8 bits
    frame: int  # 10 o 11 bits dependiendo de paridad


def compute_parity(data: int, mode: str) -> int:
    """Calcula el bit de paridad exclusivamente sobre `data` (8 bits).

    Parámetros:
    - data: entero de 8 bits (0..255).
    - mode: "even", "odd" o "none".

    Retorna:
    - 0/1 con el bit de paridad para `even`/`odd`. Para `none` retorna 0.
    """
    xor_all = 0
    for i in range(8):
        xor_all ^= (data >> i) & 0x1
    if mode == "even":
        return xor_all  # 1 si count impar -> hace total par
    elif mode == "odd":
        return 1 - xor_all
    else:
        return 0


def build_frame(data: int, parity_mode: str) -> int:
    """Construye el frame serial empaquetado (LSB-first).

    Formato: START(0) + DATA[7:0] + [PARITY] + STOP(1)

    Retorna:
    - Entero con 10 bits (sin paridad) o 11 bits (con paridad) empaquetados.
    """
    frame = 0
    bit_pos = 0

    # START bit (0)
    frame |= 0 << bit_pos
    bit_pos += 1

    # DATA bits LSB-first
    for i in range(8):
        frame |= ((data >> i) & 0x1) << bit_pos
        bit_pos += 1

    # PARITY opcional
    if parity_mode != "none":
        parity_bit = compute_parity(data, parity_mode)
        frame |= parity_bit << bit_pos
        bit_pos += 1

    # STOP bit (1 único)
    frame |= 1 << bit_pos
    bit_pos += 1

    return frame


def build_vectors(parity_mode: str) -> List[TxVector]:
    """Genera la lista de vectores (smoke + random) para un modo.

    - `parity_mode` debe ser uno de: "none", "even", "odd".
    - Usa semillas fijas por modo para reproducibilidad.
    """
    vectors: List[TxVector] = []

    # Smoke
    for name, data in SMOKE_CASES:
        frame = build_frame(data, parity_mode)
        vectors.append(TxVector(name, data & 0xFF, frame))

    # Random (semilla fija para reproducibilidad)
    seed_map = {"none": 1234, "even": 2234, "odd": 3234}
    rng = random.Random(seed_map[parity_mode])
    for idx in range(NUM_RANDOM_VECTORS):
        data = rng.randrange(0, 256)
        frame = build_frame(data, parity_mode)
        vectors.append(TxVector(f"RND_{idx}", data, frame))

    return vectors


def get_frame_bits(parity_mode: str) -> int:
    """Devuelve la cantidad de bits del frame (10 para none, 11 para even/odd)."""
    bits = 1 + 8 + 1  # START + DATA + STOP(1)
    if parity_mode != "none":
        bits += 1
    return bits


def write_include_multi_mode() -> None:
    """Genera el include SystemVerilog con vectores para los 3 modos.

    Estructura del include por modo:
    - `localparam int NUM_SMOKE_*`, `NUM_RANDOM_*`, `FRAME_BITS_*`
    - `logic [7:0] smoke_data_* [0:NUM_SMOKE_*-1];` (con bloque initial)
    - `logic [7:0] random_data_* [0:NUM_RANDOM_*-1];` (con bloque initial)
    """
    lines: List[str] = []
    lines.append(
        "/* Auto-generated by scripts/gen_uart_tx_vectors.py. Do not edit manually. */"
    )
    lines.append("`ifndef UART_TX_TEST_VECTORS_SVH")
    lines.append("`define UART_TX_TEST_VECTORS_SVH")
    lines.append("")
    lines.append("// Stop bits: 1")
    lines.append("// Vectores por modo: 6 smoke + 9 random = 15 x 3 modos = 45 total")
    lines.append("")

    # Generar vectores para cada modo
    for parity_mode in ["none", "even", "odd"]:
        vectors = build_vectors(parity_mode)
        frame_bits = get_frame_bits(parity_mode)
        mode_suffix = parity_mode

        # Separar smoke y random
        smoke = [v for v in vectors if not v.name.startswith("RND_")]
        rnd = [v for v in vectors if v.name.startswith("RND_")]

        lines.append(
            f"// ========== Parity mode: {parity_mode.upper()} (frame bits: {frame_bits}) =========="
        )
        lines.append(f"localparam int NUM_SMOKE_{mode_suffix.upper()} = {len(smoke)};")
        lines.append(f"localparam int NUM_RANDOM_{mode_suffix.upper()} = {len(rnd)};")
        lines.append(f"localparam int FRAME_BITS_{mode_suffix.upper()} = {frame_bits};")
        lines.append("")

        # Arrays paralelos para smoke (solo data; el TB calcula el frame esperado)
        lines.append(
            f"logic [7:0] smoke_data_{mode_suffix} [0:NUM_SMOKE_{mode_suffix.upper()}-1];"
        )
        lines.append("")
        lines.append("initial begin")
        for i, v in enumerate(smoke):
            lines.append(
                f"    smoke_data_{mode_suffix}[{i}] = 8'h{v.data:02X}; // {v.name}"
            )
        lines.append("end")
        lines.append("")

        # Arrays paralelos para random (solo data)
        lines.append(
            f"logic [7:0] random_data_{mode_suffix} [0:NUM_RANDOM_{mode_suffix.upper()}-1];"
        )
        lines.append("")
        lines.append("initial begin")
        for i, v in enumerate(rnd):
            lines.append(
                f"    random_data_{mode_suffix}[{i}] = 8'h{v.data:02X}; // {v.name}"
            )
        lines.append("end")
        lines.append("")

    lines.append("`endif // UART_TX_TEST_VECTORS_SVH")
    lines.append("")

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text("\n".join(lines))


def parse_args() -> argparse.Namespace:
    """Analiza argumentos de línea de comandos.

    Actualmente no expone opciones; se mantiene por simetría/escabilidad.
    """
    p = argparse.ArgumentParser(description="Generador de vectores UART TX (stop=1)")
    return p.parse_args()


def main() -> None:
    """Punto de entrada del script: genera el include y reporta el resumen."""
    parse_args()
    write_include_multi_mode()
    total_vectors = (len(SMOKE_CASES) + NUM_RANDOM_VECTORS) * 3  # 3 modos
    print(
        f"✓ Generados {total_vectors} vectores totales (15 por modo × 3 modos) en {OUTPUT_PATH}"
    )
    print("  - 6 smoke + 9 random para NONE, EVEN, ODD")
    print("  - Stop bits: 1")


if __name__ == "__main__":
    main()
