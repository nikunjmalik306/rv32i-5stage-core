// ============================================================================
// File: rv32i_core.sv
// Description: Top-level RV32I 5-Stage Pipelined Processor Core integrating
//              IF, ID, EX, MEM, WB stages, dynamic branch predictor, hazard &
//              forwarding unit, L1 Data Cache, and AMBA AXI4-Lite master bus.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

`timescale 1ns / 1ps

module rv32i_core #(
  parameter logic [31:0] RESET_VECTOR = 32'h0000_0000,
  parameter logic [31:0] TRAP_VECTOR  = 32'h0000_0004
)(
  input  logic        clk,
  input  logic        rst_n,

  // Instruction Memory Bus Interface (Direct Single-Cycle Fetch Interface)
  output logic [31:0] imem_addr,
  output logic        imem_ren,
  input  logic [31:0] imem_rdata,

  // External AMBA AXI4-Lite Master Interface (for Data Cache Refill/Eviction)
  // Write Address Channel
  output logic [31:0] m_axi_awaddr,
  output logic [2:0]  m_axi_awprot,
  output logic        m_axi_awvalid,
  input  logic        m_axi_awready,

  // Write Data Channel
  output logic [31:0] m_axi_wdata,
  output logic [3:0]  m_axi_wstrb,
  output logic        m_axi_wvalid,
  input  logic        m_axi_wready,

  // Write Response Channel
  input  logic [1:0]  m_axi_bresp,
  input  logic        m_axi_bvalid,
  output logic        m_axi_bready,

  // Read Address Channel
  output logic [31:0] m_axi_araddr,
  output logic [2:0]  m_axi_arprot,
  output logic        m_axi_arvalid,
  input  logic        m_axi_arready,

  // Read Data Channel
  input  logic [31:0] m_axi_rdata,
  input  logic [1:0]  m_axi_rresp,
  input  logic        m_axi_rvalid,
  output logic        m_axi_rready,

  // Architectural Exception / Trap Interface
  output logic        trap_taken,
  output logic [31:0] trap_cause,
  output logic [31:0] trap_epc,
  output logic [31:0] trap_val,

  // Trace & Verification Interface
  output logic        dcache_error,
  output logic        dbg_wb_valid,
  output logic [4:0]  dbg_wb_rd,
  output logic [31:0] dbg_wb_data
);

  // --------------------------------------------------------------------------
  // Interconnect Wires
  // --------------------------------------------------------------------------
  logic        bp_pred_taken;
  logic [31:0] bp_pred_target;
  logic        bp_update_en;
  logic [31:0] bp_update_pc;
  logic [31:0] bp_update_target;
  logic        bp_actual_taken;

  logic [31:0] if_pc;
  logic [31:0] if_pc_plus4;
  logic [31:0] if_inst;
  logic        if_pred_taken;

  logic [31:0] id_pc;
  logic [31:0] id_pc_plus4;
  logic [31:0] id_inst;
  logic        id_pred_taken;

  logic [4:0]  id_rs1;
  logic [4:0]  id_rs2;
  logic [4:0]  id_rd;
  logic [31:0] id_rs1_data;
  logic [31:0] id_rs2_data;
  logic [31:0] id_imm;
  logic [31:0] id_out_pc;
  logic [31:0] id_out_pc_plus4;
  logic        id_out_pred_taken;
  logic        id_reg_write;
  logic        id_mem_to_reg;
  logic        id_mem_read;
  logic        id_mem_write;
  logic [2:0]  id_mem_width;
  logic        id_alu_src_a;
  logic        id_alu_src_b;
  logic [3:0]  id_alu_op;
  logic [2:0]  id_branch_type;
  logic        id_is_branch;
  logic        id_is_jal;
  logic        id_is_jalr;

  logic        ex_reg_write;
  logic        ex_mem_to_reg;
  logic        ex_mem_read;
  logic        ex_mem_write;
  logic [2:0]  ex_mem_width;
  logic        ex_alu_src_a;
  logic        ex_alu_src_b;
  logic [3:0]  ex_alu_op;
  logic [2:0]  ex_branch_type;
  logic        ex_is_branch;
  logic        ex_is_jal;
  logic        ex_is_jalr;
  logic [31:0] ex_pc;
  logic [31:0] ex_pc_plus4;
  logic        ex_pred_taken;
  logic [31:0] ex_rs1_data;
  logic [31:0] ex_rs2_data;
  logic [31:0] ex_imm;
  logic [4:0]  ex_rs1;
  logic [4:0]  ex_rs2;
  logic [4:0]  ex_rd;

  logic        ex_out_reg_write;
  logic        ex_out_mem_to_reg;
  logic        ex_out_mem_read;
  logic        ex_out_mem_write;
  logic [2:0]  ex_out_mem_width;
  logic [31:0] ex_out_alu_result;
  logic [31:0] ex_out_store_data;
  logic [4:0]  ex_out_rd;
  logic        ex_redirect_en;
  logic [31:0] ex_redirect_pc;

  logic        mem_reg_write;
  logic        mem_mem_to_reg;
  logic        mem_mem_read;
  logic        mem_mem_write;
  logic [2:0]  mem_mem_width;
  logic [31:0] mem_alu_result;
  logic [31:0] mem_store_data;
  logic [4:0]  mem_rd;
  logic [31:0] mem_pc;

  logic        dcache_req;
  logic        dcache_we;
  logic [31:0] dcache_addr;
  logic [31:0] dcache_wdata;
  logic [3:0]  dcache_wstrb;
  logic [31:0] dcache_rdata;
  logic        dcache_stall;

  logic        trap_redirect_en;
  logic [31:0] trap_redirect_pc;

  // Architectural Trap Generation for Memory Access Faults
  wire is_mem_fault = dcache_error && (mem_mem_read || mem_mem_write);
  assign trap_taken       = is_mem_fault;
  assign trap_cause       = mem_mem_read ? rv32i_types_pkg::CAUSE_LOAD_ACCESS_FAULT :
                                           rv32i_types_pkg::CAUSE_STORE_ACCESS_FAULT;
  assign trap_epc         = mem_pc;
  assign trap_val         = dcache_addr;
  assign trap_redirect_en = is_mem_fault;
  assign trap_redirect_pc = TRAP_VECTOR;

  logic        mem_out_reg_write;
  logic        mem_out_mem_to_reg;
  logic [31:0] mem_out_read_data;
  logic [31:0] mem_out_alu_result;
  logic [4:0]  mem_out_rd;

  logic        wb_reg_write;
  logic        wb_mem_to_reg;
  logic [31:0] wb_read_data;
  logic [31:0] wb_alu_result;
  logic [4:0]  wb_rd;

  logic        wb_out_reg_write;
  logic [4:0]  wb_out_rd;
  logic [31:0] wb_out_data;

  logic [1:0]  fwd_a_sel;
  logic [1:0]  fwd_b_sel;
  logic        stall_if;
  logic        stall_id;
  logic        stall_ex;
  logic        stall_mem;
  logic        stall_wb;
  logic        flush_if_id;
  logic        flush_id_ex;
  logic        flush_ex_mem;

  logic        axi_cmd_valid;
  logic        axi_cmd_write;
  logic [31:0] axi_cmd_addr;
  logic [31:0] axi_cmd_wdata;
  logic [3:0]  axi_cmd_wstrb;
  logic        axi_cmd_ready;
  logic        axi_rsp_valid;
  logic [31:0] axi_rsp_rdata;
  logic        axi_rsp_error;

  // --------------------------------------------------------------------------
  // Module Instances
  // --------------------------------------------------------------------------

  // 1. Branch Predictor
  branch_predictor #(
    .BHT_ENTRIES(64),
    .INDEX_BITS(6)
  ) u_bp (
    .clk          (clk),
    .rst_n        (rst_n),
    .if_pc        (if_pc),
    .pred_taken   (bp_pred_taken),
    .pred_target  (bp_pred_target),
    .update_en    (bp_update_en),
    .update_pc    (bp_update_pc),
    .update_target(bp_update_target),
    .actual_taken (bp_actual_taken)
  );

  // 2. IF Stage
  stage_if #(
    .RESET_VECTOR(RESET_VECTOR)
  ) u_stage_if (
    .clk             (clk),
    .rst_n           (rst_n),
    .stall_pc        (stall_if),
    .trap_redirect_en(trap_redirect_en),
    .trap_redirect_pc(trap_redirect_pc),
    .ex_redirect_en  (ex_redirect_en),
    .ex_redirect_pc  (ex_redirect_pc),
    .bp_pred_taken (bp_pred_taken),
    .bp_pred_target(bp_pred_target),
    .imem_addr     (imem_addr),
    .imem_ren      (imem_ren),
    .imem_rdata    (imem_rdata),
    .if_pc         (if_pc),
    .if_pc_plus4   (if_pc_plus4),
    .if_inst       (if_inst),
    .if_pred_taken (if_pred_taken)
  );

  // 3. IF/ID Pipeline Register
  pipe_reg_if_id u_pipe_reg_if_id (
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (stall_id),
    .flush        (flush_if_id),
    .if_pc        (if_pc),
    .if_pc_plus4  (if_pc_plus4),
    .if_inst      (if_inst),
    .if_pred_taken(if_pred_taken),
    .id_pc        (id_pc),
    .id_pc_plus4  (id_pc_plus4),
    .id_inst      (id_inst),
    .id_pred_taken(id_pred_taken)
  );

  // 4. ID Stage
  stage_id u_stage_id (
    .clk              (clk),
    .rst_n            (rst_n),
    .id_pc            (id_pc),
    .id_pc_plus4      (id_pc_plus4),
    .id_inst          (id_inst),
    .id_pred_taken    (id_pred_taken),
    .wb_reg_write     (wb_out_reg_write),
    .wb_rd            (wb_out_rd),
    .wb_data          (wb_out_data),
    .id_rs1           (id_rs1),
    .id_rs2           (id_rs2),
    .id_rd            (id_rd),
    .id_rs1_data      (id_rs1_data),
    .id_rs2_data      (id_rs2_data),
    .id_imm           (id_imm),
    .id_out_pc        (id_out_pc),
    .id_out_pc_plus4  (id_out_pc_plus4),
    .id_out_pred_taken(id_out_pred_taken),
    .id_reg_write     (id_reg_write),
    .id_mem_to_reg    (id_mem_to_reg),
    .id_mem_read      (id_mem_read),
    .id_mem_write     (id_mem_write),
    .id_mem_width     (id_mem_width),
    .id_alu_src_a     (id_alu_src_a),
    .id_alu_src_b     (id_alu_src_b),
    .id_alu_op        (id_alu_op),
    .id_branch_type   (id_branch_type),
    .id_is_branch     (id_is_branch),
    .id_is_jal        (id_is_jal),
    .id_is_jalr       (id_is_jalr)
  );

  // 5. ID/EX Pipeline Register
  pipe_reg_id_ex u_pipe_reg_id_ex (
    .clk           (clk),
    .rst_n         (rst_n),
    .stall         (stall_ex),
    .flush         (flush_id_ex),
    .id_reg_write  (id_reg_write),
    .id_mem_to_reg (id_mem_to_reg),
    .id_mem_read   (id_mem_read),
    .id_mem_write  (id_mem_write),
    .id_mem_width  (id_mem_width),
    .id_alu_src_a  (id_alu_src_a),
    .id_alu_src_b  (id_alu_src_b),
    .id_alu_op     (id_alu_op),
    .id_branch_type(id_branch_type),
    .id_is_branch  (id_is_branch),
    .id_is_jal     (id_is_jal),
    .id_is_jalr    (id_is_jalr),
    .id_pc         (id_out_pc),
    .id_pc_plus4   (id_out_pc_plus4),
    .id_pred_taken (id_out_pred_taken),
    .id_rs1_data   (id_rs1_data),
    .id_rs2_data   (id_rs2_data),
    .id_imm        (id_imm),
    .id_rs1        (id_rs1),
    .id_rs2        (id_rs2),
    .id_rd         (id_rd),
    .ex_reg_write  (ex_reg_write),
    .ex_mem_to_reg (ex_mem_to_reg),
    .ex_mem_read   (ex_mem_read),
    .ex_mem_write  (ex_mem_write),
    .ex_mem_width  (ex_mem_width),
    .ex_alu_src_a  (ex_alu_src_a),
    .ex_alu_src_b  (ex_alu_src_b),
    .ex_alu_op     (ex_alu_op),
    .ex_branch_type(ex_branch_type),
    .ex_is_branch  (ex_is_branch),
    .ex_is_jal     (ex_is_jal),
    .ex_is_jalr    (ex_is_jalr),
    .ex_pc         (ex_pc),
    .ex_pc_plus4   (ex_pc_plus4),
    .ex_pred_taken (ex_pred_taken),
    .ex_rs1_data   (ex_rs1_data),
    .ex_rs2_data   (ex_rs2_data),
    .ex_imm        (ex_imm),
    .ex_rs1        (ex_rs1),
    .ex_rs2        (ex_rs2),
    .ex_rd         (ex_rd)
  );

  // 6. EX Stage
  stage_ex u_stage_ex (
    .ex_reg_write     (ex_reg_write),
    .ex_mem_to_reg    (ex_mem_to_reg),
    .ex_mem_read      (ex_mem_read),
    .ex_mem_write     (ex_mem_write),
    .ex_mem_width     (ex_mem_width),
    .ex_alu_src_a     (ex_alu_src_a),
    .ex_alu_src_b     (ex_alu_src_b),
    .ex_alu_op        (ex_alu_op),
    .ex_branch_type   (ex_branch_type),
    .ex_is_branch     (ex_is_branch),
    .ex_is_jal        (ex_is_jal),
    .ex_is_jalr       (ex_is_jalr),
    .ex_pc            (ex_pc),
    .ex_pc_plus4      (ex_pc_plus4),
    .ex_pred_taken    (ex_pred_taken),
    .ex_rs1_data      (ex_rs1_data),
    .ex_rs2_data      (ex_rs2_data),
    .ex_imm           (ex_imm),
    .ex_rs1           (ex_rs1),
    .ex_rs2           (ex_rs2),
    .ex_rd            (ex_rd),
    .fwd_a_sel        (fwd_a_sel),
    .fwd_b_sel        (fwd_b_sel),
    .fwd_ex_mem_data  (mem_alu_result),
    .fwd_mem_wb_data  (wb_out_data),
    .ex_out_reg_write (ex_out_reg_write),
    .ex_out_mem_to_reg(ex_out_mem_to_reg),
    .ex_out_mem_read  (ex_out_mem_read),
    .ex_out_mem_write (ex_out_mem_write),
    .ex_out_mem_width (ex_out_mem_width),
    .ex_out_alu_result(ex_out_alu_result),
    .ex_out_store_data(ex_out_store_data),
    .ex_out_rd        (ex_out_rd),
    .ex_redirect_en   (ex_redirect_en),
    .ex_redirect_pc   (ex_redirect_pc),
    .bp_update_en     (bp_update_en),
    .bp_update_pc     (bp_update_pc),
    .bp_update_target (bp_update_target),
    .bp_actual_taken  (bp_actual_taken)
  );

  // 7. Hazard and Forwarding Unit
  hazard_unit u_hazard_unit (
    .id_ex_rs1       (ex_rs1),
    .id_ex_rs2       (ex_rs2),
    .ex_mem_rd       (mem_rd),
    .ex_mem_reg_write(mem_reg_write),
    .mem_wb_rd       (wb_rd),
    .mem_wb_reg_write(wb_reg_write),
    .id_ex_mem_read  (ex_mem_read),
    .id_ex_rd        (ex_rd),
    .if_id_rs1       (id_rs1),
    .if_id_rs2       (id_rs2),
    .ex_redirect_en  (ex_redirect_en),
    .trap_taken      (trap_taken),
    .dcache_stall    (dcache_stall),
    .fwd_a_sel       (fwd_a_sel),
    .fwd_b_sel       (fwd_b_sel),
    .stall_if        (stall_if),
    .stall_id        (stall_id),
    .stall_ex        (stall_ex),
    .stall_mem       (stall_mem),
    .stall_wb        (stall_wb),
    .flush_if_id     (flush_if_id),
    .flush_id_ex     (flush_id_ex),
    .flush_ex_mem    (flush_ex_mem)
  );

  // 8. EX/MEM Pipeline Register
  pipe_reg_ex_mem u_pipe_reg_ex_mem (
    .clk           (clk),
    .rst_n         (rst_n),
    .stall         (stall_mem),
    .flush         (flush_ex_mem),
    .ex_reg_write  (ex_out_reg_write),
    .ex_mem_to_reg (ex_out_mem_to_reg),
    .ex_mem_read   (ex_out_mem_read),
    .ex_mem_write  (ex_out_mem_write),
    .ex_mem_width  (ex_out_mem_width),
    .ex_alu_result (ex_out_alu_result),
    .ex_store_data (ex_out_store_data),
    .ex_rd         (ex_out_rd),
    .ex_pc         (ex_pc),
    .mem_reg_write (mem_reg_write),
    .mem_mem_to_reg(mem_mem_to_reg),
    .mem_mem_read  (mem_mem_read),
    .mem_mem_write (mem_mem_write),
    .mem_mem_width (mem_mem_width),
    .mem_alu_result(mem_alu_result),
    .mem_store_data(mem_store_data),
    .mem_rd        (mem_rd),
    .mem_pc        (mem_pc)
  );

  // 9. MEM Stage
  stage_mem u_stage_mem (
    .mem_reg_write     (mem_reg_write),
    .mem_mem_to_reg    (mem_mem_to_reg),
    .mem_mem_read      (mem_mem_read),
    .mem_mem_write     (mem_mem_write),
    .mem_mem_width     (mem_mem_width),
    .mem_alu_result    (mem_alu_result),
    .mem_store_data    (mem_store_data),
    .mem_rd            (mem_rd),
    .dcache_req        (dcache_req),
    .dcache_we         (dcache_we),
    .dcache_addr       (dcache_addr),
    .dcache_wdata      (dcache_wdata),
    .dcache_wstrb      (dcache_wstrb),
    .dcache_rdata      (dcache_rdata),
    .dcache_error      (dcache_error),
    .mem_out_reg_write (mem_out_reg_write),
    .mem_out_mem_to_reg(mem_out_mem_to_reg),
    .mem_out_read_data (mem_out_read_data),
    .mem_out_alu_result(mem_out_alu_result),
    .mem_out_rd        (mem_out_rd)
  );

  // 10. L1 Data Cache
  l1_dcache u_l1_dcache (
    .clk          (clk),
    .rst_n        (rst_n),
    .cpu_req      (dcache_req),
    .cpu_we       (dcache_we),
    .cpu_addr     (dcache_addr),
    .cpu_wdata    (dcache_wdata),
    .cpu_wstrb    (dcache_wstrb),
    .cpu_rdata    (dcache_rdata),
    .cpu_stall    (dcache_stall),
    .cpu_error    (dcache_error),
    .axi_cmd_valid(axi_cmd_valid),
    .axi_cmd_write(axi_cmd_write),
    .axi_cmd_addr (axi_cmd_addr),
    .axi_cmd_wdata(axi_cmd_wdata),
    .axi_cmd_wstrb(axi_cmd_wstrb),
    .axi_cmd_ready(axi_cmd_ready),
    .axi_rsp_valid(axi_rsp_valid),
    .axi_rsp_rdata(axi_rsp_rdata),
    .axi_rsp_error(axi_rsp_error)
  );

  // 11. AMBA AXI4-Lite Master Bridge
  axi4_lite_master u_axi_master (
    .aclk         (clk),
    .aresetn      (rst_n),
    .cmd_valid    (axi_cmd_valid),
    .cmd_write    (axi_cmd_write),
    .cmd_addr     (axi_cmd_addr),
    .cmd_wdata    (axi_cmd_wdata),
    .cmd_wstrb    (axi_cmd_wstrb),
    .cmd_ready    (axi_cmd_ready),
    .rsp_valid    (axi_rsp_valid),
    .rsp_rdata    (axi_rsp_rdata),
    .rsp_error    (axi_rsp_error),
    .m_axi_awaddr (m_axi_awaddr),
    .m_axi_awprot (m_axi_awprot),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata  (m_axi_wdata),
    .m_axi_wstrb  (m_axi_wstrb),
    .m_axi_wvalid (m_axi_wvalid),
    .m_axi_wready (m_axi_wready),
    .m_axi_bresp  (m_axi_bresp),
    .m_axi_bvalid (m_axi_bvalid),
    .m_axi_bready (m_axi_bready),
    .m_axi_araddr (m_axi_araddr),
    .m_axi_arprot (m_axi_arprot),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rdata  (m_axi_rdata),
    .m_axi_rresp  (m_axi_rresp),
    .m_axi_rvalid (m_axi_rvalid),
    .m_axi_rready (m_axi_rready)
  );

  // 12. MEM/WB Pipeline Register
  pipe_reg_mem_wb u_pipe_reg_mem_wb (
    .clk          (clk),
    .rst_n        (rst_n),
    .stall        (stall_wb),
    .flush        (1'b0),
    .mem_reg_write(mem_out_reg_write),
    .mem_mem_to_reg(mem_out_mem_to_reg),
    .mem_read_data(mem_out_read_data),
    .mem_alu_result(mem_out_alu_result),
    .mem_rd       (mem_out_rd),
    .wb_reg_write (wb_reg_write),
    .wb_mem_to_reg(wb_mem_to_reg),
    .wb_read_data (wb_read_data),
    .wb_alu_result(wb_alu_result),
    .wb_rd        (wb_rd)
  );

  // 13. WB Stage
  stage_wb u_stage_wb (
    .wb_reg_write    (wb_reg_write),
    .wb_mem_to_reg   (wb_mem_to_reg),
    .wb_read_data    (wb_read_data),
    .wb_alu_result   (wb_alu_result),
    .wb_rd           (wb_rd),
    .wb_out_reg_write(wb_out_reg_write),
    .wb_out_rd       (wb_out_rd),
    .wb_out_data     (wb_out_data)
  );

  // Trace / Debug Outputs
  assign dbg_wb_valid = wb_out_reg_write && (wb_out_rd != 5'd0);
  assign dbg_wb_rd    = wb_out_rd;
  assign dbg_wb_data  = wb_out_data;

endmodule
