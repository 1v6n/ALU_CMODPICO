`include "alu_timescale.vh"

/*
 * @file shifter_unit.v
 * @brief Unidad de desplazamiento combinacional: SRL y SRA con desplazamiento variable sobre operando A.
 * Implementa desplazamientos lógicos y aritméticos a la derecha seleccionados por shift_sel_t.
 * Lógica totalmente combinacional.
 */

//! @brief Módulo shifter_unit: Unidad combinacional para desplazamientos SRL/SRA con desplazamiento variable
module shifter_unit #(
    //! @param DATA_WIDTH: Ancho de los datos (por defecto 8 bits)
    parameter DATA_WIDTH = 8
) (
    //! @brief Entradas y salidas de la unidad de desplazamiento combinacional
    input [DATA_WIDTH-1:0] A,  //!< Operando A
    input [DATA_WIDTH-1:0] B,  //!< Operando B (valor indica el desplazamiento)
    input  alu_pkg::shift_sel_t op,    //!< Selección interna de operación de desplazamiento (de alu_pkg)
    output reg [DATA_WIDTH-1:0] Result  //!< Resultado de la operación de desplazamiento
);

  //! @brief Bloque always combinacional: selecciona y aplica desplazamiento variable
  always @(*) begin
    unique case (op)
      alu_pkg::SHIFT_SEL_SRL: Result = A >> B;
      alu_pkg::SHIFT_SEL_SRA: Result = $signed(A) >>> B;
      default:                Result = {DATA_WIDTH{1'b0}};
    endcase
  end

endmodule
