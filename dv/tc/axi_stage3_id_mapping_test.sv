`ifndef AXI_STAGE3_ID_MAPPING_TEST_SV
`define AXI_STAGE3_ID_MAPPING_TEST_SV

class axi_stage3_id_mapping_test extends axi_stage3_base_test;

  `uvm_component_utils(axi_stage3_id_mapping_test)

  extern function new(string name = "axi_stage3_id_mapping_test",
                      uvm_component parent = null);
  extern virtual task run_phase(uvm_phase phase);

endclass

function axi_stage3_id_mapping_test::new(
  string name = "axi_stage3_id_mapping_test",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

task axi_stage3_id_mapping_test::run_phase(uvm_phase phase);
  axi_stage3_id_mapping_seq scenario;

  phase.raise_objection(this);
  configure_ready_fixed(0, 0, 0, 0, 0);
  scenario = axi_stage3_id_mapping_seq::type_id::create("scenario");
  wait_for_reset_release();
  env.stage3_checker.set_expected_counts(4, 4);
  start_stage3_scenario(scenario);
  wait_for_stage3_counts(4, 4);
  finish_stage3_test("axi_stage3_id_mapping_test", 4, 4);
  phase.drop_objection(this);
endtask

`endif
