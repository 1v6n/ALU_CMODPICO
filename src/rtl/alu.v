`include "alu_timescale.vh"

/*
 * @file alu.v
 * @brief Módulo principal ALU: decodificador combinacional de opcodes para selección de sub-unidades.
 * Decodifica códigos de 6 bits para seleccionar sub-unidades aritmética, lógica o de desplazamiento.
 * Lógica totalmente combinacional.
 */

//! @brief Módulo alu: Núcleo combinacional principal que decodifica el opcode y selecciona la sub-unidad
module alu #(
    //! @param DATA_WIDTH: Ancho de los datos y operandos (por defecto 8 bits)
    parameter DATA_WIDTH   = 8,
    //! @param OPCODE_WIDTH: Ancho del opcode (debe ser 6 bits)
    parameter OPCODE_WIDTH = 6
) (
    //! @brief Entradas y salidas del núcleo ALU combinacional
    input      [  DATA_WIDTH-1:0] A,         //!< Operando A
    input      [  DATA_WIDTH-1:0] B,         //!< Operando B
    input      [OPCODE_WIDTH-1:0] opcode,    //!< Opcode de 6 bits
    input                         carry_in,  //!< Carry registrado desde la operación previa
    output reg [  DATA_WIDTH-1:0] Result,    //!< Resultado final de la ALU
    output reg                    Cout,      //!< Carry out (solo para operaciones aritméticas)
    output                        Zero       //!< Zero flag (resultado es cero)
);

  alu_pkg::arith_sel_t arith_sel;  //!< Selección de operación para la unidad aritmética
  alu_pkg::logic_sel_t logic_sel;  //!< Selección de operación para la unidad lógica
  alu_pkg::shift_sel_t shift_sel;  //!< Selección de operación para la unidad de desplazamiento

  reg arith_carry_in;  //!< Carry hacia la unidad aritmética
  reg use_arith;  //!< Habilita salida de unidad aritmética
  reg use_logic;  //!< Habilita salida de unidad lógica
  reg use_shift;  //!< Habilita salida de unidad de desplazamiento

  wire [DATA_WIDTH-1:0] arith_result;  //!< Resultado de la unidad aritmética
  wire [DATA_WIDTH-1:0] logic_result;  //!< Resultado de la unidad lógica
  wire [DATA_WIDTH-1:0] shift_result;  //!< Resultado de la unidad de desplazamiento
  wire arith_cout;  //!< Carry de la unidad aritmética

  //! @brief Instancia de la unidad aritmética combinacional
  arithmetic_unit #(
      .DATA_WIDTH(DATA_WIDTH)
  ) arith_inst (
      .A(A),
      .B(B),
      .carry_in(arith_carry_in),
      .op(arith_sel),
      .Result(arith_result),
      .Cout(arith_cout)
  );

  //! @brief Instancia de la unidad lógica combinacional
  logical_unit #(
      .DATA_WIDTH(DATA_WIDTH)
  ) logic_inst (
      .A(A),
      .B(B),
      .op(logic_sel),
      .Result(logic_result)
  );

  //! @brief Instancia de la unidad de desplazamiento combinacional
  shifter_unit #(
      .DATA_WIDTH(DATA_WIDTH)
  ) shift_inst (
      .A(A),
      .B(B),
      .op(shift_sel),
      .Result(shift_result)
  );

  //! @brief Bloque combinacional: decodifica el opcode y configura selectores de sub-unidades
  always @(*) begin
    arith_sel = alu_pkg::ARITH_SEL_ADD;
    logic_sel = alu_pkg::LOGIC_SEL_AND;
    shift_sel = alu_pkg::SHIFT_SEL_SRL;
    arith_carry_in = alu_pkg::FALSE;
    use_arith = alu_pkg::FALSE;
    use_logic = alu_pkg::FALSE;
    use_shift = alu_pkg::FALSE;

    unique case (alu_pkg::opcode_family_t'(opcode[5:2]))
      alu_pkg::OPCODE_FAMILY_ARITH: begin
        use_arith = alu_pkg::TRUE;
        unique case (opcode[1:0])
          alu_pkg::ARITH_SEL_ADD: begin
            arith_sel = alu_pkg::ARITH_SEL_ADD;
            arith_carry_in = alu_pkg::FALSE;
          end
          alu_pkg::ARITH_SEL_ADC: begin
            arith_sel = alu_pkg::ARITH_SEL_ADC;
            arith_carry_in = carry_in;
          end
          alu_pkg::ARITH_SEL_SUB: begin
            arith_sel = alu_pkg::ARITH_SEL_SUB;
            arith_carry_in = alu_pkg::FALSE;
          end
          alu_pkg::ARITH_SEL_SBC: begin
            arith_sel = alu_pkg::ARITH_SEL_SBC;
            arith_carry_in = carry_in;
          end
          default: begin
            use_arith = alu_pkg::FALSE;
          end
        endcase
      end

      alu_pkg::OPCODE_FAMILY_LOGIC: begin
        use_logic = alu_pkg::TRUE;
        unique case (opcode[1:0])
          alu_pkg::LOGIC_SEL_AND: logic_sel = alu_pkg::LOGIC_SEL_AND;
          alu_pkg::LOGIC_SEL_OR: logic_sel = alu_pkg::LOGIC_SEL_OR;
          alu_pkg::LOGIC_SEL_XOR: logic_sel = alu_pkg::LOGIC_SEL_XOR;
          alu_pkg::LOGIC_SEL_NOR: logic_sel = alu_pkg::LOGIC_SEL_NOR;
          default: use_logic = 1'b0;
        endcase
      end

      alu_pkg::OPCODE_FAMILY_SHIFT: begin
        use_shift = alu_pkg::TRUE;
        unique case (opcode[0:0])
          alu_pkg::SHIFT_SEL_SRL: shift_sel = alu_pkg::SHIFT_SEL_SRL;
          alu_pkg::SHIFT_SEL_SRA: shift_sel = alu_pkg::SHIFT_SEL_SRA;
          default: use_shift = alu_pkg::FALSE;
        endcase
      end

      default: begin
        use_arith = alu_pkg::FALSE;
        use_logic = alu_pkg::FALSE;
        use_shift = alu_pkg::FALSE;
      end
    endcase
  end

  //! @brief Bloque combinacional: selecciona resultado y flags según la sub-unidad activa
  always @(*) begin
    Result = {DATA_WIDTH{1'b0}};
    Cout   = alu_pkg::FALSE;

    if (use_arith) begin
      Result = arith_result;
      Cout   = arith_cout;

    end else if (use_logic) begin
      Result = logic_result;
    end else if (use_shift) begin
      Result = shift_result;
    end
  end

  assign Zero = (Result == 0);  //!< Zero flag si el resultado es cero

endmodule
