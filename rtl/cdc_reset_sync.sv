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

    // Separate internal shift stages from final reset-driver flop so Verilator
    // (5.055+) sees zero SYNCASYNCNET overlap on the reset net.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO", preserve,
       altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *)
    logic [STAGES-2:0] rst_pipe;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO", preserve,
       altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" *)
    logic srst_reg;

    generate
        if (STAGES == 2) begin : gen_2stage
            always_ff @(posedge clk or negedge arst_n) begin
                if (!arst_n) begin
                    rst_pipe <= '0;
                    srst_reg <= 1'b0;
                end else begin
                    rst_pipe <= 1'b1;
                    srst_reg <= rst_pipe[0];
                end
            end
        end else begin : gen_nstage
            always_ff @(posedge clk or negedge arst_n) begin
                if (!arst_n) begin
                    rst_pipe <= '0;
                    srst_reg <= 1'b0;
                end else begin
                    rst_pipe <= {rst_pipe[STAGES-3:0], 1'b1};
                    srst_reg <= rst_pipe[STAGES-2];
                end
            end
        end
    endgenerate

    assign srst_n = srst_reg;

endmodule
