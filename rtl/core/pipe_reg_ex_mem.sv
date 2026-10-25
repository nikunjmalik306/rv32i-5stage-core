// ============================================================================
// File: pipe_reg_ex_mem.sv
// Description: EX/MEM Pipeline Register with synchronous stall and flush controls.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module pipe_reg_ex_mem (
  input  logic        clk,
  input  logic        rst_n,

  // Control
  input  logic        stall,
  input  logic        flush,

  // Inputs from EX Stage
  input  logic        ex_reg_write,
  input  logic        ex_mem_to_reg,
  input  logic        ex_mem_read,
  input  logic        ex_mem_write,
  input  logic [2:0]  ex_mem_width,
  input  logic [31:0] ex_alu_result,
  input  logic [31:0] ex_store_data,
  input  logic [4:0]  ex_rd,

  // Outputs to MEM Stage
  output logic        mem_reg_write,
  output logic        mem_mem_to_reg,
  output logic        mem_mem_read,
  output logic        mem_mem_write,
  output logic [2:0]  mem_mem_width,
  output logic [31:0] mem_alu_result,
  output logic [31:0] mem_store_data,
  output logic [4:0]  mem_rd
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_reg_write  <= 1'b0;
      mem_mem_to_reg <= 1'b0;
      mem_mem_read   <= 1'b0;
      mem_mem_write  <= 1'b0;
      mem_mem_width  <= 3'b000;
      mem_alu_result <= 32'h0000_0000;
      mem_store_data <= 32'h0000_0000;
      mem_rd         <= 5'd0;
    end else if (flush) begin
      mem_reg_write  <= 1'b0;
      mem_mem_to_reg <= 1'b0;
      mem_mem_read   <= 1'b0;
      mem_mem_write  <= 1'b0;
      mem_mem_width  <= 3'b000;
      mem_alu_result <= 32'h0000_0000;
      mem_store_data <= 32'h0000_0000;
      mem_rd         <= 5'd0;
    end else if (!stall) begin
      mem_reg_write  <= ex_reg_write;
      mem_mem_to_reg <= ex_mem_to_reg;
      mem_mem_read   <= ex_mem_read;
      mem_mem_write  <= ex_mem_write;
      mem_mem_width  <= ex_mem_width;
      mem_alu_result <= ex_alu_result;
      mem_store_data <= ex_store_data;
      mem_rd         <= ex_rd;
    end
  end

endmodule
