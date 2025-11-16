`include "alu_timescale.vh"
`include "uart_parity.v"

/**
 * @file uart_tx.sv
 * @brief Transmisor UART parametrizable con soporte de paridad
 *
 * @details Módulo de transmisión UART simple y robusto. Genera frames
 * en formato: START + DATA[LSB→MSB] + [PARITY] + STOP. El tamaño de
 * datos (DATA_BITS), el factor de oversampling (OVERSAMPLE) y el modo
 * de paridad (NONE/EVEN/ODD) son parametrizables.
 *
 * Características ADICIONALES:
 * - Interfaz opcional tipo FIFO: write_o/read_en
 * - Latch de tx_start para capturar pulsos de 1 ciclo
 *
 * Estructura del frame transmitido:
 * - START: 1 bit (siempre '0')
 * - DATA: DATA_BITS (LSB primero)
 * - PARITY: 1 bit opcional (si PARITY != NONE)
 * - STOP: 1 bit (siempre '1')
 *
 * Máquina de estados (FSM):
 * - S_IDLE   → Espera tx_start o write_o (línea en '1')
 * - S_START  → Transmite START ('0') durante 1 bit
 * - S_DATA   → Transmite DATA LSB→MSB
 * - S_PARITY → Transmite bit de paridad (si aplica)
 * - S_STOP   → Transmite STOP ('1') durante 1 bit
 * - S_DONE   → Pulso tx_done_tick y retorno a IDLE
 *
 * Temporización:
 * - Cada bit dura OVERSAMPLE ticks de baud_tick (p.ej. x16 del baudrate)
 * - El avance de la FSM y contadores se realiza con baud_tick
 *
 * Paridad:
 * - Calculada sobre data_reg (copia de los DATA_BITS originales)
 * - EVEN: bit de paridad = XOR(data_reg), total de '1' par
 * - ODD:  bit de paridad = ~XOR(data_reg), total de '1' impar
 * - NONE: no se agrega bit de paridad
 */

module uart_tx
  import uart_parity_pkg::*;
