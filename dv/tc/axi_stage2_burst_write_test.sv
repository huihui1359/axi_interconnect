`ifndef AXI_STAGE2_BURST_WRITE_TEST_SV
`define AXI_STAGE2_BURST_WRITE_TEST_SV

class axi_stage2_burst_write_test extends axi_stage2_base_test;

  `uvm_component_utils(axi_stage2_burst_write_test)

  function new(string name = "axi_stage2_burst_write_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage2_burst_write_sequence scenario;

    phase.raise_objection(this);
    configure_ready_fixed(0, 0, 0, 0, 0);
    scenario = axi_stage2_burst_write_sequence::type_id::create("scenario");
    wait_for_reset_release();
    run_stage2_scenario(scenario, 36, 0,
                        "axi_stage2_burst_write_test");
    phase.drop_objection(this);
  endtask

endclass

`endif
