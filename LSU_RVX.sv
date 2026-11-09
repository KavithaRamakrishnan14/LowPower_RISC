module LSU_RVX (
  input  logic         clk,
  input  logic         rst,

  // Memory interface
  output logic         data_req_o,
  input  logic         data_gnt_i,
  input  logic         data_rvalid_i,

  output logic [31:0]  data_addr_o,
  output logic         data_we_o,
  output logic [3:0]   data_be_o,
  output logic [31:0]  data_wdata_o,
  input  logic [31:0]  data_rdata_i,

  // Request
  input  logic         req_i,
  input  logic         we_i,
  input  logic [1:0]   type_i,      // 00=word, 01=half, 10=byte
  input  logic         sign_ext_i,
  input  logic [31:0]  addr_i,
  input  logic [31:0]  wdata_i,

  // Response
  output logic [31:0]  rdata_o,
  output logic         rvalid_o,
  output logic         busy_o
);

  // -------------------------------
  // Internal registers
  // -------------------------------
  logic [31:0] addr_q;
  logic [31:0] wdata_q;
  logic [1:0]  type_q;
  logic        we_q;
  logic        sign_ext_q;
  logic [1:0]  offset_q;

  logic misaligned_q;
  assign misaligned_q = (type_q == 2'b00 && offset_q != 2'b00) || (type_q == 2'b01 && offset_q == 2'b11);

  logic [31:0] rdata_low_q;
  logic        load_resp_active;
  logic        write_req_active;
  logic [31:0] data_rdata_iso;

  // -------------------------------
  // Misaligned detect
  // -------------------------------
  logic [1:0] offset;

  assign offset = addr_i[1:0];


  // -------------------------------
  // FSM
  // -------------------------------
  // LOW POWER STATE ENCODING:
  // The common LSU path is sequential, so a Gray-style state assignment cuts
  // state-bit toggles compared with the default binary enum.
  typedef enum logic [2:0] {
    IDLE         = 3'b000,
    REQ1         = 3'b001,
    WAIT_RVALID1 = 3'b011,
    REQ2         = 3'b010,
    WAIT_RVALID2 = 3'b110
  } state_e;

  state_e state, next;
  logic state_clk_en;

  // LOW POWER CLOCK GATING:
  // The LSU sits in IDLE for most cycles. Only clock the FSM state register
  // when a request/handshake actually changes the state.
  assign state_clk_en = (next != state);
  assign load_resp_active = ((state == WAIT_RVALID1) || (state == WAIT_RVALID2)) && data_rvalid_i;
  assign write_req_active = we_q && ((state == REQ1) || (state == REQ2));
  assign data_rdata_iso   = load_resp_active ? data_rdata_i : 32'd0;

  // -------------------------------
  // Control latch
  // -------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      addr_q      <= 0;
      wdata_q     <= 0;
      type_q      <= 0;
      we_q        <= 0;
      sign_ext_q  <= 0;
      offset_q    <= 0;
    end else if (state == IDLE && req_i) begin
      addr_q      <= addr_i;
      wdata_q     <= wdata_i;
      type_q      <= type_i;
      we_q        <= we_i;
      sign_ext_q  <= sign_ext_i;
      offset_q    <= offset;
    end
  end

  // -------------------------------
  // FSM next-state
  // -------------------------------
  always_comb begin
    next = state;

    case (state)

      IDLE:
        if (req_i) next = REQ1;

      REQ1:
        if (data_gnt_i)
          next = WAIT_RVALID1;

      WAIT_RVALID1:
        if (data_rvalid_i) begin
          if (misaligned_q)
            next = REQ2;
          else
            next = IDLE;
        end

      REQ2:
        if (data_gnt_i)
          next = WAIT_RVALID2;

      WAIT_RVALID2:
        if (data_rvalid_i)
          next = IDLE;

    endcase
  end

  always_ff @(posedge clk) begin
    if (rst)
      state <= IDLE;
    else if (state_clk_en)
      state <= next;
  end

  assign busy_o = (state != IDLE);

  // -------------------------------
  // Address generation
  // -------------------------------
  logic [31:0] base_addr;

  assign base_addr = {addr_q[31:2], 2'b00};

  assign data_addr_o =
      (state == REQ2 || state == WAIT_RVALID2)
      ? ((base_addr + 32'd4) >> 2)
      : (base_addr >> 2);

  // -------------------------------
  // Write enable (FIXED BUG)
  // -------------------------------
  //assign data_we_o = we_q && (state == REQ1 || state == REQ2); // June 22 change
 assign data_we_o = we_q && data_req_o;
  // -------------------------------
  // Byte enable generation
  // -------------------------------
  always_comb begin
    data_be_o = 4'b0000;

    if (data_req_o) begin
      unique case (type_q)

        // WORD
        2'b00: begin
          if (state == REQ1)
            data_be_o = 4'b1111 << offset_q;
          else
            data_be_o = 4'b1111 >> (4 - offset_q);
        end

        // HALF
        2'b01: begin
          if (state == REQ1)
            data_be_o = 4'b0011 << offset_q;
          else
            data_be_o = 4'b0001;
        end

        // BYTE
        default: begin
          data_be_o = 4'b0001 << offset_q;
        end

      endcase
    end
  end

  // -------------------------------
  // Write data alignment   // June 22 change
  // -------------------------------
//   always_comb begin
//     case (offset_q)
//       2'b00: data_wdata_o = wdata_q;
//       2'b01: data_wdata_o = {wdata_q[23:0], wdata_q[31:24]};
//       2'b10: data_wdata_o = {wdata_q[15:0], wdata_q[31:16]};
//       2'b11: data_wdata_o = {wdata_q[7:0],  wdata_q[31:8]};
//     endcase
  //end
  always_comb begin
    data_wdata_o = 32'd0;

    if (write_req_active && (state == REQ2)) begin
      // Phase 2: Shift down the remaining upper fragments to the base byte lanes
      case (offset_q)
        2'b01: data_wdata_o = {24'b0, wdata_q[31:24]};
        2'b10: data_wdata_o = {16'b0, wdata_q[31:16]};
        2'b11: data_wdata_o = {8'b0,  wdata_q[31:8]};
        default: data_wdata_o = wdata_q;
      endcase
    end else if (write_req_active) begin
      // Phase 1 (or perfectly aligned transactions)
      case (offset_q)
        2'b00: data_wdata_o = wdata_q;
        2'b01: data_wdata_o = {wdata_q[23:0], wdata_q[31:24]};
        2'b10: data_wdata_o = {wdata_q[15:0], wdata_q[31:16]};
        2'b11: data_wdata_o = {wdata_q[7:0],  wdata_q[31:8]};
      endcase
    end
  end
  // -------------------------------
  // Load data capture
  // -------------------------------
  always_ff @(posedge clk) begin
    if (state == WAIT_RVALID1 && data_rvalid_i && misaligned_q)
      rdata_low_q <= data_rdata_i;
  end

  // -------------------------------
  // Load stitching
  // -------------------------------
  logic [31:0] merged;

  always_comb begin
    case (offset_q)
      2'b00: merged = data_rdata_iso;
      2'b01: merged = {data_rdata_iso[7:0],  rdata_low_q[31:8]};
      2'b10: merged = {data_rdata_iso[15:0], rdata_low_q[31:16]};
      2'b11: merged = {data_rdata_iso[23:0], rdata_low_q[31:24]};
    endcase
  end

  // -------------------------------
  // Final load formatting
  // -------------------------------
  logic [7:0] byte_;
  always_comb begin
    case (type_q)

      // WORD
      2'b00: begin
  if (!misaligned_q)
    rdata_o = data_rdata_iso; // aligned
  else
    rdata_o = merged;         // misaligned
