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
    parameter int DATA_WIDTH   = 8,
    parameter int OPCODE_WIDTH = 6,
    parameter int UART_FIFO_DEPTH = 16
) (
    //! @brief Señales de reloj y reset
    input  wire clk,
    input  wire rst,

    //! @brief Interfaz UART RX ready/valid
    input  wire [7:0] uart_rx_data,
    input  wire       uart_rx_valid,
    output wire       uart_rx_ready,

    //! @brief Resultados hacia el exterior
    output wire [DATA_WIDTH-1:0] alu_result,
    output wire                  alu_cout,
    output wire                  alu_zero
);

    //! @brief FIFO RX 
    wire rx_fifo_read_en;
    wire rx_fifo_empty;
    wire rx_fifo_full;
    wire rx_fifo_data_valid;
    wire [7:0] rx_fifo_data;

    //! @brief Instancia de la FIFO síncrona para almacenar datos recibidos por UART
    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(UART_FIFO_DEPTH)
    ) uart_rx_fifo (
        .clk(clk),
        .rst(rst),
        .write_en(uart_rx_valid && uart_rx_ready),
        .read_en(rx_fifo_read_en),
        .data_in(uart_rx_data),
        .data_out(rx_fifo_data),
        .data_valid(rx_fifo_data_valid),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty),
        .level()
    );

    assign uart_rx_ready = !rx_fifo_full;   //!< Listo para recibir si la FIFO no está llena    

    //! @brief Decoder UART -> pulsos de carga ALU
    wire [DATA_WIDTH-1:0] alu_data;
    wire load_a;
    wire load_b;
    wire load_sel;
    wire exec_pulse;
    wire decoder_error;

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

    //! @brief Instancia de la ALU top reutilizando el banco de registros
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
        .result_led0(),
        .result_led1(),
        .result_led_b_n(),
        .result_led_g_n(),
        .result_led_r_n()
    );

endmodule
