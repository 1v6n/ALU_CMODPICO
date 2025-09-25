/*
 * @file alu.v
 * @brief Módulo principal ALU: decodificador combinacional de opcodes para selección de sub-unidades.
 * Decodifica códigos de 6 bits para seleccionar sub-unidades aritmética, lógica o de desplazamiento.
 * Lógica totalmente combinacional.
 */
module alu #(
    //! @param DATA_WIDTH: Ancho de los datos y operandos (por defecto 8 bits)
    parameter DATA_WIDTH = 8,
    //! @param OPCODE_WIDTH: Ancho del opcode (debe ser 6 bits)
    parameter OPCODE_WIDTH = 6
) (
    //! @brief Entradas y salidas del núcleo ALU combinacional
    input  [DATA_WIDTH-1:0] A,        //!< Operando A
    input  [DATA_WIDTH-1:0] B,        //!< Operando B
    input  [OPCODE_WIDTH-1:0] opcode, //!< Opcode de 6 bits
    output reg [DATA_WIDTH-1:0] Result, //!< Resultado final de la ALU
    output reg Cout,                 //!< Carry out (solo para operaciones aritméticas)
    output reg Overflow,             //!< Overflow (solo para operaciones aritméticas)
    output Zero                      //!< Zero flag (resultado es cero)
);

    //! @brief Módulo alu: Núcleo combinacional principal que decodifica el opcode y selecciona la sub-unidad

  alu_pkg::arith_sel_t arith_sel; //!< Selector para unidad aritmética
  alu_pkg::logic_sel_t logic_sel; //!< Selector para unidad lógica
  alu_pkg::shift_sel_t shift_sel; //!< Selector para unidad de desplazamiento

  wire [DATA_WIDTH-1:0] arith_result; //!< Resultado de la unidad aritmética
  wire [DATA_WIDTH-1:0] logic_result; //!< Resultado de la unidad lógica
  wire [DATA_WIDTH-1:0] shift_result; //!< Resultado de la unidad de desplazamiento
  wire arith_cout;                    //!< Carry de la unidad aritmética
  wire arith_overflow;                //!< Overflow de la unidad aritmética

  //! @brief Instancia de la unidad aritmética combinacional
  arithmetic_unit #(
                    .DATA_WIDTH(DATA_WIDTH)
                  ) arith_inst (
                    .A(A),
                    .B(B),
                    .op(arith_sel),
                    .Result(arith_result),
                    .Cout(arith_cout),
                    .Overflow(arith_overflow)
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
                 .op(shift_sel),
                 .Result(shift_result)
               );

  //! @brief Bloque always combinacional: decodifica opcode y selecciona sub-unidad/resultados/flags
  always @(*)
  begin

    arith_sel = alu_pkg::ARITH_SEL_ADD;
    logic_sel = alu_pkg::LOGIC_SEL_AND;
    shift_sel = alu_pkg::SHIFT_SEL_SRL;
    Result = {DATA_WIDTH{1'b0}};
    Cout = 1'b0;
    Overflow = 1'b0;

    unique case (alu_pkg::opcode_family_t'(opcode[5:2]))
             alu_pkg::OPCODE_FAMILY_ARITH:
             begin
               unique case (opcode[1:0])
                 2'b00:
                 begin
                   arith_sel = alu_pkg::ARITH_SEL_ADD;
                   Result = arith_result;
                   Cout = arith_cout;
                   Overflow = arith_overflow;
                 end
                 2'b10:
                 begin
                   arith_sel = alu_pkg::ARITH_SEL_SUB;
                   Result = arith_result;
                   Cout = arith_cout;
                   Overflow = arith_overflow;
                 end
                 default:
                 begin
                   Result = {DATA_WIDTH{1'b0}};
                 end
               endcase
             end

             alu_pkg::OPCODE_FAMILY_LOGIC:
             begin
               unique case (opcode[1:0])
                 2'b00:
                 begin
                   logic_sel = alu_pkg::LOGIC_SEL_AND;
                   Result = logic_result;
                 end
                 2'b01:
                 begin
                   logic_sel = alu_pkg::LOGIC_SEL_OR;
                   Result = logic_result;
                 end
                 2'b10:
                 begin
                   logic_sel = alu_pkg::LOGIC_SEL_XOR;
                   Result = logic_result;
                 end
                 2'b11:
                 begin
                   logic_sel = alu_pkg::LOGIC_SEL_NOR;
                   Result = logic_result;
                 end
                 default:
                 begin
                   Result = {DATA_WIDTH{1'b0}};
                 end
               endcase
             end

             alu_pkg::OPCODE_FAMILY_SHIFT:
             begin
               unique case (opcode[1:0])
                 2'b10:
                 begin
                   shift_sel = alu_pkg::SHIFT_SEL_SRL;
                   Result = shift_result;
                 end
                 2'b11:
                 begin
                   shift_sel = alu_pkg::SHIFT_SEL_SRA;
                   Result = shift_result;
                 end
                 default:
                 begin
                   Result = {DATA_WIDTH{1'b0}};
                 end
               endcase
             end

             default:
             begin
               Result = {DATA_WIDTH{1'b0}};
             end
           endcase
         end
         assign Zero = (Result == 0);
        
endmodule
