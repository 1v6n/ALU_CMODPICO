# Guía de Cableado Pico 2 ↔ Cmod A7

Este documento describe las conexiones utilizadas por `pico_uart_to_fpga/src/main.cpp` para controlar el diseño de la ALU en la placa Cmod A7-35T.

## Alimentación y Referencia

- Conectar el `GND` de la Pico al `GND` de la Cmod A7.
- Alimentar ambas placas desde sus puertos USB o una fuente compartida de 5 V.

## Señales Digitales

| Pin GP del Pico | Función del Pico | Señal de Cmod | Pin del FPGA |
| --- | --- | --- | --- |
| GP2 | Control de `data_in[0]` | `data_in[0]` | PIO1 |
| GP3 | Control de `data_in[1]` | `data_in[1]` | PIO2 |
| GP4 | Control de `data_in[2]` | `data_in[2]` | PIO3 |
| GP5 | Control de `data_in[3]` | `data_in[3]` | PIO4 |
| GP6 | Control de `data_in[4]` | `data_in[4]` | PIO5 |
| GP7 | Control de `data_in[5]` | `data_in[5]` | PIO6 |
| GP8 | Control de `data_in[6]` | `data_in[6]` | PIO7 |
| GP9 | Control de `data_in[7]` | `data_in[7]` | PIO8 |
| GP10 | Pulso de `load_a` | `load_a` | PIO9 |
| GP11 | Pulso de `load_b` | `load_b` | PIO10 |
| GP12 | Pulso de `load_sel` | `load_sel` | PIO11 |
| GP13 | Pulso de `rst` | `rst` | PIO12 |
| GP14 | Detección de estado | `Cout` | PIO13 |
| GP15 | Detección de estado | `Zero` | PIO14 |
| GP16 | Detección de estado | `Overflow` | PIO40 |
| GP17 | Detección de resultado | `Result[0]` | PIO41 |
| GP18 | Detección de resultado | `Result[1]` | PIO42 |
| GP19 | Detección de resultado | `Result[2]` | PIO43 |
| GP20 | Detección de resultado | `Result[3]` | PIO44 |
| GP21 | Detección de resultado | `Result[4]` | PIO45 |
| GP22 | Detección de resultado | `Result[5]` | PIO46 |
| GP26 | Detección de resultado | `Result[6]` | PIO47 |
| GP27 | Detección de resultado | `Result[7]` | PIO48 |

Todas las señales utilizan el estándar de E/S LVCMOS33 (lógica CMOS de 3.3 V), compatible con los GPIOs del Pico.
