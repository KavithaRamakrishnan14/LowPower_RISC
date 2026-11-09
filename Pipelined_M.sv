// ============================================================
// Author: Goutham Badhrinath V
// 32-bit Signed Radix-4 Modified Booth 3S Pipelined Multiplier
// Wallace Reduction + Final 64-bit CLA
//
// Architecture:
//   Stage 1 : Radix-4 Booth PP Generation (17 PP rows)
//   Stage 2 : Wallace Compression Tree
//   Stage 3 : 64-bit Carry Lookahead Adder
// ============================================================

// ============================================================
// Top Multiplier
// ============================================================
`timescale 1ns / 1ps
module Pipelined_M(
    input clk,
    input rst,
    input logic start,
    output logic M_over,
    input  signed [31:0] A,
    input  signed [31:0] B,
    output signed [31:0] P_32,
    input logic M_ctrl
);
wire signed [63:0] pp [0:16];
reg signed [63:0] pp_next [0:16];
M1 multi1(.A(A),.B(B),.pp(pp));
integer i;
logic v1,v2,v2_prev;
logic valid_clk_en;

// LOW POWER CLOCK GATING:
// Shift the multiplier-valid bits only while a multiply is starting or draining.
// When idle, synthesis can map this hold behavior to clock-enable/ICG logic.
assign valid_clk_en = start | v1 | v2 | v2_prev;

always @(posedge clk) begin
    if (rst) begin
        v1 <= 0;
        v2 <= 0;
        v2_prev <= 0;
    end else if (valid_clk_en) begin
        v1 <= start;
        v2 <= v1;
        v2_prev <= v2;
    end
end
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 17; i = i + 1)
            pp_next[i] <= 0;
    end else if (start) begin
        for (i = 0; i < 17; i = i + 1)
            pp_next[i] <= pp[i];
    end
end

wire signed [63:0] s6;
wire signed [64:0] c6;
reg signed [63:0] s6_next;
reg signed [64:0] c6_next;

M2 multi2(.pp(pp_next),.s6(s6),.c6(c6));

always@(posedge clk) begin
    if (rst) begin
        s6_next <= 0;
        c6_next <= 0;
    end else if (v1) begin
        s6_next <= s6;
        c6_next <= c6;
    end
    
end

// ============================================================
// Final CLA
// ============================================================
reg signed [63:0] P;
wire cz;
cla64 Final_Add(
    .a(s6_next),
    .b(c6_next[63:0]),
    .cin(1'b0),
    .sum(P),
    .cout(cz)
);
logic _unused;
assign _unused = cz; // Unused carry-out
assign P_32 = M_ctrl ? P[63:32] : P[31:0];
assign M_over = ~v2_prev & v2; // Assert M_over for one cycle when multiplication is done

endmodule


module M1(
    input  signed [31:0] A,
    input  signed [31:0] B,
    output reg signed [63:0] pp [0:16]
);

// ============================================================
// Booth Partial Products
// ============================================================

//wire signed [63:0] pp [0:16];

genvar i;

generate

    for(i=0;i<17;i=i+1) begin : BOOTH_PP_GEN

        wire [2:0] booth_bits;
        wire signed [2:0] code;

        if(i == 0) begin : GEN_I0
            assign booth_bits = {B[1], B[0], 1'b0};
        end
        else if(i == 16) begin : GEN_I16
            assign booth_bits = {B[31], B[31], B[31]};
        end
        else begin : GEN_MID
            assign booth_bits = {B[2*i+1], B[2*i], B[2*i-1]};
        end
        booth_encoder ENC(
            .y(booth_bits),
            .code(code)
        );

        reg signed [63:0] temp;

        always @(*) begin
            case(code)

                0: temp = 64'd0;

                1: temp = {{32{A[31]}},A};

               -1: temp = -({{32{A[31]}},A});

                2: temp = ({{32{A[31]}},A} <<< 1);

               -2: temp = -(({{32{A[31]}},A}) <<< 1);

                default: temp = 64'd0;

            endcase
        end

        assign pp[i] = $signed(temp) <<< (2*i);

    end

endgenerate
endmodule

module M2(
    input wire signed [63:0] pp [0:16],
    output signed [63:0] s6,
    output signed [64:0] c6
);

/* Stage 1 Partial Products:
    s1[0] c1[0]
    s1[1] c1[1]
    s1[2] c1[2]
    s1[3] c1[3]
    s1[4] c1[4]
    pp15  pp16  - remain unchanged
*/
// ============================================================
// Wallace Compression Tree
// ============================================================

// Stage 1
wire [63:0] s1 [0:4];
wire [64:0] c1 [0:4];
assign c1 [0][0] = 0;
assign c1 [1][0] = 0;
assign c1 [2][0] = 0;
assign c1 [3][0] = 0;
assign c1 [4][0] = 0;
genvar i;
generate

for(i=0;i<5;i=i+1) begin : WALLACE_STAGE1

    genvar j;

    for(j=0;j<64;j=j+1) begin : S1_GEN

        full_adder FA(
            .a   (pp[i*3][j]),
            .b   (pp[i*3+1][j]),
            .cin (pp[i*3+2][j]),
            .sum (s1[i][j]),
            .carry(c1[i][j+1])
        );

    end

end

endgenerate

// ============================================================
// Stage 2
// ============================================================

wire [63:0] s2 [0:3];
wire [64:0] c2 [0:3];
assign c2 [0][0] = 0;
assign c2 [1][0] = 0;
assign c2 [2][0] = 0;
assign c2 [3][0] = 0;
generate

    genvar k;

    for(k=0;k<64;k=k+1) begin : S2_GEN1

        full_adder FA2(
            .a   (s1[0][k]),
            .b   (c1[0][k]),
            .cin (s1[1][k]),
            .sum (s2[0][k]),
            .carry(c2[0][k+1])
        );

    end
    for(k=0;k<64;k=k+1) begin : S2_GEN2

        full_adder FA3(
            .a   (c1[1][k]),
            .b   (c1[2][k]),
            .cin (s1[2][k]),
            .sum (s2[1][k]),
            .carry(c2[1][k+1])
        );

    end
    for(k=0;k<64;k=k+1) begin : S2_GEN3

        full_adder FA4(
            .a   (s1[3][k]),
            .b   (c1[3][k]),
            .cin (s1[4][k]),
            .sum (s2[2][k]),
            .carry(c2[2][k+1])
        );

    end
    for(k=0;k<64;k=k+1) begin : S2_GEN4

        full_adder FA5(
            .a   (c1[4][k]),
            .b   (pp[15][k]),
            .cin (pp[16][k]),
            .sum (s2[3][k]),
            .carry(c2[3][k+1])
        );

    end


endgenerate

// ============================================================
// Stage 3
// ============================================================
wire [63:0] s3 [0:1];
wire [64:0] c3 [0:1];
assign c3 [0][0] = 0;
assign c3 [1][0] = 0;
generate

    genvar k1;

    for(k1=0;k1<64;k1=k1+1) begin : S3_GEN1

        full_adder FA6(
            .a   (s2[0][k1]),
            .b   (s2[1][k1]),
            .cin (c2[0][k1]),
            .sum (s3[0][k1]),
            .carry(c3[0][k1+1])
        );

    end
    for(k1=0;k1<64;k1=k1+1) begin : S3_GEN2

        full_adder FA7(
            .a   (s2[2][k1]),
            .b   (c2[1][k1]),
            .cin (c2[2][k1]),
            .sum (s3[1][k1]),
            .carry(c3[1][k1+1])
        );

    end

endgenerate

// ============================================================
// Stage 4
// ============================================================
wire [63:0] s4 [0:1];
wire [64:0] c4 [0:1];
assign c4 [0][0] = 0;
assign c4 [1][0] = 0;
generate

    genvar k2;

    for(k2=0;k2<64;k2=k2+1) begin : S4_GEN1

        full_adder FA8(
            .a   (s3[0][k2]),
            .b   (s3[1][k2]),
            .cin (c3[0][k2]),
            .sum (s4[0][k2]),
            .carry(c4[0][k2+1])
        );

    end
    for(k2=0;k2<64;k2=k2+1) begin : S4_GEN2

        full_adder FA9(
            .a   (c3[1][k2]),
            .b   (s2[3][k2]),
            .cin (c2[3][k2]),
            .sum (s4[1][k2]),
            .carry(c4[1][k2+1])
        );

    end

endgenerate

// ============================================================
// Stage 5
// ============================================================
wire [63:0] s5;
wire [64:0] c5;
assign c5[0] = 0;
generate

    genvar k4;

    for(k4=0;k4<64;k4=k4+1) begin : S5_GEN

        full_adder FA10(
            .a   (s4[0][k4]),
            .b   (s4[1][k4]),
            .cin (c4[0][k4]),
            .sum (s5[k4]),
            .carry(c5[k4+1])
        );

    end

endgenerate

// ============================================================
// Stage 6
// ============================================================
//wire [63:0] s6;
//wire [64:0] c6;
assign c6[0] = 0;
generate

    genvar k5;

    for(k5=0;k5<64;k5=k5+1) begin : S6_GEN

        full_adder FA11(
            .a   (s5[k5]),
            .b   (c5[k5]),
            .cin (c4[1][k5]),
            .sum (s6[k5]),
            .carry(c6[k5+1])
        );

    end

endgenerate

endmodule

module half_adder(
    input  a,
    input  b,
    output sum,
    output carry
);
assign sum   = a ^ b;
assign carry = a & b;
endmodule

module full_adder(
    input  a,
    input  b,
    input  cin,
    output sum,
    output carry
);
assign sum   = a ^ b ^ cin;
assign carry = (a & b) | (b & cin) | (a & cin);
endmodule


// ============================================================
// Radix-4 Booth Encoder
// ============================================================

module booth_encoder(
    input  [2:0] y,
    output reg signed [2:0] code
);

always @(*) begin
    case(y)
        3'b000: code =  0;
        3'b001: code = +1;
        3'b010: code = +1;
        3'b011: code = +2;
        3'b100: code = -2;
        3'b101: code = -1;
        3'b110: code = -1;
        3'b111: code =  0;
    endcase
end

endmodule

// ============================================================
// 64-bit Carry Lookahead Adder (CLA)
// Fully Functional Hierarchical CLA
// Supports fast carry computation using:
//   - 1-bit Generate/Propagate
//   - 4-bit CLA blocks
//   - 16-bit CLA blocks
//   - 64-bit top-level CLA
// ============================================================


// ============================================================
// 1-BIT GP CELL
// ============================================================

module gp_cell(
    input  wire a,
    input  wire b,
    output wire g,
    output wire p
);

assign g = a & b;   // Generate
assign p = a ^ b;   // Propagate

endmodule


// ============================================================
// 4-BIT CLA BLOCK
// ============================================================

module cla4(
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,

    output wire [3:0] sum,
    output wire       cout,

    output wire       G,
    output wire       P
);

wire [3:0] g, p;
wire c0,c1,c2,c3,c4;
wire [4:0] c = {c4, c3, c2, c1, c0};

// Generate/Propagate
genvar i;
generate
    for(i=0; i<4; i=i+1) begin : GP
        gp_cell gp_inst(
            .a(a[i]),
            .b(b[i]),
            .g(g[i]),
            .p(p[i])
        );
    end
endgenerate

assign c0 = cin;

// Carry Lookahead Logic
assign c1 = g[0] | (p[0] & c0);

assign c2 = g[1]
            | (p[1] & g[0])
            | (p[1] & p[0] & c0);

assign c3 = g[2]
            | (p[2] & g[1])
            | (p[2] & p[1] & g[0])
            | (p[2] & p[1] & p[0] & c0);

assign c4 = g[3]
            | (p[3] & g[2])
            | (p[3] & p[2] & g[1])
            | (p[3] & p[2] & p[1] & g[0])
            | (p[3] & p[2] & p[1] & p[0] & c0);

// Sum
assign sum[0] = p[0] ^ c0;
assign sum[1] = p[1] ^ c1;
assign sum[2] = p[2] ^ c2;
assign sum[3] = p[3] ^ c3;

assign cout = c4;

// Group Generate / Propagate
assign P = p[3] & p[2] & p[1] & p[0];

assign G = g[3]
         | (p[3] & g[2])
         | (p[3] & p[2] & g[1])
         | (p[3] & p[2] & p[1] & g[0]);

endmodule


// ============================================================
// 16-BIT CLA
// Built using four 4-bit CLA blocks
// ============================================================

module cla16(
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        cin,

    output wire [15:0] sum,
    output wire        cout,

    output wire        G,
    output wire        P
);

wire [3:0] blockG, blockP;
wire c0,c1,c2,c3,c4;
wire [4:0] c = {c4, c3, c2, c1, c0};
wire cx;
assign c0 = cin;

// Carry between 4-bit blocks
assign c1 = blockG[0]
            | (blockP[0] & c0);

assign c2 = blockG[1]
            | (blockP[1] & blockG[0])
            | (blockP[1] & blockP[0] & c0);

assign c3 = blockG[2]
            | (blockP[2] & blockG[1])
            | (blockP[2] & blockP[1] & blockG[0])
            | (blockP[2] & blockP[1] & blockP[0] & c0);

assign c4 = blockG[3]
            | (blockP[3] & blockG[2])
            | (blockP[3] & blockP[2] & blockG[1])
            | (blockP[3] & blockP[2] & blockP[1] & blockG[0])
            | (blockP[3] & blockP[2] & blockP[1] & blockP[0] & c0);

// 4-bit CLA instances
genvar i;
generate
    for(i=0; i<4; i=i+1) begin : CLA4_BLOCKS

        cla4 cla4_inst(
            .a   (a[i*4 +: 4]),
            .b   (b[i*4 +: 4]),
            .cin (c[i]),

            .sum (sum[i*4 +: 4]),
            .cout(cx),

            .G   (blockG[i]),
            .P   (blockP[i])
        );

    end
endgenerate
logic _unused;
assign _unused = cx;
assign cout = c4;

// Group Generate/Propagate
assign P = blockP[3] & blockP[2] & blockP[1] & blockP[0];

assign G = blockG[3]
         | (blockP[3] & blockG[2])
         | (blockP[3] & blockP[2] & blockG[1])
         | (blockP[3] & blockP[2] & blockP[1] & blockG[0]);

endmodule


// ============================================================
// 64-BIT CLA TOP MODULE
// Built using four 16-bit CLA blocks
// ============================================================

module cla64(
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire        cin,

    output wire [63:0] sum,
    output wire        cout
);
wire cy;
wire [3:0] blockG, blockP;
wire c0,c1,c2,c3,c4;
wire [4:0] c = {c4, c3, c2, c1, c0};

assign c0 = cin;

// Carry lookahead between 16-bit blocks
assign c1 = blockG[0]
            | (blockP[0] & c0);

assign c2 = blockG[1]
            | (blockP[1] & blockG[0])
            | (blockP[1] & blockP[0] & c0);

assign c3 = blockG[2]
            | (blockP[2] & blockG[1])
            | (blockP[2] & blockP[1] & blockG[0])
            | (blockP[2] & blockP[1] & blockP[0] & c0);

assign c4 = blockG[3]
            | (blockP[3] & blockG[2])
            | (blockP[3] & blockP[2] & blockG[1])
            | (blockP[3] & blockP[2] & blockP[1] & blockG[0])
            | (blockP[3] & blockP[2] & blockP[1] & blockP[0] & c0);

// 16-bit CLA blocks
genvar i;
generate
    for(i=0; i<4; i=i+1) begin : CLA16_BLOCKS

        cla16 cla16_inst(
            .a   (a[i*16 +: 16]),
            .b   (b[i*16 +: 16]),
            .cin (c[i]),

            .sum (sum[i*16 +: 16]),
            .cout(cy),

            .G   (blockG[i]),
            .P   (blockP[i])
        );

    end
endgenerate

assign cout = c4;
logic _unused;
assign _unused = cy;
endmodule
