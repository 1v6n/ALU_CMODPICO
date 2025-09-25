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

"""
@brief Clase para opcodes de ALU, adaptados de funct MIPS de 6 bits.
Refleja operaciones soportadas: aritméticas (ADD, SUB), lógicas (AND, OR, XOR, NOR)
y desplazamientos (SRL, SRA). Adaptados para ALU de 5 bits efectiva.
"""
class Opcode:
    ADD = 0b100000 
    SUB = 0b100010 
    AND = 0b100100  
    OR  = 0b100101 
    XOR = 0b100110 
    NOR = 0b100111  
    SRL = 0b000010  
    SRA = 0b000011  


def format_opcode(opcode):
    """
    @brief Formatea un opcode como cadena hexadecimal con prefijo 0x.
    Utilizado para generar comandos UART como "S 0x20".
    @param opcode Valor entero del opcode.
    @return Cadena formateada (e.g., "0x20").
    """
    return f"0x{opcode:02X}"


def run_operation_test(test_name, opcode, a_val, b_val, expected_result, cout=None, zero=None, overflow=None):
    """
    @brief Función auxiliar para crear secuencia de prueba para una operación única.
    Genera una secuencia de comandos UART: reset (R), set opcode (S), load A/B, print (P).
    Incluye verificación de flags si se proporcionan.
    @param test_name Nombre descriptivo de la prueba.
    @param opcode Opcode de la operación.
    @param a_val Valor del operando A (hex).
    @param b_val Valor del operando B (hex).
    @param expected_result Resultado esperado (hex).
    @param cout Acarreo esperado (opcional, bool).
    @param zero Flag de cero esperado (opcional, bool).
    @param overflow Desbordamiento esperado (opcional, bool).
    @return Lista de TestVector para la secuencia de prueba.
    """
    test_sequence = [
        TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
        TestVector(f"S {format_opcode(opcode)}\n"),
        TestVector(f"A 0x{a_val:02X}\n"),
        TestVector(f"B 0x{b_val:02X}\n"),
        TestVector("P\n", (f"Result=0x{expected_result:02X}",))
    ]
    
    if cout is not None:
        test_sequence[-1].expect_substrings += (f"Cout={cout}",)
    if zero is not None:
        test_sequence[-1].expect_substrings += (f"Zero={zero}",)
    if overflow is not None:
        test_sequence[-1].expect_substrings += (f"Overflow={overflow}",)
        
    return test_sequence


TEST_SEQUENCE = [
    # @brief Reset inicial y verificación de estado
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),

    # @brief Prueba básica de suma (0x0A + 0x05 = 0x0F)
    TestVector(f"S {format_opcode(Opcode.ADD)}\n"),
    TestVector("A 0x0A\n"),
    TestVector("B 0x05\n"),
    TestVector("P\n", ("Result=0x0F", "Cout=0", "Zero=0", "Overflow=0")),

    # @brief Prueba de suma con desbordamiento (0x7F + 0x01 = 0x80, overflow=1)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.ADD)}\n"),
    TestVector("A 0x7F\n"),
    TestVector("B 0x01\n"),
    TestVector("P\n", ("Result=0x80", "Cout=0", "Zero=0", "Overflow=1")),

    # @brief Prueba básica de resta (0x34 - 0x12 = 0x22, Cout=1 sin borrow)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.SUB)}\n"),
    TestVector("A 0x34\n"),
    TestVector("B 0x12\n"),
    TestVector("P\n", ("Result=0x22", "Cout=1", "Zero=0", "Overflow=0")),

    # @brief Prueba de resta con desbordamiento (0x80 - 0x01 = 0x7F, overflow=1)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.SUB)}\n"),
    TestVector("A 0x80\n"),
    TestVector("B 0x01\n"),
    TestVector("P\n", ("Result=0x7F", "Cout=1", "Zero=0", "Overflow=1")),

    # @brief Prueba de AND (0xF0 & 0x0F = 0x00)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.AND)}\n"),
    TestVector("A 0xF0\n"),
    TestVector("B 0x0F\n"),
    TestVector("P\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),

    # @brief Prueba de OR (0x55 | 0x0F = 0x5F)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.OR)}\n"),
    TestVector("A 0x55\n"),
    TestVector("B 0x0F\n"),
    TestVector("P\n", ("Result=0x5F", "Cout=0", "Zero=0", "Overflow=0")),

    # @brief Prueba de XOR (0xAA ^ 0x5A = 0xF0)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.XOR)}\n"),
    TestVector("A 0xAA\n"),
    TestVector("B 0x5A\n"),
    TestVector("P\n", ("Result=0xF0", "Cout=0", "Zero=0", "Overflow=0")),


    # @brief Prueba de NOR (~(0xFF | 0x00) = 0x00)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.NOR)}\n"),
    TestVector("A 0xFF\n"),
    TestVector("B 0x00\n"),
    TestVector("P\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),


    # @brief Prueba de SRL (0x02 >> 1 = 0x01)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.SRL)}\n"),
    TestVector("A 0x02\n"),
    TestVector("P\n", ("Result=0x01", "Cout=0", "Zero=0", "Overflow=0")),


    # @brief Prueba de SRA (0x81 >>> 1 = 0xC0)
    TestVector("R\n", ("Result=0x00", "Cout=0", "Zero=1", "Overflow=0")),
    TestVector(f"S {format_opcode(Opcode.SRA)}\n"),
    TestVector("A 0x81\n"),
    TestVector("P\n", ("Result=0xC0", "Cout=0", "Zero=0", "Overflow=0")),
]


def run_test(port: str, baud: int, timeout: float) -> bool:
    """
    @brief Ejecuta la secuencia de pruebas UART sobre el puerto serial.
    Envía comandos al Pico (reset, set opcode, load A/B, print) y verifica respuestas.
    @param port Puerto serial (e.g., '/dev/ttyACM0').
    @param baud Velocidad de baudios (default 115200).
    @param timeout Tiempo de espera para lectura (default 1.0s).
    @return True si todas las pruebas pasan, False si hay fallos o errores serial.
    """
    try:
        with serial.Serial(port, baudrate=baud, timeout=timeout) as ser:
            time.sleep(0.5)
            ser.reset_input_buffer()

            overall_pass = True
            for i, vector in enumerate(TEST_SEQUENCE):
                ser.write(vector.command.encode("ascii"))
                ser.flush()

                response = ser.read_until(b"> ")
                text = response.decode("ascii", errors="replace")

                expected = vector.expect_substrings
                if expected:
                    missing = [needle for needle in expected if needle not in text]
                    if missing:
                        sys.stderr.write(
                            f"[FAIL] Test {i+1} Command '{vector.command.strip()}' missing {missing}\n{text}\n"
                        )
                        overall_pass = False
                    else:
                        print(f"[PASS] Test {i+1} {vector.command.strip()} -> {', '.join(expected)}")
                else:
                    print(f"[PASS] Test {i+1} {vector.command.strip()} (no check)")

            return overall_pass
    except serial.SerialException as exc:
        sys.stderr.write(f"Serial error: {exc}\n")
        return False


def main():
    """
    @brief Función principal: parsea argumentos y ejecuta pruebas UART.
    Maneja argumentos de puerto, baudios y timeout; ejecuta run_test y reporta resultado.
    """
    parser = argparse.ArgumentParser(description="Pico UART ALU self-test")
    parser.add_argument("port", help="Serial port (e.g. /dev/ttyACM0 or COM5)")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=1.0)
    args = parser.parse_args()

    if run_test(args.port, args.baud, args.timeout):
        print("All UART self-tests passed.")
        sys.exit(0)
    else:
        print("UART self-test failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
