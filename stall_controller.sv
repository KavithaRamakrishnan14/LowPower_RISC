`timescale 1ns / 1ps
module stall_controller (
    input  logic clk,
    input  logic rst,
    //Forwarding Unit Signals
    input logic [4:0] rs1E,rs2E,rdW,rdM,
    input logic RegWriteW,RegWriteM,
    output logic [1:0] ForwardAE,ForwardBE,
    // Load-use hazard
    input logic [4:0] rs1D,rs2D,rdE,
    input logic uses_rs1D,uses_rs2D,loadE,
    output logic load_hazard,
    // MUL
    input  logic mul_req,
    input  logic M_over,
    output logic mul_start,
    // LSU
    input  logic lsu_busy,
    // Final stall
    output logic pipe_stall
);
    always_comb begin
        ForwardAE = 2'b00;
        ForwardBE = 2'b00;

        if (!rst) begin
            // Memory-stage forwarding has priority over writeback forwarding.
            if ((rs1E == rdM) && RegWriteM && (rdM != 0))
                ForwardAE = 2'b10;
            else if ((rs1E == rdW) && RegWriteW && (rdW != 0))
                ForwardAE = 2'b01;

            if ((rs2E == rdM) && RegWriteM && (rdM != 0))
                ForwardBE = 2'b10;
            else if ((rs2E == rdW) && RegWriteW && (rdW != 0))
                ForwardBE = 2'b01;
        end
    end

    assign load_hazard = loadE && (rdE != 5'd0) &&((uses_rs1D && (rs1D == rdE)) ||(uses_rs2D && (rs2D == rdE)));

    logic M_busy;

    // A request starts only while idle.
    // for one cycle so the completed result and its controls advance together.
    assign mul_start = mul_req && !M_busy && !M_over && !rst;

    always_ff @(posedge clk) begin
        if (rst)
            M_busy <= 1'b0;
        else if (M_over)
            M_busy <= 1'b0;
        else if (mul_start)
            M_busy <= 1'b1;
    end

    assign pipe_stall = lsu_busy || mul_start || (M_busy && !M_over);

endmodule
