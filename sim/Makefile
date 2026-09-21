#============================================================
# Environment
#============================================================
PRO_HOME := $(CURDIR)
WORK_DIR ?= work
LIB_DIR  := $(WORK_DIR)/lib
LOG_DIR  := $(WORK_DIR)/log
WAVE_DIR := $(WORK_DIR)/wave
COV_DIR  := $(WORK_DIR)/cov

UVM_HOME ?= D:/questasim64_10.6c/verilog_src/uvm-1.1d/src
UVM_LIB  ?= mtiUvm
TOP      ?= tb
FILELIST ?= sim.f

#============================================================
# Function switches
#============================================================
dump      ?= n
cov       ?= n
rand      ?= n
test      ?= axi_stage1_single_write_test
reg_times ?= 20

# Questa 10.6c interprets an environment variable named "dump" as an
# internal hierarchy-dump switch. Keep it as a Make switch only.
unexport dump

ifeq ($(rand),y)
  SEED ?= $(shell powershell -NoProfile -Command "Get-Random -Minimum 1 -Maximum 2147483647")
else
  SEED ?= 0
endif

UVM_VERBO ?= UVM_LOW
UVM_OPTION = +UVM_NO_RELNOTES

#============================================================
# Coverage and waveform options
#============================================================
ifeq ($(cov),y)
  COV_COM_OPTION = +cover=bcesft
  COV_SIM_OPTION = -coverage
  COV_SAVE_CMD   = coverage save -onexit $(COV_DIR)/$(test).ucdb;
endif

