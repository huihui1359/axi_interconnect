`ifndef TP_READ_END_TO_END_SV
`define TP_READ_END_TO_END_SV

class tp_read_end_to_end extends axi_base_test;

  `uvm_component_utils(tp_read_end_to_end)

  extern function new(string name = "tp_read_end_to_end",
                      uvm_component parent = null);
  extern virtual task run_phase(uvm_phase phase);

endclass

function tp_read_end_to_end::new(
  string name = "tp_read_end_to_end",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

task tp_read_end_to_end::run_phase(uvm_phase phase);
  axi_m_single_read_seq read_seq;
  axi_s_single_reactive_seq reactive_seq;

  phase.raise_objection(this);
  wait_for_reset_release();

  read_seq = axi_m_single_read_seq #()::type_id::create("read_seq");
  read_seq.id   = 4'h5;
  read_seq.addr = 32'h0000_0100;

  reactive_seq = axi_s_single_reactive_seq #()::type_id::create(
    "reactive_seq"
  );
  reactive_seq.response_count = 1;
  reactive_seq.read_data      = 32'hCAFE_BABE;
  reactive_seq.response_code  = AXI_RESP_OKAY;

  fork
    reactive_seq.start(env.s_agents[0].sequencer);
    read_seq.start(env.m_agents[0].sequencer);
  join

  while ((env.stage1_checker.ar_match_count != 1) ||
         (env.stage1_checker.r_match_count  != 1))
    @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
  finish_test("tp_read_end_to_end");
  phase.drop_objection(this);
endtask

`endif
