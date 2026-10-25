// ============================================================================
// File: l1_dcache.sv
// Description: 4KB 2-Way Set-Associative Write-Back, Write-Allocate L1 Data Cache
//              with pseudo-LRU replacement and AXI4-Lite burst refill/evict FSM.
//
// Cache Geometry:
//   - Total Capacity: 4096 Bytes (4 KB)
//   - Line Size:      32 Bytes (8 words x 32 bits = 256 bits)
//   - Associativity:  2 Ways
//   - Number of Sets: 64 Sets (4096 / (2 * 32))
//   - Addressing:     Offset = [4:0], Set = [10:5], Tag = [31:11]
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module l1_dcache (
  input  logic        clk,
  input  logic        rst_n,

  // CPU Core Memory Stage Interface
  input  logic        cpu_req,        // Memory access requested
  input  logic        cpu_we,         // 1 = Write, 0 = Read
  input  logic [31:0] cpu_addr,       // Byte address
  input  logic [31:0] cpu_wdata,      // Store data
  input  logic [3:0]  cpu_wstrb,      // Byte write strobes
  output logic [31:0] cpu_rdata,      // Read data output
  output logic        cpu_stall,      // Pipeline stall while handling miss

  // AXI4-Lite Master Bridge Interface
  output logic        axi_cmd_valid,
  output logic        axi_cmd_write,
  output logic [31:0] axi_cmd_addr,
  output logic [31:0] axi_cmd_wdata,
  output logic [3:0]  axi_cmd_wstrb,
  input  logic        axi_cmd_ready,
  input  logic        axi_rsp_valid,
  input  logic [31:0] axi_rsp_rdata,
  input  logic        axi_rsp_error
);

  // --------------------------------------------------------------------------
  // Address Partitioning
  // --------------------------------------------------------------------------
  wire [4:0]  offset   = cpu_addr[4:0];
  wire [2:0]  word_idx = offset[4:2];
  wire [5:0]  set_idx  = cpu_addr[10:5];
  wire [20:0] tag      = cpu_addr[31:11];

  // --------------------------------------------------------------------------
  // Cache Storage Arrays
  // --------------------------------------------------------------------------
  logic [20:0] tag_array   [0:1][0:63];
  logic        valid_array [0:1][0:63];
  logic        dirty_array [0:1][0:63];
  logic        lru_array   [0:63];
  logic [31:0] data_array  [0:1][0:63][0:7];

  // --------------------------------------------------------------------------
  // Hit Detection Logic
  // --------------------------------------------------------------------------
  wire hit_way0 = valid_array[0][set_idx] && (tag_array[0][set_idx] == tag);
  wire hit_way1 = valid_array[1][set_idx] && (tag_array[1][set_idx] == tag);
  wire cache_hit = hit_way0 | hit_way1;
  wire hit_way   = hit_way1;

  logic [31:0] hit_rdata;
  always_comb begin
    if (hit_way1)
      hit_rdata = data_array[1][set_idx][word_idx];
    else
      hit_rdata = data_array[0][set_idx][word_idx];
  end

  // --------------------------------------------------------------------------
  // Cache Controller FSM States
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE        = 3'b000,
    S_CHECK       = 3'b001,
    S_EVICT       = 3'b010,
    S_REFILL      = 3'b011,
    S_UPDATE      = 3'b100,
    S_RESP        = 3'b101
  } cache_state_e;

  cache_state_e state, next_state;

  logic [31:0] reg_addr;
  logic [31:0] reg_wdata;
  logic [3:0]  reg_wstrb;
  logic        reg_we;
  logic [2:0]  burst_cnt;
  logic        victim_way;

  wire [4:0]  reg_offset   = reg_addr[4:0];
  wire [2:0]  reg_word_idx = reg_offset[4:2];
  wire [5:0]  reg_set_idx  = reg_addr[10:5];
  wire [20:0] reg_tag      = reg_addr[31:11];

  // --------------------------------------------------------------------------
  // Synchronous State Machine & Cache Array Modifications
  // --------------------------------------------------------------------------
  integer s;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= S_IDLE;
      reg_addr    <= 32'h0;
      reg_wdata   <= 32'h0;
      reg_wstrb   <= 4'h0;
      reg_we      <= 1'b0;
      burst_cnt   <= 3'd0;
      victim_way  <= 1'b0;

      for (s = 0; s < 64; s = s + 1) begin
        valid_array[0][s] <= 1'b0;
        valid_array[1][s] <= 1'b0;
        dirty_array[0][s] <= 1'b0;
        dirty_array[1][s] <= 1'b0;
        tag_array[0][s]   <= 21'h0;
        tag_array[1][s]   <= 21'h0;
        lru_array[s]      <= 1'b0;
      end
    end else begin
      state <= next_state;

      case (state)
        S_IDLE: begin
          burst_cnt <= 3'd0;
          if (cpu_req) begin
            if (cache_hit) begin
              if (cpu_we) begin
                if (cpu_wstrb[0]) data_array[hit_way][set_idx][word_idx][7:0]   <= cpu_wdata[7:0];
                if (cpu_wstrb[1]) data_array[hit_way][set_idx][word_idx][15:8]  <= cpu_wdata[15:8];
                if (cpu_wstrb[2]) data_array[hit_way][set_idx][word_idx][23:16] <= cpu_wdata[23:16];
                if (cpu_wstrb[3]) data_array[hit_way][set_idx][word_idx][31:24] <= cpu_wdata[31:24];
                dirty_array[hit_way][set_idx] <= 1'b1;
              end
              lru_array[set_idx] <= ~hit_way;
            end else begin
              reg_addr   <= cpu_addr;
              reg_wdata  <= cpu_wdata;
              reg_wstrb  <= cpu_wstrb;
              reg_we     <= cpu_we;
              victim_way <= lru_array[set_idx];
            end
          end
        end

        S_CHECK: begin
          burst_cnt <= 3'd0;
        end

        S_EVICT: begin
          if (axi_rsp_valid) begin
            if (burst_cnt == 3'd7) begin
              burst_cnt <= 3'd0;
            end else begin
              burst_cnt <= burst_cnt + 3'd1;
            end
          end
        end

        S_REFILL: begin
          if (axi_rsp_valid) begin
            data_array[victim_way][reg_set_idx][burst_cnt] <= axi_rsp_rdata;
            if (burst_cnt == 3'd7) begin
              burst_cnt <= 3'd0;
            end else begin
              burst_cnt <= burst_cnt + 3'd1;
            end
          end
        end

        S_UPDATE: begin
          tag_array[victim_way][reg_set_idx]   <= reg_tag;
          valid_array[victim_way][reg_set_idx] <= 1'b1;

          if (reg_we) begin
            if (reg_wstrb[0]) data_array[victim_way][reg_set_idx][reg_word_idx][7:0]   <= reg_wdata[7:0];
            if (reg_wstrb[1]) data_array[victim_way][reg_set_idx][reg_word_idx][15:8]  <= reg_wdata[15:8];
            if (reg_wstrb[2]) data_array[victim_way][reg_set_idx][reg_word_idx][23:16] <= reg_wdata[23:16];
            if (reg_wstrb[3]) data_array[victim_way][reg_set_idx][reg_word_idx][31:24] <= reg_wdata[31:24];
            dirty_array[victim_way][reg_set_idx] <= 1'b1;
          end else begin
            dirty_array[victim_way][reg_set_idx] <= 1'b0;
          end

          lru_array[reg_set_idx] <= ~victim_way;
        end

        S_RESP: begin
        end

        default: begin
          state <= S_IDLE;
        end
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Next-State Combinational Logic
  // --------------------------------------------------------------------------
  always_comb begin
    next_state = state;

    case (state)
      S_IDLE: begin
        if (cpu_req && !cache_hit) begin
          next_state = S_CHECK;
        end
      end

      S_CHECK: begin
        if (valid_array[victim_way][reg_set_idx] && dirty_array[victim_way][reg_set_idx]) begin
          next_state = S_EVICT;
        end else begin
          next_state = S_REFILL;
        end
      end

      S_EVICT: begin
        if (axi_rsp_valid && (burst_cnt == 3'd7)) begin
          next_state = S_REFILL;
        end
      end

      S_REFILL: begin
        if (axi_rsp_valid && (burst_cnt == 3'd7)) begin
          next_state = S_UPDATE;
        end
      end

      S_UPDATE: begin
        next_state = S_RESP;
      end

      S_RESP: begin
        next_state = S_IDLE;
      end

      default: next_state = S_IDLE;
    endcase
  end

  // --------------------------------------------------------------------------
  // AXI Master Command Dispatch Logic
  // --------------------------------------------------------------------------
  wire [31:0] evict_base_addr = {tag_array[victim_way][reg_set_idx], reg_set_idx, 5'b00000};
  wire [31:0] refill_base_addr = {reg_tag, reg_set_idx, 5'b00000};

  always_comb begin
    axi_cmd_valid = 1'b0;
    axi_cmd_write = 1'b0;
    axi_cmd_addr  = 32'h0;
    axi_cmd_wdata = 32'h0;
    axi_cmd_wstrb = 4'h0;

    case (state)
      S_EVICT: begin
        axi_cmd_valid = 1'b1;
        axi_cmd_write = 1'b1;
        axi_cmd_addr  = evict_base_addr | {24'h0, burst_cnt, 2'b00};
        axi_cmd_wdata = data_array[victim_way][reg_set_idx][burst_cnt];
        axi_cmd_wstrb = 4'hF;
      end

      S_REFILL: begin
        axi_cmd_valid = 1'b1;
        axi_cmd_write = 1'b0;
        axi_cmd_addr  = refill_base_addr | {24'h0, burst_cnt, 2'b00};
        axi_cmd_wdata = 32'h0;
        axi_cmd_wstrb = 4'h0;
      end

      default: ;
    endcase
  end

  // --------------------------------------------------------------------------
  // CPU Output Interface
  // --------------------------------------------------------------------------
  assign cpu_stall = (state != S_IDLE) || (cpu_req && !cache_hit);

  always_comb begin
    if (state == S_RESP || state == S_UPDATE) begin
      cpu_rdata = data_array[victim_way][reg_set_idx][reg_word_idx];
    end else begin
      cpu_rdata = hit_rdata;
    end
  end

endmodule
