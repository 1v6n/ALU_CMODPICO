#!/usr/bin/env python3
"""
@file gen_uart_rx_vectors.py
@brief Genera el include de vectores de prueba para el receptor UART (uart_rx)

@details Script autónomo que construye un archivo include SystemVerilog con los
datos de prueba necesarios para validar el módulo `uart_rx`. Se inspira en la
filosofía del generador del transmisor UART: mantener un "modelo dorado" simple
y producir artefactos fáciles de consumir desde el testbench.

Características principales:
- Produce un include (`uart_rx_test_vectors.svh`) con arrays paralelos:
    * datos esperados a la salida (DATA de 8 bits)
    * frames seriales completos (10/11 bits empaquetados) para inyectar
    * flags de error esperados (paridad y frame)
- Cubre tres modos de paridad: `none`, `even`, `odd`.
- Para cada modo genera:
    * 6 casos smoke (casos básicos predefinidos)
    * 9 casos aleatorios (con semillas fijas para reproducibilidad)
    * Casos de error: 1 frame error para todos, +1 parity error para even/odd
- Total: 16 vectores (NONE) + 17 vectores (EVEN) + 17 vectores (ODD) = 50 vectores

Estructura del frame (recibido por el DUT):
- START (0) + DATA[LSB→MSB] + [PARITY] + STOP (1)
- Frame empaquetado en formato LSB-first para inyección serial

Paridad (calculada exclusivamente sobre DATA):
- even → bit de paridad = XOR(DATA)
- odd  → bit de paridad = ~XOR(DATA)
- none → no se agrega bit de paridad

Casos de error generados:
- Parity error: se invierte el bit de paridad calculado (solo even/odd)
- Frame error: se pone el bit de STOP en 0 en lugar de 1 (todos los modos)

Salida generada:
- Archivo: `src/sim/sv/uart_rx_test_vectors.svh`
- Contenido por modo (`none`, `even`, `odd`):
    - Constantes: `NUM_SMOKE_*`, `NUM_RANDOM_*`, `NUM_ERROR_*`, `FRAME_BITS_*`
    - Casos válidos (smoke):
        * `logic [7:0] smoke_data_*[...]` - datos esperados a la salida
        * `logic [10:0] smoke_frame_*[...]` - frames seriales a inyectar
    - Casos válidos (random):
        * `logic [7:0] random_data_*[...]` - datos esperados a la salida
        * `logic [10:0] random_frame_*[...]` - frames seriales a inyectar
    - Casos de error:
        * `logic [7:0] error_data_*[...]` - datos esperados a la salida
        * `logic [10:0] error_frame_*[...]` - frames seriales a inyectar
        * `logic error_parity_flag_*[...]` - flags de error de paridad esperados
        * `logic error_frame_flag_*[...]` - flags de error de frame esperados

Suposiciones y alcance:
- DATA es de 8 bits y STOP es 1 bit (alineado al RTL/TB actual).
- Los frames se empaquetan en formato LSB-first para facilitar inyección serial.
- Todos los arrays se inicializan en bloques `initial` para facilitar depuración.

Uso:
- Ejecutar directamente desde el repositorio del proyecto:
        python src/sim/scripts/gen_uart_rx_vectors.py
    El script creará/actualizará `src/sim/sv/uart_rx_test_vectors.svh`.
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
OUTPUT_PATH = Path(__file__).resolve().parents[1] / "sv" / "uart_rx_test_vectors.svh"

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
class RxVector:
    """Representa un vector de prueba para el receptor UART en un modo de paridad.

    Atributos:
    - name: Nombre descriptivo del caso de prueba (p. ej., "BASIC_1F", "RND_0", "PERR", "FERR").
    - data: Valor de datos de 8 bits (0..255) esperado a la salida del receptor (dout).
    - frame: Frame serial empaquetado en formato LSB-first, de 10 bits (sin paridad)
             o 11 bits (con paridad), que se inyecta a la entrada serie del DUT.
             Estructura: START(0) + DATA[LSB→MSB] + [PARITY] + STOP(1).
    - expect_parity_error: Flag booleano que indica si se espera que el DUT detecte
                           error de paridad (True) o no (False). Solo relevante para
                           casos de error con modos even/odd.
    - expect_frame_error: Flag booleano que indica si se espera que el DUT detecte
                          error de frame (True) o no (False). Se activa cuando el
                          bit de STOP es incorrecto (0 en lugar de 1).
    """

    name: str
    data: int  # 8 bits
    frame: int  # 10 o 11 bits dependiendo de paridad
    expect_parity_error: bool = False
    expect_frame_error: bool = False


def compute_parity(data: int, mode: str) -> int:
    """Calcula el bit de paridad exclusivamente sobre los datos (8 bits).

    La paridad se calcula mediante XOR de todos los bits de datos:
    - Even parity: el bit de paridad hace que el total de unos sea par
    - Odd parity: el bit de paridad hace que el total de unos sea impar
    - None: no se calcula paridad (retorna 0)

    Parámetros:
    - data: Entero de 8 bits (rango 0..255) sobre el que se calcula la paridad.
    - mode: Modo de paridad ("even", "odd" o "none").

    Retorna:
    - 0 o 1: bit de paridad para modos "even"/"odd".
    - 0: para modo "none" (sin paridad).

    Ejemplos:
    - compute_parity(0x55, "even") → 0 (0x55 tiene 4 unos, ya es par)
    - compute_parity(0x55, "odd") → 1 (necesita 1 para hacer total impar)
    - compute_parity(0xFF, "even") → 0 (0xFF tiene 8 unos, ya es par)
    """
    xor_all = 0
    for i in range(8):
        xor_all ^= (data >> i) & 0x1
    if mode == "even":
        return xor_all  # 1 si count impar → hace total par
    elif mode == "odd":
        return 1 - xor_all  # 1 si count par → hace total impar
    else:
        return 0  # Sin paridad


def build_frame(
    data: int,
    parity_mode: str,
    corrupt_parity: bool = False,
    corrupt_stop: bool = False,
) -> int:
    """Construye el frame serial UART empaquetado en formato LSB-first.

    El frame se construye bit a bit siguiendo el formato estándar UART:
    - Bit 0: START (siempre 0)
    - Bits 1-8: DATA[LSB→MSB] (8 bits de datos)
    - Bit 9 (opcional): PARITY (solo si parity_mode != "none")
    - Bit final: STOP (normalmente 1, puede corromperse para tests de error)

    Los bits se empaquetan en un entero con el bit menos significativo
    correspondiente al START bit, facilitando la inyección serial.

    Parámetros:
    - data: Datos de 8 bits (0..255) a transmitir.
    - parity_mode: Modo de paridad ("none", "even" o "odd").
    - corrupt_parity: Si True, invierte el bit de paridad calculado para
                      generar un caso de prueba con error de paridad.
                      Solo tiene efecto si parity_mode != "none".
    - corrupt_stop: Si True, pone el bit de STOP en 0 en lugar de 1 para
                    generar un caso de prueba con error de frame.

    Retorna:
    - Entero con el frame empaquetado:
        * 10 bits para parity_mode == "none" (START + 8 DATA + STOP)
        * 11 bits para parity_mode == "even"/"odd" (START + 8 DATA + PARITY + STOP)

    Ejemplos:
    - build_frame(0x55, "none") → 0x2AB (10 bits: 0|01010101|1)
    - build_frame(0x55, "even") → 0x2AB (11 bits: 0|01010101|0|1)
    - build_frame(0x55, "none", corrupt_stop=True) → 0x0AB (STOP=0)
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
        if corrupt_parity:
            parity_bit ^= 1  # Invertir para generar error
        frame |= parity_bit << bit_pos
        bit_pos += 1

    # STOP bit (1 por defecto, 0 si se corrompe)
    stop_bit = 0 if corrupt_stop else 1
    frame |= stop_bit << bit_pos
    bit_pos += 1

    return frame


