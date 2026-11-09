`timescale 1ns / 1ps
module pc_mux (
    input  logic [31:0] branch_addr,
    input  logic [31:0] alu_result,
    input  logic [1:0]  pcsrc,
    input  logic        pc_stall,
    output logic [31:0] pc_in,
    input logic [31:0] PC
);

always_comb begin
    case (pcsrc)
        2'b10: pc_in = alu_result;     // JALR
        2'b01: pc_in = branch_addr;    // Branch
        default: begin
            if (pc_stall)
                pc_in = PC;
            else
                pc_in = PC + 4;
        end
    endcase
end
endmodule
