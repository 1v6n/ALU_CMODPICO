<p align="center">
  <a>
    <img src="imgs/Logo.png" alt="Logo">
  </a>

***TRABAJO PRACTICO 2***

**Titulo:** UART Parametrizable para Control de ALU

**Asignatura:** Arquitectura de Computadoras

**Integrantes:**
   - Ignacio Ledesma
   - Ivan Zuñiga

---------------

## Enunciado

Desarrollar una UART (Universal Asynchronous Receiver-Transmitter) parametrizable en SystemVerilog para controlar la ALU desarrollada en el trabajo práctico anterior. La UART debe implementar comunicación serie full-duplex con parámetros configurables, incluyendo generador de baudrate, módulo transmisor y receptor.

### Requerimientos

1. **Generador de Baudrate:**
    - Implementar un divisor de frecuencia que genere señales de temporización para UART
    - Utilizar la frecuencia de reloj de 12 MHz de la Cmod A7-35T

2. **Módulo Transmisor UART (TX):**
    - Implementar máquina de estados para transmisión serie
    - Soportar formato configurable: 8 bits de datos (parametrizable)
    - (opcional) Incluir bit de paridad (parametrizable: par, impar, ninguna)
    - Configurar 1 stop bit

3. **Módulo Receptor UART (RX):**
    - Implementar máquina de estados para recepción serie
    - Detectar automáticamente el bit de start
    - Muestrear datos en el centro del bit usando oversampling
    - Verificar paridad y detectar errores de trama

4. **Integración con ALU:**
    - Interfaz de comandos para controlar la ALU del TP anterior
    - Protocolo de comunicación para envío de operandos y opcodes
    - Lectura de resultados y flags de la ALU vía UART

---

## Marco Teórico

### Comunicación UART

La comunicación UART (Universal Asynchronous Receiver-Transmitter) es un protocolo de comunicación serie asíncrona ampliamente utilizado en sistemas embebidos. A diferencia de los protocolos síncronos, UART no requiere una línea de reloj compartida, sino que depende de que ambos extremos de la comunicación operen a la misma velocidad de transmisión (baudrate).

---

## Especificaciones del Sistema

- **FPGA:** Xilinx Artix-7 (XC7A35T-1CPG236C) en placa Cmod A7-35T
- **Frecuencia de reloj:** 12 MHz (oscilador integrado)
- **Herramientas:** Vivado, SystemVerilog
- **Protocolo:** UART parametrizable (8 bits de datos, paridad, 1 stop bit)

---

## 1. Baudrate Generator

### 1.1. Baudrate y Temporización

El baudrate define la velocidad de transmisión en bits por segundo (bps). Para una comunicación exitosa, ambos dispositivos deben estar sincronizados temporalmente.

#### **Justificación del Baudrate de 9600 bps**

La selección de 9600 bps como velocidad de transmisión se basa en múltiples consideraciones técnicas y prácticas:

**1. Compatibilidad Universal**
- 9600 bps es uno de los baudrates estándar más ampliamente soportados
- Garantiza compatibilidad con la mayoría de dispositivos y software de terminal
- Es el baudrate por defecto en muchos microcontroladores y sistemas embebidos

**2. Precisión con Reloj de 12 MHz**
```
Factor de división = 12,000,000 Hz ÷ 9600 bps = 1250
Error de cuantización = 0% (división exacta)
```
Esta división exacta elimina completamente el error de cuantización, proporcionando una precisión perfecta en la temporización.

**3. Comparación con Otros Baudrates Comunes**

| Baudrate | Factor División | Error | Observaciones |
|----------|----------------|-------|---------------|
| 4800 bps | 2500 | 0% | Muy lento para aplicaciones interactivas |
| 9600 bps | 1250 | 0% | **ÓPTIMO: División exacta, velocidad adecuada** |
| 19200 bps | 625 | 0% | Rápido, pero menos tolerante a ruido |
| 38400 bps | 312.5 | ~0.16% | Requiere aproximación, introduce error |
| 115200 bps | ~104.17 | ~0.16% | Muy rápido, sensible a condiciones de línea |

**4. Consideraciones de Potencia**
- Baudrates menores resultan en menor actividad de conmutación
- Reduce el consumo de potencia en sistemas alimentados por batería
- Disminuye la generación de EMI (interferencia electromagnética)

### 1.2. Oversampling en Sistemas UART

El oversampling es una técnica que consiste en muestrear la señal de entrada múltiples veces durante cada período de bit. Esto proporciona varios beneficios:

