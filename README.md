# ALU FPGA en Digilent Cmod A7-35T

Diseño en Verilog y SystemVerilog de una ALU parametrizable de 8 bits para la FPGA Artix-7 (Digilent Cmod A7-35T), desarrollada con Vivado.

El sistema admite dos formas de control:
1. UART directo PC ↔ FPGA (Trabajo Práctico 2): módulo UART en hardware (divisor de baudrate, receptor con oversampling 16x, transmisor, paridad, FIFOs sincrónicas, decodificador de tramas y FSM) comunicado por puerto serie con herramientas Python (CLI y TUI en curses).
2. Control por microcontrolador (Trabajo Práctico 1): firmware en C++ sobre Raspberry Pi Pico que comanda la ALU vía GPIO.

---

## Estructura del Proyecto

```text
├── constraints/              # Restricciones XDC (pines y reloj)
│   └── uart_loopback.xdc     # Asignaciones para Cmod A7 (reloj 12 MHz, UART USB, LEDs, reset)
├── doc/                      # Especificaciones y diagramas
│   ├── ALU_UART_Interface.md # Interfaz entre decodificador y ALU
│   ├── MODULE_CONNECTIONS.md # Conexiones internas
│   ├── PICOCMOD_WIRING.md    # Cableado físico Pico ↔ Cmod A7
│   ├── System_Arquitecture.md# Diagrama de arquitectura general
│   └── UART_Packet_Decoder.md# Protocolo de tramas
├── imgs/                     # Diagramas RTL, ASMD y capturas de simulación
├── pico_uart_to_fpga/        # Firmware PlatformIO para Raspberry Pi Pico
│   ├── platformio.ini
│   ├── scripts/uart_selftest.py
│   └── src/main.cpp
├── scripts/                  # Herramientas de prueba en PC para UART directo
│   ├── alu_uart_serial_test.py # Pruebas automatizadas en puerto serie
│   └── alu_uart_tui_curses.py  # Interfaz de terminal en ncurses
├── src/
│   ├── rtl/                  # Código fuente sintetizable
│   │   ├── alu.v             # Núcleo combinacional de la ALU
│   │   ├── alu_top.v         # Módulo top con banco de registros
│   │   ├── alu_top_fsm.v     # FSM para integración UART-ALU
│   │   ├── sync_fifo.sv      # FIFO sincrónica
│   │   ├── uart_baudrate_gen.sv # Divisor de baudrate y oversampling
│   │   ├── uart_packet_decoder.sv # Decodificador y formateador de respuestas
│   │   ├── uart_parity.v     # Verificador y generador de paridad
│   │   ├── uart_rx.sv        # Receptor UART (muestreo a 16x)
│   │   ├── uart_tx.sv        # Transmisor UART
│   │   └── uart_top.sv       # Integración UART (transceptor y FIFOs)
│   └── sim/                  # Bancos de pruebas y verificación
│       ├── scripts/          # Generadores de vectores de prueba en Python
│       └── sv/               # Testbenches SystemVerilog
├── CHANGELOG.md              # Registro de versiones
├── INFORME.md                # Informe técnico de TP1 (ALU con microcontrolador)
├── INFORME_UART.md           # Informe técnico de TP2 (UART en FPGA)
├── LICENSE                   # Licencia MIT
└── README.md
```

---

## Requisitos

### Hardware
- Placa FPGA Digilent Cmod A7-35T.
- Cable micro-USB (programación JTAG y comunicación serie UART por el puente FTDI).
- *(Opcional para TP1)*: Placa Raspberry Pi Pico y cables jumper.

### Software
- Xilinx Vivado Design Suite (versión 2024 o posterior).
- Python 3 con paquete `pyserial`:
  ```bash
  pip install pyserial
  ```
- *(Opcional para TP1)*: PlatformIO (`pip install platformio`).

---

## Control Directo PC ↔ FPGA vía UART (TP2)

La FPGA se conecta por USB a la PC. El conversor FTDI integrado en la Cmod A7 expone el puerto serie mapeado según `constraints/uart_loopback.xdc`.

### Protocolo de Tramas
Trama de 4 bytes:
```
[STX] [CMD] [DATA] [ETX]
```
- STX: `0x02`
- ETX: `0x03`
- Comandos (CMD):
  - `0x41` (`'A'`): Carga operando A (`DATA`: 8 bits).
  - `0x42` (`'B'`): Carga operando B (`DATA`: 8 bits).
  - `0x43` (`'C'`): Carga opcode (`DATA`: 6 bits de operación).
  - `0x45` (`'E'`): Ejecuta la operación (`DATA`: 0x00).
- Respuesta de la FPGA:
  ```
  [0x02] [0x02] [RESULT] [0x03]
  ```
  `RESULT` contiene el resultado de 8 bits entregado por la ALU.

