# Changelog

## [2.0.0] - 2026-09-30

### Added
- Módulos UART en `src/rtl/`:
  - `uart_baudrate_gen.sv`: divisor de frecuencia para reloj de 12 MHz con pulso de oversampling a 16x.
  - `uart_tx.sv`: transmisor serie con FSM y paridad configurable.
  - `uart_rx.sv`: receptor serie con muestreo central a 16x y filtrado de ruido.
  - `uart_parity.v`: generador y verificador de paridad (par, impar o ninguna).
  - `sync_fifo.sv`: FIFO sincrónica para desacoplar transceptores del decodificador.
  - `uart_top.sv`: integración de transceptor, generador de baudrate y FIFOs.
  - `uart_packet_decoder.sv`: decodificación de tramas STX/CMD/DATA/ETX y serialización de respuestas.
  - `alu_top_fsm.v`: FSM de control para coordinar decodificador y ALU, con propagación de carry.
  - `uart_loopback_top.sv` y `uart_rx_led_toggle.sv`: diseños para pruebas en hardware.
- Archivo de restricciones `constraints/uart_loopback.xdc` para Cmod A7-35T (reloj 12 MHz, UART USB, reset y LEDs).
- Testbenches SystemVerilog (`tb_uart_*.sv`, `tb_sync_fifo.sv`, `tb_alu_top_fsm.sv`, `uart_top_tb.sv`) y generadores de vectores en Python (`gen_uart_rx_vectors.py`, `gen_uart_tx_vectors.py`).
- Scripts de prueba en PC: `scripts/alu_uart_serial_test.py` (CLI automatizado) y `scripts/alu_uart_tui_curses.py` (interfaz TUI con curses).
- Documentación técnica: `INFORME_UART.md`, diagramas de arquitectura en `doc/` y esquemas en `imgs/`.

### Changed
- `src/rtl/alu_top.v`: control de carry mediante `exec_pulse` para operaciones encadenadas.

## [1.0.0] - 2025-11-04

### Added
- Núcleo de ALU de 8 bits en `src/rtl/`: operaciones aritméticas (`arithmetic_unit.v`), lógicas (`logical_unit.v`), desplazamientos (`shifter_unit.v`), banco de registros (`alu_register_bank.v`) y módulo top (`alu_top.v`).
- Firmware C++ para Raspberry Pi Pico (`pico_uart_to_fpga/`) y script de autotest (`uart_selftest.py`).
- Testbench SystemVerilog `src/sim/sv/tb_alu.sv` y generador de vectores `gen_test_vectors.py`.
- Informe técnico de TP1 en `INFORME.md`.
