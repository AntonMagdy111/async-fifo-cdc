// =============================================================================
// Module      : async_fifo
// Project     : Parameterized Dual-Clock Asynchronous FIFO (async-fifo-cdc)
// Author      : Anton Magdy (@AntonMagdy111)
// License     : Apache-2.0
// Description : Production-grade Dual-Clock Asynchronous FIFO using Gray-code
//               pointer crossing (Clifford Cummings architecture) enhanced with:
//                 - Parameterized DATA_WIDTH, ADDR_WIDTH (DEPTH = 2^ADDR_WIDTH),
//                   SYNC_STAGES (>=2), ALMOST_FULL_THRESH, ALMOST_EMPTY_THRESH
//                 - Built-in async-assert / sync-deassert reset synchronizers
//                   for both wclk and rclk domains (bypassable via USE_RESET_SYNC)
//                 - Conservative write-domain & read-domain fill levels
//                 - Registered full, empty, almost-full, and almost-empty flags
//                 - Safe overflow / underflow protection + diagnostic flags
// =============================================================================

`timescale 1ns / 1ps

module async_fifo #(
    parameter int DATA_WIDTH          = 32,
    parameter int ADDR_WIDTH          = 4,
    parameter int SYNC_STAGES         = 2,
    parameter int ALMOST_FULL_THRESH  = 2,  // Asserts walmost_full when free slots <= THRESH
    parameter int ALMOST_EMPTY_THRESH = 2,  // Asserts ralmost_empty when used slots <= THRESH
    parameter bit USE_RESET_SYNC      = 1'b1
) (
    // Write Clock Domain
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,
    output logic                  walmost_full,
    output logic [ADDR_WIDTH:0]   wlevel,
    output logic                  woverflow,

    // Read Clock Domain
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty,
    output logic                  ralmost_empty,
    output logic [ADDR_WIDTH:0]   rlevel,
    output logic                  runderflow
);

    localparam int DEPTH = (1 << ADDR_WIDTH);
    localparam int PTR_W = ADDR_WIDTH + 1;

    localparam logic [ADDR_WIDTH:0] DEPTH_U      = DEPTH[ADDR_WIDTH:0];
    localparam logic [ADDR_WIDTH:0] AF_THRESH_U  = ALMOST_FULL_THRESH[ADDR_WIDTH:0];
    localparam logic [ADDR_WIDTH:0] AE_THRESH_U  = ALMOST_EMPTY_THRESH[ADDR_WIDTH:0];
    localparam logic [ADDR_WIDTH:0] AF_LIMIT_U   = DEPTH_U - AF_THRESH_U;

    // Parameter sanity checks
    initial begin
        if (ADDR_WIDTH < 2)
            $error("async_fifo: ADDR_WIDTH must be >= 2 (got %0d)", ADDR_WIDTH);
        if (SYNC_STAGES < 2)
            $error("async_fifo: SYNC_STAGES must be >= 2 (got %0d)", SYNC_STAGES);
        if (ALMOST_FULL_THRESH < 0 || ALMOST_FULL_THRESH >= DEPTH)
            $error("async_fifo: ALMOST_FULL_THRESH (%0d) out of range [0, %0d)", ALMOST_FULL_THRESH, DEPTH);
        if (ALMOST_EMPTY_THRESH < 0 || ALMOST_EMPTY_THRESH >= DEPTH)
            $error("async_fifo: ALMOST_EMPTY_THRESH (%0d) out of range [0, %0d)", ALMOST_EMPTY_THRESH, DEPTH);
    end

    // =========================================================================
    // Helper Functions: Binary <-> Gray Conversion
    // =========================================================================
    function automatic logic [ADDR_WIDTH:0] bin2gray(input logic [ADDR_WIDTH:0] bin);
        bin2gray = (bin >> 1) ^ bin;
    endfunction

    function automatic logic [ADDR_WIDTH:0] gray2bin(input logic [ADDR_WIDTH:0] gray);
        logic [ADDR_WIDTH:0] bin_tmp;
        integer k;
        begin
            bin_tmp[ADDR_WIDTH] = gray[ADDR_WIDTH];
            for (k = ADDR_WIDTH - 1; k >= 0; k = k - 1) begin
                bin_tmp[k] = bin_tmp[k + 1] ^ gray[k];
            end
            gray2bin = bin_tmp;
        end
    endfunction

    // =========================================================================
    // Domain Reset Synchronizers (Async-Assert, Sync-Deassert)
    // =========================================================================
    logic wrst_sync_n;
    logic rrst_sync_n;

    generate
        if (USE_RESET_SYNC) begin : gen_rst_sync
            cdc_reset_sync #(
                .STAGES (SYNC_STAGES)
            ) u_wrst_sync (
                .clk    (wclk),
                .arst_n (wrst_n),
                .srst_n (wrst_sync_n)
            );

            cdc_reset_sync #(
                .STAGES (SYNC_STAGES)
            ) u_rrst_sync (
                .clk    (rclk),
                .arst_n (rrst_n),
                .srst_n (rrst_sync_n)
            );
        end else begin : gen_rst_direct
            assign wrst_sync_n = wrst_n;
            assign rrst_sync_n = rrst_n;
        end
    endgenerate

    // =========================================================================
    // Internal Signals & Synchronized Pointers
    // =========================================================================
    logic [ADDR_WIDTH:0]   wbin, wbin_next;
    logic [ADDR_WIDTH:0]   wptr, wgray_next;
    logic [ADDR_WIDTH:0]   wq2_rptr;
    logic [ADDR_WIDTH:0]   wq2_rbin;
    logic [ADDR_WIDTH:0]   wlevel_next;
    logic [ADDR_WIDTH-1:0] waddr;
    logic                  w_en;
    logic                  wfull_val;
    logic                  walmost_full_val;

    logic [ADDR_WIDTH:0]   rbin, rbin_next;
    logic [ADDR_WIDTH:0]   rptr, rgray_next;
    logic [ADDR_WIDTH:0]   rq2_wptr;
    logic [ADDR_WIDTH:0]   rq2_wbin;
    logic [ADDR_WIDTH:0]   rlevel_next;
    logic [ADDR_WIDTH-1:0] raddr;
    logic                  r_en;
    logic                  rempty_val;
    logic                  ralmost_empty_val;

    // =========================================================================
    // Cross-Domain Gray-Code Pointer Synchronizers
    // =========================================================================
`ifdef FORMAL
    logic [ADDR_WIDTH:0]   f_wq1_rptr_raw;
    logic [ADDR_WIDTH:0]   f_rq1_wptr_raw;
    (* anyconst *) logic [ADDR_WIDTH:0] f_const_addr;
    logic [ADDR_WIDTH:0]   f_const_next;
    logic [DATA_WIDTH-1:0] f_mem_data1;
    logic [DATA_WIDTH-1:0] f_mem_data2;
    assign f_const_next = f_const_addr + {{ADDR_WIDTH{1'b0}}, 1'b1};
`endif

    // Sync read Gray pointer (rptr) into write clock domain (wclk)
    cdc_sync_2ff #(
        .WIDTH     (PTR_W),
        .STAGES    (SYNC_STAGES),
        .RESET_VAL ('0)
    ) u_sync_r2w (
        .clk   (wclk),
        .rst_n (wrst_sync_n),
        .d_in  (rptr),
        .q_out (wq2_rptr)
`ifdef FORMAL
        , .f_stage0_q (f_wq1_rptr_raw)
`endif
    );

    // Sync write Gray pointer (wptr) into read clock domain (rclk)
    cdc_sync_2ff #(
        .WIDTH     (PTR_W),
        .STAGES    (SYNC_STAGES),
        .RESET_VAL ('0)
    ) u_sync_w2r (
        .clk   (rclk),
        .rst_n (rrst_sync_n),
        .d_in  (wptr),
        .q_out (rq2_wptr)
`ifdef FORMAL
        , .f_stage0_q (f_rq1_wptr_raw)
`endif
    );

    // =========================================================================
    // Dual-Port Storage Array
    // =========================================================================
    assign waddr = wbin[ADDR_WIDTH-1:0];
    assign raddr = rbin[ADDR_WIDTH-1:0];
    assign w_en  = winc && !wfull;
    assign r_en  = rinc && !rempty;

    fifo_mem_dp #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_fifo_mem (
        .wclk   (wclk),
        .wclken (w_en),
        .waddr  (waddr),
        .wdata  (wdata),
        .raddr  (raddr),
        .rdata  (rdata)
`ifdef FORMAL
        , .f_peek_addr1 (f_const_addr[ADDR_WIDTH-1:0])
        , .f_peek_addr2 (f_const_next[ADDR_WIDTH-1:0])
        , .f_peek_data1 (f_mem_data1)
        , .f_peek_data2 (f_mem_data2)
`endif
    );

    // =========================================================================
    // Write Clock Domain Pointer, Full, Almost-Full & Level Logic
    // =========================================================================
    assign wbin_next  = wbin + {{ADDR_WIDTH{1'b0}}, w_en};
    assign wgray_next = bin2gray(wbin_next);

    // Direct Gray comparison for wfull keeps critical path off gray2bin XOR tree
    assign wfull_val = (wgray_next == {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1],
                                        wq2_rptr[ADDR_WIDTH-2:0]});

    // Conservative write-domain occupancy (wlevel >= true occupancy)
    assign wq2_rbin         = gray2bin(wq2_rptr);
    assign wlevel_next      = wbin_next - wq2_rbin;
    assign walmost_full_val = (wlevel_next >= AF_LIMIT_U);

    always_ff @(posedge wclk or negedge wrst_sync_n) begin
        if (!wrst_sync_n) begin
            wbin         <= '0;
            wptr         <= '0;
            wfull        <= 1'b0;
            walmost_full <= 1'b0;
            wlevel       <= '0;
            woverflow    <= 1'b0;
        end else begin
            wbin         <= wbin_next;
            wptr         <= wgray_next;
            wfull        <= wfull_val;
            walmost_full <= walmost_full_val;
            wlevel       <= wlevel_next;
            woverflow    <= winc && wfull;
        end
    end

    // =========================================================================
    // Read Clock Domain Pointer, Empty, Almost-Empty & Level Logic
    // =========================================================================
    assign rbin_next  = rbin + {{ADDR_WIDTH{1'b0}}, r_en};
    assign rgray_next = bin2gray(rbin_next);

    // Direct Gray comparison for rempty keeps critical path minimal
    assign rempty_val = (rgray_next == rq2_wptr);

    // Conservative read-domain occupancy (rlevel <= true occupancy)
    assign rq2_wbin          = gray2bin(rq2_wptr);
    assign rlevel_next       = rq2_wbin - rbin_next;
    assign ralmost_empty_val = (rlevel_next <= AE_THRESH_U);

    always_ff @(posedge rclk or negedge rrst_sync_n) begin
        if (!rrst_sync_n) begin
            rbin          <= '0;
            rptr          <= '0;
            rempty        <= 1'b1;
            ralmost_empty <= 1'b1;
            rlevel        <= '0;
            runderflow    <= 1'b0;
        end else begin
            rbin          <= rbin_next;
            rptr          <= rgray_next;
            rempty        <= rempty_val;
            ralmost_empty <= ralmost_empty_val;
            rlevel        <= rlevel_next;
            runderflow    <= rinc && rempty;
        end
    end

    // =========================================================================
    // Formal Verification Properties (SymbiYosys / SMTBMC Multiclock)
    // Proves unboundedly via k-induction:
    //   1. Zero overflow (f_fill <= DEPTH, full prevents write)
    //   2. Zero underflow (empty prevents read)
    //   3. Zero data loss & strict FIFO ordering (2-value symbolic contract)
    //   4. Gray-code single-bit CDC transition property
    //   5. Conservative write/read fill level & almost-full/empty bounds
    // =========================================================================
`ifdef FORMAL
    // Formal clock-edge tracking on global clock (SymbiYosys multiclock)
    (* gclk *) logic f_gclk;

    logic                  f_past_valid;
    logic                  f_prev_wclk, f_prev_rclk;
    logic                  f_prev_wrst_n, f_prev_rrst_n;
    logic [ADDR_WIDTH:0]   f_prev_wptr, f_prev_rptr;

    initial f_past_valid  = 1'b0;
    initial f_prev_wclk   = 1'b0;
    initial f_prev_rclk   = 1'b0;
    initial f_prev_wrst_n = 1'b0;
    initial f_prev_rrst_n = 1'b0;
    initial f_prev_wptr   = '0;
    initial f_prev_rptr   = '0;

    always @(posedge f_gclk) begin
        f_past_valid  <= 1'b1;
        f_prev_wclk   <= wclk;
        f_prev_rclk   <= rclk;
        f_prev_wrst_n <= wrst_sync_n;
        f_prev_rrst_n <= rrst_sync_n;
        f_prev_wptr   <= wptr;
        f_prev_rptr   <= rptr;
    end

    // Initial synchronized reset assumptions for clean multiclock induction
    initial assume (!wrst_n && !rrst_n);
    always @(posedge f_gclk) begin
        // Keep domain resets coupled during formal proof
        assume (wrst_n == rrst_n);
        if (!f_past_valid) begin
            assume (!wrst_n && !rrst_n);
        end
    end

    // Edge detectors on global clock
    logic f_wclk_rose, f_rclk_rose;
    assign f_wclk_rose = f_past_valid && wclk && !f_prev_wclk;
    assign f_rclk_rose = f_past_valid && rclk && !f_prev_rclk;

    // Internal synchronizer taps (binary equivalents for ring invariant proof)
    logic [ADDR_WIDTH:0]   f_wq1_rbin, f_wq2_rbin;
    logic [ADDR_WIDTH:0]   f_rq1_wbin, f_rq2_wbin;
    logic [ADDR_WIDTH:0]   f_fill;
    logic [ADDR_WIDTH:0]   f_d0, f_d1, f_d2, f_d3, f_d4;
    logic [ADDR_WIDTH+3:0] f_ring_sum;
    logic [ADDR_WIDTH:0]   f_wptr_diff, f_rptr_diff;

    assign f_wq1_rbin  = gray2bin(f_wq1_rptr_raw);
    assign f_wq2_rbin  = wq2_rbin;
    assign f_rq1_wbin  = gray2bin(f_rq1_wptr_raw);
    assign f_rq2_wbin  = rq2_wbin;

    assign f_fill = wbin - rbin;

    // Monotonic circular ordering intervals around pointer ring:
    // wq2_rbin <= wq1_rbin <= rbin <= rq2_wbin <= rq1_wbin <= wbin
    assign f_d0 = f_wq1_rbin - f_wq2_rbin;
    assign f_d1 = rbin       - f_wq1_rbin;
    assign f_d2 = f_rq2_wbin - rbin;
    assign f_d3 = f_rq1_wbin - f_rq2_wbin;
    assign f_d4 = wbin       - f_rq1_wbin;
    assign f_ring_sum = {3'b0, f_d0} + {3'b0, f_d1} + {3'b0, f_d2}
                      + {3'b0, f_d3} + {3'b0, f_d4};

    assign f_wptr_diff = wptr ^ f_prev_wptr;
    assign f_rptr_diff = rptr ^ f_prev_rptr;

    // Core safety + k-induction invariants
    always @(posedge f_gclk) begin
        if (f_past_valid && wrst_sync_n && rrst_sync_n) begin
            // Gray <-> Binary pointer consistency
            assert (wptr == bin2gray(wbin));
            assert (rptr == bin2gray(rbin));

            // Ring ordering invariant: proves no overflow/underflow inductively
            assert (f_ring_sum <= {3'b0, DEPTH_U});
            assert (f_fill <= DEPTH_U);
            assert ((wbin - f_wq2_rbin) <= DEPTH_U);

            // Conservative write-domain level and flag guarantees
            assert (wlevel >= (wbin - f_wq2_rbin));
            assert (wlevel >= f_fill);
            assert (wlevel <= DEPTH_U);
            assert (wfull == (wlevel == DEPTH_U));
            assert (walmost_full == (wlevel >= AF_LIMIT_U));
            if (f_fill == DEPTH_U) begin
                assert (wfull == 1'b1);
            end
            if ((DEPTH_U - f_fill) <= AF_THRESH_U) begin
                assert (walmost_full == 1'b1);
            end

            // Conservative read-domain level and flag guarantees
            assert (rlevel <= f_d2);
            assert (rlevel <= f_fill);
            assert (rempty == (rlevel == '0));
            assert (ralmost_empty == (rlevel <= AE_THRESH_U));
            if (f_fill == '0) begin
                assert (rempty == 1'b1);
            end
            if (f_fill <= AE_THRESH_U) begin
                assert (ralmost_empty == 1'b1);
            end
        end

        // Gray-code CDC safety: Hamming weight of (ptr ^ prev_ptr) <= 1
        // Identity: (x & (x - 1)) == 0 iff popcount(x) <= 1
        if (f_past_valid && wrst_sync_n && f_prev_wrst_n) begin
            assert ((f_wptr_diff & (f_wptr_diff - {{ADDR_WIDTH{1'b0}}, 1'b1})) == '0);
        end
        if (f_past_valid && rrst_sync_n && f_prev_rrst_n) begin
            assert ((f_rptr_diff & (f_rptr_diff - {{ADDR_WIDTH{1'b0}}, 1'b1})) == '0);
        end
    end

    // =========================================================================
    // Two-Value Symbolic FIFO Data Integrity & Ordering Contract
    // Shadow tags are clocked on posedge wclk (exact same clk2fflogic phase as
    // wbin and u_fifo_mem.mem), proving zero data loss, zero overwrite, and
    // strict FIFO ordering for all adjacent arbitrary addresses & payloads.
    // =========================================================================
    logic                  f_addr1_in_fifo, f_addr2_in_fifo;
    logic                  f_tag1_valid, f_tag2_valid;
    logic [DATA_WIDTH-1:0] f_tag1_data, f_tag2_data;

    assign f_addr1_in_fifo = ((f_const_addr - rbin) < f_fill);
    assign f_addr2_in_fifo = ((f_const_next - rbin) < f_fill);

    always_ff @(posedge wclk or negedge wrst_sync_n) begin
        if (!wrst_sync_n) begin
            f_tag1_valid <= 1'b0;
            f_tag2_valid <= 1'b0;
            f_tag1_data  <= '0;
            f_tag2_data  <= '0;
        end else if (w_en) begin
            if (wbin == f_const_addr) begin
                f_tag1_valid <= 1'b1;
                f_tag1_data  <= wdata;
            end
            if (wbin == f_const_next) begin
                f_tag2_valid <= 1'b1;
                f_tag2_data  <= wdata;
            end
        end
    end

    // Unbounded k-induction data integrity & ordering assertions
    always @(posedge f_gclk) begin
        if (f_past_valid && wrst_sync_n && rrst_sync_n) begin
            if (f_addr1_in_fifo) begin
                assert (f_tag1_valid);
                assert (f_mem_data1 == f_tag1_data);
                if (rbin == f_const_addr) begin
                    assert (rdata == f_tag1_data);
                end
            end
            if (f_addr2_in_fifo) begin
                assert (f_tag2_valid);
                assert (f_mem_data2 == f_tag2_data);
                if (rbin == f_const_next) begin
                    assert (rdata == f_tag2_data);
                end
            end
        end
    end

    // Cover properties to ensure non-vacuous reachability
    always @(posedge f_gclk) begin
        if (f_past_valid && wrst_sync_n && rrst_sync_n) begin
            cover (wfull);
            cover (walmost_full && !wfull);
            cover (ralmost_empty && !rempty);
            cover (woverflow);
            cover (runderflow);
            cover (f_addr1_in_fifo && f_addr2_in_fifo);
            cover (f_addr2_in_fifo && !f_addr1_in_fifo && (rbin == f_const_next));
            cover (wbin[ADDR_WIDTH] == 1'b1 && rbin[ADDR_WIDTH] == 1'b1 && rempty);
        end
    end
`endif

endmodule
