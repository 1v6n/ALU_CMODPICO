`timescale 1ns/1ps

/**
 * @file tb_uart_rx.sv
 * @brief Testbench para el receptor UART (uart_rx)
 *
 * @details Testbench para validar el módulo `uart_rx` en sus tres
 * modos de paridad: NONE, EVEN y ODD. Para cada modo ejecuta casos smoke,
 * aleatorios y casos de error (frame/parity), compara los datos recibidos
 * contra el modelo dorado y verifica las señales de error.
 *
 * Características principales:
 * - Inyección de frames seriales bit a bit con timing preciso
 * - Verificación de datos recibidos (dout) contra valores esperados
 * - Validación de señales de error: parity_error y frame_error
 * - Verificación de pulso rx_done_tick al completar frame
 * - Timing sincronizado con baud_x16_tick para reproducir condiciones reales
 *
 * Modos de prueba (parámetro `TEST_MODE`):
 * - 0 → PARITY_NONE (frame de 10 bits)
 * - 1 → PARITY_EVEN (frame de 11 bits)
 * - 2 → PARITY_ODD  (frame de 11 bits)
 *
 * Estructura de frame recibido:
 * - START (0) + DATA[LSB→MSB] + [PARITY] + STOP (1)
 * - Paridad calculada únicamente sobre DATA
 *
 * Flujo de pruebas:
 * 1) Reset y setup de reloj/baudrate
 * 2) Para cada vector: inyectar frame bit a bit, esperar rx_done_tick
 * 3) Verificar datos recibidos (dout) y flags de error
 * 4) Reportar PASS/FAIL por caso y resumen por modo
 *
 * Recursos:
 * - Vectores: `uart_rx_test_vectors.svh`
 * - DUT: `uart_rx` con parámetros configurables
 */

module tb_uart_rx;
    `include "uart_rx_test_vectors.svh"

    //! @param TEST_MODE Selección de modo de paridad a probar (0=NONE, 1=EVEN, 2=ODD)
    parameter int TEST_MODE = 0;

    // ========================================================================
    // Parámetros de configuración
    // ========================================================================
    
    //! @brief Factor de oversampling (debe coincidir con el DUT)
    localparam int OVERSAMPLE = 16;
    //! @brief Período de reloj en nanosegundos (83.33 ns para 12 MHz)
    localparam real CLK_PERIOD = 83.33;
    //! @brief Frecuencia de reloj del testbench en Hz
    localparam int CLOCK_FREQ_HZ = 12_000_000;
    //! @brief Tasa de baudios configurada
    localparam int BAUD_RATE = 9600;
    //! @brief Ciclos de reloj por tick de oversampling
    localparam int TICKS_PER_OS = CLOCK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);

    // Nota: FRAME_BITS_NONE, FRAME_BITS_EVEN, FRAME_BITS_ODD ya están definidos en uart_rx_test_vectors.svh

    // ========================================================================
    // Señales del DUT
    // ========================================================================
    
    logic clk;                  //!< Reloj del sistema
    logic rst_n;                //!< Reset síncrono activo por bajo
    logic rx;                   //!< Línea serie de entrada
    logic baud_tick;            //!< Tick de baudrate x1 (no usado en TB)
    logic baud_x16_tick;        //!< Tick de oversampling x16 (alimenta al DUT)
    logic [7:0] dout;           //!< Datos paralelos de salida
    logic rx_done_tick;         //!< Pulso de finalización de frame
    logic parity_error;         //!< Error de paridad detectado
    logic frame_error;          //!< Error de frame (STOP incorrecto)
    logic write_en;             //!< Señal FIFO: pulso de escritura
    logic full;                 //!< Señal FIFO: buffer lleno

    // ========================================================================
    // Contadores y variables de control
    // ========================================================================
    
    integer error_count;        //!< Contador de errores detectados
    integer test_count;         //!< Contador de casos de prueba ejecutados

    // ========================================================================
    // Generación de reloj y baudrate
    // ========================================================================
    
    /**
     * @brief Generador de reloj del sistema
     * @details Produce un reloj de ~12 MHz (período ≈ 83.33 ns)
     */
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    /**
     * @brief Instancia del generador de baudrate
     * @details Genera los ticks de baudrate x1 y x16 para sincronizar la recepción.
     * El tick x16 (baud_x16_tick) es el que alimenta la entrada baud_tick del DUT.
     */
    uart_baudrate_gen #(
        .CLOCK_FREQ(CLOCK_FREQ_HZ),
        .BAUD_RATE (BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE)
    ) baudgen (
        .clk(clk),
        .rst_n(rst_n),
        .baud_tick(baud_tick),
        .baud_x16_tick(baud_x16_tick)
    );

    // ========================================================================
    // Instanciación del DUT
    // ========================================================================
    
    /**
     * @brief Instancia del módulo uart_rx bajo prueba
     * @details Configuración:
     * - 8 bits de datos
     * - Oversampling x16
     * - Paridad según TEST_MODE
     */
    uart_rx #(
        .DATA_BITS(8),
        .OVERSAMPLE(OVERSAMPLE),
        .PARITY((TEST_MODE == 1) ? uart_parity_pkg::PARITY_EVEN :
                (TEST_MODE == 2) ? uart_parity_pkg::PARITY_ODD :
                                   uart_parity_pkg::PARITY_NONE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx(rx),
        .baud_tick(baud_x16_tick),  // Tick de oversampling x16
        .dout(dout),
        .rx_done_tick(rx_done_tick),
        .parity_error(parity_error),
        .frame_error(frame_error),
        .write_en(write_en),
        .full(1'b0)  // FIFO siempre disponible
    );

    // ========================================================================
    // Tasks de utilidad
    // ========================================================================
    
    /**
     * @brief Inicializa el sistema y realiza reset
     * @details Aplica reset durante 10 ciclos, luego espera 5 ciclos adicionales
     * para estabilización. Inicializa todos los contadores y señales de control.
     */
    task automatic do_reset();
        rst_n       = 1'b0;
        rx          = 1'b1;  // Línea idle en alto
        full        = 1'b0;
        error_count = 0;
        test_count  = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
    endtask

    /**
     * @brief Inyecta un frame serial completo bit a bit en la línea rx
     * @details Transmite cada bit del frame con timing preciso basado en baud_x16_tick.
     * Cada bit dura OVERSAMPLE ticks de baud_x16_tick.
     *
     * @param frame_data Frame a transmitir (10 u 11 bits empaquetados LSB-first)
     * @param frame_bits Cantidad de bits del frame (10 para NONE, 11 para EVEN/ODD)
     */
    task automatic inject_frame(
        input [10:0] frame_data,
        input int frame_bits
    );
        integer bit_idx;
        
        // Asegurar línea idle antes de empezar
        rx = 1'b1;
        repeat (32) @(posedge baud_x16_tick);  // Idle por 2 bit-times
        
        // Transmitir cada bit del frame
        for (bit_idx = 0; bit_idx < frame_bits; bit_idx++) begin
            // Cambiar el bit 
            rx = (frame_data >> bit_idx) & 1'b1;
            // Mantener el bit durante OVERSAMPLE ticks de baud_x16
            repeat (OVERSAMPLE) @(posedge baud_x16_tick);
        end
        
        // Volver a línea idle y esperar un bit-time adicional
        // para que el DUT termine de procesar y genere rx_done_tick
        rx = 1'b1;
        repeat (OVERSAMPLE) @(posedge baud_x16_tick);
    endtask

    /**
     * @brief Inyecta frame y verifica la recepción
     * @details Envía un frame completo bit a bit, espera la señal rx_done_tick
     * del DUT, y verifica los datos recibidos y las señales de error contra los
     * valores esperados.
     *
     * Estrategia de sincronización:
     * - Un bloque always captura rx_done_tick y las señales asociadas en paralelo
     * - La tarea inject_frame transmite el frame bit a bit
     * - Después de transmitir, la tarea espera a que se capture rx_done_tick
     * - Si no se captura en el tiempo esperado, se reporta timeout
     *
     * @param frame_data Frame a transmitir (10 u 11 bits empaquetados LSB-first)
     * @param frame_bits Cantidad de bits del frame (10 para NONE, 11 para EVEN/ODD)
     * @param exp_data Datos esperados a la salida (dout)
     * @param exp_parity_err Indica si se espera error de paridad (1) o no (0)
     * @param exp_frame_err Indica si se espera error de frame (1) o no (0)
     * @param test_name Nombre descriptivo del caso de prueba para reporte
     */
    task automatic inject_and_verify(
        input [10:0] frame_data,
        input int frame_bits,
        input [7:0] exp_data,
        input logic exp_parity_err,
        input logic exp_frame_err,
        input string test_name
    );
        integer timeout_cycles;
        integer cycle_count;
        
        // Calcular timeout: 3x el tiempo esperado de un frame completo
        timeout_cycles = frame_bits * OVERSAMPLE * TICKS_PER_OS * 3;
        cycle_count = 0;
        
        // Resetear flag de captura antes de inyectar
        done_tick_captured = 1'b0;
        
        // Inyectar frame (el always block capturará rx_done_tick en paralelo)
        inject_frame(frame_data, frame_bits);
        
        // Esperar a que se capture el done_tick o timeout
        while (!done_tick_captured && cycle_count < timeout_cycles) begin
            @(posedge clk);
            cycle_count++;
        end
        
        // Verificar resultado y reportar
        if (!done_tick_captured) begin
            // Timeout: el DUT no generó rx_done_tick en el tiempo esperado
            $display("[TIMEOUT] %s: rx_done_tick no se activo", test_name);
            error_count++;
            test_count++;
        end else begin
            // rx_done_tick capturado: verificar datos y errores
            test_count++;
            if (dout_captured !== exp_data) begin
                error_count++;
                $display("[FAIL] %s: data mismatch got=0x%02h exp=0x%02h", test_name, dout_captured, exp_data);
            end else if (parity_error_captured !== exp_parity_err) begin
                error_count++;
                $display("[FAIL] %s: parity_error mismatch got=%b exp=%b", test_name, parity_error_captured, exp_parity_err);
            end else if (frame_error_captured !== exp_frame_err) begin
                error_count++;
                $display("[FAIL] %s: frame_error mismatch got=%b exp=%b", test_name, frame_error_captured, exp_frame_err);
            end else begin
                $display("[PASS] %s", test_name);
            end
        end
        
        // Esperar algunos ciclos antes del siguiente test para estabilización
        repeat (10) @(posedge clk);
    endtask

    // ========================================================================
    // Monitor de captura de rx_done_tick
    // ========================================================================
    
    /**
     * @brief Señales de captura para sincronización con rx_done_tick
     * @details Estas señales capturan el pulso rx_done_tick y los datos/errores
     * asociados en el momento exacto en que se generan, evitando race conditions.
     */
    logic done_tick_captured;           //!< Flag: indica que rx_done_tick fue capturado
    logic [7:0] dout_captured;          //!< Datos capturados al momento del pulso
    logic parity_error_captured;        //!< Error de paridad capturado al momento del pulso
    logic frame_error_captured;         //!< Error de frame capturado al momento del pulso
    
    /**
     * @brief Monitor de captura de rx_done_tick y señales asociadas
     * @details Este bloque always corre en paralelo con la inyección de frames
     * y captura el pulso rx_done_tick (que dura solo 1 ciclo de reloj) junto
     * con los valores de dout, parity_error y frame_error en ese mismo ciclo.
     * 
     * Esta estrategia garantiza que no se pierda el pulso done_tick incluso si
     * la tarea inject_frame aún está ejecutándose cuando el DUT genera la señal.
     */
    always @(posedge clk) begin
        if (rx_done_tick) begin
            done_tick_captured <= 1'b1;
            dout_captured <= dout;
            parity_error_captured <= parity_error;
            frame_error_captured <= frame_error;
        end
    end
    
    // ========================================================================
    // Secuencia principal de pruebas
    // ========================================================================
    
    /**
     * @brief Secuencia principal de pruebas
     * @details Ejecuta los casos de prueba según TEST_MODE:
     * - Smoke cases: casos básicos predefinidos
     * - Random cases: casos aleatorios con semilla fija
     * - Error cases: casos de error de paridad y frame
     */
    initial begin
        // Generar archivo de forma de onda para depuración
        $dumpfile("uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
        
        $display("========================================");
        $display("  UART RX Testbench");
        $display("  TEST_MODE=%0d", TEST_MODE);
        if (TEST_MODE == 0) $display("  Parity: NONE");
        else if (TEST_MODE == 1) $display("  Parity: EVEN");
        else if (TEST_MODE == 2) $display("  Parity: ODD");
        $display("========================================");
        
        // Reset inicial
        do_reset();
        
        // Ejecutar casos según modo
        if (TEST_MODE == 0) begin
            // ========== PARITY_NONE ==========
            $display("\n--- Smoke Cases (NONE) ---");
            for (int i = 0; i < NUM_SMOKE_NONE; i++) begin
                inject_and_verify(
                    smoke_frame_none[i],
                    FRAME_BITS_NONE,
                    smoke_data_none[i],
                    1'b0,  // No parity error expected
                    1'b0,  // No frame error expected
                    $sformatf("SMOKE_NONE[%0d]", i)
                );
            end
            
            $display("\n--- Random Cases (NONE) ---");
            for (int i = 0; i < NUM_RANDOM_NONE; i++) begin
                inject_and_verify(
                    random_frame_none[i],
                    FRAME_BITS_NONE,
                    random_data_none[i],
                    1'b0,
                    1'b0,
                    $sformatf("RANDOM_NONE[%0d]", i)
                );
            end
            
            $display("\n--- Error Cases (NONE) ---");
            for (int i = 0; i < NUM_ERROR_NONE; i++) begin
                inject_and_verify(
                    error_frame_none[i],
                    FRAME_BITS_NONE,
                    error_data_none[i],
                    error_parity_flag_none[i],
                    error_frame_flag_none[i],
                    $sformatf("ERROR_NONE[%0d]", i)
                );
            end
            
        end else if (TEST_MODE == 1) begin
            // ========== PARITY_EVEN ==========
            $display("\n--- Smoke Cases (EVEN) ---");
            for (int i = 0; i < NUM_SMOKE_EVEN; i++) begin
                inject_and_verify(
                    smoke_frame_even[i],
                    FRAME_BITS_EVEN,
                    smoke_data_even[i],
                    1'b0,
                    1'b0,
                    $sformatf("SMOKE_EVEN[%0d]", i)
                );
            end
            
            $display("\n--- Random Cases (EVEN) ---");
            for (int i = 0; i < NUM_RANDOM_EVEN; i++) begin
                inject_and_verify(
                    random_frame_even[i],
                    FRAME_BITS_EVEN,
                    random_data_even[i],
                    1'b0,
                    1'b0,
                    $sformatf("RANDOM_EVEN[%0d]", i)
                );
            end
            
            $display("\n--- Error Cases (EVEN) ---");
            for (int i = 0; i < NUM_ERROR_EVEN; i++) begin
                inject_and_verify(
                    error_frame_even[i],
                    FRAME_BITS_EVEN,
                    error_data_even[i],
                    error_parity_flag_even[i],
                    error_frame_flag_even[i],
                    $sformatf("ERROR_EVEN[%0d]", i)
                );
            end
            
        end else if (TEST_MODE == 2) begin
            // ========== PARITY_ODD ==========
            $display("\n--- Smoke Cases (ODD) ---");
            for (int i = 0; i < NUM_SMOKE_ODD; i++) begin
                inject_and_verify(
                    smoke_frame_odd[i],
                    FRAME_BITS_ODD,
                    smoke_data_odd[i],
                    1'b0,
                    1'b0,
                    $sformatf("SMOKE_ODD[%0d]", i)
                );
            end
            
            $display("\n--- Random Cases (ODD) ---");
            for (int i = 0; i < NUM_RANDOM_ODD; i++) begin
                inject_and_verify(
                    random_frame_odd[i],
                    FRAME_BITS_ODD,
                    random_data_odd[i],
                    1'b0,
                    1'b0,
                    $sformatf("RANDOM_ODD[%0d]", i)
                );
            end
            
            $display("\n--- Error Cases (ODD) ---");
            for (int i = 0; i < NUM_ERROR_ODD; i++) begin
                inject_and_verify(
                    error_frame_odd[i],
                    FRAME_BITS_ODD,
                    error_data_odd[i],
                    error_parity_flag_odd[i],
                    error_frame_flag_odd[i],
                    $sformatf("ERROR_ODD[%0d]", i)
                );
            end
        end
        
        // ========== Resumen Final ==========
        $display("\n========================================");
        $display("  Resumen de Pruebas");
        $display("========================================");
        $display("Tests ejecutados: %0d", test_count);
        $display("Tests PASS: %0d", test_count - error_count);
        $display("Tests FAIL: %0d", error_count);
        
        if (error_count == 0) begin
            $display("\n*** TODOS LOS TESTS PASARON sin errores ***");
        end else begin
            $display("\n*** SE DETECTARON ERRORES ***");
        end
        
        $finish;
    end

endmodule
