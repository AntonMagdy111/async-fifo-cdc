# =============================================================================
# Makefile — Parameterized Dual-Clock Asynchronous FIFO (async-fifo-cdc)
# =============================================================================

RTL_SRCS = rtl/cdc_sync_2ff.sv rtl/cdc_reset_sync.sv rtl/fifo_mem_dp.sv rtl/async_fifo.sv
TB_SRCS  = tb/tb_async_fifo.sv

.PHONY: all lint sim-verilator sim-iverilog sim-modelsim formal synth-yosys clean

all: lint sim-verilator sim-iverilog

lint:
	verilator --lint-only -Wall -Werror-LATCH -Werror-WIDTH -Werror-UNOPTFLAT \
		--top-module async_fifo $(RTL_SRCS)

sim-verilator:
	verilator --binary --timing -Wall -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD --top-module tb_async_fifo \
		$(RTL_SRCS) $(TB_SRCS) -o Vtb_async_fifo
	./obj_dir/Vtb_async_fifo

sim-iverilog:
	iverilog -g2012 -o tb_async_fifo.vvp $(RTL_SRCS) $(TB_SRCS)
	vvp tb_async_fifo.vvp

sim-modelsim:
	vsim -c -do "do sim/run_modelsim.do"

formal:
	sby -f formal/async_fifo.sby

synth-yosys:
	yosys -p "read_verilog -sv $(RTL_SRCS); synth -top async_fifo; stat"

clean:
	rm -rf obj_dir work *.vvp *.vcd *.wlf transcript sim/tb_bind_sva.sv \
		formal/async_fifo_* synth/build