end

      // HALF
      2'b01: begin
        logic [15:0] half;

        case (offset_q)
          2'b00: half = data_rdata_iso[15:0];
          2'b01: half = data_rdata_iso[23:8];
          2'b10: half = data_rdata_iso[31:16];
          2'b11: half = {data_rdata_iso[7:0], rdata_low_q[31:24]};
        endcase

        rdata_o = sign_ext_q ? {{16{half[15]}}, half} : {16'b0, half};
      end

      // BYTE
      default: begin
        

        case (offset_q)
          2'b00: byte_ = data_rdata_iso[7:0];
          2'b01: byte_ = data_rdata_iso[15:8];
          2'b10: byte_ = data_rdata_iso[23:16];
          2'b11: byte_ = data_rdata_iso[31:24];
        endcase

        rdata_o = sign_ext_q ? {{24{byte_[7]}}, byte_} : {24'b0, byte_};
      end

    endcase
  end

  // -------------------------------
  // Request generation
  // -------------------------------
  assign data_req_o =
      (state == REQ1) || (state == REQ2);

  // -------------------------------
  // Response valid
  // -------------------------------
  assign rvalid_o =
      (state == WAIT_RVALID1 && data_rvalid_i && !misaligned_q) ||
      (state == WAIT_RVALID2 && data_rvalid_i);

endmodule
