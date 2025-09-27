#include "Valu_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include <array>
#include <cstdint>
#include <exception>
#include <iostream>
#include <iomanip>
#include <random>
#include <sstream>
#include <string>
#include <vector>

/**
 * @file tb_alu.cpp
 * @brief Testbench para simulación de ALU usando Verilator en C++.
 * Este archivo implementa un testbench para el módulo ALU implementado en Verilog,
 * ejecutando casos dirigidos y aleatorios para verificar operaciones aritméticas,
 * lógicas y de desplazamiento, comparando contra un modelo de referencia.
 */

/**
 * @enum Opcode
 * @brief Enumeración de opcodes para ALU.
 * Refleja operaciones soportadas: aritméticas (ADD, SUB), lógicas (AND, OR, XOR, NOR)
 * y desplazamientos (SRL, SRA), usando valores binarios de 6 bits.
 */
enum class Opcode : uint8_t
{
    ADD = 0b100000, //!< Suma A + B
    ADC = 0b100001, //!< Suma A + B con acarreo previo
    SUB = 0b100010, //!< Resta A - B
    SBC = 0b100011, //!< Resta A - B con préstamo
    AND = 0b100100, //!< AND bit a bit A & B
    OR = 0b100101,  //!< OR bit a bit A | B
    XOR = 0b100110, //!< XOR bit a bit A ^ B
    NOR = 0b100111, //!< NOR bit a bit
    SRL = 0b000010, //!< Desplazamiento derecho lógico A >> B
    SRA = 0b000011  //!< Desplazamiento derecho aritmético A >>> B
};

const char *opcode_to_string(Opcode op)
{
    switch (op)
    {
    case Opcode::ADD:
        return "ADD";
    case Opcode::ADC:
        return "ADC";
    case Opcode::SUB:
        return "SUB";
    case Opcode::SBC:
        return "SBC";
    case Opcode::AND:
        return "AND";
    case Opcode::OR:
        return "OR";
    case Opcode::XOR:
        return "XOR";
    case Opcode::NOR:
        return "NOR";
    case Opcode::SRL:
        return "SRL";
    case Opcode::SRA:
        return "SRA";
    default:
        return "UNKNOWN";
    }
}

/**
 * @struct ModelOut
 * @brief Estructura para salida del modelo de referencia de ALU.
 * Contiene el resultado esperado y flags para comparación con DUT.
 */
struct ModelOut
{
    uint8_t result; //!< Resultado de 8 bits
    bool cout;      //!< Carry out
    bool overflow;  //!< Overflow
};

/**
 * @struct TestCase
 * @brief Estructura para casos de prueba de ALU.
 * Define un caso de prueba con nombre, opcode y operandos para la verificación.
 */
struct TestCase
{
    std::string name; //!< Nombre descriptivo del caso de prueba
    Opcode opcode;    //!< Opcode de la operación
    uint8_t A;        //!< Operando A
    uint8_t B;        //!< Operando B
};

std::string format_hex8(uint32_t value)
{
    std::ostringstream oss;
    oss << "0x"
        << std::uppercase << std::setfill('0') << std::setw(2)
        << std::hex << (value & 0xFF);
    return oss.str();
}

std::string format_dut_snapshot(const Valu_top *dut)
{
    std::ostringstream snap;
    snap << "Res=" << format_hex8(dut->Result)
         << " Cout=" << static_cast<uint32_t>(dut->Cout)
         << " Zero=" << static_cast<uint32_t>(dut->Zero)
         << " Ovf=" << static_cast<uint32_t>(dut->Overflow);
    return snap.str();
}

std::string format_test_context(const TestCase &tc, bool include_carry, bool carry_in)
{
    std::ostringstream oss;
    oss << std::left << std::setw(24) << tc.name << " | "
        << "op=" << std::setw(3) << opcode_to_string(tc.opcode) << " | "
        << "A=" << format_hex8(tc.A) << " | "
        << "B=" << format_hex8(tc.B);
    if (include_carry)
    {
        oss << " | Cin=" << static_cast<uint32_t>(carry_in);
    }
    return oss.str();
}

bool opcode_uses_carry(Opcode op)
{
    return op == Opcode::ADC || op == Opcode::SBC;
}

bool opcode_updates_carry(Opcode op)
{
    switch (op)
    {
    case Opcode::ADD:
    case Opcode::ADC:
    case Opcode::SUB:
    case Opcode::SBC:
        return true;
    default:
        return false;
    }
}

