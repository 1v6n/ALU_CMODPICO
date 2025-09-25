/*
 * @file shifter_unit.v
 * @brief Unidad de desplazamiento combinacional: SRL y SRA de 1 bit sobre operando A.
 * Implementa desplazamientos lógicos y aritméticos a la derecha seleccionados por shift_sel_t.
 * Lógica totalmente combinacional.
 */

module shifter_unit #(
    //! @param DATA_WIDTH: Ancho de los datos (por defecto 8 bits)
    parameter DATA_WIDTH = 8
) (
    //! @brief Entradas y salidas de la unidad de desplazamiento combinacional
    input  [DATA_WIDTH-1:0] A,        //!< Operando A (único operando para desplazamientos)
    input  alu_pkg::shift_sel_t op,   //!< Selección interna de operación de desplazamiento (de alu_pkg)
    output reg [DATA_WIDTH-1:0] Result //!< Resultado de la operación de desplazamiento
);

    //! @brief Módulo shifter_unit: Unidad combinacional para desplazamientos SRL/SRA de 1 bit

    //! @brief Bloque always combinacional: selecciona y aplica desplazamiento de 1 bit
    always @(*) begin
        case (op)
            alu_pkg::SHIFT_SEL_SRL: Result = A >> 1;          //!< Desplazamiento derecho lógico
            alu_pkg::SHIFT_SEL_SRA: Result = $signed(A) >>> 1; //!< Desplazamiento derecho aritmético
            default:                Result = {DATA_WIDTH{1'b0}};     //!< Valor seguro para selecciones inválidas
        endcase
    end

endmodule
