`timescale 1ns / 1ps
module Stage1 #(
    parameter INSTR_ADDR_WIDTH = 8,
    parameter BOOT_ADDR_WIDTH  = 8,
    parameter INSTR_WORDS      = 256,
    parameter BOOT_WORDS       = 256,
    parameter BOOT_ADDR = 32'h0000_0000,
    parameter INSTR_ADDR = 32'h0000_8000
)(
    input logic clk,
    input logic rst,
    input logic pc_stall,
    input logic RegWrite_wb,
    input logic [4:0] rd,
    output logic [4:0] rd_s12,
    input logic [31:0] wb_data,
    input logic [1:0] PCSrc,
    input logic [31:0] BranchAddr,
    input logic [31:0] ALUResult,
    output logic [31:0] PC,
    output logic [31:0] instr_PC,
    output logic [31:0] rs1_value,
    output logic [31:0] rs2_value,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic uses_rs1,
    output logic uses_rs2,
    output logic [31:0] imm,
    output logic [17:0] ctrl,
    input logic redirect_flush,
    input logic redirect_flush_d,
    // From MEM Stage 
    input  logic                   en_mem,
    input  logic [INSTR_ADDR_WIDTH-1:0]  addr_mem,
    input  logic [31:0]            wdata_mem,
    output logic [31:0]            rdata_mem,
    input  logic                   we_mem,
    input  logic [3:0]             be_mem,
    input  logic                   sign_ext_mem,

    input logic boot_mode
);
logic [31:0] instr;
logic [31:0] mux_out;
logic [31:0] instr_reg;
logic [31:0] instr_PC_reg;
//Control signals for Stage 1 
logic [3:0] ALUControl;
logic [1:0] MemtoReg;
logic [1:0] lsu_type;
logic RegWrite, ALUSrc, Lui, Jump, Branch, Mul, M_ctrl, lsu_req, lsu_we, lsu_sign_ext;
logic pc_clk_en;
logic if_id_clk_en;
logic [31:0] rs1_value_raw;
logic [31:0] rs2_value_raw;

// LOW POWER CLOCK GATING:
// These enables keep the fetch PC and IF/ID instruction flops quiet while the
// front end is stalled. A redirect is still allowed to update the PC immediately.
assign pc_clk_en    = !pc_stall || (PCSrc != 2'b00);
assign if_id_clk_en = !pc_stall;

pc_mux mux1 (
    .branch_addr(BranchAddr),
    .alu_result(ALUResult),
    .pcsrc(PCSrc),
    .pc_in(mux_out), // Connect to PC input
    .PC(PC),
    .pc_stall(pc_stall)
);
always_ff @(posedge clk) begin
    if (rst) begin
        PC       <= 32'b0;
        instr_PC_reg <= 32'b0;
    end
    else if (pc_clk_en) begin
        PC <= mux_out; // Update PC with the output of the mux
        if (if_id_clk_en)
            instr_PC_reg <= PC;
    end
end
logic [BOOT_ADDR_WIDTH-1:0] boot_fetch_addr;
logic [INSTR_ADDR_WIDTH-1:0] instr_fetch_addr;

always_comb begin
    boot_fetch_addr  = '0;
    instr_fetch_addr = '0;

    if (boot_mode)
        boot_fetch_addr = (PC - BOOT_ADDR) >> 2;
    else
        instr_fetch_addr = (PC - INSTR_ADDR) >> 2;
end
instr_ram #(
    .INSTR_ADDR_WIDTH(INSTR_ADDR_WIDTH),
    .BOOT_ADDR_WIDTH(BOOT_ADDR_WIDTH),
    .INSTR_WORDS(INSTR_WORDS),
    .BOOT_WORDS(BOOT_WORDS)
)instr_mem(
    .clk(clk),
    .en_a_i(!pc_stall),
    .addr_boot_a_i(boot_fetch_addr),
    .addr_instr_a_i(instr_fetch_addr),
    .wdata_a_i(32'b0),
    .rdata_a_o(instr_reg),
    .we_a_i(1'b0),
    .be_a_i(4'b0),
    .en_b_i(en_mem),
    .addr_b_i(addr_mem),
    .wdata_b_i(wdata_mem),
    .rdata_b_o(rdata_mem),
    .we_b_i(we_mem),
    .be_b_i(be_mem),
    .sign_ext_b_i(sign_ext_mem),
    .boot_mode(boot_mode)
);
always_ff @(posedge clk) begin
    if (rst || redirect_flush || redirect_flush_d) begin
        instr <= 32'b0;
        instr_PC <= 32'b0;
    end
    else if (if_id_clk_en) begin
        instr <= instr_reg; // Update instruction register with the fetched instruction
        instr_PC <= instr_PC_reg; // Update instruction PC register with the current PC
    end
end
register_file rf (
    .clk(clk),
    .rst(rst),
    .rs1(instr[19:15]),
    .rs2(instr[24:20]),
    .rd(rd),
    .rd_value(wb_data),
    .regwrite(RegWrite_wb),
    .rs1_value(rs1_value_raw), 
    .rs2_value(rs2_value_raw)
);

Control_Unit cu (
    .opcode(instr[6:0]),
    .funct3(instr[14:12]),
    .funct7_5(instr[30]),
    .funct7_0(instr[25]),
    .RegWrite(RegWrite),
    .MemtoReg(MemtoReg),
    .ALUSrc(ALUSrc),
    .Lui(Lui),
    .ALUControl(ALUControl),
    .Jump(Jump),
    .Branch(Branch),
    .Mul(Mul),
    .M_ctrl(M_ctrl),
    .lsu_req(lsu_req),
    .lsu_we(lsu_we),
    .lsu_type(lsu_type),
    .lsu_sign_ext(lsu_sign_ext)
);

assign ctrl = {
    RegWrite,        // 1 (17)
    MemtoReg,        // 2 (16:15)
    ALUSrc,          // 1 (14)
    Lui,             // 1 (13)
    ALUControl,      // 4 (12:9)
    Jump,            // 1 (8)
    Branch,          // 1 (7)
    Mul,             // 1 (6)
    M_ctrl,          // 1 (5)
    lsu_req,         // 1 (4)
    lsu_we,          // 1 (3)
    lsu_type,        // 2 (2:1)
    lsu_sign_ext     // 1 (0)
                     // 18 bits total
};

immediate_generator imm_gen (
    .instr(instr),
    .imm_out(imm)
);

assign rs1 = instr[19:15];
assign rs2 = instr[24:20];
assign rd_s12 = instr[11:7];

always_comb begin
    uses_rs1 = 1'b0;
    uses_rs2 = 1'b0;

    unique case (instr[6:0])
        7'b0000011, // LOAD
        7'b0010011, // I-type ALU
        7'b1100111: // JALR
            uses_rs1 = 1'b1;

        7'b0100011, // STORE
        7'b0110011, // R-type / M extension
        7'b1100011: begin // BRANCH
            uses_rs1 = 1'b1;
            uses_rs2 = 1'b1;
        end

        default: begin
            uses_rs1 = 1'b0;
            uses_rs2 = 1'b0;
        end
    endcase
end

// LOW POWER OPERAND ISOLATION:
// Only propagate register-file read data for source operands that the decoded
// instruction actually observes.
assign rs1_value = uses_rs1 ? rs1_value_raw : 32'd0;
assign rs2_value = uses_rs2 ? rs2_value_raw : 32'd0;

endmodule
