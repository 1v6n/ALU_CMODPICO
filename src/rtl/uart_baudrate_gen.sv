`include "alu_timescale.vh"

/**
 * @file uart_baudrate_gen.sv
 * @brief Generador de baudrate para UART a 9600 bps en Cmod A7-35T
 * 
 * @details Este módulo genera el clock de baudrate para comunicación UART a 9600 bps
 * utilizando el oscilador de 12 MHz de la placa Cmod A7-35T. El módulo implementa
 * un divisor de frecuencia que produce un tick de baudrate cada 1250 ciclos.
 * 
 * El módulo genera dos señales:
 * - baud_tick: Pulso de 1 ciclo de reloj cada vez que se completa el período de baudrate
 * - baud_x16_tick: Pulso 16 veces más rápido para oversampling (común en UARTs)
 */

//! @brief Generador de baudrate para UART 9600 bps con reloj de 12 MHz
module uart_baudrate_gen #(
    //! @param CLOCK_FREQ: Frecuencia del reloj de entrada en Hz
    parameter integer CLOCK_FREQ = 12_000_000,
    //! @param BAUD_RATE: Baudrate deseado en bps
    parameter integer BAUD_RATE = 9600,
    //! @param OVERSAMPLE: Factor de oversampling (típicamente 16 para UART)
    parameter integer OVERSAMPLE = 16
) (
    //! @brief Señales de entrada
    input  logic clk,        //!< Reloj principal (12 MHz)
    input  logic rst,        //!< Reset síncrono ACTIVO POR ALTO
    
    //! @brief Señales de salida
    output logic baud_tick,     //!< Tick de baudrate
    output logic baud_x16_tick  //!< Tick de oversampling
);

    // Cálculo automático de los divisores
    localparam integer BAUD_DIVISOR = CLOCK_FREQ / BAUD_RATE;           // 1250
    localparam integer BAUD_X16_DIVISOR = CLOCK_FREQ / (BAUD_RATE * OVERSAMPLE); // ~78
    
    // Ancho de bits necesario para los contadores
    // Usa $clog2(DIVISOR) para asegurar que se puedan representar valores de 0 a DIVISOR-1
    localparam integer BAUD_COUNTER_WIDTH = $clog2(BAUD_DIVISOR + 1);
    localparam integer BAUD_X16_COUNTER_WIDTH = $clog2(BAUD_X16_DIVISOR + 1);
    
    // Registros internos
    logic [BAUD_COUNTER_WIDTH-1:0] baud_counter;
    logic [BAUD_X16_COUNTER_WIDTH-1:0] baud_x16_counter;
    
    // Generación del tick de baudrate principal (9600 Hz)
    always_ff @(posedge clk) begin
        if (rst) begin
            baud_counter <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_counter == BAUD_DIVISOR - 1) begin
                baud_counter <= '0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end
    
    // Generación del tick de oversampling x16 (153.6 kHz)
    always_ff @(posedge clk) begin
        if (rst) begin
            baud_x16_counter <= '0;
            baud_x16_tick <= 1'b0;
        end else begin
            if (baud_x16_counter == BAUD_X16_DIVISOR - 1) begin
                baud_x16_counter <= '0;
                baud_x16_tick <= 1'b1;
            end else begin
                baud_x16_counter <= baud_x16_counter + 1'b1;
                baud_x16_tick <= 1'b0;
            end
        end
    end
    
    // Verificaciones de síntesis (assertions)
    initial begin
        assert (CLOCK_FREQ > 0) else $fatal("CLOCK_FREQ debe ser mayor que 0");
        assert (BAUD_RATE > 0) else $fatal("BAUD_RATE debe ser mayor que 0");
        assert (OVERSAMPLE > 0) else $fatal("OVERSAMPLE debe ser mayor que 0");
        assert (BAUD_DIVISOR > 1) else $fatal("BAUD_DIVISOR debe ser mayor que 1");
        assert (BAUD_X16_DIVISOR > 1) else $fatal("BAUD_X16_DIVISOR debe ser mayor que 1");
        
        // Información de síntesis
        $display("=== UART Baudrate Generator Configuration ===");
        $display("Clock Frequency: %0d Hz", CLOCK_FREQ);
        $display("Baud Rate: %0d bps", BAUD_RATE);
        $display("Oversample Factor: %0d", OVERSAMPLE);
        $display("Baud Divisor: %0d", BAUD_DIVISOR);
        $display("Baud x16 Divisor: %0d", BAUD_X16_DIVISOR);
        $display("Baud Counter Width: %0d bits", BAUD_COUNTER_WIDTH);
        $display("Baud x16 Counter Width: %0d bits", BAUD_X16_COUNTER_WIDTH);
        $display("Expected Baud Tick Frequency: %0.2f Hz", real'(CLOCK_FREQ) / BAUD_DIVISOR);
        $display("Expected Baud x16 Tick Frequency: %0.2f Hz", real'(CLOCK_FREQ) / BAUD_X16_DIVISOR);
    end

endmodule
