`ifndef TP_SID_TABLE_DEPTH_READ_SV
`define TP_SID_TABLE_DEPTH_READ_SV

class tp_sid_table_depth_read extends axi_stage3_base_test;

  `uvm_component_utils(tp_sid_table_depth_read)

  function new(string name = "tp_sid_table_depth_read",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage3_outstanding_read_seq scenario;
    int unsigned expected_reads;

    phase.raise_objection(this);
    configure_ready_fixed(0, 0, 0, 0, 0);
    wait_for_reset_release();
    expected_reads = 18;
    env.stage3_checker.set_expected_counts(0, expected_reads);

    for (int unsigned depth = 1; depth <= 4; depth++) begin
      env_cfg.m_cfg[0].max_read_outstanding = depth;
      scenario = axi_stage3_outstanding_read_seq::type_id::create(
        $sformatf("different_id_depth_%0d", depth)
      );
      scenario.transaction_count = depth + 1;
      start_stage3_scenario(scenario);
      wait_for_stage3_counts(0, ((depth * (depth + 3)) / 2));
    end

    env_cfg.m_cfg[0].max_read_outstanding = 4;
    scenario = axi_stage3_outstanding_read_seq::type_id::create(
      "same_id_depth_4"
    );
    scenario.transaction_count = 4;
    scenario.same_id = 1'b1;
    start_stage3_scenario(scenario);
    wait_for_stage3_counts(0, expected_reads);
    finish_stage3_test("tp_sid_table_depth_read",
                       0, expected_reads, 0, 4, 1'b0, 1'b1);
    phase.drop_objection(this);
  endtask

endclass

`endif
