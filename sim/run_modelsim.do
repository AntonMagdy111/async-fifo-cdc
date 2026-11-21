# ModelSim / Questa Automated Regression Script — async-fifo-cdc
if {[file exists work]} { vdel -lib work -all }
vlib work

# Compile RTL + SVA + Testbench
vlog -sv +acc rtl/cdc_sync_2ff.sv rtl/cdc_reset_sync.sv rtl/fifo_mem_dp.sv rtl/async_fifo.sv
vlog -sv +acc formal/async_fifo_sva.sv tb/tb_async_fifo.sv

# Create bind wrapper file on-the-fly for ModelSim SVA binding
set fp [open "sim/tb_bind_sva.sv" w]
puts $fp "module tb_bind_sva;"
puts $fp "  bind async_fifo async_fifo_sva #("
puts $fp "    .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH),"
puts $fp "    .ALMOST_FULL_THRESH(ALMOST_FULL_THRESH), .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)"
puts $fp "  ) u_sva ("
puts $fp "    .wclk(wclk), .wrst_sync_n(wrst_sync_n), .winc(winc), .wfull(wfull),"
puts $fp "    .walmost_full(walmost_full), .wlevel(wlevel), .woverflow(woverflow),"
puts $fp "    .wbin(wbin), .wptr(wptr),"
puts $fp "    .rclk(rclk), .rrst_sync_n(rrst_sync_n), .rinc(rinc), .rempty(rempty),"
puts $fp "    .ralmost_empty(ralmost_empty), .rlevel(rlevel), .runderflow(runderflow),"
puts $fp "    .rbin(rbin), .rptr(rptr)"
puts $fp "  );"
puts $fp "endmodule"
close $fp
vlog -sv +acc sim/tb_bind_sva.sv

vsim -c -voptargs="+acc" work.tb_async_fifo work.tb_bind_sva -do "run -all; quit -f"
