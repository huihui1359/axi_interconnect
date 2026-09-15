UVM_HOME ?= D:/questasim64_10.6c/verilog_src/uvm-1.1d/src
WORK_DIR ?= work
TESTNAME ?= axi_write_test
SEED     ?= 1

TESTS := axi_write_test axi_read_test
VLOG_FLAGS := -sv -L mtiUvm +incdir+$(UVM_HOME)

.PHONY: all compile run regress $(TESTS) clean

all: run

compile:
	if not exist "$(WORK_DIR)" vlib "$(WORK_DIR)"
	vlog $(VLOG_FLAGS) -work "$(WORK_DIR)" -f sim.f \
		-l "$(WORK_DIR)/compile.log"

run: compile
	vsim -c -L mtiUvm work.tb +UVM_TESTNAME=$(TESTNAME) \
		-sv_seed $(SEED) -wlf "$(WORK_DIR)/$(TESTNAME).wlf" \
		-do "log -r /*; run -all; quit -code 0" \
		-l "$(WORK_DIR)/$(TESTNAME).log"
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(WORK_DIR)/$(TESTNAME).log'; if (($$text -notmatch 'AXI_TC_PASS') -or ($$text -notmatch 'UVM_ERROR\s*:\s*0') -or ($$text -notmatch 'UVM_FATAL\s*:\s*0')) { exit 1 }"

$(TESTS): compile
	vsim -c -L mtiUvm work.tb +UVM_TESTNAME=$@ \
		-sv_seed $(SEED) -wlf "$(WORK_DIR)/$@.wlf" \
		-do "log -r /*; run -all; quit -code 0" \
		-l "$(WORK_DIR)/$@.log"
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(WORK_DIR)/$@.log'; if (($$text -notmatch 'AXI_TC_PASS') -or ($$text -notmatch 'UVM_ERROR\s*:\s*0') -or ($$text -notmatch 'UVM_FATAL\s*:\s*0')) { exit 1 }"

regress: $(TESTS)

clean:
	powershell -NoProfile -Command "if (Test-Path -LiteralPath '$(WORK_DIR)') { Remove-Item -LiteralPath '$(WORK_DIR)' -Recurse -Force }"
