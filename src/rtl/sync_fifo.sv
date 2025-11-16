/*
 * @file sync_fifo.sv
 * @brief FIFO síncrona parametrizable que desacopla productores y consumidores ready/valid.
 *
 * El módulo implementa una cola de profundidad configurable en un único dominio de reloj,
 * con indicadores de lleno/vacío y un contador de ocupación para depuración. Las lecturas
 * entregan datos registrados con un ciclo de latencia y se permite operar en modo “bypass” cuando
 * coinciden lecturas y escrituras sin hacer un overflow de la cola.
 */
//! @brief FIFO síncrona 
module sync_fifo #(
    //! @param DATA_WIDTH Ancho de los datos a almacenar.
    parameter int DATA_WIDTH = 8,
    //! @param DEPTH Número total de posiciones disponibles (>=2).
    parameter int DEPTH = 16
) (
    //! @brief Señales de reloj y reset síncrono.
    input  wire                     clk,
    input  wire                     rst,
    //! @brief Interfaz de escritura (datos + habilitación).
    input  wire                     write_en,
    input  wire [DATA_WIDTH-1:0]    data_in,
    //! @brief Interfaz de lectura (habilitación + datos registrados).
    input  wire                     read_en,
    output reg  [DATA_WIDTH-1:0]    data_out,
    output reg                      data_valid,
    //! @brief Indicadores de estado y nivel de ocupación.
    output wire                     full,
    output wire                     empty,
    output wire [$clog2(DEPTH+1)-1:0] level
);

    //! @brief Cálculo de anchos de punteros y contadores.
    localparam int ADDR_WIDTH  = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH+1);

    //! @brief Casting explicitos para los anchos de los parámetros.
    localparam [COUNT_WIDTH-1:0] DEPTH_CONST = COUNT_WIDTH'(DEPTH);
    localparam [ADDR_WIDTH-1:0] DEPTH_MINUS_ONE = ADDR_WIDTH'(DEPTH-1);

    //! @brief Banco de memoria interna del FIFO.
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    //! @brief Punteros circulares y contador de nivel.
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [COUNT_WIDTH-1:0] count;

    //! @brief Señales de disparo para escrituras y lecturas efectivas.
    wire write_fire = write_en && !full;
    wire read_fire  = read_en && !empty;

    //! @brief Calcula el siguiente puntero circular para lectura/escritura.
    function automatic [ADDR_WIDTH-1:0] ptr_next;
        input [ADDR_WIDTH-1:0] value;
        begin
            if (value == DEPTH_MINUS_ONE) begin
                ptr_next = '0;
            end else begin
                ptr_next = value + 1'b1;
            end
        end
    endfunction

    //! @brief Lógica secuencial: almacena datos y actualiza punteros/contador.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            count      <= '0;
            data_out   <= '0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (write_fire) begin
                mem[wr_ptr] <= data_in;
                wr_ptr <= ptr_next(wr_ptr);
            end

            if (read_fire) begin
                data_out   <= mem[rd_ptr];
                rd_ptr     <= ptr_next(rd_ptr);
                data_valid <= 1'b1;
            end

            case ({write_fire, read_fire})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    //! @brief Asignaciones de salidas de estado.
    assign full  = (count == DEPTH_CONST);
    assign empty = (count == '0);
    assign level = count;

endmodule
