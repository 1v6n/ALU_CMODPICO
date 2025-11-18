`include "alu_timescale.vh"
`include "uart_parity.v"

/**
 * @file uart_rx_led_toggle.sv
 * @brief Módulo top que recibe datos por UART RX y hace toggle de LED cuando llega '1'
 *
 * @details Este módulo implementa un sistema simple que:
 * - Recibe bytes por UART RX desde una PC
 * - Lee el bit menos significativo (LSB) del byte recibido
 * - Si el bit es '1', hace toggle del LED
 * - Si el bit es '0', no hace nada
 *
 * Uso:
 * - Enviar '0x01' desde PC → LED cambia de estado
 * - Enviar '0x00' desde PC → LED se mantiene igual
 * - Enviar '0x03' desde PC → LED cambia de estado (LSB=1)
 * - Enviar '0xFF' desde PC → LED cambia de estado (LSB=1)
 *
 * Parámetros:
 * - CLOCK_FREQ: 12 MHz (oscilador de la Cmod A7-35T)
 * - BAUD_RATE: 9600 bps
 * - DATA_BITS: 8 bits
 * - PARITY: Sin paridad
 */

module uart_rx_led_toggle
  import uart_parity_pkg::*;
#(
    parameter int DATA_BITS   = 8,
    parameter parity_t PARITY = PARITY_NONE,
    parameter int OVERSAMPLE  = 16,
    parameter int CLOCK_FREQ  = 12_000_000,
    parameter int BAUD_RATE   = 9600
) (
    // ========================================================================
    // Señales de reloj y reset
    // ========================================================================
    input  logic              clk,                     //!< Reloj del sistema (12 MHz)
    input  logic              rst,                     //!< Reset síncrono activo por BAJO

    // ========================================================================
    // Interfaz UART física
    // ========================================================================
    input  logic              rx,                      //!< Línea serie de entrada desde PC

    // ========================================================================
    // Indicador LED
    // ========================================================================
    output logic              led                      //!< LED que hace toggle cuando llega '1'
);

    // ========================================================================
    // Señal de reset activo por bajo
    // Se usa teniendo en cuenta que el botón de RST tiene una pullup interna
    // ========================================================================
    logic rst_n;
    assign rst_n = ~rst;

    // ========================================================================
    // Señales internas del generador de baudrate
    // ========================================================================
    logic baud_tick;
    logic baud_x16_tick;

    // ========================================================================
    // Señales internas del receptor UART
    // ========================================================================
    logic [DATA_BITS-1:0] dout;
    logic rx_done_tick;
    logic parity_error;
    logic frame_error;

    // ========================================================================
    // Instancia del generador de baudrate
    // ========================================================================
    uart_baudrate_gen #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_baudrate_gen (
        .clk           (clk),
        .rst           (rst_n),
        .baud_tick     (baud_tick),
        .baud_x16_tick (baud_x16_tick)
    );

    // ========================================================================
    // Instancia del receptor UART
    // ========================================================================
    uart_rx #(
        .DATA_BITS  (DATA_BITS),
        .OVERSAMPLE (OVERSAMPLE),
        .PARITY     (PARITY)
    ) u_uart_rx (
        .clk           (clk),
        .rst           (rst_n),
        .rx            (rx),
        .baud_tick     (baud_x16_tick),
        .dout          (dout),
        .rx_done_tick  (rx_done_tick),
        .parity_error  (parity_error),
        .frame_error   (frame_error),
        .write_en      (),                  // No usado (sin FIFO)
        .full          (1'b0)               // Siempre hay espacio
    );

    // ========================================================================
    // Lógica de toggle del LED
    // ========================================================================
    
    /**
     * @brief Control del LED con toggle
     * @details Cuando llega un byte válido (rx_done_tick=1):
     * - Si dout[0] == 1 → LED hace toggle (cambia de estado)
     * - Si dout[0] == 0 → LED se mantiene igual
     * 
     * El toggle permite ver actividad acumulativa sin necesidad
     * de mantener el estado desde la PC.
     */
    always_ff @(posedge clk) begin
        if (rst_n) begin
            led <= 1'b0;
        end else begin
            if (rx_done_tick && !frame_error && !parity_error) begin
                // Si el LSB del byte recibido es '1', hacer toggle
                if (dout[0] == 1'b1) begin
                    led <= ~led;
                end
                // Si dout[0] == 0, no hacer nada (mantener led)
            end
        end
    end

    // ========================================================================
    // Reporte de configuración (solo para simulación)
    // ========================================================================
    initial begin
        $display("==================================================");
        $display("  UART RX LED Toggle Configuration");
        $display("==================================================");
        $display("  CLOCK_FREQ     : %0d Hz", CLOCK_FREQ);
        $display("  BAUD_RATE      : %0d bps", BAUD_RATE);
        $display("  DATA_BITS      : %0d", DATA_BITS);
        $display("  PARITY         : %s", 
                 (PARITY==PARITY_NONE) ? "NONE" : 
                 (PARITY==PARITY_EVEN) ? "EVEN" : "ODD");
        $display("  OVERSAMPLE     : %0d", OVERSAMPLE);
        $display("  ");
        $display("  Funcionamiento:");
        $display("  - Recibir byte con LSB=1 → LED toggle");
        $display("  - Recibir byte con LSB=0 → LED mantiene");
        $display("  - Ejemplos:");
        $display("    0x01 → toggle");
        $display("    0x03 → toggle");
        $display("    0xFF → toggle");
        $display("    0x00 → sin cambio");
        $display("    0xFE → sin cambio");
        $display("==================================================");
    end

endmodule