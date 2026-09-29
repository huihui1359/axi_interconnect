`ifndef AXI_STAGE6_BASE_TEST_SV
`define AXI_STAGE6_BASE_TEST_SV

class axi_stage6_base_test extends axi_base_test;

  int unsigned expected_response_count;

  `uvm_component_utils(axi_stage6_base_test)

  function new(string name = "axi_stage6_base_test",
               uvm_component parent = null);
    super.new(name, parent);
    expected_response_count = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    if (uvm_config_db#(axi_env_cfg)::get(this, "", "env_cfg", env_cfg)) begin
      env_cfg.checker_mode = AXI_CHECKER_STAGE6;
      foreach (env_cfg.m_cfg[index]) begin
        env_cfg.m_cfg[index].max_write_outstanding = 4;
        env_cfg.m_cfg[index].max_read_outstanding = 4;
        env_cfg.m_cfg[index].request_prefetch_enabled = 1'b1;
      end
    end
    super.build_phase(phase);
  endfunction

  virtual function axi_stage6_base_vseq create_vseq();
    return null;
  endfunction

  virtual task configure_stage6_ready();
    foreach (env.m_agents[index]) begin
      env.m_agents[index].driver.bready_latency.fixed_delay = 0;
      env.m_agents[index].driver.bready_latency.mode.rand_mode(1);
      if (!env.m_agents[index].driver.bready_latency.randomize() with {
        mode == LAT_MODE_FIXED;
      }) `uvm_fatal("AXI_STAGE6_LATENCY", "Failed to configure BREADY")
      env.m_agents[index].driver.bready_latency.mode.rand_mode(0);
      env.m_agents[index].driver.rready_latency.fixed_delay = 0;
      env.m_agents[index].driver.rready_latency.mode.rand_mode(1);
      if (!env.m_agents[index].driver.rready_latency.randomize() with {
        mode == LAT_MODE_FIXED;
      }) `uvm_fatal("AXI_STAGE6_LATENCY", "Failed to configure RREADY")
      env.m_agents[index].driver.rready_latency.mode.rand_mode(0);
    end
    foreach (env.s_agents[index]) begin
      env.s_agents[index].driver.awready_latency.fixed_delay = 0;
      env.s_agents[index].driver.wready_latency.fixed_delay = 0;
      env.s_agents[index].driver.arready_latency.fixed_delay = 0;
      env.s_agents[index].driver.awready_latency.mode.rand_mode(1);
      env.s_agents[index].driver.wready_latency.mode.rand_mode(1);
      env.s_agents[index].driver.arready_latency.mode.rand_mode(1);
      if (!env.s_agents[index].driver.awready_latency.randomize() with {
        mode == LAT_MODE_FIXED;
      }) `uvm_fatal("AXI_STAGE6_LATENCY", "Failed to configure AWREADY")
      if (!env.s_agents[index].driver.wready_latency.randomize() with {
        mode == LAT_MODE_FIXED;
      }) `uvm_fatal("AXI_STAGE6_LATENCY", "Failed to configure WREADY")
      if (!env.s_agents[index].driver.arready_latency.randomize() with {
        mode == LAT_MODE_FIXED;
      }) `uvm_fatal("AXI_STAGE6_LATENCY", "Failed to configure ARREADY")
      env.s_agents[index].driver.awready_latency.mode.rand_mode(0);
      env.s_agents[index].driver.wready_latency.mode.rand_mode(0);
      env.s_agents[index].driver.arready_latency.mode.rand_mode(0);
    end
  endtask

  virtual task wait_for_stage6_completion();
    int unsigned cycles;
    cycles = 0;
    while (env.scoreboard.response_match_count < expected_response_count) begin
      @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
      cycles++;
      if (cycles >= 5_000)
        `uvm_fatal("AXI_STAGE6_TIMEOUT", $sformatf(
          "Expected %0d responses, observed %0d",
          expected_response_count, env.scoreboard.response_match_count))
    end
  endtask

  virtual task finish_stage6_test();
    int error_count;
    repeat (5) @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
    if ((env.ref_model.error_count != 0) ||
        (env.scoreboard.mismatch_count != 0) ||
        (env.channel_checker.mismatch_count != 0))
      `uvm_error("AXI_STAGE6_CHECK", "Stage 6 checking component reported errors")
    if ((env.ref_model.pending_count() != 0) ||
        (env.scoreboard.pending_count() != 0) ||
        (env.channel_checker.pending_count() != 0))
      `uvm_error("AXI_STAGE6_PENDING", "Stage 6 checking component has pending state")
    foreach (env.m_trackers[index]) begin
      if ((env.m_trackers[index].error_count != 0) ||
          (env.m_trackers[index].pending_count() != 0))
        `uvm_error("AXI_STAGE6_M_TRACKER", $sformatf(
          "M%0d tracker is not clean", index))
      if ((env.m_agents[index].driver.write_outstanding() != 0) ||
          (env.m_agents[index].driver.read_outstanding() != 0) ||
          (env.m_agents[index].driver.pending_context_count() != 0) ||
          (env.m_agents[index].monitor.pending_count() != 0))
        `uvm_error("AXI_STAGE6_M_AGENT", $sformatf(
          "M%0d agent is not drained", index))
    end
    foreach (env.s_trackers[index]) begin
      if ((env.s_trackers[index].error_count != 0) ||
          (env.s_trackers[index].pending_count() != 0))
        `uvm_error("AXI_STAGE6_S_TRACKER", $sformatf(
          "S%0d tracker is not clean", index))
      if ((env.s_agents[index].monitor.pending_count() != 0) ||
          (env.s_agents[index].sequencer.request_fifo.used() != 0))
        `uvm_error("AXI_STAGE6_S_AGENT", $sformatf(
          "S%0d agent is not drained", index))
    end
    error_count = uvm_report_server::get_server().get_severity_count(UVM_ERROR);
    if (error_count != 0)
      `uvm_fatal("AXI_TC_FAIL", $sformatf(
        "%s failed: uvm_errors=%0d", get_type_name(), error_count))
    `uvm_info("AXI_TC_PASS", {get_type_name(), " passed"}, UVM_NONE)
  endtask

  virtual task run_phase(uvm_phase phase);
    axi_stage6_base_vseq vseq;
    phase.raise_objection(this);
    wait_for_reset_release();
    configure_stage6_ready();
    vseq = create_vseq();
    if (vseq == null)
      `uvm_fatal("AXI_STAGE6_VSEQ", "Stage 6 test did not create a virtual sequence")
    vseq.start(env.virtual_sequencer);
    wait_for_stage6_completion();
    finish_stage6_test();
    phase.drop_objection(this);
  endtask

endclass

`endif
