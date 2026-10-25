// ============================================================================
// File: branch_predictor.sv
// Description: 64-entry 2-bit Saturating Counter Branch History Table (BHT)
//              integrated with a Branch Target Buffer (BTB).
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module branch_predictor #(
  parameter int unsigned BHT_ENTRIES = 64,
  parameter int unsigned INDEX_BITS  = 6 // $clog2(64)
)(
  input  logic        clk,
  input  logic        rst_n,

  // Prediction Interface (IF Stage)
  input  logic [31:0] if_pc,
  output logic        pred_taken,
  output logic [31:0] pred_target,

  // Update Interface (EX Stage Resolution)
  input  logic        update_en,
  input  logic [31:0] update_pc,
  input  logic [31:0] update_target,
  input  logic        actual_taken
);

  // --------------------------------------------------------------------------
  // Internal State: BHT and BTB arrays
  // --------------------------------------------------------------------------
  logic [1:0]  bht [0:BHT_ENTRIES-1];
  logic [31:0] btb [0:BHT_ENTRIES-1];
  logic [31:0] btb_tag [0:BHT_ENTRIES-1];
  logic        btb_valid [0:BHT_ENTRIES-1];

  // Indices
  wire [INDEX_BITS-1:0] if_index     = if_pc[INDEX_BITS+1:2];
  wire [INDEX_BITS-1:0] update_index = update_pc[INDEX_BITS+1:2];

  // --------------------------------------------------------------------------
  // Prediction: Taken if MSB is set AND BTB has a valid matching tag
  // --------------------------------------------------------------------------
  wire hit = btb_valid[if_index] && (btb_tag[if_index] == if_pc);
  assign pred_taken  = hit && bht[if_index][1];
  assign pred_target = hit ? btb[if_index] : (if_pc + 32'd4);

  // --------------------------------------------------------------------------
  // Synchronous Update with Saturating Arithmetic
  // --------------------------------------------------------------------------
  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < BHT_ENTRIES; i = i + 1) begin
        bht[i]       <= rv32i_types_pkg::BHT_WEAKLY_NOT_TAKEN;
        btb[i]       <= 32'h00000000;
        btb_tag[i]   <= 32'h00000000;
        btb_valid[i] <= 1'b0;
      end
    end else if (update_en) begin
      // Update BTB
      if (actual_taken) begin
        btb[update_index]       <= update_target;
        btb_tag[update_index]   <= update_pc;
        btb_valid[update_index] <= 1'b1;
      end

      // Update 2-bit counter
      case (bht[update_index])
        rv32i_types_pkg::BHT_STRONGLY_NOT_TAKEN: begin
          if (actual_taken)
            bht[update_index] <= rv32i_types_pkg::BHT_WEAKLY_NOT_TAKEN;
          else
            bht[update_index] <= rv32i_types_pkg::BHT_STRONGLY_NOT_TAKEN;
        end

        rv32i_types_pkg::BHT_WEAKLY_NOT_TAKEN: begin
          if (actual_taken)
            bht[update_index] <= rv32i_types_pkg::BHT_WEAKLY_TAKEN;
          else
            bht[update_index] <= rv32i_types_pkg::BHT_STRONGLY_NOT_TAKEN;
        end

        rv32i_types_pkg::BHT_WEAKLY_TAKEN: begin
          if (actual_taken)
            bht[update_index] <= rv32i_types_pkg::BHT_STRONGLY_TAKEN;
          else
            bht[update_index] <= rv32i_types_pkg::BHT_WEAKLY_NOT_TAKEN;
        end

        rv32i_types_pkg::BHT_STRONGLY_TAKEN: begin
          if (actual_taken)
            bht[update_index] <= rv32i_types_pkg::BHT_STRONGLY_TAKEN;
          else
            bht[update_index] <= rv32i_types_pkg::BHT_WEAKLY_TAKEN;
        end

        default: begin
          bht[update_index] <= rv32i_types_pkg::BHT_WEAKLY_NOT_TAKEN;
        end
      endcase
    end
  end

endmodule
