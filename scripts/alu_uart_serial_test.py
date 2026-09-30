#!/usr/bin/env python3
"""Pruebas dirigidas para la interfaz UART del ALU usando tramas STX/CMD/DATA/ETX."""
import argparse
import sys
import time
from dataclasses import dataclass

import serial

STX = 0x02
ETX = 0x03

CMD_LOAD_A = 0x41
CMD_LOAD_B = 0x42
CMD_LOAD_OPCODE = 0x43
CMD_EXEC = 0x45


class Opcode:
    ADD = 0b100000
    ADC = 0b100001
    SUB = 0b100010
    SBC = 0b100011
    AND = 0b100100
    OR = 0b100101
    XOR = 0b100110
    NOR = 0b100111
    SRL = 0b000010
    SRA = 0b000011


OPCODE_NAMES = {
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


def opcode_name(opcode: int) -> str:
    return OPCODE_NAMES.get(opcode, f"0x{opcode:02X}")


@dataclass
class OperationTest:
    name: str
    opcode: int
    op_a: int
    op_b: int
    exp_result: int
    exp_carry: int
    exp_zero: int


DIRECTED_TESTS = [
    OperationTest("ADD simple", Opcode.ADD, 0x12, 0x05, 0x17, 0, 0),
    OperationTest("ADD overflow", Opcode.ADD, 0xFF, 0x01, 0x00, 1, 1),
    OperationTest("ADC con carry", Opcode.ADC, 0x40, 0x40, 0x81, 0, 0),
    OperationTest("SUB resta", Opcode.SUB, 0x34, 0x12, 0x22, 1, 0),
    OperationTest("SBC borrow", Opcode.SBC, 0x00, 0x01, 0xFF, 0, 0),
    OperationTest("AND enmascarado", Opcode.AND, 0xF0, 0x0F, 0x00, 0, 1),
    OperationTest("XOR patrón", Opcode.XOR, 0xAA, 0x55, 0xFF, 0, 0),
    OperationTest("NOR cero", Opcode.NOR, 0x00, 0x00, 0xFF, 0, 0),
    OperationTest("SRL desplazamiento", Opcode.SRL, 0x04, 0x01, 0x02, 0, 0),
    OperationTest("SRA signo", Opcode.SRA, 0x80, 0x01, 0xC0, 0, 0),
]


def build_frame(cmd: int, data: int) -> bytes:
    return bytes([STX, cmd & 0xFF, data & 0xFF, ETX])


def send_frame(port: serial.Serial, cmd: int, data: int):
    port.write(build_frame(cmd, data))


def read_frame(port: serial.Serial, timeout: float = 1.0) -> bytes | None:
    """Devuelve el payload recibido (resultado+flags) o None si agota timeout."""
    deadline = time.time() + timeout
    state = "WAIT_STX"
    payload: list[int] = []

    while time.time() < deadline:
        if port.in_waiting == 0:
            time.sleep(0.001)
            continue
        byte = port.read(1)
        if not byte:
            continue
        value = byte[0]
        if state == "WAIT_STX":
            if value == STX:
                state = "WAIT_RESULT"
                payload = []
        elif state == "WAIT_RESULT":
            payload.append(value)
            state = "WAIT_FLAGS"
        elif state == "WAIT_FLAGS":
            payload.append(value)
            state = "WAIT_ETX"
        elif state == "WAIT_ETX":
            if value == ETX:
                return bytes(payload)
            state = "WAIT_STX"
            payload = []
    return None


def wait_result(port: serial.Serial, timeout: float = 1.0):
    """Espera una respuesta con formato [resultado][flags]."""
    frame = read_frame(port, timeout)
    if not frame:
        raise TimeoutError("Timeout esperando respuesta del ALU")
    if len(frame) < 2:
        raise ValueError(f"Trama inesperada: {frame!r}")
    result = frame[0]
    flags = frame[1]
    zero = (flags >> 1) & 0x1
    carry = flags & 0x1
    return result, zero, carry, frame


def run_test(port: serial.Serial, test: OperationTest, timeout: float):
    def exec_sequence(opcode, op_a, op_b):
        send_frame(port, CMD_LOAD_A, op_a)
        send_frame(port, CMD_LOAD_B, op_b)
        send_frame(port, CMD_LOAD_OPCODE, opcode)
        time.sleep(0.001)
        send_frame(port, CMD_EXEC, 0x00)
        return wait_result(port, timeout)

    def prime_carry(value: int):
        if value:
            return exec_sequence(Opcode.ADD, 0xFF, 0x01)
        return exec_sequence(Opcode.ADD, 0x00, 0x00)

    if test.opcode == Opcode.ADC:
        try:
            prime_carry(1)
        except (TimeoutError, ValueError) as exc:
            return False, f"{test.name}: ERROR pre-carry {exc}", None
    elif test.opcode == Opcode.SBC:
        try:
            prime_carry(1)
        except (TimeoutError, ValueError) as exc:
            return False, f"{test.name}: ERROR pre-carry {exc}", None

    try:
        result, zero, carry, raw_frame = exec_sequence(test.opcode, test.op_a, test.op_b)
    except (TimeoutError, ValueError) as exc:
        return False, f"{test.name}: ERROR {exc}", None

    passed = (
        result == (test.exp_result & 0xFF)
        and zero == test.exp_zero
        and carry == test.exp_carry
    )
    msg = (
        f"{test.name}: op={opcode_name(test.opcode)} "
        f"A=0x{test.op_a:02X} B=0x{test.op_b:02X} -> "
        f"Res=0x{result:02X} (exp 0x{test.exp_result:02X}) "
        f"Z={zero} (exp {test.exp_zero}) "
        f"C={carry} (exp {test.exp_carry})"
    )
    return passed, msg, raw_frame


def main():
    parser = argparse.ArgumentParser(description="Pruebas para ALU vía UART FSM")
    parser.add_argument("port", help="Puerto serie (ej. /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=9600)
    parser.add_argument(
        "-t", "--timeout", type=float, default=1.0, help="Timeout por respuesta (s)"
    )
    parser.add_argument(
        "--tests",
        nargs="*",
        help="Filtra por nombres de prueba (coincidencia parcial, sensible a mayúsculas)",
    )
    args = parser.parse_args()

    selected = DIRECTED_TESTS
    if args.tests:
        filters = [f.lower() for f in args.tests]
        selected = [
            test for test in DIRECTED_TESTS if any(f in test.name.lower() for f in filters)
        ]
        if not selected:
            print("No se encontraron pruebas que coincidan con los filtros", file=sys.stderr)
            sys.exit(1)

    try:
        port = serial.Serial(args.port, args.baud, timeout=0.01)
    except serial.SerialException as exc:
        print(f"No se pudo abrir el puerto {args.port}: {exc}", file=sys.stderr)
        sys.exit(1)

    total = len(selected)
    passed = 0
    print(f"[INFO] Ejecutando {total} pruebas...\n")
    for idx, test in enumerate(selected, start=1):
        ok, message, raw = run_test(port, test, args.timeout)
        status = "OK " if ok else "FAIL"
        print(f"[{status}] ({idx:02d}/{total:02d}) {message}")
        if raw is not None:
            print(f"      RX payload: {raw.hex(' ')}")
        print("")
        if ok:
            passed += 1
        else:
            time.sleep(0.05)

    port.close()
    print("Resumen final".ljust(20, "="))
    print(f"Total : {total}")
    print(f"OK    : {passed}")
    print(f"Fail  : {total - passed}")
    if passed != total:
        sys.exit(1)


if __name__ == "__main__":
    main()
