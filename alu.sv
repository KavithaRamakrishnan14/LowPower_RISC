`timescale 1ns / 1ps
module alu(
    input  logic [31:0] a, b,
    input  logic [3:0]  Control,
    input  logic        branch,
    output logic [31:0] result,
    output logic        compare_out
);

always_comb begin
    result      = 32'd0;
    compare_out = 1'b0;

    if (branch) begin
        unique case (Control)
            4'b1000: compare_out = (a == b);                   // BEQ
            4'b1001: compare_out = (a != b);                   // BNE
            4'b1100: compare_out = ($signed(a) < $signed(b));  // BLT
            4'b1101: compare_out = ($signed(a) >= $signed(b)); // BGE
            4'b1110: compare_out = (a < b);                    // BLTU
            4'b1111: compare_out = (a >= b);                   // BGEU
            default: compare_out = 1'b0;
        endcase
    end 
    else begin
        unique case (Control)
            4'b0000: result = a + b;                           // ADD
            4'b1000: result = a - b;                           // SUB
            4'b0100: result = a ^ b;                           // XOR
            4'b0110: result = a | b;                           // OR
            4'b0111: result = a & b;                           // AND

            // Shift
            4'b0001: result = a << b[4:0];                     // SLL
            4'b0101: result = a >> b[4:0];                     // SRL
            4'b1101: result = $signed(a) >>> b[4:0];           // SRA

            // Set Less Than
            4'b0010: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            4'b0011: result = (a < b) ? 32'd1 : 32'd0;                   // SLTU

            default: result = 32'd0;
        endcase
    end
end

endmodule
