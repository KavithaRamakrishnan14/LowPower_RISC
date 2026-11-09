`timescale 1ns/1ps
module register_file (
    input  logic        clk, rst,          // Clock and asynchronous reset
    input  logic [4:0]  rs1, rs2, rd,      // Register addresses (32 registers → 5 bits)
    input  logic [31:0] rd_value,          // Data to be written into destination register
    input  logic        regwrite,          // Write enable signal
    output logic [31:0] rs1_value,         // Read data from rs1
    output logic [31:0] rs2_value          // Read data from rs2
);

    // 32 registers, each 32-bit wide

    logic [31:0] regfile [31:0];


    // WRITE + RESET LOGIC (Sequential)
    
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++)
                regfile[i] <= 32'b0;
        end
        else if (regwrite && (rd != 5'd0) && (regfile[rd] != rd_value)) begin
            // LOW POWER CLOCK GATING:
            // Skip same-data writes so the selected register and write muxes do not toggle.
            // x0 is always zero, so ignore rd = 0.
            regfile[rd] <= rd_value;
        end
    end

  
    // This combinational logic implements the read ports with bypassing for the current write.
    //     addi x5, x0, 10
    //     addi x6, x0, 20
    //     addi x7, x0, 30
    //     ori  x8, x5, 1 (The value of x5 should be 10, not the previous value, even though the write to x5 happens in the same cycle as the read for x5)

assign rs1_value =(rs1 == 5'd0) ? 32'd0 :(regwrite && (rd != 5'd0) && (rs1 == rd)) ? rd_value : regfile[rs1];

assign rs2_value =(rs2 == 5'd0) ? 32'd0 :(regwrite && (rd != 5'd0) && (rs2 == rd)) ? rd_value : regfile[rs2];

endmodule  