def build_vectors(parity_mode: str) -> List[RxVector]:
    """Genera la lista completa de vectores de prueba para un modo de paridad.

    La lista incluye tres categorías de casos de prueba:
    1. Smoke cases (6): casos básicos predefinidos para validación rápida
       - BASIC_1F, ALL_ZERO, MSB_SET, ALL_ONES, ALT_55, ALT_AA
    2. Random cases (9): casos generados aleatoriamente con semilla fija
       - Garantiza reproducibilidad entre ejecuciones
       - Usa semillas diferentes por modo (1234, 2234, 3234)
    3. Error cases (1 o 2): casos con errores intencionales
       - Frame error (todos los modos): STOP bit incorrecto (0 en lugar de 1)
       - Parity error (solo even/odd): bit de paridad invertido

    Total por modo:
    - NONE: 6 smoke + 9 random + 1 frame_err = 16 vectores
    - EVEN: 6 smoke + 9 random + 1 parity_err + 1 frame_err = 17 vectores
    - ODD:  6 smoke + 9 random + 1 parity_err + 1 frame_err = 17 vectores

    Parámetros:
    - parity_mode: Modo de paridad a generar ("none", "even" o "odd").

    Retorna:
    - Lista de objetos RxVector con todos los casos de prueba para el modo.

    Raises:
    - Ninguna excepción explícita, pero asume que parity_mode es válido.
    """
    vectors: List[RxVector] = []

    # Smoke cases (casos válidos)
    for name, data in SMOKE_CASES:
        frame = build_frame(data, parity_mode)
        vectors.append(RxVector(name, data & 0xFF, frame, False, False))

    # Random cases (semilla fija para reproducibilidad)
    seed_map = {"none": 1234, "even": 2234, "odd": 3234}
    rng = random.Random(seed_map[parity_mode])
    for idx in range(NUM_RANDOM_VECTORS):
        data = rng.randrange(0, 256)
        frame = build_frame(data, parity_mode)
        vectors.append(RxVector(f"RND_{idx}", data, frame, False, False))

    # Error cases (solo para modos con paridad)
    if parity_mode != "none":
        # Caso de error de paridad
        data_perr = 0x42
        frame_perr = build_frame(data_perr, parity_mode, corrupt_parity=True)
        vectors.append(RxVector("PERR", data_perr, frame_perr, True, False))

    # Caso de error de frame (para todos los modos)
    data_ferr = 0x99
    frame_ferr = build_frame(data_ferr, parity_mode, corrupt_stop=True)
    vectors.append(RxVector("FERR", data_ferr, frame_ferr, False, True))

    return vectors


