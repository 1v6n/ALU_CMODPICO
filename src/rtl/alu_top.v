/*
 * @file alu_top.v
 * @brief Módulo de nivel superior para el sistema ALU: integra banco de registros y núcleo combinacional.
 * Este módulo secuencial maneja la carga de operandos A, B y opcode desde un bus de entrada compartido,
 * almacena en registros internos y pasa al núcleo a la ALU combinacional para su ejecución.
 * Incluye salidas para flags (Cout, Zero, Overflow) y LEDs en la placa CMOD A7 para la visualización de resultados.
 */
module alu_top #(
    //! @param DATA_WIDTH: Ancho de los datos y operandos (por defecto 8 bits)
    parameter DATA_WIDTH = 8,
    //! @param OPCODE_WIDTH: Ancho del opcode (por defecto 6 bits)
    parameter OPCODE_WIDTH = 6
  ) (
    //! @brief Entradas y salidas del módulo ALU top-level
    input clk,                   //!< Señal de reloj para sincronización
    input rst,                   //!< Reset síncrono activo alto

    input [DATA_WIDTH-1:0] data_in, //!< Bus de entrada de datos compartido para operandos y opcode
    input load_a,                //!< Señal de control para cargar operando A
    input load_b,                //!< Señal de control para cargar operando B
    input load_sel,              //!< Señal de control para cargar opcode/selección

    output [DATA_WIDTH-1:0] Result, //!< Resultado de la operación ALU
    output Cout,                 //!< Carry Out
    output Zero,                 //!< Zero flag
    output Overflow,             //!< Overflow

    output result_led0,          //!< LED0: refleja bit 0 del resultado (activo alto)
    output result_led1,          //!< LED1: refleja bit 1 del resultado (activo alto)
    output result_led_b_n,       //!< LED Azul: refleja bit 2 invertido (activo bajo)
    output result_led_g_n,       //!< LED Verde: refleja bit 3 invertido (activo bajo)
    output result_led_r_n        //!< LED Rojo: refleja bit 4 invertido (activo bajo)
  );

  //! @brief Módulo alu_top: Nivel superior que integra el banco de registros y el núcleo de la ALU combinacional
  
  initial
  begin
    if (OPCODE_WIDTH > DATA_WIDTH)
    begin
      $error("alu_top: OPCODE_WIDTH (%0d) debe ser menor o igual a DATA_WIDTH (%0d)", OPCODE_WIDTH, DATA_WIDTH);
    end
  end

  wire [DATA_WIDTH-1:0] reg_a;     //!< Salida del registro A (operando A)
  wire [DATA_WIDTH-1:0] reg_b;     //!< Salida del registro B (operando B)
  wire [OPCODE_WIDTH-1:0] reg_sel; //!< Salida del registro de selección (opcode)

  //! @brief Instancia del banco de registros para la carga secuencial de operandos y opcode
  alu_register_bank #(
                      .DATA_WIDTH(DATA_WIDTH),
                      .OPCODE_WIDTH(OPCODE_WIDTH)
                    ) register_bank_inst (
                      .clk(clk),
                      .rst(rst),
                      .data_in(data_in),
                      .load_a(load_a),
                      .load_b(load_b),
                      .load_sel(load_sel),
                      .reg_a(reg_a),
                      .reg_b(reg_b),
                      .reg_sel(reg_sel)
                    );


  wire [DATA_WIDTH-1:0] core_result;   //!< Resultado del núcleo de la ALU
  wire core_cout;                      //!< Carry del núcleo de la ALU
  wire core_zero;                      //!< Zero flag del núcleo de la ALU
  wire core_overflow;                  //!< Overflow del núcleo de la ALU
  reg carry_flag_old;                  //!< Flag de carry registrado de operaciones con carry anteriores
  reg carry_flag_new;                   //!< Flag de carry disponible para la operación actual
  reg load_sel_d;                      //!< Retardo de un ciclo para load_sel
  wire is_arith_family;                //!< Indica si el opcode actual pertenece a la familia aritmética

  //! @brief Instancia del núcleo ALU combinacional principal
  alu #(
        .DATA_WIDTH(DATA_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH)
      ) alu_core_inst (
        .A(reg_a),
        .B(reg_b),
        .opcode(reg_sel),
        .carry_in(carry_flag_new),
        .Result(core_result),
        .Cout(core_cout),
        .Zero(core_zero),
        .Overflow(core_overflow)
      );

  wire [3:0] opcode_family = reg_sel[OPCODE_WIDTH-1:OPCODE_WIDTH-4];                                    //!< Bits superiores del opcode para identificar la familia
  assign is_arith_family = (alu_pkg::opcode_family_t'(opcode_family) == alu_pkg::OPCODE_FAMILY_ARITH);  //!< Indica si la familia de opcode es aritmética

  always @(posedge clk) begin
    if (rst) begin
      carry_flag_old <= 1'b0;
      carry_flag_new <= 1'b0;
      load_sel_d <= 1'b0;
    end else begin
      carry_flag_new <= carry_flag_old;
      load_sel_d <= load_sel;
      if (load_sel_d && is_arith_family) begin
        carry_flag_old <= core_cout;
      end
    end
  end


  assign Result = core_result;
  assign Cout = core_cout;
  assign Zero = core_zero;
  assign Overflow = core_overflow;
  assign result_led0 = core_result[0];
  assign result_led1 = (DATA_WIDTH > 1) ? core_result[1] : 1'b0;
  assign result_led_b_n = (DATA_WIDTH > 2) ? ~core_result[2] : 1'b1;
  assign result_led_g_n = (DATA_WIDTH > 3) ? ~core_result[3] : 1'b1;
  assign result_led_r_n = (DATA_WIDTH > 4) ? ~core_result[4] : 1'b1;

endmodule