WAVE_OPTION = -wlf $(WAVE_DIR)/$(test).wlf
ifeq ($(dump),y)
  WAVE_CMD = log -r /$(TOP)/m_if/*; \
	log -r /$(TOP)/s_if/*; \
	log -r /$(TOP)/dut/*;
endif

#============================================================
# Compile and simulation commands
#============================================================
COM_CMD = -sv \
	-L $(UVM_LIB) \
	+incdir+$(UVM_HOME) \
	-timescale 1ns/1ps \
	$(COV_COM_OPTION) \
	-modelsimini $(WORK_DIR)/modelsim.ini \
	-work work \
	-f $(FILELIST) \
	-l $(LOG_DIR)/compile.log

SIM_CMD = -c \
	-L $(UVM_LIB) \
	-modelsimini $(WORK_DIR)/modelsim.ini \
	work.$(TOP) \
	-sv_seed $(SEED) \
	+UVM_VERBOSITY=$(UVM_VERBO) \
	+UVM_TESTNAME=$(test) \
	$(UVM_OPTION) \
	$(COV_SIM_OPTION) \
	$(WAVE_OPTION) \
	-l $(LOG_DIR)/$(test).log

RUN_CMD = $(WAVE_CMD) $(COV_SAVE_CMD) run -all; quit -code 0

#============================================================
# Targets
#============================================================
.PHONY: all prepare com compile sim run debug wave verdi cov_report urg \
	clean clean_all regress stage2_regress positive_regress assertion_selftest \
	stage3_elab stage3_regress stage3_assertion_selftest \
	stage3_switch_model_selftest

all: clean com sim

prepare:
	if not exist "$(WORK_DIR)" mkdir "$(WORK_DIR)"
	if not exist "$(LOG_DIR)" mkdir "$(LOG_DIR)"
	if not exist "$(WAVE_DIR)" mkdir "$(WAVE_DIR)"
	if not exist "$(COV_DIR)" mkdir "$(COV_DIR)"
	if not exist "$(LIB_DIR)\_info" vlib "$(LIB_DIR)"
	if not exist "$(WORK_DIR)\modelsim.ini" powershell -NoProfile -Command "Set-Location -LiteralPath '$(WORK_DIR)'; & vmap -c; exit $$LASTEXITCODE"
	vmap -modelsimini "$(WORK_DIR)/modelsim.ini" work "$(PRO_HOME)/$(LIB_DIR)"

# Compile
com: prepare
	vlog $(COM_CMD)

stage3_elab: com
	vsim -c -L $(UVM_LIB) -modelsimini $(WORK_DIR)/modelsim.ini \
		work.$(TOP) $(UVM_OPTION) \
		-l $(LOG_DIR)/stage3_elab.log \
		-do "quit -code 0"


# Simulation
sim: prepare
	vsim $(SIM_CMD) -do "$(RUN_CMD)"
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(LOG_DIR)/$(test).log'; if (($$text -notmatch 'AXI_TC_PASS') -or ($$text -notmatch 'UVM_ERROR\s*:\s*0') -or ($$text -notmatch 'UVM_FATAL\s*:\s*0')) { exit 1 }"

# Questa GUI debug
debug: prepare
	vsim -gui -L $(UVM_LIB) -modelsimini "$(WORK_DIR)/modelsim.ini" \
		-uvmcontrol=all \
		work.$(TOP) -sv_seed $(SEED) +UVM_VERBOSITY=$(UVM_VERBO) \
		+UVM_TESTNAME=$(test) $(UVM_OPTION) $(COV_SIM_OPTION) \
		$(WAVE_OPTION) -do "$(WAVE_CMD) run -all"

# Open a generated WLF. The verdi target is retained as a compatibility alias.
wave:
	vsim -view "$(WAVE_DIR)/$(test).wlf"


# Questa coverage report. The urg target is retained as a compatibility alias.
cov_report:
	vcover report -html -htmldir "$(COV_DIR)/$(test)_report" \
		"$(COV_DIR)/$(test).ucdb"

urg: cov_report

# Remove the compiled library while retaining logs, waves and coverage results.
clean:
	powershell -NoProfile -Command "if (Test-Path -LiteralPath '$(LIB_DIR)') { Remove-Item -LiteralPath '$(LIB_DIR)' -Recurse -Force }; if (Test-Path -LiteralPath '$(WORK_DIR)/modelsim.ini') { Remove-Item -LiteralPath '$(WORK_DIR)/modelsim.ini' -Force }"

clean_all:
	powershell -NoProfile -Command "if (Test-Path -LiteralPath '$(WORK_DIR)') { Remove-Item -LiteralPath '$(WORK_DIR)' -Recurse -Force }"

# Repeat the selected test with independent random seeds.
regress: com
	powershell -NoProfile -Command "for ($$index = 1; $$index -le $(reg_times); $$index++) { $$reg_seed = Get-Random -Minimum 1 -Maximum 2147483647; & '$(MAKE)' sim test='$(test)' SEED=$$reg_seed dump='$(dump)' cov='$(cov)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE } }"

stage2_regress: com
	powershell -NoProfile -Command "$$tests = @('axi_stage2_burst_write_test','axi_stage2_burst_read_test','axi_stage2_aw_w_order_test','axi_stage2_delay_gap_test','axi_stage2_channel_stall_test','axi_stage2_read_write_parallel_test','axi_stage2_ready_random_smoke_test'); foreach ($$name in $$tests) { & '$(MAKE)' sim test=$$name dump='$(dump)' cov='$(cov)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE } }"

stage3_regress: com
	powershell -NoProfile -Command "$$tests = @('axi_stage3_outstanding_write_test','axi_stage3_outstanding_read_test','axi_stage3_write_ooo_test','axi_stage3_read_ooo_test','axi_stage3_same_id_order_test','axi_stage3_mixed_rw_test','axi_stage3_id_mapping_test','axi_stage3_outstanding_stall_test'); foreach ($$name in $$tests) { & '$(MAKE)' sim test=$$name dump='$(dump)' cov='$(cov)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE } }"

positive_regress: com
	powershell -NoProfile -Command "$$tests = @('axi_stage1_single_write_test','axi_stage1_single_read_test','axi_stage2_burst_write_test','axi_stage2_burst_read_test','axi_stage2_aw_w_order_test','axi_stage2_delay_gap_test','axi_stage2_channel_stall_test','axi_stage2_read_write_parallel_test','axi_stage2_ready_random_smoke_test','axi_stage3_outstanding_write_test','axi_stage3_outstanding_read_test','axi_stage3_write_ooo_test','axi_stage3_read_ooo_test','axi_stage3_same_id_order_test','axi_stage3_mixed_rw_test','axi_stage3_id_mapping_test','axi_stage3_outstanding_stall_test'); foreach ($$name in $$tests) { & '$(MAKE)' sim test=$$name dump='$(dump)' cov='$(cov)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE } }"

assertion_selftest: com
	vsim -c -L $(UVM_LIB) -modelsimini $(WORK_DIR)/modelsim.ini \
		work.axi_protocol_assertions_selftest $(UVM_OPTION) \
		-l $(LOG_DIR)/axi_protocol_assertions_selftest.log \
		-do "run -all; quit -code 0"
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(LOG_DIR)/axi_protocol_assertions_selftest.log'; if ($$text -notmatch 'AXI_ASSERT_SELFTEST_PASS') { exit 1 }"

stage3_assertion_selftest: com
	vsim -c -L $(UVM_LIB) -modelsimini $(WORK_DIR)/modelsim.ini \
		work.axi_stage3_protocol_assertions_selftest $(UVM_OPTION) \
		-l $(LOG_DIR)/axi_stage3_protocol_assertions_selftest.log \
		-do "run -all; quit -code 0"
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(LOG_DIR)/axi_stage3_protocol_assertions_selftest.log'; if ($$text -notmatch 'AXI_STAGE3_ASSERT_SELFTEST_PASS') { exit 1 }"

stage3_switch_model_selftest: com
	vsim -c -L $(UVM_LIB) -modelsimini $(WORK_DIR)/modelsim.ini \
		work.axi_switch_ref_model_selftest $(UVM_OPTION) \
		-l $(LOG_DIR)/axi_switch_ref_model_selftest.log \
		-do "run -all; quit -code 0"
	powershell -NoProfile -Command "$$text = Get-Content -Raw -LiteralPath '$(LOG_DIR)/axi_switch_ref_model_selftest.log'; if ($$text -notmatch 'AXI_SWITCH_MODEL_SELFTEST_PASS') { exit 1 }"
