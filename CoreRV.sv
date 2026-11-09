`timescale 1ns / 1ps
module CoreRV #(
    parameter BOOT_ADDR = 32'h0000_0000,
    parameter INSTR_ADDR = 32'h0000_0100,
    parameter DATA_ADDR = 32'h0000_0200,
    parameter EXTERNAL_ADDR = 32'h0000_0300
)(
    input logic clk,
    input logic rst,
    
    output logic [31:0] data_addr_o,
    output logic [31:0] data_wdata_o,
    output logic data_we_o,
    output logic data_req_o,
    output logic [3:0] data_be_o,
    input logic [31:0] data_rdata_i,
    input logic data_gnt_i,
    input logic data_rvalid_i
);
typedef struct packed {
    logic [4:0] rd_s12;
    logic [31:0] PC;
    logic [31:0] rs1_value;
    logic [31:0] rs2_value;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [31:0] imm;
    logic [17:0] ctrl;
    logic [31:0] rdata_mem;
} s1_buffer;


// Memory Width and Size Parameters
localparam int DATA_WORDS = (EXTERNAL_ADDR - DATA_ADDR) / 4;
localparam int DATA_ADDR_WIDTH = $clog2(DATA_WORDS); 
localparam int INSTR_WORDS = (DATA_ADDR - INSTR_ADDR) / 4;
localparam int INSTR_ADDR_WIDTH = $clog2(INSTR_WORDS);
localparam int BOOT_WORDS = (INSTR_ADDR - BOOT_ADDR) / 4;
localparam int BOOT_ADDR_WIDTH = $clog2(BOOT_WORDS);


//Stage 1 Signals
logic Reg_wb, branch_flush, redirect_flush, redirect_flush_d, Jump;
logic [4:0] rd_out;
logic [31:0] data_wb;
logic [31:0] BranchAddr;
logic [31:0] ALUResult;
logic [31:0] instr_PC_S12, rs1_value_S12, rs2_value_S12;
logic [4:0] rs1_S12, rs2_S12;
logic uses_rs1_S12, uses_rs2_S12;
logic [31:0] imm;
logic [17:0] ctrl;
logic m_stall;
logic load_hazard;
logic front_stall;
logic [4:0] rd_s12;
logic [1:0] PCSrc;
logic M_over;

// Buffer to hold Stage 1 outputs for use in Stage 2
s1_buffer s1_buf;

assign PCSrc = (m_stall) ? 2'b00 : {Jump,branch_flush};
assign redirect_flush = (!m_stall) && (branch_flush | Jump);
assign front_stall = m_stall | load_hazard;
logic loadE;
assign loadE = s1_buf.ctrl[17] && (s1_buf.ctrl[16:15] == 2'b01); // Check if it's a load instruction in EX stage

//Instruction memory Signals
logic en_mem;
logic [INSTR_ADDR_WIDTH-1:0] addr_mem;
logic [31:0] wdata_mem;
logic [31:0] rdata_mem;
logic we_mem;
logic [3:0] be_mem;
logic sign_ext_mem;

//Stage 2 Signals
logic [31:0] exec_result;
logic [4:0] rd_S23;
logic [31:0] rs2_value_S23;
logic [7:0] ctrl_s2;
logic [31:0] pc_out_s2;
logic [1:0] ForwardA, ForwardB;
logic mul_start;

// Memory Stage Signals
logic dram_en_i;
logic [DATA_ADDR_WIDTH-1:0] dram_addr_i;
logic [31:0] dram_wdata_i;
logic [31:0] dram_rdata_i;
logic dram_we_i;
logic [3:0] dram_be_i;
logic dram_sign_ext_i;
logic [1:0] mem_select;
logic lsu_we_i;
logic [1:0] lsu_type_i;
logic [31:0] lsu_wdata_i;
logic lsu_sign_ext_i;
logic lsu_req_i;
logic [31:0] adder_result_ex_i;
logic [31:0] lsu_rdata_o;
logic lsu_rdata_valid_o;
logic busy_o;
logic mem_access_s2;
logic mem_write_s2;
logic [31:0] mem_addr_iso;
logic [31:0] store_data_iso;

// WB signals
logic [31:0] alu_result_wb;
logic [31:0] pc_wb;
logic [1:0] memtoreg_wb;
logic [4:0] rd_wb;
logic       regwrite_wb;

// Mem to WB BUFFER
logic [31:0] alu_result_buf;
logic [31:0] mem_data_buf;
logic [31:0] pc_buf;
logic [1:0] memtoreg_buf;
logic [4:0] rd_buf;
logic       regwrite_buf;
logic [31:0] Mem_Ctrl_PC;
logic boot_mode;

//LSU
logic lsu_req_pulse;
logic lsu_req_issued;

// LOW POWER CLOCK GATING:
// Keep high-fanout pipeline registers from receiving new data while the stage is
// intentionally stalled. FPGA tools infer clock enables from these guards; ASIC
// flows can replace the enables with integrated clock-gating cells.
logic redirect_flush_d_clk_en;
logic s1_buf_clk_en;
logic ex_mem_clk_en;
logic mem_wb_clk_en;

assign redirect_flush_d_clk_en = (redirect_flush_d != redirect_flush);
assign s1_buf_clk_en           = !m_stall;
assign ex_mem_clk_en           = !m_stall;

// LOW POWER OPERAND ISOLATION:
// Memory address decode and store-data alignment are only meaningful for real
// load/store traffic. Non-memory instructions drive stable zeros into this
// combinational datapath.
assign mem_access_s2  = ctrl_s2[4] && !m_stall;
assign mem_write_s2   = mem_access_s2 && ctrl_s2[3];
assign mem_addr_iso   = mem_access_s2 ? exec_result   : 32'd0;
assign store_data_iso = mem_write_s2  ? rs2_value_S23 : 32'd0;

Memory_Ctrl #(
    .INSTR_ADDR(INSTR_ADDR)
) mem_ctrl (
    .clk(clk),
    .rst(rst),
    .Mem_Ctrl_PC(Mem_Ctrl_PC),
    .boot_mode(boot_mode)
);
Stage1 #(
    .INSTR_ADDR_WIDTH(INSTR_ADDR_WIDTH),
    .BOOT_ADDR_WIDTH(BOOT_ADDR_WIDTH),
    .INSTR_WORDS(INSTR_WORDS),
    .BOOT_WORDS(BOOT_WORDS),
    .BOOT_ADDR(BOOT_ADDR),
    .INSTR_ADDR(INSTR_ADDR)
) s1(
    .clk(clk),
    .rst(rst),
    .pc_stall(front_stall),
    .RegWrite_wb(Reg_wb),
    .rd(rd_out),
    .rd_s12(rd_s12),
    .wb_data(data_wb),
    .PCSrc(PCSrc),
    .BranchAddr(BranchAddr),
    .ALUResult(ALUResult),
    .PC(Mem_Ctrl_PC),
    .boot_mode(boot_mode),
    .instr_PC(instr_PC_S12),
    .rs1_value(rs1_value_S12),
    .rs2_value(rs2_value_S12),
    .rs1(rs1_S12),
    .rs2(rs2_S12),
    .uses_rs1(uses_rs1_S12),
    .uses_rs2(uses_rs2_S12),
    .imm(imm),
    .ctrl(ctrl),
    .redirect_flush(redirect_flush),
    .redirect_flush_d(redirect_flush_d),
    // From MEM Stage 
    .en_mem(en_mem),
    .addr_mem(addr_mem),
    .wdata_mem(wdata_mem),
    .rdata_mem(rdata_mem),
    .we_mem(we_mem),
    .be_mem(be_mem),
    .sign_ext_mem(sign_ext_mem)
);


// The instruction RAM has a registered output. After a branch or jump,
// outstanding wrong-path read arrives one cycle after the redirect, so keep
// the Stage 1/2 buffer invalid for that additional cycle.
always_ff @(posedge clk) begin
    if (rst)
        redirect_flush_d <= 1'b0;
    else if (redirect_flush_d_clk_en)
        redirect_flush_d <= redirect_flush;
end

always_ff @(posedge clk) begin
    if (rst || redirect_flush || redirect_flush_d) begin
        s1_buf.PC <= 32'b0;
        s1_buf.rs1_value <= 32'b0;
        s1_buf.rs2_value <= 32'b0;
        s1_buf.rs1 <= 5'b0;
        s1_buf.rs2 <= 5'b0;
        s1_buf.imm <= 32'b0;
        s1_buf.ctrl <= 18'b0;
        s1_buf.rd_s12 <= 5'b0;
        s1_buf.rdata_mem <= 32'b0;
    end
    else if (s1_buf_clk_en) begin
        if (load_hazard) begin
            // Freeze fetch/decode and inject a NOP into EX while the load advances.
            s1_buf.PC <= 32'b0;
            s1_buf.rs1_value <= 32'b0;
            s1_buf.rs2_value <= 32'b0;
            s1_buf.rs1 <= 5'b0;
            s1_buf.rs2 <= 5'b0;
            s1_buf.imm <= 32'b0;
            s1_buf.ctrl <= 18'b0;
            s1_buf.rd_s12 <= 5'b0;
            s1_buf.rdata_mem <= 32'b0;
        end
        else begin
            s1_buf.PC <= instr_PC_S12;
            s1_buf.rs1_value <= rs1_value_S12;
            s1_buf.rs2_value <= rs2_value_S12;
            s1_buf.rs1 <= rs1_S12;
            s1_buf.rs2 <= rs2_S12;
            s1_buf.imm <= imm;
            s1_buf.ctrl <= ctrl;
            s1_buf.rd_s12 <= rd_s12;
            s1_buf.rdata_mem <= rdata_mem;
        end
    end
end

Stage2 s2 (
    .clk(clk),
    .rst(rst),
    .pc_in_2(s1_buf.PC),
    .imm(s1_buf.imm),
    .rs1_value(s1_buf.rs1_value),
    .rs2_value(s1_buf.rs2_value),
    .rd(s1_buf.rd_s12),
    .ctrl_s1(s1_buf.ctrl),
    .ForwardA(ForwardA),
    .ForwardB(ForwardB),
    .Fwd_rd_value1(data_wb),
    .Fwd_rd_value2(alu_result_wb),
    .mul_start(mul_start),
    .exec_result(exec_result),
    .rd_out(rd_S23),
    .rs2_value_out(rs2_value_S23),
    .branch_flush(branch_flush),
    .ctrl_s2(ctrl_s2),
    .BranchAddr(BranchAddr),
    .ALUResult(ALUResult),
    .pc_out_s2(pc_out_s2),
    .M_over(M_over),
    .Jump(Jump)
);

always_comb begin
    mem_select = 2'b00;

    en_mem = 0;
    addr_mem = 0;
    wdata_mem = 0;
    we_mem = 0;
    be_mem = 0;

    dram_en_i = 0;
    dram_addr_i = 0;
    dram_wdata_i = 0;
    dram_we_i = 0;
    dram_be_i = 0;

    lsu_we_i = 0;
    lsu_type_i = 0;
    lsu_wdata_i = 0;
    lsu_sign_ext_i = 0;
    lsu_req_i = 0;
    adder_result_ex_i = 0;

    if(mem_access_s2 && (mem_addr_iso >= INSTR_ADDR) && (mem_addr_iso < DATA_ADDR))  begin
        // Handle instruction memory access
        mem_select = 2'b01;
        en_mem = mem_access_s2 && boot_mode; // Only enable instruction memory access in boot mode
        addr_mem = (mem_addr_iso - INSTR_ADDR) >> 2;
        unique case (ctrl_s2[2:1])
            2'b00: wdata_mem = store_data_iso; //word
            2'b01: begin // half-word
                unique case (mem_addr_iso[1:0])
                2'b00: wdata_mem = {16'b0, store_data_iso[15:0]}; // lower half-word
                2'b01: wdata_mem = {8'b0, store_data_iso[23:8], 8'b0}; //
                2'b10: wdata_mem = {store_data_iso[31:16], 16'b0}; // upper half-word
                2'b11: wdata_mem = {store_data_iso[31:24], 16'b0, store_data_iso[7:0]}; //
                default: wdata_mem = {16'b0, store_data_iso[15:0]};
                endcase
            end
            2'b10: begin // byte
                unique case (mem_addr_iso[1:0])
                2'b00: wdata_mem = {24'b0, store_data_iso[7:0]}; // byte 0 (lowest)
                2'b01: wdata_mem = {16'b0, store_data_iso[15:8], 8'b0}; // byte 1
                2'b10: wdata_mem = {8'b0, store_data_iso[23:16], 16'b0}; // byte 2
                2'b11: wdata_mem = {store_data_iso[31:24], 24'b0}; // byte 3
                default: wdata_mem = {24'b0, store_data_iso[7:0]};
                endcase
            end
            default: wdata_mem = store_data_iso;
        endcase
        we_mem = mem_write_s2;
        sign_ext_mem = ctrl_s2[0];
        unique case (ctrl_s2[2:1])
            2'b00: be_mem = 4'b1111; //word
            2'b01: begin // half-word
                unique case (mem_addr_iso[1:0])
                2'b00: be_mem = 4'b0011; // lower half-word
                2'b01: be_mem = 4'b0110; // 
                2'b10: be_mem = 4'b1100; // upper half-word 
                2'b11: be_mem = 4'b1001; // 
                default: be_mem = 4'b0011;
                endcase
            end
            2'b10: begin // byte
                unique case (mem_addr_iso[1:0])
                2'b00: be_mem = 4'b0001; // byte 0 (lowest)
                2'b01: be_mem = 4'b0010; // byte 1
                2'b10: be_mem = 4'b0100; // byte 2
                2'b11: be_mem = 4'b1000; // byte 3
                default: be_mem = 4'b0001;
                endcase
            end
            default: be_mem = 4'b1111;
        endcase
    end
    else if(mem_access_s2 && (mem_addr_iso >= DATA_ADDR) && (mem_addr_iso < EXTERNAL_ADDR)) begin
        mem_select = 2'b00;
        dram_en_i = mem_access_s2;
        dram_addr_i = (mem_addr_iso - DATA_ADDR) >> 2;
        unique case (ctrl_s2[2:1])
            2'b00: dram_wdata_i = store_data_iso; //word
            2'b01: begin // half-word
                unique case (mem_addr_iso[1:0])
                2'b00: dram_wdata_i = {16'b0, store_data_iso[15:0]}; // lower half-word
                2'b01: dram_wdata_i = {8'b0, store_data_iso[23:8], 8'b0}; //
                2'b10: dram_wdata_i = {store_data_iso[31:16], 16'b0}; // upper half-word
                2'b11: dram_wdata_i = {store_data_iso[31:24], 16'b0, store_data_iso[7:0]}; //
                default: dram_wdata_i = {16'b0, store_data_iso[15:0]};
                endcase
            end
            2'b10: begin // byte
                unique case (mem_addr_iso[1:0])
                2'b00: dram_wdata_i = {24'b0, store_data_iso[7:0]}; // byte 0 (lowest)
                2'b01: dram_wdata_i = {16'b0, store_data_iso[15:8], 8'b0}; // byte 1
                2'b10: dram_wdata_i = {8'b0, store_data_iso[23:16], 16'b0}; // byte 2
                2'b11: dram_wdata_i = {store_data_iso[31:24], 24'b0}; // byte 3
                default: dram_wdata_i = {24'b0, store_data_iso[7:0]};
                endcase
            end
            default: dram_wdata_i = store_data_iso;
        endcase
        dram_we_i = mem_write_s2;
        dram_sign_ext_i = ctrl_s2[0];
        unique case (ctrl_s2[2:1])
            2'b00: dram_be_i = 4'b1111; //word
            2'b01: begin // half-word
                unique case (mem_addr_iso[1:0])
                2'b00: dram_be_i = 4'b0011; // lower half-word
                2'b01: dram_be_i = 4'b0110; // 
                2'b10: dram_be_i = 4'b1100; // upper half-word 
                2'b11: dram_be_i = 4'b1001; // 
                default: dram_be_i = 4'b0011;
                endcase
            end
            2'b10: begin // byte
                unique case (mem_addr_iso[1:0])
                2'b00: dram_be_i = 4'b0001; // byte 0 (lowest)
                2'b01: dram_be_i = 4'b0010; // byte 1
                2'b10: dram_be_i = 4'b0100; // byte 2
                2'b11: dram_be_i = 4'b1000; // byte 3
                default: dram_be_i = 4'b0001;
                endcase
            end
            default: dram_be_i = 4'b1111;
        endcase
    end
    else if(mem_access_s2 && (mem_addr_iso >= EXTERNAL_ADDR)) begin
        // Handle external I/O access (e.g., UART, GPIO)
        mem_select = 2'b10;
        lsu_we_i = mem_write_s2;
        lsu_type_i = ctrl_s2[2:1];
        lsu_wdata_i = store_data_iso;
        lsu_sign_ext_i = ctrl_s2[0];
        lsu_req_i = mem_access_s2;
        adder_result_ex_i = (mem_addr_iso - EXTERNAL_ADDR);
    end
end

stall_controller stall_ctrl (
    .clk(clk),
    .rst(rst),
    .rs1E(s1_buf.rs1),
    .rs2E(s1_buf.rs2),
    .rdW(rd_buf),
    .RegWriteW(Reg_wb),
    .RegWriteM(regwrite_wb),
    .ForwardAE(ForwardA),
    .ForwardBE(ForwardB),
    .rs1D(rs1_S12),
    .rs2D(rs2_S12),
    .rdE(s1_buf.rd_s12),
    .uses_rs1D(uses_rs1_S12),
    .uses_rs2D(uses_rs2_S12),
    .loadE(loadE),
    .load_hazard(load_hazard),
    .mul_req(s1_buf.ctrl[6]),
    .mul_start(mul_start),
    .M_over(M_over),
    .lsu_busy(busy_o),
    .pipe_stall(m_stall),
    .rdM(rd_wb)
);

LSU_RVX lsu(
  .clk(clk),
  .rst(rst),

  // data interface
  .data_req_o(data_req_o),
  .data_gnt_i(data_gnt_i),
  .data_rvalid_i(data_rvalid_i),

  .data_addr_o(data_addr_o),
  .data_we_o(data_we_o),
  .data_be_o(data_be_o),
  .data_wdata_o(data_wdata_o),
  .data_rdata_i(data_rdata_i),

  // ID/EX inputs
  .we_i(lsu_we_i),
  .type_i(lsu_type_i),
  .wdata_i(lsu_wdata_i),
  .sign_ext_i(lsu_sign_ext_i),
  .req_i(lsu_req_pulse),
  .addr_i(adder_result_ex_i),

  // outputs to WB / pipeline control
  .rdata_o(lsu_rdata_o),
  .rvalid_o(lsu_rdata_valid_o),
  .busy_o(busy_o)
);

data_ram #(
    .ADDR_WIDTH(DATA_ADDR_WIDTH),
    .DATA_WIDTH(32),
    .NUM_WORDS(DATA_WORDS)
) dram(
    .clk(clk),
    .en_i(dram_en_i),
    .addr_i(dram_addr_i),
    .wdata_i(dram_wdata_i),
    .rdata_o(dram_rdata_i),
    .we_i(dram_we_i),
    .be_i(dram_be_i),
    .sign_ext_i(dram_sign_ext_i)
);
logic [1:0] mem_select_wb;
// EXE-MEM stage buffer
always_ff @(posedge clk) begin
    if (rst) begin
        alu_result_wb <= 32'd0;
        pc_wb         <= 32'd0;
        memtoreg_wb   <= 2'b00;
        rd_wb         <= 5'd0;
        regwrite_wb   <= 1'b0;
        mem_select_wb <= 2'b00;
    end
    else if (ex_mem_clk_en) begin
        alu_result_wb <= exec_result;
        pc_wb         <= pc_out_s2;
        memtoreg_wb   <= ctrl_s2[7:6];
        rd_wb         <= rd_S23;
        regwrite_wb   <= ctrl_s2[5];
        mem_select_wb <= mem_select;
    end
end
logic [31:0] mem_data_wb;
/////////////////////////////////////////////////////////////
// LSU waiting signals for external memory access
logic lsu_load_wait_wb;
assign lsu_load_wait_wb = (mem_select_wb == 2'b10) &&
                          (memtoreg_wb == 2'b01) &&
                          !lsu_rdata_valid_o;
assign mem_wb_clk_en = !lsu_load_wait_wb;

assign lsu_req_pulse = lsu_req_i && !lsu_req_issued;

always_ff @(posedge clk) begin
    if (rst)
        lsu_req_issued <= 1'b0;
    else if (lsu_rdata_valid_o)
        lsu_req_issued <= 1'b0;
    else if (lsu_req_pulse)
        lsu_req_issued <= 1'b1;
end
/////////////////////////////////////////////////////////////

always_comb begin
    mem_data_wb = 32'd0;
    if (memtoreg_wb == 2'b01) begin
        case(mem_select_wb)
            2'b00: mem_data_wb = dram_rdata_i;
            2'b01: mem_data_wb = rdata_mem;
            2'b10: mem_data_wb = lsu_rdata_o;
            default: mem_data_wb = 32'd0;
        endcase
    end
end
//MEM-WB stage buffer
always_ff @(posedge clk) begin
    if (rst) begin
        alu_result_buf <= 32'd0;
        pc_buf         <= 32'd0;
        memtoreg_buf   <= 2'b00;
        mem_data_buf    <= 32'd0;
        rd_buf          <= 5'd0;
        regwrite_buf    <= 1'b0;
    end
    else if (mem_wb_clk_en) begin
        alu_result_buf  <= alu_result_wb;
        pc_buf          <= pc_wb;
        memtoreg_buf    <= memtoreg_wb;
        mem_data_buf    <= mem_data_wb;
        rd_buf          <= rd_wb;
        regwrite_buf    <= regwrite_wb;
    end
end
//WB Mux
memtoreg_mux mux_wb (
    .alu_result (alu_result_buf),
    .mem_data   (mem_data_buf),
    .pc         (pc_buf),
    .MemtoReg   (memtoreg_buf),
    .wb_data    (data_wb)
);
assign rd_out = rd_buf;
assign Reg_wb = regwrite_buf;

endmodule