def get_frame_bits(parity_mode: str) -> int:
    """Calcula la cantidad total de bits en un frame UART según el modo de paridad.

    Estructura del frame:
    - START: 1 bit (siempre presente)
    - DATA: 8 bits (siempre presente)
    - PARITY: 1 bit (solo si parity_mode != "none")
    - STOP: 1 bit (siempre presente)

    Parámetros:
    - parity_mode: Modo de paridad ("none", "even" o "odd").

    Retorna:
    - 10: para modo "none" (START + 8 DATA + STOP)
    - 11: para modos "even"/"odd" (START + 8 DATA + PARITY + STOP)
    """
    bits = 1 + 8 + 1  # START + DATA + STOP
    if parity_mode != "none":
        bits += 1  # PARITY
    return bits


def write_include_multi_mode() -> None:
    """Genera el archivo include SystemVerilog con vectores para los 3 modos de paridad.

    El archivo generado (`uart_rx_test_vectors.svh`) contiene arrays paralelos organizados
    por modo de paridad (none, even, odd) y por categoría (smoke, random, error):

    Para cada modo se generan:
    1. Constantes de configuración:
       - NUM_SMOKE_*, NUM_RANDOM_*, NUM_ERROR_*: cantidad de vectores por categoría
       - FRAME_BITS_*: longitud del frame (10 bits para none, 11 para even/odd)

    2. Arrays de casos válidos (smoke y random):
       - *_data_*[]: datos esperados a la salida del DUT (8 bits)
       - *_frame_*[]: frames seriales completos a inyectar (10/11 bits)

    3. Arrays de casos de error:
       - error_data_*[]: datos esperados (8 bits)
       - error_frame_*[]: frames con errores intencionales (10/11 bits)
       - error_parity_flag_*[]: flags de error de paridad esperados (1 bit)
       - error_frame_flag_*[]: flags de error de frame esperados (1 bit)

    Todos los arrays se inicializan en bloques `initial` con comentarios que
    indican el nombre del caso de prueba para facilitar depuración.

    El archivo incluye guards `ifndef/define/endif` para evitar inclusión múltiple.

    Salida:
    - Archivo: src/sim/sv/uart_rx_test_vectors.svh
    - Total: 50 vectores (16 NONE + 17 EVEN + 17 ODD)
    """
    lines: List[str] = []
    lines.append(
        "/* Auto-generated by scripts/gen_uart_rx_vectors.py. Do not edit manually. */"
    )
    lines.append("`ifndef UART_RX_TEST_VECTORS_SVH")
    lines.append("`define UART_RX_TEST_VECTORS_SVH")
    lines.append("")
    lines.append("// Stop bits: 1")
    lines.append("// Vectores por modo: 6 smoke + 9 random + error cases")
    lines.append("// - NONE: 15 valid + 1 frame_err = 16 total")
    lines.append("// - EVEN/ODD: 15 valid + 1 parity_err + 1 frame_err = 17 total")
    lines.append("// Total: 16 + 17 + 17 = 50 vectores")
    lines.append("")

    # Generar vectores para cada modo
    for parity_mode in ["none", "even", "odd"]:
        vectors = build_vectors(parity_mode)
        frame_bits = get_frame_bits(parity_mode)
        mode_suffix = parity_mode

        # Separar smoke, random y error
        smoke = [
            v
            for v in vectors
            if not v.name.startswith("RND_")
            and not v.name.startswith("PERR")
            and not v.name.startswith("FERR")
        ]
        rnd = [v for v in vectors if v.name.startswith("RND_")]
        error = [
            v for v in vectors if v.name.startswith("PERR") or v.name.startswith("FERR")
        ]

        lines.append(
            f"// ========== Parity mode: {parity_mode.upper()} (frame bits: {frame_bits}) =========="
        )
        lines.append(f"localparam int NUM_SMOKE_{mode_suffix.upper()} = {len(smoke)};")
        lines.append(f"localparam int NUM_RANDOM_{mode_suffix.upper()} = {len(rnd)};")
        lines.append(f"localparam int NUM_ERROR_{mode_suffix.upper()} = {len(error)};")
        lines.append(f"localparam int FRAME_BITS_{mode_suffix.upper()} = {frame_bits};")
        lines.append("")

        # Arrays para smoke (datos + frames)
        lines.append(
            f"logic [7:0] smoke_data_{mode_suffix} [0:NUM_SMOKE_{mode_suffix.upper()}-1];"
        )
        lines.append(
            f"logic [10:0] smoke_frame_{mode_suffix} [0:NUM_SMOKE_{mode_suffix.upper()}-1];"
        )
        lines.append("")
        lines.append("initial begin")
        for i, v in enumerate(smoke):
            lines.append(
                f"    smoke_data_{mode_suffix}[{i}] = 8'h{v.data:02X}; // {v.name}"
            )
            lines.append(
                f"    smoke_frame_{mode_suffix}[{i}] = 11'h{v.frame:03X}; // {v.name}"
            )
        lines.append("end")
        lines.append("")

        # Arrays para random (datos + frames)
        lines.append(
            f"logic [7:0] random_data_{mode_suffix} [0:NUM_RANDOM_{mode_suffix.upper()}-1];"
        )
        lines.append(
            f"logic [10:0] random_frame_{mode_suffix} [0:NUM_RANDOM_{mode_suffix.upper()}-1];"
        )
        lines.append("")
        lines.append("initial begin")
        for i, v in enumerate(rnd):
            lines.append(
                f"    random_data_{mode_suffix}[{i}] = 8'h{v.data:02X}; // {v.name}"
            )
            lines.append(
                f"    random_frame_{mode_suffix}[{i}] = 11'h{v.frame:03X}; // {v.name}"
            )
        lines.append("end")
        lines.append("")

        # Arrays para error cases (datos + frames + flags)
        lines.append(
            f"logic [7:0] error_data_{mode_suffix} [0:NUM_ERROR_{mode_suffix.upper()}-1];"
        )
        lines.append(
            f"logic [10:0] error_frame_{mode_suffix} [0:NUM_ERROR_{mode_suffix.upper()}-1];"
        )
        lines.append(
            f"logic error_parity_flag_{mode_suffix} [0:NUM_ERROR_{mode_suffix.upper()}-1];"
        )
        lines.append(
            f"logic error_frame_flag_{mode_suffix} [0:NUM_ERROR_{mode_suffix.upper()}-1];"
        )
        lines.append("")
        lines.append("initial begin")
        for i, v in enumerate(error):
            lines.append(
                f"    error_data_{mode_suffix}[{i}] = 8'h{v.data:02X}; // {v.name}"
            )
            lines.append(
                f"    error_frame_{mode_suffix}[{i}] = 11'h{v.frame:03X}; // {v.name}"
            )
            lines.append(
                f"    error_parity_flag_{mode_suffix}[{i}] = 1'b{1 if v.expect_parity_error else 0}; // {v.name}"
            )
            lines.append(
                f"    error_frame_flag_{mode_suffix}[{i}] = 1'b{1 if v.expect_frame_error else 0}; // {v.name}"
            )
        lines.append("end")
        lines.append("")

    lines.append("`endif // UART_RX_TEST_VECTORS_SVH")
    lines.append("")

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text("\n".join(lines))


