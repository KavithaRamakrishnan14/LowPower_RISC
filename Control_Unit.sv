`timescale 1ns / 1ps
module Control_Unit (
    input  logic [6:0] opcode,        // opcode
    input  logic [2:0] funct3,
    input  logic       funct7_5,  // Instr[30]
    input  logic       funct7_0,  // Instr[25] (M extension)

    // Control Outputs
    output logic       RegWrite,
    output logic [1:0] MemtoReg,
    output logic       ALUSrc,
    output logic       Lui,
    output logic [3:0] ALUControl,
    output logic       Jump,
    output logic       Branch,
    output logic       Mul,
    output logic       M_ctrl,
    output logic       lsu_req,
    output logic       lsu_we,
    output logic [1:0] lsu_type,
    output logic       lsu_sign_ext
);

    // Internal signals
    logic [1:0] ALUOp;

    // =========================
    // MAIN DECODER
    // =========================
    always_comb begin
        // Default values (avoid latches)
        RegWrite   = 0;
        ALUSrc     = 0;
        Lui        = 0;
        MemtoReg   = 2'b00;
        Jump       = 0;
        Branch     = 0;
        ALUOp      = 2'b00;
        lsu_req    = 0;
        lsu_we     = 0;
        lsu_type   = 2'b00;
        lsu_sign_ext = 0;
        case (opcode)

            // LOAD (lw)
            7'b0000011: begin
                RegWrite  = 1;
                ALUSrc    = 1;
                Lui       = 0;
                MemtoReg  = 2'b01;
                Jump      = 0;
                Branch    = 0;
                ALUOp     = 2'b00;
                lsu_req    = 1;
                lsu_we     = 0;
                case(funct3)
                3'b000: begin
                    lsu_type   = 2'b10;
                    lsu_sign_ext = 1;
                end
                3'b001: begin
                    lsu_type   = 2'b01;
                    lsu_sign_ext = 1;
                end
                3'b010: begin
                    lsu_type   = 2'b00;
                    lsu_sign_ext = 1;
                end
                3'b100: begin
                    lsu_type   = 2'b10;
                    lsu_sign_ext = 0;
                end
                3'b101: begin
                    lsu_type   = 2'b01;
                    lsu_sign_ext = 0;
                end
                default :begin
                    lsu_type   = 2'b00;
                    lsu_sign_ext = 1;
                end
                endcase
            end

            // STORE (sw)
            7'b0100011: begin
                RegWrite  = 0;
                ALUSrc    = 1;
                Lui       = 0;
                MemtoReg  = 2'b11;
                Jump      = 0;
                Branch    = 0;
                ALUOp     = 2'b00;
                lsu_req    = 1;
                lsu_we     = 1;
                case(funct3)
                3'b000:
                    lsu_type   = 2'b10;
                3'b001: 
                    lsu_type   = 2'b01;
                3'b010: 
                    lsu_type   = 2'b00;
                default:
                    lsu_type   = 2'b00;
            endcase
            end

            // R-TYPE // MUL (M extension)
            7'b0110011: begin
                RegWrite  = 1;
                ALUSrc    = 0;
                Lui       = 0;
                MemtoReg  = 2'b00;
                Jump      = 0;
                Branch    = 0;
                ALUOp     = 2'b10;
            end

            // BRANCH 
            7'b1100011: begin
                RegWrite  = 0;
                ALUSrc    = 0;
                Lui       = 0;
                MemtoReg  = 2'b11;
                Jump      = 0;
                Branch    = 1;
                ALUOp     = 2'b01;
            end

            // I-TYPE ALU
            7'b0010011: begin
                RegWrite  = 1;
                ALUSrc    = 1;
                Lui       = 0;
                MemtoReg  = 2'b00;
                Jump      = 0;
                Branch    = 0;
                ALUOp     = 2'b10;
            end

            // JAL
            7'b1101111: begin
                RegWrite  = 1;
                ALUSrc    = 1; // PC= PC + imm ccurs in ALU and is sent to PC mux when Jump = 1
                Lui       = 1;
                MemtoReg  = 2'b10; // rd = PC + 4
                Jump      = 1;
                Branch    = 0;
                ALUOp     = 2'b00;
            end
            // JALR
            7'b1100111: begin
                RegWrite  = 1;
                ALUSrc    = 1; // PC = rs1 + imm occurs in ALU and is sent to PC mux when Jump = 1
                Lui       = 0;
                MemtoReg  = 2'b10; // rd = PC + 4
                Jump      = 1;
                Branch    = 0;
                ALUOp     = 2'b00;
            end
            // LUI
            7'b0110111: begin
                RegWrite  = 1;
                ALUSrc    = 0; 
                Lui       =  1;
                MemtoReg  = 2'b00; // ALU will be configured to pass imm directly to rd
                Jump      = 0;
                Branch    = 0;
                ALUOp     = 2'b00;
            end
            // AUIPC
            7'b0010111: begin
                RegWrite  = 1;
                ALUSrc    = 1;
                Lui       = 1; 
                MemtoReg  = 2'b00; // ALU will be configured to add imm to PC and pass result to rd
                Jump      = 0;
                Branch    = 0;
                ALUOp     = 2'b00;
            end

            default: begin
                RegWrite   = 0;
                ALUSrc     = 0;
                Lui        = 0;
                MemtoReg   = 2'b11;
                Jump       = 0;
                Branch     = 0;
                ALUOp      = 2'b00;
            end

        endcase
    end


    // =========================
    // ALU DECODER
    // =========================
    always_comb begin

        ALUControl = 4'b0000;
        Mul = 0;
        M_ctrl = 0;
        case (ALUOp)

            // ADD (lw, sw, JAL, JALR, LUI, AUIPC etc)
            2'b00: begin 
                ALUControl = 4'b0000;
                Mul = 0;
                M_ctrl = 0;
            end  

            // Branch use funct3 directly to determine the type of branch
            2'b01: begin
                ALUControl = {1'b1, funct3};
                Mul = 0;
                M_ctrl = 0;
            end
            // R-type / I-type ALU ops / MUL (M extension)
            2'b10: begin
                // Using same ALUControl for M-EXT Multiplier to reduce pipeline registers.
                if (opcode == 7'b0010011) begin 
                    if (funct3 == 3'b101)
                        ALUControl = {funct7_5, funct3};
                    else
                        ALUControl = {1'b0, funct3};
                Mul = 0;
                M_ctrl = 0;
                end
                else if (opcode == 7'b0110011) begin
                    ALUControl = {funct7_5, funct3};
                    Mul = funct7_0;
                    M_ctrl = funct3[0] | funct3[1];
                end
            end
            // Use funct7 bit 5 to distinguish between ADD/SUB
            // Use funct7 bit 0 to distinguish between MUL and other R-type ops (M extension)
            default: begin 
                ALUControl = 4'b0000;
                Mul = 0;
                M_ctrl = 0;
            end
        endcase
    end

endmodule


// Documentation of control signals:
/*
ALUSrc = 1 meaning we load imm not rs2
ALUSrc = 0 meaning we load rs2
MemtoReg {
    00: ALU result
    01: Memory data (for lw)
    10: PC + 4 (for JAL)
    11: Don't care (for sw, branches) meaning no writeback to rd
}


*/
