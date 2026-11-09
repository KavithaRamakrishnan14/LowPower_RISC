`timescale 1ns / 1ps
module Stage2(
    input logic clk,
    input logic rst,
    input logic [31:0] pc_in_2,
    input logic [31:0] imm,
    input logic [31:0] rs1_value,
    input logic [31:0] rs2_value,
    input logic [4:0] rd,
    input logic [17:0] ctrl_s1,
    input logic [1:0] ForwardA,
    input logic [1:0] ForwardB,
    input logic [31:0] Fwd_rd_value1, //data_wb from Write Back stage
    input logic [31:0] Fwd_rd_value2, //alu_result_wb from Mem stage
    input logic mul_start,
    output logic [31:0] exec_result, // Final result after ALU/Mul Mux
    output logic [4:0] rd_out,
    output logic [31:0] rs2_value_out,
    output logic branch_flush,
    output logic [7:0] ctrl_s2,
    output logic [31:0] BranchAddr,
    output logic [31:0] ALUResult, // for jars/jalrs
    output logic [31:0] pc_out_s2,
    output logic M_over,
    output logic Jump
);
    logic compare_out;
    logic [31:0] alu_result;
    logic [31:0] mul_result;
    logic [31:0] alu_in1;
    logic [31:0] alu_in2;
    logic [3:0] ALUControl;
    logic [1:0] MemtoReg;
    logic [1:0] lsu_type;
    logic RegWrite, ALUSrc, Lui, Branch, Mul, M_ctrl, lsu_req, lsu_we, lsu_sign_ext;
    //Forwarding Signals
    logic [31:0] rs1_val_after, rs2_val_after;
    logic        alu_operand_active;
    logic [31:0] rs1_alu_iso, rs2_alu_iso, imm_alu_iso, pc_alu_iso;
    logic [3:0]  alu_control_iso;
    logic        alu_branch_iso;
    logic        branch_addr_active;
    logic [31:0] branch_pc_iso, branch_imm_iso, branch_addr_sum;
    logic        mul_operand_active;
    logic signed [31:0] mul_A_iso, mul_B_iso;
    logic        mul_ctrl_iso;

    // LOW POWER OPERAND ISOLATION:
    // Keep forwarded operands from rippling through the ALU on bubbles and
    // while the multiplier owns the execute stage.
    assign alu_operand_active = !Mul && (RegWrite || Branch || Jump || lsu_req);
    assign rs1_alu_iso        = alu_operand_active ? rs1_val_after : 32'd0;
    assign rs2_alu_iso        = alu_operand_active ? rs2_val_after : 32'd0;
    assign imm_alu_iso        = alu_operand_active ? imm           : 32'd0;
    assign pc_alu_iso         = alu_operand_active ? pc_in_2       : 32'd0;
    assign alu_control_iso    = alu_operand_active ? ALUControl    : 4'b0000;
    assign alu_branch_iso     = alu_operand_active ? Branch        : 1'b0;

    // LOW POWER OPERAND ISOLATION:
    // The branch-target adder is idle for every non-branch instruction.
    assign branch_addr_active = Branch && !Mul;
    assign branch_pc_iso      = branch_addr_active ? pc_in_2 : 32'd0;
    assign branch_imm_iso     = branch_addr_active ? imm     : 32'd0;
    assign branch_addr_sum    = branch_pc_iso + branch_imm_iso;

    // LOW POWER OPERAND ISOLATION:
    // The Booth multiplier is the widest switching block in execute. Hold its
    // inputs at zero for non-MUL instructions so the partial-product tree does
    // not toggle on ordinary ALU/load/store/branch traffic. During a MUL, the
    // pipeline is stalled, so Mul stays asserted until M_over returns.
    assign mul_operand_active = Mul | mul_start;
    assign mul_A_iso          = mul_operand_active ? $signed(rs1_val_after) : 32'sd0;
    assign mul_B_iso          = mul_operand_active ? $signed(rs2_val_after) : 32'sd0;
    assign mul_ctrl_iso       = mul_operand_active ? M_ctrl : 1'b0;

    assign {
    RegWrite,        // 1
    MemtoReg,        // 2
    ALUSrc,          // 1
    Lui,             // 1
    ALUControl,      // 4
    Jump,            // 1
    Branch,          // 1
    Mul,             // 1
    M_ctrl,          // 1
    lsu_req,         // 1
    lsu_we,          // 1
    lsu_type,        // 2
    lsu_sign_ext     // 1
                     // 18 bits total
    } = ctrl_s1;

always_comb begin
    case(ForwardA)
        2'b00: rs1_val_after = rs1_value;
        2'b01: rs1_val_after = Fwd_rd_value1;
        2'b10: rs1_val_after = Fwd_rd_value2;
        default: rs1_val_after = rs1_value;
    endcase
    case(ForwardB)
        2'b00: rs2_val_after = rs2_value;
        2'b01: rs2_val_after = Fwd_rd_value1;
        2'b10: rs2_val_after = Fwd_rd_value2;
        default: rs2_val_after = rs2_value;
    endcase
end

alu_in1_mux mux1 (
    .rs1(rs1_alu_iso),
    .imm(imm_alu_iso),
    .Lui(Lui),
    .alu_in1(alu_in1)
);

alu_in2_mux mux2 (
    .rs2(rs2_alu_iso),
    .imm(imm_alu_iso),
    .pc(pc_alu_iso),
    .Lui(Lui),
    .ALUSrc(ALUSrc),
    .alu_in2(alu_in2)
);

alu alu (
    .a(alu_in1),
    .b(alu_in2),
    .Control(alu_control_iso),
    .branch(alu_branch_iso),
    .result(alu_result),
    .compare_out(compare_out)
);

Pipelined_M multi (
    .A(mul_A_iso),
    .B(mul_B_iso),
    .clk(clk),
    .rst(rst),
    .P_32(mul_result),
    .M_ctrl(mul_ctrl_iso),
    .start(mul_start),
    .M_over(M_over)
);

alu_mul_mux mux3 (
    .alu_result(alu_result),
    .mul_result(mul_result),
    .Mul(Mul),
    .exec_result(exec_result)
);

    assign branch_flush = compare_out & Branch;
    assign BranchAddr = branch_addr_active ? branch_addr_sum : 32'b0;
    assign ctrl_s2 = {
        MemtoReg,       // 2 (7:6)
        RegWrite,       // 1 (5)
        lsu_req,        // 1 (4)
        lsu_we,         // 1 (3)
        lsu_type,       // 2 (2:1)
        lsu_sign_ext    // 1 (0)
                        // 8 bits total
    };
    assign rd_out = rd;
    assign ALUResult = alu_result; // Address Calculation for Load/Store + ALU Result
    assign rs2_value_out = lsu_we ? rs2_val_after : 32'd0;
    assign pc_out_s2 = pc_in_2;

endmodule
