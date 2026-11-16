# Execute from repository root: vsim -do sim/questa.do
vlib work
vlog -sv rtl/dut.v tb/tb_fifo.sv
vsim -c tb_fifo
run -all
quit -f
