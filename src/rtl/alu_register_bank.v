`include "alu_timescale.vh"

/*
 * @file alu_register_bank.v
 * @brief Banco de registros centralizado para alu_top: carga secuencial de operandos y opcode desde bus único.
 * Este módulo maneja la carga condicional de valores desde un bus de entrada compartido hacia registros internos
 * para operandos A, B y opcode, utilizando señales de control para determinar qué registro
 * cargar en cada ciclo de reloj. Soporta reset síncrono y verificación de parámetros.
 */

//! @brief Módulo alu_register_bank: Banco de registros para ALU secuencial alimentada por bus
module alu_register_bank #(
    //! @param DATA_WIDTH: Ancho de los datos y operandos (por defecto 8 bits)
    parameter integer DATA_WIDTH   = 8,
    //! @param OPCODE_WIDTH: Ancho del opcode (por defecto 5 bits para 3 familias x 4 operaciones)
    parameter integer OPCODE_WIDTH = 5
) (
    //! @brief Entradas y salidas del módulo
    input                     clk,       //!< Señal de reloj para sincronización
    input                     rst,       //!< Reset síncrono activo alto
    input  [  DATA_WIDTH-1:0] data_in,   //!< Bus de entrada de datos compartido
    input                     load_a,    //!< Señal de control para cargar operando A
    input                     load_b,    //!< Señal de control para cargar operando B
    input                     load_sel,  //!< Señal de control para cargar opcode/selección
    output [  DATA_WIDTH-1:0] reg_a,     //!< Salida del registro A (operando A)
    output [  DATA_WIDTH-1:0] reg_b,     //!< Salida del registro B (operando B)
    output [OPCODE_WIDTH-1:0] reg_sel    //!< Salida del registro de selección (opcode, bits bajos)
);

  localparam integer REG_COUNT = 3;  //!< Número total de registros en el banco (A, B, SEL)
  localparam integer REG_A_IDX = 0;  //!< Índice del registro A
  localparam integer REG_B_IDX = 1;  //!< Índice del registro B
  localparam integer REG_SEL_IDX = 2;  //!< Índice del registro de selección (opcode)
  localparam integer OPCODE_PAD_WIDTH = (DATA_WIDTH > OPCODE_WIDTH) ? DATA_WIDTH - OPCODE_WIDTH : 0; //!< Bits de relleno para opcode si DATA_WIDTH > OPCODE_WIDTH

  reg [DATA_WIDTH-1:0] register_bank[0:REG_COUNT-1];  //!< Banco de registros

  integer bank_idx;  //!< Índice para bucles  

  assign reg_a = register_bank[REG_A_IDX];  //!< Salida del registro A (operando A)
  assign reg_b = register_bank[REG_B_IDX];  //!< Salida del registro B (operando B)
  assign reg_sel = register_bank[REG_SEL_IDX][OPCODE_WIDTH-1:0]; //!< Salida del registro de selección (opcode, bits bajos)

  //! @brief Bloque secuencial: carga condicional de registros desde bus compartido
  always @(posedge clk) begin
    if (rst) begin
      for (bank_idx = 0; bank_idx < REG_COUNT; bank_idx = bank_idx + 1) begin
        register_bank[bank_idx] <= '0;
      end
    end else begin
      if (load_a) begin
        register_bank[REG_A_IDX] <= data_in;
      end

      if (load_b) begin
        register_bank[REG_B_IDX] <= data_in;
      end

      if (load_sel) begin
        register_bank[REG_SEL_IDX] <= {{OPCODE_PAD_WIDTH{1'b0}}, data_in[OPCODE_WIDTH-1:0]};
      end
    end
  end

endmodule
