/*
===============================================================================
Module Name : alu_in2_mux
===============================================================================

Description:
------------
This module implements a 4-to-1 multiplexer for selecting the second input
to the ALU (alu_in2) in a RISC-V datapath.

The selection is controlled by two control signals:
    1. Lui
    2. ALUSrc

These two signals together form a 2-bit select input:
    sel = {Lui, ALUSrc}

Selection Logic:
----------------
    Lui  ALUSrc   alu_in2 Output
    --------------------------------
     0     0      rs2       (Register value - R-type instructions)
     0     1      imm       (Immediate value - I-type instructions)
     1     0      0         (Used in LUI instruction)
     1     1      pc        (Used in AUIPC instruction)
===============================================================================
*/
`timescale 1ns / 1ps
module alu_in2_mux #(
    parameter WIDTH = 32   // Width of data bus (default = 32 bits)
)(
    input  logic [WIDTH-1:0] rs2,     // Register source 2
    input  logic [WIDTH-1:0] imm,     // Immediate value
    input  logic [WIDTH-1:0] pc,      // Program counter
    input  logic             Lui,     // Control signal for LUI/AUIPC
    input  logic             ALUSrc,  // Control signal for ALU source select
    output logic [WIDTH-1:0] alu_in2  // Output to ALU
);

    // ------------------------------------------------------------------------
    // Combinational MUX Logic
    // Selects one of the inputs based on {Lui, ALUSrc}
    // ------------------------------------------------------------------------
    always_comb begin
        alu_in2 = '0;
        case ({Lui, ALUSrc})

            // 00 → Select register value (rs2)
            2'b00: alu_in2 = rs2;

            // 01 → Select immediate value (imm)
            2'b01: alu_in2 = imm;

            // 10 → Select zero (used in LUI)
            2'b10: alu_in2 = '0;

            // 11 → Select program counter (pc) (used in AUIPC)
            2'b11: alu_in2 = pc;

        endcase
    end

endmodule