def parse_args() -> argparse.Namespace:
    """Analiza argumentos de línea de comandos del script.

    Actualmente no expone opciones configurables por línea de comandos.
    Se mantiene esta función por simetría con otros generadores del proyecto
    y para facilitar futuras extensiones (por ejemplo, especificar cantidad
    de vectores aleatorios, semillas personalizadas, o ruta de salida).

    Retorna:
    - Namespace de argparse (vacío en la implementación actual).
    """
    p = argparse.ArgumentParser(
        description="Generador de vectores de prueba para receptor UART (1 stop bit)"
    )
    return p.parse_args()


def main() -> None:
    """Punto de entrada principal del script.

    Flujo de ejecución:
    1. Parsea argumentos de línea de comandos (actualmente sin opciones)
    2. Genera el archivo include con todos los vectores de prueba
    3. Calcula y muestra estadísticas de generación

    El script genera un total de 50 vectores distribuidos así:
    - NONE: 6 smoke + 9 random + 1 frame_error = 16 vectores
    - EVEN: 6 smoke + 9 random + 1 parity_error + 1 frame_error = 17 vectores
    - ODD:  6 smoke + 9 random + 1 parity_error + 1 frame_error = 17 vectores

    Salida por consola:
    - Muestra resumen de vectores generados por modo
    - Indica la ruta del archivo generado
    - Confirma que se usa 1 stop bit en todos los casos
    """
    parse_args()
    write_include_multi_mode()

    # Calcular totales por modo
    total_none = 6 + 9 + 1  # smoke + random + frame_err = 16
    total_even_odd = 6 + 9 + 2  # smoke + random + parity_err + frame_err = 17
    total_vectors = total_none + 2 * total_even_odd  # 16 + 17 + 17 = 50

    print(f"✓ Generados {total_vectors} vectores totales en {OUTPUT_PATH}")
    print(f"  - NONE: {total_none} vectores (15 valid + 1 error)")
    print(f"  - EVEN: {total_even_odd} vectores (15 valid + 2 error)")
    print(f"  - ODD:  {total_even_odd} vectores (15 valid + 2 error)")
    print("  - Stop bits: 1")


if __name__ == "__main__":
    main()
