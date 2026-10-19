`ifndef TP_BACKPRESSURE_OUTSTANDING_SV
`define TP_BACKPRESSURE_OUTSTANDING_SV

class tp_backpressure_outstanding extends axi_stage3_base_test;

  `uvm_component_utils(tp_backpressure_outstanding)

  function new(string name = "tp_backpressure_outstanding",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage3_outstanding_stall_seq scenario;

    phase.raise_objection(this);
    configure_ready_random(1, 4);
    scenario = axi_stage3_outstanding_stall_seq::type_id::create("scenario");
    wait_for_reset_release();
    env.stage3_checker.set_expected_counts(4, 4);
    start_stage3_scenario(scenario);
    wait_for_stage3_counts(4, 4);
    finish_stage3_test("tp_backpressure_outstanding",
                       4, 4, 4, 4, 1'b1);
    phase.drop_objection(this);
  endtask

endclass

`endif
