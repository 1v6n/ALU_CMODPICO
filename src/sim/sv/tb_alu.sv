`timescale 1ns / 1ps

module tb_alu;
  import alu_pkg::*;

  localparam int DATA_WIDTH = 8;
  localparam int OPCODE_WIDTH = 6;

  typedef struct {
    string      name;
    logic [5:0] opcode;
    logic [7:0] a;
    logic [7:0] b;
  } testcase_t;

  typedef struct {
    logic [7:0] result;
    logic       cout;
    logic       zero;
    logic       overflow;
    logic       led0;
    logic       led1;
    logic       led_b_n;
    logic       led_g_n;
    logic       led_r_n;
  } expected_t;

  logic clk;
  logic rst;
  logic [DATA_WIDTH-1:0] data_in;
  logic load_a;
  logic load_b;
  logic load_sel;
  wire [DATA_WIDTH-1:0] result;
  wire cout;
  wire zero;
  wire overflow;
  wire result_led0;
  wire result_led1;
  wire result_led_b_n;
  wire result_led_g_n;
  wire result_led_r_n;

  bit carry_state;
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
      .Overflow      (overflow),
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
    carry_state = 1'b0;
    error_count = 0;
    test_count = 0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);
    run_smoke_tests();
    run_random_tests(200);
    report_results();
  end

  task automatic run_smoke_tests();
    testcase_t vectors[$] = '{
        '{"ADD", 6'b100000, 8'h0A, 8'h05},
        '{"ADD_WRAP", 6'b100000, 8'hFF, 8'h01},
        '{"ADC_WITH_CARRY", 6'b100001, 8'h40, 8'h40},
        '{"ADD_CLEAR", 6'b100000, 8'h01, 8'h01},
        '{"ADC_NO_CARRY", 6'b100001, 8'h05, 8'h03},
        '{"ADD_OVF", 6'b100000, 8'h7F, 8'h01},
        '{"SUB", 6'b100010, 8'h34, 8'h12},
        '{"SUB_OVF", 6'b100010, 8'h80, 8'h01},
        '{"SBC_KEEP", 6'b100011, 8'h34, 8'h12},
        '{"SUB_BORROW", 6'b100010, 8'h00, 8'h01},
        '{"SBC_BORROW", 6'b100011, 8'h00, 8'h00},
        '{"AND", 6'b100100, 8'hF0, 8'h0F},
        '{"OR", 6'b100101, 8'h55, 8'h0F},
        '{"XOR", 6'b100110, 8'hAA, 8'h5A},
        '{"NOR", 6'b100111, 8'h00, 8'h00},
        '{"SRL", 6'b000010, 8'hC0, 8'h03},
        '{"SRA", 6'b000011, 8'h81, 8'h02},
        '{"SRL_WIDE", 6'b000010, 8'hAA, 8'h20}
    };
    foreach (vectors[idx]) begin
      apply_and_check(vectors[idx]);
    end
  endtask

  task automatic run_random_tests(int unsigned count);
    testcase_t tc;
    byte rand_a;
    byte rand_b;
    bit [5:0] rand_opcode;
    for (int i = 0; i < count; i++) begin
      void'(std::randomize(rand_a));
      void'(std::randomize(rand_b));
      void'(std::randomize(
          rand_opcode
      ) with {
        rand_opcode inside {6'b100000, 6'b100001, 6'b100010, 6'b100011, 6'b100100, 6'b100101,
                            6'b100110, 6'b100111, 6'b000010, 6'b000011};
      });
      tc.a = rand_a;
      tc.b = rand_b;
      tc.opcode = rand_opcode;
      tc.name = $sformatf("RND_%0d", i);
      apply_and_check(tc);
    end
  endtask

  task automatic apply_and_check(testcase_t tc);
    expected_t exp;

    drive_operand(tc.a, load_a);
    drive_operand(tc.b, load_b);
    drive_opcode(tc.opcode);

    @(posedge clk);

    exp = compute_expected(tc);
    $display("[DBG ] time=%0t opcode=%0h reg_a=%0h reg_b=%0h reg_sel=%0h result=%0h cout=%0b",
             $time, tc.opcode, dut.reg_a, dut.reg_b, dut.reg_sel, result, cout);
    check_outputs(tc, exp);
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

  function automatic expected_t compute_expected(testcase_t tc);
    expected_t exp;
    bit [7:0] a;
    bit [7:0] b;
    bit [5:0] opcode;
    bit [3:0] family;
    bit [1:0] sel;
    bit [7:0] add_operand;
    bit carry_term;
    bit [8:0] wide;
    bit carry_in;

    a = tc.a;
    b = tc.b;
    opcode = tc.opcode;
    family = opcode[5:2];
    sel = opcode[1:0];
    exp = '{default: '0};
    carry_in = carry_state;

    unique case (family)
      OPCODE_FAMILY_ARITH: begin
        unique case (sel)
          ARITH_SEL_ADD: begin
            wide = {1'b0, a} + {1'b0, b};
            exp.result = wide[7:0];
            exp.cout = wide[8];
            exp.overflow = (a[7] == b[7]) && (exp.result[7] != a[7]);
            carry_state = exp.cout;
          end
          ARITH_SEL_ADC: begin
            wide = {1'b0, a} + {1'b0, b} + carry_in;
            exp.result = wide[7:0];
            exp.cout = wide[8];
            exp.overflow = (a[7] == b[7]) && (exp.result[7] != a[7]);
            carry_state = exp.cout;
          end
          ARITH_SEL_SUB: begin
            add_operand = ~b;
            carry_term = 1'b1;
            wide = {1'b0, a} + {1'b0, add_operand} + carry_term;
            exp.result = wide[7:0];
            exp.cout = wide[8];
            exp.overflow = (a[7] == add_operand[7]) && (exp.result[7] != a[7]);
            carry_state = exp.cout;
          end
          ARITH_SEL_SBC: begin
            add_operand = ~b;
            carry_term = carry_in;
            wide = {1'b0, a} + {1'b0, add_operand} + carry_term;
            exp.result = wide[7:0];
            exp.cout = wide[8];
            exp.overflow = (a[7] == add_operand[7]) && (exp.result[7] != a[7]);
            carry_state = exp.cout;
          end
          default: begin
            exp.result = '0;
            exp.cout = 1'b0;
            exp.overflow = 1'b0;
          end
        endcase
      end

      OPCODE_FAMILY_LOGIC: begin
        unique case (sel)
          LOGIC_SEL_AND: exp.result = a & b;
          LOGIC_SEL_OR:  exp.result = a | b;
          LOGIC_SEL_XOR: exp.result = a ^ b;
          LOGIC_SEL_NOR: exp.result = ~(a | b);
          default:       exp.result = '0;
        endcase
        exp.cout = 1'b0;
        exp.overflow = 1'b0;
      end

      OPCODE_FAMILY_SHIFT: begin
        unique case (sel)
          2'b10: begin
            exp.result = a >> b;
          end
          2'b11: begin
            exp.result = $signed(a) >>> b;
          end
          default: begin
            exp.result = '0;
          end
        endcase
        exp.cout = 1'b0;
        exp.overflow = 1'b0;
      end

      default: begin
        exp.result = '0;
        exp.cout = 1'b0;
        exp.overflow = 1'b0;
      end
    endcase

    exp.zero = (exp.result == '0);
    exp.led0 = exp.result[0];
    exp.led1 = exp.result[1];
    exp.led_b_n = ~exp.result[2];
    exp.led_g_n = ~exp.result[3];
    exp.led_r_n = ~exp.result[4];

    return exp;
  endfunction

  task automatic check_outputs(testcase_t tc, expected_t exp);
    test_count++;
    if ({result, cout, zero, overflow} !== {exp.result, exp.cout, exp.zero, exp.overflow}) begin
      error_count++;
      $display(
          "[ERROR] %s opcode=%0h A=%0h B=%0h got res=%0h cout=%0b zero=%0b ovf=%0b exp res=%0h cout=%0b zero=%0b ovf=%0b",
          tc.name, tc.opcode, tc.a, tc.b, result, cout, zero, overflow, exp.result, exp.cout,
          exp.zero, exp.overflow);
    end else begin
      $display("[PASS ] %s opcode=%0h A=%0h B=%0h res=%0h cout=%0b zero=%0b ovf=%0b", tc.name,
               tc.opcode, tc.a, tc.b, result, cout, zero, overflow);
    end

    if ({result_led0, result_led1, result_led_b_n, result_led_g_n, result_led_r_n} !==
        {exp.led0, exp.led1, exp.led_b_n, exp.led_g_n, exp.led_r_n}) begin
      error_count++;
      $display("[ERROR] %s LED mismatch got=%b%b%b%b%b exp=%b%b%b%b%b", tc.name, result_led0,
               result_led1, result_led_b_n, result_led_g_n, result_led_r_n, exp.led0, exp.led1,
               exp.led_b_n, exp.led_g_n, exp.led_r_n);
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
