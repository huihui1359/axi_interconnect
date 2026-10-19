`ifndef TP_SID_EXHAUSTIVE_LOCAL_SV
`define TP_SID_EXHAUSTIVE_LOCAL_SV

class tp_sid_exhaustive_local extends axi_stage3_base_test;

  `uvm_component_utils(tp_sid_exhaustive_local)

  extern function new(string name = "tp_sid_exhaustive_local",
                      uvm_component parent = null);
  extern virtual task run_phase(uvm_phase phase);

endclass

function tp_sid_exhaustive_local::new(
  string name = "tp_sid_exhaustive_local",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

task tp_sid_exhaustive_local::run_phase(uvm_phase phase);
  axi_stage3_id_mapping_seq scenario;

  phase.raise_objection(this);
  configure_ready_fixed(0, 0, 0, 0, 0);
  scenario = axi_stage3_id_mapping_seq::type_id::create("scenario");
  wait_for_reset_release();
  env.stage3_checker.set_expected_counts(4, 4);
  start_stage3_scenario(scenario);
  wait_for_stage3_counts(4, 4);
  finish_stage3_test("tp_sid_exhaustive_local", 4, 4);
  phase.drop_objection(this);
endtask

`endif
