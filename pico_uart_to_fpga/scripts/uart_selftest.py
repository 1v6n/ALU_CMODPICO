#!/usr/bin/env python3
"""
@file uart_selftest.py
@brief Prueba de auto-verificación interactiva UART para ALU controlada por Pico.
Este script utiliza pyserial para conducir la consola del Pico, ejecutando secuencias
de operaciones similares a los testbenches de Verilator/VUnit: reset, set opcode (S),
carga de operandos (A/B), lectura (P) y verificación de resultados y flags.
Soporta pruebas dirigidas para operaciones aritméticas, lógicas y de desplazamiento.
"""

import argparse
import re
import sys
import time
from dataclasses import dataclass
from typing import Tuple

import serial


@dataclass
class TestVector:
    """
    @brief Estructura para vectores de prueba en secuencia UART.
    Define un comando a enviar al Pico y subcadenas esperadas en la respuesta para verificación.
    """
    command: str
    expect_substrings: Tuple[str, ...] | None = None
    test_info: dict = None  

"""
@brief Clase para opcodes de ALU, adaptados para opcode de 6 bits.
Refleja operaciones soportadas: aritméticas (ADD, SUB), lógicas (AND, OR, XOR, NOR)
y desplazamientos (SRL, SRA). 
"""
class Opcode:
    ADD = 0b100000 
    ADC = 0b100001 
    SUB = 0b100010 
    SBC = 0b100011 
    AND = 0b100100  
    OR  = 0b100101 
    XOR = 0b100110 
    NOR = 0b100111  
    SRL = 0b000010  
    SRA = 0b000011  


def format_opcode(opcode: int, use_hex: bool) -> str:
    """Return the opcode string to feed the Pico command interface."""
    return f"0x{opcode:02X}" if use_hex else f"{opcode}"


OPCODE_NAMES: dict[int, str] = {
    Opcode.ADD: "ADD",
    Opcode.ADC: "ADC",
    Opcode.SUB: "SUB",
    Opcode.SBC: "SBC",
    Opcode.AND: "AND",
    Opcode.OR: "OR",
    Opcode.XOR: "XOR",
    Opcode.NOR: "NOR",
    Opcode.SRL: "SRL",
    Opcode.SRA: "SRA",
}


def opcode_to_name(opcode: int | None) -> str:
    return OPCODE_NAMES.get(opcode, f"0x{opcode:02X}" if opcode is not None else "???")


def opcode_uses_carry(opcode: int | None) -> bool:
    return opcode in (Opcode.ADC, Opcode.SBC)


def opcode_updates_carry(opcode: int | None) -> bool:
    return opcode in (Opcode.ADD, Opcode.ADC, Opcode.SUB, Opcode.SBC)


def format_hex8(value: int | None) -> str:
    return f"0x{value & 0xFF:02X}" if value is not None else "0x??"


def format_test_context(
    name: str,
    opcode: int | None,
    a_val: int | None,
    b_val: int | None,
    include_carry: bool,
    carry_in: bool,
) -> str:
    safe_name = name or "Test"
    safe_a = format_hex8(a_val)
    safe_b = format_hex8(b_val)
    base = (
        f"{safe_name:<24} | op={opcode_to_name(opcode):<3} | "
        f"A={safe_a} | B={safe_b}"
    )
    if include_carry:
        base += f" | Cin={int(carry_in)}"
    return base


def format_snapshot(result: int | None, cout: int | None, zero: int | None) -> str:
    res_str = format_hex8(result)
    def flag_str(value: int | None) -> str:
        return str(value) if value is not None else "?"

    return (
        f"Res={res_str} Cout={flag_str(cout)} "
        f"Zero={flag_str(zero)}"
    )


def normalize_flag(value: int | bool | None) -> int | None:
    if value is None:
        return None
    return int(value)


def format_snapshot_comparison(
    actual_result: int | None,
    expected_result: int | None,
    actual_cout: int | None,
    expected_cout: int | bool | None,
    actual_zero: int | None,
    expected_zero: int | bool | None,
) -> str:
    expected_result_str = format_hex8(expected_result) if expected_result is not None else "--"
    actual_result_str = format_hex8(actual_result)
    expected_cout_norm = normalize_flag(expected_cout)
    expected_zero_norm = normalize_flag(expected_zero)

    def fmt_flag_pair(actual: int | None, expected: int | None) -> str:
        actual_str = str(actual) if actual is not None else "?"
        expected_str = str(expected) if expected is not None else "--"
        return f"{actual_str} (exp {expected_str})"

    return (
        f"Res={actual_result_str} (exp {expected_result_str}) "
        f"Cout={fmt_flag_pair(actual_cout, expected_cout_norm)} "
        f"Zero={fmt_flag_pair(actual_zero, expected_zero_norm)}"
    )


