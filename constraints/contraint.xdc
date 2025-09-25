# FPGA ALU Project Constraints File for Cmod A7-35T Board
# Pin assignments and timing constraints for the alu_top design.

# ===================================================================================
# Clock Constraint
# ===================================================================================
# 12 MHz system oscillator on pin L17
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports {clk}]
create_clock -period 83.333 -name sys_clk [get_ports {clk}]

# ===================================================================================
# Reset Constraint
# ===================================================================================
# rst mapped to side header PIO36 for external controller access
# (pull-up enables idle-high behaviour; Cmod BTN0 is no longer used).

# ===================================================================================
# Data Input Bus (JA PMOD header)
# ===================================================================================
# Data inputs relocated to PIO header for 1:1 Pico wiring
set_property -dict { PACKAGE_PIN M3  IOSTANDARD LVCMOS33 } [get_ports {data_in[0]}]  ;# PIO1
set_property -dict { PACKAGE_PIN L3  IOSTANDARD LVCMOS33 } [get_ports {data_in[1]}]  ;# PIO2
set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 } [get_ports {data_in[2]}]  ;# PIO3
set_property -dict { PACKAGE_PIN K3  IOSTANDARD LVCMOS33 } [get_ports {data_in[3]}]  ;# PIO4
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports {data_in[4]}]  ;# PIO5
set_property -dict { PACKAGE_PIN H1  IOSTANDARD LVCMOS33 } [get_ports {data_in[5]}]  ;# PIO6
set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports {data_in[6]}]  ;# PIO7
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {data_in[7]}]  ;# PIO8

# ===================================================================================
# Control Inputs
# ===================================================================================
# Control strobes on nearby PIO pins (skip analog pins 15/16)
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports {load_a}]         ;# PIO9
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {load_b}]   ;# PIO10
set_property -dict { PACKAGE_PIN J1  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {load_sel}] ;# PIO11
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {rst}]      ;# PIO12

# ===================================================================================
# Outputs
# ===================================================================================
set_property -dict { PACKAGE_PIN L1 IOSTANDARD LVCMOS33 } [get_ports {Cout}]       ;# PIO13
set_property -dict { PACKAGE_PIN L2 IOSTANDARD LVCMOS33 } [get_ports {Zero}]       ;# PIO14
set_property -dict { PACKAGE_PIN W4 IOSTANDARD LVCMOS33 } [get_ports {Overflow}]   ;# PIO40

set_property -dict { PACKAGE_PIN U5 IOSTANDARD LVCMOS33 } [get_ports {Result[0]}]  ;# PIO41
set_property -dict { PACKAGE_PIN U2 IOSTANDARD LVCMOS33 } [get_ports {Result[1]}]  ;# PIO42
set_property -dict { PACKAGE_PIN W6 IOSTANDARD LVCMOS33 } [get_ports {Result[2]}]  ;# PIO43
set_property -dict { PACKAGE_PIN U3 IOSTANDARD LVCMOS33 } [get_ports {Result[3]}]  ;# PIO44
set_property -dict { PACKAGE_PIN U7 IOSTANDARD LVCMOS33 } [get_ports {Result[4]}]  ;# PIO45
set_property -dict { PACKAGE_PIN W7 IOSTANDARD LVCMOS33 } [get_ports {Result[5]}]  ;# PIO46
set_property -dict { PACKAGE_PIN U8 IOSTANDARD LVCMOS33 } [get_ports {Result[6]}]  ;# PIO47
set_property -dict { PACKAGE_PIN V8 IOSTANDARD LVCMOS33 } [get_ports {Result[7]}]  ;# PIO48

# LED mirrors (retain PIO taps)
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports {result_led0}]      ;# LED0
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {result_led1}]      ;# LED1
set_property -dict { PACKAGE_PIN B17 IOSTANDARD LVCMOS33 } [get_ports {result_led_b_n}]   ;# RGB Blue (active-low)
set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {result_led_g_n}]   ;# RGB Green (active-low)
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports {result_led_r_n}]   ;# RGB Red (active-low)

# ===================================================================================
# Timing Constraints
# ===================================================================================
set_input_delay  -clock [get_clocks sys_clk] -max 20.0 [get_ports {data_in[*]}]
set_input_delay  -clock [get_clocks sys_clk] -min  2.0 [get_ports {data_in[*]}]
set_input_delay  -clock [get_clocks sys_clk] -max 10.0 [get_ports {load_a}]
set_input_delay  -clock [get_clocks sys_clk] -min  1.0 [get_ports {load_a}]
set_input_delay  -clock [get_clocks sys_clk] -max 10.0 [get_ports {load_b}]
set_input_delay  -clock [get_clocks sys_clk] -min  1.0 [get_ports {load_b}]
set_input_delay  -clock [get_clocks sys_clk] -max 10.0 [get_ports {load_sel}]
set_input_delay  -clock [get_clocks sys_clk] -min  1.0 [get_ports {load_sel}]

set_output_delay -clock [get_clocks sys_clk] -max 15.0 [get_ports {Result[*]}]
set_output_delay -clock [get_clocks sys_clk] -min  1.0 [get_ports {Result[*]}]
set_output_delay -clock [get_clocks sys_clk] -max 10.0 [get_ports {Cout}]
set_output_delay -clock [get_clocks sys_clk] -min  0.5 [get_ports {Cout}]
set_output_delay -clock [get_clocks sys_clk] -max 10.0 [get_ports {Zero}]
set_output_delay -clock [get_clocks sys_clk] -min  0.5 [get_ports {Zero}]
set_output_delay -clock [get_clocks sys_clk] -max 10.0 [get_ports {Overflow}]
set_output_delay -clock [get_clocks sys_clk] -min  0.5 [get_ports {Overflow}]

# ===================================================================================
# Additional Constraints
# ===================================================================================
set_property MAX_FANOUT 20 [get_nets]
set_false_path -from [get_ports {rst}]

# ===================================================================================
# Notes
# ===================================================================================
# - Result bus now routed to PIO41–PIO48 with status bits on PIO13/PIO14/PIO40; add
#   external buffering if you re-enable on-board peripherals that share these nets.
# - Ensure this XDC is added to your Vivado project or sourced in the run scripts.
