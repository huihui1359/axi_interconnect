`ifndef AXI_ENV_SV
`define AXI_ENV_SV

class axi_env #(
  int unsigned ADDR_WIDTH  = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH  = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH  = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH  = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH   = AXI_LEN_WIDTH,
  int unsigned NUM_MASTERS = AXI_ENV_NUM_MASTERS,
  int unsigned NUM_SLAVES  = AXI_ENV_NUM_SLAVES
) extends uvm_env;

  typedef axi_env_cfg #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
    LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
  ) cfg_t;
  typedef axi_m_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) m_cfg_t;
  typedef axi_s_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) s_cfg_t;
  typedef axi_m_agent #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) m_agent_t;
  typedef axi_s_agent #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) s_agent_t;
  typedef stage1_e2e_checker #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) stage1_checker_t;
  typedef stage2_e2e_checker #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) stage2_checker_t;
  typedef stage3_e2e_checker #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) stage3_checker_t;
  typedef axi_outstanding_tracker #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) m_tracker_t;
  typedef axi_outstanding_tracker #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) s_tracker_t;

  cfg_t cfg;
  m_agent_t m_agents[NUM_MASTERS];
  s_agent_t s_agents[NUM_SLAVES];
  stage1_checker_t stage1_checker;
  stage2_checker_t stage2_checker;
  stage3_checker_t stage3_checker;
  m_tracker_t upstream_tracker;
  s_tracker_t downstream_tracker;

  `uvm_component_param_utils(
    axi_env #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
      LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
    )
  )

  extern function new(string name = "axi_env", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);

endclass

function axi_env::new(string name = "axi_env", uvm_component parent = null);
  super.new(name, parent);
endfunction

function void axi_env::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg) || (cfg == null))
    `uvm_fatal("AXI_ENV_CFG", "AXI environment requires a non-null cfg")

  foreach (m_agents[index]) begin
    uvm_config_db#(m_cfg_t)::set(
      this, $sformatf("m_agent_%0d", index), "cfg", cfg.m_cfg[index]
    );
    m_agents[index] = m_agent_t::type_id::create(
      $sformatf("m_agent_%0d", index), this
    );
  end

  foreach (s_agents[index]) begin
    uvm_config_db#(s_cfg_t)::set(
      this, $sformatf("s_agent_%0d", index), "cfg", cfg.s_cfg[index]
    );
    s_agents[index] = s_agent_t::type_id::create(
      $sformatf("s_agent_%0d", index), this
    );
  end

  stage1_checker = stage1_checker_t::type_id::create(
    "stage1_checker", this
  );
  stage2_checker = stage2_checker_t::type_id::create(
    "stage2_checker", this
  );
  stage3_checker = stage3_checker_t::type_id::create(
    "stage3_checker", this
  );
  upstream_tracker = m_tracker_t::type_id::create(
    "upstream_tracker", this
  );
  downstream_tracker = s_tracker_t::type_id::create(
    "downstream_tracker", this
  );

  stage1_checker.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE1);
  stage2_checker.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE2);
  stage3_checker.enabled = (cfg.checker_mode == AXI_CHECKER_STAGE3);
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

  m_agents[0].monitor.channel_ap.connect(upstream_tracker.channel_export);
  s_agents[0].monitor.channel_ap.connect(downstream_tracker.channel_export);
endfunction

`endif
