// =============================================================================
// Module      : cdc_sync_2ff
// Project     : Parameterized Dual-Clock Asynchronous FIFO (async-fifo-cdc)
// Author      : Anton Magdy (@AntonMagdy111)
// License     : Apache-2.0
// Description : Parameterized multi-stage flip-flop CDC synchronizer with
//               explicit synthesis attributes for Intel Quartus & Xilinx Vivado
//               to prevent shift-register packing and preserve metastability
//               MTBF placement.
// =============================================================================

`timescale 1ns / 1ps

module cdc_sync_2ff #(
    parameter int WIDTH  = 5,
    parameter int STAGES = 2,
    parameter logic [WIDTH-1:0] RESET_VAL = '0
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] d_in,
    output logic [WIDTH-1:0] q_out
`ifdef FORMAL
    , output logic [WIDTH-1:0] f_stage0_q
`endif
);

    // Enforce minimum 2-stage synchronization for CDC metastability resolution
    initial begin
        if (STAGES < 2) begin
            $error("cdc_sync_2ff: STAGES must be >= 2 (got %0d)", STAGES);
        end
    end

    // Synthesis attributes:
    //  - ASYNC_REG (Xilinx/Vivado): places flops in same slice, disables SRL inference
    //  - preserve / altera_attribute (Intel/Quartus): marks as CDC synchronizer chain
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO", preserve,
       altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *)
    logic [WIDTH-1:0] sync_pipe [0:STAGES-1];

    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < STAGES; i = i + 1) begin
                sync_pipe[i] <= RESET_VAL;
            end
        end else begin
            sync_pipe[0] <= d_in;
            for (i = 1; i < STAGES; i = i + 1) begin
                sync_pipe[i] <= sync_pipe[i-1];
            end
        end
    end

    assign q_out = sync_pipe[STAGES-1];
`ifdef FORMAL
    assign f_stage0_q = sync_pipe[0];
`endif

endmodule
