/*
 * @file arithmetic_unit.v
 * @brief Unidad aritmética combinacional: suma/resta con carry y detección de overflow.
 * Realiza operaciones básicas aritméticas (suma y resta) seleccionadas por arith_sel_t.
 * Lógica totalmente combinacional.
 */

module arithmetic_unit #(
    //! @param DATA_WIDTH: Ancho de los datos y operandos (por defecto 8 bits)
    parameter DATA_WIDTH = 8
) (
    //! @brief Entradas y salidas de la unidad aritmética combinacional
    input  [DATA_WIDTH-1:0] A,        //!< Operando A
    input  [DATA_WIDTH-1:0] B,        //!< Operando B
    input  alu_pkg::arith_sel_t op,   //!< Selección interna de operación aritmética (de alu_pkg)
    output reg [DATA_WIDTH-1:0] Result, //!< Resultado de la operación aritmética
    output reg Cout,                  //!< Carry Out
    output reg Overflow               //!< Overflow
);

    //! @brief Módulo arithmetic_unit: Unidad combinacional para operaciones de suma/resta con flags

    wire [DATA_WIDTH:0] add_result_full = {1'b0, A} + {1'b0, B};
    wire [DATA_WIDTH:0] sub_result_full = {1'b0, A} + {1'b0, ~B} + {{(DATA_WIDTH){1'b0}}, 1'b1};

    //! @brief Bloque always combinacional: selecciona la operación y calcula el resultado/flags
    always @(*) begin

        Result = {DATA_WIDTH{1'b0}};
        Cout = 1'b0;
        Overflow = 1'b0;
    
        case (op)
            alu_pkg::ARITH_SEL_ADD: begin
                Result = add_result_full[DATA_WIDTH-1:0];
                Cout = add_result_full[DATA_WIDTH];
                Overflow = (A[DATA_WIDTH-1] == B[DATA_WIDTH-1]) &&
                           (A[DATA_WIDTH-1] != Result[DATA_WIDTH-1]);
            end
            alu_pkg::ARITH_SEL_SUB: begin
                Result = sub_result_full[DATA_WIDTH-1:0];
                Cout = sub_result_full[DATA_WIDTH];
                Overflow = (A[DATA_WIDTH-1] != B[DATA_WIDTH-1]) &&
                           (Result[DATA_WIDTH-1] == B[DATA_WIDTH-1]);
            end
            default: begin
                Result = {DATA_WIDTH{1'b0}};
                Cout = 1'b0;
                Overflow = 1'b0;
            end
        endcase
    end

endmodule