/**
 * @brief Tiempo de simulación global para realizar las formas de onda en el archivo VCD.
 * Variable estática para rastrear tiempo en ticks para el grabado en el archivo VCD.
 */
static vluint64_t sim_time = 0;

/**
 * @brief Avanza un ciclo de reloj en la simulación.
 * Genera un pulso de reloj completo (bajo a alto) y actualiza el archivo VCD.
 * @param dut Puntero al DUT (Device Under Test) de Verilator.
 * @param trace Puntero al trace VCD para el registro de formas de onda.
 */
void tick(Valu_top *dut, VerilatedVcdC *trace)
{
    dut->clk = 0;
    dut->eval();
    trace->dump(sim_time++);
    dut->clk = 1;
    dut->eval();
    trace->dump(sim_time++);
}

/**
 * @brief Genera un pulso de carga para señales de control.
 * Establece data_in y pulso alto en load_signal por un ciclo de reloj.
 * @param dut Puntero al DUT.
 * @param trace Puntero al trace VCD.
 * @param load_signal Referencia a la señal de carga (load_a, load_b o load_sel).
 * @param value Valor a cargar en data_in.
 */
void pulse_load(Valu_top *dut, VerilatedVcdC *trace, CData &load_signal, uint8_t value)
{
    dut->data_in = value;
    load_signal = 1;
    tick(dut, trace);
    load_signal = 0;
}

/**
 * @brief Modelo de referencia (golden model) para ejecución de ALU.
 * Calcula la salida esperada para una operación dada, usado para la verificación contra DUT.
 * @param opcode Opcode de la operación a simular.
 * @param A Operando A de 8 bits.
 * @param B Operando B de 8 bits.
 * @param carry_in Carry in para operaciones con carry.
 * @return Estructura ModelOut con resultado, cout y overflow esperados.
 * @throws std::runtime_error Si el opcode no está manejado.
 */
ModelOut model_execute(Opcode opcode, uint8_t A, uint8_t B, bool carry_in = false)
{
    ModelOut out{0, false, false};
    auto sign_bit = [](uint8_t v)
    { return (v >> 7) & 0x1; };

    switch (opcode)
    {
    case Opcode::ADD:
    case Opcode::ADC:
    {
        uint16_t carry_val = (opcode == Opcode::ADC && carry_in) ? 1 : 0;
        uint16_t wide = static_cast<uint16_t>(A) + static_cast<uint16_t>(B) + carry_val;
        out.result = static_cast<uint8_t>(wide & 0xFF);
        out.cout = (wide >> 8) & 0x1;
        bool same_sign = (sign_bit(A) == sign_bit(B));
        bool sign_diff = (sign_bit(A) != sign_bit(out.result));
        out.overflow = same_sign && sign_diff;
        break;
    }
    case Opcode::SUB:
    case Opcode::SBC:
    {
        uint8_t add_operand = static_cast<uint8_t>(~B);
        uint16_t carry_val = (opcode == Opcode::SUB) ? 1 : (carry_in ? 1 : 0);
        uint16_t wide = static_cast<uint16_t>(A) + static_cast<uint16_t>(add_operand) + carry_val;
        out.result = static_cast<uint8_t>(wide & 0xFF);
        out.cout = (wide >> 8) & 0x1;
        bool same_sign = (sign_bit(A) == sign_bit(add_operand));
        bool sign_diff = (sign_bit(A) != sign_bit(out.result));
        out.overflow = same_sign && sign_diff;
        break;
    }
    case Opcode::AND:
        out.result = static_cast<uint8_t>(A & B);
        break;
    case Opcode::OR:
        out.result = static_cast<uint8_t>(A | B);
        break;
    case Opcode::XOR:
        out.result = static_cast<uint8_t>(A ^ B);
        break;
    case Opcode::NOR:
        out.result = static_cast<uint8_t>(~(A | B));
        break;
    case Opcode::SRL:
    {
        uint8_t shift_amt = B;
        if (shift_amt >= 8)
        {
            out.result = 0u;
        }
        else
        {
            out.result = static_cast<uint8_t>(static_cast<uint16_t>(A) >> shift_amt);
        }
        break;
    }
    case Opcode::SRA:
    {
        uint8_t shift_amt = B;
        if (shift_amt >= 8)
        {
            out.result = static_cast<uint8_t>((A & 0x80) ? 0xFF : 0x00);
        }
        else
        {
            out.result = static_cast<uint8_t>(static_cast<int8_t>(A) >> shift_amt);
        }
        break;
    }
    default:
        throw std::runtime_error("Opcode no manejado en el modelo");
    }

    return out;
}

