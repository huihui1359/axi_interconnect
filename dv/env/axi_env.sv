`ifndef AXI_ENV_SV
`define AXI_ENV_SV

class axi_env extends uvm_env;

  axi_env_cfg cfg;
  axi_m_agent_t m_agents[AXI_NUM_MASTERS];
  axi_s_agent_t s_agents[AXI_NUM_SLAVES];
  stage1_e2e_checker stage1_checker;
  stage2_e2e_checker stage2_checker;
  stage3_e2e_checker stage3_checker;
  axi_system_ref_model ref_model;
  axi_system_scoreboard scoreboard;
  axi_channel_forwarding_checker channel_checker;
  axi_virtual_sequencer virtual_sequencer;
  axi_system_coverage coverage;
  axi_m_outstanding_tracker_t m_trackers[AXI_NUM_MASTERS];
  axi_s_outstanding_tracker_t s_trackers[AXI_NUM_SLAVES];
  // Compatibility aliases retained for Stage 3 tests.
  axi_m_outstanding_tracker_t upstream_tracker;
  axi_s_outstanding_tracker_t downstream_tracker;

  `uvm_component_utils(axi_env)

  extern function new(string name = "axi_env", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass

function axi_env::new(string name = "axi_env", uvm_component parent = null);
  super.new(name, parent);
endfunction

function void axi_env::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(axi_env_cfg)::get(this, "", "cfg", cfg) ||
      (cfg == null))
    `uvm_fatal("AXI_ENV_CFG", "AXI environment requires a non-null cfg")

  foreach (m_agents[index]) begin
    uvm_config_db#(axi_m_agent_cfg_t)::set(
      this, $sformatf("m_agent_%0d", index), "cfg", cfg.m_cfg[index]
    );
    m_agents[index] = axi_m_agent_t::type_id::create(
      $sformatf("m_agent_%0d", index), this
    );
  end

  foreach (s_agents[index]) begin
    uvm_config_db#(axi_s_agent_cfg_t)::set(
      this, $sformatf("s_agent_%0d", index), "cfg", cfg.s_cfg[index]
    );
    s_agents[index] = axi_s_agent_t::type_id::create(
      $sformatf("s_agent_%0d", index), this
    );
  end

  stage1_checker = stage1_e2e_checker::type_id::create(
    "stage1_checker", this
  );
  stage2_checker = stage2_e2e_checker::type_id::create(
    "stage2_checker", this
  );
  stage3_checker = stage3_e2e_checker::type_id::create(
    "stage3_checker", this
  );
  ref_model = axi_system_ref_model::type_id::create("ref_model", this);
  scoreboard = axi_system_scoreboard::type_id::create("scoreboard", this);
  channel_checker = axi_channel_forwarding_checker::type_id::create(
    "channel_checker", this);
  virtual_sequencer = axi_virtual_sequencer::type_id::create(
    "virtual_sequencer", this);
  coverage = axi_system_coverage::type_id::create("coverage", this);

  foreach (m_trackers[index])
    m_trackers[index] = axi_m_outstanding_tracker_t::type_id::create(
      $sformatf("m_tracker_%0d", index), this);
  foreach (s_trackers[index])
    s_trackers[index] = axi_s_outstanding_tracker_t::type_id::create(
      $sformatf("s_tracker_%0d", index), this);
  upstream_tracker = m_trackers[0];
  downstream_tracker = s_trackers[0];

  stage1_checker.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE1);
  stage2_checker.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE2);
  stage3_checker.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE3);
  ref_model.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE6);
  scoreboard.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE6);
  channel_checker.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE6);
  coverage.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE6);
  foreach (m_trackers[index])
    m_trackers[index].enabled = ((cfg.checker_mode == AXI_CHECKER_STAGE6) ||
                                 ((cfg.checker_mode == AXI_CHECKER_STAGE3) &&
                                  (index == 0)));
  foreach (s_trackers[index])
    s_trackers[index].enabled = ((cfg.checker_mode == AXI_CHECKER_STAGE6) ||
                                 ((cfg.checker_mode == AXI_CHECKER_STAGE3) &&
                                  (index == 0)));
endfunction

function void axi_env::connect_phase(uvm_phase phase);
  super.connect_phase(phase);

  m_agents[0].monitor.channel_ap.connect(stage1_checker.upstream_export);
  s_agents[0].monitor.channel_ap.connect(stage1_checker.downstream_export);

  m_agents[0].monitor.channel_ap.connect(
    stage2_checker.upstream_channel_export
  );
  s_agents[0].monitor.channel_ap.connect(
    stage2_checker.downstream_channel_export
  );
  m_agents[0].monitor.req_ap.connect(stage2_checker.upstream_req_export);
  s_agents[0].monitor.req_ap.connect(stage2_checker.downstream_req_export);
  m_agents[0].monitor.rsp_ap.connect(stage2_checker.upstream_rsp_export);
  s_agents[0].monitor.rsp_ap.connect(stage2_checker.downstream_rsp_export);

  m_agents[0].monitor.channel_ap.connect(
    stage3_checker.upstream_channel_export
  );
  s_agents[0].monitor.channel_ap.connect(
    stage3_checker.downstream_channel_export
  );
  m_agents[0].monitor.req_ap.connect(stage3_checker.upstream_req_export);
  s_agents[0].monitor.req_ap.connect(stage3_checker.downstream_req_export);
  m_agents[0].monitor.rsp_ap.connect(stage3_checker.upstream_rsp_export);
  s_agents[0].monitor.rsp_ap.connect(stage3_checker.downstream_rsp_export);

  foreach (m_agents[index]) begin
    virtual_sequencer.m_seqr[index] = m_agents[index].sequencer;
    m_agents[index].monitor.req_ap.connect(
      ref_model.m_req_fifo[index].analysis_export);
    m_agents[index].monitor.req_ap.connect(
      coverage.m_req_fifo[index].analysis_export);
    m_agents[index].monitor.rsp_ap.connect(
      scoreboard.act_m_rsp_fifo[index].analysis_export);
    m_agents[index].monitor.channel_ap.connect(
      channel_checker.m_event_fifo[index].analysis_export);
    m_agents[index].monitor.channel_ap.connect(
      m_trackers[index].channel_fifo.analysis_export);
    ref_model.m_rsp_ap[index].connect(
      scoreboard.exp_m_rsp_fifo[index].analysis_export);
  end

  foreach (s_agents[index]) begin
    virtual_sequencer.s_seqr[index] = s_agents[index].sequencer;
    s_agents[index].monitor.req_ap.connect(
      scoreboard.act_s_req_fifo[index].analysis_export);
    s_agents[index].monitor.rsp_ap.connect(
      ref_model.s_rsp_fifo[index].analysis_export);
    s_agents[index].monitor.channel_ap.connect(
      channel_checker.s_event_fifo[index].analysis_export);
    s_agents[index].monitor.channel_ap.connect(
      s_trackers[index].channel_fifo.analysis_export);
    ref_model.s_req_ap[index].connect(
      scoreboard.exp_s_req_fifo[index].analysis_export);
  end
endfunction

`endif
