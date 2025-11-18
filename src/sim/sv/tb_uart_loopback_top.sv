`timescale 1ns/1ps

/**
 * @file tb_uart_loopback_top.sv
 * @brief Testbench para verificar el módulo uart_loopback_top
 *
 * @details Este testbench simula el comportamiento completo del sistema de loopback UART:
 * - Envía bytes por la línea RX (simulando entrada desde PC)
 * - Verifica que los mismos bytes se reciban por TX (salida hacia PC)
 * - Monitorea la actividad de los LEDs (rx_done y tx_done)
 * - Reporta errores si los datos no coinciden
 */

module tb_uart_loopback_top;

    // ========================================================================
    // Parámetros del testbench
    // ========================================================================
    localparam int CLOCK_FREQ = 12_000_000;
    localparam int BAUD_RATE  = 9600;
    localparam int DATA_BITS  = 8;

    // Periodo de bit UART en ns
    localparam real BIT_PERIOD_NS = 1e9 / BAUD_RATE;  // ~104166.67 ns

    // Número de bytes a probar
    localparam int N_BYTES = 8;

    // ========================================================================
    // Señales del DUT
    // ========================================================================
    logic clk = 0;
    logic rst = 1;

    logic rx;
    logic tx;

    logic led0;
    logic led1;

    // ========================================================================
    // Instancia del DUT
    // ========================================================================
    uart_loopback_top #(
        .DATA_BITS   (DATA_BITS),
        .PARITY      (uart_parity_pkg::PARITY_NONE),
        .OVERSAMPLE  (16),
        .CLOCK_FREQ  (CLOCK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .FIFO_DEPTH  (32)
    ) dut (
        .clk  (clk),
        .rst  (rst),
        .rx   (rx),
        .tx   (tx),
        .led0 (led0),
        .led1 (led1)
    );

    // ========================================================================
    // Generación de reloj 12 MHz
    // ========================================================================
    always #41.666 clk = ~clk;  // periodo ~83.333 ns

    // ========================================================================
    // Tareas auxiliares
    // ========================================================================
    
    /**
     * @brief Envía un byte por la línea RX (simulando PC → FPGA)
     * @param data Byte a transmitir
     * @details Formato: 1 start bit, 8 data bits (LSB primero), 1 stop bit
     */
    task automatic uart_send_byte(input [7:0] data);
        integer i;
        begin
            $display("[%0t] Enviando byte: 0x%02h", $time, data);
            
            // START bit (0)
            rx = 1'b0;
            #(BIT_PERIOD_NS);

            // DATA bits (LSB primero)
            for (i = 0; i < 8; i++) begin
                rx = data[i];
                #(BIT_PERIOD_NS);
            end

            // STOP bit (1)
            rx = 1'b1;
            #(BIT_PERIOD_NS);
        end
    endtask

    /**
     * @brief Recibe un byte desde TX (simulando FPGA → PC)
     * @param data Byte recibido
     * @details Detecta start bit y samplea en el centro de cada bit
     */
    task automatic uart_read_byte(output [7:0] data);
        integer i;
        begin
            // Esperar a que TX esté en idle (alto)
            wait(tx === 1'b1);
            
            // Esperar transición a START (bajada a 0)
            @(negedge tx);
            $display("[%0t] Detectado START bit en TX", $time);

            // Ir al centro del bit de start
            #(BIT_PERIOD_NS/2.0);

            // Leer 8 bits de datos
            for (i = 0; i < 8; i++) begin
                #(BIT_PERIOD_NS);
                data[i] = tx;
            end

            // Consumir STOP bit
            #(BIT_PERIOD_NS);
            
            $display("[%0t] Recibido byte: 0x%02h", $time, data);
        end
    endtask

    // ========================================================================
    // Monitor de LEDs
    // ========================================================================
    always @(posedge led0) begin
        $display("[%0t] LED0 encendido (rx_done)", $time);
    end

    always @(posedge led1) begin
        $display("[%0t] LED1 encendido (tx_done)", $time);
    end

    // ========================================================================
    // Proceso principal de prueba
    // ========================================================================
    byte tx_vec [N_BYTES-1:0];  // Bytes a enviar
    byte rx_vec [N_BYTES-1:0];  // Bytes recibidos
    int  errors;
    
    initial begin
        // Configuración de VCD para visualización
        $dumpfile("tb_uart_loopback_top.vcd");
        $dumpvars(0, tb_uart_loopback_top);
        
        // Inicialización
        rx = 1'b1;  // línea idle
        errors = 0;

        // Definir patrones de prueba
        tx_vec[0] = 8'h55;  // 01010101
        tx_vec[1] = 8'hAA;  // 10101010
        tx_vec[2] = 8'h00;  // 00000000
        tx_vec[3] = 8'hFF;  // 11111111
        tx_vec[4] = 8'h0F;  // 00001111
        tx_vec[5] = 8'hF0;  // 11110000
        tx_vec[6] = 8'h3C;  // 00111100
        tx_vec[7] = 8'hC3;  // 11000011

        $display("========================================");
        $display("UART Loopback Top Testbench");
        $display("========================================");
        $display("Parámetros:");
        $display("  Clock:     %0d Hz", CLOCK_FREQ);
        $display("  Baudrate:  %0d bps", BAUD_RATE);
        $display("  Bits:      %0d", DATA_BITS);
        $display("  Bit time:  %.2f ns", BIT_PERIOD_NS);
        $display("========================================\n");

        // Reset del sistema
        $display("[%0t] Aplicando reset...", $time);
        rst = 0;
        repeat(20) @(posedge clk);
        rst = 1;
        repeat(100) @(posedge clk);
        $display("[%0t] Reset completado\n", $time);

        // Transmitir y recibir en paralelo
        fork
            // Proceso de transmisión (PC → FPGA)
            begin
                for (int i = 0; i < N_BYTES; i++) begin
                    uart_send_byte(tx_vec[i]);
                    // Espacio entre bytes
                    #(BIT_PERIOD_NS * 2);
                end
            end

            // Proceso de recepción (FPGA → PC)
            begin
                for (int i = 0; i < N_BYTES; i++) begin
                    uart_read_byte(rx_vec[i]);
                end
            end
        join

        // Esperar un poco más para asegurar que todo se procese
        repeat(1000) @(posedge clk);

        // ====================================================================
        // Verificación de resultados
        // ====================================================================
        $display("\n========================================");
        $display("VERIFICACION DE RESULTADOS");
        $display("========================================");
        
        for (int i = 0; i < N_BYTES; i++) begin
            if (tx_vec[i] !== rx_vec[i]) begin
                $display("[ERROR] Byte %0d: Esperado 0x%02h, Recibido 0x%02h", 
                         i, tx_vec[i], rx_vec[i]);
                errors++;
            end else begin
                $display("[OK]    Byte %0d: 0x%02h", i, tx_vec[i]);
            end
        end

        $display("========================================");
        if (errors == 0) begin
            $display("[PASS] PRUEBA EXITOSA: Todos los bytes coinciden");
        end else begin
            $display("[FAIL] PRUEBA FALLIDA: %0d errores detectados", errors);
        end
        $display("========================================\n");

        // Finalizar simulación
        repeat(100) @(posedge clk);
        $finish;
    end

    // ========================================================================
    // Timeout de seguridad
    // ========================================================================
    initial begin
        #(BIT_PERIOD_NS * N_BYTES * 20);  // Timeout generoso
        $display("\n[ERROR] Timeout de simulación alcanzado");
        $finish;
    end

endmodule
