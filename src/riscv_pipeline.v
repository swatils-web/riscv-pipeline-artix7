`timescale 1ns/1ps

module riscv_top #(
    parameter DEBUG_EN = 1'b1      // Set to 0 for final implementation power/timing
)(
    input clk,
    input rst,
    output [31:0] wb_data,

    //  Debug / verification outputs
    output [31:0] dbg_if_id_PC,
    output [31:0] dbg_if_id_instruction,
    output [31:0] dbg_id_ex_PC,
    output [31:0] dbg_id_ex_reg_data1,
    output [31:0] dbg_id_ex_reg_data2,
    output [31:0] dbg_id_ex_imm,
    output [4:0]  dbg_id_ex_rs1,
    output [4:0]  dbg_id_ex_rs2,
    output [4:0]  dbg_id_ex_rd,
    output [3:0]  dbg_id_ex_ALUOp,
    output        dbg_id_ex_ALUSrc,
    output        dbg_id_ex_MemRead,
    output        dbg_id_ex_MemWrite,
    output        dbg_id_ex_RegWrite,
    output        dbg_id_ex_MemtoReg,
    output        dbg_id_ex_Branch,

    output [31:0] dbg_ex_mem_alu_result,
    output [31:0] dbg_ex_mem_reg_data2,
    output [4:0]  dbg_ex_mem_rd,
    output        dbg_ex_mem_MemRead,
    output        dbg_ex_mem_MemWrite,
    output        dbg_ex_mem_RegWrite,
    output        dbg_ex_mem_MemtoReg,

    output [31:0] dbg_mem_wb_alu_result,
    output [31:0] dbg_mem_wb_read_data,
    output [4:0]  dbg_mem_wb_rd,
    output        dbg_mem_wb_RegWrite,
    output        dbg_mem_wb_MemtoReg,

    output        dbg_stall,
    output        dbg_flush,
    output [1:0]  dbg_ForwardA,
    output [1:0]  dbg_ForwardB,
    output        dbg_ex_branch_taken,
    output [31:0] dbg_ex_branch_target
);

    localparam NOP = 32'h00000013;

    // IF stage
    reg  [31:0] PC;
    wire [31:0] PC_plus4;
    wire [31:0] PC_next;

    wire [31:0] if_instruction_raw;

    // Fetch buffer: breaks ROM-to-decode timing and reduces switching
    reg [31:0] if_fetch_PC;
    reg [31:0] if_fetch_instruction;
    reg        if_fetch_valid;

    // IF/ID pipeline register
    reg [31:0] if_id_PC;
    reg [31:0] if_id_instruction;

    
    // ID stage
    wire [4:0] id_rs1;
    wire [4:0] id_rs2;
    wire [4:0] id_rd;

    wire [31:0] id_reg_data1;
    wire [31:0] id_reg_data2;
    wire [31:0] id_imm;

    wire [3:0] id_ALUOp_raw;
    wire       id_ALUSrc_raw;
    wire       id_MemRead_raw;
    wire       id_MemWrite_raw;
    wire       id_RegWrite_raw;
    wire       id_MemtoReg_raw;
    wire       id_Branch_raw;

    wire       id_is_nop;

    wire [3:0] id_ALUOp;
    wire       id_ALUSrc;
    wire       id_MemRead;
    wire       id_MemWrite;
    wire       id_RegWrite;
    wire       id_MemtoReg;
    wire       id_Branch;

    wire [31:0] id_branch_target;

    // ID/EX pipeline register
    reg [31:0] id_ex_PC;
    reg [31:0] id_ex_reg_data1;
    reg [31:0] id_ex_reg_data2;
    reg [31:0] id_ex_imm;
    reg [31:0] id_ex_branch_target;

    reg [4:0] id_ex_rs1;
    reg [4:0] id_ex_rs2;
    reg [4:0] id_ex_rd;

    reg [3:0] id_ex_ALUOp;

    reg id_ex_ALUSrc;
    reg id_ex_MemRead;
    reg id_ex_MemWrite;
    reg id_ex_RegWrite;
    reg id_ex_MemtoReg;
    reg id_ex_Branch;

    // EX stage
    wire [1:0] ForwardA;
    wire [1:0] ForwardB;

    wire [31:0] ex_forward_a;
    wire [31:0] ex_forward_b;

    wire [31:0] ex_alu_operand_a;
    wire [31:0] ex_alu_operand_b;
    wire [31:0] ex_alu_operand_a_iso;
    wire [31:0] ex_alu_operand_b_iso;

    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;

    wire        ex_alu_active;
    wire        ex_branch_taken_calc;

    // EX/MEM pipeline register
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_reg_data2;
    reg [31:0] ex_mem_branch_target;

    reg [4:0] ex_mem_rd;

    reg ex_mem_MemRead;
    reg ex_mem_MemWrite;
    reg ex_mem_RegWrite;
    reg ex_mem_MemtoReg;
    reg ex_mem_branch_taken;

    // MEM/WB pipeline register
    wire [31:0] mem_read_data;

    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_read_data;

    reg [4:0] mem_wb_rd;

    reg mem_wb_RegWrite;
    reg mem_wb_MemtoReg;

    // WB stage
    wire [31:0] wb_write_back_data;

    // Hazard signals
    wire stall;
    wire flush;

    // 1. INSTRUCTION FETCH
    assign PC_plus4 = PC + 32'd4;

    // Branch has priority over stall.
    // Branch resolved in EX stage; use id_ex_branch_target as the target when flush asserted.
    assign PC_next = flush ? id_ex_branch_target :
                     stall ? PC :
                     PC_plus4;

    always @(posedge clk) begin
        if (rst)
            PC <= 32'b0;
        else
            PC <= PC_next;
    end

    instruction_mem imem (
        .addr(PC),
        .instruction(if_instruction_raw)
    );

    // Fetch buffer.
    // This register separates instruction memory output from IF/ID decode path.
    always @(posedge clk) begin
        if (rst || flush) begin
            if_fetch_PC          <= 32'b0;
            if_fetch_instruction <= NOP;
            if_fetch_valid       <= 1'b0;
        end else if (!stall) begin
            if_fetch_PC          <= PC;
            if_fetch_instruction <= if_instruction_raw;
            if_fetch_valid       <= 1'b1;
        end
    end

    // IF/ID register with clock-enable behavior.
    always @(posedge clk) begin
        if (rst || flush) begin
            if_id_PC          <= 32'b0;
            if_id_instruction <= NOP;
        end else if (!stall) begin
            if_id_PC          <= if_fetch_PC;
            if_id_instruction <= if_fetch_valid ? if_fetch_instruction : NOP;
        end
    end

    // 2. INSTRUCTION DECODE
    assign id_rs1 = if_id_instruction[19:15];
    assign id_rs2 = if_id_instruction[24:20];
    assign id_rd  = if_id_instruction[11:7];

    assign id_is_nop = (if_id_instruction == NOP);

    control_unit ctrl (
        .opcode   (if_id_instruction[6:0]),
        .funct3   (if_id_instruction[14:12]),
        .funct7   (if_id_instruction[31:25]),
        .ALUOp    (id_ALUOp_raw),
        .ALUSrc   (id_ALUSrc_raw),
        .MemRead  (id_MemRead_raw),
        .MemWrite (id_MemWrite_raw),
        .RegWrite (id_RegWrite_raw),
        .MemtoReg (id_MemtoReg_raw),
        .Branch   (id_Branch_raw)
    );

    // NOP control masking for low power.
    assign id_ALUOp    = id_is_nop ? 4'd0 : id_ALUOp_raw;
    assign id_ALUSrc   = id_is_nop ? 1'b0 : id_ALUSrc_raw;
    assign id_MemRead  = id_is_nop ? 1'b0 : id_MemRead_raw;
    assign id_MemWrite = id_is_nop ? 1'b0 : id_MemWrite_raw;
    assign id_RegWrite = id_is_nop ? 1'b0 : id_RegWrite_raw;
    assign id_MemtoReg = id_is_nop ? 1'b0 : id_MemtoReg_raw;
    assign id_Branch   = id_is_nop ? 1'b0 : id_Branch_raw;

    register_file reg_file (
        .clk        (clk),
        .rs1        (id_rs1),
        .rs2        (id_rs2),
        .rd         (mem_wb_rd),
        .write_data (wb_write_back_data),
        .reg_write  (mem_wb_RegWrite),
        .data1      (id_reg_data1),
        .data2      (id_reg_data2)
    );

    imm_gen ig (
        .instr(if_id_instruction),
        .imm  (id_imm)
    );

    // Early branch target calculation.
    assign id_branch_target = if_id_PC + id_imm;

    // Load-use hazard detection.
    assign stall = id_ex_MemRead &&
                   (id_ex_rd != 5'b0) &&
                   ((id_ex_rd == id_rs1) || (id_ex_rd == id_rs2));

    // ID/EX register.
    always @(posedge clk) begin
        if (rst || stall || flush) begin
            id_ex_PC            <= 32'b0;
            id_ex_reg_data1     <= 32'b0;
            id_ex_reg_data2     <= 32'b0;
            id_ex_imm           <= 32'b0;
            id_ex_branch_target <= 32'b0;

            id_ex_rs1 <= 5'b0;
            id_ex_rs2 <= 5'b0;
            id_ex_rd  <= 5'b0;

            id_ex_ALUOp <= 4'b0;

            id_ex_ALUSrc   <= 1'b0;
            id_ex_MemRead  <= 1'b0;
            id_ex_MemWrite <= 1'b0;
            id_ex_RegWrite <= 1'b0;
            id_ex_MemtoReg <= 1'b0;
            id_ex_Branch   <= 1'b0;
        end else begin
            id_ex_PC            <= if_id_PC;
            id_ex_reg_data1     <= id_reg_data1;
            id_ex_reg_data2     <= id_reg_data2;
            id_ex_imm           <= id_imm;
            id_ex_branch_target <= id_branch_target;

            id_ex_rs1 <= id_rs1;
            id_ex_rs2 <= id_rs2;
            id_ex_rd  <= id_rd;

            id_ex_ALUOp <= id_ALUOp;

            id_ex_ALUSrc   <= id_ALUSrc;
            id_ex_MemRead  <= id_MemRead;
            id_ex_MemWrite <= id_MemWrite;
            id_ex_RegWrite <= id_RegWrite;
            id_ex_MemtoReg <= id_MemtoReg;
            id_ex_Branch   <= id_Branch;
        end
    end

    // 3. EXECUTE

    // Forwarding.
    assign ForwardA =
        (ex_mem_RegWrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1)) ? 2'b10 :
        (mem_wb_RegWrite && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1)) ? 2'b01 :
        2'b00;

    assign ForwardB =
        (ex_mem_RegWrite && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2)) ? 2'b10 :
        (mem_wb_RegWrite && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) ? 2'b01 :
        2'b00;

    assign ex_forward_a =
        (ForwardA == 2'b10) ? ex_mem_alu_result :
        (ForwardA == 2'b01) ? wb_write_back_data  :
        id_ex_reg_data1;

    assign ex_forward_b =
        (ForwardB == 2'b10) ? ex_mem_alu_result :
        (ForwardB == 2'b01) ? wb_write_back_data  :
        id_ex_reg_data2;

    assign ex_alu_operand_a = ex_forward_a;
    assign ex_alu_operand_b = id_ex_ALUSrc ? id_ex_imm : ex_forward_b;

    // ALU is not needed for pure branch comparison unless branch is active.
    // Include branch in activity so branch compare can use forwarded operands.
    assign ex_alu_active = id_ex_RegWrite | id_ex_MemRead | id_ex_MemWrite | id_ex_Branch;

    // Operand isolation for low power.
    assign ex_alu_operand_a_iso = ex_alu_active ? ex_alu_operand_a : 32'b0;
    assign ex_alu_operand_b_iso = ex_alu_active ? ex_alu_operand_b : 32'b0;

    alu alu_u (
        .A          (ex_alu_operand_a_iso),
        .B          (ex_alu_operand_b_iso),
        .ALUControl (id_ex_ALUOp),
        .Result     (ex_alu_result),
        .Zero       (ex_alu_zero)
    );

    // BEQ compare uses direct equality instead of ALU subtract-zero.
    // Compare uses forwarded operands (ex_forward_a/ex_forward_b).
    assign ex_branch_taken_calc = id_ex_Branch && (ex_forward_a == ex_forward_b);

    // Flush signal generated immediately from EX stage branch decision.
    assign flush = ex_branch_taken_calc;

    // EX/MEM register.
    // IMPORTANT: flush must also kill the instruction currently in EX,
    // because branch resolves in EX stage now.
    always @(posedge clk) begin
        if (rst || flush) begin
            ex_mem_alu_result    <= 32'b0;
            ex_mem_reg_data2     <= 32'b0;
            ex_mem_branch_target <= 32'b0;
            ex_mem_rd            <= 5'b0;

            ex_mem_MemRead      <= 1'b0;
            ex_mem_MemWrite     <= 1'b0;
            ex_mem_RegWrite     <= 1'b0;
            ex_mem_MemtoReg     <= 1'b0;
            ex_mem_branch_taken <= 1'b0;
        end else begin
            ex_mem_alu_result    <= ex_alu_result;
            ex_mem_reg_data2     <= ex_forward_b;
            ex_mem_branch_target <= id_ex_branch_target;
            ex_mem_rd            <= id_ex_rd;

            ex_mem_MemRead      <= id_ex_MemRead;
            ex_mem_MemWrite     <= id_ex_MemWrite;
            ex_mem_RegWrite     <= id_ex_RegWrite;
            ex_mem_MemtoReg     <= id_ex_MemtoReg;
            ex_mem_branch_taken <= ex_branch_taken_calc;
        end
    end

    // 4. MEMORY
    wire        dmem_active;
    wire [31:0] dmem_addr_iso;
    wire [31:0] dmem_wdata_iso;

    assign dmem_active    = ex_mem_MemRead | ex_mem_MemWrite;
    assign dmem_addr_iso  = dmem_active ? ex_mem_alu_result : 32'b0;
    assign dmem_wdata_iso = ex_mem_MemWrite ? ex_mem_reg_data2 : 32'b0;

    data_mem dmem (
        .clk        (clk),
        .mem_read   (ex_mem_MemRead),
        .mem_write  (ex_mem_MemWrite),
        .addr       (dmem_addr_iso),
        .write_data (dmem_wdata_iso),
        .read_data  (mem_read_data)
    );

    // MEM/WB register.
    always @(posedge clk) begin
        if (rst) begin
            mem_wb_alu_result <= 32'b0;
            mem_wb_read_data  <= 32'b0;
            mem_wb_rd         <= 5'b0;
            mem_wb_RegWrite   <= 1'b0;
            mem_wb_MemtoReg   <= 1'b0;
        end else begin
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_read_data  <= mem_read_data;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_RegWrite   <= ex_mem_RegWrite;
            mem_wb_MemtoReg   <= ex_mem_MemtoReg;
        end
    end

    // 5. WRITE BACK
    assign wb_write_back_data = mem_wb_MemtoReg ? mem_wb_read_data : mem_wb_alu_result;
    assign wb_data            = wb_write_back_data;

    // Debug outputs
    generate
        if (DEBUG_EN) begin : GEN_DEBUG_ON
            assign dbg_if_id_PC          = if_id_PC;
            assign dbg_if_id_instruction = if_id_instruction;

            assign dbg_id_ex_PC          = id_ex_PC;
            assign dbg_id_ex_reg_data1   = id_ex_reg_data1;
            assign dbg_id_ex_reg_data2   = id_ex_reg_data2;
            assign dbg_id_ex_imm         = id_ex_imm;
            assign dbg_id_ex_rs1         = id_ex_rs1;
            assign dbg_id_ex_rs2         = id_ex_rs2;
            assign dbg_id_ex_rd          = id_ex_rd;
            assign dbg_id_ex_ALUOp       = id_ex_ALUOp;
            assign dbg_id_ex_ALUSrc      = id_ex_ALUSrc;
            assign dbg_id_ex_MemRead     = id_ex_MemRead;
            assign dbg_id_ex_MemWrite    = id_ex_MemWrite;
            assign dbg_id_ex_RegWrite    = id_ex_RegWrite;
            assign dbg_id_ex_MemtoReg    = id_ex_MemtoReg;
            assign dbg_id_ex_Branch      = id_ex_Branch;

            assign dbg_ex_mem_alu_result = ex_mem_alu_result;
            assign dbg_ex_mem_reg_data2  = ex_mem_reg_data2;
            assign dbg_ex_mem_rd         = ex_mem_rd;
            assign dbg_ex_mem_MemRead    = ex_mem_MemRead;
            assign dbg_ex_mem_MemWrite   = ex_mem_MemWrite;
            assign dbg_ex_mem_RegWrite   = ex_mem_RegWrite;
            assign dbg_ex_mem_MemtoReg   = ex_mem_MemtoReg;

            assign dbg_mem_wb_alu_result = mem_wb_alu_result;
            assign dbg_mem_wb_read_data  = mem_wb_read_data;
            assign dbg_mem_wb_rd         = mem_wb_rd;
            assign dbg_mem_wb_RegWrite   = mem_wb_RegWrite;
            assign dbg_mem_wb_MemtoReg   = mem_wb_MemtoReg;

            assign dbg_stall             = stall;
            assign dbg_flush             = flush;
            assign dbg_ForwardA          = ForwardA;
            assign dbg_ForwardB          = ForwardB;
            assign dbg_ex_branch_taken   = ex_mem_branch_taken;
            assign dbg_ex_branch_target  = ex_mem_branch_target;
        end else begin : GEN_DEBUG_OFF
            assign dbg_if_id_PC          = 32'b0;
            assign dbg_if_id_instruction = 32'b0;

            assign dbg_id_ex_PC          = 32'b0;
            assign dbg_id_ex_reg_data1   = 32'b0;
            assign dbg_id_ex_reg_data2   = 32'b0;
            assign dbg_id_ex_imm         = 32'b0;
            assign dbg_id_ex_rs1         = 5'b0;
            assign dbg_id_ex_rs2         = 5'b0;
            assign dbg_id_ex_rd          = 5'b0;
            assign dbg_id_ex_ALUOp       = 4'b0;
            assign dbg_id_ex_ALUSrc      = 1'b0;
            assign dbg_id_ex_MemRead     = 1'b0;
            assign dbg_id_ex_MemWrite    = 1'b0;
            assign dbg_id_ex_RegWrite    = 1'b0;
            assign dbg_id_ex_MemtoReg    = 1'b0;
            assign dbg_id_ex_Branch      = 1'b0;

            assign dbg_ex_mem_alu_result = 32'b0;
            assign dbg_ex_mem_reg_data2  = 32'b0;
            assign dbg_ex_mem_rd         = 5'b0;
            assign dbg_ex_mem_MemRead    = 1'b0;
            assign dbg_ex_mem_MemWrite   = 1'b0;
            assign dbg_ex_mem_RegWrite   = 1'b0;
            assign dbg_ex_mem_MemtoReg   = 1'b0;

            assign dbg_mem_wb_alu_result = 32'b0;
            assign dbg_mem_wb_read_data  = 32'b0;
            assign dbg_mem_wb_rd         = 5'b0;
            assign dbg_mem_wb_RegWrite   = 1'b0;
            assign dbg_mem_wb_MemtoReg   = 1'b0;

            assign dbg_stall             = 1'b0;
            assign dbg_flush             = 1'b0;
            assign dbg_ForwardA          = 2'b0;
            assign dbg_ForwardB          = 2'b0;
            assign dbg_ex_branch_taken   = 1'b0;
            assign dbg_ex_branch_target  = 32'b0;
        end
    endgenerate

endmodule


// INSTRUCTION MEMORY
module instruction_mem(
    input  [31:0] addr,
    output [31:0] instruction
);
    // Use block RAM inference for better timing on Artix-7 for moderate ROM sizes.
    (* ram_style = "block" *) reg [31:0] rom [0:63];

    integer i;

    initial begin
        for (i = 0; i < 64; i = i + 1)
            rom[i] = 32'h00000013;

        rom[0] = 32'h00a00093; // addi x1, x0, 10
        rom[1] = 32'h00500113; // addi x2, x0, 5
        rom[2] = 32'h002081b3; // add  x3, x1, x2
        rom[3] = 32'h4020c233; // xor/sub illustrative
        rom[4] = 32'h00302023; // sw   x3, 0(x0)
        rom[5] = 32'h00002203; // lw   x4, 0(x0)
        rom[6] = 32'h00418463; // beq  x3, x4, +8
        rom[7] = 32'h06300093; // addi x1, x0, 99
        rom[8] = 32'h002082b3; // add  x5, x1, x2
    end

    // word-aligned addressing
    assign instruction = rom[addr[7:2]];

endmodule


// CONTROL UNIT
module control_unit(
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output reg [3:0] ALUOp,
    output reg ALUSrc,
    output reg MemRead,
    output reg MemWrite,
    output reg RegWrite,
    output reg MemtoReg,
    output reg Branch
);

    localparam ADD = 4'd0;
    localparam SUB = 4'd1;
    localparam AND = 4'd2;
    localparam OR  = 4'd3;
    localparam SLT = 4'd4;
    localparam XOR = 4'd5;
    localparam SLL = 4'd6;
    localparam SRL = 4'd7;

    always @(*) begin
        ALUOp    = ADD;
        ALUSrc   = 1'b0;
        MemRead  = 1'b0;
        MemWrite = 1'b0;
        RegWrite = 1'b0;
        MemtoReg = 1'b0;
        Branch   = 1'b0;

        case (opcode)
            7'b0110011: begin // R-type
                RegWrite = 1'b1;
                case (funct3)
                    3'b000: ALUOp = (funct7 == 7'b0100000) ? SUB : ADD;
                    3'b111: ALUOp = AND;
                    3'b110: ALUOp = OR;
                    3'b100: ALUOp = XOR;
                    3'b001: ALUOp = SLL;
                    3'b101: ALUOp = SRL;
                    3'b010: ALUOp = SLT;
                    default: ALUOp = ADD;
                endcase
            end

            7'b0010011: begin // ADDI
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = ADD;
            end

            7'b0000011: begin // LW
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                MemRead  = 1'b1;
                MemtoReg = 1'b1;
                ALUOp    = ADD;
            end

            7'b0100011: begin // SW
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
                ALUOp    = ADD;
            end

            7'b1100011: begin // BEQ
                Branch   = 1'b1;
                ALUOp    = SUB;
            end

            default: begin
                ALUOp    = ADD;
                ALUSrc   = 1'b0;
                MemRead  = 1'b0;
                MemWrite = 1'b0;
                RegWrite = 1'b0;
                MemtoReg = 1'b0;
                Branch   = 1'b0;
            end
        endcase
    end

endmodule


// REGISTER FILE
module register_file(
    input clk,
    input  [4:0]  rs1,
    input  [4:0]  rs2,
    input  [4:0]  rd,
    input  [31:0] write_data,
    input         reg_write,
    output [31:0] data1,
    output [31:0] data2
);

    // Use block RAM for better timing on Artix-7; small regfile may still be distributed.
    (* ram_style = "block" *) reg [31:0] registers [0:31];

    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            registers[i] = 32'b0;
    end

    // Write-first bypass for correct same-cycle WB/ID behavior.
    assign data1 = (rs1 == 5'b0) ? 32'b0 :
                   (reg_write && (rd != 5'b0) && (rd == rs1)) ? write_data :
                   registers[rs1];

    assign data2 = (rs2 == 5'b0) ? 32'b0 :
                   (reg_write && (rd != 5'b0) && (rd == rs2)) ? write_data :
                   registers[rs2];

    always @(posedge clk) begin
        if (reg_write && (rd != 5'b0))
            registers[rd] <= write_data;
    end

endmodule


// IMMEDIATE GENERATOR
module imm_gen(
    input  [31:0] instr,
    output reg [31:0] imm
);

    always @(*) begin
        case (instr[6:0])
            7'b0010011,
            7'b0000011: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end

            7'b0100011: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            7'b1100011: begin
                imm = {{20{instr[31]}}, instr[7], instr[30:25],
                       instr[11:8], 1'b0};
            end

            default: begin
                imm = 32'b0;
            end
        endcase
    end

endmodule


// ALU
module alu(
    input  [31:0] A,
    input  [31:0] B,
    input  [3:0]  ALUControl,
    output reg [31:0] Result,
    output Zero
);

    always @(*) begin
        case (ALUControl)
            4'd0: Result = A + B;
            4'd1: Result = A - B;
            4'd2: Result = A & B;
            4'd3: Result = A | B;
            4'd4: Result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;
            4'd5: Result = A ^ B;
            4'd6: Result = A << B[4:0];
            4'd7: Result = A >> B[4:0];
            default: Result = 32'b0;
        endcase
    end

    assign Zero = (Result == 32'b0);

endmodule


// DATA MEMORY
module data_mem(
    input clk,
    input mem_read,
    input mem_write,
    input  [31:0] addr,
    input  [31:0] write_data,
    output [31:0] read_data
);

    (* ram_style = "block" *) reg [31:0] ram [0:63];

    integer i;

    initial begin
        for (i = 0; i < 64; i = i + 1)
            ram[i] = 32'b0;
    end

    assign read_data = mem_read ? ram[addr[7:2]] : 32'b0;

    always @(posedge clk) begin
        if (mem_write)
            ram[addr[7:2]] <= write_data;
    end

endmodule
