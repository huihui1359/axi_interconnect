package axi_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;

  `include "common_defines.svh"

  `include "latency_gen.sv"
  `include "axi_req_item.sv"
  `include "axi_rsp_item.sv"
  `include "axi_channel_event.sv"

  // Canonical transaction types for this interconnect build. Generic VIP
  // classes remain parameterized; project-level components use these aliases.
  typedef axi_req_item #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_M_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_m_req_t;
  typedef axi_req_item #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_S_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_s_req_t;
  typedef axi_rsp_item #(
    .DATA_WIDTH(AXI_DATA_WIDTH), .ID_WIDTH(AXI_M_ID_WIDTH),
    .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_m_rsp_t;
  typedef axi_rsp_item #(
    .DATA_WIDTH(AXI_DATA_WIDTH), .ID_WIDTH(AXI_S_ID_WIDTH),
    .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_s_rsp_t;
  typedef axi_channel_event #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_M_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_m_event_t;
  typedef axi_channel_event #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_S_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_s_event_t;

  `include "axi_switch_ref_model.sv"
  `include "axi_system_ref_model.sv"
  `include "axi_outstanding_tracker.sv"

  typedef axi_outstanding_tracker #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_M_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_m_outstanding_tracker_t;
  typedef axi_outstanding_tracker #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_S_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_s_outstanding_tracker_t;

  `include "master/axi_m_agent_cfg.sv"
  `include "slave/axi_s_agent_cfg.sv"

  typedef axi_m_agent_cfg #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_M_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_m_agent_cfg_t;
  typedef axi_s_agent_cfg #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_S_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_s_agent_cfg_t;

  `include "axi_env_cfg.sv"
  `include "master/axi_m_sequencer.sv"
  `include "slave/axi_s_sequencer.sv"

  typedef axi_m_sequencer #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_M_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_m_sequencer_t;
  typedef axi_s_sequencer #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_S_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_s_sequencer_t;

  `include "axi_virtual_sequencer.sv"
  `include "master/axi_m_driver.sv"
  `include "slave/axi_s_driver.sv"
  `include "master/axi_m_monitor.sv"
  `include "slave/axi_s_monitor.sv"
  `include "master/axi_m_agent.sv"
  `include "slave/axi_s_agent.sv"

  typedef axi_m_agent #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_M_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_m_agent_t;
  typedef axi_s_agent #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .ID_WIDTH(AXI_S_ID_WIDTH), .LEN_WIDTH(AXI_LEN_WIDTH)
  ) axi_s_agent_t;

  `include "checker/stage1_e2e_checker.sv"
  `include "checker/stage2_e2e_checker.sv"
  `include "checker/stage3_e2e_checker.sv"
  `include "checker/axi_system_scoreboard.sv"
  `include "checker/axi_channel_forwarding_checker.sv"
  `include "axi_system_coverage.sv"
  `include "axi_env.sv"
  `include "axi_basic_event_comparator.sv"

endpackage
