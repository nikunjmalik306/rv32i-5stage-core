// ============================================================================
// File: pipe_reg_if_id.sv
// Description: IF/ID Pipeline Register with synchronous flush and stall capabilities.
//              Flushes to RV32I NOP instruction (addi x0, x0, 0).
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module pipe_reg_if_id (
  input  logic        clk,
  input  logic        rst_n,

  // Control Signals
  input  logic        stall,
  input  logic        flush,

  // Inputs from IF Stage
  input  logic [31:0] if_pc,
  input  logic [31:0] if_pc_plus4,
  input  logic [31:0] if_inst,
  input  logic        if_pred_taken,

  // Outputs to ID Stage
  output logic [31:0] id_pc,
  output logic [31:0] id_pc_plus4,
  output logic [31:0] id_inst,
  output logic        id_pred_taken
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_pc         <= 32'h0000_0000;
      id_pc_plus4   <= 32'h0000_0000;
      id_inst       <= rv32i_types_pkg::RV32I_NOP;
      id_pred_taken <= 1'b0;
    end else if (flush) begin
      id_pc         <= 32'h0000_0000;
      id_pc_plus4   <= 32'h0000_0000;
      id_inst       <= rv32i_types_pkg::RV32I_NOP;
      id_pred_taken <= 1'b0;
    end else if (!stall) begin
      id_pc         <= if_pc;
      id_pc_plus4   <= if_pc_plus4;
      id_inst       <= if_inst;
      id_pred_taken <= if_pred_taken;
    end
  end

endmodule