- **Tolerancia a variaciones de frecuencia**: Compensa pequeñas diferencias entre los relojes del transmisor y receptor
- **Inmunidad al ruido**
- **Detección de partes de la trama**: Facilita la identificación de bits de start, data y stop
- **Sincronización robusta**: Permite encontrar el centro óptimo de cada bit para el muestreo

#### **Justificación del Factor de Oversampling 16x**

La elección del factor de oversampling de 16x se fundamenta en principios teóricos de procesamiento de señales y estándares de la industria:

**1. Fundamento Teórico - Teorema de Nyquist**

Frecuencia de muestreo mínima = 2 × frecuencia máxima de la señal   
Para baudrate de 9600 bps: fmin = 2 × 9600 = 19.2 kHz   
Con oversampling 16x: fsampling = 16 × 9600 = 153.6 kHz   
Margen de seguridad = 153.6 / 19.2 = 8x sobre el mínimo teórico

**2. Estándar de la Industria:** 16x es el factor de oversampling más común en UARTs comerciales

**3. Detección precisa del centro de bit**: 8 muestras antes y después del centro

### 1.3. Diagrama RTL del Baudrate Generator

<p align="center">
  <a>
    <img src="imgs/baudrate_gen_rtl.jpg" alt="Baudrate_Generator">
  </a>

---

## Módulo Transmisor (TX)

### 2.1 Importancia del Transmisor UART y Relación con Baudrate Generator

El módulo transmisor UART (TX) constituye el componente crítico responsable de la serialización y transmisión de datos paralelos a través de un canal serie asíncrono. Su función principal consiste en convertir palabras de datos de ancho parametrizable (típicamente 8 bits) junto con flags de estado (zero y carry de la ALU) en una secuencia serial temporizada que cumple con el estándar UART.

#### **Frame UART: Estructura y Componentes**

Un frame UART es la unidad fundamental de transmisión en el protocolo UART. La estructura implementada en este diseño transmite **dos frames consecutivos** para cada resultado de la ALU:

**Frame 1 (Datos):**
```
[START] [D0 D1 D2 D3 D4 D5 D6 D7] [PARITY] [STOP]
   1         8 bits (LSB first)     0/1       1
```

**Frame 2 (Flags):**
```
[START] [ZERO] [CARRY] [x x x x x x] [PARITY] [STOP]
   1      1       1      6 bits relleno  0/1       1
```

**Componentes de cada frame:**

- **START bit (1 bit)**: Señaliza el inicio de la transmisión mediante una transición de 1 (idle) a 0. Permite al receptor detectar el comienzo del frame y sincronizarse.

- **DATA bits (8 bits)**: En el primer frame, contienen el resultado de la ALU. En el segundo frame, ZERO y CARRY ocupan los 2 LSBs, con 6 bits de relleno (típicamente 0) para completar el byte.

- **PARITY bit (0 o 1 bit)**: Bit opcional de verificación de integridad, calculado **independientemente** sobre los 8 bits de datos de cada frame.

- **STOP bit (1 bit)**: Señaliza el fin de la transmisión mediante el valor 1, retornando la línea al estado idle.

**Longitud total por operación ALU:**
- Sin paridad: 2 × (1 + 8 + 1) = 2 × 10 = **20 bits**
- Con paridad: 2 × (1 + 8 + 1 + 1) = 2 × 11 = **22 bits**

**Ventajas de la arquitectura de dos frames:**
- Simplifica el diseño de la FSM (reutiliza la misma lógica para ambos frames)
- Facilita la integración con FIFO estándar (cada entrada es un byte completo)
- Mantiene compatibilidad con herramientas UART estándar para el frame de datos

#### **Dependencia del Baudrate Generator**

El transmisor UART opera en estrecha sincronización con el baudrate generator mediante la señal `baud_tick`. Esta relación determina fundamentalmente el comportamiento temporal del sistema:

**1. Temporización de Bit mediante Oversampling**

Duración de bit = OVERSAMPLE × Período del baud_tick → Para 16x oversampling: cada bit dura 16 ticks del generador

**2. Avance de la Máquina de Estados Finitos (FSM)**

La FSM del transmisor únicamente actualiza su estado (salvo IDLE) cuando:
- Se completa un período de bit (contador alcanza OVERSAMPLE-1)
- La señal `baud_tick` está activa

Este mecanismo garantiza:
- **Precisión temporal perfecta**: Los bits se transmiten exactamente a la velocidad configurada
- **Sincronización robusta**: El receptor puede muestrear en el centro de cada bit
- **Independencia del reloj del sistema**: La frecuencia del sistema puede variar sin afectar el baudrate

> Esta arquitectura separa claramente las responsabilidades: el baudrate generator proporciona la base temporal precisa, mientras que el TX implementa la lógica de serialización y protocolo.

