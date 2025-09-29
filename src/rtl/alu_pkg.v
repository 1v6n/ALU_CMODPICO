`include "alu_timescale.vh"

/*
 * @file alu_pkg.v
 * @brief Paquete de definiciones para ALU: enums para familias de opcodes y selectores de sub-unidades.
 * Define tipos enumerados para familias de operaciones (opcode[5:2]) y selectores internos,
 * facilitando legibilidad y evitando números mágicos. 
 */
package alu_pkg;

  //! @brief Paquete alu_pkg: Definiciones de enums para familias de opcodes y selectores de ALU

  // Familias derivadas de los bits opcode[5:2]
  //! @brief Enum para familias de opcodes (bits superiores opcode[5:2])
  typedef enum logic [3:0] {
    OPCODE_FAMILY_ARITH = 4'b1000,  //!< Familia Aritmética
    OPCODE_FAMILY_LOGIC = 4'b1001,  //!< Familia Lógica
    OPCODE_FAMILY_SHIFT = 4'b0000   //!< Familia Desplazamiento
  } opcode_family_t;

  //! @brief Enum para selectores de operaciones aritméticas
  typedef enum logic [1:0] {
    ARITH_SEL_ADD = 2'b00,  //!< Selección para suma
    ARITH_SEL_ADC = 2'b01,  //!< Selección para suma con acarreo
    ARITH_SEL_SUB = 2'b10,  //!< Selección para resta
    ARITH_SEL_SBC = 2'b11   //!< Selección para resta con préstamo
  } arith_sel_t;

  //! @brief Enum para selectores de operaciones lógicas
  typedef enum logic [1:0] {
    LOGIC_SEL_AND = 2'b00,  //!< Selección para AND
    LOGIC_SEL_OR  = 2'b01,  //!< Selección para OR
    LOGIC_SEL_XOR = 2'b10,  //!< Selección para XOR
    LOGIC_SEL_NOR = 2'b11   //!< Selección para NOR
  } logic_sel_t;

  //! @brief Enum para selectores de operaciones de desplazamiento
  typedef enum logic [0:0] {
    SHIFT_SEL_SRL = 1'b0,  //!< Selección para SRL (lógico)
    SHIFT_SEL_SRA = 1'b1   //!< Selección para SRA (aritmético)
  } shift_sel_t;

  //! @brief Enum booleano simple
  typedef enum logic {
    FALSE = 1'b0,  //!< Valor falso
    TRUE  = 1'b1   //!< Valor verdadero
  } bool_t;


endpackage
