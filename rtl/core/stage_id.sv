// ============================================================================
// File: stage_id.sv
// Description: Instruction Decode (ID) stage incorporating Register File,
//              Immediate Generator, and RV32I Control Unit decoder.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module stage_id (
  input  logic        clk,
  input  logic        rst_n,

  // Inputs from IF/ID
  input  logic [31:0] id_pc,
  input  logic [31:0] id_pc_plus4,
  input  logic [31:0] id_inst,
  input  logic        id_pred_taken,

  // Writeback Interface from WB Stage
  input  logic        wb_reg_write,
  input  logic [4:0]  wb_rd,
  input  logic [31:0] wb_data,

  // Decoded Instruction Fields
  output logic [4:0]  id_rs1,
  output logic [4:0]  id_rs2,
  output logic [4:0]  id_rd,
  output logic [31:0] id_rs1_data,
  output logic [31:0] id_rs2_data,
  output logic [31:0] id_imm,

  // Propagated PC
  output logic [31:0] id_out_pc,
  output logic [31:0] id_out_pc_plus4,
  output logic        id_out_pred_taken,

  // Control Signals to ID/EX
  output logic        id_reg_write,
  output logic        id_mem_to_reg,
  output logic        id_mem_read,
  output logic        id_mem_write,
  output logic [2:0]  id_mem_width,
  output logic        id_alu_src_a,      // 0: rs1, 1: PC
  output logic        id_alu_src_b,      // 0: rs2, 1: imm
  output logic [3:0]  id_alu_op,
  output logic [2:0]  id_branch_type,
  output logic        id_is_branch,
  output logic        id_is_jal,
  output logic        id_is_jalr
);

  // --------------------------------------------------------------------------
  // Instruction Field Extraction
  // --------------------------------------------------------------------------
  wire [6:0] opcode = id_inst[6:0];
  wire [4:0] rd     = id_inst[11:7];
  wire [2:0] funct3 = id_inst[14:12];
  wire [4:0] rs1    = id_inst[19:15];
  wire [4:0] rs2    = id_inst[24:20];
  wire [6:0] funct7 = id_inst[31:25];

  assign id_rs1 = rs1;
  assign id_rs2 = rs2;
  assign id_rd  = rd;

  assign id_out_pc         = id_pc;
  assign id_out_pc_plus4   = id_pc_plus4;
  assign id_out_pred_taken = id_pred_taken;

  // --------------------------------------------------------------------------
  // 32-entry x 32-bit Register File with Internal Forwarding (Bypass)
  // --------------------------------------------------------------------------
  logic [31:0] regfile [0:31];

  always_comb begin
    if (rs1 == 5'd0) begin
      id_rs1_data = 32'h0000_0000;
    end else if (wb_reg_write && (wb_rd == rs1)) begin
      id_rs1_data = wb_data; // Internal bypass
    end else begin
      id_rs1_data = regfile[rs1];
    end
  end

  always_comb begin
    if (rs2 == 5'd0) begin
      id_rs2_data = 32'h0000_0000;
    end else if (wb_reg_write && (wb_rd == rs2)) begin
      id_rs2_data = wb_data; // Internal bypass
    end else begin
      id_rs2_data = regfile[rs2];
    end
  end

  integer r;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (r = 0; r < 32; r = r + 1) begin
        regfile[r] <= 32'h0000_0000;
      end
    end else if (wb_reg_write && (wb_rd != 5'd0)) begin
      regfile[wb_rd] <= wb_data;
    end
  end

  // --------------------------------------------------------------------------
  // Immediate Generator
  // --------------------------------------------------------------------------
  wire [31:0] imm_i = {{20{id_inst[31]}}, id_inst[31:20]};
  wire [31:0] imm_s = {{20{id_inst[31]}}, id_inst[31:25], id_inst[11:7]};
  wire [31:0] imm_b = {{19{id_inst[31]}}, id_inst[31], id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
  wire [31:0] imm_u = {id_inst[31:12], 12'b0};
  wire [31:0] imm_j = {{11{id_inst[31]}}, id_inst[31], id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};

  always_comb begin
    case (opcode)
      rv32i_types_pkg::OPCODE_I,
      rv32i_types_pkg::OPCODE_LOAD,
      rv32i_types_pkg::OPCODE_JALR:   id_imm = imm_i;
      rv32i_types_pkg::OPCODE_STORE:  id_imm = imm_s;
      rv32i_types_pkg::OPCODE_BRANCH: id_imm = imm_b;
      rv32i_types_pkg::OPCODE_LUI,
      rv32i_types_pkg::OPCODE_AUIPC:  id_imm = imm_u;
      rv32i_types_pkg::OPCODE_JAL:    id_imm = imm_j;
      default:                        id_imm = 32'h0000_0000;
    endcase
  end

  // --------------------------------------------------------------------------
  // Control Unit Decoder
  // --------------------------------------------------------------------------
  assign id_mem_width   = funct3;
  assign id_branch_type = funct3;

  always_comb begin
    id_reg_write  = 1'b0;
    id_mem_to_reg = 1'b0;
    id_mem_read   = 1'b0;
    id_mem_write  = 1'b0;
    id_alu_src_a  = 1'b0; // rs1
    id_alu_src_b  = 1'b0; // rs2
    id_alu_op     = rv32i_types_pkg::ALU_ADD;
    id_is_branch  = 1'b0;
    id_is_jal     = 1'b0;
    id_is_jalr    = 1'b0;

    case (opcode)
      rv32i_types_pkg::OPCODE_R: begin
        id_reg_write = 1'b1;
        id_alu_src_a = 1'b0;
        id_alu_src_b = 1'b0;
        case (funct3)
          3'b000: id_alu_op = (funct7[5]) ? rv32i_types_pkg::ALU_SUB : rv32i_types_pkg::ALU_ADD;
          3'b001: id_alu_op = rv32i_types_pkg::ALU_SLL;
          3'b010: id_alu_op = rv32i_types_pkg::ALU_SLT;
          3'b011: id_alu_op = rv32i_types_pkg::ALU_SLTU;
          3'b100: id_alu_op = rv32i_types_pkg::ALU_XOR;
          3'b101: id_alu_op = (funct7[5]) ? rv32i_types_pkg::ALU_SRA : rv32i_types_pkg::ALU_SRL;
          3'b110: id_alu_op = rv32i_types_pkg::ALU_OR;
          3'b111: id_alu_op = rv32i_types_pkg::ALU_AND;
          default: id_alu_op = rv32i_types_pkg::ALU_ADD;
        endcase
      end

      rv32i_types_pkg::OPCODE_I: begin
        id_reg_write = 1'b1;
        id_alu_src_a = 1'b0;
        id_alu_src_b = 1'b1;
        case (funct3)
          3'b000: id_alu_op = rv32i_types_pkg::ALU_ADD;
          3'b001: id_alu_op = rv32i_types_pkg::ALU_SLL;
          3'b010: id_alu_op = rv32i_types_pkg::ALU_SLT;
          3'b011: id_alu_op = rv32i_types_pkg::ALU_SLTU;
          3'b100: id_alu_op = rv32i_types_pkg::ALU_XOR;
          3'b101: id_alu_op = (funct7[5]) ? rv32i_types_pkg::ALU_SRA : rv32i_types_pkg::ALU_SRL;
          3'b110: id_alu_op = rv32i_types_pkg::ALU_OR;
          3'b111: id_alu_op = rv32i_types_pkg::ALU_AND;
          default: id_alu_op = rv32i_types_pkg::ALU_ADD;
        endcase
      end

      rv32i_types_pkg::OPCODE_LOAD: begin
        id_reg_write  = 1'b1;
        id_mem_to_reg = 1'b1;
        id_mem_read   = 1'b1;
        id_alu_src_a  = 1'b0;
        id_alu_src_b  = 1'b1;
        id_alu_op     = rv32i_types_pkg::ALU_ADD;
      end

      rv32i_types_pkg::OPCODE_STORE: begin
        id_mem_write = 1'b1;
        id_alu_src_a = 1'b0;
        id_alu_src_b = 1'b1;
        id_alu_op    = rv32i_types_pkg::ALU_ADD;
      end

      rv32i_types_pkg::OPCODE_BRANCH: begin
        id_is_branch = 1'b1;
        id_alu_src_a = 1'b0;
        id_alu_src_b = 1'b0;
        id_alu_op    = rv32i_types_pkg::ALU_SUB;
      end

      rv32i_types_pkg::OPCODE_LUI: begin
        id_reg_write = 1'b1;
        id_alu_src_a = 1'b0;
        id_alu_src_b = 1'b1;
        id_alu_op    = rv32i_types_pkg::ALU_PASS_B;
      end

      rv32i_types_pkg::OPCODE_AUIPC: begin
        id_reg_write = 1'b1;
        id_alu_src_a = 1'b1;
        id_alu_src_b = 1'b1;
        id_alu_op    = rv32i_types_pkg::ALU_ADD;
      end

      rv32i_types_pkg::OPCODE_JAL: begin
        id_reg_write = 1'b1;
        id_is_jal    = 1'b1;
        id_alu_src_a = 1'b1;
        id_alu_src_b = 1'b1;
        id_alu_op    = rv32i_types_pkg::ALU_ADD;
      end

      rv32i_types_pkg::OPCODE_JALR: begin
        id_reg_write = 1'b1;
        id_is_jalr   = 1'b1;
        id_alu_src_a = 1'b0;
        id_alu_src_b = 1'b1;
        id_alu_op    = rv32i_types_pkg::ALU_ADD;
      end

      default: begin
        id_reg_write  = 1'b0;
        id_mem_to_reg = 1'b0;
        id_mem_read   = 1'b0;
        id_mem_write  = 1'b0;
        id_alu_src_a  = 1'b0;
        id_alu_src_b  = 1'b0;
        id_alu_op     = rv32i_types_pkg::ALU_ADD;
      end
    endcase
  end

endmodule
