`include "alu_timescale.vh"
`include "uart_parity.v"

/**
 * @file uart_rx.sv
 * @brief Receptor UART parametrizable con soporte de paridad
 *
 * @details Módulo de recepción UART simple y robusto. Recibe frames
 * en formato: START + DATA[LSB→MSB] + [PARITY] + STOP. El tamaño de
 * datos (DATA_BITS), el factor de oversampling (OVERSAMPLE) y el modo
 * de paridad (NONE/EVEN/ODD) son parametrizables.
 *
 * Características:
 * - Detección robusta de bit de START mediante flanco 1→0
 * - Muestreo en el centro de cada bit (OVERSAMPLE/2)
 * - Verificación de paridad con señal de error dedicada
 * - Verificación de bit de STOP con señal de frame error
 * - Recuperación de datos LSB→MSB en shifter
 * - Interfaz opcional tipo FIFO de salida: usar `dout` + write_en/full
 *
 * Estructura del frame recibido:
 * - START: 1 bit (siempre '0')
 * - DATA: DATA_BITS (LSB primero)
 * - PARITY: 1 bit opcional (si PARITY != NONE)
 * - STOP: 1 bit (siempre '1')
 *
 * Máquina de estados (FSM):
 * - S_IDLE   → Espera flanco de START (rx: 1→0)
 * - S_START  → Espera centro del bit de START para validar
 * - S_DATA   → Recibe DATA_BITS bits LSB→MSB
 * - S_PARITY → Recibe y verifica bit de paridad (si aplica)
 * - S_STOP   → Recibe y verifica bit de STOP
 * - S_DONE   → Genera pulso rx_done_tick y presenta dout
 *
 * Temporización:
 * - Cada bit dura OVERSAMPLE ticks de baud_tick (p.ej. x16 del baudrate)
 * - El muestreo de datos ocurre en el tick OVERSAMPLE/2 para centrarse
 * - El avance de la FSM y contadores se realiza con baud_tick
 *
 * Paridad:
 * - Verificada sobre data_reg (datos recibidos completos)
 * - EVEN: total de '1' en data + parity debe ser par
 * - ODD:  total de '1' en data + parity debe ser impar
 * - NONE: no se verifica paridad
 *
 * Errores:
 * - parity_error: se activa si la paridad recibida no coincide con la esperada
 * - frame_error: se activa si el bit de STOP no es '1'
 * - Ambas señales permanecen activas hasta el siguiente frame
 */

module uart_rx
  import uart_parity_pkg::*;
