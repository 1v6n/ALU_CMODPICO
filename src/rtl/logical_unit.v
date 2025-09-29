`include "alu_timescale.vh"

/*
 * @file logical_unit.v
 * @brief Unidad lógica combinacional: operaciones AND, OR, XOR y NOR bit a bit.
 * Realiza operaciones lógicas básicas seleccionadas por logic_sel_t sobre operandos A y B.
 * Lógica totalmente combinacional.
 */

//! @brief Módulo logical_unit: Unidad combinacional para operaciones lógicas bit a bit
module logical_unit #(
    //! @param DATA_WIDTH: Ancho de los datos y operandos (por defecto 8 bits)
    parameter DATA_WIDTH = 8
) (
    //! @brief Entradas y salidas de la unidad lógica combinacional
    input [DATA_WIDTH-1:0] A,  //!< Operando A
    input [DATA_WIDTH-1:0] B,  //!< Operando B
    input alu_pkg::logic_sel_t op,  //!< Selección interna de operación lógica (de alu_pkg)
    output reg [DATA_WIDTH-1:0] Result  //!< Resultado de la operación lógica
);

  //! @brief Bloque always combinacional: selecciona y aplica la operación lógica
  always @(*) begin
    unique case (op)
      alu_pkg::LOGIC_SEL_AND: Result = A & B;  //!< AND bit a bit A & B
      alu_pkg::LOGIC_SEL_OR: Result = A | B;  //!< OR bit a bit A | B
      alu_pkg::LOGIC_SEL_XOR: Result = A ^ B;  //!< XOR bit a bit A ^ B
      alu_pkg::LOGIC_SEL_NOR: Result = ~(A | B);  //!< NOR bit a bit ~(A | B)
      default: Result = {DATA_WIDTH{1'b0}};  //!< Valor por defecto para casos inválidos
    endcase
  end

endmodule
