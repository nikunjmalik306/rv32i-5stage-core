// ============================================================================
// File: stage_ex.sv
// Description: Execute (EX) stage with full RV32I 32-bit ALU, forwarding muxes,
//              branch comparator, target calculation, and branch resolution logic.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module stage_ex (
  // Pipeline Inputs from ID/EX
  input  logic        ex_reg_write,
  input  logic        ex_mem_to_reg,
  input  logic        ex_mem_read,
  input  logic        ex_mem_write,
  input  logic [2:0]  ex_mem_width,
  input  logic        ex_alu_src_a,
  input  logic        ex_alu_src_b,
  input  logic [3:0]  ex_alu_op,
  input  logic [2:0]  ex_branch_type,
  input  logic        ex_is_branch,
  input  logic        ex_is_jal,
  input  logic        ex_is_jalr,
  input  logic [31:0] ex_pc,
  input  logic [31:0] ex_pc_plus4,
  input  logic        ex_pred_taken,
  input  logic [31:0] ex_rs1_data,
  input  logic [31:0] ex_rs2_data,
  input  logic [31:0] ex_imm,
  input  logic [4:0]  ex_rs1,
  input  logic [4:0]  ex_rs2,
  input  logic [4:0]  ex_rd,

  // Forwarding Inputs from Hazard Unit & Later Stages
  input  logic [1:0]  fwd_a_sel,
  input  logic [1:0]  fwd_b_sel,
  input  logic [31:0] fwd_ex_mem_data,
  input  logic [31:0] fwd_mem_wb_data,

  // Outputs to EX/MEM Pipeline Register
  output logic        ex_out_reg_write,
  output logic        ex_out_mem_to_reg,
  output logic        ex_out_mem_read,
  output logic        ex_out_mem_write,
  output logic [2:0]  ex_out_mem_width,
  output logic [31:0] ex_out_alu_result,
  output logic [31:0] ex_out_store_data,
  output logic [4:0]  ex_out_rd,

  // Control Hazard & Branch Predictor Outputs
  output logic        ex_redirect_en,
  output logic [31:0] ex_redirect_pc,
  output logic        bp_update_en,
  output logic [31:0] bp_update_pc,
  output logic [31:0] bp_update_target,
  output logic        bp_actual_taken
);

  // --------------------------------------------------------------------------
  // Forwarding Multiplexers
  // --------------------------------------------------------------------------
  logic [31:0] fwd_rs1_data;
  logic [31:0] fwd_rs2_data;

  always_comb begin
    case (fwd_a_sel)
      rv32i_types_pkg::FWD_EX_MEM: fwd_rs1_data = fwd_ex_mem_data;
      rv32i_types_pkg::FWD_MEM_WB: fwd_rs1_data = fwd_mem_wb_data;
      default:                     fwd_rs1_data = ex_rs1_data;
    endcase
  end

  always_comb begin
    case (fwd_b_sel)
      rv32i_types_pkg::FWD_EX_MEM: fwd_rs2_data = fwd_ex_mem_data;
      rv32i_types_pkg::FWD_MEM_WB: fwd_rs2_data = fwd_mem_wb_data;
      default:                     fwd_rs2_data = ex_rs2_data;
    endcase
  end

  // --------------------------------------------------------------------------
  // ALU Operand Multiplexers
  // --------------------------------------------------------------------------
  wire [31:0] alu_in_a = (ex_alu_src_a) ? ex_pc  : fwd_rs1_data;
  wire [31:0] alu_in_b = (ex_alu_src_b) ? ex_imm : fwd_rs2_data;

  // --------------------------------------------------------------------------
  // 32-bit ALU Implementation
  // --------------------------------------------------------------------------
  logic [31:0] raw_alu_result;

  always_comb begin
    case (ex_alu_op)
      rv32i_types_pkg::ALU_ADD:    raw_alu_result = alu_in_a + alu_in_b;
      rv32i_types_pkg::ALU_SUB:    raw_alu_result = alu_in_a - alu_in_b;
      rv32i_types_pkg::ALU_SLL:    raw_alu_result = alu_in_a << alu_in_b[4:0];
      rv32i_types_pkg::ALU_SLT:    raw_alu_result = ($signed(alu_in_a) < $signed(alu_in_b)) ? 32'd1 : 32'd0;
      rv32i_types_pkg::ALU_SLTU:   raw_alu_result = (alu_in_a < alu_in_b) ? 32'd1 : 32'd0;
      rv32i_types_pkg::ALU_XOR:    raw_alu_result = alu_in_a ^ alu_in_b;
      rv32i_types_pkg::ALU_SRL:    raw_alu_result = alu_in_a >> alu_in_b[4:0];
      rv32i_types_pkg::ALU_SRA:    raw_alu_result = $signed(alu_in_a) >>> alu_in_b[4:0];
      rv32i_types_pkg::ALU_OR:     raw_alu_result = alu_in_a | alu_in_b;
      rv32i_types_pkg::ALU_AND:    raw_alu_result = alu_in_a & alu_in_b;
      rv32i_types_pkg::ALU_PASS_B: raw_alu_result = alu_in_b;
      default:                     raw_alu_result = 32'h0000_0000;
    endcase
  end

  assign ex_out_alu_result = (ex_is_jal || ex_is_jalr) ? ex_pc_plus4 : raw_alu_result;
  assign ex_out_store_data = fwd_rs2_data;
  assign ex_out_rd         = ex_rd;
  assign ex_out_reg_write  = ex_reg_write;
  assign ex_out_mem_to_reg = ex_mem_to_reg;
  assign ex_out_mem_read   = ex_mem_read;
  assign ex_out_mem_write  = ex_mem_write;
  assign ex_out_mem_width  = ex_mem_width;

  // --------------------------------------------------------------------------
  // Branch Comparator Logic
  // --------------------------------------------------------------------------
  logic br_taken;

  always_comb begin
    case (ex_branch_type)
      rv32i_types_pkg::BR_BEQ:  br_taken = (fwd_rs1_data == fwd_rs2_data);
      rv32i_types_pkg::BR_BNE:  br_taken = (fwd_rs1_data != fwd_rs2_data);
      rv32i_types_pkg::BR_BLT:  br_taken = ($signed(fwd_rs1_data) < $signed(fwd_rs2_data));
      rv32i_types_pkg::BR_BGE:  br_taken = ($signed(fwd_rs1_data) >= $signed(fwd_rs2_data));
      rv32i_types_pkg::BR_BLTU: br_taken = (fwd_rs1_data < fwd_rs2_data);
      rv32i_types_pkg::BR_BGEU: br_taken = (fwd_rs1_data >= fwd_rs2_data);
      default:                  br_taken = 1'b0;
    endcase
  end

  // --------------------------------------------------------------------------
  // Branch and Jump Target Calculations
  // --------------------------------------------------------------------------
  wire [31:0] branch_target = ex_pc + ex_imm;
  wire [31:0] jal_target    = ex_pc + ex_imm;
  wire [31:0] jalr_target   = (fwd_rs1_data + ex_imm) & ~32'd1;

  wire branch_resolved_taken = ex_is_branch && br_taken;

  // --------------------------------------------------------------------------
  // Redirect & Misprediction Resolution
  // --------------------------------------------------------------------------
  always_comb begin
    ex_redirect_en = 1'b0;
    ex_redirect_pc = 32'h0000_0000;

    if (ex_is_jal) begin
      ex_redirect_en = 1'b1;
      ex_redirect_pc = jal_target;
    end else if (ex_is_jalr) begin
      ex_redirect_en = 1'b1;
      ex_redirect_pc = jalr_target;
    end else if (ex_is_branch) begin
      if (branch_resolved_taken != ex_pred_taken) begin
        ex_redirect_en = 1'b1;
        ex_redirect_pc = branch_resolved_taken ? branch_target : ex_pc_plus4;
      end
    end
  end

  assign bp_update_en     = ex_is_branch;
  assign bp_update_pc     = ex_pc;
  assign bp_update_target = branch_target;
  assign bp_actual_taken  = branch_resolved_taken;

endmodule
