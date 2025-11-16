`timescale 1ns/1ps
/*
 * Testbench para uart_packet_decoder.
 * Simula la ruta UART RX -> FIFO -> decodificador usando sync_fifo.
 * Cada escenario imprime el contenido de la FIFO y el estado del decoder.
 */
module tb_uart_packet_decoder;

    //! @brief Parámetros de simulación
    localparam CLK_PERIOD = 10;
    localparam FIFO_DEPTH = 8;

    //! @brief Señales de interfaz
    reg clk;
    reg rst;
    reg [7:0] uart_rx_data;
    reg uart_rx_valid;
    wire uart_rx_ready;

    //! @brief Señales internas y de DUT
    wire [7:0] alu_data;
    wire load_a;
    wire load_b;
    wire load_sel;
    wire exec_pulse;
    wire decoder_error;
    wire packet_complete;

    //! @brief Contadores de resultados
    integer checks_total;
    integer checks_ok;
    integer checks_fail;
    integer decoder_error_count;
    bit decoder_error_pending;

    //! @brief Señales del FIFO y del decodificador
    wire dec_rx_fifo_read_en;
    wire rx_fifo_read_en;
    wire rx_fifo_empty;
    wire rx_fifo_full;
    wire [7:0] rx_fifo_data;
    wire rx_fifo_data_valid;
    wire [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_level;

    assign uart_rx_ready = !rx_fifo_full; //>! Listo para recibir si la FIFO no está llena

    reg write_guard; //>! No admite lectura y escritura simultáneas

    //! @brief Instancia del FIFO de recepción
    sync_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(FIFO_DEPTH)
    ) rx_fifo (
        .clk(clk),
        .rst(rst),
        .write_en(uart_rx_valid && uart_rx_ready),
        .read_en(rx_fifo_read_en),
        .data_in(uart_rx_data),
        .data_out(rx_fifo_data),
        .data_valid(rx_fifo_data_valid),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty),
        .level(rx_fifo_level)
    );

    //! @brief Instancia del decodificador UART
    uart_packet_decoder #(
        .DATA_WIDTH(8)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_fifo_read_en(dec_rx_fifo_read_en),
        .rx_fifo_empty(rx_fifo_empty),
        .rx_fifo_data_valid(rx_fifo_data_valid),
        .rx_fifo_data(rx_fifo_data),
        .alu_data(alu_data),
        .load_a(load_a),
        .load_b(load_b),
        .load_sel(load_sel),
        .exec_pulse(exec_pulse),
        .decoder_error(decoder_error),
        .packet_complete(packet_complete)
    );

    //! @brief Generador de reloj
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //! @brief Secuencia principal de pruebas
    initial begin
        rst = 1;
        uart_rx_data = 8'h00;
        uart_rx_valid = 1'b0;
        checks_total = 0;
        checks_ok = 0;
        checks_fail = 0;
        write_guard = 1'b0;
        decoder_error_count = 0;
        decoder_error_pending = 1'b0;
        repeat (4) @(posedge clk);
        rst = 0;
        @(posedge clk);
        $display("[%0t] Reset liberado", $time);
        ejecutar_pruebas();
    end

    //! @brief Envía un byte a la FIFO simulada
    task automatic enviar_byte(input [7:0] valor);
        begin
            @(posedge clk);
            uart_rx_data  <= valor;
            uart_rx_valid <= 1'b1;
            @(posedge clk);
            while (!uart_rx_ready) @(posedge clk);
            uart_rx_valid <= 1'b0;
            mostrar_fifo($sformatf("byte 0x%02h añadido", valor));
        end
    endtask

    //! @brief Envía un paquete completo (STX, CMD, DATA, ETX) a la FIFO simulada   
    task automatic enviar_paquete(input [7:0] cmd, input [7:0] data);
        begin
            enviar_byte(8'h02);
            enviar_byte(cmd);
            enviar_byte(data);
            enviar_byte(8'h03);
        end
    endtask

    //! @brief Muestra el contenido válido de la FIFO
    task automatic mostrar_fifo(input string etiqueta);
        integer idx;
        integer ptr;
        begin
            $write("[%0t] %s -> nivel=%0d contenido válido: [", $time, etiqueta, rx_fifo_level);
            if (rx_fifo_level == 0) begin
                $write(" ");
            end else begin
                for (idx = 0; idx < rx_fifo_level; idx = idx + 1) begin
                    ptr = rx_fifo.rd_ptr + idx;
                    if (ptr >= FIFO_DEPTH) ptr = ptr - FIFO_DEPTH;
                    $write("%02h", rx_fifo.mem[ptr]);
                    if (idx != rx_fifo_level-1) $write(", ");
                end
            end
            $display("]");
        end
    endtask

    //! @brief Monitorea errores del decodificador
    always @(posedge decoder_error or posedge rst) begin
        if (rst) begin
            decoder_error_count <= 0;
            decoder_error_pending <= 1'b0;
        end else begin
            decoder_error_count <= decoder_error_count + 1;
            decoder_error_pending <= 1'b1;
            $display("[%0t] DECODER_ERROR estado=%0d byte_actual=0x%02h",
                     $time, dut.current_state, dut.current_rx_byte);
        end
    end

    //! @brief Monitorea finalización de paquetes
    always @(posedge packet_complete) begin
        $display("[%0t] PACKET_COMPLETE, cmd listo", $time);
    end

    reg read_pending; //>! Indica que se solicitó una lectura en el ciclo anterior

    //! @brief Lógica de control de lectura de la FIFO
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_guard  <= 1'b0;
            read_pending <= 1'b0;
        end else begin
            if (rx_fifo_data_valid && read_pending) begin
                $display("[%0t] Decoder consume -> dato=0x%02h (level=%0d)", $time, rx_fifo_data, rx_fifo_level);
                read_pending <= 1'b0;
            end else if (dec_rx_fifo_read_en && !write_guard) begin
                read_pending <= 1'b1;
            end

            write_guard <= (uart_rx_valid && uart_rx_ready);
        end
    end

    assign rx_fifo_read_en = dec_rx_fifo_read_en && !write_guard; //>! Evita lectura simultánea con escritura

    //! @brief Registra el resultado de un check
    task automatic registrar_check(input string desc, input bit ok);
        begin
            checks_total = checks_total + 1;
            if (ok) begin
                checks_ok = checks_ok + 1;
                $display("[CHECK OK ] %s", desc);
            end else begin
                checks_fail = checks_fail + 1;
                $display("[CHECK FAIL] %s", desc);
            end
        end
    endtask

    //! @brief Espera un pulso específico y verifica su valor
    task automatic esperar_pulso(input byte tipo, input [7:0] esperado);
        int ciclos;
        bit atendido;
        string etiqueta;
        begin
            ciclos = 0;
            atendido = 0;
            while (ciclos < 60 && !atendido) begin
                @(posedge clk);
                ciclos++;
                case (tipo)
                    "A": if (load_a) begin
                            atendido = 1;
                            etiqueta = $sformatf("LOAD_A valor 0x%0h", esperado);
                            registrar_check(etiqueta, alu_data === esperado);
                        end
                    "B": if (load_b) begin
                            atendido = 1;
                            etiqueta = $sformatf("LOAD_B valor 0x%0h", esperado);
                            registrar_check(etiqueta, alu_data === esperado);
                        end
                    "C": if (load_sel) begin
                            atendido = 1;
                            etiqueta = $sformatf("LOAD_OPCODE valor 0x%0h", esperado);
                            registrar_check(etiqueta, alu_data === esperado);
                        end
                    "E": if (exec_pulse) begin
                            atendido = 1;
                            registrar_check("EXEC pulse detectado", 1'b1);
                        end
                    default: ;
                endcase
            end
            if (!atendido) begin
                etiqueta = $sformatf("Timeout esperando pulso %s", tipo);
                registrar_check(etiqueta, 1'b0);
            end
        end
    endtask

    //! @brief Espera un error del decodificador
    task automatic esperar_error(input string etiqueta);
        int ciclos;
        bit atendido;
        begin
            ciclos = 0;
            atendido = 0;
            while (ciclos < 60 && !atendido) begin
                if (decoder_error_pending) begin
                    atendido = 1;
                    decoder_error_pending = 1'b0;
                end else begin
                    @(posedge clk);
                    ciclos++;
                end
            end
            registrar_check(etiqueta, atendido);
        end
    endtask

    //! @brief Ejecuta la secuencia completa de pruebas
    task automatic ejecutar_pruebas;
        begin
            $display("=== Caso 1: Cargar buffers sin ejecutar ===");
            enviar_paquete(8'h43, 8'h20); 
            enviar_paquete(8'h41, 8'h12); 
            enviar_paquete(8'h42, 8'h05); 
            @(posedge clk);

            $display("=== Caso 2: Ejecutar (orden S,A,B) ===");
            enviar_paquete(8'h45, 8'h00);
            esperar_pulso("E", 8'h00);
            esperar_pulso("C", 8'h20);
            esperar_pulso("A", 8'h12);
            esperar_pulso("B", 8'h05);

            $display("=== Caso 3: comando inválido ===");
            enviar_byte(8'h02);
            enviar_byte(8'h44);
            enviar_byte(8'h99);
            enviar_byte(8'h03);
            esperar_error("Error por comando inválido");

            $display("=== Caso 4: ETX erróneo ===");
            enviar_byte(8'h02);
            enviar_byte(8'h43);
            enviar_byte(8'h77);
            enviar_byte(8'h00);
            esperar_error("Error por ETX inválido");

            $display("=== Caso 5: Nueva configuración y ejecución ===");
            enviar_paquete(8'h43, 8'h26); 
            enviar_paquete(8'h41, 8'hAA); 
            enviar_paquete(8'h42, 8'h55); 
            enviar_paquete(8'h45, 8'h00);
            esperar_pulso("E", 8'h00);
            esperar_pulso("C", 8'h26);
            esperar_pulso("A", 8'hAA);
            esperar_pulso("B", 8'h55);

            mostrar_resumen();
            $finish;
        end
    endtask

    //! @brief Muestra un resumen final de la simulación
    task automatic mostrar_resumen;
        begin
            $display("=== RESUMEN ===");
            $display("Checks totales : %0d", checks_total);
            $display("Checks OK      : %0d", checks_ok);
            $display("Checks FAIL    : %0d", checks_fail);
            $display("decoder_error  : %0d eventos", decoder_error_count);
            if (checks_fail == 0) begin
                $display("Estado FINAL: TODAS LAS PRUEBAS PASARON");
            end else begin
                $display("Estado FINAL: %0d prueba(s) fallaron", checks_fail);
            end
        end
    endtask

endmodule
