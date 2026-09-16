`ifndef AXI_BASE_TEST_SV
`define AXI_BASE_TEST_SV

class axi_base_test extends uvm_test;

  axi_env_cfg env_cfg;
  axi_env env;

  `uvm_component_utils(axi_base_test)

  extern function new(string name = "axi_base_test",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern task wait_for_reset_release();
  extern task finish_test(string test_name, bit check_stage1 = 1'b1);

endclass

function axi_base_test::new(
  string name = "axi_base_test",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

function void axi_base_test::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(axi_env_cfg)::get(this, "", "env_cfg", env_cfg))
    `uvm_fatal("AXI_TEST_CFG", "env_cfg was not provided")

  uvm_config_db#(axi_env_cfg)::set(this, "env", "cfg", env_cfg);
  env = axi_env #()::type_id::create("env", this);
endfunction

task axi_base_test::wait_for_reset_release();
  while (env_cfg.m_cfg[0].mon_vif.ARESETn !== 1'b1)
    @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
  @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
endtask

task axi_base_test::finish_test(string test_name, bit check_stage1 = 1'b1);
  int error_count;
  repeat (2) @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);

  if (check_stage1) begin
    if (env.stage1_checker.mismatch_count != 0)
      `uvm_error("AXI_TEST_CHECK", "End-to-end checker reported a mismatch")
    if (env.stage1_checker.pending_count() != 0)
      `uvm_error("AXI_TEST_CHECK", "End-to-end checker has pending events")
  end
  if (env.stage2_checker.mismatch_count != 0)
    `uvm_error("AXI_TEST_CHECK", "Stage 2 checker reported a mismatch")
  if (env.stage2_checker.pending_count() != 0)
    `uvm_error("AXI_TEST_CHECK", "Stage 2 checker has pending activity")
  if (env.s_agents[0].sequencer.request_fifo.used() != 0)
    `uvm_error("AXI_TEST_CHECK", "Slave request FIFO is not empty")

  error_count = uvm_report_server::get_server().get_severity_count(UVM_ERROR);
  if (error_count != 0)
    `uvm_fatal("AXI_TC_FAIL", $sformatf(
      "%s failed: uvm_errors=%0d", test_name, error_count))

  `uvm_info("AXI_TC_PASS", {test_name, " passed"}, UVM_NONE)
endtask

`endif
