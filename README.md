# python
vivado -------python send_rbf_verify.py COM4 1 SLAVE0.RBF



sim do C:/Users/kumar/Downloads/fla/MT25QL128_COMPACT_SIM_4K/run_fast_gui.do




catch {quit -sim}

set PROJECT_DIR "C:/Users/kumar/Downloads/fla/MT25QL128_COMPACT_SIM_4K"

cd $PROJECT_DIR

puts "WORKING_DIRECTORY=[pwd]"

puts "MICRON_MODEL_EXISTS=[file exists ./code/N25Qxxx.v]"
puts "CONTROLLER_EXISTS=[file exists ./mt25ql128_adc_style.vhd]"
puts "TESTBENCH_EXISTS=[file exists ./tb_mt25ql128_bulk_data.vhd]"

if {![file exists ./code/N25Qxxx.v]} {
    error "Micron model missing"
}
if {![file exists ./mt25ql128_adc_style.vhd]} {
    error "Controller missing"
}
if {![file exists ./tb_mt25ql128_bulk_data.vhd]} {
    error "Testbench missing"
}

if {![file exists work]} {
    vlib work
}
vmap work work

vlog +incdir+. +incdir+./include +define+Feature_8 +define+HOLD_pin ./code/N25Qxxx.v ./flash_module.v

vcom -2008 ./mt25ql128_adc_style.vhd
vcom -2008 ./tb_mt25ql128_bulk_data.vhd

vsim -t 1ps -gTARGET_KIB=4 work.tb_mt25ql128_bulk_data

view wave

add wave -radix hex sim:/tb_mt25ql128_bulk_data/clkin
add wave sim:/tb_mt25ql128_bulk_data/reset
add wave sim:/tb_mt25ql128_bulk_data/scsq
add wave sim:/tb_mt25ql128_bulk_data/sclk
add wave sim:/tb_mt25ql128_bulk_data/ctrl_dq0
add wave sim:/tb_mt25ql128_bulk_data/dq1
add wave sim:/tb_mt25ql128_bulk_data/busy
add wave sim:/tb_mt25ql128_bulk_data/page_program
add wave -radix hex sim:/tb_mt25ql128_bulk_data/addr

run 5 ms
