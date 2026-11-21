// =============================================================================
// Module      : tb_async_fifo
// Project     : Parameterized Dual-Clock Asynchronous FIFO (async-fifo-cdc)
// Author      : Anton Magdy (@AntonMagdy111)
// License     : Apache-2.0
// Description : Comprehensive self-checking SystemVerilog verification suite
//               exercising 6 asynchronous clock-ratio scenarios, threshold
//               checks, overflow/underflow protection, mid-flight asynchronous
//               reset recovery, >20,000 randomized transactions, and coverage.
//               Compatible with ModelSim, Verilator 5 (--timing), and Icarus 12.
// =============================================================================

`timescale 1ns / 1ps

module tb_async_fifo;

    localparam int DATA_WIDTH          = 32;
    localparam int ADDR_WIDTH          = 4;
    localparam int DEPTH               = (1 << ADDR_WIDTH);
    localparam int SYNC_STAGES         = 2;
    localparam int ALMOST_FULL_THRESH  = 3;
    localparam int ALMOST_EMPTY_THRESH = 3;

    // Programmable clock half-periods (ns)
    real wclk_half_ns = 2.5;   // Default 200 MHz
    real rclk_half_ns = 10.0;  // Default 50 MHz
    real rclk_phase_ns = 0.0;

    logic                  wclk;
    logic                  wrst_n;
    logic                  winc;
    logic [DATA_WIDTH-1:0] wdata;
    logic                  wfull;
    logic                  walmost_full;
    logic [ADDR_WIDTH:0]   wlevel;
    logic                  woverflow;

    logic                  rclk;
    logic                  rrst_n;
    logic                  rinc;
    logic [DATA_WIDTH-1:0] rdata;
    logic                  rempty;
    logic                  ralmost_empty;
    logic [ADDR_WIDTH:0]   rlevel;
    logic                  runderflow;

    // Clocks
    initial begin
        wclk = 1'b0;
        forever #(wclk_half_ns) wclk = ~wclk;
    end

    initial begin
        rclk = 1'b0;
        if (rclk_phase_ns > 0.0) #(rclk_phase_ns);
        forever #(rclk_half_ns) rclk = ~rclk;
    end

    // DUT
    async_fifo #(
        .DATA_WIDTH          (DATA_WIDTH),
        .ADDR_WIDTH          (ADDR_WIDTH),
        .SYNC_STAGES         (SYNC_STAGES),
        .ALMOST_FULL_THRESH  (ALMOST_FULL_THRESH),
        .ALMOST_EMPTY_THRESH (ALMOST_EMPTY_THRESH),
        .USE_RESET_SYNC      (1'b1)
    ) dut (
        .wclk          (wclk),
        .wrst_n        (wrst_n),
        .winc          (winc),
        .wdata         (wdata),
        .wfull         (wfull),
        .walmost_full  (walmost_full),
        .wlevel        (wlevel),
        .woverflow     (woverflow),
        .rclk          (rclk),
        .rrst_n        (rrst_n),
        .rinc          (rinc),
        .rdata         (rdata),
        .rempty        (rempty),
        .ralmost_empty (ralmost_empty),
        .rlevel        (rlevel),
        .runderflow    (runderflow)
    );

    // =========================================================================
    // Reference Scoreboard Ring Buffer (100% Portable Across All Simulators)
    // =========================================================================
    localparam int SB_SIZE = 65536;
    logic [DATA_WIDTH-1:0] sb_mem [0:SB_SIZE-1];
    integer sb_head, sb_tail, sb_count;

    // Global verification counters & functional coverage bins
    integer total_writes, total_reads, total_errors;
    integer cov_full_hit, cov_empty_hit, cov_af_hit, cov_ae_hit;
    integer cov_overflow_blk, cov_underflow_blk, cov_wrap_hit, cov_reset_rec;

    // LFSR pseudo-random generators (portable & deterministic across simulators)
    logic [31:0] w_lfsr, r_lfsr;

    function automatic logic [31:0] next_lfsr(input logic [31:0] s);
        next_lfsr = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
    endfunction

    // Continuous Gray-code & level invariant monitor
    logic [ADDR_WIDTH:0] prev_wptr_mon, prev_rptr_mon;
    logic                mon_active;

    always @(posedge wclk or negedge dut.wrst_sync_n) begin
        if (!dut.wrst_sync_n) begin
            prev_wptr_mon <= '0;
        end else if (mon_active) begin
            logic [ADDR_WIDTH:0] wd;
            wd = dut.wptr ^ prev_wptr_mon;
            if ((wd & (wd - {{ADDR_WIDTH{1'b0}}, 1'b1})) != '0) begin
                $display("[FAIL] Write Gray pointer multi-bit jump: %b -> %b @ %0t", prev_wptr_mon, dut.wptr, $time);
                total_errors = total_errors + 1;
            end
            if (wlevel > DEPTH[ADDR_WIDTH:0]) begin
                $display("[FAIL] wlevel=%0d exceeded DEPTH=%0d @ %0t", wlevel, DEPTH, $time);
                total_errors = total_errors + 1;
            end
            if (wfull)        cov_full_hit = cov_full_hit + 1;
            if (walmost_full) cov_af_hit   = cov_af_hit + 1;
            if (woverflow)    cov_overflow_blk = cov_overflow_blk + 1;
            if (dut.wbin[ADDR_WIDTH] == 1'b1) cov_wrap_hit = cov_wrap_hit + 1;
            prev_wptr_mon <= dut.wptr;
        end
    end

    always @(posedge rclk or negedge dut.rrst_sync_n) begin
        if (!dut.rrst_sync_n) begin
            prev_rptr_mon <= '0;
        end else if (mon_active) begin
            logic [ADDR_WIDTH:0] rd;
            rd = dut.rptr ^ prev_rptr_mon;
            if ((rd & (rd - {{ADDR_WIDTH{1'b0}}, 1'b1})) != '0) begin
                $display("[FAIL] Read Gray pointer multi-bit jump: %b -> %b @ %0t", prev_rptr_mon, dut.rptr, $time);
                total_errors = total_errors + 1;
            end
            if (rlevel > DEPTH[ADDR_WIDTH:0]) begin
                $display("[FAIL] rlevel=%0d exceeded DEPTH=%0d @ %0t", rlevel, DEPTH, $time);
                total_errors = total_errors + 1;
            end
            if (rempty)        cov_empty_hit = cov_empty_hit + 1;
            if (ralmost_empty) cov_ae_hit    = cov_ae_hit + 1;
            if (runderflow)    cov_underflow_blk = cov_underflow_blk + 1;
            prev_rptr_mon <= dut.rptr;
        end
    end

    // =========================================================================
    // Helper Tasks
    // =========================================================================
    task automatic apply_reset(input integer hold_cycles);
        integer k;
        begin
            mon_active = 1'b0;
            winc   = 1'b0;
            rinc   = 1'b0;
            wdata  = '0;
            wrst_n = 1'b0;
            rrst_n = 1'b0;
            sb_head  = 0;
            sb_tail  = 0;
            sb_count = 0;
            for (k = 0; k < hold_cycles; k = k + 1) begin
                @(posedge wclk);
                @(posedge rclk);
            end
            #1.3; // Asynchronous deassertion away from clock edges
            wrst_n = 1'b1;
            rrst_n = 1'b1;
            // Wait for internal reset synchronizers to release both domains
            repeat (SYNC_STAGES + 3) @(posedge wclk);
            repeat (SYNC_STAGES + 3) @(posedge rclk);
            mon_active = 1'b1;
        end
    endtask

    // Randomized dual-clock traffic stress task
    task automatic run_random_stress(
        input string  scenario_name,
        input real    wh_ns,
        input real    rh_ns,
        input integer num_items,
        input integer w_prob_pct,
        input integer r_prob_pct
    );
        integer pushed, popped;
        logic [DATA_WIDTH-1:0] exp_data;
        integer timeout_cnt;
        begin
            $display("----------------------------------------------------------------");
            $display("[SCENARIO] %s (wclk=%.1f MHz, rclk=%.1f MHz, items=%0d)",
                     scenario_name, 500.0/wh_ns, 500.0/rh_ns, num_items);
            wclk_half_ns = wh_ns;
            rclk_half_ns = rh_ns;
            apply_reset(4);

            pushed      = 0;
            popped      = 0;
            timeout_cnt = 0;

            fork
                // Writer thread (wclk domain)
                begin
                    logic [DATA_WIDTH-1:0] next_val;
                    logic                  pre_wfull;
                    w_lfsr   = w_lfsr ^ 32'hA5A5_5A5A;
                    next_val = w_lfsr;
                    while (pushed < num_items) begin
                        @(negedge wclk);
                        w_lfsr = next_lfsr(w_lfsr);
                        if (((w_lfsr % 100) < w_prob_pct)) begin
                            winc  = 1'b1;
                            wdata = next_val;
                        end else begin
                            winc  = 1'b0;
                        end
                        // Sample wfull in Active region at posedge (before NBA updates wfull)
                        @(posedge wclk);
                        pre_wfull = wfull;
                        if (winc && !pre_wfull) begin
                            sb_mem[sb_tail] = wdata;
                            sb_tail         = (sb_tail + 1) % SB_SIZE;
                            sb_count        = sb_count + 1;
                            pushed          = pushed + 1;
                            total_writes    = total_writes + 1;
                            next_val        = next_lfsr(next_val ^ pushed);
                        end
                    end
                    @(negedge wclk);
                    winc = 1'b0;
                end

                // Reader thread (rclk domain)
                begin
                    logic                  pre_rempty;
                    logic [DATA_WIDTH-1:0] pre_rdata;
                    r_lfsr = r_lfsr ^ 32'h3C3C_C3C3;
                    while (popped < num_items) begin
                        @(negedge rclk);
                        r_lfsr = next_lfsr(r_lfsr);
                        if (((r_lfsr % 100) < r_prob_pct) || (pushed == num_items)) begin
                            rinc = 1'b1;
                        end else begin
                            rinc = 1'b0;
                        end
                        // Sample rempty & rdata in Active region at posedge (before NBA updates rbin/rempty)
                        @(posedge rclk);
                        pre_rempty = rempty;
                        pre_rdata  = rdata;
                        if (rinc && !pre_rempty) begin
                            if (sb_count <= 0) begin
                                $display("[FAIL] Scoreboard underflow! Read on empty scoreboard @ %0t", $time);
                                total_errors = total_errors + 1;
                            end else begin
                                exp_data = sb_mem[sb_head];
                                if (pre_rdata !== exp_data) begin
                                    $display("[FAIL] %s item #%0d mismatch: got=0x%08h exp=0x%08h @ %0t",
                                             scenario_name, popped, pre_rdata, exp_data, $time);
                                    total_errors = total_errors + 1;
                                end
                                sb_head     = (sb_head + 1) % SB_SIZE;
                                sb_count    = sb_count - 1;
                                popped      = popped + 1;
                                total_reads = total_reads + 1;
                            end
                        end
                        timeout_cnt = timeout_cnt + 1;
                        if (timeout_cnt > (num_items * 40 + 5000)) begin
                            $display("[FAIL] %s TIMEOUT! pushed=%0d popped=%0d", scenario_name, pushed, popped);
                            total_errors = total_errors + 1;
                            popped = num_items;
                        end
                    end
                    @(negedge rclk);
                    rinc = 1'b0;
                end
            join

            // Wait for empty sync and verify clean drain
            repeat (SYNC_STAGES + 4) @(posedge rclk);
            if (!rempty || sb_count != 0) begin
                $display("[FAIL] %s did not drain cleanly: rempty=%b sb_count=%0d",
                         scenario_name, rempty, sb_count);
                total_errors = total_errors + 1;
            end else begin
                $display("[PASS] %s: %0d/%0d transfers verified bit-exact (0 errors)",
                         scenario_name, popped, num_items);
            end
        end
    endtask

    // =========================================================================
    // Main Verification Flow
    // =========================================================================
    initial begin
        total_writes      = 0;
        total_reads       = 0;
        total_errors      = 0;
        cov_full_hit      = 0;
        cov_empty_hit     = 0;
        cov_af_hit        = 0;
        cov_ae_hit        = 0;
        cov_overflow_blk  = 0;
        cov_underflow_blk = 0;
        cov_wrap_hit      = 0;
        cov_reset_rec     = 0;
        w_lfsr            = 32'hCAFE_BABE;
        r_lfsr            = 32'hDEAD_BEEF;
        mon_active        = 1'b0;

        $display("================================================================");
        $display("  ASYNC FIFO CDC VERIFICATION SUITE (DEPTH=%0d, WIDTH=%0d)", DEPTH, DATA_WIDTH);
        $display("================================================================");

        // ---------------------------------------------------------------------
        // Test 1: Directed Threshold, Overflow/Underflow Protection & Level Test
        // ---------------------------------------------------------------------
        $display("----------------------------------------------------------------");
        $display("[SCENARIO] 1. Directed Full/Empty/Almost-Flags & Overflow/Underflow Guard");
        wclk_half_ns = 5.0;  // 100 MHz
        rclk_half_ns = 5.0;  // 100 MHz
        apply_reset(4);

        // Verify post-reset state
        if (!rempty || !ralmost_empty || wfull || walmost_full || wlevel != 0 || rlevel != 0) begin
            $display("[FAIL] Post-reset flags invalid: rempty=%b rae=%b wfull=%b waf=%b wlvl=%0d rlvl=%0d",
                     rempty, ralmost_empty, wfull, walmost_full, wlevel, rlevel);
            total_errors = total_errors + 1;
        end

        // Attempt 3 illegal reads on empty FIFO -> verify runderflow asserts & pointer stays 0
        repeat (3) begin
            @(negedge rclk); rinc = 1'b1;
            @(posedge rclk);
        end
        @(negedge rclk); rinc = 1'b0;
        @(posedge rclk);
        if (!runderflow || !rempty) begin
            $display("[FAIL] Underflow guard failed: runderflow=%b rempty=%b", runderflow, rempty);
            total_errors = total_errors + 1;
        end

        // Fill FIFO completely (DEPTH entries) and check walmost_full threshold
        for (int i = 0; i < DEPTH; i = i + 1) begin
            @(negedge wclk);
            winc  = 1'b1;
            wdata = 32'h1000_0000 + i;
            @(posedge wclk);
            #0.1;
            if (i >= (DEPTH - ALMOST_FULL_THRESH - 1)) begin
                if (!walmost_full) begin
                    $display("[FAIL] walmost_full did not assert at fill=%0d (thresh=%0d)", i+1, ALMOST_FULL_THRESH);
                    total_errors = total_errors + 1;
                end
            end
        end
        @(negedge wclk); winc = 1'b0;
        #0.1;
        if (!wfull || wlevel != DEPTH[ADDR_WIDTH:0]) begin
            $display("[FAIL] Expected wfull=1 and wlevel=%0d, got wfull=%b wlevel=%0d", DEPTH, wfull, wlevel);
            total_errors = total_errors + 1;
        end

        // Attempt 3 illegal writes on full FIFO -> verify woverflow asserts & NO overwrite!
        for (int i = 0; i < 3; i = i + 1) begin
            @(negedge wclk);
            winc  = 1'b1;
            wdata = 32'hBAD0_0000 + i;
            @(posedge wclk);
        end
        @(negedge wclk); winc = 1'b0;
        @(posedge wclk);
        if (!woverflow || !wfull) begin
            $display("[FAIL] Overflow guard failed: woverflow=%b wfull=%b", woverflow, wfull);
            total_errors = total_errors + 1;
        end

        // Wait for pointer sync to read domain, then drain and verify bit-exact data
        repeat (SYNC_STAGES + 3) @(posedge rclk);
        if (rlevel != DEPTH[ADDR_WIDTH:0] || rempty || ralmost_empty) begin
            $display("[FAIL] Read domain failed to see full FIFO: rlevel=%0d rempty=%b rae=%b",
                     rlevel, rempty, ralmost_empty);
            total_errors = total_errors + 1;
        end
        for (int i = 0; i < DEPTH; i = i + 1) begin
            @(negedge rclk);
            rinc = 1'b1;
            @(posedge rclk);
            if (rdata !== (32'h1000_0000 + i)) begin
                $display("[FAIL] Directed drain idx %0d: got=0x%08h exp=0x%08h",
                         i, rdata, 32'h1000_0000 + i);
                total_errors = total_errors + 1;
            end
            #0.1;
            if ((DEPTH - 1 - i) <= ALMOST_EMPTY_THRESH) begin
                if (!ralmost_empty) begin
                    $display("[FAIL] ralmost_empty did not assert at rem=%0d", DEPTH - 1 - i);
                    total_errors = total_errors + 1;
                end
            end
        end
        @(negedge rclk); rinc = 1'b0;
        $display("[PASS] Directed Threshold & Overflow/Underflow Guard complete");

        // ---------------------------------------------------------------------
        // Test 2: Fast Write (200 MHz) / Slow Read (50 MHz) — 4:1 Saturation
        // ---------------------------------------------------------------------
        run_random_stress("2. Fast-Write / Slow-Read (4:1)", 2.5, 10.0, 4000, 90, 85);

        // ---------------------------------------------------------------------
        // Test 3: Slow Write (50 MHz) / Fast Read (200 MHz) — 1:4 Starvation
        // ---------------------------------------------------------------------
        run_random_stress("3. Slow-Write / Fast-Read (1:4)", 10.0, 2.5, 4000, 85, 90);

        // ---------------------------------------------------------------------
        // Test 4: Plesiochronous Prime-Ratio Clocks (137 MHz vs 103 MHz)
        //         Sweeps all possible CDC phase alignments continuously
        // ---------------------------------------------------------------------
        run_random_stress("4. Plesiochronous Prime Ratio (137/103 MHz)", 3.65, 4.85, 6000, 75, 75);

        // ---------------------------------------------------------------------
        // Test 5: High-Frequency Bursty Stress (250 MHz vs 166.7 MHz)
        // ---------------------------------------------------------------------
        run_random_stress("5. High-Freq Bursty Stress (250/167 MHz)", 2.0, 3.0, 6000, 60, 60);

        // ---------------------------------------------------------------------
        // Test 6: Mid-Flight Asynchronous Reset Injection & Clean Recovery
        // ---------------------------------------------------------------------
        $display("----------------------------------------------------------------");
        $display("[SCENARIO] 6. Mid-Flight Async Reset Injection & Clean Recovery");
        wclk_half_ns = 3.1;
        rclk_half_ns = 4.7;
        apply_reset(4);

        // Push 10 items without draining
        for (int i = 0; i < 10; i = i + 1) begin
            @(negedge wclk); winc = 1'b1; wdata = 32'hDEAD_0000 + i;
            @(posedge wclk);
        end
        @(negedge wclk); winc = 1'b0;

        // Slam asynchronous reset mid-flight while FIFO holds stale data
        #1.7;
        apply_reset(5);
        cov_reset_rec = cov_reset_rec + 1;

        // Verify FIFO is completely empty and fresh data passes cleanly with zero stale words
        if (!rempty || wfull || wlevel != 0 || rlevel != 0) begin
            $display("[FAIL] Post-mid-flight reset state dirty!");
            total_errors = total_errors + 1;
        end
        run_random_stress("6b. Post-Reset Recovery Traffic", 3.1, 4.7, 1000, 80, 80);

        // =====================================================================
        // Summary & Functional Coverage Report
        // =====================================================================
        $display("================================================================");
        $display("  VERIFICATION SUMMARY");
        $display("  Total Writes Verified  : %0d", total_writes);
        $display("  Total Reads Verified   : %0d", total_reads);
        $display("  Total Errors           : %0d", total_errors);
        $display("  --- Functional Coverage Bins ---");
        $display("  wfull Hit              : %0d cycles", cov_full_hit);
        $display("  rempty Hit             : %0d cycles", cov_empty_hit);
        $display("  walmost_full Hit       : %0d cycles", cov_af_hit);
        $display("  ralmost_empty Hit      : %0d cycles", cov_ae_hit);
        $display("  Overflow Guard Trigger : %0d cycles", cov_overflow_blk);
        $display("  Underflow Guard Trigger: %0d cycles", cov_underflow_blk);
        $display("  Pointer MSB Wraparound : %0d cycles", cov_wrap_hit);
        $display("  Async Reset Recovery   : %0d runs",   cov_reset_rec);
        $display("================================================================");

        if (total_errors == 0 && cov_full_hit > 0 && cov_empty_hit > 0 &&
            cov_af_hit > 0 && cov_ae_hit > 0 && cov_overflow_blk > 0 &&
            cov_underflow_blk > 0 && cov_wrap_hit > 0 && cov_reset_rec > 0) begin
            $display("*** ALL ASYNC FIFO TESTS & COVERAGE BINS PASSED (0 ERRORS) ***");
        end else begin
            $display("*** VERIFICATION FAILED (errors=%0d) ***", total_errors);
            $fatal(1, "Async FIFO testbench failed");
        end

        $finish;
    end

endmodule
