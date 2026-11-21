// =============================================================================
// Module      : cdc_reset_sync
// Project     : Parameterized Dual-Clock Asynchronous FIFO (async-fifo-cdc)
// Author      : Anton Magdy (@AntonMagdy111)
// License     : Apache-2.0
// Description : Asynchronous-Assert, Synchronous-Deassert Reset Synchronizer.
//               Asserts active-low reset immediately when arst_n falls, and
//               releases srst_n cleanly on posedge clk after STAGES cycles to
//               eliminate reset recovery/removal metastability.
// =============================================================================

`timescale 1ns / 1ps

module cdc_reset_sync #(
    parameter int STAGES = 2
) (
    input  logic clk,
    input  logic arst_n,
    output logic srst_n
);

    initial begin
        if (STAGES < 2) begin
            $error("cdc_reset_sync: STAGES must be >= 2 (got %0d)", STAGES);
        end
    end

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO", preserve,
       altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *)
    logic [STAGES-1:0] rst_pipe;

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            rst_pipe <= '0;
        end else begin
            rst_pipe <= {rst_pipe[STAGES-2:0], 1'b1};
        end
    end

    assign srst_n = rst_pipe[STAGES-1];

endmodule
