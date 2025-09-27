import random
from dataclasses import dataclass
from enum import IntEnum

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


class Opcode(IntEnum):
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


@dataclass
class TestCase:
    name: str
    opcode: Opcode
    a: int
    b: int


def opcode_uses_carry(opcode: Opcode) -> bool:
    return opcode in (Opcode.ADC, Opcode.SBC)


def opcode_updates_carry(opcode: Opcode) -> bool:
    return opcode in (Opcode.ADD, Opcode.ADC, Opcode.SUB, Opcode.SBC)


def model_execute(opcode: Opcode, a: int, b: int, carry_in: int = 0):
    a &= 0xFF
    b &= 0xFF
    carry_in = 1 if carry_in else 0

    def sign_bit(value: int) -> int:
        return (value >> 7) & 0x1

    if opcode in (Opcode.ADD, Opcode.ADC):
        wide = a + b + (carry_in if opcode == Opcode.ADC else 0)
        result = wide & 0xFF
        cout = (wide >> 8) & 0x1
        overflow = (sign_bit(a) == sign_bit(b)) and (sign_bit(a) != sign_bit(result))
    elif opcode in (Opcode.SUB, Opcode.SBC):
        add_operand = (~b) & 0xFF
        borrow_term = 1 if opcode == Opcode.SUB else carry_in
        wide = a + add_operand + borrow_term
        result = wide & 0xFF
        cout = (wide >> 8) & 0x1
        overflow = (sign_bit(a) == sign_bit(add_operand)) and (sign_bit(a) != sign_bit(result))
    elif opcode == Opcode.AND:
        result = a & b
        cout = 0
        overflow = 0
    elif opcode == Opcode.OR:
        result = a | b
        cout = 0
        overflow = 0
    elif opcode == Opcode.XOR:
        result = a ^ b
        cout = 0
        overflow = 0
    elif opcode == Opcode.NOR:
        result = (~(a | b)) & 0xFF
        cout = 0
        overflow = 0
    elif opcode == Opcode.SRL:
        result = (a >> 1) & 0xFF
        cout = 0
        overflow = 0
    elif opcode == Opcode.SRA:
        signed = a if a < 0x80 else a - 0x100
        result = (signed >> 1) & 0xFF
        cout = 0
        overflow = 0
    else:
        raise ValueError(f"Unhandled opcode {opcode}")

    zero = 1 if result == 0 else 0
    return {
        "result": result,
        "cout": cout,
        "overflow": overflow,
        "zero": zero,
        "led_bits": {
            "led0": result & 0x1,
            "led1": (result >> 1) & 0x1,
            "led_b_n": ((result >> 2) & 0x1) ^ 0x1,
            "led_g_n": ((result >> 3) & 0x1) ^ 0x1,
            "led_r_n": ((result >> 4) & 0x1) ^ 0x1,
        },
    }


async def pulse_load(dut, load_signal, value: int):
    dut.data_in.value = value & 0xFF
    load_signal.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    load_signal.value = 0


async def apply_test_case(dut, tc: TestCase, carry_state: int):
    carry_in = carry_state if opcode_uses_carry(tc.opcode) else 0

    await pulse_load(dut, dut.load_a, tc.a)
    await pulse_load(dut, dut.load_b, tc.b)
    await pulse_load(dut, dut.load_sel, int(tc.opcode))
    await RisingEdge(dut.clk)

    expected = model_execute(tc.opcode, tc.a, tc.b, carry_in)

    result = int(dut.Result.value)
    cout = int(dut.Cout.value)
    overflow = int(dut.Overflow.value)
    zero = int(dut.Zero.value)

    assert result == expected["result"], (
        f"{tc.name}: Result mismatch for opcode {tc.opcode.name}. "
        f"got 0x{result:02X}, expected 0x{expected['result']:02X}"
    )
    assert cout == expected["cout"], (
        f"{tc.name}: Cout mismatch for opcode {tc.opcode.name}. "
        f"got {cout}, expected {expected['cout']}"
    )
    assert overflow == expected["overflow"], (
        f"{tc.name}: Overflow mismatch for opcode {tc.opcode.name}. "
        f"got {overflow}, expected {expected['overflow']}"
    )
    assert zero == expected["zero"], (
        f"{tc.name}: Zero mismatch for opcode {tc.opcode.name}. "
        f"got {zero}, expected {expected['zero']}"
    )

    led_bits = expected["led_bits"]
    assert int(dut.result_led0.value) == led_bits["led0"], f"{tc.name}: LED0 mismatch"
    assert int(dut.result_led1.value) == led_bits["led1"], f"{tc.name}: LED1 mismatch"
    assert int(dut.result_led_b_n.value) == led_bits["led_b_n"], f"{tc.name}: LED_B mismatch"
    assert int(dut.result_led_g_n.value) == led_bits["led_g_n"], f"{tc.name}: LED_G mismatch"
    assert int(dut.result_led_r_n.value) == led_bits["led_r_n"], f"{tc.name}: LED_R mismatch"

    next_carry = cout if opcode_updates_carry(tc.opcode) else carry_state
    return next_carry


@cocotb.test()
async def test_alu_top(dut):
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.rst.value = 1
    dut.load_a.value = 0
    dut.load_b.value = 0
    dut.load_sel.value = 0
    dut.data_in.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    directed = [
        TestCase("SUMA", Opcode.ADD, 0x0A, 0x05),
        TestCase("SUMA con carry", Opcode.ADD, 0xFF, 0x01),
        TestCase("ADC con carry", Opcode.ADC, 0x40, 0x40),
        TestCase("SUMA limpia carry", Opcode.ADD, 0x01, 0x01),
        TestCase("ADC sin carry", Opcode.ADC, 0x05, 0x03),
        TestCase("SUMA con overflow", Opcode.ADD, 0x7F, 0x01),
        TestCase("RESTA", Opcode.SUB, 0x34, 0x12),
        TestCase("RESTA con overflow", Opcode.SUB, 0x80, 0x01),
        TestCase("SBC sin préstamo", Opcode.SBC, 0x34, 0x12),
        TestCase("SUB con borrow", Opcode.SUB, 0x00, 0x01),
        TestCase("SBC con préstamo", Opcode.SBC, 0x00, 0x00),
        TestCase("AND", Opcode.AND, 0xF0, 0x0F),
        TestCase("OR", Opcode.OR, 0x55, 0x0F),
        TestCase("XOR", Opcode.XOR, 0xAA, 0x5A),
        TestCase("NOR", Opcode.NOR, 0x00, 0x00),
        TestCase("SRL", Opcode.SRL, 0x02, 0x00),
        TestCase("SRA", Opcode.SRA, 0x81, 0x00),
    ]

    carry_state = 0
    for tc in directed:
        carry_state = await apply_test_case(dut, tc, carry_state)

    rng = random.Random(42)
    opcodes = [
        Opcode.ADD,
        Opcode.ADC,
        Opcode.SUB,
        Opcode.SBC,
        Opcode.AND,
        Opcode.OR,
        Opcode.XOR,
        Opcode.NOR,
        Opcode.SRL,
        Opcode.SRA,
    ]

    for idx in range(120):
        op = rng.choice(opcodes)
        a = rng.randrange(0x100)
        b = rng.randrange(0x100)
        tc = TestCase(f"ALU random {idx}", op, a, b)
        carry_state = await apply_test_case(dut, tc, carry_state)
