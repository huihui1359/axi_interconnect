# VCS/UVM build, regression, selftest, waveform and coverage flow.
# Run all commands from this sim_vcs directory. Generated files stay in work/.

SHELL := /bin/bash

.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

PRO_HOME := $(CURDIR)
WORK_DIR := $(PRO_HOME)/work

# Reference-style switches. Existing uppercase command-line options still work
# and take precedence over their lowercase aliases.
test        ?= tp_read_end_to_end
dump        ?= n
cov         ?= n
rand        ?= n
suite       ?=
reg_times   ?= $(if $(suite),1,20)
nseeds      ?= $(reg_times)
stop_on_fail ?= n
UVM_VERBO   ?= UVM_LOW

TOP         ?= tb
TEST        ?= $(test)
REG_TIMES   ?= $(nseeds)
VERBOSITY   ?= $(if $(filter UVM_%,$(UVM_VERBO)),$(UVM_VERBO),UVM_$(UVM_VERBO))
DUMP        ?= $(dump)
COV         ?= $(cov)
RAND        ?= $(rand)
BASE_SEED   ?= $(SEED)
SIM_EXTRA   ?=
VCS_EXTRA   ?=

# Lowercase seed is an alias; an explicit numeric SEED/seed wins over rand.
ifneq ($(origin seed),undefined)
SEED ?= $(seed)
endif
TIME_SEED := $(if $(filter undefined,$(origin SEED)),$(filter y 1,$(RAND)))
ifneq ($(TIME_SEED),)
# Reference time source, expanded once for one simulation.
SEED := $(shell date +%N)
else
SEED ?= 0
endif

FILELIST    ?= sim.f
SELFTEST_FILELIST ?= selftest.f
LOG_DIR     ?= $(WORK_DIR)/log
WAVE_DIR    ?= $(WORK_DIR)/wave
COV_DIR     ?= $(WORK_DIR)/cov

BUILD_FLAVOR  = $(if $(filter y 1,$(COV)),cov,nocov)
BUILD_DIR    ?= $(WORK_DIR)/build/$(BUILD_FLAVOR)
SIMV          = $(BUILD_DIR)/simv
COV_DB       ?= $(COV_DIR)/axi_interconnect.vdb
COV_REPORT   ?= $(COV_DIR)/report
COV_METRICS  ?= line+cond+fsm+tgl+branch+assert
COV_HIER     ?= coverage_hier.cfg

# Overrides remain relative to sim_vcs/, even though tools execute in work/.
override BUILD_DIR := $(abspath $(BUILD_DIR))
override LOG_DIR := $(abspath $(LOG_DIR))
override WAVE_DIR := $(abspath $(WAVE_DIR))
override COV_DIR := $(abspath $(COV_DIR))
override COV_DB := $(abspath $(COV_DB))
override COV_REPORT := $(abspath $(COV_REPORT))

MAIN_SOURCES := $(shell find ../dv ../rtl -type f \
	\( -name '*.sv' -o -name '*.svh' -o -name '*.v' \) -print) \
	$(FILELIST) dump_fsdb.sv Makefile

ifneq ($(filter y 1,$(COV)),)
MAIN_SOURCES += $(COV_HIER)
endif

# Group by verification intent, independent of development stages.
# Directed scenarios may still randomize payloads or channel timing.
DIRECTED_TESTS := \
	tp_write_end_to_end \
	tp_read_end_to_end \
	tp_burst_lengths_write \
	tp_burst_lengths_read \
	tp_burst_lengths_gap \
	tp_write_end_to_end_aw_w_order \
	tp_channel_backpressure \
	tp_concurrency_read_write_parallel \
	tp_sid_table_depth_write \
	tp_sid_table_depth_read \
	tp_sid_membership_write_ooo \
	tp_sid_membership_read_ooo \
	tp_sid_membership_same_id_order \
	tp_outstanding_mixed_rw \
	tp_sid_exhaustive_local \
	tp_backpressure_outstanding \
	tp_backpressure_random_stage2_smoke \
	tp_route_matrix_directed \
	tp_sid_exhaustive \
	tp_three_target_parallel \
	tp_mtos_round_robin_write \
	tp_mtos_round_robin_read \
	tp_stom_round_robin \
	tp_sid_membership_cross_master \
	tp_read_outstanding_multiport

# Include both randomized traffic and directed scenarios with random timing.
RANDOM_TESTS := \
	tp_backpressure_random_stage2_smoke \
	tp_backpressure_outstanding \
	tp_route_matrix_random \
	tp_backpressure_random \
	tp_sid_random \
	tp_progress_random \
	tp_concurrency_random

