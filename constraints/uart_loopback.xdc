# ===================================================================================
# Archivo de Restricciones para UART Loopback en la placa Cmod A7-35T
#
# Este archivo contiene las restricciones físicas para el módulo `uart_loopback_top`.
# Conecta el puerto USB-UART integrado de la placa con LEDs indicadores.
# ===================================================================================


# ===================================================================================
# SECCIÓN 1: RESTRICCIÓN DE RELOJ PRINCIPAL
# ===================================================================================
# Define el reloj del sistema que entra a la FPGA.
#
# PIN L17: Conectado al oscilador de 12 MHz integrado en la placa Cmod A7.
# IOSTANDARD LVCMOS33: Fija el estándar de voltaje a 3.3V para este pin.
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {clk}]

# Crea un reloj lógico llamado 'sys_clk' asociado al puerto 'clk'.
# -period 83.333: Especifica un período de 83.333 ns, lo que equivale a una frecuencia de 12 MHz.
create_clock -period 83.333 -name sys_clk [get_ports {clk}]


# ===================================================================================
# SECCIÓN 2: SEÑAL DE RESET
# ===================================================================================
# Asigna el pin PIO12 como señal de reset (la Cmod A7-35T no tiene botones)
# PULLUP TRUE: Asegura estado alto por defecto cuando no está conectado
set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {rst}]

# Declara reset como ruta falsa (señal asíncrona)
set_false_path -from [get_ports {rst}]


# ===================================================================================
# SECCIÓN 3: INTERFAZ UART (USB-UART INTEGRADO)
# ===================================================================================
# La placa Cmod A7-35T tiene un conversor USB-UART FTDI integrado
# que se conecta directamente a la FPGA.
#
# RX (J18): Recibe datos desde la PC
# TX (J17): Transmite datos hacia la PC
#
# IMPORTANTE: Estos pines están conectados internamente al puerto micro-USB
# de la placa, por lo que NO requieren hardware adicional.

set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {rx}]  ;# USB_UART_RXD
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {tx}]  ;# USB_UART_TXD


# ===================================================================================
# SECCIÓN 4: INDICADORES LED
# ===================================================================================
# LED0 y LED1 son los LEDs verdes incorporados en la placa
# LED0: Indica actividad de recepción (rx_done)
# LED1: Indica actividad de transmisión (tx_done)

set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {led0}]  ;# LED0
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {led1}]  ;# LED1


# ===================================================================================
# SECCIÓN 5: RESTRICCIONES DE TEMPORIZACIÓN DE E/S
# ===================================================================================
# Restricciones de temporización para la interfaz UART

# --- Retardos de Entrada (RX) ---
# El dato viene del conversor USB-UART FTDI integrado
set_input_delay  -clock [get_clocks sys_clk] -max 20.0 [get_ports {rx}]
set_input_delay  -clock [get_clocks sys_clk] -min  2.0 [get_ports {rx}]

# --- Retardos de Salida (TX) ---
# El dato va hacia el conversor USB-UART FTDI integrado
set_output_delay -clock [get_clocks sys_clk] -max 15.0 [get_ports {tx}]
set_output_delay -clock [get_clocks sys_clk] -min  1.0 [get_ports {tx}]

# --- Salidas de LEDs (sin restricciones críticas) ---
# Los LEDs no requieren restricciones de timing estrictas
set_false_path -to [get_ports {led0}]
set_false_path -to [get_ports {led1}]


# ===================================================================================
# SECCIÓN 6: RESTRICCIONES ADICIONALES
# ===================================================================================
# Limita el fan-out para mejor rendimiento
set_property MAX_FANOUT 20 [get_nets]
