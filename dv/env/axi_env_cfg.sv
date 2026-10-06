`ifndef AXI_ENV_CFG_SV
`define AXI_ENV_CFG_SV

class axi_env_cfg extends uvm_object;

  axi_m_agent_cfg_t m_cfg[AXI_NUM_MASTERS];
  axi_s_agent_cfg_t s_cfg[AXI_NUM_SLAVES];
  axi_checker_mode_e checker_mode;

  `uvm_object_utils(axi_env_cfg)

  function new(string name = "axi_env_cfg");
    super.new(name);
    checker_mode = AXI_CHECKER_STAGE1;

    foreach (m_cfg[i]) begin
      m_cfg[i] = axi_m_agent_cfg_t::type_id::create(
        $sformatf("m_cfg_%0d", i)
      );
      m_cfg[i].port_index = i;
    end

    foreach (s_cfg[i]) begin
      s_cfg[i] = axi_s_agent_cfg_t::type_id::create(
        $sformatf("s_cfg_%0d", i)
      );
      s_cfg[i].port_index = i;
    end
  endfunction

endclass

`endif