SMOKE_TESTS := \
	tp_read_end_to_end \
	tp_write_end_to_end \
	tp_burst_lengths_read \
	tp_burst_lengths_write \
	tp_route_matrix_directed \
	tp_sid_membership_same_id_order \
	tp_mtos_round_robin_write \
	tp_backpressure_random_stage2_smoke

# A test shared by directed and random runs only once in the full suite.
ALL_TESTS := $(DIRECTED_TESTS) $(filter-out $(DIRECTED_TESTS),$(RANDOM_TESTS))
SUITE_smoke    := $(SMOKE_TESTS)
SUITE_directed := $(DIRECTED_TESTS)
SUITE_random   := $(RANDOM_TESTS)
SUITE_full     := $(ALL_TESTS)
REGRESS_TESTS = $(if $(suite),$(SUITE_$(suite)),$(TEST))

SELFTESTS := \
	axi_protocol_assertions_selftest \
	axi_stage3_protocol_assertions_selftest \
	axi_switch_ref_model_selftest \
	axi_stage6_ref_model_selftest \
	axi_stage6_protocol_assertions_selftest \
	axi_stage6_arbiter_assertions_selftest

axi_protocol_assertions_selftest_MARKER        := AXI_ASSERT_SELFTEST_PASS
axi_stage3_protocol_assertions_selftest_MARKER := AXI_STAGE3_ASSERT_SELFTEST_PASS
axi_switch_ref_model_selftest_MARKER           := AXI_SWITCH_MODEL_SELFTEST_PASS
axi_stage6_ref_model_selftest_MARKER           := AXI_STAGE6_REF_MODEL_SELFTEST_PASS
axi_stage6_protocol_assertions_selftest_MARKER := AXI_STAGE6_ASSERT_SELFTEST_PASS
axi_stage6_arbiter_assertions_selftest_MARKER  := AXI_STAGE6_ARBITER_SELFTEST_PASS

# VCS O-2018 predates WSL2's kernel version.  UNAME26 makes its platform
# detection select the installed linux64 executables.
VCS       ?= setarch x86_64 --uname-2.6 vcs
SIM       ?= setarch x86_64 --uname-2.6 $(SIMV)
URG       ?= urg
VERDI     ?= verdi

VERDI_HOME ?= /opt/synopsys/verdi/Verdi_O-2018.09-SP2
NOVAS_PLI   := $(VERDI_HOME)/share/PLI/VCS/linux64

VCS_COMMON_FLAGS := -full64 -sverilog -ntb_opts uvm-1.2 \
	-timescale=1ns/1ps \
	-debug_access+all -kdb \
	-P $(NOVAS_PLI)/novas.tab $(NOVAS_PLI)/pli.a

ifneq ($(filter y 1,$(COV)),)
VCS_COV_FLAGS := -cm $(COV_METRICS) -cm_dir $(COV_DB) -cm_hier $(abspath $(COV_HIER))
SIM_COV_FLAGS := -cm $(COV_METRICS) -cm_dir $(COV_DB) \
	-cm_name $(TEST)_$(SEED)
endif

VCS_FLAGS := $(VCS_COMMON_FLAGS) $(VCS_COV_FLAGS) \
	-top $(TOP) -F $(abspath $(FILELIST)) \
	-Mdir=$(BUILD_DIR)/csrc -o $(SIMV) \
	-l $(LOG_DIR)/compile_$(BUILD_FLAVOR).log $(VCS_EXTRA)

SIM_FLAGS := +UVM_TESTNAME=$(TEST) \
	+UVM_VERBOSITY=$(VERBOSITY) \
	+UVM_NO_RELNOTES \
	+ntb_random_seed=$(SEED) \
	-l $(LOG_DIR)/$(TEST)_$(SEED).log \
	$(SIM_COV_FLAGS) $(SIM_EXTRA)

ifneq ($(filter y 1,$(DUMP)),)
SIM_FLAGS += +DUMP_FSDB +FSDB_FILE=$(WAVE_DIR)/$(TEST)_$(SEED).fsdb
endif

.PHONY: all com compile run sim dump verdi debug dve list-tests validate-test \
	regress repeat smoke_regress directed_regress random_regress full_regress \
	validate-regress coverage cov cov_report urg selftest selftests clean clean_all help

all: run

$(WORK_DIR) $(BUILD_DIR) $(LOG_DIR) $(WAVE_DIR) $(COV_DIR):
	mkdir -p $@

com: compile

compile: $(SIMV)

$(SIMV): $(MAIN_SOURCES) | $(WORK_DIR) $(BUILD_DIR) $(LOG_DIR) $(WAVE_DIR) $(COV_DIR)
	cd $(WORK_DIR) && $(VCS) $(VCS_FLAGS)

run: sim

validate-test:
	@case " $(ALL_TESTS) " in *" $(TEST) "*) ;; *) echo "unknown test: $(TEST); use make list-tests"; exit 2 ;; esac

