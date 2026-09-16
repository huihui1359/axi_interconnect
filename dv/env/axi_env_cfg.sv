`ifndef AXI_ENV_CFG_SV
`define AXI_ENV_CFG_SV

class axi_env_cfg #(
  int unsigned ADDR_WIDTH  = AXI_ADDR_WIDTH,
  int unsigned DATA_WIDTH  = AXI_DATA_WIDTH,
  int unsigned M_ID_WIDTH  = AXI_M_ID_WIDTH,
  int unsigned S_ID_WIDTH  = AXI_S_ID_WIDTH,
  int unsigned LEN_WIDTH   = AXI_LEN_WIDTH,
  int unsigned NUM_MASTERS = AXI_ENV_NUM_MASTERS,
  int unsigned NUM_SLAVES  = AXI_ENV_NUM_SLAVES
) extends uvm_object;

  typedef axi_m_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, LEN_WIDTH
  ) m_agent_cfg_t;

  typedef axi_s_agent_cfg #(
    ADDR_WIDTH, DATA_WIDTH, S_ID_WIDTH, LEN_WIDTH
  ) s_agent_cfg_t;

  m_agent_cfg_t m_cfg[NUM_MASTERS];
  s_agent_cfg_t s_cfg[NUM_SLAVES];

  `uvm_object_param_utils(
    axi_env_cfg #(
      ADDR_WIDTH, DATA_WIDTH, M_ID_WIDTH, S_ID_WIDTH,
      LEN_WIDTH, NUM_MASTERS, NUM_SLAVES
    )
  )

  function new(string name = "axi_env_cfg");
    super.new(name);

    foreach (m_cfg[i]) begin
      m_cfg[i] = m_agent_cfg_t::type_id::create(
        $sformatf("m_cfg_%0d", i)
      );
      m_cfg[i].port_index = i;
    end

    foreach (s_cfg[i]) begin
      s_cfg[i] = s_agent_cfg_t::type_id::create(
        $sformatf("s_cfg_%0d", i)
      );
      s_cfg[i].port_index = i;
    end
  endfunction

endclass

`endif
