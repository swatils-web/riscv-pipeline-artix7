`timescale 1ns/1ps

module tb_riscv_top;

    reg clk;
    reg rst;
    wire [31:0] wb_data;

    // Debug outputs
    wire [31:0] dbg_if_id_PC;
    wire [31:0] dbg_if_id_instruction;
    wire [31:0] dbg_id_ex_PC;
    wire [31:0] dbg_id_ex_reg_data1;
    wire [31:0] dbg_id_ex_reg_data2;
    wire [31:0] dbg_id_ex_imm;
    wire [4:0]  dbg_id_ex_rs1;
    wire [4:0]  dbg_id_ex_rs2;
    wire [4:0]  dbg_id_ex_rd;
    wire [3:0]  dbg_id_ex_ALUOp;
    wire        dbg_id_ex_ALUSrc;
    wire        dbg_id_ex_MemRead;
    wire        dbg_id_ex_MemWrite;
    wire        dbg_id_ex_RegWrite;
    wire        dbg_id_ex_MemtoReg;
    wire        dbg_id_ex_Branch;

    wire [31:0] dbg_ex_mem_alu_result;
    wire [31:0] dbg_ex_mem_reg_data2;
    wire [4:0]  dbg_ex_mem_rd;
    wire        dbg_ex_mem_MemRead;
    wire        dbg_ex_mem_MemWrite;
    wire        dbg_ex_mem_RegWrite;
    wire        dbg_ex_mem_MemtoReg;

    wire [31:0] dbg_mem_wb_alu_result;
    wire [31:0] dbg_mem_wb_read_data;
    wire [4:0]  dbg_mem_wb_rd;
    wire        dbg_mem_wb_RegWrite;
    wire        dbg_mem_wb_MemtoReg;

    wire        dbg_stall;
    wire        dbg_flush;
    wire [1:0]  dbg_ForwardA;
    wire [1:0]  dbg_ForwardB;
    wire        dbg_ex_branch_taken;
    wire [31:0] dbg_ex_branch_target;

    // Instantiate DUT
    riscv_top #(.DEBUG_EN(1'b1)) uut (
        .clk(clk),
        .rst(rst),
        .wb_data(wb_data),

        .dbg_if_id_PC(dbg_if_id_PC),
        .dbg_if_id_instruction(dbg_if_id_instruction),
        .dbg_id_ex_PC(dbg_id_ex_PC),
        .dbg_id_ex_reg_data1(dbg_id_ex_reg_data1),
        .dbg_id_ex_reg_data2(dbg_id_ex_reg_data2),
        .dbg_id_ex_imm(dbg_id_ex_imm),
        .dbg_id_ex_rs1(dbg_id_ex_rs1),
        .dbg_id_ex_rs2(dbg_id_ex_rs2),
        .dbg_id_ex_rd(dbg_id_ex_rd),
        .dbg_id_ex_ALUOp(dbg_id_ex_ALUOp),
        .dbg_id_ex_ALUSrc(dbg_id_ex_ALUSrc),
        .dbg_id_ex_MemRead(dbg_id_ex_MemRead),
        .dbg_id_ex_MemWrite(dbg_id_ex_MemWrite),
        .dbg_id_ex_RegWrite(dbg_id_ex_RegWrite),
        .dbg_id_ex_MemtoReg(dbg_id_ex_MemtoReg),
        .dbg_id_ex_Branch(dbg_id_ex_Branch),

        .dbg_ex_mem_alu_result(dbg_ex_mem_alu_result),
        .dbg_ex_mem_reg_data2(dbg_ex_mem_reg_data2),
        .dbg_ex_mem_rd(dbg_ex_mem_rd),
        .dbg_ex_mem_MemRead(dbg_ex_mem_MemRead),
        .dbg_ex_mem_MemWrite(dbg_ex_mem_MemWrite),
        .dbg_ex_mem_RegWrite(dbg_ex_mem_RegWrite),
        .dbg_ex_mem_MemtoReg(dbg_ex_mem_MemtoReg),

        .dbg_mem_wb_alu_result(dbg_mem_wb_alu_result),
        .dbg_mem_wb_read_data(dbg_mem_wb_read_data),
        .dbg_mem_wb_rd(dbg_mem_wb_rd),
        .dbg_mem_wb_RegWrite(dbg_mem_wb_RegWrite),
        .dbg_mem_wb_MemtoReg(dbg_mem_wb_MemtoReg),

        .dbg_stall(dbg_stall),
        .dbg_flush(dbg_flush),
        .dbg_ForwardA(dbg_ForwardA),
        .dbg_ForwardB(dbg_ForwardB),
        .dbg_ex_branch_taken(dbg_ex_branch_taken),
        .dbg_ex_branch_target(dbg_ex_branch_target)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz -> 10 ns period
    end

    // Reset and simulation control
    integer cycle;
    initial begin
        // Waveform dump
        $dumpfile("tb_riscv_top.vcd");
        $dumpvars(0, tb_riscv_top);

        // Reset pulse
        rst = 1;
        cycle = 0;
        repeat (4) @(posedge clk);
        rst = 0;

        // Run for enough cycles to execute ROM program
        // ROM program is short; run 40 cycles to be safe
        repeat (40) begin
            @(posedge clk);
            cycle = cycle + 1;
        end

        // Small delay to allow final writeback
        repeat (2) @(posedge clk);

        // Read register file and memory via hierarchical access for checks
        // Note: hierarchical access is simulation-only
        $display("----- DUT state after %0d cycles -----", cycle);
        $display("x1 = %0d (expected 10)", uut.reg_file.registers[1]);
        $display("x2 = %0d (expected 5)",  uut.reg_file.registers[2]);
        $display("x3 = %0d (expected 15)", uut.reg_file.registers[3]);
        $display("x4 = %0d (expected 15)", uut.reg_file.registers[4]);
        $display("x5 = %0d (expected 15)", uut.reg_file.registers[5]);
        $display("mem[0] = %0d (expected 15)", uut.dmem.ram[0]);

        // Automated pass/fail
        if (uut.reg_file.registers[1] == 10 &&
            uut.reg_file.registers[2] == 5  &&
            uut.reg_file.registers[3] == 15 &&
            uut.reg_file.registers[4] == 15 &&
            uut.reg_file.registers[5] == 15 &&
            uut.dmem.ram[0] == 15) begin
            $display("TEST PASS");
        end else begin
            $display("TEST FAIL");
        end

        $finish;
    end

endmodule
