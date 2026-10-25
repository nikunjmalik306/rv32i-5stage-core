// ============================================================================
// File: hazard_unit.sv
// Description: Comprehensive Hazard Management Unit incorporating:
//              1. Data forwarding unit (EX->EX, MEM->EX)
//              2. Load-Use hazard stall detector (stalls IF/ID, bubbles EX)
//              3. Control hazard flush unit (flushes IF/ID, ID/EX on mispredict/jump)
//              4. Structural cache stall arbitration
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module hazard_unit (
  // Forwarding Inputs
  input  logic [4:0]  id_ex_rs1,
  input  logic [4:0]  id_ex_rs2,
  input  logic [4:0]  ex_mem_rd,
  input  logic        ex_mem_reg_write,
  input  logic [4:0]  mem_wb_rd,
  input  logic        mem_wb_reg_write,

  // Load-Use Detection Inputs
  input  logic        id_ex_mem_read,
  input  logic [4:0]  id_ex_rd,
  input  logic [4:0]  if_id_rs1,
  input  logic [4:0]  if_id_rs2,

  // Control Hazard Inputs
  input  logic        ex_redirect_en,
  input  logic        trap_taken,

  // Memory/Cache Stall Inputs
  input  logic        dcache_stall,

  // Forwarding Outputs to EX Stage
  output logic [1:0]  fwd_a_sel,
  output logic [1:0]  fwd_b_sel,

  // Pipeline Stall and Flush Outputs
  output logic        stall_if,
  output logic        stall_id,
  output logic        stall_ex,
  output logic        stall_mem,
  output logic        stall_wb,

  output logic        flush_if_id,
  output logic        flush_id_ex,
  output logic        flush_ex_mem
);

  // --------------------------------------------------------------------------
  // 1. Data Forwarding Logic (RAW Hazard Resolution)
  // --------------------------------------------------------------------------
  always_comb begin
    if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
      fwd_a_sel = rv32i_types_pkg::FWD_EX_MEM;
    end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
      fwd_a_sel = rv32i_types_pkg::FWD_MEM_WB;
    end else begin
      fwd_a_sel = rv32i_types_pkg::FWD_NONE;
    end
  end

  always_comb begin
    if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
      fwd_b_sel = rv32i_types_pkg::FWD_EX_MEM;
    end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
      fwd_b_sel = rv32i_types_pkg::FWD_MEM_WB;
    end else begin
      fwd_b_sel = rv32i_types_pkg::FWD_NONE;
    end
  end

  // --------------------------------------------------------------------------
  // 2. Load-Use Hazard Detection
  // --------------------------------------------------------------------------
  wire load_use_hazard = !dcache_stall &&
                         id_ex_mem_read &&
                         (id_ex_rd != 5'd0) &&
                         ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

  // --------------------------------------------------------------------------
  // 3. Pipeline Stall & Flush Control Arbitration
  // --------------------------------------------------------------------------
  always_comb begin
    stall_if     = 1'b0;
    stall_id     = 1'b0;
    stall_ex     = 1'b0;
    stall_mem    = 1'b0;
    stall_wb     = 1'b0;

    flush_if_id  = 1'b0;
    flush_id_ex  = 1'b0;
    flush_ex_mem = 1'b0;

    if (trap_taken) begin
      flush_if_id  = 1'b1;
      flush_id_ex  = 1'b1;
      flush_ex_mem = 1'b1;
    end else if (dcache_stall) begin
      stall_if  = 1'b1;
      stall_id  = 1'b1;
      stall_ex  = 1'b1;
      stall_mem = 1'b1;
      stall_wb  = 1'b1;
    end else if (ex_redirect_en) begin
      flush_if_id = 1'b1;
      flush_id_ex = 1'b1;
    end else if (load_use_hazard) begin
      stall_if    = 1'b1;
      stall_id    = 1'b1;
      flush_id_ex = 1'b1;
    end
  end

endmodule
