`timescale 1ns/1ps

/**
 * @file tb_uart_tx.sv
 * @brief Testbench para el transmisor UART (uart_tx)
 *
 * @details Testbench para validar el módulo `uart_tx` en sus tres
 * modos de paridad: NONE, EVEN y ODD. Para cada modo ejecuta casos smoke y
 * aleatorios, compara los frames seriales capturados contra un modelo dorado
 * y verifica el timing en función del baudrate real y el oversampling.
 *
 * Características principales:
 * - Muestreo mid-bit sincronizado con `baud_x16_tick` para captura robusta
 * - Verificación de frame: START + DATA[7:0] + [PARITY] + STOP
 * - Validación de timing basada en `CLOCK_FREQ_HZ`, `BAUD_RATE` y `OVERSAMPLE`
 * - Modo opcional con interfaz FIFO
 * - Registro de captura de hasta 11 bits (NONE=10, EVEN/ODD=11)
 *
 * Modos de prueba (parámetro `TEST_MODE`):
 * - 0 → PARITY_NONE (frame de 10 bits)
 * - 1 → PARITY_EVEN (frame de 11 bits)
 * - 2 → PARITY_ODD  (frame de 11 bits)
 *
 * Estructura de frame transmitido:
 * - START (0) + DATA[LSB→MSB] + [PARITY] + STOP (1)
 * - Paridad calculada únicamente sobre DATA
 *
 * Flujo de pruebas:
 * 1) Reset y setup de reloj/baudrate
 * 2) Para cada vector: iniciar TX, capturar bits mid-bit y comparar
 * 3) Verificar cantidad de bits, contenido del frame y timing esperado
 * 4) Reportar PASS/FAIL por caso y resumen por modo
 *
 * Recursos:
 * - Vectores: `uart_tx_test_vectors.svh` (solo arrays de datos)
 * - Modelo dorado local: `build_expected_frame(data)`
 */

module tb_uart_tx;
    `include "uart_tx_test_vectors.svh"

    //! @param TEST_MODE Selección de modo de paridad a probar (0=NONE, 1=EVEN, 2=ODD)
    parameter int TEST_MODE = 0;
    //! @param ENABLE_FIFO_MODE Habilita pruebas adicionales con interfaz FIFO
    parameter bit ENABLE_FIFO_MODE = 1'b0;

    // ========================================================================
    // Parámetros de configuración
    // ========================================================================
    
    //! @brief Factor de oversampling (debe coincidir con el DUT)
    localparam int OVERSAMPLE = 16;
    //! @brief Período de reloj en nanosegundos (83.33 ns para 12 MHz)
    localparam int CLK_PERIOD = 83.33;
    //! @brief Frecuencia de reloj del testbench en Hz
    localparam int CLOCK_FREQ_HZ = 12_000_000;
    //! @brief Tasa de baudios configurada
    localparam int BAUD_RATE = 9600;
    //! @brief Ciclos de reloj por tick de oversampling
    localparam int TICKS_PER_OS = CLOCK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE);
    //! @brief Margen permitido en ciclos para validación de timing
    localparam int EXP_MARGIN_CYCLES = (2*TICKS_PER_OS) + 10;

    // Longitudes de frame esperadas según modo
    localparam int FRAME_BITS_NONE = 10;
    localparam int FRAME_BITS_EVEN = 11;
    localparam int FRAME_BITS_ODD  = 11;
    localparam int MAX_FRAME_BITS  = 11;

    // ========================================================================
    // Señales del DUT
    // ========================================================================
    
    logic clk;                  //!< Reloj del sistema
    logic rst_n;                //!< Reset síncrono activo por bajo
    logic tx_start;             //!< Pulso de inicio de transmisión
    logic baud_tick;            //!< Tick de baudrate x1 (no usado en TB)
    logic baud_x16_tick;        //!< Tick de oversampling x16 (alimenta al DUT)
    logic [7:0] din;            //!< Datos paralelos de entrada
    logic tx;                   //!< Línea serie de salida
    logic tx_done_tick;         //!< Pulso de finalización de frame
    logic write_o;              //!< Señal FIFO: dato disponible
    logic read_en;              //!< Pulso de consumo FIFO (salida del DUT)

    // ========================================================================
    // Contadores y variables de control
    // ========================================================================
    
    integer error_count;        //!< Contador de errores detectados
    integer test_count;         //!< Contador de casos de prueba ejecutados
    integer total_cycles;       //!< Contador global de ciclos de reloj
    integer frame_start_cycle;  //!< Ciclo de inicio del frame actual

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
     * @details Genera los ticks de baudrate x1 y x16 para sincronizar la transmisión.
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

    /**
     * @brief Contador global de ciclos de reloj
     * @details Se utiliza para medir el timing de los frames transmitidos
     */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            total_cycles <= 0;
        end else begin
            total_cycles <= total_cycles + 1;
        end
    end

    // ========================================================================
    // Instanciación del DUT
    // ========================================================================
    
    /**
     * @brief Instancia del módulo uart_tx bajo prueba
     * @details Configuración:
     * - 8 bits de datos
     * - 1 bit de stop (fijo en RTL)
     * - Oversampling x16
    * - Paridad según TEST_MODE
     */
    uart_tx #(
        .DATA_BITS(8),
        .OVERSAMPLE(OVERSAMPLE),
        .PARITY((TEST_MODE == 1) ? uart_parity_pkg::PARITY_EVEN :
                (TEST_MODE == 2) ? uart_parity_pkg::PARITY_ODD  :
                                    uart_parity_pkg::PARITY_NONE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .baud_tick(baud_x16_tick),  // Tick de oversampling x16
        .din(din),
        .write_o(write_o),
        .read_en(read_en),
        .tx(tx),
        .tx_done_tick(tx_done_tick)
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
        tx_start    = 1'b0;
        din         = 8'h00;
        write_o     = 1'b0; // Mantener en 0 para desactivar arranque por FIFO
        error_count = 0;
        test_count  = 0;
        total_cycles = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
    endtask

    /**
     * @brief Captura y verifica un frame serial completo
     * @details Inicia la transmisión mediante tx_start, muestrea la línea tx en el
     * punto medio de cada bit (usando baud_x16_tick), captura el frame completo y
     * verifica contra el frame esperado. También valida el timing de transmisión.
     *
     * @param exp_frame Frame esperado (10 u 11 bits según modo)
     * @param frame_bits Cantidad de bits del frame (10 para NONE, 11 para EVEN/ODD)
     * @param exp_cycles Ciclos de reloj esperados para el frame completo
     * @param data_val Valor de datos de 8 bits a transmitir
     * @param test_name Nombre descriptivo del caso de prueba
     */
    task automatic capture_and_verify(
        input [10:0] exp_frame,
        input int frame_bits,
        input int exp_cycles,
        input [7:0] data_val,
        input string test_name
    );
        reg [10:0] captured_frame; // Registro fijo 11-bit (máximo)
        integer bit_pos;
        integer os_count;
        integer cycles_elapsed;
        reg [10:0] exp_masked;
        reg [10:0] got_masked;
        
        // Inicialización de variables locales
        captured_frame = '0;
        bit_pos = 0;
        din = data_val;
        
        // Esperar estado idle (línea en alto)
        wait (tx == 1'b1);
        @(posedge clk);
        
        // Pulso de inicio y marca de tiempo
        frame_start_cycle = total_cycles;
        tx_start = 1'b1;
        @(posedge clk);
        tx_start = 1'b0;
        
        // Esperar bit de START (línea en bajo)
        wait (tx == 1'b0);
        
        // Captura del frame con muestreo mid-bit
        // Se muestrea en la mitad del intervalo de oversampling para mayor confiabilidad
        os_count = 0;
        bit_pos = 0;
        while (!tx_done_tick) begin
            @(posedge clk);
            if (baud_x16_tick) begin
                if (os_count == (OVERSAMPLE-1)) begin
                    os_count = 0;
                end else begin
                    os_count = os_count + 1;
                end
                if (os_count == (OVERSAMPLE/2)) begin
                    if (bit_pos < MAX_FRAME_BITS) begin
                        captured_frame[bit_pos] = tx;
                        bit_pos = bit_pos + 1;
                    end
                end
            end
        end
        
        // Cálculo de ciclos transcurridos desde el inicio del frame
        cycles_elapsed = total_cycles - frame_start_cycle;
        
        // Esperar estabilización en estado idle
        repeat (2) @(posedge clk);
        
        // Enmascarar frames según longitud (NONE=10 bits, EVEN/ODD=11 bits)
        if (frame_bits == FRAME_BITS_NONE) begin
            exp_masked = exp_frame & 11'h3FF; // 10 LSBs
            got_masked = captured_frame & 11'h3FF;
        end else begin
            exp_masked = exp_frame & 11'h7FF; // 11 bits
            got_masked = captured_frame & 11'h7FF;
        end
        
        // Verificación multi-criterio: bits capturados, contenido y timing
        test_count++;
        if (bit_pos != frame_bits) begin
            error_count++;
            $display("[FAIL] %s: bit count mismatch got=%0d exp=%0d", test_name, bit_pos, frame_bits);
        end else if (got_masked !== exp_masked) begin
            error_count++;
            $display("[FAIL] %s: frame mismatch got=%0h exp=%0h", test_name, got_masked, exp_masked);
        end else if (cycles_elapsed < exp_cycles || cycles_elapsed > exp_cycles + EXP_MARGIN_CYCLES) begin
            error_count++;
            $display("[FAIL] %s: timing mismatch got=%0d exp=%0d cycles", test_name, cycles_elapsed, exp_cycles);
        end else begin
            $display("[PASS] %s: frame=%0h data=%0h cycles=%0d", 
                     test_name, got_masked, data_val, cycles_elapsed);
        end
    endtask

    /**
     * @brief Captura y verifica frame usando interfaz FIFO
     * @details Similar a capture_and_verify, pero inicia la transmisión mediante
     * la señal write_o (dato disponible en FIFO) en lugar de tx_start. Verifica que
     * el DUT pulse read_en para consumir el dato antes de iniciar la transmisión.
     * 
     * IMPORTANTE: Con el estado S_LOAD agregado en uart_tx, hay 1 ciclo adicional
     * de latencia entre read_en y el inicio de transmisión (START bit). Esto permite
     * que la FIFO entregue el dato válido antes de que uart_tx lo capture.
     *
     * Timing esperado (con S_LOAD):
     * - Ciclo N:   TB activa write_o=1, uart_tx en S_IDLE
     * - Ciclo N+1: uart_tx genera read_en=1, transiciona a S_LOAD
     * - Ciclo N+2: uart_tx captura din, transiciona a S_START, tx→0 (START bit)
     *
     * @param exp_frame Frame esperado (10 u 11 bits según modo)
     * @param frame_bits Cantidad de bits del frame (10 para NONE, 11 para EVEN/ODD)
     * @param exp_cycles Ciclos de reloj esperados para el frame completo
     * @param data_val Valor de datos de 8 bits a transmitir
     * @param test_name Nombre descriptivo del caso de prueba
     */
    task automatic capture_and_verify_fifo(
        input [10:0] exp_frame,
        input int frame_bits,
        input int exp_cycles,
        input [7:0] data_val,
        input string test_name
    );
        reg [10:0] captured_frame;
        integer bit_pos;
        integer os_count;
        integer cycles_elapsed;
        reg [10:0] exp_masked;
        reg [10:0] got_masked;

        // Inicialización de variables locales
        captured_frame = '0;
        bit_pos = 0;
        din = data_val;

        // Esperar idle y activar interfaz FIFO
        wait (tx == 1'b1);
        @(posedge clk);
        write_o = 1'b1; // Señal: dato disponible en FIFO
        
        // Esperar handshake: DUT debe pulsar read_en para consumir
        wait (read_en == 1'b1);
        @(posedge clk);
        write_o = 1'b0; // Desactivar tras consumo

        // Esperar 1 ciclo adicional para estado S_LOAD
        // (uart_tx necesita este tiempo para que sync_fifo entregue dato válido)
        @(posedge clk);

        // Esperar inicio de transmisión (bit START)
        wait (tx == 1'b0);
        frame_start_cycle = total_cycles;

        // Muestreo mid-bit (mismo algoritmo que captura normal)
        os_count = 0;
        bit_pos = 0;
        while (!tx_done_tick) begin
            @(posedge clk);
            if (baud_x16_tick) begin
                if (os_count == (OVERSAMPLE-1)) begin
                    os_count = 0;
                end else begin
                    os_count = os_count + 1;
                end
                if (os_count == (OVERSAMPLE/2)) begin
                    if (bit_pos < MAX_FRAME_BITS) begin
                        captured_frame[bit_pos] = tx;
                        bit_pos = bit_pos + 1;
                    end
                end
            end
        end

        cycles_elapsed = total_cycles - frame_start_cycle;
        repeat (2) @(posedge clk);

        if (frame_bits == FRAME_BITS_NONE) begin
            exp_masked = exp_frame & 11'h3FF;
            got_masked = captured_frame & 11'h3FF;
        end else begin
            exp_masked = exp_frame & 11'h7FF;
            got_masked = captured_frame & 11'h7FF;
        end

        test_count++;
        if (bit_pos != frame_bits) begin
            error_count++;
            $display("[FAIL] %s(FIFO): bit count mismatch got=%0d exp=%0d", test_name, bit_pos, frame_bits);
        end else if (got_masked !== exp_masked) begin
            error_count++;
            $display("[FAIL] %s(FIFO): frame mismatch got=%0h exp=%0h", test_name, got_masked, exp_masked);
        end else if (cycles_elapsed < exp_cycles || cycles_elapsed > exp_cycles + EXP_MARGIN_CYCLES) begin
            error_count++;
            $display("[FAIL] %s(FIFO): timing mismatch got=%0d exp=%0d cycles", test_name, cycles_elapsed, exp_cycles);
        end else begin
            $display("[PASS] %s(FIFO): frame=%0h data=%0h cycles=%0d", test_name, got_masked, data_val, cycles_elapsed);
        end
    endtask

    // ========================================================================
    // Modelo dorado simple para construir el frame esperado (sin flags)
    // ========================================================================
    function automatic [10:0] build_expected_frame(input [7:0] data);
        logic parity_bit;
        logic parity_xor;
        begin
            parity_xor = ^data; // 1 si cantidad de '1' es impar
            case (TEST_MODE)
                1: parity_bit = parity_xor;       // EVEN
                2: parity_bit = ~parity_xor;      // ODD
                default: parity_bit = 1'b0;       // NONE (no usado)
            endcase
            if (TEST_MODE == 0) begin
                // 10 bits: [STOP|DATA(8)|START]
                build_expected_frame = {1'b0, 1'b1, data, 1'b0};
            end else begin
                // 11 bits: [STOP|PARITY|DATA(8)|START]
                build_expected_frame = {1'b1, parity_bit, data, 1'b0};
            end
        end
    endfunction

    // ========================================================================
    // Secuencia principal de pruebas
    // ========================================================================
    
    /**
     * @brief Bloque principal de ejecución de pruebas
     * @details Ejecuta la secuencia completa de pruebas según el modo seleccionado:
     * 1. Realiza reset del sistema
     * 2. Selecciona vectores de prueba según TEST_MODE
     * 3. Ejecuta casos smoke (básicos) y aleatorios
     * 4. Opcionalmente ejecuta pruebas FIFO si ENABLE_FIFO_MODE=1
     * 5. Genera reporte final con estadísticas
     */
    initial begin
        integer i;
        integer exp_cycles;
        string mode_name;
        
        do_reset();
        
        // Selección de modo de paridad y vectores de prueba
        case (TEST_MODE)
            0: begin
                mode_name = "NONE";
                exp_cycles = FRAME_BITS_NONE * OVERSAMPLE * TICKS_PER_OS;
                $display("========================================");
                $display("  Testing PARITY_NONE (frame_bits=%0d)", FRAME_BITS_NONE);
                $display("========================================");
                
                // Smoke vectors
                for (i = 0; i < NUM_SMOKE_NONE; i++) begin
                    capture_and_verify(
                        build_expected_frame(smoke_data_none[i]),
                        FRAME_BITS_NONE,
                        exp_cycles,
                        smoke_data_none[i],
                        $sformatf("NONE_SMOKE[%0d]", i)
                    );
                end
                
                // Random vectors
                for (i = 0; i < NUM_RANDOM_NONE; i++) begin
                    capture_and_verify(
                        build_expected_frame(random_data_none[i]),
                        FRAME_BITS_NONE,
                        exp_cycles,
                        random_data_none[i],
                        $sformatf("NONE_RND[%0d]", i)
                    );
                end
            end
            
            1: begin
                mode_name = "EVEN";
                exp_cycles = FRAME_BITS_EVEN * OVERSAMPLE * TICKS_PER_OS;
                $display("========================================");
                $display("  Testing PARITY_EVEN (frame_bits=%0d)", FRAME_BITS_EVEN);
                $display("========================================");
                
                for (i = 0; i < NUM_SMOKE_EVEN; i++) begin
                    capture_and_verify(
                        build_expected_frame(smoke_data_even[i]),
                        FRAME_BITS_EVEN,
                        exp_cycles,
                        smoke_data_even[i],
                        $sformatf("EVEN_SMOKE[%0d]", i)
                    );
                end
                
                for (i = 0; i < NUM_RANDOM_EVEN; i++) begin
                    capture_and_verify(
                        build_expected_frame(random_data_even[i]),
                        FRAME_BITS_EVEN,
                        exp_cycles,
                        random_data_even[i],
                        $sformatf("EVEN_RND[%0d]", i)
                    );
                end
            end
            
            2: begin
                mode_name = "ODD";
                exp_cycles = FRAME_BITS_ODD * OVERSAMPLE * TICKS_PER_OS;
                $display("========================================");
                $display("  Testing PARITY_ODD (frame_bits=%0d)", FRAME_BITS_ODD);
                $display("========================================");
                
                for (i = 0; i < NUM_SMOKE_ODD; i++) begin
                    capture_and_verify(
                        build_expected_frame(smoke_data_odd[i]),
                        FRAME_BITS_ODD,
                        exp_cycles,
                        smoke_data_odd[i],
                        $sformatf("ODD_SMOKE[%0d]", i)
                    );
                end
                
                for (i = 0; i < NUM_RANDOM_ODD; i++) begin
                    capture_and_verify(
                        build_expected_frame(random_data_odd[i]),
                        FRAME_BITS_ODD,
                        exp_cycles,
                        random_data_odd[i],
                        $sformatf("ODD_RND[%0d]", i)
                    );
                end
            end
            
            default: begin
                $display("[ERROR] Invalid TEST_MODE=%0d", TEST_MODE);
                $finish;
            end
        endcase
        
        // ====================================================================
        // Pruebas adicionales con interfaz FIFO
        // ====================================================================
        
        /**
         * @brief Verifica funcionamiento con interfaz FIFO externa
         * @details Ejecuta un subconjunto de casos (3 smoke + 3 random) usando
         * write_o/read_en en lugar de tx_start para iniciar transmisiones.
         * 
         * Nota: El estado S_LOAD en uart_tx agrega ~1 ciclo de latencia adicional
         * para sincronizar con la latencia de sync_fifo. Esto es correcto y esperado.
         * El testbench espera este ciclo adicional antes de comenzar la captura.
         */
        if (ENABLE_FIFO_MODE) begin
            integer j;
            $display("\n========================================");
            $display("Pruebas con FIFO");
            $display("========================================");
            case (TEST_MODE)
                0: begin
                    // Usar primeras 3 smoke y 3 random para brevedad
                    for (j = 0; j < 3; j++) begin
                        capture_and_verify_fifo(build_expected_frame(smoke_data_none[j]), FRAME_BITS_NONE,
                            FRAME_BITS_NONE * OVERSAMPLE * TICKS_PER_OS,
                            smoke_data_none[j], $sformatf("NONE_SMOKE[%0d]", j));
                    end
                    for (j = 0; j < 3 && j < NUM_RANDOM_NONE; j++) begin
                        capture_and_verify_fifo(build_expected_frame(random_data_none[j]), FRAME_BITS_NONE,
                            FRAME_BITS_NONE * OVERSAMPLE * TICKS_PER_OS,
                            random_data_none[j], $sformatf("NONE_RND[%0d]", j));
                    end
                end
                1: begin
                    for (j = 0; j < 3; j++) begin
                        capture_and_verify_fifo(build_expected_frame(smoke_data_even[j]), FRAME_BITS_EVEN,
                            FRAME_BITS_EVEN * OVERSAMPLE * TICKS_PER_OS,
                            smoke_data_even[j], $sformatf("EVEN_SMOKE[%0d]", j));
                    end
                    for (j = 0; j < 3 && j < NUM_RANDOM_EVEN; j++) begin
                        capture_and_verify_fifo(build_expected_frame(random_data_even[j]), FRAME_BITS_EVEN,
                            FRAME_BITS_EVEN * OVERSAMPLE * TICKS_PER_OS,
                            random_data_even[j], $sformatf("EVEN_RND[%0d]", j));
                    end
                end
                2: begin
                    for (j = 0; j < 3; j++) begin
                        capture_and_verify_fifo(build_expected_frame(smoke_data_odd[j]), FRAME_BITS_ODD,
                            FRAME_BITS_ODD * OVERSAMPLE * TICKS_PER_OS,
                            smoke_data_odd[j], $sformatf("ODD_SMOKE[%0d]", j));
                    end
                    for (j = 0; j < 3 && j < NUM_RANDOM_ODD; j++) begin
                        capture_and_verify_fifo(build_expected_frame(random_data_odd[j]), FRAME_BITS_ODD,
                            FRAME_BITS_ODD * OVERSAMPLE * TICKS_PER_OS,
                            random_data_odd[j], $sformatf("ODD_RND[%0d]", j));
                    end
                end
            endcase
        end

        // ====================================================================
        // Reporte final de resultados
        // ====================================================================
        
        $display("");
        $display("========================================");
        if (error_count == 0) begin
            $display("[PASS] Test UART TX (%s) completado: %0d casos, sin errores", mode_name, test_count);
        end else begin
            $display("[FAIL] Test UART TX (%s) completado: %0d casos, %0d errores", mode_name, test_count, error_count);
        end
        $display("========================================");
        $finish;
    end

endmodule
