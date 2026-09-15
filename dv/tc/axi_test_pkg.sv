package axi_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi_types_pkg::*;
  import axi_env_pkg::*;
  import axi_seq_pkg::*;

  `uvm_analysis_imp_decl(_upstream)
  `uvm_analysis_imp_decl(_downstream)
  `include "support/stage1_e2e_checker.sv"

  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).m_drv_mp m_drv_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp m_mon_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).s_drv_mp s_drv_vif_t;
  typedef virtual axi_if #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ).mon_mp s_mon_vif_t;

  typedef axi_env_cfg #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH,
    AXI_M_ID_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH, 1, 1
  ) env_cfg_t;
  typedef axi_env #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH,
    AXI_M_ID_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH, 1, 1
  ) env_t;
  typedef axi_m_single_write_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_write_seq_t;
  typedef axi_m_single_read_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_M_ID_WIDTH, AXI_LEN_WIDTH
  ) m_read_seq_t;
  typedef axi_s_single_reactive_seq #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) s_reactive_seq_t;
  typedef stage1_e2e_checker #(
    AXI_ADDR_WIDTH, AXI_DATA_WIDTH,
    AXI_M_ID_WIDTH, AXI_S_ID_WIDTH, AXI_LEN_WIDTH
  ) e2e_checker_t;

  `include "support/axi_test_env.sv"
  `include "axi_base_test.sv"
  `include "axi_write_test.sv"
  `include "axi_read_test.sv"

endpackage
