`include "alu_timescale.vh"

/**
 * @file tb_uart_baudrate_gen.sv
 * @brief Testbench para el generador de baudrate UART
 * 
 * @details Verifica el funcionamiento del generador de baudrate para 9600 bps
 * con un reloj de 12 MHz. El testbench mide los períodos de los ticks generados
 * y verifica que estén dentro del rango esperado.
 */

module tb_uart_baudrate_gen;

    // Parámetros del testbench
    localparam integer CLOCK_FREQ = 12_000_000;
    localparam integer BAUD_RATE = 9600;
    localparam integer OVERSAMPLE = 16;
    localparam integer CLOCK_PERIOD_NS = 1_000_000_000 / CLOCK_FREQ; // ~83.33 ns
    
    // Señales del testbench
    logic clk;
    logic rst_n;
    logic baud_tick;
    logic baud_x16_tick;
    
    // Variables para medición
    realtime last_baud_tick_time = 0;
    realtime last_baud_x16_tick_time = 0;
    int baud_tick_count = 0;
    int baud_x16_tick_count = 0;
    realtime baud_period_measured = 0;
    realtime baud_x16_period_measured = 0;
    
    // Valores esperados
    localparam real EXPECTED_BAUD_PERIOD_NS = 1_000_000_000.0 / BAUD_RATE; // ~104166.67 ns
    localparam real EXPECTED_BAUD_X16_PERIOD_NS = 1_000_000_000.0 / (BAUD_RATE * OVERSAMPLE); // ~6510.42 ns
    localparam real TOLERANCE_PERCENT = 1.0; // 1% de tolerancia
    
    // Instanciación del DUT (Device Under Test)
    uart_baudrate_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .baud_tick(baud_tick),
        .baud_x16_tick(baud_x16_tick)
    );
    
    // Generación del reloj
    initial begin
        clk = 1'b0;
        forever #(CLOCK_PERIOD_NS/2) clk = ~clk;
    end
    
    // Secuencia de reset y test
    initial begin
        $display("=== Iniciando testbench para UART Baudrate Generator ===");
        $display("Clock Period: %0.2f ns", real'(CLOCK_PERIOD_NS));
        $display("Expected Baud Period: %0.2f ns", EXPECTED_BAUD_PERIOD_NS);
        $display("Expected Baud x16 Period: %0.2f ns", EXPECTED_BAUD_X16_PERIOD_NS);
        
        // Reset inicial
        rst_n = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        
        // Esperar a que se estabilice
        repeat(100) @(posedge clk);
        
        // Ejecutar mediciones
        fork
            measure_baud_tick();
            measure_baud_x16_tick();
        join
        
        // Esperar suficientes ticks para tener mediciones precisas
        wait(baud_tick_count >= 10 && baud_x16_tick_count >= 100);
        
        // Mostrar resultados y verificar
        show_results();
        verify_results();
        
        $display("=== Testbench completado ===");
        $finish;
    end
    
    // Tarea para medir el período del baud_tick
    task automatic measure_baud_tick();
        forever @(posedge baud_tick) begin
            if (baud_tick_count > 0) begin
                baud_period_measured = $realtime - last_baud_tick_time;
            end
            last_baud_tick_time = $realtime;
            baud_tick_count++;
            
            if (baud_tick_count <= 5) begin
                $display("Baud tick #%0d at time %0.2f ns", baud_tick_count, $realtime);
            end
        end
    endtask
    
    // Tarea para medir el período del baud_x16_tick
    task automatic measure_baud_x16_tick();
        forever @(posedge baud_x16_tick) begin
            if (baud_x16_tick_count > 0) begin
                baud_x16_period_measured = $realtime - last_baud_x16_tick_time;
            end
            last_baud_x16_tick_time = $realtime;
            baud_x16_tick_count++;
            
            if (baud_x16_tick_count <= 10) begin
                $display("Baud x16 tick #%0d at time %0.2f ns", baud_x16_tick_count, $realtime);
            end
        end
    endtask
    
    // Mostrar resultados de las mediciones
    task show_results();
        real baud_freq_measured = 1_000_000_000.0 / baud_period_measured;
        real baud_x16_freq_measured = 1_000_000_000.0 / baud_x16_period_measured;
        
        $display("\n=== RESULTADOS DE MEDICIÓN ===");
        $display("Baud Tick:");
        $display("  Período esperado: %0.2f ns", EXPECTED_BAUD_PERIOD_NS);
        $display("  Período medido:   %0.2f ns", baud_period_measured);
        $display("  Frecuencia esperada: %0.2f Hz", real'(BAUD_RATE));
        $display("  Frecuencia medida:   %0.2f Hz", baud_freq_measured);
        $display("  Error: %0.3f%%", abs((baud_period_measured - EXPECTED_BAUD_PERIOD_NS) / EXPECTED_BAUD_PERIOD_NS * 100));
        
        $display("\nBaud x16 Tick:");
        $display("  Período esperado: %0.2f ns", EXPECTED_BAUD_X16_PERIOD_NS);
        $display("  Período medido:   %0.2f ns", baud_x16_period_measured);
        $display("  Frecuencia esperada: %0.2f Hz", real'(BAUD_RATE * OVERSAMPLE));
        $display("  Frecuencia medida:   %0.2f Hz", baud_x16_freq_measured);
        $display("  Error: %0.3f%%", abs((baud_x16_period_measured - EXPECTED_BAUD_X16_PERIOD_NS) / EXPECTED_BAUD_X16_PERIOD_NS * 100));
        
        $display("\nContadores:");
        $display("  Baud ticks: %0d", baud_tick_count);
        $display("  Baud x16 ticks: %0d", baud_x16_tick_count);
        $display("  Ratio x16/baud: %0.2f (esperado: 16.0)", real'(baud_x16_tick_count) / real'(baud_tick_count));
    endtask
    
    // Verificar que los resultados están dentro de la tolerancia
    task verify_results();
        real baud_error = abs((baud_period_measured - EXPECTED_BAUD_PERIOD_NS) / EXPECTED_BAUD_PERIOD_NS * 100);
        real baud_x16_error = abs((baud_x16_period_measured - EXPECTED_BAUD_X16_PERIOD_NS) / EXPECTED_BAUD_X16_PERIOD_NS * 100);
        
        $display("\n=== VERIFICACIÓN ===");
        
        if (baud_error <= TOLERANCE_PERCENT) begin
            $display("✓ PASS: Baud tick dentro de tolerancia (%0.3f%% <= %0.1f%%)", baud_error, TOLERANCE_PERCENT);
        end else begin
            $display("✗ FAIL: Baud tick fuera de tolerancia (%0.3f%% > %0.1f%%)", baud_error, TOLERANCE_PERCENT);
        end
        
        if (baud_x16_error <= TOLERANCE_PERCENT) begin
            $display("✓ PASS: Baud x16 tick dentro de tolerancia (%0.3f%% <= %0.1f%%)", baud_x16_error, TOLERANCE_PERCENT);
        end else begin
            $display("✗ FAIL: Baud x16 tick fuera de tolerancia (%0.3f%% > %0.1f%%)", baud_x16_error, TOLERANCE_PERCENT);
        end
        
        // Verificar relación entre ticks
        real ratio = real'(baud_x16_tick_count) / real'(baud_tick_count);
        if (abs(ratio - 16.0) <= 0.1) begin
            $display("✓ PASS: Ratio x16/baud correcto (%0.2f ≈ 16.0)", ratio);
        end else begin
            $display("✗ FAIL: Ratio x16/baud incorrecto (%0.2f ≠ 16.0)", ratio);
        end
    endtask
    
    // Función auxiliar para valor absoluto
    function real abs(real x);
        return (x >= 0) ? x : -x;
    endfunction

endmodule