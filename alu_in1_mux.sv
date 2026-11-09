`timescale 1ns / 1ps
module alu_in1_mux #(
    parameter WIDTH = 32
)(
    input  logic [WIDTH-1:0] rs1,     // data from source register 1 from Register file
    input  logic [WIDTH-1:0] imm,     // Immediate value
    input  logic             Lui,     // control signal
    output logic [WIDTH-1:0] alu_in1  // First input for the ALU
);
    // MUX logic
    always_comb begin
        if (Lui)
            alu_in1 = imm;     // if Lui = 1 , then 12 bit shifted input is selected as 1st input for ALU
        else
            alu_in1 = rs1;    // if Lui = 0 , then source register 1 is selected as 1st input for ALU
    end

endmodule
