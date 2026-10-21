`ifndef TP_CONCURRENCY_RANDOM_SV
`define TP_CONCURRENCY_RANDOM_SV

// Covers: F08
// Testplan: tp_concurrency_random
// Minimum campaign: 20_000 transactions
// Expected result: PASS
class tp_concurrency_random extends axi_cr_base_test;

  `uvm_component_utils(tp_concurrency_random)

  function new(string name = "tp_concurrency_random",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void configure_cr_cfg();
    cr_cfg.transaction_count = 20_000;
    cr_cfg.request_delay_min = 0;
    cr_cfg.request_delay_max = 0;
    cr_cfg.write_gap_min = 0;
    cr_cfg.write_gap_max = 0;
    cr_cfg.ready_delay_min = 2;
    cr_cfg.ready_delay_max = 8;
    cr_cfg.response_delay_min = 1;
    cr_cfg.response_delay_max = 3;
    cr_cfg.no_progress_timeout_cycles = 256;
    cr_cfg.constrain_read_id_to_route = 1'b1;
  endfunction

  virtual function axi_stage6_base_vseq create_vseq();
    axi_cr_concurrency_vseq vseq;
    vseq = axi_cr_concurrency_vseq::type_id::create("vseq");
    vseq.cfg = cr_cfg;
    cr_vseq = vseq;
    expected_response_count = cr_cfg.expected_response_count();
    return vseq;
  endfunction

  virtual task finish_stage6_test();
    int unsigned two_endpoint_percent;
    int unsigned all_endpoint_percent;
    int unsigned planned_all_endpoint_percent;
    axi_cr_concurrency_vseq concurrency_vseq;

    two_endpoint_percent = 0;
    all_endpoint_percent = 0;
    planned_all_endpoint_percent = 0;
    if (traffic_active_cycles != 0) begin
      two_endpoint_percent =
        (100 * two_endpoint_active_cycles) / traffic_active_cycles;
      all_endpoint_percent =
        (100 * all_endpoint_active_cycles) / traffic_active_cycles;
    end
    if ($cast(concurrency_vseq, cr_vseq) &&
        (concurrency_vseq.synchronized_round_count != 0))
      planned_all_endpoint_percent =
        (100 * concurrency_vseq.full_six_endpoint_round_count) /
        concurrency_vseq.synchronized_round_count;

    `uvm_info("AXI_CR_CONCURRENCY", $sformatf(
      {"active_cycles=%0d observed_at_least_two=%0d%% ",
       "observed_all_six=%0d%% max_active_endpoints=%0d ",
       "planned_all_six_rounds=%0d%%"},
      traffic_active_cycles, two_endpoint_percent,
      all_endpoint_percent, max_active_endpoints,
      planned_all_endpoint_percent), UVM_LOW)

    if (cr_cfg.transaction_count >= 20_000) begin
      if (planned_all_endpoint_percent < 20)
        `uvm_error("AXI_CR_CONCURRENCY",
          "Planned rounds with all six selected endpoints are below 20%")
    end
    super.finish_stage6_test();
  endtask

endclass

`endif
