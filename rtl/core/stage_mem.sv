// ============================================================================
// File: stage_mem.sv
// Description: Memory (MEM) Stage with alignment, byte masking for stores,
//              sign/zero extension for loads, and L1 D-Cache interface.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module stage_mem (
  // Pipeline Inputs from EX/MEM
  input  logic        mem_reg_write,
  input  logic        mem_mem_to_reg,
  input  logic        mem_mem_read,
  input  logic        mem_mem_write,
  input  logic [2:0]  mem_mem_width,
  input  logic [31:0] mem_alu_result,
  input  logic [31:0] mem_store_data,
  input  logic [4:0]  mem_rd,

  // Interface to L1 D-Cache
  output logic        dcache_req,
  output logic        dcache_we,
  output logic [31:0] dcache_addr,
  output logic [31:0] dcache_wdata,
  output logic [3:0]  dcache_wstrb,
  input  logic [31:0] dcache_rdata,

  // Outputs to MEM/WB Pipeline Register
  output logic        mem_out_reg_write,
  output logic        mem_out_mem_to_reg,
  output logic [31:0] mem_out_read_data,
  output logic [31:0] mem_out_alu_result,
  output logic [4:0]  mem_out_rd
);

  wire [1:0] byte_offset = mem_alu_result[1:0];

  // --------------------------------------------------------------------------
  // D-Cache Request and Store Alignment Logic
  // --------------------------------------------------------------------------
  assign dcache_req  = mem_mem_read | mem_mem_write;
  assign dcache_we   = mem_mem_write;
  assign dcache_addr = mem_alu_result;

  always_comb begin
    dcache_wstrb = 4'b0000;
    dcache_wdata = 32'h0000_0000;

    if (mem_mem_write) begin
      case (mem_mem_width)
        rv32i_types_pkg::MEM_BYTE: begin
          case (byte_offset)
            2'b00: begin dcache_wstrb = 4'b0001; dcache_wdata = {24'h0, mem_store_data[7:0]}; end
            2'b01: begin dcache_wstrb = 4'b0010; dcache_wdata = {16'h0, mem_store_data[7:0], 8'h0}; end
            2'b10: begin dcache_wstrb = 4'b0100; dcache_wdata = {8'h0,  mem_store_data[7:0], 16'h0}; end
            2'b11: begin dcache_wstrb = 4'b1000; dcache_wdata = {mem_store_data[7:0], 24'h0}; end
          endcase
        end

        rv32i_types_pkg::MEM_HALF: begin
          case (byte_offset[1])
            1'b0:  begin dcache_wstrb = 4'b0011; dcache_wdata = {16'h0, mem_store_data[15:0]}; end
            1'b1:  begin dcache_wstrb = 4'b1100; dcache_wdata = {mem_store_data[15:0], 16'h0}; end
          endcase
        end

        rv32i_types_pkg::MEM_WORD: begin
          dcache_wstrb = 4'b1111;
          dcache_wdata = mem_store_data;
        end

        default: begin
          dcache_wstrb = 4'b1111;
          dcache_wdata = mem_store_data;
        end
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Load Alignment and Sign / Zero Extension Logic
  // --------------------------------------------------------------------------
  logic [31:0] formatted_load_data;

  always_comb begin
    case (mem_mem_width)
      rv32i_types_pkg::MEM_BYTE: begin
        case (byte_offset)
          2'b00: formatted_load_data = {{24{dcache_rdata[7]}},  dcache_rdata[7:0]};
          2'b01: formatted_load_data = {{24{dcache_rdata[15]}}, dcache_rdata[15:8]};
          2'b10: formatted_load_data = {{24{dcache_rdata[23]}}, dcache_rdata[23:16]};
          2'b11: formatted_load_data = {{24{dcache_rdata[31]}}, dcache_rdata[31:24]};
        endcase
      end

      rv32i_types_pkg::MEM_BYTE_U: begin
        case (byte_offset)
          2'b00: formatted_load_data = {24'h000000, dcache_rdata[7:0]};
          2'b01: formatted_load_data = {24'h000000, dcache_rdata[15:8]};
          2'b10: formatted_load_data = {24'h000000, dcache_rdata[23:16]};
          2'b11: formatted_load_data = {24'h000000, dcache_rdata[31:24]};
        endcase
      end

      rv32i_types_pkg::MEM_HALF: begin
        case (byte_offset[1])
          1'b0:  formatted_load_data = {{16{dcache_rdata[15]}}, dcache_rdata[15:0]};
          1'b1:  formatted_load_data = {{16{dcache_rdata[31]}}, dcache_rdata[31:16]};
        endcase
      end

      rv32i_types_pkg::MEM_HALF_U: begin
        case (byte_offset[1])
          1'b0:  formatted_load_data = {16'h0000, dcache_rdata[15:0]};
          1'b1:  formatted_load_data = {16'h0000, dcache_rdata[31:16]};
        endcase
      end

      rv32i_types_pkg::MEM_WORD: begin
        formatted_load_data = dcache_rdata;
      end

      default: formatted_load_data = dcache_rdata;
    endcase
  end

  // Outputs
  assign mem_out_reg_write  = mem_reg_write;
  assign mem_out_mem_to_reg = mem_mem_to_reg;
  assign mem_out_read_data  = formatted_load_data;
  assign mem_out_alu_result = mem_alu_result;
  assign mem_out_rd         = mem_rd;

endmodule