sim: validate-test compile | $(LOG_DIR) $(WAVE_DIR)
	@echo "[SIM] TEST=$(TEST) SEED=$(SEED) COV=$(COV) DUMP=$(DUMP)"
	cd $(WORK_DIR) && $(SIM) $(SIM_FLAGS)
	@grep -q "AXI_TC_PASS.*$(TEST) passed" $(LOG_DIR)/$(TEST)_$(SEED).log
	@grep -Eq "UVM_ERROR[[:space:]]*:[[:space:]]*0" $(LOG_DIR)/$(TEST)_$(SEED).log
	@grep -Eq "UVM_FATAL[[:space:]]*:[[:space:]]*0" $(LOG_DIR)/$(TEST)_$(SEED).log

dump:
	$(MAKE) run DUMP=1 TEST=$(TEST) SEED=$(SEED) VERBOSITY=$(VERBOSITY)

validate-regress:
	@if [ -n "$(suite)" ] && { [ "$(origin test)" = "command line" ] || [ "$(origin TEST)" = "command line" ]; }; then echo "choose either suite or test, not both"; exit 2; fi
	@test -n "$(REGRESS_TESTS)" || { echo "unknown suite: $(suite); choose smoke, directed, random or full"; exit 2; }
	@case " $(ALL_TESTS) " in *" $(TEST) "*) ;; *) if [ -z "$(suite)" ]; then echo "unknown test: $(TEST)"; exit 2; fi ;; esac
	@if [ -z "$(TIME_SEED)" ]; then [[ "$(BASE_SEED)" =~ ^[0-9]+$$ ]] || { echo "BASE_SEED/SEED must be a nonnegative integer"; exit 2; }; fi
	@[[ "$(REG_TIMES)" =~ ^[0-9]+$$ ]] && [ "$(REG_TIMES)" -gt 0 ] || { echo "nseeds/reg_times must be a positive integer"; exit 2; }

