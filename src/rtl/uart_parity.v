`include "alu_timescale.vh"

/**
 * @file uart_parity.vh
 * @brief Definiciones de tipos para configuración de paridad UART
 *
 * @details Define el enum parity_t para selección de modo de paridad
 * en tiempo de síntesis
 */

package uart_parity_pkg;

  //! @brief Enum para selección de modo de paridad UART
  typedef enum logic [1:0] {
    PARITY_NONE = 2'b00,  //!< Sin paridad
    PARITY_EVEN = 2'b01,  //!< Paridad par
    PARITY_ODD  = 2'b10   //!< Paridad impar
  } parity_t;

endpackage