/**
 * @brief Verifica salidas del DUT contra el modelo de referencia.
 * Compara resultado, flags (Cout, Overflow, Zero) y LEDs contra valores esperados.
 * Imprime PASS/FAIL para cada campo discrepante.
 * @param dut Puntero al DUT.
 * @param expected Estructura con valores esperados del modelo.
 * @param tc Caso de prueba actual para nombre en mensajes.
 * @return true si todas las salidas coinciden, false en caso contrario.
 */
bool check_outputs(Valu_top *dut, const ModelOut &expected, const TestCase &tc, bool carry_in)
{
    bool pass = true;
    const bool include_carry = opcode_uses_carry(tc.opcode);
    const std::string test_context = format_test_context(tc, include_carry, carry_in);

    auto print_fail = [&](const std::string &field, uint32_t got, uint32_t exp, bool use_hex = false)
    {
        std::ostringstream msg;
        msg << "  [FAIL] " << test_context
            << " | " << format_dut_snapshot(dut)
            << " :: " << field << " exp=";

        if (use_hex)
        {
            msg << format_hex8(exp);
        }
        else
        {
            msg << static_cast<uint32_t>(exp);
        }

        msg << " got=";

        if (use_hex)
        {
            msg << format_hex8(got);
        }
        else
        {
            msg << static_cast<uint32_t>(got);
        }

        std::cerr << msg.str() << std::endl;
        pass = false;
    };

    if (dut->Result != expected.result)
    {
        print_fail("Result", dut->Result, expected.result, true);
    }

    if (dut->Cout != expected.cout)
    {
        print_fail("Cout", dut->Cout, expected.cout);
    }

    if (dut->Overflow != expected.overflow)
    {
        print_fail("Overflow", dut->Overflow, expected.overflow);
    }

    bool expected_zero = (expected.result == 0);
    if (dut->Zero != expected_zero)
    {
        print_fail("Zero", dut->Zero, expected_zero ? 1U : 0U);
    }

    uint8_t bit0 = expected.result & 0x1;
    uint8_t bit1 = (expected.result >> 1) & 0x1;
    uint8_t bit2 = (expected.result >> 2) & 0x1;
    uint8_t bit3 = (expected.result >> 3) & 0x1;
    uint8_t bit4 = (expected.result >> 4) & 0x1;

    if (dut->result_led0 != bit0)
    {
        print_fail("result_led0", dut->result_led0, bit0);
    }
    if (dut->result_led1 != bit1)
    {
        print_fail("result_led1", dut->result_led1, bit1);
    }
    if (dut->result_led_b_n != static_cast<uint8_t>(bit2 ^ 0x1))
    {
        print_fail("result_led_b_n", dut->result_led_b_n, static_cast<uint8_t>(bit2 ^ 0x1));
    }
    if (dut->result_led_g_n != static_cast<uint8_t>(bit3 ^ 0x1))
    {
        print_fail("result_led_g_n", dut->result_led_g_n, static_cast<uint8_t>(bit3 ^ 0x1));
    }
    if (dut->result_led_r_n != static_cast<uint8_t>(bit4 ^ 0x1))
    {
        print_fail("result_led_r_n", dut->result_led_r_n, static_cast<uint8_t>(bit4 ^ 0x1));
    }

    if (pass)
    {
        std::cout << "  [PASS] " << test_context
                  << " | " << format_dut_snapshot(dut)
                  << std::endl;
    }

    return pass;
}

/**
 * @brief Ejecuta un caso de prueba completo para ALU.
 * Carga operandos y opcode vía pulsos de control, avanza reloj y verifica salidas.
 * @param dut Puntero al DUT.
 * @param trace Puntero al trace VCD.
 * @param tc Caso de prueba a ejecutar.
 * @throws std::runtime_error Si la verificación falla.
 */
void run_test(Valu_top *dut, VerilatedVcdC *trace, const TestCase &tc, bool &carry_state)
{
    bool carry_in = opcode_uses_carry(tc.opcode) ? carry_state : false;

    pulse_load(dut, trace, dut->load_a, tc.A);
    pulse_load(dut, trace, dut->load_b, tc.B);
    pulse_load(dut, trace, dut->load_sel, static_cast<uint8_t>(tc.opcode));
    tick(dut, trace);

    ModelOut expected = model_execute(tc.opcode, tc.A, tc.B, carry_in);
    if (!check_outputs(dut, expected, tc, carry_in))
    {
        throw std::runtime_error("Prueba fallida");
    }

    if (opcode_updates_carry(tc.opcode))
    {
        carry_state = static_cast<bool>(dut->Cout);
    }
}

