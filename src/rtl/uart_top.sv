`include "alu_timescale.vh"
`include "uart_parity.v"

/**
 * @file uart_top.sv
 * @brief Módulo top UART completo con FIFOs de TX/RX y generador de baudrate
 *
 * @details Este módulo integra una UART completa y robusta para conectar la ALU 
 * con la PC a través de USB-UART. Proporciona una interfaz limpia y desacoplada
 * mediante FIFOs síncronas que separan los dominios de velocidad entre la lógica
 * de usuario (ALU) y la comunicación serie (UART).
 *
 * Componentes integrados:
 * - uart_baudrate_gen: Generador de ticks de oversampling x16
 * - uart_rx: Receptor UART con detección de errores
 * - uart_tx: Transmisor UART con interfaz FIFO
 * - sync_fifo (x2): Buffers de recepción y transmisión
 *
 * Flujo de datos de recepción (PC → ALU) con control de flujo:
 * 1. uart_rx recibe bits serie desde PC
 * 2. Al completar frame, verifica rx_fifo_full
 * 3. Si !full: genera rx_write_en, escribe rx_dout en FIFO_RX
 *    Si full: descarta frame, continúa recepción
 * 4. ALU lee datos cuando read_en_rx_top=1
 * 5. FIFO_RX entrega data_out_rx con data_valid_rx
 *
 * Flujo de datos de transmisión (ALU → PC):
 * 1. ALU escribe tx_data_in en FIFO_TX
 * 2. uart_tx detecta dato disponible (write_o = ~tx_fifo_empty)
 * 3. TX genera read_en para consumir dato de FIFO_TX
 * 4. TX transmite bits serie hacia PC
 *
 * Características principales:
 * - FIFO_RX: Desacopla la recepción UART de la lectura por parte de la ALU
 * - FIFO_TX: Desacopla la escritura de la ALU de la transmisión UART
 *
 * Parámetros configurables:
 * - DATA_BITS: Ancho de datos UART (típicamente 8)
 * - PARITY: Modo de paridad (PARITY_NONE, PARITY_EVEN, PARITY_ODD)
 * - OVERSAMPLE: Factor de oversampling (típicamente 16)
 * - CLOCK_FREQ: Frecuencia del reloj del sistema (12 MHz por defecto)
 * - BAUD_RATE: Tasa de baudios (9600 por defecto)
 * - FIFO_DEPTH: Profundidad de las FIFOs (16 por defecto)
 *
 * Interfaz externa:
 * - Lado PC: rx (entrada), tx (salida)
 * - Lado ALU: write_en_tx_top, tx_data_in, read_en_rx_top, data_out_rx
 * - Señales de estado: *_empty, *_full, *_level, *_error
 *
 * Consideraciones de diseño:
 * - FIFO_RX con control de flujo (full conectado a uart_rx)
 *   Si FIFO_RX se llena, uart_rx descarta frames pero NO se bloquea
 *   → Dimensionar FIFO_DEPTH según tasa de procesamiento de la ALU
 * - FIFO_TX alimenta TX automáticamente vía write_o
 *   TX consume datos solo cuando está listo (lectura controlada)
 * - Errores de RX se exportan independientemente del estado de FIFO_RX
 *   → Frames con error se escriben en FIFO SIEMPRE (ALU decide qué hacer)
 */

module uart_top
  import uart_parity_pkg::*;
