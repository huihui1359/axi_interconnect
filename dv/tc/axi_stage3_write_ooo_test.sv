`ifndef AXI_STAGE3_WRITE_OOO_TEST_SV
`define AXI_STAGE3_WRITE_OOO_TEST_SV

class axi_stage3_write_ooo_test extends axi_stage3_base_test;

  `uvm_component_utils(axi_stage3_write_ooo_test)

  function new(string name = "axi_stage3_write_ooo_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage3_write_ooo_seq scenario;

    phase.raise_objection(this);
    configure_ready_fixed(0, 0, 0, 0, 0);
    scenario = axi_stage3_write_ooo_seq::type_id::create("scenario");
    wait_for_reset_release();
    env.stage3_checker.set_expected_counts(4, 0);
    start_stage3_scenario(scenario);
    wait_for_stage3_counts(4, 0);
    finish_stage3_test("axi_stage3_write_ooo_test",
                       4, 0, 4, 0, 1'b1);
    phase.drop_objection(this);
  endtask

endclass

`endif
