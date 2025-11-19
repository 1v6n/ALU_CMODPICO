`include "alu_timescale.vh"

/**
 * FSM Decodificador de Paquetes UART
 *
 * Este módulo implementa una máquina de estados finitos que lee desde una UART RX FIFO
 * externa y decodifica paquetes con formato: [STX][CMD][DATA][ETX]
 *
 * STX = 0x02 (Start of Text)
 * ETX = 0x03 (End of Text)
 * CMD = {A, B, C, E} (Tipo de comando)
 * DATA = Payload de 8 bits
 *
 * La UART RX FIFO externa contiene: [0x02][0x41][0x12][0x03][0x02][0x42][0x34][0x03]...
 * Este decoder identifica el comando y aplica directamente la carga correspondiente a los registros
 * A, B u opcode de la ALU (además de generar el pulso de ejecución para `E`).
 *
 */
module uart_packet_decoder #(
    parameter int DATA_WIDTH = 8
) (
    //! @brief  Reloj y reset
    input  wire clk,
    input  wire rst,

    //! @brief  Interfaz de lectura desde la FIFO externa de la UART
    output wire rx_fifo_read_en,
    input  wire rx_fifo_empty,
    input  wire rx_fifo_data_valid,
    input  wire [7:0] rx_fifo_data,

    //! @brief  Interfaz directa al banco de registros/control de la ALU
    output wire [DATA_WIDTH-1:0] alu_data,
    output wire                  load_a,
    output wire                  load_b,
    output wire                  load_sel,
    output wire                  exec_pulse,

    //! @brief  Salidas de estado
    output wire decoder_error,
    output wire packet_complete
);

    //! @brief Enumeración de la máquina de estados
    typedef enum logic [1:0] {
        S0_WAIT_START,
        S1_RECV_CMD,
        S2_RECV_DATA,
        S3_WAIT_END
    } state_t;

    //! @brief Registros de estado
    state_t current_state, next_state;

    //! @brief Registros internos
    reg [7:0] stored_cmd;
    reg [DATA_WIDTH-1:0] stored_data;
    reg [DATA_WIDTH-1:0] buffer_a;
    reg [DATA_WIDTH-1:0] buffer_b;
    reg [DATA_WIDTH-1:0] buffer_sel;

    //! @brief Señales de control para la FIFO de entrada
    reg fifo_read;

    //! @brief Control de bytes consumidos
    reg [7:0] current_rx_byte;
    reg current_rx_valid;

    //! @brief Seguimiento de errores
    reg invalid_cmd_error;
    reg invalid_framing_error;

    typedef enum reg [2:0] {
        EXEC_IDLE,
        EXEC_LOAD_SEL,
        EXEC_LOAD_A,
        EXEC_LOAD_B,
        EXEC_WAIT_RESULT,
        EXEC_DONE
    } exec_state_t;

    exec_state_t exec_state;
    reg [DATA_WIDTH-1:0] alu_data_reg;
    reg load_a_reg;
    reg load_b_reg;
    reg load_sel_reg;
    reg exec_pulse_reg;
    reg exec_pending;
    reg exec_trigger;

    assign alu_data  = alu_data_reg;
    assign load_a    = load_a_reg;
    assign load_b    = load_b_reg;
    assign load_sel  = load_sel_reg;
    assign exec_pulse = exec_pulse_reg;

    assign rx_fifo_read_en = fifo_read;

    //! @brief Control de lectura 
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_rx_byte <= 8'h00;
            current_rx_valid <= 1'b0;
        end else begin
            current_rx_valid <= rx_fifo_data_valid;

            if (rx_fifo_data_valid) begin
                current_rx_byte <= rx_fifo_data;
            end
        end
    end

    //! @brief  Solicitar siguiente byte cuando necesitamos datos
    always_comb begin
        fifo_read = 1'b0;

        if (!rx_fifo_empty) begin
            case (current_state)
                S0_WAIT_START: fifo_read = 1'b1;  //!< Buscar STX
                S1_RECV_CMD: fifo_read = 1'b1;   //!< Esperar comando
                S2_RECV_DATA: fifo_read = 1'b1;  //!< Esperar datos
                S3_WAIT_END: fifo_read = 1'b1;   //!< Esperar ETX
                default: fifo_read = 1'b0;
            endcase
        end
    end

    //! @brief  Máquina de estados: parte secuencial
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= S0_WAIT_START;
            stored_cmd    <= 8'h00;
            stored_data   <= '0;
            buffer_a      <= '0;
            buffer_b      <= '0;
            buffer_sel    <= '0;
            exec_trigger  <= 1'b0;
        end else begin
            current_state <= next_state;
            exec_trigger  <= 1'b0;

            //!<  Almacenar comando y datos inmediatamente cuando se lee un byte válido
            if (current_rx_valid) begin
                case (current_state)
                    S1_RECV_CMD: stored_cmd <= current_rx_byte;
                    S2_RECV_DATA: stored_data <= current_rx_byte[DATA_WIDTH-1:0];
                    default: ;
                endcase
            end

            //!<  Ejecutar acción al recibir ETX válido
            if (current_state == S3_WAIT_END && current_rx_valid && current_rx_byte == 8'h03) begin
                unique case (stored_cmd)
                    8'h41: buffer_a   <= stored_data;
                    8'h42: buffer_b   <= stored_data;
                    8'h43: buffer_sel <= stored_data;
                    8'h45: exec_trigger <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    //! @brief  Máquina de estados: parte combinacional
    always_comb begin
        next_state = current_state;
        invalid_cmd_error = 1'b0;
        invalid_framing_error = 1'b0;

        case (current_state)
            S0_WAIT_START: begin
                //!< Esperar STX (0x02)
                if (current_rx_valid && current_rx_byte == 8'h02) begin
                    next_state = S1_RECV_CMD;
                end
            end

            S1_RECV_CMD: begin
                //!< Esperar byte de comando válido
                if (current_rx_valid) begin
                    if ((current_rx_byte >= 8'h41 && current_rx_byte <= 8'h45) && current_rx_byte != 8'h44) begin
                        next_state = S2_RECV_DATA;
                    end else begin
                        next_state = S0_WAIT_START;
                        invalid_cmd_error = 1'b1;
                    end
                end
            end

            S2_RECV_DATA: begin
                //!< Esperar byte de datos
                if (current_rx_valid) begin
                    next_state = S3_WAIT_END;
                end
            end

            S3_WAIT_END: begin
                //!< Esperar ETX (0x03)
                if (current_rx_valid) begin
                    if (current_rx_byte == 8'h03) begin
                        next_state = S0_WAIT_START;
                    end else begin
                        next_state = S0_WAIT_START;
                        invalid_framing_error = 1'b1;
                    end
                end
            end

            default: begin
                next_state = S0_WAIT_START;
            end
        endcase
    end

    //! @brief  Secuencia de ejecución: carga diferida de opcode y operandos
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            exec_state     <= EXEC_IDLE;
            exec_pending   <= 1'b0;
            alu_data_reg   <= '0;
            load_a_reg     <= 1'b0;
            load_b_reg     <= 1'b0;
            load_sel_reg   <= 1'b0;
            exec_pulse_reg <= 1'b0;
        end else begin
            load_a_reg     <= 1'b0;
            load_b_reg     <= 1'b0;
            load_sel_reg   <= 1'b0;
            exec_pulse_reg <= 1'b0;

            if (exec_trigger) begin
                exec_pending <= 1'b1;
            end

            case (exec_state)
                EXEC_IDLE: begin
                    if (exec_pending) begin
                        exec_state <= EXEC_LOAD_SEL;
                    end
                end
                EXEC_LOAD_SEL: begin
                    load_sel_reg <= 1'b1;
                    alu_data_reg <= buffer_sel;
                    exec_state   <= EXEC_LOAD_A;
                end
                EXEC_LOAD_A: begin
                    load_a_reg   <= 1'b1;
                    alu_data_reg <= buffer_a;
                    exec_state   <= EXEC_LOAD_B;
                end
                EXEC_LOAD_B: begin
                    load_b_reg   <= 1'b1;
                    alu_data_reg <= buffer_b;
                    exec_state   <= EXEC_WAIT_RESULT;
                end
                EXEC_WAIT_RESULT: begin
                    exec_state   <= EXEC_DONE;
                end
                EXEC_DONE: begin
                    exec_pulse_reg <= 1'b1;
                    exec_pending   <= 1'b0;
                    exec_state     <= EXEC_IDLE;
                end
                default: exec_state <= EXEC_IDLE;
            endcase
        end
    end

    //! @brief  Asignaciones de salida
    assign decoder_error = invalid_cmd_error || invalid_framing_error;
    assign packet_complete = (current_state == S3_WAIT_END) && current_rx_valid && (current_rx_byte == 8'h03);

endmodule
