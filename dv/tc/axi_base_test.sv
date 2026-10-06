`ifndef AXI_BASE_TEST_SV
`define AXI_BASE_TEST_SV

class axi_base_test extends uvm_test;

  axi_env_cfg env_cfg;
  axi_env env;

  `uvm_component_utils(axi_base_test)

  extern function new(string name = "axi_base_test",
                      uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern function void configure_ready_fixed(
    int unsigned aw_delay,
    int unsigned w_delay,
    int unsigned ar_delay,
    int unsigned b_delay,
    int unsigned r_delay
  );
  extern function void configure_ready_random(
    int unsigned minimum,
    int unsigned maximum
  );
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
  env = axi_env::type_id::create("env", this);
endfunction

function void axi_base_test::configure_ready_fixed(
  int unsigned aw_delay,
  int unsigned w_delay,
  int unsigned ar_delay,
  int unsigned b_delay,
  int unsigned r_delay
);
  latency_gen generators[5];
  int unsigned delays[5];

  generators[0] = env.s_agents[0].driver.awready_latency;
  generators[1] = env.s_agents[0].driver.wready_latency;
  generators[2] = env.s_agents[0].driver.arready_latency;
  generators[3] = env.m_agents[0].driver.bready_latency;
  generators[4] = env.m_agents[0].driver.rready_latency;
  delays[0] = aw_delay;
  delays[1] = w_delay;
  delays[2] = ar_delay;
  delays[3] = b_delay;
  delays[4] = r_delay;

  foreach (generators[index]) begin
    generators[index].fixed_delay = delays[index];
    generators[index].mode.rand_mode(1);
    if (!generators[index].randomize() with {
      mode == LAT_MODE_FIXED;
    })
      `uvm_fatal("AXI_READY_LATENCY", $sformatf(
        "Failed to randomize fixed READY latency index %0d", index))
    generators[index].mode.rand_mode(0);
  end
endfunction

function void axi_base_test::configure_ready_random(
  int unsigned minimum,
  int unsigned maximum
);
  latency_gen generators[5];

  generators[0] = env.s_agents[0].driver.awready_latency;
  generators[1] = env.s_agents[0].driver.wready_latency;
  generators[2] = env.s_agents[0].driver.arready_latency;
  generators[3] = env.m_agents[0].driver.bready_latency;
  generators[4] = env.m_agents[0].driver.rready_latency;

  foreach (generators[index]) begin
    generators[index].mode.rand_mode(1);
    generators[index].min_delay.rand_mode(1);
    generators[index].max_delay.rand_mode(1);
    if (!generators[index].randomize() with {
      mode      == LAT_MODE_RANDOM;
      min_delay == local::minimum;
      max_delay == local::maximum;
    })
      `uvm_fatal("AXI_READY_LATENCY", $sformatf(
        "Failed to randomize READY latency index %0d", index))
    generators[index].mode.rand_mode(0);
    generators[index].min_delay.rand_mode(0);
    generators[index].max_delay.rand_mode(0);
  end
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
