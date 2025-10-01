#!/usr/bin/env python3
"""
Generador de Vectores de Prueba para la ALU.

Este script actúa como un "golden model" de la ALU, calculando los resultados
esperados para un conjunto de casos de prueba predefinidos (smoke tests) y
casos generados aleatoriamente.

El resultado se escribe en un archivo header de SystemVerilog (`alu_test_vectors.svh`)
que es consumido por el testbench (`tb_alu.sv`) para la simulación en Vivado.
Esto evita duplicar la lógica de la ALU en el testbench y asegura una fuente
de verdad única para la verificación.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import random
from typing import Iterable, List, Tuple

# --- Constantes de Configuración ---

DATA_WIDTH = 8
"""Ancho de bits para los operandos de la ALU."""

OUTPUT_PATH = Path(__file__).resolve().parents[1] / "sv" / "alu_test_vectors.svh"
"""Ruta del archivo de salida para los vectores de prueba generados."""

# --- Definiciones de Opcodes ---

OPCODE_FAMILY_ARITH = 0b1000
OPCODE_FAMILY_LOGIC = 0b1001
OPCODE_FAMILY_SHIFT = 0b0000

# Casos de prueba predefinidos (smoke tests) para cubrir casos esquina y básicos.
# Formato: (Nombre, Opcode, Operando A, Operando B)
SMOKE_CASES: List[Tuple[str, int, int, int]] = [
    ("ADD",            0b100000, 0x0A, 0x05),
    ("ADD_WRAP",       0b100000, 0xFF, 0x01),
    ("ADC_WITH_CARRY", 0b100001, 0x40, 0x40),
    ("ADD_CLEAR",      0b100000, 0x01, 0x01),
    ("ADC_NO_CARRY",   0b100001, 0x05, 0x03),
    ("ADD_OVF",        0b100000, 0x7F, 0x01),
    ("SUB",            0b100010, 0x34, 0x12),
    ("SUB_OVF",        0b100010, 0x80, 0x01),
    ("SBC_KEEP",       0b100011, 0x34, 0x12),
    ("SUB_BORROW",     0b100010, 0x00, 0x01),
    ("SBC_BORROW",     0b100011, 0x00, 0x00),
    ("AND",            0b100100, 0xF0, 0x0F),
    ("OR",             0b100101, 0x55, 0x0F),
    ("XOR",            0b100110, 0xAA, 0x5A),
    ("NOR",            0b100111, 0x00, 0x00),
    ("SRL",            0b000010, 0xC0, 0x03),
    ("SRA",            0b000011, 0x81, 0x02),
    ("SRL_WIDE",       0b000010, 0xAA, 0x20),
]

# Opcodes utilizados para la generación de pruebas aleatorias.
RANDOM_OPCODE_POOL = [
    0b100000,
    0b100001,
    0b100010,
    0b100011,
    0b100100,
    0b100101,
    0b100110,
    0b100111,
    0b000010,
    0b000011,
]

@dataclass
class Vector:
    """
    Estructura de datos para un único vector de prueba.

    Almacena las entradas para la ALU y todos los resultados esperados
    correspondientes (resultado principal, flags y estado de los LEDs).
    """
    name: str
    opcode: int
    a: int
    b: int
    exp_result: int
    exp_cout: int
    exp_zero: int
    exp_led0: int
    exp_led1: int
    exp_led_b_n: int
    exp_led_g_n: int
    exp_led_r_n: int


def _signed(value: int, width: int = DATA_WIDTH) -> int:
    """
    Convierte un valor a un entero con signo del ancho de datos especificado.

    Args:
        value: El valor de entrada sin signo.
        width: El ancho de bits para la conversión (por defecto DATA_WIDTH).

    Returns:
        El valor interpretado como un entero con signo en complemento a dos.
    """
    mask = (1 << width) - 1
    value &= mask
    sign_bit = 1 << (width - 1)
    return value - (1 << width) if value & sign_bit else value


def evaluate_case(name: str, opcode: int, a: int, b: int, carry_state: int) -> Tuple[Vector, int]:
    """
    Evalúa un único caso de prueba y calcula los resultados esperados.

    Esta función emula la lógica completa de la ALU en Python, incluyendo las
    operaciones aritméticas, lógicas y de desplazamiento, así como el estado

    de los flags y los LEDs.

    Args:
        name: Nombre descriptivo del caso de prueba.
        opcode: El código de operación de 6 bits.
        a: El valor del operando A.
        b: El valor del operando B.
        carry_state: El estado del flag de acarreo de la operación anterior.

    Returns:
        Una tupla que contiene el objeto Vector con todos los resultados
        calculados y el nuevo estado del flag de acarreo.
    """
    family = (opcode >> 2) & 0xF
    sel = opcode & 0x3

    result = 0
    cout = 0
    next_carry = carry_state

    # --- Lógica Aritmética ---
    if family == OPCODE_FAMILY_ARITH:
        if sel == 0:  # ADD
            wide = a + b
        elif sel == 1:  # ADC
            wide = a + b + carry_state
        elif sel == 2:  # SUB
            wide = a + ((~b) & 0xFF) + 1
        elif sel == 3:  # SBC
            wide = a + ((~b) & 0xFF) + carry_state
        else:
            wide = 0
        result = wide & 0xFF
        cout = (wide >> 8) & 0x1
        next_carry = cout
    # --- Lógica Booleana ---
    elif family == OPCODE_FAMILY_LOGIC:
        if sel == 0:
            result = a & b
        elif sel == 1:
            result = a | b
        elif sel == 2:
            result = a ^ b
        elif sel == 3:
            result = (~(a | b)) & 0xFF
        else:
            result = 0
        cout = 0
    # --- Lógica de Desplazamiento ---
    elif family == OPCODE_FAMILY_SHIFT:
        shift_amt = b & 0xFF
        if sel == 0b10:  # SRL
            result = (a >> shift_amt) & 0xFF
        elif sel == 0b11:  # SRA
            signed_a = _signed(a)
            result = (_signed(signed_a >> shift_amt) & 0xFF)
        else:
            result = 0
        cout = 0
    # --- Caso por Defecto ---
    else:
        result = 0
        cout = 0

    # --- Cálculo de Flags y LEDs ---
    exp_zero = 1 if result == 0 else 0
    exp_led0 = (result >> 0) & 1
    exp_led1 = (result >> 1) & 1
    exp_led_b_n = 0 if ((result >> 2) & 1) else 1
    exp_led_g_n = 0 if ((result >> 3) & 1) else 1
    exp_led_r_n = 0 if ((result >> 4) & 1) else 1

    vector = Vector(
        name=name,
        opcode=opcode,
        a=a & 0xFF,
        b=b & 0xFF,
        exp_result=result & 0xFF,
        exp_cout=cout,
        exp_zero=exp_zero,
        exp_led0=exp_led0,
        exp_led1=exp_led1,
        exp_led_b_n=exp_led_b_n,
        exp_led_g_n=exp_led_g_n,
        exp_led_r_n=exp_led_r_n,
    )
    return vector, next_carry


def build_vectors() -> Tuple[List[Vector], List[Vector]]:
    """
    Construye las listas de vectores de prueba.

    Genera una lista para los casos predefinidos (smoke) y otra para los
    casos aleatorios, manteniendo el estado del acarreo entre operaciones.

    Returns:
        Una tupla con dos listas: (vectores_smoke, vectores_aleatorios).
    """
    vectors_smoke: List[Vector] = []
    carry_state = 0
    for name, opcode, a, b in SMOKE_CASES:
        vec, carry_state = evaluate_case(name, opcode, a, b, carry_state)
        vectors_smoke.append(vec)

    rng = random.Random(42)  # Semilla fija para resultados reproducibles
    vectors_rand: List[Vector] = []
    for idx in range(200):
        opcode = rng.choice(RANDOM_OPCODE_POOL)
        a = rng.randrange(0, 256)
        b = rng.randrange(0, 256)
        vec, carry_state = evaluate_case(f"RND_{idx}", opcode, a, b, carry_state)
        vectors_rand.append(vec)

    return vectors_smoke, vectors_rand


def fmt_vec(vec: Vector) -> str:
    """
    Formatea un objeto Vector a una cadena con la sintaxis de SystemVerilog.

    Args:
        vec: El objeto Vector a formatear.

    Returns:
        Una cadena de texto lista para ser insertada en el archivo .svh.
    """
    return (
        f"'{{ \"{vec.name}\", 6'h{vec.opcode:02X}, 8'h{vec.a:02X}, 8'h{vec.b:02X}, 8'h{vec.exp_result:02X}, "
        f"1'b{vec.exp_cout}, 1'b{vec.exp_zero}, 1'b{vec.exp_led0}, 1'b{vec.exp_led1}, "
        f"1'b{vec.exp_led_b_n}, 1'b{vec.exp_led_g_n}, 1'b{vec.exp_led_r_n} }}"
    )


def write_include(smoke: Iterable[Vector], random_vecs: Iterable[Vector]) -> None:
    """
    Escribe el contenido completo del archivo header de SystemVerilog.

    Args:
        smoke: Una lista iterable de vectores de prueba predefinidos.
        random_vecs: Una lista iterable de vectores de prueba aleatorios.
    """
    lines = []
    lines.append("/* Auto-generated by scripts/gen_test_vectors.py. Do not edit manually. */")
    lines.append("`ifndef ALU_TEST_VECTORS_SVH")
    lines.append("`define ALU_TEST_VECTORS_SVH")
    lines.append("")
    lines.append("typedef struct {")
    lines.append("    string name;")
    lines.append("    logic [5:0] opcode;")
    lines.append("    logic [7:0] a;")
    lines.append("    logic [7:0] b;")
    lines.append("    logic [7:0] exp_result;")
    lines.append("    logic       exp_cout;")
    lines.append("    logic       exp_zero;")
    lines.append("    logic       exp_led0;")
    lines.append("    logic       exp_led1;")
    lines.append("    logic       exp_led_b_n;")
    lines.append("    logic       exp_led_g_n;")
    lines.append("    logic       exp_led_r_n;")
    lines.append("} testcase_t;")
    lines.append("")
    lines.append("testcase_t smoke_vectors[$] = '{")
    smoke_list = list(smoke)
    for idx, vec in enumerate(smoke_list):
        suffix = "," if idx != len(smoke_list) - 1 else ""
        lines.append(f"    {fmt_vec(vec)}{suffix}")
    lines.append("}")
    lines.append("")
    lines.append("testcase_t random_vectors[$] = '{")
    random_list = list(random_vecs)
    for idx, vec in enumerate(random_list):
        suffix = "," if idx != len(random_list) - 1 else ""
        lines.append(f"    {fmt_vec(vec)}{suffix}")
    lines.append("}")
    lines.append("")
    lines.append("`endif // ALU_TEST_VECTORS_SVH")
    lines.append("")

    OUTPUT_PATH.write_text("\n".join(lines) + "\n")


def main() -> None:
    """
    Punto de entrada principal del script.

    Orquesta la generación de vectores y la escritura del archivo de salida.
    """
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    smoke, random_vecs = build_vectors()
    write_include(smoke, random_vecs)
    print(f"Se escribieron {len(smoke)} vectores de prueba predefinidos y {len(random_vecs)} aleatorios en {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
