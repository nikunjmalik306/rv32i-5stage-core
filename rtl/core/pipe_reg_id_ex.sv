// ============================================================================
// File: pipe_reg_id_ex.sv
// Description: ID/EX Pipeline Register with synchronous flush (NOP bubble injection)
//              and stall capabilities.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module pipe_reg_id_ex (
  input  logic        clk,
  input  logic        rst_n,

  // Control
  input  logic        stall,
  input  logic        flush,

  // Inputs from ID Stage
  input  logic        id_reg_write,
  input  logic        id_mem_to_reg,
  input  logic        id_mem_read,
  input  logic        id_mem_write,
  input  logic [2:0]  id_mem_width,
  input  logic        id_alu_src_a,
  input  logic        id_alu_src_b,
  input  logic [3:0]  id_alu_op,
  input  logic [2:0]  id_branch_type,
  input  logic        id_is_branch,
  input  logic        id_is_jal,
  input  logic        id_is_jalr,
  input  logic [31:0] id_pc,
  input  logic [31:0] id_pc_plus4,
  input  logic        id_pred_taken,
  input  logic [31:0] id_rs1_data,
  input  logic [31:0] id_rs2_data,
  input  logic [31:0] id_imm,
  input  logic [4:0]  id_rs1,
  input  logic [4:0]  id_rs2,
  input  logic [4:0]  id_rd,

  // Outputs to EX Stage
  output logic        ex_reg_write,
  output logic        ex_mem_to_reg,
  output logic        ex_mem_read,
  output logic        ex_mem_write,
  output logic [2:0]  ex_mem_width,
  output logic        ex_alu_src_a,
  output logic        ex_alu_src_b,
  output logic [3:0]  ex_alu_op,
  output logic [2:0]  ex_branch_type,
  output logic        ex_is_branch,
  output logic        ex_is_jal,
  output logic        ex_is_jalr,
  output logic [31:0] ex_pc,
  output logic [31:0] ex_pc_plus4,
  output logic        ex_pred_taken,
  output logic [31:0] ex_rs1_data,
  output logic [31:0] ex_rs2_data,
  output logic [31:0] ex_imm,
  output logic [4:0]  ex_rs1,
  output logic [4:0]  ex_rs2,
  output logic [4:0]  ex_rd
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_reg_write   <= 1'b0;
      ex_mem_to_reg  <= 1'b0;
      ex_mem_read    <= 1'b0;
      ex_mem_write   <= 1'b0;
      ex_mem_width   <= 3'b000;
      ex_alu_src_a   <= 1'b0;
      ex_alu_src_b   <= 1'b0;
      ex_alu_op      <= rv32i_types_pkg::ALU_ADD;
      ex_branch_type <= rv32i_types_pkg::BR_BEQ;
      ex_is_branch   <= 1'b0;
      ex_is_jal      <= 1'b0;
      ex_is_jalr     <= 1'b0;
      ex_pc          <= 32'h0000_0000;
      ex_pc_plus4    <= 32'h0000_0000;
      ex_pred_taken  <= 1'b0;
      ex_rs1_data    <= 32'h0000_0000;
      ex_rs2_data    <= 32'h0000_0000;
      ex_imm         <= 32'h0000_0000;
      ex_rs1         <= 5'd0;
      ex_rs2         <= 5'd0;
      ex_rd          <= 5'd0;
    end else if (flush) begin
      ex_reg_write   <= 1'b0;
      ex_mem_to_reg  <= 1'b0;
      ex_mem_read    <= 1'b0;
      ex_mem_write   <= 1'b0;
      ex_mem_width   <= 3'b000;
      ex_alu_src_a   <= 1'b0;
      ex_alu_src_b   <= 1'b0;
      ex_alu_op      <= rv32i_types_pkg::ALU_ADD;
      ex_branch_type <= rv32i_types_pkg::BR_BEQ;
      ex_is_branch   <= 1'b0;
      ex_is_jal      <= 1'b0;
      ex_is_jalr     <= 1'b0;
      ex_pc          <= 32'h0000_0000;
      ex_pc_plus4    <= 32'h0000_0000;
      ex_pred_taken  <= 1'b0;
      ex_rs1_data    <= 32'h0000_0000;
      ex_rs2_data    <= 32'h0000_0000;
      ex_imm         <= 32'h0000_0000;
      ex_rs1         <= 5'd0;
      ex_rs2         <= 5'd0;
      ex_rd          <= 5'd0;
    end else if (!stall) begin
      ex_reg_write   <= id_reg_write;
      ex_mem_to_reg  <= id_mem_to_reg;
      ex_mem_read    <= id_mem_read;
      ex_mem_write   <= id_mem_write;
      ex_mem_width   <= id_mem_width;
      ex_alu_src_a   <= id_alu_src_a;
      ex_alu_src_b   <= id_alu_src_b;
      ex_alu_op      <= id_alu_op;
      ex_branch_type <= id_branch_type;
      ex_is_branch   <= id_is_branch;
      ex_is_jal      <= id_is_jal;
      ex_is_jalr     <= id_is_jalr;
      ex_pc          <= id_pc;
      ex_pc_plus4    <= id_pc_plus4;
      ex_pred_taken  <= id_pred_taken;
      ex_rs1_data    <= id_rs1_data;
      ex_rs2_data    <= id_rs2_data;
      ex_imm         <= id_imm;
      ex_rs1         <= id_rs1;
      ex_rs2         <= id_rs2;
      ex_rd          <= id_rd;
    end
  end

endmodule
