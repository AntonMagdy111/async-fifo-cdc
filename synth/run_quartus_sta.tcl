# =============================================================================
# Intel Quartus Prime Automated Synthesis, Fitter & TimeQuest STA Script
# Target: Cyclone V (5CSEMA5F31C6 — DE1-SoC)
# Usage:  quartus_sh -t synth/run_quartus_sta.tcl
# =============================================================================

load_package flow

set proj_name "async_fifo_qproj"
set build_dir "synth/build"
file mkdir $build_dir
file mkdir "synth/reports"

cd $build_dir

if {[project_exists $proj_name]} {
    project_open $proj_name
} else {
    project_new $proj_name -overwrite
}

set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEMA5F31C6
set_global_assignment -name TOP_LEVEL_ENTITY async_fifo
set_global_assignment -name SYSTEMVERILOG_FILE ../../rtl/cdc_sync_2ff.sv
set_global_assignment -name SYSTEMVERILOG_FILE ../../rtl/cdc_reset_sync.sv
set_global_assignment -name SYSTEMVERILOG_FILE ../../rtl/fifo_mem_dp.sv
set_global_assignment -name SYSTEMVERILOG_FILE ../../rtl/async_fifo.sv
set_global_assignment -name SDC_FILE ../../constraints/async_fifo.sdc
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL

# Characterize async_fifo as an on-chip IP block (virtualize data/ctrl I/Os
# so external 3.3V GPIO pad buffers do not mask internal fabric Fmax)
foreach port [list winc wdata wfull walmost_full wlevel woverflow rinc rdata rempty ralmost_empty rlevel runderflow wrst_n rrst_n] {
    set_instance_assignment -name VIRTUAL_PIN ON -to $port
}

# Run Analysis & Synthesis -> Fitter -> Timing Analyzer
execute_module -tool map
execute_module -tool fit
execute_module -tool sta

project_close

# Copy key human-readable reports into synth/reports/
foreach rpt [list "${proj_name}.map.summary" "${proj_name}.fit.summary" "${proj_name}.sta.summary" "${proj_name}.sta.rpt"] {
    if {[file exists $rpt]} {
        file copy -force $rpt "../reports/$rpt"
    }
}
puts "=== Quartus Synthesis + Fitter + TimeQuest STA Complete ==="
