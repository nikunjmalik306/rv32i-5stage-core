// ============================================================================
// File: stage_wb.sv
// Description: Writeback (WB) Stage multiplexer selecting ALU result vs Load data.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module stage_wb (
  // Inputs from MEM/WB Register
  input  logic        wb_reg_write,
  input  logic        wb_mem_to_reg,
  input  logic [31:0] wb_read_data,
  input  logic [31:0] wb_alu_result,
  input  logic [4:0]  wb_rd,

  // Writeback feedback to ID stage Register File and Hazard Unit
  output logic        wb_out_reg_write,
  output logic [4:0]  wb_out_rd,
  output logic [31:0] wb_out_data
);

  assign wb_out_reg_write = wb_reg_write;
  assign wb_out_rd        = wb_rd;
  assign wb_out_data      = (wb_mem_to_reg) ? wb_read_data : wb_alu_result;

endmodule
