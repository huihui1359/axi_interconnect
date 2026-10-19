`ifndef TP_OUTSTANDING_MIXED_RW_SV
`define TP_OUTSTANDING_MIXED_RW_SV

class tp_outstanding_mixed_rw extends axi_stage3_base_test;

  `uvm_component_utils(tp_outstanding_mixed_rw)

  function new(string name = "tp_outstanding_mixed_rw",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage3_mixed_rw_seq scenario;

    phase.raise_objection(this);
    configure_ready_fixed(0, 0, 0, 0, 0);
    scenario = axi_stage3_mixed_rw_seq::type_id::create("scenario");
    wait_for_reset_release();
    env.stage3_checker.set_expected_counts(4, 4);
    start_stage3_scenario(scenario);
    wait_for_stage3_counts(4, 4);
    finish_stage3_test("tp_outstanding_mixed_rw",
                       4, 4, 0, 0, 1'b1, 1'b1);
    phase.drop_objection(this);
  endtask

endclass

`endif