### 2.3 Justificación del Latch Interno para tx_start

#### **Problema: Uso Directo de tx_start desde Lógica Externa**

En sistemas digitales síncronos, el uso directo de señales de control desde módulos externos presenta múltiples desafíos que pueden comprometer la funcionalidad del transmisor UART:

**1. Pulsos Transitorios Muy Cortos**

Si tx_start dura solo 1 ciclo de reloj:
- Puede ocurrir entre dos baud_ticks consecutivos
- La FSM del TX nunca "ve" el pulso
- Transmisión no se inicia, dato se pierde

**2. Desincronización con baud_tick**
- La FSM del TX solo avanza cuando `baud_tick = 1` (para lograr desacople del clk del sistema y porque mejora la alineación temporal con los bits)
- Si tx_start llega cuando `baud_tick = 0`, se ignora

#### **Solución: Latch Interno Sincronizado**

El diseño implementa un registro interno `tx_start_pending` que captura y mantiene la solicitud de transmisión hasta que el sistema esté listo:

**Ventajas del Mecanismo de Latch:**

**1. Captura Garantizada de Pulsos Cortos**
```
clk         _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
tx_start    ___|‾|_____________________
pending     _____|‾‾‾‾‾‾‾‾‾‾‾‾|_______  ← Extendido hasta baud_tick
baud_tick   _______________|‾|_________
```
El pulso de 1 ciclo se extiende automáticamente hasta el próximo baud_tick.

**2. Sincronización Automática**
- El latch actúa como buffer entre dominio de control y dominio de baudrate
- Elimina requisitos de timing estrictos para lógica externa
- Simplifica integración con ALU y otros módulos

**3. Inmunidad a Glitches**
- Solo se captura tx_start cuando `state == S_IDLE`
- Durante transmisión activa, pulsos por ruido o interferencia son ignorados
- Comportamiento determinista y predecible

### 2.4 Interfaz con la FIFO — write_o y read_en

#### **Arquitectura de Integración con FIFO**

En sistemas que requieren buffering de múltiples transmisiones (como cuando la ALU genera resultados más rápido que la capacidad del UART), se introduce una FIFO entre el productor de datos (ALU) y el transmisor UART. Esta arquitectura desacopla temporalmente ambos módulos y maximiza el throughput del sistema.

<p align="center">
  <a>
    <img src="imgs/ALU-FIFO-TX.jpg" alt="Flujo ALU-FIFO-TX">
  </a>

#### **Señales de la Interfaz FIFO**

**write_o (input del TX, output de FIFO)**
- **Tipo**: Señal de nivel (level signal)
- **Función**: Indica que la FIFO tiene al menos un elemento disponible para transmitir
- **Comportamiento**:
  - `write_o = 1`: Dato válido presente en las salidas de la FIFO
  - `write_o = 0`: FIFO vacía, no hay datos disponibles

**read_en (output del TX, input de FIFO)**
- **Tipo**: Pulso de 1 ciclo de reloj
- **Función**: Señal de consumo que indica que el TX ha tomado el dato actual
- **Comportamiento**:
  - Genera pulso de 1 ciclo cuando TX captura dato de FIFO
  - Causa que FIFO avance al siguiente elemento (pop)
  - Solo se activa en transición `S_IDLE → S_START`
  - **Para cada operación ALU, se generan dos pulsos**: uno para el frame de datos y otro para el frame de flags

#### **Secuencia de Handshake FIFO-TX**

```
write_o  read_en   state     Acción
───────────────────────────────────────────────────────────────
0        0         S_IDLE    TX esperando
1        0         S_IDLE    FIFO ofrece dato (byte de datos)
1        1         S_START   TX acepta frame 1, genera read_en
1        0         S_DATA    Transmitiendo frame 1...
...
1        0         S_DONE    Frame 1 completo
1        0         S_IDLE    TX regresa a IDLE brevemente
1        1         S_START   TX acepta frame 2 (flags), genera read_en
1        0         S_DATA    Transmitiendo frame 2...
...
1        0         S_DONE    Frame 2 completo (operación ALU finalizada)
1        0         S_IDLE    Listo para próximo par de frames
```

**Nota importante:** Por cada operación de la ALU, la FIFO debe contener **dos bytes**:
1. Byte de datos (resultado de la ALU)
2. Byte de flags (ZERO en bit 0, CARRY en bit 1, resto en 0)

**Características clave:**
- **No bloqueante**: TX continúa transmitiendo mientras FIFO tenga datos
- **Backpressure implícito**: Si FIFO está vacía (write_o=0), TX espera en IDLE
- **Zero bubble**: Transiciones consecutivas sin ciclos muertos si FIFO siempre tiene datos

