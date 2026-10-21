`ifndef TP_BACKPRESSURE_RANDOM_SV
`define TP_BACKPRESSURE_RANDOM_SV

// Covers: F21
// Testplan: tp_backpressure_random
// Minimum campaign: 10_000 transactions
// Expected result: PASS
class tp_backpressure_random extends axi_cr_base_test;

  `uvm_component_utils(tp_backpressure_random)

  function new(string name = "tp_backpressure_random",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_cr_cfg();
    cr_cfg.transaction_count = 10_000;
    cr_cfg.ready_delay_min = 0;
    cr_cfg.ready_delay_max = 20;
    cr_cfg.no_progress_timeout_cycles = 256;
    cr_cfg.constrain_read_id_to_route = 1'b1;
  endfunction

  virtual task finish_stage6_test();
    `uvm_info("AXI_CR_STALL_COV", stall_coverage_summary(), UVM_LOW)
    if ((cr_cfg.transaction_count >= 10_000) &&
        !all_stall_buckets_hit())
      `uvm_error("AXI_CR_STALL_COV",
        {"Full backpressure campaign missed one or more ",
         "AW/W/B/AR/R stall buckets: ", stall_coverage_summary()})
    super.finish_stage6_test();
  endtask

endclass

// Compatibility smoke retained for the historical Stage 2 regression.
class tp_backpressure_random_stage2_smoke extends axi_stage2_base_test;

  `uvm_component_utils(tp_backpressure_random_stage2_smoke)

  function new(string name = "tp_backpressure_random_stage2_smoke",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage2_ready_random_smoke_sequence scenario;

    phase.raise_objection(this);
    configure_ready_random(0, 100);
    scenario = axi_stage2_ready_random_smoke_sequence::type_id::create(
      "scenario"
    );
    wait_for_reset_release();
    run_stage2_scenario(scenario, 8, 8,
                        "tp_backpressure_random_stage2_smoke");
    phase.drop_objection(this);
  endtask

endclass

`endif
