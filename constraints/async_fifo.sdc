# =============================================================================
# Synopsys Design Constraints (SDC) — Parameterized Dual-Clock Async FIFO
# Compatible with Intel Quartus TimeQuest STA, OpenSTA, and Synopsys PrimeTime
# =============================================================================

# 1. Define Asynchronous Primary Clocks (Cyclone V 4-Corner PVT Sign-Off)
#    Write domain: 166.7 MHz (Period = 6.000 ns)
#    Read domain : 120.0 MHz (Period = 8.333 ns)
create_clock -name wclk -period 6.000 [get_ports {wclk}]
create_clock -name rclk -period 8.333 [get_ports {rclk}]

derive_clock_uncertainty

# 2. Declare Asynchronous Clock Groups
#    Prevents STA from attempting meaningless synchronous setup/hold closure
#    between unrelated clock edges.
set_clock_groups -asynchronous \
    -group [get_clocks {wclk}] \
    -group [get_clocks {rclk}]

# 3. Skew-Bounded Max-Delay Constraints on Gray-Coded CDC Pointer Buses
#    CRITICAL CDC PRACTICE: set_clock_groups alone leaves Gray-code bus skew
#    unbounded. If skew across bits exceeds 1 source clock period, >1 bit can
#    transition in the destination sampling window, breaking Gray-code safety.
#    Bound datapath delay to < min(T_wclk, T_rclk) = 4.0 ns.
set_max_delay 4.000 \
    -from [get_registers {*wptr[*]}] \
    -to   [get_registers {*u_sync_w2r*sync_pipe[0][*]}]

set_max_delay 4.000 \
    -from [get_registers {*rptr[*]}] \
    -to   [get_registers {*u_sync_r2w*sync_pipe[0][*]}]

# 4. Asynchronous Reset Input Paths (Protected by cdc_reset_sync bridges)
set_false_path -from [get_ports {wrst_n}]
set_false_path -from [get_ports {rrst_n}]

# 5. I/O Timing Budgets (On-chip IP boundary — 0.5 ns nominal virtual-pin budget)
set_input_delay  -clock wclk -max 0.500 [get_ports {winc wdata[*]}]
set_input_delay  -clock wclk -min 0.100 [get_ports {winc wdata[*]}]
set_output_delay -clock wclk -max 0.500 [get_ports {wfull walmost_full wlevel[*] woverflow}]
set_output_delay -clock wclk -min 0.100 [get_ports {wfull walmost_full wlevel[*] woverflow}]

set_input_delay  -clock rclk -max 0.500 [get_ports {rinc}]
set_input_delay  -clock rclk -min 0.100 [get_ports {rinc}]
set_output_delay -clock rclk -max 0.500 [get_ports {rdata[*] rempty ralmost_empty rlevel[*] runderflow}]
set_output_delay -clock rclk -min 0.100 [get_ports {rdata[*] rempty ralmost_empty rlevel[*] runderflow}]
