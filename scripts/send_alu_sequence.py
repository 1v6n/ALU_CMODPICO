#!/usr/bin/env python3
"""Send ALU UART command packets (STX/CMD/DATA/ETX) over serial."""
import argparse
import serial

PACKETS = [
    (0x41, 0x12, "Load operand A = 0x12"),
    (0x42, 0x34, "Load operand B = 0x34"),
    (0x43, 0x20, "Load opcode = 0x20 (ADD)"),
    (0x45, 0x00, "Execute"),
]


def build_frame(cmd, data):
    return bytes([0x02, cmd, data, 0x03])


def main():
    parser = argparse.ArgumentParser(description="Send ALU UART packets")
    parser.add_argument("port", help="Serial port (e.g. /dev/ttyACM0)")
    parser.add_argument("-b", "--baud", type=int, default=9600)
    args = parser.parse_args()

    with serial.Serial(args.port, args.baud, timeout=1) as ser:
        for cmd, data, desc in PACKETS:
            frame = build_frame(cmd, data)
            print(f"-> {desc}: {[hex(b) for b in frame]}")
            ser.write(frame)


if __name__ == "__main__":
    main()
