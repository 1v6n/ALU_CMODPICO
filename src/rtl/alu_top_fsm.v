`include "alu_timescale.vh"

/*
 * @file alu_top_fsm.v
 * @brief Top-level FSM para la ruta UART: integra UART RX FIFO, decoder y ALU.
 *
 * Este módulo recibe bytes desde la UART RX (ready/valid) y, mediante el uart_packet_decoder,
 * genera los pulsos de carga `load_a/load_b/load_sel` y el pulso de ejecución que alimentan al
 * módulo `alu_top`.
 */
module alu_top_fsm #(
    //! @brief Parámetros de configuración
    parameter integer DATA_WIDTH   = 8,
    parameter integer OPCODE_WIDTH = 6
) (
    //! @brief Señales de reloj y reset
    input  wire clk,
    input  wire rst,

    //! @brief Interfaz FIFO proveniente de uart_top
    output wire      rx_fifo_read_en,
    input  wire      rx_fifo_empty,
    input  wire      rx_fifo_data_valid,
    input  wire [7:0] rx_fifo_data,

    //! @brief Resultados hacia el exterior
    output wire [DATA_WIDTH-1:0] alu_result,
    output wire                  alu_cout,
    output wire                  alu_zero,
    output wire                  alu_exec_pulse
);

    //! @brief Decoder UART -> pulsos de carga ALU
    wire [DATA_WIDTH-1:0] alu_data;
    wire load_a;
    wire load_b;
    wire load_sel;
    wire exec_pulse;
    wire decoder_error;

    //! @brief Instancia del decoder de paquetes UART
    uart_packet_decoder #(
        .DATA_WIDTH(DATA_WIDTH)
    ) uart_decoder (
        .clk(clk),
        .rst(rst),
        .rx_fifo_read_en(rx_fifo_read_en),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_data_valid(rx_fifo_data_valid),
        .rx_fifo_data(rx_fifo_data),
        .alu_data(alu_data),
        .load_a(load_a),
        .load_b(load_b),
        .load_sel(load_sel),
        .exec_pulse(exec_pulse),
        .decoder_error(decoder_error),
        .packet_complete()
    );

    //! @brief Instancia de la ALU top
    alu_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH)
    ) alu_core (
        .clk(clk),
        .rst(rst),
        .data_in(alu_data),
        .load_a(load_a),
        .load_b(load_b),
        .load_sel(load_sel),
        .Result(alu_result),
        .Cout(alu_cout),
        .Zero(alu_zero),
        .exec_pulse(alu_exec_pulse),
        .result_led0(),
        .result_led1(),
        .result_led_b_n(),
        .result_led_g_n(),
        .result_led_r_n()
    );

    assign alu_exec_pulse = exec_pulse;

endmodule
