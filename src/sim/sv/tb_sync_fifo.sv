`timescale 1ns/1ps

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

    // Utilidad: imprime estado, contenido lógico y RAM interna del FIFO
    task automatic mostrar_estado(input string etiqueta);
        int idx;
        int ptr;
        begin
            $display("[%0t] %s", $time, etiqueta);
            $display("  level=%0d empty=%0b full=%0b data_out=%0h data_valid=%0b",
                     level, empty, full, data_out, data_valid);

            // Mostrar únicamente los elementos válidos según puntero de lectura
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

            // Mostrar también la RAM cruda para depuración
            $write("  memoria cruda: [");
            for (idx = 0; idx < DEPTH; idx = idx + 1) begin
                $write("%0h", dut.mem[idx]);
                if (idx != DEPTH-1) $write(", ");
            end
            $display("]");
        end
    endtask

    // Instancia del FIFO bajo prueba
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

    // Generación de reloj
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Secuencia de reset
    initial begin
        rst = 1'b1;
        write_en = 1'b0;
        read_en  = 1'b0;
        data_in  = '0;
        errores = 0;
        lecturas_ok = 0;
        repeat (3) @(posedge clk);
        rst = 1'b0;
    end

    // Tarea: insertar un byte
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

    // Tarea: extraer y comprobar un byte
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
            end else begin
                lecturas_ok = lecturas_ok + 1;
            end
            @(negedge clk);
            read_en <= 1'b0;
            etiqueta = $sformatf("pop 0x%0h verificado", esperado);
            mostrar_estado(etiqueta);
        end
    endtask

    // Estímulos principales
    initial begin
        @(negedge rst);
        @(posedge clk);

        // Verificar estado tras reset
        if (!empty || full) begin
            $display("ERROR: Bandera incorrecta tras reset. empty=%0b full=%0b", empty, full);
            errores = errores + 1;
        end
        mostrar_estado("Estado tras reset");

        // Llenar FIFO
        push_byte(8'h11);
        push_byte(8'h22);
        push_byte(8'h33);
        push_byte(8'h44);
        @(posedge clk);
        if (!full) begin
            $display("ERROR: El FIFO debería estar lleno. level=%0d", level);
            errores = errores + 1;
        end
        mostrar_estado("FIFO lleno tras 4 inserciones");

        // Vaciar y comprobar orden
        pop_and_check(8'h11);
        pop_and_check(8'h22);
        pop_and_check(8'h33);
        pop_and_check(8'h44);
        @(posedge clk);
        if (!empty || full) begin
            $display("ERROR: Bandera incorrecta tras vaciar. empty=%0b full=%0b", empty, full);
            errores = errores + 1;
        end
        mostrar_estado("FIFO vacio tras drenado");

        // Probar lectura y escritura simultánea
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
        end else begin
            lecturas_ok = lecturas_ok + 1;
        end
        @(negedge clk);
        write_en <= 1'b0;
        read_en  <= 1'b0;
        data_in  <= '0;
        mostrar_estado("Lectura y escritura simultaneas completadas");
        pop_and_check(8'hBB);

        // Intento de lectura en vacío (no debe entregar datos)
        @(negedge clk);
        read_en <= 1'b1;
        @(posedge clk);
        #1;
        if (data_valid !== 1'b0) begin
            $display("ERROR: data_valid no debe activarse cuando el FIFO está vacío");
            errores = errores + 1;
        end
        @(negedge clk);
        read_en <= 1'b0;
        mostrar_estado("Intento de lectura en vacio");

        // Resultados finales
        @(posedge clk);
        if (errores == 0) begin
            $display("Prueba completada SIN errores (%0d lecturas verificadas)", lecturas_ok);
        end else begin
            $display("Prueba completada con %0d error(es)", errores);
        end
        $finish;
    end

endmodule
