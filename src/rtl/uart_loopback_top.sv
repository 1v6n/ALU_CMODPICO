`include "alu_timescale.vh"
`include "uart_parity.v"

/**
 * @file uart_loopback_top.sv
 * @brief Módulo top para loopback UART con indicadores LED
 *
 * @details Este módulo implementa un sistema de loopback UART completo que:
 * - Recibe datos desde una PC por el puerto UART (RX)
 * - Almacena los datos en FIFO_RX
 * - Transfiere automáticamente los datos de FIFO_RX a FIFO_TX
 * - Transmite los datos de vuelta a la PC (TX)
 * - Indica actividad con LEDs: LED0 para rx_done, LED1 para tx_done
 */

module uart_loopback_top
  import uart_parity_pkg::*;
#(
    parameter int DATA_BITS   = 8,
    parameter parity_t PARITY = PARITY_NONE,
    parameter int OVERSAMPLE  = 16,
    parameter int CLOCK_FREQ  = 12_000_000,
    parameter int BAUD_RATE   = 9600,
    parameter int FIFO_DEPTH  = 32
) (
    // ========================================================================
    // Señales de reloj y reset
    // ========================================================================
    input  wire               clk,                     //!< Reloj del sistema (12 MHz)
    input  wire               rst,                     //!< Reset síncrono activo por BAJO (botón con pullup)

    // ========================================================================
    // Interfaz UART física (hacia/desde PC)
    // ========================================================================
    input  wire               rx,                      //!< Línea serie de entrada desde PC
    output wire               tx,                      //!< Línea serie de salida hacia PC

    // ========================================================================
    // Indicadores LED (incorporados en la placa)
    // ========================================================================
    output reg                led0,                    //!< LED0: indica rx_done_tick
    output reg                led1                     //!< LED1: indica tx_done_tick
);

    // ========================================================================
    // Gestión de reset: Adaptación de botón activo bajo a lógica activa alta
    // ========================================================================
    
    /**
     * @brief Conversión de señal de reset del botón a lógica interna
     * @details El botón físico tiene PULLUP interno:
     *   - Botón liberado (no presionado) → rst=1 (alto)
     *   - Botón presionado              → rst=0 (bajo)
     * 
     * Los módulos internos y lógica local usan reset activo ALTO:
     *   - rst_n=1 → En RESET
     *   - rst_n=0 → Operando
     * 
     * La inversión rst_n = ~rst genera:
     *   - Botón liberado  → rst=1 → rst_n=0 → OPERACIÓN NORMAL ✓
     *   - Botón presionado → rst=0 → rst_n=1 → RESET ACTIVO ✓
     */
    wire rst_n;
    assign rst_n = ~rst;

    // ========================================================================
    // Señales internas del módulo uart_top
    // ========================================================================
    
    // Interfaz de transmisión
    reg                write_en_tx_top;
    reg [DATA_BITS-1:0] tx_data_in;
    wire               tx_done_tick;

    // Interfaz de recepción
    wire               read_en_rx_top;
    wire [DATA_BITS-1:0] data_out_rx;
    wire               data_valid_rx;
    wire               rx_done_tick;

    // Estado de FIFOs
    wire               rx_fifo_empty;
    wire               rx_fifo_full;
    wire [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_level;

    wire               tx_fifo_empty;
    wire               tx_fifo_full;
    wire [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_level;

    // Errores (no usados en este diseño)
    wire               parity_error;
    wire               frame_error;

    // Interface hacia la FSM de ALU
    wire                   alu_rx_read_en;
    wire [DATA_BITS-1:0]   alu_result;
    wire                   alu_cout;
    wire                   alu_zero;
    wire                   alu_exec_pulse;

    // ========================================================================
    // Instancia de la FSM que conecta la UART con la ALU
    // ========================================================================
    alu_top_fsm #(
        .DATA_WIDTH     (DATA_BITS),
        .OPCODE_WIDTH   (6)
    ) u_alu_top_fsm (
        .clk             (clk),
        .rst             (rst_n),
        .rx_fifo_read_en (alu_rx_read_en),
        .rx_fifo_empty   (rx_fifo_empty),
        .rx_fifo_data_valid(data_valid_rx),
        .rx_fifo_data    (data_out_rx),
        .alu_result      (alu_result),
        .alu_cout        (alu_cout),
        .alu_zero        (alu_zero),
        .alu_exec_pulse  (alu_exec_pulse)
    );

    // ========================================================================
    // Instancia del módulo uart_top
    // ========================================================================
    uart_top #(
        .DATA_BITS   (DATA_BITS),
        .PARITY      (PARITY),
        .OVERSAMPLE  (OVERSAMPLE),
        .CLOCK_FREQ  (CLOCK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .FIFO_DEPTH  (FIFO_DEPTH)
    ) u_uart_top (
        .clk            (clk),
        .rst            (rst_n),     

        .rx             (rx),
        .tx             (tx),

        .write_en_tx_top(write_en_tx_top),
        .tx_data_in     (tx_data_in),
        .tx_done_tick   (tx_done_tick),

        .read_en_rx_top (read_en_rx_top),
        .data_out_rx    (data_out_rx),
        .data_valid_rx  (data_valid_rx),
        .rx_done_tick   (rx_done_tick),

        .rx_fifo_empty  (rx_fifo_empty),
        .rx_fifo_full   (rx_fifo_full),
        .rx_fifo_level  (rx_fifo_level),

        .tx_fifo_empty  (tx_fifo_empty),
        .tx_fifo_full   (tx_fifo_full),
        .tx_fifo_level  (tx_fifo_level),

        .parity_error   (parity_error),
        .frame_error    (frame_error)
    );

    // ========================================================================
    // Respuesta UART: reportar resultado/flags sin loopback
    // ========================================================================
    typedef enum reg [2:0] {
        RESP_IDLE,
        RESP_STX,
        RESP_PAYLOAD,
        RESP_FLAGS,
        RESP_ETX
    } resp_state_t;

    resp_state_t         resp_state;
    reg [DATA_BITS-1:0]  pending_result;
    reg [1:0]            pending_flags;
    reg                  resp_pending;
    reg                  capture_wait;

    assign read_en_rx_top = alu_rx_read_en;  // solo ALU consume RX FIFO

    always_ff @(posedge clk) begin
        if (rst_n) begin
            resp_state      <= RESP_IDLE;
            pending_result  <= '0;
            pending_flags   <= '0;
            resp_pending    <= 1'b0;
            capture_wait    <= 1'b0;
            write_en_tx_top <= 1'b0;
            tx_data_in      <= '0;
        end else begin
            write_en_tx_top <= 1'b0; 
            //!<  Capturar resultado ALU cuando esté listo
            if (alu_exec_pulse) begin
                capture_wait <= 1'b1;
            end
            //!< Almacenar resultado y flags cuando estén listos
            if (capture_wait) begin
                pending_result <= alu_result;
                pending_flags  <= {alu_zero, alu_cout};
                resp_pending   <= 1'b1;
                capture_wait   <= 1'b0;
            end
            //!< FSM de respuesta UART
            case (resp_state)
                //!< Espera
                RESP_IDLE: begin
                    if (resp_pending) begin
                        resp_state   <= RESP_STX;
                    end
                end
                //!< Enviar STX
                RESP_STX: begin
                    if (!tx_fifo_full) begin
                        tx_data_in      <= 8'h02;
                        write_en_tx_top <= 1'b1;
                        resp_state      <= RESP_PAYLOAD;
                    end
                end
                //!< Enviar resultado ALU
                RESP_PAYLOAD: begin
                    if (!tx_fifo_full) begin
                        tx_data_in      <= pending_result;
                        write_en_tx_top <= 1'b1;
                        resp_state      <= RESP_FLAGS;
                    end
                end
                //!< Enviar flags ALU
                RESP_FLAGS: begin
                    if (!tx_fifo_full) begin
                        tx_data_in      <= {6'b0, pending_flags};
                        write_en_tx_top <= 1'b1;
                        resp_state      <= RESP_ETX;
                    end
                end
                //!< Enviar ETX
                RESP_ETX: begin
                    if (!tx_fifo_full) begin
                        tx_data_in      <= 8'h03; // ETX
                        write_en_tx_top <= 1'b1;
                        resp_state      <= RESP_IDLE;
                        resp_pending    <= 1'b0;
                    end
                end
                default: resp_state <= RESP_IDLE;
            endcase
        end
    end

    // ========================================================================
    // Control de LEDs
    // ========================================================================
    
    /**
     * @brief Indicadores LED para rx_done y tx_done
     * @details 
     * - LED0: Se enciende cuando rx_done_tick = 1 (se recibió un byte completo)
     * - LED1: Se enciende cuando tx_done_tick = 1 (se transmitió un byte completo)
     * 
     * Los LEDs se mantienen encendidos durante un periodo corto para 
     * visualización. Implementado con contadores de timeout.
     */
    
    localparam int LED_TIMEOUT_CYCLES = 1_200_000;  // ~100 ms @ 12 MHz
    
    reg [$clog2(LED_TIMEOUT_CYCLES+1)-1:0] led0_counter;
    reg [$clog2(LED_TIMEOUT_CYCLES+1)-1:0] led1_counter;

    // LED0: rx_done indicator
    always_ff @(posedge clk) begin
        if (rst_n) begin
            led0         <= 1'b0;
            led0_counter <= '0;
        end else begin
            if (rx_done_tick) begin
                led0         <= 1'b1;
                led0_counter <= LED_TIMEOUT_CYCLES;
            end else if (led0_counter > 0) begin
                led0_counter <= led0_counter - 1;
                if (led0_counter == 1)  // Apagar cuando llegue a 0
                    led0 <= 1'b0;
            end
        end
    end

    // LED1: tx_done indicator
    always_ff @(posedge clk) begin
        if (rst_n) begin
            led1         <= 1'b0;
            led1_counter <= '0;
        end else begin
            if (tx_done_tick) begin
                led1         <= 1'b1;
                led1_counter <= LED_TIMEOUT_CYCLES;
            end else if (led1_counter > 0) begin
                led1_counter <= led1_counter - 1;
                if (led1_counter == 1)  // Apagar cuando llegue a 0
                    led1 <= 1'b0;
            end
        end
    end

endmodule