### Scripts en Python

#### Pruebas automáticas (`alu_uart_serial_test.py`)
Ejecuta la suite de operaciones aritméticas, lógicas y de desplazamiento con verificación de resultados y flags:
```bash
python3 scripts/alu_uart_serial_test.py /dev/ttyUSB0 --baud 9600
```
*En Windows, sustituir `/dev/ttyUSB0` por el puerto asignado (por ejemplo, `COM3`).*

#### Interfaz interactiva (`alu_uart_tui_curses.py`)
Permite seleccionar opcodes, cargar operandos y observar el intercambio de tramas en tiempo real:
```bash
python3 scripts/alu_uart_tui_curses.py /dev/ttyUSB0 --baud 9600
```

---

## Control por Raspberry Pi Pico (TP1)

### Compilación y carga del firmware
1. Entorno virtual e instalación de dependencias:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install platformio
   ```
2. Compilar y cargar:
   ```bash
   cd pico_uart_to_fpga
   platformio run --target upload
   ```
3. Monitor serie a 115200 baudios:
   ```bash
   platformio device monitor --baud 115200
   ```

### Comandos de la consola
- `A <valor>`: Carga operando A en decimal o hexadecimal (`A 0x2A`).
- `B <valor>`: Carga operando B.
- `S <valor>`: Carga opcode de 6 bits (`S 0x20` para ADD).
- `W <valor>`: Fuerza bus de datos para depuración.
- `R`: Pulso de reset síncrono.
- `P`: Lee resultado y flags (Cout, Zero).
- `H`: Muestra ayuda.

Autotest con la Pico:
```bash
python3 pico_uart_to_fpga/scripts/uart_selftest.py /dev/ttyACM0 --baud 115200
```

---

## Opcodes de la ALU

Opcodes de 6 bits: bits `[5:2]` definen la familia (`1000` aritmética, `1001` lógica, `0000` desplazamientos) y bits `[1:0]` la operación.

| Mnemónico | Binario | Hex  | Operación | Detalle |
|---|---|---|---|---|
| ADD | 100000 | 0x20 | `A + B` | Suma |
| ADC | 100001 | 0x21 | `A + B + Cin` | Suma con acarreo previo |
| SUB | 100010 | 0x22 | `A - B` | Resta (`A + ~B + 1`) |
| SBC | 100011 | 0x23 | `A - B - (1 - Cout_prev)` | Resta con borrow previo |
| AND | 100100 | 0x24 | `A & B` | AND bit a bit |
| OR  | 100101 | 0x25 | `A \| B` | OR bit a bit |
| XOR | 100110 | 0x26 | `A ^ B` | XOR bit a bit |
| NOR | 100111 | 0x27 | `~(A \| B)` | NOR bit a bit |
| SRL | 000010 | 0x02 | `A >> 1` | Desplazamiento lógico derecha |
| SRA | 000011 | 0x03 | `A >>> 1` | Desplazamiento aritmético derecha |

---

## Simulación

### 1. Simulación de la ALU
```bash
cd src/sim/scripts
python3 gen_test_vectors.py
```
Abrir `src/sim/sv/tb_alu.sv` en el simulador de Vivado y ejecutar `run all`.

### 2. Módulos UART en SystemVerilog
- Generador de baudrate: `src/sim/sv/tb_uart_baudrate_gen.sv`
- Transmisor: `src/sim/sv/tb_uart_tx.sv` (vectores generados con `gen_uart_tx_vectors.py`)
- Receptor: `src/sim/sv/tb_uart_rx.sv` (vectores generados con `gen_uart_rx_vectors.py`)
- FIFO sincrónica: `src/sim/sv/tb_sync_fifo.sv` (script: `src/sim/scripts/run_fifo_tb.sh`)
- Decodificador de tramas: `src/sim/sv/tb_uart_packet_decoder.sv` (script: `src/sim/scripts/run_uart_decoder_tb.sh`)
- FSM de control: `src/sim/sv/tb_alu_top_fsm.sv` (script: `src/sim/scripts/run_alu_top_fsm_tb.sh`)
- Sistema UART integrado: `src/sim/sv/uart_top_tb.sv`

---

## Documentación e Informes Técnicos

- [INFORME_UART.md](INFORME_UART.md): Informe técnico del Trabajo Práctico 2 (UART en SystemVerilog, diagramas ASMD, recursos en FPGA y mediciones en osciloscopio).
- [INFORME.md](INFORME.md): Informe técnico del Trabajo Práctico 1 (ALU y control con Raspberry Pi Pico).
- [CHANGELOG.md](CHANGELOG.md): Historial de versiones del proyecto.

---

## Licencia

Licencia MIT. Ver [LICENSE](LICENSE).
