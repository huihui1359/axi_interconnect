`ifndef AXI_ENV_SV
`define AXI_ENV_SV

class axi_env #(
  int unsigned ADDR_WIDTH  = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH  = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH  = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH  = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH   = AXI_LEN_WIDTH,
  int unsigned NUM_MASTERS = AXI_NUM_MASTERS,
  int unsigned NUM_SLAVES  = AXI_NUM_SLAVES
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

  cfg_t cfg;
  m_agent_t m_agents[NUM_MASTERS];
  s_agent_t s_agents[NUM_SLAVES];

  `uvm_component_param_utils(
    axi_env #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
      LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
    )
  )

  extern function new(string name = "axi_env", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);

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
endfunction

`endif