def run_operation_test(test_name, opcode, a_val, b_val, expected_result,
                       cout=None, zero=None, *, use_hex: bool):
    """
    @brief Función auxiliar para crear secuencia de prueba para una operación única.
    Genera una secuencia de comandos UART: reset (R), set opcode (S), load A/B, print (P).
    Incluye verificación de flags si se proporcionan.
    @param test_name Nombre descriptivo de la prueba.
    @param opcode Opcode de la operación.
    @param a_val Valor del operando A (hex).
    @param b_val Valor del operando B (hex).
    @param expected_result Resultado esperado (hex).
    @param cout Carry esperado (opcional, bool).
    @param zero Flag de cero esperado (opcional, bool).
    @return Lista de TestVector para la secuencia de prueba.
    """
    test_sequence = [
        TestVector(f"S {format_opcode(opcode, use_hex)}\n", None),
        TestVector(f"A 0x{a_val:02X}\n", None),
        TestVector(f"B 0x{b_val:02X}\n", None),
        TestVector("P\n", (f"Result=0x{expected_result:02X}",))
    ]

    if cout is not None:
        test_sequence[-1].expect_substrings += (f"Cout={cout}",)
    if zero is not None:
        test_sequence[-1].expect_substrings += (f"Zero={zero}",)
    test_sequence[-1].test_info = {
        'name': test_name,
        'expected_result': expected_result,
        'a_val': a_val,
        'b_val': b_val,
        'opcode': opcode,
        'cout': cout,
        'zero': zero,
    }

    return test_sequence


DIRECTED_CASES = [
    ("SUMA",               Opcode.ADD, 0x0A, 0x05, 0x0F, 0, 0),
    ("SUMA con carry",     Opcode.ADD, 0xFF, 0x01, 0x00, 1, 1),
    ("ADC con carry",      Opcode.ADC, 0x40, 0x40, 0x81, 0, 0),
    ("SUMA reset carry",   Opcode.ADD, 0x01, 0x01, 0x02, 0, 0),
    ("ADC sin carry",      Opcode.ADC, 0x05, 0x03, 0x08, 0, 0),
    ("RESTA",              Opcode.SUB, 0x34, 0x12, 0x22, 1, 0),
    ("SBC sin borrow",     Opcode.SBC, 0x34, 0x12, 0x22, 1, 0),
    ("SUB con borrow",     Opcode.SUB, 0x00, 0x01, 0xFF, 0, 0),
    ("SBC con borrow",     Opcode.SBC, 0x00, 0x00, 0xFF, 0, 0),
    ("AND",                Opcode.AND, 0xF0, 0x0F, 0x00, 0, 1),
    ("OR",                 Opcode.OR,  0x55, 0x0F, 0x5F, 0, 0),
    ("XOR",                Opcode.XOR, 0xAA, 0x5A, 0xF0, 0, 0),
    ("NOR",                Opcode.NOR, 0xFF, 0x00, 0x00, 0, 1),
    ("SRL",                Opcode.SRL, 0x02, 0x01, 0x01, 0, 0),
    ("SRA",                Opcode.SRA, 0x81, 0x01, 0xC0, 0, 0),
]


def build_test_sequence(use_hex: bool) -> list[TestVector]:
    """
    Construye una secuencia de pruebas para operaciones de la ALU usando casos dirigidos.

    Itera sobre los casos definidos en DIRECTED_CASES, ejecutando pruebas de operación para cada caso
    y recopilando las instancias de TestVector resultantes en una secuencia.

    Args:
        use_hex (bool): Si es True, formatea los valores de prueba en hexadecimal; de lo contrario, usa decimal.

    Returns:
        list[TestVector]: Una lista de objetos TestVector que representan la secuencia de pruebas.
    """
    sequence: list[TestVector] = []
    for name, opcode, a_val, b_val, expected, cout, zero in DIRECTED_CASES:
        sequence.extend(
            run_operation_test(
                name,
                opcode,
                a_val,
                b_val,
                expected,
                cout=cout,
                zero=zero,
                use_hex=use_hex,
            )
        )
    return sequence


