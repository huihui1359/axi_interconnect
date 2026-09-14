UVM_HOME ?= D:/questasim64_10.6c/verilog_src/uvm-1.1d/src
WORK_LIB ?= work
BUILD_DIR ?= build
SEED ?= 1

VLOG_BASE_FLAGS := -sv -L mtiUvm +incdir+$(UVM_HOME)
STAGE1_UNIT_TESTS := \
	stage1_m_driver_unit_test \
	stage1_s_driver_unit_test \
	stage1_m_monitor_unit_test \
	stage1_s_monitor_unit_test \
	stage1_event_comparator_unit_test \
	stage1_agent_unit_test \
	stage1_reactive_chain_unit_test
STAGE1_E2E_TESTS := \
	stage1_e2e_write_test \
	stage1_e2e_read_test \
	stage1_e2e_reset_test

.PHONY: all compile run stage0 stage0_compile stage0_run \
	stage1_unit stage1_unit_compile $(STAGE1_UNIT_TESTS) \
	stage1_e2e stage1_e2e_compile $(STAGE1_E2E_TESTS) stage1 clean

all: stage0

compile: stage0_compile

run: stage0

stage0_compile:
	if not exist "$(BUILD_DIR)" mkdir "$(BUILD_DIR)"
	if not exist "$(WORK_LIB)" vlib "$(WORK_LIB)"
	vlog $(VLOG_BASE_FLAGS) -f stage0.f -l $(BUILD_DIR)/stage0_compile.log

stage0_run: stage0_compile
	vsim -c -L mtiUvm work.stage0_tb -sv_seed $(SEED) \
		-do "run -all; quit -code 0" -l $(BUILD_DIR)/stage0.log
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(BUILD_DIR)/stage0.log'; if (($$text -notmatch 'STAGE0_PASS') -or ($$text -notmatch 'UVM_ERROR\s*:\s*0') -or ($$text -notmatch 'UVM_FATAL\s*:\s*0')) { exit 1 }"

stage0: stage0_run

stage1_unit_compile:
	if not exist "$(BUILD_DIR)" mkdir "$(BUILD_DIR)"
	if not exist "$(WORK_LIB)" vlib "$(WORK_LIB)"
	vlog $(VLOG_BASE_FLAGS) -f stage1_unit.f \
		-l $(BUILD_DIR)/stage1_unit_compile.log

$(STAGE1_UNIT_TESTS): stage1_unit_compile
	vsim -c -L mtiUvm work.stage1_unit_tb +UVM_TESTNAME=$@ \
		-sv_seed $(SEED) -do "run -all; quit -code 0" \
		-l $(BUILD_DIR)/$@.log
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(BUILD_DIR)/$@.log'; if (($$text -notmatch 'STAGE1_UNIT_PASS') -or ($$text -notmatch 'UVM_ERROR\s*:\s*0') -or ($$text -notmatch 'UVM_FATAL\s*:\s*0')) { exit 1 }"

stage1_unit: $(STAGE1_UNIT_TESTS)

stage1_e2e_compile:
	if not exist "$(BUILD_DIR)" mkdir "$(BUILD_DIR)"
	if not exist "$(WORK_LIB)" vlib "$(WORK_LIB)"
	vlog $(VLOG_BASE_FLAGS) -f stage1_e2e.f \
		-l $(BUILD_DIR)/stage1_e2e_compile.log

$(STAGE1_E2E_TESTS): stage1_e2e_compile
	vsim -c -L mtiUvm work.stage1_e2e_tb +UVM_TESTNAME=$@ \
		-sv_seed $(SEED) -do "run -all; quit -code 0" \
		-l $(BUILD_DIR)/$@.log
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(BUILD_DIR)/$@.log'; if (($$text -notmatch 'STAGE1_E2E_PASS') -or ($$text -notmatch 'UVM_ERROR\s*:\s*0') -or ($$text -notmatch 'UVM_FATAL\s*:\s*0')) { exit 1 }"

stage1_e2e: $(STAGE1_E2E_TESTS)

stage1: stage0 stage1_unit stage1_e2e

clean:
	powershell -NoProfile -Command "$$paths = @('$(WORK_LIB)', '$(BUILD_DIR)', 'transcript', 'modelsim.ini'); foreach ($$path in $$paths) { if (Test-Path -LiteralPath $$path) { Remove-Item -LiteralPath $$path -Recurse -Force } }"
