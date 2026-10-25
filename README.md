# 5-Stage Pipelined RV32I Processor with L1 Cache & AMBA AXI4-Lite

A production-grade, fully synthesizable 5-stage pipelined RISC-V RV32I processor core with a 4KB 2-way set-associative Write-Back/Write-Allocate L1 Data Cache and an AMBA AXI4-Lite master bus interface, authored in SystemVerilog (IEEE 1800-2012/2017).

Cleanly verified and synthesizable with open-source EDA tools on macOS/Linux (**Icarus Verilog**, **Verilator**, **Yosys**, and **GTKWave**).

---

## Architecture Overview

```
+===================================================================================================================+
|                                  5-STAGE PIPELINED RV32I CORE ARCHITECTURE                                        |
+===================================================================================================================+
|  [IF Stage]         [ID Stage]             [EX Stage]               [MEM Stage]              [WB Stage]           |
|  +------------+     +----------------+     +------------------+     +------------------+     +-----------------+  |
|  | PC & Next  |     | RV32I Decoder  |     | Forwarding Muxes |     | L1 Data Cache    |     | Writeback Mux   |  |
|  |   PC Mux   |==>==| RegFile (x0-31)|==>==| 32-bit ALU       |==>==| (4KB 2-way WB/WA)|==>==| (ALU vs MemData)|  |
|  | BHT + BTB  |     | Imm Generator  |     | Branch Comparator|     | AXI4-Lite Master |     +--------+--------+  |
|  +------------+     +----------------+     +------------------+     +--------+---------+              |           |
|        ^                     ^                      |                        |                        |           |
|        |                     |                      |                        | (AXI Bus Miss Refill)  |           |
|        |                     +----------------------|------------------------|------------------------+           |
|        |                                            | (Register Writeback & Internal Bypass)                      |
|        +--------------------------------------------+                                                             |
|                   (EX Branch Mispredict / Jump Redirect)                                                          |
|                                                                                                                   |
|  +-------------------------------------------------------------------------------------------------------------+  |
|  | HAZARD UNIT: RAW Forwarding (EX->EX, MEM->EX) | Load-Use Stall (1 cycle) | D-Cache Pipeline Freeze          |  |
|  +-------------------------------------------------------------------------------------------------------------+  |
+===================================================================================================================+
```

### Key Features
1. **Full RV32I Base ISA Support**:
   - R-type: `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`
   - I-type: `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI`, `LB`, `LH`, `LW`, `LBU`, `LHU`, `JALR`
   - S-type: `SB`, `SH`, `SW`
   - B-type: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`
   - U-type: `LUI`, `AUIPC`
   - J-type: `JAL`
2. **Dynamic Branch Prediction**:
   - 64-entry 2-bit Saturating Counter Branch History Table (BHT).
   - Integrated Branch Target Buffer (BTB).
   - Fast 1-cycle speculative fetch with branch misprediction redirect & pipeline flush in EX stage.
3. **Hazard Detection & Forwarding**:
   - Full RAW hazard data forwarding (EX $\rightarrow$ EX, MEM $\rightarrow$ EX).
   - Hardware Load-Use stall detector (stalls IF/ID by 1 cycle, injects bubble into EX).
   - Multi-stage pipeline freeze during D-Cache miss refills and writeback evictions.
4. **L1 Data Cache Subsystem**:
   - 4KB capacity, 2-way set-associative.
   - 32-byte cache line (8 words x 32 bits = 256 bits).
   - Write-Back with Write-Allocate policy and pseudo-LRU replacement.
   - 1-cycle hit latency.
5. **AMBA AXI4-Lite Master Interface**:
   - Connects cache misses / dirty evictions to external system memory.
   - Decoupled address read/write and response channels.

---

## Directory Structure

```text
rv32i_processor/
├── rtl/
│   ├── core/
│   │   ├── rv32i_types_pkg.sv      # Global opcodes, ALU ops, pipeline constants
│   │   ├── branch_predictor.sv     # 64-entry 2-bit saturating counter BHT + BTB
│   │   ├── stage_if.sv             # Instruction Fetch stage + PC logic
│   │   ├── pipe_reg_if_id.sv       # IF/ID Pipeline Register with flush & stall
│   │   ├── stage_id.sv             # Instruction Decode + RegFile + ImmGen + Control
│   │   ├── pipe_reg_id_ex.sv       # ID/EX Pipeline Register with bubble injection
│   │   ├── stage_ex.sv             # Execute Stage + 32-bit ALU + Branch comparator
│   │   ├── hazard_unit.sv          # Forwarding unit + Load-Use hazard detector
│   │   ├── pipe_reg_ex_mem.sv      # EX/MEM Pipeline Register
│   │   ├── stage_mem.sv            # Memory Stage interface with load/store alignment
│   │   ├── pipe_reg_mem_wb.sv      # MEM/WB Pipeline Register
│   │   ├── stage_wb.sv             # Writeback multiplexer
│   │   └── rv32i_core.sv           # Top-level core hooking all stages, cache & bus
│   ├── cache/
│   │   └── l1_dcache.sv            # 4KB 2-way Write-Back/Write-Allocate L1 Cache
│   └── bus/
│       └── axi4_lite_master.sv     # AMBA AXI4-Lite Master Bridge
├── tb/
│   ├── tb_rv32i_top.sv             # Self-checking testbench with AXI memory model & SVAs
│   └── programs/
│       └── test_hazards.hex        # Machine-code test program verifying hazards & cache
└── sim/
    ├── Makefile                    # Build Makefile (Icarus Verilog, Verilator, Yosys, GTKWave)
    ├── run_sim.sh                  # Automated execution script
    ├── synth.ys                    # Yosys open-source synthesis script
    └── sim_main.cpp                # Verilator C++ testbench wrapper
```

---

## Quick Start & Simulation

### Prerequisites (macOS via Homebrew)
```bash
brew install icarus-verilog verilator yosys
brew install --cask gtkwave
```

### Run Simulation with Icarus Verilog
```bash
cd sim
make sim
```
Or execute the automated runner:
```bash
./run_sim.sh
```

### Inspect Waveforms
```bash
make wave
```

### Run Synthesis with Yosys
```bash
make synth
```

---

## License
Apache-2.0 or MIT Open Source License.
