`ifndef TP_BACKPRESSURE_RANDOM_SV
`define TP_BACKPRESSURE_RANDOM_SV

class tp_backpressure_random extends axi_stage2_base_test;

  `uvm_component_utils(tp_backpressure_random)

  function new(string name = "tp_backpressure_random",
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
                        "tp_backpressure_random");
    phase.drop_objection(this);
  endtask

endclass

`endif
