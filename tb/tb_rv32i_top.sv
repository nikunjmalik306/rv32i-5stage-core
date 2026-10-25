// ============================================================================
// File: tb_rv32i_top.sv
// Description: Industrial-grade, self-checking testbench for the 5-stage
//              RV32I processor core with L1 cache and AXI4-Lite bus.
// Features:
//   - Instruction Memory Model with hex program loading
//   - AMBA AXI4-Lite Slave Memory Model responding with realistic handshake
//   - Architectural register scoreboard & retired instruction tracer
//   - Clocked assertions for forwarding and load-use timing (iverilog & Verilator clean)
//   - Automatic pass/fail checker evaluating register signature x10 == 42
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017
// ============================================================================

`timescale 1ns / 1ps

module tb_rv32i_top;

  // --------------------------------------------------------------------------
  // Clock & Reset Generation
  // --------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  localparam time CLK_PERIOD = 10ns; // 100 MHz clock

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // --------------------------------------------------------------------------
  // Interconnect Signals
  // --------------------------------------------------------------------------
  // Instruction Memory Interface
  wire [31:0] imem_addr;
  wire        imem_ren;
  logic [31:0] imem_rdata;

  // AXI4-Lite Bus
  wire [31:0] m_axi_awaddr;
  wire [2:0]  m_axi_awprot;
  wire        m_axi_awvalid;
  logic       m_axi_awready;

  wire [31:0] m_axi_wdata;
  wire [3:0]  m_axi_wstrb;
  wire        m_axi_wvalid;
  logic       m_axi_wready;

  logic [1:0] m_axi_bresp;
  logic       m_axi_bvalid;
  wire        m_axi_bready;

  wire [31:0] m_axi_araddr;
  wire [2:0]  m_axi_arprot;
  wire        m_axi_arvalid;
  logic       m_axi_arready;

  logic [31:0] m_axi_rdata;
  logic [1:0]  m_axi_rresp;
  logic       m_axi_rvalid;
  wire        m_axi_rready;

  // Core Trace / Debug Interface
  wire        dbg_wb_valid;
  wire [4:0]  dbg_wb_rd;
  wire [31:0] dbg_wb_data;

  // --------------------------------------------------------------------------
  // Device Under Test (DUT) Instance
  // --------------------------------------------------------------------------
  rv32i_core #(
    .RESET_VECTOR(32'h0000_0000)
  ) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .imem_addr    (imem_addr),
    .imem_ren     (imem_ren),
    .imem_rdata   (imem_rdata),
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
    .m_axi_rready (m_axi_rready),
    .dbg_wb_valid (dbg_wb_valid),
    .dbg_wb_rd    (dbg_wb_rd),
    .dbg_wb_data  (dbg_wb_data)
  );

  // --------------------------------------------------------------------------
  // Instruction Memory Model
  // --------------------------------------------------------------------------
  logic [31:0] rom_memory [0:1023];

  initial begin
    integer m;
    for (m = 0; m < 1024; m = m + 1) begin
      rom_memory[m] = 32'h00000013;
    end

    $display("[TB] Loading hex program into Instruction ROM...");
    $readmemh("programs/test_hazards.hex", rom_memory);
    if (rom_memory[0] === 32'hxx || rom_memory[0] == 32'h00000013) begin
      $readmemh("../tb/programs/test_hazards.hex", rom_memory);
    end
  end

  assign imem_rdata = rom_memory[imem_addr[11:2]];

  // --------------------------------------------------------------------------
  // AMBA AXI4-Lite Slave Memory Model
  // --------------------------------------------------------------------------
  logic [31:0] axi_ram [0:16383];

  typedef enum logic [1:0] {
    AXI_SLV_IDLE  = 2'b00,
    AXI_SLV_WRITE = 2'b01,
    AXI_SLV_READ  = 2'b10
  } axi_slv_state_e;

  axi_slv_state_e slv_state;

  logic [31:0] latched_awaddr;
  logic [31:0] latched_wdata;
  logic [3:0]  latched_wstrb;
  logic [31:0] latched_araddr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      slv_state      <= AXI_SLV_IDLE;
      m_axi_awready  <= 1'b0;
      m_axi_wready   <= 1'b0;
      m_axi_bvalid   <= 1'b0;
      m_axi_bresp    <= 2'b00;
      m_axi_arready  <= 1'b0;
      m_axi_rvalid   <= 1'b0;
      m_axi_rdata    <= 32'h0;
      m_axi_rresp    <= 2'b00;
      latched_awaddr <= 32'h0;
      latched_wdata  <= 32'h0;
      latched_wstrb  <= 4'h0;
      latched_araddr <= 32'h0;
    end else begin
      case (slv_state)
        AXI_SLV_IDLE: begin
          m_axi_bvalid <= 1'b0;
          m_axi_rvalid <= 1'b0;

          if (m_axi_awvalid && m_axi_wvalid) begin
            m_axi_awready  <= 1'b1;
            m_axi_wready   <= 1'b1;
            latched_awaddr <= m_axi_awaddr;
            latched_wdata  <= m_axi_wdata;
            latched_wstrb  <= m_axi_wstrb;
            slv_state      <= AXI_SLV_WRITE;
          end else if (m_axi_arvalid) begin
            m_axi_arready  <= 1'b1;
            latched_araddr <= m_axi_araddr;
            slv_state      <= AXI_SLV_READ;
          end
        end

        AXI_SLV_WRITE: begin
          m_axi_awready <= 1'b0;
          m_axi_wready  <= 1'b0;

          if (latched_wstrb[0]) axi_ram[latched_awaddr[15:2]][7:0]   <= latched_wdata[7:0];
          if (latched_wstrb[1]) axi_ram[latched_awaddr[15:2]][15:8]  <= latched_wdata[15:8];
          if (latched_wstrb[2]) axi_ram[latched_awaddr[15:2]][23:16] <= latched_wdata[23:16];
          if (latched_wstrb[3]) axi_ram[latched_awaddr[15:2]][31:24] <= latched_wdata[31:24];

          m_axi_bvalid <= 1'b1;
          m_axi_bresp  <= 2'b00;

          if (m_axi_bready && m_axi_bvalid) begin
            m_axi_bvalid <= 1'b0;
            slv_state    <= AXI_SLV_IDLE;
          end
        end

        AXI_SLV_READ: begin
          m_axi_arready <= 1'b0;
          m_axi_rdata   <= axi_ram[latched_araddr[15:2]];
          m_axi_rvalid  <= 1'b1;
          m_axi_rresp   <= 2'b00;

          if (m_axi_rready && m_axi_rvalid) begin
            m_axi_rvalid <= 1'b0;
            slv_state    <= AXI_SLV_IDLE;
          end
        end

        default: slv_state <= AXI_SLV_IDLE;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // Architectural Scoreboard & Trace Logger
  // --------------------------------------------------------------------------
  logic [31:0] shadow_regfile [0:31];
  integer retired_inst_count;
  integer cycle_count;
  integer load_use_stall_cycles;
  logic   prev_load_use;

  initial begin
    integer r;
    for (r = 0; r < 32; r = r + 1) shadow_regfile[r] = 32'h0;
    retired_inst_count    = 0;
    cycle_count           = 0;
    load_use_stall_cycles = 0;
    prev_load_use         = 1'b0;
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      cycle_count   <= cycle_count + 1;
      prev_load_use <= dut.u_hazard_unit.load_use_hazard;

      // Monitor load-use stalls
      if (dut.u_hazard_unit.load_use_hazard) begin
        load_use_stall_cycles <= load_use_stall_cycles + 1;
        $display("[CYCLE %04d] [HAZARD] Load-Use hazard detected: stall_if=%b stall_id=%b bubble_ex=%b",
                 cycle_count, dut.stall_if, dut.stall_id, dut.flush_id_ex);

        // Clocked Assertion: Load-use stall duration must be at most 1 cycle
        if (prev_load_use) begin
          $error("[ASSERTION VIOLATION] Load-Use stall lasted longer than 1 cycle!");
        end
      end

      // Monitor branch mispredictions & redirects
      if (dut.ex_redirect_en) begin
        $display("[CYCLE %04d] [CONTROL] EX Redirect fired -> Target PC: 0x%08x",
                 cycle_count, dut.ex_redirect_pc);
      end

      // Monitor writeback commits and verify invariants
      if (dbg_wb_valid) begin
        shadow_regfile[dbg_wb_rd] <= dbg_wb_data;
        retired_inst_count        <= retired_inst_count + 1;
        $display("[CYCLE %04d] [COMMIT] x%02d <= 0x%08x (%0d)",
                 cycle_count, dbg_wb_rd, dbg_wb_data, $signed(dbg_wb_data));

        // Clocked Assertions
        if (dbg_wb_rd == 5'd0 && dbg_wb_data != 32'd0) begin
          $error("[ASSERTION VIOLATION] Register x0 was written with non-zero: 0x%08x", dbg_wb_data);
        end
        if (dbg_wb_rd == 5'd3 && dbg_wb_data != 32'd30) begin
          $error("[ASSERTION VIOLATION] Data forwarding failed for x3: Expected 30, got %0d", dbg_wb_data);
        end
        if (dbg_wb_rd == 5'd4 && dbg_wb_data != 32'd20) begin
          $error("[ASSERTION VIOLATION] Data forwarding failed for x4: Expected 20, got %0d", dbg_wb_data);
        end
        if (dbg_wb_rd == 5'd5 && dbg_wb_data != 32'd30) begin
          $error("[ASSERTION VIOLATION] Data forwarding failed for x5: Expected 30, got %0d", dbg_wb_data);
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // Test Sequence & Pass/Fail Monitor
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("rv32i_trace.vcd");
    $dumpvars(0, tb_rv32i_top);

    $display("==================================================================");
    $display("  RV32I 5-Stage Pipelined Processor Core Testbench Simulation     ");
    $display("==================================================================");

    // Apply Reset
    rst_n = 1'b0;
    #(CLK_PERIOD * 5);
    @(negedge clk);
    rst_n = 1'b1;
    $display("[TB] Reset released at t = %0t ns", $time);

    // Run until halt or maximum cycle timeout
    fork
      begin
        // Wait for HALT condition: JAL x0, 0 at PC 0x50
        wait (dut.u_stage_if.pc_reg == 32'h0000_0050);
        repeat (10) @(posedge clk);

        $display("\n==================================================================");
        $display("  SIMULATION HALT DETECTED: EVALUATING ARCHITECTURAL RESULTS      ");
        $display("==================================================================");
        $display("  Total Cycles Elapsed:        %0d", cycle_count);
        $display("  Instructions Retired:        %0d", retired_inst_count);
        $display("  Load-Use Stalls Occurred:    %0d", load_use_stall_cycles);
        $display("  Final x1  (JAL Link x1):     %0d (Expected: 60)", shadow_regfile[1]);
        $display("  Final x2  (ADDI x2, 20):     %0d (Expected: 20)", shadow_regfile[2]);
        $display("  Final x3  (ADD x3, x1, x2):  %0d (Expected: 30)", shadow_regfile[3]);
        $display("  Final x4  (SUB x4, x3, x1):  %0d (Expected: 20)", shadow_regfile[4]);
        $display("  Final x5  (OR  x5, x4, x3):  %0d (Expected: 30)", shadow_regfile[5]);
        $display("  Final x7  (LW  x7, 0(x6)):   %0d (Expected: 30)", shadow_regfile[7]);
        $display("  Final x8  (ADDI x8, x7, 12): %0d (Expected: 42)", shadow_regfile[8]);
        $display("  Final x9  (ADDI x9, 1):      %0d (Expected: 1)", shadow_regfile[9]);
        $display("  Final x10 (Return Code):     %0d (Expected: 42)", shadow_regfile[10]);
        $display("  Final x11 (Cache Hit Read):  %0d (Expected: 42)", shadow_regfile[11]);
        $display("==================================================================");

        if (shadow_regfile[10] === 32'd42 &&
            shadow_regfile[11] === 32'd42 &&
            shadow_regfile[8]  === 32'd42 &&
            shadow_regfile[3]  === 32'd30 &&
            shadow_regfile[1]  === 32'd60 &&
            load_use_stall_cycles == 1) begin
          $display("\n##################################################################");
          $display("###                   TEST PASSED                              ###");
          $display("###  All Hazards, Branches, and Cache Accesses Verified!       ###");
          $display("##################################################################\n");
          $finish;
        end else begin
          $display("\n******************************************************************");
          $display("***                   TEST FAILED                              ***");
          $display("***  Architectural register signatures did not match expected! ***");
          $display("******************************************************************\n");
          $fatal(1, "Testbench verification failed.");
        end
      end

      begin
        // Watchdog Timeout (1000 clock cycles = 10,000 ns)
        #(CLK_PERIOD * 1000);
        $display("\n[TB ERROR] Simulation Watchdog Timeout reached after 1000 cycles!");
        $fatal(2, "Watchdog timeout.");
      end
    join_any
  end

endmodule
