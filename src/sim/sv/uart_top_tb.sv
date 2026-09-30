`timescale 1ns/1ps

module uart_top_tb;

    // ------------------------------------------------------------
    // Parámetros de UART (coherentes con el top por defecto)
    // ------------------------------------------------------------
    localparam int CLOCK_FREQ = 12_000_000;
    localparam int BAUD_RATE  = 9600;
    localparam int DATA_BITS  = 8;

    // periodo de bit en ns
    localparam real BIT_PERIOD_NS = 1e9 / BAUD_RATE;

    // Cantidad de bytes a probar
    localparam int N_BYTES = 4;

    // ------------------------------------------------------------
    // Señales DUT
    // ------------------------------------------------------------
    logic clk = 0;
    logic rst = 0;

    logic rx;
    logic tx;

    // Interfaz TX (ALU → PC)
    logic              write_en_tx_top;
    logic [DATA_BITS-1:0] tx_data_in;
    logic              tx_done_tick;

    // Interfaz RX (PC → ALU)
    logic                 read_en_rx_top;
    logic [DATA_BITS-1:0] data_out_rx;
    logic                 data_valid_rx;
    logic                 rx_done_tick;

    // Estado FIFOs
    logic rx_fifo_empty;
    logic rx_fifo_full;
    logic [$clog2(32+1)-1:0] rx_fifo_level;

    logic tx_fifo_empty;
    logic tx_fifo_full;
    logic [$clog2(32+1)-1:0] tx_fifo_level;

    // Errores RX
    logic parity_error;
    logic frame_error;

    // ------------------------------------------------------------
    // Instancia del DUT
    // ------------------------------------------------------------
    uart_top #(
        .DATA_BITS   (DATA_BITS),
        .PARITY      (uart_parity_pkg::PARITY_NONE),
        .OVERSAMPLE  (16),
        .CLOCK_FREQ  (CLOCK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .FIFO_DEPTH  (32)
    ) dut (
        .clk            (clk),
        .rst            (rst),

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

    // ------------------------------------------------------------
    // Clock 12 MHz
    // ------------------------------------------------------------
    always #41.666 clk = ~clk;  // periodo ~83.333 ns

    // ------------------------------------------------------------
    // Monitor de debug para ALU y FIFOs
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rx_done_tick)
            $display("[DEBUG @ %0t] RX completó frame, rx_fifo_level=%0d", $time, rx_fifo_level);
        
        if (read_en_rx_top)
            $display("[DEBUG @ %0t] ALU lee FIFO_RX, data_valid_rx=%0b, data_out_rx=0x%0h", 
                     $time, data_valid_rx, data_out_rx);
        
        if (write_en_tx_top)
            $display("[DEBUG @ %0t] ALU escribe FIFO_TX, tx_data_in=0x%0h, tx_fifo_level=%0d", 
                     $time, tx_data_in, tx_fifo_level);
        
        if (tx_done_tick)
            $display("[DEBUG @ %0t] TX completó frame, tx_fifo_level=%0d", $time, tx_fifo_level);
    end

    // ------------------------------------------------------------
    // Tarea: enviar un byte por la línea RX (PC → UART)
    // Formato: 1 start, 8 datos, 1 stop, sin paridad
    // ------------------------------------------------------------
    task automatic uart_send_byte(input [7:0] data);
        integer i;
        begin
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

    // ------------------------------------------------------------
    // Tarea: recibir un byte desde TX (UART → PC)
    // Detecta start y samplea en el centro de cada bit
    // ------------------------------------------------------------
    task automatic uart_read_byte(output [7:0] data);
        integer i;
        begin
            // Asegurar que TX está en idle (1) antes de esperar START
            wait(tx === 1'b1);
            
            // Esperar transición a START (bajada a 0)
            @(negedge tx);

            // Ir al centro del bit de start
            #(BIT_PERIOD_NS/2.0);

            // Leer 8 bits de datos
            for (i = 0; i < 8; i++) begin
                #(BIT_PERIOD_NS);
                data[i] = tx;
            end

            // Consumir STOP (no lo chequeo acá, pero se podría)
            #(BIT_PERIOD_NS);
        end
    endtask

    // ------------------------------------------------------------
    // "ALU" emulada:
    // Lee desde FIFO_RX y escribe lo mismo en FIFO_TX
    // ------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE,
        S_WAIT_DATA
    } alu_state_t;

    alu_state_t alu_state;

    // Buffer interno para dato leído de RX
    logic [DATA_BITS-1:0] rx_buffer;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            alu_state        <= S_IDLE;
            write_en_tx_top  <= 1'b0;
            read_en_rx_top   <= 1'b0;
            tx_data_in       <= '0;
        end else begin
            // por defecto, pulsos desactivados
            write_en_tx_top  <= 1'b0;
            read_en_rx_top   <= 1'b0;

            case (alu_state)
                S_IDLE: begin
                    // Si hay dato en FIFO_RX y hay espacio en FIFO_TX
                    if (!rx_fifo_empty && !tx_fifo_full) begin
                        // Pedimos un dato a FIFO_RX
                        read_en_rx_top <= 1'b1;
                        alu_state      <= S_WAIT_DATA;
                    end
                end

                S_WAIT_DATA: begin
                    // Esperamos a que FIFO_RX nos indique que el dato es válido
                    if (data_valid_rx) begin
                        rx_buffer  <= data_out_rx;
                        tx_data_in <= data_out_rx;
                        write_en_tx_top <= 1'b1;  // escribir en FIFO_TX
                        alu_state  <= S_IDLE;
                    end
                end

                default: alu_state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------
    // Estímulos y comprobación
    // ------------------------------------------------------------
    byte tx_vec   [N_BYTES-1:0];  // lo que mando por RX
    byte rx_vec   [N_BYTES-1:0];  // lo que reconstruyo desde TX
    int  idx_tx;
    int  idx_rx;

    logic all_ok;  // Variable para chequeo global
    
    initial begin
        // VCD dump para visualización
        $dumpfile("uart_top_tb.vcd");
        $dumpvars(0, uart_top_tb);
        
        // Inicializaciones
        rx = 1'b1;  // línea idle
        idx_tx = 0;
        idx_rx = 0;
        all_ok = 1'b1;

        // Cargar algunos patrones
        tx_vec[0] = 8'h55;
        tx_vec[1] = 8'hA3;
        tx_vec[2] = 8'h00;
        tx_vec[3] = 8'hFF;

        // Reset
        rst = 1;
        repeat(10) @(posedge clk);
        rst = 0;
        repeat(50) @(posedge clk);

        $display("[TB] TX value after reset: %0b", tx);
        $display("[TB] Comenzando envío de %0d bytes por RX", N_BYTES);

        // Transmitir y recibir en paralelo
        fork
            begin : DRIVER_RX
                for (idx_tx = 0; idx_tx < N_BYTES; idx_tx++) begin
                    $display("[TB] Enviando byte %0d por RX: 0x%0h", idx_tx, tx_vec[idx_tx]);
                    uart_send_byte(tx_vec[idx_tx]);
                    #(BIT_PERIOD_NS * 2);  // gap entre frames
                end
            end

            begin : MONITOR_TX
                
                for (idx_rx = 0; idx_rx < N_BYTES; idx_rx++) begin
                    uart_read_byte(rx_vec[idx_rx]);
                    $display("[TB] Recibido byte %0d desde TX: 0x%0h", idx_rx, rx_vec[idx_rx]);
                end
            end
        join

        $display("[TB] Completada transmisión y recepción");

        // Comparación final
        $display("==============================================");
        $display("[TB] Comparando lo que entró por RX vs lo que salió por TX");
        for (int i = 0; i < N_BYTES; i++) begin
            if (tx_vec[i] === rx_vec[i])
                $display("[TB] Byte %0d OK: RX_in=0x%0h  TX_out=0x%0h", i, tx_vec[i], rx_vec[i]);
            else
                $display("[TB] Byte %0d ERROR: RX_in=0x%0h  TX_out=0x%0h", i, tx_vec[i], rx_vec[i]);
        end

        // Chequeo global
        all_ok = 1'b1;
        for (int i = 0; i < N_BYTES; i++) begin
            if (tx_vec[i] !== rx_vec[i]) all_ok = 1'b0;
        end

        if (all_ok)
            $display("[TB] TEST PASO: datos RX -> TX coinciden");
        else
            $display("[TB] TEST FALLO: hay diferencias entre RX y TX");

        $finish;
    end

    // Timeout de seguridad
    initial begin
        #500ms;
        $display("[TB] ERROR: Timeout - simulación excedió 500ms");
        $finish;
    end

endmodule
