`ifndef AXI_TEST_ENV_SV
`define AXI_TEST_ENV_SV

class axi_test_env extends env_t;

  e2e_checker_t e2e_checker;

  `uvm_component_utils(axi_test_env)

  extern function new(string name = "axi_test_env",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass

function axi_test_env::new(
  string name = "axi_test_env",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

function void axi_test_env::build_phase(uvm_phase phase);
  super.build_phase(phase);
  e2e_checker = e2e_checker_t::type_id::create("e2e_checker", this);
endfunction

function void axi_test_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  m_agents[0].monitor.channel_ap.connect(e2e_checker.upstream_export);
  s_agents[0].monitor.channel_ap.connect(e2e_checker.downstream_export);
endfunction

`endif
