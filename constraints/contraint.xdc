# ===================================================================================
# Archivo de Restricciones para el Proyecto ALU en la placa Cmod A7-35T
#
# Este archivo contiene las restricciones físicas (asignación de pines, estándar de E/S)
# y de temporización (reloj, retardos) para el módulo `alu_top`.
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
# SECCIÓN 2: BUS DE ENTRADA DE DATOS (data_in[7:0])
# ===================================================================================
# Mapea los 8 bits del bus de datos a los pines de E/S (PIO) para la conexión
# directa con la Raspberry Pi Pico.
set_property -dict { PACKAGE_PIN M3  IOSTANDARD LVCMOS33 } [get_ports {data_in[0]}]  ;# PIO1
set_property -dict { PACKAGE_PIN L3  IOSTANDARD LVCMOS33 } [get_ports {data_in[1]}]  ;# PIO2
set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 } [get_ports {data_in[2]}]  ;# PIO3
set_property -dict { PACKAGE_PIN K3  IOSTANDARD LVCMOS33 } [get_ports {data_in[3]}]  ;# PIO4
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports {data_in[4]}]  ;# PIO5
set_property -dict { PACKAGE_PIN H1  IOSTANDARD LVCMOS33 } [get_ports {data_in[5]}]  ;# PIO6
set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports {data_in[6]}]  ;# PIO7
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {data_in[7]}]  ;# PIO8


# ===================================================================================
# SECCIÓN 3: SEÑALES DE CONTROL Y RESET
# ===================================================================================
# Asigna las señales de control (load_a, load_b, load_sel) y el reset a pines PIO.
# PULLUP TRUE: Habilita una resistencia interna a VCC. Esto asegura que la señal
# se mantenga en estado alto (1) si no es activamente puesta en bajo (0) por el
# controlador, evitando estados de flotación.
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports {load_a}]         ;# PIO9
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {load_b}]   ;# PIO10
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {load_sel}] ;# PIO11
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {rst}]      ;# PIO12


# ===================================================================================
# SECCIÓN 4: SALIDAS DE DATOS Y FLAGS
# ===================================================================================
# Mapea las salidas de flags (Cout, Zero) y el bus de resultado a pines
# PIO para que la Raspberry Pi Pico pueda leerlos.
set_property -dict { PACKAGE_PIN L1 IOSTANDARD LVCMOS33 } [get_ports {Cout}]       ;# PIO13
set_property -dict { PACKAGE_PIN L2 IOSTANDARD LVCMOS33 } [get_ports {Zero}]       ;# PIO14

set_property -dict { PACKAGE_PIN U5 IOSTANDARD LVCMOS33 } [get_ports {Result[0]}]  ;# PIO41
set_property -dict { PACKAGE_PIN U2 IOSTANDARD LVCMOS33 } [get_ports {Result[1]}]  ;# PIO42
set_property -dict { PACKAGE_PIN W6 IOSTANDARD LVCMOS33 } [get_ports {Result[2]}]  ;# PIO43
set_property -dict { PACKAGE_PIN U3 IOSTANDARD LVCMOS33 } [get_ports {Result[3]}]  ;# PIO44
set_property -dict { PACKAGE_PIN U7 IOSTANDARD LVCMOS33 } [get_ports {Result[4]}]  ;# PIO45
set_property -dict { PACKAGE_PIN W7 IOSTANDARD LVCMOS33 } [get_ports {Result[5]}]  ;# PIO46
set_property -dict { PACKAGE_PIN U8 IOSTANDARD LVCMOS33 } [get_ports {Result[6]}]  ;# PIO47
set_property -dict { PACKAGE_PIN V8 IOSTANDARD LVCMOS33 } [get_ports {Result[7]}]  ;# PIO48


# ===================================================================================
# SECCIÓN 5: SALIDAS A LEDS (VISUALIZACIÓN)
# ===================================================================================
# Conecta bits específicos del resultado a los LEDs de la placa para una
# debug visual rápido.
# Nota: El LED RGB (pines B17, B16, C17) es activo en bajo.
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {result_led0}]      ;# LED0
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {result_led1}]      ;# LED1
set_property -dict { PACKAGE_PIN B17 IOSTANDARD LVCMOS33 } [get_ports {result_led_b_n}]   ;# RGB Azul (activo-bajo)
set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {result_led_g_n}]   ;# RGB Verde (activo-bajo)
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports {result_led_r_n}]   ;# RGB Rojo (activo-bajo)


# ===================================================================================
# SECCIÓN 6: RESTRICCIONES DE TEMPORIZACIÓN DE E/S
# ===================================================================================
# --- Retardos de Entrada ---
# Le dice a Vivado el tiempo que ya ha consumido una señal antes de llegar a la FPGA.
# -max: El peor caso (el más lento). Usado para la verificación de 'setup time'.
# -min: El mejor caso (el más rápido). Usado para la verificación de 'hold time'.
set_input_delay  -clock [get_clocks sys_clk] -max 20.0 [get_ports {data_in[*]}]
set_input_delay  -clock [get_clocks sys_clk] -min  2.0 [get_ports {data_in[*]}]
set_input_delay  -clock [get_clocks sys_clk] -max 10.0 [get_ports {load_a}]
set_input_delay  -clock [get_clocks sys_clk] -min  1.0 [get_ports {load_a}]
set_input_delay  -clock [get_clocks sys_clk] -max 10.0 [get_ports {load_b}]
set_input_delay  -clock [get_clocks sys_clk] -min  1.0 [get_ports {load_b}]
set_input_delay  -clock [get_clocks sys_clk] -max 10.0 [get_ports {load_sel}]
set_input_delay  -clock [get_clocks sys_clk] -min  1.0 [get_ports {load_sel}]

# --- Retardos de Salida ---
# Le dice a Vivado el tiempo que necesita una señal después de salir de la FPGA
# para ser capturada correctamente por el dispositivo externo (la Pico).
set_output_delay -clock [get_clocks sys_clk] -max 15.0 [get_ports {Result[*]}]
set_output_delay -clock [get_clocks sys_clk] -min  1.0 [get_ports {Result[*]}]
set_output_delay -clock [get_clocks sys_clk] -max 10.0 [get_ports {Cout}]
set_output_delay -clock [get_clocks sys_clk] -min  0.5 [get_ports {Cout}]
set_output_delay -clock [get_clocks sys_clk] -max 10.0 [get_ports {Zero}]
set_output_delay -clock [get_clocks sys_clk] -min  0.5 [get_ports {Zero}]


# ===================================================================================
# SECCIÓN 7: RESTRICCIONES ADICIONALES DE SÍNTESIS Y TEMPORIZACIÓN
# ===================================================================================
# Limita el fan-out (número de cargas que una señal maneja) a 20. Utilizado por
# al ser avisado por un warning de Vivado.
set_property MAX_FANOUT 20 [get_nets]

# Declara la señal de reset como una "ruta falsa". Esto le dice al analizador de
# temporización que ignore esta señal, ya que es asíncrona y no tiene una relación
# temporal con el reloj. 
set_false_path -from [get_ports {rst}]