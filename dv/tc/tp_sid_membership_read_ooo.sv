`ifndef TP_SID_MEMBERSHIP_READ_OOO_SV
`define TP_SID_MEMBERSHIP_READ_OOO_SV

class tp_sid_membership_read_ooo extends axi_stage3_base_test;

  `uvm_component_utils(tp_sid_membership_read_ooo)

  function new(string name = "tp_sid_membership_read_ooo",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    axi_stage3_read_ooo_seq scenario;

    phase.raise_objection(this);
    configure_ready_fixed(0, 0, 0, 0, 0);
    scenario = axi_stage3_read_ooo_seq::type_id::create("scenario");
    wait_for_reset_release();
    env.stage3_checker.set_expected_counts(0, 4);
    start_stage3_scenario(scenario);
    wait_for_stage3_counts(0, 4);
    finish_stage3_test("tp_sid_membership_read_ooo",
                       0, 4, 0, 4, 1'b1);
    phase.drop_objection(this);
  endtask

endclass

`endif
