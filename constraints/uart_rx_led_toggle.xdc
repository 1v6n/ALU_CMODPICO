# ===================================================================================
# Archivo de Restricciones para UART RX LED Toggle en la placa Cmod A7-35T
#
# Este archivo contiene las restricciones físicas para el módulo `uart_rx_led_toggle`.
# Recibe datos por UART y hace toggle de LED cuando llega un byte con LSB=1.
# ===================================================================================


# ===================================================================================
# SECCIÓN 1: RESTRICCIÓN DE RELOJ PRINCIPAL
# ===================================================================================
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {clk}]
create_clock -period 83.333 -name sys_clk [get_ports {clk}]


# ===================================================================================
# SECCIÓN 2: SEÑAL DE RESET
# ===================================================================================
# Pin PIO12 como reset (con pull-up interno)
set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {rst}]
set_false_path -from [get_ports {rst}]


# ===================================================================================
# SECCIÓN 3: INTERFAZ UART (USB-UART INTEGRADO)
# ===================================================================================
# RX (J18): Recibe datos desde la PC a través del conversor USB-UART integrado
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {rx}]


# ===================================================================================
# SECCIÓN 4: INDICADOR LED
# ===================================================================================
# LED0: Hace toggle cuando se recibe un byte con LSB=1
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {led}]


# ===================================================================================
# SECCIÓN 5: RESTRICCIONES DE TEMPORIZACIÓN DE E/S
# ===================================================================================
# --- Retardos de Entrada (RX) ---
set_input_delay  -clock [get_clocks sys_clk] -max 20.0 [get_ports {rx}]
set_input_delay  -clock [get_clocks sys_clk] -min  2.0 [get_ports {rx}]

# --- Salida de LED (sin restricciones críticas) ---
set_false_path -to [get_ports {led}]


# ===================================================================================
# SECCIÓN 6: RESTRICCIONES ADICIONALES
# ===================================================================================
set_property MAX_FANOUT 20 [get_nets]
