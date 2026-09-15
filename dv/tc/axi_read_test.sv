`ifndef AXI_READ_TEST_SV
`define AXI_READ_TEST_SV

class axi_read_test extends axi_base_test;

  `uvm_component_utils(axi_read_test)

  extern function new(string name = "axi_read_test",
                      uvm_component parent = null);
  extern virtual task run_phase(uvm_phase phase);

endclass

function axi_read_test::new(
  string name = "axi_read_test",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

task axi_read_test::run_phase(uvm_phase phase);
  m_read_seq_t read_seq;
  s_reactive_seq_t reactive_seq;

  phase.raise_objection(this);
  wait_for_reset_release();

  read_seq = m_read_seq_t::type_id::create("read_seq");
  read_seq.id   = 4'h5;
  read_seq.addr = 32'h0000_0100;

  reactive_seq = s_reactive_seq_t::type_id::create("reactive_seq");
  reactive_seq.response_count = 1;
  reactive_seq.read_data_base = 32'hCAFE_BABE;
  reactive_seq.response_code  = AXI_RESP_OKAY;

  fork
    reactive_seq.start(env.s_agents[0].sequencer);
    read_seq.start(env.m_agents[0].sequencer);
  join

  wait ((env.e2e_checker.ar_match_count == 1) &&
        (env.e2e_checker.r_match_count  == 1));
  finish_test("axi_read_test");
  phase.drop_objection(this);
endtask

`endif
