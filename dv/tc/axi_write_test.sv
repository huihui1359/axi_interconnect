`ifndef AXI_WRITE_TEST_SV
`define AXI_WRITE_TEST_SV

class axi_write_test extends axi_base_test;

  `uvm_component_utils(axi_write_test)

  extern function new(string name = "axi_write_test",
                      uvm_component parent = null);
  extern virtual task run_phase(uvm_phase phase);

endclass

function axi_write_test::new(
  string name = "axi_write_test",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

task axi_write_test::run_phase(uvm_phase phase);
  m_write_seq_t write_seq;
  s_reactive_seq_t reactive_seq;

  phase.raise_objection(this);
  wait_for_reset_release();

  write_seq = m_write_seq_t::type_id::create("write_seq");
  write_seq.id   = 4'h5;
  write_seq.addr = 32'h0000_0080;
  write_seq.data = 32'hDEAD_BEEF;
  write_seq.strb = 4'hF;

  reactive_seq = s_reactive_seq_t::type_id::create("reactive_seq");
  reactive_seq.response_count = 1;
  reactive_seq.response_code  = AXI_RESP_OKAY;

  fork
    reactive_seq.start(env.s_agents[0].sequencer);
    write_seq.start(env.m_agents[0].sequencer);
  join

  wait ((env.e2e_checker.aw_match_count == 1) &&
        (env.e2e_checker.w_match_count  == 1) &&
        (env.e2e_checker.b_match_count  == 1));
  finish_test("axi_write_test");
  phase.drop_objection(this);
endtask

`endif