### 2.5 Comparación: Latch vs. Modo FIFO

| **Aspecto / Característica** | **Modo Pulso / Latch (tx_start)**                          | **Modo FIFO (write_o / read_en)**                       |
| ---------------------------- | ---------------------------------------------------------- | ------------------------------------------------------- |
| **Iniciación**               | Pulso de 1 ciclo, capturado por latch interno              | write_o en nivel; TX toma dato cuando está listo        |
| **Latencia inicial**         | Hasta baud_tick, depende del oversampling     | Inmediata: TX toma el siguiente dato disponible         |
| **Robustez a glitches**      | Alta (el latch filtra pulsos breves)                       | Muy alta (handshake explícito write_o/read_en)          |
| **Consumo del dato**         | Automático al detectar el pulso                            | Confirmado con read_en por parte del TX                 |
| **Throughput sostenido**     | Limitado: 2 frames por solicitud externa (datos + flags)   | Máximo: permite streaming continuo sin gaps             |
| **Escalabilidad**            | Baja (requiere un pulso por cada operación → 2 frames)     | Alta (FIFO absorbe bursts; 2 bytes por operación ALU)   |
| **Complejidad del sistema**  | Baja (1 FF + lógica mínima)                                | Media (FIFO + protocolo handshake)                      |
| **Uso de recursos FPGA**     | Mínimo                                          | Moderado                     |
| **Pérdida de datos**         | Posible si TX está ocupado y el pulso llega en mal momento | No hay pérdidas: FIFO bufferiza y TX confirma recepción |
| **Integración con ALU**      | Directa (ej: tx_start = alu_done)                          | Indirecta: la ALU escribe a FIFO, que alimenta al TX    |
| **Aplicaciones típicas**     | Transmisión ocasional o eventos aislados                   | Streaming continuo, alta tasa, pipelines                |

#### **Ventajas de la Integración con Latch**

Permite que módulos externos (como la ALU) generen pulsos de control simples sin preocuparse por:
- Timing exacto respecto a baud_tick
- Duración del pulso
- Sincronización entre dominios de reloj

Este patrón simple y robusto es posible gracias al latch interno, que absorbe la complejidad de sincronización y garantiza que ninguna solicitud de transmisión se pierda.

#### **Ventajas de la Integración con FIFO**

**1. Desacoplamiento Temporal:** el Throughput de la ALU suele ser mucho mayor que el de la UART, lo que provoca un desbalance, haciendo necesaria una FIFO para absorber ráfagas de ALU sin pérdida de datos (sumado al hecho de que cada operación de la ALU implica 2 frames enviados por la UART)

**2. Maximización de Utilización del Canal**
- TX transmite back-to-back mientras FIFO tenga datos
- Overhead entre frames reducido a 0 ciclos

**3. Simplificación de Lógica Externa**
- ALU no necesita conocer estado del UART, solo debe escribir a FIFO cuando tiene resultado
- No requiere sincronización explícita

**4. Tolerancia a Variaciones de Tasa**
- Si ALU se detiene temporalmente, TX continúa vaciando FIFO
- Si ALU acelera, FIFO bufferiza hasta alcanzar capacidad
- Sistema robusto ante condiciones variables

#### **Implementación en el Diseño Actual**

El módulo `uart_tx.sv` soporta **ambos modos simultáneamente**.
- Configuración en tiempo de síntesis (parámetro)
- Permite testing de ambos modos con mismo RTL
- Facilita migración de sistemas simples a sistemas con buffering

### 2.5 Flujo Detallado de la Máquina de Estados Finitos (FSM)

#### **Diagrama de Máquina de Estados Algorítmica**

La FSM del transmisor UART implementa el protocolo de serialización mediante los siguientes estados:

<p align="center">
  <a>
    <img src="imgs/tx_asmdp.jpg" alt="Tx_FSM">
  </a>

#### **Tablas de Temporización**

**Duración Teórica de un Frame Individual por Modo de Paridad**

| Modo Paridad | Bits por Frame | Ticks de Baud | Ciclos @ 12 MHz | Tiempo @ 9600 bps |
|--------------|----------------|---------------|-----------------|-------------------|
| NONE | 10 | 10 × 16 = 160 | 10×1250 = 12500 | 1.042 ms |
| EVEN | 11 | 11 × 16 = 176 | 11×1250 = 13750 | 1.146 ms |
| ODD | 11 | 11 × 16 = 176 | 11×1250 = 13750 | 1.146 ms |

**Desglose de Tiempo por Estado (un frame, modo NONE)**

