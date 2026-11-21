// =============================================================================
// Module      : async_fifo_sva
// Project     : Parameterized Dual-Clock Asynchronous FIFO (async-fifo-cdc)
// Author      : Anton Magdy (@AntonMagdy111)
// License     : Apache-2.0
// Description : Bindable SystemVerilog Assertions (SVA) & Functional Coverage
//               companion for commercial simulators (ModelSim / Questa / VCS /
//               Xcelium) and formal property checkers (JasperGold / PropCheck).
// =============================================================================

`timescale 1ns / 1ps

module async_fifo_sva #(
    parameter int DATA_WIDTH          = 32,
    parameter int ADDR_WIDTH          = 4,
    parameter int ALMOST_FULL_THRESH  = 2,
    parameter int ALMOST_EMPTY_THRESH = 2
) (
    input logic                  wclk,
    input logic                  wrst_sync_n,
    input logic                  winc,
    input logic                  wfull,
    input logic                  walmost_full,
    input logic [ADDR_WIDTH:0]   wlevel,
    input logic                  woverflow,
    input logic [ADDR_WIDTH:0]   wbin,
    input logic [ADDR_WIDTH:0]   wptr,

    input logic                  rclk,
    input logic                  rrst_sync_n,
    input logic                  rinc,
    input logic                  rempty,
    input logic                  ralmost_empty,
    input logic [ADDR_WIDTH:0]   rlevel,
    input logic                  runderflow,
    input logic [ADDR_WIDTH:0]   rbin,
    input logic [ADDR_WIDTH:0]   rptr
);

    localparam int DEPTH = (1 << ADDR_WIDTH);
    localparam logic [ADDR_WIDTH:0] DEPTH_U    = DEPTH[ADDR_WIDTH:0];
    localparam logic [ADDR_WIDTH:0] AF_LIMIT_U = DEPTH_U - ALMOST_FULL_THRESH[ADDR_WIDTH:0];
    localparam logic [ADDR_WIDTH:0] AE_THRESH_U = ALMOST_EMPTY_THRESH[ADDR_WIDTH:0];

    // Helper: Hamming weight <= 1 check
    function automatic logic one_bit_or_zero(input logic [ADDR_WIDTH:0] diff);
        return ((diff & (diff - {{ADDR_WIDTH{1'b0}}, 1'b1})) == '0);
    endfunction

    // =========================================================================
    // Write Domain Concurrent Assertions
    // =========================================================================
    // 1. Gray-code single-bit transition on wptr
    property p_wptr_gray_step;
        @(posedge wclk) disable iff (!wrst_sync_n)
        one_bit_or_zero(wptr ^ $past(wptr));
    endproperty
    ast_wptr_gray_step : assert property (p_wptr_gray_step)
        else $error("[SVA] Write Gray pointer changed by >1 bit! prev=%b curr=%b", $past(wptr), wptr);

    // 2. Write pointer must never advance when wfull is asserted
    property p_no_write_when_full;
        @(posedge wclk) disable iff (!wrst_sync_n)
        (wfull) |=> ($stable(wbin) && $stable(wptr));
    endproperty
    ast_no_write_when_full : assert property (p_no_write_when_full)
        else $error("[SVA] Write pointer incremented while wfull was asserted!");

    // 3. Overflow diagnostic flag accurately signals blocked write
    property p_woverflow_accurate;
        @(posedge wclk) disable iff (!wrst_sync_n)
        (winc && wfull) |=> woverflow;
    endproperty
    ast_woverflow_accurate : assert property (p_woverflow_accurate)
        else $error("[SVA] woverflow failed to assert after write attempt on full FIFO!");

    // 4. Write level bounds & consistency with wfull / walmost_full
    property p_wlevel_bounds;
        @(posedge wclk) disable iff (!wrst_sync_n)
        (wlevel <= DEPTH_U) && (wfull == (wlevel == DEPTH_U)) && (walmost_full == (wlevel >= AF_LIMIT_U));
    endproperty
    ast_wlevel_bounds : assert property (p_wlevel_bounds)
        else $error("[SVA] wlevel/wfull/walmost_full mismatch: wlevel=%0d wfull=%b af=%b", wlevel, wfull, walmost_full);

    // 5. No X/Z on write-domain control outputs
    property p_no_x_write_ctrl;
        @(posedge wclk) disable iff (!wrst_sync_n)
        !$isunknown({wfull, walmost_full, woverflow, wlevel, wptr});
    endproperty
    ast_no_x_write_ctrl : assert property (p_no_x_write_ctrl)
        else $error("[SVA] Unknown (X/Z) detected on write-domain outputs!");

    // =========================================================================
    // Read Domain Concurrent Assertions
    // =========================================================================
    // 6. Gray-code single-bit transition on rptr
    property p_rptr_gray_step;
        @(posedge rclk) disable iff (!rrst_sync_n)
        one_bit_or_zero(rptr ^ $past(rptr));
    endproperty
    ast_rptr_gray_step : assert property (p_rptr_gray_step)
        else $error("[SVA] Read Gray pointer changed by >1 bit! prev=%b curr=%b", $past(rptr), rptr);

    // 7. Read pointer must never advance when rempty is asserted
    property p_no_read_when_empty;
        @(posedge rclk) disable iff (!rrst_sync_n)
        (rempty) |=> ($stable(rbin) && $stable(rptr));
    endproperty
    ast_no_read_when_empty : assert property (p_no_read_when_empty)
        else $error("[SVA] Read pointer incremented while rempty was asserted!");

    // 8. Underflow diagnostic flag accurately signals blocked read
    property p_runderflow_accurate;
        @(posedge rclk) disable iff (!rrst_sync_n)
        (rinc && rempty) |=> runderflow;
    endproperty
    ast_runderflow_accurate : assert property (p_runderflow_accurate)
        else $error("[SVA] runderflow failed to assert after read attempt on empty FIFO!");

    // 9. Read level bounds & consistency with rempty / ralmost_empty
    property p_rlevel_bounds;
        @(posedge rclk) disable iff (!rrst_sync_n)
        (rlevel <= DEPTH_U) && (rempty == (rlevel == '0)) && (ralmost_empty == (rlevel <= AE_THRESH_U));
    endproperty
    ast_rlevel_bounds : assert property (p_rlevel_bounds)
        else $error("[SVA] rlevel/rempty/ralmost_empty mismatch: rlevel=%0d rempty=%b ae=%b", rlevel, rempty, ralmost_empty);

    // 10. No X/Z on read-domain control outputs
    property p_no_x_read_ctrl;
        @(posedge rclk) disable iff (!rrst_sync_n)
        !$isunknown({rempty, ralmost_empty, runderflow, rlevel, rptr});
    endproperty
    ast_no_x_read_ctrl : assert property (p_no_x_read_ctrl)
        else $error("[SVA] Unknown (X/Z) detected on read-domain outputs!");

    // =========================================================================
    // Cross-Domain Instantaneous Safety Check (Global View)
    // =========================================================================
    logic [ADDR_WIDTH:0] true_fill;
    assign true_fill = wbin - rbin;

    always @(posedge wclk) begin
        if (wrst_sync_n && rrst_sync_n) begin
            if (true_fill > DEPTH_U) begin
                $error("[SVA-CDC] FIFO OVERFLOW! true_fill=%0d > DEPTH=%0d", true_fill, DEPTH);
            end
        end
    end

endmodule
