UVM_HOME ?= D:/questasim64_10.6c/verilog_src/uvm-1.1d/src
WORK_LIB ?= work
BUILD_DIR ?= build

VLOG_FLAGS := -sv -L mtiUvm +incdir+$(UVM_HOME) -f stage0.f
VSIM_FLAGS := -c -L mtiUvm work.stage0_tb

.PHONY: all compile run clean

all: run

compile:
	if not exist "$(BUILD_DIR)" mkdir "$(BUILD_DIR)"
	if not exist "$(WORK_LIB)" vlib "$(WORK_LIB)"
	vlog $(VLOG_FLAGS) -l $(BUILD_DIR)/compile.log

run: compile
	vsim $(VSIM_FLAGS) -do "run -all; quit -code 0" \
		-l $(BUILD_DIR)/run.log

clean:
	powershell -NoProfile -Command "$$paths = @('$(WORK_LIB)', '$(BUILD_DIR)', 'transcript', 'modelsim.ini'); foreach ($$path in $$paths) { if (Test-Path -LiteralPath $$path) { Remove-Item -LiteralPath $$path -Recurse -Force } }"
