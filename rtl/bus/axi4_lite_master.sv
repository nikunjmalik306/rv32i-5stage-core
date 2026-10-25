// ============================================================================
// File: axi4_lite_master.sv
// Description: AMBA AXI4-Lite Master Bridge interfacing L1 Cache requests
//              (burst refills and dirty evictions) to an external memory system.
// Features:
//   - Independent, concurrent AW and W channels with individual ready tracking
//   - Compliant with any AXI4-Lite slave handshake ordering
//   - Zero-latency combinational forwarding of rdata & error during rsp_valid
//   - Strict error reporting on SLVERR / DECERR
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ============================================================================

`timescale 1ns / 1ps

module axi4_lite_master (
  input  logic        aclk,
  input  logic        aresetn,

  // Cache-facing Internal Transaction Interface
  input  logic        cmd_valid,
  input  logic        cmd_write,      // 0: Read request, 1: Write request
  input  logic [31:0] cmd_addr,
  input  logic [31:0] cmd_wdata,
  input  logic [3:0]  cmd_wstrb,
  output logic        cmd_ready,      // Master ready to accept new command
  output logic        rsp_valid,      // Transaction complete pulse
  output logic [31:0] rsp_rdata,      // Read data returned
  output logic        rsp_error,      // Bus SLVERR / DECERR

  // AMBA AXI4-Lite Master Port
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
  output logic        m_axi_rready
);

  // --------------------------------------------------------------------------
  // FSM States
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    AXI_IDLE       = 3'b000,
    AXI_READ_ADDR  = 3'b001,
    AXI_READ_DATA  = 3'b010,
    AXI_WRITE_DATA = 3'b011, // Concurrent AW & W channels
    AXI_WRITE_RESP = 3'b100
  } axi_state_e;

  axi_state_e state, next_state;

  // Internal registers
  logic [31:0] reg_addr;
  logic [31:0] reg_wdata;
  logic [3:0]  reg_wstrb;
  logic [31:0] reg_rdata;
  logic        reg_error;

  // Handshake completion tracking flags for write channels
  logic        aw_done;
  logic        w_done;

  // Constant protection attributes: unprivileged, secure, data
  assign m_axi_awprot = 3'b000;
  assign m_axi_arprot = 3'b000;

  // --------------------------------------------------------------------------
  // Synchronous State & Register Update
  // --------------------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      state     <= AXI_IDLE;
      reg_addr  <= 32'h0;
      reg_wdata <= 32'h0;
      reg_wstrb <= 4'h0;
      reg_rdata <= 32'h0;
      reg_error <= 1'b0;
      aw_done   <= 1'b0;
      w_done    <= 1'b0;
    end else begin
      state <= next_state;

      case (state)
        AXI_IDLE: begin
          aw_done   <= 1'b0;
          w_done    <= 1'b0;
          reg_error <= 1'b0;
          if (cmd_valid) begin
            reg_addr  <= cmd_addr;
            reg_wdata <= cmd_wdata;
            reg_wstrb <= cmd_wstrb;
          end
        end

        AXI_WRITE_DATA: begin
          if (m_axi_awvalid && m_axi_awready) aw_done <= 1'b1;
          if (m_axi_wvalid && m_axi_wready)   w_done  <= 1'b1;
        end

        AXI_READ_DATA: begin
          if (m_axi_rvalid && m_axi_rready) begin
            reg_rdata <= m_axi_rdata;
            reg_error <= (m_axi_rresp != 2'b00);
          end
        end

        AXI_WRITE_RESP: begin
          if (m_axi_bvalid && m_axi_bready) begin
            reg_error <= (m_axi_bresp != 2'b00);
          end
        end

        default: ;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Next-State Combinational Logic & Output Assignments
  // --------------------------------------------------------------------------
  always_comb begin
    next_state = state;

    cmd_ready     = 1'b0;
    rsp_valid     = 1'b0;

    m_axi_araddr  = reg_addr;
    m_axi_arvalid = 1'b0;
    m_axi_rready  = 1'b0;

    m_axi_awaddr  = reg_addr;
    m_axi_awvalid = 1'b0;
    m_axi_wdata   = reg_wdata;
    m_axi_wstrb   = reg_wstrb;
    m_axi_wvalid  = 1'b0;
    m_axi_bready  = 1'b0;

    case (state)
      AXI_IDLE: begin
        cmd_ready = 1'b1;
        if (cmd_valid) begin
          if (cmd_write) begin
            next_state = AXI_WRITE_DATA;
          end else begin
            next_state = AXI_READ_ADDR;
          end
        end
      end

      // Read Transaction Path
      AXI_READ_ADDR: begin
        m_axi_arvalid = 1'b1;
        if (m_axi_arready) begin
          next_state = AXI_READ_DATA;
        end
      end

      AXI_READ_DATA: begin
        m_axi_rready = 1'b1;
        if (m_axi_rvalid) begin
          rsp_valid  = 1'b1;
          next_state = AXI_IDLE;
        end
      end

      // Write Transaction Path: Independent, Concurrent AW & W channels
      AXI_WRITE_DATA: begin
        m_axi_awvalid = !aw_done;
        m_axi_wvalid  = !w_done;

        // Transition when both handshakes are complete (either simultaneously or sequentially)
        if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
            (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
          next_state = AXI_WRITE_RESP;
        end
      end

      AXI_WRITE_RESP: begin
        m_axi_bready = 1'b1;
        if (m_axi_bvalid) begin
          rsp_valid  = 1'b1;
          next_state = AXI_IDLE;
        end
      end

      default: next_state = AXI_IDLE;
    endcase
  end

  // Combinational feed-through ensures rsp_rdata & rsp_error are valid on the exact cycle rsp_valid pulses
  assign rsp_rdata = (state == AXI_READ_DATA && m_axi_rvalid) ? m_axi_rdata : reg_rdata;
  assign rsp_error = (state == AXI_READ_DATA && m_axi_rvalid) ? (m_axi_rresp != 2'b00) :
                     (state == AXI_WRITE_RESP && m_axi_bvalid) ? (m_axi_bresp != 2'b00) : reg_error;

endmodule
