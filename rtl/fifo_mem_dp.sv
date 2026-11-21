// =============================================================================
// Module      : fifo_mem_dp
// Project     : Parameterized Dual-Clock Asynchronous FIFO (async-fifo-cdc)
// Author      : Anton Magdy (@AntonMagdy111)
// License     : Apache-2.0
// Description : Parameterized Dual-Port FIFO Storage Array.
//               Synchronous write port in wclk domain, combinational/show-ahead
//               read port indexed by raddr (classic Cummings FWFT architecture).
//               Cleanly separated for FPGA MLAB/distributed RAM inference or
//               easy swap to foundry dual-port SRAM macros.
// =============================================================================

`timescale 1ns / 1ps

module fifo_mem_dp #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  wclk,
    input  logic                  wclken,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
`ifdef FORMAL
    , input  logic [ADDR_WIDTH-1:0] f_peek_addr1
    , input  logic [ADDR_WIDTH-1:0] f_peek_addr2
    , output logic [DATA_WIDTH-1:0] f_peek_data1
    , output logic [DATA_WIDTH-1:0] f_peek_data2
`endif
);

    localparam int DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge wclk) begin
        if (wclken) begin
            mem[waddr] <= wdata;
        end
    end

    assign rdata = mem[raddr];
`ifdef FORMAL
    assign f_peek_data1 = mem[f_peek_addr1];
    assign f_peek_data2 = mem[f_peek_addr2];
`endif

endmodule
