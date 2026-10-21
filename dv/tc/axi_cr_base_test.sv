`ifndef AXI_CR_BASE_TEST_SV
`define AXI_CR_BASE_TEST_SV

class axi_cr_base_test extends axi_stage6_base_test;

  localparam int unsigned CR_CHANNEL_COUNT = 5;
  localparam int unsigned CR_STALL_BUCKET_COUNT = 5;

  axi_cr_cfg cr_cfg;
  axi_cr_base_vseq cr_vseq;

  int unsigned stall_run[CR_CHANNEL_COUNT][AXI_NUM_MASTERS];
  bit [CR_STALL_BUCKET_COUNT-1:0]
    stall_bucket_hit[CR_CHANNEL_COUNT];
  int unsigned max_stall_cycles[CR_CHANNEL_COUNT];
  int unsigned traffic_active_cycles;
  int unsigned two_endpoint_active_cycles;
  int unsigned all_endpoint_active_cycles;
  int unsigned max_active_endpoints;
  int unsigned observed_max_no_progress_cycles;

  `uvm_component_utils(axi_cr_base_test)

  function new(string name = "axi_cr_base_test",
               uvm_component parent = null);
    super.new(name, parent);
    cr_cfg = null;
    cr_vseq = null;
    foreach (stall_run[channel, port])
      stall_run[channel][port] = 0;
    foreach (stall_bucket_hit[channel, bucket])
      stall_bucket_hit[channel][bucket] = 1'b0;
    foreach (max_stall_cycles[channel])
      max_stall_cycles[channel] = 0;
    traffic_active_cycles = 0;
    two_endpoint_active_cycles = 0;
    all_endpoint_active_cycles = 0;
    max_active_endpoints = 0;
    observed_max_no_progress_cycles = 0;
  endfunction

  virtual function void configure_cr_cfg();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    cr_cfg = axi_cr_cfg::type_id::create("cr_cfg");
    configure_cr_cfg();
    cr_cfg.apply_plusargs();
    cr_cfg.validate();

    super.build_phase(phase);

    foreach (env_cfg.m_cfg[index]) begin
      env_cfg.m_cfg[index].max_read_outstanding =
        cr_cfg.max_read_outstanding;
      env_cfg.m_cfg[index].max_write_outstanding =
        cr_cfg.max_write_outstanding;
      env_cfg.m_cfg[index].request_prefetch_enabled =
        cr_cfg.request_prefetch_enabled;
    end

    `uvm_info("AXI_CR_CFG", cr_cfg.convert2string(), UVM_LOW)
  endfunction

  protected function void configure_random_latency(
    latency_gen generator,
    int unsigned minimum,
    int unsigned maximum
  );
    generator.mode.rand_mode(1);
    generator.min_delay.rand_mode(1);
    generator.max_delay.rand_mode(1);
    if (!generator.randomize() with {
      mode      == LAT_MODE_RANDOM;
      min_delay == local::minimum;
      max_delay == local::maximum;
    })
      `uvm_fatal("AXI_CR_LATENCY", "Failed to configure random latency")
    generator.mode.rand_mode(0);
    generator.min_delay.rand_mode(0);
    generator.max_delay.rand_mode(0);
  endfunction

  virtual task configure_stage6_ready();
    foreach (env.m_agents[index]) begin
      configure_random_latency(
        env.m_agents[index].driver.bready_latency,
        cr_cfg.ready_delay_min, cr_cfg.ready_delay_max);
      configure_random_latency(
        env.m_agents[index].driver.rready_latency,
        cr_cfg.ready_delay_min, cr_cfg.ready_delay_max);
    end
    foreach (env.s_agents[index]) begin
      configure_random_latency(
        env.s_agents[index].driver.awready_latency,
        cr_cfg.ready_delay_min, cr_cfg.ready_delay_max);
      configure_random_latency(
        env.s_agents[index].driver.wready_latency,
        cr_cfg.ready_delay_min, cr_cfg.ready_delay_max);
      configure_random_latency(
        env.s_agents[index].driver.arready_latency,
        cr_cfg.ready_delay_min, cr_cfg.ready_delay_max);
    end
  endtask

  virtual function axi_stage6_base_vseq create_vseq();
    cr_vseq = axi_cr_base_vseq::type_id::create("vseq");
    cr_vseq.cfg = cr_cfg;
    expected_response_count = cr_cfg.expected_response_count();
    return cr_vseq;
  endfunction

  protected function int unsigned stall_bucket(int unsigned cycles);
    if (cycles == 0) return 0;
    if (cycles == 1) return 1;
    if (cycles <= 5) return 2;
    if (cycles <= 15) return 3;
    return 4;
  endfunction

  protected function void sample_channel(
    int unsigned channel,
    int unsigned port,
    bit valid,
    bit ready
  );
    int unsigned bucket;

    if (valid && !ready) begin
      stall_run[channel][port]++;
      if (stall_run[channel][port] > max_stall_cycles[channel])
        max_stall_cycles[channel] = stall_run[channel][port];
    end
    else if (valid && ready) begin
      bucket = stall_bucket(stall_run[channel][port]);
      stall_bucket_hit[channel][bucket] = 1'b1;
      stall_run[channel][port] = 0;
    end
    else if (!valid) begin
      stall_run[channel][port] = 0;
    end
  endfunction

  virtual task monitor_cr_activity();
    int unsigned active_endpoints;

    forever begin
      @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
      if (env_cfg.m_cfg[0].mon_vif.ARESETn !== 1'b1) begin
        foreach (stall_run[channel, port])
          stall_run[channel][port] = 0;
        continue;
      end

      foreach (env_cfg.s_cfg[port]) begin
        sample_channel(0, port,
          env_cfg.s_cfg[port].mon_vif.awvalid,
          env_cfg.s_cfg[port].mon_vif.awready);
        sample_channel(1, port,
          env_cfg.s_cfg[port].mon_vif.wvalid,
          env_cfg.s_cfg[port].mon_vif.wready);
        sample_channel(3, port,
          env_cfg.s_cfg[port].mon_vif.arvalid,
          env_cfg.s_cfg[port].mon_vif.arready);
      end
      foreach (env_cfg.m_cfg[port]) begin
        sample_channel(2, port,
          env_cfg.m_cfg[port].mon_vif.bvalid,
          env_cfg.m_cfg[port].mon_vif.bready);
        sample_channel(4, port,
          env_cfg.m_cfg[port].mon_vif.rvalid,
          env_cfg.m_cfg[port].mon_vif.rready);
      end

      active_endpoints = 0;
      foreach (env_cfg.m_cfg[port]) begin
        if (env_cfg.m_cfg[port].mon_vif.awvalid ||
            env_cfg.m_cfg[port].mon_vif.wvalid  ||
            env_cfg.m_cfg[port].mon_vif.bvalid  ||
            env_cfg.m_cfg[port].mon_vif.arvalid ||
            env_cfg.m_cfg[port].mon_vif.rvalid)
          active_endpoints++;
      end
      foreach (env_cfg.s_cfg[port]) begin
        if (env_cfg.s_cfg[port].mon_vif.awvalid ||
            env_cfg.s_cfg[port].mon_vif.wvalid  ||
            env_cfg.s_cfg[port].mon_vif.bvalid  ||
            env_cfg.s_cfg[port].mon_vif.arvalid ||
            env_cfg.s_cfg[port].mon_vif.rvalid)
          active_endpoints++;
      end
      if (active_endpoints != 0) begin
        traffic_active_cycles++;
        if (active_endpoints >= 2)
          two_endpoint_active_cycles++;
        if (active_endpoints ==
            (AXI_NUM_MASTERS + AXI_NUM_SLAVES))
          all_endpoint_active_cycles++;
        if (active_endpoints > max_active_endpoints)
          max_active_endpoints = active_endpoints;
      end
    end
  endtask

  virtual function bit all_stall_buckets_hit();
    foreach (stall_bucket_hit[channel, bucket]) begin
      if (!stall_bucket_hit[channel][bucket])
        return 1'b0;
    end
    return 1'b1;
  endfunction

  virtual function string stall_coverage_summary();
    return $sformatf(
      {"AW=%05b W=%05b B=%05b AR=%05b R=%05b ",
       "max=%0d/%0d/%0d/%0d/%0d"},
      stall_bucket_hit[0], stall_bucket_hit[1],
      stall_bucket_hit[2], stall_bucket_hit[3],
      stall_bucket_hit[4], max_stall_cycles[0],
      max_stall_cycles[1], max_stall_cycles[2],
      max_stall_cycles[3], max_stall_cycles[4]
    );
  endfunction

  virtual task wait_for_stage6_completion();
    int unsigned last_match_count;
    int unsigned no_progress_cycles;

    last_match_count = env.scoreboard.response_match_count;
    no_progress_cycles = 0;

    while (env.scoreboard.response_match_count < expected_response_count) begin
      @(posedge env_cfg.m_cfg[0].mon_vif.ACLK);
      if (env.scoreboard.response_match_count != last_match_count) begin
        last_match_count = env.scoreboard.response_match_count;
        no_progress_cycles = 0;
      end
      else begin
        no_progress_cycles++;
        if (no_progress_cycles > observed_max_no_progress_cycles)
          observed_max_no_progress_cycles = no_progress_cycles;
      end

      if (no_progress_cycles >= cr_cfg.no_progress_timeout_cycles)
        `uvm_fatal("AXI_CR_TIMEOUT", $sformatf(
          {"No response progress for %0d cycles; expected=%0d matched=%0d ",
           "scoreboard_pending=%0d ref_pending=%0d"},
          no_progress_cycles, expected_response_count,
          env.scoreboard.response_match_count,
          env.scoreboard.pending_count(), env.ref_model.pending_count()))
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    axi_stage6_base_vseq vseq;

    phase.raise_objection(this);
    wait_for_reset_release();
    configure_stage6_ready();
    vseq = create_vseq();
    if (vseq == null)
      `uvm_fatal("AXI_CR_VSEQ", "CR test did not create a virtual sequence")

    fork
      monitor_cr_activity();
    join_none

    fork
      vseq.start(env.virtual_sequencer);
      wait_for_stage6_completion();
    join

    finish_stage6_test();
    phase.drop_objection(this);
  endtask

endclass

`endif
