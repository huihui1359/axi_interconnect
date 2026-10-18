`ifndef AXI_STAGE6_TESTS_SV
`define AXI_STAGE6_TESTS_SV

// 用例：3x3 路由矩阵全覆盖，每个端口组合各一读一写，共检查 18 个响应。
class axi_stage6_route_matrix_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_route_matrix_test)
  function new(string name="axi_stage6_route_matrix_test", uvm_component parent=null); super.new(name,parent); expected_response_count=18; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_route_matrix_vseq::type_id::create("vseq"); endfunction
endclass

// 用例：M0->S0 覆盖 4 种 transaction tag 并交替读写，共检查 4 个响应。
class axi_stage6_id_matrix_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_id_matrix_test)
  function new(string name="axi_stage6_id_matrix_test", uvm_component parent=null); super.new(name,parent); expected_response_count=4; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_id_matrix_vseq::type_id::create("vseq"); endfunction
endclass

// 用例：M0 并发读取三个 Slave，检查多目标路由，共检查 3 个响应。
class axi_stage6_multi_slave_parallel_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_multi_slave_parallel_test)
  function new(string name="axi_stage6_multi_slave_parallel_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_multi_slave_parallel_vseq::type_id::create("vseq"); endfunction
endclass

// 用例：三个 Master 竞争写 S0，并延迟 S0 AW/W READY 形成仲裁压力，共检查 3 个响应。
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

// 用例：三个 Master 竞争读 S1，并延迟 S1 ARREADY 形成仲裁压力，共检查 3 个响应。
class axi_stage6_multi_master_read_arb_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_multi_master_read_arb_test)
  function new(string name="axi_stage6_multi_master_read_arb_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_multi_master_read_arb_vseq::type_id::create("vseq"); endfunction
  virtual task configure_stage6_ready();
    super.configure_stage6_ready();
    env.s_agents[1].driver.arready_latency.fixed_delay = 3;
  endtask
endclass

// 用例：S0/S1/S2 向 M0 返回读响应，并延迟 M0 RREADY 检查响应仲裁与反压。
class axi_stage6_response_arb_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_response_arb_test)
  function new(string name="axi_stage6_response_arb_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_response_arb_vseq::type_id::create("vseq"); endfunction
  virtual task configure_stage6_ready();
    super.configure_stage6_ready();
    env.m_agents[0].driver.rready_latency.fixed_delay = 3;
  endtask
endclass

// 用例：三个 Master 使用相同原始 ID 读取 S1，检查响应准确返回源 Master，共 3 个响应。
class axi_stage6_cross_master_same_id_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_cross_master_same_id_test)
  function new(string name="axi_stage6_cross_master_same_id_test", uvm_component parent=null); super.new(name,parent); expected_response_count=3; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_cross_master_same_id_vseq::type_id::create("vseq"); endfunction
endclass

// 用例：三个 Master 跨三个 Slave 累计发出 12 笔读请求，检查多端口 outstanding。
class axi_stage6_multiport_outstanding_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_multiport_outstanding_test)
  function new(string name="axi_stage6_multiport_outstanding_test", uvm_component parent=null); super.new(name,parent); expected_response_count=12; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_multiport_outstanding_vseq::type_id::create("vseq"); endfunction
endclass

// 用例：3x3 端口组合随机读写、随机 tag/data，共检查 9 个响应。
class axi_stage6_random_smoke_test extends axi_stage6_base_test;
  `uvm_component_utils(axi_stage6_random_smoke_test)
  function new(string name="axi_stage6_random_smoke_test", uvm_component parent=null); super.new(name,parent); expected_response_count=9; endfunction
  virtual function axi_stage6_base_vseq create_vseq(); return axi_stage6_random_smoke_vseq::type_id::create("vseq"); endfunction
endclass

`endif
