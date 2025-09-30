`include "alu_timescale.vh"

/*
 * @file arithmetic_unit.v
 * @brief Unidad aritmética combinacional: suma/resta con carry y detección de overflow.
 * Realiza operaciones básicas aritméticas (suma y resta) seleccionadas por arith_sel_t.
 * Lógica totalmente combinacional.
 */

//! @brief Módulo arithmetic_unit: Unidad combinacional para operaciones de suma/resta con flags
module arithmetic_unit #(
    //! @param DATA_WIDTH: Ancho de los datos y operandos (por defecto 8 bits)
    parameter DATA_WIDTH = 8
) (
    //! @brief Entradas y salidas de la unidad aritmética combinacional
    input [DATA_WIDTH-1:0] A,  //!< Operando A
    input [DATA_WIDTH-1:0] B,  //!< Operando B
    input carry_in,  //!< Acarreo de entrada (registrado en alu_top)
    input alu_pkg::arith_sel_t op,  //!< Selección interna de operación aritmética (de alu_pkg)
    output reg [DATA_WIDTH-1:0] Result,  //!< Resultado de la operación aritmética
    output reg Cout  //!< Carry Out
);

  reg [DATA_WIDTH-1:0] add_operand;  //!< Operando B tras ajustes (complemento o directo)
  reg                  carry_term;  //!< Acarreo que se suma a la operación seleccionada
  reg [  DATA_WIDTH:0] wide_result;  //!< Resultado extendido para capturar el carry
  reg                  op_valid;  //!< Indica si la operación seleccionada es válida

  //! @brief Bloque always combinacional: selecciona la operación y calcula el resultado/flags
  always @(*) begin

    Result = {DATA_WIDTH{1'b0}};
    Cout = alu_pkg::FALSE;
    add_operand = {DATA_WIDTH{1'b0}};
    carry_term = alu_pkg::FALSE;
    wide_result = {DATA_WIDTH + 1{1'b0}};
    op_valid = alu_pkg::FALSE;
    unique case (op)
      alu_pkg::ARITH_SEL_ADD: begin
        add_operand = B;
        carry_term = alu_pkg::FALSE;
        op_valid = alu_pkg::TRUE;
      end
      alu_pkg::ARITH_SEL_ADC: begin
        add_operand = B;
        carry_term = carry_in;
        op_valid = alu_pkg::TRUE;
      end
      alu_pkg::ARITH_SEL_SUB: begin
        add_operand = ~B;
        carry_term = alu_pkg::TRUE;
        op_valid = alu_pkg::TRUE;
      end
      alu_pkg::ARITH_SEL_SBC: begin
        add_operand = ~B;
        carry_term = carry_in;
        op_valid = alu_pkg::TRUE;
      end
      default: begin
        Result = {DATA_WIDTH{1'b0}};
        Cout = alu_pkg::FALSE;
        op_valid = alu_pkg::FALSE;
      end
    endcase

    if (op_valid) begin
      wide_result = {1'b0, A} + {1'b0, add_operand} + {{DATA_WIDTH{1'b0}}, carry_term};
      Result = wide_result[DATA_WIDTH-1:0];
      Cout = wide_result[DATA_WIDTH];
    end else begin
      wide_result = {DATA_WIDTH + 1{1'b0}};
    end
  end

endmodule
