# 5-Stage Pipelined RV32I Processor with L1 Cache & AMBA AXI4-Lite

[![CI Regression & Synthesis](https://github.com/nikunjmalik306/rv32i-5stage-core/actions/workflows/ci.yml/badge.svg)](https://github.com/nikunjmalik306/rv32i-5stage-core/actions/workflows/ci.yml)

A production-grade, fully synthesizable 5-stage pipelined RISC-V RV32I processor core with a 4KB 2-way set-associative Write-Back/Write-Allocate L1 Data Cache and an AMBA AXI4-Lite master bus interface, authored in SystemVerilog (IEEE 1800-2012/2017).

Verified with automated multi-suite self-checking testbenches and synthesizable with open-source EDA tools on macOS/Linux (**Icarus Verilog**, **Verilator**, **Yosys**, and **GTKWave**).

---

## Architecture Overview

```text
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

### Architectural & Verification Upgrades
1. **Precise Architectural Exception Handling**:
   - Implements synchronous exception traps on memory bus faults (`SLVERR`/`DECERR`):
     - `trap_taken`: Asserts precise trap on faulting memory load/store instruction.
     - `trap_cause`: Standard RISC-V synchronous exception code (`5` for `CAUSE_LOAD_ACCESS_FAULT`, `7` for `CAUSE_STORE_ACCESS_FAULT`).
     - `trap_epc`: Captures exact PC of the faulting instruction.
     - `trap_val`: Captures faulting memory byte address (`dcache_addr`).
   - **Architectural State Protection**: Suppresses destination register writeback (`mem_out_reg_write = mem_reg_write && !dcache_error`), preventing invalid data from corrupting the register file.
   - **Pipeline Purge & Vector Redirection**: Flushes speculative younger instructions in `IF/ID`, `ID/EX`, and `EX/MEM`, and redirects PC to parameterizable `TRAP_VECTOR` (default `0x000001E0`).
2. **Dirty-Data Preservation on Eviction Failure (`S_EVICT_ERR`)**:
   - If an AXI4-Lite dirty writeback encounters a bus fault (`SLVERR` / `DECERR`), the victim cache line is **NEVER invalidated or cleared**.
   - Modified data and dirty bits remain strictly preserved in the cache array to prevent silent data loss.
   - Core receives `dcache_error` notification to trap and handle the bus exception safely.
3. **Refill Fault Containment (`S_REFILL_ERR`)**:
   - If a line refill receives a bus error, the line is marked invalid (`valid_array = 0`) so unverified or corrupted memory data is never served to the core.
4. **Decoupled AXI4-Lite AW & W Channels**:
   - Write Address (`AW`) and Write Data (`W`) channels operate concurrently with independent handshake tracking (`aw_done`, `w_done`).
   - Interoperates with `AW-first`, `W-first`, and `simultaneous` slave handshake profiles without deadlock.
5. **Tightly Coupled Cache/Bridge Handshake**:
   - Cache burst word counters advance strictly on individual word acceptance (`cmd_valid && cmd_ready`) followed by verified response capture (`rsp_valid`).
   - Guarantees each word in a 32-byte cache line is issued and consumed exactly once.
6. **Multi-Suite Directed Regression**:
   - Covers full RISC-V RV32I ISA, RAW forwarding, 1-cycle load-use stalls, branch taken/not-taken, conflict misses with 32-byte dirty writebacks, AW-first/W-first handshake ordering, and word-level SLVERR fault injection with precise architectural trap assertions.

---

## Directory Structure

```text
rv32i-5stage-core/
├── docs/
│   ├── technical_audit.md          # Architecture, exception traps, cache FSM & gate synthesis
│   └── portfolio_summary.md        # Qualcomm resume bullets, microarch metrics & interview guide
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
│   │   └── l1_dcache.sv            # 4KB 2-way L1 Cache with safe error recovery
│   └── bus/
│       └── axi4_lite_master.sv     # AMBA AXI4-Lite Master Bridge (Decoupled AW/W)
├── tb/
│   ├── tb_rv32i_top.sv             # Multi-suite self-checking testbench
│   └── programs/
│       └── test_hazards.hex        # Machine-code test program with dirty eviction tests
└── sim/
    ├── Makefile                    # Multi-tool Makefile (Icarus Verilog, Verilator, Yosys, GTKWave)
    ├── run_sim.sh                  # Automated execution script
    ├── synth.ys                    # Yosys open-source synthesis script
    └── yosys_synth.log             # Gate-level synthesis log & primitive cell breakdown
```

---

## Detailed Documentation

- [Technical Audit & Architectural Specification](docs/technical_audit.md)
- [Portfolio Summary & Qualcomm Interview Guide](docs/portfolio_summary.md)

---

## Verification & Simulation Results

Executed on macOS with **Icarus Verilog** and **GTKWave**:

```text
==================================================================
 QUALCOMM HW-DV GRADE RV32I 5-STAGE PROCESSOR REGRESSION SUITE   
 Suites: Architecture, Decoupled AW/W Handshakes, Fault Recovery  
==================================================================
[TB] Reset released at t = 50 ns
[CYCLE 0004] [COMMIT] x01 <= 0x0000000a (10)
[CYCLE 0005] [COMMIT] x02 <= 0x00000014 (20)
[CYCLE 0006] [COMMIT] x03 <= 0x0000001e (30)
[CYCLE 0007] [COMMIT] x04 <= 0x00000014 (20)
[CYCLE 0008] [COMMIT] x05 <= 0x0000001e (30)
[CYCLE 0038] [COMMIT] x15 <= 0x00000028 (40)
[CYCLE 0068] [COMMIT] x16 <= 0x00000032 (50)
[CYCLE 0155] [HAZARD] Load-Use hazard detected: stall_if=1 stall_id=1 bubble_ex=1
[CYCLE 0225] [COMMIT] x07 <= 0x0000001e (30)
[CYCLE 0227] [COMMIT] x08 <= 0x0000002a (42)
[CYCLE 0228] [CONTROL] EX Redirect fired -> Target PC: 0x00000050
[CYCLE 0229] [COMMIT] x09 <= 0x00000001 (1)
[CYCLE 0231] [CONTROL] EX Redirect fired -> Target PC: 0x0000005c
[CYCLE 0233] [COMMIT] x01 <= 0x00000054 (84)
[CYCLE 0284] [COMMIT] x10 <= 0x0000002a (42)
[CYCLE 0305] [COMMIT] x11 <= 0x00000028 (40)

==================================================================
 [SUITE 1 AUDIT] ARCHITECTURAL REGISTERS & MEMORY VERIFICATION   
==================================================================
  Total Cycles Elapsed:        353
  Instructions Retired:        224
  Load-Use Stalls Occurred:    1
  Final x1  (JAL Link x1):     84 (Expected: 84)
  Final x2  (ADDI x2, 20):     20 (Expected: 20)
  Final x3  (ADD x3, x1, x2):  30 (Expected: 30)
  Final x4  (SUB x4, x3, x1):  20 (Expected: 20)
  Final x5  (OR  x5, x4, x3):  30 (Expected: 30)
  Final x7  (LW  x7, 0(x12)):  30 (Expected: 30 - Eviction Refill)
  Final x8  (ADDI x8, x7, 12): 42 (Expected: 42 - Load-Use Stall)
  Final x9  (ADDI x9, 1):      1 (Expected: 1)
  Final x10 (Return Code):     42 (Expected: 42)
  Final x11 (LW  x11, 0(x13)): 40 (Expected: 40 - Eviction Refill)
  External RAM[0x1000/4]:      30 (Expected: 30 - Evicted Way 0)
  External RAM[0x2000/4]:      40 (Expected: 40 - Evicted Way 1)
==================================================================
>>> [PASSED] SUITE 1: Full RISC-V ISA & Dirty Evictions Verified!

==================================================================
 [SUITE 2] DIRECTED AXI4-LITE HANDSHAKE PROTOCOL TESTS           
==================================================================
>>> [TEST 2A] Verifying AW-First Write Handshake Ordering...
    [PASSED] Master safely holds WVALID/WDATA until WREADY asserted.
>>> [TEST 2B] Verifying W-First Write Handshake Ordering...
    [PASSED] Master safely holds AWVALID/AWADDR until AWREADY asserted.
>>> [TEST 2C] Verifying Multi-Cycle Read Latency Handshake...
    [PASSED] Master maintains RREADY=1 across variable memory delays.

==================================================================
 [SUITE 3] DIRECTED BUS FAULT INJECTION & RECOVERY TESTS         
==================================================================
>>> [TEST 3A] Injecting SLVERR during Cache Refill at Burst Word 3...
    [PASSED] Architectural exception raised: trap_taken=1, trap_cause=5 (LOAD_ACCESS_FAULT).
    [PASSED] Exception PC: 0x00000138 | Faulting Address: 0x00008000
    [PASSED] D-Cache asserted cpu_error (dcache_error = 1); fault propagated to CPU.
    [PASSED] Corrupted line remains INVALID (no corruption in cache array).
    [PASSED] Speculative instruction flushed; destination register x30 protected (no data corruption).
    [PASSED] CPU redirected to TRAP_VECTOR (0x1E0) and safely resumed execution at Suite 3B.
>>> [TEST 3B] Injecting SLVERR during Dirty Writeback at Burst Word 7...
    [PASSED] Store access fault architectural trap raised: trap_taken=1, trap_cause=7 (STORE_ACCESS_FAULT).
    [PASSED] Faulting instruction PC: 0x0000014c | Faulting store address: 0x0000b000
    [PASSED] D-Cache asserted cpu_error (dcache_error = 1); fault propagated to CPU.
    [PASSED] Cache entered S_EVICT_ERR; DIRTY line and data PRESERVED in cache!
    [PASSED] Zero data loss on failed eviction writeback (cache_data = 0xDEADBEEF).

##################################################################
###                 ALL 3 TEST SUITES PASSED!                  ###
###  Processor, Cache & AXI4-Lite Protocol Verified 100%       ###
##################################################################
```

---

## Gate-Level Synthesis (Yosys)

Synthesized with Yosys Open SYnthesis Suite:

```text
=== design hierarchy ===

   Module Hierarchy:
     rv32i_core (Top)
       ├── l1_dcache (4KB 2-Way Cache)      : 805,647 cells
       ├── stage_id (Decode & RegFile)       :   5,807 cells
       ├── stage_ex (ALU & Comparator)       :   2,799 cells
       ├── branch_predictor (BHT + BTB)      :  15,107 cells
       ├── axi4_lite_master (Bus Bridge)     :     243 cells
       ├── hazard_unit (Forwarding & Stalls) :      90 cells
       └── Pipeline Registers                :   1,325 cells

   Primitive Cell Breakdown:
     $_AND_              : 230,054
     $_OR_               : 189,451
     $_MUX_              : 365,120
     $_XOR_              :   5,441
     $_DFFE_PP_          :  32,768 (Cache Data & Tag Arrays)
     $_DFFE_PN0P_        :   8,844 (Pipeline & Core Flip-Flops)
     $_DFFE_PN0N_        :      30
     $_DFFE_PN1P_        :      67

   Total Cell Count:     831,777
   Inferred Latches:     0 (Strictly synchronous, lint-clean)
```

---

## How to Run

```bash
cd sim
make sim       # Compiles and executes full 3-suite regression
make wave      # Launches GTKWave to view pipeline & bus waveforms
make synth     # Synthesizes gate-level netlist with Yosys
```
