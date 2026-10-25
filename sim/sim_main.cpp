// ==============================================================================
// File: sim_main.cpp
// Description: Verilator C++ testbench harness with VCD tracing and cycle control.
// ==============================================================================

#include <iostream>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vtb_rv32i_top.h"

vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    auto top = std::make_unique<Vtb_rv32i_top>();
    auto tfp = std::make_unique<VerilatedVcdC>();

    top->trace(tfp.get(), 99);
    tfp->open("rv32i_trace_verilator.vcd");

    std::cout << "[VERILATOR] Starting simulation..." << std::endl;

    while (!Verilated::gotFinish() && main_time < 20000) {
        top->eval();
        tfp->dump(main_time);
        main_time += 5;
    }

    top->final();
    tfp->close();

    std::cout << "[VERILATOR] Simulation finished at " << main_time << " ticks." << std::endl;
    return 0;
}