def run_test(port: str, baud: int, timeout: float, use_hex: bool) -> bool:
    """
    Ejecuta una secuencia de auto-prueba sobre una conexión UART hacia la ALU en la FPGA.

    Abre el puerto serie, envía una serie de comandos de prueba y verifica las respuestas
    contra los resultados esperados. Cada vector de prueba incluye subcadenas esperadas en la respuesta,
    y opcionalmente información detallada para comparar resultados.

    Args:
        port (str): Puerto serie a utilizar (ejemplo: '/dev/ttyUSB0').
        baud (int): Baudrate para la conexión UART.
        timeout (float): Tiempo de espera en segundos para operaciones de lectura.
        use_hex (bool): Si es True, utiliza formato hexadecimal en los vectores de prueba.

    Returns:
        bool: True si todas las pruebas pasan, False si alguna falla o ocurre un error de comunicación.

    Raises:
        serial.SerialException: Si ocurre un error al abrir o comunicar con el puerto serie.
    """
    try:
        with serial.Serial(port, baudrate=baud, timeout=timeout) as ser:
            time.sleep(0.5)
            ser.reset_input_buffer()

            vectors = build_test_sequence(use_hex)
            overall_pass = True
            carry_state = False
            test_number = 0

            for vector in vectors:
                ser.write(vector.command.encode("ascii"))
                ser.flush()

                response = ser.read_until(b"> ")
                text = response.decode("ascii", errors="replace")

                if vector.expect_substrings:
                    test_number += 1
                    info = vector.test_info or {}
                    opcode = info.get('opcode')
                    include_carry = opcode_uses_carry(opcode)
                    carry_in = carry_state if include_carry else False

                    context = format_test_context(
                        info.get('name', f"Test {test_number}"),
                        opcode,
                        info.get('a_val'),
                        info.get('b_val'),
                        include_carry,
                        carry_in,
                    )

                    missing = [needle for needle in vector.expect_substrings if needle not in text]
                    if missing:
                        response = text if text.endswith("\n") else text + "\n"
                        sys.stderr.write(f"[FAIL] {context} missing {missing}\n{response}")
                        overall_pass = False
                        continue

                    result_match = re.search(r'Result=0x([0-9A-Fa-f]+)', text)
                    cout_match = re.search(r'Cout=(\d+)', text)
                    zero_match = re.search(r'Zero=(\d+)', text)

                    actual_result_val = int(result_match.group(1), 16) if result_match else None
                    actual_cout_val = int(cout_match.group(1)) if cout_match else None
                    actual_zero_val = int(zero_match.group(1)) if zero_match else None

                    expected_result_val = info.get('expected_result')
                    expected_cout_val = info.get('cout')
                    expected_zero_val = info.get('zero')

                    print(
                        "[PASS] "
                        + context
                        + " | "
                        + format_snapshot_comparison(
                            actual_result_val,
                            expected_result_val,
                            actual_cout_val,
                            expected_cout_val,
                            actual_zero_val,
                            expected_zero_val,
                        )
                    )

                    if opcode_updates_carry(opcode) and actual_cout_val is not None:
                        carry_state = bool(actual_cout_val)
                else:
                    print(f"[INFO] {vector.command.strip()} (setup)")

            return overall_pass
    except serial.SerialException as exc:
        sys.stderr.write(f"Serial error: {exc}")
        return False


def main() -> None:
    """
    Analiza los argumentos de línea de comandos y ejecuta la auto-prueba UART para la ALU controlada por Pico.

    Argumentos:
        port (str): Puerto serie a utilizar (ejemplo: /dev/ttyACM0 o COM5).
        --baud (int, opcional): Baudrate para la comunicación UART. Por defecto 115200.
        --timeout (float, opcional): Tiempo de espera para operaciones UART en segundos. Por defecto 1.0.
        --hex-opcode (bool, opcional): Si se especifica, envía los opcodes con prefijo '0x'.

    Salidas:
        SystemExit(0): Si todas las auto-pruebas UART pasan.
        SystemExit(1): Si alguna auto-prueba UART falla.
    """
    parser = argparse.ArgumentParser(description="Pico UART ALU self-test")
    parser.add_argument("port", help="Serial port (e.g. /dev/ttyACM0 or COM5)")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--hex-opcode", action="store_true", help="Enviar opcodes con prefijo 0x")
    args = parser.parse_args()

    if run_test(args.port, args.baud, args.timeout, args.hex_opcode):
        print("All UART self-tests passed.")
        raise SystemExit(0)

    print("UART self-test failed.")
    raise SystemExit(1)


if __name__ == "__main__":
    main()