| Estado | Bits | Ticks Baud | % Frame | Tiempo @ 9600 bps |
|--------|------|------------|---------|-------------------|
| IDLE | - | Variable | - | Variable |
| START | 1 | 16 | 10% | 104.17 μs |
| DATA | 8 | 128 | 80% | 833.33 μs |
| STOP | 1 | 16 | 10% | 104.17 μs |
| DONE | - | 1 | <1% | 6.51 μs |
| **TOTAL** | **10** | **161** | **100%** | **1.048 ms** |

**Duración Total por Operación ALU (2 Frames):** Para completar una operación ALU, la FSM ejecuta esta secuencia **dos veces consecutivas** (frame de datos + frame de flags).

| Modo Paridad | Bits Totales | Tiempo Total @ 9600 bps |
|--------------|--------------|-------------------------|
| NONE | 2 × 10 = 20 | 2 × 1.048 ms = **2.096 ms** |
| EVEN | 2 × 11 = 22 | 2 × 1.152 ms = **2.304 ms** |
| ODD | 2 × 11 = 22 | 2 × 1.152 ms = **2.304 ms** |

### 2.6 Alcance de la Testbench del Módulo TX

La testbench del módulo `uart_tx` implementa una estrategia de verificación exhaustiva basada en vectores de prueba pregenerados mediante un script Python (`gen_uart_tx_vectors.py`). Este enfoque proporciona múltiples ventajas sobre generación de estímulos en tiempo de simulación:

**1. Modelo Dorado en Python**
- Construcción de frames esperados mediante algoritmo simple y verificable
- Cálculo de paridad en Python independiente de RTL (detecta errores de especificación)
- Generación de casos corner predefinidos (smoke tests)
- Casos random para cobertura estadística
- **Generación de vectores solo para frame de datos** (8 bits); el testbench construye internamente el frame de flags

**2. Separación de Generación y Verificación**
- Testbench consume vectores de datos y construye ambos frames esperados (datos + flags)
- Verifica secuencialmente los dos frames por cada operación
- Permite auditoría manual de vectores esperados

#### **Smoke Tests: Casos Críticos Predefinidos**

La testbench ejecuta **6 smoke tests** por cada modo de paridad, cubriendo casos esenciales. Cada test verifica **dos frames consecutivos**: uno para los datos y otro para los flags.

| Nombre | Dato (Frame 1) | Justificación |
|--------|----------------|---------------|
| BASIC_1F | 0x1F | Caso normal, patrón variado |
| ALL_ZERO | 0x00 | Todos los bits de data en 0 |
| MSB_SET | 0x80 | MSB activo, verifica LSB-first |
| ALL_ONES | 0xFF | Todos los bits de data en 1 |
| ALT_55 | 0x55 | Patrón alternado 01010101 |
| ALT_AA | 0xAA | Patrón alternado 10101010 |

**Total:** 6 casos × 3 modos de paridad = **18 smoke tests**

#### **Tests Random: Cobertura Estadística**

**9 vectores random** por modo de paridad, generados con distribución uniforme.

**Objetivo:**
- Explorar espacio de estados no cubierto por smoke tests
- Detectar errores en combinaciones no anticipadas
- Simular casos reales con datos arbitrarios

**Total:** 9 casos × 3 modos de paridad = **27 random tests**

#### **Verificaciones Realizadas por la Testbench**

**1. Serialización Bit a Bit (Ambos Frames)**

La testbench captura la línea TX mediante muestreo mid-bit:

- Compara `captured_frame` con `expected_frame` generado por Python
- Detecta errores de:
  - Orden de bits (LSB vs MSB first)
  - START/STOP incorrectos
  - Inclusión/omisión de paridad en cada frame (si aplica)
  - Valores transmitidos

**2. Timing Exacto:** verifica cuantos ciclos del clock fueron necesarios para transmistir cada frame, y si cae dentro de un rango de valores aceptable

**Detecta:**
- Errores en contador de oversampling
- Saltos de estados entre frames
- Retrasos no anticipados

**3. Cobertura de Modos de Paridad**

La testbench ejecuta **3 configuraciones completas** mediante parámetro `TEST_MODE`

**Garantiza:**
- Frames con/sin bit de paridad (10 vs 11 bits por frame)
- Cálculo correcto de paridad even/odd **independiente para cada frame**

**4. Modo FIFO Adicional**

Con `ENABLE_FIFO_MODE=1`, testbench ejecuta **6 tests adicionales** por modo de paridad:

### 2.7 Diagrama RTL del Módulo UART TX

<p align="center">
  <a>
    <img src="imgs/tx_rtl.jpg" alt="Transmitter">
  </a>

---