#(
    //! @param DATA_BITS Cantidad de bits de datos a recibir
    parameter int DATA_BITS   = 8,
    //! @param OVERSAMPLE Factor de oversampling para control de timing
    parameter int OVERSAMPLE  = 16,
    //! @param PARITY Modo de paridad: PARITY_NONE, PARITY_EVEN, PARITY_ODD
    parameter parity_t PARITY = PARITY_NONE
) (
    // ========================================================================
    // Señales de reloj y reset
    // ========================================================================
    input  logic              clk,            //!< Reloj del sistema
    input  logic              rst_n,          //!< Reset síncrono activo por bajo

    // ========================================================================
    // Interfaz de control de recepción
    // ========================================================================
    input  logic              rx,             //!< Línea serie de entrada
    input  logic              baud_tick,      //!< Tick de oversampling

    // ========================================================================
    // Datos recibidos y señales de estado
    // ========================================================================
    output logic [DATA_BITS-1:0] dout,        //!< Datos recibidos paralelos (LSB primero)
    output logic              rx_done_tick,   //!< Pulso de 1 ciclo al completar frame válido
    output logic              parity_error,   //!< Error de paridad detectado
    output logic              frame_error,    //!< Error de frame (STOP incorrecto)

    // ========================================================================
    // Interfaz FIFO externa (opcional)
    // ========================================================================
    output logic              write_en,       //!< FIFO: pulso de escritura de 1 ciclo
    input  logic              full            //!< FIFO: indica que no admite más escrituras
);

    // ========================================================================
    // Definición de estados de la FSM
    // ========================================================================
    
    /**
     * @brief Estados de la máquina de recepción
     * @details Secuencia: IDLE → START → DATA → [PARITY] → STOP → DONE → IDLE
     */
    typedef enum logic [3:0] {
        S_IDLE,   //!< Espera de flanco de START (rx: 1→0)
        S_START,  //!< Validación del bit de inicio en su centro
        S_DATA,   //!< Recepción de bits de datos (LSB primero)
        S_PARITY, //!< Recepción y verificación de paridad
        S_STOP,   //!< Recepción y verificación de bit de parada
        S_DONE    //!< Estado de finalización (genera pulso rx_done_tick)
    } state_t;

    state_t state;  //!< Estado actual de la FSM

    // ========================================================================
    // Registros internos y contadores
    // ========================================================================
    
    logic [$clog2(OVERSAMPLE):0] os_count;   //!< Contador de oversampling (0..OVERSAMPLE-1)
    logic [$clog2(DATA_BITS):0] bit_index;   //!< Índice del bit de datos actual (0..DATA_BITS-1)
    logic [DATA_BITS-1:0] shifter;           //!< Registro de desplazamiento para recepción
    logic [DATA_BITS-1:0] data_reg;          //!< Copia de datos recibidos completos (para paridad)

    // ========================================================================
    // Lógica de paridad
    // ========================================================================
    
    logic parity_bit_expected;  //!< Bit de paridad esperado (calculado localmente)
    logic parity_bit_received;  //!< Bit de paridad recibido del frame
    logic xor_data;             //!< XOR de todos los bits de datos recibidos

    // ========================================================================
    // Señales de control de timing
    // ========================================================================
    
    /**
     * @brief Indica que se completó un período de bit completo
     * @details Se activa cuando os_count alcanza OVERSAMPLE-1
     */
    logic bit_time_done;
    assign bit_time_done = (os_count == OVERSAMPLE-1);

    /**
     * @brief Indica el punto medio de un bit (momento de muestreo)
     * @details Se activa cuando os_count alcanza (OVERSAMPLE/2 - 1)
     */
    logic bit_mid_sample;
    assign bit_mid_sample = (os_count == (OVERSAMPLE/2 - 1));

    /**
     * @brief Cálculo combinacional del bit de paridad esperado
     * @details La paridad se calcula sobre los bits de datos recibidos:
     * - data_reg: datos completos ya recibidos
     * 
     * Nota: Se usa data_reg para tener el valor completo antes de
     * verificar la paridad en el estado S_PARITY.
     */
    always_comb begin
        xor_data = ^data_reg;                              // Reducción XOR de datos
        case (PARITY)
            PARITY_NONE: parity_bit_expected = 1'b0;       // No se verifica paridad
            PARITY_EVEN: parity_bit_expected = xor_data;   // Bit para hacer total par
            PARITY_ODD:  parity_bit_expected = ~xor_data;  // Bit para hacer total impar
            default:     parity_bit_expected = 1'b0;       // Caso por defecto
        endcase
    end

    // ========================================================================
    // Señales next para lógica combinacional de próximo estado
    // ========================================================================
    
    state_t next_state;                                    //!< Próximo estado de la FSM
    logic [$clog2(OVERSAMPLE):0] next_os_count;            //!< Próximo valor del contador de oversampling
    logic [$clog2(DATA_BITS):0]  next_bit_index;           //!< Próximo índice de bit
    logic [DATA_BITS-1:0]        next_shifter;             //!< Próximo valor del shifter
    logic [DATA_BITS-1:0]        next_data_reg;            //!< Próxima copia de datos
    logic [DATA_BITS-1:0]        next_dout;                //!< Próximo valor de datos de salida
    logic                        next_rx_done_tick;        //!< Próximo valor de pulso done
    logic                        next_parity_error;        //!< Próximo valor de error de paridad
    logic                        next_frame_error;         //!< Próximo valor de error de frame
    logic                        next_parity_bit_received; //!< Próximo valor de bit de paridad recibido
    logic                        next_write_en;            //!< Próximo valor de pulso de escritura FIFO

    // ========================================================================
    // Lógica combinacional de próximo estado y salidas
    // ========================================================================
    
    /**
     * @brief Bloque combinacional principal de la FSM
     * @details Determina el próximo estado y salidas basándose en:
     * - Estado actual
     * - Señal baud_tick (habilita avance de estados)
     * - Contador de oversampling (determina finalización de bit y muestreo)
     * - Línea serie rx (detecta START, muestrea datos y paridad)
     */
    always_comb begin
        // Valores por defecto: mantener estado actual
        next_state               = state;
        next_os_count            = os_count;
        next_bit_index           = bit_index;
        next_shifter             = shifter;
        next_data_reg            = data_reg;
        next_dout                = dout;
        next_rx_done_tick        = 1'b0;  // Pulso por defecto en bajo
        next_parity_error        = parity_error;
        next_frame_error         = frame_error;
        next_parity_bit_received = parity_bit_received;
        next_write_en            = 1'b0;  // Pulso por defecto en bajo

        /**
         * @brief Estado IDLE - Espera de inicio de recepción
         * @details Monitorea la línea rx en busca de un flanco 1→0 (START bit).
         * Al detectarlo, pasa a S_START para validar en el centro del bit.
         * No requiere baud_tick para detectar el flanco.
         */
        if (state == S_IDLE) begin
            // Limpiar errores al inicio de un nuevo frame
            next_parity_error = 1'b0;
            next_frame_error  = 1'b0;
            
            // Detectar flanco de START (rx pasa de 1→0)
            if (rx == 1'b0) begin
                next_state    = S_START;    // Pasar a validación de START
                next_os_count = '0;         // Reiniciar contador de oversampling
                next_bit_index = '0;        // Reiniciar índice de bit
                next_shifter  = '0;         // Limpiar shifter
            end
        end

        // Resto de estados solo avanzan con baud_tick
        else if (baud_tick) begin
            // Gestión del contador de oversampling
            if (bit_time_done) begin
                next_os_count = '0;  // Reiniciar al completar un bit
            end else begin
                next_os_count = os_count + 1'b1;  // Incrementar
            end

            // Máquina de estados principal
            unique case (state)

                /**
                 * @brief Estado START - Validación de bit de inicio
                 * @details Espera hasta el centro del bit (OVERSAMPLE/2 - 1) y verifica
                 * que rx siga en '0'. Si es válido, re-fasea os_count y pasa a DATA.
                 * * Modelo bibliográfico: única validación en mid-bit y luego
                 * * muestreos cada bit_time_done (16 ticks) quedan centrados.
                 */
                S_START: begin
                    if (bit_mid_sample) begin
                        if (rx == 1'b0) begin
                            // START válido → re-fasear y pasar a DATA
                            next_state    = S_DATA;
                            next_os_count = '0;       // Re-iniciar para que el primer DATA quede centrado
                            next_bit_index = '0;      // Asegurar índice en 0
                        end else begin
                            // Falsa alarma (glitch) → volver a IDLE
                            next_state = S_IDLE;
                        end
                    end
                end

                /**
                 * @brief Estado DATA - Recepción de bits de datos
                 * @details Muestrea la línea rx en cada bit_time_done (16 ticks
                 * tras la re-fase de START), lo que equivale al centro del bit.
                 * Desplaza LSB→MSB y, al finalizar, decide si avanzar a PARITY o STOP.
                 */
                S_DATA: begin
                    if (bit_time_done) begin
                        // Desplazar a la derecha e insertar el nuevo bit en MSB
                        next_shifter = {rx, shifter[DATA_BITS-1:1]};

                        if (bit_index == DATA_BITS-1) begin
                            // Último bit recibido → data_reg con valor actualizado del shifter
                            next_data_reg = {rx, shifter[DATA_BITS-1:1]};
                            if (PARITY != PARITY_NONE) begin
                                next_state = S_PARITY;  // Con paridad
                            end else begin
                                next_state = S_STOP;    // Sin paridad
                            end
                        end else begin
                            next_bit_index = bit_index + 1'b1;  // Siguiente bit
                        end
                    end
                end

                /**
                 * @brief Estado PARITY - Recepción y verificación de paridad
                 * @details Solo se alcanza si PARITY != NONE.
                 */
                S_PARITY: begin
                    if (bit_time_done) begin
                        next_parity_bit_received = rx;
                        if (rx != parity_bit_expected) begin
                            next_parity_error = 1'b1;  // Error de paridad detectado
                        end
                        next_state = S_STOP;
                    end
                end

                /**
                 * @brief Estado STOP - Recepción y verificación de bit de parada
                 */
                S_STOP: begin
                    if (bit_time_done) begin
                        if (rx != 1'b1) begin
                            next_frame_error = 1'b1;  // Error de frame detectado
                        end
                        next_state = S_DONE;
                    end
                end

                /**
                 * @brief Estado DONE - Finalización de frame
                 * @details Genera pulso rx_done_tick y presenta datos en dout.
                 * El usuario decide si usa el dato según señales de error.
                 */
                S_DONE: begin
                    next_rx_done_tick = 1'b1;     // Pulso de finalización
                    next_dout = data_reg;         // Presentar datos recibidos
                    // Escritura a FIFO si no está llena
                    if (!full) begin
                        next_write_en = 1'b1;     // Pulso de escritura de 1 ciclo
                    end
                    next_state = S_IDLE;          // Volver a espera
                end
                
                /**
                 * @brief Estado por defecto
                 */
                default: begin
                    next_state = S_IDLE;  // Recuperar a estado seguro
                end
            endcase
        end
    end

    // ========================================================================
    // Bloque secuencial de registro de estado y señales
    // ========================================================================
    
    /**
     * @brief Registro síncrono de estado y actualización de señales
     * @details Estructura de actualización:
     * 1. Reset: inicializa todo a valores seguros
     * 2. Actualización con baud_tick: avance de FSM y contadores
     * 3. Actualización continua: señales de salida (fuera de baud_tick)
     */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Reset asíncrono: valores iniciales seguros
            state              <= S_IDLE;   // Estado inicial
            dout               <= '0;       // Datos en cero
            rx_done_tick       <= 1'b0;     // Sin pulso
            parity_error       <= 1'b0;     // Sin error de paridad
            frame_error        <= 1'b0;     // Sin error de frame
            os_count           <= '0;       // Contador en cero
            bit_index          <= '0;       // Índice en cero
            shifter            <= '0;       // Shifter vacío
            data_reg           <= '0;       // Datos en cero
            parity_bit_received <= 1'b0;    // Bit de paridad en cero
            write_en           <= 1'b0;     // FIFO: sin pulso
        end else begin
            // Actualización de FSM y contadores
            if (state == S_IDLE) begin
                // En IDLE, puede cambiar de estado sin baud_tick (detección de START)
                state              <= next_state;
                os_count           <= next_os_count;
                bit_index          <= next_bit_index;
                shifter            <= next_shifter;
                parity_error       <= next_parity_error;
                frame_error        <= next_frame_error;
            end else if (baud_tick) begin
                // En otros estados, solo avanza con baud_tick
                state              <= next_state;
                os_count           <= next_os_count;
                bit_index          <= next_bit_index;
                shifter            <= next_shifter;
                data_reg           <= next_data_reg;
                parity_error       <= next_parity_error;
                frame_error        <= next_frame_error;
                parity_bit_received <= next_parity_bit_received;
            end

            // Actualización continua (cada ciclo) de salidas
            dout         <= next_dout;
            rx_done_tick <= next_rx_done_tick;
            write_en     <= next_write_en;
        end
    end

    // ========================================================================
    // Assertions de validación de parámetros y reporte de configuración
    // ========================================================================
    
    /**
     * @brief Validación de parámetros y reporte de configuración
     * @details Verifica que los parámetros sean válidos al compilar
     * y muestra la configuración del receptor.
     * 
     * Frame total incluye:
     * - 1 bit de START
     * - DATA_BITS bits de datos
     * - 0 o 1 bit de paridad (según PARITY)
     * - 1 bit de STOP
     */
    initial begin
        // Validación de parámetros
        assert (DATA_BITS > 0) 
            else $fatal(1, "[UART_RX] ERROR: DATA_BITS debe ser mayor que 0 (actual=%0d)", DATA_BITS);
        assert (OVERSAMPLE > 1) 
            else $fatal(1, "[UART_RX] ERROR: OVERSAMPLE debe ser mayor que 1 (actual=%0d)", OVERSAMPLE);
        
        // Reporte de configuración
        $display("==================================================");
        $display("  UART RX Configuration");
        $display("==================================================");
        $display("  DATA_BITS      : %0d", DATA_BITS);
        $display("  PARITY         : %s", 
                 (PARITY==PARITY_NONE) ? "NONE" : 
                 (PARITY==PARITY_EVEN) ? "EVEN" : "ODD");
        $display("  OVERSAMPLE     : %0d", OVERSAMPLE);
        $display("  Sample point   : tick %0d (mid-bit)", OVERSAMPLE/2);
        $display("  Frame length   : %0d bits", 
             1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1);
        if (PARITY==PARITY_NONE) begin
            $display("  Frame structure: START + DATA[%0d] + STOP", DATA_BITS);
        end else begin
            $display("  Frame structure: START + DATA[%0d] + PARITY + STOP", DATA_BITS);
        end
        $display("==================================================");
    end

endmodule
