// ============================================================================
// File: pipe_reg_mem_wb.sv
// Description: MEM/WB Pipeline Register holding writeback control and data signals.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module pipe_reg_mem_wb (
  input  logic        clk,
  input  logic        rst_n,

  // Control
  input  logic        stall,
  input  logic        flush,

  // Inputs from MEM Stage
  input  logic        mem_reg_write,
  input  logic        mem_mem_to_reg,
  input  logic [31:0] mem_read_data,
  input  logic [31:0] mem_alu_result,
  input  logic [4:0]  mem_rd,

  // Outputs to WB Stage
  output logic        wb_reg_write,
  output logic        wb_mem_to_reg,
  output logic [31:0] wb_read_data,
  output logic [31:0] wb_alu_result,
  output logic [4:0]  wb_rd
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_reg_write  <= 1'b0;
      wb_mem_to_reg <= 1'b0;
      wb_read_data  <= 32'h0000_0000;
      wb_alu_result <= 32'h0000_0000;
      wb_rd         <= 5'd0;
    end else if (flush) begin
      wb_reg_write  <= 1'b0;
      wb_mem_to_reg <= 1'b0;
      wb_read_data  <= 32'h0000_0000;
      wb_alu_result <= 32'h0000_0000;
      wb_rd         <= 5'd0;
    end else if (!stall) begin
      wb_reg_write  <= mem_reg_write;
      wb_mem_to_reg <= mem_mem_to_reg;
      wb_read_data  <= mem_read_data;
      wb_alu_result <= mem_alu_result;
      wb_rd         <= mem_rd;
    end
  end

endmodule
