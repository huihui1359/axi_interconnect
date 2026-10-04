`ifndef AXI_STAGE6_TESTS_SV
`define AXI_STAGE6_TESTS_SV

class axi_stage6_route_matrix_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_route_matrix_test)
  function new(string name="axi_stage6_route_matrix_test", uvm_component parent=null); super.new(name,parent); expected_response_count=18; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_route_matrix_vseq::type_id::create("vseq"); endfunction
endclass

class axi_stage6_id_matrix_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_id_matrix_test)
  function new(string name="axi_stage6_id_matrix_test", uvm_component parent=null); super.new(name,parent); expected_response_count=4; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_id_matrix_vseq::type_id::create("vseq"); endfunction
endclass

class axi_stage6_multi_slave_parallel_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_multi_slave_parallel_test)
  function new(string name="axi_stage6_multi_slave_parallel_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_multi_slave_parallel_vseq::type_id::create("vseq"); endfunction
endclass

class axi_stage6_multi_master_write_arb_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_multi_master_write_arb_test)
  function new(string name="axi_stage6_multi_master_write_arb_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_multi_master_write_arb_vseq::type_id::create("vseq"); endfunction
  virtual task configure_stage6_ready();
    super.configure_stage6_ready();
    env.s_agents[0].driver.awready_latency.fixed_delay = 3;
    env.s_agents[0].driver.wready_latency.fixed_delay = 3;
  endtask
endclass

class axi_stage6_multi_master_read_arb_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_multi_master_read_arb_test)
  function new(string name="axi_stage6_multi_master_read_arb_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_multi_master_read_arb_vseq::type_id::create("vseq"); endfunction
  virtual task configure_stage6_ready();
    super.configure_stage6_ready();
    env.s_agents[1].driver.arready_latency.fixed_delay = 3;
  endtask
endclass

class axi_stage6_response_arb_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_response_arb_test)
  function new(string name="axi_stage6_response_arb_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_response_arb_vseq::type_id::create("vseq"); endfunction
  virtual task configure_stage6_ready();
    super.configure_stage6_ready();
    env.m_agents[0].driver.rready_latency.fixed_delay = 3;
  endtask
endclass

class axi_stage6_cross_master_same_id_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_cross_master_same_id_test)
  function new(string name="axi_stage6_cross_master_same_id_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_cross_master_same_id_vseq::type_id::create("vseq"); endfunction
endclass

class axi_stage6_multiport_outstanding_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_multiport_outstanding_test)
  function new(string name="axi_stage6_multiport_outstanding_test", uvm_component parent=null); super.new(name,parent); expected_response_count=12; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_multiport_outstanding_vseq::type_id::create("vseq"); endfunction
endclass

class axi_stage6_random_smoke_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_random_smoke_test)
  function new(string name="axi_stage6_random_smoke_test", uvm_component parent=null); super.new(name,parent); expected_response_count=9; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_random_smoke_vseq::type_id::create("vseq"); endfunction
endclass

`endif
