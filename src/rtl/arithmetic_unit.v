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
    input  logic carry_in,            //!< Acarreo de entrada (registrado en alu_top)
    input  alu_pkg::arith_sel_t op,   //!< Selección interna de operación aritmética (de alu_pkg)
    output reg [DATA_WIDTH-1:0] Result, //!< Resultado de la operación aritmética
    output reg Cout,                  //!< Carry Out
    output reg Overflow               //!< Overflow
);

    //! @brief Módulo arithmetic_unit: Unidad combinacional para operaciones de suma/resta con flags

    logic [DATA_WIDTH-1:0] add_operand;   //!< Operando B tras ajustes (complemento o directo)
    logic carry_term;                     //!< Acarreo que se suma a la operación seleccionada
    logic [DATA_WIDTH:0] wide_result;     //!< Resultado extendido para capturar el carry
    logic op_valid;                       //!< Indica si la operación seleccionada es válida

    //! @brief Bloque always combinacional: selecciona la operación y calcula el resultado/flags
    always @(*) begin

        Result = {DATA_WIDTH{1'b0}};
        Cout = 1'b0;
        Overflow = 1'b0;
        add_operand = {DATA_WIDTH{1'b0}};
        carry_term = 1'b0;
        wide_result = {DATA_WIDTH+1{1'b0}};
        op_valid = 1'b0;
    
        case (op)
            alu_pkg::ARITH_SEL_ADD: begin
                add_operand = B;
                carry_term = 1'b0;
                op_valid = 1'b1;
            end
            alu_pkg::ARITH_SEL_ADC: begin
                add_operand = B;
                carry_term = carry_in;
                op_valid = 1'b1;
            end
            alu_pkg::ARITH_SEL_SUB: begin
                add_operand = ~B;
                carry_term = 1'b1;
                op_valid = 1'b1;
            end
            alu_pkg::ARITH_SEL_SBC: begin
                add_operand = ~B;
                carry_term = carry_in;
                op_valid = 1'b1;
            end
            default: begin
                Result = {DATA_WIDTH{1'b0}};
                Cout = 1'b0;
                Overflow = 1'b0;
                op_valid = 1'b0;
            end
        endcase

        if (op_valid) begin
            wide_result = {1'b0, A} + {1'b0, add_operand} + {{DATA_WIDTH{1'b0}}, carry_term};
            Result = wide_result[DATA_WIDTH-1:0];
            Cout = wide_result[DATA_WIDTH];
            Overflow = (A[DATA_WIDTH-1] == add_operand[DATA_WIDTH-1]) &&
                       (Result[DATA_WIDTH-1] != A[DATA_WIDTH-1]);
        end else begin
            wide_result = {DATA_WIDTH+1{1'b0}};
        end
    end

endmodule
