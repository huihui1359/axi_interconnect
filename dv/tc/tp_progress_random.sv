`ifndef TP_PROGRESS_RANDOM_SV
`define TP_PROGRESS_RANDOM_SV

// Covers: F23
// Testplan: tp_progress_random
// Minimum campaign: 10_000 transactions
// Expected result: PASS
class tp_progress_random extends axi_cr_base_test;

  `uvm_component_utils(tp_progress_random)

  function new(string name = "tp_progress_random",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_cr_cfg();
    cr_cfg.transaction_count = 10_000;
    cr_cfg.request_delay_min = 0;
    cr_cfg.request_delay_max = 0;
    cr_cfg.write_gap_min = 0;
    cr_cfg.write_gap_max = 0;
    cr_cfg.ready_delay_min = 0;
    cr_cfg.ready_delay_max = 32;
    cr_cfg.response_delay_min = 0;
    cr_cfg.response_delay_max = 0;
    // This is a global completed-response watchdog, not the per-channel
    // 32-cycle release observation bound checked below.
    cr_cfg.no_progress_timeout_cycles = 1_024;
    cr_cfg.constrain_read_id_to_route = 1'b1;
  endfunction

  virtual task finish_stage6_test();
    `uvm_info("AXI_CR_PROGRESS", $sformatf(
      "max_no_response_progress=%0d %s",
      observed_max_no_progress_cycles, stall_coverage_summary()), UVM_LOW)
    super.finish_stage6_test();
  endtask

endclass

`endif
