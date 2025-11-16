`timescale 1ns/1ps

/*
 * @file tb_sync_fifo.sv
 * @brief Banco de pruebas autocontenido para verificar la FIFO sincronizada con patrones básicos.
 * Ejecuta inserciones, extracciones, lecturas/escrituras simultáneas y casos de underflow forzado.
 */

//! @brief Testbench principal que ejercita la FIFO con múltiples escenarios.
module tb_sync_fifo;
    localparam DATA_WIDTH = 8;
    localparam DEPTH      = 4;

    reg clk;
    reg rst;
    reg write_en;
    reg read_en;
    reg [DATA_WIDTH-1:0] data_in;

    wire [DATA_WIDTH-1:0] data_out;
    wire data_valid;
    wire full;
    wire empty;
    wire [$clog2(DEPTH+1)-1:0] level;

    integer errores;
    integer lecturas_ok;
    integer tests_totales;
    integer tests_ok;
    integer tests_fail;

    //! @brief Registra el resultado de cada comprobación individual.
    task automatic registrar_test(input string descripcion, input bit exito);
        begin
            tests_totales = tests_totales + 1;
            if (exito) begin
                tests_ok = tests_ok + 1;
                $display("[TEST OK ] %s", descripcion);
            end else begin
                tests_fail = tests_fail + 1;
                $display("[TEST FAIL] %s", descripcion);
            end
        end
    endtask

    //! @brief Utilidad para mostrar flags, contenido lógico y RAM interna de la FIFO.
    task automatic mostrar_estado(input string etiqueta);
        int idx;
        int ptr;
        begin
            $display("[%0t] %s", $time, etiqueta);
            $display("  level=%0d empty=%0b full=%0b data_out=%0h data_valid=%0b",
                     level, empty, full, data_out, data_valid);

            if (level == 0) begin
                $display("  contenido válido: []");
            end else begin
                $write("  contenido válido: [");
                for (idx = 0; idx < level; idx = idx + 1) begin
                    ptr = dut.rd_ptr + idx;
                    if (ptr >= DEPTH) ptr = ptr - DEPTH;
                    $write("%0h", dut.mem[ptr]);
                    if (idx != level-1) $write(", ");
                end
                $display("]");
            end

            $write("  memoria cruda: [");
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                $write("%0h", dut.mem[idx]);
                if (idx != DEPTH-1) $write(", ");
            end
            $display("]");
        end
    endtask

    //! @brief Instancia de la DUT: FIFO síncrona parametrizable.
    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .write_en(write_en),
        .read_en(read_en),
        .data_in(data_in),
        .data_out(data_out),
        .data_valid(data_valid),
        .full(full),
        .empty(empty),
        .level(level)
    );

    //! @brief Generación del reloj de simulación (100 MHz).
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //! @brief Reset y condición inicial del banco de pruebas.
    initial begin
        rst = 1'b1;
        write_en = 1'b0;
        read_en  = 1'b0;
        data_in  = '0;
        errores = 0;
        lecturas_ok = 0;
        tests_totales = 0;
        tests_ok = 0;
        tests_fail = 0;
        repeat (3) @(posedge clk);
        rst = 1'b0;
    end

    //! @brief Inserta un valor en la FIFO esperando espacio disponible.
    task automatic push_byte(input [DATA_WIDTH-1:0] valor);
        string etiqueta;
        begin
            @(negedge clk);
            while (full) @(negedge clk);
            data_in  <= valor;
            write_en <= 1'b1;
            @(negedge clk);
            write_en <= 1'b0;
            data_in  <= '0;
            etiqueta = $sformatf("push 0x%0h completado", valor);
            mostrar_estado(etiqueta);
        end
    endtask

    //! @brief Extrae y compara un valor esperado desde la FIFO.
    task automatic pop_and_check(input [DATA_WIDTH-1:0] esperado);
        string etiqueta;
        begin
            @(negedge clk);
            while (empty) @(negedge clk);
            read_en <= 1'b1;
            @(posedge clk);
            #1;
            if (data_valid !== 1'b1 || data_out !== esperado) begin
                $display("ERROR: Esperado %0h, recibido %0h (valid=%0b)", esperado, data_out, data_valid);
                errores = errores + 1;
                registrar_test($sformatf("Lectura de 0x%0h", esperado), 1'b0);
            end else begin
                lecturas_ok = lecturas_ok + 1;
                registrar_test($sformatf("Lectura de 0x%0h", esperado), 1'b1);
            end
            @(negedge clk);
            read_en <= 1'b0;
            etiqueta = $sformatf("pop 0x%0h verificado", esperado);
            mostrar_estado(etiqueta);
        end
    endtask

    //! @brief Secuencia principal de estímulos para verificar funcionamiento básico.
    initial begin
        @(negedge rst);
        @(posedge clk);

        // TEST: Verificar estado tras reset
        if (!empty || full) begin
            $display("ERROR: Bandera incorrecta tras reset. empty=%0b full=%0b", empty, full);
            errores = errores + 1;
            registrar_test("Estado tras reset", 1'b0);
        end else begin
            registrar_test("Estado tras reset", 1'b1);
        end
        mostrar_estado("Estado tras reset");

        // TEST: Llenar FIFO
        push_byte(8'h11);
        push_byte(8'h22);
        push_byte(8'h33);
        push_byte(8'h44);
        @(posedge clk);
        if (!full) begin
            $display("ERROR: FIFO debería estar lleno. level=%0d", level);
            errores = errores + 1;
            registrar_test("FIFO lleno tras cuatro inserciones", 1'b0);
        end else begin
            registrar_test("FIFO lleno tras cuatro inserciones", 1'b1);
        end
        mostrar_estado("FIFO lleno tras 4 inserciones");

        // TEST: Vaciar y comprobar orden
        pop_and_check(8'h11);
        pop_and_check(8'h22);
        pop_and_check(8'h33);
        pop_and_check(8'h44);
        @(posedge clk);
        if (!empty || full) begin
            $display("ERROR: Bandera incorrecta tras vaciar. empty=%0b full=%0b", empty, full);
            errores = errores + 1;
            registrar_test("FIFO vacio tras drenado", 1'b0);
        end else begin
            registrar_test("FIFO vacio tras drenado", 1'b1);
        end
        mostrar_estado("FIFO vacio tras drenado");

        // TEST: Probar lectura y escritura simultánea
        push_byte(8'hAA);
        @(negedge clk);
        while (full) @(negedge clk);
        data_in  <= 8'hBB;
        write_en <= 1'b1;
        read_en  <= 1'b1;
        @(posedge clk);
        #1;
        if (data_valid !== 1'b1 || data_out !== 8'hAA) begin
            $display("ERROR: Fallo en operación simultánea. data_out=%0h", data_out);
            errores = errores + 1;
            registrar_test("Lectura durante operación simultánea", 1'b0);
        end else begin
            lecturas_ok = lecturas_ok + 1;
            registrar_test("Lectura durante operación simultánea", 1'b1);
        end
        @(negedge clk);
        write_en <= 1'b0;
        read_en  <= 1'b0;
        data_in  <= '0;
        mostrar_estado("Lectura y escritura simultaneas completadas");
        pop_and_check(8'hBB);

        // TEST: Intento de lectura con FIFO vacío
        @(negedge clk);
        read_en <= 1'b1;
        @(posedge clk);
        #1;
        if (data_valid !== 1'b0) begin
            $display("ERROR: data_valid no debe activarse cuando el FIFO está vacío");
            errores = errores + 1;
            registrar_test("Lectura con FIFO vacío", 1'b0);
        end else begin
            registrar_test("Lectura con FIFO vacío", 1'b1);
        end
        @(negedge clk);
        read_en <= 1'b0;
        mostrar_estado("Intento de lectura con FIFO vacío");

        @(posedge clk);
        if (errores == 0) begin
            $display("Prueba completada SIN errores (%0d lecturas verificadas)", lecturas_ok);
        end else begin
            $display("Prueba completada con %0d error(es)", errores);
        end
        $display("Resumen de tests -> Total: %0d | OK: %0d | FAIL: %0d",
                 tests_totales, tests_ok, tests_fail);
        $finish;
    end

endmodule