#(
    //! @param DATA_BITS Cantidad de bits de datos a transmitir
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
    // Interfaz de control de transmisión
    // ========================================================================
    input  logic              tx_start,       //!< Pulso de 1 ciclo para iniciar transmisión
    input  logic              baud_tick,      //!< Tick de oversampling

    // ========================================================================
    // Datos a transmitir
    // ========================================================================
    input  logic [DATA_BITS-1:0] din,         //!< Datos paralelos (se transmiten LSB primero)

    // ========================================================================
    // Interfaz FIFO externa (opcional)
    // ========================================================================
    input  logic              write_o,        //!< FIFO: indica dato disponible (alternativa a tx_start)
    output logic              read_en,        //!< FIFO: pulso de consumo de 1 ciclo

    // ========================================================================
    // Salidas de transmisión
    // ========================================================================
    output logic              tx,             //!< Línea serie de salida (idle='1', start='0')
    output logic              tx_done_tick    //!< Pulso de 1 ciclo al completar frame
);

    // ========================================================================
    // Definición de estados de la FSM
    // ========================================================================
    
    /**
     * @brief Estados de la máquina de transmisión
    * @details Secuencia: IDLE → START → DATA → [PARITY] → STOP → DONE → IDLE
     */
    typedef enum logic [3:0] {
        S_IDLE,   //!< Espera de tx_start o write_o, línea en alto (idle)
        S_START,  //!< Transmisión de bit de inicio (siempre '0')
        S_DATA,   //!< Transmisión de bits de datos (LSB primero)
        S_PARITY, //!< Transmisión de bit de paridad (condicional)
        S_STOP,   //!< Transmisión de bit de parada (siempre '1')
        S_DONE    //!< Estado de finalización (genera pulso tx_done_tick)
    } state_t;

    state_t state;  //!< Estado actual de la FSM

    // ========================================================================
    // Registros internos y contadores
    // ========================================================================
    
    logic [$clog2(OVERSAMPLE):0] os_count;   //!< Contador de oversampling (0..OVERSAMPLE-1)
    logic [$clog2(DATA_BITS):0] bit_index;   //!< Índice del bit de datos actual (0..DATA_BITS-1)
    logic [DATA_BITS-1:0] shifter;           //!< Registro de desplazamiento para transmisión
    logic [DATA_BITS-1:0] data_reg;          //!< Copia de datos originales (para paridad)

    // ========================================================================
    // Lógica de paridad
    // ========================================================================
    
    logic parity_bit;  //!< Bit de paridad calculado
    logic xor_data;    //!< XOR de todos los bits de datos

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
    * @brief Cálculo combinacional del bit de paridad
    * @details La paridad se calcula sobre los bits de datos transmitidos:
    * - data_reg: datos originales (sin shiftear)
     * 
     * Nota: Se usa data_reg en lugar de shifter para tener el valor completo
     * sin modificar durante el cálculo.
     */
    always_comb begin
        xor_data = ^data_reg;                     // Reducción XOR de datos
        case (PARITY)
            PARITY_NONE: parity_bit = 1'b0;       // No se transmite paridad
            PARITY_EVEN: parity_bit = xor_data;   // Bit para hacer total par
            PARITY_ODD:  parity_bit = ~xor_data;  // Bit para hacer total impar
            default:     parity_bit = 1'b0;       // Caso por defecto
        endcase
    end

    /**
     * @brief Latch para capturar pulsos de tx_start
     * @details Permite capturar un pulso de tx_start de 1 ciclo incluso si
     * llega cuando baud_tick está en bajo. Se limpia al iniciar la transmisión.
     */
    logic tx_start_pending;

    // ========================================================================
    // Señales next para lógica combinacional de próximo estado
    // ========================================================================
    
    state_t next_state;                             //!< Próximo estado de la FSM
    logic [$clog2(OVERSAMPLE):0] next_os_count;     //!< Próximo valor del contador de oversampling
    logic [$clog2(DATA_BITS):0]  next_bit_index;    //!< Próximo índice de bit
    logic [DATA_BITS-1:0]        next_shifter;      //!< Próximo valor del shifter
    logic [DATA_BITS-1:0]        next_data_reg;     //!< Próxima copia de datos
    logic                        next_tx;           //!< Próximo valor de línea serie
    logic                        next_tx_done_tick; //!< Próximo valor de pulso done
    logic                        next_read_en;      //!< Próximo valor de pulso FIFO

    // ========================================================================
    // Lógica combinacional de próximo estado y salidas
    // ========================================================================
    
    /**
     * @brief Bloque combinacional principal de la FSM
     * @details Determina el próximo estado y salidas basándose en:
     * - Estado actual
     * - Señal baud_tick (habilita avance de estados)
     * - Contador de oversampling (determina finalización de bit)
     * - Señales de control (tx_start_pending, write_o)
     */
    always_comb begin
        // Valores por defecto: mantener estado actual
        next_state        = state;
        next_os_count     = os_count;
        next_bit_index    = bit_index;
        next_shifter      = shifter;
        next_data_reg     = data_reg;
        next_tx           = tx;
        next_tx_done_tick = 1'b0;  // Pulso por defecto en bajo
        next_read_en      = 1'b0;  // Pulso por defecto en bajo

        /**
         * @brief Estado IDLE - Espera de inicio de transmisión
         * @details Mantiene línea en alto (idle). Inicia transmisión si:
         * - tx_start_pending está activo (pulso capturado previamente)
         * - write_o está activo (dato disponible en FIFO)
         * Al iniciar, captura datos; genera pulso read_en si aplica.
         * Opera sin necesidad de baud_tick
         */
        if (state == S_IDLE) begin
            next_tx = 1'b1;  // Línea idle en alto
            // Detectar solicitud de transmisión
            if (tx_start_pending || write_o) begin
                next_shifter   = din;         // Cargar datos a shifter
                next_data_reg  = din;         // Copiar para cálculo de paridad
                next_bit_index = '0;          // Reiniciar índice
                next_os_count  = '0;          // Reiniciar contador
                next_state     = S_START;     // Pasar a START
                next_tx        = 1'b0;        // Bajar línea (START bit)
                // Pulso read_en solo si se usa FIFO
                if (write_o) next_read_en = 1'b1;
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
                 * @brief Estado START - Transmisión de bit de inicio
                 * @details Mantiene línea en bajo durante OVERSAMPLE ticks.
                 */
                S_START: begin
                    next_tx = 1'b0;  // START bit siempre es '0'
                    if (bit_time_done) begin
                        next_state = S_DATA;  // Pasar a transmisión de datos
                    end
                end

                /**
                 * @brief Estado DATA - Transmisión de bits de datos
                 * @details Transmite bits LSB primero, desplazando shifter a la derecha.
                 * Tras transmitir el último bit, pasa a PARITY o STOP.
                 */
                S_DATA: begin
                    next_tx = shifter[0];  // Transmitir LSB
                    if (bit_time_done) begin
                        // Desplazar a la derecha (siguiente bit a transmitir)
                        next_shifter = shifter >> 1;
                        if (bit_index == DATA_BITS-1) begin
                            // Último bit → decidir siguiente etapa según paridad
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
                 * @brief Estado PARITY - Transmisión de bit de paridad
                 * @details Solo se alcanza si PARITY != NONE.
                 * Transmite el bit de paridad calculado combinacionalmente.
                 */
                S_PARITY: begin
                    next_tx = parity_bit;  // Transmitir bit de paridad
                    if (bit_time_done) begin
                        next_state = S_STOP;  // Pasar a bit de parada
                    end
                end

                /**
                 * @brief Estado STOP - Transmisión de bit de parada
                 * @details Mantiene línea en alto durante OVERSAMPLE ticks.
                 */
                S_STOP: begin
                    next_tx = 1'b1;  // STOP bit siempre es '1'
                    if (bit_time_done) begin
                        next_state = S_DONE;  // Pasar a finalización
                    end
                end

                /**
                 * @brief Estado DONE - Finalización de frame
                 * @details Genera pulso tx_done_tick y retorna a IDLE.
                 */
                S_DONE: begin
                    next_tx           = 1'b1;     // Mantener línea idle
                    next_tx_done_tick = 1'b1;     // Pulso de finalización
                    next_state        = S_IDLE;   // Volver a espera
                end
                
                /**
                 * @brief Estado por defecto
                 */
                default: begin
                    next_state = S_IDLE;  // Recuperar a estado seguro
                    next_tx    = 1'b1;    // Línea idle
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
     * 2. Latch de tx_start: captura pulsos de 1 ciclo en IDLE
     * 3. Actualización con baud_tick: avance de FSM y contadores
     * 4. Actualización continua: tx y tx_done_tick (fuera de baud_tick)
     * 5. Gestión de pulsos: read_en se mantiene 1 ciclo
     */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            // Reset asíncrono: valores iniciales seguros
            state            <= S_IDLE;   // Estado inicial
            tx               <= 1'b1;     // Línea idle en alto
            tx_done_tick     <= 1'b0;     // Sin pulso
            os_count         <= '0;       // Contador en cero
            bit_index        <= '0;       // Índice en cero
            shifter          <= '0;       // Shifter vacío
            data_reg         <= '0;       // Datos en cero
            read_en          <= 1'b0;     // Sin pulso FIFO
            tx_start_pending <= 1'b0;     // Sin petición pendiente
        end else begin
            // Captura de pulso tx_start cuando estamos en IDLE
            // Permite capturar pulsos de 1 ciclo incluso sin baud_tick
            if (state == S_IDLE && tx_start) begin
                tx_start_pending <= 1'b1;
            end
            
            // Actualización de FSM y contadores solo con baud_tick
            if (baud_tick) begin
                state     <= next_state;      // Avanzar estado
                os_count  <= next_os_count;   // Actualizar contador oversampling
                bit_index <= next_bit_index;  // Actualizar índice de bit
                shifter   <= next_shifter;    // Actualizar shifter
                data_reg  <= next_data_reg;   // Actualizar copia de datos
                read_en   <= next_read_en;    // Pulso FIFO alineado a baud_tick

                // Limpiar latch al iniciar transmisión
                if (state == S_IDLE && (tx_start_pending || write_o)) begin
                    tx_start_pending <= 1'b0;
                end
            end else begin
                read_en <= 1'b0; // Garantizar que read_en sea un pulso de 1 ciclo
            end

            // Actualización continua (cada ciclo) de salidas
            tx           <= next_tx;          
            tx_done_tick <= next_tx_done_tick; // Actualizar pulso done
        end
    end

    // ========================================================================
    // Assertions de validación de parámetros y reporte de configuración
    // ========================================================================
    
    /**
     * @brief Validación de parámetros y reporte de configuración
     * @details Verifica que los parámetros sean válidos al compilar
     * y muestra la configuración del transmisor.
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
            else $fatal(1, "[UART_TX] ERROR: DATA_BITS debe ser mayor que 0 (actual=%0d)", DATA_BITS);
        assert (OVERSAMPLE > 1) 
            else $fatal(1, "[UART_TX] ERROR: OVERSAMPLE debe ser mayor que 1 (actual=%0d)", OVERSAMPLE);
        
        // Reporte de configuración
        $display("==================================================");
        $display("  UART TX Configuration");
        $display("==================================================");
        $display("  DATA_BITS      : %0d", DATA_BITS);
        $display("  PARITY         : %s", 
                 (PARITY==PARITY_NONE) ? "NONE" : 
                 (PARITY==PARITY_EVEN) ? "EVEN" : "ODD");
        $display("  OVERSAMPLE     : %0d", OVERSAMPLE);
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
