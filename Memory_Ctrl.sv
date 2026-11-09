`timescale 1ns / 1ps
module Memory_Ctrl #(
    parameter INSTR_ADDR = 32'h0000_8000
)(
    input logic clk,
    input logic rst,
    input logic [31:0] Mem_Ctrl_PC,
    output logic boot_mode
);
always_ff @(posedge clk) begin
    if (rst) begin
        boot_mode <= 1'b1; // Start in boot mode
    end else begin
        // Exit boot mode when PC reaches INSTR_ADDR
        if (Mem_Ctrl_PC >= (INSTR_ADDR - 32'd4)) begin
            boot_mode <= 1'b0;
        end
    end
end
endmodule