# Each test uses the same fixed seed sequence, unaffected by suite membership.
# Time-based seeds are generated inside the loop, once for each simulation.
regress: validate-regress compile
	@total=0; failed=0; \
	for test_name in $(REGRESS_TESTS); do \
		for ((index=0; index<10#$(REG_TIMES); index++)); do \
			if [ -n "$(TIME_SEED)" ]; then seed=$$(date +%N); \
			else seed=$$(( 10#$(BASE_SEED) + index )); fi; \
			echo "[REGRESS] TEST=$$test_name SEED=$$seed COV=$(COV) DUMP=$(DUMP)"; \
			total=$$((total + 1)); \
			if $(MAKE) --no-print-directory sim TEST=$$test_name SEED=$$seed \
				COV=$(COV) DUMP=$(DUMP) VERBOSITY=$(VERBOSITY); then :; \
			else failed=$$((failed + 1)); \
				if [[ "$(stop_on_fail)" == y || "$(stop_on_fail)" == 1 ]]; then exit 1; fi; \
			fi; \
		done; \
	done; \
	echo "[SUMMARY] total=$$total passed=$$((total - failed)) failed=$$failed"; \
	test $$failed -eq 0

repeat: regress

smoke_regress:
	$(MAKE) regress suite=smoke

directed_regress:
	$(MAKE) regress suite=directed

random_regress:
	$(MAKE) regress suite=random

full_regress:
	$(MAKE) regress suite=full

coverage:
	$(MAKE) full_regress COV=1

cov_report:
	@test -d "$(COV_DB)" || { echo "coverage database not found: $(COV_DB)"; exit 1; }
	cd $(WORK_DIR) && $(URG) -full64 -dir $(COV_DB) -report $(COV_REPORT) \
		-metric line+cond+fsm+tgl+branch+assert+group -format both -show testrecords

SELFTEST ?= axi_protocol_assertions_selftest
SELFTEST_FILE      = $(PRO_HOME)/../dv/tb/$(SELFTEST).sv
SELFTEST_EXTRA_axi_stage6_arbiter_assertions_selftest = $(PRO_HOME)/../dv/env/axi_stage6_arbiter_assertions.sv
SELFTEST_EXTRA     = $(SELFTEST_EXTRA_$(SELFTEST))
SELFTEST_MARKER    = $($(SELFTEST)_MARKER)
SELFTEST_BUILD_DIR = $(WORK_DIR)/build/selftest/$(SELFTEST)
SELFTEST_SIMV      = $(SELFTEST_BUILD_DIR)/simv
SELFTEST_LOG       = $(LOG_DIR)/$(SELFTEST).log

selftest: | $(WORK_DIR) $(LOG_DIR)
	@test -n "$(SELFTEST_MARKER)" || { echo "unknown SELFTEST=$(SELFTEST)"; exit 2; }
	@mkdir -p $(SELFTEST_BUILD_DIR)
	cd $(WORK_DIR) && $(VCS) $(VCS_COMMON_FLAGS) -top $(SELFTEST) -F $(abspath $(SELFTEST_FILELIST)) \
		$(SELFTEST_EXTRA) $(SELFTEST_FILE) \
		-Mdir=$(SELFTEST_BUILD_DIR)/csrc -o $(SELFTEST_SIMV) \
		-l $(LOG_DIR)/compile_$(SELFTEST).log
	cd $(WORK_DIR) && setarch x86_64 --uname-2.6 $(SELFTEST_SIMV) +UVM_NO_RELNOTES -l $(SELFTEST_LOG)
	@grep -q "$(SELFTEST_MARKER)" $(SELFTEST_LOG)

selftests:
	@for selftest_name in $(SELFTESTS); do \
		echo "[SELFTEST] $$selftest_name"; \
		$(MAKE) --no-print-directory selftest SELFTEST=$$selftest_name || exit $$?; \
	done

list-tests:
	@echo "Smoke ($(words $(SMOKE_TESTS))): $(SMOKE_TESTS)"
	@echo "Directed ($(words $(DIRECTED_TESTS))): $(DIRECTED_TESTS)"
	@echo "Random ($(words $(RANDOM_TESTS))): $(RANDOM_TESTS)"
	@echo "Full ($(words $(ALL_TESTS)) unique): $(ALL_TESTS)"
	@echo "Selftests ($(words $(SELFTESTS))): $(SELFTESTS)"

# GUI tools also run inside work/ so their auxiliary files stay there.
verdi: | $(WORK_DIR)
	@test -f "$(WAVE_DIR)/$(TEST)_$(SEED).fsdb" || { echo "FSDB not found; run make sim dump=y with the same test and SEED"; exit 1; }
	cd $(WORK_DIR) && $(VERDI) -ntb_opts uvm-1.2 -sverilog \
		-F $(abspath $(FILELIST)) -top $(TOP) -ssf $(WAVE_DIR)/$(TEST)_$(SEED).fsdb

debug: | $(WORK_DIR)
	cd $(WORK_DIR) && $(VERDI) -ntb_opts uvm-1.2 -sverilog \
		-F $(abspath $(FILELIST)) -top $(TOP) -uvmDebug

dve: compile
	cd $(WORK_DIR) && $(SIM) -gui $(SIM_FLAGS)

urg: cov_report

cov: | $(WORK_DIR)
	@test -d "$(COV_DB)" || { echo "coverage database not found: $(COV_DB)"; exit 1; }
	cd $(WORK_DIR) && $(VERDI) -cov -covdir $(COV_DB)

# Explicit build paths avoid the reference Makefile's filename-filter cleanup.
# Existing outputs outside work/ belong to the previous flow and are untouched.
clean:
	rm -rf -- $(WORK_DIR)/build

clean_all:
	rm -rf -- $(WORK_DIR)

help:
	@echo "make [all]                       compile and run; default test=tp_read_end_to_end"
	@echo "make com                         compile only (compile is an alias)"
	@echo "make sim test=<tp_name> SEED=N dump=y cov=y rand=n"
	@echo "make regress suite=smoke|directed|random|full nseeds=N rand=y"
	@echo "make regress test=<tp_name> reg_times=N BASE_SEED=N"
	@echo "make smoke_regress               run 8 representative short tests"
	@echo "make directed_regress            run 25 directed scenarios"
	@echo "make random_regress              run 7 random traffic/timing scenarios"
	@echo "make full_regress                run all 30 UVM tests without duplicates"
	@echo "Suites default to one seed/test; selected-test regress defaults to 20."
	@echo "Default seed=0; rand=y uses date +%N; explicit SEED/seed takes precedence."
	@echo "Regression continues after failures; stop_on_fail=y stops immediately."
	@echo "make selftests                   run all six checker/model selftests"
	@echo "make selftest SELFTEST=<top>      run one independent selftest"
	@echo "make coverage                    full regression with coverage enabled"
	@echo "make urg / cov_report            generate URG HTML/text reports"
	@echo "make cov                         open coverage in Verdi"
	@echo "make list-tests                  list test collections"
	@echo "make verdi test=<tp_name> SEED=N  open an existing FSDB"
	@echo "make debug                       open sources in Verdi"
	@echo "make clean / clean_all           remove work/build or all of work/"
	@echo "TEST/DUMP/COV/RAND/REG_TIMES/VERBOSITY override lowercase aliases."
	@echo "SIM_EXTRA='<plusargs>' and VCS_EXTRA='<flags>' append tool options."
