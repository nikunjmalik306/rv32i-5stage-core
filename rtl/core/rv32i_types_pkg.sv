// ============================================================================
// File: rv32i_types_pkg.sv
// Description: Global type definitions, opcodes, ALU operations, and pipeline
//              constants for the 5-stage pipelined RV32I processor.
// Standard: SystemVerilog IEEE 1800-2012 / 1800-2017 (Yosys & Verilator clean)
// ============================================================================

package rv32i_types_pkg;

  // --------------------------------------------------------------------------
  // Major RV32I Base Opcodes (Inst[6:0])
  // --------------------------------------------------------------------------
  localparam logic [6:0] OPCODE_R      = 7'b0110011; // Register-Register ALU
  localparam logic [6:0] OPCODE_I      = 7'b0010011; // Register-Immediate ALU
  localparam logic [6:0] OPCODE_LOAD   = 7'b0000011; // Load instructions
  localparam logic [6:0] OPCODE_STORE  = 7'b0100011; // Store instructions
  localparam logic [6:0] OPCODE_BRANCH = 7'b1100011; // Conditional branches
  localparam logic [6:0] OPCODE_JAL    = 7'b1101111; // Jump and Link
  localparam logic [6:0] OPCODE_JALR   = 7'b1100111; // Jump and Link Register
  localparam logic [6:0] OPCODE_LUI    = 7'b0110111; // Load Upper Immediate
  localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111; // Add Upper Immediate to PC
  localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011; // ECALL, EBREAK, CSR
  localparam logic [6:0] OPCODE_FENCE  = 7'b0001111; // FENCE, FENCE.I

  // --------------------------------------------------------------------------
  // ALU Operations (4-bit encoding)
  // --------------------------------------------------------------------------
  localparam logic [3:0] ALU_ADD    = 4'b0000;
  localparam logic [3:0] ALU_SUB    = 4'b0001;
  localparam logic [3:0] ALU_SLL    = 4'b0010;
  localparam logic [3:0] ALU_SLT    = 4'b0011;
  localparam logic [3:0] ALU_SLTU   = 4'b0100;
  localparam logic [3:0] ALU_XOR    = 4'b0101;
  localparam logic [3:0] ALU_SRL    = 4'b0110;
  localparam logic [3:0] ALU_SRA    = 4'b0111;
  localparam logic [3:0] ALU_OR     = 4'b1000;
  localparam logic [3:0] ALU_AND    = 4'b1001;
  localparam logic [3:0] ALU_PASS_B = 4'b1010;

  // --------------------------------------------------------------------------
  // Branch Condition Types (from funct3, 3-bit encoding)
  // --------------------------------------------------------------------------
  localparam logic [2:0] BR_BEQ  = 3'b000;
  localparam logic [2:0] BR_BNE  = 3'b001;
  localparam logic [2:0] BR_BLT  = 3'b100;
  localparam logic [2:0] BR_BGE  = 3'b101;
  localparam logic [2:0] BR_BLTU = 3'b110;
  localparam logic [2:0] BR_BGEU = 3'b111;

  // --------------------------------------------------------------------------
  // Memory Access Widths / Types (from funct3, 3-bit encoding)
  // --------------------------------------------------------------------------
  localparam logic [2:0] MEM_BYTE   = 3'b000; // LB / SB
  localparam logic [2:0] MEM_HALF   = 3'b001; // LH / SH
  localparam logic [2:0] MEM_WORD   = 3'b010; // LW / SW
  localparam logic [2:0] MEM_BYTE_U = 3'b100; // LBU
  localparam logic [2:0] MEM_HALF_U = 3'b101; // LHU

  // --------------------------------------------------------------------------
  // Forwarding Source Multiplexer Selects (2-bit encoding)
  // --------------------------------------------------------------------------
  localparam logic [1:0] FWD_NONE   = 2'b00; // Use ID/EX register value
  localparam logic [1:0] FWD_EX_MEM = 2'b01; // Forward from EX/MEM stage
  localparam logic [1:0] FWD_MEM_WB = 2'b10; // Forward from MEM/WB stage

  // --------------------------------------------------------------------------
  // Branch Predictor 2-bit Saturating Counter States
  // --------------------------------------------------------------------------
  localparam logic [1:0] BHT_STRONGLY_NOT_TAKEN = 2'b00;
  localparam logic [1:0] BHT_WEAKLY_NOT_TAKEN   = 2'b01;
  localparam logic [1:0] BHT_WEAKLY_TAKEN       = 2'b10;
  localparam logic [1:0] BHT_STRONGLY_TAKEN     = 2'b11;

  // --------------------------------------------------------------------------
  // RISC-V Synchronous Exception Causes (mcause[31]=0)
  // --------------------------------------------------------------------------
  localparam logic [31:0] CAUSE_LOAD_ACCESS_FAULT  = 32'd5;
  localparam logic [31:0] CAUSE_STORE_ACCESS_FAULT = 32'd7;

  // --------------------------------------------------------------------------
  // NOP Instruction Constant (addi x0, x0, 0)
  // --------------------------------------------------------------------------
  localparam logic [31:0] RV32I_NOP = 32'h00000013;

endpackage: rv32i_types_pkg
