# Proyecto ALU FPGA con Raspberry Pi Pico y CMOD A7

Este repositorio contiene el diseño de hardware para una Unidad Aritmético-Lógica (ALU) simple implementada en un FPGA utilizando Vivado, junto con una interfaz básica basado en una Raspberry Pi Pico para interactuar con la ALU a través de UART.

## Descripción General

La ALU es un componente fundamental de una CPU que realiza operaciones aritméticas y lógicas. Este proyecto implementa una ALU básica de 8 bits capaz de operaciones como suma, suma con carry, resta, resta con borrow, AND, OR, XOR, NOT y desplazamientos. La FPGA se ejecuta en la placa CMOD A7-35T y la Raspberry Pi Pico actúa como interfaz para cargar operandos y opcodes vía comandos UART, permitiendo control, lectura de resultados y flags de estado (Carry Out, Zero).

El diseño utiliza Verilog, con uso de packages y enum de System Verilog, para la ALU en la FPGA y C++ para el firmware de la Pico con PlatformIO.

## Estructura de Directorios

El proyecto sigue una estructura estándar para proyectos Vivado y PlatformIO:

- **`/src`**: Contiene todos los archivos fuente en Verilog para el diseño de la FPGA.
  - **`/src/rtl`**: Archivos de diseño RTL que describen la lógica de la ALU y sus componentes (`alu_top.v`, `alu.v`, etc.).
  - **`/src/sim`**: Archivos para la simulación lógica del diseño.
    - **`/src/sim/sv`**: Contiene el testbench principal en SystemVerilog (`tb_alu.sv`) y los vectores de prueba (`alu_test_vectors.svh`) que este consume.
    - **`/src/sim/scripts`**: Incluye el script de Python (`gen_test_vectors.py`) que genera los vectores de prueba para el testbench.
- **`/constraints`**: Archivos de restricciones de diseño (`.xdc`), incluyendo asignaciones de pines y restricciones de tiempo.
- **`/doc`**: Documentación del proyecto, hojas de datos y documentos relevantes (MODULE_CONNECTIONS.md, PICOCMOD_WIRING.md).
- **`/pico_uart_to_fpga`**: Proyecto de la Raspberry Pi Pico.
  - **`/src`**: Código fuente principal (main.cpp).
  - **`/scripts`**: Scripts de prueba de hardware (uart_selftest.py).
  - `platformio.ini`: Configuración de PlatformIO.

## Requisitos

### Para el FPGA (CMOD A7)
- **Xilinx Vivado Design Suite**: Versión 2024 o posterior.
- Placa CMOD A7-35T de Digilent.

### Para el Raspberry Pi Pico
- **PlatformIO**.
- Raspberry Pi Pico 2.
- Conexiones físicas entre Pico y CMOD A7 según el diagrama de cableado.

## Configuración

### Configuración del FPGA
1. Clonar el repositorio:
   ```bash
   git clone <url-del-repositorio>
   cd FPGA_ALU_RP2
   ```

2. Abrir Vivado y cargar los archivos source y constraints.

3. Ejecutar la síntesis e implementación para generar el bitstream.

4. Cargar el bitstream en la placa CMOD A7 usando el programador integrado de Vivado.

### Configuración del Raspberry Pi Pico
1. Crear un entorno virtual de Python (venv) en la carpeta del proyecto: `python -m venv .venv`.

2. Activar el venv: `source .venv/bin/activate`.

3. Instalar PlatformIO: `pip install platformio`.

4. Compilar y cargar el firmware: `cd pico_uart_to_fpga && platformio run --target upload`.

5. Conectar la Pico mediante un USB para acceder a la consola UART (115200 baudios).

6. Ejecutar el monitor serial: `cd pico_uart_to_fpga && platformio device monitor --baud 115200`.

## Uso

### Interacción con la ALU vía Pico
El firmware del Pico proporciona una interfaz de comandos UART (vía USB Serial). 

**Comandos disponibles:**
- `A <valor>`: Carga el operando A (valor de 8 bits en decimal o 0x hex, ej. `A 42` o `A 0x2A`).
- `B <valor>`: Carga el operando B.
- `S <valor>`: Carga el opcode de 6 bits.
- `W <valor>`: Establece el bus de datos sin realizar una operación (para debug).
- `R`: Pulso de reset síncrono en la FPGA.
- `P`: Imprime el resultado y flags de estado (Cout, Zero).
- `H`: Muestra ayuda.

Los resultados se muestran en LEDs de la CMOD A7 y se pueden leer en el monitor serial.

