`ifndef AXI_STAGE2_BASE_TEST_SV
`define AXI_STAGE2_BASE_TEST_SV

class axi_stage2_base_test extends axi_base_test;

  `uvm_component_utils(axi_stage2_base_test)

  extern function new(string name = "axi_stage2_base_test",
                      uvm_component parent = null);
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
  extern task run_stage2_scenario(
    axi_stage2_scenario_sequence scenario,
    int unsigned write_count,
    int unsigned read_count,
    string test_name
  );
  extern task wait_for_stage2_counts(
    int unsigned write_count,
    int unsigned read_count
  );

endclass

function axi_stage2_base_test::new(
  string name = "axi_stage2_base_test",
  uvm_component parent = null
);
  super.new(name, parent);
endfunction

function void axi_stage2_base_test::configure_ready_fixed(
  int unsigned aw_delay,
  int unsigned w_delay,
  int unsigned ar_delay,
  int unsigned b_delay,
  int unsigned r_delay
);
  env.s_agents[0].driver.awready_latency.configure_fixed(aw_delay);
  env.s_agents[0].driver.wready_latency.configure_fixed(w_delay);
  env.s_agents[0].driver.arready_latency.configure_fixed(ar_delay);
  env.m_agents[0].driver.bready_latency.configure_fixed(b_delay);
  env.m_agents[0].driver.rready_latency.configure_fixed(r_delay);
endfunction

function void axi_stage2_base_test::configure_ready_random(
  int unsigned minimum,
  int unsigned maximum
);
  env.s_agents[0].driver.awready_latency.configure_random(minimum, maximum);
  env.s_agents[0].driver.wready_latency.configure_random(minimum, maximum);
  env.s_agents[0].driver.arready_latency.configure_random(minimum, maximum);
  env.m_agents[0].driver.bready_latency.configure_random(minimum, maximum);
  env.m_agents[0].driver.rready_latency.configure_random(minimum, maximum);
endfunction

task axi_stage2_base_test::run_stage2_scenario(
  axi_stage2_scenario_sequence scenario,
  int unsigned write_count,
  int unsigned read_count,
  string test_name
);
  env.stage2_checker.set_expected_counts(write_count, read_count);
  env.stage1_checker.enabled = 1'b0;
  scenario.m_sequencer = env.m_agents[0].sequencer;
  scenario.s_sequencer = env.s_agents[0].sequencer;
  scenario.start(null);
  wait_for_stage2_counts(write_count, read_count);
  finish_test(test_name, 1'b0);
endtask

task axi_stage2_base_test::wait_for_stage2_counts(
  int unsigned write_count,
  int unsigned read_count
);
  int unsigned elapsed_cycles;

  elapsed_cycles = 0;
  while ((env.stage2_checker.write_rsp_match_count < write_count) ||
         (env.stage2_checker.read_rsp_match_count < read_count)) begin
    @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
    elapsed_cycles++;
    if (elapsed_cycles >= 100_000)
      `uvm_fatal("AXI_STAGE2_TIMEOUT", $sformatf(
        "Timed out waiting for writes=%0d reads=%0d", write_count, read_count))
  end
endtask

`endif
