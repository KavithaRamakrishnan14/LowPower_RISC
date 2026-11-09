// module for selecting the output from alu or the multipler
`timescale 1ns / 1ps
module alu_mul_mux #(
    parameter WIDTH = 32                 // 32-bit
)(
    input  logic [WIDTH-1:0] alu_result, // output from alu
    input  logic [WIDTH-1:0] mul_result, // output from multiplier
    input  logic             Mul,        // select signal Mul from the control unit
    output logic [WIDTH-1:0] exec_result
);

    always_comb begin
        if (Mul)
            exec_result = mul_result;   // if Mul=1 the result of multiplier goes to execute stage
        else
            exec_result = alu_result;   // if Mul=0 the result of alu goes to execute stage
    end

endmodule
