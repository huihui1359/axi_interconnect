package axi_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;

  `include "axi_req_item.sv"
  `include "axi_rsp_item.sv"
  `include "master/axi_m_agent_cfg.sv"
  `include "slave/axi_s_agent_cfg.sv"
  `include "axi_env_cfg.sv"
  `include "master/axi_m_sequencer.sv"
  `include "slave/axi_s_sequencer.sv"

endpackage
