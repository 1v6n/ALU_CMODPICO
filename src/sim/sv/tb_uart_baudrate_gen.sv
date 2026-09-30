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
    parameter integer CLOCK_FREQ = 12_000_000;
    parameter integer BAUD_RATE = 9600;
    parameter integer OVERSAMPLE = 16;
    parameter real CLOCK_PERIOD_NS = 1_000_000_000.0 / CLOCK_FREQ; // ~83.33 ns
    
    // Señales del testbench
    reg clk;
    reg rst;
    wire baud_tick;
    wire baud_x16_tick;
    
    // Variables para medición
    realtime last_baud_tick_time;
    realtime last_baud_x16_tick_time;
    integer baud_tick_count;
    integer baud_x16_tick_count;
    realtime baud_period_measured;
    realtime baud_x16_period_measured;
    
    // Valores esperados
    parameter real EXPECTED_BAUD_PERIOD_NS = 1_000_000_000.0 / BAUD_RATE; // ~104166.67 ns
    parameter real EXPECTED_BAUD_X16_PERIOD_NS = 1_000_000_000.0 / (BAUD_RATE * OVERSAMPLE); // ~6510.42 ns
    parameter real TOLERANCE_PERCENT = 1.0; // 1% de tolerancia
    
    // Instanciación del DUT (Device Under Test)
    uart_baudrate_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .baud_tick(baud_tick),
        .baud_x16_tick(baud_x16_tick)
    );
    
    // Generación del reloj
    initial begin
        clk = 1'b0;
        forever #(CLOCK_PERIOD_NS/2) clk = ~clk;
    end
    
    // Inicialización de variables
    initial begin
        last_baud_tick_time = 0;
        last_baud_x16_tick_time = 0;
        baud_tick_count = 0;
        baud_x16_tick_count = 0;
        baud_period_measured = 0;
        baud_x16_period_measured = 0;
    end
    
    // Secuencia de reset y test
    initial begin
        $display("=== Iniciando testbench para UART Baudrate Generator ===");
        $display("Clock Period: %0.2f ns", CLOCK_PERIOD_NS);
        $display("Expected Baud Period: %0.2f ns", EXPECTED_BAUD_PERIOD_NS);
        $display("Expected Baud x16 Period: %0.2f ns", EXPECTED_BAUD_X16_PERIOD_NS);
        
        // Reset inicial
        rst = 1'b1;
        repeat(10) @(posedge clk);
        rst = 1'b0;
        
        // Esperar a que se estabilice
        repeat(100) @(posedge clk);
        
        // Ejecutar mediciones
        fork
            measure_baud_tick();
            measure_baud_x16_tick();
        join_none
        
        // Esperar suficientes ticks para tener mediciones precisas
        wait(baud_tick_count >= 10 && baud_x16_tick_count >= 100);
        
        // Mostrar resultados y verificar
        show_results();
        verify_results();
        
        $display("=== Testbench completado ===");
        $finish;
    end
    
    // Tarea para medir el período del baud_tick
    task measure_baud_tick;
        begin
            forever @(posedge baud_tick) begin
                if (baud_tick_count > 0) begin
                    baud_period_measured = $realtime - last_baud_tick_time;
                end
                last_baud_tick_time = $realtime;
                baud_tick_count = baud_tick_count + 1;
                
                if (baud_tick_count <= 5) begin
                    $display("Baud tick #%0d at time %0.2f ns", baud_tick_count, $realtime);
                end
            end
        end
    endtask
    
    // Tarea para medir el período del baud_x16_tick
    task measure_baud_x16_tick;
        begin
            forever @(posedge baud_x16_tick) begin
                if (baud_x16_tick_count > 0) begin
                    baud_x16_period_measured = $realtime - last_baud_x16_tick_time;
                end
                last_baud_x16_tick_time = $realtime;
                baud_x16_tick_count = baud_x16_tick_count + 1;
                
                if (baud_x16_tick_count <= 10) begin
                    $display("Baud x16 tick #%0d at time %0.2f ns", baud_x16_tick_count, $realtime);
                end
            end
        end
    endtask
    
    // Variables auxiliares para cálculos
    real baud_freq_measured;
    real baud_x16_freq_measured;
    real baud_error;
    real baud_x16_error;
    real ratio;
    
    // Mostrar resultados de las mediciones
    task show_results;
        begin
            baud_freq_measured = 1_000_000_000.0 / baud_period_measured;
            baud_x16_freq_measured = 1_000_000_000.0 / baud_x16_period_measured;
            
            $display("\n=== RESULTADOS DE MEDICION ===");
            $display("Baud Tick:");
            $display("  Periodo esperado: %0.2f ns", EXPECTED_BAUD_PERIOD_NS);
            $display("  Periodo medido:   %0.2f ns", baud_period_measured);
            $display("  Frecuencia esperada: %0.2f Hz", $itor(BAUD_RATE));
            $display("  Frecuencia medida:   %0.2f Hz", baud_freq_measured);
            $display("  Error: %0.3f%%", abs((baud_period_measured - EXPECTED_BAUD_PERIOD_NS) / EXPECTED_BAUD_PERIOD_NS * 100));
            
            $display("\nBaud x16 Tick:");
            $display("  Periodo esperado: %0.2f ns", EXPECTED_BAUD_X16_PERIOD_NS);
            $display("  Periodo medido:   %0.2f ns", baud_x16_period_measured);
            $display("  Frecuencia esperada: %0.2f Hz", $itor(BAUD_RATE * OVERSAMPLE));
            $display("  Frecuencia medida:   %0.2f Hz", baud_x16_freq_measured);
            $display("  Error: %0.3f%%", abs((baud_x16_period_measured - EXPECTED_BAUD_X16_PERIOD_NS) / EXPECTED_BAUD_X16_PERIOD_NS * 100));
            
            $display("\nContadores:");
            $display("  Baud ticks: %0d", baud_tick_count);
            $display("  Baud x16 ticks: %0d", baud_x16_tick_count);
            $display("  Ratio x16/baud: %0.2f (esperado: 16.0)", $itor(baud_x16_tick_count) / $itor(baud_tick_count));
        end
    endtask
    
    // Verificar que los resultados están dentro de la tolerancia
    task verify_results;
        begin
            baud_error = abs((baud_period_measured - EXPECTED_BAUD_PERIOD_NS) / EXPECTED_BAUD_PERIOD_NS * 100);
            baud_x16_error = abs((baud_x16_period_measured - EXPECTED_BAUD_X16_PERIOD_NS) / EXPECTED_BAUD_X16_PERIOD_NS * 100);
            
            $display("\n=== VERIFICACION ===");
            
            if (baud_error <= TOLERANCE_PERCENT) begin
                $display("PASS: Baud tick dentro de tolerancia (%0.3f%% <= %0.1f%%)", baud_error, TOLERANCE_PERCENT);
            end else begin
                $display("FAIL: Baud tick fuera de tolerancia (%0.3f%% > %0.1f%%)", baud_error, TOLERANCE_PERCENT);
            end
            
            if (baud_x16_error <= TOLERANCE_PERCENT) begin
                $display("PASS: Baud x16 tick dentro de tolerancia (%0.3f%% <= %0.1f%%)", baud_x16_error, TOLERANCE_PERCENT);
            end else begin
                $display("FAIL: Baud x16 tick fuera de tolerancia (%0.3f%% > %0.1f%%)", baud_x16_error, TOLERANCE_PERCENT);
            end
            
            // Verificar relación entre ticks
            ratio = $itor(baud_x16_tick_count) / $itor(baud_tick_count);
            if (abs(ratio - 16.0) <= 0.1) begin
                $display("PASS: Ratio x16/baud correcto (%0.2f vs 16.0)", ratio);
            end else begin
                $display("FAIL: Ratio x16/baud incorrecto (%0.2f vs 16.0)", ratio);
            end
        end
    endtask
    
    // Función auxiliar para valor absoluto
    function real abs(real x);
        return (x >= 0) ? x : -x;
    endfunction

endmodule