#(
    //! @param DATA_BITS Cantidad de bits de datos UART
    parameter int DATA_BITS   = 8,
    //! @param PARITY Modo de paridad: PARITY_NONE, PARITY_EVEN, PARITY_ODD
    parameter parity_t PARITY = PARITY_NONE,
    //! @param OVERSAMPLE Factor de oversampling para control de timing
    parameter int OVERSAMPLE  = 16,
    //! @param CLOCK_FREQ Frecuencia del reloj del sistema en Hz
    parameter int CLOCK_FREQ  = 12_000_000,
    //! @param BAUD_RATE Tasa de baudios deseada en bps
    parameter int BAUD_RATE   = 9600,
    //! @param FIFO_DEPTH Profundidad de las FIFOs de TX y RX
    parameter int FIFO_DEPTH  = 32
) (
    // ========================================================================
    // Señales de reloj y reset
    // ========================================================================
    input  logic              clk,                     //!< Reloj del sistema
    input  logic              rst,                     //!< Reset síncrono activo por BAJO (tiene una pullup interna)

    // ========================================================================
    // Interfaz UART física (hacia PC)
    // ========================================================================
    input  logic              rx,                      //!< Línea serie de entrada desde PC
    output logic              tx,                      //!< Línea serie de salida hacia PC

    // ========================================================================
    // Interfaz de transmisión (desde ALU hacia PC)
    // ========================================================================
    input  logic              write_en_tx_top,         //!< ALU escribe en FIFO_TX
    input  logic [DATA_BITS-1:0] tx_data_in,           //!< Datos a transmitir desde ALU
    output logic              tx_done_tick,            //!< Pulso al completar transmisión de un frame

    // ========================================================================
    // Interfaz de recepción (desde PC hacia ALU)
    // ========================================================================
    input  logic              read_en_rx_top,          //!< ALU lee desde FIFO_RX
    output logic [DATA_BITS-1:0] data_out_rx,          //!< Datos recibidos hacia ALU
    output logic              data_valid_rx,           //!< Dato válido disponible en data_out_rx
    output logic              rx_done_tick,            //!< Pulso al completar recepción de un frame

    // ========================================================================
    // Estado de FIFO de recepción (RX)
    // ========================================================================
    output logic              rx_fifo_empty,               //!< FIFO_RX vacía (sin datos)
    output logic              rx_fifo_full,                //!< FIFO_RX llena (no admite más datos)
    output logic [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_level, //!< Nivel de ocupación FIFO_RX

    // ========================================================================
    // Estado de FIFO de transmisión (TX)
    // ========================================================================
    output logic              tx_fifo_empty,               //!< FIFO_TX vacía (sin datos)
    output logic              tx_fifo_full,                //!< FIFO_TX llena (no admite más datos)
    output logic [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_level, //!< Nivel de ocupación FIFO_TX

    // ========================================================================
    // Señales de error de recepción
    // ========================================================================
    output logic              parity_error,            //!< Error de paridad detectado en RX
    output logic              frame_error              //!< Error de frame detectado en RX
);

    // ========================================================================
    // Señales internas del generador de baudrate
    // ========================================================================
    
    /**
     * @brief Ticks de temporización generados por uart_baudrate_gen
     * @details El generador produce dos señales de tick:
     * - baud_tick: Frecuencia x1 del baudrate (ej. 9600 Hz @ 9600 bps) → No usado actualmente
     * - baud_x16_tick: Frecuencia x16 del baudrate (ej. 153.6 kHz @ 9600 bps)
     *   Usado por TX y RX para oversampling y control de timing preciso
     * 
     * El oversampling x16 permite:
     * - RX: Muestreo en el centro del bit (tick 8 de 16)
     * - TX: Generación precisa de cada bit durante 16 ticks
     */
    logic baud_tick;       //!< Tick de baudrate x1 (no usado en esta configuración)
    logic baud_x16_tick;   //!< Tick de oversampling x16 (usado por TX y RX)

    // ========================================================================
    // Señales internas de FIFO_RX (FROM PC → ALU)
    // ========================================================================
    
    /**
     * @brief Señales de interconexión entre uart_rx y FIFO_RX
     * @details Flujo de recepción:
     * 1. uart_rx recibe frame completo y lo decodifica → rx_dout contiene los DATA_BITS recibidos (LSB primero)
     * 2. uart_rx genera rx_write_en internamente cuando completa frame
     * 3. rx_fifo_full retroalimenta a uart_rx para control de flujo → Si FIFO está llena, uart_rx NO escribe y se pierde el frame
     * 
     * Ventaja del control de flujo:
     * - uart_rx conoce estado de FIFO_RX antes de escribir
     * - Previene sobrescritura de datos en FIFO llena
     */
    logic [DATA_BITS-1:0]  rx_dout;               //!< Datos desde uart_rx hacia FIFO_RX
    logic                  rx_write_en;           //!< Escritura desde uart_rx hacia FIFO_RX
    
    // ========================================================================
    // Señales internas de FIFO_TX (FROM ALU → PC)
    // ========================================================================
    
    /**
     * @brief Señales de interconexión entre FIFO_TX y uart_tx
     * @details Flujo de transmisión:
     * 1. FIFO_TX almacena datos escritos por ALU → tx_fifo_data_out contiene el dato en el frente de la cola
     * 2. tx_write_o indica dato disponible (~empty)
     * 3. uart_tx genera tx_fifo_read_en para consumir dato
     * 4. FIFO_TX avanza al siguiente dato en la cola
     * 
     * La señal tx_fifo_data_valid no se usa actualmente, ya que
     * tx_write_o es suficiente para indicar dato disponible.
     */
    logic [DATA_BITS-1:0]  tx_fifo_data_out;      //!< Datos desde FIFO_TX hacia uart_tx
    logic                  tx_fifo_data_valid;    //!< Dato válido desde FIFO_TX (no usado)
    logic                  tx_fifo_read_en;       //!< Lectura de FIFO_TX (pulso desde TX)
    logic                  tx_write_o;            //!< Dato disponible para TX (= ~empty)

    // ========================================================================
    // Instancia del generador de baudrate
    // ========================================================================
    
    /**
     * @brief Generador de baudrate configurable
     * @details Produce dos señales de tick:
     * - baud_tick: x1 del baudrate (9600 Hz por defecto)
     * - baud_x16_tick: x16 del baudrate (153.6 kHz por defecto)
     * El tick x16 se usa para oversampling en TX y RX.
     */
    uart_baudrate_gen #(
        .CLOCK_FREQ (CLOCK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_baudrate_gen (
        .clk           (clk),
        .rst           (rst),
        .baud_tick     (baud_tick),
        .baud_x16_tick (baud_x16_tick)
    );

    // ========================================================================
    // Instancia del receptor UART (uart_rx)
    // ========================================================================
    
    /**
     * @brief Instancia del receptor UART con detección de errores y control de flujo
     * @details Implementa una FSM robusta para recepción de frames serie con
     * integración directa a FIFO mediante señales write_en y full:
     * 
     * Secuencia de recepción con control de flujo:
     * 1. S_IDLE: Monitorea línea rx en busca de flanco 1→0 (START bit)
     * 2. S_START: Valida START bit en su centro (mitad de período)
     * 3. S_DATA: Muestrea DATA_BITS bits en el centro de cada período
     * 4. S_PARITY: Muestrea y verifica bit de paridad (si aplica)
     * 5. S_STOP: Verifica bit de parada (debe ser '1')
     * 6. S_DONE: Verifica full antes de activar write_en
     *    - Si full=0: Genera write_en por 1 ciclo, datos se escriben en FIFO
     *    - Si full=1: NO genera write_en, frame se descarta (pérdida)
     * 
     * Control de flujo inteligente:
     * - uart_rx consulta señal full en estado S_DONE
     * - Solo escribe en FIFO si full=0 (espacio disponible)
     * - Si full=1, frame se pierde pero uart_rx continúa operando
     * 
     * Detección de errores:
     * - parity_error: Se activa si paridad recibida != paridad calculada
     * - frame_error: Se activa si bit de STOP != '1' → Indica pérdida de sincronización o ruido en la línea
     * 
     * Ambas señales de error permanecen activas hasta que la FSM vuelva a IDLE.
     */
    uart_rx #(
        .DATA_BITS  (DATA_BITS),
        .OVERSAMPLE (OVERSAMPLE),
        .PARITY     (PARITY)
    ) u_uart_rx (
        .clk           (clk),
        .rst           (rst),
        .rx            (rx),
        .baud_tick     (baud_x16_tick),
        .dout          (rx_dout),
        .rx_done_tick  (rx_done_tick),      
        .parity_error  (parity_error),
        .frame_error   (frame_error),
        .write_en      (rx_write_en),       // Pulso de escritura hacia FIFO_RX
        .full          (rx_fifo_full)       // Retroalimentación desde FIFO_RX
    );

    // ========================================================================
    // Instancia de FIFO de recepción (FIFO_RX: FROM PC → ALU)
    // ========================================================================
    
    /**
     * @brief Instancia de FIFO síncrona para desacoplar recepción UART de lectura por ALU
     * @details Implementa una cola circular con punteros read/write independientes
     * que permite almacenar hasta FIFO_DEPTH frames recibidos antes de que la ALU
     * los procese. Esto es crítico para evitar pérdida de datos cuando:
     * - ALU está ocupada procesando datos anteriores
     * - Múltiples frames llegan en ráfaga desde PC
     * - Diferencia de velocidad entre baudrate y procesamiento ALU
     */
    sync_fifo #(
        .DATA_WIDTH (DATA_BITS),
        .DEPTH      (FIFO_DEPTH)
    ) u_fifo_rx (
        .clk        (clk),
        .rst        (rst),
        .write_en   (rx_write_en),      // Escritura controlada desde uart_rx
        .data_in    (rx_dout),          // Datos desde uart_rx
        .read_en    (read_en_rx_top),   // Lectura desde ALU
        .data_out   (data_out_rx),      // Datos hacia ALU
        .data_valid (data_valid_rx),    // Dato válido disponible
        .full       (rx_fifo_full),     // Estado: FIFO llena
        .empty      (rx_fifo_empty),    // Estado: FIFO vacía
        .level      (rx_fifo_level)     // Nivel de ocupación
    );

    // ========================================================================
    // Instancia del transmisor UART (uart_tx)
    // ========================================================================
    
    /**
     * @brief Instancia del transmisor UART con interfaz tipo FIFO y control de flujo
     * @details Implementa una FSM robusta para transmisión de frames serie con
     * integración directa a FIFO mediante señales write_o y read_en:
     * 
     * Secuencia de transmisión con control de flujo:
     * 1. S_IDLE: Espera a que write_o se active (dato disponible en FIFO_TX)
     * 2. S_START: Transmite bit de START ('0') durante OVERSAMPLE ticks
     * 3. S_DATA: Transmite DATA_BITS bits (LSB primero) durante OVERSAMPLE ticks c/u
     * 4. S_PARITY: Transmite bit de paridad (si aplica) durante OVERSAMPLE ticks
     * 5. S_STOP: Transmite bit de STOP ('1') durante OVERSAMPLE ticks
     * 6. S_DONE: Genera pulsos read_en y tx_done_tick, vuelve a S_IDLE
     *    - read_en: Pulso por 1 ciclo hacia FIFO_TX para consumir dato transmitido
     *    - tx_done_tick: Pulso por 1 ciclo indicando frame completado
     * 
     * Control de flujo inteligente:
     * - uart_tx solo inicia transmisión si write_o=1 (dato disponible en FIFO_TX)
     * - Al completar transmisión, genera read_en para que FIFO_TX avance al siguiente dato
     * - Si FIFO_TX vacía (write_o=0), uart_tx permanece en S_IDLE sin transmitir
     * 
     * Interfaz con FIFO_TX:
     * - write_o (entrada): Indica dato disponible (~tx_fifo_empty), actúa como trigger de inicio
     * - din (entrada): Datos paralelos desde FIFO_TX (DATA_BITS bits)
     * - read_en (salida): Pulso de consumo hacia FIFO_TX al completar transmisión
     * 
     * Ventajas del diseño:
     * - Transmisión automática: No requiere señal tx_start externa
     * - Desacoplamiento: ALU escribe en FIFO_TX sin esperar a uart_tx
     * - Throughput continuo: Si FIFO_TX tiene datos, uart_tx transmite sin pausas
     * 
     * La señal tx_start está conectada a 1'b0 ya que se usa la interfaz FIFO (write_o).
     */
    uart_tx #(
        .DATA_BITS  (DATA_BITS),
        .OVERSAMPLE (OVERSAMPLE),
        .PARITY     (PARITY)
    ) u_uart_tx (
        .clk           (clk),
        .rst           (rst),
        .tx_start      (1'b0),              // No usado: interfaz FIFO en uso
        .baud_tick     (baud_x16_tick),
        .din           (tx_fifo_data_out),  // Datos desde FIFO_TX
        .write_o       (tx_write_o),        // Dato disponible (~empty)
        .read_en       (tx_fifo_read_en),   // Pulso de consumo hacia FIFO_TX
        .tx            (tx),                // Línea serie hacia PC
        .tx_done_tick  (tx_done_tick)       // Pulso al completar frame
    );

    // ========================================================================
    // Instancia de FIFO de transmisión (FIFO_TX: FROM ALU → PC)
    // ========================================================================
    
    /**
     * @brief Instancia de FIFO síncrona para desacoplar escritura de ALU de transmisión UART
     * @details Implementa una cola circular que permite a la ALU escribir múltiples
     * frames de transmisión sin esperar a que uart_tx complete el frame actual.
     * Esto es especialmente útil cuando:
     * - ALU genera datos más rápido que la velocidad del baudrate
     * - Se desea enviar ráfagas de datos hacia PC
     * - ALU necesita respuesta inmediata (no bloqueante)
     */
    sync_fifo #(
        .DATA_WIDTH (DATA_BITS),
        .DEPTH      (FIFO_DEPTH)
    ) u_fifo_tx (
        .clk        (clk),
        .rst        (rst),  
        .write_en   (write_en_tx_top),      // Escritura desde ALU
        .data_in    (tx_data_in),           // Datos desde ALU
        .read_en    (tx_fifo_read_en),      // Lectura desde uart_tx
        .data_out   (tx_fifo_data_out),     // Datos hacia uart_tx
        .data_valid (tx_fifo_data_valid),   // Dato válido disponible
        .full       (tx_fifo_full),         // Estado: FIFO llena
        .empty      (tx_fifo_empty),        // Estado: FIFO vacía
        .level      (tx_fifo_level)         // Nivel de ocupación
    );

    /**
     * @brief Señal de dato disponible para transmisión
     * @details Se activa cuando FIFO_TX tiene al menos un dato disponible.
     * Esta señal se conecta a write_o de uart_tx para indicar dato listo.
     */
    assign tx_write_o = ~tx_fifo_empty;

    // ========================================================================
    // Assertions de validación de parámetros y reporte de configuración
    // ========================================================================
    
    /**
     * @brief Validación de parámetros y reporte de configuración
     * @details Verifica que los parámetros sean válidos al compilar
     * y muestra la configuración completa del módulo top.
     */
    initial begin
        // Validación de parámetros
        assert (DATA_BITS > 0) 
            else $fatal(1, "[UART_TOP] ERROR: DATA_BITS debe ser mayor que 0 (actual=%0d)", DATA_BITS);
        assert (OVERSAMPLE > 1) 
            else $fatal(1, "[UART_TOP] ERROR: OVERSAMPLE debe ser mayor que 1 (actual=%0d)", OVERSAMPLE);
        assert (FIFO_DEPTH >= 2) 
            else $fatal(1, "[UART_TOP] ERROR: FIFO_DEPTH debe ser >= 2 (actual=%0d)", FIFO_DEPTH);
        assert (CLOCK_FREQ > 0) 
            else $fatal(1, "[UART_TOP] ERROR: CLOCK_FREQ debe ser mayor que 0 (actual=%0d)", CLOCK_FREQ);
        assert (BAUD_RATE > 0) 
            else $fatal(1, "[UART_TOP] ERROR: BAUD_RATE debe ser mayor que 0 (actual=%0d)", BAUD_RATE);
        
        // Reporte de configuración
        $display("==================================================");
        $display("  UART TOP Configuration");
        $display("==================================================");
        $display("  DATA_BITS      : %0d", DATA_BITS);
        $display("  PARITY         : %s", 
                 (PARITY==PARITY_NONE) ? "NONE" : 
                 (PARITY==PARITY_EVEN) ? "EVEN" : "ODD");
        $display("  OVERSAMPLE     : %0d", OVERSAMPLE);
        $display("  CLOCK_FREQ     : %0d Hz", CLOCK_FREQ);
        $display("  BAUD_RATE      : %0d bps", BAUD_RATE);
        $display("  FIFO_DEPTH     : %0d positions", FIFO_DEPTH);
        $display("  FIFO_RX        : %0d x %0d bits (%0d bits total)", 
                 FIFO_DEPTH, DATA_BITS, FIFO_DEPTH * DATA_BITS);
        $display("  FIFO_TX        : %0d x %0d bits (%0d bits total)", 
                 FIFO_DEPTH, DATA_BITS, FIFO_DEPTH * DATA_BITS);
        $display("  Frame length   : %0d bits", 
             1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1);
        if (PARITY==PARITY_NONE) begin
            $display("  Frame structure: START + DATA[%0d] + STOP", DATA_BITS);
        end else begin
            $display("  Frame structure: START + DATA[%0d] + PARITY + STOP", DATA_BITS);
        end
        $display("  ");
        $display("  Timing Analysis:");
        $display("  ---------------");
        $display("  Baud divisor      : %0d (ticks/bit @ x1)", 
                 CLOCK_FREQ / BAUD_RATE);
        $display("  Baud x16 divisor  : %0d (ticks/bit @ x16)", 
                 CLOCK_FREQ / (BAUD_RATE * OVERSAMPLE));
        $display("  Bit period        : %0.2f µs", 
                 1e6 / real'(BAUD_RATE));
        $display("  Frame period      : %0.2f µs (%0d bits)", 
                 1e6 * (1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1) / real'(BAUD_RATE),
                 1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1);
        $display("  Max throughput    : %0d bytes/s", 
                 BAUD_RATE / (1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1));
        $display("  FIFO RX latency   : ~%0.2f ms + 1 cycle", 
                 1e3 * (1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1) / real'(BAUD_RATE));
        $display("  FIFO TX latency   : 1 cycle + ~%0.2f ms", 
                 1e3 * (1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1) / real'(BAUD_RATE));
        $display("  Total FIFO buffer : %0.2f ms @ max rate", 
                 1e3 * FIFO_DEPTH * (1 + DATA_BITS + ((PARITY==PARITY_NONE)?0:1) + 1) / real'(BAUD_RATE));
        $display("==================================================");
    end

endmodule
