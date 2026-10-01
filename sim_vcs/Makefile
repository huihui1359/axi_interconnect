# VCS/UVM build for the AXI interconnect verification environment.
# Run all commands from this sim_vcs directory.

SHELL := /bin/bash

TOP       ?= tb
TEST      ?= axi_stage1_single_read_test
SEED      ?= 1
VERBOSITY ?= UVM_LOW
DUMP      ?= 0

FILELIST  ?= sim.f
BUILD_DIR ?= build
LOG_DIR   ?= log
WAVE_DIR  ?= wave
SIMV      := $(BUILD_DIR)/simv

# VCS O-2018 predates WSL2's kernel version.  UNAME26 makes its platform
# detection select the installed linux64 executables.
VCS       ?= setarch x86_64 --uname-2.6 vcs
SIM       ?= setarch x86_64 --uname-2.6 $(SIMV)

VERDI_HOME ?= /opt/synopsys/verdi/Verdi_O-2018.09-SP2
NOVAS_PLI   := $(VERDI_HOME)/share/PLI/VCS/linux64

VCS_FLAGS := -full64 -sverilog -ntb_opts uvm-1.2 \
	-timescale=1ns/1ps \
	-top $(TOP) \
	-f $(FILELIST) \
	-Mdir=$(BUILD_DIR)/csrc \
	-o $(SIMV) \
	-debug_access+all -kdb \
	-P $(NOVAS_PLI)/novas.tab $(NOVAS_PLI)/pli.a \
	-l $(LOG_DIR)/compile.log

SIM_FLAGS := +UVM_TESTNAME=$(TEST) \
	+UVM_VERBOSITY=$(VERBOSITY) \
	+ntb_random_seed=$(SEED) \
	-l $(LOG_DIR)/$(TEST)_$(SEED).log

ifeq ($(DUMP),1)
SIM_FLAGS += +DUMP_FSDB +FSDB_FILE=$(WAVE_DIR)/$(TEST)_$(SEED).fsdb
endif

.PHONY: all compile run sim dump verdi dve clean help FORCE

all: run

$(BUILD_DIR) $(LOG_DIR) $(WAVE_DIR):
	mkdir -p $@

compile: $(SIMV)

$(SIMV): FORCE $(FILELIST) axi_seq_pkg.sv axi_test_pkg.sv dump_fsdb.sv | $(BUILD_DIR) $(LOG_DIR) $(WAVE_DIR)
	$(VCS) $(VCS_FLAGS)

FORCE:

run: compile sim

sim: | $(LOG_DIR) $(WAVE_DIR)
	$(SIM) $(SIM_FLAGS)
	@grep -q "AXI_TC_PASS.*$(TEST) passed" $(LOG_DIR)/$(TEST)_$(SEED).log
	@grep -Eq "UVM_ERROR[[:space:]]*:[[:space:]]*0" $(LOG_DIR)/$(TEST)_$(SEED).log
	@grep -Eq "UVM_FATAL[[:space:]]*:[[:space:]]*0" $(LOG_DIR)/$(TEST)_$(SEED).log

dump:
	$(MAKE) run DUMP=1 TEST=$(TEST) SEED=$(SEED) VERBOSITY=$(VERBOSITY)

verdi:
	verdi -ssf $(WAVE_DIR)/$(TEST)_$(SEED).fsdb &

dve:
	$(SIM) -gui $(SIM_FLAGS) &

clean:
	rm -rf $(BUILD_DIR) $(LOG_DIR) $(WAVE_DIR) csrc simv.daidir \
		ucli.key vc_hdrs.h novas_dump.log verdi_config_file

help:
	@echo "make run                         compile and run the default test"
	@echo "make run TEST=<uvm_test> SEED=N run another test/seed"
	@echo "make dump                        run with an FSDB waveform"
	@echo "make verdi                       open the generated FSDB"
	@echo "make clean                       remove generated outputs"
