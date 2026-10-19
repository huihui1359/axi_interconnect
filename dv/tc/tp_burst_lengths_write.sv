`ifndef TP_BURST_LENGTHS_WRITE_SV
`define TP_BURST_LENGTHS_WRITE_SV

class tp_burst_lengths_write extends axi_stage2_base_test;

  `uvm_component_utils(tp_burst_lengths_write)

  function new(string name = "tp_burst_lengths_write",
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
                        "tp_burst_lengths_write");
    phase.drop_objection(this);
  endtask

endclass

`endif
