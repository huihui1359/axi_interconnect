`ifndef AXI_STAGE2_READY_RANDOM_SMOKE_TEST_SV
`define AXI_STAGE2_READY_RANDOM_SMOKE_TEST_SV

class axi_stage2_ready_random_smoke_test extends axi_stage2_base_test;

  `uvm_component_utils(axi_stage2_ready_random_smoke_test)

  function new(string name = "axi_stage2_ready_random_smoke_test",
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
                        "axi_stage2_ready_random_smoke_test");
    phase.drop_objection(this);
  endtask

endclass

`endif
