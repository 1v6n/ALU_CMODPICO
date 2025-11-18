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
    input  logic              clk,                     //!< Reloj del sistema (12 MHz)
    input  logic              rst,                     //!< Reset síncrono activo por BAJO (botón con pullup)

    // ========================================================================
    // Interfaz UART física (hacia/desde PC)
    // ========================================================================
    input  logic              rx,                      //!< Línea serie de entrada desde PC
    output logic              tx,                      //!< Línea serie de salida hacia PC

    // ========================================================================
    // Indicadores LED (incorporados en la placa)
    // ========================================================================
    output logic              led0,                    //!< LED0: indica rx_done_tick
    output logic              led1                     //!< LED1: indica tx_done_tick
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
    logic rst_n;
    assign rst_n = ~rst;

    // ========================================================================
    // Señales internas del módulo uart_top
    // ========================================================================
    
    // Interfaz de transmisión
    logic              write_en_tx_top;
    logic [DATA_BITS-1:0] tx_data_in;
    logic              tx_done_tick;

    // Interfaz de recepción
    logic              read_en_rx_top;
    logic [DATA_BITS-1:0] data_out_rx;
    logic              data_valid_rx;
    logic              rx_done_tick;

    // Estado de FIFOs
    logic              rx_fifo_empty;
    logic              rx_fifo_full;
    logic [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_level;

    logic              tx_fifo_empty;
    logic              tx_fifo_full;
    logic [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_level;

    // Errores (no usados en este diseño)
    logic              parity_error;
    logic              frame_error;

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
    // Lógica de loopback: transfiere datos de FIFO_RX a FIFO_TX
    // ========================================================================
    
    /**
     * @brief Máquina de estados de loopback
     * @details Estados:
     * - S_IDLE: Espera a que haya dato en RX y espacio en TX
     * - S_WAIT_DATA: Espera a que data_valid_rx se active
     * 
     * Funcionamiento:
     * 1. En S_IDLE: si !rx_fifo_empty && !tx_fifo_full → genera read_en_rx_top
     * 2. En S_WAIT_DATA: espera data_valid_rx → copia dato a tx_data_in y genera write_en_tx_top
     * 3. Vuelve a S_IDLE
     */
    typedef enum logic [1:0] {
        S_IDLE,
        S_WAIT_DATA
    } loopback_state_t;

    loopback_state_t loopback_state;

    always_ff @(posedge clk) begin
        if (rst_n) begin
            loopback_state   <= S_IDLE;
            write_en_tx_top  <= 1'b0;
            read_en_rx_top   <= 1'b0;
            tx_data_in       <= '0;
        end else begin
            // Por defecto, desactivar pulsos
            write_en_tx_top  <= 1'b0;
            read_en_rx_top   <= 1'b0;

            case (loopback_state)
                S_IDLE: begin
                    // Si hay dato en FIFO_RX y espacio en FIFO_TX
                    if (!rx_fifo_empty && !tx_fifo_full) begin
                        read_en_rx_top  <= 1'b1;        // Solicitar lectura
                        loopback_state  <= S_WAIT_DATA;
                    end
                end

                S_WAIT_DATA: begin
                    // Esperar a que el dato sea válido
                    if (data_valid_rx) begin
                        tx_data_in       <= data_out_rx;  // Copiar dato recibido
                        write_en_tx_top  <= 1'b1;         // Escribir en FIFO_TX
                        loopback_state   <= S_IDLE;       // Volver a idle
                    end
                end

                default: loopback_state <= S_IDLE;
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
    
    logic [$clog2(LED_TIMEOUT_CYCLES+1)-1:0] led0_counter;
    logic [$clog2(LED_TIMEOUT_CYCLES+1)-1:0] led1_counter;

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
