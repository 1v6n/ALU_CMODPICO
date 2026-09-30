`timescale 1ns / 1ps
/*
 * @file tb_alu_top_fsm.sv
 * @brief Banco de pruebas para verificar el módulo alu_top_fsm. 
 * Simula la recepción de paquetes UART y verifica las señales de la ALU.
 */

module tb_alu_top_fsm;
  localparam CLK_PERIOD = 10;

  //! @brief Señales de reloj y reset
  reg clk;
  reg rst;

  //! @brief Señales UART
  reg [7:0] uart_rx_data;
  reg uart_rx_valid;
  wire uart_rx_ready;

  //! @brief Señales ALU
  wire [7:0] alu_result;
  wire alu_cout;
  wire alu_zero;

  //! @brief Instancia deL DUT
  alu_top_fsm dut (
      .clk(clk),
      .rst(rst),
      .uart_rx_data(uart_rx_data),
      .uart_rx_valid(uart_rx_valid),
      .uart_rx_ready(uart_rx_ready),
      .alu_result(alu_result),
      .alu_cout(alu_cout),
      .alu_zero(alu_zero)
  );

  //! @brief Generador de reloj
  initial clk = 0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  //! @brief Secuencia de reset y ejecución de pruebas
  initial begin
    rst = 1;
    uart_rx_data = 8'h00;
    uart_rx_valid = 1'b0;
    checks_total = 0;
    checks_ok = 0;
    checks_fail = 0;
    repeat (5) @(posedge clk);
    rst = 0;
    @(posedge clk);
    $display("[%0t] Reset liberado", $time);
    ejecutar_pruebas();
  end

  //! @brief Tarea para enviar un byte por UART
  task automatic enviar_byte(input [7:0] value);
    begin
      @(posedge clk);
      uart_rx_data  = value;
      uart_rx_valid = 1'b1;
      @(posedge clk);
      while (!uart_rx_ready) @(posedge clk);
      uart_rx_valid = 1'b0;
    end
  endtask

  //! @brief Tarea para enviar un paquete completo (STX, CMD, DATA, ETX)
  task automatic enviar_paquete(input [7:0] cmd, input [7:0] data);
    begin
      enviar_byte(8'h02);
      enviar_byte(cmd);
      enviar_byte(data);
      enviar_byte(8'h03);
    end
  endtask

  //! @brief Contadores de resultados
  integer       checks_total;
  integer       checks_ok;
  integer       checks_fail;

  //! @brief Señales internas del DUT para verificación
  wire    [7:0] dec_alu_data = dut.alu_data;
  wire          dec_load_a = dut.uart_decoder.load_a;
  wire          dec_load_b = dut.uart_decoder.load_b;
  wire          dec_load_sel = dut.uart_decoder.load_sel;
  wire          dec_exec_pulse = dut.uart_decoder.exec_pulse;

  //! @brief Tarea para registrar el resultado de una verificación
  task automatic registrar_check(input string desc, input bit ok);
    begin
      checks_total = checks_total + 1;
      if (ok) begin
        checks_ok = checks_ok + 1;
        $display("[CHECK OK ] %s", desc);
      end else begin
        checks_fail = checks_fail + 1;
        $display("[CHECK FAIL] %s", desc);
        $fatal;
      end
    end
  endtask

  //! @brief Tarea para verificar el estado de la ALU
  task automatic assert_estado(input [7:0] exp_result, input bit exp_cout, input bit exp_zero,
                               input string mensaje);
    begin
      registrar_check($sformatf(
                      "%s -> result=0x%0h (exp 0x%0h) Cout=%0b (exp %0b) Zero=%0b (exp %0b)",
                      mensaje,
                      alu_result,
                      exp_result,
                      alu_cout,
                      exp_cout,
                      alu_zero,
                      exp_zero
                      ),
                      (alu_result === exp_result) && (alu_cout === exp_cout) && (alu_zero === exp_zero)
            );
    end
  endtask

  //! @brief Tarea para esperar un pulso específico del decodificador
  task automatic esperar_pulso_decoder(input byte tipo, input [7:0] esperado);
    int ciclos;
    bit atendido;
    begin
      ciclos   = 0;
      atendido = 0;
      while (ciclos < 80 && !atendido) begin
        @(posedge clk);
        ciclos++;
        case (tipo)
          "E":
          if (dec_exec_pulse) begin
            atendido = 1;
            registrar_check("EXEC pulse detectado", 1'b1);
          end
          "S":
          if (dec_load_sel) begin
            atendido = 1;
            registrar_check($sformatf("LOAD_SEL valor 0x%0h", esperado), dec_alu_data === esperado);
          end
          "A":
          if (dec_load_a) begin
            atendido = 1;
            registrar_check($sformatf("LOAD_A valor 0x%0h", esperado), dec_alu_data === esperado);
          end
          "B":
          if (dec_load_b) begin
            atendido = 1;
            registrar_check($sformatf("LOAD_B valor 0x%0h", esperado), dec_alu_data === esperado);
          end
          default: ;
        endcase
      end
      if (!atendido) begin
        registrar_check($sformatf("Timeout esperando pulso %0h", tipo), 1'b0);
      end
    end
  endtask

  //! @brief Tarea para ejecutar la secuencia completa de pruebas
  task automatic ejecutar_pruebas;
    begin
      $display("=== Caso 1: cargar sin ejecutar ===");
      enviar_paquete(8'h43, 8'h10);
      enviar_paquete(8'h41, 8'h01);
      enviar_paquete(8'h42, 8'h02);
      repeat (10) @(posedge clk);
      assert_estado(8'h00, 1'b0, 1'b1, "Sin E no debe cambiar ALU");

      $display("=== Caso 2: secuencia completa ADD ===");
      enviar_paquete(8'h43, 8'h20);
      enviar_paquete(8'h41, 8'h12);
      enviar_paquete(8'h42, 8'h05);
      enviar_paquete(8'h45, 8'h00);
      esperar_pulso_decoder(8'h45, 8'h00);
      esperar_pulso_decoder(8'h53, 8'h20);
      esperar_pulso_decoder(8'h41, 8'h12);
      esperar_pulso_decoder(8'h42, 8'h05);
      repeat (4) @(posedge clk);
      assert_estado(8'h17, 1'b0, 1'b0, "ADD 0x12 + 0x05");

      $display("=== Caso 3: secuencia completa XOR ===");
      enviar_paquete(8'h43, 8'h26);
      enviar_paquete(8'h41, 8'hAA);
      enviar_paquete(8'h42, 8'h55);
      enviar_paquete(8'h45, 8'h00);
      esperar_pulso_decoder(8'h45, 8'h00);
      esperar_pulso_decoder(8'h53, 8'h26);
      esperar_pulso_decoder(8'h41, 8'hAA);
      esperar_pulso_decoder(8'h42, 8'h55);
      repeat (4) @(posedge clk);
      assert_estado(8'hFF, 1'b0, 1'b0, "XOR 0xAA ^ 0x55");

      $display("Pruebas finalizadas");
      $display("Resumen: total=%0d ok=%0d fail=%0d", checks_total, checks_ok, checks_fail);
      $finish;
    end
  endtask


endmodule
