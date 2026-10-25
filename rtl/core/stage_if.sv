// ============================================================================
// File: stage_if.sv
// Description: Instruction Fetch (IF) stage with Program Counter management,
//              branch predictor integration, and instruction memory interfacing.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module stage_if #(
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000
)(
  input  logic        clk,
  input  logic        rst_n,

  // Stall & Redirect Controls
  input  logic        stall_pc,
  input  logic        trap_redirect_en,
  input  logic [31:0] trap_redirect_pc,
  input  logic        ex_redirect_en,
  input  logic [31:0] ex_redirect_pc,

  // Branch Predictor Signals
  input  logic        bp_pred_taken,
  input  logic [31:0] bp_pred_target,

  // Instruction Memory Interface
  output logic [31:0] imem_addr,
  output logic        imem_ren,
  input  logic [31:0] imem_rdata,

  // IF Stage Outputs to IF/ID Pipeline Register
  output logic [31:0] if_pc,
  output logic [31:0] if_pc_plus4,
  output logic [31:0] if_inst,
  output logic        if_pred_taken
);

  // --------------------------------------------------------------------------
  // Program Counter Logic
  // --------------------------------------------------------------------------
  logic [31:0] pc_reg;
  logic [31:0] next_pc;

  assign if_pc_plus4 = pc_reg + 32'd4;

  always_comb begin
    if (trap_redirect_en) begin
      next_pc = trap_redirect_pc;
    end else if (ex_redirect_en) begin
      next_pc = ex_redirect_pc;
    end else if (bp_pred_taken) begin
      next_pc = bp_pred_target;
    end else begin
      next_pc = if_pc_plus4;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_reg <= RESET_VECTOR;
    end else if (!stall_pc) begin
      pc_reg <= next_pc;
    end
  end

  assign imem_addr     = pc_reg;
  assign imem_ren      = 1'b1;
  assign if_pc         = pc_reg;
  assign if_inst       = imem_rdata;
  assign if_pred_taken = bp_pred_taken;

endmodule
