`timescale 1ns / 1ps

module tb_alu;
  import alu_pkg::*;
  `include "alu_test_vectors.svh"

  localparam int DATA_WIDTH   = 8;
  localparam int OPCODE_WIDTH = 6;

  logic clk;
  logic rst;
  logic [DATA_WIDTH-1:0] data_in;
  logic load_a;
  logic load_b;
  logic load_sel;
  wire [DATA_WIDTH-1:0] result;
  wire cout;
  wire zero;
  wire result_led0;
  wire result_led1;
  wire result_led_b_n;
  wire result_led_g_n;
  wire result_led_r_n;

  int unsigned error_count;
  int unsigned test_count;

  alu_top #(
      .DATA_WIDTH  (DATA_WIDTH),
      .OPCODE_WIDTH(OPCODE_WIDTH)
  ) dut (
      .clk           (clk),
      .rst           (rst),
      .data_in       (data_in),
      .load_a        (load_a),
      .load_b        (load_b),
      .load_sel      (load_sel),
      .Result        (result),
      .Cout          (cout),
      .Zero          (zero),
      .result_led0   (result_led0),
      .result_led1   (result_led1),
      .result_led_b_n(result_led_b_n),
      .result_led_g_n(result_led_g_n),
      .result_led_r_n(result_led_r_n)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst = 1'b1;
    data_in = '0;
    load_a = 1'b0;
    load_b = 1'b0;
    load_sel = 1'b0;
    error_count = 0;
    test_count = 0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);
    run_smoke_tests();
    run_random_tests();
    report_results();
  end

  task automatic run_smoke_tests();
    foreach (smoke_vectors[idx]) begin
      apply_and_check(smoke_vectors[idx]);
    end
  endtask

  task automatic run_random_tests();
    foreach (random_vectors[idx]) begin
      apply_and_check(random_vectors[idx]);
    end
  endtask

  task automatic apply_and_check(testcase_t tc);
    drive_operand(tc.a, load_a);
    drive_operand(tc.b, load_b);
    drive_opcode(tc.opcode);

    @(posedge clk);

    $display("[DBG ] time=%0t opcode=%0h reg_a=%0h reg_b=%0h reg_sel=%0h result=%0h cout=%0b",
             $time, tc.opcode, dut.reg_a, dut.reg_b, dut.reg_sel, result, cout);
    check_outputs(tc);
  endtask

  task automatic drive_operand(logic [7:0] value, ref logic load_sig);
    data_in  = value;
    load_sig = 1'b1;
    @(posedge clk);
    load_sig = 1'b0;
  endtask

  task automatic drive_opcode(logic [5:0] opcode_value);
    data_in  = {2'b00, opcode_value};
    load_sel = 1'b1;
    @(posedge clk);
    load_sel = 1'b0;
    data_in  = '0;
  endtask

  task automatic check_outputs(testcase_t tc);
    test_count++;
    if ({result, cout, zero} !== {tc.exp_result, tc.exp_cout, tc.exp_zero}) begin
      error_count++;
      $display(
          "[ERROR] %s opcode=%0h A=%0h B=%0h got res=%0h cout=%0b zero=%0b exp res=%0h cout=%0b zero=%0b",
          tc.name, tc.opcode, tc.a, tc.b, result, cout, zero, tc.exp_result, tc.exp_cout,
          tc.exp_zero);
    end else begin
      $display("[PASS ] %s opcode=%0h A=%0h B=%0h res=%0h cout=%0b zero=%0b", tc.name, tc.opcode, tc.a, tc.b, result, cout, zero);
    end

    if ({result_led0, result_led1, result_led_b_n, result_led_g_n, result_led_r_n} !==
        {tc.exp_led0, tc.exp_led1, tc.exp_led_b_n, tc.exp_led_g_n, tc.exp_led_r_n}) begin
      error_count++;
      $display("[ERROR] %s LED mismatch got=%b%b%b%b%b exp=%b%b%b%b%b", tc.name, result_led0, result_led1,
               result_led_b_n, result_led_g_n, result_led_r_n, tc.exp_led0, tc.exp_led1, tc.exp_led_b_n,
               tc.exp_led_g_n, tc.exp_led_r_n);
    end

  endtask

  task automatic report_results();
    if (error_count == 0) begin
      $display("Test completed: %0d cases, no errors", test_count);
    end else begin
      $display("Test completed: %0d cases, %0d errors", test_count, error_count);
    end
    $finish;
  endtask
endmodule
