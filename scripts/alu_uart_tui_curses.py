#!/usr/bin/env python3
"""Interfaz TUI (curses) para enviar tramas UART al ALU."""
import argparse
import curses
import time
from collections import deque

import serial

STX = 0x02
ETX = 0x03

COMMANDS = {
    "a": (0x41, "LOAD_A"),
    "b": (0x42, "LOAD_B"),
    "c": (0x43, "LOAD_OPCODE"),
    "e": (0x45, "EXEC"),
}

CMD_NAMES = {
    0x41: "LOAD_A",
    0x42: "LOAD_B",
    0x43: "LOAD_OPCODE",
    0x45: "EXEC",
    0x02: "RESP",
}

OPCODE_LIST = [
    (0b100000, "ADD"),
    (0b100001, "ADC"),
    (0b100010, "SUB"),
    (0b100011, "SBC"),
    (0b100100, "AND"),
    (0b100101, "OR"),
    (0b100110, "XOR"),
    (0b100111, "NOR"),
    (0b000010, "SRL"),
    (0b000011, "SRA"),
]


def build_frame(cmd: int, data: int) -> bytes:
    return bytes([STX, cmd & 0xFF, data & 0xFF, ETX])


class CursesTui:
    def __init__(self, port: str, baud: int):
        self.port = port
        self.baud = baud
        self.serial = serial.Serial(port, baud, timeout=0.01)
        self.value_text = ""
        self.selected_opcode = 0
        self.logs = deque(maxlen=500)
        self.running = True
        self.rx_state = "WAIT_STX"
        self.rx_buffer = []
        self.rx_result = 0
        self.rx_flags = 0

    def log(self, text: str):
        timestamp = time.strftime("%H:%M:%S")
        self.logs.appendleft(f"[{timestamp}] {text}")

    def parse_value(self) -> int:
        text = self.value_text.strip()
        if not text:
            return 0
        try:
            if text.lower().startswith("0x"):
                return int(text, 16) & 0xFF
            return int(text) & 0xFF
        except ValueError:
            self.log("Valor inválido, usando 0")
            return 0

    def send_frame(self, cmd: int, data: int):
        frame = build_frame(cmd, data)
        self.serial.write(frame)
        self.log(f"TX frame cmd=0x{cmd:02X} data=0x{data:02X}")

    def send_raw_byte(self, value: int):
        self.serial.write(bytes([value & 0xFF]))
        self.log(f"TX raw 0x{value & 0xFF:02X}")

    def poll_serial(self):
        try:
            pending = self.serial.in_waiting
            if pending:
                incoming = self.serial.read(pending)
            else:
                incoming = b""
        except serial.SerialException as exc:
            self.log(f"Error leyendo puerto: {exc}")
            self.running = False
            return

        if incoming:
            for byte in incoming:
                self._process_rx_byte(byte & 0xFF)

    def _process_rx_byte(self, byte: int):
        if self.rx_state == "WAIT_STX":
            self.rx_buffer = []
            if byte == STX:
                self.rx_buffer.append(byte)
                self.rx_state = "WAIT_RESULT"
        elif self.rx_state == "WAIT_RESULT":
            self.rx_result = byte
            self.rx_buffer.append(byte)
            self.rx_state = "WAIT_FLAGS"
        elif self.rx_state == "WAIT_FLAGS":
            self.rx_flags = byte
            self.rx_buffer.append(byte)
            self.rx_state = "WAIT_ETX"
        elif self.rx_state == "WAIT_ETX":
            self.rx_buffer.append(byte)
            if byte == ETX:
                self._finalize_result()
            else:
                self.log(f"Trama inválida: esperado ETX, recibido 0x{byte:02X} | raw={' '.join(f'0x{x:02X}' for x in self.rx_buffer)}")
            self.rx_state = "WAIT_STX"

    def _finalize_result(self):
        flags = self.rx_flags & 0xFF
        result = self.rx_result & 0xFF
        carry = (flags >> 1) & 0x1
        zero = flags & 0x1
        raw_str = " ".join(f"0x{b:02X}" for b in self.rx_buffer)
        self.log(f"Resultado=0x{result:02X} Zero={zero} Carry={carry} (flags=0x{flags:02X}) | raw={raw_str}")

    def draw(self, stdscr):
        stdscr.erase()
        h, w = stdscr.getmaxyx()
        left_width = min(max(12, w // 3), max(12, w - 8))
        left_width = min(left_width, max(4, w - 4))
        log_x = min(left_width + 2, w - 6)
        log_width = max(8, w - log_x - 2)
        max_logs = h - 2

        stdscr.addstr(0, 0, f"Puerto: {self.port}  Baud: {self.baud}")
        stdscr.addstr(1, 0, "Teclas: A/B/C/E, R raw, ↑/↓ opcode, Q salir.")
        stdscr.addstr(2, 0, f"Valor actual: {self.value_text or '(vacío)'}")
        stdscr.addstr(4, 0, "Opcodes:")
        for i, (code, name) in enumerate(OPCODE_LIST):
            row = 5 + i
            if row >= h:
                break
            marker = ">" if i == self.selected_opcode else " "
            stdscr.addstr(row, 2, f"{marker} {name:<4} -> 0x{code:02X}")

        for y in range(h):
            stdscr.addch(y, left_width, "|")

        stdscr.addstr(0, log_x, "Log (resultado + flags):")
        for idx, line in enumerate(list(self.logs)[:max_logs]):
            row = 1 + idx
            if row >= h:
                break
            stdscr.addstr(row, log_x, line[:log_width])

        stdscr.refresh()

    def handle_key(self, key):
        if key in (curses.KEY_UP, ord("k")):
            self.selected_opcode = (self.selected_opcode - 1) % len(OPCODE_LIST)
        elif key in (curses.KEY_DOWN, ord("j")):
            self.selected_opcode = (self.selected_opcode + 1) % len(OPCODE_LIST)
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            self.value_text = self.value_text[:-1]
        elif key in (ord("\n"), ord("\r")):
            pass
        elif key in (ord("q"), ord("Q")):
            self.running = False
        elif key in (ord("r"), ord("R")):
            value = self.parse_value()
            self.send_raw_byte(value)
        elif key in (ord("a"), ord("b"), ord("c"), ord("e")):
            lower = chr(key)
            self._execute_command(lower)
        elif 32 <= key <= 126:
            ch = chr(key)
            if ch.isalnum() or ch in "xX":
                self.value_text += ch
        else:
            lower = chr(key).lower() if 0 <= key < 256 else ""
            if lower in COMMANDS:
                self._execute_command(lower)

    def _execute_command(self, key_char: str):
        cmd, name = COMMANDS[key_char]
        if cmd == 0x43:
            data = OPCODE_LIST[self.selected_opcode][0]
        elif cmd == 0x45:
            data = 0
        else:
            data = self.parse_value()
        self.log(f"Acción {name}")
        self.send_frame(cmd, data)

    def run(self, stdscr):
        curses.curs_set(0)
        stdscr.nodelay(True)
        stdscr.timeout(100)

        self.log("TUI iniciado")
        while self.running:
            self.poll_serial()
            self.draw(stdscr)
            key = stdscr.getch()
            if key != -1:
                self.handle_key(key)

        self.serial.close()


def main():
    parser = argparse.ArgumentParser(description="Curses UART sender para tramas ALU")
    parser.add_argument("port", help="Puerto serie (ej. /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=9600)
    args = parser.parse_args()

    tui = CursesTui(args.port, args.baud)
    curses.wrapper(tui.run)


if __name__ == "__main__":
    main()