/**
 * @brief Realiza un reset completo del DUT.
 * Establece la señal de reset, espera ciclos de reloj y la desactiva.
 * @param dut Puntero al DUT.
 * @param trace Puntero al trace VCD.
 */
void reset_dut(Valu_top *dut, VerilatedVcdC *trace)
{
    dut->rst = 1;
    tick(dut, trace);
    dut->rst = 0;
    tick(dut, trace);
}

/**
 * @brief Función principal: configura simulación, ejecuta pruebas y genera el reporte.
 * Inicializa Verilator, DUT y trace VCD; ejecuta casos dirigidos y aleatorios;
 * verifica salidas y cierra la simulación.
 * @param argc Número de argumentos de línea de comandos.
 * @param argv Argumentos de línea de comandos para Verilator.
 * @return EXIT_SUCCESS si todas las pruebas pasan, EXIT_FAILURE en caso de error.
 */
int main(int argc, char **argv)
{
    VerilatedContext context;
    context.commandArgs(argc, argv);
    context.traceEverOn(true);

    Valu_top dut{&context};
    VerilatedVcdC trace;
    dut.trace(&trace, 99);
    trace.open("dump.vcd");

    reset_dut(&dut, &trace);

    bool carry_state = false;

    std::vector<TestCase> directed = {
        {"SUMA", Opcode::ADD, 0x0A, 0x05},
        {"SUMA con carry", Opcode::ADD, 0xFF, 0x01},
        {"ADC con carry", Opcode::ADC, 0x40, 0x40},
        {"Carry reset", Opcode::ADD, 0x01, 0x01},
        {"ADC sin carry", Opcode::ADC, 0x05, 0x03},
        {"SUMA con overflow", Opcode::ADD, 0x7F, 0x01},
        {"RESTA", Opcode::SUB, 0x34, 0x12},
        {"RESTA con overflow", Opcode::SUB, 0x80, 0x01},
        {"SBC sin borrow", Opcode::SBC, 0x34, 0x12},
        {"SUB con borrow", Opcode::SUB, 0x00, 0x01},
        {"SBC con préstamo", Opcode::SBC, 0x00, 0x00},
        {"AND", Opcode::AND, 0xF0, 0x0F},
        {"OR", Opcode::OR, 0x55, 0x0F},
        {"XOR", Opcode::XOR, 0xAA, 0x5A},
        {"NOR", Opcode::NOR, 0x00, 0x00},
        {"SRL", Opcode::SRL, 0xC0, 0x03},
        {"SRA", Opcode::SRA, 0x81, 0x02},
        {"SRL", Opcode::SRL, 0xAA, 0x20},
        {"SRA", Opcode::SRA, 0x81, 0x20}
    };

    try
    {
        for (const auto &tc : directed)
        {
            run_test(&dut, &trace, tc, carry_state);
        }

        std::mt19937 rng(42);
        std::uniform_int_distribution<int> value_dist(0, 0xFF);

        auto run_random = [&](const std::vector<Opcode> &ops, const std::string &label, int count)
        {
            for (int i = 0; i < count; ++i)
            {
                uint8_t A = static_cast<uint8_t>(value_dist(rng));
                uint8_t B = static_cast<uint8_t>(value_dist(rng));
                Opcode op = ops[rng() % ops.size()];
                TestCase tc{label + " aleatorio", op, A, B};
                run_test(&dut, &trace, tc, carry_state);
            }
        };

        const std::vector<Opcode> all_ops = {
            Opcode::ADD,
            Opcode::ADC,
            Opcode::SUB,
            Opcode::SBC,
            Opcode::AND,
            Opcode::OR,
            Opcode::XOR,
            Opcode::NOR,
            Opcode::SRL,
            Opcode::SRA};

        run_random(all_ops, "ALU", 120);
    }
    catch (const std::exception &e)
    {
        std::cerr << "Error en simulación: " << e.what() << std::endl;
        trace.close();
        return EXIT_FAILURE;
    }

    tick(&dut, &trace);
    trace.close();
    std::cout << "\nTodas las pruebas completadas exitosamente." << std::endl;
    return EXIT_SUCCESS;
}