**Ejemplo de sesión:**
```
> A 5
Loaded A = 0x05
Result=0x00 Cout=0 Zero=1

> B 3
Loaded B = 0x03
Result=0x00 Cout=0 Zero=1

> S 0x20  # Opcode para ADD (100000)
Loaded opcode = 0x20
Result=0x08 Cout=0 Zero=0

> P
Result=0x08 Cout=0 Zero=0
```

### Simulación (Vivado)

La verificación funcional del diseño RTL se realiza mediante un testbench de SystemVerilog (`tb_alu.sv`) dentro del entorno de simulación de Vivado. Este testbench utiliza vectores de prueba que son generados por un script externo (`gen_test_vectors.py`).

El flujo de simulación consta de dos pasos:

**Paso 1: Generar los Vectores de Prueba**

Antes de poder simular, es necesario generar los casos de prueba. Esto se hace con el script de Python `gen_test_vectors.py`.

1.  Navegar al directorio de scripts de simulación:
    ```bash
    cd src/sim/scripts
    ```

2.  Ejecutar el script:
    ```bash
    python3 gen_test_vectors.py
    ```
    Este comando creará el archivo `src/sim/sv/alu_test_vectors.svh`. Este archivo contiene los casos de prueba (entradas y resultados esperados) que el testbench de SystemVerilog utilizará para verificar la ALU.

**Paso 2: Ejecutar la Simulación en Vivado**

1.  Abrir el proyecto en Vivado.
2.  Asegurar de que `tb_alu.sv` esté definido como el "top" del conjunto de simulación.
3.  Hacer clic en **Run Simulation** y luego en **Run Behavioral Simulation**.
4.  Los resultados de la prueba se imprimirán en la **Tcl Console**. Para ejecutar la totalidad de los test, utilizar el comando `run all` en la consola TCL.

### Pruebas Automatizadas con uart_selftest.py
El script `uart_selftest.py` permite ejecutar pruebas automatizadas de la ALU mediante comandos UART. Este script envía secuencias de comandos al Pico para probar diferentes operaciones de la ALU y verificar los resultados.

Para ejecutar las pruebas automatizadas:
```bash
cd pico_uart_to_fpga/scripts/
python3 uart_selftest.py /dev/ttyACMx
```
Donde `/dev/ttyACMx` es el puerto serial al que está conectado el Pico. Por ejemplo, `/dev/ttyACM1` o `/dev/ttyACM0`.

Opciones adicionales:
- `--baud`: Establece la velocidad en baudios (por defecto 115200)
- `--timeout`: Establece el tiempo de espera en segundos (por defecto 1.0)
- `--hex-opcode`: Envía los opcodes con prefijo 0x

Ejemplo:
```bash
python3 uart_selftest.py /dev/ttyACM0 --baud 115200 --timeout 2.0
```

El script realiza una serie de pruebas predefinidas para operaciones aritméticas, lógicas y de desplazamiento, verificando los resultados y las flags (Cout, Zero) esperadas.

## Mapa de Opcodes

La ALU sigue los códigos de 6 bits propuestos a continuación. Cada valor
selecciona directamente una operación. Los bits `[5:2]` determinan la familia
(1000 = aritmética, 1001 = lógica, 0000 = desplazamientos) y los bits bajos
identifican la operación concreta dentro de esa familia.

| Mnemonic | Binario | Hex  | Operación                         
|----------|---------|------|-----------------------------------
| ADD      | 100000  | 0x20 | `A + B`                          
| ADC      | 100001  | 0x21 | `A + B + Cin` (Cin = último `Cout`)
| SUB      | 100010  | 0x22 | `A - B` (`A + ~B + 1`)           
| SBC      | 100011  | 0x23 | `A - B - (1 - Cout_prev)`        
| AND      | 100100  | 0x24 | `A & B`                          
| OR       | 100101  | 0x25 | `A | B`                          
| XOR      | 100110  | 0x26 | `A ^ B`                          
| NOR      | 100111  | 0x27 | `~(A | B)`                       
| SRL      | 000010  | 0x02 | `A >> 1` (desplazamiento lógico) 
| SRA      | 000011  | 0x03 | `A >>> 1` (desplazamiento aritmético) 

## Conexiones de Hardware (Pico ↔ CMOD A7)

Conectar según la tabla en `doc/PICOCMOD_WIRING.md`. 

## Licencia

Este proyecto está licenciado bajo la Licencia MIT. Ver el archivo `LICENSE` para más detalles.
