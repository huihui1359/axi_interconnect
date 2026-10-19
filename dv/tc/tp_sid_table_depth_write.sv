`ifndef TP_SID_TABLE_DEPTH_WRITE_SV
`define TP_SID_TABLE_DEPTH_WRITE_SV

class tp_sid_table_depth_write extends axi_stage3_base_test;

  `uvm_component_utils(tp_sid_table_depth_write)

  function new(string name = "tp_sid_table_depth_write",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage3_outstanding_write_seq scenario;
    int unsigned expected_writes;

    phase.raise_objection(this);
    configure_ready_fixed(0, 0, 0, 0, 0);
    wait_for_reset_release();
    expected_writes = 18;
    env.stage3_checker.set_expected_counts(expected_writes, 0);

    for (int unsigned depth = 1; depth <= 4; depth++) begin
      env_cfg.m_cfg[0].max_write_outstanding = depth;
      scenario = axi_stage3_outstanding_write_seq::type_id::create(
        $sformatf("different_id_depth_%0d", depth)
      );
      scenario.transaction_count = depth + 1;
      start_stage3_scenario(scenario);
      wait_for_stage3_counts(((depth * (depth + 3)) / 2), 0);
    end

    env_cfg.m_cfg[0].max_write_outstanding = 4;
    scenario = axi_stage3_outstanding_write_seq::type_id::create(
      "same_id_depth_4"
    );
    scenario.transaction_count = 4;
    scenario.same_id = 1'b1;
    start_stage3_scenario(scenario);
    wait_for_stage3_counts(expected_writes, 0);
    finish_stage3_test("tp_sid_table_depth_write",
                       expected_writes, 0, 4, 0, 1'b0, 1'b1);
    phase.drop_objection(this);
  endtask

endclass

`endif
